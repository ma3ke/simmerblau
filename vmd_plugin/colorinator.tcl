# Colorinator logic for Simmerblau.
#
# Based on Colorinator in PECOC by Tsjerk Wassenaar.

package provide simmerblau_colorinator 1.0

namespace eval ::simmerblau::logic::colorinator {
    # This array stores lists of {point {r g b}} for each colormap.
    variable colormaps

    # Sky Blue - White - Burnt Orange.
    set colormaps(SBW) {
        {0.00 {0.15 0.55 0.90}}
        {0.50 {1.00 1.00 1.00}}
        {1.00 {0.85 0.40 0.05}}
    }

    # Blue - White - Red.
    set colormaps(BWR) {
        {0.00 {0.00 0.00 1.00}}
        {0.50 {1.00 1.00 1.00}}
        {1.00 {1.00 0.00 0.00}}
    }

    # Purple - White - Green.
    set colormaps(PRGn) {
        {0.00 {0.45 0.00 0.55}}
        {0.50 {1.00 1.00 1.00}}
        {1.00 {0.00 0.55 0.35}}
    }

    # High-contrast Spectral.
    set colormaps(Spectral) {
        {0.00 {0.00 0.00 0.90}}
        {0.25 {0.00 0.70 1.00}}
        {0.50 {0.00 1.00 0.30}}
        {0.75 {1.00 1.00 0.00}}
        {1.00 {1.00 0.00 0.00}}
    }

    # Perceptually uniform Viridis.
    set colormaps(Viridis) {
        {0.00 {0.267 0.005 0.329}}
        {0.25 {0.253 0.405 0.600}}
        {0.50 {0.163 0.698 0.498}}
        {0.75 {0.478 0.821 0.318}}
        {1.00 {0.993 0.906 0.144}}
    }

    # Blue - Turquoise - White.
    set colormaps(BGW) {
        {0.00 {0.00 0.20 0.90}}
        {0.20 {0.20 0.80 0.60}}
        {1.00 {1.00 1.00 1.00}}
    }

    # Red - Yellow - White.
    set colormaps(RYW) {
        {0.00 {0.80 0.00 0.00}}
        {0.50 {1.00 0.80 0.00}}
        {1.00 {1.00 1.00 1.00}}
    }

    # Purple - Magenta - Green.
    set colormaps(PMG) {
        {0.00 {0.30 0.00 0.60}}
        {0.50 {0.90 0.00 0.70}}
        {1.00 {0.00 0.70 0.30}}
    }

    # Hotpink - White - Chartreuse.
    set colormaps(HWC) {
        {0.00 {1.00 0.00 0.50}}
        {0.50 {1.00 1.00 1.00}}
        {1.00 {0.50 1.00 0.00}}
    }

    # Deep blue to white.
    set colormaps(Blues) {
        {0.00 {0.03 0.06 0.35}}
        {0.33 {0.10 0.45 0.80}}
        {0.66 {0.60 0.85 1.00}}
        {1.00 {1.00 1.00 1.00}}
    }

    # Dark red to white.
    set colormaps(Reds) {
        {0.00 {0.35 0.03 0.03}}
        {0.33 {0.85 0.25 0.10}}
        {0.66 {1.00 0.80 0.60}}
        {1.00 {1.00 1.00 1.00}}
    }

    # Sapphire - White - Burnt Orange.
    set colormaps(BWO) {
        {0.00 {0.059 0.322 0.729}}
        {0.50 {1.000 1.000 1.000}}
        {1.00 {0.850 0.400 0.050}}
    }

    # Peacock Blue - White - Deep Magenta.
    set colormaps(PeacockMagenta) {
        {0.00 {0.000 0.510 0.500}}
        {0.50 {1.000 1.000 1.000}}
        {1.00 {0.750 0.100 0.550}}
    }

    # Van Gogh: Swirling night blues and starlight yellows.
    set colormaps(VanGogh) {
        {0.00 {0.05 0.05 0.20}}
        {0.20 {0.10 0.20 0.55}}
        {0.40 {0.15 0.45 0.70}}
        {0.60 {0.975 0.95 0.60}}
        {0.80 {0.95 0.85 0.20}}
        {1.00 {0.60 0.55 0.20}}
    }

    # Peacock: Iridescent green to electric blue.
    set colormaps(Peacock) {
        {0.00 {0.05 0.05 0.05}}
        {0.15 {0.00 0.20 0.30}}
        {0.35 {0.00 0.55 0.55}}
        {0.50 {0.00 0.40 0.20}}
        {0.65 {0.00 0.65 0.80}}
        {0.80 {0.80 0.75 0.10}}
        {1.00 {0.95 0.90 0.60}}
    }

    # Heat: Black - Red - Yellow - White.
    set colormaps(Heat) {
        {0.00 {0.00 0.00 0.00}}
        {0.33 {0.80 0.00 0.00}}
        {0.66 {1.00 0.80 0.00}}
        {1.00 {1.00 1.00 1.00}}
    }
}

# Interpolate a color from a colormap or a list of stops at point t.
proc ::simmerblau::logic::colorinator::map {colormap_input t} {
    variable colormaps
    set map ""
    if {[info exists colormaps($colormap_input)]} {
        set map $colormaps($colormap_input)
    } else {
        # Assume colormap_input is a literal list of stops.
        set map $colormap_input
    }

    if {[llength $map] == 0} { return {0 0 0} }

    # Clamp t to the [0, 1] range.
    if {$t < 0.0} { set t 0.0 }
    if {$t > 1.0} { set t 1.0 }

    # Find the two control points surrounding t.
    set p1 [lindex $map 0]
    set p2 [lindex $map end]

    foreach point $map {
        set pt [lindex $point 0]
        if {$pt <= $t} { set p1 $point }
        if {$pt >= $t} {
            set p2 $point
            break
        }
    }

    lassign $p1 t1 rgb1
    lassign $p2 t2 rgb2

    if {$t1 == $t2} { return $rgb1 }

    # Calculate the linear interpolation factor.
    set f [expr {($t - $t1) / ($t2 - $t1)}]
    set res {}
    foreach c1 $rgb1 c2 $rgb2 {
        lappend res [expr {$c1 + $f * ($c2 - $c1)}]
    }
    return $res
}

# Generate a ramp based on the selected colormap or custom stops.
proc ::simmerblau::logic::colorinator::generate_ramp {args} {
    set total 9
    set colormap "SBW"
    set stops ""

    foreach {key val} $args { set [string range $key 1 end] $val }

    set ramp {}
    set input $colormap
    if {$stops != ""} { set input $stops }

    for {set i 0} {$i < $total} {incr i} {
        set t [expr {$total > 1 ? double($i) / ($total - 1) : 0.0}]
        lappend ramp [map $input $t]
    }
    return $ramp
}
