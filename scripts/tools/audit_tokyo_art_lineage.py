"""核对旧色板是否沿用到HLOD原始屋顶输入；只审计，不重烘或修改资产。"""
from __future__ import annotations

import argparse
import hashlib
import json
import re
from pathlib import Path

import numpy as np


def digest(path: Path) -> str:
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def roof_colors(path: Path) -> dict[str, int]:
    data = np.memmap(path, dtype='<f4', mode='r').reshape(-1, 3, 10)
    # 按向上屋顶计数，避免将大量侧墙颜色误报成屋顶。
    upward = data[:, :, 4].mean(axis=1) > 0.5
    colors = np.rint(data[upward, 0, 6:9] * 255).astype(np.int32)
    unique, counts = np.unique(colors, axis=0, return_counts=True)
    return {''.join(f'{int(channel):02x}' for channel in color): int(count)
            for color, count in zip(unique, counts)}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[2]
    base = root / 'tmp/tokyo-bay-volume'
    palette = root / 'scripts/experiments/tokyo_palette.gd'
    pairs = dict(re.findall(r'"([0-9a-f]{6})":\s*"([0-9a-f]{6})"', palette.read_text(encoding='utf8')))
    assert len(pairs) == 11
    references = [
        ('user_latest_color_priority', base / 'approved-art-reference/user-selected.png'),
        ('r3_approved_style_not_all_details', root / 'bench/results/tokyo_volume_r3_close_135.png'),
        ('r152_154_approved_massing_not_palette', base / 'r154-lit-preview-a/view_450_variant_0.png'),
    ]
    result = {'schema': 1, 'read_only_sources': True, 'runtime_installed': False,
              'visual_accepted': False, 'scope': 'three_source_tiles_not_whole_map',
              'references': [{'role': role, 'path': str(path), 'sha256': digest(path)}
                             for role, path in references],
              'palette': {'path': str(palette), 'sha256': digest(palette), 'pairs': pairs},
              'tiles': []}
    for tile in ['detail_06_06', 'detail_07_01', 'detail_12_12']:
        directory = base / f'r345-{tile}-layers-a'
        manifest_path = directory / 'manifest.json'
        manifest = json.loads(manifest_path.read_text(encoding='utf8'))
        layers = []
        for layer in manifest['layers'][:2]:
            path = directory / (layer['file'] + '.attributes')
            actual = digest(path)
            assert actual == layer['attributes_sha256'], f'changed source: {path}'
            counts = roof_colors(path)
            layers.append({'layer': layer['layer'], 'path': str(path), 'sha256': actual,
                           'upward_triangles': sum(counts.values()), 'rgb_triangle_counts': counts,
                           'unmapped_old_palette_triangles': sum(counts.get(key, 0) for key in pairs),
                           'already_mapped_palette_triangles': sum(counts.get(key, 0) for key in pairs.values())})
        result['tiles'].append({'tile': tile, 'manifest_sha256': digest(manifest_path), 'layers': layers})
    # 只创建新报告，防止覆盖先前证据；不把采样审计当成全图色板验证。
    with args.output.open('x', encoding='utf8') as stream:
        json.dump(result, stream, ensure_ascii=False, indent=2)
    for tile in result['tiles']:
        print(tile['tile'], [(row['layer'], row['upward_triangles'],
                             row['unmapped_old_palette_triangles'], row['already_mapped_palette_triangles'])
                            for row in tile['layers']])


if __name__ == '__main__':
    main()
