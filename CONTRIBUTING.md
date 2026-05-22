# Contributing to risc-v-ooo-processor

Thank you for your interest in contributing! This project is a Verilog implementation of a
superscalar out-of-order RISC-V (RV32IM) processor using the Tomasulo algorithm.

## How to Contribute

### Reporting Issues

If you find a bug or a simulation mismatch:
1. Open a GitHub Issue with a clear title.
2. Include the simulation log output (from `tb_top.vcd` or Vivado console).
3. Describe the instruction sequence or test case that triggers the bug.

### Submitting Changes

1. Fork the repository.
2. Create a feature branch: `git checkout -b feature/your-feature-name`
3. Make your changes, following the coding style guidelines below.
4. Run the testbench and verify all 9 tests pass before submitting.
5. Open a Pull Request with a clear description of what changed and why.

## Coding Style

- Use consistent 4-space indentation.
- Declare all wires before first use (avoid implicit 1-bit wires in Verilog).
- Keep section comments concise — no banner lines of `=` characters.
- Prefer `always @(posedge clk or negedge rst_n)` for synchronous reset-active-low logic.
- Parameterize all design constants through `rtl/include/params.vh`.

## Simulation

Before submitting, verify the design with:
```bash
vivado -mode batch -source scripts/build_vivado.tcl
vivado -mode batch -source scripts/run_sim.tcl
```
All 9 self-checking tests in `tb/tb_top.v` must report `[ ALL TESTS PASSED ]`.

## Questions

Open a GitHub Discussion or Issue — happy to help.
