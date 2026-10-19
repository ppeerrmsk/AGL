from __future__ import annotations

import json
import math
import re
import sys
from collections import Counter
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tmp" / "python-packages"))
import osmium  # type: ignore


PBF = ROOT / "tmp" / "full_map_detail" / "kanto-latest.osm.pbf"
OUTPUT = ROOT / "resources" / "maps" / "tokyo_volume_preview" / "r1_tokyo_downtown.json"

LAT_CENTER = 35.44
LON_CENTER = 139.76
METERS_PER_LAT = 111000.0
METERS_PER_LON = 90434.27326522839
PX_PER_METER = 0.5

CENTER = (300.0, -13300.0)
SIZE = (1400.0, 900.0)
MARGIN = 120.0
MIN_X = CENTER[0] - SIZE[0] * 0.5
MAX_X = CENTER[0] + SIZE[0] * 0.5
MIN_Y = CENTER[1] - SIZE[1] * 0.5
MAX_Y = CENTER[1] + SIZE[1] * 0.5

ROAD_WIDTHS = {
    "motorway": 7.0,
    "motorway_link": 5.0,
    "trunk": 6.0,
    "trunk_link": 4.5,
    "primary": 5.0,
    "primary_link": 3.8,
    "secondary": 3.8,
    "secondary_link": 3.0,
    "tertiary": 2.8,
    "tertiary_link": 2.4,
    "residential": 1.5,
    "living_street": 1.3,
    "unclassified": 1.25,
    "service": 0.8,
}


def world_point(lon: float, lat: float) -> tuple[float, float]:
    return (
        (lon - LON_CENTER) * METERS_PER_LON * PX_PER_METER,
        -(lat - LAT_CENTER) * METERS_PER_LAT * PX_PER_METER,
    )


def signed_area(points: list[tuple[float, float]]) -> float:
    return sum(
        points[i][0] * points[(i + 1) % len(points)][1]
        - points[(i + 1) % len(points)][0] * points[i][1]
        for i in range(len(points))
    ) * 0.5


def centroid(points: list[tuple[float, float]]) -> tuple[float, float]:
    area6 = signed_area(points) * 6.0
    if abs(area6) < 1e-6:
        return (
            sum(point[0] for point in points) / len(points),
            sum(point[1] for point in points) / len(points),
        )
    cx = 0.0
    cy = 0.0
    for i, point in enumerate(points):
        following = points[(i + 1) % len(points)]
        cross = point[0] * following[1] - following[0] * point[1]
        cx += (point[0] + following[0]) * cross
        cy += (point[1] + following[1]) * cross
    return cx / area6, cy / area6


def parse_measure(value: str) -> float:
    values = [float(match) for match in re.findall(r"\d+(?:\.\d+)?", value)]
    if not values:
        return 0.0
    result = max(values)
    if "ft" in value.lower() or "'" in value:
        result *= 0.3048
    return result


def fallback_height(area: float, kind: str) -> float:
    root = math.sqrt(area)
    if kind == "industrial":
        value = min(28.8, max(9.6, 9.6 + 0.05 * root))
    elif area >= 500.0:
        value = min(38.4, max(19.2, 19.2 + 0.075 * root))
    elif area >= 100.0:
        value = min(25.6, max(12.8, 12.8 + 0.055 * root))
    else:
        value = min(12.8, max(6.4, 6.4 + 0.035 * root))
    return round(value / 1.6) * 1.6


def bbox_intersects(points: list[tuple[float, float]], margin: float = 0.0) -> bool:
    return not (
        max(point[0] for point in points) < MIN_X - margin
        or min(point[0] for point in points) > MAX_X + margin
        or max(point[1] for point in points) < MIN_Y - margin
        or min(point[1] for point in points) > MAX_Y + margin
    )


def perpendicular_distance(point, start, end) -> float:
    dx = end[0] - start[0]
    dy = end[1] - start[1]
    if dx * dx + dy * dy < 1e-9:
        return math.dist(point, start)
    t = max(0.0, min(1.0, ((point[0] - start[0]) * dx + (point[1] - start[1]) * dy) / (dx * dx + dy * dy)))
    return math.dist(point, (start[0] + dx * t, start[1] + dy * t))


def simplify(points: list[tuple[float, float]], tolerance: float) -> list[tuple[float, float]]:
    if len(points) <= 2:
        return points
    distance = 0.0
    index = 0
    for i in range(1, len(points) - 1):
        candidate = perpendicular_distance(points[i], points[0], points[-1])
        if candidate > distance:
            distance = candidate
            index = i
    if distance <= tolerance:
        return [points[0], points[-1]]
    left = simplify(points[: index + 1], tolerance)
    right = simplify(points[index:], tolerance)
    return left[:-1] + right


def round_points(points: list[tuple[float, float]]) -> list[list[float]]:
    return [[round(x, 2), round(y, 2)] for x, y in points]


class PreviewCollector(osmium.SimpleHandler):
    def __init__(self) -> None:
        super().__init__()
        self.buildings: list[dict] = []
        self.roads: list[dict] = []
        self.rails: list[dict] = []
        self.counts: Counter[str] = Counter()

    def way(self, way) -> None:
        tags = {tag.k: tag.v for tag in way.tags}
        building = tags.get("building", "")
        highway = tags.get("highway", "")
        railway = tags.get("railway", "")
        if not building and highway not in ROAD_WIDTHS and railway not in {"rail", "light_rail", "subway"}:
            return
        try:
            points = [world_point(node.lon, node.lat) for node in way.nodes]
        except osmium.InvalidLocationError:
            return
        if len(points) < 2 or not bbox_intersects(points, MARGIN):
            return
        if building:
            if len(points) < 4 or math.dist(points[0], points[-1]) > 0.05:
                return
            points = points[:-1]
            area = abs(signed_area(points))
            if len(points) < 3 or area < 2.0:
                return
            center = centroid(points)
            if not (MIN_X - MARGIN <= center[0] <= MAX_X + MARGIN and MIN_Y - MARGIN <= center[1] <= MAX_Y + MARGIN):
                return
            source = "fallback"
            height = 0.0
            if tags.get("height"):
                height = parse_measure(tags["height"])
                source = "height"
            elif tags.get("building:levels"):
                height = parse_measure(tags["building:levels"]) * 3.2
                source = "levels"
            kind = "industrial" if building in {"industrial", "warehouse", "factory", "hangar"} else "urban"
            if height <= 0.0:
                height = fallback_height(area, kind)
            height = min(640.0, max(3.2, height))
            detailed = source != "fallback"
            tolerance = 0.08 if detailed else (0.22 if area < 120.0 else 0.14)
            closed = points + [points[0]]
            simplified = simplify(closed, tolerance)[:-1]
            if len(simplified) < 3:
                return
            record = {
                "id": f"w{way.id}",
                "points": round_points(simplified),
                "height_m": round(height, 2),
                "height_source": source,
                "area_px2": round(area, 2),
                "kind": kind,
                "building": building,
                "roof_shape": tags.get("roof:shape", "flat"),
                "roof_material": tags.get("roof:material", ""),
                "levels": tags.get("building:levels", ""),
            }
            self.buildings.append(record)
            self.counts[f"building_{source}"] += 1
            if height >= 80.0:
                self.counts["highrise"] += 1
            return
        path = simplify(points, 0.18 if highway else 0.10)
        if len(path) < 2:
            return
        if highway:
            self.roads.append({
                "id": f"w{way.id}",
                "points": round_points(path),
                "class": highway,
                "width_px": ROAD_WIDTHS[highway],
            })
            self.counts[f"road_{highway}"] += 1
        else:
            self.rails.append({
                "id": f"w{way.id}",
                "points": round_points(path),
                "class": railway,
                "width_px": 1.2,
            })
            self.counts[f"rail_{railway}"] += 1


def main() -> None:
    collector = PreviewCollector()
    collector.apply_file(str(PBF), locations=True)
    collector.buildings.sort(key=lambda record: record["id"])
    collector.roads.sort(key=lambda record: record["id"])
    collector.rails.sort(key=lambda record: record["id"])
    payload = {
        "schema_version": 1,
        "source": "OpenStreetMap Geofabrik Kanto PBF; isolated Tokyo volume preview",
        "center": list(CENTER),
        "rect": [MIN_X, MIN_Y, SIZE[0], SIZE[1]],
        "world_scale": "1 m = 0.5 world px",
        "counts": dict(sorted(collector.counts.items())),
        "buildings": collector.buildings,
        "roads": collector.roads,
        "rails": collector.rails,
    }
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT.write_text(json.dumps(payload, separators=(",", ":"), ensure_ascii=False) + "\n", encoding="utf-8")
    print(json.dumps({"output": str(OUTPUT), "bytes": OUTPUT.stat().st_size,
        "buildings": len(collector.buildings), "roads": len(collector.roads),
        "rails": len(collector.rails), "counts": payload["counts"]}, indent=2))


if __name__ == "__main__":
    main()
