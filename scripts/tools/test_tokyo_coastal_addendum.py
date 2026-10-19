"""近岸补充面反例：不重复铺陆地/建筑，不凭线扩面，不越过孔洞/精度门。"""
import copy
import unittest
from build_tokyo_coastal_addendum import existing_coverage, native_faces, prepare
from shapely.geometry import Polygon, box, GeometryCollection
from shapely import wkb


def record(identity, shape, **tags):
    return {'id':identity,'wkb':shape.wkb_hex,'tags':{'man_made':'pier',**tags}}


class CoastalAddendumTests(unittest.TestCase):
    def run_case(self, areas, existing=None, ids=None, ways=None):
        source={'areas':areas,'ways':ways or []}
        saved=copy.deepcopy(source)
        result=prepare(source,box(0,0,20,20),existing if existing is not None else GeometryCollection(),ids or set())
        self.assertEqual(source,saved)
        return result

    def test_missing_rectangle(self):
        result=self.run_case([record('w1',box(1,1,10,10))])
        self.assertEqual(result['triangles'],2)
        self.assertAlmostEqual(result['surfaces'][0]['native_area_px2'],81)

    def test_existing_land_not_rebuilt(self):
        result=self.run_case([record('w1',box(1,1,10,10))],box(0,0,20,20))
        self.assertEqual(result['surfaces'],[])
        self.assertEqual(result['audit'][0]['status'],'existing_geometry')
        self.assertEqual(result['audit'][0]['pieces'],[])

    def test_existing_building_identity_not_duplicated(self):
        result=self.run_case([record('w1',box(1,1,10,10))],ids={'w1'})
        self.assertEqual(result['triangles'],0)
        self.assertEqual(result['audit'][0]['status'],'existing_building_identity')

    def test_overlap_deducted_and_other_building_hole_preserved(self):
        result=self.run_case([record('w1',box(1,1,10,10))],box(3,3,5,5))
        shape=wkb.loads(result['surfaces'][0]['native_wkb'],hex=True)
        self.assertEqual(len(shape.interiors),1)
        self.assertEqual(shape.intersection(box(3,3,5,5)).area,0)
        self.assertEqual(shape.area,77)

    def test_courtyard_not_filled(self):
        shape=Polygon(box(1,1,10,10).exterior.coords,[box(3,3,5,5).exterior.coords])
        result=native_faces(shape)
        self.assertEqual(wkb.loads(result['native_wkb'],hex=True).area,77)

    def test_invalid_source_not_repaired(self):
        result=self.run_case([record('w1',Polygon([(1,1),(9,9),(1,9),(9,1)]))])
        self.assertEqual(result['audit'][0]['status'],'deferred_invalid_source')
        self.assertEqual(result['surfaces'],[])

    def test_unknown_width_way_is_deferred(self):
        result=self.run_case([],ways=[{'id':'w2','tags':{'man_made':'pier'},'points':[[1,1],[9,9]],'closed':False}])
        self.assertEqual(result['triangles'],0)
        self.assertEqual(len(result['deferred_ways']),1)

    def test_sorted_unique_ownership_and_reorder_determinism(self):
        records=[record('w2',box(5,1,12,10)),record('w1',box(1,1,10,10))]
        result=self.run_case(records)
        self.assertEqual(result,self.run_case(records[::-1]))
        shapes=[wkb.loads(s['native_wkb'],hex=True) for s in result['surfaces']]
        self.assertEqual(shapes[0].intersection(shapes[1]).area,0)
        self.assertEqual(sum(s.area for s in shapes),99)
        with self.assertRaises(ValueError):
            self.run_case([records[0],records[0]])

    def test_underground_area_no_and_outside(self):
        records=[record('w1',box(1,1,2,2),location='underground'),
                 record('w2',box(1,1,2,2),area='no'),record('w3',box(30,30,40,40))]
        result=self.run_case(records)
        self.assertEqual(result['triangles'],0)
        self.assertEqual(result['audit'][-1]['status'],'outside_coverage')

    def test_negative_layer_not_assumed_underground(self):
        self.assertEqual(self.run_case([record('w1',box(1,1,2,2),layer='-1')])['triangles'],2)

    def test_quantization_collapse_fails_closed(self):
        self.assertIsNone(native_faces(box(-6000,-3000,-6000+1e-7,-2990)))

    def test_native_contact_inset_remains_under_original_error_gate(self):
        shape=box(0,0,4,4)
        occupied=box(3.9999,0,5,4)
        result=native_faces(shape,occupied)
        native=wkb.loads(result['native_wkb'],hex=True)
        self.assertEqual(native.intersection(occupied).area,0)
        self.assertEqual(result['source_wkb'],shape.wkb_hex)
        self.assertLessEqual(shape.boundary.hausdorff_distance(native.boundary),.002)
        self.assertGreater(result['contact_inset_world_px'],0)

    def test_large_overlap_cannot_be_hidden_by_contact_correction(self):
        self.assertIsNone(native_faces(box(0,0,4,4),box(3,0,5,4)))

    def test_short_source_contact_does_not_flip_native_triangles(self):
        # w1110457288扣除既有岸线后的真实短接边；原生逐角量化曾造成三角相交。
        shape=Polygon([(-3301.0997356454814,-2162.7629917946138),(-3301.1,-2162.763),
            (-3301.639394046418,-2163.9014617643497),(-3302.2572271292124,-2165.2048500000374),
            (-3320.8550354273166,-2165.698800000289),(-3320.927382845489,-2163.3511500000645),
            (-3301.099668432027,-2162.762850000288)])
        result=native_faces(shape)
        self.assertIsNotNone(result)
        native=wkb.loads(result['native_wkb'],hex=True)
        pts=result['triangles']
        area=sum(Polygon(pts[i:i+3]).area for i in range(0,len(pts),3))
        self.assertAlmostEqual(area,native.area,places=7)
        self.assertLessEqual(shape.boundary.hausdorff_distance(native.boundary),.002)

    def test_existing_deferred_buildings_and_water_do_not_hide_deck(self):
        ring={'outer':[[1,1],[10,1],[10,10],[1,10]],'holes':[]}
        city={'buildings':[{'id':'w1','rings':[ring],'defer_render':True}]}
        ground={'surfaces':[{'kind':'water','triangles':[[1,1],[10,1],[1,10]]}]}
        covered,ids=existing_coverage(city,ground)
        self.assertTrue(covered.is_empty)
        self.assertEqual(ids,set())


if __name__=='__main__':
    unittest.main()
