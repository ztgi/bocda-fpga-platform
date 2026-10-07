# Read an existing accepted checkpoint; never run synthesis/implementation.
if {$argc != 2} {error "Usage: export_stage1_xsa.tcl <accepted_repaired.dcp> <new.xsa>"}
set dcp [file normalize [lindex $argv 0]]
set out [file normalize [lindex $argv 1]]
if {![file exists $dcp]} {error "Missing accepted checkpoint"}
if {[file exists $out]} {error "Refusing to overwrite XSA"}
file mkdir [file dirname $out]
open_checkpoint $dcp
if {[get_property PART [current_design]] ne "xc7z100ffg900-2"} {error "Wrong device"}
write_hw_platform -fixed -file $out
puts "STAGE1_EXISTING_DCP_XSA_EXPORT_PASS"
close_design
