import unittest
import numpy as np
from restore_tokyo_hlod_palette import remap, compose


class PaletteTest(unittest.TestCase):
    def test_exact_only_and_no_mutation(self):
        colors = np.array([[[146/255, 151/255, 137/255, 1],
                            [146.2/255, 151/255, 137/255, 1],
                            [146/255, 151/255, 137/255, .5]]], dtype=np.float32)
        saved = colors.copy()
        output, counts = remap(colors, {'929789': 'a9ada7'})
        self.assertEqual(counts, {'929789': 1})
        np.testing.assert_array_equal(colors, saved)
        np.testing.assert_array_equal(output[:, 1:], saved[:, 1:])
        np.testing.assert_array_equal(output[..., 3], saved[..., 3])
        again, counts = remap(output, {'929789': 'a9ada7'})
        self.assertEqual(counts['929789'], 0)
        np.testing.assert_array_equal(output, again)

    def test_ao_after_color_and_alpha_preserved(self):
        colors = np.array([[[1., 1., 1., 1.], [1., 1., 1., 0.]]], dtype=np.float32)
        output = compose(colors, np.array([[255, 255]], dtype=np.uint8))
        np.testing.assert_array_equal(output, [[[199, 199, 199, 255], [0, 0, 0, 0]]])


if __name__ == '__main__':
    unittest.main()
