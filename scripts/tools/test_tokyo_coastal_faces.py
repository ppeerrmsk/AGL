"""离线海岸拓扑反例；无需启动 Godot。"""
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "tmp/tokyo-r3-pydeps"))
from shapely.geometry import Point
from tokyo_coastal_faces import coastal_faces


class CoastalFacesTests(unittest.TestCase):
    def test_open_shore(self):
        land, sea, audit = coastal_faces((0, 0, 10, 10), [[(-1, 5), (11, 5)]])
        self.assertTrue(land.contains(Point(5, 2)))
        self.assertTrue(sea.contains(Point(5, 8)))
        self.assertEqual(audit["land_area_px2"], 50)
        self.assertEqual(audit["coverage_error_px2"], 0)

    def test_island_and_hole(self):
        coast = [[(2, 2), (2, 8), (8, 8), (8, 2), (2, 2)],
            [(4, 4), (6, 4), (6, 6), (4, 6), (4, 4)]]
        land, sea, audit = coastal_faces((0, 0, 10, 10), coast)
        self.assertEqual(land.area, 32)
        self.assertTrue(sea.contains(Point(5, 5)))
        self.assertEqual(audit["overlap_px2"], 0)

    def test_gap_and_reversed_segment_rejected(self):
        for coast in [[[(-1, 5), (4, 5)], [(6, 5), (11, 5)]],
                [[(-1, 5), (5, 5)], [(11, 5), (5, 5)]], []]:
            with self.subTest(coast=coast), self.assertRaises(ValueError):
                coastal_faces((0, 0, 10, 10), coast)


if __name__ == "__main__":
    unittest.main()
