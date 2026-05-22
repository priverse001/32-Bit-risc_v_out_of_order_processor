create_clock -name core_clk -period 10.000 \[get_ports core_clk\]
create_clock -name axi_clk -period 20.000 \[get_ports axi_clk\]
set_clock_groups -asynchronous -group \[get_clocks core_clk\] -group \[get_clocks axi_clk\]
