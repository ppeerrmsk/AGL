"""R65 全局高度调色板：编码逐像素无损；超过256种值拒绝，不量化楼高。"""
import hashlib
import json
import shutil
import sys
from pathlib import Path
import numpy as np
from PIL import Image


def pack(codes):
    if codes.ndim != 2 or codes.dtype != np.uint16:
        raise ValueError('expected uint16 height field')
    values, indices = np.unique(codes, return_inverse=True)
    if len(values) > 256:
        raise ValueError('height palette overflow; never quantize')
    palette = np.full(256, 65535, dtype=np.uint16)
    palette[:len(values)] = values
    return indices.reshape(codes.shape).astype(np.uint8), palette


def build(source, output):
    if output.exists():
        raise ValueError('never overwrite evidence')
    manifest = json.loads((source/'manifest.json').read_bytes())
    for row in manifest['rows']:
        for field in ['ao', 'height']:
            if hashlib.sha256((source/row[field]).read_bytes()).hexdigest() != row[field+'_sha256']:
                raise ValueError('source asset hash drift')
    master = next(row for row in manifest['rows'] if row['size'] == 2048)
    original_height_sha = master['height_sha256']
    raw = np.asarray(Image.open(source/master['height']), dtype=np.uint16)
    if raw.shape != (2048, 2048, 3) or np.any(raw[:, :, 2]):
        raise ValueError('invalid height format')
    codes = raw[:, :, 0]*256 + raw[:, :, 1]
    indices, palette = pack(codes)
    rgb = np.zeros((1, 256, 3), dtype=np.uint8)
    rgb[0, :, 0], rgb[0, :, 1] = palette >> 8, palette & 255
    output.mkdir(parents=True)
    Image.fromarray(indices).save(output/'height_indices.png')
    Image.fromarray(rgb).save(output/'height_palette.png')
    saved_indices = np.asarray(Image.open(output/'height_indices.png'))
    saved_palette = np.asarray(Image.open(output/'height_palette.png'), dtype=np.uint16)
    decoded = (saved_palette[0, :, 0]*256 + saved_palette[0, :, 1])[saved_indices]
    if not np.array_equal(decoded, codes):
        raise ValueError('lossless roundtrip failed')
    for row in manifest['rows']:
        shutil.copyfile(source/row['ao'], output/row['ao'])
        row['height'] = 'height_indices.png'
        row['height_sha256'] = hashlib.sha256((output/row['height']).read_bytes()).hexdigest()
        row['conservative_bytes'] = row['size']**2*4 + 2048**2*3 + 256*2*3
    manifest.update(height_encoding='global_palette_r8', height_size=2048,
                    palette='height_palette.png',
                    palette_sha256=hashlib.sha256((output/'height_palette.png').read_bytes()).hexdigest(),
                    original_height_sha256=original_height_sha,
                    unique_height_codes=int(len(np.unique(codes))), lossless_pixels=int(codes.size))
    (output/'manifest.json').write_text(json.dumps(manifest, indent=2), encoding='utf-8')
    print(json.dumps({'unique_codes': manifest['unique_height_codes'], 'lossless_pixels': codes.size,
                      'texture_height_bytes': indices.nbytes+512}))


if __name__ == '__main__':
    build(*map(Path, sys.argv[1:]))
