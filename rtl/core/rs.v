`timescale 1ns / 1ps
`include "../include/params.vh"

module rs #(
    parameter ENTRIES = 8,
    parameter IDX_WIDTH = 3,
    parameter ORDERED = 0
)(
    input  wire                      clk,
    input  wire                      rst_n,
    
    // Issue Interface
    input  wire                      issue_req,
    input  wire [3:0]                issue_op,
    input  wire                      issue_vj_valid,
    input  wire [`DATA_WIDTH-1:0]     issue_vj,
    input  wire [`ROB_TAG_WIDTH-1:0]  issue_qj,
    input  wire                      issue_vk_valid,
    input  wire [`DATA_WIDTH-1:0]     issue_vk,
    input  wire [`ROB_TAG_WIDTH-1:0]  issue_qk,
    input  wire [`ROB_TAG_WIDTH-1:0]  issue_dest,
    input  wire [`ADDR_WIDTH-1:0]     issue_pc,      // mainly for branch/JAL
    input  wire [`DATA_WIDTH-1:0]     issue_imm,     // immediate for operations
    output wire                      rs_full,
    
    // CDB Interface
    input  wire                      cdb_valid,
    input  wire [`ROB_TAG_WIDTH-1:0]  cdb_tag,
    input  wire [`DATA_WIDTH-1:0]     cdb_data,
    
    // Execution Interface (Output to FU)
    input  wire                      fu_ready,      // FU can accept new instruction
    output reg                       fu_valid,
    output reg  [3:0]                fu_op,
    output reg  [`DATA_WIDTH-1:0]     fu_vj,
    output reg  [`DATA_WIDTH-1:0]     fu_vk,
    output reg  [`DATA_WIDTH-1:0]     fu_imm,
    output reg  [`ADDR_WIDTH-1:0]     fu_pc,
    output reg  [`ROB_TAG_WIDTH-1:0]  fu_dest,
    
    // Flush
    input  wire                      flush
);

    reg                      busy [0:ENTRIES-1];
    reg [3:0]                op   [0:ENTRIES-1];
    reg                      qj_v [0:ENTRIES-1];
    reg [`ROB_TAG_WIDTH-1:0]  qj   [0:ENTRIES-1];
    reg [`DATA_WIDTH-1:0]     vj   [0:ENTRIES-1];
    reg                      qk_v [0:ENTRIES-1];
    reg [`ROB_TAG_WIDTH-1:0]  qk   [0:ENTRIES-1];
    reg [`DATA_WIDTH-1:0]     vk   [0:ENTRIES-1];
    reg [`ROB_TAG_WIDTH-1:0]  dest [0:ENTRIES-1];
    reg [`DATA_WIDTH-1:0]     imm  [0:ENTRIES-1];
    reg [`ADDR_WIDTH-1:0]     pc   [0:ENTRIES-1];

    // Priority encoder for free slot
    wire [IDX_WIDTH-1:0] free_idx;
    wire has_free;
    reg [IDX_WIDTH-1:0] free_idx_reg;
    reg has_free_reg;
    integer i;
    always @(*) begin
        free_idx_reg = 0;
        has_free_reg = 0;
        for (i = ENTRIES-1; i >= 0; i = i - 1) begin
            if (~busy[i]) begin
                free_idx_reg = i;
                has_free_reg = 1;
            end
        end
    end
    assign free_idx = free_idx_reg;
    assign has_free = has_free_reg;
    
    assign rs_full = ~has_free;

    // Find oldest ready entry (smallest dest tag = oldest instruction)
    reg [IDX_WIDTH-1:0] ready_idx;
    reg has_ready;
    reg [`ROB_TAG_WIDTH-1:0] oldest_ready_tag;
    reg [`ROB_TAG_WIDTH-1:0] oldest_busy_tag;
    reg has_any_busy;
    always @(*) begin
        ready_idx = 0;
        has_ready = 0;
        oldest_ready_tag = {`ROB_TAG_WIDTH{1'b1}};
        oldest_busy_tag  = {`ROB_TAG_WIDTH{1'b1}};
        has_any_busy = 0;
        for (i = 0; i < ENTRIES; i = i + 1) begin
            if (busy[i]) begin
                // Track oldest busy entry (ready or not)
                if (!has_any_busy || dest[i] < oldest_busy_tag) begin
                    oldest_busy_tag = dest[i];
                    has_any_busy = 1;
                end
                // Track oldest ready entry
                if (qj_v[i] && qk_v[i]) begin
                    if (!has_ready || dest[i] < oldest_ready_tag) begin
                        ready_idx = i;
                        has_ready = 1;
                        oldest_ready_tag = dest[i];
                    end
                end
            end
        end
        // In ORDERED mode: block dispatch if oldest busy entry isn't ready
        if (ORDERED && has_ready && (oldest_ready_tag != oldest_busy_tag)) begin
            has_ready = 0;
        end
    end

    integer j;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (j = 0; j < ENTRIES; j = j + 1) begin
                busy[j] <= 0;
                qj_v[j] <= 0;
                qk_v[j] <= 0;
            end
            fu_valid <= 0;
        end else if (flush) begin
            for (j = 0; j < ENTRIES; j = j + 1) begin
                busy[j] <= 0;
            end
            fu_valid <= 0;
        end else begin
            fu_valid <= 0;
            
            // Dispatch to FU
            if (has_ready && fu_ready) begin
                fu_valid <= 1;
                fu_op    <= op[ready_idx];
                fu_vj    <= vj[ready_idx];
                fu_vk    <= vk[ready_idx];
                fu_imm   <= imm[ready_idx];
                fu_pc    <= pc[ready_idx];
                fu_dest  <= dest[ready_idx];
                
                busy[ready_idx] <= 0; // Free the entry
            end
            
            // Issue new instruction
            if (issue_req && has_free) begin
                busy[free_idx] <= 1;
                op[free_idx]   <= issue_op;
                
                // If issuing and CDB is broadcasting what we need simultaneously
                if (!issue_vj_valid && cdb_valid && cdb_tag == issue_qj) begin
                    qj_v[free_idx] <= 1;
                    vj[free_idx]   <= cdb_data;
                end else begin
                    qj_v[free_idx] <= issue_vj_valid;
                    qj[free_idx]   <= issue_qj;
                    vj[free_idx]   <= issue_vj;
                end
                
                if (!issue_vk_valid && cdb_valid && cdb_tag == issue_qk) begin
                    qk_v[free_idx] <= 1;
                    vk[free_idx]   <= cdb_data;
                end else begin
                    qk_v[free_idx] <= issue_vk_valid;
                    qk[free_idx]   <= issue_qk;
                    vk[free_idx]   <= issue_vk;
                end
                
                dest[free_idx] <= issue_dest;
                imm[free_idx]  <= issue_imm;
                pc[free_idx]   <= issue_pc;
            end
            
            // CDB Snooping
            if (cdb_valid) begin
                for (j = 0; j < ENTRIES; j = j + 1) begin
                    if (busy[j]) begin
                        if (!qj_v[j] && qj[j] == cdb_tag) begin
                            qj_v[j] <= 1;
                            vj[j]   <= cdb_data;
                        end
                        if (!qk_v[j] && qk[j] == cdb_tag) begin
                            qk_v[j] <= 1;
                            vk[j]   <= cdb_data;
                        end
                    end
                end
            end
        end
    end

endmodule
