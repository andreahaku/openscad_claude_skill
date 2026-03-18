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

### Step 1: Analyze the STL

First, render multi-angle previews of the STL to understand its geometry:

```openscad
// Temporary viewer file
import("path/to/model.stl");
```

Save this as a temporary .scad file and render 4 previews:

```bash
bash ~/.claude/skills/openscad/scripts/openscad-render.sh preview /tmp/stl-viewer.scad
```

Read all preview images to understand the 3D shape from multiple angles.

### Step 2: Extract Mesh Metadata

Use echo output to get bounding box and basic geometry info:

```openscad
// Analysis file
model = import("path/to/model.stl");

// OpenSCAD 2021.01 doesn't have mesh introspection,
// so we rely on the render output stats (vertices, facets, etc.)
import("path/to/model.stl");
```

The render output will report vertex count, facet count, and bounding box info. Note these for dimensional reference.

### Step 3: Decompose into Primitives

Based on the visual analysis, identify the geometric primitives that compose the object:

**Primitive detection heuristics:**
- **Flat faces with right angles** → `cube()` or `linear_extrude()` of a rectangle
- **Curved surfaces (uniform radius)** → `cylinder()` or `sphere()`
- **Tapered curves** → `cylinder(r1, r2)` (cone)
- **Complex profiles extruded** → `linear_extrude()` of a 2D `polygon()`
- **Axially symmetric shapes** → `rotate_extrude()` of a 2D profile
- **Holes/cutouts** → `difference()` with cylinders or cubes
- **Rounded edges** → `minkowski()` with small sphere, or `hull()`
- **Repeated features** → `for()` loop with a module
- **Organic/freeform surfaces** → May not be fully reconstructable; use `import()` for complex parts

Create a decomposition plan:
```
Original STL: bracket-v2.stl (15,234 triangles)
Decomposition:
1. Base plate: cube([80, 40, 5]) — flat bottom section
2. Upright: cube([5, 40, 60]) — vertical section
3. Fillet: hull-based transition between base and upright
4. 4x mounting holes: cylinder(d=5, h=10) at corners
5. 2x slot cutouts: cube([20, 3, 40]) in upright
```

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

### Step 7: Dimensional Verification

Compare echo output from the reconstruction with the STL bounding box:

```openscad
echo(str("Reconstructed BBOX: ", width, " x ", depth, " x ", height));
```

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
