"""同源海岸构筑物的独立补充面；扣除已绘地表/楼体，不改海陆权威或原包。"""
import argparse
import hashlib
import json
from pathlib import Path

from build_tokyo_volume_region import above_ground, box, polygons, Polygon, unary_union, wkb
from build_tokyo_footprint_lod import f32, within_error
from shapely import constrained_delaunay_triangles

KINDS = {'pier', 'quay', 'breakwater', 'groyne'}
WORLD_ERROR = .01 / 5.0


def native_faces(shape, occupied=None):
    """float32逐角重建；退化三角只在整体面积、边界、孔洞同时守恒时可接受。"""
    if shape.is_empty or not shape.is_valid or shape.geom_type != 'Polygon':
        return None
    native_shape = None
    # 先量化轮廓再三角化，避免极短接边在逐角量化后反转三角。
    # 无效原源已在入口拒绝；这里只对其量化派生轮廓尝试有界小简化。
    for factor in (0.0, .125, .25, .5):
        proposal = shape if factor == 0 else shape.simplify(WORLD_ERROR*factor,preserve_topology=True)
        candidate = Polygon([(f32(x),f32(y)) for x,y in proposal.exterior.coords],
            [[(f32(x),f32(y)) for x,y in ring.coords] for ring in proposal.interiors])
        if not candidate.is_empty and within_error(shape,candidate,WORLD_ERROR) \
                and abs(candidate.area/shape.area-1)<=.05:
            native_shape = candidate
            break
    if native_shape is None:
        return None
    triangles = []
    faces = []
    for tri in constrained_delaunay_triangles(native_shape).geoms:
        points = [[f32(x), f32(y)] for x,y in list(tri.exterior.coords)[:3]]
        face = Polygon(points)
        if face.area == 0:
            continue
        if not face.is_valid:
            return None
        triangles.extend(points)
        faces.append(face)
    native = unary_union(faces)
    inset = 0.0
    if occupied is not None and native.intersection(occupied).area > 1e-7:
        # 只收窄量化后发生重叠的接点；回退结果仍必须相对原shape过完整误差门。
        inset = WORLD_ERROR * .5
        trimmed = native_faces(shape.difference(occupied.buffer(inset,join_style=2)))
        if trimmed is None:
            return None
        triangles = trimmed['triangles']
        native = wkb.loads(trimmed['native_wkb'],hex=True)
        faces = [Polygon(triangles[i:i+3]) for i in range(0,len(triangles),3)]
        if native.intersection(occupied).area > 1e-7:
            return None
    if native.is_empty or not within_error(shape, native, WORLD_ERROR) \
            or abs(native.area / shape.area - 1) > .05 \
            or abs(sum(face.area for face in faces) - native.area) > 1e-7:
        return None
    return {'triangles': triangles, 'area_px2': shape.area, 'native_area_px2': native.area,
            'contact_inset_world_px':inset,
            'source_wkb': shape.wkb_hex, 'native_wkb': native.wkb_hex}


def existing_coverage(city, ground):
    """只排除实际会绘制的楼体；水上pier仍是独立面，不提升为海陆碰撞数据。"""
    faces = []
    for surface in ground['surfaces']:
        if surface['kind'] == 'water':
            continue
        points = surface['triangles']
        if len(points) % 3:
            raise ValueError('incomplete existing ground triangle')
        faces.extend(Polygon(points[i:i+3]) for i in range(0,len(points),3))
    identities = set()
    for building in city['buildings']:
        if building.get('defer_render') or not building.get('render_outline',True):
            continue
        identities.add(building['id'])
        faces.extend(Polygon(ring['outer'],ring.get('holes',[])) for ring in building['rings'])
    if any(not face.is_valid for face in faces):
        raise ValueError('invalid existing coverage, repair separately')
    return unary_union(faces), identities


def prepare(inventory, coverage, existing, building_ids):
    """稳定ID唯一领取；每项都有采用/暂缓记录，输入不变。"""
    if not coverage.is_valid or not existing.is_valid:
        raise ValueError('invalid coverage')
    seen = set()
    claimed = existing
    native_claimed = Polygon()
    result = {'schema_version':1, 'world_error_px':WORLD_ERROR, 'max_output_scale':5.0,
              'surfaces':[], 'audit':[], 'deferred_ways':[]}
    for record in sorted(inventory['areas'],key=lambda value:value['id']):
        identity = record['id']
        if identity in seen:
            raise ValueError('duplicate source identity: '+identity)
        seen.add(identity)
        tags = record['tags']
        row = {'id':identity, 'source_tags':tags, 'status':'excluded', 'pieces':[]}
        result['audit'].append(row)
        if tags.get('man_made') not in KINDS or not above_ground(tags) or tags.get('area') == 'no':
            continue
        shape = wkb.loads(record['wkb'],hex=True)
        if not shape.is_valid:
            row['status'] = 'deferred_invalid_source'
            continue
        if identity in building_ids:
            row['status'] = 'existing_building_identity'
            continue
        clipped = shape.intersection(coverage)
        row['covered_area_px2'] = clipped.area
        if clipped.area == 0:
            row['status'] = 'outside_coverage'
            continue
        missing = clipped.difference(claimed)
        row['missing_area_px2'] = missing.area
        row['existing_area_px2'] = clipped.area - missing.area
        row['status'] = 'existing_geometry' if missing.area == 0 else 'prepared'
        for part, polygon in enumerate(polygons(missing)):
            if polygon.is_empty or polygon.area == 0:
                continue
            prepared = native_faces(polygon, native_claimed)
            piece = {'part':part, 'area_px2':polygon.area, 'status':'prepared' if prepared else 'deferred_native_precision'}
            row['pieces'].append(piece)
            if prepared is None:
                continue
            # 新增面与所有既有面只允许float32误差带内的极小接边。
            native = wkb.loads(prepared['native_wkb'],hex=True)
            overlap = native.intersection(claimed)
            if not overlap.is_empty and not overlap.covered_by(polygon.boundary.buffer(WORLD_ERROR)):
                piece['status'] = 'deferred_native_overlap'
                continue
            result['surfaces'].append({'id':identity, 'part':part, 'kind':tags['man_made'], **prepared})
            claimed = claimed.union(polygon)
            native_claimed = native_claimed.union(native)
        if missing.area and not any(p['status']=='prepared' for p in row['pieces']):
            row['status'] = 'deferred_native_precision'
    for way in inventory['ways']:
        if way['id'] not in seen:
            result['deferred_ways'].append({'id':way['id'], 'source_tags':way['tags'],
                'reason':'no_assembled_area_no_inferred_width'})
    result['deferred_ways'].sort(key=lambda row:row['id'])
    result['triangles'] = sum(len(s['triangles'])//3 for s in result['surfaces'])
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--inventory',type=Path,required=True)
    parser.add_argument('--source',type=Path,required=True)
    parser.add_argument('--output',type=Path,required=True)
    args = parser.parse_args()
    if args.output.exists():
        parser.error('output exists; use a new candidate')
    inventory = json.loads(args.inventory.read_text(encoding='utf-8'))
    regions, existing, identities, hashes = [], [], set(), {}
    for name in ('yokohama','north_coast'):
        data = {}
        for kind in ('city','ground'):
            payload = (args.source/name/(kind+'.json')).read_bytes()
            hashes[name+'/'+kind] = hashlib.sha256(payload).hexdigest()
            data[kind] = json.loads(payload)
        cover, ids = existing_coverage(data['city'],data['ground'])
        existing.append(cover)
        identities.update(ids)
        regions.append(box(*data['ground']['bounds']))
    result = prepare(inventory,unary_union(regions),unary_union(existing),identities)
    result['provenance'] = {'inventory_sha256':hashlib.sha256(args.inventory.read_bytes()).hexdigest(),
        'pbf_sha256':inventory['pbf_sha256'],'pbf_bytes':inventory['pbf_bytes'],'source_hashes':hashes}
    args.output.parent.mkdir(parents=True,exist_ok=True)
    with args.output.open('x',encoding='utf-8') as file:
        json.dump(result,file,ensure_ascii=False,separators=(',',':'))
    print(json.dumps({'output':str(args.output),'surfaces':len(result['surfaces']),
        'source_ids':len({s['id'] for s in result['surfaces']}),'triangles':result['triangles'],
        'deferred_ways':len(result['deferred_ways'])}))


if __name__ == '__main__':
    main()
