"""从既有无损底图与 Terrarium 缓存提取实验用几何数据；不修改源图片。

运行时只读生成的 JSON。默认输出 tmp，--output 可指定实验资源路径。
"""
from __future__ import annotations
import argparse
import hashlib
import json
import math
from pathlib import Path
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parents[1]
GRID = 257


def simplify(points, tolerance=0.8):
    if len(points) < 3:
        return points
    p = np.asarray(points, dtype=float)
    d = p[-1] - p[0]
    if np.dot(d, d) == 0:
        distances = np.linalg.norm(p - p[0], axis=1)
    else:
        t = np.clip((p - p[0]) @ d / np.dot(d, d), 0, 1)
        distances = np.linalg.norm(p - p[0] - t[:, None] * d, axis=1)
    at = int(np.argmax(distances))
    if distances[at] <= tolerance:
        return [points[0], points[-1]]
    return simplify(points[:at + 1], tolerance)[:-1] + simplify(points[at:], tolerance)


def outlines(mask):
    # 格点有向边追踪，保留每个闭环（包括内洞），不把洞错误填实。
    m = np.pad(mask, 1)
    edges = {}
    for condition, a, b in [
        (m[1:-1, 1:-1] & ~m[:-2, 1:-1], (0, 0), (1, 0)),
        (m[1:-1, 1:-1] & ~m[1:-1, 2:], (1, 0), (1, 1)),
        (m[1:-1, 1:-1] & ~m[2:, 1:-1], (1, 1), (0, 1)),
        (m[1:-1, 1:-1] & ~m[1:-1, :-2], (0, 1), (0, 0)),
    ]:
        ys, xs = np.nonzero(condition)
        for x, y in zip(xs.tolist(), ys.tolist()):
            edges.setdefault((x + a[0], y + a[1]), []).append((x + b[0], y + b[1]))
    result = []
    while edges:
        start = next(iter(edges))
        at = start
        loop = [start]
        while at in edges:
            options = edges[at]
            nxt = options.pop()
            if not options:
                del edges[at]
            loop.append(nxt)
            at = nxt
            if at == start:
                break
        if len(loop) < 24 or loop[-1] != start:
            continue
        mid = len(loop) // 2
        reduced = simplify(loop[:mid + 1], 1.25)[:-1] + simplify(loop[mid:], 1.25)
        if len(reduced) >= 4:
            result.append(reduced)
    return result


def build(output):
    source_dir = ROOT / 'resources/maps/basemap_tiles/desert'
    manifest_path = source_dir / 'manifest.json'
    manifest = json.loads(manifest_path.read_text())
    meta = json.loads((ROOT / 'resources/maps/desert_railway_bg_v2.json').read_text())
    doc = json.loads((ROOT / 'resources/maps/desert_railway_preview.aglmap').read_text())
    level = manifest['levels']['detail']
    w, h = level['size']
    rgb = np.zeros((h, w, 3), dtype=np.uint8)
    for tile in level['tiles']:
        x, y, tw, th = tile['content_rect']
        pixels = np.asarray(Image.open(source_dir / 'detail' / tile['path']).convert('RGB'))
        rgb[y:y + th, x:x + tw] = pixels[16:16 + th, 16:16 + tw]
    r, g, b = [rgb[:, :, i].astype(np.int16) for i in range(3)]
    water = (b - r > 8) & (g - r > 6)
    # 仅闭合源岸边虚线造成的单像素孔隙，提取轮廓而不输出改写的位图。
    water = np.asarray(Image.fromarray(water).filter(ImageFilter.MaxFilter(3)).filter(ImageFilter.MinFilter(3))) > 0
    loops = outlines(water)
    bbox = meta['bbox_ll']
    clat, clon = meta['game_world_center_latlon']
    sx = meta['game_world_meters_per_degree_lon_at_center'] * 0.5
    sy = meta['game_world_meters_per_degree_lat'] * 0.5
    rect = [(bbox['lon_min'] - clon) * sx, -(bbox['lat_max'] - clat) * sy,
            (bbox['lon_max'] - bbox['lon_min']) * sx, (bbox['lat_max'] - bbox['lat_min']) * sy]
    def world(p):
        return [round(rect[0] + p[0] / w * rect[2], 2), round(rect[1] + p[1] / h * rect[3], 2)]
    water_loops = [[world(p) for p in loop] for loop in loops]
    # 水面用 even-odd 扫描条带分解成互不重叠梯形；保留内洞，不铺矩形盖掉岛屿。
    edges = []
    for loop in water_loops:
        for p, q in zip(loop, loop[1:]):
            if p[1] == q[1]:
                continue
            if p[1] > q[1]:
                p, q = q, p
            edges.append((p, q))
    levels = sorted({p[1] for edge in edges for p in edge})
    def edge_x(index, y):
        p, q = edges[index]
        return p[0] + (q[0] - p[0]) * ((y - p[1]) / (q[1] - p[1]))
    bands = []
    active = {}
    for lo, hi in zip(levels, levels[1:]):
        mid = (lo + hi) * 0.5
        crossings = sorted((edge_x(i, mid), i) for i, (p, q) in enumerate(edges) if p[1] < mid < q[1])
        assert len(crossings) % 2 == 0
        following = {}
        for left, right in zip(crossings[::2], crossings[1::2]):
            key = (left[1], right[1])
            record = active.get(key)
            if record is None:
                record = [key, lo, hi]
                bands.append(record)
            else:
                record[2] = hi
            following[key] = record
        active = following
    water_quads = [[[round(edge_x(key[0], lo), 2), lo], [round(edge_x(key[1], lo), 2), lo],
                    [round(edge_x(key[1], hi), 2), hi], [round(edge_x(key[0], hi), 2), hi]]
                   for key, lo, hi in bands]
    # 先逐瓦片解码米值，再按世界点对应的 Mercator 坐标双线性采样。
    tile_cache = ROOT / 'tmp/topographic-relief-prototype/terrain-cache/11'
    tiles = {}
    hashes = {}
    dem = np.zeros((GRID, GRID), dtype=np.float32)
    for iy in range(GRID):
        lat = bbox['lat_max'] - iy / (GRID - 1) * (bbox['lat_max'] - bbox['lat_min'])
        wy = (0.5 - math.log((1 + math.sin(math.radians(lat))) / (1 - math.sin(math.radians(lat)))) / (4 * math.pi)) * 524288 - 0.5
        for ix in range(GRID):
            lon = bbox['lon_min'] + ix / (GRID - 1) * (bbox['lon_max'] - bbox['lon_min'])
            wx = (lon + 180) / 360 * 524288 - 0.5
            value = 0.0
            for dy in range(2):
                for dx in range(2):
                    px, py = math.floor(wx) + dx, math.floor(wy) + dy
                    key = (px // 256, py // 256)
                    if key not in tiles:
                        path = tile_cache / str(key[0]) / f'{key[1]}.png'
                        a = np.asarray(Image.open(path).convert('RGB'), dtype=np.float32)
                        tiles[key] = a[:, :, 0] * 256 + a[:, :, 1] + a[:, :, 2] / 256 - 32768
                        hashes[f'11/{key[0]}/{key[1]}'] = hashlib.sha256(path.read_bytes()).hexdigest()
                    weight = (wx % 1 if dx else 1 - wx % 1) * (wy % 1 if dy else 1 - wy % 1)
                    value += tiles[key][py % 256, px % 256] * weight
            dem[iy, ix] = value
    assert np.isfinite(dem).all() and 0 < dem.min() < dem.max() < 2000
    # 冻结玩法地理周围的表现地面；保护区含两个格点裕量，避免插值抬起道路。
    protected = Image.new('L', (GRID, GRID))
    draw = ImageDraw.Draw(protected)
    def grid(p):
        return ((p[0] - rect[0]) / rect[2] * (GRID - 1), (p[1] - rect[1]) / rect[3] * (GRID - 1))
    for road in doc['roads'] + doc['railways']:
        draw.line([grid(p) for p in road['points']], fill=255, width=7)
        for p in road['points']:
            gx, gy = grid(p)
            draw.ellipse((gx - 4, gy - 4, gx + 4, gy + 4), fill=255)
    for poly in doc['layer_polygons']['urban'] + [a['polygon'] for a in doc['airports']] + [a['footprint'] for a in doc['buildings']]:
        draw.polygon([grid(p) for p in poly], fill=255)
        draw.line([grid(p) for p in poly + [poly[0]]], fill=255, width=9)
    water_small = np.asarray(Image.fromarray(water).resize((GRID, GRID), Image.Resampling.NEAREST)) > 0
    # 粗三角面采样会使用相邻偶数格点；补一格保护边缘，保住原道路平面。
    protected = protected.filter(ImageFilter.MaxFilter(3))
    protect = np.asarray(protected) / 255.0
    feather = np.asarray(protected.filter(ImageFilter.GaussianBlur(2))) / 255.0
    field = np.clip((dem - 430.0) * 0.8, 0, 500) * (1 - np.maximum(protect, feather))
    field[water_small] = 0

    water_guard = Image.fromarray(water_small).filter(ImageFilter.MaxFilter(5)).convert('L')
    water_guard = np.asarray(water_guard) / 255.0
    field *= 1 - water_guard
    # 谷地曲率只决定美术植被覆盖，不作为现实植被测绘或玩法地貌。
    neighbour_mean = (np.roll(dem, 2, 0) + np.roll(dem, -2, 0) + np.roll(dem, 2, 1) + np.roll(dem, -2, 1)) * 0.25
    cover = np.clip((neighbour_mean - dem) / 15, 0, 1) * (1 - np.maximum(protect, feather))
    cover[water_small] = 0
    cover[:2] = cover[-2:] = 0
    cover[:, :2] = cover[:, -2:] = 0
    # 确定性稀疏灌丛带：沿低坡谷地，避开水面和全部设施保护区；不是测绘植被。
    rng = np.random.default_rng(20260906)
    candidates = []
    for iy in range(3, GRID - 3):
        for ix in range(3, GRID - 3):
            if protect[iy, ix] > 0 or feather[iy, ix] > 0.02 or water_small[iy - 1:iy + 2, ix - 1:ix + 2].any():
                continue
            legacy_height = field[iy, ix] * (0.23 / 0.8)
            if not (15 < legacy_height < 95) or max(abs(dem[iy + 1, ix] - dem[iy - 1, ix]), abs(dem[iy, ix + 1] - dem[iy, ix - 1])) > 40:
                continue
            if rng.random() > 0.05 + float(cover[iy, ix]) * 0.75:
                continue
            p = [rect[0] + ix / (GRID - 1) * rect[2], rect[1] + iy / (GRID - 1) * rect[3]]
            downhill = math.atan2(float(dem[iy - 1, ix] - dem[iy + 1, ix]), float(dem[iy, ix - 1] - dem[iy, ix + 1]))
            candidates.append([round(p[0], 2), round(p[1], 2), round(float(field[iy, ix]), 2), round(float(rng.uniform(0.7, 1.4)), 2), round(downhill, 5)])
    if len(candidates) > 1200:
        chosen = sorted(rng.choice(len(candidates), 1200, replace=False))
        candidates = [candidates[i] for i in chosen]
    # 裸岩是 DEM 凸坡约束的美术台阶，独立随机源不影响原植被分布。
    rock_rng = np.random.default_rng(20260914)
    outcrops = []
    plant_centers = np.asarray(candidates)[:, :2]
    spacing = np.array(rect[2:]) / (GRID - 1)
    blocked = np.maximum(protect, feather)
    for iy in range(4, GRID - 4, 2):
        for ix in range(4, GRID - 4, 2):
            if blocked[iy-2:iy+3, ix-2:ix+3].max() > 0.02 or water_guard[iy-2:iy+3, ix-2:ix+3].any():
                continue
            gx = float(dem[iy, ix+1] - dem[iy, ix-1]) / (2 * spacing[0])
            gz = float(dem[iy+1, ix] - dem[iy-1, ix]) / (2 * spacing[1])
            # 高程先乘水平比例，得到未夸张的坡度。
            slope = math.hypot(gx, gz) * 0.5
            if slope < 0.035 or dem[iy, ix] - neighbour_mean[iy, ix] < 0.5:
                continue
            x, z = rect[0] + ix * spacing[0], rect[1] + iy * spacing[1]
            length = float(rock_rng.uniform(80, 170))
            if np.square(plant_centers - [x, z]).sum(axis=1).min() < (length * 1.15 + 100) ** 2:
                continue
            outcrops.append([round(x, 2), round(z, 2), round(math.atan2(gz, gx) + math.pi/2, 5),
                round(length, 2), round(length * float(rock_rng.uniform(0.38, 0.62)), 2), round(float(rock_rng.uniform(30, 90)), 2)])
    selected = []
    for index in rock_rng.permutation(len(outcrops)):
        rock = outcrops[index]
        if any(math.hypot(rock[0]-other[0], rock[1]-other[1]) < (rock[3]+other[3])*1.15+20 for other in selected):
            continue
        selected.append(rock)
        if len(selected) == 360:
            break
    outcrops = selected
    result = {'version': 14, 'world_rect': rect, 'grid_size': GRID,
              'heights': np.round(field, 2).flatten().tolist(), 'vegetation': candidates,
              'outcrops': outcrops,
              'cover': np.round(cover, 2).flatten().tolist(),
              'water_contours': water_loops, 'water_quads': water_quads,
              'provenance': {'map_manifest_sha256': hashlib.sha256(manifest_path.read_bytes()).hexdigest(),
                 'source': 'Mapzen / Tilezen Terrarium, cached z11; CARTO / OSM water silhouettes',
                 'attribution': 'Mapzen, SRTM and other upstream data: https://www.mapzen.com/rights/ ; OpenStreetMap contributors and CARTO',
                 'terrain_url': 'https://s3.amazonaws.com/elevation-tiles-prod/terrarium/{z}/{x}/{y}.png',
                 'tile_sha256': hashes, 'dem_min_m': float(dem.min()), 'dem_max_m': float(dem.max()),
                 'display_height': 'clamp((DEM_m - 430)*0.8, 0, 500) with gameplay corridor flattening; vertical exaggeration 1.6; not absolute altitude'}}
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(result, separators=(',', ':')), encoding='utf-8')
    print(json.dumps({'output': str(output), 'bytes': output.stat().st_size, 'water_loops': len(water_loops),
        'water_vertices': sum(map(len, water_loops)), 'vegetation': len(candidates), 'outcrops': len(outcrops), 'dem_range': [float(dem.min()), float(dem.max())]}))


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--output', type=Path, default=ROOT / 'tmp/desert-volume/relief_data.json')
    build(parser.parse_args().output)
