#!/usr/bin/env bash
# openscad-render.sh — Core render/export/preview engine for OpenSCAD skill
set -euo pipefail

OPENSCAD="${OPENSCAD_BIN:-$(command -v openscad || echo /opt/homebrew/bin/openscad)}"
IMGSIZE_PREVIEW="${OPENSCAD_IMGSIZE:-800,600}"
IMGSIZE_HIRES="1600,1200"
COLORSCHEME="${OPENSCAD_COLORSCHEME:-DeepOcean}"

usage() {
    cat <<'EOF'
Usage: openscad-render.sh <command> <file.scad> [options]

Commands:
  quick    <file>              Single isometric preview PNG
  preview  <file>              Multi-angle preview (4 views)
  stl      <file> [-D ...]     Export STL
  3mf      <file> [-D ...]     Export 3MF
  export   <file> [-D ...]     Export STL + 3MF + final PNG
  analyze  <file>              Render analysis views (cross-sections, bottom)
  custom   <file> [options]    Custom render with full control

Options (for custom):
  --format <ext>        Output format (png, stl, 3mf, amf, svg, dxf, pdf)
  --imgsize <W,H>       Image dimensions
  --camera <params>     Camera: translate_x,y,z,rot_x,y,z,dist
  --colorscheme <name>  Color scheme
  -D 'var=val'          Parameter override (repeatable)

EOF
    exit 1
}

# Resolve output directory relative to .scad file
get_project_dir() {
    local scad_file="$1"
    local scad_dir
    scad_dir="$(dirname "$(realpath "$scad_file")")"

    # If inside a project structure (has src/ parent), go up
    if [[ "$(basename "$scad_dir")" == "src" ]]; then
        echo "$(dirname "$scad_dir")"
    else
        echo "$scad_dir"
    fi
}

ensure_dirs() {
    local project_dir="$1"
    mkdir -p "$project_dir/previews" "$project_dir/output"
}

# Render with error handling
do_render() {
    local scad_file="$1"
    shift
    local output=""
    local exit_code=0

    output=$("$OPENSCAD" "$@" "$scad_file" 2>&1) || exit_code=$?

    if [[ $exit_code -ne 0 ]]; then
        echo "ERROR: OpenSCAD render failed (exit code $exit_code)" >&2
        echo "$output" >&2
        # Extract specific error info
        if echo "$output" | grep -q "Parser error"; then
            echo "" >&2
            echo "SYNTAX ERROR detected. Check the .scad file at the reported line." >&2
        fi
        return $exit_code
    fi

    # Check for warnings
    if echo "$output" | grep -qi "warning"; then
        echo "WARNINGS:" >&2
        echo "$output" | grep -i "warning" >&2
    fi

    # Print render stats
    if echo "$output" | grep -q "rendering time"; then
        echo "$output" | grep "rendering time"
    fi
    if echo "$output" | grep -q "Facets:"; then
        echo "$output" | grep -E "(Facets|Vertices):"
    fi

    echo "$output" | grep -v "^$" | tail -5
    return 0
}

cmd_quick() {
    local scad_file="$1"
    shift
    local project_dir
    project_dir="$(get_project_dir "$scad_file")"
    ensure_dirs "$project_dir"

    local out="$project_dir/previews/quick-preview.png"
    echo "Rendering quick preview..."
    do_render "$scad_file" \
        --autocenter --viewall \
        --imgsize="$IMGSIZE_PREVIEW" \
        --colorscheme="$COLORSCHEME" \
        --render \
        -o "$out" \
        "$@"

    echo "Preview saved: $out"
}

cmd_preview() {
    local scad_file="$1"
    shift
    local project_dir
    project_dir="$(get_project_dir "$scad_file")"
    ensure_dirs "$project_dir"

    local timestamp
    timestamp="$(date +%Y%m%d-%H%M%S)"
    local preview_dir="$project_dir/previews"

    # Define camera angles: name, camera_params or flags
    declare -A views
    views=(
        ["1-isometric"]="--autocenter --viewall"
        ["2-front"]="--autocenter --viewall --projection o --camera 0,0,0,90,0,0,0"
        ["3-right"]="--autocenter --viewall --projection o --camera 0,0,0,90,0,90,0"
        ["4-top"]="--autocenter --viewall --projection o --camera 0,0,0,0,0,0,0"
    )

    local failed=0
    echo "Rendering 4-view preview..."
    for view_name in $(echo "${!views[@]}" | tr ' ' '\n' | sort); do
        local out="$preview_dir/${view_name}-${timestamp}.png"
        local camera_args="${views[$view_name]}"

        echo "  Rendering $view_name..."
        # shellcheck disable=SC2086
        if ! do_render "$scad_file" \
            $camera_args \
            --imgsize="$IMGSIZE_PREVIEW" \
            --colorscheme="$COLORSCHEME" \
            --render \
            -o "$out" \
            "$@"; then
            echo "  FAILED: $view_name" >&2
            rm -f "$out"
            failed=1
        elif [[ ! -s "$out" ]]; then
            echo "  ERROR: Empty render output: $out" >&2
            rm -f "$out"
            failed=1
        fi
    done

    echo ""
    echo "Preview images saved in: $preview_dir/"
    ls -la "$preview_dir"/*-"${timestamp}".png 2>/dev/null
}

cmd_stl() {
    local scad_file="$1"
    shift
    local project_dir
    project_dir="$(get_project_dir "$scad_file")"
    ensure_dirs "$project_dir"

    local basename
    basename="$(basename "$scad_file" .scad)"
    local out="$project_dir/output/${basename}.stl"

    echo "Exporting STL..."
    do_render "$scad_file" \
        --export-format binstl \
        -o "$out" \
        "$@"

    local size
    size=$(wc -c < "$out" | tr -d ' ')
    echo "STL saved: $out ($size bytes)"
}

cmd_3mf() {
    local scad_file="$1"
    shift
    local project_dir
    project_dir="$(get_project_dir "$scad_file")"
    ensure_dirs "$project_dir"

    local basename
    basename="$(basename "$scad_file" .scad)"
    local out="$project_dir/output/${basename}.3mf"

    echo "Exporting 3MF..."
    do_render "$scad_file" \
        -o "$out" \
        "$@"

    local size
    size=$(wc -c < "$out" | tr -d ' ')
    echo "3MF saved: $out ($size bytes)"
}

cmd_export() {
    local scad_file="$1"
    shift
    local project_dir
    project_dir="$(get_project_dir "$scad_file")"
    ensure_dirs "$project_dir"

    local basename
    basename="$(basename "$scad_file" .scad)"

    echo "=== Full Export ==="

    # STL (binary)
    echo ""
    echo "--- STL ---"
    do_render "$scad_file" \
        --export-format binstl \
        -o "$project_dir/output/${basename}.stl" \
        "$@"
    echo "STL: $project_dir/output/${basename}.stl ($(wc -c < "$project_dir/output/${basename}.stl" | tr -d ' ') bytes)"

    # 3MF
    echo ""
    echo "--- 3MF ---"
    do_render "$scad_file" \
        -o "$project_dir/output/${basename}.3mf" \
        "$@" || echo "3MF export failed (may not be supported in this version)"

    # Final high-res preview
    echo ""
    echo "--- Final Preview ---"
    do_render "$scad_file" \
        --autocenter --viewall \
        --imgsize="$IMGSIZE_HIRES" \
        --colorscheme="$COLORSCHEME" \
        --render \
        -o "$project_dir/previews/final-preview.png" \
        "$@"

    echo ""
    echo "=== Export Complete ==="
    echo "Output directory: $project_dir/output/"
    ls -la "$project_dir/output/"
}

cmd_analyze() {
    local scad_file="$1"
    shift
    local project_dir
    project_dir="$(get_project_dir "$scad_file")"
    ensure_dirs "$project_dir"

    local timestamp
    timestamp="$(date +%Y%m%d-%H%M%S)"

    echo "=== Design Analysis ==="

    # Render STL to get geometry stats
    echo ""
    echo "--- Geometry Stats ---"
    local stl_output
    stl_output="$project_dir/output/analysis-temp.stl"
    do_render "$scad_file" \
        --export-format binstl \
        -o "$stl_output" \
        "$@" 2>&1

    if [[ -f "$stl_output" ]]; then
        local stl_size
        stl_size=$(wc -c < "$stl_output" | tr -d ' ')
        echo "STL file size: $stl_size bytes"
    fi

    # Capture echo output for debug info
    echo ""
    echo "--- Echo Output ---"
    do_render "$scad_file" \
        -o "$project_dir/output/analysis.echo" \
        "$@" 2>&1 || echo "Echo capture failed (non-critical)" >&2
    if [[ -f "$project_dir/output/analysis.echo" ]] && [[ -s "$project_dir/output/analysis.echo" ]]; then
        cat "$project_dir/output/analysis.echo"
    fi

    # Bottom view (to check overhangs / first layer)
    local bottom_png="$project_dir/previews/analysis-bottom-${timestamp}.png"
    echo ""
    echo "--- Bottom View (check first layer / overhangs) ---"
    if ! do_render "$scad_file" \
        --autocenter --viewall \
        --camera 0,0,0,180,0,0,0 \
        --imgsize="$IMGSIZE_PREVIEW" \
        --colorscheme="$COLORSCHEME" \
        --render \
        -o "$bottom_png" \
        "$@"; then
        echo "WARNING: Bottom view render failed (may need OpenGL context)" >&2
        rm -f "$bottom_png"
    fi

    # Isometric wireframe
    local wireframe_png="$project_dir/previews/analysis-wireframe-${timestamp}.png"
    echo ""
    echo "--- Wireframe View ---"
    if ! do_render "$scad_file" \
        --autocenter --viewall \
        --view edges \
        --imgsize="$IMGSIZE_PREVIEW" \
        --colorscheme="$COLORSCHEME" \
        --render \
        -o "$wireframe_png" \
        "$@"; then
        echo "WARNING: Wireframe render failed (may need OpenGL context)" >&2
        rm -f "$wireframe_png"
    fi

    echo ""
    echo "=== Analysis Complete ==="
    echo "Review images in: $project_dir/previews/"
    ls -la "$project_dir/previews"/analysis-*-"${timestamp}".png 2>/dev/null

    # Cleanup temp
    rm -f "$stl_output"
}

cmd_custom() {
    local scad_file="$1"
    shift

    local format="png"
    local imgsize="$IMGSIZE_PREVIEW"
    local camera_args=""
    local colorscheme="$COLORSCHEME"
    local extra_args=()

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --format) format="$2"; shift 2 ;;
            --imgsize) imgsize="$2"; shift 2 ;;
            --camera) camera_args="--camera $2"; shift 2 ;;
            --colorscheme) colorscheme="$2"; shift 2 ;;
            -D) extra_args+=(-D "$2"); shift 2 ;;
            *) extra_args+=("$1"); shift ;;
        esac
    done

    local project_dir
    project_dir="$(get_project_dir "$scad_file")"
    ensure_dirs "$project_dir"

    local basename
    basename="$(basename "$scad_file" .scad)"
    local out="$project_dir/output/${basename}-custom.${format}"

    local render_args=(
        --imgsize="$imgsize"
        --colorscheme="$colorscheme"
        --render
        -o "$out"
    )

    if [[ -n "$camera_args" ]]; then
        # shellcheck disable=SC2086
        render_args+=($camera_args)
    else
        render_args+=(--autocenter --viewall)
    fi

    do_render "$scad_file" "${render_args[@]}" "${extra_args[@]}"
    echo "Output: $out"
}

# --- Main ---
[[ $# -lt 2 ]] && usage

command="$1"
scad_file="$2"
shift 2

# Validate input file
if [[ ! -f "$scad_file" ]]; then
    echo "ERROR: File not found: $scad_file" >&2
    exit 1
fi

case "$command" in
    quick)   cmd_quick "$scad_file" "$@" ;;
    preview) cmd_preview "$scad_file" "$@" ;;
    stl)     cmd_stl "$scad_file" "$@" ;;
    3mf)     cmd_3mf "$scad_file" "$@" ;;
    export)  cmd_export "$scad_file" "$@" ;;
    analyze) cmd_analyze "$scad_file" "$@" ;;
    custom)  cmd_custom "$scad_file" "$@" ;;
    *)       echo "Unknown command: $command"; usage ;;
esac
