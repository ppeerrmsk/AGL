extends RefCounted
## 显式离线构建：整栋/分部连通组唯一归属；地表三角精确裁格，所有资源仅输出 bench/results。
const Factory := preload("res://scripts/experiments/tokyo_volume_preview_factory.gd")
const Geometry := preload("res://scripts/experiments/volume_mesh_factory.gd")
const Dome := preload("res://scripts/experiments/tokyo_dome_roof.gd")
const Duplicates := preload("res://scripts/experiments/tokyo_duplicate_outline.gd")
const Regional := preload("res://scripts/experiments/tokyo_regional_ownership.gd")
const Cell := preload("res://scripts/rendering/tokyo_cell_archive.gd")
const Index := preload("res://scripts/rendering/tokyo_cell_index.gd")
const OUT := "res://bench/results/tokyo_r6_cells"
const DEST := "res://resources/maps/tokyo_volume_preview/r6_cells"
var _fail := 0
var _relief_lod := false
var _mid_relief := false
var _adaptive := false
var _coverage := false
var _batch_guard := false
var _cut_steps := 10
var _domes := false
var _dome_round_only := false
var _dedup := false
var _footprint_lod := false
var _out := OUT
var _dest := DEST
var _regional: Dictionary = {}


func run() -> void:
	if OS.get_environment("AGL_TOKYO_EXTENSION_CATALOG_BUILD") == "1":
		_fail = load("res://scripts/tests/build_tokyo_extension_catalog.gd").new().run()
		return
	if OS.get_environment("AGL_TOKYO_PATH_LOD_BUILD") == "1":
		_fail = load("res://scripts/tests/build_tokyo_path_lod.gd").new().run(OS.get_environment("AGL_TOKYO_GUARDED_BLOCK_ROOT"),OS.get_environment("AGL_TOKYO_GUARDED_BLOCK_OUT"))
		return
	if OS.get_environment("AGL_TOKYO_GUARDED_BLOCK_BUILD") == "1":
		_fail = load("res://scripts/tests/build_tokyo_guarded_blocks.gd").new().run()
		return
	if OS.get_environment("AGL_TOKYO_REGIONAL_CATALOG_BUILD") == "1":
		_fail = load("res://scripts/tests/build_tokyo_regional_catalog.gd").new().run()
		return
	if OS.get_environment("AGL_TOKYO_BOUNDARY_TRANSFER_BUILD") == "1":
		_fail = load("res://scripts/tests/build_tokyo_boundary_transfer.gd").new().run()
		return
	if OS.get_environment("AGL_TOKYO_REGIONAL_BLOCKS_BUILD") == "1":
		_fail = load("res://scripts/tests/build_tokyo_owned_region_blocks.gd").new().run()
		return
	if OS.get_environment("AGL_TOKYO_REGIONAL_NATIVE_BUILD") == "1":
		_fail = load("res://scripts/tests/build_tokyo_regional_native.gd").new().run()
		return
	if OS.get_environment("AGL_TOKYO_REGION_SURFACE_BUILD") == "1":
		_fail = load("res://scripts/tests/build_tokyo_region_surface.gd").new().run(OS.get_environment("AGL_TOKYO_REGION_SAMPLE_INDEX"), OS.get_environment("AGL_TOKYO_REGION_SAMPLE_OUT"), OS.get_environment("AGL_TOKYO_REGION_SURFACE_REGION"))
		return
	if OS.get_environment("AGL_TOKYO_REGION_SAMPLE_BLOCKS") != "":
		var sample_builder: RefCounted = load("res://scripts/tests/build_tokyo_region_blocks.gd").new()
		_fail = sample_builder.run(OS.get_environment("AGL_TOKYO_REGION_SOURCE"), OS.get_environment("AGL_TOKYO_REGION_SAMPLE_BLOCKS"), OS.get_environment("AGL_TOKYO_REGION_SAMPLE_OUT"))
		return
	if OS.get_environment("AGL_TOKYO_GROUND_EXPORT") == "1":
		var ground_script: Script = load("res://scripts/tests/export_tokyo_ground_planes.gd")
		if ground_script == null or not ground_script.can_instantiate():
			_fail = 1
			return
		var ground_export: RefCounted = ground_script.new()
		ground_export.run()
		_fail = ground_export._fail
		return
	if OS.get_environment("AGL_TOKYO_CLUSTER_BUILD") == "1":
		var cluster_script: Script = load("res://scripts/tests/build_tokyo_cluster_pages.gd")
		if cluster_script == null or not cluster_script.can_instantiate():
			_fail = 1
			return
		var cluster_builder: RefCounted = cluster_script.new()
		cluster_builder.run()
		_fail = cluster_builder._fail
		return
	if OS.get_environment("AGL_TOKYO_ROOF_EXPORT") == "1":
		var roof_script: Script = load("res://scripts/tests/export_tokyo_roof_ownership.gd")
		if roof_script == null or not roof_script.can_instantiate():
			_fail = 1
			return
		var roof_export: RefCounted = roof_script.new()
		roof_export.run()
		_fail = roof_export._fail
		return
	if OS.get_environment("AGL_TOKYO_LOD_SPATIAL_BUILD") == "1":
		var lod_script: Script = load("res://scripts/tests/build_tokyo_lod_spatial_pages.gd")
		if lod_script == null or not lod_script.can_instantiate():
			_fail = 1
			return
		var lod_builder: RefCounted = lod_script.new()
		lod_builder.run()
		_fail = lod_builder._fail
		return
	if OS.get_environment("AGL_TOKYO_HIERARCHY_BUILD") == "1":
		var hierarchy: RefCounted = load("res://scripts/tests/build_tokyo_hierarchical_pages.gd").new()
		hierarchy.run()
		_fail = hierarchy._fail
		return
	if OS.get_environment("AGL_TOKYO_OWNED_BUILD") == "1":
		var owned: RefCounted = load("res://scripts/tests/build_tokyo_owned_pages.gd").new()
		owned.run()
		_fail = owned._fail
		return
	if OS.get_environment("AGL_TOKYO_SPATIAL_BUILD") == "1":
		var spatial: RefCounted = load("res://scripts/tests/build_tokyo_spatial_pages.gd").new()
		spatial.run()
		_fail = spatial._fail
		return
	if OS.get_environment("AGL_TOKYO_CELLS_VARIANT") == "yokohama_joined_coastal":
		var coastal: RefCounted = load("res://scripts/tests/build_tokyo_coastal_cells.gd").new()
		coastal.run()
		_fail = coastal._fail
		return
	if OS.get_environment("AGL_TOKYO_CELLS_VARIANT") == "yokohama_joined_palette":
		var palette: RefCounted = load("res://scripts/tests/build_tokyo_palette_cells.gd").new()
		palette.run()
		_fail = palette._fail
		return
	if OS.get_environment("AGL_TOKYO_CELLS_VARIANT") == "yokohama_joined_area":
		var area: RefCounted = load("res://scripts/tests/build_tokyo_area_cells.gd").new()
		area.run()
		_fail = area._fail
		return
	if OS.get_environment("AGL_TOKYO_CELLS_VARIANT") == "yokohama_joined_indexed":
		var indexed: RefCounted = load("res://scripts/tests/build_tokyo_indexed_cells.gd").new()
		indexed.run()
		_fail = indexed._fail
		return
	if OS.get_environment("AGL_TOKYO_CELLS_VARIANT") in ["yokohama_joined", "yokohama_joined_spatial"]:
		var joined: RefCounted = load("res://scripts/tests/build_tokyo_joined_cells.gd").new()
		joined.run()
		_fail = joined._fail
		return
	if OS.get_environment("AGL_TOKYO_CELL_EXPORT") == "1":
		_export_fixed_for_cell_audit()
		return
	_footprint_lod = OS.get_environment("AGL_TOKYO_CELLS_VARIANT") == "kawasaki_lod"
	_dedup = OS.get_environment("AGL_TOKYO_CELLS_VARIANT") in ["yokohama_dedup", "kawasaki", "kawasaki_strokes", "kawasaki_lod"]
	_relief_lod = OS.get_environment("AGL_TOKYO_CELLS_VARIANT") == "relief"
	_out = "res://bench/results/tokyo_r8_cells" if _relief_lod else OUT
	_dest = "res://resources/maps/tokyo_volume_preview/r8_cells" if _relief_lod else DEST
	if OS.get_environment("AGL_TOKYO_CELLS_VARIANT") == "yokohama":
		_relief_lod = true
		_out = "res://bench/results/tokyo_r9_cells"
		_dest = "res://resources/maps/tokyo_volume_preview/r9_cells"
	if OS.get_environment("AGL_TOKYO_CELLS_VARIANT") == "yokohama_color":
		_relief_lod = true
		_out = "res://bench/results/tokyo_r9c_cells"
		_dest = "res://resources/maps/tokyo_volume_preview/r9c_cells"
	if OS.get_environment("AGL_TOKYO_CELLS_VARIANT") == "yokohama_roofs":
		_relief_lod = true
		_out = "res://bench/results/tokyo_r10_cells"
		_dest = "res://resources/maps/tokyo_volume_preview/r10_cells"
	var source_dir := OS.get_environment("AGL_TOKYO_REGION_SOURCE")
	if OS.get_environment("AGL_TOKYO_CELLS_VARIANT") == "yokohama_mid":
		_relief_lod = true
		_mid_relief = true
		_out = "res://bench/results/tokyo_r11_cells"
		_dest = "res://resources/maps/tokyo_volume_preview/r11_cells"
	if OS.get_environment("AGL_TOKYO_CELLS_VARIANT") == "yokohama_adaptive":
		_relief_lod = true
		_mid_relief = true
		_adaptive = true
		_out = "res://bench/results/tokyo_r13_cells"
		_dest = "res://resources/maps/tokyo_volume_preview/r13_cells"
	if OS.get_environment("AGL_TOKYO_CELLS_VARIANT") == "yokohama_coverage":
		_relief_lod = true
		_mid_relief = true
		_adaptive = true
		_coverage = true
		_out = "res://bench/results/tokyo_r15_cells"
		_dest = "res://resources/maps/tokyo_volume_preview/r15_cells"
	if OS.get_environment("AGL_TOKYO_CELLS_VARIANT") == "yokohama_coverage_b":
		_relief_lod = true
		_mid_relief = true
		_adaptive = true
		_coverage = true
		_batch_guard = true
		_out = "res://bench/results/tokyo_r15b_cells"
		_dest = "res://resources/maps/tokyo_volume_preview/r15b_cells"
	if OS.get_environment("AGL_TOKYO_CELLS_VARIANT") in ["yokohama_coverage_c", "yokohama_domes", "yokohama_domes_b", "yokohama_dedup", "kawasaki", "kawasaki_strokes", "kawasaki_lod"]:
		_relief_lod = true
		_mid_relief = true
		_adaptive = true
		_coverage = true
		_cut_steps = 20
		_out = "res://bench/results/tokyo_r15c_cells"
		_dest = "res://resources/maps/tokyo_volume_preview/r15c_cells"
		_domes = OS.get_environment("AGL_TOKYO_CELLS_VARIANT").begins_with("yokohama_domes") or _dedup
		if _domes:
			_out = "res://bench/results/tokyo_r17_cells"
			_dest = "res://resources/maps/tokyo_volume_preview/r17_cells"
			_dome_round_only = OS.get_environment("AGL_TOKYO_CELLS_VARIANT") == "yokohama_domes_b" or _dedup
			if _dome_round_only:
				_out = "res://bench/results/tokyo_r17b_cells"
				_dest = "res://resources/maps/tokyo_volume_preview/r17b_cells"
	if _dedup:
		_out = "res://bench/results/tokyo_r19_cells"
		_dest = "res://resources/maps/tokyo_volume_preview/r19_cells"
	if OS.get_environment("AGL_TOKYO_CELLS_VARIANT") == "kawasaki":
		_out = "res://bench/results/tokyo_r20_cells"
		_dest = "res://resources/maps/tokyo_volume_preview/r20_cells"
	if OS.get_environment("AGL_TOKYO_CELLS_VARIANT") == "kawasaki_strokes":
		_out = "res://bench/results/tokyo_r21_cells"
		_dest = "res://resources/maps/tokyo_volume_preview/r21_cells"
	if _footprint_lod:
		_out = "res://bench/results/tokyo_r22_cells"
		_dest = "res://resources/maps/tokyo_volume_preview/r22_cells"
	if source_dir.is_empty() or not FileAccess.file_exists(source_dir.path_join("city.json")):
		_fail = 1
		return
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(source_dir.path_join("city.json")))
	var sample := OS.get_environment("AGL_TOKYO_CELLS_VARIANT") == "regional_sample"
	if not OS.get_environment("AGL_TOKYO_REGION_SAMPLE_OUT").is_empty():
		print("[Tokyo sample request] variant=", OS.get_environment("AGL_TOKYO_CELLS_VARIANT"), " sample=", sample, " output=", OS.get_environment("AGL_TOKYO_REGION_SAMPLE_OUT"))
		if not sample:
			_fail = 1
			push_error("Explicit sample output requires regional_sample variant")
			return
	if sample:
		var sample_out := OS.get_environment("AGL_TOKYO_REGION_SAMPLE_OUT")
		if not valid_sample_output(source_dir, sample_out) or data.has("regional_ownership"):
			_fail = 1
			return
		_out = sample_out
		_dest = sample_out
		_relief_lod = true
		_mid_relief = true
		_adaptive = true
	if not _load_regional_ownership(data, source_dir):
		_fail = 1
		print("[Tokyo cells] regional source gate rejected fail=1")
		return
	var suppressed: Dictionary = Duplicates.suppressed(data.buildings) if _dedup else {}
	var index := Index.new()
	index.bounds = Rect2(data.rect[0], data.rect[1], data.rect[2], data.rect[3])
	index.source_count = data.buildings.size()
	index.surface_only = data.buildings.is_empty()
	if index.surface_only:
		_adaptive = false
	index.source_hash = FileAccess.get_sha256(source_dir.path_join("city.json")) + ":" + FileAccess.get_sha256(source_dir.path_join("ground.json"))
	if not _regional.is_empty():
		index.regional_id = _regional.region
		index.regional_registry_hash = _regional.registry_hash
		index.regional_nonowner_ids = _regional.nonowner_ids
	DirAccess.make_dir_recursive_absolute(_out)
	var rectangles: Array[Rect2] = []
	if _adaptive:
		rectangles.assign(adaptive_rects(data.buildings, index.bounds))
	if _coverage:
		rectangles = coverage_rects(data.buildings, index.bounds, _batch_guard, _cut_steps)
	var partitions := partition(data.buildings, index.bounds, rectangles)
	var fixed_builders: Array = []
	for id in Index.MAX_CELLS:
		fixed_builders.append(Geometry.new())
	var packet: Dictionary = Factory.build(source_dir.path_join("city.json"))
	var fixed_inputs: Array[ArrayMesh] = [packet.road_mesh, packet.rail_mesh, Factory.build_ground(source_dir.path_join("ground.json"))]
	var source_area := 0.0
	for mesh in fixed_inputs:
		source_area += split_fixed(mesh, index.bounds, fixed_builders, rectangles)
	packet.clear()
	fixed_inputs.clear()
	var report: Dictionary = {"source_count": index.source_count, "cells": [], "fixed_source_area": source_area, "fixed_split_area": 0.0}
	report["domes"] = []
	report["suppressed_outlines"] = suppressed
	report["regional_ownership"] = _regional
	for id in Index.MAX_CELLS:
		var rect := rectangles[id] if _adaptive else cell_rect(index.bounds, id)
		var group: Array = partitions[id]
		var content := rect
		var max_height_px := 0.0
		var ids := PackedStringArray()
		var height_lines := PackedStringArray()
		for raw: Dictionary in group:
			ids.append(raw.id)
			height_lines.append("%s:%.6f:%.6f" % [raw.id, raw.height_m, raw.min_height_m])
			content = content.merge(building_bounds(raw))
			max_height_px = maxf(max_height_px, float(raw.height_m) * 0.5)
		var height_hash := "\n".join(height_lines).sha256_text()
		var fixed := Cell.new()
		fixed.cell_id = id
		fixed.bounds = rect
		fixed.meshes.append(fixed_builders[id].mesh())
		finish(fixed)
		report.fixed_split_area += mesh_area(fixed.meshes[0])
		var stem := "cell_%02d" % id
		_save(fixed, stem + "_fixed.res")
		var entry: Dictionary = {"id": id, "bounds": rect, "content_bounds": content, "fixed": _dest.path_join(stem + "_fixed.res"),
			"fixed_bytes": fixed.geometry_bytes, "fixed_triangles": fixed.triangles, "levels": [], "source_count": ids.size(),
			"max_height_px": max_height_px, "visibility_margin": max_height_px * 1.6 + 8.0}
		for slot in Index.LEVELS.SCALES.size() + int(_mid_relief):
			var middle := slot == 6
			var level := 4 if middle else slot
			var cell := Cell.new()
			cell.cell_id = id
			cell.level = level
			cell.bounds = content
			cell.source_ids = ids
			cell.height_hash = height_hash
			cell.detail_counts = PackedInt32Array([0, 0, 0, 0])
			var low := Geometry.new()
			var known := Geometry.new()
			var original_low: RefCounted = Geometry.new() if _footprint_lod and level < 4 else null
			var simplified := false
			for raw: Dictionary in group:
				if raw.get("defer_render", false) or not raw.get("render_outline", true) or suppressed.has(String(raw.id)) \
						or (not _regional.is_empty() and String(raw.regional_draw_owner) != String(_regional.region)):
					cell.detail_counts[3] += 1
					continue
				var scale_value: float = 1.0 if middle and raw.height_source == "fallback" else Index.LEVELS.SCALES[level]
				var detail := detail_level(raw, scale_value, _relief_lod)
				cell.detail_counts[detail] += 1
				var record := raw
				if _domes and raw.get("source_tags", {}).get("roof:shape", "") == "dome":
					var dome := Dome.build(raw, maxf(scale_value, 12.0) if level == 5 else scale_value, _dome_round_only)
					if level == 5:
						report.domes.append({"id": raw.id, "status": dome.status, "bands": dome.get("bands", 0), "error_px": dome.get("error_px", 0.0)})
					if dome.status == "ready":
						record = raw.duplicate()
						record["roof_volume"] = dome.volume
				if original_low != null and raw.height_source == "fallback":
					Factory._add_ring_building(original_low, record, float(raw.height_m) * 0.5, detail)
					if detail == 2 and raw.get("footprint_lod", {}).has(str(level)):
						var prepared: Dictionary = raw.footprint_lod[str(level)]
						assert(is_equal_approx(float(prepared.max_scale), Index.LEVELS.CUTS[level] * 1.08))
						record = record.duplicate()
						record.rings = prepared.rings
						simplified = true
				Factory._add_ring_building(known if raw.height_source != "fallback" else low, record, float(raw.height_m) * 0.5, detail)
			cell.meshes.assign([low.mesh(), known.mesh()])
			if simplified:
				cell.precision_original = original_low.mesh()
				cell.precision_max_scale = Index.LEVELS.CUTS[level] * 1.08
				cell.precision_triangles = Factory._triangles(cell.precision_original)
			finish(cell)
			var name_value := stem + ("_mid_4.res" if middle else "_lod_%d.res" % level)
			_save(cell, name_value)
			var descriptor := {"path": _dest.path_join(name_value), "bytes": cell.geometry_bytes, "triangles": cell.triangles,
				"counts": Array(cell.detail_counts), "height_hash": height_hash}
			if middle:
				entry["mid"] = descriptor
			else:
				entry.levels.append(descriptor)
		index.cells.append(entry)
		report.cells.append(entry)
		print("[Tokyo cells] cell=", id, " sources=", ids.size(), " fixed=", fixed.triangles, " near=", entry.levels[5].triangles)
	if not index.valid(String(_regional.get("registry_hash", ""))) or absf(float(report.fixed_source_area) - float(report.fixed_split_area)) > 2.0:
		_fail += 1
	if ResourceSaver.save(index, _out.path_join("index.res"), ResourceSaver.FLAG_COMPRESS) != OK:
		_fail += 1
	report["fail"] = _fail
	var file := FileAccess.open(_out.path_join("build_report.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print("[Tokyo cells] area_error=", absf(float(report.fixed_source_area) - float(report.fixed_split_area)), " fail=", _fail)
	if sample and _fail == 0:
		var audit: RefCounted = load("res://scripts/tests/audit_tokyo_region_sample.gd").new()
		_fail += audit.run(source_dir, _out)
		print("[Tokyo regional sample] fail=", _fail)


static func valid_sample_output(source_dir: String, output: String) -> bool:
	var source := source_dir.replace("\\", "/")
	var target := output.replace("\\", "/")
	var parent := source.get_base_dir()
	return source.is_absolute_path() and target.is_absolute_path() and target == target.simplify_path() \
		and parent.ends_with("/tmp/tokyo-bay-volume") and target.get_base_dir() == parent \
		and target.get_file().begins_with("r") and target != source \
		and not DirAccess.dir_exists_absolute(target) and not FileAccess.file_exists(target)


func _load_regional_ownership(data: Dictionary, source_dir: String) -> bool:
	_regional = {}
	var region := OS.get_environment("AGL_TOKYO_JOINED_REGION")
	if not data.has("regional_ownership"):
		for raw: Dictionary in data.buildings:
			if raw.has("regional_draw_owner"):
				return false
		return region.is_empty()
	var expected_variant := "yokohama_dedup" if region == "yokohama" else "kawasaki_lod"
	if region not in ["yokohama", "north_coast"] or OS.get_environment("AGL_TOKYO_CELLS_VARIANT") != expected_variant:
		print("[Tokyo regional gate] wrong region or variant")
		return false
	var registry_path := source_dir.get_base_dir().path_join("ownership.json")
	var original_dir := OS.get_environment("AGL_TOKYO_JOINED_ORIGINAL_SOURCE")
	if not FileAccess.file_exists(registry_path) or original_dir.is_empty():
		print("[Tokyo regional gate] missing registry or original source")
		return false
	var registry: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(registry_path))
	var hashes: Dictionary = registry.get("inputs", {}).get(region, {})
	for name_value: String in ["city.json", "ground.json"]:
		var source_path := original_dir.path_join(name_value)
		if not FileAccess.file_exists(source_path) or FileAccess.get_sha256(source_path) != String(hashes.get(name_value, "")):
			print("[Tokyo regional gate] original hash mismatch: ", name_value)
			return false
	if FileAccess.get_sha256(source_dir.path_join("ground.json")) != String(hashes.get("ground.json", "")):
		print("[Tokyo regional gate] prepared ground mismatch")
		return false
	var original: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(original_dir.path_join("city.json")))
	_regional = Regional.validate(data, original, registry, region, FileAccess.get_sha256(registry_path))
	if _regional.is_empty():
		print("[Tokyo regional gate] source payload validation rejected")
		return false
	_out = "res://bench/results/tokyo_r25_%s_cells" % region
	_dest = "res://resources/maps/tokyo_volume_preview/r25_%s_cells" % region
	return true


func _export_fixed_for_cell_audit() -> void:
	# 只读最终原生地表，供离线层级成本预检；不重新构图或修改地图归档。
	var index: Resource = load("res://resources/maps/tokyo_volume_preview/r22_cells/index.res")
	var cells: Array = []
	var total := 0
	for entry: Dictionary in index.cells:
		var fixed: Resource = load(entry.fixed)
		assert(fixed.valid())
		var vertices: PackedVector3Array = fixed.meshes[0].surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		assert(vertices.size() / 3 == entry.fixed_triangles)
		var packed: Array = []
		for point: Vector3 in vertices:
			packed.append([point.x, point.y, point.z])
		cells.append({"id": entry.id, "vertices": packed, "triangles": entry.fixed_triangles})
		total += entry.fixed_triangles
	var file := FileAccess.open("res://bench/results/tokyo_r23_fixed_audit.json", FileAccess.WRITE)
	assert(file != null)
	file.store_string(JSON.stringify({"source_hash": index.source_hash, "triangles": total, "cells": cells}))
	file.close()
	print("[Tokyo R23 fixed audit] cells=", cells.size(), " triangles=", total, " fail=0")


static func cell_rect(bounds: Rect2, id: int) -> Rect2:
	var size := bounds.size / 4.0
	return Rect2(bounds.position + Vector2(id % 4, id / 4) * size, size)


static func building_bounds(raw: Dictionary) -> Rect2:
	var first := true
	var bounds := Rect2()
	for ring: Dictionary in raw.rings:
		for point: Vector2 in Factory._points(ring.outer):
			if first:
				bounds = Rect2(point, Vector2.ZERO)
				first = false
			else:
				bounds = bounds.expand(point)
	return bounds


static func connected_groups(records: Array) -> Array:
	var lookup: Dictionary = {}
	var edges: Dictionary = {}
	var result: Array = []
	for raw: Dictionary in records:
		lookup[raw.id] = raw
		edges[raw.id] = []
	for raw: Dictionary in records:
		for parent: String in raw.get("parents", []):
			if lookup.has(parent):
				edges[raw.id].append(parent)
				edges[parent].append(raw.id)
	var visited: Dictionary = {}
	for raw: Dictionary in records:
		if visited.has(raw.id):
			continue
		var stack: Array = [raw.id]
		var members: Array = []
		while not stack.is_empty():
			var identity: String = stack.pop_back()
			if visited.has(identity):
				continue
			visited[identity] = true
			members.append(lookup[identity])
			stack.append_array(edges[identity])
		members.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return String(a.id) < String(b.id))
		result.append(members)
	return result


static func partition(records: Array, bounds: Rect2, rectangles: Array[Rect2] = []) -> Array:
	var result: Array = []
	for id in Index.MAX_CELLS:
		result.append([])
	for members: Array in connected_groups(records):
		var extent := building_bounds(members[0])
		for raw: Dictionary in members:
			extent = extent.merge(building_bounds(raw))
		var coordinate := (extent.get_center() - bounds.position) / (bounds.size / 4.0)
		var owner := clampi(floori(coordinate.x), 0, 3) + 4 * clampi(floori(coordinate.y), 0, 3)
		if not rectangles.is_empty():
			owner = -1
			var center := extent.get_center().clamp(bounds.position, bounds.end - Vector2.ONE * 0.001)
			for id in rectangles.size():
				if rectangles[id].has_point(center):
					owner = id
					break
			assert(owner >= 0, "adaptive cell partition must cover every source")
		result[owner].append_array(members)
	for group: Array in result:
		group.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return String(a.id) < String(b.id))
	return result


static func adaptive_rects(records: Array, bounds: Rect2) -> Array[Rect2]:
	return _split_density(_partition_atoms(records), bounds, 4)


static func _partition_atoms(records: Array) -> Array[Dictionary]:
	var atoms: Array[Dictionary] = []
	for group: Array in connected_groups(records):
		var extent := building_bounds(group[0])
		var weight := 0
		var layers := [{"weight": 0}, {"weight": 0}]
		for raw: Dictionary in group:
			extent = extent.merge(building_bounds(raw))
			if raw.get("defer_render", false) or not raw.get("render_outline", true):
				continue
			var detail := detail_level(raw, 1.6, true)
			var triangles := 0
			if raw.has("roof_volume") and detail < 2:
				triangles = (raw.roof_volume.walls.size() + raw.roof_volume.roof.size()) / 3
			else:
				for ring: Dictionary in raw.rings:
					triangles += ring.triangles.size() / 3
					if detail < 2:
						triangles += ring.outer.size() * 2
						for hole: Array in ring.holes:
							triangles += hole.size() * 2
					if detail == 0:
						triangles += (ring.get("inset_triangles", []).size() + ring.get("panel_triangles", []).size()) / 3
			weight += triangles
			var layer: Dictionary = layers[0 if raw.height_source == "fallback" else 1]
			var guard := float(raw.height_m) * 0.5 * (sin(deg_to_rad(38.0)) + 1.0 / tan(deg_to_rad(50.0))) + 8.0
			var protected := building_bounds(raw).grow(guard)
			layer["footprint"] = (layer.footprint as Rect2).merge(building_bounds(raw)) if layer.weight > 0 else building_bounds(raw)
			layer["guard"] = maxf(float(layer.get("guard", 0.0)), guard)
			layer["bounds"] = (layer.bounds as Rect2).merge(protected) if layer.weight > 0 else protected
			layer.weight += triangles
		atoms.append({"center": extent.get_center(), "weight": weight, "id": String(group[0].id), "layers": layers})
	atoms.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.id < b.id)
	return atoms


static func coverage_rects(records: Array, bounds: Rect2, batch_guard: bool = false, cut_steps: int = 10) -> Array[Rect2]:
	var atoms := _partition_atoms(records)
	for atom: Dictionary in atoms:
		atom.center = (atom.center as Vector2).clamp(bounds.position, bounds.end - Vector2.ONE * 0.001)
	var leaves: Array[Dictionary] = [_coverage_split(atoms, bounds, batch_guard, cut_steps)]
	while leaves.size() < Index.MAX_CELLS:
		var best := 0
		for i in range(1, leaves.size()):
			if float(leaves[i].gain) > float(leaves[best].gain) or (leaves[i].gain == leaves[best].gain \
					and (leaves[i].bounds as Rect2).get_area() > (leaves[best].bounds as Rect2).get_area()):
				best = i
		var chosen: Dictionary = leaves[best]
		leaves[best] = _coverage_split(chosen.lower, chosen.left, batch_guard, cut_steps)
		leaves.insert(best + 1, _coverage_split(chosen.upper, chosen.right, batch_guard, cut_steps))
	var result: Array[Rect2] = []
	for leaf: Dictionary in leaves:
		result.append(leaf.bounds)
	return result


static func _coverage_cost(atoms: Array[Dictionary], batch_guard: bool = false) -> float:
	var layers := [{"weight": 0}, {"weight": 0}]
	for atom: Dictionary in atoms:
		for kind in 2:
			var input: Dictionary = atom.layers[kind]
			if input.weight <= 0:
				continue
			var output: Dictionary = layers[kind]
			output["bounds"] = (output.bounds as Rect2).merge(input.bounds) if output.weight > 0 else input.bounds
			output["footprint"] = (output.footprint as Rect2).merge(input.footprint) if output.weight > 0 else input.footprint
			output["guard"] = maxf(float(output.get("guard", 0.0)), float(input.guard))
			output.weight += int(input.weight)
	var cost := 0.0
	for layer: Dictionary in layers:
		if layer.weight <= 0:
			continue
		var size: Vector2 = layer.bounds.size
		if batch_guard:
			size = (layer.footprint as Rect2).grow(float(layer.guard)).size
		for scale_value: float in [0.8, 1.6, 3.2]:
			# 均匀旋转矩形的Minkowski面积；常量屏幕面积在分割前后抵消。
			cost += float(layer.weight) * (size.x * size.y * scale_value * scale_value \
				+ (size.x + size.y) * scale_value * 2500.0 * 2.0 / PI)
	return cost


static func _coverage_split(atoms: Array[Dictionary], bounds: Rect2, batch_guard: bool = false, cut_steps: int = 10) -> Dictionary:
	var base := _coverage_cost(atoms, batch_guard)
	var result: Dictionary = {}
	var best := INF
	for axis in 2:
		for step in range(ceili(cut_steps * 0.2), floori(cut_steps * 0.8) + 1):
			var fraction := float(step) / float(cut_steps)
			var cut := roundf(bounds.position[axis] + bounds.size[axis] * fraction)
			if cut <= bounds.position[axis] or cut >= bounds.end[axis]:
				continue
			var lower: Array[Dictionary] = []
			var upper: Array[Dictionary] = []
			for atom: Dictionary in atoms:
				if atom.center[axis] < cut:
					lower.append(atom)
				else:
					upper.append(atom)
			var cost := _coverage_cost(lower, batch_guard) + _coverage_cost(upper, batch_guard)
			# 空叶子优先均分长轴，避免零收益并列反复切出极细区域。
			if base == 0.0:
				cost = absf(fraction - 0.5) + (0.0 if bounds.size[axis] >= bounds.size[1 - axis] else 1.0)
			if cost >= best:
				continue
			best = cost
			var left := bounds
			var right := bounds
			left.size[axis] = cut - bounds.position[axis]
			right.position[axis] = cut
			right.size[axis] = bounds.end[axis] - cut
			result = {"bounds": bounds, "gain": base - cost, "lower": lower, "upper": upper, "left": left, "right": right}
	assert(not result.is_empty(), "coverage split requires integer world-pixel region")
	return result


static func _split_density(atoms: Array[Dictionary], bounds: Rect2, depth: int) -> Array[Rect2]:
	if depth == 0:
		return [bounds]
	var axis := 0 if bounds.size.x >= bounds.size.y else 1
	atoms.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a.center[axis] < b.center[axis] if a.center[axis] != b.center[axis] else a.id < b.id)
	var total := 0
	for atom: Dictionary in atoms:
		total += int(atom.weight)
	var cumulative := 0
	var cut := bounds.get_center()[axis]
	for atom: Dictionary in atoms:
		cumulative += int(atom.weight)
		if total > 0 and cumulative * 2 >= total:
			cut = atom.center[axis]
			break
	cut = clampf(roundf(cut), ceilf(bounds.position[axis] + bounds.size[axis] * 0.2), floorf(bounds.position[axis] + bounds.size[axis] * 0.8))
	var left := bounds
	var right := bounds
	left.size[axis] = cut - bounds.position[axis]
	right.position[axis] = cut
	right.size[axis] = bounds.end[axis] - cut
	var lower: Array[Dictionary] = []
	var upper: Array[Dictionary] = []
	for atom: Dictionary in atoms:
		if atom.center[axis] < cut:
			lower.append(atom)
		else:
			upper.append(atom)
	var result := _split_density(lower, left, depth - 1)
	result.append_array(_split_density(upper, right, depth - 1))
	return result


static func detail_level(raw: Dictionary, scale_value: float, relief_lod: bool = false) -> int:
	var size := building_bounds(raw).size
	var pixels := maxf(size.x, size.y) * scale_value
	var detail := 0 if pixels >= 10.0 else (1 if pixels >= 2.5 else 2)
	if float(raw.height_m) >= 80.0 and scale_value > 0.1:
		detail = mini(detail, 1)
	# R8独立候选：只概括没有来源标高、投影墙厚不足2px的低层，屋顶仍在原高度。
	if relief_lod and raw.get("height_source", "fallback") == "fallback" \
			and float(raw.height_m) < 80.0 and scale_value < 1.6 \
			and float(raw.height_m) * 0.5 * sin(deg_to_rad(38.0)) * scale_value < 2.0:
		detail = 2
	return detail


static func clip_polygon(points: PackedVector3Array, axis: int, edge: float, keep_above: bool) -> PackedVector3Array:
	var output := PackedVector3Array()
	if points.is_empty():
		return output
	var previous := points[-1]
	var previous_inside := previous[axis] >= edge if keep_above else previous[axis] <= edge
	for point in points:
		var inside := point[axis] >= edge if keep_above else point[axis] <= edge
		if inside != previous_inside:
			var cut := previous.lerp(point, (edge - previous[axis]) / (point[axis] - previous[axis]))
			cut[axis] = edge
			output.append(cut)
		if inside:
			output.append(point)
		previous = point
		previous_inside = inside
	return output


static func split_fixed(mesh: ArrayMesh, bounds: Rect2, builders: Array, rectangles: Array[Rect2] = []) -> float:
	if mesh.get_surface_count() == 0:
		return 0.0
	var arrays := mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	var source_area := 0.0
	for start in range(0, vertices.size(), 3):
		var triangle := PackedVector3Array([vertices[start], vertices[start + 1], vertices[start + 2]])
		# 来源道路可能伸出观察范围：面积守恒基线也裁到同一外边界。
		triangle = clip_polygon(triangle, 0, bounds.position.x, true)
		triangle = clip_polygon(triangle, 0, bounds.end.x, false)
		triangle = clip_polygon(triangle, 2, bounds.position.y, true)
		triangle = clip_polygon(triangle, 2, bounds.end.y, false)
		for n in range(1, triangle.size() - 1):
			source_area += (triangle[n] - triangle[0]).cross(triangle[n + 1] - triangle[0]).length() * 0.5
		if triangle.is_empty():
			continue
		var extent := Rect2(Vector2(triangle[0].x, triangle[0].z), Vector2.ZERO)
		for point in triangle:
			extent = extent.expand(Vector2(point.x, point.z))
		for id in Index.MAX_CELLS:
			var rect := rectangles[id] if not rectangles.is_empty() else cell_rect(bounds, id)
			if not rect.intersects(extent):
				continue
			var polygon := clip_polygon(triangle, 0, rect.position.x, true)
			polygon = clip_polygon(polygon, 0, rect.end.x, false)
			polygon = clip_polygon(polygon, 2, rect.position.y, true)
			polygon = clip_polygon(polygon, 2, rect.end.y, false)
			for n in range(1, polygon.size() - 1):
				if (polygon[n] - polygon[0]).cross(polygon[n + 1] - polygon[0]).length_squared() > 0.00000001:
					# 输入已是 Godot 顺时针面；Geometry.triangle 内部会再翻一次，先还原逻辑顺序。
					builders[id].triangle(polygon[0], polygon[n + 1], polygon[n], colors[start])
	return source_area


static func mesh_area(mesh: ArrayMesh) -> float:
	if mesh.get_surface_count() == 0:
		return 0.0
	var vertices: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var area := 0.0
	for start in range(0, vertices.size(), 3):
		area += (vertices[start + 1] - vertices[start]).cross(vertices[start + 2] - vertices[start]).length() * 0.5
	return area


static func finish(cell: Resource) -> void:
	for mesh: ArrayMesh in cell.meshes:
		cell.triangles += Factory._triangles(mesh)
		cell.geometry_bytes += mesh_bytes(mesh)
	if cell.precision_original != null:
		cell.geometry_bytes += mesh_bytes(cell.precision_original)


static func mesh_bytes(mesh: ArrayMesh) -> int:
	var result := 0
	if mesh.get_surface_count() > 0:
		for channel: Variant in mesh.surface_get_arrays(0):
			if channel != null:
				result += channel.to_byte_array().size()
	return result


func _save(cell: Resource, name_value: String) -> void:
	if not cell.valid() or ResourceSaver.save(cell, _out.path_join(name_value), ResourceSaver.FLAG_COMPRESS) != OK:
		_fail += 1
