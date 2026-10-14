extends RefCounted
## 仅拼接已验证原生数组，先形成完整联合观察候选；不放宽全局流送预算。
const Index := preload("res://scripts/rendering/tokyo_cell_index.gd")
const Cell := preload("res://scripts/rendering/tokyo_cell_archive.gd")
const Builder := preload("res://scripts/tests/build_tokyo_cells.gd")
const OUT := "res://bench/results/tokyo_r26b_cells"
const DEST := "res://resources/maps/tokyo_volume_preview/r26b_cells"
var _fail := 0
var _out := OUT
var _dest := DEST
var _repaired := false


static func pair_entries(entries: Array) -> Array:
	var remaining := entries.duplicate()
	var pairs: Array = []
	while not remaining.is_empty():
		assert(remaining.size() >= 2)
		var chosen := Vector2i(0, 1)
		var best := Vector2(INF, INF)
		for a in remaining.size():
			for b in range(a + 1, remaining.size()):
				var left: Rect2 = remaining[a].bounds
				var right: Rect2 = remaining[b].bounds
				var merged := left.merge(right)
				var score := Vector2(merged.get_area() - left.get_area() - right.get_area(), merged.size.x + merged.size.y)
				if score.x < best.x or (score.x == best.x and score.y < best.y):
					best = score
					chosen = Vector2i(a, b)
		pairs.append([remaining[chosen.x], remaining[chosen.y]])
		remaining.remove_at(chosen.y)
		remaining.remove_at(chosen.x)
	return pairs


static func merge_meshes(meshes: Array) -> ArrayMesh:
	# 使用4.7原生资源序列化接口保留已量化法线。Dummy后端的update_vertex_region为空操作，不能用于无头烘焙。
	var vertex_data := PackedByteArray()
	var normal_data := PackedByteArray()
	var attribute_data := PackedByteArray()
	var descriptor: Dictionary = {}
	var count := 0
	for mesh: ArrayMesh in meshes:
		if mesh.get_surface_count() == 0:
			continue
		assert(mesh.get_surface_count() == 1)
		var surfaces: Array = mesh.get("_surfaces")
		assert(surfaces.size() == 1 and mesh.get_blend_shape_count() == 0)
		var data: Dictionary = surfaces[0]
		var format := int(data.format)
		assert((format & Mesh.ARRAY_FLAG_COMPRESS_ATTRIBUTES) == 0, "AABB-relative compressed vertices cannot be concatenated")
		assert(int(data.get("index_count", 0)) == 0 and data.get("skin_data", PackedByteArray()).is_empty() and data.get("lods", []).is_empty())
		var source_count := int(data.vertex_count)
		var vertex_stride := RenderingServer.mesh_surface_get_format_vertex_stride(format, source_count)
		var normal_stride := RenderingServer.mesh_surface_get_format_normal_tangent_stride(format, source_count)
		var buffer: PackedByteArray = data.vertex_data
		assert(buffer.size() == source_count * (vertex_stride + normal_stride))
		vertex_data.append_array(buffer.slice(0, source_count * vertex_stride))
		normal_data.append_array(buffer.slice(source_count * vertex_stride))
		attribute_data.append_array(data.get("attribute_data", PackedByteArray()))
		if descriptor.is_empty():
			descriptor = data.duplicate()
		else:
			assert(int(descriptor.format) == format and descriptor.primitive == data.primitive)
			descriptor.aabb = (descriptor.aabb as AABB).merge(data.aabb)
		count += source_count
	var result := ArrayMesh.new()
	if count > 0:
		vertex_data.append_array(normal_data)
		descriptor.vertex_data = vertex_data
		descriptor.attribute_data = attribute_data
		descriptor.vertex_count = count
		result.set("_surfaces", [descriptor])
		assert(result.get_surface_count() == 1 and result.surface_get_array_len(0) == count)
	return result


func run() -> void:
	_repaired = OS.get_environment("AGL_TOKYO_CELLS_VARIANT") == "yokohama_joined_spatial"
	if _repaired:
		_out = "res://bench/results/tokyo_r29_cells"
		_dest = "res://resources/maps/tokyo_volume_preview/r29_cells"
	var source_root := OS.get_environment("AGL_TOKYO_JOINED_ROOT")
	if source_root.is_empty():
		_fail = 1
		return
	var registry_path := source_root.path_join("ownership.json")
	var digest := FileAccess.get_sha256(registry_path)
	var result := Index.new()
	var all_pairs: Array = []
	var raw_by_region: Dictionary = {}
	var indices: Dictionary = {}
	for region: String in ["yokohama", "north_coast"]:
		var path := "res://resources/maps/tokyo_volume_preview/r25_%s_cells/index.res" % region
		var index: Resource = load(path)
		var source_dir := source_root.path_join(region)
		if index == null or not index.valid(digest) or index.regional_id != region \
				or index.source_hash != FileAccess.get_sha256(source_dir.path_join("city.json")) + ":" + FileAccess.get_sha256(source_dir.path_join("ground.json")):
			_fail = 1
			print("[Tokyo joined] rejected paired source fail=1")
			return
		indices[region] = index
		result.joined_sources[region] = {"index": path, "source_hash": index.source_hash, "registry_hash": digest}
		result.coverage_rects.append(index.bounds)
		result.bounds = index.bounds if result.coverage_rects.size() == 1 else result.bounds.merge(index.bounds)
		var city: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(source_dir.path_join("city.json")))
		var records: Dictionary = {}
		for raw: Dictionary in city.buildings:
			records[raw.id] = raw
		raw_by_region[region] = records
		var pairs: Array = pair_entries(index.cells)
		if _repaired and region == "north_coast":
			pairs = load("res://scripts/experiments/tokyo_cell_pairing.gd").pair_entries(index.cells)
		for pair: Array in pairs:
			all_pairs.append({"region": region, "parts": pair})
	result.source_hash = (indices.yokohama.source_hash + ":" + indices.north_coast.source_hash + ":" + digest).sha256_text()
	if _repaired:
		# 阴影深度保持原来的完整来源包络，配对变化不扰动深度量化。
		result.shadow_cells = load("res://resources/maps/tokyo_volume_preview/r26b_cells/index.res").cells.duplicate(true)
	DirAccess.make_dir_recursive_absolute(_out)
	var report := {"cells": [], "fail": 0, "registry_hash": digest, "coverage_rects": result.coverage_rects}
	var seen: Dictionary = {}
	for id in all_pairs.size():
		var pair: Dictionary = all_pairs[id]
		var index: Resource = indices[pair.region]
		var parts: Array = pair.parts
		var bounds: Rect2 = parts[0].bounds.merge(parts[1].bounds)
		var content: Rect2 = parts[0].content_bounds.merge(parts[1].content_bounds)
		var source_ids := PackedStringArray()
		var height_lines := PackedStringArray()
		var nonowners := 0
		for part: Dictionary in parts:
			var original: Resource = ResourceLoader.load(part.levels[0].path, "", ResourceLoader.CACHE_MODE_IGNORE)
			for identity: String in original.source_ids:
				if identity in index.regional_nonowner_ids:
					nonowners += 1
					continue
				assert(not seen.has(identity), "joint source owner must be globally unique")
				seen[identity] = true
				source_ids.append(identity)
		source_ids.sort()
		for identity: String in source_ids:
			var raw: Dictionary = raw_by_region[pair.region][identity]
			height_lines.append("%s:%.6f:%.6f" % [identity, raw.height_m, raw.min_height_m])
		var height_hash := "\n".join(height_lines).sha256_text()
		var fixed := Cell.new()
		fixed.cell_id = id
		fixed.bounds = bounds
		fixed.meshes.append(merge_meshes([load(parts[0].fixed).meshes[0], load(parts[1].fixed).meshes[0]]))
		if _repaired:
			fixed.meshes[0] = load("res://scripts/experiments/tokyo_indexed_mesh.gd").pack(fixed.meshes[0])
		Builder.finish(fixed)
		var stem := "cell_%02d" % id
		_save(fixed, stem + "_fixed.res")
		var max_height := maxf(parts[0].max_height_px, parts[1].max_height_px)
		var entry := {"id": id, "bounds": bounds, "content_bounds": content, "fixed": _dest.path_join(stem + "_fixed.res"),
			"fixed_bytes": fixed.geometry_bytes, "fixed_triangles": fixed.triangles, "source_count": source_ids.size(),
			"max_height_px": max_height, "visibility_margin": max_height * 1.6 + 8.0, "levels": [],
			"region": pair.region, "part_ids": [parts[0].id, parts[1].id], "removed_nonowner_records": nonowners}
		for slot in 7:
			var cell := Cell.new()
			cell.cell_id = id
			cell.level = 4 if slot == 6 else slot
			cell.bounds = content
			cell.source_ids = source_ids
			cell.height_hash = height_hash
			cell.detail_counts = PackedInt32Array([0, 0, 0, -nonowners])
			var packages: Array = []
			for part: Dictionary in parts:
				var package: Resource = ResourceLoader.load(part.mid.path if slot == 6 else part.levels[slot].path, "", ResourceLoader.CACHE_MODE_IGNORE)
				packages.append(package)
				for detail in 4:
					cell.detail_counts[detail] += package.detail_counts[detail]
			assert(cell.detail_counts[3] >= 0)
			for kind in 2:
				cell.meshes.append(merge_meshes([packages[0].meshes[kind], packages[1].meshes[kind]]))
			if packages[0].precision_original != null or packages[1].precision_original != null:
				var originals: Array = []
				for package: Resource in packages:
					originals.append(package.precision_original if package.precision_original != null else package.meshes[0])
				cell.precision_original = merge_meshes(originals)
				cell.precision_max_scale = Index.LEVELS.CUTS[slot] * 1.08
				cell.precision_triangles = cell.precision_original.surface_get_array_len(0) / 3
			if _repaired:
				var indexed: GDScript = load("res://scripts/experiments/tokyo_indexed_mesh.gd")
				for kind in cell.meshes.size():
					cell.meshes[kind] = indexed.pack(cell.meshes[kind])
				if cell.precision_original != null:
					cell.precision_original = indexed.pack(cell.precision_original)
			Builder.finish(cell)
			var filename := stem + ("_mid_4.res" if slot == 6 else "_lod_%d.res" % slot)
			_save(cell, filename)
			var descriptor := {"path": _dest.path_join(filename), "bytes": cell.geometry_bytes, "triangles": cell.triangles,
				"counts": Array(cell.detail_counts), "height_hash": height_hash}
			if slot == 6:
				entry["mid"] = descriptor
			else:
				entry.levels.append(descriptor)
		result.cells.append(entry)
		report.cells.append(entry)
		print("[Tokyo joined] cell=", id, " source=", source_ids.size(), " parts=", entry.part_ids)
	result.source_count = seen.size()
	assert(result.source_count == 69775 and result.valid())
	_save(result, "index.res")
	report["source_count"] = result.source_count
	report.fail = _fail
	var file := FileAccess.open(_out.path_join("build_report.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	print("[Tokyo joined] sources=", result.source_count, " cells=", result.cells.size(), " fail=", _fail)


func _save(resource: Resource, filename: String) -> void:
	if ResourceSaver.save(resource, _out.path_join(filename), ResourceSaver.FLAG_COMPRESS) != OK:
		_fail += 1
