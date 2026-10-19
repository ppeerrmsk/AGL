"""分块、分真实高度烘焙地表候选；不扁平桥面，不授予运行时覆盖资格。"""
import argparse
import hashlib
import json
import re
from pathlib import Path

import numpy as np
from PIL import Image
from build_tokyo_ao import height_field
from build_tokyo_fixed_atlas import validate, reduce_rgba, mip_bytes


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def layer_pixels(data, bounds, pixels):
    """每层独立覆盖，保留透明孔洞；同高异色重叠拒绝，不任意覆盖。"""
    rgba = np.zeros((pixels * 2, pixels * 2, 4), dtype=np.float32)
    occupied = np.zeros(rgba.shape[:2], dtype=bool)
    for color in np.unique(data[:, 0, 6:10], axis=0):
        selected = np.all(data[:, 0, 6:10] == color, axis=1)
        mask = height_field(data[selected, :, :3], bounds, pixels * 2) >= -1
        if np.any(mask & occupied):
            raise ValueError('ambiguous same-height colors')
        rgba[mask] = color
        occupied |= mask
    filtered = reduce_rgba(rgba, 2)
    filtered[:, :, :3] *= filtered[:, :, 3:4]
    return np.rint(np.clip(filtered, 0, 1) * 255).astype(np.uint8)


def build(source, expected, output, step=.25, tile=512, max_scale=5., max_mib=256):
    if sha(source) != expected or output.exists():
        raise ValueError('source drift or output exists')
    if not step > 0 or not max_scale > 0 or not 0 < step * max_scale <= 1.25 or tile not in (256, 512, 1024):
        raise ValueError('invalid clarity or bounded tile size')
    data = np.fromfile(source, dtype='<f4').reshape(-1, 3, 10)
    validate(data)
    palette = Path('scripts/experiments/tokyo_palette.gd')
    pairs = json.loads(re.search(r'const PAIRS := (\{[^}]+\})', palette.read_text(encoding='utf-8')).group(1))
    for old, new in pairs.items():
        rgb = np.array(list(bytes.fromhex(old)), dtype=np.float32) / 255
        selected = np.all(np.abs(data[:, :, 6:9] - rgb) < .0000039, axis=2)
        data[:, :, 6:9][selected] = np.array(list(bytes.fromhex(new)), dtype=np.float32) / 255
    points = data[:, :, [0, 2]]
    low, high = points.min(axis=1), points.max(axis=1)
    span = tile * step
    first = np.floor(low.min(axis=0) / span).astype(int)
    last = np.ceil(high.max(axis=0) / span).astype(int)
    heights = np.unique(data[:, 0, 1])
    # 先核最坏所有高度全占用的解码额；不把PNG文件大小误称显存。
    worst = int(np.prod(last-first)) * len(heights) * mip_bytes(tile+4, tile+4)
    if worst > max_mib * 1024**2:
        raise ValueError(f'worst texture allocation {worst} exceeds offline guard')
    output.mkdir(parents=True)
    rows = []
    for iy in range(first[1], last[1]):
        for ix in range(first[0], last[0]):
            core = np.array([ix*span, iy*span, (ix+1)*span, (iy+1)*span])
            # 两像素共享世界坐标边缘，仅扩纹理采样，不扩几何所有权。
            bounds = core + np.array([-2, -2, 2, 2]) * step
            hit = np.all(high > bounds[:2], axis=1) & np.all(low < bounds[2:], axis=1)
            for index, height in enumerate(heights):
                part = data[hit & (data[:, 0, 1] == height)]
                if not len(part):
                    continue
                pixels = layer_pixels(part, bounds, tile+4)
                if not pixels[2:-2, 2:-2, 3].any():
                    continue
                path = output / f'{ix}_{iy}_{index}.png'
                Image.fromarray(pixels).save(path)
                if not np.array_equal(pixels, np.asarray(Image.open(path))):
                    raise ValueError('texture roundtrip drift')
                rows.append(dict(file=path.name, sha256=sha(path), height=float(height),
                                 geometry_bounds=core.tolist(), texture_bounds=bounds.tolist(),
                                 rgba_mip_bytes=mip_bytes(tile+4, tile+4),
                                 bc3_estimate_only=mip_bytes(tile+4, tile+4, 16)))
    result = dict(schema=1, source=str(source.resolve()), source_sha256=expected,
                  palette_sha256=sha(palette), source_faces=len(data), candidate_faces=len(rows)*2,
                  surfaces_unbatched=len(rows), layers=len(heights), rows=rows,
                  step=step, max_scale=max_scale, source_pixel_output=step*max_scale,
                  rgba_mip_bytes=sum(r['rgba_mip_bytes'] for r in rows),
                  bc3_estimate_only=sum(r['bc3_estimate_only'] for r in rows),
                  height_flattening_error=0, premultiplied_alpha=True,
                  runtime_integrated=False, coverage_proven=False, visual_accepted=False,
                  note='真实层高保留；纹理孔洞/亚像素特征/接缝仍须验收。页数不等于surface数。')
    (output/'manifest.json').write_text(json.dumps(result, indent=2), encoding='utf-8')
    print(json.dumps({k:v for k,v in result.items() if k != 'rows'}, ensure_ascii=False))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source', type=Path)
    parser.add_argument('expected')
    parser.add_argument('output', type=Path)
    parser.add_argument('--step', type=float, default=.25)
    parser.add_argument('--max-scale', type=float, default=5.)
    args = parser.parse_args()
    build(args.source, args.expected, args.output, step=args.step, max_scale=args.max_scale)
