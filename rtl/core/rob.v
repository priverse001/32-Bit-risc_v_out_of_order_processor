`timescale 1ns / 1ps
`include "../include/params.vh"
`include "../include/rv32i_defines.vh"

//-----------------------------------------------------------------------------
// Reorder Buffer (ROB)
// Circular FIFO that tracks all in-flight instructions.
// Supports: allocation (issue), result writeback (CDB), in-order commit,
// and pipeline flush on branch misprediction.
//-----------------------------------------------------------------------------
module rob (
    input  wire                      clk,
    input  wire                      rst_n,
    
    // Issue Stage Interface
    input  wire                      issue_req,
    input  wire [`REG_ADDR_WIDTH-1:0] issue_rd,
    input  wire [2:0]                issue_inst_type,
    input  wire [`ADDR_WIDTH-1:0]     issue_pc,
    input  wire                      issue_pred_taken, // New
    output wire                      rob_full,
    output wire [`ROB_TAG_WIDTH-1:0]  rob_alloc_idx,
    
    // CDB Interface
    input  wire                      cdb_valid,
    input  wire [`ROB_TAG_WIDTH-1:0]  cdb_tag,
    input  wire [`DATA_WIDTH-1:0]     cdb_data,
    input  wire                      cdb_branch_taken,
    input  wire [`ADDR_WIDTH-1:0]     cdb_branch_target,
    
    // Commit Stage Interface
    output reg                       commit_valid,
    output reg  [`ROB_TAG_WIDTH-1:0]  commit_tag,
    output reg  [`REG_ADDR_WIDTH-1:0] commit_rd,
    output reg  [`DATA_WIDTH-1:0]     commit_data,
    output reg  [`ADDR_WIDTH-1:0]     commit_pc,
    output reg                       commit_is_branch, // New
    output reg                       commit_taken, // New
    output reg                       commit_pred_taken, // New
    output reg                       commit_flush,
    output reg  [`ADDR_WIDTH-1:0]     commit_flush_target
);

    // ROB Entry structure
    reg                       valid      [0:`ROB_ENTRIES-1];
    reg                       ready      [0:`ROB_ENTRIES-1];
    reg [`REG_ADDR_WIDTH-1:0]  dest_reg   [0:`ROB_ENTRIES-1];
    reg [`DATA_WIDTH-1:0]      value      [0:`ROB_ENTRIES-1];
    reg [2:0]                 inst_type  [0:`ROB_ENTRIES-1];
    reg [`ADDR_WIDTH-1:0]      pc         [0:`ROB_ENTRIES-1];
    reg                       pred_taken [0:`ROB_ENTRIES-1]; // New
    
    // Branch specifics
    reg                       br_taken   [0:`ROB_ENTRIES-1];
    reg [`ADDR_WIDTH-1:0]      br_target  [0:`ROB_ENTRIES-1];

    // Circular buffer pointers
    reg [`ROB_TAG_WIDTH-1:0]   head;
    reg [`ROB_TAG_WIDTH-1:0]   tail;
    reg [`ROB_TAG_WIDTH:0]     count; // Extra bit to distinguish full/empty

    // Internal signal: can we commit this cycle?
    wire can_commit = (count > 0) && valid[head] && ready[head];
    
    // Internal signal: can we issue this cycle? (no flush pending)
    wire can_issue = issue_req && !rob_full && !commit_flush;

    assign rob_full = (count == `ROB_ENTRIES);
    assign rob_alloc_idx = tail;
    // commit_tag is now registered — set alongside commit_valid in the always block

    integer i;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            head  <= 0;
            tail  <= 0;
            count <= 0;
            commit_valid        <= 0;
            commit_tag          <= 0;
            commit_rd           <= 0;
            commit_data         <= 0;
            commit_pc           <= 0;
            commit_is_branch    <= 0;
            commit_taken        <= 0;
            commit_pred_taken   <= 0;
            commit_flush        <= 0;
            commit_flush_target <= 0;
            for (i = 0; i < `ROB_ENTRIES; i = i + 1) begin
                valid[i]     <= 0;
                ready[i]     <= 0;
                dest_reg[i]  <= 0;
                value[i]     <= 0;
                inst_type[i] <= 0;
                pc[i]        <= 0;
                pred_taken[i]<= 0;
                br_taken[i]  <= 0;
                br_target[i] <= 0;
            end
        end else begin
            // Default: de-assert single-cycle pulses
            commit_valid <= 0;
            commit_flush <= 0;
            commit_is_branch <= 0;

            // ---- FLUSH (takes priority over everything) ----
            // commit_flush was asserted on the *previous* posedge;
            // on this posedge we drain the ROB.
            if (commit_flush) begin
                head  <= 0;
                tail  <= 0;
                count <= 0;
                for (i = 0; i < `ROB_ENTRIES; i = i + 1) begin
                    valid[i] <= 0;
                    ready[i] <= 0;
                end
            end else begin

                // ---- CDB WRITEBACK (first, so commit can see ready[head]) ----
                if (cdb_valid && valid[cdb_tag]) begin
                    ready[cdb_tag]     <= 1;
                    value[cdb_tag]     <= cdb_data;
                    br_taken[cdb_tag]  <= cdb_branch_taken;
                    br_target[cdb_tag] <= cdb_branch_target;
                end

                // ---- COMMIT ----
                if (can_commit) begin
                    commit_valid <= 1;
                    commit_tag   <= head;  // Capture head BEFORE it advances
                    commit_rd    <= dest_reg[head];
                    commit_data  <= value[head];
                    commit_pc    <= pc[head];
                    
                    commit_is_branch  <= (inst_type[head] == `INST_BR);
                    commit_taken      <= br_taken[head];
                    commit_pred_taken <= pred_taken[head];
                    
                    // Free the entry
                    valid[head] <= 0;
                    ready[head] <= 0;
                    
                    // Branch misprediction detection
                    if (inst_type[head] == `INST_BR && (br_taken[head] != pred_taken[head])) begin
                        commit_flush        <= 1;
                        // If we wrongly predicted taken, we must flush to pc+4 (which we don't have stored here easily, wait)
                        // Actually, branch_unit computes br_target_out. If it's NOT taken, br_target_out is pc+4!
                        // So we can always just use br_target[head] as the flush target, because branch_unit
                        // will set br_target to pc+4 if the branch is not taken.
                        commit_flush_target <= br_target[head];
                    end
                    
                    head <= (head + 1) % `ROB_ENTRIES;
                end
                
                // ---- ISSUE ----
                if (can_issue) begin
                    valid[tail]     <= 1;
                    ready[tail]     <= 0;
                    dest_reg[tail]  <= issue_rd;
                    inst_type[tail] <= issue_inst_type;
                    pc[tail]        <= issue_pc;
                    pred_taken[tail]<= issue_pred_taken;
                    br_taken[tail]  <= 0;
                    
                    tail <= (tail + 1) % `ROB_ENTRIES;
                end
                
                // ---- COUNT MANAGEMENT ----
                if (can_issue && can_commit)
                    count <= count;       // issue + commit cancel out
                else if (can_issue)
                    count <= count + 1;   // only issue
                else if (can_commit)
                    count <= count - 1;   // only commit
            end
        end
    end

endmodule
