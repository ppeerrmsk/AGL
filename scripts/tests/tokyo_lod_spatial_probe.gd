extends RefCounted
## 只读原生覆盖面定位；不据此自动删面，不改渲染资源。


static func capture(overlay: Node, label: String) -> void:
	var samples := [Vector2(543.5, 776.5), Vector2(486.5, 786.5)]
	var hits: Array[Dictionary] = []
	var camera_inverse: Transform3D = overlay._camera.global_transform.affine_inverse()
	for slot in overlay._slots.size():
		for kind in 3:
			var node: MeshInstance3D = overlay._slots[slot][kind]
			var mesh: ArrayMesh = node.mesh
			if not node.visible or mesh == null or mesh.get_surface_count() == 0:
				continue
			var arrays := mesh.surface_get_arrays(0)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var indices := PackedInt32Array()
			if arrays[Mesh.ARRAY_INDEX] != null:
				indices = arrays[Mesh.ARRAY_INDEX]
			var projected := PackedVector2Array()
			for point: Vector3 in vertices:
				projected.append(overlay._camera.unproject_position(overlay._city.to_global(point)))
			var count := indices.size() if not indices.is_empty() else vertices.size()
			for offset in range(0, count, 3):
				var ids := PackedInt32Array()
				for n in 3:
					ids.append(indices[offset + n] if not indices.is_empty() else offset + n)
				for sample: Vector2 in samples:
					if not Geometry2D.point_is_inside_triangle(sample, projected[ids[0]], projected[ids[1]], projected[ids[2]]):
						continue
					var row := {"sample": [sample.x, sample.y], "slot": slot, "layer": kind, "face": offset / 3, "vertices": [], "normals": [], "colors": [], "depth": []}
					for id in ids:
						var p: Vector3 = vertices[id]
						var normal: Vector3 = arrays[Mesh.ARRAY_NORMAL][id]
						var color: Color = arrays[Mesh.ARRAY_COLOR][id]
						row.vertices.append([p.x, p.y, p.z])
						row.normals.append([normal.x, normal.y, normal.z])
						row.colors.append([color.r, color.g, color.b, color.a])
						row.depth.append(-(camera_inverse * overlay._city.to_global(p)).z)
					hits.append(row)
	var file := FileAccess.open("res://bench/results/tokyo_r42_probe_" + label + ".json", FileAccess.WRITE)
	file.store_string(JSON.stringify(hits, "\t"))
	file.close()
