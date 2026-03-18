#!/usr/bin/env python3
"""
openscad-profile-extract.py — Extract 2D profiles from STL meshes

Detects the extrusion axis, extracts the dominant cross-section profile,
and generates OpenSCAD polygon() + linear_extrude() code.

Usage:
    python3 openscad-profile-extract.py <file.stl> [--output <file.scad>] [--simplify <tolerance>]
"""

import numpy as np
import trimesh
from trimesh import intersections
import json
import sys
import argparse


def segments_to_polygons(segments, snap=1e-4):
    """Convert line segments from mesh slicing to polygons using Shapely."""
    from shapely.geometry import MultiLineString
    from shapely.ops import polygonize

    lines = []
    for seg in np.asarray(segments):
        a = tuple(np.round(seg[0] / snap) * snap)
        b = tuple(np.round(seg[1] / snap) * snap)
        if a != b:
            lines.append([a, b])

    if not lines:
        return []

    return [p for p in polygonize(MultiLineString(lines)) if p.area > snap * snap]


def detect_extrusion_axis(mesh, n_slices=64):
    """Find the best extrusion axis by measuring cross-section stability.

    Returns: (stability_score, axis_index, transform, heights, polygons_per_slice)
    The axis with the LOWEST stability score is the extrusion direction.
    """
    # Use OBB for canonical alignment
    try:
        T = np.linalg.inv(mesh.bounding_box_oriented.primitive.transform)
    except Exception:
        T = np.eye(4)

    m = mesh.copy()
    m.apply_transform(T)

    best = None
    axis_names = ['X', 'Y', 'Z']

    for axis in range(3):
        lo, hi = m.bounds[0][axis], m.bounds[1][axis]
        margin = (hi - lo) * 0.02
        heights = np.linspace(lo + margin, hi - margin, n_slices)

        try:
            segments, _, _ = intersections.mesh_multiplane(
                m,
                plane_origin=np.zeros(3),
                plane_normal=np.eye(3)[axis],
                heights=heights,
            )
        except Exception:
            continue

        desc = []
        polys_by_slice = []
        for segs in segments:
            polys = segments_to_polygons(segs)
            polys_by_slice.append(polys)
            if not polys:
                desc.append([0, 0, 0, 0])
                continue
            from shapely.ops import unary_union
            u = unary_union(polys)
            n_holes = sum(len(p.interiors) for p in polys)
            desc.append([u.area, u.length, n_holes, len(polys)])

        if len([d for d in desc if d[0] > 0]) < n_slices // 3:
            continue

        arr = np.asarray(desc, dtype=float)
        nonzero = arr[arr[:, 0] > 0]
        if len(nonzero) < 3:
            continue

        # Stability = low variance in area/perimeter/holes across slices
        means = nonzero.mean(axis=0)
        means[means < 1e-6] = 1e-6
        stability = np.mean(np.std(nonzero / means, axis=0))

        extent = hi - lo
        item = (stability, axis, T, heights, polys_by_slice, extent)
        if best is None or item[0] < best[0]:
            best = item

        print(f"  Axis {axis_names[axis]}: stability={stability:.4f}, "
              f"extent={extent:.1f}mm, non-empty={len(nonzero)}/{n_slices}")

    return best


def extract_dominant_profile(polys_by_slice, simplify_tol=0.1):
    """Find the slice with the largest area and return its simplified polygon."""
    from shapely.ops import unary_union

    best_area = 0
    best_poly = None
    best_idx = 0

    for i, polys in enumerate(polys_by_slice):
        if not polys:
            continue
        u = unary_union(polys)
        if u.area > best_area:
            best_area = u.area
            best_poly = u
            best_idx = i

    if best_poly is None:
        return None, 0

    # Simplify to remove tessellation noise
    simplified = best_poly.simplify(simplify_tol, preserve_topology=True)
    return simplified, best_idx


def polygon_to_scad(poly, var_name="profile"):
    """Convert a Shapely polygon to OpenSCAD polygon() code."""
    points = []
    paths = []

    # Outer boundary
    exterior_coords = np.asarray(poly.exterior.coords[:-1], dtype=float)
    start = 0
    for coord in exterior_coords:
        points.append(list(np.round(coord, 3)))
    paths.append(list(range(start, start + len(exterior_coords))))

    # Holes (inner boundaries)
    for interior in poly.interiors:
        interior_coords = np.asarray(interior.coords[:-1], dtype=float)
        start = len(points)
        for coord in interior_coords:
            points.append(list(np.round(coord, 3)))
        # Reverse winding for holes
        paths.append(list(reversed(range(start, start + len(interior_coords)))))

    # Format as OpenSCAD
    pts_str = ",\n        ".join(f"[{p[0]}, {p[1]}]" for p in points)
    paths_str = ", ".join(f"{p}" for p in paths)

    return f"""module {var_name}() {{
    polygon(
        points = [
        {pts_str}
        ],
        paths = [{paths_str}]
    );
}}"""


def analyze_hole_variations(polys_by_slice, heights, dominant_idx):
    """Detect features that vary along the extrusion axis (holes appearing/disappearing)."""
    from shapely.ops import unary_union

    dominant_polys = polys_by_slice[dominant_idx]
    if not dominant_polys:
        return []

    dom_union = unary_union(dominant_polys)
    dom_holes = sum(len(p.interiors) for p in dominant_polys)

    variations = []
    for i, (polys, h) in enumerate(zip(polys_by_slice, heights)):
        if not polys:
            continue
        u = unary_union(polys)
        n_holes = sum(len(p.interiors) for p in polys)
        n_parts = len(polys)

        if n_holes != dom_holes or n_parts != len(dominant_polys):
            variations.append({
                'height': round(float(h), 3),
                'slice_idx': i,
                'holes': n_holes,
                'parts': n_parts,
                'area': round(float(u.area), 2),
                'dom_holes': dom_holes,
                'dom_parts': len(dominant_polys),
            })

    return variations


def generate_scad(profile_poly, extrusion_length, axis, variations=None):
    """Generate complete OpenSCAD file from extracted profile."""
    profile_code = polygon_to_scad(profile_poly, "extracted_profile")

    # Determine extrusion direction
    axis_names = ['X', 'Y', 'Z']

    scad = f"""// ============================================
// Auto-generated from STL profile extraction
// Extrusion axis: {axis_names[axis]}, length: {extrusion_length:.3f}mm
// Profile points: {len(profile_poly.exterior.coords) - 1}
// Profile holes: {len(profile_poly.interiors)}
// ============================================

// --- Parameters ---
extrusion_length = {extrusion_length:.3f};

// --- Quality ---
$fn = 64;
eps = 0.01;

// --- Extracted 2D Profile ---
{profile_code}

// --- Main Body ---
// Sculptor approach: extrude profile, then subtract features
difference() {{
    // Primary body from extracted profile
    linear_extrude(height = extrusion_length)
        extracted_profile();

    // TODO: Add subtractive features (holes, counterbores, chamfers)
    // detected from cross-section variations
"""

    if variations:
        scad += f"\n    // Feature variations detected at {len(variations)} heights:\n"
        for v in variations[:10]:  # Limit output
            scad += f"    // Z={v['height']}: {v['holes']} holes, {v['parts']} parts (dominant: {v['dom_holes']} holes, {v['dom_parts']} parts)\n"

    scad += "}\n"
    return scad


def main():
    parser = argparse.ArgumentParser(description='Extract 2D profile from STL mesh')
    parser.add_argument('stl_file', help='Input STL file')
    parser.add_argument('--output', '-o', help='Output .scad file')
    parser.add_argument('--simplify', type=float, default=0.1,
                        help='Profile simplification tolerance (mm)')
    parser.add_argument('--slices', type=int, default=64,
                        help='Number of slices per axis')
    parser.add_argument('--json', help='Output analysis as JSON')
    args = parser.parse_args()

    print(f"Loading: {args.stl_file}")
    mesh = trimesh.load_mesh(args.stl_file, force='mesh')
    trimesh.repair.fix_normals(mesh)

    print(f"Mesh: {len(mesh.vertices)} verts, {len(mesh.faces)} faces, "
          f"vol={mesh.volume:.1f}mm³")
    print(f"Bounds: {mesh.bounds[0].round(3)} to {mesh.bounds[1].round(3)}")
    dims = mesh.extents
    print(f"Dimensions: {dims[0]:.3f} x {dims[1]:.3f} x {dims[2]:.3f} mm")

    print(f"\nDetecting extrusion axis ({args.slices} slices per axis)...")
    result = detect_extrusion_axis(mesh, n_slices=args.slices)

    if result is None:
        print("ERROR: Could not detect extrusion axis")
        sys.exit(1)

    stability, axis, T, heights, polys_by_slice, extent = result
    axis_names = ['X', 'Y', 'Z']
    print(f"\nBest extrusion axis: {axis_names[axis]} "
          f"(stability={stability:.4f}, extent={extent:.1f}mm)")

    print("Extracting dominant profile...")
    profile, dom_idx = extract_dominant_profile(polys_by_slice, args.simplify)

    if profile is None:
        print("ERROR: Could not extract profile")
        sys.exit(1)

    n_pts = len(profile.exterior.coords) - 1
    n_holes = len(profile.interiors)
    print(f"Profile: {n_pts} points, {n_holes} holes, area={profile.area:.1f}mm²")

    print("Analyzing feature variations along extrusion axis...")
    variations = analyze_hole_variations(polys_by_slice, heights, dom_idx)
    print(f"Found {len(variations)} slices with different features")

    # Generate OpenSCAD
    scad_code = generate_scad(profile, extent, axis, variations)

    if args.output:
        with open(args.output, 'w') as f:
            f.write(scad_code)
        print(f"\nOpenSCAD saved to: {args.output}")
    else:
        print(f"\n--- Generated OpenSCAD ---")
        print(scad_code)

    if args.json:
        analysis = {
            'extrusion_axis': axis_names[axis],
            'extrusion_length': round(float(extent), 3),
            'stability_score': round(float(stability), 4),
            'profile_points': n_pts,
            'profile_holes': n_holes,
            'profile_area': round(float(profile.area), 2),
            'feature_variations': variations[:20],
        }
        with open(args.json, 'w') as f:
            json.dump(analysis, f, indent=2)
        print(f"Analysis saved to: {args.json}")


if __name__ == '__main__':
    main()
