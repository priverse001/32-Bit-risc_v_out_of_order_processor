`timescale 1ns / 1ps
`include "../include/params.vh"

//-----------------------------------------------------------------------------
// AXI4-Lite Master with Clock Domain Crossing (CDC)
// Wraps the AXI4-Lite master state machine with asynchronous FIFOs so the
// core can run on a high-speed clock while memory runs on a system clock.
//
// IMPORTANT: All wires MUST be declared before first use to avoid
// Verilog implicit 1-bit wire bugs.
//-----------------------------------------------------------------------------
module axi4_lite_master_cdc (
    // Core Domain
    input  wire                      core_clk,
    input  wire                      core_rst_n,
    
    input  wire                      core_mem_req,
    input  wire                      core_mem_we,
    input  wire [`ADDR_WIDTH-1:0]     core_mem_addr,
    input  wire [`DATA_WIDTH-1:0]     core_mem_wdata,
    output wire [`DATA_WIDTH-1:0]     core_mem_rdata,
    output wire                      core_mem_ack,
    
    // AXI Domain
    input  wire                      axi_clk,
    input  wire                      axi_rst_n,
    
    output wire [`ADDR_WIDTH-1:0]     m_axi_awaddr,
    output wire                      m_axi_awvalid,
    input  wire                      m_axi_awready,
    output wire [`DATA_WIDTH-1:0]     m_axi_wdata,
    output wire [3:0]                m_axi_wstrb,
    output wire                      m_axi_wvalid,
    input  wire                      m_axi_wready,
    input  wire [1:0]                m_axi_bresp,
    input  wire                      m_axi_bvalid,
    output wire                      m_axi_bready,
    output wire [`ADDR_WIDTH-1:0]     m_axi_araddr,
    output wire                      m_axi_arvalid,
    input  wire                      m_axi_arready,
    input  wire [`DATA_WIDTH-1:0]     m_axi_rdata,
    input  wire [1:0]                m_axi_rresp,
    input  wire                      m_axi_rvalid,
    output wire                      m_axi_rready
);

    // Internal wire declarations
    localparam REQ_WIDTH = 1 + `ADDR_WIDTH + `DATA_WIDTH;

    // Request FIFO signals
    wire                 req_fifo_full;
    wire                 req_fifo_empty;
    wire [REQ_WIDTH-1:0] req_fifo_wdata;
    wire [REQ_WIDTH-1:0] req_fifo_rdata;
    wire                 core_req_push;

    // AXI-side unpacked request signals
    wire                  axi_mem_req;
    wire                  axi_mem_we;
    wire [`ADDR_WIDTH-1:0] axi_mem_addr;
    wire [`DATA_WIDTH-1:0] axi_mem_wdata;
    wire                  axi_mem_ack;
    wire [`DATA_WIDTH-1:0] axi_mem_rdata;
    wire                  axi_req_pop;
    wire                  axi_resp_push;

    // Response FIFO signals
    wire                  resp_fifo_full;
    wire                  resp_fifo_empty;
    wire [`DATA_WIDTH-1:0] resp_fifo_rdata;

    // Core-side ack signals
    wire                  core_mem_ack_int;
    wire                  core_resp_pop;

    // Wire assignments
    assign req_fifo_wdata = {core_mem_we, core_mem_addr, core_mem_wdata};
    assign axi_mem_req    = !req_fifo_empty;
    assign axi_mem_we     = req_fifo_rdata[REQ_WIDTH-1];
    assign axi_mem_addr   = req_fifo_rdata[REQ_WIDTH-2:`DATA_WIDTH];
    assign axi_mem_wdata  = req_fifo_rdata[`DATA_WIDTH-1:0];
    assign axi_req_pop    = axi_mem_ack;
    assign axi_resp_push  = axi_mem_ack;

    // Core-side handshake logic
    reg core_req_pending;
    reg resp_consumed;

    assign core_mem_ack_int = !resp_fifo_empty && core_req_pending && !resp_consumed;
    assign core_mem_ack     = core_mem_ack_int;
    assign core_mem_rdata   = resp_fifo_rdata;
    assign core_resp_pop    = core_mem_ack_int;
    assign core_req_push    = (core_mem_req && !core_req_pending && !req_fifo_full);

    always @(posedge core_clk or negedge core_rst_n) begin
        if (!core_rst_n) begin
            core_req_pending <= 0;
            resp_consumed <= 0;
        end else begin
            if (resp_fifo_empty)
                resp_consumed <= 0;

            if (core_mem_req && !core_req_pending && !req_fifo_full)
                core_req_pending <= 1;
            else if (core_mem_ack_int) begin
                core_req_pending <= 0;
                resp_consumed <= 1;
            end
        end
    end

    // Request FIFO: Core clock domain → AXI clock domain
    async_fifo #(
        .WIDTH(REQ_WIDTH),
        .DEPTH_LOG2(3)
    ) u_req_fifo (
        .wr_clk(core_clk), .wr_rst_n(core_rst_n),
        .wr_en(core_req_push), .wr_data(req_fifo_wdata), .wr_full(req_fifo_full),
        .rd_clk(axi_clk), .rd_rst_n(axi_rst_n),
        .rd_en(axi_req_pop), .rd_data(req_fifo_rdata), .rd_empty(req_fifo_empty)
    );

    // AXI4-Lite Master (runs on axi_clk)
    axi4_lite_master u_axi_master (
        .clk(axi_clk), .rst_n(axi_rst_n),
        .mem_req(axi_mem_req), .mem_we(axi_mem_we),
        .mem_addr(axi_mem_addr), .mem_wdata(axi_mem_wdata),
        .mem_rdata(axi_mem_rdata), .mem_ack(axi_mem_ack),
        .m_axi_awaddr(m_axi_awaddr), .m_axi_awvalid(m_axi_awvalid), .m_axi_awready(m_axi_awready),
        .m_axi_wdata(m_axi_wdata), .m_axi_wstrb(m_axi_wstrb), .m_axi_wvalid(m_axi_wvalid), .m_axi_wready(m_axi_wready),
        .m_axi_bresp(m_axi_bresp), .m_axi_bvalid(m_axi_bvalid), .m_axi_bready(m_axi_bready),
        .m_axi_araddr(m_axi_araddr), .m_axi_arvalid(m_axi_arvalid), .m_axi_arready(m_axi_arready),
        .m_axi_rdata(m_axi_rdata), .m_axi_rresp(m_axi_rresp), .m_axi_rvalid(m_axi_rvalid), .m_axi_rready(m_axi_rready)
    );

    // Response FIFO: AXI clock domain → Core clock domain
    async_fifo #(
        .WIDTH(`DATA_WIDTH),
        .DEPTH_LOG2(3)
    ) u_resp_fifo (
        .wr_clk(axi_clk), .wr_rst_n(axi_rst_n),
        .wr_en(axi_resp_push), .wr_data(axi_mem_rdata), .wr_full(resp_fifo_full),
        .rd_clk(core_clk), .rd_rst_n(core_rst_n),
        .rd_en(core_resp_pop), .rd_data(resp_fifo_rdata), .rd_empty(resp_fifo_empty)
    );

endmodule
