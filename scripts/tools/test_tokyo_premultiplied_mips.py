import unittest
from PIL import Image
from tokyo_premultiplied_mips import halve


class PremultipliedMipTests(unittest.TestCase):
    def test_sparse_color_is_not_premultiplied_twice(self):
        image = Image.new('RGBA', (2, 2))
        image.putpixel((0, 0), (128, 64, 32, 255))
        self.assertEqual(halve(image).getpixel((0, 0)), (32, 16, 8, 64))
        self.assertNotEqual(image.resize((1, 1), Image.Resampling.BOX).getpixel((0, 0)), (32, 16, 8, 64))

    def test_constant_and_final_mip(self):
        for size in [(4, 4), (3, 5), (1, 1)]:
            image = Image.new('RGBA', size, (32, 16, 8, 64))
            result = halve(image)
            self.assertEqual(result.getpixel((0, 0)), (32, 16, 8, 64))

    def test_reject_straight_rgb(self):
        with self.assertRaises(ValueError):
            halve(Image.new('RGB', (2, 2)))


if __name__ == '__main__':
    unittest.main()
