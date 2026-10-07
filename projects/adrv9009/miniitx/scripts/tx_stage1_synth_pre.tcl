# XCI-managed global GT synthesis, same lower-module binding as laser_tx.
set root [file normalize [file join [file dirname [info script]] ..]]
set gen [file join $root adrv9009_zc706.gen sources_1 ip gtwizard_0]
foreach rel {gtwizard_0_gt.v gtwizard_0_cpll_railing.v gtwizard_0/example_design/gtwizard_0_rx_startup_fsm.v gtwizard_0/example_design/gtwizard_0_sync_block.v gtwizard_0/example_design/gtwizard_0_tx_startup_fsm.v} {
    set path [file join $gen $rel]
    if {![file exists $path]} {error "XCI-managed GT child missing: $path"}
    read_verilog -library xil_defaultlib $path
}
puts "STAGE1_GT_XCI_CHILDREN_LOADED=5"
