# Product Requirements Document (PRD): Out-of-Order RISC-V Execution Engine

## 1. Executive Summary
The goal of this project is to design and implement a high-performance, **Out-of-Order (OoO) Execution Engine** for the **RISC-V RV32I** Instruction Set Architecture (ISA). The engine will utilize **Tomasulo's Algorithm** to achieve dynamic instruction scheduling, effectively mitigating data hazards (RAW, WAR, WAW) and maximizing instruction-level parallelism (ILP). The design will be authored in **Verilog HDL** and optimized for deployment on Xilinx FPGAs using the **Vivado Design Suite**.

## 2. Project Objectives
*   **Dynamic Scheduling**: Implement Tomasulo's algorithm to allow instructions to execute as soon as their operands are available, regardless of program order.
*   **Hazard Management**: Eliminate WAR and WAW hazards through register renaming via Reservation Stations and handle RAW hazards via the Common Data Bus (CDB).
*   **Speculative Execution**: Incorporate a Reorder Buffer (ROB) to support branch speculation and ensure precise exceptions.
*   **FPGA Optimization**: Ensure the RTL is synthesizable and optimized for Xilinx 7-series or UltraScale+ architectures.

## 3. Architectural Specifications

### 3.1 Instruction Set Support
The engine shall support the **RV32I Base Integer Instruction Set**, including:
*   **Arithmetic/Logic**: `ADD`, `SUB`, `SLL`, `SLT`, `SLTU`, `XOR`, `SRL`, `SRA`, `OR`, `AND` (and their immediate variants).
*   **Memory Operations**: `LB`, `LH`, `LW`, `LBU`, `LHU`, `SB`, `SH`, `SW`.
*   **Control Flow**: `BEQ`, `BNE`, `BLT`, `BGE`, `BLTU`, `BGEU`, `JAL`, `JALR`.
*   **System**: `LUI`, `AUIPC`.

### 3.2 Microarchitecture Components
The execution engine is divided into several critical hardware modules:

| Module | Description | Key Features |
| :--- | :--- | :--- |
| **Instruction Buffer** | Decouples the front-end fetch from the execution engine. | FIFO-based, 16-32 entries deep. |
| **Issue/Dispatch Logic** | Decodes instructions and allocates entries in RS and ROB. | Checks for structural hazards (RS/ROB full). |
| **Reservation Stations (RS)** | Holds instructions waiting for operands. | Distributed buffers for ALU, Branch, and Mem units. |
| **Reorder Buffer (ROB)** | Maintains program order for "Commit" stage. | Supports speculative execution and register renaming. |
| **Functional Units (FU)** | Executes the actual operations. | Pipelined ALU, Multiplier (optional), and Load/Store unit. |
| **Common Data Bus (CDB)** | Broadcasts results to all RS and the ROB. | High-fanout broadcast network with priority arbitration. |
| **Register File (RF)** | Physical storage for the 32 RISC-V registers. | Dual-read, single-write ports (minimum). |

### 3.3 Detailed Module Specifications

#### 3.3.1 Reorder Buffer (ROB)
The ROB is a circular buffer that tracks the status of all "in-flight" instructions.
*   **Entry Fields**: `Valid`, `Instruction Type`, `Destination Register`, `Value`, `Done Status`, `Exception/Mispredict Flag`.
*   **Depth**: 16 to 64 entries (configurable via Verilog parameters).
*   **Interface**:
    *   `rob_alloc_idx`: Index provided to the Issue stage.
    *   `rob_commit_data`: Data sent to the architectural Register File.
    *   `rob_flush`: Signal to clear speculative state on branch misprediction.

#### 3.3.2 Reservation Stations (RS)
Each RS entry acts as a virtual register for an instruction waiting to execute.
*   **Entry Fields**: `Busy`, `Opcode`, `Vj` (Value of source 1), `Vk` (Value of source 2), `Qj` (ROB tag for source 1), `Qk` (ROB tag for source 2), `Dest` (ROB tag for destination).
*   **Dispatch Logic**: If a source register is not ready in the Register File, the RS captures the ROB tag (`Qj`/`Qk`) and waits for the CDB broadcast.

#### 3.3.3 Common Data Bus (CDB)
The CDB is the backbone of the Tomasulo engine.
*   **Signals**: `cdb_tag` (ROB index), `cdb_data` (Result value), `cdb_valid`.
*   **Arbitration**: A fixed-priority or round-robin arbiter handles cases where multiple FUs complete in the same cycle.

#### 3.3.4 Load/Store Queue (LSQ)
To handle memory operations out-of-order while maintaining consistency:
*   **Load Queue**: Monitors the Store Queue for address matches (Store-to-Load Forwarding).
*   **Store Queue**: Buffers writes until the instruction reaches the head of the ROB (Commit stage).
*   **Memory Disambiguation**: Prevents a load from bypassing a store to the same address.

## 4. Functional Requirements

### 4.1 Pipeline Stages
The engine shall follow a modified Tomasulo pipeline:
1.  **Issue**: Instruction is fetched from the buffer, decoded, and dispatched to a free Reservation Station and ROB entry. Register renaming occurs here.
2.  **Execute**: Once all operands are available (monitored via CDB), the instruction begins execution in its assigned FU.
3.  **Write Result**: FU completes execution and broadcasts the result on the CDB. RS entries are freed, and the ROB entry is updated.
4.  **Commit (Retire)**: The ROB ensures instructions update the architectural Register File in strict program order.

### 4.2 Hazard Handling
*   **RAW (Read-After-Write)**: Resolved by stalling in RS until the producer broadcasts the value on the CDB.
*   **WAR (Write-After-Read)**: Eliminated by register renaming; the RS holds the value or a tag, not the register name.
*   **WAW (Write-After-Write)**: Eliminated by the ROB; only the latest instruction in program order updates the architectural state.

### 4.3 Branch Handling
*   **Branch Prediction**: A simple Branch Target Buffer (BTB) or Bimodal Predictor shall be implemented.
*   **Misprediction Recovery**: Upon a mispredicted branch, the ROB shall flush all speculative instructions and reset the front-end to the correct PC.

## 5. Interface Specifications (Top-Level)

| Signal Name | Direction | Width | Description |
| :--- | :--- | :--- | :--- |
| `clk` | Input | 1 | System clock. |
| `rst_n` | Input | 1 | Asynchronous active-low reset. |
| `instr_in` | Input | 32 | Instruction from Fetch unit. |
| `instr_pc` | Input | 32 | Program Counter of the incoming instruction. |
| `instr_valid` | Input | 1 | High when `instr_in` is valid. |
| `ready_for_instr` | Output | 1 | Back-pressure signal to Fetch unit. |
| `mem_addr` | Output | 32 | Memory address for Load/Store. |
| `mem_wdata` | Output | 32 | Data to be written to memory. |
| `mem_rdata` | Input | 32 | Data read from memory. |
| `mem_req` | Output | 1 | Memory request signal. |
| `mem_ack` | Input | 1 | Memory acknowledgment/ready signal. |
| `pc_out` | Output | 32 | Current Program Counter for commit. |
| `debug_reg_idx` | Input | 5 | Register index for debug probing. |
| `debug_reg_val` | Output | 32 | Value of the probed register. |

## 6. Vivado-Specific Implementation Details

### 6.1 Project Structure
*   **Source Files**: Organized into `rtl/`, `hdl/`, and `ip/` directories.
*   **IP Cores**: Use Xilinx **Block RAM (BRAM)** for Instruction and Data memories to ensure efficient resource usage.
*   **Constraints**: A `.xdc` file must define the target clock period (e.g., `create_clock -period 10.000 [get_ports clk]`).

### 6.2 Synthesis & Implementation Strategy
*   **Hierarchy**: Maintain a clean module hierarchy to allow Vivado's "Out-of-Context" (OOC) synthesis for faster iteration.
*   **Optimization**: Use `DONT_TOUCH` or `KEEP` attributes sparingly on critical control signals (like CDB tags) to prevent over-optimization that might break the logic.
*   **Timing Closure**: Pay close attention to the CDB fanout. If timing fails, implement a **CDB Pipeline Stage** or use a **Hierarchical CDB** structure.

### 6.3 Debugging with Vivado ILA
*   The design shall include pre-defined debug nets for the **Integrated Logic Analyzer (ILA)**:
    *   `rob_head`, `rob_tail`
    *   `cdb_valid`, `cdb_tag`
    *   `rs_busy_vector`
    *   `current_state_issue`


## 6. Design Constraints & Performance Targets
*   **Target Device**: Xilinx Artix-7 (e.g., XC7A100T) or Kintex-7.
*   **Clock Frequency**: Minimum **100 MHz** on Artix-7.
*   **Resource Utilization**:
    *   LUTs: < 15,000
    *   Flip-Flops: < 10,000
    *   BRAMs: < 10 (for Instruction/Data cache simulation).
*   **Latency**:
    *   Simple ALU: 1 cycle.
    *   Load/Store: 2-3 cycles (assuming cache hit).

## 7. Verification & Testing Plan

### 7.1 Simulation Strategy
*   **Unit Testing**: Individual testbenches for RS, ROB, and CDB.
*   **Integration Testing**: Full engine simulation using RISC-V Assembly test suites (e.g., `riscv-tests`).
*   **Waveform Analysis**: Use Vivado Simulator (XSIM) to verify tag broadcasting and ROB retirement.

### 7.2 Hardware-in-the-Loop
*   **ILA (Integrated Logic Analyzer)**: Use Xilinx ILA cores to monitor the CDB and ROB status in real-time on the FPGA.
*   **UART Debug**: Implement a UART module to dump register states after program execution.

## 8. Implementation Roadmap
1.  **Phase 1**: Design the ROB and Register Alias Table (RAT).
2.  **Phase 2**: Implement Reservation Stations and the Common Data Bus.
3.  **Phase 3**: Integrate Functional Units (ALU, Branch).
4.  **Phase 4**: Implement Load/Store Queue with memory disambiguation.
5.  **Phase 5**: Full system integration and Vivado timing closure.

## 9. Documentation Requirements
*   **RTL Block Diagrams**: Detailed schematics of the data path.
*   **Timing Diagrams**: Visualization of the Issue-Execute-Write-Commit flow.
*   **User Guide**: Instructions for running simulations and synthesizing in Vivado.

## 9. References

[1] Tomasulo's algorithm - Wikipedia. (n.d.). Retrieved from https://en.wikipedia.org/wiki/Tomasulo%27s_algorithm
[2] Vaidya, S. (n.d.). Implementing Tomasulo's Algorithm. Retrieved from https://sujalvaidya.pages.dev/projects/tomasulo/
[3] Skyzh. (n.d.). RISCV-Simulator. Retrieved from https://github.com/skyzh/RISCV-Simulator/blob/out-of-order/README.md
[4] Register Transfer Level Design of 32-Bit RISC-V Out-of-Order ... (2026, January 31). Retrieved from https://www.researchgate.net/publication/400213114_Register_Transfer_Level_Design_of_32-Bit_RISC-V_Out-of-Order_Processor
