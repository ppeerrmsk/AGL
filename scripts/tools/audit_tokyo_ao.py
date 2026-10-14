"""独立资产、面积平均和真实原生截图范围审计；不重写图片或源几何。"""
import hashlib
import json
import sys
from pathlib import Path
import numpy as np
from PIL import Image


def audit(source, assets, images, reference=None):
    output = images/'r64_independent_ao_audit.json'
    if output.exists():
        raise ValueError('do not overwrite audit evidence')
    manifest = json.loads((assets/'manifest.json').read_bytes())
    fail = int(hashlib.sha256(source.read_bytes()).hexdigest() != manifest['source_sha256'])
    data = json.loads(source.read_bytes())
    for row in data['sources']:
        fail += int(hashlib.sha256(Path(row['path']).read_bytes()).hexdigest() != row['sha256'])
    master = np.asarray(Image.open(assets/'ao_2048.png'), dtype=np.float64)
    indexed = manifest.get('height_encoding') == 'global_palette_r8'
    if indexed:
        palette = np.asarray(Image.open(assets/manifest['palette']), dtype=np.uint16)
        fail += int(palette.shape != (1, 256, 3))
        fail += int(hashlib.sha256((assets/manifest['palette']).read_bytes()).hexdigest() != manifest['palette_sha256'])
        indices = np.asarray(Image.open(assets/manifest['rows'][0]['height']))
        decoded = (palette[0, :, 0]*256+palette[0, :, 1])[indices]
        original = np.asarray(Image.open(reference/'height_2048.png'), dtype=np.uint16)
        fail += int(hashlib.sha256((reference/'height_2048.png').read_bytes()).hexdigest() != manifest['original_height_sha256'])
        fail += int(not np.array_equal(decoded, original[:, :, 0]*256+original[:, :, 1]))
    mips = []
    for row in manifest['rows']:
        size = row['size']
        for field in ['ao', 'height']:
            fail += int(hashlib.sha256((assets/row[field]).read_bytes()).hexdigest() != row[field+'_sha256'])
        ao = np.asarray(Image.open(assets/row['ao']), dtype=np.float64)
        h = np.asarray(Image.open(assets/row['height']), dtype=np.uint16)
        fail += int(ao.shape != (size, size))
        fail += int(h.shape != (2048, 2048)) if indexed else int(h.shape != (size, size, 3) or not np.all(h[:, :, 2] == 0))
        step = 2048//size
        reference = master.reshape(size, step, size, step).mean((1, 3))
        error = np.abs(reference-ao)
        mips.append({'size': size, 'area_mean_error': float(error.mean()), 'max_error': float(error.max())})
        if manifest.get('lod_filter') == 'highest_native_bake_area_average':
            fail += int(error.max() > 1)
    review = json.loads((images/'r64_ao_review.json').read_bytes())
    fail += review['fail']
    fail += int(len(review['rows']) != 8)
    records = []
    for row in review['rows']:
        if row.get('rejected'):
            continue
        stem = row['stem']
        before = np.asarray(Image.open(stem+'_none_native.png').convert('RGBA'), dtype=np.int16)
        mask = np.zeros(before.shape[:2], dtype=bool)
        for x0, y0, x1, y1 in row['allowed_screen_bounds']:
            x0, x1 = max(0, int(np.floor(x0-2))), min(mask.shape[1], int(np.ceil(x1+2)))
            y0, y1 = max(0, int(np.floor(y0-2))), min(mask.shape[0], int(np.ceil(y1+2)))
            if x1 > x0 and y1 > y0:
                mask[y0:y1, x0:x1] = True
        fail += int(not row['geometry_collision_unchanged'] or row['state']['output_scale'] > row['ao']['max_scale']
                    or row['ao']['conservative_resident_bytes'] > 96*1024*1024)
        for name in ['zero', 'restored', 'ao45', 'ao75']:
            current = np.asarray(Image.open(stem+'_'+name+'_native.png').convert('RGBA'), dtype=np.int16)
            delta = np.abs(before-current)
            outside = int(((delta.max(2)>1)&~mask).sum())
            fail += int(outside != 0 or (name in ['zero', 'restored'] and delta.max()>1))
            fail += int(not np.array_equal(before[:, :, 3], current[:, :, 3]))
            records.append({'zoom': row['zoom'], 'rotation': row['rotation'], 'mode': name,
                            'outside_gt1': outside, 'changed_pixels_gt1': int((delta.max(2)>1).sum()),
                            'max_channel_error': int(delta.max()), 'rgb_mean_error': float(delta[:, :, :3].mean())})
        fine_path = Path(stem+'_finer45_native.png')
        if fine_path.exists():
            fine = np.asarray(Image.open(fine_path).convert('RGB'), dtype=np.int16)
            coarse = np.asarray(Image.open(stem+'_ao45_native.png').convert('RGB'), dtype=np.int16)
            difference = np.abs(fine-coarse)
            records.append({'zoom': row['zoom'], 'rotation': row['rotation'], 'mode': 'same_view_next_resolution',
                            'max_channel_error': int(difference.max()), 'rgb_mean_error': float(difference.mean()),
                            'pixels_gt2': int((difference.max(2)>2).sum())})
            for name in ['only_ao_finer', 'only_height_finer']:
                path = Path(stem+'_'+name+'_native.png')
                if path.exists():
                    current = np.asarray(Image.open(path).convert('RGB'), dtype=np.int16)
                    delta = np.abs(current-coarse)
                    records.append({'zoom': row['zoom'], 'rotation': row['rotation'], 'mode': name,
                                    'max_channel_error': int(delta.max()), 'rgb_mean_error': float(delta.mean()),
                                    'pixels_gt2': int((delta.max(2)>2).sum())})
    unchanged = len(review['rows']) == 8 and all(r.get('geometry_collision_unchanged', False) for r in review['rows'])
    result = {'fail': fail, 'mips': mips, 'records': records, 'geometry_unchanged': unchanged,
              'horizontal_only': True, 'continuous_handoff_accepted': False}
    output.write_text(json.dumps(result, indent=2), encoding='utf-8')
    print(json.dumps(result))
    return int(fail > 0)


if __name__ == '__main__':
    raise SystemExit(audit(*map(Path, sys.argv[1:])))
