set root [file normalize [file join [file dirname [info script]] ..]]
open_project [file join $root Core_test Core_test.xpr]
if {[get_property PART [current_project]] ne "xczu19eg-ffvc1760-2-i"} {error "Wrong target"}
if {[llength [get_ips]] != 14} {error "Expected fourteen IPs"}
foreach ip [get_ips] {
 if {[get_property IS_LOCKED $ip]} {error "Locked IP $ip"}
 if {![file exists [get_property IP_FILE $ip]]} {error "Missing IP $ip"}
}
update_compile_order -fileset sources_1
puts "CLEAN_CURRENT_PROJECT_PASS IP_COUNT=[llength [get_ips]] TOP=[get_property top [get_filesets sources_1]]"
close_project
