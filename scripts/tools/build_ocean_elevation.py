"""按海洋母图 UV 重建 Terrarium 高程；默认只输出 tmp，依赖 numpy/Pillow。"""
import argparse, hashlib, json, math, pathlib, urllib.request
import numpy as np
from PIL import Image
ROOT = pathlib.Path(__file__).resolve().parents[2]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--output-dir", type=pathlib.Path, default=ROOT/"tmp/ocean-volume/elevation")
args = parser.parse_args()
OUT = args.output_dir.resolve()
OUT.mkdir(parents=True, exist_ok=True)
meta = json.loads((ROOT/'resources/maps/ocean_islands_bg_v2.json').read_text())
b = meta['bbox_ll']; z = 11; n = 2**z
def tx(lon): return (lon+180)/360*n
def ty(lat): return (1-math.asinh(math.tan(math.radians(lat)))/math.pi)/2*n
x0,x1=tx(b['lon_min']),tx(b['lon_max']); y0,y1=ty(b['lat_max']),ty(b['lat_min'])
tiles={}; records=[]
for y in range(math.floor(y0),math.floor(y1)+1):
    for x in range(math.floor(x0),math.floor(x1)+1):
        url=f'https://s3.amazonaws.com/elevation-tiles-prod/terrarium/{z}/{x}/{y}.png'
        path=OUT/f'dem-{z}-{x}-{y}.png'
        if not path.exists():
            with urllib.request.urlopen(url,timeout=25) as response: path.write_bytes(response.read())
        a=np.asarray(Image.open(path).convert('RGB'),dtype=np.float64)
        tiles[x,y]=a[:,:,0]*256+a[:,:,1]+a[:,:,2]/256-32768
        records.append({'url':url,'sha256':hashlib.sha256(path.read_bytes()).hexdigest()})
def sample(px,py):
    # 像素中心采样，只在已下载拼图的外边缘钳制。
    ix,iy=math.floor(px),math.floor(py); fx,fy=px-ix,py-iy
    def at(a,c):
        a=max(math.floor(x0)*256,min((math.floor(x1)+1)*256-1,a))
        c=max(math.floor(y0)*256,min((math.floor(y1)+1)*256-1,c))
        return tiles[a//256,c//256][c%256,a%256]
    return (at(ix,iy)*(1-fx)+at(ix+1,iy)*fx)*(1-fy)+(at(ix,iy+1)*(1-fx)+at(ix+1,iy+1)*fx)*fy
size=257
heights=[round(max(0,sample((x0+(x1-x0)*x/(size-1))*256-.5,(y0+(y1-y0)*y/(size-1))*256-.5)),3) for y in range(size) for x in range(size)]
data={'schema_version':1,'grid_size':size,'bbox_ll':b,'projection':'source Web Mercator UV to existing linear world rect','height_unit':'meters','sources':records,'attribution':'Mapzen Terrain Tiles; SRTM and other open data contributors. https://github.com/tilezen/joerd/blob/master/docs/attribution.md','metadata_sha256':hashlib.sha256((ROOT/'resources/maps/ocean_islands_bg_v2.json').read_bytes()).hexdigest(),'heights_m':heights}
(OUT/'ocean_volume_elevation.json').write_text(json.dumps(data,separators=(',',':')))
print(json.dumps({'tiles':len(records),'size':size,'min':min(heights),'max':max(heights),'bytes':(OUT/'ocean_volume_elevation.json').stat().st_size}))
