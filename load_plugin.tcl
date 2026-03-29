# Load the Simmerblau plugin into VMD.
set script_dir [file dirname [info script]]
set plugin_dir [file join $script_dir "vmd_plugin"]

puts "Simmerblau: Loading plugin from $plugin_dir."
lappend auto_path $plugin_dir

if {[catch {package require simmerblau} msg]} {
    puts "Simmerblau Error: Could not load package: $msg"
} else {
    simmerblau_tk_cb
    puts "Simmerblau: Ready! Look for 'Simmerblau Palette Generator' in the Extensions menu."
}
