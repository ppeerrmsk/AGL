"""5bit行内低位先行索引；不量化接收高度，不改AO载荷或原清单。"""
import hashlib
import json
import shutil
import sys
from pathlib import Path
import numpy as np
from PIL import Image


def pack5(indices):
    if indices.dtype!=np.uint8 or indices.ndim!=2 or indices.shape[1]%8 or not indices.size or indices.max()>31:
        raise ValueError('expected nonempty R8 indices below32 and row width multiple8')
    groups=indices.reshape(indices.shape[0],-1,8).astype(np.uint64)
    words=np.zeros(groups.shape[:2],dtype=np.uint64)
    for n in range(8):words|=groups[:,:,n]<<(5*n)
    return np.stack([(words>>(8*n)).astype(np.uint8) for n in range(5)],axis=2).reshape(indices.shape[0],-1)


def unpack5(packed):
    if packed.dtype!=np.uint8 or packed.ndim!=2 or not packed.size or packed.shape[1]%5:
        raise ValueError('invalid packed rows')
    groups=packed.reshape(packed.shape[0],-1,5).astype(np.uint64)
    words=np.zeros(groups.shape[:2],dtype=np.uint64)
    for n in range(5):words|=groups[:,:,n]<<(8*n)
    return np.stack([((words>>(5*n))&31).astype(np.uint8) for n in range(8)],axis=2).reshape(packed.shape[0],-1)


def build(source,output):
    if output.exists():raise ValueError('never overwrite evidence')
    manifest=json.loads((source/'manifest.json').read_bytes())
    if manifest.get('height_encoding')!='global_palette_r8' or manifest.get('height_size')!=2048 or manifest.get('ao_encoding')!='bc4_unorm_mips':
        raise ValueError('expected original full resolution BC4 plus palette R8')
    names={manifest['palette']:manifest['palette_sha256']}
    for row in manifest['rows']:
        for field in ['ao','height']:names[row[field]]=row[field+'_sha256']
    for name,digest in names.items():
        if Path(name).name!=name or hashlib.sha256((source/name).read_bytes()).hexdigest()!=digest:raise ValueError('source drift')
    height_names={row['height'] for row in manifest['rows']}
    if len(height_names)!=1:raise ValueError('height field must be shared')
    name=height_names.pop()
    indices=np.asarray(Image.open(source/name))
    if indices.shape!=(2048,2048):raise ValueError('wrong logical extent')
    packed=pack5(indices)
    np.testing.assert_array_equal(unpack5(packed),indices)
    if len(np.unique(indices))!=manifest['unique_height_codes']:raise ValueError('palette count mismatch')
    output.mkdir(parents=True)
    Image.fromarray(packed).save(output/'height_indices5.png')
    np.testing.assert_array_equal(unpack5(np.asarray(Image.open(output/'height_indices5.png'))),indices)
    for name in names:
        if name not in {row['height'] for row in manifest['rows']}:shutil.copyfile(source/name,output/name)
    manifest['original_indices_sha256']=manifest['rows'][0]['height_sha256']
    manifest['height_encoding']='global_palette_r5_lsb'
    manifest['height_bits']=5
    manifest['height_row_bytes']=1280
    manifest['source_manifest_sha256']=hashlib.sha256((source/'manifest.json').read_bytes()).hexdigest()
    for row in manifest['rows']:
        row['height']='height_indices5.png'
        row['height_sha256']=hashlib.sha256((output/row['height']).read_bytes()).hexdigest()
        row['conservative_bytes']=(row['ao_data_bytes']+packed.nbytes+512)*3
    (output/'manifest.json').write_text(json.dumps(manifest,indent=2),encoding='utf8')
    print(json.dumps({'lossless_pixels':int(indices.size),'indices_bytes':packed.nbytes,'unique_codes':int(len(np.unique(indices))),'ao_unchanged':True,'highest_reservation':manifest['rows'][-1]['conservative_bytes']}))


if __name__=='__main__':build(*map(Path,sys.argv[1:]))
