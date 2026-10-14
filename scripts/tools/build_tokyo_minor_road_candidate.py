"""同一源级简化链扩至次级道路，锁宽度/端点/连接，轮廓超限即回退。"""
import argparse
import copy
from collections import Counter
import json
from pathlib import Path
from build_tokyo_path_candidate import digest, simplify
from review_tokyo_path_candidate import within_ribbon_error, LineString, STRtree

MAJOR={'motorway','motorway_link','trunk','trunk_link','primary','primary_link','secondary','secondary_link'}


def build(source, ground, output):
    if output.exists() or digest(source)!='2540f09c21a6ca53a7c298952fabeeaee1dc0de2a3562ff4ab5ef5b0d1fb82cb' or digest(ground)!='2969ac9c7f968435da226c5d8824a4a71fbadabf2aa76d61c0d2d82f91d7182a':
        raise ValueError('candidate output or source identity rejected')
    original=json.loads(source.read_bytes())
    data=copy.deepcopy(original)
    old=original['roads']
    new=data['roads']
    extra=original.get('rails',[])+json.loads(ground.read_bytes())['paths']
    counts=Counter(tuple(p) for row in old+extra for p in row['points'])
    locked={p for p,n in counts.items() if n>1}
    changed=set()
    rejected={}
    for i,row in enumerate(new):
        points=row['points']
        if row['class'] in MAJOR or len(points)<3 or 'joined_strokes' in row:
            continue
        anchors=sorted({0,len(points)-1}|{j for j,p in enumerate(points) if tuple(p) in locked})
        result=[]
        for start,end in zip(anchors,anchors[1:]):
            result.extend(simplify(points[start:end+1],.2)[:-1])
        result.append(points[-1])
        if result==points:
            continue
        if not within_ribbon_error(points,result,width=row['width_px']):
            rejected[i]='ribbon_outline'
            continue
        row['points']=result
        changed.add(i)
    old_lines=[LineString(r['points']) for r in old+extra]
    new_lines=[LineString(r['points']) for r in new+extra]
    tree=STRtree([a.union(b).envelope for a,b in zip(old_lines,new_lines)])
    checks=0
    while True:
        bad=set()
        for i in sorted(changed):
            if old_lines[i].is_simple!=new_lines[i].is_simple:
                bad.add(i)
            for j in tree.query(old_lines[i].union(new_lines[i]).envelope):
                j=int(j)
                if j==i: continue
                checks+=1
                if old_lines[i].relate(old_lines[j])!=new_lines[i].relate(new_lines[j]):
                    bad.add(i)
                    if j in changed: bad.add(j)
        if not bad: break
        for i in bad:
            rejected[i]='centerline_topology'
            new[i]=copy.deepcopy(old[i]);new_lines[i]=old_lines[i];changed.remove(i)
    before=sum(len(r['points'])-1 for r in old if r['class'] not in MAJOR)
    after=sum(len(r['points'])-1 for r in new if r['class'] not in MAJOR)
    output.mkdir(parents=True)
    target=output/'city.json'
    target.write_text(json.dumps(data,separators=(',',':')),encoding='utf-8')
    if json.loads(target.read_bytes())!=data: raise ValueError('roundtrip drift')
    report=dict(source_sha256=digest(source),ground_sha256=digest(ground),candidate_sha256=digest(target),
                changed_roads=len(changed),rejected_roads=len(rejected),relation_checks=checks,
                segments_before=before,segments_after=after,estimated_unclipped_faces_saved=2*(before-after),
                width_unchanged=True,centerline_relation_preserved=True,ribbon_set_distance_bound=.2,
                original_mesh_replay_verified=False,runtime_integrated=False)
    (output/'report.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
    print(json.dumps(report))


if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('source',type=Path);p.add_argument('ground',type=Path);p.add_argument('output',type=Path)
    args=p.parse_args();build(args.source,args.ground,args.output)
