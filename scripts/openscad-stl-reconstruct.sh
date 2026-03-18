#!/usr/bin/env bash
# openscad-stl-reconstruct.sh — Automated STL analysis for reconstruction
# Uses projection slicing, trimesh analysis, and normal-based CSG inference
set -euo pipefail

OPENSCAD="${OPENSCAD_BIN:-$(command -v openscad || echo /opt/homebrew/bin/openscad)}"

usage() {
    cat <<'EOF'
Usage: openscad-stl-reconstruct.sh <file.stl> <output_dir>

Automated STL analysis pipeline:
  1. Bounding box + volume + basic mesh stats (via trimesh/admesh)
  2. 2D profile slices at multiple Z levels (via OpenSCAD projection)
  3. Normal analysis for CSG inference (cuts vs solid features)
  4. Primitive detection (RANSAC plane/cylinder fitting)
  5. Generates a decomposition report with OpenSCAD code suggestions

Output:
  <output_dir>/report.txt              Full analysis report
  <output_dir>/slices/slice-z*.svg     2D profile SVGs at each Z level
  <output_dir>/slices/slice-z*.png     Rendered slice images
  <output_dir>/primitives.json         Detected primitives with parameters

EOF
    exit 1
}

[[ $# -lt 2 ]] && usage

STL_FILE="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
OUTDIR="$2"

[[ -f "$STL_FILE" ]] || { echo "ERROR: File not found: $STL_FILE" >&2; exit 1; }

mkdir -p "$OUTDIR/slices"

echo "=== STL Reconstruction Analysis ==="
echo "Input: $STL_FILE"
echo "Output: $OUTDIR"
echo ""

# --- Step 1: Basic mesh analysis with trimesh ---
echo "--- Step 1: Mesh Analysis ---"
python3 << PYEOF
import trimesh
import numpy as np
import json, os

mesh = trimesh.load_mesh('$STL_FILE', force='mesh')

print(f"Vertices: {len(mesh.vertices)}")
print(f"Faces: {len(mesh.faces)}")
print(f"Volume: {mesh.volume:.2f} mm³")
print(f"Watertight: {mesh.is_watertight}")
print(f"Bounding box: {mesh.bounds[0].round(3)} to {mesh.bounds[1].round(3)}")
dims = mesh.bounds[1] - mesh.bounds[0]
print(f"Dimensions: {dims[0]:.3f} x {dims[1]:.3f} x {dims[2]:.3f} mm")
print(f"Center: {mesh.centroid.round(3)}")

# Identify the primary axes (longest = extrusion direction)
axes = ['X', 'Y', 'Z']
sorted_axes = sorted(range(3), key=lambda i: dims[i], reverse=True)
print(f"Primary axis (longest): {axes[sorted_axes[0]]} ({dims[sorted_axes[0]]:.1f}mm)")
print(f"Likely extrusion axis: {axes[sorted_axes[0]]}")

# Bounding cylinder
try:
    cyl = trimesh.bounds.minimum_cylinder(mesh)
    print(f"Bounding cylinder: h={cyl['height']:.2f} r={cyl['radius']:.2f}")
except:
    pass

# Face normal analysis — detect dominant orientations
normals = mesh.face_normals
# Cluster normals by major axis alignment
for i, axis in enumerate(axes):
    pos = np.sum(normals[:, i] > 0.9)
    neg = np.sum(normals[:, i] < -0.9)
    if pos + neg > 0:
        print(f"Faces aligned with {axis}: +{pos} / -{neg}")

# Detect inward-facing curved surfaces (= cuts/holes)
# Curved faces have normals NOT aligned with any axis
non_planar = np.sum(np.all(np.abs(normals) < 0.9, axis=1))
print(f"Curved/non-planar faces: {non_planar} ({non_planar/len(normals)*100:.0f}%)")

# Save basic info as JSON
info = {
    'file': '$STL_FILE',
    'vertices': int(len(mesh.vertices)),
    'faces': int(len(mesh.faces)),
    'volume': float(mesh.volume),
    'watertight': bool(mesh.is_watertight),
    'bounds_min': mesh.bounds[0].tolist(),
    'bounds_max': mesh.bounds[1].tolist(),
    'dimensions': dims.tolist(),
    'center': mesh.centroid.tolist(),
    'primary_axis': axes[sorted_axes[0]],
}
with open('$OUTDIR/mesh-info.json', 'w') as f:
    json.dump(info, f, indent=2)

PYEOF

# --- Step 2: 2D Profile Slices via OpenSCAD projection ---
echo ""
echo "--- Step 2: 2D Profile Slices ---"

# Get Z range from mesh info
Z_MIN=$(python3 -c "import json; d=json.load(open('$OUTDIR/mesh-info.json')); print(d['bounds_min'][2])")
Z_MAX=$(python3 -c "import json; d=json.load(open('$OUTDIR/mesh-info.json')); print(d['bounds_max'][2])")
Z_MID=$(python3 -c "print(($Z_MIN + $Z_MAX) / 2)")

echo "Z range: $Z_MIN to $Z_MAX (mid=$Z_MID)"

# Generate slices at key Z levels (bottom, 25%, 50%, 75%, top)
for pct in 0.01 0.25 0.50 0.75 0.99; do
    Z_LEVEL=$(python3 -c "print(round($Z_MIN + ($Z_MAX - $Z_MIN) * $pct, 3))")
    SLICE_NAME="slice-z${Z_LEVEL}"

    # Create OpenSCAD file for this slice
    cat > "/tmp/slice-${pct}.scad" << SCADEOF
projection(cut=true)
    translate([0, 0, -${Z_LEVEL}])
        import("${STL_FILE}", convexity=10);
SCADEOF

    # Export as SVG
    if "$OPENSCAD" -o "$OUTDIR/slices/${SLICE_NAME}.svg" "/tmp/slice-${pct}.scad" 2>/dev/null; then
        SVG_SIZE=$(wc -c < "$OUTDIR/slices/${SLICE_NAME}.svg" | tr -d ' ')
        if [[ "$SVG_SIZE" -gt 200 ]]; then
            echo "  Z=$Z_LEVEL (${pct}): SVG exported ($SVG_SIZE bytes)"
        else
            echo "  Z=$Z_LEVEL (${pct}): Empty slice (no geometry at this Z)"
            rm -f "$OUTDIR/slices/${SLICE_NAME}.svg"
        fi
    else
        echo "  Z=$Z_LEVEL (${pct}): Export failed"
    fi
done

# --- Step 3: Primitive Detection with trimesh ---
echo ""
echo "--- Step 3: Primitive Detection ---"
python3 -c "
import trimesh
import numpy as np
import json

mesh = trimesh.load_mesh('$STL_FILE', force='mesh')
primitives = []

# Planar facets
try:
    for i, (facet, area) in enumerate(zip(mesh.facets, mesh.facets_area)):
        if area > 10:
            fn = mesh.face_normals[facet]
            avg_n = fn.mean(axis=0); avg_n /= np.linalg.norm(avg_n)
            fv = mesh.vertices[mesh.faces[facet].flatten()]
            primitives.append({'type':'plane','normal':avg_n.round(4).tolist(),'centroid':fv.mean(axis=0).round(3).tolist(),'area':round(float(area),2),'faces':len(facet)})
except Exception as e:
    print(f'Facet error: {e}')

# Cylindrical surfaces
normals = mesh.face_normals
curved_mask = np.all(np.abs(normals) < 0.85, axis=1)
curved_faces = np.where(curved_mask)[0]
print(f'Planar facets: {len([p for p in primitives if p[\"type\"]==\"plane\"])} (>{\"10mm²\"})')
print(f'Curved faces: {len(curved_faces)} ({len(curved_faces)/len(normals)*100:.0f}%)')

if len(curved_faces) > 10:
    cv = mesh.vertices[np.unique(mesh.faces[curved_faces].flatten())]
    cn = mesh.face_normals[curved_faces]
    # Axis from normal cross products
    axes_c = []
    for _ in range(min(200, len(cn))):
        i,j = np.random.choice(len(cn),2,replace=False)
        cp = np.cross(cn[i],cn[j])
        if np.linalg.norm(cp) > 0.1:
            cp /= np.linalg.norm(cp)
            if cp[0] < 0: cp *= -1
            axes_c.append(cp)
    if axes_c:
        ax = np.mean(axes_c, axis=0); ax /= np.linalg.norm(ax)
        # Project to 2D for circle fitting
        if abs(ax[0]) < 0.9: u = np.cross(ax,[1,0,0])
        else: u = np.cross(ax,[0,1,0])
        u /= np.linalg.norm(u); v = np.cross(ax,u)
        c3d = cv.mean(axis=0); centered = cv - c3d
        pu = centered@u; pv = centered@v; pa = centered@ax
        r = float(np.median(np.sqrt(pu**2+pv**2)))
        # Inward/outward
        fc = mesh.triangles_center[curved_faces]
        tc = c3d - fc; tc /= (np.linalg.norm(tc,axis=1,keepdims=True)+1e-10)
        inw = float(np.mean(np.sum(cn*tc,axis=1) > 0))
        op = 'difference' if inw > 0.5 else 'union'
        print(f'Cylinder: axis=[{ax[0]:.3f},{ax[1]:.3f},{ax[2]:.3f}] r={r:.3f} d={r*2:.3f} center={c3d.round(2).tolist()} type={op}')
        print(f'  Axis span: {float(pa.min()):.2f} to {float(pa.max()):.2f}')
        primitives.append({'type':'cylinder','axis':ax.round(4).tolist(),'radius':round(r,3),'diameter':round(r*2,3),'center':c3d.round(3).tolist(),'axis_min':round(float(pa.min()),3),'axis_max':round(float(pa.max()),3),'csg_operation':op,'inward_ratio':round(inw,3),'faces':int(len(curved_faces))})

with open('$OUTDIR/primitives.json','w') as f:
    json.dump(primitives,f,indent=2)
print(f'Saved {len(primitives)} primitives to $OUTDIR/primitives.json')
"

# --- Step 4: Generate Report ---
echo ""
echo "--- Step 4: Report ---"
echo "Profile slices saved in: $OUTDIR/slices/"
ls -la "$OUTDIR/slices/"*.svg 2>/dev/null | wc -l | xargs -I{} echo "  {} SVG slices generated"
echo "Primitives saved to: $OUTDIR/primitives.json"
echo "Mesh info saved to: $OUTDIR/mesh-info.json"
echo ""
echo "=== Analysis Complete ==="
