#!/usr/bin/env bash
# openscad-project.sh — Project scaffolding and management for OpenSCAD skill
set -euo pipefail

PROJECTS_ROOT="$HOME/openscad-projects"

usage() {
    cat <<'EOF'
Usage: openscad-project.sh <command> [args]

Commands:
  init  <project-name>     Create a new project directory
  list                     List all projects
  clean <project-name>     Remove build artifacts (keep source)
  info  <project-name>     Show project info and file listing

EOF
    exit 1
}

cmd_init() {
    local name="$1"

    # Sanitize project name to prevent directory traversal
    if [[ ! "$name" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        echo "ERROR: Project name must contain only letters, numbers, hyphens, and underscores." >&2
        exit 1
    fi

    local project_dir="$PROJECTS_ROOT/$name"

    if [[ -d "$project_dir" ]]; then
        echo "Project already exists: $project_dir"
        echo "Use existing project or choose a different name."
        exit 1
    fi

    mkdir -p "$project_dir"/{src,output,previews}

    # Create a starter main.scad
    cat > "$project_dir/src/main.scad" <<'SCAD'
// ============================================
// Project: ${PROJECT_NAME}
// Description: TODO
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

// --- Derived dimensions ---
inner_width = width - 2 * wall;
inner_height = height - 2 * wall;
inner_depth = depth - 2 * wall;

// --- Debug output ---
echo(str("BBOX: ", width, " x ", depth, " x ", height, " mm"));
echo(str("Wall: ", wall, " mm | Tolerance: ", tolerance, " mm"));

// --- Main Assembly ---
// TODO: Replace with your design
example();

module example() {
    difference() {
        cube([width, depth, height], center = true);
        translate([0, 0, wall])
            cube([inner_width, inner_depth, inner_height + wall], center = true);
    }
}
SCAD

    # Replace placeholder (compatible with both macOS and Linux sed)
    if [[ "$(uname)" == "Darwin" ]]; then
        sed -i '' "s/\${PROJECT_NAME}/$name/g" "$project_dir/src/main.scad"
    else
        sed -i "s/\${PROJECT_NAME}/$name/g" "$project_dir/src/main.scad"
    fi

    # Create a project README
    cat > "$project_dir/README.md" <<EOF
# $name

OpenSCAD project created $(date +%Y-%m-%d).

## Structure
- \`src/\` — OpenSCAD source files (.scad)
- \`output/\` — Exported STL, 3MF files
- \`previews/\` — Rendered PNG previews

## Quick Commands
\`\`\`bash
# Preview
bash ~/.claude/skills/openscad/scripts/openscad-render.sh preview src/main.scad

# Export STL
bash ~/.claude/skills/openscad/scripts/openscad-render.sh stl src/main.scad

# With custom parameters
bash ~/.claude/skills/openscad/scripts/openscad-render.sh stl src/main.scad -D 'width=60' -D 'height=40'
\`\`\`
EOF

    echo "Project created: $project_dir"
    echo ""
    echo "Structure:"
    echo "  $project_dir/"
    echo "  ├── src/"
    echo "  │   └── main.scad (starter template)"
    echo "  ├── output/"
    echo "  ├── previews/"
    echo "  └── README.md"
}

cmd_list() {
    if [[ ! -d "$PROJECTS_ROOT" ]]; then
        echo "No projects directory found at $PROJECTS_ROOT"
        exit 0
    fi

    echo "OpenSCAD Projects in $PROJECTS_ROOT:"
    echo ""

    for dir in "$PROJECTS_ROOT"/*/; do
        [[ ! -d "$dir" ]] && continue
        local name
        name="$(basename "$dir")"
        local scad_count
        scad_count=$(find "$dir/src" -name "*.scad" 2>/dev/null | wc -l | tr -d ' ')
        local stl_count
        stl_count=$(find "$dir/output" -name "*.stl" 2>/dev/null | wc -l | tr -d ' ')
        local preview_count
        preview_count=$(find "$dir/previews" -name "*.png" 2>/dev/null | wc -l | tr -d ' ')

        echo "  $name — ${scad_count} .scad, ${stl_count} .stl, ${preview_count} previews"
    done
}

cmd_clean() {
    local name="$1"
    local project_dir="$PROJECTS_ROOT/$name"

    if [[ ! -d "$project_dir" ]]; then
        echo "Project not found: $name"
        exit 1
    fi

    rm -rf "${project_dir:?}/output/"*
    rm -rf "${project_dir:?}/previews/"*
    echo "Cleaned build artifacts for: $name"
}

cmd_info() {
    local name="$1"
    local project_dir="$PROJECTS_ROOT/$name"

    if [[ ! -d "$project_dir" ]]; then
        echo "Project not found: $name"
        exit 1
    fi

    echo "Project: $name"
    echo "Path: $project_dir"
    echo ""
    echo "Source files:"
    find "$project_dir/src" -name "*.scad" -exec echo "  {}" \; 2>/dev/null
    echo ""
    echo "Exports:"
    find "$project_dir/output" -type f -exec echo "  {}" \; 2>/dev/null || echo "  (none)"
    echo ""
    echo "Previews:"
    find "$project_dir/previews" -name "*.png" -exec echo "  {}" \; 2>/dev/null || echo "  (none)"
}

# --- Main ---
[[ $# -lt 1 ]] && usage

command="$1"
shift

case "$command" in
    init)  [[ $# -lt 1 ]] && usage; cmd_init "$1" ;;
    list)  cmd_list ;;
    clean) [[ $# -lt 1 ]] && usage; cmd_clean "$1" ;;
    info)  [[ $# -lt 1 ]] && usage; cmd_info "$1" ;;
    *)     echo "Unknown command: $command"; usage ;;
esac
