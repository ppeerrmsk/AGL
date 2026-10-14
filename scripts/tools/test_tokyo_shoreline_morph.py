"""岸线共拓扑候选反例；只证明离线几何，不替代GL。"""
import unittest
from shapely.geometry import LineString, MultiLineString, Polygon, box
from build_tokyo_shoreline_morph import build_plan, candidate, coverage, orientation_safe, ring_match, stroke


class MorphTests(unittest.TestCase):
    def test_straight_continuous_width(self):
        lines = LineString([(0, 0), (10, 0)])
        window = box(-5, -5, 15, 5)
        result = build_plan(lines, window)
        self.assertEqual(result['summary']['accepted'], 1)
        self.assertEqual(result['summary']['predicted_transition'], [2, 2])
        self.assertEqual(result['summary']['original_transition'], [4, 4])
        self.assertFalse(result['native_verified'])

    def test_island_hole(self):
        lines = LineString([(0, 0), (10, 0), (10, 10), (0, 10), (0, 0)])
        result = build_plan(lines, box(-5, -5, 15, 15))
        self.assertEqual(result['summary']['accepted'], 1)
        self.assertEqual(result['groups'][0]['mesh']['sample_count'], 34)

    def test_split_falls_back_without_losing_faces(self):
        lines = MultiLineString([[(0, 0), (10, 0)], [(0, 1.5), (10, 1.5)]])
        result = build_plan(lines, box(-5, -5, 15, 15))
        self.assertEqual(result['summary']['accepted'], 0)
        self.assertEqual(result['summary']['fallback_faces'], result['summary']['baseline_faces'])
        self.assertEqual([m['faces'] for m in result['groups'][0]['meshes']], result['summary']['baseline_faces'])

    def test_clip_keeps_source_window(self):
        result = build_plan(LineString([(-5, 0), (15, 0)]), box(0, -5, 10, 5))
        self.assertEqual(result['summary']['accepted'], 1)
        self.assertTrue(all(0 <= p[0] <= 10 for p in result['groups'][0]['mesh']['wide']))

    def test_world_native_precision(self):
        lines = LineString([(-6300.1123, -3700.0345), (-5300.2276, -2700.9851)])
        result = build_plan(lines, box(-6500, -3900, -5000, -2500))
        self.assertEqual(result['summary']['accepted'], 1)

    def test_reversed_ring(self):
        a = [(0, 0), (10, 0), (10, 10), (0, 10)]
        self.assertEqual(ring_match(a, a[1:]+a[:1]), a)
        self.assertEqual(ring_match(a, a[::-1]), a)
        with self.assertRaises(ValueError):
            ring_match(a, a[:3])

    def test_interior_orientation_rejected(self):
        # 端点同朝向，但中途两边交换并退化，不能只测端点。
        self.assertFalse(orientation_safe([(0, 0), (1, 0), (0, 1)],
                                         [(0, 0), (-1, 0), (0, -1)], [[0, 1, 2]]))

    def test_duplicate_triangle_rejected(self):
        with self.assertRaisesRegex(ValueError, 'native_overlap'):
            coverage([(0, 0), (1, 0), (0, 1)], [[0, 1, 2], [0, 1, 2]], Polygon([(0, 0), (1, 0), (0, 1)]))

    def test_missing_hole_rejected(self):
        lines = LineString([(0, 0), (10, 0), (10, 10), (0, 10), (0, 0)])
        window = box(-5, -5, 15, 15)
        wide = stroke(lines, window, 2)
        with self.assertRaisesRegex(ValueError, 'hole_count_changed'):
            candidate(wide, Polygon(wide.exterior), lambda w: stroke(lines, window, w))


if __name__ == '__main__':
    unittest.main()
