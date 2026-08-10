#!/usr/bin/env python3
"""Bake one 4 km detail tile from an Overpass JSON export.

The output contains only vector triangles and polylines. It is a debug preview
resource, not gameplay geography and not a rasterized derivative of the PNG.

The historical defaults still bake the Yokohama gold slice. ``--rect`` and
``--tile-id`` let the same proven pipeline bake adjacent tiles without
forking the style or geometry rules.
"""

from __future__ import annotations

import argparse
import json
import math
from collections import Counter, defaultdict
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
DEFAULT_INPUT = ROOT / "tmp" / "map_visual_qa" / "yokohama_gold_raw.json"
DEFAULT_OUTPUT = ROOT / "resources" / "maps" / "yokohama_gold_slice_preview.json"
LAT_CENTER = 35.44
LON_CENTER = 139.76
METERS_PER_LAT = 111000.0
METERS_PER_LON = 90434.27326522839
PX_PER_METER = 0.5
GOLD_RECT = (-6300.0, -1700.0, -4300.0, 300.0)


def parse_rect(value: str) -> tuple[float, float, float, float]:
    values = tuple(float(item.strip()) for item in value.split(","))
    if len(values) != 4:
        raise argparse.ArgumentTypeError("rect must be min_x,min_y,max_x,max_y")
    if values[2] <= values[0] or values[3] <= values[1]:
        raise argparse.ArgumentTypeError("rect max values must exceed min values")
    return values


def world_point(item: dict) -> tuple[float, float]:
    return (
        (float(item["lon"]) - LON_CENTER) * METERS_PER_LON * PX_PER_METER,
        -(float(item["lat"]) - LAT_CENTER) * METERS_PER_LAT * PX_PER_METER,
    )


def signed_area(points: list[tuple[float, float]]) -> float:
    return 0.5 * sum(
        points[index][0] * points[(index + 1) % len(points)][1]
        - points[(index + 1) % len(points)][0] * points[index][1]
        for index in range(len(points))
    )


def clean_ring(geometry: list[dict]) -> list[tuple[float, float]]:
    points = [world_point(item) for item in geometry]
    if len(points) > 1 and math.dist(points[0], points[-1]) < 0.01:
        points.pop()
    clean: list[tuple[float, float]] = []
    for point in points:
        if not clean or math.dist(point, clean[-1]) >= 0.01:
            clean.append(point)
    changed = True
    while changed and len(clean) > 3:
        changed = False
        for index in range(len(clean)):
            previous = clean[index - 1]
            current = clean[index]
            following = clean[(index + 1) % len(clean)]
            cross = (
                (current[0] - previous[0]) * (following[1] - current[1])
                - (current[1] - previous[1]) * (following[0] - current[0])
            )
            if abs(cross) < 0.001:
                del clean[index]
                changed = True
                break
    if signed_area(clean) < 0.0:
        clean.reverse()
    return clean


def point_in_triangle(point, a, b, c) -> bool:
    def side(p1, p2, p3):
        return (p1[0] - p3[0]) * (p2[1] - p3[1]) - (p2[0] - p3[0]) * (p1[1] - p3[1])

    d1 = side(point, a, b)
    d2 = side(point, b, c)
    d3 = side(point, c, a)
    has_negative = d1 < -0.0001 or d2 < -0.0001 or d3 < -0.0001
    has_positive = d1 > 0.0001 or d2 > 0.0001 or d3 > 0.0001
    return not (has_negative and has_positive)


def triangulate(points: list[tuple[float, float]]) -> list[tuple[float, float]]:
    if len(points) < 3:
        return []
    remaining = list(range(len(points)))
    triangles: list[tuple[float, float]] = []
    guard = len(points) * len(points)
    while len(remaining) > 3 and guard > 0:
        guard -= 1
        ear_found = False
        for offset, current_index in enumerate(remaining):
            previous_index = remaining[offset - 1]
            next_index = remaining[(offset + 1) % len(remaining)]
            a, b, c = points[previous_index], points[current_index], points[next_index]
            cross = (b[0] - a[0]) * (c[1] - b[1]) - (b[1] - a[1]) * (c[0] - b[0])
            if cross <= 0.0001:
                continue
            if any(
                point_in_triangle(points[index], a, b, c)
                for index in remaining
                if index not in (previous_index, current_index, next_index)
            ):
                continue
            triangles.extend((a, b, c))
            del remaining[offset]
            ear_found = True
            break
        if not ear_found:
            return []
    if len(remaining) == 3:
        triangles.extend(points[index] for index in remaining)
    return triangles


def intersects_rect(
    points: list[tuple[float, float]],
    detail_rect: tuple[float, float, float, float],
) -> bool:
    if not points:
        return False
    min_x = min(point[0] for point in points)
    max_x = max(point[0] for point in points)
    min_y = min(point[1] for point in points)
    max_y = max(point[1] for point in points)
    return not (
        max_x < detail_rect[0]
        or min_x > detail_rect[2]
        or max_y < detail_rect[1]
        or min_y > detail_rect[3]
    )


def flatten(points: list[tuple[float, float]]) -> list[float]:
    values = []
    for x, y in points:
        values.extend((round(x, 2), round(y, 2)))
    return values


def polygon_kind(tags: dict) -> str | None:
    landuse = tags.get("landuse", "")
    leisure = tags.get("leisure", "")
    amenity = tags.get("amenity", "")
    natural = tags.get("natural", "")
    if natural == "water":
        return "water"
    if landuse in {"forest", "farmland", "grass", "meadow", "orchard"}:
        return landuse
    if landuse in {"industrial", "commercial", "retail", "railway", "brownfield", "construction"}:
        return "industrial"
    if landuse == "residential":
        return "residential"
    if leisure in {"park", "garden", "sports_centre", "pitch"}:
        return "park"
    if amenity in {"parking", "school", "university", "hospital"}:
        return "parking" if amenity == "parking" else "civic"
    return None


def append_polygon(
    triangle_layers,
    counts,
    kind: str,
    geometry: list[dict],
    detail_rect: tuple[float, float, float, float],
) -> None:
    ring = clean_ring(geometry)
    if len(ring) < 3 or not intersects_rect(ring, detail_rect):
        return
    triangles = triangulate(ring)
    if not triangles:
        counts[f"failed_{kind}"] += 1
        return
    triangle_layers[kind].extend(flatten(triangles))
    counts[kind] += 1


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", type=Path, default=DEFAULT_INPUT)
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    parser.add_argument("--rect", type=parse_rect, default=GOLD_RECT)
    parser.add_argument("--tile-id", default="yokohama_gold")
    args = parser.parse_args()
    detail_rect = args.rect

    source = json.loads(args.input.read_text(encoding="utf-8"))
    triangle_layers: dict[str, list[float]] = defaultdict(list)
    line_layers: dict[str, list[list[float]]] = defaultdict(list)
    counts: Counter = Counter()

    for element in source.get("elements", []):
        tags = element.get("tags", {})
        geometries: list[list[dict]] = []
        if element.get("type") == "way" and element.get("geometry"):
            geometries.append(element["geometry"])
        elif element.get("type") == "relation":
            geometries.extend(
                member["geometry"]
                for member in element.get("members", [])
                if member.get("role", "") == "outer" and member.get("geometry")
            )

        if tags.get("building") and element.get("type") == "way":
            ring = clean_ring(element.get("geometry", []))
            if len(ring) >= 3 and intersects_rect(ring, detail_rect):
                area = abs(signed_area(ring))
                kind = "building_small" if area < 35.0 else ("building_medium" if area < 180.0 else "building_large")
                triangles = triangulate(ring)
                if triangles:
                    triangle_layers[kind].extend(flatten(triangles))
                    line_layers[f"{kind}_outline"].append(flatten(ring + [ring[0]]))
                    counts[kind] += 1
                else:
                    counts["failed_building"] += 1

        polygon_layer = polygon_kind(tags)
        if polygon_layer:
            for geometry in geometries:
                append_polygon(triangle_layers, counts, polygon_layer, geometry, detail_rect)

        line_kind = None
        if tags.get("railway") in {"rail", "subway", "light_rail", "tram", "disused", "abandoned"}:
            line_kind = "rail"
        elif tags.get("waterway") in {"river", "stream", "drain", "canal", "ditch"}:
            line_kind = "waterway"
        elif tags.get("man_made") in {"pier", "breakwater", "groyne"}:
            line_kind = "port"
        if line_kind:
            for geometry in geometries:
                points = [world_point(item) for item in geometry]
                if len(points) >= 2 and intersects_rect(points, detail_rect):
                    line_layers[line_kind].append(flatten(points))
                    counts[line_kind] += 1

    payload = {
        "schema_version": 1,
        "source": "OpenStreetMap Overpass vector data",
        "source_file": args.input.name,
        "license": "ODbL 1.0",
        "tile_id": args.tile_id,
        "detail_rect": list(detail_rect),
        # Compatibility for the original gold-slice consumer during migration.
        "gold_rect": list(detail_rect),
        "triangles": dict(sorted(triangle_layers.items())),
        "lines": dict(sorted(line_layers.items())),
        "counts": dict(sorted(counts.items())),
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(payload, separators=(",", ":")), encoding="utf-8")
    print(json.dumps({"output": str(args.output), "bytes": args.output.stat().st_size, "counts": payload["counts"]}, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
