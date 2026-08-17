#!/usr/bin/env python3
"""图2/图3正式 PNG 底图：CartoDB Voyager no-labels 17×17 @2x 瓦片拼接。

只负责离线生产；运行时读取生成的 PNG + metadata。默认一次生成两张，也可传
`desert` / `ocean` 单跑。输出固定 8704×8704，与东京湾正式底图同尺寸、同 zoom。
"""

from __future__ import annotations

import json
import math
import sys
import time
import urllib.request
from io import BytesIO
from pathlib import Path

from PIL import Image

from remove_admin_boundaries import clean_admin_boundaries


ROOT = Path(__file__).resolve().parents[2]
ZOOM = 13
TILES_PER_AXIS = 17
TILE_PX = 512
TILE_URL = (
    "https://a.basemaps.cartocdn.com/rastertiles/"
    "voyager_nolabels/{z}/{x}/{y}@2x.png"
)
MAPS = {
    "desert": {
        "center": (-23.34718, 119.64044),
        "png": ROOT / "resources/maps/desert_railway_bg.png",
        "meta": ROOT / "resources/maps/desert_railway_bg.json",
        "label": "Mount Whaleback / Newman West",
    },
    "ocean": {
        "center": (-9.25, 160.0),
        "png": ROOT / "resources/maps/ocean_islands_bg.png",
        "meta": ROOT / "resources/maps/ocean_islands_bg.json",
        "label": "Ironbottom Sound",
    },
}


def latlon_to_tile(lat: float, lon: float, zoom: int) -> tuple[float, float]:
    scale = 2.0**zoom
    x = (lon + 180.0) / 360.0 * scale
    y = (
        1.0
        - math.log(
            math.tan(math.radians(lat)) + 1.0 / math.cos(math.radians(lat))
        )
        / math.pi
    ) / 2.0 * scale
    return x, y


def tile_to_latlon(x: int, y: int, zoom: int) -> tuple[float, float]:
    scale = 2.0**zoom
    lon = x / scale * 360.0 - 180.0
    lat = math.degrees(math.atan(math.sinh(math.pi * (1.0 - 2.0 * y / scale))))
    return lat, lon


def download_tile(url: str, retries: int = 4) -> Image.Image:
    for attempt in range(retries):
        try:
            request = urllib.request.Request(
                url, headers={"User-Agent": "AGL-map-baker/2.0 (personal project)"}
            )
            with urllib.request.urlopen(request, timeout=30) as response:
                image = Image.open(BytesIO(response.read())).convert("RGB")
            if image.size != (TILE_PX, TILE_PX):
                raise RuntimeError(f"unexpected tile size {image.size}: {url}")
            return image
        except Exception:
            if attempt + 1 >= retries:
                raise
            time.sleep(1.0 + attempt)
    raise AssertionError("unreachable")


def bake(map_key: str) -> None:
    config = MAPS[map_key]
    lat, lon = config["center"]
    center_x, center_y = latlon_to_tile(lat, lon, ZOOM)
    tile_x0 = math.floor(center_x) - TILES_PER_AXIS // 2
    tile_y0 = math.floor(center_y) - TILES_PER_AXIS // 2
    tile_x1 = tile_x0 + TILES_PER_AXIS
    tile_y1 = tile_y0 + TILES_PER_AXIS
    output_px = TILES_PER_AXIS * TILE_PX
    canvas = Image.new("RGB", (output_px, output_px))
    total = TILES_PER_AXIS * TILES_PER_AXIS
    started = time.time()

    print(
        f"[{map_key}] {config['label']} center=({lat:.5f},{lon:.5f}) "
        f"tiles={TILES_PER_AXIS}x{TILES_PER_AXIS} output={output_px}x{output_px}"
    )
    for ix, tile_x in enumerate(range(tile_x0, tile_x1)):
        for iy, tile_y in enumerate(range(tile_y0, tile_y1)):
            url = TILE_URL.format(z=ZOOM, x=tile_x, y=tile_y)
            tile = download_tile(url)
            canvas.paste(tile, (ix * TILE_PX, iy * TILE_PX))
            done = ix * TILES_PER_AXIS + iy + 1
            if done % 25 == 0 or done == total:
                print(f"[{map_key}] {done}/{total} elapsed={time.time() - started:.1f}s")
            time.sleep(0.04)

    canvas, boundary_mask = clean_admin_boundaries(canvas, canvas)
    print(f"[{map_key}] removed administrative boundary mask={int(boundary_mask.sum())} px")
    config["png"].parent.mkdir(parents=True, exist_ok=True)
    canvas.save(config["png"], optimize=True, compress_level=6)

    real_lat_max, real_lon_min = tile_to_latlon(tile_x0, tile_y0, ZOOM)
    real_lat_min, real_lon_max = tile_to_latlon(tile_x1, tile_y1, ZOOM)
    metadata = {
        "image": config["png"].name,
        "bbox_ll": {
            "lat_min": real_lat_min,
            "lat_max": real_lat_max,
            "lon_min": real_lon_min,
            "lon_max": real_lon_max,
        },
        "image_size_px": [output_px, output_px],
        "zoom": ZOOM,
        "source": "CartoDB Voyager no-labels / OpenStreetMap",
        "license": "OpenStreetMap ODbL + CARTO attribution",
        "reference_label": config["label"],
        "game_world_center_latlon": [lat, lon],
        "game_world_meters_per_degree_lat": 111000.0,
        "game_world_meters_per_degree_lon_at_center": 111000.0
        * math.cos(math.radians(lat)),
        "game_world_px_per_meter": 0.5,
    }
    config["meta"].write_text(
        json.dumps(metadata, ensure_ascii=False, indent=2), encoding="utf-8"
    )
    size_mib = config["png"].stat().st_size / (1024.0 * 1024.0)
    print(f"[{map_key}] saved {config['png']} ({size_mib:.1f} MiB)")
    print(f"[{map_key}] saved {config['meta']}")


def main() -> None:
    keys = list(MAPS) if len(sys.argv) == 1 or sys.argv[1] == "all" else [sys.argv[1]]
    unknown = [key for key in keys if key not in MAPS]
    if unknown:
        raise SystemExit(f"unknown map key: {', '.join(unknown)}")
    for key in keys:
        bake(key)


if __name__ == "__main__":
    main()
