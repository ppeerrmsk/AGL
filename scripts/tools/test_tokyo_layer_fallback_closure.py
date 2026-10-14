import unittest
import json
import tempfile
from pathlib import Path
import numpy as np
from tokyo_layer_fallback_closure import mark_group, build, sha

class FallbackTests(unittest.TestCase):
    def test_incomplete_map_never_writes_removal_contract(self):
        with tempfile.TemporaryDirectory(dir=Path(__file__).resolve().parents[2]/'tmp') as temporary:
            root=Path(temporary)
            ids=root/'ids.u32';ids.write_bytes(np.array([0],dtype='<u4').tobytes())
            plan={'rows':[{'source':{'faces':1},'planar_ids':str(ids),'ids_sha256':sha(ids),'planar_faces':1}],
                  'jobs':{'0:0:0':[0]}}
            source=root/'plan.json';source.write_text(json.dumps(plan),encoding='utf-8')
            target=root/'closure'
            with self.assertRaisesRegex(ValueError,'incomplete full-map jobs: 0/1'):
                build(source,sha(source),root,target)
            self.assertFalse(target.exists())

    def test_unsafe_neighbor_retains_shared_source(self):
        eligible=[np.array([True,True,False])];seen=[np.zeros(3,bool)];fallback=[np.zeros(3,bool)]
        mark_group({'status':'texture_candidate','source_faces':[[0,0],[0,1]]},[0],eligible,seen,fallback)
        self.assertFalse(fallback[0].any())
        mark_group({'status':'native_color_conflict','source_faces':[[0,1]]},[0],eligible,seen,fallback)
        np.testing.assert_array_equal(fallback[0],[False,True,False])
        np.testing.assert_array_equal(seen[0],[True,True,False])

    def test_rejects_nonplanar_or_wrong_page(self):
        for member in [[0,1],[1,0]]:
            with self.assertRaises(ValueError):
                mark_group({'status':'texture_candidate','source_faces':[member]},[0],[np.array([True,False])],[np.zeros(2,bool)],[np.zeros(2,bool)])

if __name__=='__main__':unittest.main()
