#!/usr/bin/env python3
"""Pack seam-owned large buildings plus quota-limited city marks for Operational LOD."""

from __future__ import annotations

import gzip
import json
import math
import struct
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
MANIFEST = ROOT / "resources" / "maps" / "tokyo_bay_detail_tiles_full.json"
OUTPUT = ROOT / "resources" / "maps" / "tokyo_bay_operational_buildings.agob.gz"
QUANTIZATION = 4.0
TRIANGLE_LAYER_COUNT = 14
LINE_LAYER_COUNT = 6
SMALL_OUTLINE_INDEX = 0
MEDIUM_OUTLINE_INDEX = 1
LARGE_OUTLINE_INDEX = 2
MEDIUM_QUOTA_PER_TILE = 600
SMALL_QUOTA_PER_TILE = 1200


def oriented_quad(points: list[tuple[float, float]]) -> tuple[float, list[tuple[float, float]]] | None:
    if len(points) > 1 and points[0] == points[-1]:
        points = points[:-1]
    if len(points) < 3:
        return None
    center_x = sum(point[0] for point in points) / len(points)
    center_y = sum(point[1] for point in points) / len(points)
    xx = sum((point[0] - center_x) ** 2 for point in points)
    yy = sum((point[1] - center_y) ** 2 for point in points)
    xy = sum((point[0] - center_x) * (point[1] - center_y) for point in points)
    angle = 0.5 * math.atan2(2.0 * xy, xx - yy)
    axis_x = (math.cos(angle), math.sin(angle))
    axis_y = (-axis_x[1], axis_x[0])
    projected_x = [point[0] * axis_x[0] + point[1] * axis_x[1] for point in points]
    projected_y = [point[0] * axis_y[0] + point[1] * axis_y[1] for point in points]
    min_x, max_x = min(projected_x), max(projected_x)
    min_y, max_y = min(projected_y), max(projected_y)
    width = max_x - min_x
    height = max_y - min_y
    if width < 1.0 or height < 1.0:
        return None
    polygon_area = abs(sum(
        points[index][0] * points[(index + 1) % len(points)][1]
        - points[(index + 1) % len(points)][0] * points[index][1]
        for index in range(len(points))
    )) * 0.5
    # 凹形/折线型厂房的完整 OBB 会把空角填成巨大黑块；保持朝向但按原面积
    # 等比缩小，最低保留 35% 线性面积比例以免细长地标消失。
    fill_ratio = max(0.35, min(1.0, polygon_area / max(width * height, 1.0)))
    scale = math.sqrt(fill_ratio)
    projected_center_x = (min_x + max_x) * 0.5
    projected_center_y = (min_y + max_y) * 0.5
    half_width = width * scale * 0.5
    half_height = height * scale * 0.5
    min_x, max_x = projected_center_x - half_width, projected_center_x + half_width
    min_y, max_y = projected_center_y - half_height, projected_center_y + half_height
    corners = []
    for px, py in ((min_x, min_y), (max_x, min_y), (max_x, max_y), (min_x, max_y)):
        corners.append((px * axis_x[0] + py * axis_y[0], px * axis_x[1] + py * axis_y[1]))
    return polygon_area, corners


def quad_triangles(corners: list[tuple[float, float]]) -> list[tuple[float, float]]:
    return [corners[0], corners[1], corners[2], corners[0], corners[2], corners[3]]


def main() -> int:
    manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
    world_origin_x, world_origin_y = (float(value) for value in manifest["grid"]["origin"])
    output_groups: dict[str, list[tuple[int, int]]] = {"large": [], "medium": [], "small": []}
    for tile_index, tile in enumerate(manifest["tiles"]):
        path = ROOT / tile["data_path"].removeprefix("res://")
        data = gzip.decompress(path.read_bytes())
        if data[:4] != b"AGDT":
            raise ValueError(f"bad AGDT: {path}")
        version, _reserved, tile_x, tile_y, _w, _h, quantization = struct.unpack_from("<HHfffff", data, 4)
        if version != 1:
            raise ValueError(f"unsupported AGDT: {path}")
        offset = 28
        rect_x, rect_y, rect_w, rect_h = (float(value) for value in tile["rect"])
        for _layer_index in range(TRIANGLE_LAYER_COUNT):
            point_count = struct.unpack_from("<I", data, offset)[0]
            offset += 4
            offset += point_count * 8
        candidates: dict[str, list[tuple[float, list[tuple[float, float]]]]] = {
            "large": [], "medium": [], "small": [],
        }
        for line_layer_index in range(LINE_LAYER_COUNT):
            path_count = struct.unpack_from("<I", data, offset)[0]
            offset += 4
            for _path_index in range(path_count):
                point_count = struct.unpack_from("<I", data, offset)[0]
                offset += 4
                points = []
                for point_index in range(point_count):
                    qx, qy = struct.unpack_from("<ii", data, offset + point_index * 8)
                    points.append((tile_x + qx / quantization, tile_y + qy / quantization))
                offset += point_count * 8
                group = (
                    "small" if line_layer_index == SMALL_OUTLINE_INDEX
                    else "medium" if line_layer_index == MEDIUM_OUTLINE_INDEX
                    else "large" if line_layer_index == LARGE_OUTLINE_INDEX
                    else ""
                )
                if not group or len(points) < 3:
                    continue
                center_points = points[:-1] if points[0] == points[-1] else points
                center_x = sum(point[0] for point in center_points) / len(center_points)
                center_y = sum(point[1] for point in center_points) / len(center_points)
                if not (rect_x <= center_x < rect_x + rect_w and rect_y <= center_y < rect_y + rect_h):
                    continue
                quad = oriented_quad(points)
                if quad is not None:
                    candidates[group].append(quad)
        for group, quota in (
            ("large", len(candidates["large"])),
            ("medium", MEDIUM_QUOTA_PER_TILE),
            ("small", SMALL_QUOTA_PER_TILE),
        ):
            # 面积优先保证缩到 0.28 时仍是柔和街区颗粒；坐标作为稳定 tie-breaker。
            selected = sorted(
                candidates[group],
                key=lambda entry: (-entry[0], entry[1][0][1], entry[1][0][0]),
            )[:quota]
            for _area, corners in selected:
                for x, y in quad_triangles(corners):
                    output_groups[group].append((
                        round((x - world_origin_x) * QUANTIZATION),
                        round((y - world_origin_y) * QUANTIZATION),
                    ))
        if (tile_index + 1) % 20 == 0:
            print(f"[operational-buildings] {tile_index + 1}/{len(manifest['tiles'])}")

    payload = bytearray(b"AGOB")
    payload.extend(struct.pack(
        "<HHfffIII", 2, 0, world_origin_x, world_origin_y, QUANTIZATION,
        len(output_groups["large"]), len(output_groups["medium"]), len(output_groups["small"]),
    ))
    for group in ("large", "medium", "small"):
        for x, y in output_groups[group]:
            payload.extend(struct.pack("<ii", x, y))
    OUTPUT.write_bytes(gzip.compress(bytes(payload), compresslevel=9, mtime=0))
    print(json.dumps({
        "output": str(OUTPUT),
        "points": {group: len(points) for group, points in output_groups.items()},
        "triangles": {group: len(points) // 3 for group, points in output_groups.items()},
        "quads": {
            "large": len(output_groups["large"]) // 6,
            "medium": len(output_groups["medium"]) // 6,
            "small": len(output_groups["small"]) // 6,
        },
        "uncompressed_bytes": len(payload),
        "gzip_bytes": OUTPUT.stat().st_size,
    }, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
