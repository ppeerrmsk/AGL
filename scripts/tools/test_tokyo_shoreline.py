"""岸线来源裁切、闭环与原生精度反例。"""
import math
import unittest
from shapely.geometry import LineString, Point, Polygon, box
from shapely import unary_union
from build_tokyo_shoreline import collect, build, parts


def surface(result):
    points = result['triangles']
    return unary_union([Polygon(points[i:i+3]) for i in range(0,len(points),3)])


class ShoreTests(unittest.TestCase):
    def test_clip_does_not_draw_window(self):
        lines, window, records = collect([('hash',dict(bounds=[0,0,10,10],coastlines=[[[-5,5],[15,5]]]))])
        result = surface(build(lines,window,2))
        self.assertEqual(result.bounds,(0,4,10,6))
        self.assertEqual(records[0]['ordinal'],0)
        self.assertEqual(records[0]['points'],[[-5,5],[15,5]])
        self.assertFalse(result.covers(Point(5,0)))

    def test_neighbor_join_and_duplicate(self):
        points = [[-5,5],[25,5]]
        sources = [('a',dict(bounds=[0,0,10,10],coastlines=[points,points])),
                   ('b',dict(bounds=[10,0,20,10],coastlines=[points]))]
        lines, window, _ = collect(sources)
        self.assertEqual(lines.length,20)
        self.assertEqual(len(parts(lines)),1)
        self.assertAlmostEqual(surface(build(lines,window,2)).area,40)

    def test_island_retains_hole_and_direction(self):
        points = [(0,0),(10,0),(10,10),(0,10),(0,0)]
        window = box(-5,-5,15,15)
        a = surface(build(LineString(points),window,1))
        b = surface(build(LineString(points[::-1]),window,1))
        self.assertTrue(a.equals(b))
        self.assertFalse(a.covers(Point(5,5)))
        self.assertEqual(len(a.interiors),1)

    def test_sharp_turn_and_crossing(self):
        for points in [[(0,0),(10,0),(0,.01)],[(0,0),(10,10),(0,10),(10,0)]]:
            result = build(LineString(points),box(-5,-5,15,15),2)
            self.assertLess(result['stats']['relative_area_error'],.002)
            self.assertLessEqual(surface(result).bounds[2],12.002)

    def test_reject_invalid_source_and_width(self):
        for bounds,points in [([0,0,0,10],[[0,0],[2,2]]),([0,0,10,10],[[0,0],[math.nan,2]]),
                              ([0,0,10,10],[[0,0],[0,0]])]:
            with self.assertRaises(ValueError):
                collect([('a',dict(bounds=bounds,coastlines=[points]))])
        with self.assertRaises(ValueError):
            build(LineString([(0,0),(10,0)]),box(-5,-5,15,15),3)

    def test_world_float32_precision(self):
        result = build(LineString([(-6300.1123,-3700.0345),(-5300.2276,-2700.9851),(-4300.7527,299.2341)]),box(-6301,-3701,-4300,300),1)
        self.assertLess(result['stats']['relative_area_error'],.002)


if __name__ == '__main__':
    unittest.main()
