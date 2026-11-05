"""由东京正式地图的完整渲染地表源生成舰船到岸净空。仅依赖 Pillow。"""
import argparse
import hashlib
import json
import math
from pathlib import Path
import zlib

from PIL import Image, ImageDraw

ORIGIN = (-16300, -15700)
STEP = 8
TILES = 16
TILE_SIZE = 2000
WIDTH = TILES * TILE_SIZE // STEP
LAND_KINDS = {'land', 'green', 'park', 'paved', 'rail_yard'}


def clearance_grid(surface):
    # 两趟求到最近陆格的棋盘距离。它是欧氏距离的下界，255格以外饱和。
    values = bytearray(surface.tobytes())
    for step in (1, -1):
        rows = range(1, WIDTH - 1) if step == 1 else range(WIDTH - 2, 0, -1)
        for row in rows:
            start = row * WIDTH
            for col in rows:
                i = start + col
                if values[i] == 0:
                    continue
                above = i - step * WIDTH
                nearest = min(values[i - step], values[above - 1], values[above], values[above + 1])
                if nearest + 1 < values[i]:
                    values[i] = nearest + 1
    return values


def build(source, output):
    surface = Image.new('L', (WIDTH, WIDTH), 255)
    draw = ImageDraw.Draw(surface)
    counts = dict.fromkeys(sorted(LAND_KINDS), 0)
    source_hash = hashlib.sha256()
    for y in range(TILES):
        for x in range(TILES):
            name = f'detail_{x:02}_{y:02}/ground.json'
            data = (source / name).read_bytes()
            digest = hashlib.sha256(data)
            status = json.loads((source / name).with_name('source-status.json').read_bytes())
            if status['status'] != 'source_ready' or digest.hexdigest() != status['hashes']['ground']:
                raise ValueError(f'地表与制作记录不一致 {name}')
            source_hash.update(name.encode() + digest.digest())
            tile = json.loads(data)
            left = ORIGIN[0] + TILE_SIZE * x
            top = ORIGIN[1] + TILE_SIZE * y
            if tile['bounds'] != [left, top, left + TILE_SIZE, top + TILE_SIZE] or tile['base_kind'] != 'water':
                raise ValueError(f'地表范围或底色异常 {name}')
            for face in tile['surfaces']:
                kind = face['kind']
                if kind == 'water':
                    continue
                points = face['triangles']
                if kind not in LAND_KINDS or len(points) % 3:
                    raise ValueError(f'未知地表或无效三角形 {name}: {kind}')
                for i in range(0, len(points), 3):
                    polygon = [(math.floor((a - ORIGIN[0]) / STEP), math.floor((b - ORIGIN[1]) / STEP))
                               for a, b in points[i:i+3]]
                    draw.polygon(polygon, fill=0)
                counts[kind] += len(points) // 3
    # 预留地图边界，舰身不能越出有地表证据的范围。
    draw.rectangle((0, 0, WIDTH - 1, WIDTH - 1), outline=0)
    packed = zlib.compress(clearance_grid(surface), 9)
    output.write_bytes(packed)
    report = dict(schema=1, origin=ORIGIN, step=STEP, width=WIDTH, tiles=TILES*TILES,
                  triangles=counts, source_sha256=source_hash.hexdigest(), sha256=hashlib.sha256(packed).hexdigest())
    output.with_suffix('.json').write_text(json.dumps(report, indent=2) + '\n', encoding='utf8')
    print(report, 'packed_bytes', len(packed))


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--source', type=Path, default=Path('tmp/tokyo-bay-volume/r343-full-replayed-a'))
    parser.add_argument('--output', type=Path, default=Path('resources/maps/tokyo_naval_clearance.bin'))
    args = parser.parse_args()
    build(args.source, args.output)
