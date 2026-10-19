"""北城低层体块概括候选：同高合并、保留来源、道路/标高轮廓隔离，不覆盖原数据。"""
import argparse
import hashlib
import json
import math
from pathlib import Path
from build_tokyo_shell_lod import plain_shell
from build_tokyo_footprint_lod import f32
from shapely.geometry import Polygon, LineString, box
from shapely import STRtree, unary_union, constrained_delaunay_triangles

MAX_SCALE = 1.44 * 1.08
LIMIT = 1.0 / MAX_SCALE
MAX_GROUP = 4
DEFAULT_BOUNDS = [-6300, -3500, -4900, -2200]

def mesh_faces(poly):
    return 3 * (len(poly.exterior.coords) - 1) - 2

def candidate(polygons, blockers, max_scale=MAX_SCALE, native_costs=None, strategy='legacy'):
    if not math.isfinite(max_scale) or max_scale <= 0:
        raise ValueError('invalid cluster output scale')
    if strategy not in ('legacy', 'min_cost') or (strategy == 'min_cost' and native_costs is None):
        raise ValueError('invalid cluster strategy or missing native costs')
    limit = 1.0 / max_scale
    original = unary_union(polygons)
    if not original.is_valid or original.is_empty:
        return None
    # 小于一输出像素的缝隙可概括；不连接大庭院或跨道路。
    radius = limit
    merged = original.buffer(radius, join_style=2).buffer(-radius, join_style=2)
    shapes = []
    if merged.geom_type == 'Polygon' and not merged.interiors:
        shapes.append(merged.simplify(limit * .5, preserve_topology=True))
        if strategy == 'min_cost':
            shapes.append(merged.simplify(limit, preserve_topology=True))
    if strategy == 'min_cost':
        shapes.extend([original.convex_hull, original.minimum_rotated_rectangle])
    accepted = [_evaluate(original, shape, polygons, blockers, limit, native_costs) for shape in shapes]
    accepted = [result for result in accepted if result is not None]
    return min(accepted, key=lambda result: (-result[1], result[0].symmetric_difference(original).area)) if accepted else None


def _evaluate(original, merged, polygons, blockers, limit, native_costs):
    # 各种构造都重过相同的原生精度/障碍/成本门；几何构造本身不是误差证据。
    if merged.geom_type != 'Polygon' or merged.interiors:
        return None
    merged = Polygon([(f32(x), f32(y)) for x, y in list(merged.exterior.coords)[:-1]])
    if not merged.is_valid or merged.is_empty or merged.interiors:
        return None
    if not original.covered_by(merged.buffer(limit, quad_segs=16)) or not merged.covered_by(original.buffer(limit, quad_segs=16)):
        return None
    if abs(merged.area / original.area - 1) > .12:
        return None
    addition = merged.difference(original)
    if not addition.is_empty and any(addition.intersects(p) for p in blockers):
        return None
    if native_costs is None:
        saved = sum(mesh_faces(p) for p in polygons) - mesh_faces(merged)
    else:
        if len(native_costs) != len(polygons) or any(c['faces'] <= 0 or c['detail'] not in (0, 1, 2) for c in native_costs):
            raise ValueError('invalid native cluster costs')
        new_faces = len(constrained_delaunay_triangles(merged).geoms)
        if min(c['detail'] for c in native_costs) < 2:
            new_faces += 2 * (len(merged.exterior.coords) - 1)
        saved = sum(c['faces'] for c in native_costs) - new_faces
    if saved < (4 if native_costs is None else 1):
        return None
    return merged, saved, addition.area

def prepare(city, bounds, water_polygons=(), max_scale=MAX_SCALE, max_group=MAX_GROUP, native_costs=None, strategy='legacy'):
    if not math.isfinite(max_scale) or max_scale <= 0 or max_group not in [4, 8]:
        raise ValueError('invalid cluster scale or group limit')
    if len(bounds) != 4 or not all(math.isfinite(v) for v in bounds) or bounds[0] >= bounds[2] or bounds[1] >= bounds[3]:
        raise ValueError('invalid cluster production bounds')
    limit = 1.0 / max_scale
    area = box(*bounds)
    eligible = []
    blocked = [p for p in water_polygons if p.is_valid and not p.is_empty and p.intersects(area)]
    for raw in city['buildings']:
        if raw.get('defer_render') or not raw.get('render_outline', True):
            continue
        if raw.get('regional_draw_owner') != 'north_coast':
            continue
        rings = raw.get('rings', [])
        polygons = [Polygon(r['outer'], r.get('holes', [])) for r in rings]
        if not polygons or not any(p.intersects(area) for p in polygons):
            continue
        if plain_shell(raw) and 0 < raw['height_m'] <= 24 and area.covers(polygons[0]) and (native_costs is None or str(raw['id']) in native_costs):
            p = Polygon([(f32(x), f32(y)) for x, y in rings[0]['outer']])
            if p.is_valid and p.area > 0:
                eligible.append((raw, p))
        else:
            blocked.extend(polygons)
    for road in city.get('roads', []):
        if len(road.get('points', [])) >= 2:
            major = road.get('class') in {'motorway', 'motorway_link', 'trunk', 'trunk_link', 'primary', 'primary_link', 'secondary', 'secondary_link'}
            # 与实际工厂的道路外描边同宽，再保留小间隙；只避开中心线会侵入路沿。
            width = max(.1, float(road.get('width_px', 1))) + (.65 if major else 0)
            p = LineString(road['points']).buffer(width / 2 + .15)
            if p.intersects(area):
                blocked.append(p)
    for rail in city.get('rails', []):
        if rail.get('class') != 'subway' and len(rail.get('points', [])) >= 2:
            p = LineString(rail['points']).buffer(.8)
            if p.intersects(area):
                blocked.append(p)
    eligible.sort(key=lambda item: str(item[0]['id']))
    tree = STRtree([item[1] for item in eligible])
    barrier_tree = STRtree(blocked)
    used = set()
    groups = []
    for seed, (raw, shape) in enumerate(eligible):
        if seed in used:
            continue
        nearby = [int(i) for i in tree.query(shape.buffer(2 * limit)) if i != seed and i not in used]
        nearby.sort(key=lambda i: (shape.distance(eligible[i][1]), str(eligible[i][0]['id'])))
        members = [seed]
        chosen = None
        for n in nearby:
            record, p = eligible[n]
            if record['height_m'] != raw['height_m'] or record.get('kind') != raw.get('kind'):
                continue
            if native_costs is not None and native_costs[str(record['id'])]['parent'] != native_costs[str(raw['id'])]['parent']:
                continue
            proposed = [eligible[i][1] for i in members] + [p]
            envelope = unary_union(proposed).envelope
            if max(envelope.bounds[2] - envelope.bounds[0], envelope.bounds[3] - envelope.bounds[1]) > 40:
                continue
            obstacles = [blocked[int(i)] for i in barrier_tree.query(envelope)]
            proposed_ids = set(members + [n])
            obstacles.extend(eligible[int(i)][1] for i in tree.query(envelope) if int(i) not in proposed_ids)
            costs = None if native_costs is None else [native_costs[str(eligible[i][0]['id'])] for i in members + [n]]
            found = candidate(proposed, obstacles, max_scale, costs, strategy)
            if found is not None and not area.covers(found[0]):
                continue
            if native_costs is not None and chosen is not None and found is not None and found[1] <= chosen[1]:
                continue
            if found is not None:
                members.append(n)
                chosen = found
                if len(members) == max_group:
                    break
        if chosen is None:
            continue
        merged, saved, added = chosen
        used.update(members)
        triangles = list(constrained_delaunay_triangles(merged).geoms)
        groups.append({'ids': [eligible[i][0]['id'] for i in members], 'height_m': raw['height_m'],
            'kind': raw.get('kind', 'urban'), 'faces_saved': saved, 'added_area': added,
            'outer': [list(p) for p in list(merged.exterior.coords)[:-1]],
            'triangles': [list(p) for t in triangles for p in list(t.exterior.coords)[:3]]})
    return {'schema': 1, 'preview_only': True, 'strategy': strategy, 'bounds': bounds, 'max_scale': max_scale,
        'occupied_error_px': 1.0, 'max_group': max_group, 'eligible': len(eligible),
        'cost_model': 'native_lod' if native_costs is not None else 'full_shell_estimate',
        'merged_sources': len(used), 'groups': groups, 'faces_saved': sum(g['faces_saved'] for g in groups)}

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', type=Path, required=True)
    parser.add_argument('--ground', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--max-scale', type=float, choices=[MAX_SCALE, .1944, .3888], default=MAX_SCALE)
    parser.add_argument('--max-group', type=int, choices=[4, 8], default=MAX_GROUP)
    parser.add_argument('--costs', type=Path)
    parser.add_argument('--level', type=int, choices=[1, 2])
    parser.add_argument('--strategy', choices=['legacy', 'min_cost'], default='legacy')
    parser.add_argument('--bounds', type=float, nargs=4, default=DEFAULT_BOUNDS, metavar=('X0','Y0','X1','Y1'))
    args = parser.parse_args()
    if args.output.exists():
        parser.error('output already exists')
    source = args.source.read_bytes()
    ground_bytes = args.ground.read_bytes()
    ground = json.loads(ground_bytes)
    if not all(math.isfinite(v) for v in args.bounds) or args.bounds[0] >= args.bounds[2] or args.bounds[1] >= args.bounds[3] or not box(*ground['bounds']).covers(box(*args.bounds)):
        parser.error('production bounds must be finite, nonempty and inside source ground')
    waters = []
    for surface in ground['surfaces']:
        if surface['kind'] == 'water':
            points = surface['triangles']
            if len(points) % 3:
                raise ValueError('invalid source water triangles')
            waters.extend(Polygon(points[i:i+3]) for i in range(0, len(points), 3))
    costs = None
    if args.costs:
        data = json.loads(args.costs.read_bytes())
        if args.level is None or data['source_sha256'] != hashlib.sha256(source).hexdigest() or not math.isclose(data['levels'][str(args.level)]['max_scale'], args.max_scale):
            parser.error('native cost source or level mismatch')
        costs = data['levels'][str(args.level)]['records']
    result = prepare(json.loads(source), args.bounds, waters, args.max_scale, args.max_group, costs, args.strategy)
    if args.costs:
        result['native_costs_sha256'] = hashlib.sha256(args.costs.read_bytes()).hexdigest()
    result['source_sha256'] = hashlib.sha256(source).hexdigest()
    result['ground_sha256'] = hashlib.sha256(ground_bytes).hexdigest()
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, separators=(',', ':')), encoding='utf8')
    print(json.dumps({k: (len(v) if k == 'groups' else v) for k, v in result.items()}))

if __name__ == '__main__':
    main()
