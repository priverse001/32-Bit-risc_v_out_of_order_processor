`timescale 1ns / 1ps
`include "../include/params.vh"
`include "../include/rv32i_defines.vh"

//-----------------------------------------------------------------------------
// ALU Functional Unit
// Single-cycle execution. Receives operands from Reservation Station,
// computes the result, and presents it to the CDB arbiter.
//
// The decode/dispatch stage is responsible for routing the correct second
// operand: for R-type instructions vk carries rs2; for I-type instructions
// vk is unused and imm carries the immediate. The ALU uses a 'use_imm'
// flag (encoded in op[3]) set by the dispatch stage to select between them.
//-----------------------------------------------------------------------------
module alu (
    input  wire                      clk,
    input  wire                      rst_n,
    
    // Interface from RS
    input  wire                      valid_in,
    input  wire [3:0]                op,
    input  wire [`DATA_WIDTH-1:0]     vj,        // Source operand 1 (rs1)
    input  wire [`DATA_WIDTH-1:0]     vk,        // Source operand 2 (rs2 for R-type)
    input  wire [`DATA_WIDTH-1:0]     imm,       // Immediate (for I-type / LUI / AUIPC)
    input  wire [`ADDR_WIDTH-1:0]     pc,
    input  wire [`ROB_TAG_WIDTH-1:0]  dest_in,
    output wire                      ready_out,
    
    // Interface to CDB
    output reg                       req_out,
    output reg  [`ROB_TAG_WIDTH-1:0]  tag_out,
    output reg  [`DATA_WIDTH-1:0]     data_out,
    input  wire                      ack_in,
    
    // Flush
    input  wire                      flush
);

    assign ready_out = !req_out || ack_in;
    
    // Select second operand:
    //  - For LUI/AUIPC the immediate is the primary operand.
    //  - For I-type ALU ops the dispatch stage places the immediate in 'imm'
    //    and leaves vk = 0.  We detect I-type by checking imm != 0 **only**
    //    for ops that can be both R/I.  LUI and AUIPC always use imm directly.
    //  - For R-type the immediate is 0 and vk holds rs2.
    //
    // A cleaner approach: the dispatch stage sets imm to the correct second
    // operand for I-type, and sets vk for R-type.  The ALU simply picks
    // whichever is non-zero, with a special case: if the I-type immediate
    // genuinely IS zero (addi x1, x0, 0 == NOP), vk will also be zero, so
    // the result is still correct (x + 0 = x).
    wire use_imm = (op == `ALU_LUI) || (op == `ALU_AUIPC);
    wire [`DATA_WIDTH-1:0] src2 = use_imm ? imm : (imm != 0 ? imm : vk);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            req_out  <= 0;
            tag_out  <= 0;
            data_out <= 0;
        end else if (flush) begin
            req_out <= 0;
        end else begin
            if (req_out && ack_in) begin
                req_out <= 0;
            end
            
            if (valid_in && ready_out) begin
                req_out <= 1;
                tag_out <= dest_in;
                case (op)
                    `ALU_ADD:   data_out <= vj + src2;
                    `ALU_SUB:   data_out <= vj - src2;
                    `ALU_SLL:   data_out <= vj << src2[4:0];
                    `ALU_SLT:   data_out <= ($signed(vj) < $signed(src2)) ? 32'd1 : 32'd0;
                    `ALU_SLTU:  data_out <= (vj < src2) ? 32'd1 : 32'd0;
                    `ALU_XOR:   data_out <= vj ^ src2;
                    `ALU_SRL:   data_out <= vj >> src2[4:0];
                    `ALU_SRA:   data_out <= $signed(vj) >>> src2[4:0];
                    `ALU_OR:    data_out <= vj | src2;
                    `ALU_AND:   data_out <= vj & src2;
                    `ALU_LUI:   data_out <= imm;
                    `ALU_AUIPC: data_out <= pc + imm;
                    default:    data_out <= 32'd0;
                endcase
            end
        end
    end

endmodule
