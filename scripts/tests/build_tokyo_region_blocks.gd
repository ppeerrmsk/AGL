extends RefCounted
## 同源独立样片的街坊版本；不改三片owner或原生运行时目录。
const Far := preload("res://scripts/tests/build_tokyo_far_clusters.gd")
const Auditor := preload("res://scripts/tests/audit_tokyo_region_sample.gd")
const Gameplay := preload("res://scripts/tests/tokyo_region_gameplay_guard.gd")


func run(source_dir: String, plan_dir: String, output: String) -> int:
	if not Far.Builder.valid_sample_output(source_dir, output):
		return 1
	var city_path := source_dir.path_join("city.json")
	var city: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(city_path))
	if city.has("regional_ownership"):
		return 1
	var baseline := OS.get_environment("AGL_TOKYO_REGION_SAMPLE_BASE")
	var index: Resource = ResourceLoader.load(baseline.path_join("index.res"), "", ResourceLoader.CACHE_MODE_IGNORE)
	var hash_value := FileAccess.get_sha256(city_path)
	var ground_hash := FileAccess.get_sha256(source_dir.path_join("ground.json"))
	if index == null or not index.valid() or index.source_hash != hash_value + ":" + ground_hash:
		return 1
	var game_source := Gameplay.read_source()
	if game_source.is_empty():
		return 1
	# 来源跨界楼和合并计划的实际顶点也入保护范围，不能只验名义样片矩形。
	var protected_bounds: Rect2 = index.bounds
	for building: Dictionary in city.buildings:
		for ring: Dictionary in building.rings:
			var expanded := Gameplay.include_points(protected_bounds, ring.get("outer"))
			if expanded.is_empty():
				return 1
			protected_bounds = expanded.bounds
	var plans: Dictionary = {}
	for level in range(1,6):
		var plan: Variant = JSON.parse_string(FileAccess.get_file_as_string(plan_dir.path_join("%d.json" % level)))
		if not plan is Dictionary or not plan.get("groups") is Array:
			return 1
		for group: Dictionary in plan.groups:
			for key: String in ["outer", "triangles"]:
				var expanded := Gameplay.include_points(protected_bounds, group.get(key))
				if expanded.is_empty():
					return 1
				protected_bounds = expanded.bounds
		plans[level] = plan
	var protection := Gameplay.inspect_bounds(protected_bounds, game_source.entries)
	if protection.is_empty() or not protection.standalone_merge_allowed:
		print("[Tokyo region blocks] requires canonical gameplay protection: ", protection)
		return 1
	var converter := Far.new()
	for raw: Dictionary in city.buildings:
		if raw.has("regional_draw_owner"):
			return 1
		converter._records[String(raw.id)] = raw
	DirAccess.make_dir_recursive_absolute(output)
	var rows: Array[Dictionary] = []
	for level in range(1,6):
		var plan_path := plan_dir.path_join("%d.json" % level)
		var plan: Dictionary = plans[level]
		if plan.source_sha256 != hash_value or plan.ground_sha256 != ground_hash or plan.native_costs_sha256 != FileAccess.get_sha256(baseline.path_join("native_costs.json")) \
				or plan.get("source_ownership", "") != "independent_complete_source" or Far.group_limit(plan) == 0 or not is_equal_approx(plan.max_scale, Far.maximum_scale(level)):
			return 1
		var saved_faces := 0
		var accepted := 0
		for entry: Dictionary in index.cells:
			var source: Resource = ResourceLoader.load(entry.levels[level].path, "", ResourceLoader.CACHE_MODE_IGNORE)
			var converted: Dictionary = converter._convert(source, plan, false)
			if converted.is_empty():
				return 1
			var result: Resource = source.duplicate(false)
			var meshes: Array[ArrayMesh] = [converted.mesh, source.meshes[1]]
			result.meshes = meshes
			result.geometry_bytes = 0
			result.triangles = 0
			Far.Builder.finish(result)
			if not result.valid() or result.triangles > source.triangles or result.geometry_bytes > source.geometry_bytes:
				return 1
			var path := output.path_join("cell_%02d_lod_%d.res" % [source.cell_id, level])
			if ResourceSaver.save(result, path, ResourceSaver.FLAG_COMPRESS) != OK:
				return 1
			var loaded: Resource = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
			if loaded == null or not loaded.valid() or loaded.source_ids != source.source_ids or loaded.height_hash != source.height_hash \
					or not Auditor.same_mesh(loaded.meshes[0], result.meshes[0]) or not Auditor.same_mesh(loaded.meshes[1], source.meshes[1]):
				return 1
			accepted += converted.groups.size()
			saved_faces += source.triangles - result.triangles
			rows.append({"cell_id": source.cell_id, "level": level, "source": entry.levels[level].path, "path": path,
				"groups": converted.groups, "before": source.triangles, "after": result.triangles, "plan_sha256": FileAccess.get_sha256(plan_path)})
			entry.levels[level].path = path
			entry.levels[level].bytes = result.geometry_bytes
			entry.levels[level].triangles = result.triangles
		if accepted != plan.groups.size() or saved_faces != int(plan.faces_saved):
			return 1
		print("[Tokyo region blocks] level=",level," groups=",accepted," saved=",saved_faces)
	if not index.valid() or ResourceSaver.save(index, output.path_join("index.res"), ResourceSaver.FLAG_COMPRESS) != OK:
		return 1
	var file := FileAccess.open(output.path_join("manifest.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"rows": rows, "fail": 0, "source_sha256": hash_value, "production_enabled": false, "joined_ready": false,
		"gameplay_protection": protection, "game_source_sha256": game_source.source_sha256, "collision_sha256": game_source.collision_sha256}))
	file.close()
	return 0
