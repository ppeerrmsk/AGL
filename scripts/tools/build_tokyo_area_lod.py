"""只添加独立远景派生轮廓：面积/质心补偿后仍通过原有双端float32误差门。"""
import argparse
import copy
import hashlib
import json
import math
from pathlib import Path
from build_tokyo_footprint_lod import f32, eligible, within_error, MAX_SCALES, PIXEL_ERROR, AREA_ERROR
from shapely.geometry import Polygon
from shapely import constrained_delaunay_triangles


def area_corrected_ring(ring, max_scale, previous=None):
    if not math.isfinite(max_scale) or max_scale <= 0:
        raise ValueError('invalid output scale')
    original=Polygon(ring['outer'],ring.get('holes',[]))
    native=Polygon([(f32(x),f32(y)) for x,y in ring['outer']])
    if any(not p.is_valid or p.is_empty or p.area<=0 or p.interiors for p in [original,native]):
        return None
    limit=PIXEL_ERROR/max_scale
    best=previous
    best_count=len((previous or ring)['triangles'])//3
    center=original.centroid
    for fraction in [2.,1.5,1.,.75,.5,.25]:
        simplified=original.simplify(limit*fraction,preserve_topology=True)
        if simplified.geom_type!='Polygon' or simplified.is_empty or simplified.area<=0:
            continue
        if len(simplified.exterior.coords)-3>=best_count:
            continue
        factor=math.sqrt(original.area/simplified.area)
        anchor=simplified.centroid
        candidate=Polygon([(f32(center.x+(x-anchor.x)*factor),f32(center.y+(y-anchor.y)*factor))
                           for x,y in list(simplified.exterior.coords)[:-1]])
        if not candidate.is_valid or candidate.is_empty:
            continue
        if any(abs(candidate.area/p.area-1)>AREA_ERROR or not within_error(p,candidate,limit) for p in [original,native]):
            continue
        faces=list(constrained_delaunay_triangles(candidate).geoms)
        if len(faces)>=best_count:
            continue
        best_count=len(faces)
        best={'outer':[[x,y] for x,y in list(candidate.exterior.coords)[:-1]],'holes':[],
              'triangles':[[x,y] for face in faces for x,y in list(face.exterior.coords)[:3]]}
    # 亚像素屋顶还可试等面积等质心的对称三角；不是直接删楼或无条件方向盒。
    if best_count>1 and max(original.bounds[2]-original.bounds[0],original.bounds[3]-original.bounds[1])*max_scale<=1.4:
        box=list(original.minimum_rotated_rectangle.exterior.coords)
        dx,dy=box[1][0]-box[0][0],box[1][1]-box[0][1]
        width=math.hypot(dx,dy)
        height=math.dist(box[1],box[2])
        for turn in range(4):
            angle=math.atan2(dy,dx)+turn*math.pi*.5
            c,s=math.cos(angle),math.sin(angle)
            for adjustment in [1.,2/math.sqrt(3),math.sqrt(3)/2]:
                aspect=(width/height if turn%2==0 else height/width)*adjustment
                w=math.sqrt(2*original.area*aspect)
                h=2*original.area/w
                points=[(0,-2*h/3),(-w/2,h/3),(w/2,h/3)]
                candidate=Polygon([(f32(center.x+x*c-y*s),f32(center.y+x*s+y*c)) for x,y in points])
                if candidate.is_valid and candidate.area>0 and all(abs(candidate.area/p.area-1)<=AREA_ERROR \
                        and within_error(p,candidate,limit) for p in [original,native]):
                    points=[[x,y] for x,y in list(candidate.exterior.coords)[:-1]]
                    best={'outer':points,'holes':[],'triangles':points}
                    best_count=1
                    break
            if best_count==1:
                break
    return best if best is not previous else None


def prepare(city, region):
    result=copy.deepcopy(city)
    stats=[dict(changed=0,roof_faces_saved=0,one_triangle=0) for _ in MAX_SCALES]
    for raw in result['buildings']:
        if 'area_lod' in raw:
            raise ValueError('derived source cannot be overwritten')
        if raw.get('regional_draw_owner')!=region or not eligible(raw):
            continue
        finer=None
        for slot in reversed(range(4)):
            prior=raw.get('footprint_lod',{}).get(str(slot),{}).get('rings',[raw['rings'][0]])[0]
            new=area_corrected_ring(raw['rings'][0],MAX_SCALES[slot],prior)
            candidates=[ring for ring in [prior,new,finer] if ring is not None]
            chosen=min(candidates,key=lambda ring:len(ring['triangles']))
            if len(chosen['triangles'])<len(prior['triangles']):
                raw.setdefault('area_lod',{})[str(slot)]={'max_scale':MAX_SCALES[slot],'rings':[chosen]}
                stats[slot]['changed']+=1
                stats[slot]['roof_faces_saved']+=(len(prior['triangles'])-len(chosen['triangles']))//3
                stats[slot]['one_triangle']+=int(len(chosen['triangles'])==3)
            finer=chosen
    return result,stats


def audit(original, prepared, region):
    restored=copy.deepcopy(prepared)
    checked=0
    for raw in restored['buildings']:
        entries=raw.pop('area_lod',{})
        if not entries:
            continue
        assert raw.get('regional_draw_owner')==region and eligible(raw)
        ring=raw['rings'][0]
        source=Polygon(ring['outer'])
        native=Polygon([(f32(x),f32(y)) for x,y in ring['outer']])
        for slot,entry in entries.items():
            assert slot in ['0','1','2','3'] and entry['max_scale']==MAX_SCALES[int(slot)]
            assert len(entry['rings'])==1
            candidate_ring=entry['rings'][0]
            assert not candidate_ring['holes']
            candidate=Polygon(candidate_ring['outer'])
            assert all(f32(v)==v for point in candidate_ring['outer'] for v in point)
            for reference in [source,native]:
                assert abs(candidate.area/reference.area-1)<=AREA_ERROR
                assert within_error(reference,candidate,PIXEL_ERROR/entry['max_scale'])
            faces=[Polygon(candidate_ring['triangles'][i:i+3]) for i in range(0,len(candidate_ring['triangles']),3)]
            assert faces and all(face.area>0 and candidate.covers(face) for face in faces)
            assert math.isclose(sum(face.area for face in faces),candidate.area,rel_tol=1e-9)
            prior=raw.get('footprint_lod',{}).get(slot,{}).get('rings',[ring])[0]
            assert len(candidate_ring['triangles'])<len(prior['triangles'])
            checked+=1
        sizes=[len(raw.get('footprint_lod',{}).get(str(slot),{}).get('rings',[ring])[0]['triangles']) for slot in range(4)]
        for slot,entry in entries.items():
            sizes[int(slot)]=len(entry['rings'][0]['triangles'])
        assert sizes==sorted(sizes)
    assert original==restored, 'source identity geometry heights tags and prior LOD must remain exact'
    return checked


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source',type=Path,required=True)
    parser.add_argument('--output',type=Path,required=True)
    args=parser.parse_args()
    if args.output.exists():
        parser.error('output already exists')
    payloads={}
    report={'regions':{},'pixel_error':PIXEL_ERROR,'area_error':AREA_ERROR}
    for region in ['yokohama','north_coast']:
        payload=(args.source/region/'city.json').read_bytes()
        original=json.loads(payload)
        prepared,stats=prepare(original,region)
        checked=audit(original,prepared,region)
        output=json.dumps(prepared,ensure_ascii=False,separators=(',',':')).encode('utf-8')
        payloads[region]=output
        report['regions'][region]={'source_hash':hashlib.sha256(payload).hexdigest()+':'+hashlib.sha256((args.source/region/'ground.json').read_bytes()).hexdigest(),
            'prepared_sha256':hashlib.sha256(output).hexdigest(),'checked':checked,'stats':stats}
        print(region,checked,stats,flush=True)
    args.output.mkdir(parents=True,exist_ok=False)
    for region,payload in payloads.items():
        (args.output/region).mkdir()
        (args.output/region/'city.json').write_bytes(payload)
    (args.output/'audit.json').write_text(json.dumps(report,indent=2),encoding='utf-8')


if __name__=='__main__':
    main()
