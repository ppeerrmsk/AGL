extends "res://scripts/rendering/tokyo_volume_overlay.gd"
## R7 显式实验接线：沿用正式相机与合成，后台资源按块领取，未通过性能/过渡门前不默认启用。
const CellIndex := preload("res://scripts/rendering/tokyo_cell_index.gd")
const Stream := preload("res://scripts/rendering/tokyo_cell_stream.gd")
const ShadowDepth := preload("res://scripts/rendering/tokyo_shadow_depth.gd")
const Indexed := preload("res://scripts/experiments/tokyo_indexed_mesh.gd")
var _tight_depth := false
var _source_max_height := 0.0
var _depth_max_height := 0.0
var _local_depth := false
var _stream: Node
var _descriptors: Dictionary = {}
var _desired := PackedInt32Array()
var _batches: Dictionary = {}
var _extent := Rect2()
var max_bind_usec := 0
var binds := 0
var peak_triangles := 0
var budget_exceeded := false
var _warm_deadline := 0
var _warm_ready_frame := -1
var _candidate := "R7 cells"
var _layer_culling := false
var _cull_view := Rect2()
var _mid_relief := false
var _relief_active := false
var _mid_binds := 0
var _full4_binds := 0
var _directional_cull := false
var _cull_camera := Basis()
var _cull_light := Basis()
var _peak_snapshot: Dictionary = {}
var _exact_view := false
var _precision_binds := 0


func _load_archive() -> Resource:
	if OS.get_environment("AGL_TOKYO_CELLS_VARIANT") in ["yokohama_joined", "yokohama_joined_depth", "yokohama_joined_indexed", "yokohama_joined_spatial", "yokohama_joined_area", "yokohama_joined_palette", "yokohama_joined_coastal"]:
		_layer_culling = true
		_mid_relief = true
		_directional_cull = true
		_exact_view = true
		_tight_depth = true
		_candidate = "R26 Joint Yokohama north coast"
		_local_depth = OS.get_environment("AGL_TOKYO_CELLS_VARIANT") != "yokohama_joined"
		if OS.get_environment("AGL_TOKYO_CELLS_VARIANT") == "yokohama_joined_coastal":
			_candidate = "R34 Joint coastal surfaces"
			return load("res://resources/maps/tokyo_volume_preview/r34_cells/index.res")
		if OS.get_environment("AGL_TOKYO_CELLS_VARIANT") == "yokohama_joined_palette":
			_candidate = "R32 Joint native palette"
			return load("res://resources/maps/tokyo_volume_preview/r32_cells/index.res")
		if OS.get_environment("AGL_TOKYO_CELLS_VARIANT") == "yokohama_joined_area":
			_candidate = "R30 Joint bounded area LOD"
			return load("res://resources/maps/tokyo_volume_preview/r30_cells/index.res")
		if OS.get_environment("AGL_TOKYO_CELLS_VARIANT") == "yokohama_joined_spatial":
			_candidate = "R29 Joint spatial pairing"
			return load("res://resources/maps/tokyo_volume_preview/r29_cells/index.res")
		if _local_depth:
			_candidate = "R27 Joint local shadow depth"
		if OS.get_environment("AGL_TOKYO_CELLS_VARIANT") == "yokohama_joined_indexed":
			_candidate = "R28 Joint indexed vertices"
			return load("res://resources/maps/tokyo_volume_preview/r28_cells/index.res")
		return load("res://resources/maps/tokyo_volume_preview/r26b_cells/index.res")
	if OS.get_environment("AGL_TOKYO_CELLS_VARIANT") in ["yokohama_shadow_depth", "yokohama_dedup", "kawasaki", "kawasaki_strokes", "kawasaki_lod"]:
		_layer_culling = true
		_mid_relief = true
		_directional_cull = true
		_exact_view = true
		_tight_depth = true
		_candidate = "R18 Yokohama fitted shadow depth"
		if OS.get_environment("AGL_TOKYO_CELLS_VARIANT") == "kawasaki_lod":
			_candidate = "R22 North coast bounded footprints"
			return load("res://resources/maps/tokyo_volume_preview/r22_cells/index.res")
		if OS.get_environment("AGL_TOKYO_CELLS_VARIANT") == "kawasaki_strokes":
			_candidate = "R21 North coast joined strokes"
			return load("res://resources/maps/tokyo_volume_preview/r21_cells/index.res")
		if OS.get_environment("AGL_TOKYO_CELLS_VARIANT") == "kawasaki":
			_candidate = "R20 North coast industry"
			return load("res://resources/maps/tokyo_volume_preview/r20_cells/index.res")
		if OS.get_environment("AGL_TOKYO_CELLS_VARIANT") == "yokohama_dedup":
			_candidate = "R19 Yokohama deduplicated outlines"
			return load("res://resources/maps/tokyo_volume_preview/r19_cells/index.res")
		return load("res://resources/maps/tokyo_volume_preview/r17b_cells/index.res")
	if OS.get_environment("AGL_TOKYO_CELLS_VARIANT") in ["yokohama_coverage", "yokohama_coverage_b", "yokohama_coverage_c", "yokohama_domes", "yokohama_domes_b"]:
		_layer_culling = true
		_mid_relief = true
		_directional_cull = true
		_exact_view = true
		_candidate = "R15 Yokohama coverage cells"
		if OS.get_environment("AGL_TOKYO_CELLS_VARIANT") == "yokohama_domes_b":
			_candidate = "R17B Yokohama round source domes"
			return load("res://resources/maps/tokyo_volume_preview/r17b_cells/index.res")
		if OS.get_environment("AGL_TOKYO_CELLS_VARIANT") == "yokohama_domes":
			_candidate = "R17 Yokohama source domes"
			return load("res://resources/maps/tokyo_volume_preview/r17_cells/index.res")
		if OS.get_environment("AGL_TOKYO_CELLS_VARIANT") == "yokohama_coverage_c":
			_candidate = "R15C Yokohama fine coverage cells"
			return load("res://resources/maps/tokyo_volume_preview/r15c_cells/index.res")
		if OS.get_environment("AGL_TOKYO_CELLS_VARIANT") == "yokohama_coverage_b":
			_candidate = "R15B Yokohama batch coverage cells"
			return load("res://resources/maps/tokyo_volume_preview/r15b_cells/index.res")
		return load("res://resources/maps/tokyo_volume_preview/r15_cells/index.res")
	if OS.get_environment("AGL_TOKYO_CELLS_VARIANT") in ["yokohama_mid", "yokohama_directional", "yokohama_adaptive", "yokohama_frustum"]:
		_layer_culling = true
		_mid_relief = true
		_directional_cull = OS.get_environment("AGL_TOKYO_CELLS_VARIANT") != "yokohama_mid"
		_candidate = "R12 Yokohama directional bounds" if _directional_cull else "R11B Yokohama mid relief"
		var candidate: Resource = load("res://resources/maps/tokyo_volume_preview/r11_cells/index.res")
		if OS.get_environment("AGL_TOKYO_CELLS_VARIANT") in ["yokohama_adaptive", "yokohama_frustum"]:
			_candidate = "R13 Yokohama density cells"
			candidate = load("res://resources/maps/tokyo_volume_preview/r13_cells/index.res")
			_exact_view = OS.get_environment("AGL_TOKYO_CELLS_VARIANT") == "yokohama_frustum"
			if _exact_view:
				_candidate = "R14 Yokohama rotated view"
		if candidate == null:
			return null
		for cell: Dictionary in candidate.cells:
			if not cell.has("mid"):
				return null
		return candidate
	if OS.get_environment("AGL_TOKYO_CELLS_VARIANT") == "yokohama_cull":
		_layer_culling = true
		_candidate = "R11 Yokohama layer visibility"
		return load("res://resources/maps/tokyo_volume_preview/r10_cells/index.res")
	if OS.get_environment("AGL_TOKYO_CELLS_VARIANT") == "yokohama_roofs":
		_candidate = "R10 Yokohama source roofs"
		return load("res://resources/maps/tokyo_volume_preview/r10_cells/index.res")
	if OS.get_environment("AGL_TOKYO_CELLS_VARIANT") == "yokohama_color":
		_candidate = "R9C Yokohama water"
		return load("res://resources/maps/tokyo_volume_preview/r9c_cells/index.res")
	if OS.get_environment("AGL_TOKYO_CELLS_VARIANT") == "yokohama":
		_candidate = "R9 Yokohama"
		return load("res://resources/maps/tokyo_volume_preview/r9_cells/index.res")
	if OS.get_environment("AGL_TOKYO_CELLS_VARIANT") == "relief":
		_candidate = "R8 relief"
		return load("res://resources/maps/tokyo_volume_preview/r8_cells/index.res")
	return load(CellIndex.PATH)


func _setup_geometry() -> void:
	if OS.get_environment("AGL_TOKYO_CELLS_VARIANT") in ["yokohama_joined_palette", "yokohama_joined_coastal"]:
		_composite.set_shader_parameter("edge_feather", 0.0)
	if _layer_culling or OS.get_environment("AGL_TOKYO_CELLS_VARIANT") == "yokohama_roofs":
		# R10 仓库坡面近景自阴影条纹校准；仅候选，避免改变既有归档的阴影基线。
		_sun.shadow_normal_bias = 2.0
	_warm_deadline = Time.get_ticks_msec() + 2000
	_extent = _archive.bounds
	for cell: Dictionary in _archive.cells:
		if _tight_depth:
			_source_max_height = maxf(_source_max_height, float(cell.get("max_height_px", INF)))
		_extent = _extent.merge((cell.content_bounds as Rect2).grow(float(cell.visibility_margin)))
		_descriptors[cell.fixed] = {"id": cell.id, "level": -1, "bytes": cell.fixed_bytes}
		for level in cell.levels.size():
			var entry: Dictionary = cell.levels[level]
			_descriptors[entry.path] = {"id": cell.id, "level": level, "bytes": entry.bytes, "height_hash": entry.height_hash}
		if _mid_relief:
			_descriptors[cell.mid.path] = {"id": cell.id, "level": 4, "bytes": cell.mid.bytes, "height_hash": cell.mid.height_hash}
	_stream = Stream.new()
	_stream.name = "TokyoCellStream"
	_stream.configure(self, _descriptors)
	# 独立于地图owner的短暂排空者；只在有请求时tick，弱owner失效后不绑定任何节点。
	get_tree().root.add_child.call_deferred(_stream)


func _configure_camera_depth(camera_basis: Basis) -> void:
	if _tight_depth:
		_depth_max_height = _source_max_height
		if _local_depth:
			var size := Vector2(_camera.size * float(_viewport.size.x) / float(_viewport.size.y), _camera.size)
			var depth_cells: Array = _archive.cells if _archive.shadow_cells.is_empty() else _archive.shadow_cells
			var local_height := ShadowDepth.visible_height(depth_cells, _city.basis, _camera.transform, _sun.basis, size)
			if is_finite(local_height):
				_depth_max_height = local_height
		var clip := ShadowDepth.fit(_camera.size, _depth_max_height, camera_basis, _sun.basis)
		if clip != Vector2.ZERO:
			_camera.near = clip.x
			_camera.far = clip.y
			_sun.directional_shadow_max_distance = clip.y
			return
	super._configure_camera_depth(camera_basis)


func _presentation_bounds() -> Rect2:
	return _extent


func _should_prewarm() -> bool:
	# 异步包在入场两帧内通常尚未就绪；必须真的绘制过网格才能预热着色器。
	return Time.get_ticks_msec() < _warm_deadline \
		and (_warm_ready_frame < 0 or Engine.get_process_frames() <= _warm_ready_frame + 2)


func _step_geometry(view_bounds: Rect2, scale_value: float, _delta: float) -> bool:
	var changed := false
	if _lod_clock <= 0.0:
		_lod_clock = 0.1
		var next: int = Archive.choose_level(_level, scale_value)
		var next_relief := relief_enabled(_relief_active, scale_value) if _mid_relief else false
		var selected: PackedInt32Array = _archive.visible_cells(view_bounds)
		if selected != _desired or next != _level or next_relief != _relief_active:
			PerfBuckets.mark_frame_event("tokyo_cell_selection")
			_relief_active = next_relief
			_desired = selected
			_previous_level = _level
			lod_switches += int(next != _level)
			_level = next
			for id: int in _batches.keys():
				if id not in _desired:
					_remove_cell(id)
					changed = true
			_sync_requests()
	for id in _desired:
		var entry: Dictionary = _archive.cells[id]
		var target: Dictionary = _target_entry(entry)
		if _batches.has(id) and _batches[id].path == target.path:
			continue
		var fixed: Resource = _stream.resource(entry.fixed)
		var building: Resource = _stream.resource(target.path)
		if fixed == null or building == null:
			continue
		var time := Time.get_ticks_usec()
		PerfBuckets.mark_frame_event("tokyo_cell_bind")
		if not _batches.has(id):
			_batches[id] = {"nodes": [_add_mesh(null, _materials[0], true), _add_mesh(null, _materials[1], true), _add_mesh(fixed.meshes[0], _materials[4], false)]}
		var batch: Dictionary = _batches[id]
		batch["fixed"] = fixed
		batch["building"] = building
		batch["precision_guarded"] = false
		batch["level"] = _level
		batch["path"] = target.path
		if _mid_relief and _level == 4:
			_mid_binds += int(_relief_active)
			_full4_binds += int(not _relief_active)
		for kind in 2:
			batch.nodes[kind].mesh = building.meshes[kind]
			batch.nodes[kind].cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if _level >= (2 if kind == 0 else 1) else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if _layer_culling:
			batch["layer_bounds"] = []
			batch["layer_triangles"] = []
			batch["boxes"] = []
			for node: MeshInstance3D in batch.nodes:
				batch.boxes.append(node.mesh.get_aabb())
				batch.layer_bounds.append(layer_bounds(node.mesh.get_aabb()))
				batch.layer_triangles.append(Indexed.triangles(node.mesh))
		max_bind_usec = maxi(max_bind_usec, Time.get_ticks_usec() - time)
		if PerfBuckets.frame_trace_enabled:
			PerfBuckets.tick("tokyo_map_bind", Time.get_ticks_usec() - time)
		binds += 1
		var live_triangles := 0
		for live: Dictionary in _batches.values():
			live_triangles += live.fixed.triangles + live.building.triangles
		if not _layer_culling:
			peak_triangles = maxi(peak_triangles, live_triangles)
		changed = true
		_sync_requests()
		break
	changed = _apply_precision_guards(scale_value) or changed
	if _layer_culling and (changed or view_bounds != _cull_view \
			or (_directional_cull and (_camera.basis != _cull_camera or _sun.basis != _cull_light))):
		changed = _apply_visibility(view_bounds) or changed
		_cull_view = view_bounds
		_cull_camera = _camera.basis
		_cull_light = _sun.basis
	if _warm_ready_frame < 0 and not _desired.is_empty():
		var all_ready := true
		for id in _desired:
			if not _batches.has(id) or _batches[id].path != _target_entry(_archive.cells[id]).path:
				all_ready = false
				break
		if all_ready:
			_warm_ready_frame = Engine.get_process_frames()
	return changed


func _apply_precision_guards(output_scale: float) -> bool:
	var changed := false
	for batch: Dictionary in _batches.values():
		var building: Resource = batch.building
		var use_original: bool = building.precision_original != null and output_scale > building.precision_max_scale
		if use_original == bool(batch.get("precision_guarded", false)):
			continue
		var mesh: ArrayMesh = building.precision_original if use_original else building.meshes[0]
		batch.nodes[0].mesh = mesh
		batch.precision_guarded = use_original
		if _layer_culling:
			batch.boxes[0] = mesh.get_aabb()
			batch.layer_bounds[0] = layer_bounds(mesh.get_aabb())
			batch.layer_triangles[0] = building.precision_triangles if use_original else Indexed.triangles(mesh)
		_precision_binds += 1
		PerfBuckets.mark_frame_event("tokyo_cell_precision")
		changed = true
	return changed


static func relief_enabled(current: bool, output_scale: float) -> bool:
	return output_scale <= (1.0 if current else 0.97)


func _target_entry(entry: Dictionary) -> Dictionary:
	return entry.mid if _mid_relief and _relief_active and _level == 4 else entry.levels[_level]


static func layer_bounds(box: AABB) -> Rect2:
	# 投影屋顶与日光落影都可能超出底面；保守相加，保持旋转后的高楼/长影。
	var guard := maxf(0.0, box.end.y) * (sin(TILT) + 1.0 / tan(deg_to_rad(50.0))) + 8.0
	return Rect2(Vector2(box.position.x, box.position.z), Vector2(box.size.x, box.size.z)).grow(guard)


static func projected_layer_bounds(box: AABB, roof_shift: Vector2, shadow_shift: Vector2) -> Rect2:
	var footprint := Rect2(Vector2(box.position.x, box.position.z), Vector2(box.size.x, box.size.z))
	var result := footprint
	# 固定四次合并保持原运算顺序，避免热点里每层构造临时数组和动态迭代器。
	result=result.merge(Rect2(footprint.position+roof_shift*box.position.y,footprint.size))
	result=result.merge(Rect2(footprint.position+roof_shift*box.end.y,footprint.size))
	result=result.merge(Rect2(footprint.position+shadow_shift*box.position.y,footprint.size))
	result=result.merge(Rect2(footprint.position+shadow_shift*box.end.y,footprint.size))
	return result.grow(8.0)


static func intersects_view(bounds: Rect2, view_bounds: Rect2, canvas: Transform2D, logical: Vector2) -> bool:
	# 矩形相交的分离轴：地图X/Y由第一步检验，屏幕X/Y由第二步检验。
	if not bounds.intersects(view_bounds, true):
		return false
	if absf(canvas.determinant()) < 0.00000001:
		return true
	var projected := Rect2(canvas * bounds.position, Vector2.ZERO)
	projected=projected.expand(canvas*Vector2(bounds.end.x,bounds.position.y))
	projected=projected.expand(canvas*bounds.end)
	projected=projected.expand(canvas*Vector2(bounds.position.x,bounds.end.y))
	return projected.intersects(Rect2(Vector2.ZERO, logical), true)


func _apply_visibility(view_bounds: Rect2) -> bool:
	var changed := false
	var visible_triangles := 0
	var roof_shift := Vector2.ZERO
	var shadow_shift := Vector2.ZERO
	var valid_direction := true
	var logical := Vector2(_viewport.size) * _screen.scale
	if _directional_cull:
		var inverse := _city.basis.inverse()
		var camera_ray := inverse * _camera.basis.z
		var light_ray := inverse * _sun.basis.z
		valid_direction = absf(camera_ray.y) > 0.001 and absf(light_ray.y) > 0.001
		if valid_direction:
			roof_shift = -Vector2(camera_ray.x, camera_ray.z) / camera_ray.y
			shadow_shift = -Vector2(light_ray.x, light_ray.z) / light_ray.y
	for batch: Dictionary in _batches.values():
		for kind in 3:
			var node: MeshInstance3D = batch.nodes[kind]
			var bounds: Rect2 = projected_layer_bounds(batch.boxes[kind], roof_shift, shadow_shift) if _directional_cull else batch.layer_bounds[kind]
			var intersects := intersects_view(bounds, view_bounds, _last_canvas, logical) if _exact_view else bounds.intersects(view_bounds)
			var logical_faces: int = batch.get("low_full_triangles",batch.layer_triangles[kind]) if kind == 0 else batch.layer_triangles[kind]
			var visible_now: bool = logical_faces > 0 and (not valid_direction or intersects)
			if node.visible != visible_now:
				node.visible = visible_now
				changed = true
			if visible_now:
				visible_triangles += int(batch.layer_triangles[kind])
	if visible_triangles > peak_triangles:
		peak_triangles = visible_triangles
		var per_cell: Dictionary = {}
		for id: Variant in _batches:
			var batch: Dictionary = _batches[id]
			var counts := PackedInt32Array()
			for kind in 3:
				counts.append(int(batch.layer_triangles[kind]) if batch.nodes[kind].visible else 0)
			per_cell[id] = {"path": batch.path, "submitted": counts}
		_peak_snapshot = {"frame": Engine.get_process_frames(), "view": view_bounds, "level": _level,
			"output_scale": float(_viewport.size.y) / _camera.size, "canvas_rotation": _last_canvas.get_rotation(), "cells": per_cell}
	return changed


func _sync_requests() -> void:
	var wanted := PackedStringArray()
	var pins := PackedStringArray()
	# 先替换仍在显示的旧LOD，绑定新包后才释放旧包；新街区不能抢占替换空间。
	var replacements := PackedStringArray()
	for id in _desired:
		var cell: Dictionary = _archive.cells[id]
		var target: String = _target_entry(cell).path
		if _batches.has(id) and _batches[id].path != target:
			replacements.append(cell.fixed)
			replacements.append(target)
		else:
			wanted.append(cell.fixed)
			wanted.append(target)
	replacements.append_array(wanted)
	for id: int in _batches:
		pins.append(_archive.cells[id].fixed)
		pins.append(_batches[id].path)
	_stream.request(replacements, pins)


func _remove_cell(id: Variant) -> void:
	PerfBuckets.mark_frame_event("tokyo_cell_retire")
	for node: MeshInstance3D in _batches[id].nodes:
		node.hide()
		node.mesh = null
		node.queue_free()
	_batches.erase(id)


func _deactivate() -> void:
	for id: int in _batches.keys():
		_remove_cell(id)
	_desired.clear()
	if is_instance_valid(_stream):
		_stream.request(PackedStringArray(), PackedStringArray())
	super._deactivate()


func _exit_tree() -> void:
	if is_instance_valid(_stream):
		_stream.close()


func debug_state() -> Dictionary:
	var triangles := 0
	var resident_triangles := 0
	var visible_nodes := 0
	var ready := 0
	var counts := [0, 0, 0, 0]
	var precision_guarded := 0
	for batch: Dictionary in _batches.values():
		resident_triangles += batch.fixed.triangles + batch.building.triangles + batch.building.precision_triangles
		precision_guarded += int(batch.get("precision_guarded", false))
		if _layer_culling:
			for kind in 3:
				if batch.nodes[kind].visible:
					triangles += int(batch.layer_triangles[kind])
					visible_nodes += 1
		else:
			triangles += batch.fixed.triangles + batch.building.triangles
			visible_nodes += 3
		ready += int(batch.path == _target_entry(_archive.cells[batch.building.cell_id]).path)
		for kind in 4:
			counts[kind] += batch.building.detail_counts[kind]
	budget_exceeded = triangles > 240000
	return {"candidate": _candidate, "active": _active, "enabled": _enabled, "level": _level,
		"previous_level": _previous_level, "blend": 1.0, "lod_switches": lod_switches, "redraws": redraws,
		"nodes": _batches.size() * 3, "materials": _materials.size() + 1,
		"output_size": _viewport.size if is_instance_valid(_viewport) else Vector2i.ZERO, "setup_ms": setup_ms,
		"triangles": triangles, "resident_triangles": resident_triangles, "visible_nodes": visible_nodes,
		"layer_culling": _layer_culling, "counts": counts, "max_transition_triangles": peak_triangles,
		"cull_view": _cull_view, "output_scale": float(_viewport.size.y) / _camera.size if is_instance_valid(_camera) else 0.0,
		"mid_relief": _mid_relief and _relief_active and _level == 4, "canvas_rotation": _last_canvas.get_rotation(),
		"mid_binds": _mid_binds, "full4_binds": _full4_binds,
		"precision_guarded": precision_guarded, "precision_binds": _precision_binds,
		"directional_cull": _directional_cull,
		"exact_view": _exact_view,
		"tight_depth": _tight_depth, "source_max_height": _source_max_height,
		"local_depth": _local_depth, "depth_max_height": _depth_max_height,
		"camera_near": _camera.near if is_instance_valid(_camera) else 0.0,
		"camera_far": _camera.far if is_instance_valid(_camera) else 0.0,
		"peak_snapshot": _peak_snapshot,
		"desired_cells": _desired.size(), "ready_cells": ready, "max_bind_usec": max_bind_usec, "binds": binds,
		"budget_exceeded": budget_exceeded, "stream": _stream.summary() if is_instance_valid(_stream) else {}}
