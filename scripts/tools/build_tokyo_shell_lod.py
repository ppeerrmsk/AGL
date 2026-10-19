"""中近景低楼轮廓实验：保持来源字段，派生轮廓仅供独立原生对拍。"""
import argparse
import copy
import hashlib
import json
import math
from pathlib import Path
from build_tokyo_footprint_lod import eligible, f32, within_error, PIXEL_ERROR, AREA_ERROR
from shapely.geometry import Polygon
from shapely import constrained_delaunay_triangles

SCALES = {'middle': 1.44 * 1.08, 'near': 5.0}


def plain_shell(raw):
    return eligible(raw) and not any(raw['rings'][0].get(key) for key in ['inset_triangles', 'panel_triangles'])


def simplify_shell(ring, scale):
    if not math.isfinite(scale) or scale <= 0:
        raise ValueError('invalid output scale')
    source = Polygon(ring['outer'], ring.get('holes', []))
    native = Polygon([(f32(x), f32(y)) for x, y in ring['outer']])
    if any(not p.is_valid or p.is_empty or p.area <= 0 or p.interiors for p in [source, native]):
        return None
    candidate = native.simplify(PIXEL_ERROR / scale, preserve_topology=True)
    candidate = Polygon([(f32(x), f32(y)) for x, y in list(candidate.exterior.coords)[:-1]])
    # 中近景不试亚像素三角楼，也不平移/缩放整栋来补面积。
    if len(candidate.exterior.coords) < 5 or len(candidate.exterior.coords) >= len(native.exterior.coords):
        return None
    if any(not within_error(p, candidate, PIXEL_ERROR / scale)
           or abs(candidate.area / p.area - 1) > AREA_ERROR for p in [source, native]):
        return None
    faces = list(constrained_delaunay_triangles(candidate).geoms)
    result = copy.deepcopy(ring)
    result['outer'] = [list(p) for p in list(candidate.exterior.coords)[:-1]]
    result['triangles'] = [list(p) for face in faces for p in list(face.exterior.coords)[:3]]
    return result


def prepare(city):
    result = copy.deepcopy(city)
    for raw in result['buildings']:
        if 'shell_lod' in raw:
            raise ValueError('derived shell source cannot be overwritten')
        if raw.get('regional_draw_owner') != 'yokohama' or not plain_shell(raw):
            continue
        for name, scale in SCALES.items():
            ring = simplify_shell(raw['rings'][0], scale)
            if ring:
                raw.setdefault('shell_lod', {})[name] = {'max_scale': scale, 'rings': [ring]}
    return result


def audit(original, prepared):
    restored = copy.deepcopy(prepared)
    stats = {name: dict(changed=0, shell_roof_faces_saved=0, max_error_px=0., max_area_error=0.) for name in SCALES}
    for raw in restored['buildings']:
        entries = raw.pop('shell_lod', {})
        if not entries:
            continue
        assert raw.get('regional_draw_owner') == 'yokohama' and plain_shell(raw)
        ring = raw['rings'][0]
        source = Polygon(ring['outer'])
        native = Polygon([(f32(x), f32(y)) for x, y in ring['outer']])
        for name, entry in entries.items():
            assert name in SCALES and entry['max_scale'] == SCALES[name] and len(entry['rings']) == 1
            candidate_ring = entry['rings'][0]
            restored_ring = copy.deepcopy(candidate_ring)
            restored_ring['outer'], restored_ring['triangles'] = ring['outer'], ring['triangles']
            assert restored_ring == ring, 'all non-outline roof fields stay exact'
            candidate = Polygon(candidate_ring['outer'], candidate_ring['holes'])
            assert 4 <= len(candidate_ring['outer']) < len(ring['outer'])
            assert all(f32(v) == v for p in candidate_ring['outer'] + candidate_ring['triangles'] for v in p)
            for reference in [source, native]:
                assert within_error(reference, candidate, PIXEL_ERROR / entry['max_scale'])
                area_error = abs(candidate.area / reference.area - 1)
                assert area_error <= AREA_ERROR
                stats[name]['max_error_px'] = max(stats[name]['max_error_px'], reference.boundary.hausdorff_distance(candidate.boundary) * entry['max_scale'])
                stats[name]['max_area_error'] = max(stats[name]['max_area_error'], area_error)
            faces = [Polygon(candidate_ring['triangles'][i:i+3]) for i in range(0, len(candidate_ring['triangles']), 3)]
            assert faces and all(f.area > 0 and candidate.covers(f) for f in faces)
            assert math.isclose(sum(f.area for f in faces), candidate.area, rel_tol=1e-9)
            savings = 2 * (len(ring['outer']) - len(candidate_ring['outer'])) + (len(ring['triangles']) - len(candidate_ring['triangles'])) // 3
            assert savings > 0
            stats[name]['changed'] += 1
            stats[name]['shell_roof_faces_saved'] += savings
    assert original == restored, 'identity, source geometry, heights, tags and earlier LOD remain exact'
    return stats


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    if args.output.exists():
        parser.error('output exists')
    source = args.source.read_bytes()
    original = json.loads(source)
    prepared = prepare(original)
    stats = audit(original, prepared)
    payload = json.dumps(prepared, ensure_ascii=False, separators=(',', ':')).encode('utf-8')
    report = {'source_sha256': hashlib.sha256(source).hexdigest(), 'prepared_sha256': hashlib.sha256(payload).hexdigest(),
              'scales': SCALES, 'pixel_error': PIXEL_ERROR, 'area_error': AREA_ERROR, 'stats': stats, 'preview_only': True}
    args.output.mkdir(parents=True, exist_ok=False)
    (args.output/'city.json').write_bytes(payload)
    (args.output/'audit.json').write_text(json.dumps(report, indent=2), encoding='utf-8')
    print(json.dumps(report, indent=2))


if __name__ == '__main__':
    main()
