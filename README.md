# OpenSCAD Claude Code Skill

A Claude Code skill for programmatic 3D CAD using [OpenSCAD](https://openscad.org/). Design, preview, iterate, reconstruct from STL, and export 3D-printable models — with AI-driven visual feedback and automated mesh comparison.

## Features

- **Programmatic 3D modeling** — Generate `.scad` files from natural language descriptions
- **AI vision feedback loop** — Render multi-angle PNG previews and analyze them to iteratively refine designs
- **STL-to-SCAD reconstruction** — Reverse-engineer STL meshes into parametric OpenSCAD code using SVG profiling and SDF optimization
- **Image-to-CAD replication** — Reproduce physical objects from reference photos
- **Parametric design** — All dimensions as variables, overridable via CLI `-D` flags
- **Mesh comparison** — Boolean diff rendering and IoU scoring to verify reconstruction accuracy
- **Printability analysis** — Wall thickness, overhang, and manifold validation
- **Reusable module library** — Common 3D printing patterns (counterbores, heat-set bosses, ribs, snap-fits)
- **Eval framework** — Automated testing with 20 binary assertions across 4 scenarios (100% pass rate)

## Prerequisites

- **OpenSCAD** installed and accessible via CLI
  ```bash
  brew install openscad    # macOS
  ```
- **Python packages** (for STL reconstruction):
  ```bash
  pip3 install trimesh numpy scipy rtree shapely
  ```
- **admesh** (for mesh validation):
  ```bash
  brew install admesh
  ```
- **Claude Code** CLI installed

## Installation

### Option 1: Clone and symlink (recommended)

```bash
git clone https://github.com/andreahaku/openscad_claude_skill.git ~/Development/Claude/openscad_claude_skill

mkdir -p ~/.claude/skills
ln -sf ~/Development/Claude/openscad_claude_skill ~/.claude/skills/openscad
```

### Option 2: Direct clone into skills

```bash
git clone https://github.com/andreahaku/openscad_claude_skill.git ~/.claude/skills/openscad
```

### Verify installation

```bash
openscad --version
bash ~/.claude/skills/openscad/scripts/openscad-render.sh quick ~/.claude/skills/openscad/templates/bracket.scad
```

## Usage

The skill triggers automatically when you mention 3D modeling, CAD, STL export, or OpenSCAD:

```
/openscad design a phone stand with adjustable angle
```

### Modes

| Mode | Trigger | Description |
|------|---------|-------------|
| **Design** | "design a bracket", "make a box" | Create new 3D models from descriptions |
| **Replicate** | "reproduce this from the photo" | Reverse-engineer objects from reference images |
| **Reconstruct** | "convert this STL to SCAD" | Reverse-engineer STL meshes into parametric code |
| **Refine** | "make it taller", "add fillets" | Iterate on existing designs |
| **Export** | "export STL", "ready for printing" | Generate production files |
| **Analyze** | "check printability" | Validate designs for 3D printing |

### Example Workflows

**Design from scratch:**
```
> Design a parametric enclosure for a Raspberry Pi 4 with ventilation slots
```

**Reconstruct from STL:**
```
> Convert /path/to/model.stl into parametric OpenSCAD code
```

**Export with parameter overrides:**
```
> Export the bracket with width=100 and wall=3
```

## Project Structure

```
openscad_claude_skill/
├── SKILL.md                              # Skill definition (6 modes, 762 lines)
├── README.md                             # This file
├── scripts/
│   ├── openscad-render.sh                # Core render/export/preview engine (7 commands)
│   ├── openscad-project.sh               # Project scaffolding (init/list/clean/info)
│   ├── openscad-validate.sh              # Strict validation with error categorization
│   ├── openscad-stl-analyze.sh           # STL mesh analysis (bbox, cross-sections, gaps)
│   ├── openscad-stl-reconstruct.sh       # Automated reconstruction pipeline (SVG profiling)
│   ├── openscad-stl-compare.sh           # Mesh comparison (boolean diff, accuracy %)
│   └── openscad-sdf-optimize.py          # SDF parameter optimizer (IoU scoring)
├── references/
│   ├── language-reference.md             # Complete OpenSCAD v2021.01 cheat sheet
│   └── reconstruction-guide.md           # Best practices for STL-to-SCAD reconstruction
├── templates/
│   ├── enclosure.scad                    # Parametric electronics box with lid
│   ├── bracket.scad                      # L-bracket with countersunk holes
│   └── printable-lib.scad               # Reusable 3D printing modules
└── eval/
    ├── eval.json                         # 4 test scenarios, 20 binary assertions
    └── results.jsonl                     # Test results log
```

## Scripts

### `openscad-render.sh` — Core Rendering Engine

```bash
bash scripts/openscad-render.sh quick <file.scad>           # Single isometric preview
bash scripts/openscad-render.sh preview <file.scad>          # 4-view (iso, front, right, top)
bash scripts/openscad-render.sh stl <file.scad> [-D ...]     # Export STL
bash scripts/openscad-render.sh 3mf <file.scad>              # Export 3MF
bash scripts/openscad-render.sh export <file.scad>           # Full export (STL + 3MF + PNG)
bash scripts/openscad-render.sh analyze <file.scad>          # Printability analysis
bash scripts/openscad-render.sh custom <file.scad> [opts]    # Custom render
```

### `openscad-stl-reconstruct.sh` — Automated STL Analysis

```bash
bash scripts/openscad-stl-reconstruct.sh model.stl output_dir/
```

Runs the full analysis pipeline:
1. **trimesh** mesh analysis (volume, watertight, normals, bounding cylinder)
2. **SVG profiling** via OpenSCAD `projection(cut=true)` at 5 Z levels
3. **Primitive detection** (RANSAC axis estimation, normal-based CSG inference)

Output: `mesh-info.json`, `primitives.json`, SVG slice files

### `openscad-stl-compare.sh` — Mesh Comparison

```bash
bash scripts/openscad-stl-compare.sh original.stl reconstruction.stl output_dir/
```

Produces:
- **diff-A-minus-B.png** — Geometry in original but MISSING from reconstruction
- **diff-B-minus-A.png** — EXTRA geometry in reconstruction
- **overlay.png** — Both models overlaid
- **Geometric accuracy %** — Based on volume of boolean differences

### `openscad-sdf-optimize.py` — Parameter Optimizer

```bash
python3 scripts/openscad-sdf-optimize.py model.stl stadium-slot --verbose
```

Uses Signed Distance Fields + IoU scoring to find optimal parameters without invoking OpenSCAD in the loop. Converges in seconds via `scipy.optimize.minimize`.

### `openscad-stl-analyze.sh` — Raw Mesh Analysis

```bash
bash scripts/openscad-stl-analyze.sh model.stl                          # Full analysis
bash scripts/openscad-stl-analyze.sh model.stl --cross-section z 5.0     # Slice at Z=5
bash scripts/openscad-stl-analyze.sh model.stl --gaps y                  # Find Y-axis gaps
```

## STL-to-SCAD Reconstruction

The reconstruction pipeline converts triangle meshes into clean, parametric OpenSCAD code:

### The Sculptor Approach

All reconstructions follow the sculptor method — start from a solid block, subtract everything:

```openscad
difference() {
    solid_body();        // 1. Full solid first
    channels();          // 2. Subtract channels/slots
    taper_cuts();        // 3. Subtract wedges
    all_holes();         // 4. ALL holes LAST
}
```

### Two-Tier Pipeline

1. **SVG Profile Analysis** (fast) — `openscad-stl-reconstruct.sh` identifies the model topology by slicing at multiple Z levels
2. **SDF Optimization** (precise) — `openscad-sdf-optimize.py` finds exact parameters via IoU scoring

### Proven Results

| Model | Complexity | Accuracy | Iterations |
|-------|-----------|----------|------------|
| Toothpaste Squeezer | Simple (1180 tri) | 96.27% | 2 |
| Interior Bracket | Complex (7576 tri) | 95.63% | 8 |

See `references/reconstruction-guide.md` for the complete best practices guide.

## Templates

### `printable-lib.scad` — Reusable Modules

```openscad
use <printable-lib.scad>

shell_box(outer=[60,40,20], wall=2, floor=2);
rounded_box([50,30,10], r=3);
screw_clearance_hole(d=3, h=10, fit="close");
counterbore_hole(shaft_d=3, head_d=6, head_h=3, h=12);
countersink_hole(d=3, cs_d=6, cs_h=2, h=10);
heatset_boss(insert_d=4.6, insert_h=5, wall=2, h=8);
screw_post(outer_d=7, inner_d=3, h=10);
rib(len=20, height=12, thick=2);
snap_tab(width=8, length=6, thick=1.5, overhang=0.8);
text_label("Hello", size=8, depth=1);

fit_clearance("press");   // 0.15mm
fit_clearance("close");   // 0.25mm
fit_clearance("slide");   // 0.30mm
fit_clearance("loose");   // 0.40mm
```

## 3D Printing Guidelines

- **Wall thickness**: min 1.2mm (FDM with 0.4mm nozzle)
- **Clearance**: 0.2-0.3mm for fitting parts
- **Overhangs**: < 45° from vertical; prefer chamfers on downward faces
- **Epsilon** (`eps = 0.01`) in all boolean operations
- **Flat bottoms** for bed adhesion
- **`assert()`** for self-validating parametric models
- **Counterbore vs countersink**: always check reference images

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `OPENSCAD_BIN` | `$(command -v openscad)` | Path to OpenSCAD binary |
| `OPENSCAD_IMGSIZE` | `800,600` | Default preview image size |
| `OPENSCAD_COLORSCHEME` | `DeepOcean` | Default color scheme |

## Eval Framework

The skill includes automated testing:

```bash
ls eval/
# eval.json      — 4 test scenarios, 20 binary assertions
# results.jsonl  — Test results log
```

**Baseline: 100% pass rate (20/20)** across:
- Design (simple box + sculptor approach)
- STL reconstruction (96.27% geometric accuracy)
- Parametric export with -D overrides

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make changes
4. Run: `bash scripts/openscad-render.sh quick templates/bracket.scad`
5. Submit a pull request

## License

MIT

## Credits

Built with Claude Code (Anthropic), with architectural input from Gemini (Google) and Codex (OpenAI).

Powered by [OpenSCAD](https://openscad.org/) — The Programmers Solid 3D CAD Modeller.
