# Changelog

All notable changes to this project will be documented here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

## [1.0.0] - 2026-05-22

### Added
- Fully-pipelined RV32IM out-of-order processor (Tomasulo algorithm)
- 5 execution units: ALU, Branch Unit, Load-Store Queue (LSQ), Multiply/Divide Unit (MDU), and CDB arbiter
- Perceptron branch predictor (speculative execution support)
- Register Alias Table (RAT) for register renaming
- Reorder Buffer (ROB) for precise in-order commit and branch misprediction recovery
- 4 parameterized Reservation Stations (ALU, Branch, LSQ, MDU)
- Dual clock domain support (core vs. AXI) bridged via async FIFOs
- AXI4-Lite master interfaces for instruction fetch and data memory
- Hardware performance counters (cycles, instructions retired, branches, mispredicts)
- Self-checking testbench (`tb/tb_top.v`) with 9-test program covering ALU, MDU, LSQ
- Vivado project automation script (`scripts/build_vivado.tcl`) for Artix-7 target
- Professional repository structure: `rtl/`, `tb/`, `scripts/`, `docs/`
- MIT License
