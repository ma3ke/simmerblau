# Simmerblau is a VMD plugin that lets you generate parameterized color palettes.
#
# The color generation system is based on the wonderful RampenSau by David Aerne, which is
# distributed under the MIT license: https://github.com/meodai/rampensau.
#
# Marieke Westendorp & Aster Kovács, 2026.

package provide simmerblau 1.0

package require simmerblau_logic 1.0
package require simmerblau_rampensau 1.0
package require simmerblau_colorinator 1.0

namespace eval ::simmerblau:: {
    variable w
    variable total 32
    variable technique "rampensau"
    variable colorinator_map "SBW"
    variable colorinator_stops {{0.00 {0.15 0.55 0.90}} {0.50 {1.00 1.00 1.00}} {1.00 {0.85 0.40 0.05}}}
    variable hStart 180.0
    variable hCycles 1.0
    variable hStartCenter 0.5
    variable sMin 0.4
    variable sMax 0.8
    variable lMin 0.2
    variable lMax 0.9
    variable curveMethod "lamé"
    variable curveAccent 0.5
    variable useHarvey 0
    variable colorSpace "OKLCH"
    variable harmony "none"
    variable version "1.0"
    variable targetRange "0-32"
    variable livePreview 0
    variable undoStack {}
    variable redoStack {}
    variable snapshotAfterID ""
    # This dictionary maps the color index to its {r g b} values.
    variable lockedColors {}
    variable selected_stop_idx 0
    variable cur_r 0.0
    variable cur_g 0.0
    variable cur_b 0.0
    variable dragging_stop_idx -1
    set plugin_title "Simmerblau Colors"
    set label_width 14
}

proc simmerblau_tk_cb {} {
    ::simmerblau::simmerblau_gui
    return $::simmerblau::w
}

proc ::simmerblau::get_current_state {} {
    set state {}
    foreach var {technique total colorinator_map colorinator_stops selected_stop_idx hStart hCycles hStartCenter sMin sMax lMin lMax curveMethod curveAccent useHarvey colorSpace harmony} {
        dict set state $var [set ::simmerblau::$var]
    }
    return $state
}

proc ::simmerblau::set_current_state {state} {
    foreach {var val} $state { set ::simmerblau::$var $val }
    variable w
    if {[winfo exists $w.f.nb]} {
        set nb $w.f.nb
        foreach tab [$nb tabs] {
            if {[string tolower [$nb tab $tab -text]] == [string tolower $::simmerblau::technique]} {
                $nb select $tab
                break
            }
        }
    }
    # Update the Colorinator stop editor if it exists.
    if {[winfo exists $w.f.nb.colorinator]} {
        ::simmerblau::colorinator_select_stop $::simmerblau::selected_stop_idx 1
    }
    ::simmerblau::update_preview
}

proc ::simmerblau::bring_to_colorinator {} {
    variable technique
    if {$technique != "rampensau"} return

    # Generate the current ramp from RampenSau.
    set ramp [::simmerblau::generate_ramp 5] ;# We'll use 5 points as a baseline (0, 0.25, 0.5, 0.75, 1.0)
    set new_stops {}
    set n [llength $ramp]
    for {set i 0} {$i < $n} {incr i} {
        set pos [expr {double($i) / ($n - 1)}]
        set rgb [lindex $ramp $i]
        lappend new_stops [list $pos $rgb]
    }

    set ::simmerblau::colorinator_stops $new_stops
    set ::simmerblau::technique "colorinator"

    # Switch the tab in the UI.
    variable w
    if {[winfo exists $w.f.nb]} {
        set nb $w.f.nb
        foreach tab [$nb tabs] {
            if {[string tolower [$nb tab $tab -text]] == "colorinator"} {
                $nb select $tab
                break
            }
        }
    }
    ::simmerblau::colorinator_select_stop 0 1
}

proc ::simmerblau::update_button_states {} {
    variable w
    variable undoStack
    variable redoStack
    variable technique
    if {![winfo exists $w]} return
    set u_btn $w.f.frh.undo
    set r_btn $w.f.frh.redo
    set t_btn $w.f.frh.to_col
    if {[winfo exists $u_btn]} { if {[llength $undoStack] > 1} { $u_btn configure -state normal } else { $u_btn configure -state disabled } }
    if {[winfo exists $r_btn]} { if {[llength $redoStack] > 0} { $r_btn configure -state normal } else { $r_btn configure -state disabled } }
    if {[winfo exists $t_btn]} {
        if {$technique == "rampensau"} { $t_btn configure -state normal } else { $t_btn configure -state disabled }
    }
}

proc ::simmerblau::push_undo_snapshot {} {
    variable undoStack
    variable redoStack
    set currentState [::simmerblau::get_current_state]
    if {[llength $undoStack] > 0 && [lindex $undoStack end] == $currentState} { return }
    lappend undoStack $currentState
    if {[llength $undoStack] > 50} { set undoStack [lrange $undoStack 1 end] }
    set redoStack {}
    ::simmerblau::update_button_states
}

proc ::simmerblau::trigger_undo {} {
    variable undoStack
    variable redoStack
    if {[llength $undoStack] <= 1} return
    lappend redoStack [lindex $undoStack end]
    set undoStack [lrange $undoStack 0 end-1]
    ::simmerblau::set_current_state [lindex $undoStack end]
    ::simmerblau::update_button_states
}

proc ::simmerblau::trigger_redo {} {
    variable redoStack
    variable undoStack
    if {[llength $redoStack] == 0} return
    set state [lindex $redoStack end]
    set redoStack [lrange $redoStack 0 end-1]
    lappend undoStack $state
    ::simmerblau::set_current_state $state
    ::simmerblau::update_button_states
}

proc ::simmerblau::debounce_snapshot {} {
    variable snapshotAfterID
    if {$snapshotAfterID != ""} { after cancel $snapshotAfterID }
    set snapshotAfterID [after 1000 ::simmerblau::push_undo_snapshot]
}

proc ::simmerblau::get_storage_path {} {
    if {[file isdirectory ".simmerblau"]} { return [file normalize ".simmerblau"] }
    set config_root ""
    if {[info exists ::env(XDG_CONFIG_HOME)]} { set config_root $::env(XDG_CONFIG_HOME) } else { set config_root [file join $::env(HOME) ".config"] }
    set path [file join $config_root "simmerblau"]
    if {![file isdirectory $path]} { catch {file mkdir $path} }
    return $path
}

proc ::simmerblau::generate_ramp {total {extra_params ""}} {
    variable technique
    if {$extra_params == ""} {
        if {[info procs ::simmerblau::get_${technique}_params] != ""} {
            set extra_params [::simmerblau::get_${technique}_params]
        }
    }

    set raw_ramp ""
    if {[info procs ::simmerblau::logic::${technique}::generate_ramp] != ""} {
        set raw_ramp [::simmerblau::logic::${technique}::generate_ramp -total $total {*}$extra_params]
    } else {
        # Fallback to rampensau if technique is unknown.
        set raw_ramp [::simmerblau::logic::rampensau::generate_ramp -total $total {*}$extra_params]
    }

    if {$technique == "colorinator"} {
        return $raw_ramp
    }

    # Convert Rampensau HSL to RGB.
    set rgb_ramp {}
    foreach color $raw_ramp {
        if {$::simmerblau::colorSpace == "OKLCH"} {
            lappend rgb_ramp [::simmerblau::logic::oklch2rgb [lindex $color 2] [expr {[lindex $color 1] * 0.4}] [lindex $color 0]]
        } else {
            lappend rgb_ramp [::simmerblau::logic::hsl2rgb {*}$color]
        }
    }
    return $rgb_ramp
}

proc ::simmerblau::get_rampensau_params {} {
    return [list \
        -hStart $::simmerblau::hStart \
        -hCycles $::simmerblau::hCycles \
        -hStartCenter $::simmerblau::hStartCenter \
        -sRange [list $::simmerblau::sMin $::simmerblau::sMax] \
        -lRange [list $::simmerblau::lMin $::simmerblau::lMax] \
        -curveMethod $::simmerblau::curveMethod \
        -curveAccent $::simmerblau::curveAccent \
        -useHarvey $::simmerblau::useHarvey \
        -harmony $::simmerblau::harmony \
    ]
}

# This procedure retrieves the parameters required for the colorinator generation technique.
proc ::simmerblau::get_colorinator_params {} {
    return [list \
        -stops $::simmerblau::colorinator_stops \
    ]
}

proc ::simmerblau::save_palette {name} {
    if {$name == ""} return
    variable version
    package require json::write
    set path [::simmerblau::get_storage_path]
    set filename [file join $path "${name}.json"]
    set ramp [::simmerblau::generate_ramp $::simmerblau::total]
    set hex_items {}
    foreach rgb $ramp {
        lappend hex_items [json::write string [format "#%02x%02x%02x" [expr {int([lindex $rgb 0]*255)}] [expr {int([lindex $rgb 1]*255)}] [expr {int([lindex $rgb 2]*255)}]]]
    }
    set meta [json::write object author [json::write string $::tcl_platform(user)] host [json::write string [info hostname]] date [json::write string [clock format [clock seconds]]] version [json::write string $version] app [json::write string "Simmerblau"]]
    set params {}
    foreach {k v} [::simmerblau::get_current_state] { if {[string is double -strict $v]} { lappend params $k $v } else { lappend params $k [json::write string $v] } }
    set json [json::write object metadata $meta parameters [json::write object {*}$params] swatch [json::write array {*}$hex_items]]
    set fp [open $filename w]
    puts $fp $json; close $fp
    ::simmerblau::refresh_library
}

proc ::simmerblau::load_palette {name} {
    package require json
    set path [::simmerblau::get_storage_path]
    set filename [file join $path "${name}.json"]
    if {![file exists $filename]} return
    set fp [open $filename r]; set raw [read $fp]; close $fp
    if {[catch {set d [json::json2dict $raw]} msg]} { return }
    if {[dict exists $d parameters]} { ::simmerblau::set_current_state [dict get $d parameters] }
}

proc ::simmerblau::refresh_library {} {
    variable w; if {![winfo exists $w]} return
    set tv $w.f.lib.frtv.tv
    if {![winfo exists $tv]} return
    $tv delete [$tv children ""]
    set path [::simmerblau::get_storage_path]
    foreach f [lsort -dictionary [glob -nocomplain -directory $path -tails *.json]] {
        set filename [file join $path $f]
        set technique "Unknown"
        # Peek into the file to find the technique.
        if {[catch {
            set fp [open $filename r]
            set content [read $fp 2000]
            close $fp
            if {[regexp {"technique"\s*:\s*"([^"]+)"} $content -> tech]} {
                if {$tech == "rampensau"} { set technique "RampenSau" }
                if {$tech == "colorinator"} { set technique "Colorinator" }
            }
        }]} { catch {close $fp} }

        set id [$tv insert {} end -text [file rootname $f] -values [list $technique]]
        $tv item $id -tags [string tolower $technique]
    }
    ::simmerblau::update_library_colors
}

proc ::simmerblau::create_control {parent label var from to {res 0.01}} {
    set fr [frame $parent.f_$var]
    label $fr.l -text $label -width $::simmerblau::label_width -anchor w
    scale $fr.s -from $from -to $to -resolution $res -orient horizontal -variable ::simmerblau::$var -showvalue 0 -width 10
    entry $fr.e -width 8 -textvariable ::simmerblau::$var
    bind $fr.e <Up> [list ::simmerblau::step_value $var $res 1 $from $to]
    bind $fr.e <Down> [list ::simmerblau::step_value $var $res -1 $from $to]
    pack $fr.l -side left
    pack $fr.s -side left -fill x -expand 1
    pack $fr.e -side left -padx 5
    return $fr
}

proc ::simmerblau::step_value {var res dir from to} {
    if {[catch {set val [set ::simmerblau::$var]}]} { set val $from }
    set newVal [expr {$val + $res * $dir}]
    if {$newVal < $from} { set newVal $from }
    if {$newVal > $to} { set newVal $to }
    if {$res < 1} { set ::simmerblau::$var [format "%.2f" $newVal] } else { set ::simmerblau::$var [expr {int($newVal)}] }
}

proc ::simmerblau::update_library_colors {} {
    variable w; if {![winfo exists $w]} return
    set tv $w.f.lib.frtv.tv
    if {![winfo exists $tv]} return
    variable technique
    set current [string tolower $technique]

    if {$current == "rampensau"} {
        $tv tag configure rampensau -foreground ""
        $tv tag configure colorinator -foreground gray60
    } elseif {$current == "colorinator"} {
        $tv tag configure rampensau -foreground gray60
        $tv tag configure colorinator -foreground ""
    } else {
        $tv tag configure rampensau -foreground ""
        $tv tag configure colorinator -foreground ""
    }
    $tv tag configure unknown -foreground gray60
}

proc ::simmerblau::on_tab_changed {nb} {
    variable technique
    set technique [string tolower [$nb tab current -text]]
    ::simmerblau::update_library_colors
    ::simmerblau::update_preview
}

# This is the most cursed mess you will ever see. I am so sorry.
proc ::simmerblau::colorinator_load_preset {args} {
    variable colorinator_map
    if {![info exists ::simmerblau::logic::colorinator::colormaps($colorinator_map)]} return
    set stops [set ::simmerblau::logic::colorinator::colormaps($colorinator_map)]
    set ::simmerblau::colorinator_stops $stops
    ::simmerblau::colorinator_select_stop 0 1
    ::simmerblau::update_preview
}

proc ::simmerblau::colorinator_select_stop {idx {force_refresh 0}} {
    variable selected_stop_idx
    set old_idx $selected_stop_idx
    set selected_stop_idx $idx
    variable colorinator_stops
    if {$idx < 0 || $idx >= [llength $colorinator_stops]} return

    set stop [lindex $colorinator_stops $idx]
    lassign $stop pos rgb
    lassign $rgb r g b

    # Update sliders without triggering their traces to avoid feedback loops.
    set ::simmerblau::block_slider_trace 1
    set ::simmerblau::cur_r [format "%.2f" $r]
    set ::simmerblau::cur_g [format "%.2f" $g]
    set ::simmerblau::cur_b [format "%.2f" $b]
    set ::simmerblau::block_slider_trace 0

    # Only refresh the list if forced. Otherwise just update background colors.
    if {$force_refresh} {
        ::simmerblau::colorinator_refresh_editor
    } elseif {$old_idx != $idx} {
        ::simmerblau::colorinator_update_selection_colors $old_idx $idx
    }
}

proc ::simmerblau::colorinator_update_selection_colors {old_idx new_idx} {
    variable w
    set f $w.f.nb.colorinator.stops.stops
    if {![winfo exists $f]} return

    if {$old_idx >= 0 && [winfo exists $f.row_$old_idx]} {
        $f.row_$old_idx configure -bg white
        $f.row_$old_idx.l configure -bg white
    }
    if {$new_idx >= 0 && [winfo exists $f.row_$new_idx]} {
        $f.row_$new_idx configure -bg lightblue
        $f.row_$new_idx.l configure -bg lightblue
    }
}

proc ::simmerblau::colorinator_update_from_sliders {args} {
    variable block_slider_trace
    if {[info exists block_slider_trace] && $block_slider_trace} return

    variable selected_stop_idx
    variable colorinator_stops
    if {$selected_stop_idx < 0 || $selected_stop_idx >= [llength $colorinator_stops]} return

    set rgb [list $::simmerblau::cur_r $::simmerblau::cur_g $::simmerblau::cur_b]
    lset ::simmerblau::colorinator_stops $selected_stop_idx 1 $rgb

    # Update the color swatch in the list without rebuilding the whole thing.
    variable w
    if {[winfo exists $w.f.nb.colorinator.stops.stops.row_$selected_stop_idx.c]} {
        set hex [format "#%02x%02x%02x" [expr {int([lindex $rgb 0]*255)}] [expr {int([lindex $rgb 1]*255)}] [expr {int([lindex $rgb 2]*255)}]]
        $w.f.nb.colorinator.stops.stops.row_$selected_stop_idx.c configure -bg $hex
    }

    ::simmerblau::update_preview
}

proc ::simmerblau::colorinator_refresh_editor {} {
    variable w
    variable selected_stop_idx
    if {![winfo exists $w.f.nb.colorinator.stops.stops]} return
    set f $w.f.nb.colorinator.stops.stops

    # If the focus is currently in an entry, we should be careful about destroying it.
    set focus [focus]
    set focus_idx -1
    if {[string match "$f.row_*.e" $focus]} {
        scan $focus "$f.row_%d.e" focus_idx
    }

    foreach child [winfo children $f] { destroy $child }

    set i 0
    foreach stop $::simmerblau::colorinator_stops {
        lassign $stop pos rgb
        set hex [format "#%02x%02x%02x" [expr {int([lindex $rgb 0]*255)}] [expr {int([lindex $rgb 1]*255)}] [expr {int([lindex $rgb 2]*255)}]]

        set bg "white"
        if {$i == $selected_stop_idx} { set bg "lightblue" }
        set row [frame $f.row_$i -bg $bg]
        pack $row -fill x -pady 2

        label $row.l -text "Stop [expr {$i+1}]" -width 6 -bg $bg
        entry $row.e -width 6
        # Values are rounded to three decimal places for display.
        $row.e insert 0 [format "%.3f" $pos]

        # Bindings:
        # Return/FocusOut: commit change and re-sort.
        # Up/Down: step and re-sort.
        # FocusIn: select but don't rebuild (to avoid losing focus immediately).
        bind $row.e <Return> [list ::simmerblau::colorinator_update_stop_pos $i %W]
        bind $row.e <FocusOut> [list ::simmerblau::colorinator_update_stop_pos $i %W]
        bind $row.e <Up> [list ::simmerblau::colorinator_step_stop_pos $i %W 1]
        bind $row.e <Down> [list ::simmerblau::colorinator_step_stop_pos $i %W -1]
        bind $row.e <FocusIn> [list ::simmerblau::colorinator_select_stop $i]

        canvas $row.c -width 20 -height 20 -bg $hex -highlightthickness 1 -highlightbackground black
        bind $row.c <Button-1> [list ::simmerblau::colorinator_select_stop $i]
        bind $row.l <Button-1> [list ::simmerblau::colorinator_select_stop $i]
        bind $row <Button-1>   [list ::simmerblau::colorinator_select_stop $i]

        pack $row.l $row.e $row.c -side left -padx 5

        # Restore focus if we were editing and this is the selected stop.
        if {$focus_idx >= 0 && $i == $selected_stop_idx} { focus $row.e }
        incr i
    }
}

proc ::simmerblau::colorinator_update_stop_pos {idx widget} {
    set val [$widget get]
    if {![string is double $val]} return

    set old_stop [lindex $::simmerblau::colorinator_stops $idx]
    lassign $old_stop old_val old_rgb
    if {$val == $old_val} return

    lset ::simmerblau::colorinator_stops $idx 0 $val
    set ::simmerblau::colorinator_stops [lsort -real -index 0 $::simmerblau::colorinator_stops]

    # Find the new index of the stop we just moved.
    set new_idx 0
    foreach stop $::simmerblau::colorinator_stops {
        if {abs([lindex $stop 0] - $val) < 0.0001 && [lindex $stop 1] == $old_rgb} {
            break
        }
        incr new_idx
    }
    ::simmerblau::colorinator_select_stop $new_idx 1
    ::simmerblau::update_preview
}

proc ::simmerblau::colorinator_step_stop_pos {idx widget dir} {
    set val [$widget get]
    if {![string is double $val]} { set val 0.0 }
    set res 0.01
    set newVal [expr {$val + $res * $dir}]
    if {$newVal < 0.0} { set newVal 0.0 }
    if {$newVal > 1.0} { set newVal 1.0 }
    $widget delete 0 end
    $widget insert 0 [format "%.2f" $newVal]
    ::simmerblau::colorinator_update_stop_pos $idx $widget
}

proc ::simmerblau::colorinator_pick_color {idx} {
    set old_rgb [lindex [lindex $::simmerblau::colorinator_stops $idx] 1]
    set old_hex [format "#%02x%02x%02x" [expr {int([lindex $old_rgb 0]*255)}] [expr {int([lindex $old_rgb 1]*255)}] [expr {int([lindex $old_rgb 2]*255)}]]
    set new_hex [tk_chooseColor -initialcolor $old_hex -title "Choose Stop Color"]
    if {$new_hex == ""} return

    # Convert hex to RGB 0..1.
    scan [string range $new_hex 1 2] %x r
    scan [string range $new_hex 3 4] %x g
    scan [string range $new_hex 5 6] %x b
    set rgb [list [expr {$r/255.0}] [expr {$g/255.0}] [expr {$b/255.0}]]

    lset ::simmerblau::colorinator_stops $idx 1 $rgb
    ::simmerblau::colorinator_refresh_editor
    ::simmerblau::update_preview
}

proc ::simmerblau::colorinator_add_stop {} {
    variable colorinator_stops
    set n [llength $colorinator_stops]
    if {$n == 0} {
        set colorinator_stops {{0.5 {0.5 0.5 0.5}}}
        set new_idx 0
    } else {
        set last [lindex $colorinator_stops end]
        lassign $last pos rgb
        set new_pos [expr {$pos + 0.1}]
        if {$new_pos > 1.0} { set new_pos 1.0 }
        lappend colorinator_stops [list $new_pos $rgb]
        set new_idx [expr {[llength $colorinator_stops] - 1}]
    }
    # Sort stops by position.
    set colorinator_stops [lsort -real -index 0 $colorinator_stops]
    # Find where the new stop ended up.
    set i 0
    foreach stop $colorinator_stops {
        if {[lindex $stop 0] == $new_pos} { set new_idx $i; break }
        incr i
    }
    ::simmerblau::colorinator_select_stop $new_idx 1
    ::simmerblau::update_preview
}

proc ::simmerblau::colorinator_remove_stop {} {
    variable colorinator_stops
    variable selected_stop_idx
    if {[llength $colorinator_stops] > 1} {
        set colorinator_stops [lreplace $colorinator_stops $selected_stop_idx $selected_stop_idx]
        if {$selected_stop_idx >= [llength $colorinator_stops]} {
            set selected_stop_idx [expr {[llength $colorinator_stops] - 1}]
        }
    }
    ::simmerblau::colorinator_select_stop $selected_stop_idx 1
    ::simmerblau::update_preview
}

proc ::simmerblau::colorinator_snap_spacing {type} {
    set n [llength $::simmerblau::colorinator_stops]
    if {$n < 2} return

    set positions {}
    switch $type {
        "uniform" {
            for {set i 0} {$i < $n} {incr i} { lappend positions [expr {double($i) / ($n - 1)}] }
        }
        "quartile" {
            set q [list 0.0 0.25 0.5 0.75 1.0]
            for {set i 0} {$i < $n} {incr i} {
                if {$i < [llength $q]} { lappend positions [lindex $q $i] } else { lappend positions 1.0 }
            }
        }
        "boxplot" {
            set q [list 0.0 0.25 0.48 0.52 0.75 1.0]
            for {set i 0} {$i < $n} {incr i} {
                if {$i < [llength $q]} { lappend positions [lindex $q $i] } else { lappend positions 1.0 }
            }
        }
    }

    for {set i 0} {$i < $n} {incr i} {
        lset ::simmerblau::colorinator_stops $i 0 [lindex $positions $i]
    }
    ::simmerblau::colorinator_select_stop 0 1
    ::simmerblau::update_preview
}

proc ::simmerblau::simmerblau_gui {} {
    set font "Helvetica"
    set font_explanation "Times 10 italic"
    set fg_subtle gray50
    set pad 5
    set framepad 10
    set wraplength 400

    variable w

    if {[winfo exists .simmerblau]} {
        wm deiconify .simmerblau
        raise .simmerblau
        return
    }
    set w [toplevel ".simmerblau"]
    wm title $w $::simmerblau::plugin_title
    wm resizable $w 1 1
    wm minsize $w 600 850

    set cv [canvas $w.cv -width 100 -height 700 -bg black -highlightthickness 0]
    grid $cv -row 0 -column 0 -sticky nsew -padx $pad -pady $pad
    bind $cv <Configure> { ::simmerblau::update_preview }
    bind $cv <Button-1> { ::simmerblau::on_mouse_down %x %y }
    bind $cv <B1-Motion> { ::simmerblau::on_mouse_move %x %y }
    bind $cv <ButtonRelease-1> { ::simmerblau::on_mouse_up %x %y }

    set f [frame $w.f -padx $framepad -pady $framepad]
    grid $f -row 0 -column 1 -sticky nsew
    grid columnconfigure $w 1 -weight 1
    grid rowconfigure $w 0 -weight 1

    # Header with Undo/Redo and Technique transfer buttons.
    set frh [frame $f.frh]
    pack $frh -fill x -pady "0 $pad"
    button $frh.undo -text "Undo" -command ::simmerblau::trigger_undo
    button $frh.redo -text "Redo" -command ::simmerblau::trigger_redo
    button $frh.to_col -text "Bring to Colorinator" -command ::simmerblau::bring_to_colorinator
    pack $frh.undo $frh.redo -side left -padx 2
    pack $frh.to_col -side right -padx 2

    set nb [ttk::notebook $f.nb]
    pack $nb -fill both -expand 1 -pady $pad
    bind $nb <<NotebookTabChanged>> { ::simmerblau::on_tab_changed %W }

    set frs [frame $nb.rampensau -padx $framepad -pady $framepad]
    $nb add $frs -text "RampenSau"

    set frp [frame $nb.colorinator -padx $framepad -pady $framepad]
    $nb add $frp -text "Colorinator"

    set pce [labelframe $frp.editor -text "Stop color" -padx $framepad -pady $framepad]
    pack $pce -fill x -pady $pad
    label $pce.desc -text "Adjust RGB values of the selected stop." \
        -font $font_explanation -fg $fg_subtle -wraplength $wraplength -justify left
    pack $pce.desc -anchor w -pady "0 $pad"

    ::simmerblau::create_control $pce "Red" cur_r 0 1
    ::simmerblau::create_control $pce "Green" cur_g 0 1
    ::simmerblau::create_control $pce "Blue" cur_b 0 1
    foreach child [winfo children $pce] { if {$child != "$pce.desc"} { pack $child -fill x -expand 1 } }

    set pms [labelframe $frp.stops -text "Custom stops" -padx $framepad -pady $framepad]
    pack $pms -fill both -expand 1 -pady $pad

    label $pms.desc -text "Flexible color mapping with adjustable control points. \
        Based on Colorinator in PECOC by Tsjerk Wassenaar." \
        -font $font_explanation -fg $fg_subtle -wraplength $wraplength -justify left
    pack $pms.desc -anchor w -pady "0 $pad"

    set fbn [frame $pms.btns]
    pack $fbn -fill x -pady $pad
    button $fbn.add -text "Add Stop" -command ::simmerblau::colorinator_add_stop
    button $fbn.rem -text "Remove Stop" -command ::simmerblau::colorinator_remove_stop
    pack $fbn.add $fbn.rem -side left -padx 2

    set fst [frame $pms.stops]
    pack $fst -fill both -expand 1 -pady $pad

    set fsn [frame $pms.snap]
    pack $fsn -fill x -pady $pad
    label $fsn.desc -text "Snap positions to common distributions or load a preset map:" \
        -font $font_explanation -fg $fg_subtle -wraplength $wraplength -justify left
    pack $fsn.desc -anchor w -pady "5 2"

    button $fsn.uni -text "Uniform" -command {::simmerblau::colorinator_snap_spacing "uniform"}
    button $fsn.qua -text "Quartile" -command {::simmerblau::colorinator_snap_spacing "quartile"}
    button $fsn.box -text "Boxplot" -command {::simmerblau::colorinator_snap_spacing "boxplot"}
    pack $fsn.uni $fsn.qua $fsn.box -side left -padx 2

    # Map preset menu aligned to the right.
    set c_opts [list "SBW" "BWR" "PRGn" "Spectral" "Viridis" "BGW" "RYW" "PMG" "HWC" "Blues" "Reds" "VanGogh" "Peacock" "Heat" "BWO" "PeacockMagenta"]
    eval [list tk_optionMenu $fsn.m ::simmerblau::colorinator_map] $c_opts
    pack $fsn.m -side right -padx 2

    set pm [labelframe $frs.mode -text "Color space" -padx $framepad -pady $framepad]
    pack $pm -fill x -pady $pad
    label $pm.desc -text "OKLCH tries to provide uniform perceived brightness. \
        The Harvey fix smooths out clumped blue/green hues to give a more natural spectrum." \
        -font $font_explanation -fg $fg_subtle -wraplength $wraplength -justify left
    pack $pm.desc -anchor w -pady "0 $pad"

    set frm [frame $pm.frm]
    label $frm.l1 -text "Space"
    radiobutton $frm.r1 -text "HSL" -value "HSL" -variable ::simmerblau::colorSpace
    radiobutton $frm.r2 -text "OKLCH" -value "OKLCH" -variable ::simmerblau::colorSpace
    checkbutton $frm.c1 -text "Harvey fix" -variable ::simmerblau::useHarvey
    pack $frm.l1 $frm.r1 $frm.r2 $frm.c1 -side left -padx $pad
    pack $frm -fill x

    set phue [labelframe $frs.hue -text "Hue" -padx $framepad -pady $framepad]
    pack $phue -fill x -pady $pad
    label $phue.desc -text "Defines the path through the color wheel." \
        -font $font_explanation -fg $fg_subtle -wraplength $wraplength -justify left
    pack $phue.desc -anchor w -pady "0 $pad"

    set frh [frame $phue.frh]
    label $frh.l -text "Scheme" -width $::simmerblau::label_width -anchor w
    set h_opts [list "none" "complementary" "triadic" "split" "tetradic" "analogous"]
    eval [list tk_optionMenu $frh.m ::simmerblau::harmony] $h_opts
    button $frh.rand -text "Randomize palette" -command ::simmerblau::randomize
    pack $frh.l $frh.m -side left
    pack $frh.rand -side right
    pack $frh -fill x -pady $pad
    ::simmerblau::create_control $phue "Start" hStart 0 360 1
    ::simmerblau::create_control $phue "Cycles" hCycles -2 2
    ::simmerblau::create_control $phue "Center" hStartCenter 0 1
    foreach child [winfo children $phue] { if {$child != "$frh" && $child != "$phue.desc"} { pack $child -fill x -expand 1 } }

    set psl [labelframe $frs.sl -text "Vibrancy & brightness" -padx $framepad -pady $framepad]
    pack $psl -fill x -pady $pad
    label $psl.desc -text "Controls color intensity and brightness." \
        -font $font_explanation -fg $fg_subtle -wraplength $wraplength -justify left
    pack $psl.desc -anchor w -pady "0 $pad"
    ::simmerblau::create_control $psl "Saturation min" sMin 0 1
    ::simmerblau::create_control $psl "Saturation max" sMax 0 1
    ::simmerblau::create_control $psl "Lightness min" lMin 0 1
    ::simmerblau::create_control $psl "Lightness max" lMax 0 1
    foreach child [winfo children $psl] { if {$child != "$psl.desc"} { pack $child -fill x -expand 1 } }

    set pc [labelframe $frs.curve -text "Flow" -padx $framepad -pady $framepad]
    pack $pc -fill x -pady $pad
    label $pc.desc -text "Control the accelaration through the color ramp." \
        -font $font_explanation -fg $fg_subtle -wraplength $wraplength -justify left
    pack $pc.desc -anchor w -pady "0 $pad"

    set frc [frame $pc.frc]
    radiobutton $frc.r1 -text "Lamé" -value "lamé" -variable ::simmerblau::curveMethod
    radiobutton $frc.r2 -text "Arc" -value "arc" -variable ::simmerblau::curveMethod
    radiobutton $frc.r3 -text "Power" -value "power" -variable ::simmerblau::curveMethod
    radiobutton $frc.r4 -text "Shift Y" -value "powY" -variable ::simmerblau::curveMethod
    radiobutton $frc.r5 -text "Shift X" -value "powX" -variable ::simmerblau::curveMethod
    radiobutton $frc.r6 -text "Linear" -value "linear" -variable ::simmerblau::curveMethod
    pack $frc.r1 $frc.r2 $frc.r3 $frc.r4 $frc.r5 $frc.r6 -side left -expand 1
    pack $frc -fill x
    ::simmerblau::create_control $pc "Flow intensity" curveAccent 0 5
    foreach child [winfo children $pc] { if {$child != "$frc" && $child != "$pc.desc"} { pack $child -fill x -expand 1 } }

    set pl [labelframe $f.lib -text "Palette library" -padx $framepad -pady $framepad]
    pack $pl -fill x -pady $pad
    label $pl.desc -text "Palettes will be loaded from the .simmerblau directory if present. \
        Globally accessible palettes are stored in ~/.config/simmerblau." \
        -font $font_explanation -fg $fg_subtle -wraplength $wraplength -justify left
    pack $pl.desc -anchor w -pady "0 $pad"

    set frtv [frame $pl.frtv]
    pack $frtv -fill x -pady $pad

    ttk::treeview $frtv.tv -columns {tech} -show tree -height 5 -selectmode browse
    $frtv.tv column #0 -stretch 1 -width 150
    $frtv.tv column tech -stretch 0 -width 120 -anchor e

    scrollbar $frtv.vsb -orient vertical -command [list $frtv.tv yview]
    $frtv.tv configure -yscrollcommand [list $frtv.vsb set]

    pack $frtv.vsb -side right -fill y
    pack $frtv.tv -side left -fill x -expand 1

    bind $frtv.tv <<TreeviewSelect>> {
        set sel [%W selection]
        if {$sel != ""} {
            ::simmerblau::load_palette [%W item $sel -text]
        }
    }

    set frl [frame $pl.frl]
    button $frl.save -text "Save current" -command {
        set name [::simmerblau::tk_inputDialog "Save Palette" "Enter name:"]
        if {$name != ""} { ::simmerblau::save_palette $name }
    }
    button $frl.refresh -text "Refresh" -command ::simmerblau::refresh_library
    pack $frl.save $frl.refresh -side left -padx 2
    pack $frl -fill x


    set pa [labelframe $f.apply -text "Apply to target" -padx $framepad -pady $framepad]
    pack $pa -fill x -pady $pad

    set frt [frame $pa.frt]
    radiobutton $frt.r1 -text "Color IDs (0-32)" -value "0-32" -variable ::simmerblau::targetRange
    radiobutton $frt.r2 -text "Color scale" -value "Scale" -variable ::simmerblau::targetRange
    checkbutton $frt.live -text "Live preview" -variable ::simmerblau::livePreview
    button $frt.btn -text "Apply to VMD" -font "$font 9 bold" -command ::simmerblau::apply_ramp -pady 2

    pack $frt.r1 $frt.r2 $frt.live -side left -padx 5
    pack $frt.btn -side right -padx 5
    pack $frt -fill x -pady 2
    foreach var {technique total colorinator_map colorinator_stops selected_stop_idx hStart hCycles hStartCenter sMin sMax lMin lMax curveMethod curveAccent targetRange livePreview useHarvey colorSpace harmony} { trace add variable ::simmerblau::$var write "::simmerblau::trace_update" }
    trace add variable ::simmerblau::colorinator_map write "::simmerblau::colorinator_load_preset"
    foreach var {cur_r cur_g cur_b} { trace add variable ::simmerblau::$var write "::simmerblau::colorinator_update_from_sliders" }

    # Byline at the bottom.
    label $f.byline -text "By Marieke Westendorp & Aster Kovács at the University of Groningen.\n\
        Color generation based on RampenSau by David Aerne (meodai)\n\
        and the Colorinator in the PECOC project by Tsjerk Wassenaar." \
        -font "$font 7 italic" -fg $fg_subtle -wraplength $wraplength -justify center
    pack $f.byline -side bottom -fill x -pady {10 0}

    ::simmerblau::refresh_library
    if {[file exists [file join [::simmerblau::get_storage_path] "default.json"]]} { catch { ::simmerblau::load_palette "default" } }
    ::simmerblau::push_undo_snapshot
    ::simmerblau::colorinator_refresh_editor
    ::simmerblau::update_preview
}

proc ::simmerblau::tk_inputDialog {title msg} {
    set ::simmerblau::input_dialog_res ""
    set d [toplevel .input_dialog]
    wm title $d $title
    label $d.l -text $msg
    entry $d.e
    frame $d.f
    button $d.f.ok -text "OK" -command {
        set ::simmerblau::input_dialog_res [.input_dialog.e get]
        destroy .input_dialog
    }
    button $d.f.can -text "Cancel" -command {
        set ::simmerblau::input_dialog_res ""
        destroy .input_dialog
    }
    pack $d.l $d.e $d.f -padx 10 -pady 10
    pack $d.f.ok $d.f.can -side left -padx 5
    vwait ::simmerblau::input_dialog_res
    return $::simmerblau::input_dialog_res
}

proc ::simmerblau::randomize {} {
    set ::simmerblau::hStart [format "%.2f" [expr {rand() * 360.0}]]
    set ::simmerblau::hCycles [format "%.2f" [expr {rand() * 2.0 - 1.0}]]
}

proc ::simmerblau::trace_update {args} {
    variable w
    variable livePreview
    ::simmerblau::update_preview
    ::simmerblau::debounce_snapshot
    if {$livePreview} {
        if {[winfo exists $w.f.apply.btn]} { $w.f.apply.btn configure -state disabled }
        catch { ::simmerblau::apply_ramp }
    } else {
        if {[winfo exists $w.f.apply.btn]} { $w.f.apply.btn configure -state normal }
    }
}

proc ::simmerblau::on_canvas_click {x y} {
    variable w
    variable lockedColors
    variable total

    set canvas $w.cv
    set width [winfo width $canvas]
    # Only palette side is lockable.
    if {$x > ($width / 2.0)} return

    set height [winfo height $canvas]
    # We always show 33 slots for the palette side.
    set num_boxes 33
    set step [expr {double($height) / $num_boxes}]
    set idx [expr {int(floor($y / $step))}]

    if {[dict exists $lockedColors $idx]} {
        dict unset lockedColors $idx
    } else {
        # Lock current projected color.
        set ramp [::simmerblau::generate_ramp $total]

        # Calculate the color value for this specific slot.
        set color_idx $idx
        if {$idx >= [llength $ramp]} { set color_idx [expr {[llength $ramp] - 1}] }
        if {$color_idx < 0} { set color_idx 0 }

        set rgb [lindex $ramp $color_idx]
        dict set lockedColors $idx $rgb
        }

    ::simmerblau::update_preview
    if {$::simmerblau::livePreview} { ::simmerblau::apply_ramp }
}

proc ::simmerblau::update_preview {args} {
    variable w; if {![winfo exists $w]} return
    set canvas $w.cv
    $canvas delete all

    set height [winfo height $canvas]; if {$height <= 1} { set height 700 }
    set width [winfo width $canvas]; if {$width <= 1} { set width 100 }
    set half [expr {$width / 2.0}]

    # Full colorscale gradient.
    # Visual resolution for preview.
    set num_scale 256
    if {[catch {
        set scale_ramp [::simmerblau::generate_ramp $num_scale]
    } msg]} { return }

    set s_step [expr {double($height) / $num_scale}]
    set sy 0
    foreach rgb $scale_ramp {
        set hex [format "#%02x%02x%02x" [expr {int([lindex $rgb 0]*255)}] [expr {int([lindex $rgb 1]*255)}] [expr {int([lindex $rgb 2]*255)}]]
        $canvas create rectangle $half $sy $width [expr {$sy + $s_step}] -fill $hex -outline ""
        set sy [expr {$sy + $s_step}]
    }

    # Discrete palette for the Color IDs.
    set num_palette 33
    set p_ramp [::simmerblau::generate_ramp $::simmerblau::total]

    set p_step [expr {double($height) / $num_palette}]
    for {set i 0} {$i < $num_palette} {incr i} {
        set py [expr {$i * $p_step}]

        # Determine the cell's color.
        if {[dict exists $::simmerblau::lockedColors $i]} {
            set rgb [dict get $::simmerblau::lockedColors $i]
            set is_locked 1
        } else {
            set color_idx $i
            if {$i >= [llength $p_ramp]} { set color_idx [expr {[llength $p_ramp] - 1}] }
            if {$color_idx < 0} { set color_idx 0 }
            set rgb [lindex $p_ramp $color_idx]
            set is_locked 0
        }

        set hex [format "#%02x%02x%02x" [expr {int([lindex $rgb 0]*255)}] [expr {int([lindex $rgb 1]*255)}] [expr {int([lindex $rgb 2]*255)}]]
        $canvas create rectangle 0 $py $half [expr {$py + $p_step}] -fill $hex -outline "#ffffff"

        # Visual indicator for locking.
        if {$is_locked} {
            set cx [expr {$half / 2.0}]
            set cy [expr {$py + $p_step / 2.0}]
            set r 3
            # Contrast dot.
            set dot_fill "white"
            set lum [expr {0.2126*[lindex $rgb 0] + 0.7152*[lindex $rgb 1] + 0.0722*[lindex $rgb 2]}]
            if {$lum > 0.5} { set dot_fill "black" }
            $canvas create oval [expr {$cx-$r}] [expr {$cy-$r}] [expr {$cx+$r}] [expr {$cy+$r}] -fill $dot_fill -outline ""
        }
    }

    # Draw Colorinator stop markers if active.
    variable technique
    if {$technique == "colorinator"} {
        variable colorinator_stops
        set i 0
        foreach stop $colorinator_stops {
            lassign $stop pos rgb
            set py [expr {$pos * $height}]
            set px [expr {$width * 0.75}]
            set r 4

            # A contrast dot is drawn for visibility.
            set dot_fill "white"
            set lum [expr {0.2126*[lindex $rgb 0] + 0.7152*[lindex $rgb 1] + 0.0722*[lindex $rgb 2]}]
            if {$lum > 0.5} { set dot_fill "black" }

            $canvas create oval [expr {$px-$r}] [expr {$py-$r}] [expr {$px+$r}] [expr {$py+$r}] -fill $dot_fill -outline "#888888" -tags [list stop_marker stop_$i]

            # A contrasting ring highlights the selected stop.
            variable selected_stop_idx
            if {$i == $selected_stop_idx} {
                set r2 [expr {$r + 3}]
                $canvas create oval [expr {$px-$r2}] [expr {$py-$r2}] [expr {$px+$r2}] [expr {$py+$r2}] -outline $dot_fill -width 2 -tags selection_ring
            }
            incr i
        }
    }
}

proc ::simmerblau::on_mouse_down {x y} {
    variable w
    variable dragging_stop_idx
    set canvas $w.cv

    # First, check if a stop marker was clicked.
    set items [$canvas find overlapping [expr {$x-3}] [expr {$y-3}] [expr {$x+3}] [expr {$y+3}]]
    foreach item $items {
        set tags [$canvas gettags $item]
        if {[lsearch $tags "stop_marker"] != -1} {
            foreach tag $tags {
                if {[scan $tag "stop_%d" idx] == 1} {
                    set dragging_stop_idx $idx
                    ::simmerblau::colorinator_select_stop $idx
                    return
                }
            }
        }
    }

    # If no marker was clicked, fall back to the locking logic for the palette.
    ::simmerblau::on_canvas_click $x $y
}

proc ::simmerblau::on_mouse_move {x y} {
    variable dragging_stop_idx
    if {$dragging_stop_idx < 0} return

    variable w
    set canvas $w.cv
    set height [winfo height $canvas]
    if {$height <= 1} { set height 700 }

    # Calculate the normalized position.
    set pos [expr {double($y) / $height}]
    if {$pos < 0.0} { set pos 0.0 }
    if {$pos > 1.0} { set pos 1.0 }

    # Update the stop position during the drag.
    lset ::simmerblau::colorinator_stops $dragging_stop_idx 0 $pos
    ::simmerblau::update_preview
}

proc ::simmerblau::on_mouse_up {x y} {
    variable dragging_stop_idx
    if {$dragging_stop_idx < 0} return

    # Commit the final position and sort.
    set idx $dragging_stop_idx
    set dragging_stop_idx -1

    variable w
    set canvas $w.cv
    set height [winfo height $canvas]
    if {$height <= 1} { set height 700 }
    set pos [expr {double($y) / $height}]
    if {$pos < 0.0} { set pos 0.0 }
    if {$pos > 1.0} { set pos 1.0 }

    # Find the new index of the stop after sorting.
    set old_rgb [lindex [lindex $::simmerblau::colorinator_stops $idx] 1]
    lset ::simmerblau::colorinator_stops $idx 0 $pos
    set ::simmerblau::colorinator_stops [lsort -real -index 0 $::simmerblau::colorinator_stops]

    set new_idx 0
    foreach stop $::simmerblau::colorinator_stops {
        if {abs([lindex $stop 0] - $pos) < 0.0001 && [lindex $stop 1] == $old_rgb} {
            break
        }
        incr new_idx
    }

    # A full refresh is triggered upon release to update the editor rows.
    ::simmerblau::colorinator_select_stop $new_idx 1
    ::simmerblau::update_preview
}

proc ::simmerblau::apply_ramp {} {
    variable targetRange
    variable total
    set ramp [::simmerblau::generate_ramp $::simmerblau::total]
    if {$targetRange == "0-32"} {
        set i 0
        foreach rgb $ramp {
            if {$i > 32} break
            # Skip white.
            if {$i == 8} { incr i }

            # Respect locked colors.
            if {[dict exists $::simmerblau::lockedColors $i]} {
                incr i
                continue
            }

            color change rgb $i {*}$rgb
            incr i
        }
    } else {
        set start_id [colorinfo num]
        set max_id [colorinfo max]
        set num_colors [expr {$max_id - $start_id}]
        if {$num_colors <= 0} return
        set scale_ramp [::simmerblau::generate_ramp $num_colors]
        set i $start_id
        foreach rgb $scale_ramp {
            color change rgb $i {*}$rgb
            incr i
        }
    }
}

if {[info commands vmd_install_extension] != ""} { vmd_install_extension simmerblau simmerblau_tk_cb "Visualization/Simmerblau Colors" }
