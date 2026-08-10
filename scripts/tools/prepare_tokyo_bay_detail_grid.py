#!/usr/bin/env python3
"""Prepare resumable Overpass queries for the full Tokyo Bay detail grid.

The accepted Yokohama gold slice fixes the 4 km tile size and grid alignment.
This tool uses the production land mask only to skip pure-ocean chunks; it does
not rasterize or ship the legacy PNG. Generated queries/raw downloads stay in
``tmp/`` and are ignored by Godot.
"""

from __future__ import annotations

import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
TOKYO_DATA = ROOT / "resources" / "maps" / "tokyo_bay.json"
OUTPUT_ROOT = ROOT / "tmp" / "full_map_detail"

LAT_CENTER = 35.44
LON_CENTER = 139.76
METERS_PER_LAT = 111000.0
METERS_PER_LON = 90434.27326522839
PX_PER_METER = 0.5

# Gold tile (-6300,-1700)-(-4300,300) lands exactly at grid (5,7).
GRID_ORIGIN_X = -16300.0
GRID_ORIGIN_Y = -15700.0
TILE_SIZE = 2000.0
GRID_COLUMNS = 16
GRID_ROWS = 16
QUERY_CHUNK_TILES = 2
QUERY_PADDING_PX = 160.0

QUERY_TEMPLATE = """[out:json][timeout:420][maxsize:536870912];
(
  way[\"building\"]({bbox});
  relation[\"building\"]({bbox});
  way[\"landuse\"]({bbox});
  relation[\"landuse\"]({bbox});
  way[\"railway\"]({bbox});
  way[\"waterway\"]({bbox});
  way[\"natural\"=\"water\"]({bbox});
  relation[\"natural\"=\"water\"]({bbox});
  way[\"leisure\"~\"^(park|garden|sports_centre|pitch)$\"]({bbox});
  relation[\"leisure\"~\"^(park|garden|sports_centre|pitch)$\"]({bbox});
  way[\"amenity\"~\"^(parking|school|university|hospital)$\"]({bbox});
  relation[\"amenity\"~\"^(parking|school|university|hospital)$\"]({bbox});
  way[\"man_made\"~\"^(pier|breakwater|groyne)$\"]({bbox});
);
out geom;
"""


def point_in_polygon(x: float, y: float, polygon: list[tuple[float, float]]) -> bool:
    inside = False
    previous = len(polygon) - 1
    for index, (current_x, current_y) in enumerate(polygon):
        previous_x, previous_y = polygon[previous]
        crosses = (current_y > y) != (previous_y > y)
        if crosses and x < (previous_x - current_x) * (y - current_y) / (previous_y - current_y) + current_x:
            inside = not inside
        previous = index
    return inside


def tile_rect(column: int, row: int) -> tuple[float, float, float, float]:
    x = GRID_ORIGIN_X + column * TILE_SIZE
    y = GRID_ORIGIN_Y + row * TILE_SIZE
    return x, y, x + TILE_SIZE, y + TILE_SIZE


def tile_has_land(rect, polygons: list[list[tuple[float, float]]]) -> bool:
    min_x, min_y, max_x, max_y = rect
    samples = []
    for y_step in range(5):
        for x_step in range(5):
            samples.append((
                min_x + (x_step + 0.5) * (max_x - min_x) / 5.0,
                min_y + (y_step + 0.5) * (max_y - min_y) / 5.0,
            ))
    if any(point_in_polygon(x, y, polygon) for x, y in samples for polygon in polygons):
        return True
    return any(
        min_x <= x <= max_x and min_y <= y <= max_y
        for polygon in polygons
        for x, y in polygon
    )


def world_rect_to_bbox(rect) -> str:
    min_x, min_y, max_x, max_y = rect
    min_x -= QUERY_PADDING_PX
    min_y -= QUERY_PADDING_PX
    max_x += QUERY_PADDING_PX
    max_y += QUERY_PADDING_PX
    lon_min = LON_CENTER + min_x / (METERS_PER_LON * PX_PER_METER)
    lon_max = LON_CENTER + max_x / (METERS_PER_LON * PX_PER_METER)
    lat_min = LAT_CENTER - max_y / (METERS_PER_LAT * PX_PER_METER)
    lat_max = LAT_CENTER - min_y / (METERS_PER_LAT * PX_PER_METER)
    return f"{lat_min:.7f},{lon_min:.7f},{lat_max:.7f},{lon_max:.7f}"


def main() -> int:
    source = json.loads(TOKYO_DATA.read_text(encoding="utf-8"))
    polygons = [list(zip(values[0::2], values[1::2])) for values in source["land_mask"]]
    selected_tiles = []
    chunks: dict[tuple[int, int], list[dict]] = {}
    for row in range(GRID_ROWS):
        for column in range(GRID_COLUMNS):
            rect = tile_rect(column, row)
            if not tile_has_land(rect, polygons):
                continue
            tile_id = f"detail_{column:02d}_{row:02d}"
            tile = {
                "id": tile_id,
                "column": column,
                "row": row,
                "rect": [rect[0], rect[1], TILE_SIZE, TILE_SIZE],
                "output": f"tmp/full_map_detail/detail_tiles_source/{tile_id}.json",
            }
            selected_tiles.append(tile)
            chunk_key = (column // QUERY_CHUNK_TILES, row // QUERY_CHUNK_TILES)
            chunks.setdefault(chunk_key, []).append(tile)

    query_dir = OUTPUT_ROOT / "queries"
    raw_dir = OUTPUT_ROOT / "raw"
    query_dir.mkdir(parents=True, exist_ok=True)
    raw_dir.mkdir(parents=True, exist_ok=True)
    chunk_rows = []
    for (chunk_column, chunk_row), tiles in sorted(chunks.items()):
        min_column = chunk_column * QUERY_CHUNK_TILES
        min_row = chunk_row * QUERY_CHUNK_TILES
        min_x, min_y, _, _ = tile_rect(min_column, min_row)
        _, _, max_x, max_y = tile_rect(
            min(min_column + QUERY_CHUNK_TILES - 1, GRID_COLUMNS - 1),
            min(min_row + QUERY_CHUNK_TILES - 1, GRID_ROWS - 1),
        )
        chunk_id = f"chunk_{chunk_column:02d}_{chunk_row:02d}"
        query_path = query_dir / f"{chunk_id}.overpassql"
        raw_path = raw_dir / f"{chunk_id}.json"
        bbox = world_rect_to_bbox((min_x, min_y, max_x, max_y))
        query_path.write_text(QUERY_TEMPLATE.format(bbox=bbox), encoding="utf-8")
        chunk_rows.append({
            "id": chunk_id,
            "query": str(query_path.relative_to(ROOT)).replace("\\", "/"),
            "raw": str(raw_path.relative_to(ROOT)).replace("\\", "/"),
            "bbox": bbox,
            "tiles": [tile["id"] for tile in tiles],
        })

    manifest = {
        "schema_version": 1,
        "grid": {
            "origin": [GRID_ORIGIN_X, GRID_ORIGIN_Y],
            "tile_size": TILE_SIZE,
            "columns": GRID_COLUMNS,
            "rows": GRID_ROWS,
        },
        "selected_tile_count": len(selected_tiles),
        "query_chunk_count": len(chunk_rows),
        "tiles": selected_tiles,
        "chunks": chunk_rows,
    }
    OUTPUT_ROOT.mkdir(parents=True, exist_ok=True)
    (OUTPUT_ROOT / "build_manifest.json").write_text(
        json.dumps(manifest, indent=2), encoding="utf-8"
    )
    print(json.dumps({
        "manifest": str(OUTPUT_ROOT / "build_manifest.json"),
        "tiles": len(selected_tiles),
        "chunks": len(chunk_rows),
    }, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
