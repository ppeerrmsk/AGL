extends RefCounted
## 当前目录所有配置的楼体投影；不是原city轮廓，仅用于离线审计。
const EXPECTED_SHA := "f4139942c2708b515de82aa32f48c1de1f7cac6fe7b2eab37d9eee9047e2bc85"
const REGION := Rect2(-5660.0, -2700.0, 960.0, 1000.0)


static func region_for_parent(parent: int) -> Rect2:
	if parent == 11:
		return Rect2(-7300,-2700,1640,1000)
	return REGION if parent == 12 else Rect2()


static func projected_overlap(a: Vector3, b: Vector3, c: Vector3, region: Rect2 = REGION) -> bool:
	var x0 := minf(a.x, minf(b.x, c.x))
	var x1 := maxf(a.x, maxf(b.x, c.x))
	var z0 := minf(a.z, minf(b.z, c.z))
	var z1 := maxf(a.z, maxf(b.z, c.z))
	return region.has_area() and x1 > region.position.x and x0 < region.end.x and z1 > region.position.y and z0 < region.end.y


static func corners(mesh: ArrayMesh, region: Rect2 = REGION) -> Dictionary:
	var output := PackedFloat32Array()
	for surface in mesh.get_surface_count():
		if mesh.surface_get_primitive_type(surface) != Mesh.PRIMITIVE_TRIANGLES:
			return {}
		var arrays := mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var raw_indices: Variant = arrays[Mesh.ARRAY_INDEX]
		if raw_indices != null and not raw_indices is PackedInt32Array:
			return {}
		var indices: PackedInt32Array = raw_indices if raw_indices != null else PackedInt32Array()
		if indices.is_empty():
			indices.resize(vertices.size())
			for n in vertices.size():
				indices[n] = n
		if indices.size() % 3 != 0:
			return {}
		for n in range(0, indices.size(), 3):
			for offset in 3:
				if indices[n + offset] < 0 or indices[n + offset] >= vertices.size():
					return {}
			var a := vertices[indices[n]]
			var b := vertices[indices[n + 1]]
			var c := vertices[indices[n + 2]]
			if not a.is_finite() or not b.is_finite() or not c.is_finite():
				return {}
			if not projected_overlap(a, b, c, region):
				continue
			# 投影不覆盖面积的垂直墙面不作实心足迹；保留其它全部三角，不凭楼高猜类型。
			var area2 := (b.x-a.x)*(c.z-a.z)-(b.z-a.z)*(c.x-a.x)
			if area2 == 0.0:
				continue
			output.append_array(PackedFloat32Array([a.x,a.y,a.z,b.x,b.y,b.z,c.x,c.y,c.z]))
	return {"corners": output, "triangles": output.size()/9}


static func run(catalog_path: String, output: String, parent: int = 12) -> int:
	var region := region_for_parent(parent)
	var expected := EXPECTED_SHA
	if OS.get_environment("AGL_TOKYO_RAIL_SOUTHWEST") == "1":
		if parent != 11:
			return 1
		region = Rect2(-8290,-2690,980,980)
		expected = "22a0c03939f61d6f15fc800a7c676d411cbee72c30806dd4f6fe98c92ef5fd30"
	if not region.has_area() or output.is_empty() or DirAccess.dir_exists_absolute(output) or FileAccess.get_sha256(catalog_path) != expected:
		return 1
	var catalog: Resource = ResourceLoader.load(catalog_path, "", ResourceLoader.CACHE_MODE_IGNORE)
	if catalog == null or not catalog.valid():
		return 1
	if DirAccess.make_dir_recursive_absolute(output) != OK:
		return 1
	var rows: Array[Dictionary] = []
	var unique: Dictionary = {}
	for configuration: String in catalog.configurations:
		for entry: Dictionary in catalog.configurations[configuration]:
			if not unique.has(entry.path):
				var page: Resource = ResourceLoader.load(entry.path, "", ResourceLoader.CACHE_MODE_IGNORE)
				if page == null or not page.valid() or FileAccess.get_sha256(entry.path) != entry.sha256 \
					or page.stream_identity() != catalog.descriptors[entry.path].canonical_identity or page.meshes.size() != 3:
					return 1
				var layers: Array[Dictionary] = []
				for layer in 2:
					var decoded := corners(page.meshes[layer],region)
					if decoded.is_empty():
						return 1
					var name := "page_%04d_layer_%d.bin" % [unique.size(), layer]
					var path := output.path_join(name)
					var file := FileAccess.open(path, FileAccess.WRITE)
					if file == null:
						return 1
					file.store_buffer(decoded.corners.to_byte_array())
					file.close()
					if FileAccess.get_file_as_bytes(path).size() != decoded.triangles*36:
						return 1
					layers.append({"layer":layer,"file":name,"sha256":FileAccess.get_sha256(path),"triangles":decoded.triangles})
				var fixed_surfaces: Array = []
				for surface in page.meshes[2].get_surface_count():
					fixed_surfaces.append([page.meshes[2].surface_get_primitive_type(surface),page.meshes[2].surface_get_arrays(surface)])
				unique[entry.path] = {"source":entry.path,"source_sha256":entry.sha256,"layers":layers,
					"fixed_arrays_sha256":var_to_bytes(fixed_surfaces).hex_encode().sha256_text()}
			rows.append({"configuration":configuration,"parent":entry.parent_id,"source":entry.path})
	var result := {"schema":1,"catalog_sha256":expected,"record_bytes":36,
		"format":"little_endian_float32_3x_XYZ","region":[region.position.x,region.position.y,region.end.x,region.end.y],"parent":parent,
		"rows":rows,"sources":unique,"read_only":true,"runtime_integrated":false}
	var manifest := FileAccess.open(output.path_join("manifest.json"), FileAccess.WRITE)
	if manifest == null:
		return 1
	manifest.store_string(JSON.stringify(result,"\t"))
	manifest.close()
	print("[Rail obstacles] rows=",rows.size()," unique=",unique.size())
	return 0
