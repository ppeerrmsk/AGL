"""离线连续道路/轨道带；只附加准备网格，不改原中心线或建筑。"""
import argparse
import json
import math
import shutil
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tmp/tokyo-r3-pydeps'))
from shapely import constrained_delaunay_triangles
from shapely.geometry import LineString, Polygon
from shapely.ops import unary_union

MAJOR = {'motorway','motorway_link','trunk','trunk_link','primary','primary_link','secondary','secondary_link'}


def stroke(points, width):
    if not math.isfinite(width) or width <= 0 or len(points) < 2:
        raise ValueError('invalid stroke width or point count')
    clean = []
    for point in points:
        if len(point) != 2 or not all(math.isfinite(v) for v in point):
            raise ValueError('invalid stroke point')
        if not clean or point != clean[-1]:
            clean.append(point)
    if len(clean) < 2:
        raise ValueError('zero length stroke')
    shape = LineString(clean).buffer(width * .5, cap_style=2, join_style=2, mitre_limit=2).simplify(0)
    if shape.is_empty or not shape.is_valid or shape.area <= 0:
        raise ValueError('invalid stroke surface')
    faces = list(constrained_delaunay_triangles(shape).geoms)
    mesh = unary_union(faces)
    if mesh.symmetric_difference(shape).area > max(1e-7, shape.area * 1e-10):
        raise ValueError('stroke triangulation coverage mismatch')
    vertices = [[x, y] for tri in faces for x, y in list(tri.exterior.coords)[:3]]
    # 独立旧路径矩形参考，记录覆盖变化，不把接头填补误称作面积完全不变。
    old = []
    for p, q in zip(clean, clean[1:]):
        dx, dy = q[0]-p[0], q[1]-p[1]
        factor = width * .5 / math.hypot(dx, dy)
        sx, sy = -dy*factor, dx*factor
        old.append(Polygon([(p[0]+sx,p[1]+sy),(q[0]+sx,q[1]+sy),
                            (q[0]-sx,q[1]-sy),(p[0]-sx,p[1]-sy)]))
    old_union = unary_union(old)
    stats = {'old_triangles': len(old)*2, 'triangles': len(faces),
             'old_area_sum': sum(p.area for p in old), 'old_union_area': old_union.area,
             'area': shape.area, 'added_area': shape.difference(old_union).area,
             'removed_area': old_union.difference(shape).area}
    return vertices, stats


def prepare(city):
    stats = {'strokes': 0, 'roads': 0, 'rails': 0, 'subway_skipped': 0,
             'old_triangles': 0, 'triangles': 0, 'old_area_sum': 0., 'old_union_area': 0.,
             'area': 0., 'added_area': 0., 'removed_area': 0.}
    for kind in ['roads', 'rails']:
        for raw in city.get(kind, []):
            if kind == 'rails' and raw.get('class') == 'subway':
                stats['subway_skipped'] += 1
                continue
            if 'joined_strokes' in raw:
                raise ValueError('prepared stroke input cannot be overwritten')
            if kind == 'rails':
                widths = {'casing': 1.35, 'surface': .32}
            else:
                width = float(raw.get('width_px', 1.0))
                widths = {'surface': width}
                if raw.get('class') in MAJOR:
                    widths['casing'] = width + .65
            prepared = {}
            for role, width in widths.items():
                triangles, measured = stroke(raw['points'], width)
                prepared[role] = {'width': width, 'triangles': triangles}
                for key, value in measured.items():
                    stats[key] += value
                stats['strokes'] += 1
            raw['joined_strokes'] = prepared
            stats[kind] += 1
    return stats


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    if args.output.exists():
        parser.error('output already exists')
    city = json.loads((args.source/'city.json').read_text(encoding='utf-8'))
    stats = prepare(city)
    args.output.mkdir(parents=True, exist_ok=False)
    (args.output/'city.json').write_text(json.dumps(city, ensure_ascii=False, separators=(',', ':')), encoding='utf-8')
    shutil.copyfile(args.source/'ground.json', args.output/'ground.json')
    (args.output/'stroke_audit.json').write_text(json.dumps(stats, indent=2), encoding='utf-8')
    print(json.dumps(stats))


if __name__ == '__main__':
    main()
