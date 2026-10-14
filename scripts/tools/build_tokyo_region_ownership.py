"""为联合场景准备跨区唯一楼栋归属；原始来源及独立预览不修改。"""
import argparse
import copy
import hashlib
import json
import math
from pathlib import Path

CACHE_FIELDS={'footprint_lod'}


def source_payload(record):
    # 只豁免已验证的远距派生缓存；高度、孔洞、分部、屋顶、材质和近景三角均严格比较。
    return {k:v for k,v in record.items() if k not in CACHE_FIELDS}


def connected_components(records):
    # 同源装配已明确登记的别名只用于解析边；绝不改写原始来源字段。
    aliases={}
    for identity,record in records.items():
        for alias in record.get('aliases',[]):
            aliases.setdefault(alias,set()).add(identity)
    edges={identity:set() for identity in records}
    missing=[]
    for identity,record in records.items():
        for raw_target in set(record.get('parents',[])+record.get('parts',[])):
            target=raw_target
            if target not in records:
                candidates=aliases.get(target,set())
                if len(candidates)>1:
                    raise ValueError('ambiguous source alias reference: '+target)
                if candidates:target=next(iter(candidates))
            if target==identity:
                continue
            if target in edges:
                edges[identity].add(target)
                edges[target].add(identity)
            else:
                missing.append([identity,target])
    seen=set()
    components=[]
    for identity in sorted(records):
        if identity in seen:
            continue
        pending=[identity]
        members=[]
        while pending:
            current=pending.pop()
            if current in seen:
                continue
            seen.add(current)
            members.append(current)
            pending.extend(edges[current]-seen)
        components.append(sorted(members))
    return components,sorted(missing)


def component_center(members,records):
    points=[p for identity in members for ring in records[identity]['rings'] for p in ring['outer']]
    if not points or any(len(p)!=2 or not all(math.isfinite(v) for v in p) for p in points):
        raise ValueError('component without footprint: '+members[0])
    return [(min(p[axis] for p in points)+max(p[axis] for p in points))*.5 for axis in range(2)]


def region_distance(center,rect):
    x,y,w,h=rect
    if not all(math.isfinite(v) for v in rect) or w<=0 or h<=0:
        raise ValueError('invalid region extent')
    contains=x<=center[0]<x+w and y<=center[1]<y+h
    dx=max(x-center[0],0.,center[0]-(x+w))
    dy=max(y-center[1],0.,center[1]-(y+h))
    return (0 if contains else 1,dx*dx+dy*dy)


def build_registry(cities):
    if len(cities)<2:
        raise ValueError('at least two regions required')
    copies={}
    canonical={}
    for region,city in sorted(cities.items()):
        if not region or 'regional_ownership' in city:
            raise ValueError('invalid or already prepared region')
        region_distance([0.,0.],city['rect'])
        seen=set()
        for record in city['buildings']:
            identity=record['id']
            if identity in seen or 'regional_draw_owner' in record:
                raise ValueError('duplicate or prepared source identity: '+identity)
            seen.add(identity)
            copies.setdefault(identity,{})[region]=record
            if identity not in canonical:
                canonical[identity]=record
            elif source_payload(canonical[identity])!=source_payload(record):
                fields=sorted(k for k in canonical[identity].keys()|record.keys()
                              if k not in CACHE_FIELDS and canonical[identity].get(k)!=record.get(k))
                raise ValueError('conflicting source '+identity+': '+','.join(fields))
    components,missing=connected_components(canonical)
    if missing:
        raise ValueError('unresolved external family references: '+str(missing))
    assignments={}
    families=[]
    for members in components:
        candidates=set.intersection(*(set(copies[identity]) for identity in members))
        if not candidates:
            raise ValueError('no region contains complete family: '+','.join(members))
        center=component_center(members,canonical)
        owner=min(candidates,key=lambda region:(*region_distance(center,cities[region]['rect']),region))
        for identity in members:
            assignments[identity]={'owner':owner,'regions':sorted(copies[identity])}
        if len(members)>1:
            families.append({'members':members,'owner':owner})
    shared={identity:value for identity,value in assignments.items() if len(value['regions'])>1}
    return {'schema_version':1,'joined_only':True,'regions':sorted(cities),
            'input_records':sum(len(c['buildings']) for c in cities.values()),
            'unique_source_records':len(canonical),'shared_records':len(shared),
            'planned_suppressed_regional_copies':sum(len(v)-1 for v in copies.values()),
            'assignments':assignments,'shared_assignments':shared,'families':families,
            'unresolved_external_family_refs':missing,
            'native_joined_render_verified':False}


def prepare_region(city,region,registry,registry_hash):
    if region not in registry['regions']:
        raise ValueError('unknown region')
    result=copy.deepcopy(city)
    result['regional_ownership']={'schema_version':1,'joined_only':True,
                                  'region_id':region,'registry_sha256':registry_hash}
    for record in result['buildings']:
        assignment=registry['assignments'][record['id']]
        if region not in assignment['regions']:
            raise ValueError('source not registered for region')
        record['regional_draw_owner']=assignment['owner']
    return result


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--region',action='append',required=True,help='stable_id=source_directory')
    parser.add_argument('--output',type=Path,required=True)
    args=parser.parse_args()
    if args.output.exists():
        parser.error('output already exists')
    paths={}
    cities={}
    for value in args.region:
        name,path=value.split('=',1)
        if name in paths or not name or any(ch not in 'abcdefghijklmnopqrstuvwxyz0123456789_' for ch in name):
            parser.error('invalid or repeated stable region id')
        paths[name]=Path(path)
        cities[name]=json.loads((paths[name]/'city.json').read_text(encoding='utf-8'))
    registry=build_registry(cities)
    registry['inputs']={name:{file:hashlib.sha256((path/file).read_bytes()).hexdigest()
                             for file in ['city.json','ground.json']} for name,path in sorted(paths.items())}
    encoded=json.dumps(registry,ensure_ascii=False,sort_keys=True,separators=(',',':')).encode('utf-8')
    digest=hashlib.sha256(encoded).hexdigest()
    prepared={name:prepare_region(city,name,registry,digest) for name,city in cities.items()}
    args.output.mkdir(parents=True,exist_ok=False)
    (args.output/'ownership.json').write_bytes(encoded)
    for name,city in prepared.items():
        target=args.output/name
        target.mkdir()
        (target/'city.json').write_text(json.dumps(city,ensure_ascii=False,separators=(',',':')),encoding='utf-8')
        (target/'ground.json').write_bytes((paths[name]/'ground.json').read_bytes())
    print(json.dumps({k:v for k,v in registry.items() if k not in ['assignments','shared_assignments','families','inputs']},ensure_ascii=False))
    print('registry_sha256='+digest)


if __name__=='__main__':
    main()
