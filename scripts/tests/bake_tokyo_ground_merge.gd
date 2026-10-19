extends RefCounted
## R55独立地表候选；保留原打包属性，压紧顶点，不修改原归档。
const Shared := preload("res://scripts/tests/bake_tokyo_shared_roofs.gd")
const Join := preload("res://scripts/experiments/tokyo_packed_mesh_join.gd")
const Builder := preload("res://scripts/tests/build_tokyo_cells.gd")
const Indexed := preload("res://scripts/experiments/tokyo_indexed_mesh.gd")


static func run(directory: String, output: String) -> int:
	if DirAccess.dir_exists_absolute(output):
		return 1
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(directory.path_join("manifest.json")))
	var source_path := "res://resources/maps/tokyo_volume_preview/r34_cells/index.res"
	if FileAccess.get_sha256(source_path) != str(manifest.source_index_sha256) or manifest.cells.size() != 16:
		return 1
	var catalog: Resource = load(source_path).duplicate(true)
	DirAccess.make_dir_recursive_absolute(output)
	var rows: Array[Dictionary] = []
	for entry: Dictionary in manifest.cells:
		var plan_path := directory.path_join(entry.file)
		if FileAccess.get_sha256(plan_path) != str(entry.sha256):
			return 1
		var plan: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(plan_path))
		if FileAccess.get_sha256(plan.source) != str(plan.source_sha256):
			return 1
		var source: Resource = ResourceLoader.load(plan.source, "", ResourceLoader.CACHE_MODE_IGNORE)
		if not source.valid() or source.cell_id != int(plan.cell_id) or source.level != -1 or source.meshes.size() != 1:
			return 1
		var original: ArrayMesh = source.meshes[0]
		for component: Dictionary in plan.components:
			if not _uniform(original, component.sources):
				push_error("[Bench] R55 native component packed attributes differ")
				return 1
		var removed: Dictionary = {}
		for id: float in plan.removed:
			removed[int(id)] = true
		var arrays := Shared._replace(original.surface_get_arrays(0), removed, plan.triangles)
		if arrays.is_empty():
			return 1
		var rewritten := ArrayMesh.new()
		rewritten.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		Shared._retain_material(rewritten, original, 0)
		if not Shared._preserve_packed(rewritten, original, 0, plan.triangles):
			return 1
		var mesh := compact(rewritten)
		if mesh == null or not Join.conserved(rewritten, [mesh]) or Indexed.triangles(mesh) != int(plan.after):
			return 1
		var candidate: Resource = source.duplicate(false)
		var candidate_meshes: Array[ArrayMesh] = [mesh]
		candidate.meshes = candidate_meshes
		candidate.triangles = Indexed.triangles(mesh)
		candidate.geometry_bytes = Builder.mesh_bytes(mesh)
		if not candidate.valid() or candidate.geometry_bytes > source.geometry_bytes:
			push_error("[Bench] R55 candidate grew decoded bytes")
			return 1
		var target := output.path_join("cell_%02d.res" % source.cell_id)
		if ResourceSaver.save(candidate, target, ResourceSaver.FLAG_COMPRESS) != OK:
			return 1
		var saved: Resource = ResourceLoader.load(target, "", ResourceLoader.CACHE_MODE_IGNORE)
		if saved == null or not saved.valid() or not Shared._same_arrays(saved.meshes[0], mesh):
			return 1
		catalog.cells[source.cell_id].fixed = target
		catalog.cells[source.cell_id].fixed_bytes = candidate.geometry_bytes
		catalog.cells[source.cell_id].fixed_triangles = candidate.triangles
		rows.append({"cell": source.cell_id, "source": plan.source, "source_sha256": plan.source_sha256,
			"path": target, "before": source.triangles, "after": candidate.triangles,
			"old_bytes": source.geometry_bytes, "bytes": candidate.geometry_bytes, "sha256": FileAccess.get_sha256(target)})
		print("[R55 ground bake] cell=", source.cell_id, " before=", source.triangles, " after=", candidate.triangles, " bytes=", candidate.geometry_bytes)
	if not catalog.valid() or ResourceSaver.save(catalog, output.path_join("index.res"), ResourceSaver.FLAG_COMPRESS) != OK:
		return 1
	var file := FileAccess.open(output.path_join("manifest.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"rows": rows, "fail": 0, "production_enabled": false, "max_scale": manifest.max_scale,
		"preserve_boundary": manifest.get("preserve_boundary", false)}, "\t"))
	file.close()
	print("[R55 ground bake] COMPLETE cells=16 fail=0")
	return 0


static func _uniform(mesh: ArrayMesh, sources: Array) -> bool:
	var surface: Dictionary = mesh.get("_surfaces")[0]
	var count := int(surface.vertex_count)
	var ps := RenderingServer.mesh_surface_get_format_vertex_stride(surface.format, count)
	var ns := RenderingServer.mesh_surface_get_format_normal_tangent_stride(surface.format, count)
	var cs := RenderingServer.mesh_surface_get_format_attribute_stride(surface.format, count)
	var raw: PackedByteArray = surface.vertex_data
	var attributes: PackedByteArray = surface.attribute_data
	var arrays := mesh.surface_get_arrays(0)
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
	var expected := PackedByteArray()
	for source: float in sources:
		for n in 3:
			var offset := int(source) * 3 + n
			var id := indices[offset] if not indices.is_empty() else offset
			var key := raw.slice(count * ps + id * ns, count * ps + (id+1) * ns)
			key.append_array(attributes.slice(id * cs, (id+1) * cs))
			if expected.is_empty():
				expected = key
			elif key != expected:
				return false
	return not expected.is_empty()


static func compact(mesh: ArrayMesh) -> ArrayMesh:
	if mesh.get_surface_count() == 0:
		return ArrayMesh.new()
	var surface: Dictionary = mesh.get("_surfaces")[0].duplicate()
	var count := int(surface.vertex_count)
	var format := int(surface.format)
	if (format & Mesh.ARRAY_FLAG_COMPRESS_ATTRIBUTES) != 0 or mesh.get_surface_count() != 1:
		return null
	# 仅静态三角面；索引重排不能默默使骨骼/混合形状/内嵌 LOD 失效。
	if mesh.surface_get_primitive_type(0) != Mesh.PRIMITIVE_TRIANGLES or mesh.get_blend_shape_count() != 0 \
			or (format & (Mesh.ARRAY_FORMAT_BONES | Mesh.ARRAY_FORMAT_WEIGHTS)) != 0 or not surface.get("lods", []).is_empty():
		return null
	var ps := RenderingServer.mesh_surface_get_format_vertex_stride(format, count)
	var ns := RenderingServer.mesh_surface_get_format_normal_tangent_stride(format, count)
	var cs := RenderingServer.mesh_surface_get_format_attribute_stride(format, count)
	var raw: PackedByteArray = surface.vertex_data
	var attrs: PackedByteArray = surface.attribute_data
	var arrays := mesh.surface_get_arrays(0)
	var old: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
	var unique: Dictionary = {}
	var positions := PackedByteArray()
	var normals := PackedByteArray()
	var colors := PackedByteArray()
	var indices := PackedInt32Array()
	for offset in (old.size() if not old.is_empty() else count):
		var id := old[offset] if not old.is_empty() else offset
		var position := raw.slice(id * ps, (id+1) * ps)
		var normal := raw.slice(count * ps + id * ns, count * ps + (id+1) * ns)
		var color := attrs.slice(id * cs, (id+1) * cs)
		var key := position.duplicate()
		key.append_array(normal)
		key.append_array(color)
		if not unique.has(key):
			unique[key] = unique.size()
			positions.append_array(position)
			normals.append_array(normal)
			colors.append_array(color)
		indices.append(unique[key])
	positions.append_array(normals)
	format |= Mesh.ARRAY_FORMAT_INDEX
	var stride := RenderingServer.mesh_surface_get_format_index_stride(format, unique.size())
	var packed := PackedByteArray()
	packed.resize(indices.size() * stride)
	for n in indices.size():
		if stride == 2:
			packed.encode_u16(n * stride, indices[n])
		else:
			packed.encode_u32(n * stride, indices[n])
	surface.vertex_data = positions
	surface.attribute_data = colors
	surface.vertex_count = unique.size()
	surface.index_count = indices.size()
	surface.index_data = packed
	surface.format = format
	var result := ArrayMesh.new()
	result.set("_surfaces", [surface])
	return result
