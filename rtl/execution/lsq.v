`timescale 1ns / 1ps
`include "../include/params.vh"
`include "../include/rv32i_defines.vh"

//-----------------------------------------------------------------------------
// Load / Store Queue (LSQ)
// Simple state-machine based unit that handles one memory operation at a time.
//
// ORDERING STRATEGY:
//  - Stores: broadcast CDB immediately (data=0) to mark ROB ready, then
//    wait for ROB commit to actually write memory. This breaks the deadlock
//    where commit needs CDB-ready but CDB needs post-commit memory write.
//  - Loads: issue memory read immediately, broadcast result on CDB.
//  - The LSQ tracks whether it is busy (not IDLE). The RS's fu_ready signal
//    ensures only one operation enters at a time. Since the LSQ is single-entry,
//    if a store enters first, the load cannot enter until the store fully
//    completes (including the memory write after commit).
//  - To guarantee the store enters before the load, the LSQ RS uses tag-order
//    dispatch via an `oldest_first` mechanism (see top.v wiring).
//
// NOTE: The store's CDB broadcast happens BEFORE the memory write. The ROB
// commits the store, which triggers the actual memory write. Only after
// the memory write completes does the LSQ become IDLE and accept the load.
//-----------------------------------------------------------------------------
module lsq (
    input  wire                      clk,
    input  wire                      rst_n,
    
    // Interface from RS
    input  wire                      valid_in,
    input  wire [2:0]                op,       // INST_LD or INST_ST
    input  wire [2:0]                funct3,   // LB/LH/LW/LBU/LHU or SB/SH/SW
    input  wire [`DATA_WIDTH-1:0]     vj,       // base address (rs1)
    input  wire [`DATA_WIDTH-1:0]     vk,       // store data   (rs2)
    input  wire [`DATA_WIDTH-1:0]     imm,      // offset
    input  wire [`ROB_TAG_WIDTH-1:0]  dest_in,
    output wire                      ready_out,
    
    // Memory Interface
    output wire                      mem_req,
    output wire                      mem_we,
    output wire [`ADDR_WIDTH-1:0]     mem_addr,
    output wire [`DATA_WIDTH-1:0]     mem_wdata,
    input  wire [`DATA_WIDTH-1:0]     mem_rdata,
    input  wire                      mem_ack,
    
    // Interface to CDB
    output reg                       req_out,
    output reg  [`ROB_TAG_WIDTH-1:0]  tag_out,
    output reg  [`DATA_WIDTH-1:0]     data_out,
    input  wire                      ack_in,
    
    // Commit info (for store write-back)
    input  wire                      commit_valid,
    input  wire [`ROB_TAG_WIDTH-1:0]  commit_tag,
    
    // Flush
    input  wire                      flush
);

    // FSM states
    localparam [2:0] IDLE           = 3'd0,
                     LD_REQ         = 3'd1,
                     LD_DONE        = 3'd2,
                     ST_CDB         = 3'd3,
                     ST_WAIT_COMMIT = 3'd4,
                     ST_REQ         = 3'd5;
    
    reg [2:0] state;
    
    reg [2:0]                saved_funct3;
    reg [`ADDR_WIDTH-1:0]     saved_addr;
    reg [`DATA_WIDTH-1:0]     saved_wdata;
    reg [`ROB_TAG_WIDTH-1:0]  saved_tag;
    
    // Deassert ready when accepting an instruction (!valid_in) to prevent
    // the RS from dispatching a second op before our state NBA takes effect.
    assign ready_out = (state == IDLE) && (!req_out || ack_in) && !valid_in;
    
    assign mem_req   = (state == LD_REQ) || (state == ST_REQ);
    assign mem_we    = (state == ST_REQ);
    assign mem_addr  = saved_addr;
    assign mem_wdata = saved_wdata;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state    <= IDLE;
            req_out  <= 0;
            tag_out  <= 0;
            data_out <= 0;
            saved_funct3 <= 0;
            saved_addr   <= 0;
            saved_wdata  <= 0;
            saved_tag    <= 0;
        end else if (flush) begin
            if (state != ST_REQ) begin
                state   <= IDLE;
                req_out <= 0;
            end
        end else begin
            if (req_out && ack_in) begin
                req_out <= 0;
            end
            
            case (state)
                IDLE: begin
                    if (valid_in) begin
                        saved_funct3 <= funct3;
                        saved_addr   <= vj + imm;
                        saved_wdata  <= vk;
                        saved_tag    <= dest_in;
                        
                        if (op == `INST_LD)
                            state <= LD_REQ;
                        else if (op == `INST_ST)
                            state <= ST_CDB;
                    end
                end
                
                // ------ LOAD PATH ------
                LD_REQ: begin
                    if (mem_ack) begin
                        state    <= LD_DONE;
                        req_out  <= 1;
                        tag_out  <= saved_tag;
                        data_out <= mem_rdata;
                    end
                end
                
                LD_DONE: begin
                    if (!req_out || ack_in) begin
                        state <= IDLE;
                    end
                end
                
                // ------ STORE PATH ------
                ST_CDB: begin
                    if (!req_out || ack_in) begin
                        req_out  <= 1;
                        tag_out  <= saved_tag;
                        data_out <= 32'd0;
                        state    <= ST_WAIT_COMMIT;
                    end
                end
                
                ST_WAIT_COMMIT: begin
                    if (commit_valid && commit_tag == saved_tag) begin
                        state <= ST_REQ;
                    end
                end
                
                ST_REQ: begin
                    if (mem_ack) begin
                        state <= IDLE;
                    end
                end
                
                default: state <= IDLE;
            endcase
        end
    end

endmodule
