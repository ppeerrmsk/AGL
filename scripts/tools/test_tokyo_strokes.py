"""连续带独立几何反例；不依赖Godot截图自证。"""
import copy
import math
import unittest
from build_tokyo_strokes import stroke, prepare
from shapely.geometry import Point, Polygon
from shapely.ops import unary_union


def surface(vertices):
    return unary_union([Polygon(vertices[i:i+3]) for i in range(0, len(vertices), 3)])


class StrokeTests(unittest.TestCase):
    def test_straight_and_redundant_points(self):
        points = [[0,0],[0,0],[5,0],[10,0]]
        data, stats = stroke(points, 2)
        self.assertTrue(surface(data).equals(Polygon([(0,-1),(10,-1),(10,1),(0,1)])))
        self.assertEqual(stats['triangles'], 2)
        self.assertEqual(points, [[0,0],[0,0],[5,0],[10,0]])

    def test_corner_covers_missing_outer_wedge(self):
        data, stats = stroke([[0,0],[10,0],[10,10]], 2)
        mesh = surface(data)
        self.assertTrue(mesh.covers(Point(10.8,-.8)))
        self.assertAlmostEqual(stats['added_area'], 1)
        self.assertLess(stats['removed_area'], 1e-8)
        reverse, _ = stroke([[10,10],[10,0],[0,0]], 2)
        self.assertTrue(mesh.equals(surface(reverse)))

    def test_closed_loop_retains_hole(self):
        data, _ = stroke([[0,0],[10,0],[10,10],[0,10],[0,0]], 2)
        mesh = surface(data)
        self.assertFalse(mesh.covers(Point(5,5)))
        self.assertEqual(len(mesh.interiors), 1)
        self.assertAlmostEqual(mesh.area, 80)

    def test_self_crossing_has_no_overlapping_triangles(self):
        data, _ = stroke([[0,0],[10,10],[0,10],[10,0]], 2)
        mesh = surface(data)
        area_sum = sum(Polygon(data[i:i+3]).area for i in range(0,len(data),3))
        self.assertAlmostEqual(area_sum, mesh.area, places=7)
        self.assertTrue(mesh.covers(Point(5,5)))

    def test_sharp_corner_has_bounded_mitre(self):
        data, _ = stroke([[0,0],[10,0],[0,.01]], 2)
        mesh = surface(data)
        # 截角沿角平分线限长，不是世界X轴；旋转截角的端点X可以略超过12。
        dx, dy = 1 + 10 / math.hypot(10,.01), -.01 / math.hypot(10,.01)
        length = math.hypot(dx,dy)
        self.assertLessEqual(max(((x-10)*dx+y*dy)/length for x,y in mesh.exterior.coords), 2.000001)
        self.assertGreaterEqual(mesh.bounds[0], -.002)

    def test_invalid_input_rejected(self):
        for points, width in [([],1), ([[0,0]],1), ([[0,0],[0,0]],1),
                              ([[0,0],[1,1]],0), ([[0,0],[1,1]],math.inf),
                              ([[0,0],[math.nan,1]],1)]:
            with self.assertRaises(ValueError):
                stroke(points, width)

    def test_preparation_preserves_sources_and_subway_filter(self):
        city = {'buildings':[{'id':'b','height_m':90}],
                'roads':[{'id':'r','class':'primary','width_px':2,'points':[[0,0],[10,0]]}],
                'rails':[{'id':'rail','class':'rail','points':[[0,0],[0,10]]},
                         {'id':'sub','class':'subway','points':[[0,0],[10,10]]}]}
        original = copy.deepcopy(city)
        stats = prepare(city)
        self.assertEqual(stats['strokes'], 4)
        self.assertEqual(stats['subway_skipped'], 1)
        self.assertEqual(city['rails'][1], original['rails'][1])
        self.assertEqual(city['roads'][0]['joined_strokes']['casing']['width'], 2.65)
        for key in ['roads','rails']:
            for raw in city[key]:
                raw.pop('joined_strokes', None)
        self.assertEqual(city, original)


if __name__ == '__main__':
    unittest.main()
