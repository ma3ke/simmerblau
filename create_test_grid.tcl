# 33 beads mapped 1:1 to ColorIDs 0-32
# 100 beads mapped to B-factors 0-99

proc create_simmerblau_test_grid {} {
    set filename "simmerblau_.xyz"
    set fp [open $filename w]

    set num_palette 33
    set num_scale 100
    set total_atoms [expr {$num_palette + $num_scale}]

    puts $fp $total_atoms
    puts $fp "Simmerblau color test grid"

    set spacing 5.0

    # Color ID palette grid (6 by 6).
    set cols_p 6
    for {set i 0} {$i < $num_palette} {incr i} {
        set x [expr {($i % $cols_p) * $spacing}]
        set y [expr {($i / $cols_p) * $spacing}]
        puts $fp [format "C %8.3f %8.3f %8.3f" $x $y 0.0]
    }

    # Color scale grid (10 by 10).
    set cols_s 10
    set y_offset 40.0
    for {set i 0} {$i < $num_scale} {incr i} {
        set x [expr {($i % $cols_s) * $spacing}]
        set y [expr {($i / $cols_s) * $spacing + $y_offset}]
        puts $fp [format "O %8.3f %8.3f %8.3f" $x $y 0.0]
    }
    close $fp

    # Load our generated structure file.
    set molid [mol new $filename type xyz waitfor all]
    file delete $filename

    # Set b-factors (Beta) for the second section.
    set sel_scale [atomselect $molid "index $num_palette to [expr {$total_atoms - 1}]"]
    set betas {}
    for {set i 0} {$i < $num_scale} {incr i} { lappend betas [expr {double($i)}] }
    $sel_scale set beta $betas

    # Clean up default representation.
    mol delrep 0 $molid

    # Set the representations for the Color ID section.
    for {set i 0} {$i < $num_palette} {incr i} {
        mol selection "index $i"
        mol addrep $molid
        mol modstyle $i $molid VDW 1.5 32.0
        mol modcolor $i $molid ColorID $i
        mol modmaterial $i $molid AOChalky
    }

    # Set the representation for the color scale section.
    mol selection "index >= $num_palette"
    mol addrep $molid
    set scale_rep_idx $num_palette
    mol modstyle $scale_rep_idx $molid VDW 1.5 32.0
    mol modcolor $scale_rep_idx $molid Beta
    mol modmaterial $scale_rep_idx $molid AOChalky

    # Set the color scale range to match our B-factors.
    mol colupdate $scale_rep_idx $molid 1
    mol scaleminmax $molid $scale_rep_idx 0.0 99.0

    display resetview
}

create_simmerblau_test_grid
