"""同源地表实际截图独立审计：色彩控制、区外变化和恢复，保留blocked机位。"""
import argparse
import json
from pathlib import Path
import numpy as np
from PIL import Image, ImageFilter


def audit(directory):
    report = json.loads((directory / 'r71_review.json').read_bytes())
    rows = []
    def pixels(stem, suffix):
        return np.asarray(Image.open(str(stem) + suffix + '.png').convert('RGBA'), dtype=np.int16)
    for row in report['rows']:
        if 'blocked' in row:
            rows.append({'pose': row['pose'], 'blocked': row['blocked']})
            continue
        stem = Path(row['stem'])
        ground = pixels(stem, '_ground_only_native')
        control = np.abs(pixels(stem, '_ground_only') - pixels(stem, '_2d')).max(axis=2)
        mask = ground[:, :, 3] == 255
        core = np.asarray(Image.fromarray((mask*255).astype(np.uint8)).filter(ImageFilter.MinFilter(7))) > 0
        allowed = np.asarray(Image.fromarray(((ground[:,:,3]>0)*255).astype(np.uint8)).filter(ImageFilter.MaxFilter(7))) > 0
        original = pixels(stem, '_original_native')
        delta = np.abs(pixels(stem, '_candidate_native') - original).max(axis=2)
        restore = np.abs(pixels(stem, '_restored_native') - original).max()
        color = control[core]
        rows.append({'pose': row['pose'], 'native_fallback': row['ground'].get('native_fallback',False),
            'control_pixels': int(core.sum()), 'control_mean': float(color.mean()) if len(color) else 0,
            'control_p99': float(np.percentile(color,99)) if len(color) else 0,
            'control_max': int(color.max()) if len(color) else 0,
            'control_gt1': int((color>1).sum()), 'outside_gt1': int(((delta>1)&~allowed).sum()),
            'restore_max': int(restore), 'changed_pixels': int((delta>1).sum()),
            'extra_planes': row['ground']['planes'], 'extra_bytes': row['ground']['reserved_bytes'],
            'actual_faces_before': row['ground'].get('actual_faces_before'), 'actual_faces_after': row['ground'].get('actual_faces_after'),
            'retired_fixed_faces': row['ground'].get('retired_fixed_faces',0)})
    result = {'rows':rows, 'route_fail':report['fail'], 'pixel_fail':sum('blocked' not in r and (r['control_gt1']>0 or r['outside_gt1']>0 or r['restore_max']>1) for r in rows)}
    (directory/'r71_independent.json').write_text(json.dumps(result,indent=2),encoding='utf8')
    print(json.dumps(result))
    return int(report['fail']!=0 or result['pixel_fail']!=0)


if __name__ == '__main__':
    parser=argparse.ArgumentParser()
    parser.add_argument('directory',type=Path)
    raise SystemExit(audit(parser.parse_args().directory))
