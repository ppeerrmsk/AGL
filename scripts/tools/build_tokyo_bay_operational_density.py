#!/usr/bin/env python3
"""Build a compact, soft vector density field from the full Tokyo Bay AGDT tiles.

The output is not a map texture.  It stores three 8-bit scalar fields on a
regular world-space vertex grid; Godot turns that grid into one indexed canvas
triangle array.  Water polygons are drawn after it and therefore mask coastal
bleed without a per-frame shader or redraw.
"""

from __future__ import annotations

import gzip
import json
import math
import struct
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
MANIFEST = ROOT / "resources" / "maps" / "tokyo_bay_detail_tiles_full.json"
TOKYO_DATA = ROOT / "resources" / "maps" / "tokyo_bay.json"
OUTPUT = ROOT / "resources" / "maps" / "tokyo_bay_operational_density.agod.gz"

# 62.5 world px = 125 m。257² 在 0.28 zoom 下会露出约 35 屏幕像素的
# 三角插值单元；513² 保留同一世界模糊尺度，同时消除可见块感。
GRID_STEP = 62.5
TRIANGLE_LAYERS = (
    "forest", "farmland", "orchard", "grass", "meadow", "industrial",
    "residential", "parking", "civic", "park", "water",
    "building_small", "building_medium", "building_large",
)
URBAN_LAYERS = {"building_small", "building_medium", "building_large", "residential", "civic"}
VEGETATION_LAYERS = {"forest", "farmland", "orchard", "grass", "meadow", "park"}
INDUSTRIAL_LAYERS = {"industrial", "parking"}


def gaussian_kernel(radius: int, sigma: float) -> list[float]:
    values = [math.exp(-(offset * offset) / (2.0 * sigma * sigma)) for offset in range(-radius, radius + 1)]
    total = sum(values)
    return [value / total for value in values]


def blur(values: list[float], cols: int, rows: int, radius: int, sigma: float) -> list[float]:
    kernel = gaussian_kernel(radius, sigma)
    horizontal = [0.0] * len(values)
    for y in range(rows):
        row = y * cols
        for x in range(cols):
            total = 0.0
            for k, weight in enumerate(kernel):
                sx = min(cols - 1, max(0, x + k - radius))
                total += values[row + sx] * weight
            horizontal[row + x] = total
    vertical = [0.0] * len(values)
    for y in range(rows):
        for x in range(cols):
            total = 0.0
            for k, weight in enumerate(kernel):
                sy = min(rows - 1, max(0, y + k - radius))
                total += horizontal[sy * cols + x] * weight
            vertical[y * cols + x] = total
    return vertical


def normalize(values: list[float], percentile: float, gamma: float) -> bytes:
    transformed = [math.log1p(max(0.0, value)) for value in values]
    nonzero = sorted(value for value in transformed if value > 0.0)
    if not nonzero:
        return bytes(len(values))
    index = min(len(nonzero) - 1, int((len(nonzero) - 1) * percentile))
    ceiling = max(nonzero[index], 1e-6)
    return bytes(round(255.0 * min(1.0, value / ceiling) ** gamma) for value in transformed)


def point_in_polygon(x: float, y: float, polygon: list[tuple[float, float]]) -> bool:
    inside = False
    previous = len(polygon) - 1
    for index, (current_x, current_y) in enumerate(polygon):
        previous_x, previous_y = polygon[previous]
        if (current_y > y) != (previous_y > y):
            edge_x = (previous_x - current_x) * (y - current_y) / (previous_y - current_y) + current_x
            if x < edge_x:
                inside = not inside
        previous = index
    return inside


def accumulate_triangle(field: list[float], cols: int, rows: int, origin_x: float, origin_y: float,
                        points: tuple[float, float, float, float, float, float], weight_scale: float) -> None:
    ax, ay, bx, by, cx, cy = points
    center_x = (ax + bx + cx) / 3.0
    center_y = (ay + by + cy) / 3.0
    gx = int(round((center_x - origin_x) / GRID_STEP))
    gy = int(round((center_y - origin_y) / GRID_STEP))
    if gx < 0 or gx >= cols or gy < 0 or gy >= rows:
        return
    area = abs((bx - ax) * (cy - ay) - (by - ay) * (cx - ax)) * 0.5
    field[gy * cols + gx] += min(area, GRID_STEP * GRID_STEP * 3.0) * weight_scale


def main() -> int:
    manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
    grid = manifest["grid"]
    origin_x, origin_y = (float(value) for value in grid["origin"])
    width = float(grid["tile_size"]) * int(grid["columns"])
    height = float(grid["tile_size"]) * int(grid["rows"])
    cols = int(round(width / GRID_STEP)) + 1
    rows = int(round(height / GRID_STEP)) + 1
    urban = [0.0] * (cols * rows)
    vegetation = [0.0] * (cols * rows)
    industrial = [0.0] * (cols * rows)

    for tile_index, tile in enumerate(manifest["tiles"]):
        packed_path = ROOT / tile["data_path"].removeprefix("res://")
        data = gzip.decompress(packed_path.read_bytes())
        if data[:4] != b"AGDT":
            raise ValueError(f"invalid AGDT magic: {packed_path}")
        version, _reserved, tile_x, tile_y, _tile_w, _tile_h, quantization = struct.unpack_from("<HHfffff", data, 4)
        if version != 1 or quantization <= 0.0:
            raise ValueError(f"unsupported AGDT header: {packed_path}")
        offset = 28
        tile_rect = tile["rect"]
        tile_min_x, tile_min_y = float(tile_rect[0]), float(tile_rect[1])
        tile_max_x = tile_min_x + float(tile_rect[2])
        tile_max_y = tile_min_y + float(tile_rect[3])
        for layer in TRIANGLE_LAYERS:
            point_count = struct.unpack_from("<I", data, offset)[0]
            offset += 4
            byte_count = point_count * 8
            if layer not in URBAN_LAYERS | VEGETATION_LAYERS | INDUSTRIAL_LAYERS:
                offset += byte_count
                continue
            target = urban if layer in URBAN_LAYERS else vegetation if layer in VEGETATION_LAYERS else industrial
            scale = 1.0 if layer.startswith("building_") else 0.22 if layer in URBAN_LAYERS else 0.10
            for point_index in range(0, point_count - 2, 3):
                coords: list[float] = []
                for vertex in range(3):
                    qx, qy = struct.unpack_from("<ii", data, offset + (point_index + vertex) * 8)
                    coords.extend((tile_x + qx / quantization, tile_y + qy / quantization))
                center_x = (coords[0] + coords[2] + coords[4]) / 3.0
                center_y = (coords[1] + coords[3] + coords[5]) / 3.0
                # Seam-crossing features occur in adjacent query chunks.  A triangle contributes only
                # to the tile containing its centroid, making the aggregate deterministic and seam-free.
                if tile_min_x <= center_x < tile_max_x and tile_min_y <= center_y < tile_max_y:
                    accumulate_triangle(target, cols, rows, origin_x, origin_y, tuple(coords), scale)
            offset += byte_count
        if (tile_index + 1) % 20 == 0:
            print(f"[operational-density] {tile_index + 1}/{len(manifest['tiles'])}")

    urban_bytes = bytearray(normalize(blur(urban, cols, rows, 6, 3.10), 0.965, 0.72))
    vegetation_bytes = bytearray(normalize(blur(vegetation, cols, rows, 8, 4.20), 0.955, 0.82))
    industrial_bytes = bytearray(normalize(blur(industrial, cols, rows, 6, 3.30), 0.955, 0.78))
    geography = json.loads(TOKYO_DATA.read_text(encoding="utf-8"))
    land_polygons = [list(zip(values[0::2], values[1::2])) for values in geography["land_mask"]]
    for y in range(rows):
        world_y = origin_y + y * GRID_STEP
        for x in range(cols):
            world_x = origin_x + x * GRID_STEP
            index = y * cols + x
            if not any(point_in_polygon(world_x, world_y, polygon) for polygon in land_polygons):
                urban_bytes[index] = 0
                vegetation_bytes[index] = 0
                industrial_bytes[index] = 0
    payload = bytearray(b"AGOD")
    payload.extend(struct.pack("<HHfffHH", 1, 0, origin_x, origin_y, GRID_STEP, cols, rows))
    for index in range(cols * rows):
        payload.extend((urban_bytes[index], vegetation_bytes[index], industrial_bytes[index]))
    OUTPUT.write_bytes(gzip.compress(bytes(payload), compresslevel=9, mtime=0))
    print(json.dumps({
        "output": str(OUTPUT),
        "grid": [cols, rows],
        "step": GRID_STEP,
        "uncompressed_bytes": len(payload),
        "gzip_bytes": OUTPUT.stat().st_size,
        "urban_nonzero": sum(value > 0 for value in urban_bytes),
        "vegetation_nonzero": sum(value > 0 for value in vegetation_bytes),
        "industrial_nonzero": sum(value > 0 for value in industrial_bytes),
    }, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
