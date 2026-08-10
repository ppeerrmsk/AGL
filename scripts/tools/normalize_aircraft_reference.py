#!/usr/bin/env python3
"""把已经抠出的正交顶视图蒙版等比归一化为游戏用纯白 RGBA PNG。

本工具只做裁切、等比缩放和居中，不补点、不平滑轮廓、不推断缺失结构。
"""

from __future__ import annotations

import argparse
from pathlib import Path

from PIL import Image


CANVAS_SIZE = 128
MARGIN = 7


def normalize(source_path: Path, output_path: Path) -> None:
    source = Image.open(source_path).convert("RGBA")
    alpha = source.getchannel("A")
    bbox = alpha.getbbox()
    if bbox is None:
        raise ValueError(f"参考蒙版没有可见像素: {source_path}")

    cropped_alpha = alpha.crop(bbox)
    target_extent = CANVAS_SIZE - MARGIN * 2
    scale = min(target_extent / cropped_alpha.width, target_extent / cropped_alpha.height)
    target_size = (
        max(1, round(cropped_alpha.width * scale)),
        max(1, round(cropped_alpha.height * scale)),
    )
    resized_alpha = cropped_alpha.resize(target_size, Image.Resampling.LANCZOS)

    canvas_alpha = Image.new("L", (CANVAS_SIZE, CANVAS_SIZE), 0)
    offset = ((CANVAS_SIZE - target_size[0]) // 2, (CANVAS_SIZE - target_size[1]) // 2)
    canvas_alpha.paste(resized_alpha, offset)
    result = Image.new("RGBA", (CANVAS_SIZE, CANVAS_SIZE), (255, 255, 255, 255))
    result.putalpha(canvas_alpha)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    result.save(output_path, optimize=True)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("input", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    normalize(args.input, args.output)


if __name__ == "__main__":
    main()
