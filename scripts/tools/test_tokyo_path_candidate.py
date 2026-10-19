"""路径候选来源门与已记录连接点保护；不是隐式拓扑证明。"""
import json
from pathlib import Path
import tempfile
import unittest
from build_tokyo_path_candidate import build, digest


class PathCandidateTests(unittest.TestCase):
    def test_source_junction_and_surface(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory)
            source=root/'ground.json'
            data=dict(surfaces=[{'unchanged':True}], paths=[
                dict(id='a',points=[[0,0],[1,.05],[2,0],[3,.05],[4,0]]),
                dict(id='b',points=[[2,0],[2,2]])])
            source.write_text(json.dumps(data))
            city=root/'city.json'
            city.write_text(json.dumps(dict(roads=[],rails=[])))
            registry=root/'registry.json'
            registry.write_text(json.dumps(dict(rows=[dict(tile='test',source=str(root),
                hashes=dict(ground=digest(source),city=digest(city)))])))
            build(source,registry,'test',root/'candidate')
            result=json.loads((root/'candidate/ground.json').read_bytes())
            self.assertEqual(result['paths'][0]['points'],[[0,0],[2,0],[4,0]])
            self.assertEqual(result['surfaces'],data['surfaces'])
            with self.assertRaises(ValueError):
                build(source,registry,'test',root/'candidate')
            source.write_text('{}')
            with self.assertRaises(ValueError):
                build(source,registry,'test',root/'drift')


if __name__=='__main__':
    unittest.main()
