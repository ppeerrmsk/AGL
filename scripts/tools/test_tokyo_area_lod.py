"""面积补偿远景轮廓的独立反例，不放宽已有像素和拓扑门。"""
import copy
import math
import unittest
from build_tokyo_area_lod import area_corrected_ring, prepare, audit
from build_tokyo_footprint_lod import within_error, MAX_SCALES
from test_tokyo_footprint_lod import ring
from shapely.geometry import Polygon


class AreaLodTests(unittest.TestCase):
    def test_subpixel_square_retains_area_and_centroid(self):
        source=ring([[-6300,-3000],[-6294,-3000],[-6294,-2994],[-6300,-2994]])
        saved=copy.deepcopy(source)
        result=area_corrected_ring(source,MAX_SCALES[0])
        self.assertIsNotNone(result)
        self.assertEqual(len(result['triangles']),3)
        self.assertAlmostEqual(Polygon(result['outer']).area,36,places=2)
        self.assertLess(Polygon(source['outer']).centroid.distance(Polygon(result['outer']).centroid),.001)
        self.assertEqual(source,saved)

    def test_visible_square_is_not_distorted_into_triangle(self):
        source=ring([[0,0],[10,0],[10,10],[0,10]])
        self.assertIsNone(area_corrected_ring(source,MAX_SCALES[3]))

    def test_large_notch_cannot_be_filled_by_area_correction(self):
        source=ring([[0,0],[20,0],[20,20],[12,20],[12,4],[8,4],[8,20],[0,20]])
        candidate=area_corrected_ring(source,MAX_SCALES[3])
        if candidate:
            self.assertTrue(within_error(Polygon(source['outer']),Polygon(candidate['outer']),.35/MAX_SCALES[3]))

    def test_invalid_scale_and_holes(self):
        source=ring([[0,0],[10,0],[10,10],[0,10]])
        for scale in [0,-1,math.nan,math.inf]:
            with self.assertRaises(ValueError):
                area_corrected_ring(source,scale)
        source['holes']=[[[2,2],[4,2],[4,4],[2,4]]]
        self.assertIsNone(area_corrected_ring(source,MAX_SCALES[0]))

    def test_protected_sources_and_full_source_roundtrip(self):
        low={'id':'a','regional_draw_owner':'north_coast','height_source':'fallback','height_m':8,
             'rings':[ring([[0,0],[6,0],[6,6],[0,6]])]}
        records=[low]
        for key,value in [('height_source','height'),('parents',['parent']),('regional_draw_owner','yokohama')]:
            protected=copy.deepcopy(low)
            protected[key]=value
            records.append(protected)
        city={'buildings':records,'unchanged':'source'}
        saved=copy.deepcopy(city)
        prepared,_=prepare(city,'north_coast')
        self.assertGreater(audit(city,prepared,'north_coast'),0)
        self.assertEqual(prepared['buildings'][1:],city['buildings'][1:])
        self.assertEqual(city,saved)
        prepared['buildings'][0]['height_m']+=1
        with self.assertRaises(AssertionError):
            audit(city,prepared,'north_coast')


if __name__=='__main__':
    unittest.main()
