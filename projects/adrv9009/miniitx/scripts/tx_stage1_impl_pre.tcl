# Implementation pre-opt hook: verify the GT Profile 0 user-clock topology and
# declare the real AXI/TX CDC relationship after link_design has created clocks.
# All AXI<->TX crossings in laser_tx_core/laser_gt_tx_profile0 are handled by
# explicit RTL synchronizers.

# The full-dynamic scenario remains available for future development. Stage 1
# implementation explicitly selects fixed_500m in its dedicated wrapper hook.
if {![info exists TX_STAGE1_TIMING_MODE]} {set TX_STAGE1_TIMING_MODE full_dynamic}
if {$TX_STAGE1_TIMING_MODE ni {full_dynamic fixed_500m}} {
    error "Unknown optical TX timing mode: $TX_STAGE1_TIMING_MODE"
}

proc require_one_clock {description objects} {
    set clocks [get_clocks -quiet -of_objects $objects]
    if {[llength $clocks] != 1} {
        error "GT Profile 0 clock check failed: expected one clock for $description, got '$clocks'."
    }
    return $clocks
}

proc require_period {description clock expected_period_ns} {
    set period [get_property PERIOD $clock]
    set delta [expr {abs($period - $expected_period_ns)}]
    if {$delta > 0.010} {
        error "GT Profile 0 clock check failed: $description period is $period ns, expected $expected_period_ns ns."
    }
    puts "INFO: $description period verified: $period ns"
}

# Merge Stage 1: use the new real 50 MHz TX control clock, never recreate
# RX FCLK0 (100 MHz). All GT object queries are optical-TX scoped.
set tx_control_clock_ip [get_ips -all -quiet system_tx_ctrl_clkgen_0]
if {[llength $tx_control_clock_ip] == 1 &&
    [get_property CONFIG.PRIM_SOURCE $tx_control_clock_ip] ne "No_buffer"} {
    error "Stage 1 TX clock wizard must use No_buffer for its internal PS FCLK source"
}
if {[llength [get_cells -hier -quiet -filter {REF_NAME == IBUF && NAME =~ *tx_ctrl_clkgen*}]]} {
    error "Stage 1 internal FCLK-to-MMCM path still contains an input IBUF; configure tx_ctrl_clkgen PRIM_SOURCE=No_buffer before implementation"
}
set axi_clock [require_one_clock "Stage 1 TX control" [get_pins u_laser_gt_tx_profile0/ctrl_clk]]
require_period "Stage 1 TX control" $axi_clock 20.000

if {$TX_STAGE1_TIMING_MODE eq "fixed_500m"} {
    # Reachability is proved by system_top: GPIO[31:11], dynamic start/valid,
    # north clock and all other dynamic entry inputs are tied inactive.
    # Do NOT case-constrain enable, reset, lock, ready, or data/valid controls.
    set optical_gt [get_cells -hier -quiet -filter \
        {REF_NAME == GTXE2_CHANNEL && NAME =~ u_laser_gt_tx_profile0/*}]
    if {[llength $optical_gt] != 1} {error "Stage 1 optical GT not unique"}
    foreach {port value width} {CPLLREFCLKSEL 1 3 TXSYSCLKSEL 0 2 TXOUTCLKSEL 2 3} {
        set pins [get_pins -quiet -of_objects $optical_gt -filter "REF_PIN_NAME =~ ${port}*"]
        if {[llength $pins] != $width} {error "Stage 1 $port width mismatch"}
        foreach pin $pins {
            if {![regexp {\[([0-9]+)\]$} [get_property REF_PIN_NAME $pin] -> bit]} {
                error "Cannot resolve mode bit: $pin"
            }
            set selected [expr {($value >> $bit) & 1}]
            set_case_analysis $selected $pin
            puts "STAGE1_FIXED_500M_CASE $pin=$selected"
        }
    }
    update_timing
}

# The maintained adapter binds the local XCI lower module directly.  Resolve
# the primitive pin by cell/pin identity rather than the generated wrapper
# path, so imported and adapter-backed hierarchies use the same clock model.
set txoutclk_pin [get_pins -hier -quiet -filter \
    {REF_NAME == GTXE2_CHANNEL && REF_PIN_NAME == TXOUTCLK && NAME =~ *u_laser_gt_tx_profile0/*}]
if {[llength $txoutclk_pin] != 1} {
    set txoutclk_pin [get_pins -quiet \
        u_laser_gt_tx_profile0/u_gtwizard_0/gt0_gtwizard_0_i/gtxe2_i/TXOUTCLK]
}
set mmcm_clkin_pin [get_pins -quiet \
    u_laser_gt_tx_profile0/u_tx_usrclk_profile0/u_txusrclk_mmcm/CLKIN1]
set mmcm_txusrclk_pin [get_pins -quiet \
    u_laser_gt_tx_profile0/u_tx_usrclk_profile0/u_txusrclk_mmcm/CLKOUT1]
set mmcm_txusrclk2_pin [get_pins -quiet \
    u_laser_gt_tx_profile0/u_tx_usrclk_profile0/u_txusrclk_mmcm/CLKOUT0]
set mmcm_eom_clk_pin [get_pins -quiet \
    u_laser_gt_tx_profile0/u_tx_usrclk_profile0/u_txusrclk_mmcm/CLKOUT2]
set txusrclk_bufg_input_pin [get_pins -quiet \
    u_laser_gt_tx_profile0/u_tx_usrclk_profile0/u_txusrclk_bufg/I]
set txusrclk2_bufg_input_pin [get_pins -quiet \
    u_laser_gt_tx_profile0/u_tx_usrclk_profile0/u_txusrclk2_bufg/I]
set eom_clk_bufg_input_pin [get_pins -quiet \
    u_laser_gt_tx_profile0/u_tx_usrclk_profile0/u_eom_clk_bufg/I]

foreach {description object} [list \
    "GT TXOUTCLK" $txoutclk_pin \
    "TX user-clock MMCM CLKIN1" $mmcm_clkin_pin \
    "TX user-clock MMCM CLKOUT1" $mmcm_txusrclk_pin \
    "TX user-clock MMCM CLKOUT0" $mmcm_txusrclk2_pin \
    "TX user-clock MMCM CLKOUT2" $mmcm_eom_clk_pin \
    "TXUSRCLK BUFG input" $txusrclk_bufg_input_pin \
    "TXUSRCLK2 BUFG input" $txusrclk2_bufg_input_pin \
    "EOM clock BUFG input" $eom_clk_bufg_input_pin] {
    if {[llength $object] != 1} {
        error "GT Profile 0 clock check failed: expected one $description pin, got '$object'."
    }
}

# The current static netlist contains QPLL_N=80, TXOUT_DIV=8,
# TX_INT_DATAWIDTH=32 and TXOUTCLKSEL=3'b010.  With the real 125 MHz GTREFCLK,
# Vivado derives a 1.25 Gb/s static QPLL/DIV8 combination and therefore a
# 39.0625 MHz (25.600 ns) TXOUTCLK.  This is not the 500M runtime profile; it is
# the only waveform consistent with the linked static GT primitive.  The
# runtime MMCM profiles are modeled separately below.
if {[llength $txoutclk_pin] == 1 &&
    [llength [get_clocks -quiet -of_objects $txoutclk_pin]] == 0} {
    if {$TX_STAGE1_TIMING_MODE eq "fixed_500m"} {
        # The lower-module XCI binding has no generated GT output-clock XDC.
        # Model the proven selected CPLL attributes, not the QPLL candidate.
        foreach {attribute expected} {CPLL_REFCLK_DIV 1 CPLL_FBDIV 4 CPLL_FBDIV_45 4 TXOUT_DIV 8 TX_DATA_WIDTH 64 TX_INT_DATAWIDTH 1} {
            if {[get_property $attribute $optical_gt] != $expected} {
                error "Selected Stage 1 GT attribute mismatch: $attribute"
            }
        }
        # 125 MHz * (4*4)/1 * 2/8 = 500 Mb/s; TXOUTCLKSEL=010,
        # 32-bit internal datapath -> TXOUTCLK = 500/32 = 15.625 MHz.
        create_clock -name GT_TXOUTCLK_FIXED_500M -period 64.000 $txoutclk_pin
        puts "INFO: Created selected fixed CPLL/500M GT TXOUTCLK (64.000 ns)."
    } else {
        create_clock -name GT_TXOUTCLK_STATIC_NETLIST -period 25.600 $txoutclk_pin
        puts "INFO: Created static-netlist GT TXOUTCLK clock (25.600 ns) on $txoutclk_pin."
    }
}

set txoutclk_clock [require_one_clock "GT TXOUTCLK" $txoutclk_pin]
set gt_native_period [get_property PERIOD $txoutclk_clock]
if {$TX_STAGE1_TIMING_MODE eq "fixed_500m" && abs($gt_native_period - 64.000) < 0.010} {
    puts "INFO: Native GT timing derivation resolved the selected CPLL/500M mode (64 ns)."
} else {
    require_period "static-netlist GT TXOUTCLK" $txoutclk_clock 25.600
}

# Keep Vivado's 25.600 ns GT primitive waveform for static-netlist/QPLL
# analysis, but do not let that candidate waveform drive the power-up MMCM
# model.  The real reset profile is 500M/CPLL:
#   TXOUTCLK = 15.625 MHz (64.000 ns)
# Model that profile only at the MMCM input boundary.  The 2/5 ratio below is a
# timing-model overlay between the retained 25.600 ns static GT candidate and
# the selected 64.000 ns startup profile; it is not a physical divider.
if {abs($gt_native_period - 64.000) < 0.010} {
    create_generated_clock -name GT_TXOUTCLK_INITIAL_500M \
        -source $txoutclk_pin -divide_by 1 $mmcm_clkin_pin
} else {
    create_generated_clock -name GT_TXOUTCLK_INITIAL_500M \
        -source $txoutclk_pin -multiply_by 2 -divide_by 5 $mmcm_clkin_pin
}
set startup_txoutclk_clock [require_one_clock \
    "500M/CPLL startup MMCM CLKIN1" $mmcm_clkin_pin]
require_period "500M/CPLL startup MMCM CLKIN1" \
    $startup_txoutclk_clock 64.000

# With the legal 64 ns input in place, retain the clocks Vivado derives from
# the static MMCM attributes (MULT=40, DIVCLK=1; output divides 40/80/5).
# Do not create clocks on CLKOUT0/1/2: doing so overrides these auto-derived
# clocks and triggers Constraints 18-1056.
update_timing
set static_txusrclk_clock [require_one_clock \
    "auto-derived MMCM CLKOUT1/TXUSRCLK" $mmcm_txusrclk_pin]
set static_txusrclk2_clock [require_one_clock \
    "auto-derived MMCM CLKOUT0/TXUSRCLK2" $mmcm_txusrclk2_pin]
set static_eom_clk_clock [require_one_clock \
    "auto-derived MMCM CLKOUT2/EOM" $mmcm_eom_clk_pin]
require_period "auto-derived MMCM CLKOUT1/TXUSRCLK" \
    $static_txusrclk_clock 64.000
require_period "auto-derived MMCM CLKOUT0/TXUSRCLK2" \
    $static_txusrclk2_clock 128.000
require_period "auto-derived MMCM CLKOUT2/EOM" \
    $static_eom_clk_clock 8.000
set static_mmcm_output_clocks [list \
    $static_txusrclk_clock $static_txusrclk2_clock $static_eom_clk_clock]
puts "INFO: Retained auto-derived 500M/CPLL MMCM output clocks: $static_mmcm_output_clocks"

set all_runtime_clocks {}
if {$TX_STAGE1_TIMING_MODE eq "full_dynamic"} {

# The runtime planner chooses K=16/8/4/2/1 and always programs
# EOM_CLK = K * TXUSRCLK2.  Independent 161.13 MHz TXUSRCLK2 and 200 MHz EOM
# maxima describe a combination that cannot exist.  Model the legal K-family
# envelopes as related sibling clocks from the same TXOUTCLK master instead.
# Each family uses its fastest legal pair:
#   K16: TXUSRCLK2/EOM <= 12.5/200 MHz
#   K8 : TXUSRCLK2/EOM <= 25/200 MHz
#   K4 : TXUSRCLK2/EOM <= 50/200 MHz
#   K2 : TXUSRCLK2/EOM <= 100/200 MHz
#   K1 : TXUSRCLK2/EOM <= 161.1328125/161.1328125 MHz
# Lower fixed profiles have the same integer relationship and are covered by
# the corresponding family envelope.
#
# Each -master_clock query deliberately resolves the auto-derived clock from
# its MMCM output pin.  Do not pass an auto-derived clock name through a helper
# proc: Vivado records that form as a name reference and raises TIMING-28.
#
# Ratios are relative to the auto-derived 500M/CPLL startup MMCM outputs:
#   CLKOUT1/TXUSRCLK  =  64.000 ns
#   CLKOUT0/TXUSRCLK2 = 128.000 ns
#   CLKOUT2/EOM       =   8.000 ns
# Each runtime clock starts at the real MMCM output pin and is attached to the
# downstream BUFG input.  This preserves the complete
# GT TXOUTCLK -> MMCM CLKIN1 -> MMCM CLKOUTx -> BUFG topology without
# redefining a BUFG output clock.
create_generated_clock -name GT_TXUSRCLK_RUNTIME_K16_MAX -add \
    -master_clock [get_clocks -of_objects $mmcm_txusrclk_pin] \
    -source $mmcm_txusrclk_pin -multiply_by 8 -divide_by 5 \
    $txusrclk_bufg_input_pin
create_generated_clock -name GT_TXUSRCLK2_RUNTIME_K16_MAX -add \
    -master_clock [get_clocks -of_objects $mmcm_txusrclk2_pin] \
    -source $mmcm_txusrclk2_pin -multiply_by 8 -divide_by 5 \
    $txusrclk2_bufg_input_pin
create_generated_clock -name GT_EOM_CLK_RUNTIME_K16_MAX -add \
    -master_clock [get_clocks -of_objects $mmcm_eom_clk_pin] \
    -source $mmcm_eom_clk_pin -multiply_by 8 -divide_by 5 \
    $eom_clk_bufg_input_pin

create_generated_clock -name GT_TXUSRCLK_RUNTIME_K8_MAX -add \
    -master_clock [get_clocks -of_objects $mmcm_txusrclk_pin] \
    -source $mmcm_txusrclk_pin -multiply_by 16 -divide_by 5 \
    $txusrclk_bufg_input_pin
create_generated_clock -name GT_TXUSRCLK2_RUNTIME_K8_MAX -add \
    -master_clock [get_clocks -of_objects $mmcm_txusrclk2_pin] \
    -source $mmcm_txusrclk2_pin -multiply_by 16 -divide_by 5 \
    $txusrclk2_bufg_input_pin
create_generated_clock -name GT_EOM_CLK_RUNTIME_K8_MAX -add \
    -master_clock [get_clocks -of_objects $mmcm_eom_clk_pin] \
    -source $mmcm_eom_clk_pin -multiply_by 8 -divide_by 5 \
    $eom_clk_bufg_input_pin

create_generated_clock -name GT_TXUSRCLK_RUNTIME_K4_MAX -add \
    -master_clock [get_clocks -of_objects $mmcm_txusrclk_pin] \
    -source $mmcm_txusrclk_pin -multiply_by 32 -divide_by 5 \
    $txusrclk_bufg_input_pin
create_generated_clock -name GT_TXUSRCLK2_RUNTIME_K4_MAX -add \
    -master_clock [get_clocks -of_objects $mmcm_txusrclk2_pin] \
    -source $mmcm_txusrclk2_pin -multiply_by 32 -divide_by 5 \
    $txusrclk2_bufg_input_pin
create_generated_clock -name GT_EOM_CLK_RUNTIME_K4_MAX -add \
    -master_clock [get_clocks -of_objects $mmcm_eom_clk_pin] \
    -source $mmcm_eom_clk_pin -multiply_by 8 -divide_by 5 \
    $eom_clk_bufg_input_pin

create_generated_clock -name GT_TXUSRCLK_RUNTIME_K2_MAX -add \
    -master_clock [get_clocks -of_objects $mmcm_txusrclk_pin] \
    -source $mmcm_txusrclk_pin -multiply_by 64 -divide_by 5 \
    $txusrclk_bufg_input_pin
create_generated_clock -name GT_TXUSRCLK2_RUNTIME_K2_MAX -add \
    -master_clock [get_clocks -of_objects $mmcm_txusrclk2_pin] \
    -source $mmcm_txusrclk2_pin -multiply_by 64 -divide_by 5 \
    $txusrclk2_bufg_input_pin
create_generated_clock -name GT_EOM_CLK_RUNTIME_K2_MAX -add \
    -master_clock [get_clocks -of_objects $mmcm_eom_clk_pin] \
    -source $mmcm_eom_clk_pin -multiply_by 8 -divide_by 5 \
    $eom_clk_bufg_input_pin

create_generated_clock -name GT_TXUSRCLK_RUNTIME_MAX -add \
    -master_clock [get_clocks -of_objects $mmcm_txusrclk_pin] \
    -source $mmcm_txusrclk_pin -multiply_by 165 -divide_by 8 \
    $txusrclk_bufg_input_pin
create_generated_clock -name GT_TXUSRCLK2_RUNTIME_MAX -add \
    -master_clock [get_clocks -of_objects $mmcm_txusrclk2_pin] \
    -source $mmcm_txusrclk2_pin -multiply_by 165 -divide_by 8 \
    $txusrclk2_bufg_input_pin
create_generated_clock -name GT_EOM_CLK_RUNTIME_MAX -add \
    -master_clock [get_clocks -of_objects $mmcm_eom_clk_pin] \
    -source $mmcm_eom_clk_pin -multiply_by 165 -divide_by 128 \
    $eom_clk_bufg_input_pin

set runtime_profile_clock_groups [list \
    [get_clocks {GT_TXUSRCLK_RUNTIME_K16_MAX \
        GT_TXUSRCLK2_RUNTIME_K16_MAX GT_EOM_CLK_RUNTIME_K16_MAX}] \
    [get_clocks {GT_TXUSRCLK_RUNTIME_K8_MAX \
        GT_TXUSRCLK2_RUNTIME_K8_MAX GT_EOM_CLK_RUNTIME_K8_MAX}] \
    [get_clocks {GT_TXUSRCLK_RUNTIME_K4_MAX \
        GT_TXUSRCLK2_RUNTIME_K4_MAX GT_EOM_CLK_RUNTIME_K4_MAX}] \
    [get_clocks {GT_TXUSRCLK_RUNTIME_K2_MAX \
        GT_TXUSRCLK2_RUNTIME_K2_MAX GT_EOM_CLK_RUNTIME_K2_MAX}] \
    [get_clocks {GT_TXUSRCLK_RUNTIME_MAX \
        GT_TXUSRCLK2_RUNTIME_MAX GT_EOM_CLK_RUNTIME_MAX}]]

set txusrclk_clock [get_clocks GT_TXUSRCLK_RUNTIME_MAX]
set txusrclk2_clock [get_clocks GT_TXUSRCLK2_RUNTIME_MAX]
set eom_clk_clock [get_clocks GT_EOM_CLK_RUNTIME_MAX]
require_period "runtime maximum GT TXUSRCLK" $txusrclk_clock 3.103
require_period "runtime maximum GT TXUSRCLK2" $txusrclk2_clock 6.206
require_period "K=1 paired EOM clock" $eom_clk_clock 6.206

# Only one MMCM DRP profile can be active at a time.  Keep clocks inside each
# legal K family related, while making clocks from different runtime profiles
# logically exclusive.  This avoids impossible zero-cycle cross-profile paths
# without masking any real path within an active profile.
set profile_exclusive_cmd [list set_clock_groups \
    -name GT_RUNTIME_PROFILE_LOGICAL_EXCLUSIVITY -logically_exclusive]
if {[llength $static_mmcm_output_clocks] > 0} {
    lappend profile_exclusive_cmd -group $static_mmcm_output_clocks
}
foreach profile_clocks $runtime_profile_clock_groups {
    lappend profile_exclusive_cmd -group $profile_clocks
}
{*}$profile_exclusive_cmd

foreach profile_clocks $runtime_profile_clock_groups {
    set all_runtime_clocks [concat $all_runtime_clocks $profile_clocks]
}
} else {
    # In this hardware mode no request can change the MMCM DRP profile. Keeping
    # hypothetical K-family envelopes active would time unreachable hardware.
    # Only the unchanged, auto-derived 64/128/8 ns startup clocks are created.
    if {[llength [get_clocks -quiet GT_*RUNTIME*]]} {
        error "Unreachable runtime overlays already loaded in fixed_500m mode"
    }
    puts "STAGE1_FIXED_500M_CLOCKS_ONLY: TXUSRCLK=64ns TXUSRCLK2=128ns EOM=8ns"
}

set_clock_groups -asynchronous \
    -group $axi_clock \
    -group [concat [list $txoutclk_clock] $static_mmcm_output_clocks $all_runtime_clocks]
puts "INFO: Applied asynchronous clock groups: $axi_clock <-> [concat [list $txoutclk_clock] $all_runtime_clocks]"
