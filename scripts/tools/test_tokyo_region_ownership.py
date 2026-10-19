"""跨区归属的独立小场景反例；只验证数据准备，不代替原生联合渲染。"""
import copy
import math
import unittest
from build_tokyo_region_ownership import build_registry, prepare_region, region_distance
from audit_tokyo_region_ownership import audit


def building(identity='w1',x=5.,y=10.):
    return {'id':identity,'height_m':90.,'height_source':'height','min_height_m':0.,
            'rings':[{'outer':[[x-1,y-1],[x+1,y-1],[x+1,y+1],[x-1,y+1]],'holes':[],
                      'triangles':[[x-1,y-1],[x+1,y-1],[x+1,y+1]]}],
            'parents':[],'parts':[],'render_outline':True}


def cities():
    return {'north':{'rect':[0.,0.,10.,10.],'buildings':[building()]},
            'south':{'rect':[0.,10.,10.,10.],'buildings':[building()]}}


class OwnershipTests(unittest.TestCase):
    def test_explicit_alias_reference_is_resolved_without_source_mutation(self):
        source=cities()
        parent=building('parent',y=9.)
        parent['aliases']=['old-parent']
        child=building('child',y=11.)
        child['parents']=['old-parent']
        for city in source.values():city['buildings']=[copy.deepcopy(parent),copy.deepcopy(child)]
        before=copy.deepcopy(source)
        registry=build_registry(source)
        self.assertEqual(source,before)
        self.assertEqual(registry['families'],[{'members':['child','parent'],'owner':'south'}])

    def test_alias_self_reference_does_not_create_a_building(self):
        source=cities()
        for city in source.values():
            city['buildings'][0].update(aliases=['old-way'],parents=['old-way'])
        registry=build_registry(source)
        self.assertEqual(registry['unique_source_records'],1)
        self.assertEqual(registry['families'],[])

    def test_only_referenced_ambiguous_alias_is_rejected(self):
        source=cities()
        for city in source.values():
            city['buildings']=[building('w1'),building('w2')]
            for row in city['buildings']:row['aliases']=['old-way']
        self.assertEqual(build_registry(source)['unique_source_records'],2)
        for city in source.values():city['buildings'][0]['parents']=['old-way']
        with self.assertRaisesRegex(ValueError,'ambiguous source alias reference'):
            build_registry(source)

    def test_alias_never_overrides_an_existing_canonical_id(self):
        source=cities()
        for city in source.values():
            city['buildings']=[building('w1'),building('w2')]
            city['buildings'][0].update(aliases=['w2'],parents=['w2'])
        self.assertEqual(build_registry(source)['families'][0]['members'],['w1','w2'])

    def test_half_open_boundary_and_single_owner(self):
        registry=build_registry(cities())
        self.assertEqual(registry['assignments']['w1'],{'owner':'south','regions':['north','south']})
        self.assertEqual(registry['shared_records'],1)
        self.assertEqual(registry['unique_source_records'],1)
        self.assertFalse(registry['native_joined_render_verified'])

    def test_stable_order_and_tie(self):
        source=cities()
        source['south']['rect']=source['north']['rect'][:]
        for city in source.values():
            city['buildings']+=[building('w2',y=5.)]
        expected=build_registry(source)
        reordered={name:copy.deepcopy(source[name]) for name in reversed(source)}
        for city in reordered.values():
            city['buildings'].reverse()
        self.assertEqual(build_registry(reordered),expected)
        self.assertEqual(expected['assignments']['w1']['owner'],'north')

    def test_only_derived_footprint_cache_may_differ(self):
        source=cities()
        source['north']['buildings'][0]['footprint_lod']={'0':{'cached':'value'}}
        self.assertEqual(build_registry(source)['shared_records'],1)
        for key,value in [('height_m',91.),('height_source','fallback'),('min_height_m',4.),
                          ('render_outline',False),('roof_volume',{'rise':4.}),('unknown_new_field',True)]:
            altered=copy.deepcopy(source)
            altered['south']['buildings'][0][key]=value
            with self.subTest(key=key),self.assertRaisesRegex(ValueError,'conflicting source'):
                build_registry(altered)

    def test_holes_near_triangles_and_outer_are_strict(self):
        for field,value in [('holes',[[[1,1],[2,1],[1,2]]]),('outer',[[1,1],[2,1],[1,2]]),
                            ('triangles',[[1,1],[2,1],[1,2]])]:
            source=cities()
            source['south']['buildings'][0]['rings'][0][field]=value
            with self.subTest(field=field),self.assertRaisesRegex(ValueError,'conflicting source'):
                build_registry(source)

    def test_family_atomicity_and_complete_owner(self):
        source=cities()
        parent=building('parent',y=9.)
        parent['parts']=['child']
        child=building('child',y=11.)
        # 单向parts也必须成组，不能依赖反向parents恰好存在。
        for city in source.values():
            city['buildings']=[copy.deepcopy(parent),copy.deepcopy(child)]
        registry=build_registry(source)
        self.assertEqual(registry['assignments']['parent']['owner'],'south')
        self.assertEqual(registry['assignments']['child']['owner'],'south')
        source['south']['buildings'].pop()
        registry=build_registry(source)
        self.assertEqual(registry['assignments']['parent']['owner'],'north')
        self.assertEqual(registry['assignments']['child']['owner'],'north')

    def test_split_family_and_missing_reference_rejected(self):
        source=cities()
        source['north']['buildings'][0]['parts']=['child']
        source['south']['buildings']=[building('child')]
        with self.assertRaisesRegex(ValueError,'no region contains complete family'):
            build_registry(source)
        source['south']['buildings']=[]
        with self.assertRaisesRegex(ValueError,'unresolved external family'):
            build_registry(source)

    def test_original_source_retained_without_mutation(self):
        source=cities()
        before=copy.deepcopy(source)
        registry=build_registry(source)
        for name,city in source.items():
            result=prepare_region(city,name,registry,'a'*64)
            self.assertTrue(result.pop('regional_ownership')['joined_only'])
            self.assertEqual(result['buildings'][0].pop('regional_draw_owner'),'south')
            self.assertEqual(result,city)
        self.assertEqual(source,before)

    def test_duplicates_and_prepared_input_rejected(self):
        source=cities()
        source['north']['buildings']*=2
        with self.assertRaisesRegex(ValueError,'duplicate'):
            build_registry(source)
        source=cities()
        source['north']['regional_ownership']={}
        with self.assertRaisesRegex(ValueError,'already prepared'):
            build_registry(source)
        source=cities()
        source['north']['buildings'][0]['regional_draw_owner']='north'
        with self.assertRaisesRegex(ValueError,'prepared source'):
            build_registry(source)

    def test_invalid_rect_and_nonfinite_footprint_rejected(self):
        for rect in [[0,0,0,1],[0,0,1,-1],[0,0,math.nan,1],[0,0,math.inf,1]]:
            with self.subTest(rect=rect),self.assertRaises(ValueError):
                region_distance([0,0],rect)
        for value in [math.nan,math.inf]:
            source=cities()
            for city in source.values():
                city['buildings'][0]['rings'][0]['outer'][0][0]=value
            with self.assertRaises(ValueError):
                build_registry(source)

    def test_outside_extent_uses_nearest_available_region(self):
        source=cities()
        for city in source.values():
            city['buildings']=[building(y=25.)]
        self.assertEqual(build_registry(source)['assignments']['w1']['owner'],'south')

    def test_audit_data_only_not_runtime_ready(self):
        source=cities()
        registry=build_registry(source)
        prepared={region:prepare_region(city,region,registry,'a'*64) for region,city in source.items()}
        result=audit(source,prepared,registry,'a'*64)
        self.assertTrue(result['data_preparation_ok'])
        self.assertFalse(result['simultaneous_render_ready'])
        self.assertEqual(result['planned_nonowner_copies'],{'north':1})

    def test_audit_rejects_changed_source_owner_hash_and_missing_region(self):
        source=cities()
        registry=build_registry(source)
        prepared={region:prepare_region(city,region,registry,'a'*64) for region,city in source.items()}
        for fault in ['height','owner','hash','missing','registry','ground_metadata']:
            altered=copy.deepcopy(prepared)
            altered_registry=copy.deepcopy(registry)
            if fault=='height':
                altered['north']['buildings'][0]['height_m']=80.
            elif fault=='owner':
                altered['north']['buildings'][0]['regional_draw_owner']='north'
            elif fault=='hash':
                altered['north']['regional_ownership']['registry_sha256']='b'*64
            elif fault=='missing':
                del altered['south']
            elif fault=='registry':
                altered_registry['assignments']['w1']['owner']='north'
            else:
                altered['north']['rect'][0]=-1.
            with self.subTest(fault=fault),self.assertRaises(ValueError):
                audit(source,altered,altered_registry,'a'*64)


if __name__=='__main__':
    unittest.main()
