# OpenSCAD Claude Code Skill

A Claude Code skill for programmatic 3D CAD design using [OpenSCAD](https://openscad.org/). Design, preview, iterate, and export 3D-printable models directly from the terminal — with AI-driven visual feedback.

## Features

- **Programmatic 3D modeling** — Generate OpenSCAD `.scad` files from natural language descriptions
- **AI vision feedback loop** — Render PNG previews and analyze them to iteratively refine designs
- **Image-to-CAD replication** — Reproduce physical objects from reference photos
- **Parametric design** — All dimensions as variables, overridable via CLI `-D` flags
- **Multi-angle previews** — Isometric, rear, front, and top views for comprehensive review
- **STL/3MF export** — Production-ready files for 3D printing
- **Printability analysis** — Wall thickness, overhang, and manifold validation
- **Reusable module library** — Common 3D printing patterns (screw holes, heat-set bosses, ribs, snap-fits)

## Prerequisites

- **OpenSCAD** installed and accessible via CLI
  ```bash
  # macOS (Homebrew)
  brew install openscad

  # Or download from https://openscad.org/downloads.html
  ```
- **Claude Code** CLI installed

## Installation

### Option 1: Clone and symlink (recommended)

```bash
# Clone the repository
git clone https://github.com/andreahaku/openscad_claude_skill.git ~/Development/Claude/openscad_claude_skill

# Symlink into Claude Code skills directory
ln -sf ~/Development/Claude/openscad_claude_skill ~/.claude/skills/openscad
```

### Option 2: Direct clone into skills

```bash
git clone https://github.com/andreahaku/openscad_claude_skill.git ~/.claude/skills/openscad
```

### Verify installation

```bash
# Check OpenSCAD is available
openscad --version

# Test the render script
bash ~/.claude/skills/openscad/scripts/openscad-render.sh quick ~/.claude/skills/openscad/templates/bracket.scad
```

## Usage

The skill is automatically triggered by Claude Code when you mention 3D modeling, CAD, STL export, or OpenSCAD. You can also invoke it directly:

```
/openscad design a phone stand with adjustable angle
```

### Modes

| Mode | Trigger | Description |
|------|---------|-------------|
| **Design** | "design a bracket", "make a box" | Create new 3D models from descriptions |
| **Replicate** | "reproduce this from the photo" | Reverse-engineer objects from reference images |
| **Refine** | "make it taller", "add fillets" | Iterate on existing designs |
| **Export** | "export STL", "ready for printing" | Generate production files |
| **Analyze** | "check printability" | Validate designs for 3D printing |

### Example Workflows

**Design from scratch:**
```
> Design a parametric enclosure for a Raspberry Pi 4, with ventilation slots and screw mount holes
```

**Replicate from image:**
```
> Here's a photo of a cable clip I need to reproduce. It's about 25mm wide. [attach image]
```

**Parametric variations:**
```
> Export the enclosure but with width=100 and wall=3
```

## Project Structure

```
openscad_claude_skill/
├── SKILL.md                          # Skill definition and workflow instructions
├── README.md                         # This file
├── scripts/
│   ├── openscad-render.sh            # Core render/export/preview engine
│   ├── openscad-project.sh           # Project scaffolding (init/list/clean)
│   └── openscad-validate.sh          # Strict validation with error categorization
├── references/
│   └── language-reference.md         # Complete OpenSCAD v2021.01 cheat sheet
└── templates/
    ├── enclosure.scad                # Parametric electronics box with lid
    ├── bracket.scad                  # L-bracket with countersunk holes
    └── printable-lib.scad            # Reusable 3D printing modules
```

## Scripts

### `openscad-render.sh`

Core rendering engine with 7 commands:

```bash
# Quick single preview (isometric)
bash scripts/openscad-render.sh quick <file.scad>

# Multi-angle preview (4 views: iso, iso-rear, front, top)
bash scripts/openscad-render.sh preview <file.scad>

# Export STL
bash scripts/openscad-render.sh stl <file.scad> [-D 'var=val' ...]

# Export 3MF
bash scripts/openscad-render.sh 3mf <file.scad>

# Full export (STL + 3MF + high-res PNG)
bash scripts/openscad-render.sh export <file.scad>

# Printability analysis (bottom view, wireframe, geometry stats)
bash scripts/openscad-render.sh analyze <file.scad>

# Custom render with full control
bash scripts/openscad-render.sh custom <file.scad> --format png --imgsize 1920,1080 --camera 0,0,0,45,0,30,200
```

### `openscad-project.sh`

Project scaffolding:

```bash
# Create new project in ~/openscad-projects/
bash scripts/openscad-project.sh init my-widget

# List all projects
bash scripts/openscad-project.sh list

# Clean build artifacts
bash scripts/openscad-project.sh clean my-widget
```

### `openscad-validate.sh`

Strict validation with `--hardwarnings`:

```bash
bash scripts/openscad-validate.sh src/main.scad
# Output: categorized errors (SYNTAX_ERROR, EMPTY_MODEL, WARNING, OK)
```

## Templates

### `printable-lib.scad` — Reusable modules

Include in your designs:

```openscad
use <printable-lib.scad>

// Available modules:
shell_box(outer=[60,40,20], wall=2, floor=2);
rounded_box([50,30,10], r=3);
screw_clearance_hole(d=3, h=10, fit="close");
counterbore_hole(shaft_d=3, head_d=6, head_h=3, h=12);
countersink_hole(d=3, cs_d=6, cs_h=2, h=10);
heatset_boss(insert_d=4.6, insert_h=5, wall=2, h=8);
screw_post(outer_d=7, inner_d=3, h=10);
rib(len=20, height=12, thick=2);
snap_tab(width=8, length=6, thick=1.5, overhang=0.8);

// Clearance helper
fit_clearance("press");   // 0.15mm
fit_clearance("close");   // 0.25mm
fit_clearance("slide");   // 0.30mm
fit_clearance("loose");   // 0.40mm
```

## Available OpenSCAD Libraries

The skill supports these popular libraries (install to `~/.local/share/OpenSCAD/libraries/`):

| Library | Purpose |
|---------|---------|
| [BOSL2](https://github.com/BelfrySCAD/BOSL2) | Swiss-army knife: attachments, shapes, threading, paths |
| [NopSCADlib](https://github.com/nophead/NopSCADlib) | Vitamins: screws, nuts, electronics, bearings |
| [threads.scad](https://github.com/rcolyer/threads-scad) | Metric threads, hex bolts, nuts |
| [Round-Anything](https://github.com/Irev-Dev/Round-Anything) | Smooth fillets and rounding |
| [YAPP_Box](https://github.com/mrWheel/YAPP_Box) | Parametric project enclosures |
| [Catch'n'Hole](https://github.com/mmalecki/catchnhole) | Nut catches, screw holes |

## 3D Printing Guidelines

The skill follows these rules when generating models:

- **Wall thickness**: min 1.2mm (FDM with 0.4mm nozzle)
- **Clearance**: 0.2-0.3mm for fitting parts
- **Overhangs**: < 45 degrees from vertical
- **Chamfer over fillet** on downward-facing surfaces
- **Epsilon** (`eps = 0.01`) in all boolean operations
- **Flat bottoms** for bed adhesion
- **`assert()`** statements for self-validating parametric models

## How It Works

The skill leverages Claude's multimodal capabilities in a unique way:

1. **Generate** — Claude writes OpenSCAD code based on your description
2. **Render** — The script renders PNG previews via OpenSCAD CLI (headless)
3. **Analyze** — Claude reads the rendered PNGs using vision to evaluate the design
4. **Refine** — Claude modifies the code based on visual analysis
5. **Export** — Final STL/3MF for your slicer

This create-render-analyze-refine loop allows Claude to iteratively improve designs just like a human engineer would — but faster.

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test with `bash scripts/openscad-render.sh quick templates/bracket.scad`
5. Submit a pull request

## License

MIT

## Credits

Built with Claude Code (Anthropic), with architectural input from Gemini and Codex.

Powered by [OpenSCAD](https://openscad.org/) — The Programmers Solid 3D CAD Modeller.
