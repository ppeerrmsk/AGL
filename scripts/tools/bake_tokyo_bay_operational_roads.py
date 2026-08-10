#!/usr/bin/env python3
"""Bake a compact, deterministic mid-distance street skeleton from Kanto OSM.

The packet intentionally summarizes neighbourhood structure. It keeps a small
quota of the longest local roads per 2 km map tile, simplifies their geometry,
and leaves individual service alleys and building footprints to detail tiles.
"""

from __future__ import annotations

import argparse
import gzip
import json
import math
import struct
import sys
from collections import Counter, defaultdict
from dataclasses import dataclass
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
import osmium  # type: ignore  # build-only wheel


DEFAULT_PBF = ROOT / "tmp" / "full_map_detail" / "kanto-latest.osm.pbf"
MANIFEST = ROOT / "tmp" / "full_map_detail" / "build_manifest.json"
OUTPUT = ROOT / "resources" / "maps" / "tokyo_bay_operational_roads.agor.gz"

LAT_CENTER = 35.44
LON_CENTER = 139.76
METERS_PER_LAT = 111000.0
METERS_PER_LON = 90434.27326522839
PX_PER_METER = 0.5
QUANTIZATION = 4.0

ROAD_RULES = {
    # quota is per 2 km runtime tile. World-space tolerances are 2 m/px.
    "unclassified": {"quota": 45, "min_length": 60.0, "tolerance": 5.0},
    "residential": {"quota": 75, "min_length": 80.0, "tolerance": 7.0},
    "living_street": {"quota": 3, "min_length": 80.0, "tolerance": 7.0},
    "service": {"quota": 4, "min_length": 120.0, "tolerance": 9.0},
}


def world_point(lon: float, lat: float) -> tuple[float, float]:
    return (
        (lon - LON_CENTER) * METERS_PER_LON * PX_PER_METER,
        -(lat - LAT_CENTER) * METERS_PER_LAT * PX_PER_METER,
    )


def line_length(points: list[tuple[float, float]]) -> float:
    return sum(math.dist(a, b) for a, b in zip(points, points[1:]))


def point_segment_distance(point, start, end) -> float:
    dx = end[0] - start[0]
    dy = end[1] - start[1]
    length_sq = dx * dx + dy * dy
    if length_sq <= 1.0e-8:
        return math.dist(point, start)
    t = max(0.0, min(1.0, ((point[0] - start[0]) * dx + (point[1] - start[1]) * dy) / length_sq))
    projection = (start[0] + dx * t, start[1] + dy * t)
    return math.dist(point, projection)


def simplify(points: list[tuple[float, float]], tolerance: float) -> list[tuple[float, float]]:
    if len(points) <= 2:
        return points
    keep = {0, len(points) - 1}
    stack = [(0, len(points) - 1)]
    while stack:
        start_index, end_index = stack.pop()
        farthest_index = -1
        farthest_distance = tolerance
        for index in range(start_index + 1, end_index):
            distance = point_segment_distance(points[index], points[start_index], points[end_index])
            if distance > farthest_distance:
                farthest_distance = distance
                farthest_index = index
        if farthest_index >= 0:
            keep.add(farthest_index)
            stack.append((start_index, farthest_index))
            stack.append((farthest_index, end_index))
    return [point for index, point in enumerate(points) if index in keep]


@dataclass
class Road:
    osm_id: int
    kind: str
    length: float
    points: list[tuple[float, float]]


class RoadCollector(osmium.SimpleHandler):
    def __init__(self, grid: dict):
        super().__init__()
        self.origin_x, self.origin_y = (float(value) for value in grid["origin"])
        self.tile_size = float(grid["tile_size"])
        self.columns = int(grid["columns"])
        self.rows = int(grid["rows"])
        self.end_x = self.origin_x + self.columns * self.tile_size
        self.end_y = self.origin_y + self.rows * self.tile_size
        self.roads: dict[tuple[int, int, str], list[Road]] = defaultdict(list)
        self.counts: Counter = Counter()

    def way(self, way) -> None:
        tags = {tag.k: tag.v for tag in way.tags}
        kind = tags.get("highway", "")
        if kind not in ROAD_RULES or tags.get("area") == "yes":
            return
        if tags.get("access") in {"private", "no"}:
            return
        try:
            points = [world_point(node.lon, node.lat) for node in way.nodes]
        except osmium.InvalidLocationError:
            return
        if len(points) < 2:
            return
        min_x = min(point[0] for point in points)
        min_y = min(point[1] for point in points)
        max_x = max(point[0] for point in points)
        max_y = max(point[1] for point in points)
        if max_x < self.origin_x or min_x >= self.end_x or max_y < self.origin_y or min_y >= self.end_y:
            return
        length = line_length(points)
        rule = ROAD_RULES[kind]
        if length < float(rule["min_length"]):
            return
        midpoint = points[len(points) // 2]
        column = int(math.floor((midpoint[0] - self.origin_x) / self.tile_size))
        row = int(math.floor((midpoint[1] - self.origin_y) / self.tile_size))
        if not (0 <= column < self.columns and 0 <= row < self.rows):
            return
        self.roads[(column, row, kind)].append(Road(int(way.id), kind, length, points))
        self.counts[f"eligible_{kind}"] += 1

    def selected(self) -> list[Road]:
        result: list[Road] = []
        for key in sorted(self.roads):
            kind = key[2]
            quota = int(ROAD_RULES[kind]["quota"])
            # OSM id is the deterministic tie-breaker; no random thinning.
            ranked = sorted(self.roads[key], key=lambda road: (-road.length, road.osm_id))
            result.extend(ranked[:quota])
        return result


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--pbf", type=Path, default=DEFAULT_PBF)
    args = parser.parse_args()
    grid = json.loads(MANIFEST.read_text(encoding="utf-8"))["grid"]
    collector = RoadCollector(grid)
    collector.apply_file(str(args.pbf), locations=True)

    selected = collector.selected()
    simplified: list[Road] = []
    for road in selected:
        points = simplify(road.points, float(ROAD_RULES[road.kind]["tolerance"]))
        if len(points) >= 2:
            simplified.append(Road(road.osm_id, road.kind, road.length, points))

    origin_x, origin_y = (float(value) for value in grid["origin"])
    payload = bytearray(b"AGOR")
    payload.extend(struct.pack("<HHfffI", 1, 0, origin_x, origin_y, QUANTIZATION, len(simplified)))
    point_count = 0
    segment_count = 0
    selected_counts: Counter = Counter()
    for road in simplified:
        if len(road.points) > 65535:
            raise ValueError(f"road {road.osm_id} exceeds packet point limit")
        payload.extend(struct.pack("<H", len(road.points)))
        for x, y in road.points:
            payload.extend(struct.pack(
                "<ii",
                round((x - origin_x) * QUANTIZATION),
                round((y - origin_y) * QUANTIZATION),
            ))
        point_count += len(road.points)
        segment_count += len(road.points) - 1
        selected_counts[road.kind] += 1

    OUTPUT.write_bytes(gzip.compress(bytes(payload), compresslevel=9, mtime=0))
    report = {
        "output": str(OUTPUT),
        "eligible": dict(sorted(collector.counts.items())),
        "selected": dict(sorted(selected_counts.items())),
        "lines": len(simplified),
        "points": point_count,
        "segments": segment_count,
        "triangles": segment_count * 2,
        "uncompressed_bytes": len(payload),
        "gzip_bytes": OUTPUT.stat().st_size,
    }
    print(json.dumps(report, indent=2))
    # V25 neighborhood 只提交 core：每线段 2 三角，省下 casing 预算换取更多真实街巷。
    if len(simplified) > 20000 or segment_count > 60000 or segment_count * 2 > 120000 or OUTPUT.stat().st_size > 8 * 1024 * 1024:
        print("operational road packet exceeds spec budget", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
