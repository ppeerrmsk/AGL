"""从绑定的未过滤原生缓存恢复既有色板；复用全图AO和几何，不覆盖旧资产。"""
from __future__ import annotations

import argparse
import json
import re
from pathlib import Path

import numpy as np
from PIL import Image

from audit_tokyo_art_lineage import digest


def binding(path: Path) -> dict:
    return {'path': str(path.resolve()), 'sha256': digest(path)}


def checked(row: dict) -> Path:
    path = Path(row['path'])
    if digest(path) != row['sha256']:
        raise ValueError(f'Source digest mismatch: {path}')
    return path


def remap(colors: np.ndarray, pairs: dict[str, str]) -> tuple[np.ndarray, dict[str, int]]:
    result = colors.copy()
    source = colors[..., :3] * 255.0
    counts = {}
    for old, new in pairs.items():
        old_rgb = np.array([int(old[i:i+2], 16) for i in (0, 2, 4)])
        new_rgb = np.array([int(new[i:i+2], 16) for i in (0, 2, 4)]) / 255.0
        # 只认原始平坦RGBA8类别；不把滤波混合色或透明样本硬归到最近颜色。
        mask = np.all(np.abs(source - old_rgb) < 0.001, axis=-1) & (colors[..., 3] == 1)
        result[..., :3][mask] = new_rgb
        counts[old] = int(mask.sum())
    return result, counts


def compose(colors: np.ndarray, ao: np.ndarray) -> np.ndarray:
    alpha = colors[..., 3:4]
    value = np.concatenate((colors[..., :3] * alpha * (1 - .22 * ao[..., None] / 255), alpha), axis=-1)
    return np.rint(np.clip(value, 0, 1) * 255).astype(np.uint8)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    if args.output.exists():
        raise FileExistsError(args.output)
    source = json.loads(args.source.read_text(encoding='utf8'))
    if source.get('palette_restored'):
        raise ValueError('Already restored; do not apply twice')
    cache_path = checked(source['native_cache'])
    cache = json.loads(cache_path.read_text(encoding='utf8'))
    archive_path = checked(cache['cache'])
    ao_path = checked(source['ao_source'])
    original_path = checked(source['texture'])
    checked(source['proxy_height_source'])
    palette_path = Path(__file__).resolve().parents[1] / 'experiments/tokyo_palette.gd'
    pairs = dict(re.findall(r'"([0-9a-f]{6})":\s*"([0-9a-f]{6})"', palette_path.read_text(encoding='utf8')))
    assert len(pairs) == 11 and source['tiles'] == 256
    with np.load(archive_path, allow_pickle=False) as archive:
        colors = archive['colors']
    ao = np.asarray(Image.open(ao_path))
    original = np.asarray(Image.open(original_path))
    assert colors.shape == original.shape and ao.shape == colors.shape[:2]
    pixels = np.empty_like(original)
    totals = dict.fromkeys(pairs, 0)
    for start in range(0, len(colors), 128):
        stop = min(start + 128, len(colors))
        raw = colors[start:stop]
        # 复算旧颜色必须逐像素相等，证明缓存/AO/合成顺序确为当前纹理来源。
        assert np.array_equal(compose(raw, ao[start:stop]), original[start:stop]), f'Unreproducible source rows {start}'
        mapped, counts = remap(raw, pairs)
        pixels[start:stop] = compose(mapped, ao[start:stop])
        assert np.array_equal(pixels[start:stop, :, 3], original[start:stop, :, 3])
        for key in totals:
            totals[key] += counts[key]
        if start % 1024 == 0:
            print(f'Palette rows {stop}/{len(colors)}; source reproduction exact', flush=True)
    assert sum(totals.values()) > 0
    args.output.mkdir(parents=True)
    texture_path = args.output / 'color.png'
    Image.fromarray(pixels).save(texture_path)
    assert np.array_equal(np.asarray(Image.open(texture_path)), pixels)
    result = dict(source)
    result.update(texture=binding(texture_path), palette_restored=True, palette_source=binding(palette_path),
                  palette_counts=totals, palette_parent=binding(args.source), source_reproduction_exact=True,
                  alpha_unchanged=True, geometry_rebuilt=False, ao_rebaked=False,
                  runtime_integrated=False, visual_accepted=False)
    with (args.output / 'manifest.json').open('x', encoding='utf8') as stream:
        json.dump(result, stream, ensure_ascii=False, indent=2)
    print('Restored samples', sum(totals.values()), 'geometry and AO reused; runtime not installed', flush=True)


if __name__ == '__main__':
    main()
