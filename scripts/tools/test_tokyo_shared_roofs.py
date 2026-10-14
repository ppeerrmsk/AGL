"""共同分区独立反例；只构造内存输入。"""
import copy
import json
import unittest
from build_tokyo_shared_roofs import build, FULL_GRID, GRID
from audit_tokyo_shared_roofs import audit


def roof(points, color=(0.4, 0.5, 0.6, 1), height=10):
    return dict(points=points, colors=[list(color)] * 3, normals=[[0, 1, 0]] * 3,
                height=height, mesh=0, surface=0, triangle=0)


def fixture(native=None, points=None):
    return dict(native=native or [], expected=[dict(source_id=8, height=10,
        points=points or [[0, 0], [10, 0], [10, 10], [0, 10]])])


class SharedRoofsTests(unittest.TestCase):
    def test_full_grid_float32_intersections(self):
        data = fixture([roof([[0.0001, 0], [9.7001, 9.9], [0, 9.7]])])
        for source in data['native'] + data['expected']:
            source['points'] = [[x-13100, y-9950] for x,y in source['points']]
        with self.assertRaisesRegex(ValueError, 'non-float32'):
            build(data)
        plan = build(data, grid=FULL_GRID)
        self.assertTrue(plan['passed'], plan['failures']+plan['audits'])
        self.assertEqual(plan['grid'], FULL_GRID)
        self.assertEqual(plan['max_displacement'], 0.001)
        self.assertTrue(audit(plan, {'triangles': copy.deepcopy(plan['triangles'])})['passed'])

    def test_precision_is_explicit_and_bounded(self):
        self.assertEqual(build(fixture())['grid'], GRID)
        for invalid in (0, 1/512, float('nan'), 'full'):
            with self.assertRaisesRegex(ValueError, 'precision'):
                build(fixture(), grid=invalid)

    def test_saved_float32_height_identity_rejects_one_ulp_drift(self):
        plan = build(fixture(), grid=FULL_GRID)
        saved = {'triangles': copy.deepcopy(plan['triangles'])}
        self.assertTrue(audit(plan, saved)['passed'])
        saved['triangles'][0]['height'] += 2**-20
        self.assertFalse(audit(plan, saved)['passed'])

    def check_plan(self, data):
        before = copy.deepcopy(data)
        result = build(data)
        self.assertTrue(result["passed"], result["failures"] + result["audits"])
        self.assertEqual(data, before)
        self.assertTrue(all(r["overlap"] == 0 for r in result["audits"]))
        self.assertEqual(json.dumps(result, sort_keys=True), json.dumps(build(data), sort_keys=True))
        return result

    def test_interaction_saved_render_height_is_independent_of_xy_grid(self):
        import struct
        data = fixture()
        data['expected'][0]['height'] = 15.8
        plan = build(data, grid=GRID)
        plan['interaction_scope'] = {'schema': 1}
        saved = {'triangles': copy.deepcopy(plan['triangles'])}
        for triangle in saved['triangles']:
            triangle['height'] = struct.unpack('<f', struct.pack('<f', triangle['height']))[0]
        self.assertTrue(audit(plan, saved)['passed'])
        bits = struct.unpack('<I', struct.pack('<f', saved['triangles'][0]['height']))[0]
        saved['triangles'][0]['height'] = struct.unpack('<f', struct.pack('<I', bits + 1))[0]
        self.assertFalse(audit(plan, saved)['passed'])

    def test_empty_native(self):
        self.check_plan(fixture())

    def test_partial_native_and_disjoint(self):
        self.check_plan(fixture([roof([[0, 0], [8, 0], [0, 8]]), roof([[20, 0], [21, 0], [20, 1]])]))

    def test_duplicate_native_same_attributes(self):
        a = roof([[0, 0], [8, 0], [0, 8]])
        result = self.check_plan(fixture([a, copy.deepcopy(a)]))
        self.assertTrue(any(t["native_sources"] == [0, 1] for t in result["triangles"]))

    def test_duplicate_native_color_conflict(self):
        data = fixture([roof([[0, 0], [8, 0], [0, 8]]), roof([[0, 0], [8, 0], [0, 8]], (1, 0, 0, 1))])
        result = build(data)
        self.assertFalse(result["passed"])
        self.assertTrue(any(f["kind"] == "native_attribute_conflict" for f in result["failures"]))

    def test_nonflat_attributes_fail(self):
        a = roof([[0, 0], [8, 0], [0, 8]])
        a["colors"] = [[1, 0, 0, 1], [0, 1, 0, 1], [0, 0, 1, 1]]
        with self.assertRaisesRegex(ValueError, "non-flat"):
            build(fixture([a]))

    def test_concave_self_touch(self):
        self.check_plan(fixture(points=[[0, 0], [10, 0], [10, 4], [4, 4], [4, 10], [0, 10]]))
        result = self.check_plan(fixture(points=[[0, 0], [10, 10], [0, 10], [10, 0]]))
        self.assertEqual(result["warnings"][0]["kind"], "self_touch_linework")

    def test_native_island_leaves_candidate_hole(self):
        self.check_plan(fixture([roof([[2, 2], [8, 2], [5, 8]])]))

    def test_large_coordinate_intersections(self):
        data = fixture([roof([[0.0001, 0], [9.7001, 9.9], [0, 9.7]])])
        for source in data["native"] + data["expected"]:
            source["points"] = [[x - 6000, y - 1100] for x, y in source["points"]]
        self.check_plan(data)

    def test_independent_saved_audit_rejects_missing_and_duplicate(self):
        plan = self.check_plan(fixture([roof([[2, 2], [8, 2], [5, 8]])]))
        saved = dict(triangles=copy.deepcopy(plan["triangles"]))
        self.assertTrue(audit(plan, saved)["passed"])
        saved["triangles"].append(copy.deepcopy(saved["triangles"][0]))
        self.assertFalse(audit(plan, saved)["passed"])
        saved["triangles"] = saved["triangles"][1:-1]
        self.assertFalse(audit(plan, saved)["passed"])


if __name__ == "__main__":
    unittest.main()
