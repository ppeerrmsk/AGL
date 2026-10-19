"""仅重烘包含全局保留原面的高度组；未受影响纹理保留原物理身份。"""
import argparse
import json
import re
from pathlib import Path
import numpy as np
from PIL import Image
from tokyo_full_layer_plan import sha
from tokyo_bake_full_layer_batch import raster, crop_pixels, mip_bytes


def split_members(members, fallback):
    kept, retained = [], []
    for page, face in members:
        (retained if face in fallback[page] else kept).append([page, face])
    return kept, retained


def build(closure_path, expected, output, first, count):
    closure_path, output = Path(closure_path), Path(output)
    if sha(closure_path) != expected or output.exists() or first < 0 or not 0 < count <= 256:
        raise ValueError('invalid closure or batch')
    closure = json.loads(closure_path.read_text(encoding='utf-8'))
    if not closure['all_jobs_present'] or sha(closure['source']['path']) != closure['source']['sha256']:
        raise ValueError('incomplete or drifted plan')
    keys = closure['rebake_jobs'][first:first+count]
    if len(keys) != count or len(set(keys)) != count:
        raise ValueError('invalid job range')
    plan = json.loads(Path(closure['source']['path']).read_text(encoding='utf-8'))
    fallback = []
    for page, row in enumerate(closure['rows']):
        if row['page'] != page or sha(row['path']) != row['sha256']:
            raise ValueError('fallback drift')
        ids = np.fromfile(row['path'], dtype='<u4')
        if len(ids) != row['faces'] or len(np.unique(ids)) != len(ids):
            raise ValueError('fallback count mismatch')
        fallback.append(set(map(int, ids)))
    wanted, jobs = set(keys), {}
    palette_path = Path(__file__).resolve().parents[1]/'experiments/tokyo_palette.gd'
    palette_sha = sha(palette_path)
    pairs = json.loads(re.search(r'const PAIRS := (\{[^}]+\})', palette_path.read_text(encoding='utf-8')).group(1))
    for binding in closure['batches']:
        if sha(binding['path']) != binding['sha256']:
            raise ValueError('batch drift')
        batch = json.loads(Path(binding['path']).read_text(encoding='utf-8'))
        if batch['palette_sha256'] != palette_sha or batch['step'] != 1. or batch['max_scale'] != 1.25:
            raise ValueError('representation drift')
        for row in batch['rows']:
            if row['key'] in wanted:
                if row['key'] in jobs:
                    raise ValueError('duplicate job')
                jobs[row['key']] = row
    if set(jobs) != wanted:
        raise ValueError('missing source jobs')
    output.mkdir(parents=True)
    validated, results = set(), []
    changed_groups = 0
    new_fallback = set()
    for offset, key in enumerate(keys):
        row = jobs[key]
        groups = []
        for group in row['groups']:
            if group['status'] != 'texture_candidate':
                groups.append(group)
                continue
            if sha(group['path']) != group['sha256']:
                raise ValueError('texture drift')
            members, retained = split_members(group['source_faces'], fallback)
            if not retained:
                groups.append(group)
                continue
            changed_groups += 1
            groups.append({'height':group['height'], 'status':'native_global_fallback', 'source_faces':retained})
            if not members:
                continue  # 全部保留原生时不能残留旧四边形。
            chunks = []
            for page in sorted({p for p, _ in members}):
                source = plan['rows'][page]['source']
                if page not in validated:
                    if sha(source['path']) != source['sha256']:
                        raise ValueError('attribute drift')
                    validated.add(page)
                data = np.memmap(source['path'], dtype='<f4', mode='r', shape=(source['faces'],3,10))
                chunks.append(np.array(data[[face for p,face in members if p == page]]))
                del data
            data = np.concatenate(chunks)
            for old, new in pairs.items():
                rgb = np.array(list(bytes.fromhex(old)), dtype=np.float32)/255
                hit = (np.abs(data[:,:,6:9]-rgb)<.0000039).all(axis=2)
                data[:,:,6:9][hit] = np.array(list(bytes.fromhex(new)), dtype=np.float32)/255
            replacement = {'height':group['height'], 'source_faces':members}
            try:
                pixels = raster(data, np.array(row['texture_bounds']), 1.)
                if not pixels[2:-2,2:-2,3].any():
                    replacement['status'] = 'native_no_core_samples'
                else:
                    cropped, rect = crop_pixels(pixels)
                    path = output/f'{first+offset:05d}_{len(groups):04d}.png'
                    Image.fromarray(cropped).save(path)
                    if not np.array_equal(np.asarray(Image.open(path)),cropped):
                        raise ValueError('saved pixels differ')
                    replacement.update(status='texture_candidate', path=str(path.resolve()),sha256=sha(path),
                                       crop=rect,width=cropped.shape[1],height_pixels=cropped.shape[0],
                                       rgba_three_copy_mip_bytes=3*mip_bytes(cropped.shape[1],cropped.shape[0]))
            except ValueError as error:
                if str(error) != 'ambiguous same-height colors':
                    raise
                replacement['status'] = 'native_color_conflict'
            if replacement['status'] != 'texture_candidate':
                new_fallback.update(map(tuple, members))
            groups.append(replacement)
        results.append(dict(row, groups=groups))
        print(f'rebake={first+offset+1}/{len(closure["rebake_jobs"])}', flush=True)
    report = {'closure':{'path':str(closure_path.resolve()),'sha256':expected},
              'source':closure['source'],'first':first,'count':count,'rows':results,
              'changed_groups':changed_groups,'new_fallback':sorted(new_fallback),
              'source_removal_authorized':False,'runtime_integrated':False}
    (output/'manifest.json').write_text(json.dumps(report,separators=(',',':')),encoding='utf-8')


if __name__ == '__main__':
    p=argparse.ArgumentParser()
    p.add_argument('closure');p.add_argument('sha');p.add_argument('output')
    p.add_argument('--first',type=int,required=True);p.add_argument('--count',type=int,required=True)
    a=p.parse_args();build(a.closure,a.sha,a.output,a.first,a.count)
