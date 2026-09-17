"""Build editable vector artwork from an open, constant-width, half-twisted strip.

Requires numpy and shapely. No reference raster is sampled or traced.
Run from any directory; outputs are written alongside this source directory.
"""
from pathlib import Path
import json
import math
import numpy as np
from shapely.geometry import Polygon, box
from shapely.ops import unary_union

ROOT = Path(__file__).resolve().parent.parent
RADIUS = 218.0
WIDTH = 184.0
ARM = 310.0
CAP_RADIUS = 40.0
TILT = 0.30
DEPTH_X = 0.75
TWIST_SPAN = 3.10
TWIST_OFFSET = 0.0


def surface(s, v):
    """A 3D ruled strip with unit transverse direction and a 180 degree rotation.

    s is centerline arc length; v is physical distance across the strip.
    All cross sections have width WIDTH before the small corner trims at the ends.
    The oblique drawing projection exposes the overlap without rotating the arms.
    """
    if s < 0:
        x, y, nx, ny = -RADIUS, s, 1, 0
    elif s > math.pi * RADIUS:
        x, y, nx, ny = RADIUS, -(s - math.pi * RADIUS), -1, 0
    else:
        a = s / RADIUS
        x, y = -RADIUS * math.cos(a), RADIUS * math.sin(a)
        nx, ny = math.cos(a), -math.sin(a)
    q = np.clip((s / RADIUS - ((math.pi - TWIST_SPAN) / 2 + TWIST_OFFSET)) / TWIST_SPAN, 0, 1)
    theta = -math.pi * (3 * q * q - 2 * q * q * q)
    return np.array([x + v * nx * math.cos(theta), y + v * ny * math.cos(theta), v * math.sin(theta)])


def project(p):
    x, y, z = p
    return np.array([512 + x + DEPTH_X * z, 500 + y * math.cos(TILT) - z * math.sin(TILT)])


def geometry():
    ss = np.unique(np.r_[np.linspace(-ARM, 0, 12), np.linspace(0, math.pi * RADIUS, 601), np.linspace(math.pi * RADIUS, math.pi * RADIUS + ARM, 12)])
    vs = np.linspace(-WIDTH / 2, WIDTH / 2, 65)
    pp = np.array([[project(surface(s, v)) for v in vs] for s in ss])
    cyan, coral = [], []
    for i in range(len(ss) - 1):
        for j in range(len(vs) - 1):
            quad = [pp[i, j], pp[i + 1, j], pp[i + 1, j + 1], pp[i, j + 1]]
            # Triangles avoid bow ties at the silhouette fold.
            for tri in ([quad[0], quad[1], quad[2]], [quad[0], quad[2], quad[3]]):
                a, b = tri[1] - tri[0], tri[2] - tri[0]
                cross = a[0] * b[1] - a[1] * b[0]
                if abs(cross) > 1e-9:
                    (cyan if cross < 0 else coral).append(Polygon(tri))
    result = [unary_union(cyan), unary_union(coral)]
    # Soften only the terminal corners. Longitudinal ribbon edges keep their width.
    y0 = 500 - ARM * math.cos(TILT)
    rr = CAP_RADIUS
    clip = box(0, y0 + rr, 1024, 1024)
    for cx in (512 - RADIUS, 512 + RADIUS):
        rounded = box(cx - WIDTH / 2 + rr, y0 + rr, cx + WIDTH / 2 - rr, y0 + 2 * rr).buffer(rr, quad_segs=32)
        clip = clip.union(rounded)
    result = [p.intersection(clip).buffer(0) for p in result]
    # Remove occluded cyan cusp geometry, retaining a 2-unit underlap for a clean
    # antialiased seam. This changes only the hidden face, never the silhouette.
    visible = result[0].difference(result[1])
    if visible.geom_type == 'MultiPolygon':
        visible = max(visible.geoms, key=lambda p: p.area)
    result[0] = visible.buffer(2).intersection(result[0]).buffer(0)
    assert all(p.geom_type == 'Polygon' and p.is_valid for p in result)
    assert result[0].intersection(result[1]).area > 10, 'Faces must overlap at the fold.'
    return result


def unit(v):
    return v / max(np.linalg.norm(v), 1e-12)


def fit_curve(p, left, right, tolerance=0.20):
    """Fit cubic Beziers directly to the generated vector boundary, in canvas units."""
    if len(p) == 2:
        d = np.linalg.norm(p[1] - p[0]) / 3
        return [[p[0], p[0] + left * d, p[1] + right * d, p[1]]]
    u = np.r_[0, np.cumsum(np.linalg.norm(np.diff(p, axis=0), axis=1))]
    u /= u[-1]
    b0, b1, b2, b3 = (1-u)**3, 3*u*(1-u)**2, 3*u*u*(1-u), u**3
    a = np.stack([b1[:, None] * left, b2[:, None] * right], axis=2).reshape(-1, 2)
    rhs = (p - (b0+b1)[:, None]*p[0] - (b2+b3)[:, None]*p[-1]).reshape(-1)
    alpha = np.linalg.lstsq(a, rhs, rcond=None)[0]
    dist = np.linalg.norm(p[-1] - p[0])
    if min(alpha) < dist * 1e-5:
        alpha[:] = dist / 3
    c = [p[0], p[0]+left*alpha[0], p[-1]+right*alpha[1], p[-1]]
    fitted = b0[:, None]*c[0]+b1[:, None]*c[1]+b2[:, None]*c[2]+b3[:, None]*c[3]
    err = np.linalg.norm(fitted-p, axis=1)
    k = int(np.argmax(err))
    if err[k] <= tolerance:
        return [c]
    k = max(1, min(len(p)-2, k))
    tangent = unit(p[k-1] - p[k+1])
    return fit_curve(p[:k+1], left, tangent, tolerance) + fit_curve(p[k:], -tangent, right, tolerance)


def path_for(poly):
    p = np.array(poly.exterior.coords[:-1])
    # Start at a stable extremum and divide the closed boundary into four runs.
    start = int(np.argmin(p[:, 1] + p[:, 0]*0.00001))
    p = np.concatenate([p[start:], p[:start], p[start:start+1]])
    p = np.array(Polygon(p).simplify(0.025, preserve_topology=True).exterior.coords)
    cumulative = np.r_[0, np.cumsum(np.linalg.norm(np.diff(p, axis=0), axis=1))]
    cuts = [0] + [int(np.searchsorted(cumulative, cumulative[-1] * f)) for f in (0.25, 0.5, 0.75)] + [len(p)-1]
    curves = []
    for a, b in zip(cuts[:-1], cuts[1:]):
        run = p[a:b+1]
        curves.extend(fit_curve(run, unit(run[1]-run[0]), unit(run[-2]-run[-1])))
    fmt = lambda pt: f'{pt[0]:.3f},{pt[1]:.3f}'
    d = 'M' + fmt(curves[0][0]) + ''.join(' C' + ' '.join(fmt(v) for v in c[1:]) for c in curves) + ' Z'
    return d, len(curves)


def svg(body, title):
    return f'''<?xml version="1.0" encoding="UTF-8"?>
<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">
  <title>{title}</title>
  {body}
</svg>
'''


def srgb(hexcolor):
    rgb = [int(hexcolor.lstrip('#')[i:i+2], 16)/255 for i in (0, 2, 4)]
    return 'srgb:' + ','.join(f'{x:.5f}' for x in rgb) + ',1.00000'


def gradient(top, bottom, start=(0.5, 0), stop=(0.5, 1)):
    return {'linear-gradient': [srgb(top), srgb(bottom)], 'orientation': {'start': dict(zip(('x', 'y'), start)), 'stop': dict(zip(('x', 'y'), stop))}}


def main():
    for folder in ('layers', 'source', 'previews', 'Undertone.icon/Assets'):
        (ROOT/folder).mkdir(parents=True, exist_ok=True)
    faces = geometry()
    paths = [path_for(p) for p in faces]
    names = ['01-rear-cyan.svg', '02-front-coral.svg']
    colors = ['#53DFF4', '#FF8BA9']
    bodies = []
    for name, color, (d, count) in zip(names, colors, paths):
        body = f'<path fill="{color}" d="{d}"/>'
        content = svg(body, name[:-4])
        (ROOT/'layers'/name).write_text(content)
        (ROOT/'Undertone.icon/Assets'/name).write_text(content)
        bodies.append(f'<g id="{name[:-4]}">{body}</g>')
        print(name, count, 'cubic segments')
    (ROOT/'source/Undertone-master.svg').write_text(svg('\n  '.join(bodies), 'Undertone — half-twist ribbon, editable two-face master'))
    silhouette, _ = path_for(faces[0].union(faces[1]))
    (ROOT/'source/Undertone-silhouette.svg').write_text(svg(f'<path fill="#FFFFFF" d="{silhouette}"/>', 'Undertone — continuous monochrome silhouette'))
    doc = {
        'fill': gradient('#111B92', '#5413C8', (0.15, 0), (0.85, 1)),
        'groups': [{
            'name': 'Continuous half-twist ribbon',
            'blur-material': 0.12,
            'layers': [
                # Icon Composer stores the frontmost layer first.
                {'name': '02 · Coral front face', 'image-name': names[1], 'glass': True, 'fill': gradient('#FFE5A3', '#FF4E9A'), 'opacity': 1},
                {'name': '01 · Cyan rear face', 'image-name': names[0], 'glass': True, 'fill': gradient('#8AF2FF', '#3979EC'), 'opacity': 1},
            ],
            'shadow': {'kind': 'neutral', 'opacity': 0.30},
            'translucency': {'enabled': True, 'value': 0.22},
        }],
        'supported-platforms': {'circles': ['watchOS'], 'squares': 'shared'},
    }
    (ROOT/'Undertone.icon/icon.json').write_text(json.dumps(doc, indent=2)+'\n')
    checks = {
        'canvas': [1024, 1024], 'physical_width': WIDTH, 'bend_centerline_radius': RADIUS,
        'twist_degrees': -180, 'terminal_corner_radius': CAP_RADIUS,
        'projection': {'x_from_z': DEPTH_X, 'tilt_radians': TILT},
        'twist_span_radians': TWIST_SPAN, 'twist_center_offset_radians': TWIST_OFFSET,
        'bounds': list(faces[0].union(faces[1]).bounds),
        'face_overlap_area': faces[0].intersection(faces[1]).area,
        'bezier_fit_tolerance': 0.20,
        'max_cross_section_width_error': max(abs(np.linalg.norm(surface(s, WIDTH/2)-surface(s, -WIDTH/2))-WIDTH) for s in np.linspace(-ARM, math.pi*RADIUS+ARM, 1001)),
        'faces_valid': all(p.is_valid for p in faces),
        'connected_silhouette': faces[0].union(faces[1]).geom_type == 'Polygon',
        'cubic_segments': dict(zip(names, [n for d, n in paths])),
    }
    (ROOT/'source/geometry.json').write_text(json.dumps(checks, indent=2)+'\n')
    print(json.dumps(checks, indent=2))


if __name__ == '__main__':
    main()
