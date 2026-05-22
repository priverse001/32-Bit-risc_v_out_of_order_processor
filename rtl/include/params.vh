`ifndef PARAMS_VH
`define PARAMS_VH

// Reorder Buffer (ROB) Parameters
`define ROB_ENTRIES 16
`define ROB_TAG_WIDTH $clog2(`ROB_ENTRIES)

// Register File Parameters
`define NUM_REGS 32
`define REG_ADDR_WIDTH 5
`define DATA_WIDTH 32

// Reservation Station Parameters
`define RS_ALU_ENTRIES 8
`define RS_ALU_IDX_WIDTH $clog2(`RS_ALU_ENTRIES)

`define RS_BR_ENTRIES 4
`define RS_BR_IDX_WIDTH $clog2(`RS_BR_ENTRIES)

`define RS_LSQ_ENTRIES 8
`define RS_LSQ_IDX_WIDTH $clog2(`RS_LSQ_ENTRIES)

`define RS_MDU_ENTRIES 4
`define RS_MDU_IDX_WIDTH $clog2(`RS_MDU_ENTRIES)

// PC and Memory
`define ADDR_WIDTH 32
`define MEM_ADDR_WIDTH 12 // 4KB for test

`endif // PARAMS_VH
