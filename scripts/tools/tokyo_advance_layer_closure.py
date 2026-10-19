"""以完整重烘集合推进回退闭合；验证逐面/逐高度守恒，不提前授权源删除。"""
import argparse
from collections import Counter
import json
from pathlib import Path
import numpy as np
from tokyo_full_layer_plan import sha
from tokyo_layer_fallback_closure import build as close_layers


def face_contract(row):
    return Counter((page, face, group['height'])
                   for group in row['groups'] for page, face in group['source_faces'])


def verify_replacement(original, replacement, retained=None):
    for field in ('key', 'owner_bounds', 'texture_bounds'):
        if original[field] != replacement[field]:
            raise ValueError('replacement spatial contract drift')
    if face_contract(original) != face_contract(replacement):
        raise ValueError('replacement source or height drift')
    unsafe = {(p,f) for group in original['groups'] if group['status'] != 'texture_candidate'
              for p,f in group['source_faces']}
    for group in replacement['groups']:
        if group['status'] == 'texture_candidate':
            for p,f in group['source_faces']:
                if (p,f) in unsafe or (retained is not None and f in retained[p]):
                    raise ValueError('retained source still rasterized')


def build(source, expected, batch_root, output):
    source, output = Path(source), Path(output)
    if sha(source) != expected or output.exists():
        raise ValueError('closure drift or existing output')
    closure = json.loads(source.read_text(encoding='utf-8'))
    keys = closure['rebake_jobs']
    if not keys or len(set(keys)) != len(keys):
        raise ValueError('no unique rebake work')
    retained = []
    for page, row in enumerate(closure['rows']):
        if row['page'] != page or sha(row['path']) != row['sha256']:
            raise ValueError('retained identity drift')
        ids = np.fromfile(row['path'],dtype='<u4')
        if len(ids) != row['faces']:
            raise ValueError('retained count drift')
        retained.append(set(map(int,ids)))
    replacements, bindings = {}, []
    for path in sorted(Path(batch_root).glob('tokyo-installed-rebake-*/manifest.json')):
        batch = json.loads(path.read_text(encoding='utf-8'))
        if batch['closure']['sha256'] != expected:
            continue
        if batch['source'] != closure['source'] or len(batch['rows']) != batch['count'] or batch['first'] < 0:
            raise ValueError('invalid rebake binding')
        for offset, row in enumerate(batch['rows']):
            index = batch['first']+offset
            if index >= len(keys) or row['key'] != keys[index] or row['key'] in replacements:
                raise ValueError('duplicate or shifted rebake')
            replacements[row['key']] = row
        bindings.append({'path':str(path.resolve()),'sha256':sha(path)})
    if set(replacements) != set(keys):
        raise ValueError(f'incomplete rebakes: {len(replacements)}/{len(keys)}')
    # 先验证所有替换分区，再创建任何后继合同文件。
    checked = set()
    for binding in closure['batches']:
        if sha(binding['path']) != binding['sha256']:
            raise ValueError('original batch drift')
        batch = json.loads(Path(binding['path']).read_text(encoding='utf-8'))
        for row in batch['rows']:
            if row['key'] in replacements:
                verify_replacement(row, replacements[row['key']], retained)
                if row['key'] in checked:
                    raise ValueError('duplicate original job')
                checked.add(row['key'])
    if checked != set(keys):
        raise ValueError('original job missing')
    merged = output/'merged'
    merged.mkdir(parents=True)
    for index, binding in enumerate(closure['batches']):
        batch = json.loads(Path(binding['path']).read_text(encoding='utf-8'))
        batch['rows'] = [replacements.get(row['key'], row) for row in batch['rows']]
        target = merged/f'tokyo-installed-bake-{index:05d}'
        target.mkdir()
        (target/'manifest.json').write_text(json.dumps(batch,separators=(',',':')),encoding='utf-8')
    (output/'lineage.json').write_text(json.dumps({'parent':{'path':str(source.resolve()),'sha256':expected},
        'rebakes':bindings,'source_removal_authorized':False},separators=(',',':')),encoding='utf-8')
    close_layers(closure['source']['path'],closure['source']['sha256'],merged,output/'closure')


if __name__ == '__main__':
    p=argparse.ArgumentParser()
    p.add_argument('source');p.add_argument('sha');p.add_argument('batch_root');p.add_argument('output')
    a=p.parse_args();build(a.source,a.sha,a.batch_root,a.output)
