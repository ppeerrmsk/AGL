import unittest
import numpy as np
from tokyo_full_layer_plan import eligible, tile_sources


class FullLayerPlanTests(unittest.TestCase):
    def test_exact_planar_only(self):
        data = np.zeros((5, 3, 10), dtype=np.float32)
        data[:, :, :3] = [[0, 2, 0], [1, 2, 0], [0, 2, 1]]
        data[:, :, 6:] = 1
        data[1, 2, 1] += .001
        data[2, 1, 6] = .9
        data[3, :, 9] = .5
        data[4] = data[4, ::-1]
        np.testing.assert_array_equal(eligible(data), [True, False, False, False, False])

    def test_shared_edge_collects_both_sides(self):
        cells = tile_sources(np.array([[255., 10.]]), np.array([[257., 12.]]))
        self.assertIn((0, 0), cells)
        self.assertIn((1, 0), cells)
        self.assertEqual(len(cells), 2)

    def test_empty(self):
        self.assertEqual(tile_sources(np.empty((0,2)), np.empty((0,2))), [])


if __name__ == '__main__':
    unittest.main()
