extends RefCounted
## 磁盘候选独立核对：未改顶点/属性、保留索引以及新面必须逐项对应制作计划。
const Baker := preload("res://scripts/tests/bake_tokyo_shared_roofs.gd")


static func run(input: String, path: String, export_path: String = "", full_precision: bool = false) -> int:
	var plan: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(input))
	full_precision=full_precision or plan.get("grid")==1.0/1024.0
	var bundle: Resource = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
	if bundle == null or not plan.passed or bundle.plan_sha256 != FileAccess.get_sha256(input):
		return 1
	var checked := 0
	var output: Array = []
	for mesh_index in bundle.descriptors.size():
		var descriptor: Dictionary = bundle.descriptors[mesh_index]
		var resource: Resource = load(str(descriptor.path))
		var original: ArrayMesh = resource.precision_original if bool(descriptor.precision_guarded) and int(descriptor.kind) == 0 else resource.meshes[int(descriptor.kind)]
		var saved: ArrayMesh = bundle.meshes[mesh_index]
		for surface in original.get_surface_count():
			var before := original.surface_get_arrays(surface)
			var after := saved.surface_get_arrays(surface)
			for channel in [Mesh.ARRAY_VERTEX, Mesh.ARRAY_NORMAL, Mesh.ARRAY_TANGENT, Mesh.ARRAY_COLOR]:
				if before[channel] != null and after[channel].slice(0, before[channel].size()).to_byte_array() != before[channel].to_byte_array():
					push_error("Shared audit: original channel drift %d mesh=%d" % [channel, mesh_index])
					return 1
			var removed: Dictionary = {}
			for source: Dictionary in plan.native_sources:
				if int(source.mesh) == int(descriptor.id) and int(source.surface) == surface:
					removed[int(source.triangle)] = true
			var indices: PackedInt32Array = before[Mesh.ARRAY_INDEX] if before[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
			var saved_indices: PackedInt32Array = after[Mesh.ARRAY_INDEX] if after[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
			var count: int = indices.size() if not indices.is_empty() else before[Mesh.ARRAY_VERTEX].size()
			var cursor := 0
			for offset in range(0, count, 3):
				if removed.has(offset / 3):
					continue
				for n in 3:
					if saved_indices[cursor] != (indices[offset+n] if not indices.is_empty() else offset+n):
						return 1
					cursor += 1
			var vertex_cursor: int = before[Mesh.ARRAY_VERTEX].size()
			for triangle: Dictionary in plan.triangles:
				if triangle.layer != "native":
					continue
				var source: Dictionary = plan.native_sources[int(triangle.owner)]
				if int(source.mesh) != int(descriptor.id) or int(source.surface) != surface:
					continue
				var points := Baker._points(triangle)
				var actual: Array = []
				for point: Vector3 in points:
					if after[Mesh.ARRAY_VERTEX][vertex_cursor] != point or saved_indices[cursor] != vertex_cursor:
						return 1
					var p: Vector3 = after[Mesh.ARRAY_VERTEX][vertex_cursor]
					actual.append([p.x, p.z])
					var color := Color(triangle.color[0], triangle.color[1], triangle.color[2], triangle.color[3])
					var normal := Vector3(triangle.normal[0], triangle.normal[1], triangle.normal[2])
					if after[Mesh.ARRAY_COLOR][vertex_cursor] != color or after[Mesh.ARRAY_NORMAL][vertex_cursor] != normal:
						push_error("Shared audit: new native attributes drift")
						return 1
					vertex_cursor += 1
					cursor += 1
				var record := triangle.duplicate()
				record.points = actual
				if full_precision:
					record.height=after[Mesh.ARRAY_VERTEX][vertex_cursor-1].y
				output.append(record)
				checked += 1
			if cursor != saved_indices.size() or vertex_cursor != after[Mesh.ARRAY_VERTEX].size():
				return 1
	if not Baker._same_arrays(Baker._addition(plan), bundle.addition):
		return 1
	# 新补面位于一次合批的末尾；导出的是磁盘资源解码后的顶点。
	var arrays: Array = bundle.addition.surface_get_arrays(0)
	var candidate: Array = plan.triangles.filter(func(t: Dictionary) -> bool: return t.layer == "candidate")
	var start: int = arrays[Mesh.ARRAY_VERTEX].size() - candidate.size() * 3
	for triangle: Dictionary in candidate:
		var actual: Array = []
		for n in 3:
			var point: Vector3 = arrays[Mesh.ARRAY_VERTEX][start]
			actual.append([point.x, point.z])
			start += 1
		var record := triangle.duplicate()
		record.points = actual
		if full_precision:
			record.height=arrays[Mesh.ARRAY_VERTEX][start-1].y
		output.append(record)
	var destination := export_path if not export_path.is_empty() else "res://bench/results/r50_saved_roofs_%02d.json" % int(plan.pose)
	if not export_path.is_empty() and FileAccess.file_exists(destination):
		push_error("Shared audit refuses to overwrite prior evidence")
		return 1
	var file := FileAccess.open(destination, FileAccess.WRITE)
	file.store_string(JSON.stringify({"pose": plan.pose, "triangles": output, "plan_sha256": bundle.plan_sha256},"",true,full_precision))
	file.close()
	print("[Tokyo shared audit] pose=", plan.pose, " native_faces=", checked, " untouched_arrays=PASS saved_coordinates=PASS")
	return 0
