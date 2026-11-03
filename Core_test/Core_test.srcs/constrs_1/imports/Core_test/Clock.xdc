# PCIe timing constraints

# DDR4 timing constraints

## pcie_aclk
#create_generated_clock -name pcie_aclk -source [get_pins inst_xdma/sys_clk] -master_clock pcie_sys_clk [get_pins inst_xdma/axi_aclk]

## clk_out1
#create_generated_clock -name clk_out1 -source [get_pins inst_clk_wiz_0/clk_in1] -master_clock pcie_aclk [get_pins inst_clk_wiz_0/clk_out1]

## clk_out2
#create_generated_clock -name clk_out2 -source [get_pins inst_clk_wiz_0/clk_in1] -master_clock pcie_aclk [get_pins inst_clk_wiz_0/clk_out2]

## clk_out3
#create_generated_clock -name clk_out3 -source [get_pins IBUFDS_inst/I] -master_clock ddr4_sys_clk_p [get_pins IBUFDS_inst/O]

## pcie_sys_clk_gt
#create_generated_clock -name pcie_sys_clk_gt -source [get_pins inst_buffer/I] -master_clock pcie_sys_clk_p [get_pins inst_buffer/O]

## pcie_sys_clk
#create_generated_clock -name pcie_sys_clk -source [get_pins inst_buffer/I] -master_clock pcie_sys_clk_p [get_pins inst_buffer/ODIV2]




####################################################################################
# Constraints from file : 'axi_interconnect_0_impl_clocks.xdc'
####################################################################################



####################################################################################
# Constraints from file : 'axi_interconnect_0_impl_clocks.xdc'
####################################################################################


create_clock -period 10.000 -name pcie_sys_clk_p [get_ports pcie_sys_clk_p]
create_clock -period 5.000 -name ddr4_sys_clk_p [get_ports ddr4_sys_clk_p]
set_false_path -from [get_clocks -of_objects [get_pins inst_clk_wiz_0/inst/mmcme4_adv_inst/CLKOUT0]] -to [get_clocks -of_objects [get_pins inst_xdma/inst/pcie4_ip_i/inst/xdma_0_pcie4_ip_gt_top_i/diablo_gt.diablo_gt_phy_wrapper/phy_clk_i/bufg_gt_userclk/O]]
set_false_path -from [get_clocks -of_objects [get_pins inst_xdma/inst/pcie4_ip_i/inst/xdma_0_pcie4_ip_gt_top_i/diablo_gt.diablo_gt_phy_wrapper/phy_clk_i/bufg_gt_userclk/O]] -to [get_clocks -of_objects [get_pins inst_clk_wiz_0/inst/mmcme4_adv_inst/CLKOUT0]]
set_false_path -from [get_clocks -of_objects [get_pins inst_ddr4_controller/inst/u_ddr4_infrastructure/gen_mmcme4.u_mmcme_adv_inst/CLKOUT0]] -to [get_clocks -of_objects [get_pins inst_xdma/inst/pcie4_ip_i/inst/xdma_0_pcie4_ip_gt_top_i/diablo_gt.diablo_gt_phy_wrapper/phy_clk_i/bufg_gt_userclk/O]]

####################################################################################
# Constraints from file : 'axi_interconnect_0_impl_clocks.xdc'
####################################################################################

set_false_path -from [get_clocks ddr4_sys_clk_p] -to [get_clocks -of_objects [get_pins inst_xdma/inst/pcie4_ip_i/inst/xdma_0_pcie4_ip_gt_top_i/diablo_gt.diablo_gt_phy_wrapper/phy_clk_i/bufg_gt_userclk/O]]
set_property C_CLK_INPUT_FREQ_HZ 300000000 [get_debug_cores dbg_hub]
set_property C_ENABLE_CLK_DIVIDER false [get_debug_cores dbg_hub]
set_property C_USER_SCAN_CHAIN 1 [get_debug_cores dbg_hub]
connect_debug_port dbg_hub/clk [get_nets clk]
