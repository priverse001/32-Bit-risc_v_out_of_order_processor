# run_sim.tcl
# Launches a behavioral simulation of the RISC-V OOO processor.
#
# Usage from Vivado Tcl Console (project must already be open):
#   source scripts/run_sim.tcl
#
# Or from the command line (batch mode, project root):
#   vivado -mode batch -source scripts/run_sim.tcl

open_project vivado_project/riscv_ooo_project.xpr
reset_simulation -simset sim_1 -mode behavioral
launch_simulation
run 50000ns
close_project
