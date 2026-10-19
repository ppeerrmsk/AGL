import copy
import json
import tempfile
from pathlib import Path
import unittest
import numpy as np
from tokyo_advance_layer_closure import verify_replacement, build, sha
from tokyo_rebake_layer_fallback import build as rebake
import test_tokyo_rebake_layer_fallback as fixtures


class AdvanceTests(unittest.TestCase):
    def row(self):
        return {'key':'0:0:0','owner_bounds':[0,0,256,256], 'texture_bounds':[-2,-2,258,258],
                'groups':[{'height':12.,'source_faces':[[0,1],[0,2]],'status':'texture_candidate'}]}

    def test_split_preserves_source_partition(self):
        before=self.row();after=copy.deepcopy(before)
        after['groups']=[{'height':12.,'source_faces':[[0,1]],'status':'native_global_fallback'},
                         {'height':12.,'source_faces':[[0,2]],'status':'texture_candidate'}]
        verify_replacement(before,after)

    def test_rejects_missing_duplicate_height_and_bounds(self):
        before=self.row()
        variants=[]
        after=copy.deepcopy(before);after['groups'][0]['source_faces'].pop();variants.append(after)
        after=copy.deepcopy(before);after['groups'][0]['source_faces'].append([0,1]);variants.append(after)
        after=copy.deepcopy(before);after['groups'][0]['height']=0.;variants.append(after)
        after=copy.deepcopy(before);after['owner_bounds'][0]=1.;variants.append(after)
        for after in variants:
            with self.assertRaises(ValueError):verify_replacement(before,after)

    def test_rejects_retained_face_in_texture(self):
        before=self.row()
        with self.assertRaisesRegex(ValueError,'retained source still rasterized'):
            verify_replacement(before,copy.deepcopy(before),[{1}])
        before['groups'][0]['status']='native_color_conflict'
        after=copy.deepcopy(before);after['groups'][0]['status']='texture_candidate'
        with self.assertRaisesRegex(ValueError,'retained source still rasterized'):
            verify_replacement(before,after)

    def test_complete_rebake_advances_without_authorizing_runtime(self):
        with tempfile.TemporaryDirectory(dir=Path(__file__).resolve().parents[2]/'tmp') as folder:
            root=Path(folder);source=fixtures.RebakeTests().fixture(root,[0])
            plan_path=root/'plan.json';plan=json.loads(plan_path.read_text())
            ids=root/'eligible.u32';ids.write_bytes(np.arange(4,dtype='<u4').tobytes())
            plan['rows'][0].update(planar_ids=str(ids),ids_sha256=sha(ids),planar_faces=4)
            plan['jobs']={'0:0:0':[0]};plan_path.write_text(json.dumps(plan))
            closure=json.loads(source.read_text());closure['source']['sha256']=sha(plan_path)
            batch_path=root/'batch.json';batch=json.loads(batch_path.read_text())
            batch.update(source=closure['source'],first=0,count=1)
            batch_path.write_text(json.dumps(batch));closure['batches'][0]['sha256']=sha(batch_path)
            source.write_text(json.dumps(closure))
            rebake(source,sha(source),root/'tokyo-installed-rebake-0',0,1)
            build(source,sha(source),root,root/'next')
            result=json.loads((root/'next/closure/manifest.json').read_text())
            self.assertTrue(result['all_jobs_present'])
            self.assertEqual(result['fallback_faces'],1)
            self.assertEqual(result['rebake_jobs'],[])
            self.assertFalse(result['source_removal_authorized'])

    def test_incomplete_rebakes_never_create_successor(self):
        with tempfile.TemporaryDirectory(dir=Path(__file__).resolve().parents[2]/'tmp') as folder:
            root=Path(folder);source=fixtures.RebakeTests().fixture(root,[0])
            with self.assertRaisesRegex(ValueError,'incomplete rebakes: 0/1'):
                build(source,sha(source),root,root/'next')
            self.assertFalse((root/'next').exists())


if __name__=='__main__':unittest.main()
