`timescale 1ns / 1ps
`include "../include/params.vh"

//-----------------------------------------------------------------------------
// AXI4-Lite Master Interface
// Translates simple (req/we/addr/wdata) memory requests into AXI4-Lite
// transactions.
//-----------------------------------------------------------------------------
module axi4_lite_master (
    input  wire                      clk,
    input  wire                      rst_n,

    // Core Memory Interface
    input  wire                      mem_req,
    input  wire                      mem_we,
    input  wire [`ADDR_WIDTH-1:0]     mem_addr,
    input  wire [`DATA_WIDTH-1:0]     mem_wdata,
    output reg  [`DATA_WIDTH-1:0]     mem_rdata,
    output reg                       mem_ack,

    // AXI4-Lite Write Address Channel
    output reg  [`ADDR_WIDTH-1:0]     m_axi_awaddr,
    output reg                       m_axi_awvalid,
    input  wire                      m_axi_awready,

    // AXI4-Lite Write Data Channel
    output reg  [`DATA_WIDTH-1:0]     m_axi_wdata,
    output wire [3:0]                m_axi_wstrb,
    output reg                       m_axi_wvalid,
    input  wire                      m_axi_wready,

    // AXI4-Lite Write Response Channel
    input  wire [1:0]                m_axi_bresp,
    input  wire                      m_axi_bvalid,
    output reg                       m_axi_bready,

    // AXI4-Lite Read Address Channel
    output reg  [`ADDR_WIDTH-1:0]     m_axi_araddr,
    output reg                       m_axi_arvalid,
    input  wire                      m_axi_arready,

    // AXI4-Lite Read Data Channel
    input  wire [`DATA_WIDTH-1:0]     m_axi_rdata,
    input  wire [1:0]                m_axi_rresp,
    input  wire                      m_axi_rvalid,
    output reg                       m_axi_rready
);

    assign m_axi_wstrb = 4'b1111; // Always writing 32-bits for simplicity right now

    // State Machine
    localparam IDLE  = 3'd0,
               WADDR = 3'd1,
               WDATA = 3'd2,
               WRESP = 3'd3,
               RADDR = 3'd4,
               RDATA = 3'd5;
               
    reg [2:0] state;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            mem_ack <= 0;
            mem_rdata <= 0;
            
            m_axi_awaddr <= 0;
            m_axi_awvalid <= 0;
            
            m_axi_wdata <= 0;
            m_axi_wvalid <= 0;
            
            m_axi_bready <= 0;
            
            m_axi_araddr <= 0;
            m_axi_arvalid <= 0;
            
            m_axi_rready <= 0;
        end else begin
            mem_ack <= 0; // default pulse

            case (state)
                IDLE: begin
                    if (mem_req && !mem_ack) begin // prevent re-triggering while ack is high
                        if (mem_we) begin
                            m_axi_awaddr <= mem_addr;
                            m_axi_awvalid <= 1;
                            m_axi_wdata <= mem_wdata;
                            m_axi_wvalid <= 1;
                            state <= WADDR;
                        end else begin
                            m_axi_araddr <= mem_addr;
                            m_axi_arvalid <= 1;
                            state <= RADDR;
                        end
                    end
                end

                // --- WRITE FSM ---
                WADDR: begin
                    // Wait for awready. Data channel can handshake simultaneously, but we keep it sequential for safety
                    if (m_axi_awready && m_axi_awvalid) begin
                        m_axi_awvalid <= 0;
                        state <= WDATA;
                    end
                end
                
                WDATA: begin
                    if (m_axi_wready && m_axi_wvalid) begin
                        m_axi_wvalid <= 0;
                        m_axi_bready <= 1;
                        state <= WRESP;
                    end
                end
                
                WRESP: begin
                    if (m_axi_bvalid && m_axi_bready) begin
                        m_axi_bready <= 0;
                        mem_ack <= 1;
                        state <= IDLE;
                    end
                end

                // --- READ FSM ---
                RADDR: begin
                    if (m_axi_arready && m_axi_arvalid) begin
                        m_axi_arvalid <= 0;
                        m_axi_rready <= 1;
                        state <= RDATA;
                    end
                end
                
                RDATA: begin
                    if (m_axi_rvalid && m_axi_rready) begin
                        m_axi_rready <= 0;
                        mem_rdata <= m_axi_rdata;
                        mem_ack <= 1;
                        state <= IDLE;
                    end
                end
                
                default: state <= IDLE;
            endcase
        end
    end

endmodule
