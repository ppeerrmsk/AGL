#!/usr/bin/env python3
"""确定性移除 CARTO Voyager 栅格底图中的非实体行政边界。

默认只写 ``tmp/admin-boundary-cleanup/runtime_candidates``。传入
``--write-runtime`` 才会原子替换三张正式母图；道路、铁路、河道、海岸与建筑不按
颜色全局删除，只修补与 CARTO ``#e1c5c7`` 边界核心连通的窄像素带。
"""

from __future__ import annotations

import argparse
import json
import os
from pathlib import Path

import numpy as np
from PIL import Image, ImageFilter


ROOT = Path(__file__).resolve().parents[2]
MAP_DIR = ROOT / "resources/maps"
DEFAULT_OUTPUT = ROOT / "tmp/admin-boundary-cleanup/runtime_candidates"
MAPS = {
    "tokyo": {
        "detect": MAP_DIR / "tokyo_bay_bg.png",
        "source": MAP_DIR / "tokyo_bay_bg.png",
        "output": MAP_DIR / "tokyo_bay_bg.png",
        "meta": MAP_DIR / "tokyo_bay_bg.json",
    },
    "desert": {
        "detect": MAP_DIR / "desert_railway_bg.png",
        "source": MAP_DIR / "desert_railway_bg_v2.png",
        "output": MAP_DIR / "desert_railway_bg_v2.png",
        "meta": MAP_DIR / "desert_railway_bg_v2.json",
    },
    "ocean": {
        "detect": MAP_DIR / "ocean_islands_bg.png",
        "source": MAP_DIR / "ocean_islands_bg_v2.png",
        "output": MAP_DIR / "ocean_islands_bg_v2.png",
        "meta": MAP_DIR / "ocean_islands_bg_v2.json",
    },
}


def detect_admin_boundary(source: np.ndarray) -> np.ndarray:
    """返回只与 Voyager 粉灰行政边界核心连通的抗锯齿窄带。"""

    rgb = source.astype(np.int16)
    red, green, blue = rgb[:, :, 0], rgb[:, :, 1], rgb[:, :, 2]
    core = (
        (np.abs(red - 225) <= 3)
        & (np.abs(green - 197) <= 3)
        & (np.abs(blue - 199) <= 3)
    )
    family = (
        (red >= 170)
        & (red - green >= 9)
        & (blue - green >= -4)
        & (blue - green <= 12)
        & (red - blue >= 6)
    )
    grown = core.copy()
    for _ in range(3):
        neighborhood = np.zeros_like(grown)
        for dy in (-1, 0, 1):
            for dx in (-1, 0, 1):
                if dx or dy:
                    neighborhood |= np.roll(
                        np.roll(grown, dy, axis=0), dx, axis=1
                    )
        grown |= neighborhood & family
    return np.asarray(
        Image.fromarray((grown * 255).astype(np.uint8)).filter(
            ImageFilter.MaxFilter(3)
        )
    ) > 0


def inpaint_narrow(image: np.ndarray, mask: np.ndarray) -> np.ndarray:
    """从八邻域向内逐圈平均，确定性修补不足数像素宽的遮罩。"""

    work = image.astype(np.float32).copy()
    remaining = mask.copy()
    for _ in range(12):
        if not remaining.any():
            break
        valid = ~remaining
        value_sum = np.zeros_like(work)
        weight = np.zeros(remaining.shape, dtype=np.float32)
        for dy, dx in (
            (-1, 0), (1, 0), (0, -1), (0, 1),
            (-1, -1), (-1, 1), (1, -1), (1, 1),
        ):
            shifted_valid = np.roll(np.roll(valid, dy, axis=0), dx, axis=1)
            shifted_value = np.roll(np.roll(work, dy, axis=0), dx, axis=1)
            value_sum += shifted_value * shifted_valid[:, :, None]
            weight += shifted_valid
        fillable = remaining & (weight > 0)
        work[fillable] = value_sum[fillable] / weight[fillable, None]
        remaining[fillable] = False
    if remaining.any():
        raise RuntimeError(f"行政边界修补未收敛：剩余 {int(remaining.sum())} px")
    return np.clip(np.rint(work), 0, 255).astype(np.uint8)


def clean_admin_boundaries(
    detection_image: Image.Image, display_image: Image.Image
) -> tuple[Image.Image, np.ndarray]:
    detection = np.asarray(detection_image.convert("RGB"))
    display = np.asarray(display_image.convert("RGB"))
    if detection.shape != display.shape:
        raise ValueError(
            f"检测源与成图尺寸不一致：{detection.shape} != {display.shape}"
        )
    mask = detect_admin_boundary(detection)
    return Image.fromarray(inpaint_narrow(display, mask)), mask


def save_png_atomic(image: Image.Image, output: Path) -> None:
    output.parent.mkdir(parents=True, exist_ok=True)
    temporary = output.with_name(f".{output.name}.admin-boundary.tmp")
    image.save(temporary, format="PNG", optimize=True, compress_level=6)
    os.replace(temporary, output)


def update_metadata(path: Path) -> None:
    metadata = json.loads(path.read_text(encoding="utf-8"))
    process = metadata.get("postprocess", "")
    rule = "removed non-physical CARTO administrative boundaries"
    if rule not in process:
        metadata["postprocess"] = f"{process}; {rule}".strip("; ")
    path.write_text(
        json.dumps(metadata, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--maps", nargs="+", choices=tuple(MAPS), default=tuple(MAPS)
    )
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    parser.add_argument(
        "--write-runtime",
        action="store_true",
        help="原子替换 resources/maps 中的正式母图；默认只写 tmp/。",
    )
    args = parser.parse_args()
    for map_id in args.maps:
        config = MAPS[map_id]
        with Image.open(config["detect"]) as detection_image, Image.open(
            config["source"]
        ) as display_image:
            cleaned, mask = clean_admin_boundaries(detection_image, display_image)
            original = np.asarray(display_image.convert("RGB"))
        changed = np.any(original != np.asarray(cleaned), axis=2)
        output = (
            config["output"]
            if args.write_runtime
            else args.output / config["output"].name
        ).resolve()
        save_png_atomic(cleaned, output)
        if args.write_runtime:
            update_metadata(config["meta"])
        print(
            f"[{map_id}] mask={int(mask.sum())} changed={int(changed.sum())} "
            f"output={output.relative_to(ROOT)}"
        )


if __name__ == "__main__":
    main()
