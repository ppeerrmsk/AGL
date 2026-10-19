"""离线远景轮廓；验证原生float32边界双向覆盖，不把简化参数冒充误差。"""
import argparse
import json
import math
import shutil
import struct
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT/'tmp/tokyo-r3-pydeps'))
from shapely import constrained_delaunay_triangles
from shapely.geometry import Polygon

MAX_SCALES = [.09*1.08, .18*1.08, .36*1.08, .72*1.08]
PIXEL_ERROR = .35
AREA_ERROR = .05


def f32(value):
    return struct.unpack('f', struct.pack('f',value))[0]


def within_error(original, candidate, limit):
    # round buffer的内接多边形是欧氏距离带的保守子集；双向整条边界覆盖，非只采样顶点。
    if not math.isfinite(limit) or limit <= 0 or not original.is_valid or original.is_empty \
            or not candidate.is_valid or candidate.is_empty \
            or candidate.geom_type != 'Polygon' or len(candidate.interiors) != len(original.interiors):
        return False
    return original.boundary.covered_by(candidate.boundary.buffer(limit, quad_segs=16)) \
        and candidate.boundary.covered_by(original.boundary.buffer(limit, quad_segs=16))


def simplify_ring(ring, max_scale):
    if not math.isfinite(max_scale) or max_scale <= 0:
        raise ValueError('invalid output scale')
    original = Polygon(ring['outer'],ring.get('holes',[]))
    if not original.is_valid or original.is_empty or original.area <= 0 or original.interiors:
        return None
    native_original = Polygon([(f32(x), f32(y)) for x, y in list(original.exterior.coords)[:-1]])
    if not native_original.is_valid or native_original.is_empty or native_original.area <= 0:
        return None
    limit = PIXEL_ERROR/max_scale
    original_faces = len(ring['triangles'])//3
    for fraction in [1., .5, .25]:
        simplified = original.simplify(limit*fraction,preserve_topology=True)
        if simplified.geom_type != 'Polygon' or simplified.is_empty:
            continue
        candidate = Polygon([(f32(x),f32(y)) for x,y in list(simplified.exterior.coords)[:-1]])
        if abs(candidate.area/original.area-1) > AREA_ERROR \
                or abs(candidate.area/native_original.area-1) > AREA_ERROR \
                or not within_error(original,candidate,limit) \
                or not within_error(native_original,candidate,limit):
            continue
        faces = list(constrained_delaunay_triangles(candidate).geoms)
        if len(faces) >= original_faces:
            continue
        return {'outer': [[x,y] for x,y in list(candidate.exterior.coords)[:-1]], 'holes': [],
                'triangles': [[x,y] for face in faces for x,y in list(face.exterior.coords)[:3]]}
    return None


def eligible(raw):
    tags = raw.get('source_tags', {})
    if tags.get('building') == 'roof' or tags.get('building:part') == 'roof':
        return False
    return raw.get('height_source') == 'fallback' and raw.get('height_m',0) < 80 \
        and raw.get('render_outline',True) and not raw.get('defer_render') \
        and raw.get('roof_shape','flat') == 'flat' and not raw.get('roof_volume') \
        and not raw.get('parents') and not raw.get('parts') and not raw.get('is_part') \
        and len(raw.get('rings',[])) == 1 and not raw['rings'][0].get('holes')


def prepare(city):
    stats = [{'max_scale':scale,'pixel_error':PIXEL_ERROR,'changed':0,'roof_faces_saved':0} for scale in MAX_SCALES]
    for raw in city['buildings']:
        if 'footprint_lod' in raw:
            raise ValueError('prepared footprint input cannot be overwritten')
        if not eligible(raw):
            continue
        finer = None
        for slot in reversed(range(len(MAX_SCALES))):
            scale = MAX_SCALES[slot]
            ring = simplify_ring(raw['rings'][0],scale)
            # 高一档的已验证轮廓也满足本档更宽的误差带；避免拒绝大幅简化后反而比近档更重。
            if finer is not None and (ring is None or len(finer['triangles']) < len(ring['triangles'])):
                ring = finer
            if ring is not None:
                raw.setdefault('footprint_lod',{})[str(slot)] = {'max_scale':scale,'rings':[ring]}
                stats[slot]['changed'] += 1
                stats[slot]['roof_faces_saved'] += (len(raw['rings'][0]['triangles'])-len(ring['triangles']))//3
                finer = ring
    return stats


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source',type=Path,required=True)
    parser.add_argument('--output',type=Path,required=True)
    args = parser.parse_args()
    if args.output.exists():
        parser.error('output already exists')
    city = json.loads((args.source/'city.json').read_text(encoding='utf-8'))
    stats = prepare(city)
    args.output.mkdir(parents=True,exist_ok=False)
    (args.output/'city.json').write_text(json.dumps(city,ensure_ascii=False,separators=(',',':')),encoding='utf-8')
    shutil.copyfile(args.source/'ground.json',args.output/'ground.json')
    (args.output/'footprint_audit.json').write_text(json.dumps(stats,indent=2),encoding='utf-8')
    print(json.dumps(stats))


if __name__ == '__main__':
    main()
