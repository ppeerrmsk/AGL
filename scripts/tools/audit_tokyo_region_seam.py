"""只读审计相邻来源区域的海陆共边与跨界楼体；不自动删除来源或填补海面。"""
import argparse
import json
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tmp/tokyo-r3-pydeps'))
from shapely.geometry import LineString, Polygon
from shapely.ops import unary_union


def coast_land(ground):
    faces = [surface for surface in ground['surfaces'] if surface['id'] == 'source-coastal-land']
    if len(faces) != 1:
        raise ValueError('expected exactly one source coastal land surface')
    points = faces[0]['triangles']
    if len(points) % 3:
        raise ValueError('incomplete coastal triangle')
    return unary_union([Polygon(points[i:i+3]) for i in range(0, len(points), 3)])


def ring_key(points):
    values = tuple(tuple(point) for point in points)
    if not values:
        return ()
    return min(sequence[start:]+sequence[:start] for sequence in (values, values[::-1]) for start in range(len(values)))


def shape_key(building):
    return sorted((ring_key(ring['outer']), sorted(ring_key(hole) for hole in ring.get('holes', [])))
                  for ring in building.get('rings', []))


def audit(first_city, first_ground, second_city, second_ground):
    a, b = first_ground['bounds'], second_ground['bounds']
    if a[1] == b[3] or b[1] == a[3]:
        boundary = a[1] if a[1] == b[3] else b[1]
        points = [(max(a[0], b[0]), boundary), (min(a[2], b[2]), boundary)]
    elif a[0] == b[2] or b[0] == a[2]:
        boundary = a[0] if a[0] == b[2] else b[0]
        points = [(boundary, max(a[1], b[1])), (boundary, min(a[3], b[3]))]
    else:
        raise ValueError('regions do not share an exact boundary')
    if points[0][0] > points[1][0] or points[0][1] > points[1][1] or points[0] == points[1]:
        raise ValueError('regions have no positive shared edge')
    seam = LineString(points)
    first_land = coast_land(first_ground).intersection(seam)
    second_land = coast_land(second_ground).intersection(seam)
    mismatch = first_land.symmetric_difference(second_land)
    # 仅容许已有源坐标小数三位量化产生的共边交点误差；不做模糊缓冲来掩盖缺口。
    coast_ok = mismatch.length <= 0.01
    first = {building['id']: building for building in first_city['buildings']}
    second = {building['id']: building for building in second_city['buildings']}
    shared = sorted(first.keys() & second.keys())
    height_conflicts, shape_conflicts, duplicate_draws = [], [], []
    for identity in shared:
        x, y = first[identity], second[identity]
        if any(x.get(field) != y.get(field) for field in ('height_m', 'height_source', 'min_height_m')):
            height_conflicts.append(identity)
        if shape_key(x) != shape_key(y):
            shape_conflicts.append(identity)
        if all(item.get('render_outline', True) and not item.get('defer_render', False) for item in (x, y)):
            duplicate_draws.append(identity)
    return {'source_seam_ok': coast_ok and not height_conflicts and not shape_conflicts,
            'shared_edge': points, 'shared_length_px': seam.length, 'land_lengths_px': [first_land.length, second_land.length],
            'coast_mismatch_length_px': mismatch.length, 'coast_mismatch_wkt': mismatch.wkt,
            'shared_building_ids': shared, 'height_conflicts': height_conflicts, 'shape_conflicts': shape_conflicts,
            'requires_unique_draw_owner': duplicate_draws,
            'simultaneous_render_ready': coast_ok and not height_conflicts and not shape_conflicts and not duplicate_draws}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--first', type=Path, required=True)
    parser.add_argument('--second', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    read = lambda folder, name: json.loads((folder / (name+'.json')).read_text(encoding='utf-8'))
    result = audit(read(args.first, 'city'), read(args.first, 'ground'), read(args.second, 'city'), read(args.second, 'ground'))
    args.output.parent.mkdir(parents=True, exist_ok=True)
    with args.output.open('x', encoding='utf-8') as handle:
        json.dump(result, handle, ensure_ascii=False, indent=2)
    print(json.dumps({key: value if not isinstance(value, list) else len(value) for key, value in result.items()}, ensure_ascii=True))
    return 0 if result['source_seam_ok'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
