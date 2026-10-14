"""R116离线共拓扑岸线计划；不接运行时，不覆写来源或既有候选。"""
import argparse
import hashlib
import json
import math
from pathlib import Path

from shapely import constrained_delaunay_triangles, unary_union
from shapely.geometry import Polygon
from build_tokyo_shoreline import collect, f32

WIDTHS = (2.0, 1.0, .35)


def polygons(shape):
    if shape.is_empty:
        return []
    if shape.geom_type == 'Polygon':
        return [shape]
    return [p for child in shape.geoms for p in polygons(child)]


def stroke(lines, window, width):
    return lines.buffer(width/2, cap_style=2, join_style=2, mitre_limit=2).intersection(window)


def rings(shape):
    return [list(r.coords)[:-1] for r in [shape.exterior, *shape.interiors]]


def scoped_shape(shape, component):
    # 宽度缩小后的完整分量已包含在宽档内；再intersection会给共线端帽添顶点。
    selected = [p for p in polygons(shape) if component.covers(p.representative_point())]
    if any(not component.buffer(1e-7).covers(p) for p in selected):
        raise ValueError('non_nested_source')
    return unary_union(selected)


def ring_match(wide, narrow):
    """同顶点数循环对齐；不靠最近点重采样伪造对应。"""
    if len(wide) != len(narrow):
        raise ValueError('vertex_count_changed')
    options = []
    for candidate in (narrow, narrow[::-1]):
        # 小线宽下首点最近的候选先定位；随后全部点和几何门验证。
        start = min(range(len(candidate)), key=lambda i: math.dist(wide[0], candidate[i]))
        aligned = candidate[start:] + candidate[:start]
        options.append((sum(math.dist(a, b)**2 for a, b in zip(wide, aligned)), aligned))
    return min(options, key=lambda x: x[0])[1]


def signed_area(a, b, c):
    return (b[0]-a[0])*(c[1]-a[1])-(b[1]-a[1])*(c[0]-a[0])


def positions(wide, narrow, t, native=True):
    cast = f32 if native else float
    return [[cast(a[k]+(b[k]-a[k])*t) for k in range(2)] for a, b in zip(wide, narrow)]


def orientation_safe(wide, narrow, triangles):
    """线性顶点轨迹的面积是二次式；检查端点与区间内驻点。"""
    middle = positions(wide, narrow, .5, False)
    for ids in triangles:
        a, m, z = [signed_area(*(p[i] for i in ids)) for p in (wide, middle, narrow)]
        sign = 1 if a > 0 else -1
        q = 2*(z+a-2*m)
        linear = z-a-q
        samples = [a, z]
        if abs(q) > 1e-15:
            t = -linear/(2*q)
            if 0 < t < 1:
                samples.append(q*t*t+linear*t+a)
        if min(sign*x for x in samples) <= 1e-12:
            return False
    return True


def coverage(points, triangles, target):
    faces = [Polygon([points[i] for i in ids]) for ids in triangles]
    if any(not p.is_valid or p.area <= 0 for p in faces):
        raise ValueError('native_degenerate')
    shape = unary_union(faces)
    if abs(sum(p.area for p in faces)-shape.area) > max(1e-7, shape.area*1e-9):
        raise ValueError('native_overlap')
    error = shape.symmetric_difference(target).area/target.area
    if error > .002 or not shape.covered_by(target.buffer(.005)) or not target.covered_by(shape.buffer(.005)):
        raise ValueError('native_coverage')
    return error


def fixed_mesh(shape):
    points = [[f32(x), f32(y)] for tri in constrained_delaunay_triangles(shape).geoms
              for x, y in list(tri.exterior.coords)[:3]]
    indices = [list(range(i, i+3)) for i in range(0, len(points), 3)]
    coverage(points, indices, shape)
    return dict(points=points, indices=indices, faces=len(indices))


def candidate(wide_shape, narrow_shape, target_at):
    if wide_shape.geom_type != 'Polygon' or narrow_shape.geom_type != 'Polygon':
        raise ValueError('component_split')
    outer, inner = rings(wide_shape), rings(narrow_shape)
    if len(outer) != len(inner):
        raise ValueError('hole_count_changed')
    remaining = inner[1:]
    pairs = [(outer[0], inner[0])]
    for ring in outer[1:]:
        if not remaining:
            raise ValueError('missing_hole')
        index = min(range(len(remaining)), key=lambda i: Polygon(ring).hausdorff_distance(Polygon(remaining[i])))
        pairs.append((ring, remaining.pop(index)))
    wide, narrow = [], []
    for a, b in pairs:
        aligned = ring_match(a, b)
        wide.extend(a)
        narrow.extend(aligned)
    mapping = {tuple(p): i for i, p in enumerate(wide)}
    if len(mapping) != len(wide):
        raise ValueError('duplicate_boundary_vertex')
    triangles = [[mapping[tuple(p)] for p in list(tri.exterior.coords)[:3]]
                 for tri in constrained_delaunay_triangles(wide_shape).geoms]
    # 端点先转原生精度；实际GPU顶点算术仍须后续GL核对。
    wide = [[f32(x) for x in p] for p in wide]
    narrow = [[f32(x) for x in p] for p in narrow]
    if not orientation_safe(wide, narrow, triangles):
        raise ValueError('orientation_crossing')
    worst = 0.0
    samples = sorted(set([i/32 for i in range(33)] + [(2-1)/(2-.35)]))
    for t in samples:
        worst = max(worst, coverage(positions(wide, narrow, t), triangles, target_at(2-1.65*t)))
    return dict(wide=wide, narrow=narrow, indices=triangles, faces=len(triangles),
                sample_count=len(samples), max_relative_area_error=worst,
                continuous_orientation=True, continuous_coverage_proof=False)


def build_plan(lines, window):
    shapes = [stroke(lines, window, w) for w in WIDTHS]
    groups, rejects = [], {}
    all_wide = sorted(polygons(shapes[0]), key=lambda p: p.bounds)
    baseline = [len(constrained_delaunay_triangles(s).geoms) for s in shapes]
    fallback = [0, 0, 0]
    accepted = 0
    for number, component in enumerate(all_wide):
        local = [component, scoped_shape(shapes[1], component), scoped_shape(shapes[2], component)]
        counts = [len(constrained_delaunay_triangles(s).geoms) for s in local]
        row = dict(id=number, bounds=list(component.bounds), original_faces=counts)
        try:
            result = candidate(component, local[2], lambda width: scoped_shape(stroke(lines, window, width), component))
            row.update(mode='morph', mesh=result)
            accepted += result['faces']
        except ValueError as error:
            reason = str(error)
            rejects[reason] = rejects.get(reason, 0)+1
            row.update(mode='fallback', reason=reason, meshes=[fixed_mesh(s) for s in local])
            fallback = [a+b for a, b in zip(fallback, counts)]
        groups.append(row)
    if [sum(g['original_faces'][i] for g in groups) for i in range(3)] != baseline:
        raise ValueError('component_partition_cost_changed')
    return dict(schema=1, widths=WIDTHS, height=.03, rgb=[70,82,83], groups=groups,
                summary=dict(groups=len(groups), accepted=sum(g['mode']=='morph' for g in groups),
                             rejections=rejects, baseline_faces=baseline, morph_faces=accepted,
                             fallback_faces=fallback,
                             predicted_steady=[accepted+x for x in fallback],
                             predicted_transition=[accepted+fallback[i]+fallback[i+1] for i in range(2)],
                             original_transition=[baseline[i]+baseline[i+1] for i in range(2)]),
                native_verified=False, visual_verified=False, runtime_enabled=False)


def load_source(path):
    original = json.loads(path.read_bytes())
    if original.get('schema') != 2 or [c['width'] for c in original['candidates']] != list(WIDTHS):
        raise ValueError('wrong_source_schema')
    sources = []
    for row in original['sources']:
        raw = Path(row['path']).read_bytes()
        if hashlib.sha256(raw).hexdigest() != row['sha256']:
            raise ValueError('source_hash_changed')
        sources.append((row['sha256'], json.loads(raw)))
    lines, window, records = collect(sources)
    if json.loads(json.dumps(records)) != original['records']:
        raise ValueError('source_records_changed')
    return original, lines, window


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    if args.output.exists():
        parser.error('refuse to overwrite candidate')
    original, lines, window = load_source(args.source)
    plan = build_plan(lines, window)
    if plan['summary']['baseline_faces'] != [c['stats']['faces'] for c in original['candidates']]:
        raise ValueError('baseline_cost_changed')
    plan.update(source=str(args.source.resolve()), source_sha=hashlib.sha256(args.source.read_bytes()).hexdigest(),
                sources=original['sources'])
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(plan, separators=(',', ':')), encoding='utf-8')
    print(json.dumps(plan['summary']))


if __name__ == '__main__':
    main()
