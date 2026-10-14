extends RefCounted
## 离线只读：导出规范父包的原生水平屋面，保留float32位值供精确覆盖证明。
const OUT := "res://bench/results/tokyo_r43_roof_input"
var _fail := 0


func run() -> void:
	assert(not DirAccess.dir_exists_absolute(OUT), "roof audit must not overwrite earlier evidence")
	DirAccess.make_dir_recursive_absolute(OUT)
	var manifest := {"schema": 1, "stride": 44, "packages": []}
	for variant: String in ["full", "mid"]:
		var catalog: Resource = load("res://resources/maps/tokyo_volume_preview/r42_lod_pages/" + variant + "/index.res")
		assert(catalog.valid())
		for parent: Dictionary in catalog.parents:
			var source: Resource = ResourceLoader.load(parent.building, "", ResourceLoader.CACHE_MODE_IGNORE)
			assert(source.valid())
			var entry := {"variant": variant, "parent_id": parent.parent_id, "source": parent.building,
				"sha256": FileAccess.get_sha256(parent.building), "height_hash": source.height_hash, "layers": []}
			for kind in 2:
				var data := _roofs(source.meshes[kind])
				var name_value := "%s_%02d_%d.bin" % [variant, parent.parent_id, kind]
				var file := FileAccess.open(OUT.path_join(name_value), FileAccess.WRITE)
				assert(file != null)
				file.store_buffer(data)
				file.close()
				entry.layers.append({"file": name_value, "sha256": FileAccess.get_sha256(OUT.path_join(name_value)), "count": data.size() / 44})
			manifest.packages.append(entry)
	var file := FileAccess.open(OUT.path_join("manifest.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(manifest, "\t"))
	file.close()
	print("[Tokyo roof export] packages=", manifest.packages.size(), " fail=", _fail)


static func _roofs(mesh: ArrayMesh) -> PackedByteArray:
	var result := PackedByteArray()
	if mesh.get_surface_count() == 0:
		return result
	var arrays := mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var indices := PackedInt32Array()
	if arrays[Mesh.ARRAY_INDEX] != null:
		indices = arrays[Mesh.ARRAY_INDEX]
	var count := indices.size() if not indices.is_empty() else vertices.size()
	for offset in range(0, count, 3):
		var ids := PackedInt32Array()
		for n in 3:
			ids.append(indices[offset + n] if not indices.is_empty() else offset + n)
		var p: Vector3 = vertices[ids[0]]
		var normal: Vector3 = normals[ids[0]]
		if p.y != vertices[ids[1]].y or p.y != vertices[ids[2]].y or normal != normals[ids[1]] or normal != normals[ids[2]]:
			continue
		# 非水平/反向/无效面拒绝进入屋顶裁决；不把接近高度视为同平面。
		if not p.is_finite() or not vertices[ids[1]].is_finite() or not vertices[ids[2]].is_finite() or not normal.is_finite() or normal.y < 0.99:
			continue
		var record := PackedByteArray()
		record.resize(44)
		record.encode_u32(0, offset / 3)
		record.encode_float(4, p.y)
		record.encode_float(8, normal.x)
		record.encode_float(12, normal.y)
		record.encode_float(16, normal.z)
		for n in 3:
			record.encode_float(20 + n * 8, vertices[ids[n]].x)
			record.encode_float(24 + n * 8, vertices[ids[n]].z)
		result.append_array(record)
	return result
