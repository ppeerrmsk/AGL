import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "tmp/tokyo-r3-pydeps"))
from shapely.geometry import Polygon, box
from tokyo_tagged_roofs import tagged_roof


class TaggedRoofTests(unittest.TestCase):
    def test_shapes_keep_total_height(self):
        for shape in ["gabled", "hipped", "pyramidal"]:
            roof = tagged_roof(box(0, 0, 20, 8), 20, 8, shape)
            self.assertEqual(roof["eave_px"], 6)
            self.assertAlmostEqual(max(v[1] for v in roof["roof"]), 10)
            self.assertLess(roof["area_error"], 1e-6)
            self.assertLess(roof["boundary_error"], 1e-6)

    def test_courtyard_concavity_and_source_bottom(self):
        for poly in [Polygon([(0, 0), (20, 0), (20, 8), (10, 8), (10, 6), (0, 6)]),
                Polygon([(0, 0), (20, 0), (20, 8), (0, 8)], [[(4, 2), (8, 2), (8, 6), (4, 6)]])]:
            roof = tagged_roof(poly, 20, 8, "gabled", min_height_m=4)
            self.assertEqual(min(v[1] for v in roof["walls"]), 2)
            self.assertLess(roof["area_error"], 1e-6)
            self.assertLess(roof["overlap"], 1e-6)

    def test_rotated_warehouse(self):
        poly = Polygon([(-5291.508, -674.652), (-5288.791, -663.813),
            (-5252.215, -672.982), (-5254.932, -683.821)])
        roof = tagged_roof(poly, 20, 8, "gabled")
        self.assertAlmostEqual(max(v[1] for v in roof["roof"]), 10)
        self.assertLess(roof["area_error"], 1e-5)
        self.assertLess(roof["boundary_error"], 1e-5)

    def test_across_and_rejection(self):
        roof = tagged_roof(box(0, 0, 20, 8), 20, 8, "gabled", "across")
        peaks = [v for v in roof["roof"] if abs(v[1]-10) < 1e-5]
        self.assertTrue(all(abs(v[0]-10) < 1e-5 for v in peaks))
        for shape, rise in [("dome", 8), ("gabled", 0), ("gabled", 20)]:
            with self.assertRaises(ValueError):
                tagged_roof(box(0, 0, 20, 8), 20, rise, shape)


if __name__ == "__main__":
    unittest.main()
