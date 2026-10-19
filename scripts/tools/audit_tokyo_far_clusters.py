"""R57独立审查实际接受组与地图截图；不把局部面数下降当成性能验收。"""
import argparse
import hashlib
import json
from pathlib import Path
import numpy as np
from PIL import Image
from shapely import STRtree, unary_union
from shapely.geometry import Polygon, LineString, box
from build_tokyo_footprint_lod import f32


def polygon(points):
    return Polygon([(f32(x), f32(y)) for x, y in points])


def audit(root, native, images):
    city = json.loads((root / 'r30-area-source-b/north_coast/city.json').read_bytes())
    raw = {str(r['id']): r for r in city['buildings']}
    buildings, identities = [], []
    for identity, record in raw.items():
        if record.get('defer_render') or not record.get('render_outline', True):
            continue
        for ring in record.get('rings', []):
            shape = Polygon([(f32(x), f32(y)) for x, y in ring['outer']], ring.get('holes', []))
            if shape.is_valid and not shape.is_empty:
                buildings.append(shape)
                identities.append(identity)
    building_tree = STRtree(buildings)
    barriers = []
    for record in city.get('roads', []) + [r for r in city.get('rails', []) if r.get('class') != 'subway']:
        for stroke in record.get('joined_strokes', {}).values():
            points = stroke.get('triangles', [])
            parts = [polygon(points[i:i+3]) for i in range(0, len(points), 3)]
            barriers.extend(p for p in parts if p.is_valid and not p.is_empty)
    ground = json.loads((root / 'r24-owned-source-b/north_coast/ground.json').read_bytes())
    for surface in ground['surfaces']:
        if surface['kind'] == 'water':
            points = surface['triangles']
            barriers.extend(polygon(points[i:i+3]) for i in range(0, len(points), 3))
    barrier_tree = STRtree(barriers)
    manifest = json.loads((native / 'manifest.json').read_bytes())
    used = {1: set(), 2: set(), 3: set(), 4: set(), 5: set()}
    geometry_errors = []
    profile_barriers = {}
    proxies = {1:[],2:[],3:[],4:[],5:[]}
    for row in manifest['rows']:
        profile = row.get('block_profile','')
        maximum, pixel_error, area_error, span, vertices = 8, 1., .12, float('inf'), float('inf')
        active_barriers = barrier_tree
        if profile:
            from build_tokyo_block_lod import PROFILES
            if profile not in PROFILES:
                raise ValueError('unknown block profile')
            plan_bytes=Path(row['plan']).read_bytes()
            plan=json.loads(plan_bytes)
            if hashlib.sha256(plan_bytes).hexdigest()!=row['plan_sha256'] or plan.get('profile')!=profile or plan.get('schema')!=2 or plan.get('strategy')!='street_blocks' or any(plan.get(k)!=v for k,v in PROFILES[profile].items()):
                raise ValueError('block contract or plan identity mismatch')
            if profile in ('district6','district8','district12','district16','district20','district24','district20wide','district24wide','district24street','district24street45') and (row['level']!=5 or row['max_scale']!=5.0 or plan.get('max_scale')!=5.0):
                raise ValueError('district candidate cannot extend to other LODs')
            if profile in ('mid4','mid6') and (row['level']!=4 or row['max_scale']!=1.5552 or plan.get('max_scale')!=1.5552):
                raise ValueError('middle district candidate cannot extend to other LODs')
            if row['level']==4 and profile not in ('mid4','mid6'):
                raise ValueError('legacy contracts cannot silently reach middle LOD')
            if profile in ('far4','far6','far8wide','far12wide','street6','street8') and (row['level'] not in (1,2) or row['max_scale']!={1:.1944,2:.3888}[row['level']] or plan.get('max_scale')!=row['max_scale']):
                raise ValueError('far district candidate cannot extend to near LODs')
            maximum,pixel_error,area_error,span,vertices=[plan[k] for k in ['max_group','occupied_error_px','area_error','max_span','max_vertices']]
            if profile not in profile_barriers:
                protected=[]
                for is_road, record in [(True,r) for r in city.get('roads',[])]+[(False,r) for r in city.get('rails',[]) if r.get('class')!='subway']:
                    if plan['roads']=='structural' and is_road and record.get('class') in {'service','path','footway','steps'} and float(record.get('width_px',1))<1.5:
                        continue
                    strokes=record.get('joined_strokes',{})
                    if not strokes and len(record.get('points',[]))>=2:
                        protected.append(LineString(record['points']).buffer(max(.1,float(record.get('width_px',1)))/2+.475))
                    for stroke in strokes.values():
                        points=stroke.get('triangles',[])
                        if len(points)%3:
                            raise ValueError('incomplete prepared road triangle')
                        protected.extend(polygon(points[i:i+3]) for i in range(0,len(points),3))
                for surface in ground['surfaces']:
                    if surface['kind'] in ['water','park','green']:
                        points=surface['triangles']
                        protected.extend(polygon(points[i:i+3]) for i in range(0,len(points),3))
                if any(not p.is_valid or p.is_empty for p in protected):
                    raise ValueError('invalid structural barrier')
                profile_barriers[profile]=STRtree(protected)
            active_barriers=profile_barriers[profile]
        for group in row['groups']:
            ids = group['ids']
            original = unary_union([polygon(raw[i]['rings'][0]['outer']) for i in ids])
            merged = polygon(group['candidate'])
            limit = pixel_error / row['max_scale']
            valid = (2 <= len(ids) <= maximum and not used[row['level']].intersection(ids)
                     and all(raw[i]['height_source'] == 'fallback' and raw[i]['height_m'] * .5 == group['height_px']
                             and 0 < raw[i]['height_m'] <= 24 for i in ids)
                     and merged.is_valid and not merged.interiors
                     and (not profile or box(*plan['bounds']).covers(merged))
                     and abs(merged.area / original.area - 1) <= area_error
                     and (plan.get('min_vertices',3) if profile else 3)<=len(merged.exterior.coords)-1<=vertices
                     and max(merged.bounds[2]-merged.bounds[0],merged.bounds[3]-merged.bounds[1])<=span
                     and original.covered_by(merged.buffer(limit, quad_segs=16))
                     and merged.covered_by(original.buffer(limit, quad_segs=16)))
            addition = merged.difference(original)
            if profile and plan.get('shape_policy') is not None:
                from build_tokyo_block_lod import shape_acceptable
                valid = valid and shape_acceptable(merged, plan['shape_policy'])
            collisions = [int(i) for i in active_barriers.query(addition, predicate='intersects')]
            others = [identities[int(i)] for i in building_tree.query(addition, predicate='intersects') if identities[int(i)] not in ids]
            if not valid or collisions or others:
                geometry_errors.append({'cell': row['cell_id'], 'level': row['level'], 'ids': ids,
                                        'contract': valid, 'barriers': len(collisions), 'other_buildings': others})
            used[row['level']].update(ids)
            proxies[row['level']].append(merged)
    for level,polys in proxies.items():
        tree=STRtree(polys)
        for n,p in enumerate(polys):
            for other in tree.query(p,predicate='intersects'):
                if int(other)>n and p.intersection(polys[int(other)]).area>0:
                    geometry_errors.append(dict(level=level,overlapping_groups=[n,int(other)]))
    review = json.loads((images / 'review.json').read_bytes())
    pixels = []
    for row in review['records']:
        if row.get('blocked'):
            pixels.append({'pose':row['pose'],'zoom':row['zoom'],'blocked':row['blocked']})
            continue
        stem = Path(row['stem'])
        before = np.asarray(Image.open(str(stem) + '_original.png').convert('RGBA'), dtype=np.int16)
        after = np.asarray(Image.open(str(stem) + '_candidate.png').convert('RGBA'), dtype=np.int16)
        restored = np.asarray(Image.open(str(stem) + '_restored.png').convert('RGBA'), dtype=np.int16)
        delta = np.abs(before - after).max(axis=2)
        mask = np.zeros(delta.shape, dtype=bool)
        pad = row['mask_padding_px']
        for x0, y0, x1, y1 in row['allowed_screen_bounds']:
            left, right = max(0, int(np.floor(x0-pad))), min(delta.shape[1], int(np.ceil(x1+pad)))
            top, bottom = max(0, int(np.floor(y0-pad))), min(delta.shape[0], int(np.ceil(y1+pad)))
            if right > left and bottom > top:
                mask[top:bottom, left:right] = True
        pixels.append({'pose': row['pose'], 'zoom': row['zoom'], 'outside_gt1': int(((delta > 1) & ~mask).sum()),
                       'restore_max': int(np.abs(before-restored).max()), 'changed_pixels': int((delta > 1).sum()),
                       'mask_pixels': int(mask.sum()), 'faces': row['faces'], 'original_faces':row.get('original_faces',row['state']['triangles']), 'resident_bytes': row['resident_bytes']})
    result = {'geometry_errors': geometry_errors, 'accepted_sources': {k: len(v) for k, v in used.items()}, 'pixels': pixels,
              'fail': len(geometry_errors) + int(review.get('fail',1)) + sum(bool(r.get('blocked')) or r['outside_gt1'] > 0 or r['restore_max'] > 1 for r in pixels)}
    (images / 'independent_audit.json').write_text(json.dumps(result, indent=2), encoding='utf8')
    print(json.dumps({'geometry_errors': len(geometry_errors), 'accepted_sources': result['accepted_sources'], 'pixels': pixels, 'fail': result['fail']}))
    return int(result['fail'] != 0)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('root', type=Path)
    parser.add_argument('native', type=Path)
    parser.add_argument('images', type=Path)
    args = parser.parse_args()
    return audit(args.root, args.native, args.images)


if __name__ == '__main__':
    raise SystemExit(main())
