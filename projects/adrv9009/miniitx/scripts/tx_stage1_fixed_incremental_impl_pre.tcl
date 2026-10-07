# Dedicated reachable Stage 1 mode and local fabric isolation; no RX RTL change.
set root [file normalize [file join [file dirname [info script]] ..]]
set TX_STAGE1_TIMING_MODE fixed_500m
source [file join $root scripts tx_stage1_impl_pre.tcl]

# Preserve original RX/global clock resources from the native baseline database.
# Incremental matching alone does not prohibit clock replication by phys_opt.
# The run also disables both phys_opt steps. No clock/data timing exception here.
set f [open [file join $root reports tx_rx_merge_stage1 incremental_physical baseline_device_and_placement.txt] r]
set baseline_resources [read $f]
close $f
set preserved 0
foreach line [split $baseline_resources \n] {
    if {![regexp {^CELL=(\S+) TYPE=(BUFG|MMCME2_ADV) LOC=(\S+)} $line -> name type loc]} {continue}
    # Debug hub is inserted by opt_design; it is not an RX clock-tree element.
    if {[string match dbg_hub/* $name]} {continue}
    set c [get_cells -quiet $name]
    if {[llength $c] != 1 || [get_property REF_NAME $c] ne $type} {error "Baseline clock resource missing: $name"}
    set_property LOC $loc $c
    set_property DONT_TOUCH true $c
    # Preserve only the used BUFG outputs. Marking *all* MMCM output nets
    # DONT_TOUCH retains six otherwise-dead CLKOUT1/2 BUFGs from the synth
    # netlist and changes RX clock resources. MMCM cells/LOCs remain protected.
    if {$type eq "BUFG"} {
        set output [get_pins -quiet -of_objects $c -filter {DIRECTION == OUT}]
        set nets [get_nets -quiet -of_objects $output]
        if {[llength $nets]} {set_property DONT_TOUCH true $nets}
    }
    incr preserved
}
if {$preserved != 17} {error "Expected 13 original RX/platform BUFG + 4 original MMCM, got $preserved"}

# Device database: GTXE2_CHANNEL_X0Y8 / COMMON_X0Y2 lie in CLOCKREGION_X1Y2.
# Use only the east-side fabric of that region (2500 slice sites). Baseline
# FIR/BFS has no slice cells in this rectangle. Existing unrelated RX cells
# remain allowed: EXCLUDE_PLACEMENT=false avoids evicting original RX placement.
create_pblock pblock_optical_tx_stage1
set pb [get_pblocks pblock_optical_tx_stage1]
resize_pblock $pb -add {SLICE_X155Y100:SLICE_X204Y149}
set_property IS_SOFT false $pb
set_property EXCLUDE_PLACEMENT false $pb
set selected {}
foreach pattern {u_laser_gt_tx_profile0/* u_laser_tx_core/u_pattern_tx_engine/* u_laser_tx_core/u_tx_eom_window_generator/* u_laser_tx_core/u_tx_scope_debug_outputs/*} {
    foreach c [get_cells -hier -quiet -filter "NAME =~ $pattern && IS_PRIMITIVE == 1"] {
        # cpll_railing uses a regional REFCLK BUFH, not TXUSRCLK/EOM. Forcing
        # its SRLs/FFs into eastern X1Y2 violates PLCK-11. Keep that existing
        # small startup subtree in its legal regional clock footprint.
        if {[string match */cpll_railing0_i/* $c]} {continue}
        if {[regexp {^(LUT[1-6]|FD(RE|SE|CE|PE)|CARRY4|MUXF[78]|SRL.*|RAM(32|64|128|256).*)$} [get_property REF_NAME $c]]} {
            lappend selected $c
        }
    }
}
set selected [lsort -unique $selected]
if {[llength $selected] < 5000} {error "Incomplete TX fabric Pblock selection"}
foreach c $selected {
    if {[string match i_system_wrapper/* $c] || [string match */u_config_loader/* $c]} {
        error "AXI/PS/config loader unexpectedly included: $c"
    }
}
add_cells_to_pblock $pb $selected
if {![info exists STAGE1_CANDIDATE_FOLDER]} {set STAGE1_CANDIDATE_FOLDER candidate}
set out [file join $root reports tx_rx_merge_stage1 incremental_physical $STAGE1_CANDIDATE_FOLDER]
file mkdir $out
set f [open [file join $out isolation_selection.txt] w]
puts $f "MODE=fixed_500m"
puts $f "PRESERVED_BASELINE_CLOCK_RESOURCES=$preserved"
puts $f "PBLOCK=pblock_optical_tx_stage1 RANGE=SLICE_X155Y100:SLICE_X204Y149 IS_SOFT=false EXCLUDE_PLACEMENT=false"
puts $f "FABRIC_CELL_COUNT=[llength $selected]"
foreach c $selected {puts $f "CELL=$c TYPE=[get_property REF_NAME $c]"}
close $f
puts "STAGE1_FIXED_INCREMENTAL_PREHOOK_COMPLETE"
