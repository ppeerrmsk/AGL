"""联合复核最终paths/roads候选的源属性、端点和跨层中心线连接。"""
import argparse
import json
from pathlib import Path
from collections import Counter
from verify_tokyo_simplified_ground import digest
from shapely import LineString, STRtree


def verify_sources(original_ground, candidate_ground, original_city, candidate_city):
    old_rows, new_rows = [], []
    for original, candidate, fields in [(original_ground,candidate_ground,('paths',)),
                                         (original_city,candidate_city,('roads','rails'))]:
        if {k:v for k,v in original.items() if k not in fields} != {k:v for k,v in candidate.items() if k not in fields}:
            raise ValueError('non-line source drift')
        for field in fields:
            old, new = original.get(field,[]), candidate.get(field,[])
            if len(old) != len(new): raise ValueError('line count drift')
            for a,b in zip(old,new):
                if {k:v for k,v in a.items() if k!='points'} != {k:v for k,v in b.items() if k!='points'}:
                    raise ValueError('line attributes drift')
                if field=='rails' and a!=b: raise ValueError('rail changed')
                if len(a['points'])<2 or len(b['points'])<2:
                    if a!=b: raise ValueError('degenerate line changed')
                    continue
                if a['points'][0]!=b['points'][0] or a['points'][-1]!=b['points'][-1]: raise ValueError('endpoint drift')
                old_rows.append(a);new_rows.append(b)
    counts=Counter(tuple(p) for row in old_rows for p in row['points'])
    changed=[i for i,(a,b) in enumerate(zip(old_rows,new_rows)) if a!=b]
    before=[LineString(row['points']) for row in old_rows]
    after=[LineString(row['points']) for row in new_rows]
    bounds=[a.union(b).envelope for a,b in zip(before,after)]
    tree=STRtree(bounds);checks=0
    for i in changed:
        points={tuple(p) for p in new_rows[i]['points']}
        if any(counts[tuple(p)]>1 and tuple(p) not in points for p in old_rows[i]['points']): raise ValueError('shared vertex removed')
        if before[i].is_simple!=after[i].is_simple: raise ValueError('self topology drift')
        for j in tree.query(bounds[i]):
            if i==j: continue
            checks+=1
            if before[i].relate(before[j])!=after[i].relate(after[j]): raise ValueError(f'connection drift {i}:{j}')
    return dict(changed_lines=len(changed),relation_checks=checks,source_attributes_preserved=True,
                endpoints_and_shared_vertices_preserved=True,centerline_relations_preserved=True,
                visual_verified=False,runtime_integrated=False)


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    for name in ('original_ground','candidate_ground','original_city','candidate_city','output'): parser.add_argument(name,type=Path)
    args=parser.parse_args()
    if args.output.exists(): raise ValueError('output exists')
    paths=[args.original_ground,args.candidate_ground,args.original_city,args.candidate_city]
    result=verify_sources(*(json.loads(p.read_bytes()) for p in paths))
    result['sources']=[dict(path=str(p.resolve()),sha256=digest(p)) for p in paths]
    args.output.write_text(json.dumps(result,indent=2),encoding='utf-8')
    print(json.dumps(result))
