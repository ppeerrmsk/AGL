import copy
import unittest
from build_tokyo_cluster_lod import candidate, prepare
from shapely.geometry import box, Polygon

def record(identity, x, height=6.4, known=False):
    points = [[x, 0], [x + 5, 0], [x + 5, 5], [x, 5]]
    return {'id': identity, 'height_source': 'height' if known else 'fallback',
        'height_m': height, 'regional_draw_owner': 'north_coast', 'kind': 'urban',
        'rings': [{'outer': points, 'holes': [], 'triangles': points[:3] + [points[0], points[2], points[3]]}]}

class ClusterTests(unittest.TestCase):
    def test_invalid_production_bounds(self):
        for bounds in [[],[0,0,1],[0,0,0,1],[1,0,0,1],[0,2,1,1],[0,0,float('inf'),1],[0,float('nan'),1,2]]:
            with self.assertRaises(ValueError):
                prepare({'buildings':[]},bounds)

    def test_expanded_bounds_add_region_without_crossing_height_or_parent(self):
        city={'buildings':[record('a',0),record('b',5.2),record('c',100),record('d',105.2)]}
        original=copy.deepcopy(city)
        costs={i:{'parent':0 if i in ['a','b'] else 1,'faces':2,'detail':2} for i in ['a','b','c','d']}
        narrow=prepare(city,[-1,-1,15,7],max_scale=.3888,max_group=8,native_costs=costs,strategy='min_cost')
        wide=prepare(city,[-1,-1,115,7],max_scale=.3888,max_group=8,native_costs=costs,strategy='min_cost')
        self.assertEqual(narrow['merged_sources'],2)
        self.assertEqual(wide['merged_sources'],4)
        self.assertEqual(wide['faces_saved'],4)
        self.assertEqual(city,original)
        self.assertTrue(all(box(-1,-1,115,7).covers(Polygon(g['outer'])) for g in wide['groups']))

    def test_output_cannot_escape_production_window(self):
        city={'buildings':[record('a',0),record('b',5.2)]}
        result=prepare(city,[0,0,10.2,5],max_scale=.3888,max_group=8)
        self.assertTrue(all(box(0,0,10.2,5).covers(Polygon(g['outer'])) for g in result['groups']))

    def test_min_cost_cannot_widen_obstacles_or_geometry(self):
        costs = [{'faces': 10, 'detail': 2}] * 2
        close = [box(0, 0, 5, 5), box(5.2, 0, 10.2, 5)]
        for obstacle in [box(5.05, 1, 5.15, 2), box(5.05, -1, 5.15, 6)]:
            self.assertIsNone(candidate(close, [obstacle], .3888, costs, 'min_cost'))
        self.assertIsNone(candidate([box(0,0,1,10), box(2,0,3,10)], [], .3888, costs, 'min_cost'))
        self.assertIsNone(candidate([box(0,0,5,5), box(30,0,35,5)], [], .3888, costs, 'min_cost'))

    def test_min_cost_never_loses_local_native_savings(self):
        a = Polygon([(0,0),(5,0),(5,2),(4.8,2.1),(5,3),(5,5),(0,5)])
        b = box(5.2, 0, 10.2, 5)
        for detail in [0, 1, 2]:
            costs = [{'faces': 22, 'detail': detail}] * 2
            old = candidate([a,b], [], .3888, costs)
            new = candidate([a,b], [], .3888, costs, 'min_cost')
            self.assertIsNotNone(new)
            if old:
                self.assertGreaterEqual(new[1], old[1])

    def test_min_cost_preserves_height_parent_and_input(self):
        city = {'buildings': [record('a',0), record('b',5.2,known=True)]}
        original = copy.deepcopy(city)
        costs = {i: {'parent': 8, 'faces': 2, 'detail': 2} for i in ['a','b']}
        self.assertEqual(prepare(city, [-1,-1,15,7], max_scale=.3888, native_costs=costs, strategy='min_cost')['groups'], [])
        self.assertEqual(city, original)
        with self.assertRaises(ValueError):
            candidate([box(0,0,5,5)], [], strategy='min_cost')

    def test_close_same_height_group(self):
        city = {'buildings': [record('a', 0), record('b', 5.2)], 'roads': []}
        original = copy.deepcopy(city)
        result = prepare(city, [-1, -1, 15, 7])
        self.assertEqual(result['merged_sources'], 2)
        self.assertEqual(result['groups'][0]['height_m'], 6.4)
        self.assertGreater(result['faces_saved'], 0)
        self.assertEqual(city, original)

    def test_distinct_height_not_merged(self):
        result = prepare({'buildings': [record('a', 0), record('b', 5.2, 6.41)]}, [-1, -1, 15, 7])
        self.assertEqual(result['groups'], [])

    def test_far_scale_and_source_limit(self):
        city = {'buildings': [record(str(i), i * 5.2) for i in range(8)]}
        result = prepare(city, [-1, -1, 50, 7], max_scale=.1944, max_group=8)
        self.assertEqual(result['max_scale'], .1944)
        self.assertEqual(result['max_group'], 8)
        ids = [identity for group in result['groups'] for identity in group['ids']]
        self.assertTrue(ids)
        self.assertEqual(len(ids), len(set(ids)))
        self.assertTrue(all(len(group['ids']) <= 8 for group in result['groups']))

    def test_invalid_scale_rejected(self):
        for scale in [0, -1, float('nan'), float('inf')]:
            with self.assertRaises(ValueError):
                candidate([box(0, 0, 5, 5)], [], scale)

    def test_native_roof_cost(self):
        polygons = [box(0, 0, 5, 5), box(5.2, 0, 10.2, 5)]
        result = candidate(polygons, [], .1944, [{'faces': 2, 'detail': 2}] * 2)
        self.assertEqual(result[1], 2)
        self.assertIsNone(candidate(polygons, [], .1944, [{'faces': 1, 'detail': 2}] * 2))

    def test_parent_cost_membership(self):
        city = {'buildings': [record('a', 0), record('b', 5.2)]}
        costs = {'a': {'parent': 8, 'faces': 2, 'detail': 2}, 'b': {'parent': 9, 'faces': 2, 'detail': 2}}
        self.assertEqual(prepare(city, [-1,-1,15,7], max_scale=.1944, native_costs=costs)['groups'], [])
        costs['b']['parent'] = 8
        result = prepare(city, [-1,-1,15,7], max_scale=.1944, native_costs=costs)
        self.assertEqual(result['faces_saved'], 2)

    def test_far_road_still_blocks(self):
        city = {'buildings': [record('a', 0), record('b', 5.2)],
                'roads': [{'points': [[5.1, -1], [5.1, 6]], 'width_px': .1}]}
        self.assertEqual(prepare(city, [-1, -1, 15, 7], max_scale=.1944, max_group=8)['groups'], [])

    def test_known_height_preserved(self):
        result = prepare({'buildings': [record('a', 0), record('b', 5.2, known=True)]}, [-1, -1, 15, 7])
        self.assertEqual(result['groups'], [])

    def test_road_and_rail_corridor(self):
        for kind, entry in [('roads', {'points': [[5.1, -1], [5.1, 6]], 'width_px': .1}),
                            ('rails', {'points': [[5.1, -1], [5.1, 6]], 'class': 'rail'})]:
            result = prepare({'buildings': [record('a', 0), record('b', 5.2)], kind: [entry]}, [-1, -1, 15, 7])
            self.assertEqual(result['groups'], [])

    def test_wide_gap_preserved(self):
        self.assertIsNone(candidate([box(0, 0, 5, 5), box(7, 0, 12, 5)], []))

    def test_major_road_casing(self):
        city = {'buildings': [record('a', 0), record('b', 5.2)],
                'roads': [{'points': [[5.7, -1], [5.7, 6]], 'width_px': .1, 'class': 'primary'}]}
        self.assertEqual(prepare(city, [-1, -1, 15, 7])['groups'], [])

    def test_water_corridor(self):
        result = prepare({'buildings': [record('a', 0), record('b', 5.2)]}, [-1, -1, 15, 7], [box(5.05, -1, 5.15, 6)])
        self.assertEqual(result['groups'], [])

    def test_obstacle_in_new_bridge(self):
        self.assertIsNone(candidate([box(0, 0, 5, 5), box(5.2, 0, 10.2, 5)], [box(5.05, 1, 5.15, 2)]))

    def test_large_added_area_rejected(self):
        self.assertIsNone(candidate([box(0, 0, 1, 10), box(2, 0, 3, 10)], []))

    def test_group_limit_and_source_uniqueness(self):
        result = prepare({'buildings': [record(str(i), i * 5.2) for i in range(8)]}, [-1, -1, 50, 7])
        ids = [i for group in result['groups'] for i in group['ids']]
        self.assertTrue(result['groups'])
        self.assertEqual(len(ids), len(set(ids)))
        self.assertTrue(all(len(g['ids']) <= 4 for g in result['groups']))

if __name__ == '__main__':
    unittest.main()
