"""从登记来源制作路径简化候选；不把中心线误差当线带/拓扑验收。"""
import argparse
from collections import Counter
import copy
import hashlib
import json
from pathlib import Path
from build_tokyo_volume_preview import simplify


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def build(source, registry, tile, output, tolerance=.2):
    entry = next(row for row in json.loads(registry.read_bytes())['rows'] if row['tile'] == tile)
    if digest(source) != entry['hashes']['ground'] or output.exists() or not 0 < tolerance <= .2:
        raise ValueError('source identity, output or tolerance rejected')
    original = json.loads(source.read_bytes())
    data = copy.deepcopy(original)
    counts = Counter(tuple(p) for row in data['paths'] for p in row['points'])
    # 已记录的连接点必须保留；隐式线段相交需要下一道拓扑门，不能假装已证明。
    locked = {point for point, count in counts.items() if count > 1}
    city = Path(entry['source'])/'city.json'
    if digest(city) != entry['hashes']['city']:
        raise ValueError('road source identity drift')
    roads = json.loads(city.read_bytes())
    for kind in ('roads', 'rails'):
        locked.update(tuple(p) for row in roads.get(kind, []) for p in row['points'])
    before = after = changed = 0
    for row in data['paths']:
        points = row['points']
        before += max(0, len(points)-1)
        if len(points) < 3:
            after += max(0, len(points)-1)
            continue
        anchors = sorted({0, len(points)-1} | {i for i,p in enumerate(points) if tuple(p) in locked})
        result = []
        for start, end in zip(anchors, anchors[1:]):
            result.extend(simplify(points[start:end+1], tolerance)[:-1])
        result.append(points[-1])
        if result[0] != points[0] or result[-1] != points[-1]:
            raise ValueError('endpoint drift')
        changed += result != points
        row['points'] = result
        after += max(0, len(result)-1)
    if any(data[k] != original[k] for k in original if k != 'paths'):
        raise ValueError('non-path layer modified')
    output.mkdir(parents=True)
    target = output/'ground.json'
    target.write_text(json.dumps(data, separators=(',', ':')), encoding='utf-8')
    if json.loads(target.read_bytes()) != data:
        raise ValueError('source roundtrip drift')
    report = dict(source=str(source.resolve()), source_sha256=digest(source),
                  registry_sha256=digest(registry), city_sha256=digest(city),
                  candidate_sha256=digest(target), paths=len(data['paths']), changed_paths=changed,
                  segments_before=before, segments_after=after,
                  estimated_unclipped_face_saving=2*(before-after),
                  centerline_tolerance=tolerance, max_scale_5_centerline_pixels=tolerance*5,
                  non_path_layers_unchanged=True, recorded_junctions_preserved=True,
                  implicit_crossings_verified=False, ribbon_error_verified=False,
                  original_mesh_replay_verified=False, runtime_integrated=False)
    (output/'report.json').write_text(json.dumps(report,indent=2), encoding='utf-8')
    print(json.dumps(report))


if __name__ == '__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source',type=Path)
    parser.add_argument('registry',type=Path)
    parser.add_argument('tile')
    parser.add_argument('output',type=Path)
    args=parser.parse_args()
    build(args.source,args.registry,args.tile,args.output)
