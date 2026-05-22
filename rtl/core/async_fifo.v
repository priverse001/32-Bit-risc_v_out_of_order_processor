`timescale 1ns / 1ps

//-----------------------------------------------------------------------------
// Asynchronous FIFO for Clock Domain Crossing (CDC)
// Uses Gray code pointers and dual-rank synchronizers to safely pass data
// between two asynchronous clock domains.
//-----------------------------------------------------------------------------
module async_fifo #(
    parameter WIDTH = 32,
    parameter DEPTH_LOG2 = 4 // 16 entries
)(
    // Write Domain
    input  wire                  wr_clk,
    input  wire                  wr_rst_n,
    input  wire                  wr_en,
    input  wire [WIDTH-1:0] wr_data,
    output wire                  wr_full,
    
    // Read Domain
    input  wire                  rd_clk,
    input  wire                  rd_rst_n,
    input  wire                  rd_en,
    output wire [WIDTH-1:0] rd_data,
    output wire                  rd_empty
);

    localparam DEPTH = 1 << DEPTH_LOG2;

    // Memory array
    reg [WIDTH-1:0] mem [0:DEPTH-1];

    // Pointers (Binary and Gray)
    reg [DEPTH_LOG2:0] wr_ptr_bin, wr_ptr_gray;
    reg [DEPTH_LOG2:0] rd_ptr_bin, rd_ptr_gray;

    // Synchronizers
    reg [DEPTH_LOG2:0] wr_ptr_gray_sync1, wr_ptr_gray_sync2;
    reg [DEPTH_LOG2:0] rd_ptr_gray_sync1, rd_ptr_gray_sync2;

    // Next pointer values
    wire [DEPTH_LOG2:0] wr_ptr_bin_next = wr_ptr_bin + 1'b1;
    wire [DEPTH_LOG2:0] wr_ptr_gray_next = wr_ptr_bin_next ^ (wr_ptr_bin_next >> 1);
    
    wire [DEPTH_LOG2:0] rd_ptr_bin_next = rd_ptr_bin + 1'b1;
    wire [DEPTH_LOG2:0] rd_ptr_gray_next = rd_ptr_bin_next ^ (rd_ptr_bin_next >> 1);

    // Full / Empty generation
    assign wr_full = (wr_ptr_gray_next == {~rd_ptr_gray_sync2[DEPTH_LOG2:DEPTH_LOG2-1], rd_ptr_gray_sync2[DEPTH_LOG2-2:0]});
    assign rd_empty = (rd_ptr_gray == wr_ptr_gray_sync2);

    // Read Data (First-Word Fall-Through behavior logic could be added, but standard FIFO here)
    assign rd_data = mem[rd_ptr_bin[DEPTH_LOG2-1:0]];

    // --------------------------------------------------------
    // Write Domain Logic
    // --------------------------------------------------------
    always @(posedge wr_clk or negedge wr_rst_n) begin
        if (!wr_rst_n) begin
            wr_ptr_bin <= 0;
            wr_ptr_gray <= 0;
        end else begin
            if (wr_en && !wr_full) begin
                mem[wr_ptr_bin[DEPTH_LOG2-1:0]] <= wr_data;
                wr_ptr_bin <= wr_ptr_bin_next;
                wr_ptr_gray <= wr_ptr_gray_next;
            end
        end
    end

    // Synchronize Read Pointer to Write Domain
    always @(posedge wr_clk or negedge wr_rst_n) begin
        if (!wr_rst_n) begin
            rd_ptr_gray_sync1 <= 0;
            rd_ptr_gray_sync2 <= 0;
        end else begin
            rd_ptr_gray_sync1 <= rd_ptr_gray;
            rd_ptr_gray_sync2 <= rd_ptr_gray_sync1;
        end
    end

    // --------------------------------------------------------
    // Read Domain Logic
    // --------------------------------------------------------
    always @(posedge rd_clk or negedge rd_rst_n) begin
        if (!rd_rst_n) begin
            rd_ptr_bin <= 0;
            rd_ptr_gray <= 0;
        end else begin
            if (rd_en && !rd_empty) begin
                rd_ptr_bin <= rd_ptr_bin_next;
                rd_ptr_gray <= rd_ptr_gray_next;
            end
        end
    end

    // Synchronize Write Pointer to Read Domain
    always @(posedge rd_clk or negedge rd_rst_n) begin
        if (!rd_rst_n) begin
            wr_ptr_gray_sync1 <= 0;
            wr_ptr_gray_sync2 <= 0;
        end else begin
            wr_ptr_gray_sync1 <= wr_ptr_gray;
            wr_ptr_gray_sync2 <= wr_ptr_gray_sync1;
        end
    end

endmodule
