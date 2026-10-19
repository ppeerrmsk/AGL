"""离线输入回归，不启动 Godot，也不读整张 PBF。"""
import unittest
from shapely.geometry import Polygon, MultiPolygon
from build_tokyo_volume_region import RegionCollector, above_ground, heights, measure, triangulate


class RegionTests(unittest.TestCase):
    def test_measure_and_fallback_provenance(self):
        self.assertEqual(measure("-12"), 0)
        self.assertEqual(measure("12-15 m"), 0)
        self.assertAlmostEqual(measure("10'6\""), 3.2004)
        self.assertEqual(measure("12 m"), 12)
        value, source, _, errors = heights({"height": "0", "building:levels": "8"}, 120, "urban")
        self.assertEqual((value, source), (25.6, "levels"))
        self.assertIn("invalid_height_tag", errors)
        self.assertEqual(heights({"height": "unknown"}, 120, "urban")[1], "fallback")
        self.assertIn("min_height_not_below_top", heights({"height": "8", "min_height": "9"}, 120, "urban")[3])

    def test_underground_indoor_exclusion(self):
        for tags in [{"tunnel": "building_passage"}, {"location": "underground"}, {"indoor": "yes"}]:
            self.assertFalse(above_ground(tags))
        self.assertTrue(above_ground({"bridge": "yes", "layer": "1"}))
        self.assertTrue(above_ground({"layer": "-1"}))
        self.assertTrue(above_ground({"tunnel": "no"}))

    def test_courtyard_and_disconnected_roofs(self):
        outer = [(0, 0), (10, 0), (10, 10), (0, 10)]
        hole = [(2, 2), (8, 2), (8, 8), (2, 8)]
        courtyard = Polygon(outer, [hole])
        other = Polygon([(20, 0), (22, 0), (22, 2), (20, 2)])
        data = triangulate(MultiPolygon([courtyard, other]))
        triangles = [Polygon(data[index:index + 3]) for index in range(0, len(data), 3)]
        self.assertAlmostEqual(sum(tri.area for tri in triangles), 68)
        self.assertTrue(all(tri.intersection(Polygon(hole)).area == 0 for tri in triangles))

    def test_member_dedup_keeps_tagged_height_and_courtyard(self):
        collector = RegionCollector((-1, -1, 11, 11))
        outer = [(0, 0), (10, 0), (10, 10), (0, 10)]
        collector.buildings = {
            "r1": {"id": "r1", "geometry": Polygon(outer, [[(2, 2), (8, 2), (8, 8), (2, 8)]]), "height_m": 12, "height_source": "fallback", "is_part": False, "aliases": []},
            "w2": {"id": "w2", "geometry": Polygon(outer), "height_m": 80, "height_source": "height", "is_part": False},
        }
        collector.relations = {"r1": [{"id": "w2", "role": "outer"}]}
        collector.resolve_relations()
        self.assertNotIn("w2", collector.buildings)
        self.assertEqual(collector.buildings["r1"]["height_m"], 80)
        self.assertEqual(collector.buildings["r1"]["geometry"].area, 64)
        self.assertEqual(collector.buildings["r1"]["aliases"], ["w2"])

    def test_parts_replace_only_covered_outline(self):
        for width in [10, 8]:
            collector = RegionCollector((-1, -1, 11, 11))
            collector.buildings = {
                "w1": {"id": "w1", "geometry": Polygon([(0, 0), (10, 0), (10, 10), (0, 10)]), "is_part": False, "parts": []},
                "w2": {"id": "w2", "geometry": Polygon([(0, 0), (width, 0), (width, 10), (0, 10)]), "is_part": True, "parents": []},
            }
            collector.resolve_parts()
            self.assertEqual(collector.buildings["w2"]["parents"], ["w1"])
            self.assertEqual(collector.buildings["w1"]["render_outline"], width != 10)
            self.assertFalse(bool(collector.buildings["w2"].get("defer_render")))
            if width != 10:
                residual = collector.buildings["w1"]["render_geometry"]
                self.assertEqual(residual.area, 20)
                self.assertEqual(residual.intersection(collector.buildings["w2"]["geometry"]).area, 0)

    def test_cache_scope_and_construction_provenance(self):
        collector = RegionCollector((0, 0, 10, 10))
        collector.consume_area("w1", {"building": "construction", "height": "35"}, Polygon([(0, 0), (10, 0), (10, 10), (0, 10)]), "")
        loaded = RegionCollector((0, 0, 10, 10))
        loaded.load_cache(collector.source_cache())
        self.assertEqual(loaded.buildings["w1"]["height_m"], 35)
        self.assertIn("construction_state_unverified", [issue["kind"] for issue in loaded.issues])
        with self.assertRaises(ValueError):
            RegionCollector((-1, 0, 10, 10)).load_cache(collector.source_cache())

    def test_cache_preserves_bbox_only_corner_source(self):
        source = RegionCollector((0, 0, 30, 30))
        corner = Polygon([(9, 20), (20, 9), (20, 20)])
        source.consume_area("w1", {"building": "yes", "height": "12"}, corner, "")
        source.consume_area("w2", {"building": "yes"}, Polygon([(20, 20), (25, 20), (25, 25), (20, 25)]), "")
        loaded = RegionCollector((0, 0, 10, 10))
        self.assertTrue(loaded.intersects(list(corner.exterior.coords)))
        self.assertFalse(corner.intersects(loaded.clip))
        loaded.load_cache(source.source_cache())
        self.assertEqual(set(loaded.buildings), {"w1"})
        self.assertEqual(loaded.buildings["w1"]["height_m"], 12)
        self.assertTrue(loaded.buildings["w1"]["geometry"].equals_exact(corner, 0))
        self.assertEqual(set(source.buildings), {"w1", "w2"})


if __name__ == "__main__":
    unittest.main()
