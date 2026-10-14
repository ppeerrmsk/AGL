"""定位最终三角并集超距对应的已修改源线，输出局部恢复候选，不扩大容差。"""
import argparse
import json
from pathlib import Path
from verify_tokyo_simplified_ground import digest, read_mesh, masks
from shapely import polygons, union_all
from review_tokyo_path_candidate import ribbon


def locate(export, candidate, original_ground, candidate_ground, original_city, candidate_city, output):
    if output.exists(): raise ValueError('output exists')
    export_data = json.loads(export.read_bytes())
    row = next(iter(export_data['ground_export'].values()))
    original_attributes = Path(row['path'])
    if digest(original_attributes) != row['sha256']: raise ValueError('export drift')
    original, modified = read_mesh(original_attributes), read_mesh(candidate)
    old_masks, new_masks = masks(original), masks(modified)
    results = []
    restored = {}
    for name, old_file, new_file, old_mask, new_mask in zip(
        ('paths','roads'), (original_ground,original_city), (candidate_ground,candidate_city), old_masks,new_masks):
        old_data, new_data = json.loads(old_file.read_bytes()), json.loads(new_file.read_bytes())
        a = union_all(polygons(original[old_mask][:,:,[0,2]]))
        b = union_all(polygons(modified[new_mask][:,:,[0,2]]))
        error = union_all([b.difference(a.buffer(.2,quad_segs=16)), a.difference(b.buffer(.2,quad_segs=16))])
        rows = []
        matched = []
        if len(old_data[name]) != len(new_data[name]): raise ValueError('source row count drift')
        for index, (old,new) in enumerate(zip(old_data[name],new_data[name])):
            if old == new: continue
            if old.get('id') != new.get('id'): raise ValueError('source order drift')
            width = .8 if name == 'paths' else old['width_px']
            envelope = ribbon(old['points'],width).union(ribbon(new['points'],width)).buffer(.01)
            overlap = error.intersection(envelope)
            if overlap.is_empty: continue
            matched.append(overlap)
            rows.append(dict(index=index,id=old.get('id'),error_area=overlap.area,
                             restored_segments=len(old['points'])-len(new['points'])))
            new_data[name][index] = old
        unmatched = error.difference(union_all(matched))
        results.append(dict(layer=name,error_area=error.area,unmatched_area=unmatched.area,
                            unmatched_bounds=[] if unmatched.is_empty else unmatched.bounds,restored=rows,
                            source_sha256=digest(old_file),candidate_sha256=digest(new_file)))
        restored['ground.json' if name == 'paths' else 'city.json'] = new_data
    output.mkdir(parents=True)
    for filename,data in restored.items():
        (output/filename).write_text(json.dumps(data,separators=(',',':')),encoding='utf-8')
    report = dict(source_export_sha256=digest(export),attributes_sha256=digest(candidate),
                  layers=results,generated_geometry_verified=False,runtime_integrated=False)
    (output/'report.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
    print(json.dumps(report))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('export','candidate','original_ground','candidate_ground','original_city','candidate_city','output'):
        parser.add_argument(name,type=Path)
    locate(**vars(parser.parse_args()))
