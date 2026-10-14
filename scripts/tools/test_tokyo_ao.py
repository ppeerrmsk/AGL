import unittest
import numpy as np
from build_tokyo_ao import height_field, horizon_ao, encode_height, source_identity
from unittest.mock import patch
import hashlib
from audit_tokyo_ao_preload import screen_mask, shoreline_bytes, fixed_atlas_bytes


class AOTests(unittest.TestCase):
    def test_fixed_collection_reservation(self):
        from copy import deepcopy
        charges = {'11':1668112, '0':190912, '1':276784, '3':304000, '12':983632, '13':594928}
        rows = {key:dict(parent=int(key), ready=True, reserved_bytes=amount,
            warm=dict(state='ready', reserved_bytes=0, peak_reserved_bytes=524288)) for key, amount in charges.items()}
        state = dict(fixed_atlas_required=True, fixed_atlas=dict(ready=True, reserved_bytes=4018368, regions=rows))
        self.assertEqual(fixed_atlas_bytes(state), 4018368)
        fine = deepcopy(state)
        fine['fixed_atlas']['regions']['11'].update(texture_step=1, reserved_bytes=6619840,
            catalog_sha256='c0311651371c29025b8db0a8618adb57a2faeb39ab59c4751ee743b3d9c346ca')
        fine['fixed_atlas']['reserved_bytes'] = 8970096
        self.assertEqual(fixed_atlas_bytes(fine), 8970096)
        for field, value in [('catalog_sha256','wrong'), ('texture_step',2), ('reserved_bytes',1668112)]:
            bad = deepcopy(fine)
            bad['fixed_atlas']['regions']['11'][field] = value
            with self.assertRaises(ValueError): fixed_atlas_bytes(bad)
        for key in charges:
            bad = deepcopy(state)
            del bad['fixed_atlas']['regions'][key]
            with self.assertRaises(ValueError): fixed_atlas_bytes(bad)
            bad = deepcopy(state)
            bad['fixed_atlas']['regions'][key]['reserved_bytes'] -= 1
            with self.assertRaises(ValueError): fixed_atlas_bytes(bad)
            bad = deepcopy(state)
            bad['fixed_atlas']['regions'][key]['warm']['reserved_bytes'] = 524288
            with self.assertRaises(ValueError): fixed_atlas_bytes(bad)

    def test_joint_fixed_atlas_reservation(self):
        self.assertEqual(fixed_atlas_bytes({}), 0)
        row = dict(ready=True, reserved_bytes=1668112, warm=dict(state='ready', reserved_bytes=0, peak_reserved_bytes=524288))
        self.assertEqual(fixed_atlas_bytes(dict(fixed_atlas_required=True, fixed_atlas=row)), 1668112)
        for mutation in [dict(ready=False), dict(reserved_bytes=1668111), dict(warm={}), dict(warm=dict(row['warm'], reserved_bytes=524288))]:
            with self.assertRaises(ValueError):
                fixed_atlas_bytes(dict(fixed_atlas_required=True, fixed_atlas=dict(row, **mutation)))

    def test_independent_source_does_not_claim_catalog(self):
        digest=hashlib.sha256(b'fixture').hexdigest()
        data=dict(schema=1,configuration='independent_cells_lod5',sources=[{}]*32,index_path='fixture.res',index_sha256=digest)
        with patch('build_tokyo_ao.Path.read_bytes',return_value=b'fixture'):
            self.assertEqual(source_identity(data,True),dict(index_sha256=digest,source_kind='independent_cells_lod5'))
            for bad in [dict(data,index_sha256='drift'),dict(data,sources=[{}]*16),dict(data,collision_sha256='fake'),dict(data,catalog_sha256='fake')]:
                with self.assertRaises(ValueError):source_identity(bad,True)
        with self.assertRaises(ValueError):source_identity(data)

    def test_joint_shoreline_reservation(self):
        self.assertEqual(shoreline_bytes({}),0)
        state={'shoreline_required':True,'shoreline':{'ready':True,'resident_faces':8225,'reserved_bytes':4737600}}
        self.assertEqual(shoreline_bytes(state),4737600)
        for mutation in [{'resident_faces':0},{'resident_faces':1.5},{'reserved_bytes':4737599},{'ready':False}]:
            with self.assertRaises(ValueError):shoreline_bytes(dict(state,shoreline=dict(state['shoreline'],**mutation)))

    def test_audit_offscreen_mask_never_wraps(self):
        for bounds in [[[-20,0,-8,10]],[[0,-20,10,-8]],[[30,0,40,10]],[[0,30,10,40]]]:
            self.assertFalse(screen_mask(bounds,(20,20)).any())
        expected=np.zeros((20,20),dtype=bool)
        expected[:7,:7]=True
        self.assertTrue(np.array_equal(screen_mask([[-8,-8,5,5]],(20,20)),expected))
        self.assertTrue(np.array_equal(screen_mask([[-30,0,-8,10],[-8,-8,5,5]],(20,20)),expected))

    def test_empty_and_flat_are_unoccluded(self):
        for height in [-256, 0, 20]:
            self.assertEqual(float(horizon_ao(np.full((32, 32), height, dtype=np.float32), .25).max()), 0)

    def test_wall_ground_contact_not_roof_stain(self):
        heights = np.zeros((64, 64), dtype=np.float32)
        heights[:, 32:] = 20
        ao = horizon_ao(heights, .5)
        self.assertGreater(ao[32, 31], .1)
        self.assertGreater(ao[32, 31], ao[32, 26])
        self.assertEqual(float(ao[32, 0]), 0)
        self.assertEqual(float(ao[32, 40]), 0)

    def test_roof_equipment_and_courtyard(self):
        h = np.full((64, 64), 12, dtype=np.float32)
        h[28:36, 28:36] = 15
        a = horizon_ao(h, .25)
        self.assertGreater(a[27, 32], .1)
        self.assertEqual(float(a[32, 32]), 0)
        h[28:36, 28:36] = 0
        self.assertGreater(horizon_ao(h, .25)[32, 32], .1)

    def test_rotation_and_missing_receivers(self):
        h = np.zeros((48, 48), dtype=np.float32)
        h[10:20, 11:33] = 8
        a = horizon_ao(h, .5)
        self.assertTrue(np.allclose(np.rot90(a), horizon_ao(np.rot90(h), .5), atol=1e-6))
        h[:8] = -256
        self.assertEqual(float(horizon_ao(h, .5)[:8].max()), 0)

    def test_raster_native_slope_order_and_hole(self):
        a = [[0, 0, 0], [4, 4, 0], [0, 0, 4]]
        b = [[0, 7, 0], [1, 7, 0], [0, 7, 1]]
        first = height_field([a, b], [0, 0, 4, 4], 16)
        self.assertTrue(np.array_equal(first, height_field([b, a], [0, 0, 4, 4], 16)))
        self.assertEqual(float(first[0, 0]), 7)
        self.assertEqual(float(first[15, 15]), -256)
        self.assertAlmostEqual(float(first[1, 8]), 2.125)

    def test_height_encoding_not_lossy_color(self):
        values = np.array([[-256., 0., .08, 12.345, 147.9]], dtype=np.float32)
        rgb = encode_height(values)
        decoded = (rgb[:, :, 0].astype(float)*256+rgb[:, :, 1])/256-1
        self.assertTrue(np.allclose(decoded[:, 1:], values[:, 1:], atol=1/512))
        self.assertEqual(int(rgb[0, 0, 0])*256+int(rgb[0, 0, 1]), 65535)


if __name__ == '__main__':
    unittest.main()
