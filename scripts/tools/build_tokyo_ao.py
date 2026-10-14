"""R64原生最高表面的局部地平线AO；制作期计算，不是屏幕空间模糊。"""
import argparse
import hashlib
import json
import math
from pathlib import Path
import numpy as np
from PIL import Image


def height_field(triangles, bounds, size):
    """像素中心重心插值，最高表面唯一接收；孔洞不作轮廓填充。"""
    lo = np.asarray(bounds[:2], dtype=np.float64)
    span = np.asarray(bounds[2:], dtype=np.float64) - lo
    if size < 2 or np.any(span <= 0) or not np.all(np.isfinite(span)):
        raise ValueError('invalid AO raster bounds')
    heights = np.full((size, size), -256, dtype=np.float32)
    for triangle in triangles:
        p = np.asarray(triangle, dtype=np.float64)
        if p.shape != (3, 3) or not np.all(np.isfinite(p)) or p[:, 1].min() < -1 or p[:, 1].max() >= 255:
            raise ValueError('invalid native AO triangle')
        q = (p[:, (0, 2)] - lo) / span * size - .5
        a, b, c = q
        determinant = (b[0]-a[0])*(c[1]-a[1])-(b[1]-a[1])*(c[0]-a[0])
        if abs(determinant) < 1e-10:
            continue
        start = np.maximum(np.ceil(q.min(axis=0)).astype(int), 0)
        end = np.minimum(np.floor(q.max(axis=0)).astype(int) + 1, size)
        if np.any(end <= start):
            continue
        x, y = np.meshgrid(np.arange(start[0], end[0]), np.arange(start[1], end[1]))
        u = ((x-a[0])*(c[1]-a[1])-(y-a[1])*(c[0]-a[0]))/determinant
        v = ((b[0]-a[0])*(y-a[1])-(b[1]-a[1])*(x-a[0]))/determinant
        inside = (u >= -1e-9) & (v >= -1e-9) & (u+v <= 1+1e-9)
        h = p[0, 1] + u*(p[1, 1]-p[0, 1]) + v*(p[2, 1]-p[0, 1])
        dest = heights[start[1]:end[1], start[0]:end[0]]
        np.maximum(dest, np.where(inside, h, -256), out=dest)
    return heights


def horizon_ao(heights, spacing, radius=8., directions=32):
    """各方位取有限距离最高遮蔽角，sin²角度为水平余弦半球遮蔽。"""
    if not math.isfinite(spacing) or spacing <= 0 or radius <= 0 or directions < 4:
        raise ValueError('invalid AO sampling')
    n = math.ceil(radius / spacing)
    padded = np.pad(heights, n+1, constant_values=-256)
    size_y, size_x = heights.shape
    result = np.zeros_like(heights)
    for angle in np.arange(directions) * 2 * np.pi / directions:
        horizon = np.zeros_like(heights)
        offsets = {(round(math.sin(angle)*i), round(math.cos(angle)*i)) for i in range(1, n+1)}
        for dy, dx in sorted(offsets):
            distance = math.hypot(dx, dy)*spacing
            if distance <= 0 or distance >= radius:
                continue
            sample = padded[n+1+dy:n+1+dy+size_y, n+1+dx:n+1+dx+size_x]
            delta = np.maximum(sample-heights-.05, 0)
            squared = delta*delta
            occlusion = squared/(squared+distance*distance)*(1-distance/radius)**2
            np.maximum(horizon, occlusion, out=horizon)
        result += horizon/directions
    result[heights < -1] = 0
    return np.clip(result, 0, 1)


def encode_height(heights):
    packed = np.rint((np.clip(heights, -1, 255)+1)*256).astype(np.uint16)
    packed[heights < -1] = 65535
    rgb = np.zeros((*heights.shape, 3), dtype=np.uint8)
    rgb[:, :, 0] = packed >> 8
    rgb[:, :, 1] = packed & 255
    return rgb


def source_identity(data, independent=False):
    """独立样片不能借用规范目录/碰撞身份；旧调用仍只接受规范来源。"""
    if independent:
        if data.get('schema') != 1 or data.get('configuration') != 'independent_cells_lod5' or len(data.get('sources', [])) != 32 \
                or 'catalog_sha256' in data or 'collision_sha256' in data:
            raise ValueError('wrong independent AO source')
        if hashlib.sha256(Path(data['index_path']).read_bytes()).hexdigest() != data['index_sha256']:
            raise ValueError('independent AO index drift')
        return dict(index_sha256=data['index_sha256'], source_kind='independent_cells_lod5')
    if data.get('schema') != 1 or data.get('configuration') != 'lod5_full' or len(data['sources']) != 16:
        raise ValueError('wrong AO source')
    return dict(catalog_sha256=data['catalog_sha256'], collision_sha256=data['collision_sha256'])


def build(source, output, sizes=(512, 1024, 2048), independent=False):
    if output.exists():
        raise ValueError('never overwrite AO evidence')
    data = json.loads(source.read_bytes())
    identity = source_identity(data, independent)
    for row in data['sources']:
        if hashlib.sha256(Path(row['path']).read_bytes()).hexdigest().lower() != row['sha256'].lower():
            raise ValueError('native geometry source drift')
    bounds, radius = data['bounds'], float(data['radius'])
    span = bounds[2]-bounds[0]
    if span != bounds[3]-bounds[1] or span <= 0:
        raise ValueError('candidate requires a square region')
    triangles = [row['points'] for row in data['triangles']]
    output.mkdir(parents=True)
    rows = []
    master = None
    for size in sorted(sizes, reverse=True):
        spacing = span/size
        border = math.ceil(radius/spacing)+1
        margin = border*spacing
        expanded = [bounds[0]-margin, bounds[1]-margin, bounds[2]+margin, bounds[3]+margin]
        heights = height_field(triangles, expanded, size+2*border)
        if master is None:
            ao = horizon_ao(heights, spacing, radius)[border:-border, border:-border]
            master = Image.fromarray(np.rint(ao*255).astype(np.uint8))
            ao_image = master
        else:
            # 分档同源能量：先烘最高档，再面积预滤波；不能每档改变近场采样距离。
            ao_image = master.resize((size, size), Image.Resampling.BOX)
            ao = np.asarray(ao_image, dtype=np.float32)/255
        heights = heights[border:-border, border:-border]
        ao_path, h_path = output/f'ao_{size}.png', output/f'height_{size}.png'
        ao_image.save(ao_path)
        Image.fromarray(encode_height(heights)).save(h_path)
        rows.append({'size': size, 'max_scale': size/span, 'ao': ao_path.name, 'height': h_path.name,
                     'ao_sha256': hashlib.sha256(ao_path.read_bytes()).hexdigest(),
                     'height_sha256': hashlib.sha256(h_path.read_bytes()).hexdigest(),
                     'conservative_bytes': size*size*12, 'ao_max': float(ao.max()),
                     'nonzero_pixels': int(np.count_nonzero(ao)), 'valid_pixels': int(np.count_nonzero(heights >= -1))})
        print(json.dumps(rows[-1]), flush=True)
    (output/'manifest.json').write_text(json.dumps({'schema': 1, 'preview_only': True, 'method': 'local_heightfield_horizon',
        'bounds': bounds, 'radius': radius, 'directions': 32, 'rows': sorted(rows, key=lambda row: row['size']),
        'lod_filter': 'highest_native_bake_area_average',
        'source_sha256': hashlib.sha256(source.read_bytes()).hexdigest(), **identity,
        'triangles': len(triangles), 'horizontal_only': True}, indent=2), encoding='utf-8')


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('source', type=Path)
    parser.add_argument('output', type=Path)
    parser.add_argument('--independent', action='store_true')
    args = parser.parse_args()
    build(args.source, args.output, independent=args.independent)
