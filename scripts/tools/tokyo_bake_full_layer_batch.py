"""全图索引的有界纹理生产批次；冲突保留为原生候选，尚不授权删除源面。"""
import argparse
import json
import re
from pathlib import Path

import numpy as np
from PIL import Image
from tokyo_full_layer_plan import sha
from build_tokyo_layered_ground import layer_pixels
from pack_tokyo_layered_ground import crop_pixels
from build_tokyo_fixed_atlas import mip_bytes


def raster(data, bounds, step):
    width = (bounds[2] - bounds[0]) / step
    if step <= 0 or width != int(width) or width > 2048:
        raise ValueError('invalid raster dimensions')
    return layer_pixels(data, bounds, int(width))


def build(source, expected, output, first, count, step=1., max_scale=1.25):
    source, output = Path(source), Path(output)
    if sha(source) != expected or output.exists() or first < 0 or not 0 < count <= 256:
        raise ValueError('source drift or invalid batch')
    if step not in (.25, .5, 1.) or not 0 < step * max_scale <= 1.25:
        raise ValueError('clarity bound rejected')
    plan = json.loads(source.read_text(encoding='utf-8'))
    keys = sorted(plan['jobs'], key=lambda key: tuple(map(int, key.split(':'))))
    if first + count > len(keys):
        raise ValueError('batch outside full index')
    palette_path = Path(__file__).resolve().parents[1] / 'experiments/tokyo_palette.gd'
    pairs = json.loads(re.search(r'const PAIRS := (\{[^}]+\})', palette_path.read_text(encoding='utf-8')).group(1))
    output.mkdir(parents=True)
    validated = set()
    results = []
    for offset, key in enumerate(keys[first:first+count]):
        kind, x, z = map(int, key.split(':'))
        owner = np.array([x*256, z*256, (x+1)*256, (z+1)*256], dtype=np.float64)
        bounds = owner + np.array([-2, -2, 2, 2])
        chunks, attribution = [], []
        for page in plan['jobs'][key]:
            row = plan['rows'][page]
            original = row['source']
            if page not in validated:
                if sha(original['path']) != original['sha256'] or sha(row['planar_ids']) != row['ids_sha256']:
                    raise ValueError('page or planar ids drift')
                validated.add(page)
            data = np.memmap(original['path'], dtype='<f4', mode='r', shape=(original['faces'],3,10))
            ids = np.fromfile(row['planar_ids'], dtype='<u4')
            part = data[ids]
            points = part[:,:,[0,2]]
            hit = ((points.max(axis=1) >= bounds[:2]) & (points.min(axis=1) <= bounds[2:])).all(axis=1)
            chunks.append(part[hit])
            attribution.extend((page,int(i)) for i in ids[hit])
            del data
        data = np.concatenate(chunks)
        if not len(data):raise ValueError('indexed job has no source')
        for old,new in pairs.items():
            rgb = np.array(list(bytes.fromhex(old)), dtype=np.float32)/255
            hit = (np.abs(data[:,:,6:9]-rgb)<.0000039).all(axis=2)
            data[:,:,6:9][hit] = np.array(list(bytes.fromhex(new)),dtype=np.float32)/255
        groups = []
        for height in np.unique(data[:,0,1]):
            ids = np.flatnonzero(data[:,0,1] == height)
            members = [attribution[i] for i in ids]
            group = {'height':float(height), 'source_faces':members}
            # 少于一个四边形的来源不烘焙；仍保留完整来源记录。
            if len(ids) <= 2:
                group['status']='native_no_face_saving';groups.append(group);continue
            try:
                pixels = raster(data[ids], bounds, step)
            except ValueError as error:
                if str(error) != 'ambiguous same-height colors':raise
                group['status']='native_color_conflict';groups.append(group);continue
            edge = int(2/step)
            if not pixels[edge:-edge,edge:-edge,3].any():
                group['status']='native_no_core_samples';groups.append(group);continue
            cropped, rect = crop_pixels(pixels)
            path = output / f'{first+offset:05d}_{len(groups):04d}.png'
            Image.fromarray(cropped).save(path)
            if not np.array_equal(np.asarray(Image.open(path)),cropped):
                raise ValueError('saved pixels differ')
            group.update(status='texture_candidate',path=str(path.resolve()),sha256=sha(path),
                         crop=rect,width=cropped.shape[1],height_pixels=cropped.shape[0],
                         rgba_three_copy_mip_bytes=3*mip_bytes(cropped.shape[1],cropped.shape[0]))
            groups.append(group)
        results.append({'key':key,'owner_bounds':owner.tolist(),'texture_bounds':bounds.tolist(),'groups':groups})
        print(f'job={first+offset+1}/{len(keys)} groups={len(groups)}',flush=True)
    result = {'source':{'path':str(source.resolve()),'sha256':expected},'palette_sha256':sha(palette_path),
              'first':first,'count':count,'total_jobs':len(keys),'step':step,'max_scale':max_scale,'rows':results,
              'source_removal_authorized':False,'cross_tile_fallback_closed':False,'runtime_integrated':False}
    (output/'manifest.json').write_text(json.dumps(result,separators=(',',':')),encoding='utf-8')


if __name__ == '__main__':
    parser=argparse.ArgumentParser()
    parser.add_argument('source');parser.add_argument('sha');parser.add_argument('output')
    parser.add_argument('--first',type=int,required=True);parser.add_argument('--count',type=int,required=True)
    parser.add_argument('--step',type=float,default=1.);parser.add_argument('--max-scale',type=float,default=1.25)
    args=parser.parse_args()
    build(args.source,args.sha,args.output,args.first,args.count,args.step,args.max_scale)
