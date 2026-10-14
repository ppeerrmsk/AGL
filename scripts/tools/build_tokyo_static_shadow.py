"""R59地图坐标下的平顶体块投影遮罩；不改楼体、来源高度或正式资源。"""
import argparse
import hashlib
import json
import math
from pathlib import Path
from PIL import Image, ImageDraw
from shapely import affinity, unary_union
from shapely.geometry import Polygon, box

SOURCE_HASH = 'ccdb340925d2646d98eaa873055951d46e095198dec20b057774354a5633a170'
BOUNDS = [-6000, -3300, -5200, -2500]
# 对应原生零旋转机位的光源/地面基；原生Visual另独立核对。
DIRECTION = [math.sin(math.radians(35)) / math.tan(math.radians(50)),
             -math.cos(math.radians(35)) * math.cos(math.radians(38)) / math.tan(math.radians(50))]


def sweep(shape, bottom, top, direction=DIRECTION):
    if not shape.is_valid or shape.is_empty or not 0 <= bottom <= top or top <= 0:
        raise ValueError('invalid source shadow prism')
    parts = [affinity.translate(shape, xoff=direction[0]*h, yoff=direction[1]*h) for h in (bottom, top)]
    for ring in [shape.exterior, *shape.interiors]:
        points = list(ring.coords)
        for a, b in zip(points, points[1:]):
            p = [(a[0]+direction[0]*bottom, a[1]+direction[1]*bottom),
                 (b[0]+direction[0]*bottom, b[1]+direction[1]*bottom),
                 (b[0]+direction[0]*top, b[1]+direction[1]*top),
                 (a[0]+direction[0]*top, a[1]+direction[1]*top)]
            face = Polygon(p)
            if face.area > 0:
                parts.append(face)
    return unary_union(parts)


def polygons(shape):
    return [shape] if shape.geom_type == 'Polygon' else [p for p in shape.geoms if p.geom_type == 'Polygon']


def raster(shape, bounds, size):
    # 2x覆盖采样后缩回R8；每级从矢量重建，不放大低清遮罩。
    image = Image.new('L', (size*2, size*2), 0)
    draw = ImageDraw.Draw(image)
    def points(ring):
        return [((x-bounds[0])/(bounds[2]-bounds[0])*size*2-.5,
                 (y-bounds[1])/(bounds[3]-bounds[1])*size*2-.5) for x, y in ring.coords]
    # 并集分量内可有孔洞中的独立岛；父壳先画，否则后画的内院会擦掉岛影。
    for p in sorted(polygons(shape), key=lambda component: Polygon(component.exterior).area, reverse=True):
        draw.polygon(points(p.exterior), fill=255)
        for hole in p.interiors:
            draw.polygon(points(hole), fill=0)
    return image.resize((size, size), Image.Resampling.BOX)


def validate_bounds(bounds):
    if len(bounds) != 4 or not all(math.isfinite(x) for x in bounds) or bounds[0] >= bounds[2] or bounds[1] >= bounds[3]:
        raise ValueError('invalid shadow bounds')
    return max(bounds[2]-bounds[0], bounds[3]-bounds[1])


def build(source, output, bounds=BOUNDS):
    span = validate_bounds(bounds)
    if output.exists():
        raise ValueError('output already exists')
    data = source.read_bytes()
    if hashlib.sha256(data).hexdigest() != SOURCE_HASH:
        raise ValueError('unexpected city source')
    city = json.loads(data)
    area = box(*bounds)
    pieces, sources = [], []
    for raw in city['buildings']:
        if raw.get('defer_render') or not raw.get('render_outline', True) or raw.get('regional_draw_owner') != 'north_coast':
            continue
        top = float(raw['height_m']) * .5
        bottom = max(0., float(raw.get('min_height_m', 0)) * .5)
        for ring in raw.get('rings', []):
            shape = Polygon(ring['outer'], ring.get('holes', []))
            # 完整包括片区外投进来的高楼，不只按楼中心选取。
            distance = max(abs(DIRECTION[0]), abs(DIRECTION[1])) * top
            if not box(*(shape.bounds[i] + (-distance if i < 2 else distance) for i in range(4))).intersects(area):
                continue
            projected = sweep(shape, bottom, top)
            if projected.intersects(area):
                pieces.append(projected.intersection(area))
                sources.append({'id': str(raw['id']), 'height_m': raw['height_m'], 'min_height_m': raw.get('min_height_m', 0)})
    merged = unary_union(pieces)
    if merged.is_empty or not merged.is_valid:
        raise ValueError('invalid merged shadow')
    output.mkdir(parents=True)
    rows = []
    for size in [1024, 2048, 4096]:
        path = output / f'mask_{size}.png'
        raster(merged, bounds, size).save(path)
        rows.append({'size': size, 'file': path.name, 'sha256': hashlib.sha256(path.read_bytes()).hexdigest(),
                     'max_scale': size/span, 'base_bytes': size*size})
    metadata = {'schema': 1, 'preview_only': True, 'source_sha256': SOURCE_HASH,
                'bounds': bounds, 'direction': DIRECTION, 'rows': rows, 'sources': sources,
                'source_count': len(set(s['id'] for s in sources)), 'shadow_area': merged.area,
                'flat_prism_proxy': True, 'source_heights_unchanged': True}
    (output/'manifest.json').write_text(json.dumps(metadata, indent=2), encoding='utf-8')
    print(json.dumps({k:v for k,v in metadata.items() if k != 'sources'}))


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('source', type=Path)
    parser.add_argument('output', type=Path)
    parser.add_argument('--bounds', type=float, nargs=4, default=BOUNDS)
    args = parser.parse_args()
    build(args.source, args.output, args.bounds)
