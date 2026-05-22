`timescale 1ns / 1ps
`include "../include/params.vh"
`include "../include/rv32i_defines.vh"

module decode_dispatch (
    input  wire                      clk,
    input  wire                      rst_n,
    
    // From Fetch
    input  wire [31:0]               instr_in,
    input  wire [`ADDR_WIDTH-1:0]     pc_in,
    input  wire                      instr_valid,
    output wire                      ready_for_instr,
    
    // To ROB
    output reg                       rob_req,
    output reg  [`REG_ADDR_WIDTH-1:0] rob_rd,
    output reg  [2:0]                rob_inst_type,
    output reg  [`ADDR_WIDTH-1:0]     rob_pc,
    output reg                       rob_pred_taken, // New: Tell ROB what we predicted
    input  wire                      rob_full,
    input  wire [`ROB_TAG_WIDTH-1:0]  rob_alloc_idx,
    
    // To RAT
    output wire [`REG_ADDR_WIDTH-1:0] rat_rs1_addr,
    output wire [`REG_ADDR_WIDTH-1:0] rat_rs2_addr,
    input  wire                      rat_rs1_rob_valid,
    input  wire [`ROB_TAG_WIDTH-1:0]  rat_rs1_rob_tag,
    input  wire                      rat_rs2_rob_valid,
    input  wire [`ROB_TAG_WIDTH-1:0]  rat_rs2_rob_tag,
    
    output reg                       rat_rename_en,
    output reg  [`REG_ADDR_WIDTH-1:0] rat_rename_rd,
    output reg  [`ROB_TAG_WIDTH-1:0]  rat_rename_rob_tag,
    
    // To Register File (for values)
    output wire [`REG_ADDR_WIDTH-1:0] rf_rs1_addr,
    output wire [`REG_ADDR_WIDTH-1:0] rf_rs2_addr,
    input  wire [`DATA_WIDTH-1:0]     rf_rs1_data,
    input  wire [`DATA_WIDTH-1:0]     rf_rs2_data,
    
    // To RS (ALU)
    output reg                       rs_alu_req,
    output reg  [3:0]                rs_alu_op,
    output reg                       rs_alu_vj_valid,
    output reg  [`DATA_WIDTH-1:0]     rs_alu_vj,
    output reg  [`ROB_TAG_WIDTH-1:0]  rs_alu_qj,
    output reg                       rs_alu_vk_valid,
    output reg  [`DATA_WIDTH-1:0]     rs_alu_vk,
    output reg  [`ROB_TAG_WIDTH-1:0]  rs_alu_qk,
    output reg  [`ROB_TAG_WIDTH-1:0]  rs_alu_dest,
    output reg  [`DATA_WIDTH-1:0]     rs_alu_imm,
    output reg  [`ADDR_WIDTH-1:0]     rs_alu_pc,
    input  wire                      rs_alu_full,
    
    // To RS (Branch)
    output reg                       rs_br_req,
    output reg  [3:0]                rs_br_op,
    output reg                       rs_br_vj_valid,
    output reg  [`DATA_WIDTH-1:0]     rs_br_vj,
    output reg  [`ROB_TAG_WIDTH-1:0]  rs_br_qj,
    output reg                       rs_br_vk_valid,
    output reg  [`DATA_WIDTH-1:0]     rs_br_vk,
    output reg  [`ROB_TAG_WIDTH-1:0]  rs_br_qk,
    output reg  [`ROB_TAG_WIDTH-1:0]  rs_br_dest,
    output reg  [`DATA_WIDTH-1:0]     rs_br_imm,
    output reg  [`ADDR_WIDTH-1:0]     rs_br_pc,
    output reg                       rs_br_pred_taken,
    input  wire                      rs_br_full,
    
    // To RS (MDU)
    output reg                       rs_mdu_req,
    output reg  [2:0]                rs_mdu_op,
    output reg                       rs_mdu_vj_valid,
    output reg  [`DATA_WIDTH-1:0]     rs_mdu_vj,
    output reg  [`ROB_TAG_WIDTH-1:0]  rs_mdu_qj,
    output reg                       rs_mdu_vk_valid,
    output reg  [`DATA_WIDTH-1:0]     rs_mdu_vk,
    output reg  [`ROB_TAG_WIDTH-1:0]  rs_mdu_qk,
    output reg  [`ROB_TAG_WIDTH-1:0]  rs_mdu_dest,
    input  wire                      rs_mdu_full,
    
    // To RS (LSQ)
    output reg                       rs_lsq_req,
    output reg  [2:0]                rs_lsq_op,
    output reg  [2:0]                rs_lsq_funct3,
    output reg                       rs_lsq_vj_valid,
    output reg  [`DATA_WIDTH-1:0]     rs_lsq_vj,
    output reg  [`ROB_TAG_WIDTH-1:0]  rs_lsq_qj,
    output reg                       rs_lsq_vk_valid,
    output reg  [`DATA_WIDTH-1:0]     rs_lsq_vk,
    output reg  [`ROB_TAG_WIDTH-1:0]  rs_lsq_qk,
    output reg  [`ROB_TAG_WIDTH-1:0]  rs_lsq_dest,
    output reg  [`DATA_WIDTH-1:0]     rs_lsq_imm,
    input  wire                      rs_lsq_full,
    
    // CDB Snooping
    input  wire                      cdb_valid,
    input  wire [`ROB_TAG_WIDTH-1:0]  cdb_tag,
    input  wire [`DATA_WIDTH-1:0]     cdb_data,
    
    // Branch Predictor Interface (to Top/BPU)
    output wire [`ADDR_WIDTH-1:0]     bpu_fetch_pc,
    output wire                      bpu_fetch_valid,
    input  wire                      bpu_predict_taken,
    
    // To Fetch Stage (Speculative Flush)
    output reg                       spec_flush,
    output reg  [`ADDR_WIDTH-1:0]     spec_flush_target
);

    wire [6:0] opcode = instr_in[6:0];
    wire [4:0] rd     = instr_in[11:7];
    wire [2:0] funct3 = instr_in[14:12];
    wire [4:0] rs1    = instr_in[19:15];
    wire [4:0] rs2    = instr_in[24:20];
    wire [6:0] funct7 = instr_in[31:25];
    
    wire [31:0] imm_i = {{20{instr_in[31]}}, instr_in[31:20]};
    wire [31:0] imm_s = {{20{instr_in[31]}}, instr_in[31:25], instr_in[11:7]};
    wire [31:0] imm_b = {{20{instr_in[31]}}, instr_in[7], instr_in[30:25], instr_in[11:8], 1'b0};
    wire [31:0] imm_u = {instr_in[31:12], 12'b0};
    wire [31:0] imm_j = {{12{instr_in[31]}}, instr_in[19:12], instr_in[20], instr_in[30:21], 1'b0};

    assign rat_rs1_addr = rs1;
    assign rat_rs2_addr = rs2;
    assign rf_rs1_addr  = rs1;
    assign rf_rs2_addr  = rs2;

    reg [2:0]  dec_inst_type;
    reg [3:0]  dec_alu_op;
    reg [3:0]  dec_br_op;
    reg [2:0]  dec_lsq_op;
    reg [31:0] dec_imm;
    reg [2:0]  dec_mdu_op;
    reg        is_alu, is_br, is_lsq, is_mdu;
    reg        uses_rs1, uses_rs2, uses_rd;

    always @(*) begin
        is_alu = 0; is_br = 0; is_lsq = 0; is_mdu = 0;
        uses_rs1 = 0; uses_rs2 = 0; uses_rd = 0;
        dec_inst_type = `INST_ALU; dec_alu_op = 0; dec_br_op = 0; dec_lsq_op = 0; dec_mdu_op = 0; dec_imm = 0;
        
        case (opcode)
            `OPCODE_OP: begin
                if (funct7 == `F7_M) begin
                    is_mdu = 1; uses_rs1 = 1; uses_rs2 = 1; uses_rd = 1; dec_inst_type = `INST_MDU;
                    dec_mdu_op = funct3; // Funct3 matches MDU opcodes exactly
                end else begin
                    is_alu = 1; uses_rs1 = 1; uses_rs2 = 1; uses_rd = 1; dec_inst_type = `INST_ALU;
                    case (funct3)
                        `F3_ADD:  dec_alu_op = (funct7 == `F7_ALT) ? `ALU_SUB : `ALU_ADD;
                        `F3_SLL:  dec_alu_op = `ALU_SLL;
                        `F3_SLT:  dec_alu_op = `ALU_SLT;
                        `F3_SLTU: dec_alu_op = `ALU_SLTU;
                        `F3_XOR:  dec_alu_op = `ALU_XOR;
                        `F3_SRL:  dec_alu_op = (funct7 == `F7_ALT) ? `ALU_SRA : `ALU_SRL;
                        `F3_OR:   dec_alu_op = `ALU_OR;
                        `F3_AND:  dec_alu_op = `ALU_AND;
                    endcase
                end
            end
            `OPCODE_OP_IMM: begin
                is_alu = 1; uses_rs1 = 1; uses_rd = 1; dec_inst_type = `INST_ALU; dec_imm = imm_i;
                case (funct3)
                    `F3_ADD:  dec_alu_op = `ALU_ADD;
                    `F3_SLL:  dec_alu_op = `ALU_SLL;
                    `F3_SLT:  dec_alu_op = `ALU_SLT;
                    `F3_SLTU: dec_alu_op = `ALU_SLTU;
                    `F3_XOR:  dec_alu_op = `ALU_XOR;
                    `F3_SRL:  dec_alu_op = (funct7 == `F7_ALT) ? `ALU_SRA : `ALU_SRL;
                    `F3_OR:   dec_alu_op = `ALU_OR;
                    `F3_AND:  dec_alu_op = `ALU_AND;
                endcase
            end
            `OPCODE_LUI: begin
                is_alu = 1; uses_rd = 1; dec_inst_type = `INST_ALU; dec_imm = imm_u; dec_alu_op = `ALU_LUI;
            end
            `OPCODE_AUIPC: begin
                is_alu = 1; uses_rd = 1; dec_inst_type = `INST_ALU; dec_imm = imm_u; dec_alu_op = `ALU_AUIPC;
            end
            `OPCODE_BRANCH: begin
                is_br = 1; uses_rs1 = 1; uses_rs2 = 1; dec_inst_type = `INST_BR; dec_imm = imm_b;
                case (funct3)
                    `F3_BEQ:  dec_br_op = `BR_BEQ;
                    `F3_BNE:  dec_br_op = `BR_BNE;
                    `F3_BLT:  dec_br_op = `BR_BLT;
                    `F3_BGE:  dec_br_op = `BR_BGE;
                    `F3_BLTU: dec_br_op = `BR_BLTU;
                    `F3_BGEU: dec_br_op = `BR_BGEU;
                endcase
            end
            `OPCODE_JAL: begin
                is_br = 1; uses_rd = 1; dec_inst_type = `INST_BR; dec_imm = imm_j; dec_br_op = `BR_JUMP;
            end
            `OPCODE_JALR: begin
                is_br = 1; uses_rs1 = 1; uses_rd = 1; dec_inst_type = `INST_BR; dec_imm = imm_i; dec_br_op = `BR_JUMP;
            end
            `OPCODE_LOAD: begin
                is_lsq = 1; uses_rs1 = 1; uses_rd = 1; dec_inst_type = `INST_LD; dec_imm = imm_i; dec_lsq_op = `INST_LD;
            end
            `OPCODE_STORE: begin
                is_lsq = 1; uses_rs1 = 1; uses_rs2 = 1; dec_inst_type = `INST_ST; dec_imm = imm_s; dec_lsq_op = `INST_ST;
            end
        endcase
    end

    wire rs_avail = (is_alu && !rs_alu_full) || (is_br && !rs_br_full) || (is_lsq && !rs_lsq_full) || (is_mdu && !rs_mdu_full);
    wire can_dispatch = instr_valid && !rob_full && rs_avail;
    assign ready_for_instr = can_dispatch;
    
    assign bpu_fetch_pc = pc_in;
    assign bpu_fetch_valid = can_dispatch && is_br;

    always @(*) begin
        rob_req = 0; rob_rd = 0; rob_inst_type = 0; rob_pc = 0; rob_pred_taken = 0;
        rat_rename_en = 0; rat_rename_rd = 0; rat_rename_rob_tag = 0;
        rs_alu_req = 0; rs_br_req = 0; rs_lsq_req = 0; rs_mdu_req = 0;
        spec_flush = 0; spec_flush_target = 0;
        
        rs_alu_op = dec_alu_op; rs_alu_imm = dec_imm; rs_alu_pc = pc_in; rs_alu_dest = rob_alloc_idx;
        rs_br_op = dec_br_op;   rs_br_imm = dec_imm;  rs_br_pc = pc_in;  rs_br_dest = rob_alloc_idx; rs_br_pred_taken = 0;
        rs_lsq_op = dec_lsq_op; rs_lsq_imm = dec_imm; rs_lsq_funct3 = funct3; rs_lsq_dest = rob_alloc_idx;
        rs_mdu_op = dec_mdu_op; rs_mdu_dest = rob_alloc_idx;
        
        rs_alu_vj_valid = 1; rs_alu_vj = 0; rs_alu_qj = 0;
        if (uses_rs1) begin
            if (rat_rs1_rob_valid && !(cdb_valid && cdb_tag == rat_rs1_rob_tag)) begin
                rs_alu_vj_valid = 0;
                rs_alu_qj = rat_rs1_rob_tag;
            end else if (rat_rs1_rob_valid && (cdb_valid && cdb_tag == rat_rs1_rob_tag)) begin
                rs_alu_vj_valid = 1;
                rs_alu_vj = cdb_data;
            end else begin
                rs_alu_vj_valid = 1;
                rs_alu_vj = rf_rs1_data;
            end
        end
        rs_br_vj_valid = rs_alu_vj_valid; rs_br_vj = rs_alu_vj; rs_br_qj = rs_alu_qj;
        rs_lsq_vj_valid = rs_alu_vj_valid; rs_lsq_vj = rs_alu_vj; rs_lsq_qj = rs_alu_qj;
        rs_mdu_vj_valid = rs_alu_vj_valid; rs_mdu_vj = rs_alu_vj; rs_mdu_qj = rs_alu_qj;
        
        rs_alu_vk_valid = 1; rs_alu_vk = 0; rs_alu_qk = 0;
        if (uses_rs2) begin
            if (rat_rs2_rob_valid && !(cdb_valid && cdb_tag == rat_rs2_rob_tag)) begin
                rs_alu_vk_valid = 0;
                rs_alu_qk = rat_rs2_rob_tag;
            end else if (rat_rs2_rob_valid && (cdb_valid && cdb_tag == rat_rs2_rob_tag)) begin
                rs_alu_vk_valid = 1;
                rs_alu_vk = cdb_data;
            end else begin
                rs_alu_vk_valid = 1;
                rs_alu_vk = rf_rs2_data;
            end
        end
        rs_br_vk_valid = rs_alu_vk_valid; rs_br_vk = rs_alu_vk; rs_br_qk = rs_alu_qk;
        rs_lsq_vk_valid = rs_alu_vk_valid; rs_lsq_vk = rs_alu_vk; rs_lsq_qk = rs_alu_qk;
        rs_mdu_vk_valid = rs_alu_vk_valid; rs_mdu_vk = rs_alu_vk; rs_mdu_qk = rs_alu_qk;
        
        if (can_dispatch) begin
            rob_req = 1;
            rob_rd = uses_rd ? rd : 5'd0;
            rob_inst_type = dec_inst_type;
            rob_pc = pc_in;
            
            if (uses_rd && rd != 0) begin
                rat_rename_en = 1;
                rat_rename_rd = rd;
                rat_rename_rob_tag = rob_alloc_idx;
            end
            
            if (is_alu) rs_alu_req = 1;
            else if (is_br) begin
                rs_br_req = 1;
                rs_br_pred_taken = bpu_predict_taken;
                rob_pred_taken = bpu_predict_taken;
                
                // If BPU predicts taken, flush the fetch stage and redirect it
                if (bpu_predict_taken && dec_br_op != `BR_JUMP) begin
                    spec_flush = 1;
                    spec_flush_target = pc_in + dec_imm; // Calculate branch target
                end else if (dec_br_op == `BR_JUMP) begin // Unconditional Jumps are always taken
                    spec_flush = 1;
                    rs_br_pred_taken = 1;
                    rob_pred_taken = 1;
                    // For JAL we know target. For JALR we don't (need rs1), so we just guess PC+4 or stall.
                    // For simplicity, we just use pc_in + imm_j for JAL.
                    spec_flush_target = pc_in + dec_imm; 
                end
            end
            else if (is_lsq) rs_lsq_req = 1;
            else if (is_mdu) rs_mdu_req = 1;
        end
    end

endmodule
