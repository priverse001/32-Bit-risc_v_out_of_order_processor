`timescale 1ns / 1ps
`include "../include/params.vh"
`include "../include/rv32i_defines.vh"

//-----------------------------------------------------------------------------
// Multiply/Divide Unit (MDU) - RV32M Extension
// Implements a multi-cycle (32-cycle) iterative multiplier and divider.
// This long-latency unit perfectly demonstrates out-of-order execution,
// as the rest of the pipeline will continue around it while it computes.
//-----------------------------------------------------------------------------
module mdu (
    input  wire                      clk,
    input  wire                      rst_n,
    
    // Interface from RS
    input  wire                      valid_in,
    input  wire [2:0]                op,
    input  wire [`DATA_WIDTH-1:0]     vj,
    input  wire [`DATA_WIDTH-1:0]     vk,
    input  wire [`ROB_TAG_WIDTH-1:0]  dest_in,
    output reg                       ready_out,
    
    // Interface to CDB
    output reg                       req_out,
    output reg  [`ROB_TAG_WIDTH-1:0]  tag_out,
    output reg  [`DATA_WIDTH-1:0]     data_out,
    input  wire                      ack_in,
    
    // Flush from ROB
    input  wire                      flush
);

    localparam STATE_IDLE = 2'd0, STATE_CALC = 2'd1, STATE_DONE = 2'd2;
    reg [1:0] state;
    
    reg [5:0] count;
    reg [2:0] current_op;
    
    // Multiplier/Divider working registers
    reg [63:0] p;       // Product / Partial Remainder
    reg [31:0] m;       // Multiplicand / Divisor
    
    reg sign_a, sign_b, sign_res;
    wire [63:0] signed_p = sign_res ? -p : p;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= STATE_IDLE;
            ready_out <= 1;
            req_out <= 0;
            tag_out <= 0;
            data_out <= 0;
            count <= 0;
            p <= 0; m <= 0;
            current_op <= 0;
            sign_a <= 0; sign_b <= 0; sign_res <= 0;
        end else if (flush) begin
            state <= STATE_IDLE;
            ready_out <= 1;
            req_out <= 0;
        end else begin
            case (state)
                STATE_IDLE: begin
                    req_out <= 0;
                    if (valid_in && ready_out) begin
                        ready_out <= 0;
                        tag_out <= dest_in;
                        current_op <= op;
                        count <= 32;
                        
                        // Setup operands based on signedness
                        sign_a = (op == `MDU_MUL || op == `MDU_MULH || op == `MDU_MULHSU || op == `MDU_DIV || op == `MDU_REM) ? vj[31] : 1'b0;
                        sign_b = (op == `MDU_MUL || op == `MDU_MULH || op == `MDU_DIV || op == `MDU_REM) ? vk[31] : 1'b0;
                        
                        if (op == `MDU_DIV || op == `MDU_DIVU || op == `MDU_REM || op == `MDU_REMU) begin
                            // Division setup
                            p <= {32'b0, sign_a ? -vj : vj};
                            m <= sign_b ? -vk : vk;
                            sign_res <= (op == `MDU_DIV) ? (sign_a ^ sign_b) : 
                                        (op == `MDU_REM) ? sign_a : 1'b0;
                        end else begin
                            // Multiplication setup
                            p <= {32'b0, sign_a ? -vj : vj};
                            m <= sign_b ? -vk : vk;
                            sign_res <= sign_a ^ sign_b;
                        end
                        
                        // Handle divide by zero edge case immediately
                        if ((op == `MDU_DIV || op == `MDU_DIVU || op == `MDU_REM || op == `MDU_REMU) && vk == 0) begin
                            count <= 0;
                        end
                        
                        state <= STATE_CALC;
                    end
                end
                
                STATE_CALC: begin
                    if (count > 0) begin
                        count <= count - 1;
                        if (current_op == `MDU_DIV || current_op == `MDU_DIVU || current_op == `MDU_REM || current_op == `MDU_REMU) begin
                            // Non-restoring division step
                            if (p[62:31] >= m) begin
                                p <= { (p[62:31] - m), p[30:0], 1'b1 };
                            end else begin
                                p <= { p[62:31], p[30:0], 1'b0 };
                            end
                        end else begin
                            // Shift-and-add multiplication step
                            if (p[0]) begin
                                p <= { (p[63:32] + m), p[31:1] };
                            end else begin
                                p <= { 1'b0, p[63:1] };
                            end
                        end
                    end else begin
                        // Calculation complete, format result
                        req_out <= 1;
                        state <= STATE_DONE;
                        
                        if (current_op == `MDU_DIV || current_op == `MDU_DIVU || current_op == `MDU_REM || current_op == `MDU_REMU) begin
                            if (vk == 0) begin // Div by zero
                                data_out <= (current_op == `MDU_REM || current_op == `MDU_REMU) ? vj : 32'hFFFFFFFF;
                            end else if (current_op == `MDU_REM || current_op == `MDU_REMU) begin
                                data_out <= sign_res ? -p[63:32] : p[63:32]; // Remainder
                            end else begin
                                data_out <= sign_res ? -p[31:0] : p[31:0]; // Quotient
                            end
                        end else begin
                            // Multiplication
                            if (current_op == `MDU_MUL) begin
                                data_out <= signed_p[31:0];
                            end else begin
                                data_out <= signed_p[63:32];
                            end
                        end
                    end
                end
                
                STATE_DONE: begin
                    if (ack_in) begin
                        req_out <= 0;
                        ready_out <= 1;
                        state <= STATE_IDLE;
                    end
                end
            endcase
        end
    end

endmodule
