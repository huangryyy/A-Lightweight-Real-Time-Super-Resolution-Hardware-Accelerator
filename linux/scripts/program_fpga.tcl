set base [file dirname [file normalize [info script]]]
open_hw_manager
connect_hw_server -url localhost:3121
set targets [get_hw_targets -quiet]
if {[llength $argv] > 0} {set targets [get_hw_targets -quiet [lindex $argv 0]]}
if {[llength $targets] != 1} {error "Expected one JTAG target; specify filter with -tclargs"}
open_hw_target [lindex $targets 0]
set devices [get_hw_devices -quiet xczu19*]
if {[llength $devices] != 1} {error "Expected one XCZU19 device"}
set dev [lindex $devices 0]
set_property PROGRAM.FILE [file join $base .. Top.bit] $dev
set_property PROBES.FILE {} $dev
set_property FULL_PROBES.FILE {} $dev
program_hw_devices $dev
set_property PROBES.FILE [file join $base .. Top.ltx] $dev
set ok 0
for {set i 0} {$i < 30} {incr i} {
 after 500
 refresh_hw_device $dev
 set migs [get_hw_migs -quiet -of_objects $dev]
 if {[llength $migs] != 1} {continue}
 set mig [lindex $migs 0]
 refresh_hw_mig $mig
 if {[get_property CALIBRATION_FAIL.STATUS $mig] eq "FALSE" && [get_property CAL_STATUS.RANK0.21_WRITE_READ_SANITY_CHECK $mig] eq "PASS"} {set ok 1;break}
}
if {!$ok} {error "DDR calibration failed; do not start inference"}
close_hw_target
disconnect_hw_server
close_hw_manager
puts "PROGRAM_AND_DDR_PASS"


