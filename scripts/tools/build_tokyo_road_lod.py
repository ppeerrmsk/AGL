"""远景道路中心线准备：原宽度/锁定节点，实际描边/结构门，不改原JSON或运行时。"""
import argparse
from collections import Counter
import hashlib
import json
import math
from pathlib import Path
import struct
from shapely import STRtree, constrained_delaunay_triangles, make_valid, unary_union
from shapely.geometry import LineString, Polygon
from build_tokyo_strokes import MAJOR

MAX_SCALE = .3888
PROFILES = {'road15': .15, 'road25': .25}


def f32(value):
    return struct.unpack('<f', struct.pack('<f', value))[0]


def locked_points(records):
    counts = Counter(tuple(p) for row in records for p in row['points'])
    result = {p for p, count in counts.items() if count > 1}
    for row in records:
        if row['points']:
            result.update([tuple(row['points'][0]), tuple(row['points'][-1])])
    return result


def simplify_locked(points, locked, tolerance):
    if not math.isfinite(tolerance) or tolerance <= 0:
        raise ValueError('invalid tolerance')
    pts = [tuple(p) for p in points]
    if len(pts) < 2 or any(len(p) != 2 or not all(math.isfinite(v) for v in p) for p in pts):
        raise ValueError('invalid source line')
    stops = [0] + [i for i in range(1, len(pts)-1) if pts[i] in locked] + [len(pts)-1]
    result = []
    for start, end in zip(stops, stops[1:]):
        chunk = list(LineString(pts[start:end+1]).simplify(tolerance, preserve_topology=True).coords)
        result.extend(chunk if not result else chunk[1:])
    if len(set(result)) < (3 if pts[0] == pts[-1] else 2):
        return pts
    return result


def stroke(points, width, joined):
    if not math.isfinite(width) or width <= 0:
        raise ValueError('invalid width')
    if joined:
        shape = LineString(points).buffer(width/2, cap_style=2, join_style=2, mitre_limit=2).simplify(0)
        triangles = [list(p.exterior.coords)[:3] for p in constrained_delaunay_triangles(shape).geoms]
    else:
        triangles = []
        for p, q in zip(points, points[1:]):
            dx, dy = q[0]-p[0], q[1]-p[1]
            length = math.hypot(dx, dy)
            if not length:
                continue
            sx, sy = -dy*width/(2*length), dx*width/(2*length)
            a, b, c, d = [(p[0]+sx,p[1]+sy),(q[0]+sx,q[1]+sy),(q[0]-sx,q[1]-sy),(p[0]-sx,p[1]-sy)]
            triangles.extend([[a,b,c],[a,c,d]])
    faces = [[[f32(x), f32(y)] for x,y in triangle] for triangle in triangles]
    polygons = [Polygon(p) for p in faces]
    if not polygons or any(not p.is_valid or p.area <= 0 for p in polygons):
        raise ValueError('degenerate Float32 stroke')
    return unary_union(polygons), faces


def topology(shape):
    if shape.geom_type == 'Polygon':
        return (1, len(shape.interiors))
    if shape.geom_type == 'MultiPolygon':
        return (len(shape.geoms), sum(len(p.interiors) for p in shape.geoms))
    return (-1, -1)


def accept_shape(original, candidate, limit):
    if not original.is_valid or not candidate.is_valid or original.area <= 0 or candidate.area <= 0:
        return False
    if topology(original) != topology(candidate):
        return False
    if original.symmetric_difference(candidate).area / original.area > .03:
        return False
    return original.covered_by(candidate.buffer(limit)) and candidate.covered_by(original.buffer(limit))


def prepare(city, ground, profile):
    if profile not in PROFILES:
        raise ValueError('unknown road LOD profile')
    records = [('roads', r) for r in city.get('roads', [])] + [('rails', r) for r in city.get('rails', []) if r.get('class') != 'subway'] + [('paths', r) for r in ground.get('paths', [])]
    records.sort(key=lambda item: (item[0], str(item[1]['id'])))
    keys = [(kind, str(row['id'])) for kind, row in records]
    if len(set(keys)) != len(keys):
        raise ValueError('duplicate source identity')
    locks = locked_points([r for _,r in records])
    lines = [LineString(row['points']) for _,row in records]
    line_tree = STRtree(lines)
    footprints = []
    before_faces = []
    for kind, row in records:
        width = .8 if kind == 'paths' else (1.35 if kind == 'rails' else float(row['width_px']))
        roles = row.get('joined_strokes', {}) if kind != 'paths' else {}
        if roles:
            polygons = []
            for data in roles.values():
                p = data['triangles']
                if len(p) % 3:
                    raise ValueError('incomplete prepared stroke')
                polygons.extend(Polygon([(f32(x),f32(y)) for x,y in p[i:i+3]]) for i in range(0,len(p),3))
            footprints.append(unary_union(polygons))
            before_faces.append(sum(len(d['triangles'])//3 for d in roles.values()))
        else:
            shape, faces = stroke(row['points'], width, False)
            footprints.append(shape)
            before_faces.append(len(faces))
    obstacles = list(footprints)
    for row in city.get('buildings', []):
        # 建筑外环作保守障碍，庭院也不因道路概括被新占用。
        for ring in row.get('rings', []):
            p = make_valid(Polygon(ring['outer']))
            if not p.is_empty:
                obstacles.append(p)
    for row in ground.get('surfaces', []):
        if row['kind'] not in ['water','green','park']:
            continue
        points = row['triangles']
        if len(points) % 3:
            raise ValueError('incomplete protected surface')
        obstacles.extend(make_valid(Polygon(points[i:i+3])) for i in range(0,len(points),3))
    if any(not p.is_valid for p in obstacles):
        raise ValueError('invalid source obstacle')
    obstacle_tree = STRtree(obstacles)
    accepted = []
    rejected = Counter()
    limit = PROFILES[profile]/MAX_SCALE
    for index, (kind, row) in enumerate(records):
        if kind == 'rails' or (kind == 'roads' and row.get('class') in MAJOR):
            continue
        original_points = [tuple(p) for p in row['points']]
        old_shape = footprints[index]
        width = .8 if kind == 'paths' else float(row['width_px'])
        joined = kind != 'paths' and bool(row.get('joined_strokes'))
        if joined and set(row['joined_strokes']) != {'surface'}:
            rejected['unsupported_roles'] += 1
            continue
        best = None
        for fraction in [1., .5, .25]:
            points = simplify_locked(original_points, locks, limit*fraction)
            if len(points) >= len(original_points):
                continue
            line = LineString(points)
            if any(line.crosses(lines[int(other)]) and not lines[index].crosses(lines[int(other)]) for other in line_tree.query(line) if int(other) != index):
                rejected['new_crossing'] += 1
                continue
            try:
                shape, faces = stroke(points, width, joined)
            except ValueError:
                rejected['stroke'] += 1
                continue
            if len(faces) >= before_faces[index] or not accept_shape(old_shape, shape, limit):
                rejected['cost_or_shape'] += 1
                continue
            added = shape.difference(old_shape)
            if not added.is_empty and any(added.intersects(obstacles[int(other)]) for other in obstacle_tree.query(added) if int(other) != index):
                rejected['protected_addition'] += 1
                continue
            choice = dict(kind=kind,id=str(row['id']),points=[list(p) for p in points],width=width,joined=joined,
                source_index=index,
                before_faces=before_faces[index],after_faces=len(faces),triangles=faces,
                original_points_sha256=hashlib.sha256(json.dumps(row['points'],separators=(',',':')).encode()).hexdigest(),
                area_error=old_shape.symmetric_difference(shape).area/old_shape.area)
            if best is None or choice['after_faces'] < best['after_faces']:
                best = choice
        if best is not None:
            accepted.append(best)
    # 两条候选都移入同一原空隙时，单独对原障碍通过也不充分；最终两两独立保护。
    shapes = [unary_union([Polygon(p) for p in row['triangles']]) for row in accepted]
    candidate_tree = STRtree(shapes)
    removed = set()
    for i, shape in enumerate(shapes):
        for raw_j in candidate_tree.query(shape, predicate='intersects'):
            j = int(raw_j)
            if j <= i or i in removed or j in removed:
                continue
            previous = footprints[accepted[i]['source_index']].intersection(footprints[accepted[j]['source_index']])
            if not shape.intersection(shapes[j]).difference(previous).is_empty:
                removed.add(j)
                rejected['candidate_overlap'] += 1
    accepted = [row for i,row in enumerate(accepted) if i not in removed]
    return dict(schema=1,profile=profile,max_scale=MAX_SCALE,error_px=PROFILES[profile],area_error_limit=.03,
        rows=accepted,rejected=dict(rejected),source_records=len(records),locked_nodes=len(locks),
        accepted_sources=len(accepted),source_faces_saved=sum(r['before_faces']-r['after_faces'] for r in accepted),
        native_faces_verified=False,production_enabled=False)


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source',type=Path)
    parser.add_argument('output',type=Path)
    parser.add_argument('--profile',choices=PROFILES,required=True)
    args=parser.parse_args()
    if args.output.exists():
        raise ValueError('do not overwrite evidence')
    city_bytes=(args.source/'city.json').read_bytes()
    ground_bytes=(args.source/'ground.json').read_bytes()
    result=prepare(json.loads(city_bytes),json.loads(ground_bytes),args.profile)
    result.update(city_sha256=hashlib.sha256(city_bytes).hexdigest(),ground_sha256=hashlib.sha256(ground_bytes).hexdigest(),source=str(args.source.resolve()))
    args.output.write_text(json.dumps(result,separators=(',',':'),allow_nan=False),encoding='utf8')
    print(json.dumps({k:v for k,v in result.items() if k!='rows'}),flush=True)


if __name__=='__main__':
    main()
