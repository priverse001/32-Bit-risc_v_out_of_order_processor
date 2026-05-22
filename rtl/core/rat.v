`timescale 1ns / 1ps
`include "../include/params.vh"

module rat (
    input  wire                      clk,
    input  wire                      rst_n,
    
    // Read Ports (Issue)
    input  wire [`REG_ADDR_WIDTH-1:0] rs1_addr,
    input  wire [`REG_ADDR_WIDTH-1:0] rs2_addr,
    output wire                      rs1_rob_valid,
    output wire [`ROB_TAG_WIDTH-1:0]  rs1_rob_tag,
    output wire                      rs2_rob_valid,
    output wire [`ROB_TAG_WIDTH-1:0]  rs2_rob_tag,
    
    // Write Port (Issue / Rename)
    input  wire                      rename_en,
    input  wire [`REG_ADDR_WIDTH-1:0] rename_rd,
    input  wire [`ROB_TAG_WIDTH-1:0]  rename_rob_tag,
    
    // Commit Port
    input  wire                      commit_valid,
    input  wire [`REG_ADDR_WIDTH-1:0] commit_rd,
    input  wire [`ROB_TAG_WIDTH-1:0]  commit_rob_tag,
    
    // Flush Port
    input  wire                      flush
);

    reg                      valid [0:`NUM_REGS-1];
    reg [`ROB_TAG_WIDTH-1:0]  tag   [0:`NUM_REGS-1];

    assign rs1_rob_valid = (rs1_addr != 0) ? valid[rs1_addr] : 1'b0;
    assign rs1_rob_tag   = (rs1_addr != 0) ? tag[rs1_addr] : {`ROB_TAG_WIDTH{1'b0}};
    
    assign rs2_rob_valid = (rs2_addr != 0) ? valid[rs2_addr] : 1'b0;
    assign rs2_rob_tag   = (rs2_addr != 0) ? tag[rs2_addr] : {`ROB_TAG_WIDTH{1'b0}};

    integer i;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 0; i < `NUM_REGS; i = i + 1) begin
                valid[i] <= 1'b0;
                tag[i]   <= 0;
            end
        end else if (flush) begin
            for (i = 0; i < `NUM_REGS; i = i + 1) begin
                valid[i] <= 1'b0;
            end
        end else begin
            // Clear on commit
            if (commit_valid && (commit_rd != 0) && valid[commit_rd] && (tag[commit_rd] == commit_rob_tag)) begin
                valid[commit_rd] <= 1'b0;
            end
            
            // Rename on issue overrides clear
            if (rename_en && (rename_rd != 0)) begin
                valid[rename_rd] <= 1'b1;
                tag[rename_rd]   <= rename_rob_tag;
            end
        end
    end

endmodule
