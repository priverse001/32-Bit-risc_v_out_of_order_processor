`timescale 1ns / 1ps
`include "include/params.vh"
`include "include/rv32i_defines.vh"

module top (
    // Core Clock Domain
    input  wire core_clk,
    input  wire core_rst_n,
    
    // AXI Clock Domain
    input  wire axi_clk,
    input  wire axi_rst_n,
    
    // Debug ports
    input  wire [`REG_ADDR_WIDTH-1:0] debug_reg_idx,
    output wire [`DATA_WIDTH-1:0]     debug_reg_val,
    
    // Hardware Performance Counters (For ILA or external reading)
    output reg  [63:0]               perf_cycles,
    output reg  [63:0]               perf_instret,
    output reg  [63:0]               perf_branches,
    output reg  [63:0]               perf_mispredicts,
    
    // --- AXI4-Lite Master Interface: Instruction Fetch ---
    output wire [`ADDR_WIDTH-1:0]     m_axi_i_araddr,
    output wire                      m_axi_i_arvalid,
    input  wire                      m_axi_i_arready,
    input  wire [`DATA_WIDTH-1:0]     m_axi_i_rdata,
    input  wire [1:0]                m_axi_i_rresp,
    input  wire                      m_axi_i_rvalid,
    output wire                      m_axi_i_rready,
    
    output wire [`ADDR_WIDTH-1:0]     m_axi_i_awaddr,
    output wire                      m_axi_i_awvalid,
    input  wire                      m_axi_i_awready,
    output wire [`DATA_WIDTH-1:0]     m_axi_i_wdata,
    output wire [3:0]                m_axi_i_wstrb,
    output wire                      m_axi_i_wvalid,
    input  wire                      m_axi_i_wready,
    input  wire [1:0]                m_axi_i_bresp,
    input  wire                      m_axi_i_bvalid,
    output wire                      m_axi_i_bready,

    // --- AXI4-Lite Master Interface: Data (LSQ) ---
    output wire [`ADDR_WIDTH-1:0]     m_axi_d_awaddr,
    output wire                      m_axi_d_awvalid,
    input  wire                      m_axi_d_awready,
    output wire [`DATA_WIDTH-1:0]     m_axi_d_wdata,
    output wire [3:0]                m_axi_d_wstrb,
    output wire                      m_axi_d_wvalid,
    input  wire                      m_axi_d_wready,
    input  wire [1:0]                m_axi_d_bresp,
    input  wire                      m_axi_d_bvalid,
    output wire                      m_axi_d_bready,
    output wire [`ADDR_WIDTH-1:0]     m_axi_d_araddr,
    output wire                      m_axi_d_arvalid,
    input  wire                      m_axi_d_arready,
    input  wire [`DATA_WIDTH-1:0]     m_axi_d_rdata,
    input  wire [1:0]                m_axi_d_rresp,
    input  wire                      m_axi_d_rvalid,
    output wire                      m_axi_d_rready
);

    wire [31:0] instr;
    wire [`ADDR_WIDTH-1:0] instr_pc;
    wire instr_valid;
    wire ready_for_instr;
    
    wire commit_flush;
    wire [`ADDR_WIDTH-1:0] commit_flush_target;
    
    // Speculative flush from Decode/BPU
    wire spec_flush;
    wire [`ADDR_WIDTH-1:0] spec_flush_target;
    
    wire actual_flush = commit_flush | spec_flush;
    wire [`ADDR_WIDTH-1:0] actual_flush_target = commit_flush ? commit_flush_target : spec_flush_target;
    
    // Memory Interface Wires (Fetch)
    wire imem_req, imem_ack;
    wire [`ADDR_WIDTH-1:0] imem_addr;
    wire [`DATA_WIDTH-1:0] imem_rdata;
    
    fetch u_fetch (
        .clk(core_clk),
        .rst_n(core_rst_n),
        .instr_out(instr),
        .pc_out(instr_pc),
        .instr_valid(instr_valid),
        .ready_for_instr(ready_for_instr),
        .flush(actual_flush),
        .flush_target(actual_flush_target),
        .imem_req(imem_req),
        .imem_addr(imem_addr),
        .imem_rdata(imem_rdata),
        .imem_ack(imem_ack)
    );
    
    // AXI CDC for Fetch (Instruction Memory)
    axi4_lite_master_cdc u_axi_i (
        .core_clk(core_clk), .core_rst_n(core_rst_n),
        .core_mem_req(imem_req), .core_mem_we(1'b0), .core_mem_addr(imem_addr), 
        .core_mem_wdata(32'b0), .core_mem_rdata(imem_rdata), .core_mem_ack(imem_ack),
        .axi_clk(axi_clk), .axi_rst_n(axi_rst_n),
        .m_axi_awaddr(m_axi_i_awaddr), .m_axi_awvalid(m_axi_i_awvalid), .m_axi_awready(m_axi_i_awready),
        .m_axi_wdata(m_axi_i_wdata), .m_axi_wstrb(m_axi_i_wstrb), .m_axi_wvalid(m_axi_i_wvalid), .m_axi_wready(m_axi_i_wready),
        .m_axi_bresp(m_axi_i_bresp), .m_axi_bvalid(m_axi_i_bvalid), .m_axi_bready(m_axi_i_bready),
        .m_axi_araddr(m_axi_i_araddr), .m_axi_arvalid(m_axi_i_arvalid), .m_axi_arready(m_axi_i_arready),
        .m_axi_rdata(m_axi_i_rdata), .m_axi_rresp(m_axi_i_rresp), .m_axi_rvalid(m_axi_i_rvalid), .m_axi_rready(m_axi_i_rready)
    );
    
    wire rob_req;
    wire [`REG_ADDR_WIDTH-1:0] rob_rd;
    wire [2:0] rob_inst_type;
    wire [`ADDR_WIDTH-1:0] rob_pc;
    wire rob_pred_taken;
    wire rob_full;
    wire [`ROB_TAG_WIDTH-1:0] rob_alloc_idx;
    
    wire rat_rename_en;
    wire [`REG_ADDR_WIDTH-1:0] rat_rename_rd;
    wire [`ROB_TAG_WIDTH-1:0] rat_rename_rob_tag;
    
    wire [`REG_ADDR_WIDTH-1:0] rf_rs1_addr;
    wire [`REG_ADDR_WIDTH-1:0] rf_rs2_addr;
    wire [`DATA_WIDTH-1:0] rf_rs1_data;
    wire [`DATA_WIDTH-1:0] rf_rs2_data;
    
    wire [`REG_ADDR_WIDTH-1:0] rat_rs1_addr;
    wire [`REG_ADDR_WIDTH-1:0] rat_rs2_addr;
    wire rat_rs1_rob_valid;
    wire [`ROB_TAG_WIDTH-1:0] rat_rs1_rob_tag;
    wire rat_rs2_rob_valid;
    wire [`ROB_TAG_WIDTH-1:0] rat_rs2_rob_tag;
    
    wire rs_alu_req; wire [3:0] rs_alu_op; wire rs_alu_vj_valid; wire [`DATA_WIDTH-1:0] rs_alu_vj;
    wire [`ROB_TAG_WIDTH-1:0] rs_alu_qj; wire rs_alu_vk_valid; wire [`DATA_WIDTH-1:0] rs_alu_vk;
    wire [`ROB_TAG_WIDTH-1:0] rs_alu_qk; wire [`ROB_TAG_WIDTH-1:0] rs_alu_dest;
    wire [`DATA_WIDTH-1:0] rs_alu_imm; wire [`ADDR_WIDTH-1:0] rs_alu_pc; wire rs_alu_full;
    
    wire rs_br_req; wire [3:0] rs_br_op; wire rs_br_vj_valid; wire [`DATA_WIDTH-1:0] rs_br_vj;
    wire [`ROB_TAG_WIDTH-1:0] rs_br_qj; wire rs_br_vk_valid; wire [`DATA_WIDTH-1:0] rs_br_vk;
    wire [`ROB_TAG_WIDTH-1:0] rs_br_qk; wire [`ROB_TAG_WIDTH-1:0] rs_br_dest;
    wire [`DATA_WIDTH-1:0] rs_br_imm; wire [`ADDR_WIDTH-1:0] rs_br_pc; wire rs_br_pred_taken; wire rs_br_full;
    
    wire rs_lsq_req; wire [2:0] rs_lsq_op; wire [2:0] rs_lsq_funct3; wire rs_lsq_vj_valid;
    wire [`DATA_WIDTH-1:0] rs_lsq_vj; wire [`ROB_TAG_WIDTH-1:0] rs_lsq_qj; wire rs_lsq_vk_valid;
    wire [`DATA_WIDTH-1:0] rs_lsq_vk; wire [`ROB_TAG_WIDTH-1:0] rs_lsq_qk; wire [`ROB_TAG_WIDTH-1:0] rs_lsq_dest;
    wire [`DATA_WIDTH-1:0] rs_lsq_imm; wire rs_lsq_full;
    
    // MDU Wires
    wire rs_mdu_req; wire [2:0] rs_mdu_op; wire rs_mdu_vj_valid;
    wire [`DATA_WIDTH-1:0] rs_mdu_vj; wire [`ROB_TAG_WIDTH-1:0] rs_mdu_qj; wire rs_mdu_vk_valid;
    wire [`DATA_WIDTH-1:0] rs_mdu_vk; wire [`ROB_TAG_WIDTH-1:0] rs_mdu_qk; wire [`ROB_TAG_WIDTH-1:0] rs_mdu_dest;
    wire rs_mdu_full;
    
    wire cdb_valid;
    wire [`ROB_TAG_WIDTH-1:0] cdb_tag;
    wire [`DATA_WIDTH-1:0] cdb_data;
    wire cdb_br_taken;
    wire [`ADDR_WIDTH-1:0] cdb_br_target;
    
    // Commit wires (must be declared before BPU instantiation to avoid implicit 1-bit wires)
    wire commit_valid;
    wire [`ROB_TAG_WIDTH-1:0] commit_tag;
    wire [`REG_ADDR_WIDTH-1:0] commit_rd;
    wire [`DATA_WIDTH-1:0] commit_data;
    wire [`ADDR_WIDTH-1:0] commit_pc;
    wire commit_is_branch;
    wire commit_taken;
    wire commit_pred_taken;

    // Branch Predictor Wires
    wire [`ADDR_WIDTH-1:0] bpu_fetch_pc;
    wire                  bpu_fetch_valid;
    wire                  bpu_predict_taken;
    
    // BPU Instance
    perceptron_bpu #(
        .HISTORY_LEN(4),
        .WEIGHT_WIDTH(8),
        .TABLE_ENTRIES(32)
    ) u_bpu (
        .clk(core_clk),
        .rst_n(core_rst_n),
        .fetch_pc(bpu_fetch_pc),
        .fetch_valid(bpu_fetch_valid),
        .predict_taken(bpu_predict_taken),
        .commit_valid(commit_valid),
        .commit_is_branch(commit_is_branch),
        .commit_pc(commit_pc),
        .commit_taken(commit_taken),
        .commit_pred_taken(commit_pred_taken)
    );
    
    decode_dispatch u_decode_dispatch (
        .clk(core_clk),
        .rst_n(core_rst_n),
        .instr_in(instr),
        .pc_in(instr_pc),
        .instr_valid(instr_valid),
        .ready_for_instr(ready_for_instr),
        
        .rob_req(rob_req),
        .rob_rd(rob_rd),
        .rob_inst_type(rob_inst_type),
        .rob_pc(rob_pc),
        .rob_pred_taken(rob_pred_taken),
        .rob_full(rob_full),
        .rob_alloc_idx(rob_alloc_idx),
        
        .rat_rs1_addr(rat_rs1_addr),
        .rat_rs2_addr(rat_rs2_addr),
        .rat_rs1_rob_valid(rat_rs1_rob_valid),
        .rat_rs1_rob_tag(rat_rs1_rob_tag),
        .rat_rs2_rob_valid(rat_rs2_rob_valid),
        .rat_rs2_rob_tag(rat_rs2_rob_tag),
        .rat_rename_en(rat_rename_en),
        .rat_rename_rd(rat_rename_rd),
        .rat_rename_rob_tag(rat_rename_rob_tag),
        
        .rf_rs1_addr(rf_rs1_addr),
        .rf_rs2_addr(rf_rs2_addr),
        .rf_rs1_data(rf_rs1_data),
        .rf_rs2_data(rf_rs2_data),
        
        .rs_alu_req(rs_alu_req),
        .rs_alu_op(rs_alu_op),
        .rs_alu_vj_valid(rs_alu_vj_valid),
        .rs_alu_vj(rs_alu_vj),
        .rs_alu_qj(rs_alu_qj),
        .rs_alu_vk_valid(rs_alu_vk_valid),
        .rs_alu_vk(rs_alu_vk),
        .rs_alu_qk(rs_alu_qk),
        .rs_alu_dest(rs_alu_dest),
        .rs_alu_imm(rs_alu_imm),
        .rs_alu_pc(rs_alu_pc),
        .rs_alu_full(rs_alu_full),
        
        .rs_br_req(rs_br_req),
        .rs_br_op(rs_br_op),
        .rs_br_vj_valid(rs_br_vj_valid),
        .rs_br_vj(rs_br_vj),
        .rs_br_qj(rs_br_qj),
        .rs_br_vk_valid(rs_br_vk_valid),
        .rs_br_vk(rs_br_vk),
        .rs_br_qk(rs_br_qk),
        .rs_br_dest(rs_br_dest),
        .rs_br_imm(rs_br_imm),
        .rs_br_pc(rs_br_pc),
        .rs_br_pred_taken(rs_br_pred_taken),
        .rs_br_full(rs_br_full),
        
        .rs_lsq_req(rs_lsq_req),
        .rs_lsq_op(rs_lsq_op),
        .rs_lsq_funct3(rs_lsq_funct3),
        .rs_lsq_vj_valid(rs_lsq_vj_valid),
        .rs_lsq_vj(rs_lsq_vj),
        .rs_lsq_qj(rs_lsq_qj),
        .rs_lsq_vk_valid(rs_lsq_vk_valid),
        .rs_lsq_vk(rs_lsq_vk),
        .rs_lsq_qk(rs_lsq_qk),
        .rs_lsq_dest(rs_lsq_dest),
        .rs_lsq_imm(rs_lsq_imm),
        .rs_lsq_full(rs_lsq_full),
        
        .rs_mdu_req(rs_mdu_req),
        .rs_mdu_op(rs_mdu_op),
        .rs_mdu_vj_valid(rs_mdu_vj_valid),
        .rs_mdu_vj(rs_mdu_vj),
        .rs_mdu_qj(rs_mdu_qj),
        .rs_mdu_vk_valid(rs_mdu_vk_valid),
        .rs_mdu_vk(rs_mdu_vk),
        .rs_mdu_qk(rs_mdu_qk),
        .rs_mdu_dest(rs_mdu_dest),
        .rs_mdu_full(rs_mdu_full),
        
        .cdb_valid(cdb_valid),
        .cdb_tag(cdb_tag),
        .cdb_data(cdb_data),
        
        .bpu_fetch_pc(bpu_fetch_pc),
        .bpu_fetch_valid(bpu_fetch_valid),
        .bpu_predict_taken(bpu_predict_taken),
        
        .spec_flush(spec_flush),
        .spec_flush_target(spec_flush_target)
    );
    
    
    rob u_rob (
        .clk(core_clk),
        .rst_n(core_rst_n),
        .issue_req(rob_req),
        .issue_rd(rob_rd),
        .issue_inst_type(rob_inst_type),
        .issue_pc(rob_pc),
        .issue_pred_taken(rob_pred_taken),
        .rob_full(rob_full),
        .rob_alloc_idx(rob_alloc_idx),
        
        .cdb_valid(cdb_valid),
        .cdb_tag(cdb_tag),
        .cdb_data(cdb_data),
        .cdb_branch_taken(cdb_br_taken),
        .cdb_branch_target(cdb_br_target),
        
        .commit_valid(commit_valid),
        .commit_tag(commit_tag),
        .commit_rd(commit_rd),
        .commit_data(commit_data),
        .commit_pc(commit_pc),
        .commit_is_branch(commit_is_branch),
        .commit_taken(commit_taken),
        .commit_pred_taken(commit_pred_taken),
        .commit_flush(commit_flush),
        .commit_flush_target(commit_flush_target)
    );
    
    rat u_rat (
        .clk(core_clk),
        .rst_n(core_rst_n),
        .rs1_addr(rat_rs1_addr),
        .rs2_addr(rat_rs2_addr),
        .rs1_rob_valid(rat_rs1_rob_valid),
        .rs1_rob_tag(rat_rs1_rob_tag),
        .rs2_rob_valid(rat_rs2_rob_valid),
        .rs2_rob_tag(rat_rs2_rob_tag),
        
        .rename_en(rat_rename_en),
        .rename_rd(rat_rename_rd),
        .rename_rob_tag(rat_rename_rob_tag),
        
        .commit_valid(commit_valid),
        .commit_rd(commit_rd),
        .commit_rob_tag(commit_tag),
        .flush(actual_flush) // Update RAT flush to use actual_flush
    );
    
    register_file u_rf (
        .clk(core_clk),
        .rst_n(core_rst_n),
        .rs1_addr(rf_rs1_addr),
        .rs2_addr(rf_rs2_addr),
        .rs1_data(rf_rs1_data),
        .rs2_data(rf_rs2_data),
        .debug_addr(debug_reg_idx),
        .debug_data(debug_reg_val),
        .we(commit_valid),
        .rd_addr(commit_rd),
        .rd_data(commit_data)
    );
    
    wire alu_fu_ready, alu_fu_valid;
    wire [3:0] alu_fu_op;
    wire [`DATA_WIDTH-1:0] alu_fu_vj, alu_fu_vk, alu_fu_imm;
    wire [`ADDR_WIDTH-1:0] alu_fu_pc;
    wire [`ROB_TAG_WIDTH-1:0] alu_fu_dest;
    
    rs #(
        .ENTRIES(`RS_ALU_ENTRIES),
        .IDX_WIDTH(`RS_ALU_IDX_WIDTH)
    ) u_rs_alu (
        .clk(core_clk), .rst_n(core_rst_n),
        .issue_req(rs_alu_req), .issue_op(rs_alu_op),
        .issue_vj_valid(rs_alu_vj_valid), .issue_vj(rs_alu_vj), .issue_qj(rs_alu_qj),
        .issue_vk_valid(rs_alu_vk_valid), .issue_vk(rs_alu_vk), .issue_qk(rs_alu_qk),
        .issue_dest(rs_alu_dest), .issue_pc(rs_alu_pc), .issue_imm(rs_alu_imm),
        .rs_full(rs_alu_full),
        .cdb_valid(cdb_valid), .cdb_tag(cdb_tag), .cdb_data(cdb_data),
        .fu_ready(alu_fu_ready), .fu_valid(alu_fu_valid),
        .fu_op(alu_fu_op), .fu_vj(alu_fu_vj), .fu_vk(alu_fu_vk),
        .fu_imm(alu_fu_imm), .fu_pc(alu_fu_pc), .fu_dest(alu_fu_dest),
        .flush(actual_flush) // Update RS flush to use actual_flush
    );
    
    wire alu_req_out, alu_ack_in;
    wire [`ROB_TAG_WIDTH-1:0] alu_tag_out;
    wire [`DATA_WIDTH-1:0] alu_data_out;
    
    alu u_alu (
        .clk(core_clk), .rst_n(core_rst_n),
        .valid_in(alu_fu_valid), .op(alu_fu_op),
        .vj(alu_fu_vj), .vk(alu_fu_vk), .imm(alu_fu_imm),
        .pc(alu_fu_pc), .dest_in(alu_fu_dest),
        .ready_out(alu_fu_ready),
        .req_out(alu_req_out), .tag_out(alu_tag_out),
        .data_out(alu_data_out), .ack_in(alu_ack_in),
        .flush(actual_flush)
    );
    
    wire br_fu_ready, br_fu_valid;
    wire [3:0] br_fu_op;
    wire [`DATA_WIDTH-1:0] br_fu_vj, br_fu_vk, br_fu_imm;
    wire [`ADDR_WIDTH-1:0] br_fu_pc;
    wire [`ROB_TAG_WIDTH-1:0] br_fu_dest;
    
    rs #(
        .ENTRIES(`RS_BR_ENTRIES),
        .IDX_WIDTH(`RS_BR_IDX_WIDTH)
    ) u_rs_br (
        .clk(core_clk), .rst_n(core_rst_n),
        .issue_req(rs_br_req), .issue_op(rs_br_op),
        .issue_vj_valid(rs_br_vj_valid), .issue_vj(rs_br_vj), .issue_qj(rs_br_qj),
        .issue_vk_valid(rs_br_vk_valid), .issue_vk(rs_br_vk), .issue_qk(rs_br_qk),
        .issue_dest(rs_br_dest), .issue_pc(rs_br_pc), .issue_imm(rs_br_imm),
        .rs_full(rs_br_full),
        .cdb_valid(cdb_valid), .cdb_tag(cdb_tag), .cdb_data(cdb_data),
        .fu_ready(br_fu_ready), .fu_valid(br_fu_valid),
        .fu_op(br_fu_op), .fu_vj(br_fu_vj), .fu_vk(br_fu_vk),
        .fu_imm(br_fu_imm), .fu_pc(br_fu_pc), .fu_dest(br_fu_dest),
        .flush(actual_flush) // Update RS flush
    );
    
    wire br_req_out, br_taken_out, br_ack_in;
    wire [`ROB_TAG_WIDTH-1:0] br_tag_out;
    wire [`DATA_WIDTH-1:0] br_data_out;
    wire [`ADDR_WIDTH-1:0] br_target_out;
    
    branch_unit u_br (
        .clk(core_clk), .rst_n(core_rst_n),
        .valid_in(br_fu_valid), .op(br_fu_op),
        .vj(br_fu_vj), .vk(br_fu_vk), .imm(br_fu_imm),
        .pc(br_fu_pc), .dest_in(br_fu_dest),
        .ready_out(br_fu_ready),
        .req_out(br_req_out), .tag_out(br_tag_out), .data_out(br_data_out),
        .br_taken_out(br_taken_out), .br_target_out(br_target_out),
        .ack_in(br_ack_in),
        .flush(actual_flush)
    );
    
    wire [3:0] rs_lsq_op_packed = { (rs_lsq_op == `INST_ST) ? 1'b1 : 1'b0, rs_lsq_funct3 };
    wire lsq_fu_ready, lsq_fu_valid;
    wire [3:0] lsq_fu_op_packed;
    wire [`DATA_WIDTH-1:0] lsq_fu_vj, lsq_fu_vk, lsq_fu_imm;
    wire [`ADDR_WIDTH-1:0] lsq_fu_pc;
    wire [`ROB_TAG_WIDTH-1:0] lsq_fu_dest;
    
    rs #(
        .ENTRIES(`RS_LSQ_ENTRIES),
        .IDX_WIDTH(`RS_LSQ_IDX_WIDTH),
        .ORDERED(1)
    ) u_rs_lsq (
        .clk(core_clk), .rst_n(core_rst_n),
        .issue_req(rs_lsq_req), .issue_op(rs_lsq_op_packed),
        .issue_vj_valid(rs_lsq_vj_valid), .issue_vj(rs_lsq_vj), .issue_qj(rs_lsq_qj),
        .issue_vk_valid(rs_lsq_vk_valid), .issue_vk(rs_lsq_vk), .issue_qk(rs_lsq_qk),
        .issue_dest(rs_lsq_dest), .issue_pc(32'b0), .issue_imm(rs_lsq_imm),
        .rs_full(rs_lsq_full),
        .cdb_valid(cdb_valid), .cdb_tag(cdb_tag), .cdb_data(cdb_data),
        .fu_ready(lsq_fu_ready), .fu_valid(lsq_fu_valid),
        .fu_op(lsq_fu_op_packed), .fu_vj(lsq_fu_vj), .fu_vk(lsq_fu_vk),
        .fu_imm(lsq_fu_imm), .fu_pc(lsq_fu_pc), .fu_dest(lsq_fu_dest),
        .flush(actual_flush) // Update RS flush
    );
    
    wire dmem_req, dmem_we, lsq_req_out, lsq_ack_in;
    wire [`ADDR_WIDTH-1:0] dmem_addr;
    wire [`DATA_WIDTH-1:0] dmem_wdata;
    wire [`DATA_WIDTH-1:0] dmem_rdata;
    wire dmem_ack;
    wire [`ROB_TAG_WIDTH-1:0] lsq_tag_out;
    wire [`DATA_WIDTH-1:0] lsq_data_out;
    
    lsq u_lsq (
        .clk(core_clk), .rst_n(core_rst_n),
        .valid_in(lsq_fu_valid), 
        .op(lsq_fu_op_packed[3] ? `INST_ST : `INST_LD),
        .funct3(lsq_fu_op_packed[2:0]),
        .vj(lsq_fu_vj), .vk(lsq_fu_vk), .imm(lsq_fu_imm),
        .dest_in(lsq_fu_dest), .ready_out(lsq_fu_ready),
        .mem_req(dmem_req), .mem_we(dmem_we), .mem_addr(dmem_addr),
        .mem_wdata(dmem_wdata), .mem_rdata(dmem_rdata), .mem_ack(dmem_ack),
        .req_out(lsq_req_out), .tag_out(lsq_tag_out), .data_out(lsq_data_out),
        .ack_in(lsq_ack_in),
        .commit_valid(commit_valid), .commit_tag(commit_tag),
        .flush(actual_flush)
    );
    
    // -------------------------------------------------------------------------
    // MULTIPLY/DIVIDE UNIT (MDU)
    // -------------------------------------------------------------------------
    wire mdu_fu_ready, mdu_fu_valid;
    wire [3:0] mdu_fu_op_out;
    wire [2:0] mdu_fu_op = mdu_fu_op_out[2:0];
    wire [`DATA_WIDTH-1:0] mdu_fu_vj, mdu_fu_vk;
    wire [`ROB_TAG_WIDTH-1:0] mdu_fu_dest;
    
    rs #(
        .ENTRIES(`RS_MDU_ENTRIES),
        .IDX_WIDTH(`RS_MDU_IDX_WIDTH)
    ) u_rs_mdu (
        .clk(core_clk), .rst_n(core_rst_n),
        .issue_req(rs_mdu_req), .issue_op({1'b0, rs_mdu_op}),
        .issue_vj_valid(rs_mdu_vj_valid), .issue_vj(rs_mdu_vj), .issue_qj(rs_mdu_qj),
        .issue_vk_valid(rs_mdu_vk_valid), .issue_vk(rs_mdu_vk), .issue_qk(rs_mdu_qk),
        .issue_dest(rs_mdu_dest), .issue_pc(32'b0), .issue_imm(32'b0),
        .rs_full(rs_mdu_full),
        .cdb_valid(cdb_valid), .cdb_tag(cdb_tag), .cdb_data(cdb_data),
        .fu_ready(mdu_fu_ready), .fu_valid(mdu_fu_valid),
        .fu_op(mdu_fu_op_out), .fu_vj(mdu_fu_vj), .fu_vk(mdu_fu_vk),
        .fu_imm(), .fu_pc(), .fu_dest(mdu_fu_dest),
        .flush(actual_flush)
    );
    
    wire mdu_req_out, mdu_ack_in;
    wire [`ROB_TAG_WIDTH-1:0] mdu_tag_out;
    wire [`DATA_WIDTH-1:0] mdu_data_out;
    
    mdu u_mdu (
        .clk(core_clk), .rst_n(core_rst_n),
        .valid_in(mdu_fu_valid), .op(mdu_fu_op),
        .vj(mdu_fu_vj), .vk(mdu_fu_vk),
        .dest_in(mdu_fu_dest), .ready_out(mdu_fu_ready),
        .req_out(mdu_req_out), .tag_out(mdu_tag_out), .data_out(mdu_data_out),
        .ack_in(mdu_ack_in),
        .flush(actual_flush)
    );
    
    // AXI CDC for LSQ (Data Memory)
    axi4_lite_master_cdc u_axi_d (
        .core_clk(core_clk), .core_rst_n(core_rst_n),
        .core_mem_req(dmem_req), .core_mem_we(dmem_we), .core_mem_addr(dmem_addr), 
        .core_mem_wdata(dmem_wdata), .core_mem_rdata(dmem_rdata), .core_mem_ack(dmem_ack),
        .axi_clk(axi_clk), .axi_rst_n(axi_rst_n),
        .m_axi_awaddr(m_axi_d_awaddr), .m_axi_awvalid(m_axi_d_awvalid), .m_axi_awready(m_axi_d_awready),
        .m_axi_wdata(m_axi_d_wdata), .m_axi_wstrb(m_axi_d_wstrb), .m_axi_wvalid(m_axi_d_wvalid), .m_axi_wready(m_axi_d_wready),
        .m_axi_bresp(m_axi_d_bresp), .m_axi_bvalid(m_axi_d_bvalid), .m_axi_bready(m_axi_d_bready),
        .m_axi_araddr(m_axi_d_araddr), .m_axi_arvalid(m_axi_d_arvalid), .m_axi_arready(m_axi_d_arready),
        .m_axi_rdata(m_axi_d_rdata), .m_axi_rresp(m_axi_d_rresp), .m_axi_rvalid(m_axi_d_rvalid), .m_axi_rready(m_axi_d_rready)
    );
    
    cdb u_cdb (
        .fu0_req(alu_req_out), .fu0_tag(alu_tag_out), .fu0_data(alu_data_out),
        .fu0_br_taken(1'b0), .fu0_br_target(32'b0), .fu0_ack(alu_ack_in),
        
        .fu1_req(br_req_out), .fu1_tag(br_tag_out), .fu1_data(br_data_out),
        .fu1_br_taken(br_taken_out), .fu1_br_target(br_target_out), .fu1_ack(br_ack_in),
        
        .fu2_req(lsq_req_out), .fu2_tag(lsq_tag_out), .fu2_data(lsq_data_out),
        .fu2_br_taken(1'b0), .fu2_br_target(32'b0), .fu2_ack(lsq_ack_in),
        
        .fu3_req(mdu_req_out), .fu3_tag(mdu_tag_out), .fu3_data(mdu_data_out),
        .fu3_br_taken(1'b0), .fu3_br_target(32'b0), .fu3_ack(mdu_ack_in),
        
        .cdb_valid(cdb_valid), .cdb_tag(cdb_tag), .cdb_data(cdb_data),
        .cdb_br_taken(cdb_br_taken), .cdb_br_target(cdb_br_target)
    );

    // -------------------------------------------------------------------------
    // Hardware Performance Counters
    // -------------------------------------------------------------------------
    always @(posedge core_clk or negedge core_rst_n) begin
        if (!core_rst_n) begin
            perf_cycles      <= 0;
            perf_instret     <= 0;
            perf_branches    <= 0;
            perf_mispredicts <= 0;
        end else begin
            perf_cycles <= perf_cycles + 1;
            
            if (commit_valid) begin
                perf_instret <= perf_instret + 1;
                
                if (commit_is_branch) begin
                    perf_branches <= perf_branches + 1;
                    // Check for misprediction
                    if (commit_taken != commit_pred_taken) begin
                        perf_mispredicts <= perf_mispredicts + 1;
                    end
                end
            end
        end
    end

endmodule
