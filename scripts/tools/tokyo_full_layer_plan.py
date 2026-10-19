"""正式全图水平面分块输入；只建稀疏来源索引，不删面或授予运行时资格。"""
import argparse
import hashlib
import json
from pathlib import Path

import numpy as np


def sha(path):
    digest = hashlib.sha256()
    with Path(path).open('rb') as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b''):
            digest.update(block)
    return digest.hexdigest()


def eligible(data):
    xyz = data[:, :, :3].astype(np.float64)
    normal = np.cross(xyz[:, 2] - xyz[:, 0], xyz[:, 1] - xyz[:, 0])
    # 不用容差把斜面或渐变色变成水平面；真实高度保留。
    return ((xyz[:, :, 1] == xyz[:, :1, 1]).all(axis=1)
            & (normal[:, 1] > 0)
            & (data[:, :, 6:10] == data[:, :1, 6:10]).all(axis=(1, 2))
            & (data[:, :, 9] == 1).all(axis=1))


def tile_sources(low, high, span=256, padding=2):
    if not len(low):
        return []
    first = np.floor((low.min(axis=0) - padding) / span).astype(int)
    last = np.floor((high.max(axis=0) + padding) / span).astype(int)
    result = []
    for z in range(first[1], last[1] + 1):
        for x in range(first[0], last[0] + 1):
            a = np.array([x * span - padding, z * span - padding])
            b = a + span + 2 * padding
            if np.any(((high >= a) & (low <= b)).all(axis=1)):
                result.append((x, z))
    return result


def build(source, expected, output):
    source, output = Path(source), Path(output)
    if sha(source) != expected or output.exists():
        raise ValueError('source drift or existing output')
    manifest = json.loads(source.read_text())
    output.mkdir(parents=True)
    jobs, rows = {}, []
    totals, planar = [0, 0, 0], [0, 0, 0]
    for index, row in enumerate(manifest['rows']):
        path = Path(row['path'])
        if sha(path) != row['sha256'] or path.stat().st_size != row['faces'] * 120:
            raise ValueError('attribute drift')
        data = np.memmap(path, dtype='<f4', mode='r', shape=(row['faces'], 3, 10))
        if not np.isfinite(data).all():
            raise ValueError('nonfinite source')
        ids = np.flatnonzero(eligible(data)).astype('<u4')
        target = output / f'page_{index:05d}.u32'
        raw = ids.tobytes()
        target.write_bytes(raw)
        if sha(target) != hashlib.sha256(raw).hexdigest():
            raise ValueError('saved ids differ')
        points = data[ids][:, :, [0, 2]]
        cells = tile_sources(points.min(axis=1), points.max(axis=1)) if len(ids) else []
        for x, z in cells:
            jobs.setdefault(f"{row['layer']}:{x}:{z}", []).append(index)
        rows.append({'source': row, 'planar_ids': str(target.resolve()), 'ids_sha256': sha(target),
                     'planar_faces': len(ids), 'native_faces': row['faces'] - len(ids)})
        totals[row['layer']] += row['faces']
        planar[row['layer']] += len(ids)
        del data
        if (index + 1) % 512 == 0:
            print(f'pages={index + 1} planar={planar}', flush=True)
    if totals != manifest['layer_faces']:
        raise ValueError('incomplete layer totals')
    result = {'source': {'path': str(source.resolve()), 'sha256': expected}, 'span': 256,
              'padding_world': 2, 'rows': rows, 'jobs': jobs, 'layer_faces': totals,
              'planar_faces': planar, 'native_faces': [a-b for a,b in zip(totals, planar)],
              'high_layer_retained_native': True, 'conflicts_resolved': False,
              'geometry_removed': False, 'runtime_integrated': False}
    (output / 'manifest.json').write_text(json.dumps(result, separators=(',', ':')))
    print(json.dumps({'pages': len(rows), 'jobs': len(jobs), 'planar_faces': planar,
                      'native_faces': result['native_faces']}))


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('source'); parser.add_argument('sha'); parser.add_argument('output')
    args = parser.parse_args()
    build(args.source, args.sha, args.output)
