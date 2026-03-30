set dir [file normalize [file dirname [info script]]]
package ifneeded simmerblau_logic 1.0 [list source [file join $dir logic.tcl]]
package ifneeded simmerblau_rampensau 1.0 [list source [file join $dir rampensau.tcl]]
package ifneeded simmerblau 1.0 [list source [file join $dir main.tcl]]
