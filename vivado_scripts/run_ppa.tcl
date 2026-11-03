# Vivado 2023.2: fresh source build and post-route PPA reports.
# Usage: vivado -mode batch -source run_ppa.tcl -tclargs OUTPUT_DIR
set script_dir [file dirname [file normalize [info script]]]
if {[llength $argv] != 1} {error "Pass one new output directory"}
set ppa_output [file normalize [lindex $argv 0]]
if {![file exists [file join $ppa_output Core_test.xpr]]} {
 set argv [list --output $ppa_output --generate-ip]
 source [file join $script_dir rebuild.tcl]
}
open_project [file join $ppa_output Core_test.xpr]
set_param general.maxThreads 6
foreach ip [get_ips] {
 set ip_file [get_files [get_property IP_FILE $ip]]
 if {[get_property GENERATE_SYNTH_CHECKPOINT $ip_file]} {create_ip_run $ip_file}
}
launch_runs synth_1 -jobs 4
wait_on_run synth_1
if {[get_property PROGRESS [get_runs synth_1]] ne "100%"} {
 error "Synthesis failed: [get_property STATUS [get_runs synth_1]]"
}
open_run synth_1
report_utilization -file [file join $ppa_output synthesis_utilization.rpt]
report_utilization -hierarchical -file [file join $ppa_output synthesis_utilization_hierarchical.rpt]
close_design
launch_runs impl_1 -to_step route_design -jobs 4
wait_on_run impl_1
if {[get_property PROGRESS [get_runs impl_1]] ne "100%" && ![string match "*route_design Complete*" [get_property STATUS [get_runs impl_1]]]} {
 error "Implementation failed: [get_property STATUS [get_runs impl_1]]"
}
open_run impl_1
report_route_status -file [file join $ppa_output route_status.rpt]
report_utilization -file [file join $ppa_output implemented_utilization.rpt]
report_utilization -hierarchical -file [file join $ppa_output implemented_utilization_hierarchical.rpt]
report_timing_summary -report_unconstrained -file [file join $ppa_output implemented_timing.rpt]
report_clock_interaction -file [file join $ppa_output clock_interaction.rpt]
report_drc -file [file join $ppa_output implemented_drc.rpt]
# No SAIF is supplied: this is a vectorless tool estimate, not measured board power.
report_power -file [file join $ppa_output implemented_power.rpt]
write_checkpoint -force [file join $ppa_output Top_routed.dcp]
puts "PPA_BUILD_PASS OUTPUT=$ppa_output POWER_METHOD=VECTORLESS_DEFAULT_ACTIVITY"
close_project
