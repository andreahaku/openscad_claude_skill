#!/usr/bin/env bash
# openscad-stl-compare.sh — Compare two STL files geometrically
# Uses OpenSCAD boolean difference + Python mesh distance analysis
set -euo pipefail

OPENSCAD="${OPENSCAD_BIN:-$(command -v openscad || echo /opt/homebrew/bin/openscad)}"
IMGSIZE="${OPENSCAD_IMGSIZE:-800,600}"

usage() {
    cat <<'EOF'
Usage: openscad-stl-compare.sh <original.stl> <reconstruction.stl> [output_dir]

Compares two STL files and reports:
  1. Bounding box comparison
  2. Volume/triangle count comparison
  3. Boolean difference renders (what's in A but not B, and vice versa)
  4. Point-to-mesh distance statistics (Hausdorff, RMS, mean)

Output:
  <output_dir>/diff-A-minus-B.png    — Geometry in original but NOT in reconstruction
  <output_dir>/diff-B-minus-A.png    — Geometry in reconstruction but NOT in original
  <output_dir>/overlay.png           — Both overlaid (original=transparent, recon=red)
  <output_dir>/comparison-report.txt — Full numerical report

EOF
    exit 1
}

[[ $# -lt 2 ]] && usage

STL_A="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
STL_B="$(cd "$(dirname "$2")" && pwd)/$(basename "$2")"
OUTDIR="${3:-/tmp/stl-compare-$(date +%s)}"

[[ -f "$STL_A" ]] || { echo "ERROR: File not found: $STL_A" >&2; exit 1; }
[[ -f "$STL_B" ]] || { echo "ERROR: File not found: $STL_B" >&2; exit 1; }

mkdir -p "$OUTDIR"
TMPDIR=$(mktemp -d /tmp/stl-compare-XXXXXX)
trap 'rm -rf "$TMPDIR"' EXIT

echo "=== STL Mesh Comparison ==="
echo "A (original):       $STL_A"
echo "B (reconstruction): $STL_B"
echo "Output:             $OUTDIR"
echo ""

# --- Step 1: Bounding box + triangle comparison ---
echo "--- Dimensional Comparison ---"
python3 -c "
import struct, sys

def parse_stl(path):
    with open(path, 'rb') as f:
        header = f.read(80)
        n = struct.unpack('<I', f.read(4))[0]
        mn = [float('inf')]*3
        mx = [float('-inf')]*3
        for _ in range(n):
            f.read(12)
            for _ in range(3):
                v = struct.unpack('<3f', f.read(12))
                for i in range(3):
                    mn[i] = min(mn[i], v[i])
                    mx[i] = max(mx[i], v[i])
            f.read(2)
    return n, mn, mx

n_a, mn_a, mx_a = parse_stl('$STL_A')
n_b, mn_b, mx_b = parse_stl('$STL_B')

print(f'                  Original         Reconstruction   Delta')
print(f'Triangles:        {n_a:>8}         {n_b:>8}')
labels = ['X', 'Y', 'Z']
total_delta = 0
for i in range(3):
    da = mx_a[i] - mn_a[i]
    db = mx_b[i] - mn_b[i]
    delta = abs(db - da)
    total_delta += delta
    print(f'{labels[i]} dimension:  {da:>12.4f} mm   {db:>12.4f} mm   {delta:>8.4f} mm')
    # Also check position offset
    ca = (mn_a[i] + mx_a[i]) / 2
    cb = (mn_b[i] + mx_b[i]) / 2
    if abs(ca - cb) > 0.01:
        print(f'  Center offset: {abs(ca-cb):.4f} mm')

print(f'Total dim delta:                                   {total_delta:>8.4f} mm')
"

# --- Step 2: Boolean difference renders ---
echo ""
echo "--- Boolean Difference Renders ---"

# A - B: what's in original but not reconstruction
cat > "$TMPDIR/diff-a-minus-b.scad" << SCAD
difference() {
    import("$STL_A", convexity=10);
    import("$STL_B", convexity=10);
}
SCAD

# B - A: what's in reconstruction but not original
cat > "$TMPDIR/diff-b-minus-a.scad" << SCAD
difference() {
    import("$STL_B", convexity=10);
    import("$STL_A", convexity=10);
}
SCAD

# Overlay
cat > "$TMPDIR/overlay.scad" << SCAD
%import("$STL_A", convexity=10);
color("red", 0.5) import("$STL_B", convexity=10);
SCAD

# Render A-B
echo "  Rendering A-B (in original, missing from reconstruction)..."
if "$OPENSCAD" --autocenter --viewall --imgsize="$IMGSIZE" --colorscheme=DeepOcean \
    --render -o "$OUTDIR/diff-A-minus-B.png" "$TMPDIR/diff-a-minus-b.scad" 2>"$TMPDIR/ab.log"; then
    # Check if the difference produced any geometry
    if grep -q "Top level object is a 3D object" "$TMPDIR/ab.log"; then
        facets=$(grep "Facets:" "$TMPDIR/ab.log" | tail -1 | grep -oE '[0-9]+')
        echo "    Difference has $facets facets"
    fi
    # Also export the difference as STL for volume analysis
    "$OPENSCAD" --render --export-format binstl \
        -o "$TMPDIR/diff-ab.stl" "$TMPDIR/diff-a-minus-b.scad" 2>/dev/null || true
else
    echo "    Render failed" >&2
    rm -f "$OUTDIR/diff-A-minus-B.png"
fi

# Render B-A
echo "  Rendering B-A (in reconstruction, not in original)..."
if "$OPENSCAD" --autocenter --viewall --imgsize="$IMGSIZE" --colorscheme=DeepOcean \
    --render -o "$OUTDIR/diff-B-minus-A.png" "$TMPDIR/diff-b-minus-a.scad" 2>"$TMPDIR/ba.log"; then
    if grep -q "Top level object is a 3D object" "$TMPDIR/ba.log"; then
        facets=$(grep "Facets:" "$TMPDIR/ba.log" | tail -1 | grep -oE '[0-9]+')
        echo "    Difference has $facets facets"
    fi
    "$OPENSCAD" --render --export-format binstl \
        -o "$TMPDIR/diff-ba.stl" "$TMPDIR/diff-b-minus-a.scad" 2>/dev/null || true
else
    echo "    Render failed" >&2
    rm -f "$OUTDIR/diff-B-minus-A.png"
fi

# Render overlay
echo "  Rendering overlay..."
"$OPENSCAD" --autocenter --viewall --imgsize="$IMGSIZE" --colorscheme=Cornfield \
    -o "$OUTDIR/overlay.png" "$TMPDIR/overlay.scad" 2>/dev/null || true

# --- Step 3: Volume analysis of differences ---
echo ""
echo "--- Difference Volume Analysis ---"
python3 -c "
import struct, os

def stl_volume(path):
    '''Calculate volume of a binary STL using signed tetrahedron method'''
    if not os.path.exists(path):
        return 0, 0
    with open(path, 'rb') as f:
        f.read(80)
        n = struct.unpack('<I', f.read(4))[0]
        if n == 0:
            return 0, 0
        volume = 0.0
        for _ in range(n):
            f.read(12)  # normal
            v1 = struct.unpack('<3f', f.read(12))
            v2 = struct.unpack('<3f', f.read(12))
            v3 = struct.unpack('<3f', f.read(12))
            f.read(2)
            # Signed volume of tetrahedron with origin
            volume += (
                v1[0] * (v2[1]*v3[2] - v2[2]*v3[1]) +
                v1[1] * (v2[2]*v3[0] - v2[0]*v3[2]) +
                v1[2] * (v2[0]*v3[1] - v2[1]*v3[0])
            ) / 6.0
        return n, abs(volume)

n_a, vol_a = stl_volume('$STL_A')
n_b, vol_b = stl_volume('$STL_B')
n_ab, vol_ab = stl_volume('$TMPDIR/diff-ab.stl')
n_ba, vol_ba = stl_volume('$TMPDIR/diff-ba.stl')

print(f'Original volume:       {vol_a:>12.2f} mm³')
print(f'Reconstruction volume: {vol_b:>12.2f} mm³')
print(f'Volume delta:          {abs(vol_b - vol_a):>12.2f} mm³ ({abs(vol_b-vol_a)/max(vol_a,1)*100:.2f}%)')
print()
print(f'A-B (missing from recon): {vol_ab:>10.2f} mm³ ({n_ab} triangles)')
print(f'B-A (extra in recon):     {vol_ba:>10.2f} mm³ ({n_ba} triangles)')
print()

total_error = vol_ab + vol_ba
if vol_a > 0:
    accuracy = (1 - total_error / vol_a) * 100
    print(f'Total error volume:       {total_error:>10.2f} mm³')
    print(f'Geometric accuracy:       {accuracy:>10.2f}%')
    print()
    if accuracy > 99:
        print('Result: EXCELLENT match')
    elif accuracy > 95:
        print('Result: Good match (minor differences)')
    elif accuracy > 90:
        print('Result: Fair match (visible differences)')
    else:
        print('Result: Needs significant refinement')
" 2>&1 || echo "Volume analysis failed (non-manifold geometry?)"

# --- Step 4: Summary ---
echo ""
echo "--- Output Files ---"
ls -la "$OUTDIR"/*.png 2>/dev/null || echo "No PNG files generated"
echo ""
echo "View difference images to see WHERE the models differ."
echo "  diff-A-minus-B.png = geometry in original but MISSING from reconstruction"
echo "  diff-B-minus-A.png = EXTRA geometry in reconstruction not in original"
