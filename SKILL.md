---
name: openscad
description: >
  Programmatic 3D CAD with OpenSCAD. Generate .scad files, render to STL for 3D printing,
  preview as PNG, iterate designs with AI vision feedback, and manage parametric models.
  Use when user asks to "design a 3D model", "create an STL", "make a 3D printable part",
  "openscad", "parametric design", "3D print", "CAD model", "render 3D", "generate STL",
  "design an enclosure", "make a box", "create a bracket", or any 3D modeling task.
  Also triggers on "refine the model", "adjust dimensions", "preview the design",
  "export for printing", "multi-view preview", "check printability", "replicate this object",
  "reproduce from image", "recreate this part", "model this from photo", "reverse engineer",
  "convert STL to SCAD", "reconstruct from STL", "make this STL parametric", or "STL to OpenSCAD".
argument-hint: "<description of object to design or path to existing .scad file>"
allowed-tools: "Bash(*),Read,Edit,Write,Glob,Grep,Agent"
metadata:
  version: 1.0.0
  category: 3d-cad
  tags: [openscad, 3d-printing, cad, parametric, stl, modeling, design]
---

# OpenSCAD Skill

Design, render, preview, and export 3D models using OpenSCAD's programmatic CAD engine. Supports iterative AI-driven design refinement via rendered PNG analysis.

## Environment

- **OpenSCAD binary**: `/opt/homebrew/bin/openscad` (v2021.01)
- **Working directory for designs**: `~/openscad-projects/` (create per-project subdirectories)
- **Skill scripts**: `~/.claude/skills/openscad/scripts/`
- **Templates**: `~/.claude/skills/openscad/templates/`
- **Language reference**: `~/.claude/skills/openscad/references/`

## Modes

The skill operates in six modes, auto-detected from the user's request:

- **Design** — Create a new 3D model from a description
- **Replicate** — Reproduce a physical object from reference images
- **Reconstruct** — Reverse-engineer an STL mesh into parametric OpenSCAD code
- **Refine** — Iterate on an existing .scad file (modify, preview, repeat)
- **Export** — Render final STL/3MF for 3D printing
- **Analyze** — Review an existing design for printability or improvements

---

## Workflow: Design Mode

When the user asks to create a new 3D object:

### Step 1: Understand Requirements

Clarify with the user:
- **What** is the object? (enclosure, bracket, gear, container, etc.)
- **Dimensions** — key measurements in mm
- **Purpose** — functional print, aesthetic, mechanical fit?
- **Constraints** — printer bed size, material, wall thickness preferences
- **Parametric?** — which dimensions should be adjustable?

### Step 2: Set Up Project

```bash
bash ~/.claude/skills/openscad/scripts/openscad-project.sh init "<project-name>"
```

This creates `~/openscad-projects/<project-name>/` with subdirectories for source, output, and previews.

### Step 3: Generate the .scad File

Write the OpenSCAD code to `~/openscad-projects/<project-name>/src/main.scad`.

**Mandatory file structure (Feature Tree pattern):**
```openscad
// 1. PARAMETERS (independent variables)
width = 60;  height = 30;  wall = 2;

// 2. DERIVED DIMENSIONS (calculated from parameters)
inner_width = width - 2 * wall;

// 3. BASE PROFILE (2D sketch — the core shape)
module sketch_base() {
    offset(r = corner_r)
        square([width - 2*corner_r, depth - 2*corner_r], center=true);
}

// 4. PRIMARY BODY (extrude the sketch)
module body() { linear_extrude(height = height) sketch_base(); }

// 5. ADDITIVE FEATURES (bosses, ribs, tabs)
module features_add() { ... }

// 6. SUBTRACTIVE FEATURES (holes, slots, pockets — ALWAYS LAST)
module features_cut() { ... }

// 7. ASSEMBLY (the Feature Tree)
difference() {
    union() { body(); features_add(); }
    features_cut();
}
```

**Profile-first design rules:**
- Prefer `polygon()` + `linear_extrude()` over `hull()` of 3D primitives
- Use `offset(r=radius)` for corner rounding instead of `hull()` with cylinders
- Use `rotate_extrude()` for axially symmetric parts (never stack cylinders)
- Define dimensions relative to edges/features, not absolute coordinates: `hole_x = total_length - edge_margin` (not magic numbers)
- Cascade tolerances from a single `fit_clearance` parameter

**Critical rules for generating OpenSCAD code:**
- Read `~/.claude/skills/openscad/references/language-reference.md` if unsure about syntax
- Always define parametric dimensions as variables at the top of the file
- Use `$fn = 64;` for smooth curves (or higher for final renders)
- Add comments explaining each section
- Use modules for reusable parts
- Keep wall thickness >= 1.2mm for FDM printing
- Design with the print orientation in mind (flat bottom, minimal overhangs)

### Step 4: Preview

Render a multi-angle PNG preview:

```bash
bash ~/.claude/skills/openscad/scripts/openscad-render.sh preview ~/openscad-projects/<project-name>/src/main.scad
```

This generates 4 preview images (front, side, top, isometric) in the project's `previews/` directory.

### Step 5: Analyze Preview

Read each preview PNG using the Read tool to see the rendered object. Evaluate:
- Does the shape match the user's description?
- Are proportions correct?
- Are there visible artifacts or unintended geometry?
- Would this print well? (overhangs, bridging, thin walls)

Report findings to the user with the preview images.

### Step 6: Iterate

If changes are needed, edit the .scad file and re-render. Repeat Steps 4-5 until the user is satisfied. Each iteration should be targeted — change one aspect at a time.

### Step 7: Export

When the design is approved:

```bash
bash ~/.claude/skills/openscad/scripts/openscad-render.sh export ~/openscad-projects/<project-name>/src/main.scad
```

This produces:
- `output/model.stl` — for slicing and printing
- `output/model.3mf` — alternative format (better metadata)
- `previews/final-preview.png` — high-res final render

---

## Workflow: Replicate Mode

When the user provides reference images of a physical object to reproduce in OpenSCAD:

### Step 1: Analyze Reference Images

Read ALL provided reference images using the Read tool. For each image, extract:
- **Overall shape**: What geometric primitives compose this object?
- **Proportions**: Relative dimensions (height-to-width ratio, etc.)
- **Features**: Holes, fillets, chamfers, textures, slots, lips, threads
- **Symmetry**: Is it symmetric along any axis?
- **Construction**: How would you decompose it into boolean operations?

If dimensions are provided, note them. If not, estimate proportions from the images and ask the user for at least one known measurement to establish scale.

### Step 2: Create Decomposition Plan

Before writing any code, describe the object as a series of OpenSCAD operations:

```
Object: Phone stand
Decomposition:
1. Base: flat rectangle with rounded corners (80x60x5mm)
2. Back support: angled plate (60x3mm, tilted 70 degrees)
3. Front lip: small ridge to hold phone (60x3x8mm)
4. Fillet: smooth transition between base and back support
5. Cable channel: cylinder subtracted from base center
```

Present this plan to the user for confirmation before coding.

### Step 3: Generate Initial .scad File

Write the OpenSCAD code based on the decomposition. Set up the project:

```bash
bash ~/.claude/skills/openscad/scripts/openscad-project.sh init "<object-name>"
```

Write the .scad to the project's `src/main.scad`.

### Step 4: Render and Compare

Generate a preview from the **same angle** as the reference image:

```bash
bash ~/.claude/skills/openscad/scripts/openscad-render.sh quick ~/openscad-projects/<name>/src/main.scad
```

Read both the reference image and the rendered preview. Compare them side by side mentally:
- Does the overall silhouette match?
- Are proportions correct?
- Are features (holes, edges, curves) in the right places?
- What's the biggest discrepancy?

### Step 5: Iterative Refinement Loop

For each discrepancy found:
1. Identify which part of the .scad code controls the mismatched feature
2. Make a **single targeted edit** to improve the match
3. Re-render from the same angle
4. Re-compare with the reference

**Refinement priorities** (fix in this order):
1. Overall shape and proportions
2. Major features (holes, cutouts, protrusions)
3. Angles and curves
4. Fillets, chamfers, and surface details
5. Fine details

### Step 6: Multi-Angle Validation

Once the primary angle looks good, render from all angles that have reference images:

```bash
bash ~/.claude/skills/openscad/scripts/openscad-render.sh preview ~/openscad-projects/<name>/src/main.scad
```

Compare each rendered view against its corresponding reference image. Fix any angle-specific discrepancies.

### Step 7: Dimensional Verification

If the user provided measurements, add `echo()` statements to verify:

```openscad
echo("Total width:", width);
echo("Total height:", height);
echo("Wall thickness:", wall);
```

Render with echo capture to verify dimensions match specifications.

### Step 8: Export

When the user confirms the replication is satisfactory, export for printing.

### Tips for Accurate Replication

- **Start simple**: Begin with bounding-box primitives, then refine
- **Use reference dimensions**: If user says "it's about 10cm tall", anchor ALL proportions to that
- **Match camera angle**: Use `--camera` to match the reference photo's perspective
- **Organic shapes**: Approximate with hull(), minkowski(), or rotate_extrude() of a profile
- **Iterate small**: Change one thing per render cycle
- **Ask when unsure**: If a feature is ambiguous from the images, ask the user rather than guessing

---

## Workflow: Reconstruct Mode (STL-to-SCAD)

When the user provides an STL file and wants it converted to parametric OpenSCAD code:

### Overview

STL files are triangle meshes with no semantic information about the original primitives or operations that created them. Reconstruction is the process of analyzing the mesh geometry and re-expressing it as clean, parametric OpenSCAD code. This is valuable because:
- Parametric code can be modified (change dimensions, add features)
- OpenSCAD code is human-readable and version-controllable
- The resulting model can be adapted to different use cases

### Critical Rules for Reconstruction

**Read `references/reconstruction-guide.md` before starting any reconstruction.** It contains the complete best practices guide learned from real reconstructions.

**Rule 1: SCULPTOR APPROACH (mandatory).** Start from a full solid block, subtract ALL features. Never build up from pieces — CSG ordering bugs cause added material to cover previously-cut holes. Structure: `difference() { solid_body(); channels(); tapers(); ALL_holes_LAST(); }`

**Rule 2: NEVER add features based on assumptions.** Always verify with SVG contour data AND reference images. If a feature doesn't appear as a separate contour in the SVG slices, IT DOES NOT EXIST. Known hallucinations to avoid:
- Pyramids/cones from render shadows
- Cylinders from curved wall edges
- Top holes from through-hole exit points

**Rule 3: Bounding box match ≠ correct model.** 0.000mm bbox delta can mean only 70% geometric accuracy. Always use mesh comparison (`openscad-stl-compare.sh`) with boolean diff images.

**Rule 4: Choose the right approach for the geometry type:**

| Geometry | Best Approach | Expected Accuracy |
|----------|--------------|-------------------|
| Flat/angular (brackets, plates) | Profile extraction + linear_extrude | 90-96% |
| Simple known shapes (stadium, box) | Parametric primitives + SDF optimizer | 90-96% |
| Cylindrical features (puzzle tabs, bosses) | Parametric circle() + square() | 85-95% |
| Mixed (curves + flats) | Polygon profile (hi-res, tol=0.02) | 70-80% |
| Complex organic shapes | import() original STL + parametric modifications | N/A |

**Rule 5: Profile-extract FIRST, then decide approach.**
```bash
# Always run both tools before writing any code:
bash ~/.claude/skills/openscad/scripts/openscad-stl-reconstruct.sh model.stl analysis/
python3 ~/.claude/skills/openscad/scripts/openscad-profile-extract.py model.stl --json analysis/profile.json
```
The profile extractor's stability score tells you which axis to extrude along. The SVG contour analysis tells you the internal structure. Together they determine the approach.

**Use the automated reconstruction analysis FIRST — before writing any code:**
```bash
bash ~/.claude/skills/openscad/scripts/openscad-stl-reconstruct.sh model.stl output_dir/
```

This runs the full pipeline: mesh stats (trimesh), 2D profile slices (OpenSCAD projection), primitive detection (RANSAC/normal analysis), and generates SVG profiles at multiple Z levels. The SVG profile analysis is the MOST IMPORTANT output — it reveals the complete cross-section structure at each height level.

**The SVG Profile Method** (preferred over vertex analysis):
1. `projection(cut=true)` slices the STL at a Z height → exports 2D SVG
2. Parse the SVG to count contours: BODY (large area) vs HOLES (small area)
3. Compare contours at different Z levels to understand how the shape changes with height
4. This reveals: channels, slots, holes, wall thickness, taper angles — all from 2D data

**After analysis, verify with mesh comparison:**
```bash
bash ~/.claude/skills/openscad/scripts/openscad-stl-compare.sh original.stl reconstruction.stl output_dir/
```
Target: >95% geometric accuracy. Use diff images to identify remaining discrepancies.

### Step 1: Automated Analysis (run BOTH tools)

```bash
# Tool 1: SVG profiling + primitive detection
bash ~/.claude/skills/openscad/scripts/openscad-stl-reconstruct.sh model.stl analysis/

# Tool 2: Profile extraction + extrusion axis detection
python3 ~/.claude/skills/openscad/scripts/openscad-profile-extract.py model.stl \
    --output analysis/profile.scad --json analysis/profile.json
```

**Key outputs to examine:**
- `analysis/slices/*.svg` — 2D profiles at 5 Z levels
- `analysis/profile.json` — extrusion axis, stability score, profile points, hole count
- `analysis/primitives.json` — detected cylinders/planes
- `analysis/mesh-info.json` — volume, dimensions, symmetry

**Decision tree from the analysis:**
1. If `stability_score < 0.1` → the shape is a clean extrusion. Use `profile.scad` directly with `linear_extrude()`
2. If `stability_score < 0.3` → mostly extruded with variations. Extract profile + add features from SVG contour differences
3. If `stability_score > 0.3` → complex shape. Use SVG slicing at 1mm intervals to map the full structure, then model with parametric primitives

**For models with cylindrical features** (stability > 0.3 or SVG shows circular contours):
- Do NOT rely on polygon profiles — they approximate curves poorly
- Identify circle centers and radii from the SVG contour data
- Model with `circle()` + `square()` in 2D, then extrude

Then render multi-angle previews:

```openscad
// Temporary viewer file
import("path/to/model.stl");
```

```bash
bash ~/.claude/skills/openscad/scripts/openscad-render.sh preview /tmp/stl-viewer.scad
```

Read all preview images to understand the 3D shape from multiple angles.

### Step 2: Detailed Structure Mapping

**For simple models** (5 SVG slices are enough):
Parse the SVG contours to count bodies vs holes at each Z level.

**For complex models** (brackets, enclosures with multiple features):
Slice at every 1mm to map transitions precisely:
```bash
for z in $(seq 0.5 1 <max_z>); do
    echo "projection(cut=true) translate([0,0,-$z]) import(\"model.stl\");" > /tmp/s.scad
    openscad -o "slices/z${z}.svg" /tmp/s.scad
done
```

Parse each SVG to build a structural map:
```
Z=0-5:   1 body (full width) + 8 holes     → Solid base with screw holes
Z=5-10:  2 bodies + 8 holes                → Channel appeared, walls split
Z=10-20: 2 bodies narrowing                → Taper zone (measure rate)
Z=20-33: 2 bodies constant width           → Top section
Z=25-27: Bodies interrupted                → Counterbore pockets at this depth
```

**Hole positions from SVG centroids** — for each hole contour at a given Z, compute the centroid. This gives exact X,Y positions far more reliably than vertex analysis.

**Feature verification rule:** If a feature doesn't appear as a distinct contour in the SVG data, IT DOES NOT EXIST in the model. Never add features based on visual interpretation of 3D renders alone.

### Step 3: Choose Approach and Decompose

Based on the analysis data, choose the reconstruction approach:

**Approach A — Profile Extrusion** (for extruded parts, stability < 0.3):
```bash
# The profile extractor already generated the .scad — use it as a starting point
cat analysis/profile.scad
# Adjust: add cavity with offset(delta=-wall), add floor, add features
```

**Approach B — Parametric Primitives** (for known shapes or cylindrical features):
Create a decomposition plan using measured dimensions from SVG data:
```
Decomposition:
1. Base: square([80, 80]) + circle tabs — from SVG outer contour at Z=mid
2. Cavity: offset(delta=-wall) of base — from SVG inner contour
3. Floor: solid at Z=0 to floor_h — from SVG at Z=0 (1 contour = solid)
4. Holes: cylinder(d=3) at SVG hole centroids
5. Counterbores: cylinder(d=8, h=2) at same positions
```

**Approach C — Hybrid** (for complex shapes with both flat and curved features):
1. Extract polygon profile for the overall outline
2. Identify which curves in the profile are circles (regular spacing, arc-like)
3. Replace those polygon sections with parametric `circle(r)` operations
4. Assemble: `square() + circle()` union for tabs, `difference()` for slots

**Counterbore vs Countersink** — always verify from reference images:
- **Counterbore**: flat cylindrical pocket (`cylinder(d=cb_d, h=cb_depth)`)
- **Countersink**: conical taper (`cylinder(d1=cs_d, d2=hole_d, h=cs_depth)`)
- Most 3D-printed parts use counterbores, not countersinks

### Step 4: Write Parametric .scad Code

Create a new project and write the reconstructed code:

```bash
bash ~/.claude/skills/openscad/scripts/openscad-project.sh init "<name>-reconstructed"
```

**Key principles for reconstruction:**
- Extract ALL dimensions as named variables at the top
- Use meaningful variable names that describe the physical feature
- Add comments linking each section to the original STL features
- Include `echo()` statements for bounding box verification
- Add `assert()` for parameter ranges

### Step 5: Visual Comparison Loop

Render the reconstructed .scad and compare side-by-side with the original STL renders:

1. Render the reconstruction from the same camera angles as Step 1
2. Read both sets of images
3. Compare silhouettes, proportions, and feature placement
4. Identify the biggest discrepancy
5. Fix it and re-render
6. Repeat until the reconstruction matches the original

### Step 6: Overlay Verification

For precise verification, create an overlay .scad file:

```openscad
// Overlay: original STL (transparent) vs reconstruction
%import("path/to/original.stl");  // % = transparent background
color("red", 0.6) reconstructed_model();
```

Render this overlay — any RED areas visible through the transparent original indicate reconstruction errors. Any grey areas not covered by red indicate missing geometry.

### Step 7: Mesh-to-Mesh Comparison

**This is the most important verification step.** Export the reconstruction as STL and compare it against the original using boolean difference:

```bash
# Export reconstruction
bash ~/.claude/skills/openscad/scripts/openscad-render.sh stl ~/openscad-projects/<name>/src/main.scad

# Run mesh comparison
bash ~/.claude/skills/openscad/scripts/openscad-stl-compare.sh \
    path/to/original.stl \
    ~/openscad-projects/<name>/output/main.stl \
    ~/openscad-projects/<name>/previews/comparison
```

This produces:
- **diff-A-minus-B.png** — geometry in original but MISSING from reconstruction (what you need to add)
- **diff-B-minus-A.png** — EXTRA geometry in reconstruction not in original (what you need to remove)
- **overlay.png** — both models overlaid for visual check
- **Geometric accuracy %** — based on volume of boolean differences vs original volume

**Target: >95% geometric accuracy.** If below 95%, examine the diff images to identify which features are wrong, fix them, re-export, and re-compare. Iterate until accuracy is satisfactory.

**Important:** Bounding box delta can be 0.000mm while geometric accuracy is only 78% — internal features matter more than outer dimensions.

### Step 8: Dimensional Verification

Compare echo output from the reconstruction with the STL bounding box:

```openscad
echo(str("Reconstructed BBOX: ", width, " x ", depth, " x ", height));
```

### Step 9: SDF Parameter Optimization (Advanced)

If the SVG profile method doesn't achieve >95% accuracy, use the SDF optimizer for automatic parameter tuning:

```bash
python3 ~/.claude/skills/openscad/scripts/openscad-sdf-optimize.py \
    path/to/original.stl \
    stadium-slot \
    --verbose \
    --output analysis/sdf-result.json
```

This works by:
1. Sampling 30,000 random points in the bounding box
2. Computing target occupancy (inside/outside original mesh) via trimesh
3. Defining the reconstruction as a parametric SDF (Signed Distance Field)
4. Using `scipy.optimize.minimize(method="Powell")` to maximize IoU (Intersection over Union)
5. Generating OpenSCAD code with optimized parameters

**When to use**: When you know the correct model topology (e.g., "stadium body with cylindrical slot") but can't find the exact parameters. The optimizer finds them automatically.

**Supported model types**: `stadium-slot`, `box-holes`. Add new types by defining an SDF function in the script.

**Workflow**: Run `openscad-stl-reconstruct.sh` first (to identify the model topology), then `openscad-sdf-optimize.py` (to find exact parameters), then `openscad-stl-compare.sh` (to verify).

**Prerequisites**: `pip3 install trimesh numpy scipy rtree`

### Common Pitfalls

- **Bounding box match ≠ correct model.** A model with completely wrong internal geometry can still have a 0.000mm bounding box delta. Always verify visually from multiple angles.
- **Don't assume features from renders alone.** What looks like a cylinder in a top-down view might just be a curved wall edge. Always verify with vertex analysis.
- **Coincident faces cause Z-fighting.** If a feature touches the body boundary exactly, use `intersection()` to clip it cleanly rather than making it the exact same size.
- **Don't flip between adding and removing features.** If unsure whether a feature exists, run cross-section analysis before deciding. Oscillating between "add bar" and "remove bar" wastes iterations.
- **Offset features are common.** Cylinders, holes, and channels are often NOT centered. Always calculate the actual center from vertex data rather than assuming symmetry.

### Limitations

- **Organic shapes** (sculpted, freeform surfaces) cannot be fully reconstructed as primitives. For these, keep the STL import and wrap it in a module.
- **Very complex models** (1000+ features) should be reconstructed incrementally, starting with the major body and adding features one group at a time.
- **Thread geometry** in STL is extremely difficult to reconstruct. Use `threads.scad` library instead of trying to match individual thread faces.
- **Text/engravings** embedded in STL meshes are very hard to extract. It's better to re-add text using OpenSCAD's `text()` module.

### Hybrid Approach

For complex models, use a hybrid strategy:
```openscad
// Import the complex organic base from STL
module original_base() {
    import("base-section.stl");
}

// Reconstruct and parameterize the mechanical features
module mounting_bracket(width=30, hole_d=5) {
    difference() {
        original_base();
        // Add parametric mounting holes
        for (pos = hole_positions)
            translate(pos) cylinder(d=hole_d, h=50, center=true);
    }
}
```

This lets the user modify the parametric parts while keeping the complex geometry intact.

---

## Workflow: Refine Mode

When the user wants to modify an existing design:

### Step 1: Read the Existing File

```bash
# Find .scad files in the project
```
Read the .scad source to understand the current design.

### Step 2: Render Current State

```bash
bash ~/.claude/skills/openscad/scripts/openscad-render.sh preview /path/to/file.scad
```

Read the preview images to see what currently exists.

### Step 3: Apply Changes

Edit the .scad file with the requested modifications. Use the Edit tool for surgical changes.

### Step 4: Re-render and Compare

Generate new previews and visually compare with the previous version. Report what changed.

### Step 5: Repeat or Export

Continue iterating or export when satisfied.

---

## Workflow: Export Mode

Quick export of an existing .scad file:

```bash
# Single format
bash ~/.claude/skills/openscad/scripts/openscad-render.sh stl /path/to/file.scad

# Multiple formats
bash ~/.claude/skills/openscad/scripts/openscad-render.sh export /path/to/file.scad

# With parameter overrides
bash ~/.claude/skills/openscad/scripts/openscad-render.sh stl /path/to/file.scad -D 'width=50' -D 'height=30'
```

---

## Workflow: Analyze Mode

Review a design for printability:

```bash
bash ~/.claude/skills/openscad/scripts/openscad-render.sh analyze /path/to/file.scad
```

This renders cross-section views and reports:
- Object bounding box dimensions
- Whether the mesh is manifold (watertight)
- Estimated print time indicators (volume, surface area from STL)
- Visual check of overhangs via bottom-up view

---

## Script Reference

All scripts live in `~/.claude/skills/openscad/scripts/`:

| Script | Purpose |
|--------|---------|
| `openscad-render.sh` | Core render/export/preview engine |
| `openscad-project.sh` | Project scaffolding and management |
| `openscad-validate.sh` | Strict validation with categorized error output |
| `openscad-stl-analyze.sh` | STL mesh analysis: bbox, cross-sections, gap detection |
| `openscad-stl-compare.sh` | Mesh comparison: boolean diff, volume delta, accuracy % |
| `openscad-stl-reconstruct.sh` | Automated STL analysis: profiles, primitives, CSG inference |
| `openscad-sdf-optimize.py` | SDF-based parameter optimizer (IoU scoring, no OpenSCAD in loop) |

### openscad-render.sh Commands

```bash
# Quick single preview (isometric)
openscad-render.sh quick <file.scad>

# Multi-angle preview (4 views)
openscad-render.sh preview <file.scad>

# Export STL only
openscad-render.sh stl <file.scad> [-D 'var=val' ...]

# Export all formats (STL + 3MF + PNG)
openscad-render.sh export <file.scad> [-D 'var=val' ...]

# Analyze printability
openscad-render.sh analyze <file.scad>

# Custom render
openscad-render.sh custom <file.scad> --format png --imgsize 1920,1080 --camera 0,0,0,45,0,30,200
```

### openscad-project.sh Commands

```bash
# Initialize new project
openscad-project.sh init <project-name>

# List projects
openscad-project.sh list

# Clean build artifacts
openscad-project.sh clean <project-name>
```

---

## OpenSCAD Code Guidelines

### File Structure Convention

```openscad
// ============================================
// Project: <name>
// Description: <what this models>
// Author: Claude Code + User
// ============================================

// --- Parameters (user-configurable) ---
width = 50;        // [mm] overall width
height = 30;       // [mm] overall height
depth = 20;        // [mm] overall depth
wall = 2.0;        // [mm] wall thickness
tolerance = 0.3;   // [mm] printer tolerance

// --- Rendering quality ---
$fn = 64;          // curve smoothness (use 128+ for final export)
eps = 0.01;        // epsilon for clean boolean operations

// --- Derived dimensions ---
inner_width = width - 2 * wall;
inner_height = height - 2 * wall;

// --- Main model ---
main_assembly();

// --- Modules ---
module main_assembly() {
    // ...
}
```

### 3D Printing Best Practices in OpenSCAD

- **Wall thickness**: minimum 1.2mm for FDM (2-3 perimeters with 0.4mm nozzle)
- **Tolerance**: 0.2-0.3mm clearance for fitting parts together (peg-in-hole, snap fits)
- **Overhangs**: keep below 45 degrees from vertical, or add supports in design
- **Chamfer vs fillet**: prefer chamfers on downward-facing surfaces (avoids supports); use fillets on top surfaces
- **Bridging**: max ~10mm unsupported spans
- **First layer**: design flat bottoms for bed adhesion; largest flat surface on build plate
- **Epsilon constant**: always define `eps = 0.01;` and use it in boolean operations to prevent Z-fighting / coplanar faces
- **Manifold geometry**: always ensure boolean operations produce valid solids; operands must overlap
- **Resolution**: use `$fn = 64` for preview, `$fn = 128` for export
- **Design intent**: Define hole positions relative to edges (`hole_x = length - margin`), never as absolute coordinates
- **Tolerance chains**: Define a single `fit_clearance` parameter and derive all clearances from it
- **Assert validation**: Use `assert()` to validate parameters: `assert(wall >= 1.2)`, `assert(boss_d > hole_d + 2*wall)`
- **Profile-first**: Use `offset(r=corner_r)` on 2D `polygon()` instead of `hull()` with 3D cylinders

### Common Patterns

**Rounded box:**
```openscad
module rounded_box(size, radius) {
    minkowski() {
        cube([size.x - 2*radius, size.y - 2*radius, size.z - radius]);
        cylinder(r=radius, h=radius);
    }
}
```

**Shell (hollow object):**
```openscad
module shell(outer_size, wall) {
    difference() {
        cube(outer_size);
        translate([wall, wall, wall])
            cube([outer_size.x - 2*wall, outer_size.y - 2*wall, outer_size.z]);
    }
}
```

**Screw hole with countersink:**
```openscad
module screw_hole(d=3, h=10, cs_d=6, cs_h=2) {
    union() {
        cylinder(d=d, h=h);
        translate([0, 0, h - cs_h])
            cylinder(d1=d, d2=cs_d, h=cs_h);
    }
}
```

---

## Available Libraries

Popular libraries that can be installed for advanced features:

| Library | Use Case | Install |
|---------|----------|---------|
| **BOSL2** | Swiss-army knife: attachments, shapes, threading, paths | `git clone https://github.com/BelfrySCAD/BOSL2 ~/.local/share/OpenSCAD/libraries/BOSL2` |
| **NopSCADlib** | Vitamins (screws, nuts, electronics, bearings) | `git clone https://github.com/nophead/NopSCADlib ~/.local/share/OpenSCAD/libraries/NopSCADlib` |
| **threads.scad** | Metric threads, hex bolts, nuts | `git clone https://github.com/rcolyer/threads-scad ~/.local/share/OpenSCAD/libraries/threads` |
| **Round-Anything** | Smooth fillets and rounding | `git clone https://github.com/Irev-Dev/Round-Anything ~/.local/share/OpenSCAD/libraries/Round-Anything` |
| **YAPP_Box** | Parametric project enclosures | `git clone https://github.com/mrWheel/YAPP_Box ~/.local/share/OpenSCAD/libraries/YAPP_Box` |
| **Catch'n'Hole** | Nut catches, screw holes | `git clone https://github.com/mmalecki/catchnhole ~/.local/share/OpenSCAD/libraries/catchnhole` |

Check installed libraries:
```bash
ls ~/.local/share/OpenSCAD/libraries/ 2>/dev/null
ls /opt/homebrew/share/openscad/libraries/ 2>/dev/null
```

When user needs a library, install it and add `use <library/file.scad>` to the .scad source.

---

## Error Handling

When OpenSCAD fails:

1. **Parse errors** — `ERROR: Parser error: syntax error in file X, line Y`
   - Read the .scad file at the reported line
   - Fix syntax (common: missing semicolons, unmatched braces/parens, wrong function names)
   - Re-render

2. **Geometry errors** — `WARNING: Object may not be a valid 2-manifold`
   - Check boolean operations aren't creating degenerate geometry
   - Ensure shapes overlap properly for difference/intersection
   - Add small epsilon offsets (0.01mm) to prevent coplanar faces

3. **Rendering timeouts** — complex models with high `$fn`
   - Lower `$fn` for preview (32), raise for export (128)
   - Simplify geometry where possible
   - Use `render()` to cache intermediate results

4. **Empty output** — model produces no geometry
   - Check that modules are actually called
   - Verify boolean operations don't subtract everything
   - Use `echo()` statements to debug variable values

Always capture stderr when rendering — it contains warnings and errors:
```bash
openscad -o output.stl input.scad 2>&1
```

---

## Camera Presets for Multi-View

| View | Camera Parameters |
|------|-------------------|
| Front | `--camera 0,0,0,90,0,0,<dist>` |
| Back | `--camera 0,0,0,90,0,180,<dist>` |
| Right | `--camera 0,0,0,90,0,90,<dist>` |
| Left | `--camera 0,0,0,90,0,270,<dist>` |
| Top | `--camera 0,0,0,0,0,0,<dist>` |
| Bottom | `--camera 0,0,0,180,0,0,<dist>` |
| Isometric | `--autocenter --viewall` (default) |
| 3/4 view | `--camera 0,0,0,55,0,25,<dist>` |

Use `--autocenter --viewall` to auto-calculate distance, or specify explicit distance for consistent framing across iterations.
