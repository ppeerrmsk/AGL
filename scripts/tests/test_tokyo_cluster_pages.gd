extends "res://scripts/tests/test_tokyo_lod_spatial_pages.gd"
## 保存后验证：未改层严格不变、合并来源唯一、实际字节与每级原生切分守恒。
const ClusterBuild := preload("res://scripts/tests/build_tokyo_cluster_pages.gd")


func run() -> void:
	_check(load("res://scripts/tests/tokyo_cluster_review.gd").can_instantiate(), "cluster native review compiles")
	_check(ClusterBuild.face_count({"outer": [0, 1, 2, 3], "triangles": [0, 1, 2, 0, 2, 3]}, 0) == 10, "full shell count includes roof and all walls")
	_check(ClusterBuild.face_count({"outer": [0, 1, 2, 3], "triangles": [0, 1, 2, 0, 2, 3]}, 2) == 2, "middle relief count does not invent walls")
	for variant: String in ["full", "mid"]:
		var original: Resource = load("res://resources/maps/tokyo_volume_preview/r42_lod_pages/" + variant + "/index.res")
		var catalog: Resource = load("res://resources/maps/tokyo_volume_preview/r44_lod_pages/" + variant + "/index.res")
		_check(catalog.valid() and catalog.source_hash == original.source_hash and catalog.source_count == original.source_count, "cluster catalog keeps source authority and all identities")
		var used: Dictionary = {}
		var changed := 0
		for id in 16:
			var parent: Dictionary = catalog.parents[id]
			var old: Dictionary = original.parents[id]
			if not parent.has("cluster_original"):
				_check(parent == old, "unchanged root and descendants reuse exact R42 metadata")
				continue
			changed += 1
			var source: Resource = ResourceLoader.load(old.building, "", ResourceLoader.CACHE_MODE_IGNORE)
			var root: Resource = ResourceLoader.load(parent.building, "", ResourceLoader.CACHE_MODE_IGNORE)
			var fixed: Resource = ResourceLoader.load(parent.fixed, "", ResourceLoader.CACHE_MODE_IGNORE)
			_check(parent.cluster_original == old.building and parent.fixed == old.fixed and parent.cuts == old.cuts, "original root fixed layer and cut lines retained")
			_check(parent.cluster_plan_sha256 == ClusterBuild.PLAN_HASH, "saved candidate records the checked third cluster plan")
			_check(root.valid() and root.height_hash == source.height_hash and root.source_ids == source.source_ids and root.detail_counts == source.detail_counts, "source height IDs and original detail ledger remain intact")
			_check(root.meshes[1].get("_surfaces") == source.meshes[1].get("_surfaces"), "marked-height native buffers are byte-identical")
			_check(root.meshes[0].get_aabb().position.y == source.meshes[0].get_aabb().position.y and root.meshes[0].get_aabb().end.y == source.meshes[0].get_aabb().end.y, "low-layer native height extent is unchanged")
			_check(root.triangles == source.triangles - int(parent.cluster_faces_saved) and int(parent.cluster_faces_saved) > 0, "actual native index count confirms a reduction")
			var available: Dictionary = {}
			for identity: String in source.source_ids:
				available[identity] = true
			var local_ids: Dictionary = {}
			for group: Dictionary in parent.cluster_groups:
				_check(group.ids.size() >= 2 and group.ids.size() <= 4 and group.height_m > 0 and group.height_m <= 24 and group.detail in [0, 1, 2], "each group has bounded source count and height")
				for identity: String in group.ids:
					_check(available.has(identity) and not used.has(identity), "a group stays wholly inside one root and no source is duplicated")
					used[identity] = true
					local_ids[identity] = true
			_check(local_ids.size() == parent.cluster_sources.size(), "group ledger matches declared source membership")
			for identity: String in parent.cluster_sources:
				_check(local_ids.has(identity), "every declared merged source belongs to a real group")
			var meshes: Array[ArrayMesh] = [root.meshes[0], root.meshes[1], fixed.meshes[0]]
			var descriptor := Spatial.descriptor(meshes)
			_check(descriptor.bytes == parent.bytes and descriptor.boxes == parent.boxes and descriptor.triangles == parent.triangles and root.geometry_bytes + fixed.geometry_bytes == int(parent.bytes), "root actual memory faces and bounds match descriptors")
			var hash_value := (FileAccess.get_sha256(parent.fixed) + ":" + FileAccess.get_sha256(parent.building)).sha256_text()
			var children: Array[Resource] = []
			for entry: Dictionary in parent.children:
				var child := _verify_page(entry, id, variant, hash_value, root.height_hash)
				children.append(child)
				var leaves: Array[Resource] = []
				for leaf_entry: Dictionary in entry.children:
					leaves.append(_verify_page(leaf_entry, id, variant, hash_value, root.height_hash))
				for kind in 3:
					_check(_conserved(child.meshes[kind], leaves, kind), "saved cluster leaves preserve every native oriented corner")
			for kind in 3:
				_check(_conserved(meshes[kind], children, kind), "saved cluster children preserve the new canonical root exactly")
		_check(changed == 5 and not used.is_empty(), "only the five intersecting north roots change")
	print("[Tokyo cluster saved test] pass=", _pass, " fail=", _fail)
