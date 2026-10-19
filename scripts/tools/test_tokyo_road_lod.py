import copy
import math
import unittest
from shapely.geometry import Polygon
from build_tokyo_road_lod import accept_shape, locked_points, prepare, simplify_locked, stroke


def fixture():
    road={'id':'a','class':'residential','width_px':2.,'points':[[0,0],[2,.02],[4,0],[6,0],[8,0]]}
    return {'roads':[road],'rails':[],'buildings':[]},{'paths':[],'surfaces':[]}


class RoadLODTests(unittest.TestCase):
    def test_real_stroke_saves_not_input_mutation(self):
        city,ground=fixture()
        before=copy.deepcopy((city,ground))
        for profile in ['road15','road25']:
            plan=prepare(city,ground,profile)
            self.assertEqual(plan['accepted_sources'],1)
            row=plan['rows'][0]
            self.assertEqual(row['points'],[[0,0],[8,0]])
            self.assertEqual(row['width'],2.)
            self.assertEqual(row['before_faces']-row['after_faces'],6)
            self.assertFalse(plan['native_faces_verified'])
        self.assertEqual((city,ground),before)

    def test_locked_junction_survives(self):
        city,ground=fixture()
        city['rails']=[{'id':'r','class':'rail','points':[[2,.02],[2,6]]}]
        locks=locked_points(city['roads']+city['rails'])
        self.assertIn((2,.02),simplify_locked(city['roads'][0]['points'],locks,1.))

    def test_endpoints_and_closed_loop(self):
        p=[[0,0],[3,.01],[6,0]]
        self.assertEqual(simplify_locked(p,set(),1.),[(0,0),(6,0)])
        loop=[[0,0],[2,0],[2,2],[0,2],[0,0]]
        result=simplify_locked(loop,{(0,0)},100.)
        self.assertEqual(result[0],result[-1])
        self.assertGreaterEqual(len(set(result)),3)

    def test_no_delete_short_source(self):
        city,ground=fixture()
        city['roads'][0]['points']=[[0,0],[.01,0]]
        self.assertEqual(prepare(city,ground,'road15')['rows'],[])

    def test_major_and_rails_never_reduced(self):
        city,ground=fixture()
        city['roads'][0]['class']='primary'
        city['rails']=[{'id':'r','class':'rail','points':[[20,0],[22,.02],[24,0],[26,0]]}]
        self.assertEqual(prepare(city,ground,'road25')['rows'],[])

    def test_added_road_cannot_enter_building(self):
        city,ground=fixture()
        city['buildings']=[{'rings':[{'outer':[[1.9,-.999],[2.1,-.999],[2.1,-.99],[1.9,-.99]]}]}]
        plan=prepare(city,ground,'road25')
        self.assertFalse(plan['rows'])
        self.assertGreater(plan['rejected']['protected_addition'],0)

    def test_water_and_park_protected(self):
        for kind in ['water','green','park']:
            city,ground=fixture()
            ground['surfaces']=[{'kind':kind,'triangles':[[1.9,-.999],[2.1,-.999],[2.,-.99]]}]
            self.assertFalse(prepare(city,ground,'road25')['rows'])

    def test_hole_and_width_error_rejected(self):
        whole=Polygon([(0,0),(8,0),(8,2),(0,2)])
        hole=Polygon(whole.exterior.coords,[[(3,.5),(4,.5),(4,1.5),(3,1.5)]])
        self.assertFalse(accept_shape(hole,whole,2))
        wide=Polygon([(0,-1),(8,-1),(8,3),(0,3)])
        self.assertFalse(accept_shape(whole,wide,2))

    def test_occupied_error_not_only_area(self):
        a=Polygon([(0,0),(8,0),(8,2),(0,2)])
        b=Polygon([(0,.02),(8,.02),(8,2.02),(0,2.02)])
        self.assertFalse(accept_shape(a,b,.01))
        self.assertTrue(accept_shape(a,b,.03))

    def test_invalid_inputs_fail_closed(self):
        city,ground=fixture()
        with self.assertRaises(ValueError):prepare(city,ground,'near')
        city['roads'].append(copy.deepcopy(city['roads'][0]))
        with self.assertRaises(ValueError):prepare(city,ground,'road15')
        for tolerance in [0,-1,math.inf,math.nan]:
            with self.assertRaises(ValueError):simplify_locked([[0,0],[1,0]],set(),tolerance)
        with self.assertRaises(ValueError):stroke([[0,0],[1,0]],0,False)

    def test_order_independent(self):
        city,ground=fixture()
        other=copy.deepcopy(city['roads'][0]);other['id']='b'
        other['points']=[[x,y+10] for x,y in other['points']]
        city['roads'].append(other)
        a=prepare(city,ground,'road25')
        city['roads'].reverse()
        self.assertEqual(a,prepare(city,ground,'road25'))


if __name__=='__main__':
    unittest.main()
