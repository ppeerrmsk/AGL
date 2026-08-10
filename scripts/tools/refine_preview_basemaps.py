#!/usr/bin/env python3
"""离线增强图2沙漠地貌，并清理图3土地覆盖直角色块。"""

from __future__ import annotations

import json
from pathlib import Path

import numpy as np
from PIL import Image, ImageFilter


ROOT = Path(__file__).resolve().parents[2]
MAP_DIR = ROOT / "resources/maps"
PREVIEW_DIR = ROOT / "tmp/map_previews"
SIZE = (8704, 8704)


def _write_meta(source: Path, output: Path, process: str) -> None:
    metadata = json.loads(source.read_text(encoding="utf-8"))
    metadata["image"] = output.with_suffix(".png").name
    metadata["postprocess"] = process
    output.write_text(json.dumps(metadata, ensure_ascii=False, indent=2), encoding="utf-8")


def _shader_preview(source: Path, output: Path) -> None:
    image = Image.open(source).convert("RGB")
    image.thumbnail((1400, 1400), Image.Resampling.LANCZOS)
    color = np.asarray(image, dtype=np.float32) / 255.0
    lum = color @ np.array([0.299, 0.587, 0.114], dtype=np.float32)
    padded = np.pad(lum, 1, mode="edge")
    tl, tm, tr = padded[:-2, :-2], padded[:-2, 1:-1], padded[:-2, 2:]
    ml, mr = padded[1:-1, :-2], padded[1:-1, 2:]
    bl, bm, br = padded[2:, :-2], padded[2:, 1:-1], padded[2:, 2:]
    gx = -tl - 2.0 * ml - bl + tr + 2.0 * mr + br
    gy = -tl - 2.0 * tm - tr + bl + 2.0 * bm + br
    edge = np.clip(np.sqrt(gx * gx + gy * gy) * 1.2, 0.0, 1.0)[..., None]
    color *= 1.0 - edge
    gray = (color @ np.array([0.299, 0.587, 0.114], dtype=np.float32))[..., None]
    color = gray * 0.6 + color * 0.4
    color *= 0.70
    color = (color - 0.5) * 1.25 + 0.5
    color *= np.array([0.78, 0.82, 0.80], dtype=np.float32)
    preview = Image.fromarray((np.clip(color, 0.0, 1.0) * 255.0).astype(np.uint8))
    output.parent.mkdir(parents=True, exist_ok=True)
    preview.save(output, quality=94)


def refine_desert() -> Path:
    source = MAP_DIR / "desert_railway_bg.png"
    terrain_source = MAP_DIR / "source/desert_railway_terrain_texture.png"
    output = MAP_DIR / "desert_railway_bg_v2.png"

    base_image = Image.open(source).convert("RGB")
    terrain_image = Image.open(terrain_source).convert("RGB").filter(
        ImageFilter.GaussianBlur(radius=1.35)
    )
    terrain_image = terrain_image.resize(SIZE, Image.Resampling.BICUBIC)
    output_image = Image.new("RGB", SIZE)
    # 大范围暖色地貌保留约 18% 来源纹理；其余抬到浅沙色，避免 Sobel 后过花。
    pale_sand = np.array([246.0, 231.0, 207.0], dtype=np.float32)
    for y0 in range(0, SIZE[1], 256):
        y1 = min(y0 + 256, SIZE[1])
        box = (0, y0, SIZE[0], y1)
        base = np.asarray(base_image.crop(box), dtype=np.float32)
        terrain = np.asarray(terrain_image.crop(box), dtype=np.float32)
        terrain = terrain * 0.18 + pale_sand * 0.82
        composed = terrain * (base / 255.0)
        # 原图少量水体保持蓝色识别，不被暖色地貌层染成盐碱地。
        water = (base[:, :, 2] > base[:, :, 0] + 5.0) & (base[:, :, 2] > base[:, :, 1] + 2.0)
        composed[water] = base[water]
        output_image.paste(
            Image.fromarray(np.clip(composed, 0.0, 255.0).astype(np.uint8)),
            (0, y0),
        )
    output_image.save(output, optimize=True, compress_level=6)
    _write_meta(
        MAP_DIR / "desert_railway_bg.json",
        MAP_DIR / "desert_railway_bg_v2.json",
        "low-contrast generated Pilbara terrain under coordinate-stable CARTO/OSM lines",
    )
    _shader_preview(output, PREVIEW_DIR / "desert_railway_v2_filtered.jpg")
    return output


def refine_ocean() -> Path:
    source = MAP_DIR / "ocean_islands_bg.png"
    output = MAP_DIR / "ocean_islands_bg_v2.png"
    source_image = Image.open(source).convert("RGB")
    output_image = Image.new("RGB", SIZE)
    cleared_pixels = 0
    for y0 in range(0, SIZE[1], 256):
        y1 = min(y0 + 256, SIZE[1])
        image = np.asarray(source_image.crop((0, y0, SIZE[0], y1)), dtype=np.uint8).copy()
        red = image[:, :, 0].astype(np.int16)
        green = image[:, :, 1].astype(np.int16)
        blue = image[:, :, 2].astype(np.int16)
        rows = np.arange(y0, y1)[:, None]
        # 主岛南部保护区/土地覆盖面以轴对齐矩形进入 CARTO；只移除其绿色填色。
        # 河流、道路、真实海岸和北部岛屿均不符合该 mask，保持原像素。
        rectangular_landcover = (
            (rows >= 5200)
            & (green > red + 3)
            & (green > blue + 10)
            & (red > 180)
        )
        cleared_pixels += int(rectangular_landcover.sum())
        image[rectangular_landcover] = np.array([251, 248, 243], dtype=np.uint8)
        output_image.paste(Image.fromarray(image), (0, y0))
    output_image.save(output, optimize=True, compress_level=6)
    _write_meta(
        MAP_DIR / "ocean_islands_bg.json",
        MAP_DIR / "ocean_islands_bg_v2.json",
        "removed southern axis-aligned protected-area/landcover fill; coast and linework unchanged",
    )
    _shader_preview(output, PREVIEW_DIR / "ocean_islands_v2_filtered.jpg")
    print(f"[ocean] cleared landcover pixels={cleared_pixels}")
    return output


def main() -> None:
    for output in (refine_desert(), refine_ocean()):
        print(f"[done] {output.relative_to(ROOT)} {output.stat().st_size / 1048576.0:.2f} MiB")


if __name__ == "__main__":
    main()
