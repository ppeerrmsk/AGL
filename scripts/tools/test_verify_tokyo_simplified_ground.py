"""生成后地表审核的通过与拒绝反例。"""
import unittest
import numpy as np
from verify_tokyo_simplified_ground import verify


class GeneratedGroundTests(unittest.TestCase):
    def source(self):
        data = np.zeros((3,3,10),dtype=np.float32)
        for index,(height,color) in enumerate([(.22,[156,157,141]),(.38,[110,119,114]),(0,[80,80,80])]):
            data[index,:,0] = [index*3,index*3+1,index*3]
            data[index,:,2] = [0,0,1]
            data[index,:,1] = height
            data[index,:,4] = 1
            data[index,:,6:9] = np.asarray(color,dtype=np.float32)/255
            data[index,:,9] = 1
        return data

    def test_unchanged(self):
        data = self.source()
        self.assertEqual(verify(data,data.copy())['unchanged_other_faces'],1)

    def test_non_target_change_rejected(self):
        data = self.source(); changed = data.copy(); changed[2,0,0] += .01
        with self.assertRaisesRegex(ValueError,'non-target'): verify(data,changed)

    def test_target_outside_bound_rejected(self):
        data = self.source(); changed = data.copy(); changed[0,:,0] += .4
        with self.assertRaisesRegex(ValueError,'world-space'): verify(data,changed)

    def test_target_small_change(self):
        data = self.source(); changed = data.copy(); changed[0,:,0] += .05
        self.assertFalse(verify(data,changed)['visual_verified'])


if __name__ == '__main__': unittest.main()
