#!/usr/bin/env python3
"""
openscad-adaptive-slice.py — Adaptive multi-axis SVG slicing

Slices an STL on all 3 axes with adaptive resolution:
1. Coarse pass (every 5mm) → detect transitions
2. Fine pass (every 0.5mm) only at transitions
3. Outputs a complete feature map of the model

Usage:
    python3 openscad-adaptive-slice.py <file.stl> <output_dir> [--coarse 5] [--fine 0.5]
"""

import numpy as np
import trimesh
from trimesh import intersections
from shapely.geometry import MultiLineString
from shapely.ops import polygonize, unary_union
import json
import sys
import os
import argparse


def segments_to_polygons(segments, snap=1e-4):
    """Convert mesh slice segments to Shapely polygons."""
    lines = []
    for seg in np.asarray(segments):
        a = tuple(np.round(seg[0] / snap) * snap)
        b = tuple(np.round(seg[1] / snap) * snap)
        if a != b:
            lines.append([a, b])
    if not lines:
        return []
    return [p for p in polygonize(MultiLineString(lines)) if p.area > snap * snap]


def slice_at_height(mesh, axis, height):
    """Slice mesh at a given height along an axis. Returns polygon descriptors."""
    try:
        normal = np.zeros(3)
        normal[axis] = 1.0
        origin = np.zeros(3)
        origin[axis] = height

        segments, _, _ = intersections.mesh_multiplane(
            mesh, plane_origin=origin, plane_normal=normal, heights=[0.0])

        if not segments or len(segments[0]) == 0:
            return None

        polys = segments_to_polygons(segments[0])
        if not polys:
            return None

        combined = unary_union(polys)
        n_holes = sum(len(p.interiors) for p in polys) if hasattr(polys[0], 'interiors') else 0

        return {
            'height': round(float(height), 3),
            'area': round(float(combined.area), 2),
            'perimeter': round(float(combined.length), 2),
            'n_contours': len(polys),
            'n_holes': n_holes,
            'bounds': [round(float(x), 2) for x in combined.bounds],
            'width': round(float(combined.bounds[2] - combined.bounds[0]), 2),
            'height_2d': round(float(combined.bounds[3] - combined.bounds[1]), 2),
        }
    except Exception:
        return None


def detect_transitions(slices, threshold=0.1):
    """Find heights where the cross-section changes significantly."""
    transitions = []
    for i in range(1, len(slices)):
        prev = slices[i - 1]
        curr = slices[i]
        if prev is None or curr is None:
            if prev is not None or curr is not None:
                transitions.append(i)
            continue

        # Detect changes in area, contour count, or holes
        area_change = abs(curr['area'] - prev['area']) / max(prev['area'], 1)
        contour_change = curr['n_contours'] != prev['n_contours']
        hole_change = curr['n_holes'] != prev['n_holes']
        width_change = abs(curr['width'] - prev['width']) / max(prev['width'], 1)

        if area_change > threshold or contour_change or hole_change or width_change > threshold:
            transitions.append(i)

    return transitions


def adaptive_slice_axis(mesh, axis, coarse_step=5.0, fine_step=0.5, fine_range=3.0, threshold=0.1):
    """Adaptive slicing along one axis.

    1. Coarse pass at coarse_step intervals
    2. Detect transitions
    3. Fine pass around each transition
    """
    axis_names = ['X', 'Y', 'Z']
    lo, hi = mesh.bounds[0][axis], mesh.bounds[1][axis]
    extent = hi - lo

    # Pass 1: Coarse
    coarse_heights = np.arange(lo + coarse_step / 2, hi, coarse_step)
    coarse_slices = []
    for h in coarse_heights:
        s = slice_at_height(mesh, axis, h)
        coarse_slices.append(s)

    # Detect transitions
    trans_indices = detect_transitions(coarse_slices, threshold)
    transition_heights = [float(coarse_heights[i]) for i in trans_indices]

    print(f"  {axis_names[axis]}: {len(coarse_heights)} coarse slices, "
          f"{len(transition_heights)} transitions detected")

    if transition_heights:
        zones = ", ".join(f"{h:.1f}" for h in transition_heights)
        print(f"    Transition zones: {zones}")

    # Pass 2: Fine slicing around transitions
    fine_slices = []
    fine_heights_set = set()
    for th in transition_heights:
        fine_lo = max(lo, th - fine_range)
        fine_hi = min(hi, th + fine_range)
        for h in np.arange(fine_lo, fine_hi, fine_step):
            h_round = round(float(h), 3)
            if h_round not in fine_heights_set:
                fine_heights_set.add(h_round)
                s = slice_at_height(mesh, axis, h_round)
                if s:
                    fine_slices.append(s)

    # Combine coarse + fine, sorted by height
    all_slices = []
    all_heights = set()

    for s, h in zip(coarse_slices, coarse_heights):
        h_round = round(float(h), 3)
        if s and h_round not in all_heights:
            all_heights.add(h_round)
            all_slices.append(s)

    for s in fine_slices:
        if s['height'] not in all_heights:
            all_heights.add(s['height'])
            all_slices.append(s)

    all_slices.sort(key=lambda s: s['height'])

    print(f"    Total slices: {len(all_slices)} ({len(coarse_slices)} coarse + {len(fine_slices)} fine)")

    return {
        'axis': axis_names[axis],
        'extent': round(float(extent), 3),
        'n_coarse': len(coarse_slices),
        'n_fine': len(fine_slices),
        'n_total': len(all_slices),
        'transitions': [round(h, 3) for h in transition_heights],
        'slices': all_slices,
    }


def build_feature_map(axis_results):
    """Build a unified feature map from all 3 axes."""
    features = []

    for result in axis_results:
        axis = result['axis']
        slices = result['slices']
        transitions = result['transitions']

        if not slices:
            continue

        # Identify feature zones (between transitions)
        zones = []
        sorted_trans = sorted(transitions)

        # Zone before first transition
        pre_slices = [s for s in slices if s['height'] < (sorted_trans[0] if sorted_trans else 1e6)]
        if pre_slices:
            avg_area = np.mean([s['area'] for s in pre_slices])
            avg_contours = round(np.mean([s['n_contours'] for s in pre_slices]))
            avg_holes = round(np.mean([s['n_holes'] for s in pre_slices]))
            zones.append({
                'axis': axis,
                'from': round(float(slices[0]['height']), 2),
                'to': round(float(sorted_trans[0]), 2) if sorted_trans else round(float(slices[-1]['height']), 2),
                'avg_area': round(float(avg_area), 1),
                'contours': int(avg_contours),
                'holes': int(avg_holes),
                'type': classify_zone(avg_area, avg_contours, avg_holes),
            })

        # Zones between transitions
        for i in range(len(sorted_trans)):
            t_lo = sorted_trans[i]
            t_hi = sorted_trans[i + 1] if i + 1 < len(sorted_trans) else slices[-1]['height']
            zone_slices = [s for s in slices if t_lo <= s['height'] <= t_hi]
            if zone_slices:
                avg_area = np.mean([s['area'] for s in zone_slices])
                avg_contours = round(np.mean([s['n_contours'] for s in zone_slices]))
                avg_holes = round(np.mean([s['n_holes'] for s in zone_slices]))
                zones.append({
                    'axis': axis,
                    'from': round(float(t_lo), 2),
                    'to': round(float(t_hi), 2),
                    'avg_area': round(float(avg_area), 1),
                    'contours': int(avg_contours),
                    'holes': int(avg_holes),
                    'type': classify_zone(avg_area, avg_contours, avg_holes),
                })

        features.extend(zones)

    return features


def classify_zone(area, contours, holes):
    """Classify a zone based on its cross-section properties."""
    if contours == 1 and holes == 0:
        return 'solid'
    elif contours == 1 and holes > 0:
        return 'solid_with_holes'
    elif contours == 2 and holes == 0:
        return 'shell_or_channel'
    elif contours > 2:
        return 'multi_body'
    else:
        return 'complex'


def main():
    parser = argparse.ArgumentParser(description='Adaptive multi-axis STL slicing')
    parser.add_argument('stl_file', help='Input STL file')
    parser.add_argument('output_dir', help='Output directory')
    parser.add_argument('--coarse', type=float, default=5.0, help='Coarse step (mm)')
    parser.add_argument('--fine', type=float, default=0.5, help='Fine step (mm)')
    parser.add_argument('--range', type=float, default=3.0, help='Fine range around transitions (mm)')
    parser.add_argument('--threshold', type=float, default=0.1, help='Change threshold (0-1)')
    args = parser.parse_args()

    os.makedirs(args.output_dir, exist_ok=True)

    print(f"Loading: {args.stl_file}")
    mesh = trimesh.load_mesh(args.stl_file, force='mesh')
    trimesh.repair.fix_normals(mesh)

    dims = mesh.extents
    print(f"Mesh: {len(mesh.vertices)} verts, {len(mesh.faces)} faces, vol={mesh.volume:.1f}mm³")
    print(f"Dimensions: {dims[0]:.1f} x {dims[1]:.1f} x {dims[2]:.1f} mm")
    print(f"Coarse: {args.coarse}mm, Fine: {args.fine}mm, Range: ±{args.range}mm")
    print()

    # Slice on all 3 axes
    print("=== Adaptive Multi-Axis Slicing ===")
    axis_results = []
    for axis in range(3):
        result = adaptive_slice_axis(
            mesh, axis,
            coarse_step=args.coarse,
            fine_step=args.fine,
            fine_range=args.range,
            threshold=args.threshold,
        )
        axis_results.append(result)

    # Build feature map
    print("\n=== Feature Map ===")
    features = build_feature_map(axis_results)
    for f in features:
        print(f"  {f['axis']} [{f['from']:.1f} → {f['to']:.1f}]: "
              f"{f['type']} (area={f['avg_area']:.0f}, contours={f['contours']}, holes={f['holes']})")

    # Summary
    print(f"\n=== Summary ===")
    total_slices = sum(r['n_total'] for r in axis_results)
    total_coarse = sum(r['n_coarse'] for r in axis_results)
    total_fine = sum(r['n_fine'] for r in axis_results)
    total_trans = sum(len(r['transitions']) for r in axis_results)
    print(f"Total slices: {total_slices} ({total_coarse} coarse + {total_fine} fine)")
    print(f"Transitions detected: {total_trans}")
    print(f"Feature zones: {len(features)}")

    # Save results
    output = {
        'file': args.stl_file,
        'dimensions': dims.tolist(),
        'volume': float(mesh.volume),
        'settings': {
            'coarse_step': args.coarse,
            'fine_step': args.fine,
            'fine_range': args.range,
            'threshold': args.threshold,
        },
        'axes': [{
            'axis': r['axis'],
            'extent': r['extent'],
            'n_slices': r['n_total'],
            'transitions': r['transitions'],
        } for r in axis_results],
        'features': features,
        'total_slices': total_slices,
        'total_transitions': total_trans,
    }

    output_path = os.path.join(args.output_dir, 'adaptive-slicing.json')
    with open(output_path, 'w') as f:
        json.dump(output, f, indent=2)
    print(f"\nResults saved to: {output_path}")


if __name__ == '__main__':
    main()
