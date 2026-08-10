#!/usr/bin/env python3
"""Pack verbose detail-tile JSON into quantized, gzip-compressed AGDT blobs."""

from __future__ import annotations

import gzip
import json
import struct
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
MANIFEST = ROOT / "resources" / "maps" / "tokyo_bay_detail_tiles_full.json"
OUTPUT_DIR = ROOT / "resources" / "maps" / "detail_tiles_packed"
QUANTIZATION = 4.0  # quarter-world-pixel = 0.5 metre

TRIANGLE_LAYERS = (
    "forest", "farmland", "orchard", "grass", "meadow", "industrial",
    "residential", "parking", "civic", "park", "water",
    "building_small", "building_medium", "building_large",
)
LINE_LAYERS = (
    "building_small_outline", "building_medium_outline", "building_large_outline",
    "rail", "waterway", "port",
)


def quantized(value: float, origin: float) -> int:
    result = round((float(value) - origin) * QUANTIZATION)
    if result < -2147483648 or result > 2147483647:
        raise ValueError(f"quantized coordinate {result} exceeds int32")
    return result


def append_u32(buffer: bytearray, value: int) -> None:
    buffer.extend(struct.pack("<I", value))


def append_points(buffer: bytearray, values: list, origin_x: float, origin_y: float) -> None:
    append_u32(buffer, len(values) // 2)
    for index in range(0, len(values), 2):
        buffer.extend(struct.pack(
            "<ii",
            quantized(values[index], origin_x),
            quantized(values[index + 1], origin_y),
        ))


def main() -> int:
    manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    total_json = 0
    total_binary = 0
    total_gzip = 0
    for index, tile in enumerate(manifest["tiles"]):
        source_ref = tile.get("json_source_path", tile["data_path"])
        # v21 以前的 manifest 把近 1 GiB 中间 JSON 留在 resources/；迁移后
        # 构建源只允许位于 .gdignore 的 tmp/，导出包只携带 AGDT。
        if source_ref.startswith("res://resources/maps/detail_tiles/"):
            source_ref = f"tmp/full_map_detail/detail_tiles_source/{Path(source_ref).name}"
        source_path = ROOT / source_ref.removeprefix("res://")
        source = json.loads(source_path.read_text(encoding="utf-8"))
        origin_x, origin_y, width, height = (float(value) for value in tile["rect"])
        buffer = bytearray(b"AGDT")
        buffer.extend(struct.pack("<HHfffff", 1, 0, origin_x, origin_y, width, height, QUANTIZATION))
        triangles = source.get("triangles", {})
        lines = source.get("lines", {})
        for layer in TRIANGLE_LAYERS:
            append_points(buffer, triangles.get(layer, []), origin_x, origin_y)
        for layer in LINE_LAYERS:
            paths = lines.get(layer, [])
            append_u32(buffer, len(paths))
            for values in paths:
                append_points(buffer, values, origin_x, origin_y)

        output_path = OUTPUT_DIR / f"{tile['id']}.agdt.gz"
        compressed = gzip.compress(bytes(buffer), compresslevel=7, mtime=0)
        output_path.write_bytes(compressed)
        total_json += source_path.stat().st_size
        total_binary += len(buffer)
        total_gzip += len(compressed)
        tile["json_source_path"] = str(source_path.relative_to(ROOT)).replace("\\", "/")
        tile["data_path"] = f"res://resources/maps/detail_tiles_packed/{output_path.name}"
        tile["packed_bytes"] = len(compressed)
        tile["uncompressed_bytes"] = len(buffer)
        if (index + 1) % 20 == 0:
            print(f"[pack-detail] {index + 1}/{len(manifest['tiles'])}")

    manifest["schema_version"] = 3
    manifest["format"] = {
        "kind": "AGDT gzip",
        "version": 1,
        "coordinate_bits": 32,
        "quantization_per_world_px": QUANTIZATION,
        "triangle_layers": list(TRIANGLE_LAYERS),
        "line_layers": list(LINE_LAYERS),
    }
    manifest["packed_bytes"] = total_gzip
    manifest["uncompressed_binary_bytes"] = total_binary
    manifest["source_json_bytes"] = total_json
    MANIFEST.write_text(json.dumps(manifest, indent=2), encoding="utf-8")
    print(json.dumps({
        "tiles": len(manifest["tiles"]),
        "source_json_bytes": total_json,
        "binary_bytes": total_binary,
        "gzip_bytes": total_gzip,
        "ratio_to_json": round(total_gzip / max(total_json, 1), 4),
    }, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
