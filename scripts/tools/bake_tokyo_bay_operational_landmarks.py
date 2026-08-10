#!/usr/bin/env python3
"""Bake one deduplicated >=80m Tokyo Bay landmark packet for Operational LOD."""

from __future__ import annotations

import argparse
import gzip
import json
import struct
from pathlib import Path

from bake_tokyo_bay_landmark_walls import (
    DEFAULT_PBF,
    MANIFEST,
    QUANTIZATION,
    WallCollector,
    append_record,
)


ROOT = Path(__file__).resolve().parents[2]
OUTPUT = ROOT / "resources" / "maps" / "tokyo_bay_operational_landmarks.aglw.gz"
OUTPUT_MANIFEST = ROOT / "resources" / "maps" / "tokyo_bay_operational_landmarks.json"
MIN_OPERATIONAL_HEIGHT_M = 80.0
MAX_TRIANGLES = 70_000
MAX_GZIP_BYTES = 1024 * 1024


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--pbf", type=Path, default=DEFAULT_PBF)
    args = parser.parse_args()

    detail_manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
    collector = WallCollector(detail_manifest)
    collector.apply_file(str(args.pbf), locations=True)

    unique = {}
    for records in collector.records.values():
        for record in records:
            if record.height_m >= MIN_OPERATIONAL_HEIGHT_M:
                unique[record.osm_id] = record
    records = sorted(unique.values(), key=lambda item: (item.height_m, item.osm_id))

    vertices = []
    wall_triangles = 0
    roof_triangles = 0
    for record in records:
        walls, roofs = append_record(vertices, record)
        wall_triangles += walls
        roof_triangles += roofs
    triangles = len(vertices) // 3
    if triangles > MAX_TRIANGLES:
        raise ValueError(f"Operational landmarks use {triangles} triangles")

    origin_x = 0.0
    origin_y = 0.0
    payload = bytearray(b"AGLW")
    payload.extend(struct.pack(
        "<HHfffI", 1, 0, origin_x, origin_y, QUANTIZATION, len(vertices)
    ))
    for x, y, color in vertices:
        payload.extend(struct.pack(
            "<iiBBBB",
            round((x - origin_x) * QUANTIZATION),
            round((y - origin_y) * QUANTIZATION),
            *color,
        ))
    compressed = gzip.compress(bytes(payload), compresslevel=9, mtime=0)
    if len(compressed) > MAX_GZIP_BYTES:
        raise ValueError(f"Operational landmark gzip uses {len(compressed)} bytes")

    OUTPUT.write_bytes(compressed)
    report = {
        "schema_version": 1,
        "format": "AGLW gzip v1",
        "source": "OpenStreetMap Geofabrik Kanto PBF height/building:levels",
        "height_min_m": MIN_OPERATIONAL_HEIGHT_M,
        "buildings": len(records),
        "triangles": triangles,
        "wall_triangles": wall_triangles,
        "roof_triangles": roof_triangles,
        "gzip_bytes": len(compressed),
        "data_path": "res://resources/maps/tokyo_bay_operational_landmarks.aglw.gz",
    }
    OUTPUT_MANIFEST.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(report, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
