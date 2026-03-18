// ============================================
// printable-lib.scad — Reusable modules for 3D printing
// Include with: use <printable-lib.scad>
// ============================================

eps = 0.01;  // epsilon for clean boolean operations

// --- Clearance helpers ---
// Returns clearance value for different fit types
function fit_clearance(kind="close") =
    kind == "press"  ? 0.15 :
    kind == "close"  ? 0.25 :
    kind == "loose"  ? 0.40 :
    kind == "slide"  ? 0.30 : 0.25;

// --- Shell / Hollow box ---
module shell_box(outer=[60,40,20], wall=2, floor=2) {
    assert(wall >= 1.2, "wall too thin for FDM (min 1.2mm)");
    assert(floor >= 0.8, "floor too thin (min 0.8mm)");
    difference() {
        cube(outer);
        translate([wall, wall, floor])
            cube([outer.x - 2*wall, outer.y - 2*wall, outer.z - floor + eps]);
    }
}

// --- Rounded box (hull-based) ---
module rounded_box(size, r=2) {
    hull() {
        for (x = [r, size.x - r])
            for (y = [r, size.y - r])
                translate([x, y, 0])
                    cylinder(r=r, h=size.z);
    }
}

// --- Screw clearance hole ---
module screw_clearance_hole(d=3, h=10, fit="close") {
    cylinder(h=h + 2*eps, d=d + fit_clearance(fit), $fn=48);
}

// --- Counterbore hole (for socket head cap screws) ---
// Head pocket at entry side (top), shaft goes through
module counterbore_hole(shaft_d=3, head_d=6, head_h=3, h=12) {
    union() {
        screw_clearance_hole(shaft_d, h);
        translate([0, 0, h - head_h + eps])
            cylinder(h=head_h + eps, d=head_d, $fn=48);
    }
}

// --- Countersink hole ---
module countersink_hole(d=3, cs_d=6, cs_h=2, h=10) {
    union() {
        cylinder(d=d, h=h + 2*eps, $fn=48);
        translate([0, 0, h - cs_h + eps])
            cylinder(d1=d, d2=cs_d, h=cs_h, $fn=48);
    }
}

// --- Heat-set insert boss ---
module heatset_boss(insert_d=4.6, insert_h=5, wall=2, h=8) {
    assert(wall >= 1.6, "boss wall too thin for heat-set insert");
    difference() {
        cylinder(h=h, d=insert_d + 2*wall, $fn=64);
        translate([0, 0, -eps])
            cylinder(h=insert_h + 2*eps, d=insert_d, $fn=64);
    }
}

// --- Screw post (solid post with hole) ---
module screw_post(outer_d=7, inner_d=3, h=10) {
    difference() {
        cylinder(d=outer_d, h=h, $fn=48);
        translate([0, 0, -eps])
            cylinder(d=inner_d, h=h + 2*eps, $fn=48);
    }
}

// --- Structural rib / gusset ---
module rib(len=20, height=12, thick=2) {
    linear_extrude(height=thick)
        polygon([[0, 0], [len, 0], [0, height]]);
}

// --- Chamfer edge (for print-friendly overhangs) ---
module chamfer_edge(length=10, size=1) {
    translate([0, 0, -eps])
        linear_extrude(height=length)
            polygon([[0, 0], [size, 0], [0, size]]);
}

// --- Snap-fit tab ---
// Creates a cantilever snap tab extending along Y with a hook at the end
module snap_tab(width=8, length=6, thick=1.5, overhang=0.8) {
    union() {
        // Cantilever arm
        cube([width, length, thick]);
        // Hook at the end (rotated extrusion for clean manifold)
        translate([0, length - eps, 0])
            rotate([90, 0, 90])
                linear_extrude(height=width)
                    polygon([[0, 0], [thick + eps, 0], [thick/2, overhang]]);
    }
}

// --- Text emboss/deboss helper ---
// Use with difference() to deboss or union() to emboss
module text_label(txt="Label", size=8, depth=1, font="Liberation Sans:style=Bold",
                  halign="center", valign="center") {
    linear_extrude(height=depth)
        text(txt, size=size, font=font, halign=halign, valign=valign);
}

// --- Ventilation grille ---
module vent_grille(area_w=30, area_h=15, slot_w=2, slot_gap=2, depth=2) {
    n_slots = floor(area_h / (slot_w + slot_gap));
    for (i = [0:n_slots-1])
        translate([0, i * (slot_w + slot_gap), 0])
            cube([area_w, slot_w, depth + 2*eps]);
}

// --- PCB standoff array ---
module pcb_standoffs(positions, height=5, outer_d=6, hole_d=2.5) {
    for (pos = positions)
        translate(pos)
            difference() {
                cylinder(d=outer_d, h=height, $fn=32);
                translate([0, 0, -eps])
                    cylinder(d=hole_d, h=height + 2*eps, $fn=32);
            }
}

// --- Profile with rounded corners (2D) ---
// Use with linear_extrude() — preferred over hull() of cylinders
module rounded_rect_2d(size, r=2) {
    offset(r=r)
        square([size.x - 2*r, size.y - 2*r], center=true);
}

// --- Lid lip (for box closures) ---
module lid_lip(outer_size, wall=2, lip_h=2, lip_w=1.2, tol=0.25) {
    difference() {
        rounded_box([outer_size.x, outer_size.y, lip_h], r=2);
        translate([lip_w + tol, lip_w + tol, -eps])
            rounded_box([
                outer_size.x - 2*(lip_w + tol),
                outer_size.y - 2*(lip_w + tol),
                lip_h + 2*eps
            ], r=max(2 - lip_w, 0.5));
    }
}
