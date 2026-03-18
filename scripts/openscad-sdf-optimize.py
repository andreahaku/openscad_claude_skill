#!/usr/bin/env python3
"""
openscad-sdf-optimize.py — SDF-based parametric model optimizer

Uses Signed Distance Fields and IoU scoring to find optimal parameters
for an OpenSCAD reconstruction WITHOUT invoking OpenSCAD in the loop.

Usage:
    python3 openscad-sdf-optimize.py <original.stl> <model_type> [options]

Model types:
    stadium-slot    Stadium body with cylindrical slot cut
    box-holes       Rectangular body with through holes
    custom          Custom SDF defined in a Python module

Options:
    --samples N     Number of sample points (default: 30000)
    --output FILE   Output JSON with optimized parameters
    --verbose       Print optimization progress
"""

import numpy as np
import trimesh
import json
import sys
import os
from scipy.optimize import minimize, least_squares


# ========== SDF Primitives ==========

def sdf_box(p, size):
    """Signed distance to an axis-aligned box centered at origin."""
    half = np.array(size) / 2
    q = np.abs(p) - half
    return np.linalg.norm(np.maximum(q, 0), axis=1) + np.minimum(np.max(q, axis=1), 0)


def sdf_cylinder_x(p, radius, half_length, center=None):
    """Signed distance to a cylinder along X axis."""
    if center is not None:
        p = p - np.array(center)
    d_yz = np.sqrt(p[:, 1]**2 + p[:, 2]**2) - radius
    d_x = np.abs(p[:, 0]) - half_length
    return np.minimum(np.maximum(d_yz, d_x), 0) + np.linalg.norm(
        np.maximum(np.column_stack([d_yz, d_x]), 0), axis=1)


def sdf_capsule_x(p, radius, half_span, center=None):
    """Signed distance to a capsule (two spheres hulled) along X axis."""
    if center is not None:
        p = p - np.array(center)
    # Clamp X to [-half_span, half_span]
    px_clamped = np.clip(p[:, 0], -half_span, half_span)
    q = p.copy()
    q[:, 0] -= px_clamped
    return np.linalg.norm(q, axis=1) - radius


def sdf_stadium_extrude(p, total_len, width, height):
    """SDF for a stadium shape extruded along Z."""
    r = width / 2
    half_span = total_len / 2 - r
    # 2D stadium distance in XY
    px_clamped = np.clip(p[:, 0], -half_span, half_span)
    dx = p[:, 0] - px_clamped
    d_xy = np.sqrt(dx**2 + p[:, 1]**2) - r
    # Z bounds
    d_z = np.abs(p[:, 2] - height / 2) - height / 2
    return np.maximum(d_xy, d_z)


# ========== CSG Operations ==========

def sdf_union(d1, d2):
    return np.minimum(d1, d2)

def sdf_difference(d1, d2):
    return np.maximum(d1, -d2)

def sdf_intersection(d1, d2):
    return np.maximum(d1, d2)


# ========== Model Definitions ==========

def model_stadium_slot(p, params):
    """Stadium body with cylindrical slot carved from top.
    params: [length, width, height, slot_total, slot_width, cyl_d, cyl_center_z]
    """
    L, W, H, sL, sW, cD, cZ = params
    body = sdf_stadium_extrude(p, L, W, H)
    # Cylinder slot along X
    half_span = sL / 2 - sW / 2
    cyl = sdf_capsule_x(p, cD / 2, half_span, center=[0, 0, cZ])
    return sdf_difference(body, cyl)


def model_box_with_holes(p, params):
    """Rectangular box with cylindrical through-holes.
    params: [sx, sy, sz, hole_d, hole_z, n_holes, hole_spacing, hole_x_start]
    """
    sx, sy, sz, hole_d, hole_z, n_holes, spacing, x_start = params
    n_holes = int(round(n_holes))
    body = sdf_box(p, [sx, sy, sz])
    # Offset body center
    result = body
    for i in range(n_holes):
        hx = x_start + i * spacing
        hole = sdf_cylinder_x(p, hole_d / 2, sy, center=[hx, 0, hole_z - sz/2])
        # Rotate hole to Y axis
        p_rot = p.copy()
        p_rot[:, 0] = p[:, 1]
        p_rot[:, 1] = p[:, 0]
        hole = sdf_cylinder_x(p_rot, hole_d / 2, sx, center=[0, hx, hole_z - sz/2])
        result = sdf_difference(result, hole)
    return result


MODEL_REGISTRY = {
    'stadium-slot': {
        'sdf': model_stadium_slot,
        'param_names': ['length', 'width', 'height', 'slot_total', 'slot_width', 'cyl_d', 'cyl_center_z'],
    },
    'box-holes': {
        'sdf': model_box_with_holes,
        'param_names': ['sx', 'sy', 'sz', 'hole_d', 'hole_z', 'n_holes', 'spacing', 'x_start'],
    },
}


# ========== Scoring ==========

def compute_iou(target_inside, candidate_inside):
    """Intersection over Union from boolean occupancy arrays."""
    intersection = np.count_nonzero(target_inside & candidate_inside)
    union = np.count_nonzero(target_inside | candidate_inside)
    if union == 0:
        return 0.0
    return intersection / union


def compute_score(mesh, sdf_func, params, sample_points, target_inside):
    """Score a candidate model against the target mesh."""
    candidate_sdf = sdf_func(sample_points, params)
    candidate_inside = candidate_sdf <= 0
    iou = compute_iou(target_inside, candidate_inside)
    return iou


# ========== Initialization from Mesh Analysis ==========

def init_params_from_mesh(mesh, model_type):
    """Extract initial parameters from mesh analysis."""
    bounds = mesh.bounds
    dims = bounds[1] - bounds[0]
    center = mesh.centroid

    if model_type == 'stadium-slot':
        # Use section analysis to find slot
        sections = []
        z_min, z_max = bounds[0][2], bounds[1][2]
        for pct in [0.01, 0.25, 0.5, 0.75, 0.99]:
            z = z_min + (z_max - z_min) * pct
            try:
                path = mesh.section(plane_origin=[0, 0, z], plane_normal=[0, 0, 1])
                if path:
                    path2d, _ = path.to_2D()
                    polys = path2d.polygons_full
                    areas = [p.area for p in polys]
                    sections.append({'z': z, 'n_contours': len(polys), 'areas': areas,
                                     'total_area': sum(areas)})
            except:
                pass

        # Estimate slot from difference in areas across Z
        if sections:
            body_area = max(s['total_area'] for s in sections)
            # The slot width can be estimated from how the contour changes
            # For now, use bounding box as starting point
            slot_width_est = dims[1] * 0.33  # ~1/3 of body width
            slot_len_est = dims[0] * 0.89    # ~89% of body length

        return [
            dims[0],              # length
            dims[1],              # width
            dims[2],              # height
            dims[0] * 0.89,       # slot_total (slightly shorter than body)
            dims[1] * 0.33,       # slot_width (1/3 of body width)
            dims[2] * 0.8,        # cyl_d (80% of height)
            dims[2] * 0.6,        # cyl_center_z (60% up)
        ]

    return list(dims) + [0] * 4


# ========== Main Optimization ==========

def optimize(stl_path, model_type, n_samples=30000, verbose=False):
    """Main optimization pipeline."""
    print(f"Loading mesh: {stl_path}")
    mesh = trimesh.load_mesh(stl_path, force='mesh')
    trimesh.repair.fix_normals(mesh)

    print(f"Mesh: {len(mesh.vertices)} verts, {len(mesh.faces)} faces, vol={mesh.volume:.1f}mm³")

    # Sample points in and around the bounding box
    margin = 2.0
    pts = np.random.uniform(
        mesh.bounds[0] - margin,
        mesh.bounds[1] + margin,
        (n_samples, 3)
    )

    # Compute target occupancy
    print("Computing target occupancy...")
    target_sdf = trimesh.proximity.signed_distance(mesh, pts)
    target_inside = target_sdf >= 0  # trimesh convention: positive = inside

    print(f"Target: {np.sum(target_inside)}/{n_samples} points inside ({np.mean(target_inside)*100:.1f}%)")

    # Get model SDF function
    model_info = MODEL_REGISTRY[model_type]
    sdf_func = model_info['sdf']
    param_names = model_info['param_names']

    # Initialize parameters from mesh analysis
    print("Initializing parameters from mesh analysis...")
    x0 = np.array(init_params_from_mesh(mesh, model_type))
    print(f"Initial params: {dict(zip(param_names, x0.round(3)))}")

    # Score initial
    iou0 = compute_score(mesh, sdf_func, x0, pts, target_inside)
    print(f"Initial IoU: {iou0:.4f} ({iou0*100:.1f}%)")

    # Optimize with Powell method
    print("\nOptimizing with Powell method...")
    iter_count = [0]

    def objective(x):
        iter_count[0] += 1
        candidate_sdf = sdf_func(pts, x)
        candidate_inside = candidate_sdf <= 0
        iou = compute_iou(target_inside, candidate_inside)
        if verbose and iter_count[0] % 10 == 0:
            print(f"  iter {iter_count[0]}: IoU={iou:.4f} params={x.round(3)}")
        return 1.0 - iou  # minimize = maximize IoU

    # Set bounds (all positive, reasonable ranges)
    dims = mesh.bounds[1] - mesh.bounds[0]
    bounds_lo = x0 * 0.5
    bounds_hi = x0 * 1.5
    # Ensure positive
    bounds_lo = np.maximum(bounds_lo, 0.1)

    result = minimize(
        objective, x0,
        method='Powell',
        options={'maxiter': 500, 'ftol': 1e-6, 'disp': verbose}
    )

    final_params = result.x
    final_iou = 1.0 - result.fun

    print(f"\nOptimization complete ({iter_count[0]} iterations)")
    print(f"Final IoU: {final_iou:.4f} ({final_iou*100:.1f}%)")
    print(f"Final params:")
    for name, val in zip(param_names, final_params):
        print(f"  {name} = {val:.4f}")

    # Generate OpenSCAD code
    scad_code = generate_scad(model_type, param_names, final_params)
    print(f"\n--- Generated OpenSCAD ---\n{scad_code}")

    return {
        'model_type': model_type,
        'params': dict(zip(param_names, [round(float(v), 4) for v in final_params])),
        'iou': round(float(final_iou), 4),
        'iterations': iter_count[0],
        'volume_target': round(float(mesh.volume), 2),
        'scad_code': scad_code,
    }


def generate_scad(model_type, param_names, params):
    """Generate OpenSCAD code from optimized parameters."""
    p = dict(zip(param_names, params))

    if model_type == 'stadium-slot':
        return f"""// Auto-generated by SDF optimizer
// IoU-optimized parameters
length = {p['length']:.3f};
width = {p['width']:.3f};
height = {p['height']:.3f};
slot_total = {p['slot_total']:.3f};
slot_width = {p['slot_width']:.3f};
cyl_d = {p['cyl_d']:.3f};
cyl_center_z = {p['cyl_center_z']:.3f};

$fn = 64;

difference() {{
    linear_extrude(height = height)
        stadium(length, width);
    translate([0, 0, cyl_center_z])
        hull() {{
            translate([-(slot_total/2 - slot_width/2), 0, 0]) sphere(d=cyl_d, $fn=64);
            translate([(slot_total/2 - slot_width/2), 0, 0]) sphere(d=cyl_d, $fn=64);
        }}
}}

module stadium(l, w) {{
    r = w / 2;
    hull() {{
        translate([-(l/2 - r), 0]) circle(r=r);
        translate([(l/2 - r), 0]) circle(r=r);
    }}
}}
"""
    return f"// No code generator for model_type={model_type}"


# ========== CLI ==========

if __name__ == '__main__':
    import argparse
    parser = argparse.ArgumentParser(description='SDF-based OpenSCAD parameter optimizer')
    parser.add_argument('stl_file', help='Input STL file')
    parser.add_argument('model_type', choices=list(MODEL_REGISTRY.keys()),
                        help='Model type to fit')
    parser.add_argument('--samples', type=int, default=30000, help='Sample points')
    parser.add_argument('--output', help='Output JSON file')
    parser.add_argument('--verbose', action='store_true', help='Show progress')
    args = parser.parse_args()

    result = optimize(args.stl_file, args.model_type,
                      n_samples=args.samples, verbose=args.verbose)

    if args.output:
        with open(args.output, 'w') as f:
            json.dump(result, f, indent=2)
        print(f"\nResults saved to {args.output}")
