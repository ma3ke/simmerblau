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
    set src_dir [file normalize [file join [file dirname [info script]] "vmd_plugin"]]
    set vmd_rc_file ""

    # Detect the correct VMD configuration file and data dir based on the OS.
    if {$::tcl_platform(platform) == "windows"} {
        set vmd_rc_file [file join $::env(VMDDIR) "vmd.rc"]
        set vmd_plugins_dir [file join $::env(APPDATA) vmd plugins]
    } elseif {$::tcl_platform(os) == "Darwin"} {
        set vmd_rc_file [file join $::env(HOME) ".vmdrc"]
        set vmd_plugins_dir [file join $::env(HOME) Library "Application Support" vmd plugins]
    } else {
        set vmd_rc_file [file join $::env(HOME) ".vmdrc"]
        if {[info exists ::env(XDG_DATA_HOME)] && $::env(XDG_DATA_HOME) ne ""} {
            set vmd_plugins_dir [file join $::env(XDG_DATA_HOME) vmd plugins]
        } else {
            set vmd_plugins_dir [file join $::env(HOME) .local share vmd plugins]
        }
    }
    set target_dir [file join $vmd_plugins_dir simmerblau]

    puts "VMDRC: $vmd_rc_file"
    puts "Target directory: $target_dir"

    # Ensure the plugin directory exists.
    if {![file isdirectory $src_dir]} {
        puts "Error: Plugin directory not found at $src_dir"
        return
    }
    # Remove a previous installation, if it already exists there.
    if {[file isdirectory $target_dir]} {
        puts "Cleaning previous installation inside $target_dir"
        # Only delete .tcl files (since the plugin has only .tcl files).
        file delete -- {*}[glob -nocomplain -directory $target_dir -types f *.tcl]
    } else {
        # Make the plugin directory.
        file mkdir $target_dir
    }

    # Copy the plugin files to the data directory.
    set files [glob -nocomplain -directory $src_dir -types f *.tcl]
    if {[llength $files] > 0} {
        file copy -force -- {*}$files $target_dir
    }

    # Prepare the installation lines.
    set install_block {
        # VMD plugin path (added by Simmerblau).
        set _plugindir @PLUGIN_DIR@; list
        if {[lsearch -exact $auto_path $_plugindir] < 0} {
            lappend auto_path $_plugindir; list
        }
        # Simmerblau plugin.
        package require simmerblau; list
    }
    # We escape the plugins directory using `[list $vmd_plugins_dir]`.
    set install_block [
        string trim [string map [list @PLUGIN_DIR@ [list $vmd_plugins_dir]] $install_block]
    ]

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

        # 4. Load the plugin for the current session immediately, if not already installed.
        lappend ::auto_path $target_dir
        if {[catch {package require simmerblau} msg]} {
            puts "Warning: Could not load the package immediately: $msg"
        } else {
            vmd_install_extension simmerblau simmerblau_tk_cb "Visualization/Simmerblau Colors"
            puts "Simmerblau has been loaded and registered for this session."
            puts "You can find it under Extensions > Visualization > Simmerblau Colors."
        }
    }
}

simmerblau_install
