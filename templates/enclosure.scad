// ============================================
// Template: Parametric Electronics Enclosure
// Description: Box with lid, screw posts, ventilation
// ============================================

// --- Parameters ---
width = 80;          // [mm] inner width (X)
depth = 60;          // [mm] inner depth (Y)
height = 35;         // [mm] inner height (Z)
wall = 2.5;          // [mm] wall thickness
corner_r = 3;        // [mm] corner radius
lid_height = 8;      // [mm] lid inner height
lip = 1.5;           // [mm] lid overlap lip
tolerance = 0.3;     // [mm] fit tolerance

// Screw posts
screw_d = 3;         // [mm] screw hole diameter
post_d = 7;          // [mm] post outer diameter
post_inset = 5;      // [mm] post inset from inner wall

// Ventilation
vent_slots = 5;      // number of vent slots
vent_width = 2;      // [mm] slot width
vent_length = 20;    // [mm] slot length

// --- Quality ---
$fn = 64;

// --- Render ---
// Show both parts side by side
translate([0, 0, 0]) box_bottom();
translate([width + wall * 2 + 10, 0, 0]) box_lid();

// --- Modules ---
module box_bottom() {
    difference() {
        // Outer shell
        rounded_box([width + 2*wall, depth + 2*wall, height + wall], corner_r);

        // Inner cavity
        translate([wall, wall, wall])
            rounded_box([width, depth, height + wall + 1], max(corner_r - wall, 0.5));

        // Ventilation slots on one side
        translate([wall + (width - (vent_slots * (vent_width + 3))) / 2, -1, height/2])
            for (i = [0:vent_slots-1])
                translate([i * (vent_width + 3), 0, 0])
                    cube([vent_width, wall + 2, vent_length]);
    }

    // Screw posts
    for (pos = screw_post_positions())
        translate([pos.x, pos.y, wall])
            screw_post(post_d, screw_d, height - 2);

    // Lid lip (inner ridge)
    difference() {
        translate([wall - lip, wall - lip, height + wall - lip])
            rounded_box([width + 2*lip, depth + 2*lip, lip], max(corner_r - wall + lip, 0.5));
        translate([wall, wall, height + wall - lip - 0.01])
            rounded_box([width, depth, lip + 0.02], max(corner_r - wall, 0.5));
    }
}

module box_lid() {
    difference() {
        // Outer lid
        rounded_box([width + 2*wall, depth + 2*wall, lid_height + wall], corner_r);

        // Inner cavity
        translate([wall, wall, -0.01])
            rounded_box([width, depth, lid_height + 0.02], max(corner_r - wall, 0.5));
    }

    // Lip insert (fits inside bottom lip)
    translate([wall + tolerance, wall + tolerance, 0])
        difference() {
            rounded_box(
                [width - 2*tolerance, depth - 2*tolerance, lip],
                max(corner_r - wall - tolerance, 0.5)
            );
            translate([lip, lip, -0.01])
                rounded_box(
                    [width - 2*lip - 2*tolerance, depth - 2*lip - 2*tolerance, lip + 0.02],
                    max(corner_r - wall - lip - tolerance, 0.5)
                );
        }
}

module rounded_box(size, r) {
    hull() {
        for (x = [r, size.x - r])
            for (y = [r, size.y - r])
                translate([x, y, 0])
                    cylinder(r=r, h=size.z);
    }
}

module screw_post(outer_d, inner_d, h) {
    difference() {
        cylinder(d=outer_d, h=h);
        translate([0, 0, -0.01])
            cylinder(d=inner_d, h=h + 0.02);
    }
}

function screw_post_positions() = [
    [wall + post_inset, wall + post_inset, 0],
    [wall + width - post_inset, wall + post_inset, 0],
    [wall + post_inset, wall + depth - post_inset, 0],
    [wall + width - post_inset, wall + depth - post_inset, 0]
];
