# STL-to-SCAD Reconstruction Best Practices

## Profile-Based Reconstruction (Preferred Method)

For extruded parts (brackets, plates, channels), extract the 2D profile directly from the mesh and convert it to OpenSCAD `polygon()` + `linear_extrude()`. This is more accurate than fitting known primitives.

### Step 1: Detect Extrusion Axis
Use trimesh to find the axis with the most stable cross-section:
- Slice the mesh along X, Y, and Z at 64 levels each
- For each axis, measure stability: std(area), std(perimeter), std(hole_count)
- The axis with lowest stability score is the extrusion axis

### Step 2: Extract the Dominant Profile
- Find the slice with the largest area (the representative cross-section)
- Simplify the polygon (remove micro-vertices from tessellation)
- Handle holes: inner contours become `paths` in OpenSCAD `polygon()`

### Step 3: Convert to OpenSCAD
```openscad
// Auto-generated from mesh profile extraction
linear_extrude(height = <extrusion_length>)
    polygon(
        points = [<extracted_points>],
        paths = [<outer_boundary>, <hole_1>, <hole_2>]
    );
```

### Step 4: Add Secondary Features
Features that vary along the extrusion axis (holes, counterbores) are detected by comparing slice profiles at different heights. Where a slice has more holes than the dominant profile, subtract cylinders.

## The Sculptor Approach (MANDATORY)

Always model as a sculptor: start from a solid block, then subtract material.

```openscad
// CORRECT: sculptor approach
difference() {
    solid_body();       // 1. Full solid block first
    channel();          // 2. Subtract channels/slots
    taper_cuts();       // 3. Subtract wedges/tapers
    all_holes();        // 4. Subtract ALL holes LAST
}

// WRONG: additive approach (holes get covered)
union() {
    difference() {
        base();
        some_holes();   // These get covered by wings!
    }
    left_wing();        // Covers the holes above
    right_wing();
}
```

**Why**: In OpenSCAD, `difference()` only applies to its immediate children. If you add material (wings) after cutting holes, the new material covers the holes. The sculptor approach ensures ALL cuts happen after ALL additions.

## Analysis Pipeline

### Step 1: Automated SVG Profile Analysis
```bash
bash openscad-stl-reconstruct.sh model.stl output_dir/
```
This gives you the 30,000-foot view: dimensions, volume, symmetry, primitive hints.

### Step 2: Detailed 1mm Z-Slicing
For complex models, slice at every 1mm (not just 5 levels):
```bash
# Generate slices at every Z level
for z in $(seq 0.5 1 <max_z>); do
    echo "projection(cut=true) translate([0,0,-$z]) import(\"model.stl\");" > /tmp/s.scad
    openscad -o "slices/z${z}.svg" /tmp/s.scad
done
```
Parse each SVG to extract:
- Number of contours (1 body = solid level, 2+ = channels/features)
- Contour sizes: BODY (>500mm²), FEATURE (50-500mm²), HOLE (<50mm²)
- Hole positions from contour centroids
- How width changes with Z (reveals taper rate)

### Step 3: Identify Structure from Profile Data
```
Z=0-5:   1 body (full width)           → Solid base
Z=5-10:  2 bodies + 8 holes            → Channel appeared, base holes
Z=10-20: 2 bodies narrowing            → Taper zone (measure rate)
Z=20-33: 2 bodies (constant width)     → Top section
Z=25-27: bodies interrupted by holes   → Upper counterbore holes
```

### Step 4: Write OpenSCAD (Sculptor Method)
1. Create the FULL solid body (base + wings as one block)
2. Subtract the channel
3. Subtract taper wedges (use `hull()` for linear tapers)
4. Subtract ALL holes in separate modules, called LAST

### Step 5: Compare and Iterate
```bash
bash openscad-stl-compare.sh original.stl reconstruction.stl output/
```
- Check accuracy % (target: >95%)
- Read diff images to identify WHAT is wrong
- Fix ONE thing per iteration
- Re-compare

## Hole Patterns

### Counterbore (flat cylindrical pocket)
Most common in 3D-printed brackets. A shallow cylinder + through hole:
```openscad
module counterbore(hole_d, cb_d, cb_depth, total_h) {
    cylinder(d=hole_d, h=total_h);    // Through hole
    cylinder(d=cb_d, h=cb_depth);     // Flat pocket
}
```

### Countersink (conical taper)
Less common in 3D prints, used for flat-head screws:
```openscad
module countersink(hole_d, cs_d, cs_depth, total_h) {
    cylinder(d=hole_d, h=total_h);
    cylinder(d1=cs_d, d2=hole_d, h=cs_depth);
}
```

**Always check reference images** to determine which type is used. Don't assume.

### Hole Orientation Patterns
Complex brackets often have holes on multiple faces:
- **Bottom face**: Vertical (Z-axis) holes
- **Angled faces**: Holes perpendicular to the face (rotate by taper angle)
- **Side walls**: Horizontal (Y-axis) holes
- **Each set may have different spacing and count**

Extract hole positions from SVG centroids at the appropriate Z level.

## Taper/Wedge Subtraction

For a 45° taper that narrows a wing from full width to reduced width:
```openscad
// Wedge: 0 thickness at bottom, full thickness at top
hull() {
    translate([0, outer_edge, z_start])
        cube([length, eps, z_end - z_start]);    // Thin edge
    translate([0, outer_edge, z_end - eps])
        cube([length, taper_amount, eps]);         // Full face
}
// Then remove the rectangular block above the taper
translate([0, outer_edge, z_end])
    cube([length, taper_amount, z_top - z_end]);
```

## Common Pitfalls

1. **CSG order**: ALWAYS cut holes after building the full solid
2. **Feature hallucination**: Don't add features you can't verify in the reference
3. **Conical vs cylindrical**: Check if countersinks are tapered or flat
4. **Symmetric assumptions**: Don't assume symmetry — verify from SVG data
5. **Volume match ≠ shape match**: A model can have correct volume but wrong shape
6. **SVG Y-axis is inverted**: OpenSCAD projection flips Y coordinates

## Dependencies

```bash
pip3 install trimesh numpy scipy rtree shapely
brew install admesh
```

## Accuracy Targets

| Level | Accuracy | When to stop |
|-------|----------|-------------|
| Draft | >85% | Initial structure verification |
| Good  | >95% | Functional part, ready for test print |
| Excellent | >98% | Production quality |

The 95% threshold is achievable for most mechanical parts in 4-6 iterations using the SVG profiling approach. The remaining 5% is typically tessellation differences and minor feature details.
