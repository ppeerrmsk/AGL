class_name RasterBasemapRenderer
extends Node2D

## 借用者必须同步释放，之后源才能改动/退役；无订阅者时不改变原流水线。
signal presentation_changing
## 精确退役通知供共享纹理桥接释放单个借用；不要求重建全部驻留页。
signal presentation_tile_retiring(instance_id: int)
var presentation_revision := 0

## 共享栅格金字塔 renderer：主地图按视口只驻留当前 LOD 的少量无损瓦片；
## Strategic 永远作为父层兜底。静止时仅以 10Hz 检查相机状态，不触发地图重绘。

const ROOT_PATH := "res://resources/maps/basemap_tiles"
const SHADER_PATH := "res://resources/shaders/basemap_streamed.gdshader"
const GRAIN_TEXTURE_PATH := "res://resources/maps/shared_blue_noise_64.png"
const GRAIN_TEXTURE_ESTIMATED_BYTES := 5461 # L8 64² + 完整 mip 链
const CONTENT_SIZE := 1024
const GUTTER := 16
const MAX_RESIDENT_TILES := 12
const HARD_RESIDENT_TILES := 16
const MAX_REQUIRED_TILES_PER_LOD := 12
const UPDATE_INTERVAL_S := 0.10
const TRANSITION_S := 0.40
const TRANSITION_TARGET_Z := 2
const MAX_PENDING_LOADS := 4
const MAX_TEXTURE_BINDS_PER_TICK := 2
const STRATEGIC_ENTER_ZOOM := 0.08
const STRATEGIC_EXIT_ZOOM := 0.10
const DETAIL_ENTER_ZOOM := 0.24
const DETAIL_EXIT_ZOOM := 0.20

const LOD_STRATEGIC := &"strategic"
const LOD_OPERATIONAL := &"operational"
const LOD_DETAIL := &"detail"

var _camera: Camera2D
var _world_rect := Rect2()
var _map_key := ""
var _map_root := ""
var _manifest: Dictionary = {}
var _profile: Dictionary = {}
var _records: Dictionary = {}
var _layers: Dictionary = {}
var _sprites: Dictionary = {}
var _pending: Dictionary = {}
var _lru: Array[String] = []
var _strategic_sprite: Variant = null
var source_projection: Dictionary = {}
const PROJECTED_GEOMETRY_RESERVE := 128 * 1024
var _current_lod: StringName = LOD_STRATEGIC
var _target_lod: StringName = LOD_STRATEGIC
var _tick_accum := 0.0
var _active := true
var _transitioning := false
var _transition_from_lod: StringName = LOD_STRATEGIC
var _setup_elapsed_ms := 0
var _peak_resident_tiles := 0
var _peak_committed_tiles := 0
var _capacity_deferrals := 0
var _grain_texture: Texture2D = null


static func map_root_for(map_key: String, source_selection: String = "") -> String:
	# 只选择固定内置候选目录，不能把其他地图或任意外部路径一起替换。
	var folder := "desert_satellite" if map_key == "desert" and source_selection == "sentinel" else map_key
	return "%s/%s" % [ROOT_PATH, folder]


static func manifest_path_for(map_key: String) -> String:
	return map_root_for(map_key, OS.get_environment("AGL_DESERT_BASEMAP")) + "/manifest.json"


static func load_manifest(map_key: String) -> Dictionary:
	if map_key.is_empty():
		return {}
	var path := manifest_path_for(map_key)
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed = JSON.parse_string(file.get_as_text())
	file.close()
	return parsed as Dictionary if parsed is Dictionary else {}


static func load_texture(path: String) -> Texture2D:
	var texture := load(path) as Texture2D if ResourceLoader.exists(path) else null
	if texture != null:
		return texture
	if not FileAccess.file_exists(path):
		return null
	var image := Image.load_from_file(path)
	if image == null or image.is_empty():
		return null
	return ImageTexture.create_from_image(image)


func load_grain_texture() -> Texture2D:
	if _grain_texture != null:
		return _grain_texture
	_grain_texture = load(GRAIN_TEXTURE_PATH) as Texture2D
	if _grain_texture != null:
		return _grain_texture
	# 仅供尚未完成 import 的开发副本 fail-open；正式导出由 .png.import
	# 固化 mipmap，运行时不再创建第二份纹理。
	var image := Image.load_from_file(GRAIN_TEXTURE_PATH) \
		if FileAccess.file_exists(GRAIN_TEXTURE_PATH) else null
	if image == null or image.is_empty():
		return null
	if not image.has_mipmaps():
		image.generate_mipmaps()
	_grain_texture = ImageTexture.create_from_image(image)
	return _grain_texture


func make_material(
		profile: Dictionary,
		level_size: Vector2,
		tile_origin_px: Vector2,
		texture_size_px: Vector2,
		lod: StringName) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = load(SHADER_PATH) as Shader
	if material.shader == null:
		return material
	material.set_shader_parameter("tint", _profile_color(profile, "tint", Color.WHITE))
	material.set_shader_parameter("saturation", float(profile.get("saturation", 1.0)))
	material.set_shader_parameter("brightness", float(profile.get("brightness", 1.0)))
	material.set_shader_parameter("contrast", float(profile.get("contrast", 1.0)))
	material.set_shader_parameter("edge_floor", float(profile.get("edge_floor", 0.0)))
	material.set_shader_parameter("edge_gain", _profile_lod_float(profile, "edge_gain", lod, 0.0))
	material.set_shader_parameter("edge_cap", float(profile.get("edge_cap", 1.0)))
	material.set_shader_parameter("edge_color", _profile_color(profile, "edge_color", Color.BLACK))
	var grain_strength := float(profile.get("noise_strength", 0.0))
	material.set_shader_parameter("grain_strength", grain_strength)
	material.set_shader_parameter("grain_repeat", float(profile.get("grain_repeat", 64.0)))
	if grain_strength > 0.0001:
		material.set_shader_parameter("grain_texture", load_grain_texture())
	material.set_shader_parameter("vignette_strength", float(profile.get("vignette_strength", 0.0)))
	material.set_shader_parameter("level_size_px", level_size)
	material.set_shader_parameter("tile_origin_px", tile_origin_px)
	material.set_shader_parameter("tile_texture_size_px", texture_size_px)
	return material


static func _profile_lod_float(
		profile: Dictionary,
		key: String,
		lod: StringName,
		fallback: float) -> float:
	var base := float(profile.get(key, fallback))
	var overrides = profile.get("%s_by_lod" % key, {})
	if overrides is Dictionary:
		return float((overrides as Dictionary).get(String(lod), base))
	return base


static func _profile_color(profile: Dictionary, key: String, fallback: Color) -> Color:
	var value = profile.get(key, [])
	if value is Array and value.size() >= 3:
		return Color(float(value[0]), float(value[1]), float(value[2]), 1.0)
	return fallback


func setup(camera: Camera2D, world_rect: Rect2, map_key: String) -> bool:
	var setup_started := Time.get_ticks_msec()
	_camera = camera
	_world_rect = world_rect
	if not source_projection.is_empty() and not preload("res://scripts/experiments/tokyo_raster_projection.gd").valid_for(source_projection,world_rect):
		return false
	_map_key = map_key
	_map_root = manifest_path_for(map_key).get_base_dir()
	_manifest = load_manifest(map_key)
	if _camera == null or _world_rect.size.x <= 0.0 or _manifest.is_empty():
		return false
	if not source_projection.is_empty():
		if _manifest.get("volume_profile",{}).get("source_kind","carto")!="carto":
			return false
		source_projection = source_projection.duplicate(true)
	_profile = _manifest.get("style_profile", {}) as Dictionary
	if _profile.is_empty():
		return false
	_build_record_index()
	for lod in [LOD_OPERATIONAL, LOD_DETAIL]:
		var layer := Node2D.new()
		layer.name = String(lod).capitalize() + "Tiles"
		layer.visible = false
		add_child(layer)
		_layers[lod] = layer
		_sprites[lod] = {}
	if not _load_strategic():
		return false
	# 初次同步选格也使用已生效的相机投影，不等下一帧才补载出生视口。
	if _camera.is_inside_tree() and _camera.is_current():
		_camera.force_update_scroll()
	_current_lod = _initial_lod(_camera.zoom.x)
	if _current_lod != LOD_STRATEGIC \
			and _visible_keys(_current_lod).size() > MAX_REQUIRED_TILES_PER_LOD:
		_current_lod = LOD_OPERATIONAL if _current_lod == LOD_DETAIL else LOD_STRATEGIC
	_target_lod = _current_lod
	if _current_lod != LOD_STRATEGIC:
		_load_required_sync(_current_lod)
		var initial_layer := _layers.get(_current_lod) as Node2D
		if initial_layer != null:
			initial_layer.visible = true
	_setup_elapsed_ms = Time.get_ticks_msec() - setup_started
	set_process(true)
	return true


func set_active(active: bool) -> void:
	if active != _active:
		presentation_changing.emit()
	_active = active
	visible = active
	set_process(active)
	if active:
		_tick_accum = UPDATE_INTERVAL_S


func resident_tile_count() -> int:
	var total := 0
	for lod in _sprites:
		total += (_sprites[lod] as Dictionary).size()
	return total


func estimated_texture_bytes() -> int:
	var total := 0
	if _grain_texture != null:
		total += GRAIN_TEXTURE_ESTIMATED_BYTES
	if typeof(_strategic_sprite)==TYPE_OBJECT and is_instance_valid(_strategic_sprite) and _strategic_sprite.texture != null:
		var strategic_size: Vector2 = _strategic_sprite.texture.get_size()
		total += int(strategic_size.x * strategic_size.y * 4.0)
	for lod in _sprites:
		for sprite_any in (_sprites[lod] as Dictionary).values():
			var sprite: Variant = sprite_any
			if typeof(sprite)!=TYPE_OBJECT or not is_instance_valid(sprite) or sprite.texture == null:
				continue
			var texture_size: Vector2 = sprite.texture.get_size()
			total += int(texture_size.x * texture_size.y * 4.0)
	return total


func debug_state() -> Dictionary:
	var required: Array[String] = []
	var missing: Array[String] = []
	if _target_lod != LOD_STRATEGIC:
		required = _visible_keys(_target_lod) \
			if _transitioning or _target_lod != _current_lod \
			else _required_keys(_target_lod)
		var target_sprites := _sprites.get(_target_lod, {}) as Dictionary
		for key in required:
			if not target_sprites.has(key):
				missing.append(key)
	var layer_state: Dictionary = {}
	for lod in [LOD_OPERATIONAL, LOD_DETAIL]:
		var layer := _layers.get(lod) as Node2D
		layer_state[String(lod)] = {
			"visible": layer != null and layer.visible,
			"alpha": layer.modulate.a if layer != null else 0.0,
			"z_index": layer.z_index if layer != null else 0,
			"sprite_count": (_sprites.get(lod, {}) as Dictionary).size(),
		}
	return {
		"map_root": _map_root,
		"projected_source": not source_projection.is_empty(),
		"projected_geometry_bytes": projected_geometry_bytes(),
		"source_kind": _manifest.get("volume_profile", {}).get("source_kind", "carto"),
		"current_lod": String(_current_lod),
		"target_lod": String(_target_lod),
		"transitioning": _transitioning,
		"pending_count": _pending.size(),
		"resource_load_backend": "main_deferred" if DisplayServer.get_name()=="headless" else "threaded",
		"resident_tiles": resident_tile_count(),
		"peak_resident_tiles": _peak_resident_tiles,
		"committed_tiles": resident_tile_count()+_pending.size(),
		"peak_committed_tiles": _peak_committed_tiles,
		"capacity_deferrals": _capacity_deferrals,
		"estimated_texture_bytes": estimated_texture_bytes(),
		"setup_elapsed_ms": _setup_elapsed_ms,
		"required_keys": required,
		"visible_tile_count": _visible_keys(_target_lod).size() if _target_lod != LOD_STRATEGIC else 0,
		"operational_visible_tile_count": _visible_keys(LOD_OPERATIONAL).size(),
		"detail_visible_tile_count": _visible_keys(LOD_DETAIL).size(),
		"missing_keys": missing,
		"strategic_visible": typeof(_strategic_sprite)==TYPE_OBJECT and is_instance_valid(_strategic_sprite) and _strategic_sprite.visible,
		"layers": layer_state,
	}


## 只读表现投影：共享已驻留纹理，不让三维地图建立第二套流送或地理。
func presentation_profile() -> Dictionary:
	return (_manifest.get("volume_profile", {}) as Dictionary).duplicate(true)


func shared_strategic_texture(map_key: String) -> Texture2D:
	if map_key != _map_key or not is_instance_valid(_strategic_sprite):
		return null
	return _strategic_sprite.texture


func presentation_tiles() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if typeof(_strategic_sprite)==TYPE_OBJECT and is_instance_valid(_strategic_sprite):
		result.append({"sprite": weakref(_strategic_sprite), "layer": null, "lod": LOD_STRATEGIC, "projected": not source_projection.is_empty()})
	for lod in _sprites:
		var layer: Node2D = _layers[lod]
		for sprite: Variant in _sprites[lod].values():
			if typeof(sprite)==TYPE_OBJECT and is_instance_valid(sprite):
				result.append({"sprite": weakref(sprite), "layer": weakref(layer), "lod": lod, "projected": not source_projection.is_empty()})
	return result


func _build_record_index() -> void:
	_records.clear()
	var levels: Dictionary = _manifest.get("levels", {}) as Dictionary
	for lod in [LOD_OPERATIONAL, LOD_DETAIL]:
		var by_key: Dictionary = {}
		var level: Dictionary = levels.get(lod, {}) as Dictionary
		for record_any in level.get("tiles", []):
			var record := record_any as Dictionary
			var key := _tile_key(int(record.get("row", 0)), int(record.get("column", 0)))
			by_key[key] = record
		_records[lod] = by_key


func _load_strategic() -> bool:
	var levels: Dictionary = _manifest.get("levels", {}) as Dictionary
	var level: Dictionary = levels.get(LOD_STRATEGIC, {}) as Dictionary
	var tiles: Array = level.get("tiles", []) as Array
	if tiles.is_empty():
		return false
	var record := tiles[0] as Dictionary
	var path := "%s/%s" % [_map_root, String(record.get("path", "strategic.webp"))]
	var texture := load_texture(path)
	if texture == null:
		return false
	_strategic_sprite = _new_tile_node()
	_strategic_sprite.name = "StrategicBasemap"
	_strategic_sprite.texture = texture
	_strategic_sprite.centered = false
	_strategic_sprite.position = _world_rect.position
	_strategic_sprite.scale = _world_rect.size / Vector2(texture.get_size())
	_strategic_sprite.z_index = -2
	_strategic_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	# 分档下采样会改变少量低频亮度；只在静态 Sprite 创建时乘色校准，
	# 不增加道路边缘、不随缩放更新 shader，也不触发地图重绘。
	var strategic_luma_scale := _profile_lod_float(
		_profile, "luma_scale", LOD_STRATEGIC, 1.0)
	_strategic_sprite.self_modulate = Color(
		strategic_luma_scale, strategic_luma_scale, strategic_luma_scale, 1.0)
	var size_values: Array = level.get("size", [1024, 1024]) as Array
	var level_size := Vector2(float(size_values[0]), float(size_values[1]))
	_strategic_sprite.material = make_material(
		_profile, level_size, Vector2.ZERO,
		Vector2(texture.get_size()), LOD_STRATEGIC)
	if not _prepare_tile_node(_strategic_sprite):
		_strategic_sprite.free()
		_strategic_sprite = null
		return false
	add_child(_strategic_sprite)
	move_child(_strategic_sprite, 0)
	presentation_revision += 1
	return true


func _process(delta: float) -> void:
	if not _active or _camera == null:
		return
	_tick_accum += delta
	if _tick_accum < UPDATE_INTERVAL_S:
		return
	_tick_accum = 0.0
	_update_target_lod()
	_reserve_target_capacity()
	_poll_pending()
	_evict_unused()
	_request_target_tiles()
	_try_begin_transition()
	_evict_unused()


func _initial_lod(zoom: float) -> StringName:
	if zoom <= STRATEGIC_EXIT_ZOOM:
		return LOD_STRATEGIC
	if zoom >= DETAIL_ENTER_ZOOM:
		return LOD_DETAIL
	return LOD_OPERATIONAL


func _update_target_lod() -> void:
	var zoom := _camera.zoom.x
	var desired := _target_lod
	match _current_lod:
		LOD_STRATEGIC:
			desired = LOD_OPERATIONAL if zoom >= STRATEGIC_EXIT_ZOOM else LOD_STRATEGIC
		LOD_OPERATIONAL:
			if zoom < STRATEGIC_ENTER_ZOOM:
				desired = LOD_STRATEGIC
			elif zoom >= DETAIL_ENTER_ZOOM:
				desired = LOD_DETAIL
		LOD_DETAIL:
			if zoom < STRATEGIC_ENTER_ZOOM:
				desired = LOD_STRATEGIC
			elif zoom < DETAIL_EXIT_ZOOM:
				desired = LOD_OPERATIONAL
			else:
				desired = LOD_DETAIL
	if desired != LOD_STRATEGIC \
			and _visible_keys(desired).size() > MAX_REQUIRED_TILES_PER_LOD:
		desired = LOD_OPERATIONAL if desired == LOD_DETAIL else LOD_STRATEGIC
	# 大幅滚轮跳档时，前后可见格之和可能越过 16 格硬峰值；先退到常驻
	# Strategic，再装目标层，避免为了一帧过渡把两个完整集合同时留在显存。
	if _current_lod != LOD_STRATEGIC and desired != LOD_STRATEGIC and desired != _current_lod:
		var current_visible_resident := 0
		var current_sprites := _sprites.get(_current_lod, {}) as Dictionary
		for key in _visible_keys(_current_lod):
			if current_sprites.has(key):
				current_visible_resident += 1
		if current_visible_resident + _visible_keys(desired).size() > HARD_RESIDENT_TILES:
			desired = LOD_STRATEGIC
	_target_lod = desired


func _request_target_tiles() -> void:
	if _target_lod == LOD_STRATEGIC:
		return
	var request_keys := _visible_keys(_target_lod) \
		if _transitioning or _target_lod != _current_lod \
		else _required_keys(_target_lod)
	for key in request_keys:
		if _pending.size() >= MAX_PENDING_LOADS:
			break
		if (_sprites[_target_lod] as Dictionary).has(key):
			_touch_lru(_resident_key(_target_lod, key))
			continue
		var resident_key := _resident_key(_target_lod, key)
		if _pending.has(resident_key):
			continue
		# 请求成功即占一个槽；旧层过渡仍可见时不能依靠事后LRU回收来守上限。
		if resident_tile_count()+_pending.size() >= HARD_RESIDENT_TILES:
			_capacity_deferrals += 1
			break
		var record: Dictionary = (_records[_target_lod] as Dictionary).get(key, {}) as Dictionary
		if record.is_empty():
			continue
		var path := _tile_path(_target_lod, record)
		var request := {"lod": _target_lod, "key": key, "record": record, "path": path}
		if ResourceLoader.exists(path):
			# Dummy纹理RID分配器同样不支持后台构造竞争；GL异步不变。
			if DisplayServer.get_name()=="headless":
				request["kind"]="main_resource"
				request["ready_frame"]=Engine.get_process_frames()+1
				_pending[resident_key]=request
				_peak_committed_tiles=maxi(_peak_committed_tiles,resident_tile_count()+_pending.size())
				continue
			var error := ResourceLoader.load_threaded_request(path, "Texture2D", true)
			if error == OK:
				request["kind"] = "resource"
				_pending[resident_key] = request
				_peak_committed_tiles = maxi(_peak_committed_tiles,resident_tile_count()+_pending.size())
		elif FileAccess.file_exists(path):
			var thread := Thread.new()
			var error := thread.start(_load_image_thread.bind(path))
			if error == OK:
				request["kind"] = "image"
				request["thread"] = thread
				_pending[resident_key] = request
				_peak_committed_tiles = maxi(_peak_committed_tiles,resident_tile_count()+_pending.size())


func _poll_pending() -> void:
	var bound := 0
	for resident_key in _pending.keys().duplicate():
		if bound >= MAX_TEXTURE_BINDS_PER_TICK:
			break
		var request: Dictionary = _pending[resident_key] as Dictionary
		var path := String(request.get("path", ""))
		var kind := String(request.get("kind", ""))
		if kind == "main_resource":
			if Engine.get_process_frames()<int(request.ready_frame):
				continue
			_pending.erase(resident_key)
			var texture := ResourceLoader.load(path,"Texture2D") as Texture2D
			if texture!=null:
				_add_tile(request.lod,request.key,request.record,texture,true)
			bound+=1
		elif kind == "resource":
			var status := ResourceLoader.load_threaded_get_status(path)
			if status == ResourceLoader.THREAD_LOAD_LOADED:
				var texture := ResourceLoader.load_threaded_get(path) as Texture2D
				_pending.erase(resident_key)
				if texture != null:
					_add_tile(request.lod, request.key, request.record, texture, true)
				bound += 1
			elif status == ResourceLoader.THREAD_LOAD_FAILED or status == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
				_pending.erase(resident_key)
		elif kind == "image":
			var thread := request.get("thread") as Thread
			if thread == null or thread.is_alive():
				continue
			var image = thread.wait_to_finish()
			_pending.erase(resident_key)
			if image is Image and not image.is_empty():
				var texture := ImageTexture.create_from_image(image)
				_add_tile(request.lod, request.key, request.record, texture, true)
			bound += 1


func _load_image_thread(path: String) -> Image:
	return Image.load_from_file(path)


func _exit_tree() -> void:
	presentation_changing.emit()
	for request_any in _pending.values():
		var request := request_any as Dictionary
		var kind := String(request.get("kind", ""))
		if kind == "image":
			var thread := request.get("thread") as Thread
			if thread != null and thread.is_started():
				thread.wait_to_finish()
		elif kind == "resource":
			# ResourceLoader 没有取消 API；退出时取回并立即释放，避免异步请求
			# 跨过场景清理边界而被误报为仍在使用的纹理资源。
			ResourceLoader.load_threaded_get(String(request.get("path", "")))
	_pending.clear()
	# ShaderMaterial 会持有共享 ImageTexture；退出时主动断开，避免快速 bench quit
	# 把仍待销毁的材质/纹理误报为资源泄漏。
	if typeof(_strategic_sprite)==TYPE_OBJECT and is_instance_valid(_strategic_sprite):
		_strategic_sprite.material = null
	for lod in _sprites:
		for sprite_any in (_sprites[lod] as Dictionary).values():
			var sprite: Variant = sprite_any
			if typeof(sprite)==TYPE_OBJECT and is_instance_valid(sprite):
				sprite.material = null
	_grain_texture = null


func _load_required_sync(lod: StringName) -> void:
	for key in _required_keys(lod):
		var record: Dictionary = (_records[lod] as Dictionary).get(key, {}) as Dictionary
		if record.is_empty():
			continue
		var texture := load_texture(_tile_path(lod, record))
		if texture != null:
			_add_tile(lod, key, record, texture, false)


func _add_tile(
		lod: StringName,
		key: String,
		record: Dictionary,
		texture: Texture2D,
		fade_in: bool) -> void:
	var by_key := _sprites[lod] as Dictionary
	if by_key.has(key):
		return
	presentation_changing.emit()
	var levels: Dictionary = _manifest.get("levels", {}) as Dictionary
	var level: Dictionary = levels.get(lod, {}) as Dictionary
	var size_values: Array = level.get("size", [8704, 8704]) as Array
	var level_size := Vector2(float(size_values[0]), float(size_values[1]))
	var content_rect_values: Array = record.get("content_rect", [0, 0, CONTENT_SIZE, CONTENT_SIZE]) as Array
	var content_pos := Vector2(float(content_rect_values[0]), float(content_rect_values[1]))
	var content_size := Vector2(float(content_rect_values[2]), float(content_rect_values[3]))
	var sprite: Variant = _new_tile_node()
	sprite.name = "%s_%s" % [String(lod), key]
	sprite.texture = texture
	sprite.centered = false
	sprite.region_enabled = true
	sprite.region_rect = Rect2(Vector2(GUTTER, GUTTER), content_size)
	sprite.position = _world_rect.position + content_pos / level_size * _world_rect.size
	sprite.scale = _world_rect.size / level_size
	sprite.z_index = -1 if lod == LOD_OPERATIONAL else 0
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	var luma_scale := _profile_lod_float(_profile, "luma_scale", lod, 1.0)
	sprite.self_modulate = Color(luma_scale, luma_scale, luma_scale, 1.0)
	var tile_origin := content_pos - Vector2(GUTTER, GUTTER)
	sprite.material = make_material(
		_profile, level_size, tile_origin, Vector2(texture.get_size()), lod)
	if not _prepare_tile_node(sprite):
		sprite.free()
		return
	var layer := _layers[lod] as Node2D
	layer.add_child(sprite)
	by_key[key] = sprite
	presentation_revision += 1
	_peak_resident_tiles = maxi(_peak_resident_tiles, resident_tile_count())
	_peak_committed_tiles = maxi(_peak_committed_tiles,resident_tile_count()+_pending.size())
	_touch_lru(_resident_key(lod, key))
	if fade_in:
		PerfBuckets.mark_frame_event("raster_tile_bind")
		PerfBuckets.count("raster_tile_binds")
	if fade_in and lod == _current_lod and layer.visible:
		sprite.modulate.a = 0.0
		var tween: Tween = sprite.create_tween()
		tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		tween.tween_property(sprite, "modulate:a", 1.0, TRANSITION_S)


func _try_begin_transition() -> void:
	if _transitioning or _target_lod == _current_lod:
		return
	if _target_lod != LOD_STRATEGIC:
		var target_sprites := _sprites[_target_lod] as Dictionary
		for key in _visible_keys(_target_lod):
			if not target_sprites.has(key):
				return
	_begin_transition(_target_lod)


func _begin_transition(next_lod: StringName) -> void:
	presentation_changing.emit()
	_transitioning = true
	PerfBuckets.mark_frame_event("raster_lod_transition")
	var old_lod := _current_lod
	_transition_from_lod = old_lod
	var old_layer := _layers.get(old_lod) as Node2D
	var next_layer := _layers.get(next_lod) as Node2D
	if next_layer != null:
		next_layer.visible = true
		next_layer.modulate.a = 0.0
		# alpha-over 的正确交叉覆盖：旧层保持不透明，目标层临时放在最上方淡入。
		# 两层同时淡出/淡入会在中点露出 Strategic/底色，形成滚轮明暗呼吸。
		next_layer.z_index = TRANSITION_TARGET_Z
		var tween_in := next_layer.create_tween()
		tween_in.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		tween_in.tween_property(next_layer, "modulate:a", 1.0, TRANSITION_S)
	if old_layer != null and next_layer == null:
		var tween_out := old_layer.create_tween()
		tween_out.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		tween_out.tween_property(old_layer, "modulate:a", 0.0, TRANSITION_S)
	_current_lod = next_lod
	var timer := get_tree().create_timer(TRANSITION_S)
	timer.timeout.connect(func() -> void:
		if old_layer != null:
			old_layer.visible = false
			old_layer.modulate.a = 1.0
		if next_layer != null:
			next_layer.modulate.a = 1.0
			next_layer.z_index = 0
		_transitioning = false
		_transition_from_lod = LOD_STRATEGIC
		_evict_unused()
		# 一次滚轮可能跨两档；首段完成后立即继续，不额外暴露一个 10 Hz 空窗。
		_update_target_lod()
		_request_target_tiles()
		_try_begin_transition()
	)


func _required_keys(lod: StringName) -> Array[String]:
	var output: Array[String] = []
	for candidate in _tile_candidates(lod, true):
		if output.size() >= MAX_REQUIRED_TILES_PER_LOD:
			break
		output.append(String(candidate.key))
	return output


func _visible_keys(lod: StringName) -> Array[String]:
	var output: Array[String] = []
	for candidate in _tile_candidates(lod, false):
		output.append(String(candidate.key))
	return output


func _tile_candidates(lod: StringName, include_prefetch_ring: bool) -> Array[Dictionary]:
	var candidates: Array[Dictionary] = []
	var levels: Dictionary = _manifest.get("levels", {}) as Dictionary
	var level: Dictionary = levels.get(lod, {}) as Dictionary
	if level.is_empty():
		return candidates
	var size_values: Array = level.get("size", [8704, 8704]) as Array
	var level_size := Vector2(float(size_values[0]), float(size_values[1]))
	var rows := int(level.get("rows", 1))
	var columns := int(level.get("columns", 1))
	# 使用最终 Canvas 投影，覆盖镜头旋转、offset/平滑和父变换；不是相机位置的未旋转矩形。
	var viewport_size := get_viewport_rect().size
	var inverse := get_global_transform_with_canvas().affine_inverse()
	if not _camera.is_current():
		# 离屏三维观察场给的是逻辑 Camera2D；它不接管屏幕 Canvas，仍以传入相机选格。
		var angle := 0.0 if _camera.ignore_rotation else _camera.global_rotation
		inverse = Transform2D(angle, _camera.global_position + _camera.offset).scaled_local(Vector2.ONE / _camera.zoom)
		inverse = inverse.translated_local(-viewport_size * 0.5)
		inverse = global_transform.affine_inverse() * inverse
	var view_polygon := PackedVector2Array([Vector2.ZERO, Vector2(viewport_size.x, 0),
		viewport_size, Vector2(0, viewport_size.y)])
	for index in 4:
		view_polygon[index] = (inverse * view_polygon[index] - _world_rect.position) / _world_rect.size * level_size
	var view_px := Rect2(view_polygon[0], Vector2.ZERO)
	for index in range(1, 4):
		view_px = view_px.expand(view_polygon[index])
	if not view_px.intersects(Rect2(Vector2.ZERO, level_size), true):
		return candidates
	# 凸四边形与轴对齐瓦片的 SAT：世界 X/Y 已由包围盒筛选，另检查视口两组边法线。
	var axes := PackedVector2Array([(view_polygon[1] - view_polygon[0]).orthogonal().normalized(),
		(view_polygon[3] - view_polygon[0]).orthogonal().normalized()])
	var intervals := PackedVector2Array()
	for axis in axes:
		var interval := Vector2(axis.dot(view_polygon[0]), axis.dot(view_polygon[0]))
		for index in range(1, 4):
			var projection := axis.dot(view_polygon[index])
			interval.x = minf(interval.x, projection)
			interval.y = maxf(interval.y, projection)
		intervals.append(interval)
	var source_view := view_px
	if not source_projection.is_empty():
		var geo := preload("res://scripts/experiments/tokyo_raster_projection.gd")
		var raw_top := geo.raw_y(_world_rect.position.y+view_px.position.y/level_size.y*_world_rect.size.y,source_projection)
		var raw_bottom := geo.raw_y(_world_rect.position.y+view_px.end.y/level_size.y*_world_rect.size.y,source_projection)
		source_view.position.y = (raw_top-_world_rect.position.y)/_world_rect.size.y*level_size.y
		source_view.size.y = (raw_bottom-raw_top)/_world_rect.size.y*level_size.y
	var visible_min_col := clampi(int(floor(view_px.position.x / CONTENT_SIZE)), 0, columns - 1)
	var visible_max_col := clampi(int(floor(view_px.end.x / CONTENT_SIZE)), 0, columns - 1)
	var visible_min_row := clampi(int(floor(source_view.position.y / CONTENT_SIZE)), 0, rows - 1)
	var visible_max_row := clampi(int(floor(source_view.end.y / CONTENT_SIZE)), 0, rows - 1)
	var ring := 1 if include_prefetch_ring else 0
	var min_col := maxi(0, visible_min_col - ring)
	var max_col := mini(columns - 1, visible_max_col + ring)
	var min_row := maxi(0, visible_min_row - ring)
	var max_row := mini(rows - 1, visible_max_row + ring)
	var center_px := (view_polygon[0] + view_polygon[2]) * 0.5
	for row in range(min_row, max_row + 1):
		var row_top := float(row*CONTENT_SIZE)
		var row_bottom := float((row+1)*CONTENT_SIZE)
		if not source_projection.is_empty():
			var geo := preload("res://scripts/experiments/tokyo_raster_projection.gd")
			row_top = (geo.world_y(_world_rect.position.y+row_top/level_size.y*_world_rect.size.y,source_projection)-_world_rect.position.y)/_world_rect.size.y*level_size.y
			row_bottom = (geo.world_y(_world_rect.position.y+row_bottom/level_size.y*_world_rect.size.y,source_projection)-_world_rect.position.y)/_world_rect.size.y*level_size.y
		for column in range(min_col, max_col + 1):
			var visible_tile := column >= visible_min_col and column <= visible_max_col \
				and row >= visible_min_row and row <= visible_max_row
			var tile_center := Vector2((column + 0.5)*CONTENT_SIZE,(row_top+row_bottom)*0.5)
			if visible_tile:
				for axis_index in 2:
					var axis: Vector2 = axes[axis_index]
					var midpoint := axis.dot(tile_center)
					var radius := (absf(axis.x)*CONTENT_SIZE + absf(axis.y)*(row_bottom-row_top))*0.5
					if midpoint + radius < intervals[axis_index].x or midpoint - radius > intervals[axis_index].y:
						visible_tile = false
						break
			if not include_prefetch_ring and not visible_tile:
				continue
			candidates.append({
				"key": _tile_key(row, column),
				"visible": visible_tile,
				"distance": tile_center.distance_squared_to(center_px),
			})
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if bool(a.visible) != bool(b.visible):
			return bool(a.visible)
		return float(a.distance) < float(b.distance)
	)
	return candidates


func _evict_unused() -> void:
	if resident_tile_count() <= MAX_RESIDENT_TILES:
		return
	var protected: Dictionary = {}
	if _current_lod != LOD_STRATEGIC:
		var current_keys := _visible_keys(_current_lod) \
			if _transitioning or _target_lod != _current_lod \
			else _required_keys(_current_lod)
		for key in current_keys:
			protected[_resident_key(_current_lod, key)] = true
	if _transitioning and _transition_from_lod != LOD_STRATEGIC:
		for key in _visible_keys(_transition_from_lod):
			protected[_resident_key(_transition_from_lod, key)] = true
	if _target_lod != LOD_STRATEGIC and _target_lod != _current_lod:
		for key in _visible_keys(_target_lod):
			protected[_resident_key(_target_lod, key)] = true
	_evict_to_limit(MAX_RESIDENT_TILES, protected)
	if resident_tile_count() > HARD_RESIDENT_TILES:
		push_warning("Raster basemap hard tile cap exceeded: %d (lru=%d protected=%d current=%s/%d target=%s/%d transitioning=%s)" % [
			resident_tile_count(), _lru.size(), protected.size(),
			String(_current_lod), _visible_keys(_current_lod).size() if _current_lod != LOD_STRATEGIC else 0,
			String(_target_lod), _visible_keys(_target_lod).size() if _target_lod != LOD_STRATEGIC else 0,
			_transitioning])


func _reserve_target_capacity() -> void:
	if _target_lod == LOD_STRATEGIC or _target_lod == _current_lod or _transitioning:
		return
	var target_visible := _visible_keys(_target_lod)
	var target_sprites := _sprites.get(_target_lod, {}) as Dictionary
	var missing_count := 0
	for key in target_visible:
		if not target_sprites.has(key):
			missing_count += 1
	var keep_limit := maxi(0, HARD_RESIDENT_TILES - missing_count)
	if resident_tile_count() <= keep_limit:
		return
	var protected: Dictionary = {}
	if _current_lod != LOD_STRATEGIC:
		for key in _visible_keys(_current_lod):
			protected[_resident_key(_current_lod, key)] = true
	for key in target_visible:
		protected[_resident_key(_target_lod, key)] = true
	_evict_to_limit(keep_limit, protected)


func _evict_to_limit(limit: int, protected: Dictionary) -> void:
	var index := 0
	while resident_tile_count() > limit and index < _lru.size():
		var resident_key := _lru[index]
		if protected.has(resident_key):
			index += 1
			continue
		_remove_resident(resident_key)


func _remove_resident(resident_key: String) -> void:
	var parts := resident_key.split(":", false, 1)
	if parts.size() != 2:
		return
	var lod := StringName(parts[0])
	var key := parts[1]
	var by_key := _sprites.get(lod, {}) as Dictionary
	var sprite: Variant = by_key.get(key)
	if typeof(sprite)==TYPE_OBJECT and is_instance_valid(sprite):
		presentation_tile_retiring.emit(sprite.get_instance_id())
		presentation_changing.emit()
		# 先让借用者同步退役，再断开纹理；不能把排队释放的纹理提前当空槽重新分配。
		sprite.texture = null
		sprite.material = null
		# 同帧重入同一瓦片时必须先归还节点名；queue_free延后会令新节点自动改名，
		# 破坏以稳定瓦片名读取预建几何的桥接。
		if sprite.get_parent() != null:
			sprite.get_parent().remove_child(sprite)
		sprite.queue_free()
	by_key.erase(key)
	presentation_revision += 1
	_lru.erase(resident_key)


func _touch_lru(resident_key: String) -> void:
	_lru.erase(resident_key)
	_lru.append(resident_key)


func _tile_path(lod: StringName, record: Dictionary) -> String:
	return "%s/%s/%s" % [_map_root, String(lod), String(record.get("path", ""))]


func _tile_key(row: int, column: int) -> String:
	return "r%02d_c%02d" % [row, column]


func _resident_key(lod: StringName, key: String) -> String:
	return "%s:%s" % [String(lod), key]


func _new_tile_node() -> Node2D:
	return Sprite2D.new() if source_projection.is_empty() else preload("res://scripts/rendering/projected_raster_tile.gd").new()


func _prepare_tile_node(node: Variant) -> bool:
	if source_projection.is_empty():
		return true
	node.configure(source_projection)
	var total := projected_geometry_bytes()+int(node.geometry_bytes if node!=_strategic_sprite else 0)
	if total>PROJECTED_GEOMETRY_RESERVE:
		push_error("Projected raster geometry exceeded reserved budget")
		return false
	return true


func projected_geometry_bytes() -> int:
	if source_projection.is_empty():
		return 0
	var total := int(_strategic_sprite.geometry_bytes) if typeof(_strategic_sprite)==TYPE_OBJECT and is_instance_valid(_strategic_sprite) else 0
	for lod in _sprites:
		for node: Variant in _sprites[lod].values():
			if typeof(node)==TYPE_OBJECT and is_instance_valid(node):
				total += int(node.geometry_bytes)
	return total
