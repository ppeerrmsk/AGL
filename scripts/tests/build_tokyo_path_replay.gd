extends RefCounted
## 复用正式线带与裁切工序，输出原始/候选属性；不自动替换地图。
static func run(input: Dictionary) -> int:
	var contract := preload("res://scripts/rendering/tokyo_hlod_manifest.gd")
	var output: String = input.get("output", "")
	var minor: bool = input.get("minor_roads", false)
	if not output.is_absolute_path() or DirAccess.dir_exists_absolute(output): return 1
	for key: String in ["original", "candidate"]:
		if not contract.binding(input.get(key)) or FileAccess.get_sha256(input[key].path) != input[key].sha256: return 1
	var index: Resource = null
	if input.has("cell_index"):
		if not contract.binding(input.cell_index) or FileAccess.get_sha256(input.cell_index.path) != input.cell_index.sha256: return 1
		index = load(input.cell_index.path)
		if index == null or not index.valid(): return 1
		if minor:
			if not index.source_hash.begins_with(input.original.sha256 + ":"): return 1
		elif not index.source_hash.ends_with(":" + input.original.sha256): return 1
	if DirAccess.make_dir_recursive_absolute(output) != OK: return 1
	var result := {}
	for key: String in ["original", "candidate"]:
		if key == "original" and input.has("reuse_original"):
			var binding: Dictionary = input.reuse_original
			if index == null or not contract.binding(binding) or FileAccess.get_sha256(binding.path) != binding.sha256: return 1
			var prior: Variant = JSON.parse_string(FileAccess.get_file_as_string(binding.path))
			if not prior is Dictionary or not prior.get("original") is Dictionary or prior.original.get("cell_index_sha256") != input.cell_index.sha256: return 1
			for part: Dictionary in prior.original.parts:
				if not contract.binding(part) or FileAccess.get_sha256(part.path) != part.sha256: return 1
			result[key] = prior.original
			continue
		var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(input[key].path))
		var builder := preload("res://scripts/experiments/volume_mesh_factory.gd").new()
		var factory := preload("res://scripts/experiments/tokyo_volume_preview_factory.gd")
		if minor:
			if index == null: return 1
			for road: Dictionary in data.roads:
				if road.class in ["motorway","motorway_link","trunk","trunk_link","primary","primary_link","secondary","secondary_link"]: continue
				factory._path_ribbon(builder,road,"surface",factory._points(road.points),road.width_px,0.38,Color("6e7772"))
		else:
			for path: Dictionary in data.paths:
				factory._ribbon(builder, factory._points(path.points), 0.8, 0.22, Color("9c9d8d"))
		var mesh: ArrayMesh = builder.mesh()
		if index != null:
			var builders: Array = []
			var rectangles: Array[Rect2] = []
			for cell: Dictionary in index.cells:
				builders.append(preload("res://scripts/experiments/volume_mesh_factory.gd").new())
				rectangles.append(cell.bounds)
			preload("res://scripts/tests/build_tokyo_cells.gd").split_fixed(mesh,index.bounds,builders,rectangles)
			var parts: Array = []
			var total_faces := 0
			for id in builders.size():
				var saved: ArrayMesh = builders[id].mesh()
				var file := output.path_join(key + "_%02d.attributes" % id)
				if preload("res://scripts/tests/tokyo_residential_preview.gd").export_attributes(saved,file) != 0: return 1
				var faces := FileAccess.get_file_as_bytes(file).size()/120
				total_faces += faces
				parts.append({"path":file,"sha256":FileAccess.get_sha256(file),"faces":faces})
			result[key] = {"parts":parts,"faces":total_faces,"cell_index_sha256":input.cell_index.sha256}
			continue
		var arrays := mesh.surface_get_arrays(0)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var clipped := preload("res://scripts/experiments/volume_mesh_factory.gd").new()
		var clip := preload("res://scripts/tests/build_tokyo_cells.gd")
		for start in range(0, vertices.size(), 3):
			var polygon := vertices.slice(start, start + 3)
			polygon = clip.clip_polygon(polygon, 0, data.bounds[0], true)
			polygon = clip.clip_polygon(polygon, 0, data.bounds[2], false)
			polygon = clip.clip_polygon(polygon, 2, data.bounds[1], true)
			polygon = clip.clip_polygon(polygon, 2, data.bounds[3], false)
			for i in range(1, polygon.size()-1):
				var a := polygon[0]
				var b := polygon[i]
				var c := polygon[i+1]
				if (b-a).cross(c-a).y < 0: clipped.triangle(a,c,b,Color("9c9d8d"))
				else: clipped.triangle(a,b,c,Color("9c9d8d"))
		var saved: ArrayMesh = clipped.mesh()
		var file := output.path_join(key + ".attributes")
		if preload("res://scripts/tests/tokyo_residential_preview.gd").export_attributes(saved,file) != 0: return 1
		result[key] = {"path":file,"sha256":FileAccess.get_sha256(file),"faces":FileAccess.get_file_as_bytes(file).size()/120}
	result["runtime_integrated"] = false
	var report := FileAccess.open(output.path_join("report.json"),FileAccess.WRITE)
	if report == null: return 1
	report.store_string(JSON.stringify(result,"\t"));report.close()
	print("[Path replay] ", JSON.stringify(result))
	return 0
