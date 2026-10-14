"""按实际引擎mip无损打包混合R8/RG8图集；显式解码后过滤，不启用图集mip。"""
import argparse
import json
from pathlib import Path
import numpy as np
from tokyo_full_layer_plan import sha


def pack_rectangles(items, limit):
    pages=[];packed=[]
    for item in sorted(items,key=lambda i:(-i['h'],-i['w'],i['tile'],i['level'])):
        w,h=item['w'],item['h']
        if min(w,h)<=0 or max(w,h)>limit:raise ValueError('invalid rectangle')
        fits=[]
        for pi,page in enumerate(pages):
            for si,shelf in enumerate(page['shelves']):
                if shelf['height']>=h and shelf['x']+w<=limit:
                    fits.append((shelf['height']-h,limit-shelf['x']-w,pi,si))
        if fits:
            _,_,pi,si=min(fits);page=pages[pi];shelf=page['shelves'][si]
        else:
            pi=next((i for i,p in enumerate(pages) if p['height']+h<=limit),len(pages))
            if pi==len(pages):pages.append({'width':0,'height':0,'shelves':[]})
            page=pages[pi];shelf={'x':0,'y':page['height'],'height':h}
            page['shelves'].append(shelf);page['height']+=h
        packed.append(dict(item,page=pi,x=shelf['x'],y=shelf['y']))
        shelf['x']+=w;page['width']=max(page['width'],shelf['x'])
    return pages,packed


def save_array(path, array, format_name):
    raw=array.tobytes();path.write_bytes(raw)
    if path.read_bytes()!=raw:raise ValueError('saved array differs')
    return {'path':str(path.resolve()),'sha256':sha(path),'width':array.shape[1],'height':array.shape[0],
            'format':format_name,'three_copy_bytes':len(raw)*3}


def build(source, expected, output, limit=4096):
    source,output=Path(source),Path(output)
    if sha(source)!=expected or output.exists():raise ValueError('input drift or existing output')
    manifest=json.loads(source.read_text(encoding='utf-8'))
    cache=[];palettes=[];offsets=[];color_count=0;items={1:[],2:[]}
    for index,row in enumerate(manifest['rows']):
        if row['tile']!=index or sha(row['path'])!=row['sha256']:raise ValueError('mip identity drift')
        pixels=np.fromfile(row['path'],dtype='<u4')
        palette,indices=np.unique(pixels,return_inverse=True)
        if len(palette)>65536:raise ValueError('palette exceeds lossless index capacity')
        stride=1 if len(palette)<=256 else 2
        offsets.append(color_count);color_count+=len(palette);palettes.append(palette)
        cache.append(indices.astype('u1' if stride==1 else '<u2'))
        for level in row['levels']:
            if level['offset']%4:raise ValueError('unaligned rgba mip')
            items[stride].append({'tile':index,'level':level['level'],'w':level['width'],'h':level['height'],
                                  'offset':level['offset']//4})
    if color_count>=2**24:raise ValueError('palette offset exceeds exact float range')
    output.mkdir(parents=True)
    pages=[];rectangles=[]
    for stride in (1,2):
        layouts,packed=pack_rectangles(items[stride],limit)
        arrays=[np.zeros((p['height'],p['width']),dtype='u1' if stride==1 else '<u2') for p in layouts]
        base=len(pages)
        for rect in packed:
            start=rect['offset'];end=start+rect['w']*rect['h']
            arrays[rect['page']][rect['y']:rect['y']+rect['h'],rect['x']:rect['x']+rect['w']]=cache[rect['tile']][start:end].reshape(rect['h'],rect['w'])
            rectangles.append(dict(rect,page=base+rect['page'],stride=stride))
        for array in arrays:
            pages.append(save_array(output/f'page_{len(pages):02d}.bin',array,'R8' if stride==1 else 'RG8'))
    color_width=1024;color_height=(color_count+color_width-1)//color_width
    colors=np.zeros((color_height,color_width),dtype='<u4');colors.flat[:color_count]=np.concatenate(palettes)
    color_binding=save_array(output/'colors.rgba8',colors,'RGBA8')
    offset_binding=save_array(output/'offsets.rf',np.asarray(offsets,dtype='<f4')[None,:],'RF')
    max_levels=max(len(row['levels']) for row in manifest['rows'])
    metadata=np.zeros((len(cache),max_levels*2,4),dtype='<f4')
    for rect in rectangles:
        tile,level=rect['tile'],rect['level']
        metadata[tile,level*2]=[rect['x'],rect['y'],rect['w'],rect['h']]
        metadata[tile,level*2+1]=[rect['page'],len(manifest['rows'][tile]['levels']),
                                       manifest['rows'][tile]['levels'][0]['width'],manifest['rows'][tile]['levels'][0]['height']]
    meta_binding=save_array(output/'metadata.rgbaf',metadata,'RGBAF')
    stored=[np.memmap(p['path'],mode='r',dtype='u1' if p['format']=='R8' else '<u2',shape=(p['height'],p['width'])) for p in pages]
    stored_colors=np.fromfile(color_binding['path'],dtype='<u4')
    stored_offsets=np.fromfile(offset_binding['path'],dtype='<f4').astype(np.uint32)
    for rect in rectangles:
        tile=rect['tile'];start=rect['offset'];end=start+rect['w']*rect['h']
        pixels=np.memmap(manifest['rows'][tile]['path'],mode='r',dtype='<u4')
        ids=stored[rect['page']][rect['y']:rect['y']+rect['h'],rect['x']:rect['x']+rect['w']].reshape(-1).astype(np.uint32)
        if not np.array_equal(stored_colors[stored_offsets[tile]+ids],pixels[start:end]):
            raise ValueError('saved mip reconstruction differs')
    report={'mip_export':{'path':str(source.resolve()),'sha256':expected},'source_sha256':manifest['source_sha256'],
        'pages':pages,'colors':color_binding,'offsets':offset_binding,'metadata':meta_binding,
        'rectangles':rectangles,'all_mip_pixels_exact':True,'atlas_hardware_mipmaps':False,
        'three_copy_bytes':sum(p['three_copy_bytes'] for p in pages+[color_binding,offset_binding,meta_binding]),
        'gpu_sampling_verified':False,'runtime_integrated':False}
    (output/'manifest.json').write_text(json.dumps(report,separators=(',',':')),encoding='utf-8')
    print(json.dumps({'pages':len(pages),'formats':[p['format'] for p in pages],
                      'three_copy_bytes':report['three_copy_bytes'],'all_mip_pixels_exact':True}))


if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('source');p.add_argument('sha');p.add_argument('output')
    p.add_argument('--limit',type=int,default=4096)
    a=p.parse_args();build(a.source,a.sha,a.output,a.limit)
