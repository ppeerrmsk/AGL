"""街坊级低楼概括：保留结构锚点，用独立契约而非扩大旧无损门。"""
import argparse
import hashlib
import json
import math
from collections import defaultdict
from pathlib import Path
from shapely import STRtree, unary_union, constrained_delaunay_triangles
from shapely.geometry import Polygon, box, LineString
from shapely.ops import nearest_points
from build_tokyo_shell_lod import plain_shell
from build_tokyo_footprint_lod import f32

PROFILES = {
    'street_solid': dict(grid=128, max_group=256, max_span=240, min_vertices=4, max_vertices=8, closure_steps=4, occupied_error_px=80., area_error=2.0, roads='structural', grouping='road_components', link_gap=12.),
    'district24street': dict(grid=96, max_group=64, max_span=120, min_vertices=4, max_vertices=8, closure_steps=4, occupied_error_px=24., area_error=.80, roads='structural', grouping='road_components', link_gap=12.),
    'street6': dict(grid=128, max_group=96, max_span=160, min_vertices=4, max_vertices=8, closure_steps=4, occupied_error_px=6., area_error=1.0, roads='structural', grouping='road_components', link_gap=12.),
    'street8': dict(grid=128, max_group=96, max_span=160, min_vertices=4, max_vertices=8, closure_steps=4, occupied_error_px=8., area_error=1.0, roads='structural', grouping='road_components', link_gap=12.),
    'far8wide': dict(grid=128, max_group=96, max_span=160, min_vertices=4, max_vertices=8, closure_steps=4, occupied_error_px=8., area_error=1.0, roads='structural'),
    'far12wide': dict(grid=128, max_group=96, max_span=160, min_vertices=4, max_vertices=8, closure_steps=4, occupied_error_px=12., area_error=1.0, roads='structural'),
    'mid4': dict(grid=64, max_group=48, max_span=80, max_vertices=8, occupied_error_px=4., area_error=.80, roads='structural'),
    'mid6': dict(grid=64, max_group=48, max_span=80, max_vertices=8, occupied_error_px=6., area_error=.80, roads='structural'),
    'far4': dict(grid=96, max_group=64, max_span=120, max_vertices=8, occupied_error_px=4., area_error=1.0, roads='structural'),
    'far6': dict(grid=96, max_group=64, max_span=120, max_vertices=8, occupied_error_px=6., area_error=1.0, roads='structural'),
    'gentle': dict(grid=48, max_group=16, max_span=60, max_vertices=12, occupied_error_px=2., area_error=.35, roads='all'),
    'blocks': dict(grid=64, max_group=32, max_span=80, max_vertices=8, occupied_error_px=3., area_error=.60, roads='structural'),
    'district6': dict(grid=64, max_group=48, max_span=80, max_vertices=8, occupied_error_px=6., area_error=.80, roads='structural'),
    'district8': dict(grid=64, max_group=48, max_span=80, max_vertices=8, occupied_error_px=8., area_error=.80, roads='structural'),
    'district12': dict(grid=64, max_group=48, max_span=80, max_vertices=8, occupied_error_px=12., area_error=.80, roads='structural'),
    'district16': dict(grid=64, max_group=48, max_span=80, max_vertices=8, occupied_error_px=16., area_error=.80, roads='structural'),
    'district20': dict(grid=64, max_group=48, max_span=80, min_vertices=4, max_vertices=8, occupied_error_px=20., area_error=.80, roads='structural'),
    'district24': dict(grid=64, max_group=48, max_span=80, min_vertices=4, max_vertices=8, occupied_error_px=24., area_error=.80, roads='structural'),
    'district20wide': dict(grid=96, max_group=64, max_span=120, min_vertices=4, max_vertices=8, closure_steps=4, occupied_error_px=20., area_error=.80, roads='structural'),
    'district24wide': dict(grid=96, max_group=64, max_span=120, min_vertices=4, max_vertices=8, closure_steps=4, occupied_error_px=24., area_error=.80, roads='structural'),
}
MINOR = {'service', 'path', 'footway', 'steps'}
PROFILES['district24street45'] = dict(PROFILES['district24street'], shape_policy=dict(min_angle_degrees=45, max_aspect=4, min_edge_px=.5))


def contract(profile):
    if profile not in PROFILES:
        raise ValueError('unknown block profile')
    return dict(schema=2, strategy='street_blocks', profile=profile, **PROFILES[profile])


def protected_road(record, profile):
    return PROFILES[profile]['roads'] == 'all' or record.get('class') not in MINOR or float(record.get('width_px', 1)) >= 1.5


def polygon(points):
    return Polygon([(f32(x), f32(y)) for x, y in points])


def barriers(city, ground, area, profile):
    result = []
    roads = [r for r in city.get('roads', []) if protected_road(r, profile)]
    roads += [r for r in city.get('rails', []) if r.get('class') != 'subway']
    for raw in roads:
        strokes = raw.get('joined_strokes', {})
        if strokes:
            for stroke in strokes.values():
                points = stroke.get('triangles', [])
                if len(points) % 3:
                    raise ValueError('incomplete prepared road triangle')
                for i in range(0, len(points), 3):
                    p = polygon(points[i:i+3])
                    if p.intersects(area):
                        result.append(p)
        elif len(raw.get('points', [])) >= 2:
            p = LineString(raw['points']).buffer(max(.1, float(raw.get('width_px', 1)))/2+.475)
            if p.intersects(area):
                result.append(p)
    for raw in ground['surfaces']:
        if raw['kind'] not in ('water', 'green', 'park'):
            continue
        points = raw['triangles']
        if len(points) % 3:
            raise ValueError('incomplete surface triangle')
        for i in range(0, len(points), 3):
            p = polygon(points[i:i+3])
            if p.intersects(area):
                result.append(p)
    if any(not p.is_valid or p.is_empty for p in result):
        raise ValueError('invalid structural barrier')
    return result


def shape_acceptable(shape, policy):
    """只约束合并结果；原来源形状不进入这个美术筛选。"""
    if policy is None:
        return True
    points=list(shape.exterior.coords)[:-1]
    for i,p in enumerate(points):
        a,b=points[i-1],points[(i+1)%len(points)]
        u,v=(a[0]-p[0],a[1]-p[1]),(b[0]-p[0],b[1]-p[1])
        lu,lv=math.hypot(*u),math.hypot(*v)
        if min(lu,lv)<policy['min_edge_px']:
            return False
        angle=math.degrees(math.acos(max(-1.,min(1.,(u[0]*v[0]+u[1]*v[1])/(lu*lv)))))
        if angle+1e-6<policy['min_angle_degrees']:
            return False
    corners=list(shape.minimum_rotated_rectangle.exterior.coords)
    edges=[math.dist(a,b) for a,b in zip(corners,corners[1:])]
    return min(edges)>0 and max(edges)/min(edges)<=policy['max_aspect']+1e-6


def choose(polygons, obstacles, costs, scale, profile, area, shape_policy=None):
    c = contract(profile)
    limit = c['occupied_error_px']/scale
    original = unary_union(polygons)
    shapes = [original.convex_hull, original.minimum_rotated_rectangle]
    for step in range(1,c.get('closure_steps',1)+1):
        radius=limit*step/c.get('closure_steps',1)
        closed = original.buffer(radius, join_style=2).buffer(-radius, join_style=2)
        if closed.geom_type == 'Polygon':
            shapes += [closed.simplify(radius*.5, preserve_topology=True), closed.simplify(radius, preserve_topology=True)]
    accepted = []
    for shape in shapes:
        if shape.geom_type != 'Polygon' or shape.interiors:
            continue
        shape = polygon(list(shape.exterior.coords)[:-1])
        if not shape.is_valid or shape.is_empty or not area.covers(shape):
            continue
        if not shape_acceptable(shape,shape_policy):
            continue
        x0, y0, x1, y1 = shape.bounds
        if max(x1-x0, y1-y0) > c['max_span'] or not c.get('min_vertices',3) <= len(shape.exterior.coords)-1 <= c['max_vertices']:
            continue
        if abs(shape.area/original.area-1) > c['area_error']:
            continue
        if not original.covered_by(shape.buffer(limit)) or not shape.covered_by(original.buffer(limit)):
            continue
        addition = shape.difference(original)
        if any(addition.intersects(p) for p in obstacles):
            continue
        triangles = list(constrained_delaunay_triangles(shape).geoms)
        faces = len(triangles) + (2*(len(shape.exterior.coords)-1) if min(c['detail'] for c in costs) < 2 else 0)
        saved = sum(c['faces'] for c in costs)-faces
        if saved > 0:
            accepted.append((shape, saved, addition.area, triangles))
    return min(accepted, key=lambda r: (-r[1], r[2], r[0].wkt)) if accepted else None


def road_components(eligible, blocked, barrier_tree, gap):
    """按无结构障碍的近邻连通；最终合并仍须通过choose的完整占地审查。"""
    ids = sorted(eligible)
    shapes = [eligible[i][1] for i in ids]
    tree = STRtree(shapes)
    parents = list(range(len(ids)))

    def root(i):
        while parents[i] != i:
            parents[i] = parents[parents[i]]
            i = parents[i]
        return i

    for i, identity in enumerate(ids):
        raw, shape, cost = eligible[identity]
        for j in sorted(int(n) for n in tree.query(shape.buffer(gap))):
            if j <= i:
                continue
            other, polygon_value, other_cost = eligible[ids[j]]
            if cost['parent'] != other_cost['parent'] or raw['height_m'] != other['height_m'] or raw.get('kind', 'urban') != other.get('kind', 'urban'):
                continue
            if shape.distance(polygon_value) > gap:
                continue
            a, b = nearest_points(shape, polygon_value)
            bridge = a if a.equals(b) else LineString([a, b])
            if any(bridge.intersects(blocked[int(n)]) for n in barrier_tree.query(bridge)):
                continue
            left, right = root(i), root(j)
            parents[max(left, right)] = min(left, right)
    groups = defaultdict(list)
    for i, identity in enumerate(ids):
        groups[root(i)].append(identity)
    return list(groups.values())


def prepare(city, ground, costs, scale, profile, bounds, region='north_coast', shape_policy=None):
    if profile == 'street_solid' and scale != 5.0:
        raise ValueError('solid street profile requires finest output scale')
    if shape_policy is not None:
        if set(shape_policy)!={'min_angle_degrees','max_aspect','min_edge_px'} \
                or any(isinstance(v,bool) or not isinstance(v,(int,float)) or not math.isfinite(v) for v in shape_policy.values()) \
                or not 0<shape_policy['min_angle_degrees']<=90 or shape_policy['max_aspect']<1 or shape_policy['min_edge_px']<=0:
            raise ValueError('invalid independent shape policy')
        if region is not None:
            raise ValueError('shape policy requires independent source review')
    if region is None and any('regional_draw_owner' in r for r in city['buildings']):
        raise ValueError('standalone plan cannot reinterpret joined ownership')
    c = contract(profile)
    if profile in ('mid4', 'mid6') and scale != 1.5552:
        raise ValueError('middle district profiles require LOD4 output scale')
    if profile in ('district6', 'district8', 'district12', 'district16', 'district20', 'district24', 'district20wide', 'district24wide', 'district24street', 'district24street45') and scale != 5.0:
        raise ValueError('district profiles require finest output scale')
    if profile in ('far4', 'far6', 'far8wide', 'far12wide', 'street6', 'street8') and scale not in (.1944, .3888):
        raise ValueError('far district profiles require LOD1 or LOD2 output scale')
    allowed_scales = (1.5552,) if profile in ('mid4', 'mid6') else (.1944, .3888, .7776, 5.0)
    if not math.isfinite(scale) or not any(math.isclose(scale, allowed, rel_tol=0, abs_tol=1e-9) for allowed in allowed_scales):
        raise ValueError('invalid block output scale')
    if len(bounds) != 4 or not all(math.isfinite(x) for x in bounds) or bounds[0]>=bounds[2] or bounds[1]>=bounds[3]:
        raise ValueError('invalid production window')
    # 明确命名的北岸候选只筛合并输出，不放宽手工policy的独立来源门。
    shape_policy = c.get('shape_policy', shape_policy)
    area = box(*bounds)
    if not box(*ground['bounds']).covers(area):
        raise ValueError('outside original ground')
    shapes, identities, eligible = [], [], {}
    for raw in city['buildings']:
        if raw.get('defer_render') or not raw.get('render_outline', True):
            continue
        for ring in raw.get('rings', []):
            p = Polygon([(f32(x), f32(y)) for x, y in ring['outer']], ring.get('holes', []))
            if p.is_valid and not p.is_empty and p.intersects(area):
                shapes.append(p)
                identities.append(str(raw['id']))
        if (region is None or raw.get('regional_draw_owner') == region) and plain_shell(raw) and 0 < raw['height_m'] <= 24 and str(raw['id']) in costs:
            p = polygon(raw['rings'][0]['outer'])
            if p.is_valid and p.area > 0 and area.covers(p):
                cost = costs[str(raw['id'])]
                if cost['faces'] <= 0 or cost['detail'] not in (0, 1, 2):
                    raise ValueError('invalid native costs')
                eligible[str(raw['id'])] = (raw, p, cost)
    other_tree = STRtree(shapes)
    blocked = barriers(city, ground, area, profile)
    barrier_tree = STRtree(blocked)
    bins = defaultdict(list)
    for identity in sorted(eligible):
        raw, shape, cost = eligible[identity]
        center = shape.centroid
        key = (cost['parent'], raw['height_m'], raw.get('kind', 'urban'), math.floor(center.x/c['grid']), math.floor(center.y/c['grid']))
        bins[key].append(identity)
    groups = []
    placed = defaultdict(list)

    def buckets(shape):
        x0,y0,x1,y1=shape.bounds
        return [(x,y) for x in range(math.floor(x0/c['grid']),math.floor(x1/c['grid'])+1)
                for y in range(math.floor(y0/c['grid']),math.floor(y1/c['grid'])+1)]

    def split(ids):
        if len(ids) < 2:
            return
        polygons = [eligible[i][1] for i in ids]
        envelope = unary_union(polygons).envelope
        if len(ids) <= c['max_group']:
            ids_set = set(ids)
            query = envelope.buffer(c['occupied_error_px']/scale)
            obstacles = [blocked[int(i)] for i in barrier_tree.query(query)]
            obstacles += [shapes[int(i)] for i in other_tree.query(query) if identities[int(i)] not in ids_set]
            obstacles += [p for key in buckets(query) for p in placed[key]]
            found = choose(polygons, obstacles, [eligible[i][2] for i in ids], scale, profile, area, shape_policy)
            if found:
                shape, saved, added, triangles = found
                raw = eligible[ids[0]][0]
                groups.append(dict(ids=ids, height_m=raw['height_m'], kind=raw.get('kind', 'urban'), faces_saved=saved,
                    added_area=added, outer=[list(p) for p in list(shape.exterior.coords)[:-1]],
                    triangles=[list(p) for t in triangles for p in list(t.exterior.coords)[:3]]))
                for key in buckets(shape):
                    placed[key].append(shape)
                return
        # 不填掉受保护走廊；失败组按空间中位切分，最终不合格单体维持原形。
        x0, y0, x1, y1 = envelope.bounds
        axis = 0 if x1-x0 >= y1-y0 else 1
        ids = sorted(ids, key=lambda i: (eligible[i][1].centroid.coords[0][axis], i))
        middle = len(ids)//2
        split(ids[:middle])
        split(ids[middle:])

    initial_groups = road_components(eligible, blocked, barrier_tree, c['link_gap']) if c.get('grouping') == 'road_components' else bins.values()
    for ids in initial_groups:
        split(ids)
    groups.sort(key=lambda g: g['ids'])
    result = dict(c, preview_only=True, bounds=bounds, max_scale=scale, eligible=len(eligible), groups=groups,
        cost_model='native_lod', merged_sources=sum(len(g['ids']) for g in groups), faces_saved=sum(g['faces_saved'] for g in groups),
        prepared_barrier_rejected=[], structural_barriers=len(blocked))
    if shape_policy is not None:
        result['shape_policy']=dict(shape_policy)
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--profile', choices=PROFILES, required=True)
    parser.add_argument('--level', type=int, choices=[1, 2, 3, 4, 5], required=True)
    parser.add_argument('--costs', type=Path, help='显式原生逐档成本文件，默认保持R58远档文件')
    args = parser.parse_args()
    if args.output.exists():
        parser.error('output already exists')
    source = (args.root/'r30-area-source-b/north_coast/city.json').read_bytes()
    ground = (args.root/'r24-owned-source-b/north_coast/ground.json').read_bytes()
    costs = (args.costs or args.root/'r58-far-costs-a.json').read_bytes()
    data = json.loads(costs)
    if data['source_sha256'] != hashlib.sha256(source).hexdigest():
        parser.error('native costs source mismatch')
    if str(args.level) not in data['levels']:
        parser.error('requested LOD absent from native costs; export actual level first')
    level = data['levels'][str(args.level)]
    if not math.isclose(level['max_scale'], {1:.1944, 2:.3888, 3:.7776, 4:1.5552, 5:5.0}[args.level], rel_tol=0, abs_tol=1e-9):
        parser.error('native level scale mismatch')
    plan = prepare(json.loads(source), json.loads(ground), level['records'], level['max_scale'], args.profile, [-6300,-3700,-2300,-1700])
    plan.update(source_sha256=hashlib.sha256(source).hexdigest(), ground_sha256=hashlib.sha256(ground).hexdigest(), native_costs_sha256=hashlib.sha256(costs).hexdigest())
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(plan, separators=(',', ':')), encoding='utf8')
    print(json.dumps({k:len(v) if k=='groups' else v for k,v in plan.items()}))


if __name__ == '__main__':
    main()
