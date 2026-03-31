# Simmerblau VMD plugin installer.
#
# To install the plugin permanently:
# 1. Open VMD.
# 2. Open the VMD console (Extensions > TK Console).
# 3. Enter the following command:
#        source "/path/to/simmerblau/vmd_install.tcl"
#
# This script will automatically update your .vmdrc or vmd.rc file.

proc simmerblau_install {} {
    set plugin_dir [file normalize [file join [file dirname [info script]] "vmd_plugin"]]
    set vmd_rc_file ""

    # Detect the correct VMD configuration file based on the OS.
    if {$::tcl_platform(platform) == "windows"} {
        set vmd_rc_file [file join $::env(VMDDIR) "vmd.rc"]
    } else {
        set vmd_rc_file [file join $::env(HOME) ".vmdrc"]
    }

    # Ensure the plugin directory exists.
    if {![file isdirectory $plugin_dir]} {
        puts "Error: Plugin directory not found at $plugin_dir"
        return
    }

    # Prepare the installation lines.
    set install_block "\n# Simmerblau plugin.\nlappend auto_path \"$plugin_dir\"; list\npackage require simmerblau; list"

    set vmd_rc_exists [file exists $vmd_rc_file]

    # Check if the plugin is already registered in the config file.
    set already_installed 0
    if {$vmd_rc_exists} {
        set fp [open $vmd_rc_file r]
        set content [read $fp]
        close $fp
        if {[string first "simmerblau" $content] != -1} {
            set already_installed 1
        }
    }

    if {$already_installed} {
        puts "Simmerblau appears to be already registered in $vmd_rc_file."
    } else {
        # Append to the RC file.
        set fp [open $vmd_rc_file a]
        if {!$vmd_rc_exists} {
            # If there was no .vmdrc before, creating it would turn the main menu off, which is an
            # undesirable side effect.
            puts $fp "menu main on\n"
        }
        puts $fp $install_block
        close $fp
        puts "Successfully added Simmerblau to $vmd_rc_file."
    }

    # Load the plugin for the current session immediately.
    lappend ::auto_path $plugin_dir
    if {[catch {package require simmerblau} msg]} {
        puts "Warning: Could not load the package immediately: $msg"
    } else {
        vmd_install_extension simmerblau simmerblau_tk_cb "Visualization/Simmerblau Colors"
        puts "Simmerblau has been loaded and registered for this session."
        puts "You can find it under Extensions > Visualization > Simmerblau Colors."
    }
}

simmerblau_install
