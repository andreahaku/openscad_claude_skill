#!/usr/bin/env bash
# openscad-stl-analyze.sh — Extract geometry data from binary STL files
# Outputs bounding box, vertex distributions, and internal structure hints
set -euo pipefail

usage() {
    cat <<'EOF'
Usage: openscad-stl-analyze.sh <file.stl> [--cross-section <axis> <value>] [--gaps <axis>]

Commands:
  <file.stl>                       Full bounding box and triangle count
  --cross-section <axis> <value>   Show vertex distribution at a cross-section
                                   axis: x, y, or z; value: coordinate
  --gaps <axis>                    Find gaps in vertex distribution along axis
                                   (useful for finding internal features)

Examples:
  openscad-stl-analyze.sh model.stl
  openscad-stl-analyze.sh model.stl --cross-section z 0
  openscad-stl-analyze.sh model.stl --gaps y

EOF
    exit 1
}

[[ $# -lt 1 ]] && usage

STL_FILE="$1"
shift

if [[ ! -f "$STL_FILE" ]]; then
    echo "ERROR: File not found: $STL_FILE" >&2
    exit 1
fi

# Default: full analysis
if [[ $# -eq 0 ]]; then
    python3 -c "
import struct, math, sys
from collections import defaultdict

path = '$STL_FILE'
with open(path, 'rb') as f:
    header = f.read(80)
    n = struct.unpack('<I', f.read(4))[0]
    verts = set()
    for _ in range(n):
        f.read(12)  # normal
        for _ in range(3):
            v = struct.unpack('<3f', f.read(12))
            verts.add((round(v[0],4), round(v[1],4), round(v[2],4)))
        f.read(2)

xs = [v[0] for v in verts]
ys = [v[1] for v in verts]
zs = [v[2] for v in verts]

print('=== STL Analysis ===')
print(f'File: {path}')
print(f'Triangles: {n}')
print(f'Unique vertices: {len(verts)}')
print()
print('=== Bounding Box ===')
print(f'X: {min(xs):.4f} to {max(xs):.4f} = {max(xs)-min(xs):.4f} mm')
print(f'Y: {min(ys):.4f} to {max(ys):.4f} = {max(ys)-min(ys):.4f} mm')
print(f'Z: {min(zs):.4f} to {max(zs):.4f} = {max(zs)-min(zs):.4f} mm')
print(f'Center: ({(min(xs)+max(xs))/2:.4f}, {(min(ys)+max(ys))/2:.4f}, {(min(zs)+max(zs))/2:.4f})')
print()
print('=== Symmetry Check ===')
cx, cy, cz = (min(xs)+max(xs))/2, (min(ys)+max(ys))/2, (min(zs)+max(zs))/2
print(f'X symmetric: {abs(cx) < 0.01} (center offset: {cx:.4f})')
print(f'Y symmetric: {abs(cy) < 0.01} (center offset: {cy:.4f})')
print(f'Z base at 0: {abs(min(zs)) < 0.01}')
print()
print('=== Distinct Values Per Axis ===')
print(f'Distinct X values: {len(set(round(x,3) for x in xs))}')
print(f'Distinct Y values: {len(set(round(y,3) for y in ys))}')
print(f'Distinct Z values: {len(set(round(z,3) for z in zs))}')
print()

# Gap detection on each axis
for axis_name, vals in [('X', xs), ('Y', ys), ('Z', zs)]:
    sorted_unique = sorted(set(round(v,3) for v in vals))
    gaps = []
    for i in range(len(sorted_unique)-1):
        gap = sorted_unique[i+1] - sorted_unique[i]
        if gap > (max(vals)-min(vals)) * 0.05:  # gaps > 5% of range
            gaps.append((sorted_unique[i], sorted_unique[i+1], gap))
    if gaps:
        print(f'{axis_name}-axis gaps (>5% of range):')
        for v1, v2, g in gaps:
            print(f'  {v1:.3f} to {v2:.3f} (gap={g:.3f} mm) — possible internal feature boundary')
        print()
"
    exit 0
fi

# Cross-section analysis
if [[ "$1" == "--cross-section" ]]; then
    [[ $# -lt 3 ]] && usage
    AXIS="$2"
    VALUE="$3"
    python3 -c "
import struct

path = '$STL_FILE'
axis = '$AXIS'
value = float($VALUE)

with open(path, 'rb') as f:
    f.read(80)
    n = struct.unpack('<I', f.read(4))[0]
    verts = set()
    for _ in range(n):
        f.read(12)
        for _ in range(3):
            v = struct.unpack('<3f', f.read(12))
            verts.add((round(v[0],4), round(v[1],4), round(v[2],4)))
        f.read(2)

axis_idx = {'x':0, 'y':1, 'z':2}[axis]
other_axes = [i for i in range(3) if i != axis_idx]
axis_names = 'XYZ'

# Find vertices near the cross-section plane
tolerance = 0.02
cross_verts = [(v[other_axes[0]], v[other_axes[1]])
               for v in verts if abs(v[axis_idx] - value) < tolerance]

if not cross_verts:
    # Widen tolerance
    tolerance = 0.2
    cross_verts = [(v[other_axes[0]], v[other_axes[1]])
                   for v in verts if abs(v[axis_idx] - value) < tolerance]

print(f'=== Cross-section at {axis_names[axis_idx]}={value:.3f} (tol={tolerance}) ===')
print(f'Found {len(cross_verts)} vertices')
if cross_verts:
    a_vals = sorted(set(round(v[0],4) for v in cross_verts))
    b_vals = sorted(set(round(v[1],4) for v in cross_verts))
    print(f'{axis_names[other_axes[0]]} range: {min(a_vals):.4f} to {max(a_vals):.4f}')
    print(f'{axis_names[other_axes[1]]} range: {min(b_vals):.4f} to {max(b_vals):.4f}')
    print()

    # Show |values| distribution for the narrower axis (usually reveals internal features)
    for oa, name in [(0, axis_names[other_axes[0]]), (1, axis_names[other_axes[1]])]:
        abs_vals = sorted(set(round(abs(v[oa]),4) for v in cross_verts))
        if len(abs_vals) < 80:
            print(f'|{name}| distribution:')
            for av in abs_vals:
                bar = '#' * int(av * 8)
                print(f'  |{name}|={av:7.4f}  {bar}')
            print()
            # Find gaps
            for i in range(len(abs_vals)-1):
                gap = abs_vals[i+1] - abs_vals[i]
                if gap > 0.5:
                    print(f'  GAP: |{name}|={abs_vals[i]:.4f} to |{name}|={abs_vals[i+1]:.4f} (width={gap:.4f})')
                    print(f'  -> Possible feature boundary at |{name}|={abs_vals[i]:.4f}')
"
    exit 0
fi

# Gap analysis
if [[ "$1" == "--gaps" ]]; then
    [[ $# -lt 2 ]] && usage
    AXIS="$2"
    python3 -c "
import struct
from collections import defaultdict

path = '$STL_FILE'
axis = '$AXIS'
axis_idx = {'x':0, 'y':1, 'z':2}[axis]
axis_names = 'XYZ'

with open(path, 'rb') as f:
    f.read(80)
    n = struct.unpack('<I', f.read(4))[0]
    verts = set()
    for _ in range(n):
        f.read(12)
        for _ in range(3):
            v = struct.unpack('<3f', f.read(12))
            verts.add((round(v[0],4), round(v[1],4), round(v[2],4)))
        f.read(2)

# Get all distinct values for other axes, grouped by the target axis levels
other_axes = [i for i in range(3) if i != axis_idx]

# Find distinct levels of the target axis
levels = sorted(set(round(v[axis_idx], 3) for v in verts))
print(f'=== {axis_names[axis_idx]}-axis gap analysis ===')
print(f'Distinct {axis_names[axis_idx]} levels: {len(levels)}')
print()

for level in levels:
    level_verts = [v for v in verts if abs(v[axis_idx] - level) < 0.005]
    for oa in other_axes:
        abs_vals = sorted(set(round(abs(v[oa]), 4) for v in level_verts))
        gaps = []
        for i in range(len(abs_vals)-1):
            g = abs_vals[i+1] - abs_vals[i]
            if g > 0.5:
                gaps.append((abs_vals[i], abs_vals[i+1], g))
        if gaps:
            print(f'{axis_names[axis_idx]}={level:6.3f}: |{axis_names[oa]}| gaps:')
            for v1, v2, g in gaps:
                print(f'  {v1:.4f} to {v2:.4f} (gap={g:.4f}) — feature boundary')
"
    exit 0
fi

usage
