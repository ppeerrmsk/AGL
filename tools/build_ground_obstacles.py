"""从东京正式近景制作源的楼体三角形生成保守占地位图，不读取截图。"""
import argparse, hashlib, json, struct, zlib
from pathlib import Path
from PIL import Image, ImageDraw
ORIGIN=(-16500,-16500)
STEP=2
WIDTH=16504

def build(root, output):
    manifests=sorted(root.glob('r345-detail_*-layers-a/manifest.json'))
    if len(manifests)!=256: raise ValueError('需要完整256片近景楼体来源')
    mask=Image.new('1',(WIDTH,WIDTH))
    draw=ImageDraw.Draw(mask)
    sources=[]
    triangles=0
    for index,path in enumerate(manifests):
        meta=json.loads(path.read_text(encoding='utf8'))
        assert meta['configuration']=='lod5_full'
        for layer in meta['layers'][:2]:
            data=(path.parent/layer['file']).read_bytes()
            digest=hashlib.sha256(data).hexdigest()
            assert digest==layer['sha256']
            sources.append({'path':path.parent.name+'/'+layer['file'],'sha256':digest})
            for a,b,c,d,e,f,g,h,i in struct.iter_unpack('<9f',data):
                if abs((d-a)*(i-c)-(f-c)*(g-a))<1e-8: continue
                draw.polygon([((a-ORIGIN[0])/STEP,(c-ORIGIN[1])/STEP),((d-ORIGIN[0])/STEP,(f-ORIGIN[1])/STEP),((g-ORIGIN[0])/STEP,(i-ORIGIN[1])/STEP)],fill=1)
                triangles+=1
        if index%32==0: print(f'ground obstacles {index+1}/256',flush=True)
    game=Path('resources/maps/yokohama_buildings.json')
    for row in json.loads(game.read_text(encoding='utf8'))['districts']:
        draw.polygon([((x-ORIGIN[0])/STEP,(y-ORIGIN[1])/STEP) for x,y in row['footprint']],fill=1)
    output.parent.mkdir(parents=True,exist_ok=True)
    raw=mask.tobytes()
    output.write_bytes(zlib.compress(raw,9))
    report={'schema':1,'origin':ORIGIN,'step':STEP,'width':WIDTH,'raw_bytes':len(raw),'sha256':hashlib.sha256(output.read_bytes()).hexdigest(),'triangles':triangles,'sources':sources,'game_sha256':hashlib.sha256(game.read_bytes()).hexdigest()}
    output.with_suffix('.json').write_text(json.dumps(report,indent=2),encoding='utf8')
    print({k:v for k,v in report.items() if k!='sources'},flush=True)

if __name__=='__main__':
    parser=argparse.ArgumentParser()
    parser.add_argument('--root',type=Path,default=Path('tmp/tokyo-bay-volume'))
    parser.add_argument('--output',type=Path,default=Path('resources/maps/tokyo_ground_obstacles.bin'))
    args=parser.parse_args()
    build(args.root,args.output)
