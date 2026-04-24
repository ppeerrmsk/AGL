#!/usr/bin/env python3
"""
无文字 OSM 底图下载器 — 按 bbox + 缩放级别从 CartoDB 拉瓦片拼接成大 PNG

用法：
    python scripts/tools/download_basemap.py

需求：pillow (已安装)

数据源：CartoDB Light Basemap (no-labels 版本) —— CC-BY OpenStreetMap
    许可：https://carto.com/attributions
    适合小规模/个人项目。大规模商业请换 Mapbox / 自建 tile server。

下载完成后：
    resources/maps/tokyo_bay_bg.png    —— 无文字底图 PNG
    resources/maps/tokyo_bay_bg.json   —— 附带的 bbox 元数据（经纬度对应游戏坐标）
"""
import os
import math
import sys
import json
import urllib.request
import time
from io import BytesIO

try:
    from PIL import Image
except ImportError:
    print("需要 pillow: pip install pillow")
    sys.exit(1)


# ==== 目标区域 ==================================
# 对应 AGL 游戏世界：中心 (35.44N, 139.76E)，±7500 px = 1 px / 2 m 约 ±15 km
# bbox 必须对称围绕游戏中心，否则游戏内边界会和底图错位（见 2026-04-22 修复）
# 半宽略大于 ±15 km 留余量；瓦片对齐后实际范围会再扩一点
TARGET_BBOX = {
    "lat_min": 35.44 - 0.1462,   # 35.2938  (~16.2 km south)
    "lat_max": 35.44 + 0.1462,   # 35.5862  (~16.2 km north)
    "lon_min": 139.76 - 0.1730,  # 139.5870 (~15.6 km west)
    "lon_max": 139.76 + 0.1730,  # 139.9330 (~15.6 km east)
}
ZOOM = 13  # 13 → 单瓦片 ~4.77 km，整张图 ~8-10 张拼 -> 2000-2500px 宽度范围。调到 14 更清晰 4x 体积

# ==== 底图风格 ====
# voyager_nolabels  —— 自然色彩、陆地浅褐、海面浅蓝（推荐 Tacview 风格）
# light_nolabels    —— 灰底浅色，白海（偏白，默认）
# dark_nolabels     —— 深灰底，海和地都偏黑（酷但缺对比）
TILE_URL_TEMPLATE = "https://a.basemaps.cartocdn.com/rastertiles/voyager_nolabels/{z}/{x}/{y}@2x.png"

OUT_PNG = r"C:\Users\noelu\Documents\AGL\resources\maps\tokyo_bay_bg.png"
OUT_META = r"C:\Users\noelu\Documents\AGL\resources\maps\tokyo_bay_bg.json"


def latlon_to_tile(lat, lon, z):
    n = 2.0 ** z
    x = (lon + 180.0) / 360.0 * n
    y = (1.0 - math.log(math.tan(math.radians(lat)) + 1.0 / math.cos(math.radians(lat))) / math.pi) / 2.0 * n
    return x, y


def tile_to_latlon(x, y, z):
    n = 2.0 ** z
    lon = x / n * 360.0 - 180.0
    lat = math.degrees(math.atan(math.sinh(math.pi * (1.0 - 2.0 * y / n))))
    return lat, lon


def download_one_tile(url, retries=3):
    """HTTP GET with retry & UA header."""
    for i in range(retries):
        try:
            req = urllib.request.Request(url, headers={
                "User-Agent": "AGL-map-baker/1.0 (personal project)"
            })
            with urllib.request.urlopen(req, timeout=15) as resp:
                return resp.read()
        except Exception as e:
            if i == retries - 1:
                raise
            print(f"  retry {i+1}: {e}")
            time.sleep(1 + i)


def main():
    bbox = TARGET_BBOX
    # 计算 tile range (x, y 都是 tile 坐标)
    x_min, y_max = latlon_to_tile(bbox["lat_min"], bbox["lon_min"], ZOOM)
    x_max, y_min = latlon_to_tile(bbox["lat_max"], bbox["lon_max"], ZOOM)
    tx0, tx1 = int(math.floor(x_min)), int(math.ceil(x_max))
    ty0, ty1 = int(math.floor(y_min)), int(math.ceil(y_max))
    tiles_w = tx1 - tx0
    tiles_h = ty1 - ty0
    total_tiles = tiles_w * tiles_h
    # @2x 版本是 512x512，普通是 256
    tile_px = 512
    total_px_w = tiles_w * tile_px
    total_px_h = tiles_h * tile_px

    print(f"[plan] zoom={ZOOM}")
    print(f"[plan] tiles x=[{tx0}..{tx1}] y=[{ty0}..{ty1}] = {tiles_w}x{tiles_h} = {total_tiles} tiles")
    print(f"[plan] output image: {total_px_w} x {total_px_h} px (~{total_px_w*total_px_h*4/1024/1024:.1f} MB)")

    # 真实 bbox（按 tile 边界对齐的）
    real_lat_max, real_lon_min = tile_to_latlon(tx0, ty0, ZOOM)
    real_lat_min, real_lon_max = tile_to_latlon(tx1, ty1, ZOOM)
    print(f"[plan] real bbox: lat [{real_lat_min:.4f}..{real_lat_max:.4f}] lon [{real_lon_min:.4f}..{real_lon_max:.4f}]")

    # 逐瓦片下载 + 拼接
    os.makedirs(os.path.dirname(OUT_PNG), exist_ok=True)
    canvas = Image.new("RGB", (total_px_w, total_px_h), (100, 120, 140))

    t_start = time.time()
    for ix, tx in enumerate(range(tx0, tx1)):
        for iy, ty in enumerate(range(ty0, ty1)):
            url = TILE_URL_TEMPLATE.format(z=ZOOM, x=tx, y=ty)
            try:
                data = download_one_tile(url)
                img = Image.open(BytesIO(data))
                canvas.paste(img, (ix * tile_px, iy * tile_px))
            except Exception as e:
                print(f"  [tile {tx},{ty}] FAILED: {e}")
                continue
            done = ix * tiles_h + iy + 1
            if done % 5 == 0 or done == total_tiles:
                elapsed = time.time() - t_start
                print(f"  [{done}/{total_tiles}] elapsed={elapsed:.1f}s")
            time.sleep(0.1)  # 对 CartoDB 友好，别太快

    # 保存图片
    canvas.save(OUT_PNG, optimize=True)
    print(f"[done] saved {OUT_PNG} ({os.path.getsize(OUT_PNG)/1024/1024:.1f} MB)")

    # 保存元数据（游戏加载时对齐坐标用）
    meta = {
        "image": os.path.basename(OUT_PNG),
        "bbox_ll": {
            "lat_min": real_lat_min,
            "lat_max": real_lat_max,
            "lon_min": real_lon_min,
            "lon_max": real_lon_max,
        },
        "image_size_px": [total_px_w, total_px_h],
        "zoom": ZOOM,
        "source": "CartoDB Light no-labels / OSM",
        "license": "CC BY 3.0 (OpenStreetMap) + CartoDB attribution required",
        "game_world_center_latlon": [35.44, 139.76],
        "game_world_meters_per_degree_lat": 111000.0,
        "game_world_meters_per_degree_lon_at_center": 111000.0 * math.cos(math.radians(35.44)),
        "game_world_px_per_meter": 0.5,
    }
    with open(OUT_META, "w", encoding="utf-8") as f:
        json.dump(meta, f, ensure_ascii=False, indent=2)
    print(f"[done] saved {OUT_META}")


if __name__ == "__main__":
    main()
