import json
import tempfile
import unittest
from pathlib import Path
import numpy as np
from PIL import Image
from tokyo_rebake_layer_fallback import build, sha, split_members


class RebakeTests(unittest.TestCase):
    def fixture(self, root, retained):
        data = np.zeros((4,3,10), dtype='<f4')
        for i in range(4):
            x = 4+i*8
            data[i,:,:3] = [[x,0,4],[x+4,0,4],[x,0,8]]
        data[:,:,7:10] = 1
        attr=root/'attrs.bin';attr.write_bytes(data.tobytes())
        plan=root/'plan.json'
        plan.write_text(json.dumps({'rows':[{'source':{'path':str(attr),'sha256':sha(attr),'faces':4}}]}))
        ids=root/'ids.u32';ids.write_bytes(np.array(retained,dtype='<u4').tobytes())
        original=root/'original.png';Image.new('RGBA',(1,1),(255,0,0,255)).save(original)
        batch=root/'batch.json'
        batch.write_text(json.dumps({'palette_sha256':sha(Path(__file__).resolve().parents[1]/'experiments/tokyo_palette.gd'),
            'step':1.,'max_scale':1.25,'rows':[{'key':'0:0:0','owner_bounds':[0,0,256,256],
            'texture_bounds':[-2,-2,258,258],'groups':[{'height':0,'status':'texture_candidate',
            'path':str(original),'sha256':sha(original),'source_faces':[[0,i] for i in range(4)]}]}]}))
        closure=root/'closure.json'
        closure.write_text(json.dumps({'all_jobs_present':True,'source':{'path':str(plan),'sha256':sha(plan)},
            'rows':[{'page':0,'path':str(ids),'sha256':sha(ids),'faces':len(retained)}],
            'rebake_jobs':['0:0:0'],'batches':[{'path':str(batch),'sha256':sha(batch)}]}))
        return closure

    def test_partial_rebake_excludes_retained_sources(self):
        with tempfile.TemporaryDirectory(dir=Path(__file__).resolve().parents[2]/'tmp') as folder:
            root=Path(folder);closure=self.fixture(root,[0]);out=root/'out'
            build(closure,sha(closure),out,0,1)
            report=json.loads((out/'manifest.json').read_text())
            groups=report['rows'][0]['groups']
            self.assertEqual(groups[0]['source_faces'],[[0,0]])
            self.assertEqual(groups[1]['source_faces'],[[0,1],[0,2],[0,3]])
            self.assertEqual(groups[1]['status'],'texture_candidate')
            self.assertFalse(report['source_removal_authorized'])
            self.assertEqual(report['new_fallback'],[])

    def test_all_retained_removes_old_texture_group(self):
        with tempfile.TemporaryDirectory(dir=Path(__file__).resolve().parents[2]/'tmp') as folder:
            root=Path(folder);closure=self.fixture(root,[0,1,2,3]);out=root/'out'
            build(closure,sha(closure),out,0,1)
            groups=json.loads((out/'manifest.json').read_text())['rows'][0]['groups']
            self.assertEqual(len(groups),1)
            self.assertEqual(groups[0]['status'],'native_global_fallback')
            self.assertEqual(list(out.glob('*.png')),[])

    def test_shared_members_split_by_physical_source(self):
        self.assertEqual(split_members([[0,2],[1,2]],[{2},set()]),([[1,2]],[[0,2]]))


if __name__=='__main__':unittest.main()
