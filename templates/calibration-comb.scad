// ============================================
// calibration-comb.scad — Print this ONCE, measure it, fill printer-profile.scad
// ============================================
//
// Render:  openscad -o comb.stl templates/calibration-comb.scad
// Print:   same filament, same profile you use for functional parts.
//          No support needed. ~40 minutes on a typical FDM machine.
//
// What comes out:
//   - one 6.00mm test pin, printed lying down so it is round
//   - seven holes, each labelled with the clearance it was given
//   - one 20.00mm block for measuring horizontal expansion
//
// What to do with it: see the instructions at the top of printer-profile.scad.

$fn = 64;
eps = 0.01;

// --- Parameters ---
pin_d        = 6.0;      // nominal diameter under test
clearances   = [0.05, 0.10, 0.15, 0.20, 0.25, 0.30, 0.40];
plate_h      = 6;        // thickness the holes go through
hole_pitch   = 16;
margin       = 8;
label_size   = 3.2;
label_depth  = 0.6;
block        = 20.0;     // expansion reference cube edge

plate_w = margin * 2 + hole_pitch * (len(clearances) - 1);
plate_d = 22;

// --- The comb: holes at increasing clearance -------------------------------
module comb() {
    difference() {
        cube([plate_w, plate_d, plate_h]);

        for (i = [0 : len(clearances) - 1]) {
            x = margin + i * hole_pitch;

            // the hole under test
            translate([x, plate_d - 8, -eps])
                cylinder(h = plate_h + 2 * eps, d = pin_d + clearances[i]);

            // the clearance engraved under it, so the part is self-documenting
            // even months later in a drawer
            translate([x, 3.2, plate_h - label_depth])
                linear_extrude(label_depth + eps)
                    text(str(clearances[i]), size = label_size,
                         halign = "center", valign = "baseline",
                         font = "Liberation Sans:style=Bold");
        }

        // nominal diameter engraved on the side
        translate([2, plate_d - 2.2, plate_h - label_depth])
            linear_extrude(label_depth + eps)
                text(str("d=", pin_d), size = 2.6,
                     font = "Liberation Sans:style=Bold");
    }
}

// --- The pin: printed lying down, so roundness does not depend on layers ----
module test_pin() {
    rotate([0, 90, 0])
        cylinder(h = 25, d = pin_d);
}

// --- The block: for horizontal expansion --------------------------------
module expansion_block() {
    difference() {
        cube([block, block, 6]);
        translate([block / 2, 2.5, 6 - label_depth])
            linear_extrude(label_depth + eps)
                text("20.00", size = 3, halign = "center",
                     font = "Liberation Sans:style=Bold");
    }
}

// --- Layout -----------------------------------------------------------
comb();

translate([0, plate_d + 6, pin_d / 2])
    test_pin();

translate([plate_w - block, plate_d + 6, 0])
    expansion_block();
