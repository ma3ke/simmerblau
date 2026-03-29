# Simmerblau is a VMD plugin that lets you generate parameterized color palettes.
#
# The color generation system is based on the wonderful RampenSau by David Aerne, which is
# distributed under the MIT license: https://github.com/meodai/rampensau.
#
# Marieke Westendorp & Aster Kovács, 2026.

package provide simmerblau 1.0

set dir [file dirname [info script]]
source [file join $dir rampensau.tcl]

namespace eval ::simmerblau:: {
    variable w
    variable total 32
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
    # Dictionary of the index to {r g b}.
    variable lockedColors {}
    set plugin_title "Simmerblau Colors"
    set label_width 14
}

proc simmerblau_tk_cb {} {
    ::simmerblau::simmerblau_gui
    return $::simmerblau::w
}

proc ::simmerblau::get_current_state {} {
    set state {}
    foreach var {total hStart hCycles hStartCenter sMin sMax lMin lMax curveMethod curveAccent useHarvey colorSpace harmony} {
        dict set state $var [set ::simmerblau::$var]
    }
    return $state
}

proc ::simmerblau::set_current_state {state} {
    foreach {var val} $state { set ::simmerblau::$var $val }
    ::simmerblau::update_preview
}

proc ::simmerblau::update_button_states {} {
    variable w
    variable undoStack
    variable redoStack
    if {![winfo exists $w]} return
    set u_btn $w.f.apply.frh.undo
    set r_btn $w.f.apply.frh.redo
    if {[winfo exists $u_btn]} { if {[llength $undoStack] > 1} { $u_btn configure -state normal } else { $u_btn configure -state disabled } }
    if {[winfo exists $r_btn]} { if {[llength $redoStack] > 0} { $r_btn configure -state normal } else { $r_btn configure -state disabled } }
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

proc ::simmerblau::save_palette {name} {
    if {$name == ""} return
    variable version
    package require json::write
    set path [::simmerblau::get_storage_path]
    set filename [file join $path "${name}.json"]
    set ramp [::simmerblau::logic::generate_ramp \
        -total $::simmerblau::total \
        -hStart $::simmerblau::hStart \
        -hCycles $::simmerblau::hCycles \
        -hStartCenter $::simmerblau::hStartCenter \
        -sRange [list $::simmerblau::sMin $::simmerblau::sMax] \
        -lRange [list $::simmerblau::lMin $::simmerblau::lMax] \
        -curveMethod $::simmerblau::curveMethod \
        -curveAccent $::simmerblau::curveAccent \
        -useHarvey $::simmerblau::useHarvey \
        -harmony $::simmerblau::harmony
    ]
    set hex_items {}
    foreach color $ramp {
        if {$::simmerblau::colorSpace == "OKLCH"} { set rgb [::simmerblau::logic::oklch2rgb [lindex $color 2] [expr {[lindex $color 1] * 0.4}] [lindex $color 0]] } else { set rgb [::simmerblau::logic::hsl2rgb {*}$color] }
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
    set lb $w.f.lib.lb; $lb delete 0 end
    set path [::simmerblau::get_storage_path]
    foreach f [glob -nocomplain -directory $path -tails *.json] { $lb insert end [file rootname $f] }
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

# This is the most cursed mess you will ever see. I am so sorry.
proc ::simmerblau::simmerblau_gui {} {
    set font "Helvetica"
    set font_explanation "Times 10 italic"
    set fg_subtle gray50
    set pad 5
    set framepad 10
    set wraplength 450

    variable w

    if {[winfo exists .simmerblau]} {
        wm deiconify .simmerblau
        raise .simmerblau
        return
    }
    set w [toplevel ".simmerblau"]
    wm title $w $::simmerblau::plugin_title
    wm resizable $w 1 1
    wm minsize $w 600 950

    set cv [canvas $w.cv -width 100 -height 700 -bg black -highlightthickness 0]
    grid $cv -row 0 -column 0 -sticky nsew -padx $pad -pady $pad
    bind $cv <Configure> { ::simmerblau::update_preview }
    bind $cv <Button-1> { ::simmerblau::on_canvas_click %x %y }

    set f [frame $w.f -padx $framepad -pady $framepad]
    grid $f -row 0 -column 1 -sticky nsew
    grid columnconfigure $w 1 -weight 1
    grid rowconfigure $w 0 -weight 1

    set pm [labelframe $f.mode -text "Color space" -padx $framepad -pady $framepad]
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

    set phue [labelframe $f.hue -text "Hue" -padx $framepad -pady $framepad]
    pack $phue -fill x -pady $pad
    label $phue.desc -text "Defines the path through the color wheel." \
        -font $font_explanation -fg $fg_subtle -wraplength $wraplength -justify left
    pack $phue.desc -anchor w -pady "0 $pad"

    set frh [frame $phue.frh]
    label $frh.l -text "Scheme" -width $::simmerblau::label_width -anchor w
    set h_opts [list "none" "complementary" "triadic" "split" "tetradic" "analogous"]
    eval [list tk_optionMenu $frh.m ::simmerblau::harmony] $h_opts
    pack $frh.l $frh.m -side left
    pack $frh -fill x -pady $pad
    ::simmerblau::create_control $phue "Start" hStart 0 360 1
    ::simmerblau::create_control $phue "Cycles" hCycles -2 2
    ::simmerblau::create_control $phue "Center" hStartCenter 0 1
    foreach child [winfo children $phue] { if {$child != "$frh" && $child != "$phue.desc"} { pack $child -fill x -expand 1 } }

    set psl [labelframe $f.sl -text "Vibrancy & brightness" -padx $framepad -pady $framepad]
    pack $psl -fill x -pady $pad
    label $psl.desc -text "Controls color intensity and brightness." \
        -font $font_explanation -fg $fg_subtle -wraplength $wraplength -justify left
    pack $psl.desc -anchor w -pady "0 $pad"
    ::simmerblau::create_control $psl "Saturation min" sMin 0 1
    ::simmerblau::create_control $psl "Saturation max" sMax 0 1
    ::simmerblau::create_control $psl "Lightness min" lMin 0 1
    ::simmerblau::create_control $psl "Lightness max" lMax 0 1
    foreach child [winfo children $psl] { if {$child != "$psl.desc"} { pack $child -fill x -expand 1 } }

    set pc [labelframe $f.curve -text "Flow" -padx $framepad -pady $framepad]
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
    label $pl.desc -text "If you have a .simmerblau directory in your project, palettes will be loaded from there. \
        Globally accessible palettes are stored in ~/.config/simmerblau." \
        -font $font_explanation -fg $fg_subtle -wraplength $wraplength -justify left
    pack $pl.desc -anchor w -pady "0 $pad"
    listbox $pl.lb -height 5 -exportselection 0
    pack $pl.lb -fill x -pady $pad
    bind $pl.lb <<ListboxSelect>> { if {[%W curselection] != ""} { ::simmerblau::load_palette [%W get [%W curselection]] } }

    set frl [frame $pl.frl]
    button $frl.save -text "Save current" -command {
        set name [::simmerblau::tk_inputDialog "Save Palette" "Enter name:"]
        if {$name != ""} { ::simmerblau::save_palette $name }
    }
    button $frl.refresh -text "Refresh" -command ::simmerblau::refresh_library
    button $frl.rand -text "Randomize palette" -command ::simmerblau::randomize
    pack $frl.save $frl.refresh $frl.rand -side left -expand 1
    pack $frl -fill x


    set pa [labelframe $f.apply -text "Apply to target" -padx $framepad -pady $framepad]
    pack $pa -fill x -pady $pad
    ::simmerblau::create_control $pa "Steps" total 1 128 1

    set frt [frame $pa.frt]
    radiobutton $frt.r1 -text "Color IDs (0-32)" -value "0-32" -variable ::simmerblau::targetRange
    radiobutton $frt.r2 -text "Color scale" -value "Scale" -variable ::simmerblau::targetRange
    checkbutton $frt.live -text "Live preview" -variable ::simmerblau::livePreview
    pack $frt.r1 $frt.r2 $frt.live -side left -expand 1
    pack $frt -fill x -pady $pad
    button $pa.btn -text "Apply to VMD" -font "$font 10 bold" -command ::simmerblau::apply_ramp
    pack $pa.btn -fill x -pady $pad

    set frh [frame $pa.frh]
    button $frh.undo -text "Undo" -command ::simmerblau::trigger_undo
    button $frh.redo -text "Redo" -command ::simmerblau::trigger_redo
    pack $frh.undo $frh.redo -side left -expand 1
    pack $frh -fill x -pady $pad
    foreach var {total hStart hCycles hStartCenter sMin sMax lMin lMax curveMethod curveAccent targetRange livePreview useHarvey colorSpace harmony} { trace add variable ::simmerblau::$var write "::simmerblau::trace_update" }

    # Byline at the bottom.
    label $f.byline -text "By Marieke Westendorp & Aster Kovács, based on Rampensau by David Aerne (meodai)." \
        -font "$font 7 italic" -fg $fg_subtle -wraplength $wraplength -justify center
    pack $f.byline -side bottom -fill x -pady {10 0}

    ::simmerblau::refresh_library
    if {[file exists [file join [::simmerblau::get_storage_path] "default.json"]]} { catch { ::simmerblau::load_palette "default" } }
    ::simmerblau::push_undo_snapshot
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
    set ::simmerblau::sMin [format "%.2f" [expr {rand() * 0.5}]]
    set ::simmerblau::sMax [format "%.2f" [expr {0.5 + rand() * 0.5}]]
    set ::simmerblau::lMin [format "%.2f" [expr {rand() * 0.3}]]
    set ::simmerblau::lMax [format "%.2f" [expr {0.7 + rand() * 0.3}]]
    set ::simmerblau::curveAccent [format "%.2f" [expr {rand() * 2.0}]]
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
        set ramp [::simmerblau::logic::generate_ramp \
            -total $total \
            -hStart $::simmerblau::hStart \
            -hCycles $::simmerblau::hCycles \
            -hStartCenter $::simmerblau::hStartCenter \
            -sRange [list $::simmerblau::sMin $::simmerblau::sMax] \
            -lRange [list $::simmerblau::lMin $::simmerblau::lMax] \
            -curveMethod $::simmerblau::curveMethod \
            -curveAccent $::simmerblau::curveAccent \
            -useHarvey $::simmerblau::useHarvey \
            -harmony $::simmerblau::harmony]

        # Calculate color for this slot.
        set color_idx $idx
        if {$idx >= [llength $ramp]} { set color_idx [expr {[llength $ramp] - 1}] }
        if {$color_idx < 0} { set color_idx 0 }

        set color [lindex $ramp $color_idx]
        if {$::simmerblau::colorSpace == "OKLCH"} {
            set rgb [::simmerblau::logic::oklch2rgb [lindex $color 2] [expr {[lindex $color 1] * 0.4}] [lindex $color 0]]
        } else {
            set rgb [::simmerblau::logic::hsl2rgb {*}$color]
        }
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
        set scale_ramp [::simmerblau::logic::generate_ramp \
            -total $num_scale \
            -hStart $::simmerblau::hStart \
            -hCycles $::simmerblau::hCycles \
            -hStartCenter $::simmerblau::hStartCenter \
            -sRange [list $::simmerblau::sMin $::simmerblau::sMax] \
            -lRange [list $::simmerblau::lMin $::simmerblau::lMax] \
            -curveMethod $::simmerblau::curveMethod \
            -curveAccent $::simmerblau::curveAccent \
            -useHarvey $::simmerblau::useHarvey \
            -harmony $::simmerblau::harmony]
    } msg]} { return }

    set s_step [expr {double($height) / $num_scale}]
    set sy 0
    foreach color $scale_ramp {
        if {$::simmerblau::colorSpace == "OKLCH"} {
            set rgb [::simmerblau::logic::oklch2rgb [lindex $color 2] [expr {[lindex $color 1] * 0.4}] [lindex $color 0]]
        } else {
            set rgb [::simmerblau::logic::hsl2rgb {*}$color]
        }
        set hex [format "#%02x%02x%02x" [expr {int([lindex $rgb 0]*255)}] [expr {int([lindex $rgb 1]*255)}] [expr {int([lindex $rgb 2]*255)}]]
        $canvas create rectangle $half $sy $width [expr {$sy + $s_step}] -fill $hex -outline ""
        set sy [expr {$sy + $s_step}]
    }

    # Discrete palette for the Color IDs.
    set num_palette 33
    set p_ramp [::simmerblau::logic::generate_ramp \
        -total $::simmerblau::total \
        -hStart $::simmerblau::hStart \
        -hCycles $::simmerblau::hCycles \
        -hStartCenter $::simmerblau::hStartCenter \
        -sRange [list $::simmerblau::sMin $::simmerblau::sMax] \
        -lRange [list $::simmerblau::lMin $::simmerblau::lMax] \
        -curveMethod $::simmerblau::curveMethod \
        -curveAccent $::simmerblau::curveAccent \
        -useHarvey $::simmerblau::useHarvey \
        -harmony $::simmerblau::harmony]

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
            set color [lindex $p_ramp $color_idx]
            if {$::simmerblau::colorSpace == "OKLCH"} {
                set rgb [::simmerblau::logic::oklch2rgb [lindex $color 2] [expr {[lindex $color 1] * 0.4}] [lindex $color 0]]
            } else {
                set rgb [::simmerblau::logic::hsl2rgb {*}$color]
            }
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
}

proc ::simmerblau::apply_ramp {} {
    variable targetRange
    variable total
    set ramp [::simmerblau::logic::generate_ramp \
        -total $::simmerblau::total \
        -hStart $::simmerblau::hStart \
        -hCycles $::simmerblau::hCycles \
        -hStartCenter $::simmerblau::hStartCenter \
        -sRange [list $::simmerblau::sMin $::simmerblau::sMax] \
        -lRange [list $::simmerblau::lMin $::simmerblau::lMax] \
        -curveMethod $::simmerblau::curveMethod \
        -curveAccent $::simmerblau::curveAccent \
        -useHarvey $::simmerblau::useHarvey \
        -harmony $::simmerblau::harmony
    ]
    if {$targetRange == "0-32"} {
        set i 0
        foreach color $ramp {
            if {$i > 32} break
            # Skip white.
            if {$i == 8} { incr i }

            # Respect locked colors.
            if {[dict exists $::simmerblau::lockedColors $i]} {
                incr i
                continue
            }

            if {$::simmerblau::colorSpace == "OKLCH"} {
                set rgb [::simmerblau::logic::oklch2rgb [lindex $color 2] [expr {[lindex $color 1] * 0.4}] [lindex $color 0]]
            } else {
                set rgb [::simmerblau::logic::hsl2rgb {*}$color]
            }
            color change rgb $i {*}$rgb
            incr i
        }
    } else {
        set start_id [colorinfo num]
        set max_id [colorinfo max]
        set num_colors [expr {$max_id - $start_id}]
        if {$num_colors <= 0} return
        set scale_ramp [::simmerblau::logic::generate_ramp -total $num_colors -hStart $::simmerblau::hStart -hCycles $::simmerblau::hCycles -hStartCenter $::simmerblau::hStartCenter -sRange [list $::simmerblau::sMin $::simmerblau::sMax] -lRange [list $::simmerblau::lMin $::simmerblau::lMax] -curveMethod $::simmerblau::curveMethod -curveAccent $::simmerblau::curveAccent -useHarvey $::simmerblau::useHarvey -harmony $::simmerblau::harmony]
        set i $start_id
        foreach color $scale_ramp {
            if {$::simmerblau::colorSpace == "OKLCH"} { set rgb [::simmerblau::logic::oklch2rgb [lindex $color 2] [expr {[lindex $color 1] * 0.4}] [lindex $color 0]] } else { set rgb [::simmerblau::logic::hsl2rgb {*}$color] }
            color change rgb $i {*}$rgb
            incr i
        }
    }
}

if {[info commands vmd_install_extension] != ""} { vmd_install_extension simmerblau simmerblau_tk_cb $::simmerblau::plugin_title }
