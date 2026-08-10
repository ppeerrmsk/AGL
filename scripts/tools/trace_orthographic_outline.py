#!/usr/bin/env python3
"""从三视图的指定裁切框提取闭合外轮廓；不生成或修改飞机几何。"""

from __future__ import annotations

import argparse
from collections import deque
from pathlib import Path

from PIL import Image, ImageFilter


def flood_outside(blocked: Image.Image) -> Image.Image:
    width, height = blocked.size
    pixels = blocked.load()
    outside = bytearray(width * height)
    queue: deque[tuple[int, int]] = deque()

    def seed(x: int, y: int) -> None:
        index = y * width + x
        if not pixels[x, y] and not outside[index]:
            outside[index] = 1
            queue.append((x, y))

    for x in range(width):
        seed(x, 0)
        seed(x, height - 1)
    for y in range(height):
        seed(0, y)
        seed(width - 1, y)

    while queue:
        x, y = queue.popleft()
        for nx, ny in ((x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)):
            if 0 <= nx < width and 0 <= ny < height:
                seed(nx, ny)

    mask = Image.new("L", (width, height), 255)
    out = mask.load()
    for y in range(height):
        for x in range(width):
            if outside[y * width + x]:
                out[x, y] = 0
    return mask


def large_components(mask: Image.Image, min_ratio: float) -> Image.Image:
    width, height = mask.size
    pixels = mask.load()
    visited = bytearray(width * height)
    components: list[list[tuple[int, int]]] = []
    for y in range(height):
        for x in range(width):
            index = y * width + x
            if pixels[x, y] == 0 or visited[index]:
                continue
            visited[index] = 1
            queue: deque[tuple[int, int]] = deque([(x, y)])
            component: list[tuple[int, int]] = []
            while queue:
                cx, cy = queue.popleft()
                component.append((cx, cy))
                for nx, ny in (
                    (cx - 1, cy - 1), (cx, cy - 1), (cx + 1, cy - 1),
                    (cx - 1, cy), (cx + 1, cy),
                    (cx - 1, cy + 1), (cx, cy + 1), (cx + 1, cy + 1),
                ):
                    if 0 <= nx < width and 0 <= ny < height:
                        next_index = ny * width + nx
                        if pixels[nx, ny] and not visited[next_index]:
                            visited[next_index] = 1
                            queue.append((nx, ny))
            components.append(component)
    result = Image.new("L", mask.size, 0)
    if components:
        out = result.load()
        largest_size = max(map(len, components))
        for component in components:
            if len(component) < largest_size * min_ratio:
                continue
            for x, y in component:
                out[x, y] = 255
    return result


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("input", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--crop", nargs=4, type=int, required=True, metavar=("L", "T", "R", "B"))
    parser.add_argument("--threshold", type=int, default=205)
    parser.add_argument("--line-width", type=int, choices=(1, 3, 5), default=3)
    parser.add_argument("--rotate", type=int, choices=(0, 90, 180, 270), default=0)
    parser.add_argument("--components-min-ratio", type=float, default=1.0)
    parser.add_argument("--light-foreground", action="store_true")
    parser.add_argument("--alpha-foreground", action="store_true")
    parser.add_argument("--red-foreground", action="store_true")
    parser.add_argument("--ignore-red-annotations", action="store_true")
    args = parser.parse_args()

    rgba = Image.open(args.input).convert("RGBA")
    if args.ignore_red_annotations:
        cleaned = rgba.copy()
        pixels = cleaned.load()
        for y in range(cleaned.height):
            for x in range(cleaned.width):
                red, green, blue, alpha = pixels[x, y]
                if alpha and red > 110 and red > green * 1.35 and red > blue * 1.35:
                    pixels[x, y] = (255, 255, 255, alpha)
        rgba = cleaned
    if args.red_foreground:
        source = rgba.crop(tuple(args.crop))
        red_mask = Image.new("L", source.size, 0)
        source_pixels = source.load()
        mask_pixels = red_mask.load()
        for y in range(source.height):
            for x in range(source.width):
                red, green, blue, alpha = source_pixels[x, y]
                if alpha and red > 110 and red > green * 1.2 and red > blue * 1.2:
                    mask_pixels[x, y] = 255
        lines = red_mask.point(lambda value: 255 if value else 0, mode="1")
    elif args.alpha_foreground:
        source_alpha = rgba.getchannel("A").crop(tuple(args.crop))
        lines = source_alpha.point(lambda value: 255 if value > args.threshold else 0, mode="1")
    else:
        flattened = Image.new("RGBA", rgba.size, (255, 255, 255, 255))
        flattened.alpha_composite(rgba)
        source = flattened.convert("RGB").crop(tuple(args.crop))
        gray = source.convert("L")
        if args.light_foreground:
            lines = gray.point(lambda value: 255 if value > args.threshold else 0, mode="1")
        else:
            lines = gray.point(lambda value: 255 if value < args.threshold else 0, mode="1")
    if args.line_width > 1:
        lines = lines.filter(ImageFilter.MaxFilter(args.line_width))
    mask = large_components(flood_outside(lines), args.components_min_ratio)
    if args.rotate:
        mask = mask.rotate(args.rotate, expand=True)
    result = Image.new("RGBA", mask.size, (255, 255, 255, 0))
    result.putalpha(mask)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    result.save(args.output, optimize=True)


if __name__ == "__main__":
    main()
