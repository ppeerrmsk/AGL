extends "res://scripts/experiments/volume_3d_tokyo_preview.gd"
## 六档分块资产对拍：仅固定机位显式换资源，不冒充异步正式流送或帧时验收。
const CellIndex := preload("res://scripts/rendering/tokyo_cell_index.gd")
var _index: Resource
var _resident: Dictionary = {}
var _shared: Array[ShaderMaterial] = []
var _selected_level := -1
var _load_fail := false
var _selection: Dictionary = {}


func _load_geometry() -> bool:
	var sample_path := OS.get_environment("AGL_TOKYO_REGION_SAMPLE_INDEX")
	_index = load(CellIndex.PATH if sample_path.is_empty() else sample_path)
	if _index == null or not _index.valid():
		return false
	if not sample_path.is_empty():
		preview_center = _index.bounds.get_center()
		close_center = preview_center
		output_prefix = "res://bench/results/r120_west_"
		if not OS.get_environment("AGL_TOKYO_REGION_SURFACE_AO").is_empty():
			output_prefix = "res://bench/results/r122_west_"
		# 与既有shadowless审查相同：保留太阳路径，仅停投影者，避免GL整体变暗。
	for kind in 3:
		var material := ShaderMaterial.new()
		material.shader = SurfaceShader
		if not OS.get_environment("AGL_TOKYO_REGION_SURFACE_AO").is_empty():
			material.shader = preload("res://resources/shaders/tokyo_volume_surface.gdshader")
		material.set_shader_parameter("facade_detail", kind == 1)
		_shared.append(material)
	_packet = {"ok": true, "source_buildings": _index.source_count}
	return true


func _set_view(center: Vector2, zoom_value: float) -> void:
	super._set_view(center, zoom_value)
	if _index != null:
		_select_cells(center, zoom_value)


func _select_cells(center: Vector2, zoom_value: float) -> void:
	var view := Rect2(center - Vector2(CAPTURE_SIZE) / zoom_value * 0.5, Vector2(CAPTURE_SIZE) / zoom_value)
	var selected: PackedInt32Array = _index.visible_cells(view)
	var level: int = CellIndex.LEVELS.choose_level(_selected_level, zoom_value)
	for id: int in _resident.keys():
		if id not in selected:
			for node: MeshInstance3D in _resident[id].nodes:
				node.queue_free()
			_resident.erase(id)
	for id in selected:
		var entry: Dictionary = _index.cells[id]
		if not _resident.has(id):
			var fixed: Resource = ResourceLoader.load(entry.fixed, "", ResourceLoader.CACHE_MODE_IGNORE)
			if fixed == null or not fixed.valid():
				_load_fail = true
				continue
			_resident[id] = {"fixed": fixed, "building": null, "nodes": [_node(null, 0), _node(null, 1), _node(fixed.meshes[0], 2)]}
		var current: Dictionary = _resident[id]
		if current.building == null or current.building.level != level:
			var building: Resource = ResourceLoader.load(entry.levels[level].path, "", ResourceLoader.CACHE_MODE_IGNORE)
			if building == null or not building.valid():
				_load_fail = true
				continue
			current.building = building
			for kind in 2:
				current.nodes[kind].mesh = building.meshes[kind]
				current.nodes[kind].cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if level >= (2 if kind == 0 else 1) else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				if not OS.get_environment("AGL_TOKYO_REGION_SAMPLE_INDEX").is_empty():
					current.nodes[kind].cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_selected_level = level
	_selection = {"level": level, "cells": Array(selected), "resident_bytes": 0, "triangles": 0, "source_count": 0, "counts": [0, 0, 0, 0], "materials": 3}
	for current: Dictionary in _resident.values():
		if current.building == null:
			continue
		_selection.resident_bytes += current.fixed.geometry_bytes + current.building.geometry_bytes
		_selection.triangles += current.fixed.triangles + current.building.triangles
		_selection.source_count += current.building.source_ids.size()
		for kind in 4:
			_selection.counts[kind] += current.building.detail_counts[kind]
	_selection["nodes"] = _resident.size() * 3
	if not OS.get_environment("AGL_TOKYO_REGION_SAMPLE_INDEX").is_empty():
		_selection["shadow_casters"] = 0
		for current: Dictionary in _resident.values():
			for node: MeshInstance3D in current.nodes:
				_selection.shadow_casters += int(node.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
		_selection["light_shadow_path"] = _sun.shadow_enabled


func _node(mesh: ArrayMesh, kind: int) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = _shared[kind]
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if kind == 2 else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	_geometry_root.add_child(node)
	return node


func _settle() -> bool:
	await get_tree().create_timer(2.0).timeout
	await RenderingServer.frame_post_draw
	var state: Dictionary = _raster_source.debug_state()
	var ready: bool = state.current_lod == state.target_lod and int(state.pending_count) == 0 and (state.missing_keys as Array).is_empty()
	_ground.snapshot(_raster_source)
	return not ready or _load_fail


func _capture_sequence() -> void:
	if not OS.get_environment("AGL_TOKYO_REGION_SAMPLE_INDEX").is_empty():
		await _capture_sample()
		return
	var failed := false
	var captures: Array[Dictionary] = []
	for zoom_value: float in [0.06, 0.13, 0.26, 0.52, 0.98, 2.2, 5.0]:
		_set_view(close_center, zoom_value)
		failed = await _settle() or failed
		failed = await _capture("shimbashi_%03d" % roundi(zoom_value * 100), close_center, zoom_value, true, captures) or failed
		captures[-1]["selection"] = _selection.duplicate(true)
	# 共享行边界，以及原北区关系/庭院对拍，不能只验子块中心。
	for entry: Array in [["seam", Vector2(95, -12730)], ["station", CLOSE_CENTER], ["waterfront", Vector2(300, -12200)]]:
		_set_view(entry[1], 2.2)
		failed = await _settle() or failed
		failed = await _capture(entry[0] + "_220", entry[1], 2.2, true, captures) or failed
		captures[-1]["selection"] = _selection.duplicate(true)
		_sun.shadow_enabled = false
		failed = await _capture(entry[0] + "_220_no_shadow", entry[1], 2.2, false, captures) or failed
		_sun.shadow_enabled = true
	var file := FileAccess.open(output_prefix + "manifest.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"status": "fixed-view cell LOD candidate; synchronous observation only, no combat performance claim", "failed": failed, "captures": captures}, "\t"))
	file.close()
	print("[Tokyo cells Visual] captures=", captures.size(), " fail=", failed)
	get_tree().quit(1 if failed else 0)


func _capture_sample() -> void:
	if not OS.get_environment("AGL_TOKYO_REGION_SURFACE_AO").is_empty():
		var code: int = await load("res://scripts/tests/tokyo_region_surface_review.gd").new().run(self)
		get_tree().quit(code)
		return
	var failed := false
	var captures: Array[Dictionary] = []
	var poses: Array[Dictionary] = []
	for zoom_value: float in [0.06, 0.13, 0.26, 0.65, 0.98, 1.95, 5.0]:
		poses.append({"id": "center_%03d" % roundi(zoom_value * 100), "center": preview_center, "zoom": zoom_value})
	var bounds: Rect2 = _index.bounds
	poses.append({"id": "east_edge", "center": Vector2(bounds.end.x, bounds.get_center().y), "zoom": 1.95})
	poses.append({"id": "north", "center": Vector2(bounds.get_center().x, bounds.position.y + 120.0), "zoom": 1.95})
	poses.append({"id": "south", "center": Vector2(bounds.get_center().x, bounds.end.y - 120.0), "zoom": 1.95})
	if OS.get_environment("AGL_TOKYO_NORTH_SOURCE_REVIEW") == "1":
		if FileAccess.get_sha256(OS.get_environment("AGL_TOKYO_REGION_SAMPLE_INDEX")) not in ["199e256163dc145b447f3f8d8fb3e46540369ada124ba4d786d8fcfd520658c6", "7d04ded67f8d9c5894819b4239b697cbce508ebadcd154b4cc70c80dfcee6578"]:
			get_tree().quit(1)
			return
		poses.clear()
		for site: Dictionary in [{"id": "depot", "center": Vector2(-7716.45, -4410.07)}, {"id": "resthouse", "center": Vector2(-7077.05, -3964.37)}]:
			for zoom_value: float in [1.95, 5.0, 8.0]:
				poses.append({"id": "%s_%03d" % [site.id, roundi(zoom_value * 100)], "center": site.center, "zoom": zoom_value})
	if OS.get_environment("AGL_TOKYO_RIGHT_SOURCE_REVIEW") == "1":
		if FileAccess.get_sha256(OS.get_environment("AGL_TOKYO_REGION_SAMPLE_INDEX")) != "4fa67221657f9e0486f36c01ae1954a5e96c1f04856598ba91a54d181975ed3b":
			get_tree().quit(1)
			return
		poses.clear()
		# 每个实际体积重叠独立定位；保留原生/瓦片/恢复三张，不据面积告警删楼。
		var sites: Array[Vector2] = [Vector2(-6351.515, -3885.772), Vector2(-6398.207, -3821.691), Vector2(-6343.553, -3952.432), Vector2(-6389.784, -3793.496), Vector2(-6382.958, -3788.329), Vector2(-6481.627, -3703.281), Vector2(-6467.061, -3705.241), Vector2(-6564.073, -4366.713), Vector2(-6473.344, -3776.958), Vector2(-6468.525, -3771.505), Vector2(-6406.407, -4552.500), Vector2(-6763.085, -3924.728)]
		for site_index: int in range(sites.size()):
			for zoom_value: float in [5.0, 8.0]:
				poses.append({"id": "right_%02d_%03d" % [site_index, roundi(zoom_value * 100)], "center": sites[site_index], "zoom": zoom_value})
	for pose: Dictionary in poses:
		_set_view(pose.center, pose.zoom)
		failed = await _settle() or failed
		failed = await _capture(pose.id + "_native", pose.center, pose.zoom, false, captures) or failed
		failed = failed or not _sun.shadow_enabled or int(_selection.shadow_casters) != 0
		captures[-1]["selection"] = _selection.duplicate(true)
		_geometry_root.hide()
		failed = await _capture(pose.id + "_tiles", pose.center, pose.zoom, false, captures) or failed
		_geometry_root.show()
		failed = await _capture(pose.id + "_restore", pose.center, pose.zoom, false, captures) or failed
	var file := FileAccess.open(output_prefix + "manifest.json", FileAccess.WRITE)
	if file == null:
		failed = true
	else:
		file.store_string(JSON.stringify({"failed": failed, "captures": captures, "index": OS.get_environment("AGL_TOKYO_REGION_SAMPLE_INDEX"),
			"status": "independent source baseline; not current gameplay compositor, streaming or performance acceptance"}))
		file.close()
	print("[Tokyo regional sample Visual] captures=", captures.size(), " fail=", failed)
	get_tree().quit(1 if failed else 0)
