"""完成全部生产批次后，闭合跨图块原面回退；输出重烘清单，不直接授予隐藏资格。"""
import argparse
import json
from pathlib import Path
import numpy as np
from tokyo_full_layer_plan import sha


def mark_group(group, allowed, eligible, seen, fallback):
    unsafe = group['status'] != 'texture_candidate'
    if group['status'] not in ('texture_candidate','native_color_conflict','native_no_core_samples','native_no_face_saving','native_global_fallback'):
        raise ValueError('unknown raster status')
    for page, face in group['source_faces']:
        if page not in allowed or not 0 <= face < len(eligible[page]) or not eligible[page][face]:
            raise ValueError('source face outside job contract')
        seen[page][face] = True
        if unsafe:
            fallback[page][face] = True


def build(source, expected, batch_root, output):
    source, output = Path(source), Path(output)
    if sha(source) != expected or output.exists():raise ValueError('source drift or existing output')
    plan=json.loads(source.read_text(encoding='utf-8'))
    eligible=[];seen=[];fallback=[]
    for row in plan['rows']:
        if sha(row['planar_ids'])!=row['ids_sha256']:raise ValueError('ids drift')
        mask=np.zeros(row['source']['faces'],dtype=bool)
        ids=np.fromfile(row['planar_ids'],dtype='<u4')
        if len(ids)!=row['planar_faces'] or len(np.unique(ids))!=len(ids) or (len(ids) and ids.max()>=len(mask)):
            raise ValueError('invalid planar ids')
        mask[ids]=True;eligible.append(mask);seen.append(np.zeros_like(mask));fallback.append(np.zeros_like(mask))
    complete={};bindings=[]
    keys=sorted(plan['jobs'],key=lambda key:tuple(map(int,key.split(':'))))
    for path in sorted(Path(batch_root).glob('tokyo-installed-bake-*/manifest.json')):
        batch=json.loads(path.read_text(encoding='utf-8'))
        if batch['source']['sha256']!=expected:continue
        if batch['step']!=1. or batch['max_scale']!=1.25 or len(batch['rows'])!=batch['count']:
            raise ValueError('mixed representation or incomplete batch')
        for offset,row in enumerate(batch['rows']):
            index=batch['first']+offset
            if index>=len(keys) or row['key']!=keys[index] or row['key'] in complete:
                raise ValueError('duplicate or shifted job')
            complete[row['key']]=True
            for group in row['groups']:
                mark_group(group,plan['jobs'][row['key']],eligible,seen,fallback)
                if group['status']=='texture_candidate' and sha(group['path'])!=group['sha256']:
                    raise ValueError('texture drift')
        bindings.append({'path':str(path.resolve()),'sha256':sha(path)})
    if len(complete)!=len(keys):raise ValueError(f'incomplete full-map jobs: {len(complete)}/{len(keys)}')
    if any(not np.array_equal(a,b) for a,b in zip(eligible,seen)):raise ValueError('planar face absent from all jobs')
    rebake=[]
    for binding in bindings:
        batch=json.loads(Path(binding['path']).read_text(encoding='utf-8'))
        for row in batch['rows']:
            if any(group['status']=='texture_candidate' and any(fallback[p][f] for p,f in group['source_faces']) for group in row['groups']):
                rebake.append(row['key'])
    output.mkdir(parents=True)
    rows=[]
    for page,mask in enumerate(fallback):
        path=output/f'page_{page:05d}.u32'
        ids=np.flatnonzero(mask).astype('<u4');path.write_bytes(ids.tobytes())
        rows.append({'page':page,'path':str(path.resolve()),'sha256':sha(path),'faces':len(ids)})
    result={'source':{'path':str(source.resolve()),'sha256':expected},'batches':bindings,'rows':rows,
            'rebake_jobs':rebake,'total_jobs':len(keys),'fallback_faces':sum(r['faces'] for r in rows),
            'all_jobs_present':True,'source_removal_authorized':False,'rebake_complete':False}
    (output/'manifest.json').write_text(json.dumps(result,separators=(',',':')),encoding='utf-8')
    print(json.dumps({'fallback_faces':result['fallback_faces'],'rebake_jobs':len(rebake)}))


if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('source');p.add_argument('sha');p.add_argument('batch_root');p.add_argument('output')
    a=p.parse_args();build(a.source,a.sha,a.batch_root,a.output)
