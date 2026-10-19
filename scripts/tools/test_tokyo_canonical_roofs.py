"""规范来源反例；验证换序与镜头无关、错误父包身份拒绝。"""
import copy
import unittest
from build_tokyo_canonical_roofs import canonicalize, digest, generate


def fixture():
    return dict(camera_independent=True, pose=0, configuration=dict(name="fixture"), game_source_sha256="fixture",
        parents=[dict(parent_id=n) for n in range(16)],
        meshes=[dict(id=parent * 2 + kind, path=f"parent{parent:02d}", kind=kind, parent_id=parent,
            precision_guarded=False) for parent in range(16) for kind in (0, 1)],
        native=[dict(mesh=n, surface=0, triangle=0, height=10, points=[[0, 0], [5, 0], [0, 5]],
            colors=[[.5, .5, .5, 1]] * 3, normals=[[0, 1, 0]] * 3) for n in (2, 0)],
        expected=[dict(source_id=2, height=10, points=[[0, 0], [8, 0], [8, 8], [0, 8]])])


class CanonicalTests(unittest.TestCase):
    def test_full_grid_precision_propagates_without_changing_default(self):
        data = fixture()
        self.assertEqual(generate(data)['grid'], 1/2048)
        data['shared_grid'] = 1/1024
        first = generate(data)
        self.assertEqual(first['grid'], 1/1024)
        self.assertTrue(first['passed'])
        data['native'].reverse()
        data['meshes'].reverse()
        self.assertEqual(digest(first), digest(generate(data)))
        data['shared_grid'] = 1/512
        with self.assertRaises(ValueError):
            generate(data)

    def test_reordered_sources_keep_same_owner(self):
        data = fixture()
        old = copy.deepcopy(data)
        first = generate(data)
        self.assertEqual(data, old)
        data["native"].reverse()
        data["meshes"].reverse()
        data["parents"].reverse()
        self.assertEqual(digest(first), digest(generate(data)))
        self.assertTrue(first["passed"])
        self.assertEqual(first["meshes"][0]["path"], "parent00")

    def test_missing_mesh_layer_rejected(self):
        data = fixture()
        data["meshes"].pop()
        with self.assertRaises(ValueError):
            canonicalize(data)

    def test_incomplete_parent_set_rejected(self):
        data = fixture()
        data["parents"].pop()
        with self.assertRaises(ValueError):
            canonicalize(data)

    def test_repeated_parent_rejected(self):
        data = fixture()
        data["parents"][1] = data["parents"][0]
        with self.assertRaises(ValueError):
            canonicalize(data)

    def test_camera_snapshot_rejected(self):
        data = fixture()
        data["camera_independent"] = False
        with self.assertRaises(ValueError):
            canonicalize(data)

    def test_duplicate_mesh_and_face_rejected(self):
        data = fixture()
        data["meshes"].append(copy.deepcopy(data["meshes"][0]))
        with self.assertRaises(ValueError):
            canonicalize(data)
        data = fixture()
        data["native"].append(copy.deepcopy(data["native"][0]))
        with self.assertRaises(ValueError):
            canonicalize(data)


if __name__ == "__main__":
    unittest.main()
