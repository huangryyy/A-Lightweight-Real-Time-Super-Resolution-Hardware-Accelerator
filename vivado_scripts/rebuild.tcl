# Vivado 2023.2. Recreate from RTL/XCI/XDC; no old DCP or cache is required.
set root [file normalize [file join [file dirname [info script]] ..]]
set target [file join $root build Core_test]
set ix [lsearch -exact $argv --output]
if {$ix >= 0} {set target [file normalize [lindex $argv [expr {$ix+1}]]]}
if {[file exists [file join $target Core_test.xpr]]} {error "Target already has a project; use --output with a new directory or open that project"}
create_project Core_test $target -part xczu19eg-ffvc1760-2-i
set_property target_language Verilog [current_project]
set_property simulator_language Mixed [current_project]
foreach f [glob [file join $root Core *.v]] {
 if {![string match tb_* [file tail $f]]} {add_files -norecurse $f}
}
foreach f [glob [file join $root Core_test Core_test.srcs sources_1 ip * *.xci]] {
 # Import also updates XCI's embedded gen_directory; a plain file copy does not.
 import_ip $f
}
foreach f [glob [file join $root Core_test Core_test.srcs constrs_1 imports Core_test *.xdc]] {add_files -fileset constrs_1 -norecurse $f}
add_files -fileset sim_1 -norecurse [file join $root Core tb_FSRCNN_X4.v]
add_files -fileset sim_1 -norecurse [glob [file join $root sim *.mem]]
set_property top Top [get_filesets sources_1]
set_property top tb_FSRCNN_X4 [get_filesets sim_1]
set_property source_mgmt_mode All [current_project]
set_property STEPS.SYNTH_DESIGN.ARGS.FLATTEN_HIERARCHY rebuilt [get_runs synth_1]
update_compile_order -fileset sources_1
if {[llength [get_ips]] != 14} {error "Expected fourteen retained IPs"}
foreach ip [get_ips] {if {[get_property IS_LOCKED $ip]} {error "Locked IP: $ip; use Vivado 2023.2"}}
if {[lsearch -exact $argv --generate-ip] >= 0 || [lsearch -exact $argv --build] >= 0} {
 generate_target all [get_ips]
}
report_ip_status -file [file join $root fpga_release ip_status_after_cleanup.rpt]
if {[lsearch -exact $argv --build] >= 0} {
 create_ip_run [get_files *.xci]
 launch_runs synth_1 -jobs 6
 wait_on_run synth_1
 if {[get_property PROGRESS [get_runs synth_1]] ne "100%"} {error "Synthesis failed"}
 launch_runs impl_1 -to_step write_bitstream -jobs 6
 wait_on_run impl_1
 if {[get_property PROGRESS [get_runs impl_1]] ne "100%"} {error "Implementation failed"}
 open_run impl_1
 report_timing_summary -file [file join $target final_timing.rpt]
 report_bus_skew -file [file join $target final_bus_skew.rpt]
 # Keep the already verified release until the new build has been reviewed.
 puts "NEW_BUILD_BITSTREAM=[file join $target Core_test.runs impl_1 Top.bit]"
}
puts "SOURCE_RECREATE_PASS IP_COUNT=[llength [get_ips]] PROJECT=[file join $target Core_test.xpr]"
close_project

