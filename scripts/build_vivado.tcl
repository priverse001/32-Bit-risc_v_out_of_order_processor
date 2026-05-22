# build_vivado.tcl
# Recreates the Vivado project from source files.
#
# Usage (from the project root directory):
#   vivado -mode batch -source scripts/build_vivado.tcl
#
# Or from the Vivado Tcl Console:
#   source scripts/build_vivado.tcl

set proj_name "vivado_project"
set proj_dir  "./$proj_name"

# Target FPGA: Artix-7 xc7a100tcsg324-1
# Change -part to match your board (e.g., xc7z020clg400-1 for Zynq)
create_project $proj_name $proj_dir -part xc7a100tcsg324-1 -force

# Add Verilog header files first so they are visible during compilation
add_files -fileset sources_1 [glob -nocomplain ./rtl/include/*.vh]
set_property file_type "Verilog Header" [get_files [glob -nocomplain ./rtl/include/*.vh]]

# Add RTL source files
add_files -fileset sources_1 [glob -nocomplain ./rtl/*.v]
add_files -fileset sources_1 [glob -nocomplain ./rtl/core/*.v]
add_files -fileset sources_1 [glob -nocomplain ./rtl/execution/*.v]

# Add simulation/testbench files
add_files -fileset sim_1 [glob -nocomplain ./tb/*.v]

# Set top modules
set_property top top         [current_fileset]
set_property top tb_top      [get_filesets sim_1]

# Create timing constraints (XDC) for the dual clock-domain design
set xdc_file "$proj_dir/constraints.xdc"
set file_obj [open $xdc_file w]
# Core clock: 100 MHz
puts $file_obj "create_clock -name core_clk -period 10.000 \[get_ports core_clk\]"
# AXI system clock: 50 MHz
puts $file_obj "create_clock -name axi_clk -period 20.000 \[get_ports axi_clk\]"
# Mark clocks as asynchronous (CDC handled by async_fifo)
puts $file_obj "set_clock_groups -asynchronous -group \[get_clocks core_clk\] -group \[get_clocks axi_clk\]"
close $file_obj

add_files -fileset constrs_1 $xdc_file

# Update compilation order
update_compile_order -fileset sources_1
update_compile_order -fileset sim_1

puts "Vivado project created in $proj_dir"
puts "Open in GUI: vivado $proj_dir/$proj_name.xpr"
