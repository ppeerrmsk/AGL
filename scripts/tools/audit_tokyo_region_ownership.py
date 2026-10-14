"""只读核验跨区归属准备包：来源不变、整栋唯一、摘要匹配；不宣称原生绘制通过。"""
import argparse
from collections import Counter
import hashlib
import json
from pathlib import Path
from build_tokyo_region_ownership import build_registry


def audit(originals,prepared,registry,digest):
    expected=build_registry(originals)
    if {k:v for k,v in registry.items() if k!='inputs'}!=expected:
        raise ValueError('registry differs from canonical source ownership')
    if set(originals)!=set(prepared):
        raise ValueError('incomplete joined region set')
    occurrences={}
    planned_owner_counts=Counter()
    planned_nonowner_counts=Counter()
    for region,city in prepared.items():
        metadata=city.get('regional_ownership',{})
        if metadata!={'schema_version':1,'joined_only':True,'region_id':region,'registry_sha256':digest}:
            raise ValueError('invalid joined-only metadata or registry hash')
        source=originals[region]
        if {k:v for k,v in city.items() if k not in ['regional_ownership','buildings']}!={
                k:v for k,v in source.items() if k!='buildings'}:
            raise ValueError('non-building source changed')
        if len(city['buildings'])!=len(source['buildings']):
            raise ValueError('source record count changed')
        for old,new in zip(source['buildings'],city['buildings']):
            if {k:v for k,v in new.items() if k!='regional_draw_owner'}!=old:
                raise ValueError('source record changed: '+old['id'])
            identity=new['id']
            owner=new.get('regional_draw_owner')
            if owner!=registry['assignments'][identity]['owner']:
                raise ValueError('noncanonical draw owner: '+identity)
            occurrences.setdefault(identity,[]).append((region,owner))
            if region==owner:
                planned_owner_counts[region]+=1
            else:
                planned_nonowner_counts[region]+=1
    for identity,copies in occurrences.items():
        owners={owner for _,owner in copies}
        if len(owners)!=1 or sum(region==owner for region,owner in copies)!=1:
            raise ValueError('missing or repeated owner: '+identity)
    for family in registry['families']:
        if any({owner for _,owner in occurrences[member]}!={family['owner']} for member in family['members']):
            raise ValueError('family split across regions')
    return {'data_preparation_ok':True,'source_records_unchanged':True,
            'unique_source_records':len(occurrences),'shared_source_ids':registry['shared_records'],
            'planned_owner_records':dict(sorted(planned_owner_counts.items())),
            'planned_nonowner_copies':dict(sorted(planned_nonowner_counts.items())),
            'intact_families':len(registry['families']),
            'registry_sha256':digest,'native_joined_render_verified':False,
            'simultaneous_render_ready':False}


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--region',action='append',required=True,help='stable_id=original_source_directory')
    parser.add_argument('--prepared',type=Path,required=True)
    parser.add_argument('--output',type=Path,required=True)
    args=parser.parse_args()
    if args.output.exists():
        parser.error('output already exists')
    raw=(args.prepared/'ownership.json').read_bytes()
    registry=json.loads(raw)
    digest=hashlib.sha256(raw).hexdigest()
    originals,prepared={},{}
    for value in args.region:
        region,folder=value.split('=',1)
        if region not in registry['regions'] or region in originals:
            parser.error('unknown or repeated region')
        source=Path(folder)
        for filename in ['city.json','ground.json']:
            original_bytes=(source/filename).read_bytes()
            if hashlib.sha256(original_bytes).hexdigest()!=registry['inputs'][region][filename]:
                raise ValueError('original source hash mismatch: '+region+'/'+filename)
            if filename=='ground.json' and original_bytes!=(args.prepared/region/filename).read_bytes():
                raise ValueError('ground source changed: '+region)
        originals[region]=json.loads((source/'city.json').read_bytes())
        prepared[region]=json.loads((args.prepared/region/'city.json').read_bytes())
    result=audit(originals,prepared,registry,digest)
    result['ground_sources_byte_identical']=True
    args.output.parent.mkdir(parents=True,exist_ok=True)
    with args.output.open('x',encoding='utf-8') as handle:
        json.dump(result,handle,ensure_ascii=False,indent=2)
    print(json.dumps(result,ensure_ascii=False))


if __name__=='__main__':
    main()
