extends RefCounted
## 真正已绑定的网格来源与属性导出；只写独立制作输入，不修改原网格。


static func run(map: Node, entries: Array, source_ids: Array[int], pose: int, out: String) -> void:
	assert(not FileAccess.file_exists(out), "R50 source export cannot overwrite evidence")
	var expected: Array = []
	var height_keys: Dictionary = {}
	for n in entries.size():
		var entry: Dictionary = entries[n]
		var height := float(entry.max_real_h) * CombatUnit.PIXELS_PER_METER
		height_keys[roundi(height * 1000)] = true
		var points: Array = []
		for p: Vector2 in entry.footprint:
			points.append([p.x,p.y])
		expected.append({"source_id": source_ids[n], "height": height, "points": points})
	var meshes: Array = []
	var roofs: Array = []
	for batch_key: Variant in map._batches:
		var batch: Dictionary = map._batches[batch_key]
		for kind in 2:
			var node: MeshInstance3D = batch.nodes[kind]
			if not node.visible:
				continue
			var mesh: ArrayMesh = node.mesh
			var mesh_id := meshes.size()
			var descriptor := {"id": mesh_id, "batch": str(batch_key), "path": str(batch.path), "kind": kind,
				"mesh_path": mesh.resource_path, "page": bool(batch.page), "precision_guarded": bool(batch.precision_guarded),
				"source_sha256": FileAccess.get_sha256(str(batch.path)), "surfaces": []}
			for surface in mesh.get_surface_count():
				var arrays := mesh.surface_get_arrays(surface)
				descriptor.surfaces.append(var_to_bytes(arrays).hex_encode().sha256_text())
				var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
				var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
				var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
				var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
				var count := indices.size() if not indices.is_empty() else vertices.size()
				for offset in range(0, count, 3):
					var ids := PackedInt32Array()
					for n in 3:
						ids.append(indices[offset+n] if not indices.is_empty() else offset+n)
					var height: float = vertices[ids[0]].y
					if not height_keys.has(roundi(height * 1000)):
						continue
					var valid := true
					for id in ids:
						valid = valid and vertices[id].y == height and normals[id].y > 0.99
					if not valid:
						continue
					var points: Array = []
					var tint: Array = []
					var normal_data: Array = []
					for id in ids:
						points.append([vertices[id].x, vertices[id].z])
						tint.append([colors[id].r,colors[id].g,colors[id].b,colors[id].a])
						normal_data.append([normals[id].x,normals[id].y,normals[id].z])
					roofs.append({"mesh": mesh_id, "surface": surface, "triangle": offset / 3, "height": height,
						"points": points, "colors": tint, "normals": normal_data})
			meshes.append(descriptor)
	var file := FileAccess.open(out, FileAccess.WRITE)
	assert(file != null)
	file.store_string(JSON.stringify({"schema": 1, "pose": pose, "expected": expected, "meshes": meshes, "native": roofs,
		"state": map.debug_state(), "collision_sha256": var_to_bytes(BuildingRenderer._cache_entries).hex_encode().sha256_text()}))
	file.close()
	print("[Tokyo gameplay source] pose=", pose, " meshes=", meshes.size(), " roofs=", roofs.size())
