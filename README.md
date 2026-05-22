# RV32IM Out-of-Order Processor

![Language](https://img.shields.io/badge/Language-Verilog-blue)
![ISA](https://img.shields.io/badge/ISA-RV32IM-green)
![License](https://img.shields.io/badge/License-MIT-yellow)
![Target](https://img.shields.io/badge/FPGA-Artix--7%20xc7a100t-orange)
![Simulator](https://img.shields.io/badge/Simulator-Vivado%20XSim-purple)

A fully-pipelined, superscalar-capable **RISC-V RV32IM out-of-order processor** implemented in Verilog, using the **Tomasulo algorithm** with a **Perceptron branch predictor** and dual clock-domain AXI4-Lite memory interfaces.

## Features

- **Tomasulo Out-of-Order Engine** — Reservation Stations, ROB, RAT, CDB
- **RV32IM ISA** — Full base integer (RV32I) plus Multiply/Divide extension (RV32M)
- **Speculative Execution** — Perceptron branch predictor with speculative dispatch
- **Precise Interrupts** — In-order commit through Reorder Buffer (ROB)
- **Dual Clock Domains** — Core (100 MHz) / AXI (50 MHz) bridged via async FIFOs
- **AXI4-Lite Master** — Separate instruction and data memory interfaces
- **Hardware Performance Counters** — Cycles, instructions retired, branches, mispredicts
- **Self-Checking Testbench** — 9-test program covering ALU, MDU, and LSQ paths

## Architecture Overview

```
                         +------------------+
                         |  Perceptron BPU  |
                         +--------+---------+
                                  |
           +----------------------v---------------------+
           |              Fetch Unit (PC)               |
           +----------------------+---------------------+
                                  |  AXI4-Lite (i-fetch)
                                  v
           +----------------------+---------------------+
           |         Decode / Dispatch Unit             |
           |  (RAT rename, ROB alloc, RS dispatch)      |
           +----+----------+-----------+----------+-----+
                |          |           |          |
           ALU RS      Branch RS    LSQ RS    MDU RS
                |          |           |          |
             +--+--+    +--+--+    +--+--+    +--+--+
             | ALU |    | BRU |    | LSQ |    | MDU |
             +--+--+    +--+--+    +--+--+    +--+--+
                |          |       AXI4-Lite   |
                +----------+---(d-mem)--+------+
                                        |
                           +------------v-----------+
                           |    Common Data Bus     |
                           |  (CDB arbiter 4-in-1)  |
                           +------------+-----------+
                                        |
                           +------------v-----------+
                           |   Reorder Buffer (ROB) |
                           |  (in-order commit,     |
                           |   branch recovery)     |
                           +------------------------+
```

## Repository Structure

```
32-Bit-risc_v_out_of_order_processor/
├── rtl/                        # RTL source files
│   ├── top.v                   # Top-level module (wires all units together)
│   ├── include/
│   │   ├── params.vh           # Design parameters (ROB, RS sizes, widths)
│   │   └── rv32i_defines.vh    # ISA encodings and internal op codes
│   ├── core/
│   │   ├── fetch.v             # Instruction fetch with AXI interface
│   │   ├── decode_dispatch.v   # Decode, register rename, and RS dispatch
│   │   ├── rob.v               # Reorder Buffer (in-order commit)
│   │   ├── rat.v               # Register Alias Table (renaming)
│   │   ├── register_file.v     # 32-entry RV32 register file
│   │   ├── rs.v                # Parameterized Reservation Station
│   │   ├── cdb.v               # Common Data Bus arbiter (4 FU inputs)
│   │   ├── perceptron_bpu.v    # Perceptron branch predictor
│   │   ├── async_fifo.v        # Gray-code async FIFO for CDC
│   │   ├── axi4_lite_master.v  # AXI4-Lite master state machine
│   │   └── axi4_lite_master_cdc.v  # AXI master with async FIFO CDC
│   └── execution/
│       ├── alu.v               # Arithmetic Logic Unit (RV32I ops)
│       ├── branch_unit.v       # Branch and jump execution unit
│       ├── lsq.v               # Load-Store Queue with AXI interface
│       └── mdu.v               # Multi-cycle Multiply/Divide Unit (RV32M)
├── tb/
│   └── tb_top.v                # Self-checking behavioral testbench
├── scripts/
│   ├── build_vivado.tcl        # Recreates Vivado project from source
│   └── run_sim.tcl             # Launches behavioral simulation
├── docs/
│   ├── RISC-V_OoO_Engine_PRD.md           # Product Requirements Document
│   ├── RISC-V_Architecture_Study_Guide.md  # Architecture study reference
│   └── RISC-V_Architecture_Study_Guide.html
├── .gitignore
├── CHANGELOG.md
├── CONTRIBUTING.md
└── LICENSE
```

## Key Design Parameters

Configurable via `rtl/include/params.vh`:

| Parameter | Default | Description |
|---|---|---|
| `ROB_ENTRIES` | 16 | Reorder Buffer depth |
| `RS_ALU_ENTRIES` | 8 | ALU Reservation Station entries |
| `RS_BR_ENTRIES` | 4 | Branch RS entries |
| `RS_LSQ_ENTRIES` | 8 | Load-Store Queue RS entries |
| `RS_MDU_ENTRIES` | 4 | Multiply/Divide RS entries |
| `NUM_REGS` | 32 | Architectural register count |
| `DATA_WIDTH` | 32 | Data path width (bits) |
| `ADDR_WIDTH` | 32 | Address width (bits) |
| `MEM_ADDR_WIDTH` | 12 | Memory address bits (4 KB) |

Perceptron BPU parameters (in `top.v` instantiation):

| Parameter | Default | Description |
|---|---|---|
| `HISTORY_LEN` | 4 | Branch history length |
| `WEIGHT_WIDTH` | 8 | Perceptron weight bit-width |
| `TABLE_ENTRIES` | 32 | Number of perceptron entries |

## Module Hierarchy

```
top
├── fetch               (core_clk)
├── axi4_lite_master_cdc  u_axi_i  (core/axi_clk — instruction fetch)
│   ├── async_fifo      u_req_fifo
│   ├── axi4_lite_master
│   └── async_fifo      u_resp_fifo
├── perceptron_bpu      (core_clk)
├── decode_dispatch     (core_clk)
├── rob                 (core_clk)
├── rat                 (core_clk)
├── register_file       (core_clk)
├── rs  u_rs_alu        (core_clk)
├── alu                 (core_clk)
├── rs  u_rs_br         (core_clk)
├── branch_unit         (core_clk)
├── rs  u_rs_lsq  [ORDERED=1]  (core_clk)
├── lsq                 (core_clk)
├── rs  u_rs_mdu        (core_clk)
├── mdu                 (core_clk)
├── axi4_lite_master_cdc  u_axi_d  (core/axi_clk — data memory)
│   ├── async_fifo      u_req_fifo
│   ├── axi4_lite_master
│   └── async_fifo      u_resp_fifo
└── cdb                 (combinational, 4-input arbiter)
```

## Getting Started

### Prerequisites

- **Vivado 2022.1** or later (with XSim)
- Vivado must be in your system PATH (use the Vivado Developer Command Prompt)

### Step 1 — Open the Vivado Project

The Vivado project is already included in the repo under `vivado_project/`. Open it directly:

```bash
vivado vivado_project/riscv_ooo_project.xpr
```

Alternatively, **recreate it from scratch** (useful if you change RTL file structure):

```bash
vivado -mode batch -source scripts/build_vivado.tcl
```

### Step 3 — Run Simulation

**Option A — From the command line:**

```bash
vivado -mode batch -source scripts/run_sim.tcl
```

**Option B — From the Vivado GUI:**

1. In the Flow Navigator, click **Run Simulation > Run Behavioral Simulation**.
2. In the Tcl Console, type: `run 50000ns`

**Option C — From the Vivado Tcl Console (project already open):**

```tcl
source scripts/run_sim.tcl
```

### Expected Output

A passing run produces:

```
Register State after execution:
x1 =  50  (PASS)  [ADDI]
x2 =  15  (PASS)  [ADDI]
x3 =  65  (PASS)  [ADD]
x4 =  35  (PASS)  [SUB]
x5 = 750  (PASS)  [MUL]
x6 =   3  (PASS)  [DIV]
x7 =   2  (PASS)  [AND]
x8 =  63  (PASS)  [OR]
x9 = 750  (PASS)  [SW/LW]
Result: 9 / 9 tests passed
[ ALL TESTS PASSED ]
```

## Testbench Details

`tb/tb_top.v` instantiates the `top` module with a mock AXI4-Lite memory slave. Both `core_clk` and `axi_clk` are tied to the same 100 MHz clock to eliminate CDC timing uncertainty in simulation.

The 9-instruction test program loaded into memory exercises:

| Test | Instruction | Expected | Execution Unit |
|---|---|---|---|
| x1 = 50 | `addi x1, x0, 50` | 50 | ALU |
| x2 = 15 | `addi x2, x0, 15` | 15 | ALU |
| x3 = x1+x2 | `add x3, x1, x2` | 65 | ALU |
| x4 = x1-x2 | `sub x4, x1, x2` | 35 | ALU |
| x5 = x1*x2 | `mul x5, x1, x2` | 750 | MDU (multi-cycle) |
| x6 = x1/x2 | `div x6, x1, x2` | 3 | MDU (multi-cycle) |
| x7 = x1&x2 | `and x7, x1, x2` | 2 | ALU |
| x8 = x1\|x2 | `or x8, x1, x2` | 63 | ALU |
| x9 = mem[0] | `sw x5,0(x0)` + `lw x9,0(x0)` | 750 | LSQ (store then load) |

## Clock Domain Crossing

The design uses two asynchronous clock domains connected via gray-code async FIFOs (`rtl/core/async_fifo.v`):

| Domain | Signal | Typical Frequency |
|---|---|---|
| `core_clk` | All pipeline stages | 100 MHz |
| `axi_clk` | AXI4-Lite memory interface | 50 MHz |

The `axi4_lite_master_cdc` module wraps the AXI master with:
- **Request FIFO** (core → AXI): carries `{we, addr, wdata}`
- **Response FIFO** (AXI → core): carries `rdata`

Timing constraints in `constraints.xdc` declare the two clocks as asynchronous groups, so Vivado correctly ignores cross-domain paths.

## Hardware Performance Counters

Available on the `top` module's output ports (64-bit, core clock domain):

| Port | Description |
|---|---|
| `perf_cycles` | Total clock cycles elapsed |
| `perf_instret` | Instructions retired (committed) |
| `perf_branches` | Branch instructions committed |
| `perf_mispredicts` | Branch mispredictions (commit_taken ≠ commit_pred_taken) |

## Synthesis Target

| Attribute | Value |
|---|---|
| Device | Xilinx Artix-7 XC7A100T-CSG324-1 |
| Core clock | 100 MHz (10 ns period) |
| AXI clock | 50 MHz (20 ns period) |
| Tool | Vivado 2022.1 |

To target a different FPGA, update the `-part` argument in `scripts/build_vivado.tcl` and adjust clock constraints in `constraints.xdc`.

## License

This project is licensed under the [MIT License](LICENSE).
