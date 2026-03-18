#!/usr/bin/env bash
# openscad-validate.sh — Validate .scad files with structured error output
# Runs OpenSCAD in strict mode and parses errors into actionable categories
set -euo pipefail

OPENSCAD="${OPENSCAD_BIN:-$(command -v openscad || echo /opt/homebrew/bin/openscad)}"

usage() {
    echo "Usage: openscad-validate.sh <file.scad> [-D 'var=val' ...]"
    exit 1
}

[[ $# -lt 1 ]] && usage

scad_file="$1"
shift

if [[ ! -f "$scad_file" ]]; then
    echo "ERROR: File not found: $scad_file" >&2
    exit 1
fi

tmpdir=$(mktemp -d /tmp/openscad-validate-XXXXXX)
trap 'rm -rf "$tmpdir"' EXIT

stl_out="$tmpdir/check.stl"
echo_out="$tmpdir/check.echo"

# Run OpenSCAD in strict mode
output=$("$OPENSCAD" \
    --check-parameters=true \
    --check-parameter-ranges=true \
    --hardwarnings \
    -o "$stl_out" \
    -o "$echo_out" \
    "$@" \
    "$scad_file" 2>&1) || exit_code=$?

exit_code="${exit_code:-0}"

echo "=== Validation Report ==="
echo "File: $scad_file"
echo "Exit code: $exit_code"

# Categorize errors
if echo "$output" | grep -q "Parser error"; then
    echo "Category: SYNTAX_ERROR"
    echo "$output" | grep "ERROR:" | head -5
    echo ""
    # Extract line number
    line=$(echo "$output" | sed -n 's/.*line \([0-9]*\).*/\1/p' | head -1)
    if [[ -n "$line" ]]; then
        echo "Error at line $line. Context:"
        sed -n "$((line > 3 ? line - 3 : 1)),${line}p" "$scad_file" 2>/dev/null | cat -n
    fi
elif echo "$output" | grep -q "Current top level object is empty"; then
    echo "Category: EMPTY_MODEL"
    echo "The model produces no geometry. Check:"
    echo "  - Are modules being called?"
    echo "  - Did a difference() remove everything?"
    echo "  - Are parameter values valid?"
elif echo "$output" | grep -q "NSOpenGLContext\|GLX\|Unable to create"; then
    echo "Category: HEADLESS_PREVIEW"
    echo "PNG preview unavailable (no OpenGL context)."
    echo "STL export should still work."
elif echo "$output" | grep -qi "warning"; then
    echo "Category: WARNING"
    echo "$output" | grep -i "warning" | head -10
else
    echo "Category: OK"
fi

# Show echo output if present
if [[ -f "$echo_out" ]] && [[ -s "$echo_out" ]]; then
    echo ""
    echo "=== Echo Output ==="
    cat "$echo_out"
fi

# Show geometry stats if STL was produced
if [[ -f "$stl_out" ]]; then
    stl_size=$(wc -c < "$stl_out" | tr -d ' ')
    if [[ "$stl_size" -gt 0 ]]; then
        echo ""
        echo "=== Geometry ==="
        echo "STL size: $stl_size bytes"
        # Extract stats from render output
        echo "$output" | grep -E "(Facets|Vertices|rendering time|Simple):" | head -10
    fi
fi

exit "$exit_code"
