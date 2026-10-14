import copy
import unittest
from shapely.geometry import Polygon, box
from build_tokyo_block_lod import prepare, contract, protected_road, shape_acceptable, road_components
from test_tokyo_cluster_lod import record


def fixture(count=16):
    items=[]
    for i in range(count):
        r=record(str(i),6*(i%8))
        for p in r['rings'][0]['outer']:
            p[1]+=6*(i//8)
        items.append(r)
    return dict(buildings=items),dict(bounds=[-10,-10,100,100],surfaces=[]),{str(i):dict(parent=8,faces=2,detail=2) for i in range(count)}


class BlockTests(unittest.TestCase):
    def test_solid_street_preserves_anchors_and_source(self):
        city,ground,costs=fixture(96)
        for cost in costs.values(): cost.update(faces=10,detail=1)
        city['buildings'][0]['height_source']='height'
        city['roads']=[{'class':'residential','points':[[23,-3],[23,95]],'width_px':1}]
        ground['surfaces']=[dict(kind='park',triangles=[[35,-3],[36,-3],[36,95],[35,-3],[36,95],[35,95]])]
        frozen=copy.deepcopy(city)
        plan=prepare(city,ground,costs,5.,'street_solid',[-5,-5,90,90])
        self.assertGreater(plan['faces_saved'],0)
        ids=[i for group in plan['groups'] for i in group['ids']]
        self.assertNotIn('0',ids)
        self.assertEqual(len(ids),len(set(ids)))
        for group in plan['groups']:
            shape=Polygon(group['outer'])
            self.assertFalse(shape.bounds[0]<23<shape.bounds[2])
            self.assertEqual(shape.intersection(box(35,-3,36,95)).area,0)
        city['buildings'].reverse()
        self.assertEqual(prepare(city,ground,costs,5.,'street_solid',[-5,-5,90,90]),plan)
        city['buildings'].reverse()
        self.assertEqual(city,frozen)
        with self.assertRaises(ValueError): prepare(city,ground,costs,.7776,'street_solid',[-5,-5,90,90])

    def test_near_street_shape_filter_only_restricts_new_groups(self):
        a=contract('district24street')
        b=contract('district24street45')
        self.assertEqual({k:v for k,v in a.items() if k!='profile'},
                         {k:v for k,v in b.items() if k not in ('profile','shape_policy')})
        city,ground,costs=fixture(48)
        for cost in costs.values(): cost.update(faces=10,detail=1)
        frozen=copy.deepcopy(city)
        plan=prepare(city,ground,costs,5.,'district24street45',[-5,-5,90,90])
        self.assertGreater(plan['faces_saved'],0)
        self.assertTrue(all(shape_acceptable(Polygon(g['outer']),b['shape_policy']) for g in plan['groups']))
        self.assertEqual(city,frozen)
        for scale in [.1944,.3888,.7776,1.5552]:
            with self.assertRaises(ValueError): prepare(city,ground,costs,scale,'district24street45',[-5,-5,90,90])

    def test_near_street_keeps_existing_near_contract(self):
        baseline = contract('district24wide')
        candidate = contract('district24street')
        self.assertEqual({k:v for k,v in candidate.items() if k not in ('profile','grouping','link_gap')},
                         {k:v for k,v in baseline.items() if k != 'profile'})
        city, ground, costs = fixture(2)
        for cost in costs.values(): cost.update(faces=10,detail=1)
        for raw in city['buildings']:
            for p in raw['rings'][0]['outer']: p[0] += 93
        ground['bounds'] = [-10,-10,120,100]
        bounds = [-5,-5,115,90]
        frozen = copy.deepcopy(city)
        self.assertEqual(prepare(city,ground,costs,5.,'district24wide',bounds)['groups'],[])
        result = prepare(city,ground,costs,5.,'district24street',bounds)
        self.assertEqual(result['faces_saved'],10)
        self.assertEqual(result['merged_sources'],2)
        self.assertEqual(city,frozen)
        city['buildings'].reverse()
        self.assertEqual(prepare(city,ground,costs,5.,'district24street',bounds),result)
        for scale in [.1944,.3888,.7776,1.5552]:
            with self.assertRaises(ValueError): prepare(city,ground,costs,scale,'district24street',bounds)
        city['roads'] = [{'class':'residential','points':[[98,-3],[98,20]],'width_px':.1}]
        self.assertEqual(prepare(city,ground,costs,5.,'district24street',bounds)['groups'],[])

    def test_street_components_cross_grid_not_road(self):
        from shapely import STRtree
        city, ground, costs = fixture(2)
        for raw in city['buildings']:
            for point in raw['rings'][0]['outer']:
                point[0] += 123
        eligible = {raw['id']: (raw, Polygon(raw['rings'][0]['outer']), costs[raw['id']]) for raw in city['buildings']}
        self.assertEqual(road_components(eligible, [], STRtree([]), 12.), [['0', '1']])
        blocked = [box(127.5,-5,128.5,10)]
        self.assertEqual(road_components(eligible, blocked, STRtree(blocked), 12.), [['0'], ['1']])
        costs['1']['parent'] += 1
        self.assertEqual(road_components(eligible, [], STRtree([]), 12.), [['0'], ['1']])

    def test_street_profiles_keep_source_and_structural_anchors(self):
        for profile in ['street6', 'street8']:
            city, ground, costs = fixture(96)
            city['buildings'][0]['height_source'] = 'height'
            city['roads'] = [{'class':'residential', 'points':[[11.5,-3],[11.5,90]], 'width_px':.1}]
            ground['surfaces'] = [dict(kind='water', triangles=[[23,-3],[24,-3],[24,90],[23,-3],[24,90],[23,90]])]
            original = copy.deepcopy(city)
            for scale in [.1944,.3888]:
                plan = prepare(city,ground,costs,scale,profile,[-5,-5,90,90])
                self.assertGreater(plan['faces_saved'],0)
                self.assertNotIn('0',{i for g in plan['groups'] for i in g['ids']})
                used = [i for g in plan['groups'] for i in g['ids']]
                self.assertEqual(len(used),len(set(used)))
                polys = [Polygon(g['outer']) for g in plan['groups']]
                self.assertTrue(all(not (p.bounds[0]<11.5<p.bounds[2]) for p in polys))
                self.assertTrue(all(p.intersection(box(23,-3,24,90)).area == 0 for p in polys))
                self.assertTrue(all(a.intersection(b).area==0 for n,a in enumerate(polys) for b in polys[n+1:]))
                self.assertTrue(all(4<=len(g['outer'])<=8 and len(g['ids'])<=96 for g in plan['groups']))
                self.assertTrue(all(g['height_m']==next(r['height_m'] for r in city['buildings'] if r['id']==i) for g in plan['groups'] for i in g['ids']))
                city['buildings'].reverse()
                self.assertEqual(prepare(city,ground,costs,scale,profile,[-5,-5,90,90]),plan)
                city['buildings'].reverse()
            self.assertEqual(city,original)
            for scale in [.7776,5.,0.,float('nan')]:
                with self.assertRaises(ValueError):
                    prepare(city,ground,costs,scale,profile,[-5,-5,90,90])

    def test_shape_policy_rejects_spikes_not_source(self):
        policy=dict(min_angle_degrees=45,max_aspect=4,min_edge_px=.5)
        self.assertTrue(shape_acceptable(box(0,0,8,3),policy))
        self.assertFalse(shape_acceptable(box(0,0,30,2),policy))
        self.assertFalse(shape_acceptable(Polygon([(0,0),(20,0),(1,2),(0,2)]),policy))
        self.assertFalse(shape_acceptable(Polygon([(0,0),(.1,0),(4,1),(0,4)]),policy))
        city,ground,costs=fixture()
        for r in city['buildings']:r.pop('regional_draw_owner',None)
        original=copy.deepcopy(city)
        result=prepare(city,ground,costs,.3888,'blocks',[-5,-5,90,90],region=None,shape_policy=policy)
        self.assertGreater(result['faces_saved'],0)
        self.assertTrue(all(shape_acceptable(Polygon(g['outer']),policy) for g in result['groups']))
        self.assertEqual(city,original)
        self.assertEqual(prepare(city,ground,costs,.3888,'blocks',[-5,-5,90,90],region=None,shape_policy=policy),result)
        for bad in [dict(policy,min_angle_degrees=float('nan')),dict(policy,max_aspect=0),dict(policy,min_edge_px=True),{}]:
            with self.assertRaises(ValueError):prepare(city,ground,costs,.3888,'blocks',[-5,-5,90,90],region=None,shape_policy=bad)
        with self.assertRaises(ValueError):prepare(city,ground,costs,.3888,'blocks',[-5,-5,90,90],shape_policy=policy)

    def test_standalone_does_not_reinterpret_joined_ownership(self):
        city, ground, costs = fixture()
        with self.assertRaises(ValueError):
            prepare(city,ground,costs,.3888,'blocks',[-5,-5,90,90],region=None)
        for r in city['buildings']:
            r.pop('regional_draw_owner',None)
        original=copy.deepcopy(city)
        result=prepare(city,ground,costs,.3888,'blocks',[-5,-5,90,90],region=None)
        self.assertGreater(result['faces_saved'],0)
        self.assertEqual(city,original)
        self.assertEqual(prepare(city,ground,costs,.3888,'blocks',[-5,-5,90,90])['groups'],[])

    def test_wide_far_preserves_anchors_and_scale(self):
        for profile in ['far8wide','far12wide']:
            for scale in [.1944,.3888]:
                city,ground,costs=fixture(96)
                city['buildings'][0]['height_source']='height'
                city['roads']=[{'class':'residential','points':[[11.5,-3],[11.5,90]],'width_px':.1}]
                ground['surfaces']=[dict(kind='water',triangles=[[23,-3],[24,-3],[24,90],[23,-3],[24,90],[23,90]])]
                before=copy.deepcopy(city)
                plan=prepare(city,ground,costs,scale,profile,[-5,-5,90,90])
                self.assertGreater(plan['faces_saved'],0)
                self.assertEqual(city,before)
                self.assertEqual(plan['closure_steps'],4)
                self.assertNotIn('0',{i for g in plan['groups'] for i in g['ids']})
                polygons=[Polygon(g['outer']) for g in plan['groups']]
                self.assertTrue(all(4<=len(g['outer'])<=8 for g in plan['groups']))
                self.assertTrue(all(not(p.bounds[0]<11.5<p.bounds[2]) and p.intersection(box(23,-3,24,90)).area==0 for p in polygons))
                self.assertTrue(all(a.intersection(b).area==0 for n,a in enumerate(polygons) for b in polygons[n+1:]))
                originals={r['id']:r for r in city['buildings']}
                self.assertTrue(all(originals[i]['height_m']==g['height_m'] for g in plan['groups'] for i in g['ids']))
                city['buildings'].reverse()
                self.assertEqual(prepare(city,ground,costs,scale,profile,[-5,-5,90,90]),plan)
            for invalid in [.7776,1.5552,5.,float('nan')]:
                with self.assertRaises(ValueError):prepare(city,ground,costs,invalid,profile,[-5,-5,90,90])
        self.assertEqual(contract('far6').get('closure_steps',1),1)

    def test_middle_contract_preserves_anchors_and_rejects_other_scales(self):
        for profile in ['mid4','mid6']:
            city,ground,costs=fixture(32)
            for cost in costs.values():cost.update(faces=10,detail=1)
            city['buildings'][0]['height_source']='height'
            city['roads']=[{'class':'residential','points':[[11.5,-3],[11.5,40]],'width_px':.1}]
            ground['surfaces']=[dict(kind='water',triangles=[[23,-3],[24,-3],[24,40],[23,-3],[24,40],[23,40]])]
            original=copy.deepcopy(city)
            result=prepare(city,ground,costs,1.5552,profile,[-5,-5,90,90])
            self.assertGreater(result['faces_saved'],0)
            self.assertNotIn('0',{i for g in result['groups'] for i in g['ids']})
            polys=[Polygon(g['outer']) for g in result['groups']]
            self.assertTrue(all(not (p.bounds[0]<11.5<p.bounds[2]) for p in polys))
            self.assertTrue(all(p.intersection(box(23,-3,24,40)).area==0 for p in polys))
            self.assertTrue(all(a.intersection(b).area==0 for n,a in enumerate(polys) for b in polys[n+1:]))
            city['buildings'].reverse()
            self.assertEqual(prepare(city,ground,costs,1.5552,profile,[-5,-5,90,90]),result)
            city['buildings'].reverse()
            self.assertEqual(city,original)
            for scale in [.1944,.3888,.7776,5.,0.,float('nan')]:
                with self.assertRaises(ValueError):prepare(city,ground,costs,scale,profile,[-5,-5,90,90])
        for profile in ['blocks','district16','far6']:
            with self.assertRaises(ValueError):prepare(city,ground,costs,1.5552,profile,[-5,-5,90,90])

    def test_far_district_scale_height_and_structural_contract(self):
        for profile in ['far4','far6']:
            city,ground,costs=fixture(64)
            simple=prepare(city,ground,costs,.3888,profile,[-5,-5,90,90])
            legacy=prepare(city,ground,costs,.3888,'blocks',[-5,-5,90,90])
            self.assertEqual(max(len(g['ids']) for g in simple['groups']),64)
            self.assertGreater(simple['faces_saved'],legacy['faces_saved'])
            city['buildings'][0]['height_source']='height'
            city['roads']=[{'class':'residential','points':[[11.5,-3],[11.5,70]],'width_px':.1}]
            ground['surfaces']=[dict(kind='green',triangles=[[23,-3],[24,-3],[24,70],[23,-3],[24,70],[23,70]])]
            original=copy.deepcopy(city)
            for scale in [.1944,.3888]:
                result=prepare(city,ground,costs,scale,profile,[-5,-5,90,90])
                self.assertGreater(result['faces_saved'],0)
                self.assertNotIn('0',{i for g in result['groups'] for i in g['ids']})
                polys=[Polygon(g['outer']) for g in result['groups']]
                self.assertTrue(all(not (p.bounds[0]<11.5<p.bounds[2]) for p in polys))
                self.assertTrue(all(p.intersection(box(23,-3,24,70)).area==0 for p in polys))
                self.assertTrue(all(a.intersection(b).area==0 for n,a in enumerate(polys) for b in polys[n+1:]))
                city['buildings'].reverse()
                self.assertEqual(prepare(city,ground,costs,scale,profile,[-5,-5,90,90]),result)
                city['buildings'].reverse()
            self.assertEqual(city,original)
            for scale in [.7776,5.,0.,float('nan')]:
                with self.assertRaises(ValueError):prepare(city,ground,costs,scale,profile,[-5,-5,90,90])

    def test_district_finest_saves_more_without_changing_old_contract(self):
        city,ground,costs=fixture(32)
        for n, raw in enumerate(city['buildings']):
            for point in raw['rings'][0]['outer']:
                point[0] += n%8
                point[1] += n//8
        for cost in costs.values():
            cost.update(faces=10,detail=1)
        old=prepare(city,ground,costs,5.0,'blocks',[-5,-5,90,90])
        original=copy.deepcopy(city)
        for profile,error in [('district6',6.),('district8',8.),('district12',12.),('district16',16.)]:
            result=prepare(city,ground,costs,5.0,profile,[-5,-5,90,90])
            self.assertGreater(result['faces_saved'],old['faces_saved'])
            self.assertEqual(result['occupied_error_px'],error)
            self.assertEqual(result['max_group'],48)
            city['buildings'].reverse()
            self.assertEqual(prepare(city,ground,costs,5.0,profile,[-5,-5,90,90]),result)
            city['buildings'].reverse()
            with self.assertRaises(ValueError):
                prepare(city,ground,costs,.7776,profile,[-5,-5,90,90])
        self.assertEqual(city,original)
        self.assertEqual(contract('blocks')['occupied_error_px'],3.)

    def test_district_keeps_structural_anchors_and_known_height(self):
        for profile in ['district6','district8','district12','district16','district20','district24','district20wide','district24wide','district24street']:
            city,ground,costs=fixture(32)
            for cost in costs.values():
                cost.update(faces=10,detail=1)
            city['buildings'][0]['height_source']='height'
            city['roads']=[{'class':'residential','points':[[11.5,-3],[11.5,40]],'width_px':.1}]
            ground['surfaces']=[dict(kind='water',triangles=[[23,-3],[24,-3],[24,40],[23,-3],[24,40],[23,40]])]
            result=prepare(city,ground,costs,5.0,profile,[-5,-5,90,90])
            self.assertGreater(result['faces_saved'],0)
            self.assertNotIn('0',{i for g in result['groups'] for i in g['ids']})
            polys=[Polygon(g['outer']) for g in result['groups']]
            self.assertTrue(all(not (p.bounds[0]<11.5<p.bounds[2]) for p in polys))
            self.assertTrue(all(p.intersection(box(23,-3,24,40)).area==0 for p in polys))
            self.assertTrue(all(a.intersection(b).area==0 for n,a in enumerate(polys) for b in polys[n+1:]))

    def test_finest_candidate_uses_tighter_world_error(self):
        city,ground,costs=fixture(32)
        for value in costs.values():
            value.update(faces=10,detail=1)
        close=prepare(city,ground,costs,5.0,'blocks',[-5,-5,90,90])
        middle=prepare(city,ground,costs,.7776,'blocks',[-5,-5,90,90])
        self.assertEqual(close['max_scale'],5.0)
        self.assertLessEqual(close['faces_saved'],middle['faces_saved'])
        self.assertEqual(close['occupied_error_px'],3.0)

    def test_stronger_district_fills_small_gap_not_height_or_road(self):
        city,ground,costs=fixture(2)
        for point in city['buildings'][1]['rings'][0]['outer']:point[0]+=3.5
        for cost in costs.values():cost.update(faces=10,detail=1)
        self.assertEqual(prepare(city,ground,costs,5.,'district8',[-5,-5,90,90])['groups'],[])
        for profile in ['district12','district16','district20','district24','district20wide','district24wide']:
            result=prepare(city,ground,costs,5.,profile,[-5,-5,90,90])
            self.assertEqual(result['merged_sources'],2)
            self.assertEqual(result['faces_saved'],10)
            self.assertEqual(result['groups'][0]['height_m'],city['buildings'][0]['height_m'])
            if profile in ['district20','district24','district20wide','district24wide']:
                self.assertEqual(result['min_vertices'],4)
                self.assertGreaterEqual(len(result['groups'][0]['outer']),4)
            for scale in [.1944,.3888,.7776]:
                with self.assertRaises(ValueError):prepare(city,ground,costs,scale,profile,[-5,-5,90,90])
            guarded=copy.deepcopy(city)
            guarded['roads']=[{'class':'residential','points':[[7,-3],[7,10]],'width_px':.1}]
            self.assertEqual(prepare(guarded,ground,costs,5.,profile,[-5,-5,90,90])['groups'],[])
            guarded=copy.deepcopy(city)
            guarded['buildings'][1]['height_m']+=3.2
            self.assertEqual(prepare(guarded,ground,costs,5.,profile,[-5,-5,90,90])['groups'],[])

    def plan(self, city, ground, costs, profile='blocks'):
        return prepare(city,ground,costs,.3888,profile,[-5,-5,90,90])

    def test_wide_near_deterministic_and_four_corners(self):
        for profile in ['district20wide','district24wide']:
            city,ground,costs=fixture(48)
            for cost in costs.values():cost.update(faces=10,detail=1)
            original=copy.deepcopy(city)
            result=prepare(city,ground,costs,5.,profile,[-5,-5,90,90])
            self.assertEqual(result['closure_steps'],4)
            self.assertGreater(result['faces_saved'],0)
            self.assertEqual(city,original)
            city['buildings'].reverse()
            self.assertEqual(prepare(city,ground,costs,5.,profile,[-5,-5,90,90]),result)
            self.assertTrue(all(4<=len(g['outer'])<=8 for g in result['groups']))
            self.assertEqual(contract('district16').get('closure_steps',1),1)

    def test_larger_than_eight_and_deterministic(self):
        city,ground,costs=fixture(32)
        original=copy.deepcopy(city)
        result=self.plan(city,ground,costs)
        self.assertTrue(any(len(g['ids'])>8 for g in result['groups']))
        self.assertEqual(result['merged_sources'],32)
        self.assertEqual(result['faces_saved'],62)
        self.assertEqual(city,original)
        city['buildings'].reverse()
        self.assertEqual(self.plan(city,ground,costs),result)

    def test_profiles_and_legacy_are_distinct(self):
        self.assertEqual(contract('gentle')['max_group'],16)
        self.assertEqual(contract('blocks')['max_group'],32)
        with self.assertRaises(ValueError):contract('legacy')
        self.assertTrue(protected_road(dict(class_='service'),'blocks'))
        self.assertFalse(protected_road({'class':'service','width_px':.1},'blocks'))
        self.assertTrue(protected_road({'class':'service','width_px':2},'blocks'))

    def test_main_road_splits_block(self):
        city,ground,costs=fixture()
        city['roads']=[{'class':'primary','points':[[11.5,-3],[11.5,40]],'width_px':.1}]
        result=self.plan(city,ground,costs)
        for group in result['groups']:
            poly=Polygon(group['outer'])
            self.assertFalse(poly.bounds[0]<11.5<poly.bounds[2])

    def test_minor_lane_is_explicit_difference(self):
        city,ground,costs=fixture()
        city['roads']=[{'class':'service','points':[[11.5,-3],[11.5,40]],'width_px':.1}]
        gentle=self.plan(city,ground,costs,'gentle')
        blocks=self.plan(city,ground,costs)
        self.assertGreater(blocks['faces_saved'],gentle['faces_saved'])

    def test_water_green_and_park_preserved(self):
        for kind in ['water','green','park']:
            city,ground,costs=fixture()
            ground['surfaces']=[dict(kind=kind,triangles=[[11,-3],[12,-3],[12,40],[11,-3],[12,40],[11,40]])]
            result=self.plan(city,ground,costs)
            self.assertTrue(all(Polygon(g['outer']).intersection(box(11,-3,12,40)).area==0 for g in result['groups']))

    def test_height_parent_and_known_sources(self):
        city,ground,costs=fixture()
        city['buildings'][0]['height_source']='height'
        city['buildings'][1]['height_m']=12.8
        costs['2']['parent']=9
        result=self.plan(city,ground,costs)
        self.assertFalse({'0','1','2'} & {i for g in result['groups'] for i in g['ids']})

    def test_invalid_scale_bounds_costs_fail(self):
        city,ground,costs=fixture()
        for scale in [0,float('nan'),2]:
            with self.assertRaises(ValueError):prepare(city,ground,costs,scale,'blocks',[-5,-5,90,90])
        with self.assertRaises(ValueError):prepare(city,ground,costs,.3888,'blocks',[0,0,0,1])
        costs['0']['faces']=-1
        with self.assertRaises(ValueError):self.plan(city,ground,costs)

    def test_unique_sources_and_disjoint_proxies(self):
        city,ground,costs=fixture(96)
        result=self.plan(city,ground,costs)
        ids=[i for g in result['groups'] for i in g['ids']]
        self.assertEqual(len(ids),len(set(ids)))
        polys=[Polygon(g['outer']) for g in result['groups']]
        self.assertTrue(all(a.intersection(b).area==0 for n,a in enumerate(polys) for b in polys[n+1:]))

    def test_near_scale_uses_actual_wall_costs_and_tighter_world_error(self):
        city,ground,costs=fixture(32)
        for value in costs.values():
            value.update(faces=10,detail=1)
        result=prepare(city,ground,costs,.7776,'blocks',[-5,-5,90,90])
        self.assertGreater(result['faces_saved'],0)
        self.assertEqual(result['max_scale'],.7776)
        raw={r['id']:Polygon(r['rings'][0]['outer']) for r in city['buildings']}
        from shapely import unary_union
        for group in result['groups']:
            original=unary_union([raw[i] for i in group['ids']])
            merged=Polygon(group['outer'])
            self.assertTrue(original.covered_by(merged.buffer(3/.7776)))
            self.assertTrue(merged.covered_by(original.buffer(3/.7776)))
            faces=len(group['triangles'])//3+2*len(group['outer'])
            self.assertEqual(group['faces_saved'],10*len(group['ids'])-faces)


if __name__=='__main__':unittest.main()
