# RISC-V Out-of-Order Engine: Comprehensive Study Guide

This document is a deep-dive study guide designed to help you thoroughly understand every component, architectural decision, and hardware mechanism implemented in your Out-of-Order (OoO) RISC-V processor.

---

## Part 1: Tomasulo's Algorithm & Out-of-Order Execution

### 1.1 The Problem with In-Order Pipelines
In a standard 5-stage pipeline, if an instruction takes a long time to compute (like a 32-cycle Division) or wait for memory (like a Cache Miss), the entire processor stalls. Instructions behind it cannot execute, even if they are completely independent. This wastes clock cycles and reduces Instruction-Level Parallelism (ILP).

### 1.2 The Tomasulo Solution
Tomasulo's Algorithm solves this by **decoupling Decode from Execution**.
Instead of waiting in the decode stage, instructions are decoded and immediately pushed into a **Reservation Station (RS)**. If the instruction has its variables ready, it goes to the execution unit. If it is waiting on a previous instruction to finish, it "listens" to a global broadcast bus (the Common Data Bus) for its variables.
This allows later instructions to bypass stalled instructions!

### 1.3 Key Components of the Engine
*   **Reorder Buffer (ROB) `rob.v`**: Because instructions execute out of order, they might finish out of order. If an exception occurs, the processor state would be corrupted. The ROB is a circular FIFO queue that tracks every instruction in original program order. Instructions only "Commit" their results to the actual Register File when they reach the head of the ROB.
*   **Reservation Stations `rs.v`**: These are holding pens in front of the Arithmetic Logic Unit (ALU), Branch Unit, Load/Store Queue (LSQ), and Multiply/Divide Unit (MDU). They hold the instruction's operation code and its operands (`Vj`, `Vk`). If an operand isn't ready, it holds a "tag" (`Qj`, `Qk`) indicating which future instruction will produce the data.
*   **Register Alias Table (RAT) `rat.v`**: This solves Write-After-Write (WAW) and Write-After-Read (WAR) hazards via "Register Renaming". When an instruction decodes, the RAT maps its destination register (e.g., `x5`) to a unique ROB tag. Later instructions needing `x5` will look at the RAT and use the ROB tag instead of the physical register, severing false dependencies.
*   **Common Data Bus (CDB) `cdb.v`**: When an execution unit finishes, it broadcasts its result and its ROB tag on the CDB. Every Reservation Station listens to the CDB. If a station's `Qj` or `Qk` matches the broadcasted tag, it grabs the data. If both operands are now ready, the instruction fires!

---

## Part 2: The Machine-Learning Branch Predictor

### 2.1 The Problem with Branches
If a branch (`if/else`) is decoded, the processor doesn't know which path to fetch next until the branch actually executes. If it waits, it wastes cycles. If it guesses wrong, it has to throw away all the instructions it fetched (a pipeline flush). 
Standard processors use a 2-bit counter to guess branches, but these fail on complex patterns.

### 2.2 The Perceptron Neural Network (`perceptron_bpu.v`)
To make this project an industry standout, we implemented a **Hardware Neural Network** (a Perceptron) to predict branches!
*   **Global History Register (GHR)**: An 8-bit shift register that tracks whether the last 8 branches in the program were taken (1) or not taken (0). This provides "context".
*   **Weight Table**: A memory array of 8-bit signed integers. 
*   **Inference**: When a branch is fetched, its PC address is hashed to select a row of weights. The BPU computes the Dot-Product of the weights against the GHR. If the sum is positive, the AI predicts "Taken". If negative, "Not Taken".
*   **Hardware Training**: When the Reorder Buffer commits a branch, it checks if the AI was correct. If it was, the ROB sends a signal to increase the weights that contributed to the correct answer. If the AI was wrong, it flushes the pipeline and decreases the weights. The processor literally *learns* the program's behavior in real-time!

---

## Part 3: Dual-Clock AXI4-Lite Memory Subsystem

### 3.1 The Problem with Single-Cycle Memory
Academic projects often use internal BRAM that responds in 1 clock cycle. Real-world processors must talk to DDR RAM via system buses (like ARM's AMBA AXI protocol). Furthermore, the processor usually runs at a much higher clock speed (e.g., 500MHz) than the memory bus (e.g., 200MHz). 

### 3.2 Clock Domain Crossing (CDC) & FIFOs (`async_fifo.v`)
To safely send data between two different clock frequencies, we built an **Asynchronous FIFO**. 
It uses "Gray Code" pointers. Gray code is a binary numeral system where two successive values differ in only one bit. By passing Gray-coded read/write pointers through dual-rank synchronizers (two flip-flops in a row), we eliminate "metastability" (the risk of a signal getting stuck halfway between 0 and 1 when crossing clocks).

### 3.3 AXI4-Lite Master (`axi4_lite_master_cdc.v`)
We wrapped our memory requests into a standard AXI4-Lite Master state machine. 
It operates 5 independent channels: Write Address, Write Data, Write Response, Read Address, and Read Data. By implementing this, your processor IP can be dragged and dropped into a professional Xilinx Vivado Block Design alongside standard industrial IP cores.

---

## Part 4: The M-Extension (Hardware Math)

### 4.1 RV32M Integration (`mdu.v`)
We fully implemented the RISC-V Hardware Multiply/Divide Extension. 
*   **Multi-Cycle Division**: The divider uses an iterative "shift-and-subtract" algorithm that takes 32 clock cycles to complete. 
*   **Validating the Architecture**: This is the ultimate test of your Out-of-Order engine. While the MDU is busy for 32 cycles dividing a number, the decoder pushes the instruction into the `RS_MDU` and immediately continues fetching and decoding. The ALU and Branch units will execute dozens of instructions *around* the division in the background!

---

## Part 5: Hardware Performance Counters

### 5.1 Real-Time Analytics
To prove your processor's efficiency on an FPGA, we exposed four 64-bit hardware counters to the top-level ports (`top.v`):
1.  `perf_cycles`: Elapsed clock cycles.
2.  `perf_instret`: Total Instructions Retired.
3.  `perf_branches`: Total branches committed.
4.  `perf_mispredicts`: Total AI mispredictions.

By wiring these to a Xilinx Integrated Logic Analyzer (ILA), you can calculate two critical metrics live in hardware:
*   **IPC (Instructions Per Cycle) = `perf_instret / perf_cycles`** (Aim for >0.8 on OoO cores).
*   **AI Accuracy = `1.0 - (perf_mispredicts / perf_branches)`**.
