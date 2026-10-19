"""远景计划保存前过滤：按实际准备好的路面/描边/铁路/水面三角验新增占地。"""
import argparse
import hashlib
import json
from pathlib import Path
from shapely import STRtree, unary_union
from audit_tokyo_far_clusters import polygon


def filter_plan(root, source, output):
    if output.exists():
        raise ValueError('filtered plan must not overwrite evidence')
    city_bytes = (root / 'r30-area-source-b/north_coast/city.json').read_bytes()
    ground_bytes = (root / 'r24-owned-source-b/north_coast/ground.json').read_bytes()
    city, ground = json.loads(city_bytes), json.loads(ground_bytes)
    plan = json.loads(source.read_bytes())
    if plan['source_sha256'] != hashlib.sha256(city_bytes).hexdigest() or plan['ground_sha256'] != hashlib.sha256(ground_bytes).hexdigest():
        raise ValueError('barrier source identity mismatch')
    barriers = []
    for record in city.get('roads', []) + [r for r in city.get('rails', []) if r.get('class') != 'subway']:
        for stroke in record.get('joined_strokes', {}).values():
            points = stroke.get('triangles', [])
            if len(points) % 3:
                raise ValueError('partial native road triangle')
            barriers.extend(polygon(points[i:i+3]) for i in range(0, len(points), 3))
    for surface in ground['surfaces']:
        if surface['kind'] == 'water':
            points = surface['triangles']
            barriers.extend(polygon(points[i:i+3]) for i in range(0, len(points), 3))
    if any(not p.is_valid for p in barriers):
        raise ValueError('invalid prepared barrier')
    tree = STRtree(barriers)
    raw = {str(r['id']): r for r in city['buildings']}
    kept, rejected = [], []
    for group in plan['groups']:
        original = unary_union([polygon(raw[i]['rings'][0]['outer']) for i in group['ids']])
        addition = polygon(group['outer']).difference(original)
        if len(tree.query(addition, predicate='intersects')):
            rejected.append(group['ids'])
        else:
            kept.append(group)
    plan['groups'] = kept
    plan['merged_sources'] = sum(len(g['ids']) for g in kept)
    plan['faces_saved'] = sum(g['faces_saved'] for g in kept)
    plan['prepared_barrier_rejected'] = rejected
    plan['input_plan_sha256'] = hashlib.sha256(source.read_bytes()).hexdigest()
    output.write_text(json.dumps(plan, separators=(',', ':')), encoding='utf8')
    print(json.dumps({'output': str(output), 'groups': len(kept), 'rejected_groups': rejected}))


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('root', type=Path)
    parser.add_argument('source', type=Path)
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    filter_plan(args.root, args.source, args.output)
