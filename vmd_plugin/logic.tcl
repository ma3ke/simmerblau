# General color utility functions for Simmerblau.

package provide simmerblau_logic 1.0

namespace eval ::simmerblau::logic {
    variable PI 3.1415926535897931

    proc normalize_hue {h} {
        set h [expr {fmod($h, 360.0)}]
        if {$h < 0} { set h [expr {$h + 360.0}] }
        return $h
    }

    # Transforms a hue to create a more evenly distributed spectrum.
    # Originally by Harvey Rayner, adapted for RampenSau.
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
}
