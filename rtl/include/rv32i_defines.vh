`ifndef RV32I_DEFINES_VH
`define RV32I_DEFINES_VH

// Opcodes (7 bits)
`define OPCODE_LOAD     7'b0000011
`define OPCODE_STORE    7'b0100011
`define OPCODE_BRANCH   7'b1100011
`define OPCODE_JALR     7'b1100111
`define OPCODE_JAL      7'b1101111
`define OPCODE_OP_IMM   7'b0010011
`define OPCODE_OP       7'b0110011
`define OPCODE_LUI      7'b0110111
`define OPCODE_AUIPC    7'b0010111

// funct3 for Branch
`define F3_BEQ  3'b000
`define F3_BNE  3'b001
`define F3_BLT  3'b100
`define F3_BGE  3'b101
`define F3_BLTU 3'b110
`define F3_BGEU 3'b111

// funct3 for Load
`define F3_LB   3'b000
`define F3_LH   3'b001
`define F3_LW   3'b010
`define F3_LBU  3'b100
`define F3_LHU  3'b101

// funct3 for Store
`define F3_SB   3'b000
`define F3_SH   3'b001
`define F3_SW   3'b010

// funct3 for OP / OP-IMM
`define F3_ADD  3'b000 // SUB is also 000
`define F3_SLL  3'b001
`define F3_SLT  3'b010
`define F3_SLTU 3'b011
`define F3_XOR  3'b100
`define F3_SRL  3'b101 // SRA is also 101
`define F3_OR   3'b110
`define F3_AND  3'b111

// funct7 modifiers for OP / OP-IMM
`define F7_NORM 7'b0000000
`define F7_ALT  7'b0100000 // Used for SUB and SRA
`define F7_M    7'b0000001 // Used for RV32M Multiply/Divide

// Internal Execution Unit Operation Codes
// Used by ALU / Branch unit to know exactly what to do
`define ALU_ADD  4'd0
`define ALU_SUB  4'd1
`define ALU_SLL  4'd2
`define ALU_SLT  4'd3
`define ALU_SLTU 4'd4
`define ALU_XOR  4'd5
`define ALU_SRL  4'd6
`define ALU_SRA  4'd7
`define ALU_OR   4'd8
`define ALU_AND  4'd9
`define ALU_LUI  4'd10
`define ALU_AUIPC 4'd11

`define BR_BEQ   4'd0
`define BR_BNE   4'd1
`define BR_BLT   4'd2
`define BR_BGE   4'd3
`define BR_BLTU  4'd4
`define BR_BGEU  4'd5
`define BR_JUMP  4'd6 // JAL, JALR

// Instruction Type Encoding (Internal)
`define INST_ALU 3'd0
`define INST_BR  3'd1
`define INST_LD  3'd2
`define INST_ST  3'd3
`define INST_MDU 3'd4

// MDU Opcodes (Internal)
`define MDU_MUL    3'b000
`define MDU_MULH   3'b001
`define MDU_MULHSU 3'b010
`define MDU_MULHU  3'b011
`define MDU_DIV    3'b100
`define MDU_DIVU   3'b101
`define MDU_REM    3'b110
`define MDU_REMU   3'b111

`endif // RV32I_DEFINES_VH
