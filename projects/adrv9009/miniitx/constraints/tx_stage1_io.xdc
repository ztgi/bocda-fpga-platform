# Pins inherited from the implemented laser_tx source, and checked against
# RX package-pin occupancy through Vivado MCP before adding this file.
set_property PACKAGE_PIN AB2 [get_ports gtx_txp_out]
set_property PACKAGE_PIN AB1 [get_ports gtx_txn_out]
set_property PACKAGE_PIN U8 [get_ports gt_refclk125_p]
set_property PACKAGE_PIN U7 [get_ports gt_refclk125_n]
create_clock -name MGT_REFCLK_125M -period 8.000 [get_ports gt_refclk125_p]
set_property LOC GTXE2_CHANNEL_X0Y8 [get_cells -hier -filter {REF_NAME == GTXE2_CHANNEL && NAME =~ *u_laser_gt_tx_profile0/*}]
set_property LOC GTXE2_COMMON_X0Y2 [get_cells -hier -filter {REF_NAME == GTXE2_COMMON && NAME =~ *u_laser_gt_tx_profile0/*}]
set_property PACKAGE_PIN AG17 [get_ports eom_out]
set_property PACKAGE_PIN AB12 [get_ports soa_gate_out]
set_property PACKAGE_PIN AC14 [get_ports acq_trig_out]
set_property PACKAGE_PIN AD16 [get_ports acq_gate_out]
set_property PACKAGE_PIN AE17 [get_ports gt_sequence_sync_out]
set_property PACKAGE_PIN AD15 [get_ports txusrclk2_monitor_out]
set_property IOSTANDARD LVCMOS33 [get_ports {eom_out soa_gate_out acq_trig_out acq_gate_out gt_sequence_sync_out txusrclk2_monitor_out}]
# No AD9528/SPI or second AA8/AA7 reference buffer is added.
