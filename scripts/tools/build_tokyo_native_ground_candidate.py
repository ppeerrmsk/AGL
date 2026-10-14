"""从已校验组件的地面属性烘焙候选；不混入屋顶，不授予覆盖/美术资格。"""
import argparse
import hashlib
import json
import re
from pathlib import Path

import numpy as np
from PIL import Image
from build_tokyo_fixed_atlas import raster, validate, mip_bytes


def binding(path):
    return dict(path=str(path.resolve()), sha256=hashlib.sha256(path.read_bytes()).hexdigest())


def bake(source, expected, output, palette, opaque_padding=False):
    if binding(source)['sha256'] != expected or output.exists():
        raise ValueError('source drift or output already exists')
    report = json.loads(source.read_bytes())
    rows = report.get('ground_export', {})
    if not rows or not report.get('diagnostic_only') or report.get('runtime_integrated'):
        raise ValueError('not an independent ground source')
    # 与native_code在顶点阶段相同的精确匹配；不得对已经过滤的像素再映射。
    match = re.search(r'const PAIRS := (\{[^}]+\})', palette.read_text(encoding='utf-8'))
    if not match:
        raise ValueError('palette schema drift')
    pairs = json.loads(match.group(1))
    output.mkdir(parents=True)
    result = {}
    for key, row in sorted(rows.items(), key=lambda item: item[1]['path']):
        path = Path(row['path'])
        if binding(path)['sha256'] != row['sha256']:
            raise ValueError('ground attribute drift')
        data = np.fromfile(path, dtype='<f4').reshape(-1, 3, 10)
        if len(data) != row['triangles']:
            raise ValueError('ground triangle count drift')
        validate(data)  # 拒绝坡面、立墙、透明、非恒色三角；不悄悄丢弃桥梁。
        for old, new in pairs.items():
            old_rgb = np.array(list(bytes.fromhex(old)), dtype=np.float32) / 255
            new_rgb = np.array(list(bytes.fromhex(new)), dtype=np.float32) / 255
            selected = np.all(np.abs(data[:, :, 6:9] - old_rgb) < .0000039, axis=2) & (data[:, :, 9] == 1)
            data[:, :, 6:9][selected] = new_rgb
        step, max_scale = {'lod3_full': (1., .75), 'lod4_full': (.75, 1.25),
                           'lod5_full': (.5, 1.6666666667)}[row['configuration']]
        if step * max_scale > 1.25:
            raise ValueError('clarity budget exceeded')
        # 仅在原始三角集合精确覆盖矩形时允许延展纹理边缘；GPU几何仍裁到原footprint。
        pixels, info = raster(data, step, supersample=2, opaque_padding=opaque_padding)
        png = output / (path.stem + '.png')
        Image.fromarray(pixels).save(png)
        if not np.array_equal(pixels, np.asarray(Image.open(png))):
            raise ValueError('PNG roundtrip drift')
        # 此文件是制作样片，尚无GPU接缝/高度误差证明；不冒充安装manifest。
        info['max_scale'] = max_scale
        info['source_pixel_output'] = step * max_scale
        # 与未烘焙邻页的连续最低地面同高；零高度平面会在斜投影接缝漏出背景。
        info['flattened_plane_y'] = float(data[:, :, 1].min())
        info['max_world_height_error'] = float(data[:, :, 1].max() - data[:, :, 1].min())
        info['conservative_three_copy_bytes'] = 3 * mip_bytes(info['width'], info['height'])
        result[key] = dict(source=row, texture=binding(png), raster=info)
        print(json.dumps(dict(page=len(result), total=len(rows), triangles=len(data),
                              width=info['width'], height=info['height'])), flush=True)
    manifest = dict(schema=1, preview_only=True, source=binding(source), palette=binding(palette),
                    package_sha256=report['package_sha256'], rows=result,
                    roof_geometry_baked=False, runtime_integrated=False,
                    seams_accepted=False, height_error_accepted=False, visual_accepted=False,
                    conservative_three_copy_bytes=sum(r['raster']['conservative_three_copy_bytes'] for r in result.values()))
    (output / 'manifest.json').write_text(json.dumps(manifest, indent=2), encoding='utf-8')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source', type=Path)
    parser.add_argument('expected_sha')
    parser.add_argument('output', type=Path)
    parser.add_argument('--palette', type=Path, default=Path('scripts/experiments/tokyo_palette.gd'))
    parser.add_argument('--opaque-padding', action='store_true')
    args = parser.parse_args()
    bake(args.source, args.expected_sha, args.output, args.palette, args.opaque_padding)
