"""接缝审计的独立正例与反例；不读取实际地图或修改资源。"""
import copy
import unittest
from audit_tokyo_region_seam import audit


def ground(bounds, edge=5):
    x0, y0, _, y1 = bounds
    return {'bounds': bounds, 'surfaces': [{'id': 'source-coastal-land', 'triangles':
        [[x0,y0],[edge,y0],[edge,y1],[x0,y0],[edge,y1],[x0,y1]]}]}


class SeamTests(unittest.TestCase):
    def setUp(self):
        self.empty = {'buildings': []}
        self.south, self.north = ground([0,0,10,10]), ground([0,-10,10,0])

    def test_equal_coast_and_vertical_edge(self):
        self.assertTrue(audit(self.empty,self.south,self.empty,self.north)['simultaneous_render_ready'])
        self.assertTrue(audit(self.empty,ground([0,0,10,10],10),self.empty,ground([10,0,20,10],20))['source_seam_ok'])

    def test_unfilled_gap_detected(self):
        result = audit(self.empty,self.south,self.empty,ground([0,-10,10,0],6))
        self.assertFalse(result['source_seam_ok'])
        self.assertEqual(result['coast_mismatch_length_px'], 1)

    def test_shared_building_requires_owner_even_if_identical(self):
        building = {'id':'b', 'height_m':90, 'height_source':'height','min_height_m':0,
                    'rings':[{'outer':[[1,-1],[2,-1],[2,1],[1,1]],'holes':[]}]}
        city = {'buildings':[building]}
        other = copy.deepcopy(city)
        other['buildings'][0]['rings'][0]['outer'].reverse()
        result = audit(city,self.south,other,self.north)
        self.assertTrue(result['source_seam_ok'])
        self.assertFalse(result['simultaneous_render_ready'])
        self.assertEqual(result['requires_unique_draw_owner'], ['b'])
        other['buildings'][0]['height_m'] = 20
        self.assertEqual(audit(city,self.south,other,self.north)['height_conflicts'], ['b'])
        other['buildings'][0]['rings'][0]['holes'] = [[[1.2,-.2],[1.5,-.2],[1.5,.2]]]
        self.assertEqual(audit(city,self.south,other,self.north)['shape_conflicts'], ['b'])

    def test_nonadjacent_and_touching_corner_rejected(self):
        with self.assertRaises(ValueError):
            audit(self.empty,self.south,self.empty,ground([0,-20,10,-10]))
        with self.assertRaises(ValueError):
            audit(self.empty,self.south,self.empty,ground([10,-10,20,0],20))


if __name__ == '__main__':
    unittest.main()
