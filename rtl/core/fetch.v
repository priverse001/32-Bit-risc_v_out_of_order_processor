`timescale 1ns / 1ps
`include "../include/params.vh"

//-----------------------------------------------------------------------------
// Instruction Fetch Unit
// Requests instructions from memory and pipelines them to the decode stage.
// Now interfaces with an external memory system via generic req/ack signals.
//-----------------------------------------------------------------------------
module fetch (
    input  wire                      clk,
    input  wire                      rst_n,
    
    // Interface to Decode/Dispatch
    output reg  [31:0]               instr_out,
    output reg  [`ADDR_WIDTH-1:0]     pc_out,
    output reg                       instr_valid,
    input  wire                      ready_for_instr,
    
    // Flush Interface from Commit (ROB)
    input  wire                      flush,
    input  wire [`ADDR_WIDTH-1:0]     flush_target,
    
    // Memory Interface (Instruction Fetch)
    output reg                       imem_req,
    output reg  [`ADDR_WIDTH-1:0]     imem_addr,
    input  wire [31:0]               imem_rdata,
    input  wire                      imem_ack
);

    reg [`ADDR_WIDTH-1:0] pc;
    
    // State machine for fetch
    localparam FETCH_IDLE = 0, FETCH_WAIT_ACK = 1;
    reg state;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pc <= 0;
            instr_out <= 0;
            pc_out <= 0;
            instr_valid <= 0;
            imem_req <= 0;
            imem_addr <= 0;
            state <= FETCH_IDLE;
        end else if (flush) begin
            pc <= flush_target;
            instr_valid <= 0;
            imem_req <= 0;
            state <= FETCH_IDLE;
        end else begin
            // Handshake with decode stage: if decode accepts the instruction, clear valid
            if (instr_valid && ready_for_instr) begin
                instr_valid <= 0;
            end
            
            case (state)
                FETCH_IDLE: begin
                    // If we have room in the output register, request next instruction
                    if (!instr_valid || ready_for_instr) begin
                        imem_req <= 1;
                        imem_addr <= pc;
                        state <= FETCH_WAIT_ACK;
                    end
                end
                
                FETCH_WAIT_ACK: begin
                    if (imem_ack) begin
                        imem_req <= 0;
                        instr_out <= imem_rdata;
                        pc_out <= imem_addr; // the PC we requested
                        instr_valid <= 1;
                        pc <= pc + 4; // increment PC for next fetch
                        state <= FETCH_IDLE;
                    end
                end
            endcase
        end
    end

endmodule
