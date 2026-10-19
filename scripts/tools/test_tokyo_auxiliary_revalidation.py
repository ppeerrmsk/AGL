import copy
import unittest
import tempfile
from pathlib import Path
from revalidate_tokyo_auxiliary import BASE_SHA, DERIVED_SHA, RAIL_SHA, same_ao_source, digest, fixed_source_matches


class RevalidationTests(unittest.TestCase):
    def test_fixed_source_requires_full_identity_and_live_bytes(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            payload, native = root/'parent_00.bin', root/'source.res'
            payload.write_bytes(bytes(120))
            native.write_bytes(b'native')
            row = dict(parent=0, file=payload.name, source=str(native), triangles=1,
                       sha256=digest(payload), source_sha256=digest(native))
            data = dict(catalog_sha256=DERIVED_SHA, collision_sha256='collision',
                        parent=0, source=copy.deepcopy(row), original_fixed_faces=1)
            check = lambda d, r: fixed_source_matches(d, r, root, 'collision', DERIVED_SHA)
            self.assertTrue(check(data, row))
            for key, value in [('catalog_sha256',RAIL_SHA), ('collision_sha256','wrong'),
                               ('parent',1), ('original_fixed_faces',2)]:
                bad = copy.deepcopy(data)
                bad[key] = value
                self.assertFalse(check(bad, row), key)
            for key, value in [('parent',1), ('triangles',2), ('sha256','wrong'),
                               ('source_sha256','wrong'), ('file','../parent_00.bin')]:
                bad = copy.deepcopy(row)
                bad[key] = value
                self.assertFalse(check(data, bad), key)
                matched = copy.deepcopy(data)
                matched['source'] = bad
                matched['parent'] = bad['parent']
                matched['original_fixed_faces'] = bad['triangles']
                if key != 'parent':
                    self.assertFalse(check(matched, bad), 'mutated pair: '+key)
            payload.write_bytes(bytes(119)+b'x')
            self.assertFalse(check(data, row))
            payload.write_bytes(bytes(120))
            native.write_bytes(b'changed')
            self.assertFalse(check(data, row))

    def test_rail_pair_is_explicit_and_directed(self):
        before = dict(schema=1, bounds=[0,0,10,10], radius=8, collision_sha256='same', configuration='lod5_full',
                      catalog_sha256=DERIVED_SHA, triangles=[dict(parent=11,kind=2,points=[[0,3,0],[1,3,0],[0,3,1]])])
        after = copy.deepcopy(before)
        after['catalog_sha256'] = RAIL_SHA
        self.assertTrue(same_ao_source(before, after, rail=True))
        self.assertFalse(same_ao_source(before, after))
        for key, value in [('bounds',[1,0,10,10]), ('radius',9), ('catalog_sha256',BASE_SHA)]:
            bad = copy.deepcopy(after)
            bad[key] = value
            self.assertFalse(same_ao_source(before, bad, rail=True))
        after['triangles'][0]['points'].reverse()
        self.assertFalse(same_ao_source(before, after, rail=True))

    def test_native_window_identity_and_multiplicity(self):
        original = dict(schema=1, bounds=[0,0,10,10], radius=8, collision_sha256='same', configuration='lod5_full',
                        catalog_sha256=BASE_SHA, triangles=[dict(parent=11,kind=0,points=[[0,3,0],[1,3,0],[0,3,1]])])
        changed = copy.deepcopy(original)
        changed['catalog_sha256'] = DERIVED_SHA
        self.assertTrue(same_ao_source(original, changed))
        changed['triangles'][0]['points'] = [[1,3,0],[0,3,1],[0,3,0]]
        self.assertTrue(same_ao_source(original, changed))
        for key, value in [('radius',9),('bounds',[0,0,9,9]),('configuration','lod2_full'),('collision_sha256','wrong'),('catalog_sha256',BASE_SHA),('triangles',[])]:
            bad = copy.deepcopy(changed)
            bad[key] = value
            self.assertFalse(same_ao_source(original, bad))
        for mutation in ('height','reverse','duplicate','parent','kind'):
            bad = copy.deepcopy(changed)
            row = bad['triangles'][0]
            if mutation == 'height': row['points'][0][1] += .01
            if mutation == 'reverse': row['points'].reverse()
            if mutation == 'duplicate': bad['triangles'].append(copy.deepcopy(row))
            if mutation in ('parent','kind'): row[mutation] += 1
            self.assertFalse(same_ao_source(original, bad))


if __name__ == '__main__':
    unittest.main()
