"""线带轮廓与跨路径拓扑门；失败路径逐项恢复原源，不抬容差。"""
import argparse
import copy
from collections import Counter
import json
import sys
from pathlib import Path
import numpy as np
sys.path.insert(0, str(Path(__file__).resolve().parents[2]/'tmp/tokyo-geometry-deps'))
from shapely import LineString, Polygon, STRtree, union_all
from build_tokyo_path_candidate import digest


def ribbon(points, width=.8):
    """与工厂逐段矩形语义一致，不用带圆角的buffer代替实际线带。"""
    p = np.asarray(points, dtype=np.float64)
    start, end = p[:-1], p[1:]
    delta = end-start
    length = np.linalg.norm(delta, axis=1)
    valid = length > 0
    start, end, delta, length = start[valid], end[valid], delta[valid], length[valid]
    side = np.column_stack([-delta[:,1], delta[:,0]]) / length[:,None] * (width*.5)
    return union_all([Polygon([a+s,b+s,b-s,a-s]) for a,b,s in zip(start,end,side)])


def within_ribbon_error(before, after, tolerance=.2, width=.8):
    a,b = ribbon(before,width), ribbon(after,width)
    # buffer圆弧为内接近似：覆盖通过是保守距离门；不是逐点采样最大值。
    return bool(a.buffer(tolerance, quad_segs=16).covers(b) and
                b.buffer(tolerance, quad_segs=16).covers(a))


def assemble(export_path, replay_path, output, minor=False, base=None):
    """原路径逐角同向等价才替换；保留其他全部地表三角属性。"""
    if output.exists():
        raise ValueError('output exists')
    export=json.loads(export_path.read_bytes())
    row=next(iter(export['ground_export'].values()))
    source=Path(row['path'])
    if digest(source)!=row['sha256']:
        raise ValueError('export drift')
    raw=np.fromfile(source,dtype='<f4').reshape(-1,3,10)
    base_report_sha=None
    if base is not None:
        base_report=json.loads((base/'report.json').read_bytes())
        if base_report['export_sha256']!=digest(export_path) or digest(base/'ground.attributes')!=base_report['candidate_sha256']:
            raise ValueError('base candidate drift')
        raw=np.fromfile(base/'ground.attributes',dtype='<f4').reshape(-1,3,10)
        base_report_sha=digest(base/'report.json')
    # 全部顶点同时满足原工厂高度/颜色，不用近似RGB删除其他语义层。
    rgb=np.array([110,119,114] if minor else [156,157,141],dtype=np.float32)/255
    mask=np.all(raw[:,:,1]==np.float32(.38 if minor else .22),axis=1)&np.all(raw[:,:,6:9]==rgb,axis=(1,2))
    replay=json.loads(replay_path.read_bytes())
    loaded={}
    for name in ('original','candidate'):
        parts=[]
        for part in replay[name]['parts']:
            path=Path(part['path'])
            if digest(path)!=part['sha256']:
                raise ValueError('replay drift')
            parts.append(np.fromfile(path,dtype='<f4').reshape(-1,3,10))
        loaded[name]=np.concatenate(parts)
    def canonical(data):
        return Counter(min(t.tobytes(),np.roll(t,1,axis=0).tobytes(),np.roll(t,2,axis=0).tobytes()) for t in data)
    if canonical(raw[mask])!=canonical(loaded['original']):
        raise ValueError('original production replay not exact')
    candidate=np.concatenate([raw[~mask],loaded['candidate']])
    output.mkdir(parents=True)
    path=output/'ground.attributes'
    candidate.tofile(path)
    if not np.array_equal(candidate,np.fromfile(path,dtype='<f4').reshape(-1,3,10)):
        raise ValueError('candidate roundtrip drift')
    result=dict(export_sha256=digest(export_path),replay_sha256=digest(replay_path),
                base_report_sha256=base_report_sha,minor_roads=minor,
                candidate_sha256=digest(path),source_faces=len(raw),candidate_faces=len(candidate),
                saved_faces=len(raw)-len(candidate),unchanged_other_faces=int((~mask).sum()),
                original_oriented_corners_exact=True,mesh_bytes=path.stat().st_size,
                runtime_integrated=False,full_route_budget_verified=False)
    (output/'report.json').write_text(json.dumps(result,indent=2),encoding='utf-8')
    print(json.dumps(result))


def review(candidate, output):
    if output.exists():
        raise ValueError('output exists')
    report=json.loads((candidate/'report.json').read_bytes())
    source=Path(report['source'])
    target=candidate/'ground.json'
    if digest(source)!=report['source_sha256'] or digest(target)!=report['candidate_sha256']:
        raise ValueError('ground source drift')
    original=json.loads(source.read_bytes())
    modified=json.loads(target.read_bytes())
    city=Path('tmp/tokyo-bay-volume/r400-detail_08_00-source/city.json')
    if digest(city)!=report['city_sha256']:
        raise ValueError('road binding drift')
    roads=json.loads(city.read_bytes())
    old=original['paths']
    new=modified['paths']
    if [p['id'] for p in old]!=[p['id'] for p in new]:
        raise ValueError('path order drift')
    changed={i for i in range(len(old)) if old[i]!=new[i]}
    rejected={}
    for i in sorted(changed):
        if not within_ribbon_error(old[i]['points'],new[i]['points']):
            rejected[i]='ribbon_outline'
            new[i]=copy.deepcopy(old[i])
    # 使用原/新包络并集建树，保证不漏掉新位置才出现的相交。
    extra=[row for kind in ('roads','rails') for row in roads.get(kind,[]) if len(row['points'])>=2]
    old_lines=[LineString(row['points']) for row in old+extra]
    new_lines=[LineString(row['points']) for row in new+extra]
    tree=STRtree([a.union(b).envelope for a,b in zip(old_lines,new_lines)])
    checks=0
    # 回退一条会影响邻线关系，循环到稳定；每次至少永久回退一条。
    passes=0
    while True:
        bad=set()
        active=changed-set(rejected)
        for i in sorted(active):
            if old_lines[i].is_simple!=new_lines[i].is_simple:
                bad.add(i)
            for j in tree.query(old_lines[i].union(new_lines[i]).envelope):
                j=int(j)
                if j==i:
                    continue
                checks+=1
                if old_lines[i].relate(old_lines[j])!=new_lines[i].relate(new_lines[j]):
                    bad.add(i)
                    if j in active:
                        bad.add(j)
        passes+=1
        if not bad:
            break
        for i in bad:
            rejected[i]='centerline_topology'
            new[i]=copy.deepcopy(old[i])
            new_lines[i]=old_lines[i]
    before=sum(max(0,len(p['points'])-1) for p in old)
    after=sum(max(0,len(p['points'])-1) for p in new)
    if any(original[k]!=modified[k] for k in original if k!='paths'):
        raise ValueError('non-path drift')
    output.mkdir(parents=True)
    ground=output/'ground.json'
    ground.write_text(json.dumps(modified,separators=(',',':')),encoding='utf-8')
    result=dict(input_report_sha256=digest(candidate/'report.json'), source_sha256=digest(source),
                candidate_sha256=digest(ground), initially_changed=len(changed),
                accepted_changed=len(changed)-len(rejected), rejected_paths={old[i]['id']:r for i,r in rejected.items()},
                topology_relation_checks=checks, topology_passes=passes,
                centerline_relation_preserved=True, ribbon_set_distance_bound=.2,
                unchanged_non_path_layers=True, segments_before=before, segments_after=after,
                estimated_unclipped_face_saving=2*(before-after),
                original_mesh_replay_verified=False, actual_clipped_face_saving=None,
                overlap_area_preserved=False, runtime_integrated=False)
    (output/'report.json').write_text(json.dumps(result,indent=2),encoding='utf-8')
    print(json.dumps({k:v for k,v in result.items() if k!='rejected_paths'}))


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('candidate',type=Path)
    parser.add_argument('output',type=Path)
    parser.add_argument('--source-export',type=Path)
    parser.add_argument('--minor-roads',action='store_true')
    parser.add_argument('--base',type=Path)
    args=parser.parse_args()
    if args.source_export:
        assemble(args.source_export,args.candidate,args.output,args.minor_roads,args.base)
    else:
        review(args.candidate,args.output)
