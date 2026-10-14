"""独立核生成后地表：非目标三角完全保留，目标层完整集合双向误差门。"""
import argparse
from collections import Counter
import hashlib
import json
from pathlib import Path
import sys
import numpy as np
sys.path.insert(0, str(Path(__file__).resolve().parents[2]/'tmp/tokyo-geometry-deps'))
from shapely import polygons, union_all


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def read_mesh(path):
    raw = path.read_bytes()
    if not raw or len(raw) % 120:
        raise ValueError('invalid triangle attribute length')
    result = np.frombuffer(raw, dtype='<f4').reshape(-1, 3, 10)
    if not np.isfinite(result).all():
        raise ValueError('nonfinite attributes')
    return result


def masks(data):
    result = []
    for height, color in [(.22, [156,157,141]), (.38, [110,119,114])]:
        rgb = np.asarray(color, dtype=np.float32)/255
        result.append(np.all(data[:,:,1] == np.float32(height),axis=1) &
                      np.all(data[:,:,6:9] == rgb,axis=(1,2)))
    return result


def corners(data):
    return Counter(min(t.tobytes(), np.roll(t,1,axis=0).tobytes(),
                       np.roll(t,2,axis=0).tobytes()) for t in data)


def appearances(data):
    raw = data[:,:,[1,3,4,5,6,7,8,9]].reshape(-1,8).tobytes()
    return {raw[i:i+32] for i in range(0,len(raw),32)}


def verify(original, candidate):
    old_masks, new_masks = masks(original), masks(candidate)
    old_other = original[~(old_masks[0] | old_masks[1])]
    new_other = candidate[~(new_masks[0] | new_masks[1])]
    if corners(old_other) != corners(new_other):
        raise ValueError('non-target geometry or attributes changed')
    layers = []
    for label, old_mask, new_mask in zip(('paths','minor_roads'), old_masks, new_masks):
        before, after = original[old_mask], candidate[new_mask]
        if not len(before) or not len(after):
            raise ValueError('missing semantic layer')
        # 所有目标角的高度/法线/颜色保持原来的属性集合，不接受纹理或透明度替代。
        if not appearances(after).issubset(appearances(before)):
            raise ValueError('target appearance attributes drift')
        a = union_all(polygons(before[:,:,[0,2]]))
        b = union_all(polygons(after[:,:,[0,2]]))
        if not a.is_valid or not b.is_valid or a.is_empty or b.is_empty:
            raise ValueError('invalid planar union')
        if not a.buffer(.2,quad_segs=16).covers(b) or not b.buffer(.2,quad_segs=16).covers(a):
            outside_new = b.difference(a.buffer(.2,quad_segs=16))
            outside_old = a.difference(b.buffer(.2,quad_segs=16))
            raise ValueError(json.dumps(dict(error='generated geometry exceeds world-space error bound',
                layer=label,new_outside_area=outside_new.area,old_outside_area=outside_old.area,
                new_outside_bounds=outside_new.bounds,old_outside_bounds=outside_old.bounds)))
        layers.append(dict(layer=label,original_faces=len(before),candidate_faces=len(after),
                           bidirectional_set_distance_bound=.2,original_area=a.area,candidate_area=b.area))
    return dict(unchanged_other_faces=len(old_other),non_target_oriented_corners_exact=True,
                layers=layers,original_faces=len(original),candidate_faces=len(candidate),
                visual_verified=False,runtime_integrated=False)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('export',type=Path)
    parser.add_argument('candidate',type=Path)
    parser.add_argument('output',type=Path)
    args = parser.parse_args()
    args.export, args.candidate, args.output = args.export.resolve(), args.candidate.resolve(), args.output.resolve()
    if args.output.exists(): raise ValueError('output exists')
    source = json.loads(args.export.read_bytes())
    if len(source['ground_export']) != 1: raise ValueError('ambiguous source')
    target, row = next(iter(source['ground_export'].items()))
    original = Path(row['path'])
    if digest(original) != row['sha256']: raise ValueError('source export drift')
    result = verify(read_mesh(original),read_mesh(args.candidate))
    result.update(schema=1,target=target,source_export=dict(path=str(args.export),sha256=digest(args.export)),
                  original_attributes=dict(path=str(original),sha256=digest(original)),
                  candidate_attributes=dict(path=str(args.candidate),sha256=digest(args.candidate)))
    args.output.write_text(json.dumps(result,indent=2),encoding='utf-8')
    print(json.dumps(result))


if __name__ == '__main__': main()
