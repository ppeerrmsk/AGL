"""闭合后的候选原生余量批次；复用现有引擎逐角守恒与资源保存回读器。"""
import argparse
import json
from pathlib import Path
import numpy as np
from tokyo_full_layer_plan import sha


def removal_ids(eligible, retained, faces):
    eligible = np.asarray(eligible,dtype='<u4')
    retained = np.asarray(retained,dtype='<u4')
    if len(np.unique(eligible)) != len(eligible) or len(np.unique(retained)) != len(retained):
        raise ValueError('duplicate source ids')
    if len(eligible) and int(eligible.max()) >= faces:
        raise ValueError('source id out of range')
    if not np.isin(retained,eligible).all():
        raise ValueError('retained source outside eligible set')
    return np.setdiff1d(eligible,retained,assume_unique=True)


def build(source, expected, output, max_faces=200000):
    source, output = Path(source), Path(output)
    if sha(source) != expected or output.exists() or max_faces <= 0:
        raise ValueError('invalid closure or destination')
    closure=json.loads(source.read_text(encoding='utf-8'))
    if not closure['all_jobs_present'] or closure['rebake_jobs']:
        raise ValueError('fallback not closed')
    if sha(closure['source']['path']) != closure['source']['sha256']:
        raise ValueError('plan drift')
    plan=json.loads(Path(closure['source']['path']).read_text(encoding='utf-8'))
    if len(plan['rows']) != len(closure['rows']):
        raise ValueError('page count drift')
    tasks=[];unchanged=[];group=[];cost=0
    for page,(row,retained) in enumerate(zip(plan['rows'],closure['rows'])):
        if retained['page'] != page or sha(retained['path']) != retained['sha256'] or sha(row['planar_ids']) != row['ids_sha256']:
            raise ValueError('source ids drift')
        eligible=np.fromfile(row['planar_ids'],dtype='<u4');keep=np.fromfile(retained['path'],dtype='<u4')
        if len(eligible) != row['planar_faces'] or len(keep) != retained['faces']:
            raise ValueError('source count drift')
        original=row['source']
        if original['layer'] not in (0,2):
            raise ValueError('protected high layer in edits')
        remove=removal_ids(eligible,keep,original['faces'])
        if not len(remove):
            unchanged.append({'page':page,'source':original['source']});continue
        if group and cost+original['faces'] > max_faces:
            tasks.append(group);group=[];cost=0
        if original['faces'] > max_faces:
            raise ValueError('single page exceeds batch face cap')
        group.append({'page':page,'original':original,'remove':remove.tolist()})
        cost+=original['faces']
    if group:tasks.append(group)
    output.mkdir(parents=True)
    bindings=[]
    for index,task in enumerate(tasks):
        directory=output/f'batch_{index:03d}';directory.mkdir()
        exports=[dict(r['original'],slot=0) for r in task]
        export_path=directory/'exports.json'
        export_path.write_text(json.dumps({'samples':[{'triangle_cost':{'exports':exports}}]},separators=(',',':')),encoding='utf-8')
        selection={'source_sha256':sha(export_path),'closure_sha256':expected,'selected':[
            {'export_index':i,'source_sha256':r['original']['sha256'],'source_face_indices':r['remove']}
            for i,r in enumerate(task)]}
        selection_path=directory/'selection.json';selection_path.write_text(json.dumps(selection,separators=(',',':')),encoding='utf-8')
        request={'selective_native_cost':{'path':str(selection_path.resolve()),'sha256':sha(selection_path)},
                 'source_export':{'path':str(export_path.resolve()),'sha256':sha(export_path)},
                 'output':str((directory/'resources').resolve())}
        request_path=directory/'input.json';request_path.write_text(json.dumps(request,separators=(',',':')),encoding='utf-8')
        bindings.append({'input':str(request_path.resolve()),'sha256':sha(request_path),'pages':[r['page'] for r in task],
            'source_faces':sum(r['original']['faces'] for r in task),'removed_faces':sum(len(r['remove']) for r in task)})
    report={'closure':{'path':str(source.resolve()),'sha256':expected},'batches':bindings,'unchanged':unchanged,
            'removed_candidate_faces':sum(b['removed_faces'] for b in bindings),
            'runtime_integrated':False,'source_removal_authorized':False,'high_layer_unchanged':True}
    (output/'manifest.json').write_text(json.dumps(report,separators=(',',':')),encoding='utf-8')
    print(json.dumps({'batches':len(bindings),'edited_pages':sum(len(b['pages']) for b in bindings),
                      'removed_candidate_faces':report['removed_candidate_faces']}))


if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('source');p.add_argument('sha');p.add_argument('output')
    p.add_argument('--max-faces',type=int,default=200000)
    a=p.parse_args();build(a.source,a.sha,a.output,a.max_faces)
