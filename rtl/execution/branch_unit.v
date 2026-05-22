`timescale 1ns / 1ps
`include "../include/params.vh"
`include "../include/rv32i_defines.vh"

//-----------------------------------------------------------------------------
// Branch Functional Unit
// Evaluates branch conditions (BEQ, BNE, BLT, BGE, BLTU, BGEU) and
// computes the branch target address.  For JAL/JALR, the link address
// (PC+4) is produced as the result value.
//-----------------------------------------------------------------------------
module branch_unit (
    input  wire                      clk,
    input  wire                      rst_n,
    
    // Interface from RS
    input  wire                      valid_in,
    input  wire [3:0]                op,
    input  wire [`DATA_WIDTH-1:0]     vj,
    input  wire [`DATA_WIDTH-1:0]     vk,
    input  wire [`DATA_WIDTH-1:0]     imm,
    input  wire [`ADDR_WIDTH-1:0]     pc,
    input  wire [`ROB_TAG_WIDTH-1:0]  dest_in,
    output wire                      ready_out,
    
    // Interface to CDB
    output reg                       req_out,
    output reg  [`ROB_TAG_WIDTH-1:0]  tag_out,
    output reg  [`DATA_WIDTH-1:0]     data_out,
    output reg                       br_taken_out,
    output reg  [`ADDR_WIDTH-1:0]     br_target_out,
    input  wire                      ack_in,
    
    // Flush
    input  wire                      flush
);

    assign ready_out = !req_out || ack_in;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            req_out       <= 0;
            tag_out       <= 0;
            data_out      <= 0;
            br_taken_out  <= 0;
            br_target_out <= 0;
        end else if (flush) begin
            req_out <= 0;
        end else begin
            if (req_out && ack_in) begin
                req_out <= 0;
            end
            
            if (valid_in && ready_out) begin
                req_out <= 1;
                tag_out <= dest_in;
                
                // Return address for JAL/JALR (link register value)
                data_out <= pc + 4;
                
                // Target address calculation
                if (op == `BR_JUMP) begin
                    // JALR: target = (rs1 + imm) & ~1
                    br_target_out <= (vj + imm) & 32'hFFFFFFFE;
                end else begin
                    // Conditional branches: target = PC + imm
                    br_target_out <= pc + imm;
                end
                
                case (op)
                    `BR_BEQ:  br_taken_out <= (vj == vk);
                    `BR_BNE:  br_taken_out <= (vj != vk);
                    `BR_BLT:  br_taken_out <= ($signed(vj) < $signed(vk));
                    `BR_BGE:  br_taken_out <= ($signed(vj) >= $signed(vk));
                    `BR_BLTU: br_taken_out <= (vj < vk);
                    `BR_BGEU: br_taken_out <= (vj >= vk);
                    `BR_JUMP: br_taken_out <= 1'b1;
                    default:  br_taken_out <= 1'b0;
                endcase
            end
        end
    end

endmodule
