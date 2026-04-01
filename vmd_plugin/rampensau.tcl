# Ported from the excellent RampenSau (https://github.com/meodai/rampensau) by David Aerne, which is
# distributed under the MIT license.

package provide simmerblau_rampensau 1.0
package require simmerblau_logic 1.0

namespace eval ::simmerblau::logic::rampensau {
    variable PI 3.1415926535897931

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
                return [list [expr {pow(1.0 - $t, 1.0 - $accent)}] [expr {pow($t, 1.0 - $accent)}]]
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

            if {$useHarvey} {
                set hue [::simmerblau::logic::harvey_hue $hue]
            } else {
                set hue [::simmerblau::logic::normalize_hue $hue]
            }
            lappend ramp [list $hue [expr {$sStart + $sDiff * $sEase}] [expr {$lStart + $lDiff * $lEase}]]
        }
        return $ramp
    }
}
