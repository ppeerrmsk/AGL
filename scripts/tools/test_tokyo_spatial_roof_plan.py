"""固定归属反例：重叠父范围、同高来源、后备与跨档漂移。"""
import copy
import struct
import unittest
from build_tokyo_spatial_roof_plan import ownership, partition
from build_tokyo_shared_roofs import FULL_GRID


def fixture():
    return dict(configuration=dict(name="lod5_full"), passed=True, camera_independent=True,
        parents=[dict(parent_id=p, bounds=[0, 0, 20, 20]) for p in range(16)],
        meshes=[dict(id=p, parent_id=p) for p in range(16)],
        native_sources=[dict(mesh=3, surface=0, triangle=0, height=10, points=[[0,0],[8,0],[0,8]])],
        expected=[dict(source_id=42, height=10, points=[[0,0],[8,0],[8,8],[0,8]])],
        triangles=[dict(layer="candidate", game_sources=[42], points=[[0,0],[1,0],[0,1]])])


class SpatialOwnershipTests(unittest.TestCase):
    def test_interaction_grid_keeps_render_height_equivalence(self):
        plan = fixture()
        plan['grid'] = 1 / 2048
        plan['interaction_scope'] = {'schema': 1}
        plan['expected'][0]['height'] = 15.8
        bits = struct.unpack('<I', struct.pack('<f', 15.8))[0]
        plan['native_sources'][0]['height'] = struct.unpack('<f', struct.pack('<I', bits))[0]
        self.assertEqual(ownership(plan)[0]['same_height_area'], 32)
        plan['native_sources'][0]['height'] = struct.unpack('<f', struct.pack('<I', bits + 1))[0]
        self.assertEqual(ownership(plan)[0]['same_height_area'], 0)

    def test_full_grid_actual_decimal_heights_share_render_identity(self):
        # 实图82/83号楼分别为15.8/13.85世界高度；原生屋面已经过float32落盘。
        for height in (15.8, 13.85):
            plan = fixture()
            plan["grid"] = FULL_GRID
            plan["expected"][0]["height"] = height
            plan["native_sources"][0]["height"] = struct.unpack("<f", struct.pack("<f", height))[0]
            original = copy.deepcopy(plan)
            owners = ownership(plan)
            self.assertEqual(owners[0]["parent_id"], 3)
            self.assertEqual(owners[0]["same_height_area"], 32)
            partition(plan, owners)
            self.assertEqual(plan, original)

    def test_full_grid_one_float32_ulp_is_not_same_height(self):
        plan = fixture()
        plan["grid"] = FULL_GRID
        plan["expected"][0]["height"] = 15.8
        bits = struct.unpack("<I", struct.pack("<f", 15.8))[0]
        plan["native_sources"][0]["height"] = struct.unpack("<f", struct.pack("<I", bits + 1))[0]
        self.assertEqual(ownership(plan)[0]["same_height_area"], 0)
        self.assertEqual(ownership(plan)[0]["parent_id"], 0)

    def test_legacy_grid_height_matching_is_unchanged(self):
        for grid in (None, 1 / 2048):
            plan = fixture()
            if grid is not None:
                plan["grid"] = grid
            plan["expected"][0]["height"] = 15.8
            plan["native_sources"][0]["height"] = struct.unpack("<f", struct.pack("<f", 15.8))[0]
            self.assertEqual(ownership(plan)[0]["parent_id"], 0)

    def test_native_overlap_wins_over_small_parent_id(self):
        plan = fixture()
        original = copy.deepcopy(plan)
        owner = ownership(plan)[0]
        self.assertEqual(owner["parent_id"], 3)
        self.assertEqual(owner["same_height_area"], 32)
        self.assertEqual(plan, original)

    def test_height_mismatch_uses_deterministic_fallback(self):
        plan = fixture()
        plan["native_sources"][0]["height"] = 11
        self.assertEqual(ownership(plan)[0]["parent_id"], 0)
        plan["parents"][7]["bounds"] = [0, 0, 8, 8]
        self.assertEqual(ownership(plan)[0]["parent_id"], 7)

    def test_all_source_arrays_reordered(self):
        plan = fixture()
        owner = ownership(plan)
        for key in ("parents", "meshes", "native_sources", "expected"):
            plan[key].reverse()
        self.assertEqual(ownership(plan), owner)

    def test_duplicate_parent_or_district_rejected(self):
        plan = fixture()
        plan["parents"][1] = plan["parents"][0]
        with self.assertRaises(ValueError):
            ownership(plan)
        plan = fixture()
        plan["expected"].append(copy.deepcopy(plan["expected"][0]))
        with self.assertRaises(ValueError):
            ownership(plan)

    def test_cross_lod_height_or_footprint_drift_rejected(self):
        for field, value in (("height", 12), ("points", [[0,0],[9,0],[0,8]])):
            plan = fixture()
            owners = ownership(plan)
            plan["expected"][0][field] = value
            with self.assertRaises(ValueError):
                partition(plan, owners)

    def test_missing_owner_or_unknown_roof_source_rejected(self):
        plan = fixture()
        owners = ownership(plan)
        with self.assertRaises(ValueError):
            partition(plan, [])
        plan["triangles"][0]["game_sources"] = [999]
        with self.assertRaises(ValueError):
            partition(plan, owners)

    def test_shared_roof_is_assigned_exactly_once(self):
        plan = fixture()
        source = copy.deepcopy(plan["expected"][0])
        source["source_id"] = 7
        source["height"] = 8
        plan["expected"].append(source)
        plan["triangles"][0]["game_sources"] = [42, 7]
        owners = ownership(plan)
        parts = partition(plan, owners)
        self.assertEqual([p["parent_id"] for p in parts if p["triangles"]], [0])
        self.assertEqual(sum(len(p["triangles"]) for p in parts), 1)
        self.assertEqual(sum(len(p["expected"]) for p in parts), 2)
        plan["triangles"][0]["game_sources"].reverse()
        self.assertEqual(partition(plan, list(reversed(owners))), parts)

    def test_noncanonical_or_failed_reference_rejected(self):
        for key, value in (("passed", False), ("camera_independent", False), ("configuration", dict(name="lod4_full"))):
            plan = fixture()
            plan[key] = value
            with self.assertRaises(ValueError):
                ownership(plan)


if __name__ == "__main__":
    unittest.main()
