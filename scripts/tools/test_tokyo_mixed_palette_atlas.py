import json
import tempfile
import unittest
from pathlib import Path
import numpy as np
from tokyo_mixed_palette_atlas import build, pack_rectangles, sha


class MixedAtlasTests(unittest.TestCase):
    def test_layout_in_bounds_and_disjoint(self):
        items=[{'tile':i,'level':0,'w':w,'h':h} for i,(w,h) in enumerate([(7,5),(4,4),(6,2),(1,1),(8,8)])]
        pages,rects=pack_rectangles(items,8)
        masks=[np.zeros((p['height'],p['width']),bool) for p in pages]
        for r in rects:
            part=masks[r['page']][r['y']:r['y']+r['h'],r['x']:r['x']+r['w']]
            self.assertEqual(part.shape,(r['h'],r['w']))
            self.assertFalse(part.any());part[:]=True
        with self.assertRaises(ValueError):pack_rectangles([{'tile':0,'level':0,'w':9,'h':1}],8)

    def test_saved_r8_and_rg8_exact_decode(self):
        with tempfile.TemporaryDirectory(dir=Path(__file__).resolve().parents[2]/'tmp') as folder:
            root=Path(folder);rows=[]
            for tile,(w,h) in enumerate([(4,4),(32,16)]):
                levels=[];count=0
                while True:
                    levels.append({'level':len(levels),'width':w,'height':h,'offset':count*4});count+=w*h
                    if w==h==1:break
                    w=max(1,w//2);h=max(1,h//2)
                pixels=np.zeros(count,dtype='<u4') if tile==0 else np.arange(count,dtype='<u4')
                path=root/f'{tile}.rgba';path.write_bytes(pixels.tobytes())
                rows.append({'tile':tile,'path':str(path),'sha256':sha(path),'levels':levels})
            source=root/'source.json';source.write_text(json.dumps({'source_sha256':'a'*64,'rows':rows}))
            build(source,sha(source),root/'out',64)
            result=json.loads((root/'out/manifest.json').read_text())
            self.assertEqual({p['format'] for p in result['pages']},{'R8','RG8'})
            self.assertTrue(result['all_mip_pixels_exact'])
            self.assertFalse(result['gpu_sampling_verified'])
            bindings=result['pages']+[result[k] for k in ('colors','offsets','metadata')]
            self.assertEqual(result['three_copy_bytes'],sum(Path(p['path']).stat().st_size*3 for p in bindings))


if __name__=='__main__':unittest.main()
