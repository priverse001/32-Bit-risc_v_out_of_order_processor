`timescale 1ns / 1ps
`include "../include/params.vh"

module cdb (
    // FU 0 (e.g., ALU)
    input  wire                      fu0_req,
    input  wire [`ROB_TAG_WIDTH-1:0]  fu0_tag,
    input  wire [`DATA_WIDTH-1:0]     fu0_data,
    input  wire                      fu0_br_taken,
    input  wire [`ADDR_WIDTH-1:0]     fu0_br_target,
    output wire                      fu0_ack,
    
    // FU 1 (e.g., Branch)
    input  wire                      fu1_req,
    input  wire [`ROB_TAG_WIDTH-1:0]  fu1_tag,
    input  wire [`DATA_WIDTH-1:0]     fu1_data,
    input  wire                      fu1_br_taken,
    input  wire [`ADDR_WIDTH-1:0]     fu1_br_target,
    output wire                      fu1_ack,
    
    // FU 2 (e.g., LSQ)
    input  wire                      fu2_req,
    input  wire [`ROB_TAG_WIDTH-1:0]  fu2_tag,
    input  wire [`DATA_WIDTH-1:0]     fu2_data,
    input  wire                      fu2_br_taken,
    input  wire [`ADDR_WIDTH-1:0]     fu2_br_target,
    output wire                      fu2_ack,
    
    // FU 3 (e.g., MDU)
    input  wire                      fu3_req,
    input  wire [`ROB_TAG_WIDTH-1:0]  fu3_tag,
    input  wire [`DATA_WIDTH-1:0]     fu3_data,
    input  wire                      fu3_br_taken,
    input  wire [`ADDR_WIDTH-1:0]     fu3_br_target,
    output wire                      fu3_ack,
    
    // Broadcast Outputs
    output reg                       cdb_valid,
    output reg  [`ROB_TAG_WIDTH-1:0]  cdb_tag,
    output reg  [`DATA_WIDTH-1:0]     cdb_data,
    output reg                       cdb_br_taken,
    output reg  [`ADDR_WIDTH-1:0]     cdb_br_target
);

    // Fixed priority: LSQ > Branch > MDU > ALU
    assign fu2_ack = fu2_req;
    assign fu1_ack = fu1_req && !fu2_req;
    assign fu3_ack = fu3_req && !fu2_req && !fu1_req;
    assign fu0_ack = fu0_req && !fu2_req && !fu1_req && !fu3_req;
    
    always @(*) begin
        cdb_valid = 0;
        cdb_tag = 0;
        cdb_data = 0;
        cdb_br_taken = 0;
        cdb_br_target = 0;
        
        if (fu2_req) begin
            cdb_valid = 1;
            cdb_tag = fu2_tag;
            cdb_data = fu2_data;
            cdb_br_taken = fu2_br_taken;
            cdb_br_target = fu2_br_target;
        end else if (fu1_req) begin
            cdb_valid = 1;
            cdb_tag = fu1_tag;
            cdb_data = fu1_data;
            cdb_br_taken = fu1_br_taken;
            cdb_br_target = fu1_br_target;
        end else if (fu3_req) begin
            cdb_valid = 1;
            cdb_tag = fu3_tag;
            cdb_data = fu3_data;
            cdb_br_taken = fu3_br_taken;
            cdb_br_target = fu3_br_target;
        end else if (fu0_req) begin
            cdb_valid = 1;
            cdb_tag = fu0_tag;
            cdb_data = fu0_data;
            cdb_br_taken = fu0_br_taken;
            cdb_br_target = fu0_br_target;
        end
    end

endmodule
