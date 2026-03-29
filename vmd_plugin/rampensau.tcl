# Ported from the excellent RampenSau (https://github.com/meodai/rampensau) by David Aerne, which is
# distributed under the MIT license.


namespace eval ::simmerblau::logic {

    variable PI 3.1415926535897931

    proc normalize_hue {h} {
        set h [expr {fmod($h, 360.0)}]
        if {$h < 0} { set h [expr {$h + 360.0}] }
        return $h
    }

    # From the RampenSau README:
    #   Transforms a hue to create a more evenly distributed spectrum without the over-abundance of
    #   green and ultramarine in the standard HSL/HSV color wheel. Originally written by
    #   [@harvey](https://twitter.com/harvey_rayner/status/1748159440010809665) and adapted for
    #   use in RampenSau.
    proc harvey_hue {h} {
        variable PI
        set h [expr {[normalize_hue $h] / 360.0}]
        if {$h == 1.0 || $h == 0.0} { return [expr {$h * 360.0}] }
        set seg [expr {1.0 / 6.0}]
        set a [expr {((fmod($h, $seg) / $seg) * $PI) / 2.0}]
        set b [expr {$seg * cos($a)}]
        set c [expr {$seg * sin($a)}]
        set i [expr {int($h * 6.0)}]
        set cases [list $c [expr {1.0/3.0 - $b}] [expr {1.0/3.0 + $c}] [expr {2.0/3.0 - $b}] [expr {2.0/3.0 + $c}] [expr {1.0 - $b}]]
        return [expr {[lindex $cases [expr {$i % 6}]] * 360.0}]
    }

    proc hsl2rgb {h s l} {
        if {$s == 0} { return [list $l $l $l] }
        set h [expr {$h / 60.0}]
        set c [expr {(1.0 - abs(2.0 * $l - 1.0)) * $s}]
        set x [expr {$c * (1.0 - abs(fmod($h, 2.0) - 1.0))}]
        set m [expr {$l - $c / 2.0}]
        if {$h < 1} { set r $c; set g $x; set b 0 } \
        elseif {$h < 2} { set r $x; set g $c; set b 0 } \
        elseif {$h < 3} { set r 0; set g $c; set b $x } \
        elseif {$h < 4} { set r 0; set g $x; set b $c } \
        elseif {$h < 5} { set r $x; set g 0; set b $c } \
        else { set r $c; set g 0; set b $x }
        return [list [expr {$r + $m}] [expr {$g + $m}] [expr {$b + $m}]]
    }

    proc oklch2rgb {l c h} {
        variable PI
        set hr [expr {$h * $PI / 180.0}]
        set a [expr {$c * cos($hr)}]
        set b [expr {$c * sin($hr)}]
        set l_ [expr {$l + 0.3963377774 * $a + 0.2158037573 * $b}]
        set m_ [expr {$l - 0.1055613458 * $a - 0.0638541728 * $b}]
        set s_ [expr {$l - 0.0894841775 * $a - 1.2914855480 * $b}]
        set l_ [expr {pow(max(0, $l_), 3)}]
        set m_ [expr {pow(max(0, $m_), 3)}]
        set s_ [expr {pow(max(0, $s_), 3)}]
        set r_l [expr {+4.0767416621 * $l_ - 3.3077115913 * $m_ + 0.2309699292 * $s_}]
        set g_l [expr {-1.2684380046 * $l_ + 2.6097574011 * $m_ - 0.3413193965 * $s_}]
        set b_l [expr {-0.0041960863 * $l_ - 0.7034186147 * $m_ + 1.7076147010 * $s_}]
        set res {}
        foreach val [list $r_l $g_l $b_l] {
            if {$val <= 0.0031308} { set s [expr {12.92 * $val}] } else { set s [expr {1.055 * pow($val, 1.0/2.4) - 0.055}] }
            if {$s < 0} { set s 0 }; if {$s > 1} { set s 1 }
            lappend res $s
        }
        return $res
    }

    proc point_on_curve {t method accent} {
        variable PI
        set limit [expr {$PI / 2.0}]
        switch $method {
            "lamé" {
                set exp [expr {2.0 / (2.0 + 20.0 * $accent)}]
                return [list [expr {pow(abs(cos($t * $limit)), $exp)}] [expr {pow(abs(sin($t * $limit)), $exp)}]]
            }
            "arc" {
                return [list [expr {sin($limit + $t * $limit - $accent)}] [expr {cos(-$limit + $t * $limit + $accent)}]]
            }
            "power" {
                return [list [expr {pow($t, $accent)}] [expr {pow($t, $accent)}]]
            }
            "powY" {
                return [list [expr {pow(1.0 - $t, $accent)}] [expr {pow($t, 1.0 - $accent)}]]
            }
            "powX" {
                return [list [expr {pow($t, $accent)}] [expr {pow($t, 1.0 - $accent)}]]
            }
            default {
                return [list $t $t]
            }
        }
    }

    proc generate_ramp {args} {
        set total 9
        set hStart 0.0
        set hStartCenter 0.5
        set hCycles 1.0
        set sRange {0.4 0.35}
        set lRange {0.1 0.9}
        set curveMethod "linear"
        set curveAccent 0.5
        set useHarvey 0
        set harmony "none"

        foreach {key val} $args { set [string range $key 1 end] $val }

        # Pre-calculate Harmony hues if they are enabled.
        set hue_list {}
        if {$harmony != "none"} {
            set base_h $hStart
            switch $harmony {
                "complementary" { set hue_list [list $base_h [expr {$base_h + 180}]] }
                "triadic" { set hue_list [list $base_h [expr {$base_h + 120}] [expr {$base_h + 240}]] }
                "split" { set hue_list [list $base_h [expr {$base_h + 150}] [expr {$base_h - 150}]] }
                "tetradic" { set hue_list [list $base_h [expr {$base_h + 90}] [expr {$base_h + 180}] [expr {$base_h + 270}]] }
                "analogous" { set hue_list [list $base_h [expr {$base_h + 30}] [expr {$base_h + 60}]] }
            }
        }

        set lStart [lindex $lRange 0]
        set lDiff [expr {[lindex $lRange 1] - $lStart}]
        set sStart [lindex $sRange 0]
        set sDiff [expr {[lindex $sRange 1] - $sStart}]

        set ramp {}
        for {set i 0} {$i < $total} {incr i} {
            set relI [expr {$total > 1 ? double($i) / ($total - 1) : 0.0}]
            lassign [point_on_curve $relI $curveMethod $curveAccent] sEase lEase

            if {[llength $hue_list] > 0} {
                # Interpolate through harmony hues.
                set idx [expr {$relI * ([llength $hue_list] - 1)}]
                set i1 [expr {int(floor($idx))}]
                set i2 [expr {int(ceil($idx))}]
                set f [expr {$idx - $i1}]
                set h1 [lindex $hue_list $i1]
                set h2 [lindex $hue_list $i2]
                set hue [expr {$h1 + $f * ($h2 - $h1)}]
            } else {
                set hue [expr {$hStart + (1.0 - $relI - $hStartCenter) * (360.0 * $hCycles)}]
            }

            if {$useHarvey} { set hue [harvey_hue $hue] } else { set hue [normalize_hue $hue] }
            lappend ramp [list $hue [expr {$sStart + $sDiff * $sEase}] [expr {$lStart + $lDiff * $lEase}]]
        }
        return $ramp
    }
}

package provide simmerblau_logic 1.0
