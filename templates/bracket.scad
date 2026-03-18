// ============================================
// Template: L-Bracket with Mounting Holes
// Description: Adjustable L-bracket for wall/shelf mounting
// ============================================

// --- Parameters ---
arm_length = 50;     // [mm] horizontal arm
leg_length = 40;     // [mm] vertical leg
width = 25;          // [mm] bracket width
thickness = 4;       // [mm] material thickness
fillet_r = 8;        // [mm] inner fillet radius

// Mounting holes
hole_d = 5;          // [mm] hole diameter
hole_inset = 10;     // [mm] hole center from edges
countersink = true;  // countersink holes
cs_d = 9;            // [mm] countersink diameter
cs_depth = 2;        // [mm] countersink depth

// --- Quality ---
$fn = 64;

// --- Render ---
bracket();

// --- Modules ---
module bracket() {
    difference() {
        union() {
            // Horizontal arm
            cube([arm_length, width, thickness]);

            // Vertical leg
            cube([thickness, width, leg_length]);

            // Inner fillet for strength
            translate([thickness, 0, thickness])
                fillet(fillet_r, width);
        }

        // Arm mounting holes
        translate([arm_length - hole_inset, width/2, -0.01])
            mounting_hole(hole_d, thickness, countersink, cs_d, cs_depth);

        // Leg mounting holes
        translate([-0.01, width/2, leg_length - hole_inset])
            rotate([0, 90, 0])
                mounting_hole(hole_d, thickness, countersink, cs_d, cs_depth);
    }
}

module fillet(r, w) {
    difference() {
        cube([r, w, r]);
        translate([r, -0.01, r])
            rotate([-90, 0, 0])
                cylinder(r=r, h=w + 0.02);
    }
}

module mounting_hole(d, h, countersink=false, cs_d=0, cs_depth=0) {
    union() {
        cylinder(d=d, h=h + 0.02);
        if (countersink) {
            translate([0, 0, h - cs_depth + 0.01])
                cylinder(d1=d, d2=cs_d, h=cs_depth);
        }
    }
}
