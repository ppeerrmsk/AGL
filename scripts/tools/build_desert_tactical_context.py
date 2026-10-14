"""从保留的OSM源构建原坐标简洁街区；只生成几何数据，不处理照片。"""
import argparse,hashlib,json,math,sys
from pathlib import Path
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--source',type=Path,required=True)
parser.add_argument('--deps',type=Path,help='optional isolated Shapely dependency directory')
parser.add_argument('--output',type=Path,default=Path('resources/maps/desert_tactical_context.json'))
parser.add_argument('--report-dir',type=Path,required=True)
args=parser.parse_args()
if args.deps:sys.path.insert(0,str(args.deps.resolve()))
from shapely import constrained_delaunay_triangles
from shapely.geometry import Polygon,LineString,Point
from shapely.ops import unary_union

root=args.report_dir;root.mkdir(parents=True,exist_ok=True)
raw_path=args.source
raw=json.loads(raw_path.read_text(encoding='utf-8'));meta=json.loads(Path('resources/maps/desert_railway_bg_v2.json').read_text(encoding='utf-8'))
doc_path=Path('resources/maps/desert_railway_preview.aglmap');doc=json.loads(doc_path.read_text(encoding='utf-8'))
bbox=meta['bbox_ll']; lat,lon=meta['game_world_center_latlon']
sx=meta['game_world_meters_per_degree_lon_at_center']*.5;sy=meta['game_world_meters_per_degree_lat']*.5
origin=((bbox['lon_min']-lon)*sx,(lat-bbox['lat_max'])*sy)
extent=((bbox['lon_max']-bbox['lon_min'])*sx,(bbox['lat_max']-bbox['lat_min'])*sy)
merc=lambda x:math.log(math.tan(math.pi/4+math.radians(x)/2))
def project(n):
    return [origin[0]+(n['lon']-bbox['lon_min'])/(bbox['lon_max']-bbox['lon_min'])*extent[0],origin[1]+(merc(bbox['lat_max'])-merc(n['lat']))/(merc(bbox['lat_max'])-merc(bbox['lat_min']))*extent[1]]
nodes={e['id']:project(e) for e in raw['elements'] if e['type']=='node'}
facilities=[];road_clip=[];road_clip_records=[]
for index,b in enumerate(doc['buildings']):
    points=b['footprint'];p=Polygon(points);cx,cy=p.centroid.coords[0]
    old_scale=1.24 if len(points)==8 else 1.14
    facilities.append(Polygon([(cx+(x-cx)*old_scale,cy+(y-cy)*old_scale) for x,y in points]).buffer(14))
    # 对应运行时 Buildings.frame / scaled_polygon；回归另用真实GDScript复算。
    cx=sum(p[0] for p in points)/len(points);cy=sum(p[1] for p in points)/len(points)
    a,bp=points[0],points[1]
    if len(points)==4 and math.dist(points[0],points[1])<math.dist(points[1],points[2]):a,bp=points[1],points[2]
    length=math.dist(a,bp);dx=(bp[0]-a[0])/length;dy=(bp[1]-a[1])/length
    frame_length=2*max(abs((x-cx)*dx+(y-cy)*dy) for x,y in points)
    tank=len(points)==8
    scale=1.24 if tank else (1.06 if frame_length>=70 else 1.14)
    margin=.8 if tank else 0.0 # 储罐围堰实际宽1.6，外伸半宽；不是额外净空。
    outline=[(cx+(x-cx)*scale,cy+(y-cy)*scale) for x,y in points]
    shape=Polygon(outline)
    road_clip.append(shape.buffer(margin,join_style=2) if margin else shape)
    road_clip_records.append({'building_index':index,'outline':outline,'outer_margin':margin})
occupied=unary_union(facilities)
road_exclusion=unary_union(road_clip)
rail=unary_union([LineString(r['points']).buffer(28) for r in doc['railways']])
avoid=unary_union([occupied,rail])
def triangles(poly,precision=5):
    if poly.is_empty:return []
    result=[]
    for tri in constrained_delaunay_triangles(poly).geoms:
        result.extend([[round(x,precision),round(y,precision)] for x,y in list(tri.exterior.coords)[:3]])
    return result
def region(p):return ('north' if p[1]<400 else 'south')+('west' if p[0]<4800 else 'east')
cells={name:{'buildings':[],'roads':[]} for name in ['northwest','northeast','southwest','southeast']}
excluded=[];road_sources=[];road_shapes=[];counts={'buildings':0,'road_ways':0,'roof_triangles':0,'wall_triangles':0,'road_triangles':0}
widths={'residential':3.6,'service':2.8,'unclassified':3.6,'secondary':5.0,'tertiary':4.4,'primary':6.0,'trunk':7.0,'motorway':8.0}
for way in [e for e in raw['elements'] if e['type']=='way']:
    tags=way.get('tags',{});ids=way.get('nodes',[])
    if not ids or any(n not in nodes for n in ids):continue
    points=[nodes[n] for n in ids]
    if tags.get('building') and ids[0]==ids[-1] and len(ids)>=4:
        poly=Polygon(points)
        if not poly.is_valid or poly.area<.5:excluded.append({'way_id':way['id'],'reason':'invalid_or_degenerate'});continue
        if poly.intersects(avoid):excluded.append({'way_id':way['id'],'reason':'game_facility_or_rail_clearance'});continue
        height=3.2;source='presentation_fallback_3.2m'
        try:
            if tags.get('height'):height=float(tags['height'].replace(' m',''));source='height'
            elif tags.get('building:levels'):height=float(tags['building:levels'])*3.2;source='levels'
        except ValueError:height=3.2;source='presentation_fallback_3.2m'
        if height<=0 or height>100:excluded.append({'way_id':way['id'],'reason':'unsupported_height'});continue
        roof=triangles(poly);footprint=points[:-1]
        cells[region(poly.centroid.coords[0])]['buildings'].append({'way_id':way['id'],'footprint':footprint,'roof':roof,'height_m':height,'height_source':source})
        counts['buildings']+=1;counts['roof_triangles']+=len(roof)//3;counts['wall_triangles']+=len(footprint)*2
    kind=tags.get('highway','')
    if kind in widths and len(points)>=2:
        road_shapes.append(LineString(points).buffer(widths[kind]/2,cap_style=2,join_style=2))
        road_sources.append({'way_id':way['id'],'node_ids':ids,'points':points,'width_world_px':widths[kind]})
        counts['road_ways']+=1
all_roads=unary_union(road_shapes)
new_roads=all_roads.difference(road_exclusion)
old_roads=all_roads.difference(occupied)
tris=triangles(new_roads,8)
# 验证输出三角真正覆盖新增接坪段，且没有改动既有边界以外的源道路。
packed_roads=unary_union([Polygon(tris[i:i+3]) for i in range(0,len(tris),3)])
audit={'added_area':new_roads.difference(old_roads).area,
       'lost_old_road_area':old_roads.difference(new_roads).area,
       'outside_old_clearance_change_area':new_roads.symmetric_difference(old_roads).difference(occupied).area,
       'packed_area_error':new_roads.symmetric_difference(packed_roads).area,
       'facility_overlap_area':packed_roads.intersection(road_exclusion).area}
print(json.dumps(audit))
assert audit['lost_old_road_area']<.001 and audit['outside_old_clearance_change_area']<.001
assert audit['packed_area_error']<.1 and audit['facility_overlap_area']<.1
(root/'road-geometry-audit.json').write_text(json.dumps(audit,indent=2)+'\n',encoding='utf-8')
for i in range(0,len(tris),3):
    tri=tris[i:i+3];center=[sum(p[j] for p in tri)/3 for j in (0,1)]
    cells[region(center)]['roads'].extend(tri)
counts['road_triangles']=len(tris)//3
joins=[]
for road in road_sources:
    clipped=LineString(road['points']).difference(road_exclusion)
    parts=list(clipped.geoms) if hasattr(clipped,'geoms') else [clipped]
    for part in parts:
        if part.is_empty or not hasattr(part,'coords'):continue
        for xy in [part.coords[0],part.coords[-1]]:
            point=Point(xy)
            if road_exclusion.boundary.distance(point)<.00001:
                joins.append({'way_id':road['way_id'],'point':list(xy)})
report={'source_sha256':hashlib.sha256(raw_path.read_bytes()).hexdigest(),'map_sha256':hashlib.sha256(doc_path.read_bytes()).hexdigest(),'license':'OpenStreetMap contributors ODbL https://www.openstreetmap.org/copyright','projection':'existing bbox Mercator UV -> original world rect','gameplay_changed':False,'source_road_nodes_preserved':True,'counts':counts,'excluded_buildings':excluded,'road_widths':'presentation widths, not surveyed widths','candidate_only':True}
data={'schema_version':1,'source':report,'cells':cells,'road_sources':road_sources,'road_clip_footprints':road_clip_records,'road_joins':joins}
(root/'native-context.json').write_text(json.dumps(data,separators=(',',':'))+'\n',encoding='utf-8')
args.output.write_text(json.dumps(data,separators=(',',':'))+'\n',encoding='utf-8')
(root/'source-report.json').write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8')
print(json.dumps({'counts':counts,'excluded_buildings':len(excluded),'bytes':(root/'native-context.json').stat().st_size,'cells':{k:len(v['buildings']) for k,v in cells.items()}}))
