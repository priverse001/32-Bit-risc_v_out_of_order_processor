`timescale 1ns / 1ps
`include "../include/params.vh"

//-----------------------------------------------------------------------------
// Architectural Register File
//-----------------------------------------------------------------------------
module register_file (
    input  wire                      clk,
    input  wire                      rst_n,
    
    // Read Ports
    input  wire [`REG_ADDR_WIDTH-1:0] rs1_addr,
    input  wire [`REG_ADDR_WIDTH-1:0] rs2_addr,
    output wire [`DATA_WIDTH-1:0]     rs1_data,
    output wire [`DATA_WIDTH-1:0]     rs2_data,
    
    // Debug Read Port (Synthesizable)
    input  wire [`REG_ADDR_WIDTH-1:0] debug_addr,
    output wire [`DATA_WIDTH-1:0]     debug_data,
    
    // Write Port (Commit)
    input  wire                      we,
    input  wire [`REG_ADDR_WIDTH-1:0] rd_addr,
    input  wire [`DATA_WIDTH-1:0]     rd_data
);

    reg [`DATA_WIDTH-1:0] registers [0:`NUM_REGS-1];
    
    // RISC-V x0 is hardwired to 0
    assign rs1_data = (rs1_addr == 0) ? {`DATA_WIDTH{1'b0}} : registers[rs1_addr];
    assign rs2_data = (rs2_addr == 0) ? {`DATA_WIDTH{1'b0}} : registers[rs2_addr];
    
    assign debug_data = (debug_addr == 0) ? {`DATA_WIDTH{1'b0}} : registers[debug_addr];

    integer i;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 0; i < `NUM_REGS; i = i + 1) begin
                registers[i] <= 0;
            end
        end else begin
            if (we && rd_addr != 0) begin
                registers[rd_addr] <= rd_data;
            end
        end
    end

endmodule
