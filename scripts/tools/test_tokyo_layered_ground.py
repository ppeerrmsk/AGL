"""纯离线合同：颜色、透明孔洞、分块同位采样和高程隔离。"""
import unittest
import numpy as np
from build_tokyo_layered_ground import layer_pixels
from pack_tokyo_layered_ground import crop_pixels, quad_vertices


class LayeredGroundTests(unittest.TestCase):
    def test_quad_ownership_height_uv_winding(self):
        row = dict(texture_bounds=[-1,-1,5,5], geometry_bounds=[0,0,4,4], height=.5)
        v = quad_vertices(row, [0,0,12,12], [4,4,16,16], np.array([32,32]), .5)
        self.assertEqual(len(v), 6)
        np.testing.assert_array_equal(v[:,1], np.full(6,.5))
        self.assertTrue(np.all(v[:,[0,2]] >= 0) and np.all(v[:,[0,2]] <= 4))
        self.assertGreater(np.cross(v[1,:3]-v[0,:3],v[2,:3]-v[0,:3])[1], 0)
        np.testing.assert_allclose(v[0,3:], [6/32,6/32])

    def test_quad_crop_never_expands_owner(self):
        row = dict(texture_bounds=[-1,-1,5,5], geometry_bounds=[0,0,4,4], height=0)
        v = quad_vertices(row, [4,4,10,10], [4,4,10,10], np.array([32,32]), .5)
        np.testing.assert_array_equal(v[:,[0,2]].min(axis=0), [1,1])
        np.testing.assert_array_equal(v[:,[0,2]].max(axis=0), [4,4])

    def test_crop_roundtrip(self):
        pixels = np.zeros((32, 32, 4), dtype=np.uint8)
        pixels[12:15, 14:18] = [10, 20, 30, 255]
        crop, (x0, y0, x1, y1) = crop_pixels(pixels)
        restored = np.zeros_like(pixels)
        restored[y0:y1, x0:x1] = crop
        np.testing.assert_array_equal(restored, pixels)
        self.assertLess(crop.size, pixels.size)

    def test_crop_keeps_edge_and_nonzero_transparent_rgb(self):
        pixels = np.zeros((16, 16, 4), dtype=np.uint8)
        pixels[0, 0] = [1, 0, 0, 0]
        pixels[-1, -1] = [1, 2, 3, 255]
        crop, rect = crop_pixels(pixels)
        self.assertEqual(rect, [0, 0, 16, 16])
        np.testing.assert_array_equal(crop, pixels)

    def test_empty_crop_rejected(self):
        with self.assertRaises(ValueError):
            crop_pixels(np.zeros((8, 8, 4), dtype=np.uint8))

    def triangle(self, height=0., color=(.2, .4, .6, 1)):
        data = np.zeros((1, 3, 10), dtype=np.float32)
        data[0, :, :3] = [[0, height, 0], [4, height, 0], [0, height, 4]]
        data[:, :, 4] = 1
        data[:, :, 6:10] = color
        return data

    def test_holes_and_color(self):
        pixels = layer_pixels(self.triangle(), [0, 0, 4, 4], 8)
        np.testing.assert_array_equal(pixels[0, 0], [51, 102, 153, 255])
        self.assertEqual(int(pixels[-1, -1, 3]), 0)

    def test_shared_sampling(self):
        data = self.triangle()
        whole = layer_pixels(data, [0, 0, 4, 4], 8)
        tile = layer_pixels(data, [0, 0, 2, 2], 4)
        np.testing.assert_array_equal(whole[:4, :4], tile)

    def test_height_not_flattened_into_color(self):
        np.testing.assert_array_equal(layer_pixels(self.triangle(), [0, 0, 4, 4], 8),
                                      layer_pixels(self.triangle(.5), [0, 0, 4, 4], 8))

    def test_color_conflict_rejected(self):
        with self.assertRaises(ValueError):
            layer_pixels(np.concatenate([self.triangle(), self.triangle(color=(1, 0, 0, 1))]),
                         [0, 0, 4, 4], 8)


if __name__ == '__main__':
    unittest.main()
