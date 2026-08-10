#!/usr/bin/env python3
"""Bake the full Tokyo Bay detail grid from a local Geofabrik PBF.

The accepted Yokohama tile remains the style authority. This tool only expands
the same semantic layers across the 60 km world. It scans the PBF once into
chunked NDJSON spools, then triangulates one 2x2-tile chunk at a time so Python
memory never scales with the whole map.

``osmium`` is intentionally a build-only dependency installed under
``tmp/full_map_detail/pydeps``; no runtime or exported-game dependency is added.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import sys
from collections import Counter, defaultdict
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
TOOLS_DIR = Path(__file__).resolve().parent
PYDEPS = ROOT / "tmp" / "full_map_detail" / "pydeps"
sys.path.insert(0, str(PYDEPS))
sys.path.insert(0, str(TOOLS_DIR))

import osmium  # type: ignore  # build-only wheel

from bake_yokohama_gold_slice import flatten, polygon_kind, signed_area, triangulate


DEFAULT_PBF = ROOT / "tmp" / "full_map_detail" / "kanto-latest.osm.pbf"
BUILD_MANIFEST = ROOT / "tmp" / "full_map_detail" / "build_manifest.json"
SPOOL_DIR = ROOT / "tmp" / "full_map_detail" / "spool"
OUTPUT_DIR = ROOT / "tmp" / "full_map_detail" / "detail_tiles_source"
RUNTIME_MANIFEST = ROOT / "resources" / "maps" / "tokyo_bay_detail_tiles_full.json"

LAT_CENTER = 35.44
LON_CENTER = 139.76
METERS_PER_LAT = 111000.0
METERS_PER_LON = 90434.27326522839
PX_PER_METER = 0.5


def world_point(lon: float, lat: float) -> tuple[float, float]:
    return (
        (lon - LON_CENTER) * METERS_PER_LON * PX_PER_METER,
        -(lat - LAT_CENTER) * METERS_PER_LAT * PX_PER_METER,
    )


def clean_points(points: list[tuple[float, float]], closed: bool) -> list[tuple[float, float]]:
    if closed and len(points) > 1 and math.dist(points[0], points[-1]) < 0.01:
        points.pop()
    clean: list[tuple[float, float]] = []
    for point in points:
        if not clean or math.dist(point, clean[-1]) >= 0.01:
            clean.append(point)
    if closed:
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
        if len(clean) >= 3 and signed_area(clean) < 0.0:
            clean.reverse()
    return clean


def bbox_for(points: list[tuple[float, float]]) -> tuple[float, float, float, float]:
    return (
        min(point[0] for point in points),
        min(point[1] for point in points),
        max(point[0] for point in points),
        max(point[1] for point in points),
    )


class PbfSpooler(osmium.SimpleHandler):
    def __init__(self, manifest: dict, spool_dir: Path):
        super().__init__()
        self.tiles = {
            tile["id"]: tile
            for tile in manifest["tiles"]
        }
        self.chunk_for_tile = {
            tile_id: chunk["id"]
            for chunk in manifest["chunks"]
            for tile_id in chunk["tiles"]
        }
        self.grid = manifest["grid"]
        self.spool_dir = spool_dir
        self.spool_dir.mkdir(parents=True, exist_ok=True)
        self.handles: dict[str, object] = {}
        self.counts: Counter = Counter()

    def close(self) -> None:
        for handle in self.handles.values():
            handle.close()
        self.handles.clear()

    def _overlapping_tiles(self, points) -> list[str]:
        if not points:
            return []
        min_x, min_y, max_x, max_y = bbox_for(points)
        origin_x, origin_y = self.grid["origin"]
        tile_size = float(self.grid["tile_size"])
        min_column = max(0, int(math.floor((min_x - origin_x) / tile_size)))
        max_column = min(int(self.grid["columns"]) - 1, int(math.floor((max_x - origin_x) / tile_size)))
        min_row = max(0, int(math.floor((min_y - origin_y) / tile_size)))
        max_row = min(int(self.grid["rows"]) - 1, int(math.floor((max_y - origin_y) / tile_size)))
        result = []
        for row in range(min_row, max_row + 1):
            for column in range(min_column, max_column + 1):
                tile_id = f"detail_{column:02d}_{row:02d}"
                if tile_id in self.tiles:
                    result.append(tile_id)
        return result

    def _write(self, record: dict, tile_ids: list[str]) -> None:
        grouped: dict[str, list[str]] = defaultdict(list)
        for tile_id in tile_ids:
            grouped[self.chunk_for_tile[tile_id]].append(tile_id)
        for chunk_id, chunk_tiles in grouped.items():
            handle = self.handles.get(chunk_id)
            if handle is None:
                handle = (self.spool_dir / f"{chunk_id}.ndjson").open("w", encoding="utf-8")
                self.handles[chunk_id] = handle
            payload = dict(record)
            payload["tiles"] = chunk_tiles
            handle.write(json.dumps(payload, separators=(",", ":")) + "\n")
        self.counts[record["type"]] += 1

    def way(self, way) -> None:
        tags = {tag.k: tag.v for tag in way.tags}
        is_building = bool(tags.get("building"))
        polygon_layer = polygon_kind(tags)
        line_layer = None
        if tags.get("railway") in {"rail", "subway", "light_rail", "tram", "disused", "abandoned"}:
            line_layer = "rail"
        elif tags.get("waterway") in {"river", "stream", "drain", "canal", "ditch"}:
            line_layer = "waterway"
        elif tags.get("man_made") in {"pier", "breakwater", "groyne"}:
            line_layer = "port"
        if line_layer is None and not is_building and polygon_layer is None:
            return
        try:
            points = clean_points([world_point(node.lon, node.lat) for node in way.nodes], False)
        except osmium.InvalidLocationError:
            return
        if len(points) < 2:
            return
        tile_ids = self._overlapping_tiles(points)
        if not tile_ids:
            return
        is_closed = len(points) >= 3 and math.dist(points[0], points[-1]) < 0.01
        if is_closed and (is_building or polygon_layer is not None):
            ring = clean_points(points, True)
            if len(ring) >= 3:
                if is_building:
                    area_px = abs(signed_area(ring))
                    building_layer = (
                        "building_small" if area_px < 35.0
                        else "building_medium" if area_px < 180.0
                        else "building_large"
                    )
                    self._write({
                        "type": "building",
                        "layer": building_layer,
                        "points": flatten(ring),
                    }, tile_ids)
                if polygon_layer is not None:
                    self._write({
                        "type": "polygon",
                        "layer": polygon_layer,
                        "points": flatten(ring),
                    }, tile_ids)
        if line_layer is not None:
            self._write({"type": "line", "layer": line_layer, "points": flatten(points)}, tile_ids)


def unflatten(values: list[float]) -> list[tuple[float, float]]:
    return list(zip(values[0::2], values[1::2]))


def bake_chunk(chunk: dict, tiles_by_id: dict[str, dict]) -> list[dict]:
    spool_path = SPOOL_DIR / f"{chunk['id']}.ndjson"
    payloads = {
        tile_id: {
            "triangles": defaultdict(list),
            "lines": defaultdict(list),
            "counts": Counter(),
        }
        for tile_id in chunk["tiles"]
    }
    if spool_path.exists():
        with spool_path.open(encoding="utf-8") as source:
            for line in source:
                record = json.loads(line)
                points = unflatten(record["points"])
                record_type = record["type"]
                layer = record["layer"]
                triangles = triangulate(points) if record_type in {"building", "polygon"} else []
                for tile_id in record["tiles"]:
                    target = payloads[tile_id]
                    if record_type == "building":
                        if triangles:
                            target["triangles"][layer].extend(flatten(triangles))
                            target["lines"][f"{layer}_outline"].append(flatten(points + [points[0]]))
                            target["counts"][layer] += 1
                        else:
                            target["counts"]["failed_building"] += 1
                    elif record_type == "polygon":
                        if triangles:
                            target["triangles"][layer].extend(flatten(triangles))
                            target["counts"][layer] += 1
                        else:
                            target["counts"][f"failed_{layer}"] += 1
                    else:
                        target["lines"][layer].append(record["points"])
                        target["counts"][layer] += 1

    outputs = []
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    for tile_id, target in payloads.items():
        tile = tiles_by_id[tile_id]
        rect = tile["rect"]
        detail_rect = [rect[0], rect[1], rect[0] + rect[2], rect[1] + rect[3]]
        data = {
            "schema_version": 2,
            "source": "OpenStreetMap Geofabrik Kanto PBF",
            "license": "ODbL 1.0",
            "tile_id": tile_id,
            "detail_rect": detail_rect,
            "gold_rect": detail_rect,
            "triangles": dict(sorted(target["triangles"].items())),
            "lines": dict(sorted(target["lines"].items())),
            "counts": dict(sorted(target["counts"].items())),
        }
        output_path = OUTPUT_DIR / f"{tile_id}.json"
        output_path.write_text(json.dumps(data, separators=(",", ":")), encoding="utf-8")
        outputs.append({
            "id": tile_id,
            "rect": rect,
            "data_path": f"tmp/full_map_detail/detail_tiles_source/{tile_id}.json",
            "bytes": output_path.stat().st_size,
            "counts": data["counts"],
        })
    return outputs


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for block in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--pbf", type=Path, default=DEFAULT_PBF)
    parser.add_argument("--reuse-spool", action="store_true")
    args = parser.parse_args()
    manifest = json.loads(BUILD_MANIFEST.read_text(encoding="utf-8"))
    tiles_by_id = {tile["id"]: tile for tile in manifest["tiles"]}

    if not args.reuse_spool:
        SPOOL_DIR.mkdir(parents=True, exist_ok=True)
        for old_spool in SPOOL_DIR.glob("chunk_*.ndjson"):
            old_spool.unlink()
        spooler = PbfSpooler(manifest, SPOOL_DIR)
        try:
            spooler.apply_file(str(args.pbf), locations=True)
        finally:
            spooler.close()
        print(json.dumps({"spooled": dict(spooler.counts)}, indent=2))

    runtime_tiles = []
    for index, chunk in enumerate(manifest["chunks"]):
        runtime_tiles.extend(bake_chunk(chunk, tiles_by_id))
        print(f"[full-detail] chunk {index + 1}/{len(manifest['chunks'])}: {chunk['id']}")

    runtime_manifest = {
        "schema_version": 2,
        "source": "OpenStreetMap Geofabrik Kanto PBF",
        "license": "ODbL 1.0",
        "source_sha256": sha256(args.pbf),
        "style_profile": "yokohama_gold_v5_locked",
        "grid": manifest["grid"],
        "tile_count": len(runtime_tiles),
        "tiles": runtime_tiles,
    }
    RUNTIME_MANIFEST.write_text(json.dumps(runtime_manifest, indent=2), encoding="utf-8")
    print(json.dumps({
        "manifest": str(RUNTIME_MANIFEST),
        "tiles": len(runtime_tiles),
        "bytes": sum(tile["bytes"] for tile in runtime_tiles),
    }, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
