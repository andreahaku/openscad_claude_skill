// ============================================
// printer-profile.scad — Measured behaviour of THE printer you actually own
// Included automatically by printable-lib.scad
// ============================================
//
// WHY THIS FILE EXISTS
//
// Generating a part takes seconds. Finding out that the 5mm hole does not accept
// a 5mm bolt takes a whole print cycle — 30 to 60 minutes. That single number is
// where the time goes, not the modelling.
//
// Generic clearance values are a guess about someone else's printer. The values
// below become real after you print templates/calibration-comb.scad ONCE and
// measure it. From then on every quick part fits on the first print.
//
// HOW TO CALIBRATE (once, ~40 minutes of printing, 5 minutes of measuring)
//
//   1. openscad -o comb.stl templates/calibration-comb.scad
//   2. Print it with the filament and profile you use for functional parts.
//   3. Take the 6.00mm test pin (printed alongside) and try it in each hole.
//      Read the label under the hole that behaves the way you want:
//        - press : goes in with force, stays put without glue
//        - close : goes in by hand, no wobble          <- the everyday default
//        - slide : moves freely, no play worth naming
//        - loose : drops in, obvious play
//   4. Measure the 20.00mm calibration block with a caliper, on X and on Y.
//   5. Write the numbers below and set profile_measured = true.
//
// UNTIL THEN the values are declared defaults, not measurements. The skill says
// so out loud whenever it emits a part that depends on a fit.

// --- Provenance -----------------------------------------------------------
profile_measured = false;          // set true only after the comb is printed and measured
profile_printer  = "non dichiarata";
profile_filament = "";             // clearances differ per material: PLA != PETG != ABS
profile_nozzle   = 0.4;
profile_date     = "";             // YYYY-MM-DD of the measurement

// --- Clearances (mm added to a hole diameter to reach the wanted fit) -----
// Measured as: hole_that_worked - 6.00
clearance_press  = 0.15;
clearance_close  = 0.25;
clearance_slide  = 0.30;
clearance_loose  = 0.40;

// --- Horizontal expansion -------------------------------------------------
// How much wider the printer makes a part than the model says, per side.
// Measured as: (measured_block - 20.00) / 2. Positive means it prints fat.
// Holes come out that much SMALLER, which is why they need clearance at all.
xy_expansion = 0.00;

// --- Print constraints ----------------------------------------------------
// Used by the deterministic pre-flight gate before any render is looked at.
min_wall        = 1.2;   // thinnest wall that survives FDM
min_floor       = 0.8;
max_overhang    = 45;    // degrees from vertical, beyond which support is needed
bed_size        = [220, 220, 250];   // declared, not verified
