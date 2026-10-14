"""屏幕轮廓约束独立反例，包含顶点Hausdorff会漏掉的长边中点。"""
import copy
import math
import unittest
from build_tokyo_footprint_lod import eligible, f32, simplify_ring, within_error, prepare, MAX_SCALES, PIXEL_ERROR
from shapely import constrained_delaunay_triangles
from shapely.geometry import Point, Polygon


def ring(points):
    poly = Polygon(points)
    return {'outer':points,'holes':[], 'triangles':
            [[x,y] for face in constrained_delaunay_triangles(poly).geoms for x,y in list(face.exterior.coords)[:3]]}


class FootprintTests(unittest.TestCase):
    def test_small_notch_native_precision_and_area(self):
        source = ring([[-6300,-3000],[-6290,-3000],[-6290,-2990],[-6294.9,-2990],
                       [-6295,-2990.1],[-6295.1,-2990],[-6300,-2990]])
        original = copy.deepcopy(source)
        for scale in MAX_SCALES:
            candidate = simplify_ring(source,scale)
            self.assertIsNotNone(candidate)
            self.assertTrue(within_error(Polygon(source['outer']),Polygon(candidate['outer']),PIXEL_ERROR/scale))
            native = Polygon([(f32(x), f32(y)) for x, y in source['outer']])
            self.assertTrue(within_error(native,Polygon(candidate['outer']),PIXEL_ERROR/scale))
            self.assertLess(len(candidate['triangles']),len(source['triangles']))
            self.assertTrue(all(f32(v)==v for p in candidate['outer'] for v in p))
            self.assertLessEqual(abs(Polygon(candidate['outer']).area/Polygon(source['outer']).area-1),.05)
        self.assertEqual(source,original)

    def test_complete_boundary_not_only_vertices(self):
        original = Polygon([(0,0),(10,0),(10,10),(9,10),(9,1),(1,1),(1,10),(0,10)])
        candidate = Polygon([(0,0),(10,0),(10,10),(0,10)])
        self.assertLessEqual(original.hausdorff_distance(candidate),1.1)
        self.assertTrue(all(candidate.boundary.distance(Point(p)) <= 1.1 for p in original.exterior.coords))
        self.assertFalse(within_error(original,candidate,1.1))

    def test_no_reduction_and_invalid_scales(self):
        source = ring([[0,0],[10,0],[10,10],[0,10]])
        self.assertIsNone(simplify_ring(source,MAX_SCALES[0]))
        for scale in [0,-1,math.inf,math.nan]:
            with self.assertRaises(ValueError):
                simplify_ring(source,scale)

    def test_protected_buildings(self):
        raw = {'height_source':'fallback','height_m':20,'rings':[ring([[0,0],[5,0],[5,5],[0,5]])]}
        self.assertTrue(eligible(raw))
        for tags in [{'building': 'roof'}, {'building:part': 'roof'}]:
            self.assertFalse(eligible(dict(raw, source_tags=tags)))
        self.assertTrue(eligible(dict(raw, source_tags={'roof:shape': 'flat'})))
        for key,value in [('height_source','height'),('height_source','levels'),('height_m',80),
                          ('parents',['p']),('parts',['p']),('is_part',True),('roof_shape','dome'),
                          ('render_outline',False),('defer_render',True),('roof_volume',{'roof':[1]})]:
            altered=copy.deepcopy(raw)
            altered[key]=value
            self.assertFalse(eligible(altered),(key,value))
        raw['rings'][0]['holes']=[[[1,1],[2,1],[2,2],[1,2]]]
        self.assertFalse(eligible(raw))
        self.assertIsNone(simplify_ring(raw['rings'][0],MAX_SCALES[0]))

    def test_invalid_topology_and_deformation(self):
        original=Polygon([(0,0),(10,0),(10,10),(0,10)])
        self.assertFalse(within_error(original,Polygon([(0,0),(10,10),(10,0),(0,10)]),1))
        self.assertFalse(within_error(original,Polygon([(0,0),(10,0),(10,12),(0,10)]),.1))
        # 原始 JSON 合法，但单精度后极窄边全部塌缩，不能生成声称有误差保证的候选。
        collapsed=ring([[1000000,0],[1000000.01,0],[1000000.01,10],[1000000,10]])
        self.assertIsNone(simplify_ring(collapsed,MAX_SCALES[0]))

    def test_prepared_levels_monotonic_and_source_retained(self):
        source=ring([[0,0],[10,0],[10,10],[5.2,10],[5,9.8],[4.8,10],[0,10]])
        raw={'height_source':'fallback','height_m':20,'rings':[source]}
        city={'buildings':[raw]}
        original=copy.deepcopy(source)
        prepare(city)
        counts=[len(raw.get('footprint_lod',{}).get(str(slot),{'rings':[source]})['rings'][0]['triangles']) for slot in range(4)]
        self.assertEqual(counts,sorted(counts))
        self.assertEqual(raw['rings'][0],original)


if __name__ == '__main__':
    unittest.main()
