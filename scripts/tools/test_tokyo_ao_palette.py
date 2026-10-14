"""索引压缩的边界、哨兵、顺序与拒绝门。"""
import unittest
import numpy as np
from pack_tokyo_ao_height import pack


class PaletteTests(unittest.TestCase):
    def test_full_palette(self):
        values = (np.arange(256, dtype=np.uint16)*257).reshape(16, 16)
        indices, palette = pack(values)
        np.testing.assert_array_equal(palette[indices], values)

    def test_reject_overflow(self):
        with self.assertRaises(ValueError):
            pack(np.arange(257, dtype=np.uint16).reshape(1, -1))

    def test_sentinel_and_determinism(self):
        values = np.array([[65535, 256, 0], [256, 12345, 65535]], dtype=np.uint16)
        a, p = pack(values)
        b, q = pack(values[:, ::-1])
        np.testing.assert_array_equal(p, q)
        np.testing.assert_array_equal(a, b[:, ::-1])
        np.testing.assert_array_equal(p[a], values)

    def test_bad_input(self):
        for value in [np.zeros((2, 2)), np.zeros(4, dtype=np.uint16)]:
            with self.assertRaises(ValueError):
                pack(value)


if __name__ == '__main__':
    unittest.main()
