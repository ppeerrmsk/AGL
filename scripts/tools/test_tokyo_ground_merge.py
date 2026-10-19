import struct
import unittest
from shapely.geometry import Polygon
from build_tokyo_ground_merge import merge_component, plan_records


def grid(hole=False):
    result = []
    for x in range(3):
        for y in range(3):
            if hole and x == y == 1:
                continue
            result += [Polygon([(x,y),(x+1,y),(x+1,y+1)]), Polygon([(x,y),(x+1,y+1),(x,y+1)])]
    return result


def records(polygons, height=1., alpha=1.):
    return b''.join(struct.pack('<I14f', i, height, 0,1,0, .5,.5,.5,alpha,
        *[v for p in list(poly.exterior.coords)[:-1] for v in p]) for i, poly in enumerate(polygons))


class GroundMergeTests(unittest.TestCase):
    def test_collinear_grid(self):
        self.assertEqual(len(merge_component(grid())), 2)

    def test_preserved_boundary_vertices(self):
        from shapely import unary_union
        source = grid()
        result = merge_component(source, preserve_boundary=True)
        self.assertIsNotNone(result)
        self.assertLess(len(result), len(source))
        boundary = set(unary_union(source).exterior.coords)
        self.assertTrue(boundary.issubset({p for triangle in result for p in triangle}))
        self.assertTrue(unary_union([Polygon(t) for t in result]).equals(unary_union(source)))

    def test_hole_preserved(self):
        result = merge_component(grid(True))
        self.assertIsNotNone(result)
        self.assertTrue(all(not Polygon(t).contains(Polygon([(1,1),(2,1),(2,2),(1,2)]).centroid) for t in result))

    def test_no_saving(self):
        self.assertIsNone(merge_component(grid()[:2]))

    def test_transparent_kept(self):
        self.assertEqual(plan_records(records(grid(), alpha=.5))['removed'], [])

    def test_height_partition(self):
        data = bytearray(records(grid()))
        struct.pack_into('<f', data, 4, 9.)
        plan = plan_records(bytes(data))
        self.assertNotIn(0, plan['removed'])

    def test_reversed_kept(self):
        self.assertEqual(plan_records(records([Polygon(list(p.exterior.coords)[:-1][::-1]) for p in grid()]))['removed'], [])

    def test_partial_record_rejected(self):
        with self.assertRaises(ValueError):
            plan_records(b'bad')

    def test_inward_error_bound(self):
        source = [Polygon([(0,0),(5,0),(5,5),(2.6,5.04),(2.4,5.04),(0,5)])]
        from shapely import constrained_delaunay_triangles, unary_union
        original = list(constrained_delaunay_triangles(source[0]).geoms)
        result = merge_component(original, .1)
        self.assertIsNotNone(result)
        reduced = unary_union([Polygon(t) for t in result])
        self.assertTrue(source[0].covers(reduced))
        self.assertGreaterEqual(reduced.area, source[0].area * .98)

    def test_large_loss_rejected(self):
        from shapely import constrained_delaunay_triangles
        source = Polygon([(0,0),(10,0),(10,10),(5,14),(0,10)])
        self.assertIsNone(merge_component(list(constrained_delaunay_triangles(source).geoms), 5.))


if __name__ == '__main__':
    unittest.main()
