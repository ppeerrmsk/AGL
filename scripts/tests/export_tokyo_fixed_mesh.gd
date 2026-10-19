extends RefCounted
## 原规范固定层只读审计输入：每角 XYZ/normal/RGBA 的 float32，不经 JSON 舍入。


static func run(catalog_path: String, output: String, configuration: String = "lod2_full") -> int:
	if configuration!="lod2_full" and (configuration not in ["lod1_full","lod2_guarded","lod3_full","lod3_guarded"] or FileAccess.get_sha256(catalog_path)!="c0311651371c29025b8db0a8618adb57a2faeb39ab59c4751ee743b3d9c346ca"):
		return 1
	if output.is_empty() or DirAccess.dir_exists_absolute(output):
		return 1
	var catalog: Resource = load(catalog_path)
	if catalog == null or not catalog.valid():
		return 1
	DirAccess.make_dir_recursive_absolute(output)
	var rows: Array[Dictionary] = []
	var total := 0
	for entry: Dictionary in catalog.configurations[configuration]:
		var page: Resource = ResourceLoader.load(entry.path,"",ResourceLoader.CACHE_MODE_IGNORE)
		if page == null or not page.valid() or FileAccess.get_sha256(entry.path) != entry.sha256 \
				or page.stream_identity() != catalog.descriptors[entry.path].canonical_identity:
			return 1
		var path := output.path_join("parent_%02d.bin" % page.parent_id)
		if configuration.ends_with("guarded"):
			path=output.path_join("parent_%02d_%s.bin" % [page.parent_id,entry.sha256.substr(0,16)])
		if FileAccess.file_exists(path):
			return 1
		var file := FileAccess.open(path,FileAccess.WRITE)
		if file == null:
			return 1
		var count := 0
		var mesh: ArrayMesh = page.meshes[2]
		for surface in mesh.get_surface_count():
			var arrays := mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
			var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			if indices.size()%3 != 0 or vertices.size()!=normals.size() or colors.size()!=vertices.size():
				return 1
			var values := PackedFloat32Array()
			values.resize(indices.size()*10)
			for n in indices.size():
				var id := indices[n]
				var p := vertices[id]
				var normal := normals[id]
				var color := colors[id]
				var record := PackedFloat32Array([p.x,p.y,p.z,normal.x,normal.y,normal.z,color.r,color.g,color.b,color.a])
				for k in 10:
					values[n*10+k] = record[k]
			file.store_buffer(values.to_byte_array())
			count += indices.size()/3
		file.close()
		if FileAccess.get_file_as_bytes(path).size()!=count*120 or count!=int(entry.triangles[2]):
			return 1
		rows.append({"parent":page.parent_id,"source":entry.path,"source_sha256":entry.sha256,
			"file":path.get_file(),"sha256":FileAccess.get_sha256(path),"triangles":count})
		total += count
	var manifest := {"schema":1,"record_bytes":120,"format":"little_endian_float32_3x_XYZ_NXYZ_RGBA",
		"catalog_sha256":FileAccess.get_sha256(catalog_path),"configuration":configuration,
		"collision_sha256":catalog.collision_sha256,"rows":rows,"triangles":total,"read_only":true}
	var file := FileAccess.open(output.path_join("manifest.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(manifest,"\t"))
	file.close()
	print("[R73 fixed export] parents=",rows.size()," triangles=",total," original_geometry_unchanged=true")
	return 0
