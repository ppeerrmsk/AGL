#!/usr/bin/env python3
"""Bake deterministic low-frequency paper-relief plates into the vector preview JSON."""

from __future__ import annotations

import gzip
import json
import math
import struct
from pathlib import Path

import numpy as np


ROOT = Path(__file__).resolve().parents[2]
PREVIEW_PATH = ROOT / "resources" / "maps" / "tokyo_bay_vector_preview.json"
DENSITY_PATH = ROOT / "resources" / "maps" / "tokyo_bay_operational_density.agod.gz"
PREFIXES = ("green", "gray", "taupe")
MAX_PLATES = 220
MACRO_SIZE_PX = 1100.0
SAFE_SAMPLE_PX = 60.0
# 与 Godot Operational 三角/描边审计闭环得到的极窄水道点；附近整块退让，避免只删单三角。
OPERATIONAL_WATER_REJECT_POINTS = ((-328.1, -6429.1),)


def point_in_polygon(point: tuple[float, float], polygon: list[tuple[float, float]]) -> bool:
    x, y = point
    inside = False
    previous = polygon[-1]
    for current in polygon:
        x1, y1 = previous
        x2, y2 = current
        if (y1 > y) != (y2 > y):
            crossing = (x2 - x1) * (y - y1) / (y2 - y1) + x1
            if x < crossing:
                inside = not inside
        previous = current
    return inside


def soften_closed(polygon: list[tuple[float, float]], passes: int = 2) -> list[tuple[float, float]]:
    current = polygon
    for _ in range(passes):
        softened = []
        for index, point in enumerate(current):
            following = current[(index + 1) % len(current)]
            softened.append((
                point[0] * 0.78 + following[0] * 0.22,
                point[1] * 0.78 + following[1] * 0.22,
            ))
            softened.append((
                point[0] * 0.22 + following[0] * 0.78,
                point[1] * 0.22 + following[1] * 0.78,
            ))
        current = softened
    return current


def unpack(flat: list[float]) -> list[tuple[float, float]]:
    points = [(float(flat[i]), float(flat[i + 1])) for i in range(0, len(flat) - 1, 2)]
    if len(points) > 1 and math.dist(points[0], points[-1]) <= 0.01:
        points.pop()
    return points


def bounds(polygon: list[tuple[float, float]]) -> tuple[float, float, float, float]:
    xs = [point[0] for point in polygon]
    ys = [point[1] for point in polygon]
    return min(xs), min(ys), max(xs), max(ys)


def stable_hash(x: int, y: int, salt: int = 0) -> int:
    value = (x * 73856093) ^ (y * 19349663) ^ (salt * 83492791) ^ 0xA61
    return value & 0x7FFFFFFF


def cross(a: tuple[float, float], b: tuple[float, float]) -> float:
    return a[0] * b[1] - a[1] * b[0]


def segments_intersect(a: tuple[float, float], b: tuple[float, float],
                       c: tuple[float, float], d: tuple[float, float]) -> bool:
    ray = (b[0] - a[0], b[1] - a[1])
    edge = (d[0] - c[0], d[1] - c[1])
    denominator = cross(ray, edge)
    if abs(denominator) < 1e-6:
        return False
    offset = (c[0] - a[0], c[1] - a[1])
    t = cross(offset, edge) / denominator
    u = cross(offset, ray) / denominator
    return -1e-6 <= t <= 1.0 + 1e-6 and -1e-6 <= u <= 1.0 + 1e-6


def irregular_plate(center: tuple[float, float], cell_x: int, cell_y: int,
                    scale: float = 1.0) -> list[tuple[float, float]]:
    seed = stable_hash(cell_x, cell_y)
    radius_x = (400.0 + float(seed % 300)) * scale
    radius_y = (320.0 + float((seed // 17) % 260)) * scale
    rotation = float((seed // 31) % 628) / 100.0
    count = 6 + seed % 3
    points = []
    for index in range(count):
        angle = rotation + math.tau * index / count
        wobble = 0.88 + float(stable_hash(cell_x, cell_y, index) % 23) / 100.0
        points.append((
            center[0] + math.cos(angle) * radius_x * wobble,
            center[1] + math.sin(angle) * radius_y * wobble,
        ))
    return points


def scale_polygon(polygon: list[tuple[float, float]], factor: float,
                  offset: tuple[float, float] = (0.0, 0.0)) -> list[tuple[float, float]]:
    center = (
        sum(point[0] for point in polygon) / len(polygon),
        sum(point[1] for point in polygon) / len(polygon),
    )
    return [(
        center[0] + offset[0] + (point[0] - center[0]) * factor,
        center[1] + offset[1] + (point[1] - center[1]) * factor,
    ) for point in polygon]


def flatten(polygon: list[tuple[float, float]]) -> list[float]:
    return [round(value, 1) for point in polygon for value in point]


def main() -> int:
    preview = json.loads(PREVIEW_PATH.read_text(encoding="utf-8"))
    trace = [float(value) for value in preview["trace_rect"]]
    water = []
    inlays = []
    for entry in preview["water_rings"]:
        role = str(entry.get("role", "water"))
        gate = 24.0 if role == "water" else 48.0
        if float(entry.get("area_px2", 0.0)) < gate:
            continue
        polygon = soften_closed(unpack(entry["points"]))
        record = (bounds(polygon), polygon)
        (water if role == "water" else inlays).append(record)

    restore_inlays = []
    for record in inlays:
        box, polygon = record
        center = (
            sum(point[0] for point in polygon) / len(polygon),
            sum(point[1] for point in polygon) / len(polygon),
        )
        if any(
            box2[0] <= center[0] <= box2[2] and box2[1] <= center[1] <= box2[3]
            and point_in_polygon(center, polygon2)
            for box2, polygon2 in water
        ):
            restore_inlays.append(record)

    def is_land(point: tuple[float, float]) -> bool:
        x, y = point
        if not (trace[0] <= x <= trace[2] and trace[1] <= y <= trace[3]):
            return False
        in_water = any(
            box[0] <= x <= box[2] and box[1] <= y <= box[3]
            and point_in_polygon(point, polygon)
            for box, polygon in water
        )
        if not in_water:
            return True
        return any(
            box[0] <= x <= box[2] and box[1] <= y <= box[3]
            and point_in_polygon(point, polygon)
            for box, polygon in restore_inlays
        )

    def crosses_water_boundary(polygon: list[tuple[float, float]]) -> bool:
        polygon_box = bounds(polygon)
        for water_box, water_polygon in water:
            if (polygon_box[2] < water_box[0] or water_box[2] < polygon_box[0]
                    or polygon_box[3] < water_box[1] or water_box[3] < polygon_box[1]):
                continue
            for index, a in enumerate(polygon):
                b = polygon[(index + 1) % len(polygon)]
                for water_index, c in enumerate(water_polygon):
                    d = water_polygon[(water_index + 1) % len(water_polygon)]
                    if segments_intersect(a, b, c, d):
                        return True
            if (water_box[0] >= polygon_box[0] and water_box[2] <= polygon_box[2]
                    and water_box[1] >= polygon_box[1] and water_box[3] <= polygon_box[3]
                    and point_in_polygon(water_polygon[0], polygon)):
                return True
        return False

    raw = gzip.decompress(DENSITY_PATH.read_bytes())
    if raw[:4] != b"AGOD" or struct.unpack_from("<H", raw, 4)[0] != 1:
        raise ValueError("unsupported AGOD")
    origin_x, origin_y, step = struct.unpack_from("<fff", raw, 8)
    cols, rows = struct.unpack_from("<HH", raw, 20)
    channels = np.frombuffer(raw, dtype=np.uint8, offset=24).reshape(rows, cols, 3)

    candidates = []
    min_cell_x = math.floor((trace[0] - origin_x) / MACRO_SIZE_PX)
    max_cell_x = math.ceil((trace[2] - origin_x) / MACRO_SIZE_PX)
    min_cell_y = math.floor((trace[1] - origin_y) / MACRO_SIZE_PX)
    max_cell_y = math.ceil((trace[3] - origin_y) / MACRO_SIZE_PX)
    for cell_y in range(min_cell_y, max_cell_y + 1):
        for cell_x in range(min_cell_x, max_cell_x + 1):
            seed = stable_hash(cell_x, cell_y)
            center = (
                origin_x + (cell_x + 0.05 + float(seed % 90) / 100.0) * MACRO_SIZE_PX,
                origin_y + (cell_y + 0.05 + float((seed // 59) % 90) / 100.0) * MACRO_SIZE_PX,
            )
            if not is_land(center):
                continue
            ix = min(cols - 1, max(0, round((center[0] - origin_x) / step)))
            iy = min(rows - 1, max(0, round((center[1] - origin_y) / step)))
            urban, vegetation, industrial = channels[iy, ix] / 255.0
            score = float(vegetation * 0.72 + urban * 0.15 + industrial * 0.25)
            # 低密度郊区也必须有纸模层次；仅留少量连续底色作为呼吸区。
            score += float(seed % 100) / 450.0
            if score < 0.065 or seed % 7 == 0:
                continue
            candidates.append((score, cell_x, cell_y, center, urban, vegetation, industrial))
    candidates.sort(reverse=True)

    output = {f"relief_{prefix}_{tier}": [] for prefix in PREFIXES for tier in ("base", "middle", "inner")}
    accepted = 0
    for _score, cell_x, cell_y, center, urban, vegetation, industrial in candidates:
        if accepted >= MAX_PLATES:
            break
        if any(math.dist(center, point) < 850.0 for point in OPERATIONAL_WATER_REJECT_POINTS):
            continue
        polygon = []
        for attempt in range(6):
            candidate = irregular_plate(center, cell_x, cell_y, 0.84 ** attempt)
            box = bounds(candidate)
            safe = not crosses_water_boundary(candidate)
            y = box[1]
            while safe and y <= box[3]:
                x = box[0]
                while x <= box[2]:
                    point = (x, y)
                    if point_in_polygon(point, candidate):
                        for ox, oy in ((0.0, 0.0), (SAFE_SAMPLE_PX, 0.0),
                                       (-SAFE_SAMPLE_PX, 0.0), (0.0, SAFE_SAMPLE_PX),
                                       (0.0, -SAFE_SAMPLE_PX)):
                            if not is_land((x + ox, y + oy)):
                                safe = False
                                break
                    x += SAFE_SAMPLE_PX
                y += SAFE_SAMPLE_PX
            vertex_safety = all(
                is_land((point[0] + ox, point[1] + oy))
                for point in candidate
                for ox, oy in ((0.0, 0.0), (8.0, 0.0), (-8.0, 0.0),
                               (0.0, 8.0), (0.0, -8.0))
            )
            if safe and vertex_safety:
                polygon = candidate
                break
        if not polygon:
            continue
        seed = stable_hash(cell_x, cell_y, 73)
        if industrial >= vegetation * 0.82 and industrial >= urban * 0.55:
            prefix = "taupe"
        elif vegetation >= urban * 0.60:
            prefix = "green"
        else:
            prefix = "gray"
        if seed % 9 == 0:
            prefix = "taupe"
        elif seed % 7 == 0:
            prefix = "gray"
        output[f"relief_{prefix}_base"].append(flatten(polygon))
        offset_seed = stable_hash(cell_x, cell_y, 97)
        offset = (
            float(offset_seed % 61) - 30.0,
            float((offset_seed // 61) % 61) - 30.0,
        )
        output[f"relief_{prefix}_middle"].append(flatten(
            scale_polygon(polygon, 0.72, offset)))
        output[f"relief_{prefix}_inner"].append(flatten(
            scale_polygon(polygon, 0.43, (-offset[0] * 0.45, -offset[1] * 0.45))))
        accepted += 1

    if accepted < 60:
        raise ValueError(f"only {accepted} context plates were accepted")
    for key, polygons in output.items():
        preview[key] = polygons
    PREVIEW_PATH.write_text(
        json.dumps(preview, ensure_ascii=False, separators=(",", ":")), encoding="utf-8"
    )
    report = {key: len(value) for key, value in output.items()}
    report["plates"] = accepted
    print(json.dumps(report, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
