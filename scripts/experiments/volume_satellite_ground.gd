extends Node3D
## 不保存第二套地图瓦片；共用正式流送纹理，另用两张有界预构建材质纹理。
const SHADER := preload("res://resources/shaders/volume_satellite_ground.gdshader")
const OPAQUE_SHADER := preload("res://resources/shaders/volume_satellite_opaque.gdshader")
const DECORATION_SHADER := preload("res://resources/shaders/volume_desert_decoration.gdshader")
const TACTICAL_SHADER := preload("res://resources/shaders/volume_desert_tactical_ground.gdshader")
const TACTICAL_OPAQUE_SHADER := preload("res://resources/shaders/volume_desert_tactical_opaque.gdshader")
const TACTICAL_DECORATION_SHADER := preload("res://resources/shaders/volume_desert_tactical_decoration.gdshader")
const TacticalContext := preload("res://scripts/experiments/volume_desert_tactical_context.gd")
const MaterialWarmup := preload("res://scripts/experiments/volume_material_warmup.gd")
const ContactAO := preload("res://scripts/rendering/map_contact_ao.gd")
const ROCK_TEXTURE_PATH := "res://resources/maps/desert_rock_albedo_r40.res"
const CLEAN_TERRAIN_TEXTURE_PATH := "res://resources/maps/desert_clean_terrain_r52.res"
const ROCK_TEXTURE_BUDGET_BYTES := 1398100
const CLEAN_TERRAIN_TEXTURE_BUDGET_BYTES := 8388608
const LEGACY_RUNWAY_START := Vector2(7858.1353, 4228.3851)
const LEGACY_RUNWAY_END := Vector2(8711.9079, 3645.3413)
# R49 已核对的 OSM 机场边界，经原图 Mercator→显示世界换算；闭合末点不重复。
const LEGACY_AIRPORT_BOUNDARY := [Vector2(8320.5734, 3983.0627), Vector2(8743.3119, 3688.8654),
	Vector2(8757.3196, 3711.1163), Vector2(8863.6233, 3655.0756), Vector2(8760.6164, 3505.9192),
	Vector2(8704.5805, 3537.2373), Vector2(8624.6463, 3410.3276), Vector2(8314.8052, 3617.9931),
	Vector2(8016.4953, 3820.7166), Vector2(7907.7203, 3913.0149), Vector2(7766.8074, 4175.0728),
	Vector2(7711.5969, 4213.8019), Vector2(7822.8434, 4376.9731), Vector2(7908.5457, 4297.0364),
	Vector2(7901.1317, 4270.6632), Vector2(8177.1892, 4077.8287), Vector2(8250.5297, 4185.7852),
	Vector2(8388.1457, 4093.4890)]
const MAX_PLANES := 17
# 完整归档仍是 -0.8；原生面固定到既有 Detail 的 -0.6，消除照片换档的高度差。
const TACTICAL_SURFACE_LIFT := 0.2
const Relief := preload("res://scripts/experiments/volume_desert_relief.gd")
var relief: RefCounted
var _details: Node3D
var _source: WeakRef
var _planes: Dictionary = {}
var _countdown := 0.0
var version := 29
var _peak_mesh_build_us := 0
var _cover_far := false
var _cover_swaps := 0
var _cover_error_px := INF
var _terrain_detail_texture: Texture2D
var _clean_terrain_texture: Texture2D
var _clean_texture_bytes := 0
var _source_profile: Dictionary = {}
var _tactical_style := false
var _material_warmup_state := {"state": "inactive", "rendered": false}


func setup(source: RasterBasemapRenderer, context_job: Dictionary = {}) -> void:
	var warm_material: ShaderMaterial
	_source = weakref(source)
	_source_profile = source.presentation_profile()
	_tactical_style = relief != null and TacticalContext.is_enabled(source._map_key)
	if relief != null:
		relief.bind_archive(_tactical_style)
		# 知道真实source/style后只实例化一份预建装饰，不创建再删除另一档。
		_details = relief.make_details(_tactical_style)
		var water: MeshInstance3D = _details.get_node("Source_Water_EvenOdd_Fill")
		var water_material: ShaderMaterial = water.material_override.duplicate() as ShaderMaterial
		water_material.set_shader_parameter("sediment_enabled", true)
		water_material.set_shader_parameter("sediment_texture", _terrain_detail_texture)
		water_material.set_shader_parameter("sediment_mean_srgb", _terrain_detail_texture.get_meta("mean_srgb"))
		water_material.set_shader_parameter("sediment_mean_linear", _terrain_detail_texture.get_meta("mean_linear"))
		water.material_override = water_material
		add_child(_details)
	if _tactical_style:
		var water: MeshInstance3D = _details.get_node("Source_Water_EvenOdd_Fill")
		water.material_override.set_shader_parameter("sediment_enabled", false)
		water.material_override.set_shader_parameter("water_color", Color("536a68"))
		var regions := TacticalContext.build(relief) if context_job.is_empty() else TacticalContext.finish_build(context_job)
		for region: MeshInstance3D in regions:
			_details.add_child(region)
			if warm_material == null:
				warm_material = region.material_override as ShaderMaterial
	elif is_instance_valid(_details) and _source_profile.get("source_kind", "") == "satellite":
		# 实拍水域留在原图中，不叠加另一日期的 CARTO 水面几何。
		_details.get_node("Source_Water_EvenOdd_Fill").hide()
	set_process(false)
	sync(0.0)
	if warm_material != null:
		var warmup := MaterialWarmup.new()
		warmup.configure(warm_material)
		warmup.finished.connect(_on_material_warmup_finished)
		_material_warmup_state = {"state": "pending", "rendered": false}
		add_child(warmup)


## 原生全幅只替换源引用；不重建已经预绘制的网格、材质或地被。
func rebind_native_source(source: RasterBasemapRenderer) -> bool:
	if not _tactical_style or _planes.size() != 1 or source._map_key != "desert" \
			or source.presentation_profile() != _source_profile:
		return false
	var records := source.presentation_tiles()
	if records.is_empty() or records[0].lod != &"strategic":
		return false
	var sprite: Variant = records[0].sprite.get_ref()
	var entry: Dictionary = _planes.values()[0]
	var old: Variant = entry.sprite.get_ref()
	if typeof(sprite) != TYPE_OBJECT or not is_instance_valid(sprite) \
			or typeof(old) != TYPE_OBJECT or not is_instance_valid(old) \
			or sprite.position != old.position or sprite.scale != old.scale \
			or sprite.texture.get_size() != old.texture.get_size():
		return false
	_source = weakref(source)
	entry.sprite = records[0].sprite
	entry.layer = null
	entry.material.set_shader_parameter("map_texture", sprite.texture)
	for detail: MeshInstance3D in _details.get_children():
		if String(detail.name).begins_with("Scrub_"):
			detail.material_override.set_shader_parameter("map_texture", sprite.texture)
	_planes.clear()
	_planes[sprite.get_instance_id()] = entry
	_countdown = 0.0
	return true


func _on_material_warmup_finished(result: Dictionary) -> void:
	_material_warmup_state = result


func enable_relief() -> void:
	assert(_planes.is_empty(), "configure relief before binding source tiles")
	relief = Relief.new(false)
	_terrain_detail_texture = load(ROCK_TEXTURE_PATH)
	_clean_terrain_texture = load(CLEAN_TERRAIN_TEXTURE_PATH)
	_clean_texture_bytes = _clean_terrain_texture.get_image().get_data().size()


## 仅独立观察场读取同源 metadata；真实游戏直接借用已经初始化的 owner。
func setup_lab(camera: Camera2D, metadata_path: String) -> bool:
	var meta: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(metadata_path))
	var source := RasterBasemapRenderer.new()
	add_child(source)
	source.hide()
	if not source.setup(camera, Relief.Archive.source_rect(meta), "desert"):
		source.free()
		return false
	setup(source)
	return true


func sync(delta: float) -> void:
	var source: Variant = _source.get_ref() if _source != null else null
	if typeof(source) != TYPE_OBJECT or not is_instance_valid(source):
		_clear()
		return
	_countdown -= delta
	if _countdown <= 0:
		_countdown = 0.10
		_sync_cover_lod()
		var present := {}
		for entry: Dictionary in source.presentation_tiles():
			# 原生材质没有照片采样；完整预建面与全部裁切面具有同一细分和法线场。
			if _tactical_style and entry.lod != &"strategic":
				continue
			var sprite: Variant = entry.sprite.get_ref()
			if typeof(sprite) != TYPE_OBJECT or not is_instance_valid(sprite):
				continue
			var key: int = sprite.get_instance_id()
			present[key] = true
			if not _planes.has(key) and _planes.size() < MAX_PLANES:
				_planes[key] = _make_plane(sprite, entry)
		for key in _planes.keys():
			if not present.has(key):
				_planes[key].node.free()
				_planes.erase(key)
	# 仅同步 0.40s 过渡 alpha 与排序；稳定时不重复写 uniform。
	for key in _planes.keys():
		var entry: Dictionary = _planes[key]
		var sprite: Variant = entry.sprite.get_ref()
		if typeof(sprite) != TYPE_OBJECT or not is_instance_valid(sprite):
			entry.node.free()
			_planes.erase(key)
			continue
		var layer: Variant = entry.layer.get_ref() if entry.layer != null else null
		var has_layer: bool = typeof(layer) == TYPE_OBJECT and is_instance_valid(layer)
		entry.node.visible = _tactical_style or (sprite.visible and (layer.visible if has_layer else entry.layer == null))
		var opacity: float = 1.0 if _tactical_style else sprite.modulate.a * (layer.modulate.a if has_layer else 1.0)
		var opaque: bool = opacity >= 1.0
		if entry.opaque != opaque:
			entry.material.shader = (TACTICAL_OPAQUE_SHADER if opaque else TACTICAL_SHADER) if _tactical_style else (OPAQUE_SHADER if opaque else SHADER)
			entry.opaque = opaque
		var priority: int = -100 if not has_layer else (-80 if layer.z_index == 2 else -90)
		if not is_equal_approx(opacity, entry.alpha):
			entry.material.set_shader_parameter("opacity", opacity)
			entry.alpha = opacity
		if entry.priority != priority:
			entry.material.render_priority = priority
			entry.priority = priority


static func cover_lod_far(was_far: bool, error_px: float) -> bool:
	return error_px < 0.20 if was_far else error_px <= 0.15


static func cover_error_pixels(view_basis: Basis, ground_basis: Basis, viewport_extent: float, camera_size: float) -> float:
	if camera_size <= 0 or viewport_extent <= 0:
		return INF
	# 正交投影下Y位移投到相机XY；包含世界warp、旋转和真实render target尺寸。
	var displacement := view_basis.inverse() * (ground_basis * Vector3.UP)
	return Vector2(displacement.x, displacement.y).length() * Relief.COVER_LOD_ERROR * viewport_extent / camera_size


func _sync_cover_lod() -> void:
	_cover_error_px = INF
	if is_instance_valid(_details) and is_inside_tree():
		var viewport := get_viewport()
		var camera := viewport.get_camera_3d()
		if camera != null and camera.projection == Camera3D.PROJECTION_ORTHOGONAL:
			# canvas_items可有1920逻辑宽但1600实际输出；LOD不得把逻辑px当输出px。
			var dimensions := viewport.get_visible_rect().size * viewport.get_stretch_transform().get_scale()
			if viewport is SubViewport:
				dimensions = Vector2(viewport.size)
			var extent := dimensions.y if camera.keep_aspect == Camera3D.KEEP_HEIGHT else dimensions.x
			_cover_error_px = cover_error_pixels(camera.global_basis, global_basis, extent, camera.size)
	_apply_cover_lod(cover_lod_far(_cover_far, _cover_error_px))
	if _tactical_style and is_instance_valid(_details):
		for detail: MeshInstance3D in _details.get_children():
			if not detail.has_meta("context_height_error"):
				continue
			# 背景楼体不能误用矮草的误差界；按每区最大墙高保守换档。
			var error: float = _cover_error_px * float(detail.get_meta("context_height_error")) / Relief.COVER_LOD_ERROR
			var was_far: bool = detail.get_meta("context_far")
			var far := cover_lod_far(was_far, error)
			if far != was_far:
				detail.mesh = detail.get_meta("context_far_mesh" if far else "context_near_mesh")
				detail.set_meta("context_far", far)


func _apply_cover_lod(far: bool) -> void:
	if far == _cover_far or not is_instance_valid(_details):
		return
	# 16地被批次及4个候选街区；仅切档时换资源。无跨帧逐株对象缓存。
	for detail: MeshInstance3D in _details.get_children():
		if detail.has_meta("cover_near_mesh"):
			detail.mesh = detail.get_meta("cover_far_mesh" if far else "cover_near_mesh")
	_cover_far = far
	_cover_swaps += 1


func _make_plane(sprite: Sprite2D, record: Dictionary) -> Dictionary:
	var started := Time.get_ticks_usec()
	var texture_size := Vector2(sprite.texture.get_size())
	var region := sprite.region_rect if sprite.region_enabled else Rect2(Vector2.ZERO, texture_size)
	var rect := Rect2(sprite.position, region.size * sprite.scale)
	var uv := Rect2(region.position / texture_size, region.size / texture_size)
	var y := -0.8 if record.lod == &"strategic" else -0.6
	var vertices := PackedVector3Array([
		Vector3(rect.position.x, y, rect.position.y), Vector3(rect.end.x, y, rect.position.y),
		Vector3(rect.end.x, y, rect.end.y), Vector3(rect.position.x, y, rect.end.y)])
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = PackedVector3Array([Vector3.UP, Vector3.UP, Vector3.UP, Vector3.UP])
	arrays[Mesh.ARRAY_TEX_UV] = PackedVector2Array([uv.position,
		Vector2(uv.end.x, uv.position.y), uv.end, Vector2(uv.position.x, uv.end.y)])
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2, 0, 2, 3])
	var mesh := ArrayMesh.new()
	if relief != null:
		mesh = relief.presentation_mesh(String(sprite.name), rect, uv, y)
	else:
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var material := ShaderMaterial.new()
	material.shader = TACTICAL_SHADER if _tactical_style else SHADER
	if _tactical_style:
		ContactAO.bind(material, "desert")
	material.set_shader_parameter("map_texture", sprite.texture)
	material.set_shader_parameter("luma_scale", sprite.self_modulate.r)
	material.set_shader_parameter("relief_enabled", relief != null)
	if _clean_terrain_texture != null and relief != null:
		material.set_shader_parameter("clean_terrain_enabled", true)
		material.set_shader_parameter("clean_terrain_texture", _clean_terrain_texture)
		material.set_shader_parameter("clean_terrain_world_rect", Vector4(
			relief.rect.position.x, relief.rect.position.y, relief.rect.size.x, relief.rect.size.y))
		material.set_shader_parameter("legacy_runway_start", LEGACY_RUNWAY_START)
		material.set_shader_parameter("legacy_runway_end", LEGACY_RUNWAY_END)
		material.set_shader_parameter("legacy_airport_boundary", PackedVector2Array(LEGACY_AIRPORT_BOUNDARY))
	if _terrain_detail_texture != null:
		material.set_shader_parameter("terrain_detail_enabled", true)
		material.set_shader_parameter("terrain_detail_texture", _terrain_detail_texture)
		material.set_shader_parameter("terrain_detail_mean_linear", _terrain_detail_texture.get_meta("mean_linear"))
		material.set_shader_parameter("terrain_detail_mean_srgb", _terrain_detail_texture.get_meta("mean_srgb"))
	if record.lod == &"strategic" and is_instance_valid(_details):
		# 仅首次绑定源瓦片时创建；借用纹理，不改归档内共享材质或飞机材质。
		var detail_material := ShaderMaterial.new()
		detail_material.shader = TACTICAL_DECORATION_SHADER if _tactical_style else DECORATION_SHADER
		detail_material.set_shader_parameter("map_texture", sprite.texture)
		var rock_texture: Texture2D = _terrain_detail_texture
		detail_material.set_shader_parameter("rock_texture", rock_texture)
		detail_material.set_shader_parameter("rock_mean_linear", rock_texture.get_meta("mean_linear"))
		detail_material.set_shader_parameter("rock_mean_srgb", rock_texture.get_meta("mean_srgb"))
		detail_material.set_shader_parameter("luma_scale", sprite.self_modulate.r)
		detail_material.set_shader_parameter("relief_enabled", true)
		detail_material.set_shader_parameter("decoration_world_rect", Vector4(rect.position.x, rect.position.y, rect.size.x, rect.size.y))
		detail_material.set_shader_parameter("decoration_uv_rect", Vector4(uv.position.x, uv.position.y, uv.size.x, uv.size.y))
		for detail: MeshInstance3D in _details.get_children():
			if String(detail.name).begins_with("Scrub_"):
				detail.material_override = detail_material
		configure_source_material(detail_material, _source_profile)
	configure_source_material(material, _source_profile)
	var node := MeshInstance3D.new()
	if _tactical_style:
		node.position.y = TACTICAL_SURFACE_LIFT
	node.mesh = mesh
	node.material_override = material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node)
	_peak_mesh_build_us = maxi(_peak_mesh_build_us, Time.get_ticks_usec() - started)
	return {"node": node, "material": material, "sprite": record.sprite,
		"layer": record.layer, "alpha": -1.0, "priority": 0, "opaque": false}


static func configure_source_material(material: ShaderMaterial, profile: Dictionary) -> void:
	if profile.get("source_kind", "") != "satellite":
		return
	material.set_shader_parameter("source_is_satellite", true)
	material.set_shader_parameter("tint", Color.WHITE)
	for key: String in ["saturation", "brightness", "contrast"]:
		material.set_shader_parameter(key, float(profile.get(key, 1.0)))
	material.set_shader_parameter("detail_strength", float(profile.get("detail_strength", 0.12)))
	material.set_shader_parameter("clean_terrain_enabled", false)
	material.set_shader_parameter("terrain_detail_enabled", false)


func _clear() -> void:
	var warmup := get_node_or_null("MaterialWarmup")
	if warmup != null:
		warmup.free()
	_material_warmup_state = {"state": "inactive", "rendered": false}
	for entry: Dictionary in _planes.values():
		entry.node.free()
	_planes.clear()
	if is_instance_valid(_details):
		_details.free()
	_details = null
	relief = null
	_terrain_detail_texture = null
	_clean_terrain_texture = null
	_source_profile.clear()
	_tactical_style = false
	_cover_far = false
	_cover_error_px = INF


func debug_state() -> Dictionary:
	var result := {"planes": _planes.size(), "max_planes": 1 if _tactical_style else MAX_PLANES, "shared_textures": true, "version": version}
	result["surface_mode"] = "native_full" if _tactical_style else "source_tiles"
	result["material_warmup"] = _material_warmup_state.duplicate()
	result["source_kind"] = _source_profile.get("source_kind", "carto")
	result["visual_style"] = "tactical" if _tactical_style else "source"
	var terrain_triangles := 0
	for entry: Dictionary in _planes.values():
		terrain_triangles += entry.node.mesh.surface_get_array_index_len(0) / 3
	result["terrain_triangles"] = terrain_triangles
	result["peak_mesh_build_ms"] = _peak_mesh_build_us / 1000.0
	result["relief"] = relief != null
	result["prebuilt_terrain"] = relief != null and relief.archive != null
	result["archive_hits"] = relief.archive_hits if relief != null else 0
	result["archive_misses"] = relief.archive_misses if relief != null else 0
	result["geometry_bytes"] = relief.archive.geometry_bytes if relief != null and relief.archive != null else 0
	result["archive_path"] = relief.archive.resource_path if relief != null and relief.archive != null else ""
	result["vegetation"] = int(_details.get_meta("vegetation_count", 0)) if is_instance_valid(_details) else 0
	result["outcrops"] = int(_details.get_meta("outcrop_count", 0)) if is_instance_valid(_details) else 0
	result["rock_texture_budget_bytes"] = ROCK_TEXTURE_BUDGET_BYTES if is_instance_valid(_details) else 0
	result["clean_texture_budget_bytes"] = CLEAN_TERRAIN_TEXTURE_BUDGET_BYTES if _clean_terrain_texture != null else 0
	result["clean_texture_bytes"] = _clean_texture_bytes if _clean_terrain_texture != null else 0
	result["water_contours"] = int(_details.get_meta("water_contours", 0)) if is_instance_valid(_details) else 0
	result["retained_shorelines"] = int(_details.get_meta("retained_shorelines", 0)) if is_instance_valid(_details) else 0
	result["watercourses"] = int(_details.get_meta("watercourse_count", 0)) if is_instance_valid(_details) else 0
	result["cover_lod_far"] = _cover_far
	result["cover_lod_swaps"] = _cover_swaps
	result["cover_lod_error_px"] = _cover_error_px
	var source: Variant = _source.get_ref() if _source != null else null
	if typeof(source) == TYPE_OBJECT and is_instance_valid(source) and source.is_inside_tree():
		var state: Dictionary = source.debug_state()
		for key in ["current_lod", "target_lod", "resident_tiles", "peak_resident_tiles", "estimated_texture_bytes", "missing_keys"]:
			result[key] = state[key]
	return result
