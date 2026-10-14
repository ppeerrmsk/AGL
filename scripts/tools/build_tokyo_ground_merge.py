"""R55 同高度同色地表精确合并；float32拓扑不等则保留原分量。"""
import argparse
import hashlib
import json
import struct
from collections import defaultdict
from fractions import Fraction
from pathlib import Path
from shapely import STRtree, constrained_delaunay_triangles, unary_union
from shapely.geometry import Polygon


def f32(value):
    return struct.unpack('<f', struct.pack('<f', value))[0]


def parts(shape):
    if shape.geom_type == 'Polygon':
        return [shape]
    if shape.geom_type in ('MultiPolygon', 'GeometryCollection'):
        return [p for child in shape.geoms for p in parts(child)]
    return []


def exact_area(shape):
    def ring_area(ring):
        points = [(Fraction(x), Fraction(y)) for x, y in ring.coords]
        return abs(sum(x * points[i+1][1] - points[i+1][0] * y for i, (x,y) in enumerate(points[:-1]))) / 2
    return sum(ring_area(p.exterior) - sum(ring_area(h) for h in p.interiors) for p in parts(shape))


def merge_component(originals, tolerance=0., diagnostics=None, preserve_boundary=False):
    def reject(reason):
        if diagnostics is not None:
            diagnostics[reason] = diagnostics.get(reason, 0) + 1
        return None
    region = unary_union(originals)
    if not region.is_valid or region.is_empty:
        return reject('invalid_region')
    polygons = []
    triangles = []
    for part in parts(region):
        # 零容差只移除严格共线的边界顶点；保留孔洞。
        outline = part if preserve_boundary else part.simplify(tolerance, preserve_topology=True)
        if tolerance > 0:
            outline = outline.intersection(part)
        for triangle in constrained_delaunay_triangles(outline).geoms:
            points = [(f32(x), f32(y)) for x, y in list(triangle.exterior.coords)[:-1]]
            polygon = Polygon(points)
            if not polygon.is_valid or polygon.area <= 0:
                return reject('float32_degenerate')
            polygons.append(polygon)
            triangles.append(points)
    if len(triangles) >= len(originals):
        return reject('not_fewer_faces')
    if preserve_boundary:
        boundary = {xy for p in parts(region) for ring in [p.exterior, *p.interiors] for xy in ring.coords}
        if not boundary.issubset({xy for triangle in triangles for xy in triangle}):
            return reject('boundary_vertex_drift')
    rebuilt = unary_union(polygons)
    # 不用epsilon把失真说成无损；同时拒绝新三角相互重叠。
    if abs(sum(p.area for p in polygons) - rebuilt.area) > max(1e-10, rebuilt.area * 1e-12):
        return reject('triangles_overlap')
    if tolerance == 0:
        if not region.equals(rebuilt):
            return reject('float32_topology_drift')
        if exact_area(region) != exact_area(rebuilt):
            return reject('exact_area_drift')
    elif (not region.covers(rebuilt) or rebuilt.area < .98 * region.area
            or len(parts(region)) != len(parts(rebuilt))
            or sum(len(p.interiors) for p in parts(region)) != sum(len(p.interiors) for p in parts(rebuilt))
            or not region.boundary.covered_by(rebuilt.boundary.buffer(tolerance, quad_segs=32))
            or not rebuilt.boundary.covered_by(region.boundary.buffer(tolerance, quad_segs=32))):
        return reject('inward_or_error_contract')
    return triangles


def plan_records(raw, tolerance=0., preserve_boundary=False):
    if len(raw) % 60:
        raise ValueError('partial native triangle record')
    groups = defaultdict(list)
    for start in range(0, len(raw), 60):
        record = struct.unpack_from('<I14f', raw, start)
        identity, *values = record
        height, nx, ny, nz, r, g, b, a, *coords = values
        points = list(zip(coords[::2], coords[1::2]))
        signed = sum(points[i][0] * points[(i+1) % 3][1] - points[(i+1) % 3][0] * points[i][1] for i in range(3))
        polygon = Polygon(points)
        if a != 1 or signed <= 0 or not polygon.is_valid or polygon.area <= 0:
            continue
        groups[raw[start+4:start+36]].append((identity, polygon))
    removed = set()
    triangles = []
    accepted = []
    rejected = 0
    diagnostics = {}
    for attributes, records in sorted(groups.items()):
        shapes = [r[1] for r in records]
        tree = STRtree(shapes)
        # 与并集连通分量精确关联，不能按包围盒把不相交岛屿的面删掉。
        for component in parts(unary_union(shapes)):
            ids = [int(i) for i in tree.query(component) if component.covers(shapes[int(i)])]
            if len(ids) < 3:
                continue
            candidate = merge_component([shapes[i] for i in ids], tolerance, diagnostics, preserve_boundary)
            if tolerance > 0:
                exact = merge_component([shapes[i] for i in ids], 0., diagnostics)
                if exact is not None and (candidate is None or len(exact) < len(candidate)):
                    candidate = exact
            if candidate is None:
                rejected += 1
                continue
            sources = sorted(records[i][0] for i in ids)
            if not removed.isdisjoint(sources):
                raise ValueError('one native face claimed by two components')
            removed.update(sources)
            height, nx, ny, nz, r, g, b, a = struct.unpack('<8f', attributes)
            for points in candidate:
                triangles.append(dict(source_triangle=sources[0], points=points, height=height,
                    normal=[nx, ny, nz], color=[r, g, b, a]))
            accepted.append(dict(source_triangle=sources[0], sources=sources, before=len(ids), after=len(candidate)))
    return dict(removed=sorted(removed), triangles=triangles, components=accepted, rejected_components=rejected, diagnostics=diagnostics)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('source', type=Path)
    parser.add_argument('output', type=Path)
    parser.add_argument('--max-scale', type=float, choices=[0., .1944, .3888], default=0.)
    parser.add_argument('--preserve-boundary', action='store_true')
    args = parser.parse_args()
    if args.preserve_boundary and args.max_scale:
        parser.error('boundary preservation is an exact-only control')
    args.output.mkdir(exist_ok=False)
    manifest = json.loads((args.source / 'manifest.json').read_bytes())
    rows = []
    for cell in manifest['cells']:
        raw = (args.source / cell['file']).read_bytes()
        if hashlib.sha256(raw).hexdigest() != cell['buffer_sha256']:
            raise ValueError('native source buffer drift')
        plan = plan_records(raw, .2 / args.max_scale if args.max_scale else 0., args.preserve_boundary)
        plan['preserve_boundary'] = args.preserve_boundary
        plan['max_scale'] = args.max_scale
        plan.update(source=cell['path'], source_sha256=cell['sha256'], cell_id=cell['id'], before=cell['triangles'])
        plan['after'] = plan['before'] - len(plan['removed']) + len(plan['triangles'])
        destination = args.output / ('cell_%02d.json' % cell['id'])
        destination.write_text(json.dumps(plan, separators=(',', ':'), allow_nan=False), encoding='utf-8')
        row = dict(cell_id=cell['id'], before=plan['before'], after=plan['after'], components=len(plan['components']),
            rejected_components=plan['rejected_components'], file=destination.name, sha256=hashlib.sha256(destination.read_bytes()).hexdigest())
        rows.append(row)
        print(json.dumps(row), flush=True)
    (args.output / 'manifest.json').write_text(json.dumps(dict(cells=rows, source_index_sha256=manifest['index_sha256'],
        before=sum(r['before'] for r in rows), after=sum(r['after'] for r in rows), max_scale=args.max_scale,
        preserve_boundary=args.preserve_boundary, production_enabled=False)), encoding='utf-8')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
