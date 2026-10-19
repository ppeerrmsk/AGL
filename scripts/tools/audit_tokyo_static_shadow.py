"""独立检查原来源高度、遮罩摘要、分辨率/内存门及范围外像素。"""
import hashlib
import json
import sys
from pathlib import Path
import numpy as np
from PIL import Image


def audit(root, assets, images):
    output = images/'independent_audit.json'
    if output.exists():
        raise ValueError('audit output already exists')
    source = (root/'r30-area-source-b/north_coast/city.json').read_bytes()
    metadata = json.loads((assets/'manifest.json').read_bytes())
    raw = {str(r['id']): r for r in json.loads(source)['buildings']}
    fail = int(hashlib.sha256(source).hexdigest() != metadata['source_sha256'])
    span = max(metadata['bounds'][2]-metadata['bounds'][0],metadata['bounds'][3]-metadata['bounds'][1])
    fail += int(metadata['source_count'] != len(set(s['id'] for s in metadata['sources'])))
    for item in metadata['sources']:
        original = raw[item['id']]
        fail += int(original['height_m'] != item['height_m'] or original.get('min_height_m', 0) != item['min_height_m'])
    for row in metadata['rows']:
        data = (assets/row['file']).read_bytes()
        picture = Image.open(assets/row['file'])
        fail += int(hashlib.sha256(data).hexdigest() != row['sha256'] or picture.mode != 'L' or picture.size != (row['size'], row['size'])
                    or abs(row['max_scale']-row['size']/span)>1e-9)
    review = json.loads((images/'review.json').read_bytes())
    fail += review['fail']
    records = []
    for row in review['records']:
        stem = row['stem']
        before = np.asarray(Image.open(stem+'_original.png').convert('RGB'), dtype=np.int16)
        restored = np.asarray(Image.open(stem+'_restored.png').convert('RGB'), dtype=np.int16)
        mask = np.zeros(before.shape[:2], dtype=bool)
        for x0,y0,x1,y1 in row['allowed_screen_bounds']:
            x0,x1 = max(0,int(np.floor(x0-2))), min(mask.shape[1],int(np.ceil(x1+2)))
            y0,y1 = max(0,int(np.floor(y0-2))), min(mask.shape[0],int(np.ceil(y1+2)))
            if x1>x0 and y1>y0:
                mask[y0:y1,x0:x1] = True
        fail += int(np.abs(before-restored).max()>1 or row['state']['output_scale']>row['shadow']['max_scale']
                    or row['shadow']['conservative_resident_bytes']>96*1024*1024
                    or not row.get('geometry_unchanged',True))
        for strength in [50,70]:
            candidate = np.asarray(Image.open(stem+f'_static_{strength}.png').convert('RGB'), dtype=np.int16)
            delta = np.abs(before-candidate)
            outside = int(((delta.max(2)>1)&~mask).sum())
            fail += int(outside>0)
            records.append({'zoom':row['zoom'],'rotation':row['rotation'],'strength':strength,
                            'outside_gt1':outside,'changed_pixels':int((delta.max(2)>1).sum()),
                            'mean_channel_error':float(delta.mean()),'max_channel_error':int(delta.max())})
    result = {'fail':fail,'source_count':metadata['source_count'],'records':records,'dynamic_pass_removed':False}
    output.write_text(json.dumps(result,indent=2),encoding='utf-8')
    print(json.dumps(result))
    return int(fail>0)


if __name__ == '__main__':
    raise SystemExit(audit(*map(Path,sys.argv[1:])))
