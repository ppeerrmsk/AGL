"""从已保存的来源构建水文候选；仅显式输出，不联网、不改玩法地图。"""
import argparse, hashlib, json, math, os, sys
from pathlib import Path
if os.environ.get('AGL_GEOMETRY_PYTHONPATH'):
    sys.path.insert(0, os.environ['AGL_GEOMETRY_PYTHONPATH'])
from shapely.geometry import Polygon, LineString, box
from shapely.ops import unary_union

ROOT=Path(__file__).resolve().parents[1]
SOURCE=ROOT/'tools/map_sources/desert_hydrography'

def water_quads(loops):
    edges=[]
    for loop in loops:
        for p,q in zip(loop,loop[1:]):
            if p[1]==q[1]: continue
            if p[1]>q[1]: p,q=q,p
            edges.append((p,q))
    levels=sorted({p[1] for edge in edges for p in edge})
    def edge_x(i,y):
        p,q=edges[i]
        return p[0]+(q[0]-p[0])*(y-p[1])/(q[1]-p[1])
    bands=[]; active={}
    for lo,hi in zip(levels,levels[1:]):
        mid=(lo+hi)*.5
        crossings=sorted((edge_x(i,mid),i) for i,(p,q) in enumerate(edges) if p[1]<mid<q[1])
        assert len(crossings)%2==0
        following={}
        for left,right in zip(crossings[::2],crossings[1::2]):
            key=(left[1],right[1]); record=active.get(key)
            if record is None:
                record=[key,lo,hi]; bands.append(record)
            else: record[2]=hi
            following[key]=record
        active=following
    return [[[round(edge_x(key[0],lo),2),lo],[round(edge_x(key[1],lo),2),lo],
             [round(edge_x(key[1],hi),2),hi],[round(edge_x(key[0],hi),2),hi]] for key,lo,hi in bands]

def build(output, source_directory=SOURCE):
    path=ROOT/'resources/maps/desert_volume_relief.json'
    data=json.loads(path.read_text(encoding='utf-8'))
    meta=json.loads((ROOT/'resources/maps/desert_railway_bg_v2.json').read_text(encoding='utf-8'))
    audit=json.loads((source_directory/'source-classification.json').read_text(encoding='utf-8'))
    removed=[e['index'] for e in audit['contours'] if e['classification']=='watercourse_symbol_candidate']
    ids=sorted({m['id'] for e in audit['contours'] if e['index'] in removed for m in e['stream_matches']})
    assert len(removed)==384 and ids==[106879155,115450190,159633265,343881407,659805469,1090616770,1090616772]
    retained=[i for i in range(len(data['water_contours'])) if i not in removed]
    loops=[data['water_contours'][i] for i in retained]
    quads=water_quads(loops)
    def filled(polygons):
        return unary_union([Polygon(p) for p in polygons if Polygon(p).is_valid and Polygon(p).area>.0001])
    original=filled(data['water_quads']); current=filled(quads)
    removed_shape=filled([data['water_contours'][i] for i in removed])
    expected=original.difference(removed_shape)
    lake_indices=[e['index'] for e in audit['contours'] if e['classification']=='water_area_candidate']
    confirmed_water=current.intersection(filled([data['water_contours'][i] for i in lake_indices]))
    difference=current.symmetric_difference(expected).area
    # 旧扫描梯形交点保留0.01px精度；不能把大范围水面变化混入删除河色斑。
    assert difference<50 and difference/max(expected.area,1)<.00002, difference
    entries={}; hashes=[]
    for record in audit['sources']:
        source=source_directory/record['file']; raw=source.read_bytes()
        assert hashlib.sha256(raw).hexdigest()==record['sha256']
        hashes.append({'file':record['file'],'sha256':record['sha256']})
        for e in json.loads(raw)['elements']: entries[(e['type'],e['id'])]=e
    b=meta['bbox_ll']; r=data['world_rect']
    merc=lambda t:math.log(math.tan(math.pi/4+math.radians(t)/2))
    def project(n):
        return (r[0]+(n['lon']-b['lon_min'])/(b['lon_max']-b['lon_min'])*r[2],
                r[1]+(merc(b['lat_max'])-merc(n['lat']))/(merc(b['lat_max'])-merc(b['lat_min']))*r[3])
    bounds=box(r[0],r[1],r[0]+r[2],r[1]+r[3])
    rivers=[]
    for i in ids:
        way=entries[('way',i)]; points=[project(entries[('node',n)]) for n in way['nodes']]
        in_bounds=LineString(points).intersection(bounds)
        line=in_bounds.difference(confirmed_water)
        parts=[line] if line.geom_type=='LineString' else list(line.geoms)
        paths=[[[round(x,5),round(y,5)] for x,y in p.coords] for p in parts
               if p.geom_type=='LineString' and p.length>.01]
        assert all(LineString(p).intersection(confirmed_water).length < .01 for p in paths)
        assert all(LineString(p).difference(bounds.buffer(.00002)).is_empty for p in paths)
        assert abs(sum(LineString(p).length for p in paths)-line.length)<.01
        rivers.append({'way_id':i,'tags':way.get('tags',{}),'paths':paths,
            'in_bounds_length':in_bounds.length,'confirmed_water_removed_length':in_bounds.intersection(confirmed_water).length,
            'replaces_contours':[e['index'] for e in audit['contours'] if e['index'] in removed
                and any(m['id']==i for m in e['stream_matches'])]})
    result={'schema_version':1,'source_relief_sha256':hashlib.sha256(path.read_bytes()).hexdigest(),
        'sources':hashes,'projection':'existing bbox Mercator UV to original world rect',
        'removed_contours':removed,'retained_contours':retained,'confirmed_water_contours':lake_indices,
        'water_quads':quads,'rivers':rivers,
        'audit':{'water_fill_symmetric_difference_px2':difference,'retained_water_area_px2':current.area,
            'width_is_presentation_not_surveyed':True,'gameplay_coordinates_changed':False}}
    output.parent.mkdir(parents=True,exist_ok=True)
    output.write_text(json.dumps(result,separators=(',',':')),encoding='utf-8')
    print(json.dumps({'output':str(output),'quads':len(quads),'retained':len(retained),'removed':len(removed),
        'rivers':len(rivers),'paths':sum(len(r['paths']) for r in rivers),
        'segments':sum(len(p)-1 for r in rivers for p in r['paths']),'symmetric_difference':difference}))

if __name__=='__main__':
    parser=argparse.ArgumentParser(); parser.add_argument('--output',type=Path,required=True)
    parser.add_argument('--source',type=Path,default=SOURCE)
    args=parser.parse_args()
    build(args.output,args.source)
