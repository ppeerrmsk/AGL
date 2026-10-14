"""中近景轮廓实验的拒绝门与来源不可变检查。"""
import copy
import unittest
from build_tokyo_shell_lod import prepare, audit, simplify_shell


def building():
    return {'id': 'synthetic', 'regional_draw_owner': 'yokohama', 'height_source': 'fallback',
            'height_m': 12.8, 'rings': [{'outer': [[0,0],[5,.01],[10,0],[10,10],[0,10]], 'holes': [],
                                      'triangles': [[0,0],[5,.01],[0,10],[5,.01],[10,0],[10,10],[5,.01],[10,10],[0,10]]}]}


class ShellTests(unittest.TestCase):
    def test_conservative_reduction(self):
        source = {'buildings': [building()]}
        candidate = prepare(source)
        stats = audit(source, candidate)
        self.assertEqual(stats['near']['shell_roof_faces_saved'], 3)
        self.assertLessEqual(stats['near']['max_error_px'], .35)
        self.assertEqual(len(source['buildings'][0]['rings'][0]['outer']), 5)

    def test_exemptions(self):
        for key, value in [('height_source','height'),('height_m',80),('roof_shape','gabled'),('parents',['p']),
                           ('parts',['p']),('is_part',True),('defer_render',True),('render_outline',False),
                           ('regional_draw_owner','north_coast'),('roof_volume',{'roof':[]})]:
            with self.subTest(key=key):
                raw = building(); raw[key] = value
                self.assertEqual(prepare({'buildings':[raw]}), {'buildings':[raw]})
        for key in ['inset_triangles', 'panel_triangles', 'holes']:
            raw = building(); raw['rings'][0][key] = [[[2,2],[2,3],[3,3]]] if key == 'holes' else [[2,2],[2,3],[3,3]]
            self.assertEqual(prepare({'buildings':[raw]}), {'buildings':[raw]})

    def test_fine_notch_retained(self):
        ring = building()['rings'][0]; ring['outer'][1][1] = 1.
        self.assertIsNone(simplify_shell(ring, 5.))

    def test_invalid_and_scale(self):
        ring = building()['rings'][0]; ring['outer'] = [[0,0],[1,1],[0,1],[1,0]]
        self.assertIsNone(simplify_shell(ring, 5.))
        for value in [0,-1,float('inf'),float('nan')]:
            with self.assertRaises(ValueError): simplify_shell(ring, value)

    def test_corruption_rejected(self):
        source = {'buildings':[building()]}; prepared = prepare(source)
        for kind in ['height','outline','scale','triangles']:
            broken = copy.deepcopy(prepared); raw = broken['buildings'][0]
            if kind == 'height': raw['height_m'] = 100
            if kind == 'outline': raw['shell_lod']['near']['rings'][0]['outer'][0][0] = 20
            if kind == 'scale': raw['shell_lod']['near']['max_scale'] = 1
            if kind == 'triangles': raw['shell_lod']['near']['rings'][0]['triangles'] = [[0,0]]*3
            with self.assertRaises(AssertionError): audit(source, broken)
        with self.assertRaises(ValueError): prepare(prepared)


if __name__ == '__main__': unittest.main()
