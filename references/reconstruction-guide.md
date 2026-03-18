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

## When to Use Polygon Profiles vs Parametric Primitives

### Use extracted polygon profiles when:
- The shape has mostly flat/angular surfaces (brackets, plates, channels)
- The curves are gentle and well-approximated by ~200 polygon points
- Speed is more important than last-5% accuracy
- Expected accuracy: 75-96% depending on curve complexity

### Use parametric primitives (circle, cylinder) when:
- The shape has prominent cylindrical features (puzzle tabs, screw holes, bosses)
- The shape can be decomposed into known primitives (square + circles)
- You need >95% accuracy on curved surfaces
- The model has symmetry that can be exploited

### Hybrid approach (best for complex models):
1. Extract the polygon profile for the overall outline
2. Identify which curves are circles/arcs from the profile data
3. Replace polygon approximations with parametric `circle(r)` where possible
4. Use `offset(r)` for rounded corners instead of polygon vertices

### Key lesson: polygon simplification tolerance matters enormously
- 0.3mm tolerance → ~50 points → curves become flat → 52% accuracy
- 0.05mm tolerance → ~150 points → curves approximate → 75% accuracy
- 0.02mm tolerance → ~230 points → curves close but not perfect → 75% accuracy
- Diminishing returns beyond ~200 points for polygon-based approaches
- For >90% on cylindrical surfaces, parametric primitives are required

## Feature Hallucination Prevention

NEVER add features based on visual interpretation of renders alone.
- The toothpaste squeezer "cylinder" was actually a rounded slot floor
- The puzzle tray "pyramid" didn't exist at all — it was a shadow in the render
- ALWAYS verify features with SVG slice data (contour count, area, holes)
- If a feature doesn't show as a separate contour in the SVG slices, IT DOESN'T EXIST

## Adaptive Multi-Axis Slicing

The `openscad-adaptive-slice.py` script scans STL on all 3 axes:
1. Coarse pass (5mm) → detects where cross-section changes
2. Fine pass (0.5mm) only at transition zones
3. Classifies each zone: solid, shell_or_channel, multi_body, complex

### How to interpret the feature map

**Zone types and their OpenSCAD equivalents:**
- `solid` (1 contour, 0 holes) → `linear_extrude()` of the profile
- `shell_or_channel` (2 contours) → walls around a cavity, use `offset(delta=-wall)`
- `solid_with_holes` (1 contour, N holes) → solid body with `difference()` holes
- `multi_body` (N contours) → multiple separate parts or holes
- `complex` → may need `hull()` between profiles or `polyhedron()`

**Detecting specific features from zone evolution:**
- **Chamfer/taper**: contour width decreases progressively across slices
- **Fillet**: smooth curvature in contour centroids between zones
- **Counterbore**: nested circular contours with constant radius for several slices
- **Through-hole**: hole contour appears in ALL slices along that axis
- **Blind hole**: hole contour appears then disappears

**Generating OpenSCAD from zones:**
- Stable zones (many identical slices) → `linear_extrude(height=zone_length)` of representative profile
- Transition zones (gradual change) → `hull()` between two profiles at zone boundaries
- Feature zones (holes, counterbores) → `difference()` with fitted cylinders

### Future: Feature Map → OpenSCAD Translator
The next evolution is automatic translation: parse the JSON feature map, emit one `module zone_N()` per zone, assemble with `difference()/union()` in the correct order. This would close the loop from STL → analysis → parametric .scad automatically.
