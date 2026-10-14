import unittest
from shapely.geometry import Polygon, box, Point, MultiPolygon
from build_tokyo_static_shadow import sweep, raster, validate_bounds


class ShadowTests(unittest.TestCase):
    def test_thin_outer_shell_precedes_larger_courtyard_island(self):
        courtyard = Polygon([(0,0),(100,0),(100,100),(0,100)], [[(1,1),(99,1),(99,99),(1,99)]])
        island = box(10,10,90,90)
        self.assertGreater(island.area,courtyard.area)
        result = raster(MultiPolygon([island,courtyard]), [0,0,100,100], 100)
        self.assertEqual(result.getpixel((50,50)),255)

    def test_courtyard_island_order_does_not_erase_shadow(self):
        courtyard = Polygon([(0,0),(20,0),(20,20),(0,20)], [[(4,4),(16,4),(16,16),(4,16)]])
        island = box(8,8,12,12)
        first = raster(MultiPolygon([island,courtyard]), [0,0,20,20], 100)
        second = raster(MultiPolygon([courtyard,island]), [0,0,20,20], 100)
        self.assertEqual(first.getpixel((50,50)),255)
        self.assertEqual(first.tobytes(),second.tobytes())

    def test_bounds_use_long_axis(self):
        self.assertEqual(validate_bounds([0,0,800,1600]),1600)
        self.assertEqual(validate_bounds([-4,-2,1600,800]),1604)

    def test_invalid_bounds(self):
        for bounds in [[0,0,0,1],[2,0,1,1],[0,2,1,1],[0,0,float('nan'),1],[0,0,1,float('inf')],[0,0,1]]:
            with self.assertRaises(ValueError):
                validate_bounds(bounds)

    def test_height_and_direction(self):
        result = sweep(box(0, 0, 4, 4), 0, 10, [1, 0])
        self.assertAlmostEqual(result.area, 56)
        self.assertEqual(result.bounds, (0, 0, 14, 4))

    def test_raised_prism_does_not_connect_to_ground_footprint(self):
        result = sweep(box(0, 0, 4, 4), 10, 20, [1, 0])
        self.assertFalse(result.intersects(box(0, 0, 4, 4)))
        self.assertEqual(result.bounds, (10, 0, 24, 4))

    def test_courtyard_not_convex_hull(self):
        shape = Polygon([(0,0),(20,0),(20,20),(0,20)], [[(4,4),(16,4),(16,16),(4,16)]])
        result = sweep(shape, 0, 1, [1, 0])
        self.assertFalse(result.covers(Point(10, 10)))
        self.assertTrue(result.covers(Point(4.5, 10)))

    def test_off_region_caster(self):
        result = sweep(box(-5,0,-1,4), 0, 10, [1,0])
        self.assertTrue(result.intersects(box(0,0,10,10)))

    def test_invalid_height(self):
        for bottom, top in [(2,1), (-1,2), (0,0)]:
            with self.assertRaises(ValueError):
                sweep(box(0,0,1,1), bottom, top)

    def test_raster_coordinates_and_no_overlap_darkening(self):
        shape = box(1,1,3,3)
        for size in [16, 32]:
            image = raster(shape.union(shape), [0,0,4,4], size)
            self.assertEqual(image.mode, 'L')
            self.assertEqual(image.getpixel((size//2,size//2)),255)
            self.assertEqual(image.getpixel((0,0)),0)


if __name__ == '__main__':
    unittest.main()
