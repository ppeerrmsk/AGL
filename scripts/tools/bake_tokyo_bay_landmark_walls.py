#!/usr/bin/env python3
"""Bake OSM-height-backed large-building wall triangles into per-tile AGLW sidecars."""

from __future__ import annotations

import argparse
import gzip
import json
import math
import re
import struct
from collections import Counter, defaultdict
from dataclasses import dataclass
from pathlib import Path

import osmium  # type: ignore  # build-only wheel


ROOT = Path(__file__).resolve().parents[2]
DEFAULT_PBF = ROOT / "tmp" / "full_map_detail" / "kanto-latest.osm.pbf"
MANIFEST = ROOT / "resources" / "maps" / "tokyo_bay_detail_tiles_full.json"
OUTPUT_DIR = ROOT / "resources" / "maps" / "detail_landmark_walls"
OUTPUT_MANIFEST = ROOT / "resources" / "maps" / "tokyo_bay_landmark_walls.json"

LAT_CENTER = 35.44
LON_CENTER = 139.76
METERS_PER_LAT = 111000.0
METERS_PER_LON = 90434.27326522839
PX_PER_METER = 0.5
QUANTIZATION = 4.0
MIN_HEIGHT_M = 12.0
MIN_AREA_PX2 = 180.0
MAX_WALL_TRIANGLES_PER_TILE = 50_000
MAX_TOTAL_GZIP_BYTES = 16 * 1024 * 1024
MAX_RECORDED_HEIGHT_M = 640.0


def world_point(lon: float, lat: float) -> tuple[float, float]:
    return (
        (lon - LON_CENTER) * METERS_PER_LON * PX_PER_METER,
        -(lat - LAT_CENTER) * METERS_PER_LAT * PX_PER_METER,
    )


def polygon_area(points: list[tuple[float, float]]) -> float:
    return abs(sum(
        points[index][0] * points[(index + 1) % len(points)][1]
        - points[(index + 1) % len(points)][0] * points[index][1]
        for index in range(len(points))
    )) * 0.5


def signed_polygon_area(points: list[tuple[float, float]]) -> float:
    return sum(
        points[index][0] * points[(index + 1) % len(points)][1]
        - points[(index + 1) % len(points)][0] * points[index][1]
        for index in range(len(points))
    ) * 0.5


def triangle_cross(
    a: tuple[float, float], b: tuple[float, float], c: tuple[float, float]
) -> float:
    return (b[0] - a[0]) * (c[1] - a[1]) - (b[1] - a[1]) * (c[0] - a[0])


def point_in_triangle(
    point: tuple[float, float], a: tuple[float, float],
    b: tuple[float, float], c: tuple[float, float]
) -> bool:
    c1 = triangle_cross(a, b, point)
    c2 = triangle_cross(b, c, point)
    c3 = triangle_cross(c, a, point)
    return (c1 >= -1e-6 and c2 >= -1e-6 and c3 >= -1e-6) or (
        c1 <= 1e-6 and c2 <= 1e-6 and c3 <= 1e-6
    )


def triangulate_polygon(points: list[tuple[float, float]]) -> list[tuple[int, int, int]]:
    """Ear-clip a simple OSM way. Invalid/self-intersecting roofs fail closed."""
    if len(points) < 3:
        return []
    indices = list(range(len(points)))
    ccw = signed_polygon_area(points) > 0.0
    triangles: list[tuple[int, int, int]] = []
    guard = len(indices) * len(indices)
    while len(indices) > 3 and guard > 0:
        guard -= 1
        ear_found = False
        for cursor in range(len(indices)):
            previous = indices[(cursor - 1) % len(indices)]
            current = indices[cursor]
            following = indices[(cursor + 1) % len(indices)]
            cross = triangle_cross(points[previous], points[current], points[following])
            if (ccw and cross <= 1e-6) or (not ccw and cross >= -1e-6):
                continue
            if any(
                candidate not in (previous, current, following)
                and point_in_triangle(
                    points[candidate], points[previous], points[current], points[following]
                )
                for candidate in indices
            ):
                continue
            triangles.append((previous, current, following))
            del indices[cursor]
            ear_found = True
            break
        if not ear_found:
            return []
    if len(indices) == 3:
        triangles.append((indices[0], indices[1], indices[2]))
    return triangles


def parse_measure(value: str, feet: bool = False) -> float:
    values = [float(match) for match in re.findall(r"\d+(?:\.\d+)?", value)]
    if not values:
        return 0.0
    result = max(values)
    if feet or "ft" in value.lower() or "'" in value:
        result *= 0.3048
    return result


def building_height(tags: dict[str, str]) -> tuple[float, str]:
    if tags.get("height"):
        return parse_measure(tags["height"]), "height"
    if tags.get("building:levels"):
        return parse_measure(tags["building:levels"]) * 3.2, "levels"
    return 0.0, ""


def wall_projection(height_m: float) -> tuple[float, float]:
    """Return a conservative static pseudo-height; only true high-rises break the city carpet."""
    projection_y = max(6.0, min(52.0, height_m * 0.5))
    if height_m >= 80.0:
        projection_y = min(122.0, 52.0 + (height_m - 80.0) * 0.28)
    return projection_y * 0.62, projection_y


@dataclass
class WallRecord:
    osm_id: int
    height_m: float
    points: list[tuple[float, float]]


class WallCollector(osmium.SimpleHandler):
    def __init__(self, manifest: dict):
        super().__init__()
        self.tiles = manifest["tiles"]
        self.grid = manifest["grid"]
        self.origin_x, self.origin_y = (float(value) for value in self.grid["origin"])
        self.tile_size = float(self.grid["tile_size"])
        self.columns = int(self.grid["columns"])
        self.rows = int(self.grid["rows"])
        self.tile_ids = {tile["id"] for tile in self.tiles}
        self.records: dict[str, list[WallRecord]] = defaultdict(list)
        self.counts: Counter = Counter()

    def way(self, way) -> None:
        tags = {tag.k: tag.v for tag in way.tags}
        if not tags.get("building"):
            return
        height_m, source = building_height(tags)
        if height_m < MIN_HEIGHT_M:
            return
        try:
            points = [world_point(node.lon, node.lat) for node in way.nodes]
        except osmium.InvalidLocationError:
            return
        if len(points) < 4 or math.dist(points[0], points[-1]) > 0.01:
            return
        points = points[:-1]
        if len(points) < 3 or polygon_area(points) < MIN_AREA_PX2:
            return
        record = WallRecord(int(way.id), min(height_m, MAX_RECORDED_HEIGHT_M), points)
        projection_x, projection_y = wall_projection(record.height_m)
        # A tall wall may extend into the tile below/right. Assign it to every touched
        # cache tile so the independently baked textures cannot clip at a seam.
        min_x = min(point[0] for point in points)
        min_y = min(point[1] for point in points)
        max_x = max(point[0] for point in points) + projection_x
        max_y = max(point[1] for point in points) + projection_y
        min_column = max(0, int(math.floor((min_x - self.origin_x) / self.tile_size)))
        max_column = min(self.columns - 1, int(math.floor((max_x - self.origin_x) / self.tile_size)))
        min_row = max(0, int(math.floor((min_y - self.origin_y) / self.tile_size)))
        max_row = min(self.rows - 1, int(math.floor((max_y - self.origin_y) / self.tile_size)))
        if min_column > max_column or min_row > max_row:
            return
        touched = 0
        for row in range(min_row, max_row + 1):
            for column in range(min_column, max_column + 1):
                tile_id = f"detail_{column:02d}_{row:02d}"
                if tile_id in self.tile_ids:
                    self.records[tile_id].append(record)
                    touched += 1
        if touched:
            self.counts[f"source_{source}"] += 1
            self.counts["unique_buildings"] += 1
            self.counts["tile_references"] += touched
            if record.height_m >= 80.0:
                self.counts["highrise_buildings"] += 1
                self.counts["highrise_tile_references"] += touched


def wall_color(a: tuple[float, float], b: tuple[float, float], height_m: float) -> tuple[int, int, int, int]:
    dx, dy = b[0] - a[0], b[1] - a[1]
    length = max(math.hypot(dx, dy), 0.001)
    normal_x, normal_y = -dy / length, dx / length
    light = max(-1.0, min(1.0, normal_x * -0.55 + normal_y * -0.83))
    value = round(70 + light * 10 - min(height_m, 120.0) / 30.0)
    alpha = 226 if height_m >= 80.0 else 188
    return max(48, value - 4), max(54, value + 2), max(55, value + 3), alpha


def append_record(
    output: list[tuple[float, float, tuple[int, int, int, int]]], record: WallRecord
) -> tuple[int, int]:
    start_count = len(output)
    projection = wall_projection(record.height_m)
    points = record.points
    for index, a in enumerate(points):
        b = points[(index + 1) % len(points)]
        if math.dist(a, b) < 0.2:
            continue
        color = wall_color(a, b, record.height_m)
        a2 = (a[0] + projection[0], a[1] + projection[1])
        b2 = (b[0] + projection[0], b[1] + projection[1])
        for point in (a, b, b2, a, b2, a2):
            output.append((point[0], point[1], color))
    wall_triangles = (len(output) - start_count) // 3
    roof_triangles = 0
    if record.height_m >= 80.0:
        roof_casing_color = (77, 89, 89, 236)
        roof_color = (161, 157, 143, 240)
        roof_indices = triangulate_polygon(points)
        center = (
            sum(point[0] for point in points) / len(points),
            sum(point[1] for point in points) / len(points),
        )
        radius = max(math.dist(center, point) for point in points)
        inset_scale = max(0.78, 1.0 - 1.6 / max(radius, 0.01))
        inset_points = [(
            center[0] + (point[0] - center[0]) * inset_scale,
            center[1] + (point[1] - center[1]) * inset_scale,
        ) for point in points]
        # Full-size dark cap first, then a slightly inset roof. This produces the
        # approved dark roof rim without another runtime packet or draw call.
        for a_index, b_index, c_index in roof_indices:
            for point in (points[a_index], points[b_index], points[c_index]):
                output.append((
                    point[0] + projection[0], point[1] + projection[1], roof_casing_color
                ))
            roof_triangles += 1
        for a_index, b_index, c_index in roof_indices:
            for point in (inset_points[a_index], inset_points[b_index], inset_points[c_index]):
                output.append((point[0] + projection[0], point[1] + projection[1], roof_color))
            roof_triangles += 1
    return wall_triangles, roof_triangles


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--pbf", type=Path, default=DEFAULT_PBF)
    args = parser.parse_args()
    manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
    collector = WallCollector(manifest)
    collector.apply_file(str(args.pbf), locations=True)

    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    report_tiles = []
    total_gzip = 0
    total_triangles = 0
    max_tile_triangles = 0
    total_wall_triangles = 0
    total_roof_triangles = 0
    for tile in manifest["tiles"]:
        tile_id = tile["id"]
        records = sorted(
            collector.records.get(tile_id, []),
            key=lambda record: (record.height_m, record.points[0][1], record.osm_id),
        )
        vertices: list[tuple[float, float, tuple[int, int, int, int]]] = []
        tile_wall_triangles = 0
        tile_roof_triangles = 0
        for record in records:
            wall_triangles, roof_triangles = append_record(vertices, record)
            tile_wall_triangles += wall_triangles
            tile_roof_triangles += roof_triangles
        triangle_count = len(vertices) // 3
        if triangle_count > MAX_WALL_TRIANGLES_PER_TILE:
            raise ValueError(f"{tile_id} wall triangles {triangle_count} exceed budget")
        if not vertices:
            continue
        origin_x, origin_y, _width, _height = (float(value) for value in tile["rect"])
        payload = bytearray(b"AGLW")
        payload.extend(struct.pack("<HHfffI", 1, 0, origin_x, origin_y, QUANTIZATION, len(vertices)))
        for x, y, color in vertices:
            payload.extend(struct.pack(
                "<iiBBBB",
                round((x - origin_x) * QUANTIZATION),
                round((y - origin_y) * QUANTIZATION),
                *color,
            ))
        path = OUTPUT_DIR / f"{tile_id}.aglw.gz"
        compressed = gzip.compress(bytes(payload), compresslevel=9, mtime=0)
        path.write_bytes(compressed)
        total_gzip += len(compressed)
        total_triangles += triangle_count
        total_wall_triangles += tile_wall_triangles
        total_roof_triangles += tile_roof_triangles
        max_tile_triangles = max(max_tile_triangles, triangle_count)
        report_tiles.append({
            "id": tile_id,
            "data_path": f"res://resources/maps/detail_landmark_walls/{path.name}",
            "buildings": len(records),
            "triangles": triangle_count,
            "wall_triangles": tile_wall_triangles,
            "roof_triangles": tile_roof_triangles,
            "gzip_bytes": len(compressed),
        })

    if total_gzip > MAX_TOTAL_GZIP_BYTES:
        raise ValueError(f"AGLW total gzip {total_gzip} exceeds budget")
    report = {
        "schema_version": 1,
        "format": "AGLW gzip v1",
        "source": "OpenStreetMap Geofabrik Kanto PBF height/building:levels",
        "counts": dict(sorted(collector.counts.items())),
        "tile_count": len(report_tiles),
        "triangles": total_triangles,
        "wall_triangles": total_wall_triangles,
        "roof_triangles": total_roof_triangles,
        "max_tile_triangles": max_tile_triangles,
        "gzip_bytes": total_gzip,
        "tiles": report_tiles,
    }
    OUTPUT_MANIFEST.write_text(json.dumps(report, indent=2), encoding="utf-8")
    print(json.dumps({key: value for key, value in report.items() if key != "tiles"}, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
