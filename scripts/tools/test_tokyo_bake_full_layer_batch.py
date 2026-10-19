import unittest
import numpy as np
from tokyo_bake_full_layer_batch import raster

class FullLayerBatchTests(unittest.TestCase):
    def triangle(self):
        data=np.zeros((1,3,10),dtype=np.float32)
        data[0,:,:3]=[[0,1,0],[4,1,0],[0,1,4]]
        data[:,:,6:]=1
        return data

    def test_cross_source_color_conflict(self):
        a=self.triangle();b=a.copy();b[:,:,6]=0
        with self.assertRaisesRegex(ValueError,'ambiguous same-height colors'):
            raster(np.concatenate([a,b]),np.array([0,0,4,4]),1.)

    def test_same_color_overlap_and_padding(self):
        a=self.triangle()
        result=raster(np.concatenate([a,a]),np.array([-2,-2,6,6]),1.)
        self.assertEqual(result.shape,(8,8,4))
        self.assertTrue(result[:,:,3].any())
        self.assertEqual(int(result[0,0,3]),0)

if __name__=='__main__':unittest.main()
