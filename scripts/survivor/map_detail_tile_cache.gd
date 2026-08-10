class_name MapDetailTileCache
extends Node2D

## 东京湾整图近景矢量瓦片缓存。
##
## loading 只预热玩家出生区；运行时在 Detail 真正可见前按相机视野请求一圈
## 缓冲瓦片，并用 LRU 控制常驻纹理。每块仍走已批准金样的 2x 超采样 +
## GPU 两级线性降采样路线。地图内容来自压缩矢量包，不从磁盘加载任何地图 PNG。

const DirectRenderer = preload("res://scripts/survivor/map_detail_vector_renderer.gd")
const MANIFEST_PATH := "res://resources/maps/tokyo_bay_detail_tiles_full.json"
const CACHE_CONTENT_SIZE := Vector2i(1536, 1536)
const CACHE_PADDING_PX := 4
const CACHE_SIZE := Vector2i(1544, 1544)
const SOURCE_SIZE := Vector2i(3072, 3072)
const MAX_CACHE_TILES := 12
const PREFETCH_ZOOM := 0.46
const FADE_ZOOM_START := 0.50
const FADE_ZOOM_END := 0.98
const FADE_EXPONENT := 1.75
const PREFETCH_MARGIN_PX := 900.0
const REQUEST_MOVE_THRESHOLD_PX := 240.0
const TILE_APPEAR_SECONDS := 0.22
const COVERAGE_CHECK_MOVE_PX := 96.0
const COVERAGE_CHECK_ZOOM_DELTA := 0.02
const COVERAGE_FADE_SECONDS := 0.18
const PREWARM_VIEW_MARGIN_PX := 64.0
const DETAIL_COLOR_LIFT := Color(1.25, 1.25, 1.24, 1.0)
const BOOTSTRAP_REGION := Rect2(Vector2(-2400.0, 10800.0), Vector2(4800.0, 4200.0))

static var _tile_specs: Array = []
static var _cached_tiles: Dictionary = {}
static var _cache_metrics: Dictionary = {}
static var _cache_error := ""
static var _baking := false
static var _use_clock := 0

var _camera: Camera2D = null
var _sprites: Dictionary = {}
var _request_queue: Array = []
var _queued_ids: Dictionary = {}
var _draining := false
var _last_request_center := Vector2(INF, INF)
var _last_request_zoom := -1.0
var _protected_ids: Dictionary = {}
var _coverage_dirty := true
var _coverage_complete := false
var _last_coverage_center := Vector2(INF, INF)
var _last_coverage_zoom := -1.0
var _coverage_alpha := 0.0
# 帧数是地图的硬门：战斗中禁止 SubViewport 烘焙与 GPU readback。
# 未驻留区域继续显示 Operational 概括层；detail 只能由 loading/安全暂停显式 bake_region 后启用。
var _streaming_enabled := false


func _ready() -> void:
	# 跨区 detail 只允许在 Tab 真暂停时烘焙；ALWAYS 让一次性 viewport/await
	# 在暂停树中继续完成，但不会开启相机驱动的战斗中 streaming。
	process_mode = Node.PROCESS_MODE_ALWAYS


static func cache_ready() -> bool:
	return not _cached_tiles.is_empty()


static func cache_status() -> Dictionary:
	if cache_ready():
		return _cache_metrics.duplicate(true)
	return {"ok": false, "baking": _baking, "error": _cache_error}


static func cache_plan() -> Dictionary:
	if not _load_tile_specs():
		return {"ok": false, "error": _cache_error}
	var bootstrap_specs := _specs_intersecting(BOOTSTRAP_REGION)
	var bootstrap_paths: Array[String] = []
	for spec_any in bootstrap_specs:
		bootstrap_paths.append(String((spec_any as Dictionary).get("data_path", "")))
	var bytes_per_tile := CACHE_SIZE.x * CACHE_SIZE.y * 4
	return {
		"ok": true,
		"tile_count": _tile_specs.size(),
		"bootstrap_tile_count": bootstrap_specs.size(),
		"bootstrap_data_paths": bootstrap_paths,
		"max_cache_tiles": MAX_CACHE_TILES,
		"cache_bytes_rgba8": MAX_CACHE_TILES * bytes_per_tile,
		"peak_bytes_rgba8": MAX_CACHE_TILES * bytes_per_tile + SOURCE_SIZE.x * SOURCE_SIZE.y * 4,
		"max_main_canvas_draw_calls": MAX_CACHE_TILES,
	}


func setup_camera(camera: Camera2D) -> void:
	_camera = camera


func set_streaming_enabled(enabled: bool) -> void:
	_streaming_enabled = enabled


func set_detail_zoom(zoom_value: float, enabled: bool, delta: float = 1.0 / 60.0) -> void:
	if not enabled:
		visible = false
		modulate.a = 0.0
		_coverage_alpha = 0.0
		return
	_refresh_viewport_coverage(zoom_value)
	var zoom_opacity := detail_opacity_for_zoom(zoom_value)
	var target_coverage := 1.0 if _coverage_complete else 0.0
	_coverage_alpha = move_toward(_coverage_alpha, target_coverage,
		maxf(delta, 0.0) / COVERAGE_FADE_SECONDS)
	# zoom 权重必须直接取连续曲线，不能沿用上一档 alpha 慢慢追目标；否则快速滚轮会整图忽明忽暗。
	# 只有“瓦片覆盖是否完整”使用时间淡入，最终 alpha 为两个独立权重的乘积。
	modulate.a = zoom_opacity * _coverage_alpha
	visible = modulate.a > 0.001 or (zoom_opacity > 0.001 and target_coverage > 0.0)
	if _streaming_enabled and zoom_value >= PREFETCH_ZOOM and _camera != null:
		_refresh_camera_requests(zoom_value)


static func detail_opacity_for_zoom(zoom_value: float) -> float:
	# 完整 Detail 的低透明度也很显眼；感知曲线压低中段，避免一个滚轮步长突然糊满建筑。
	return pow(smoothstep(FADE_ZOOM_START, FADE_ZOOM_END, zoom_value), FADE_EXPONENT)


func attach_cached() -> Dictionary:
	if not cache_ready():
		return {"ok": false, "error": _cache_error if _cache_error != "" else "detail tiles not prewarmed"}
	for tile_id_any in _cached_tiles:
		var tile_id := String(tile_id_any)
		_attach_sprite(tile_id, false)
	_rebuild_metrics()
	var result := _cache_metrics.duplicate(true)
	result["cache_hit"] = true
	return result


func bake_cache() -> Dictionary:
	if not _load_tile_specs():
		return {"ok": false, "error": _cache_error}
	var specs := _specs_intersecting(BOOTSTRAP_REGION)
	return await _bake_spec_list(specs, {})


func bake_region(region: Rect2, priority_points: Array = []) -> Dictionary:
	if not _load_tile_specs():
		return {"ok": false, "error": _cache_error}
	var specs := _specs_intersecting(region)
	_limit_specs_nearest(specs, region.get_center(), priority_points)
	var protected: Dictionary = {}
	for spec_any in specs:
		protected[String((spec_any as Dictionary).get("id", ""))] = true
	return await _bake_spec_list(specs, protected)


## 安全暂停专用：多个真实视口所需的瓦片必须整批装入；超过 LRU 上限就拒绝，
## 绝不截断成用户可见的半屏 Detail。
func bake_regions(regions: Array) -> Dictionary:
	if not _load_tile_specs():
		return {"ok": false, "error": _cache_error}
	var specs := _specs_for_regions(regions)
	if specs.is_empty():
		return {"ok": true, "empty": true, "tile_count": 0}
	if specs.size() > MAX_CACHE_TILES:
		return {
			"ok": false,
			"error": "detail viewport union needs %d tiles; cache limit is %d" % [
				specs.size(), MAX_CACHE_TILES],
			"required_tile_count": specs.size(),
		}
	var protected: Dictionary = {}
	for spec_any in specs:
		protected[String((spec_any as Dictionary).get("id", ""))] = true
	return await _bake_spec_list(specs, protected)


static func viewport_region(center: Vector2, viewport_pixels: Vector2,
		zoom_value: float = FADE_ZOOM_END) -> Rect2:
	var world_size := viewport_pixels / maxf(zoom_value, 0.001)
	return Rect2(center - world_size * 0.5, world_size).grow(PREWARM_VIEW_MARGIN_PX)


static func regions_plan(regions: Array) -> Dictionary:
	if not _load_tile_specs():
		return {"ok": false, "error": _cache_error}
	var specs := _specs_for_regions(regions)
	var ids: Array[String] = []
	for spec_any in specs:
		ids.append(String((spec_any as Dictionary).get("id", "")))
	return {
		"ok": specs.size() <= MAX_CACHE_TILES,
		"tile_count": specs.size(),
		"tile_ids": ids,
		"cache_limit": MAX_CACHE_TILES,
	}


static func region_plan(region: Rect2, priority_points: Array = []) -> Dictionary:
	if not _load_tile_specs():
		return {"ok": false, "error": _cache_error}
	var specs := _specs_intersecting(region)
	var priority_available: Array[bool] = []
	for point_any in priority_points:
		var point: Vector2 = point_any
		var available := false
		for spec_any in specs:
			var candidate_rect: Rect2 = (spec_any as Dictionary).get("rect", Rect2())
			if candidate_rect.has_point(point):
				available = true
				break
		priority_available.append(available)
	_limit_specs_nearest(specs, region.get_center(), priority_points)
	var tile_ids: Array[String] = []
	var tile_rects: Array[Rect2] = []
	for spec_any in specs:
		var spec: Dictionary = spec_any
		tile_ids.append(String(spec.get("id", "")))
		tile_rects.append(spec.get("rect", Rect2()))
	var priority_covered: Array[bool] = []
	for point_any in priority_points:
		var point: Vector2 = point_any
		var covered := false
		for tile_rect in tile_rects:
			if tile_rect.has_point(point):
				covered = true
				break
		priority_covered.append(covered)
	return {
		"ok": not specs.is_empty(),
		"tile_count": specs.size(),
		"tile_ids": tile_ids,
		"priority_available": priority_available,
		"priority_covered": priority_covered,
	}


func _bake_spec_list(specs: Array, protected: Dictionary) -> Dictionary:
	if _baking:
		return {"ok": false, "error": "detail tile bake already in progress"}
	_baking = true
	var started_ms := Time.get_ticks_msec()
	var baked_count := 0
	for spec_any in specs:
		var spec: Dictionary = spec_any
		var tile_id := String(spec.get("id", ""))
		if _cached_tiles.has(tile_id):
			_touch(tile_id)
			continue
		var result: Dictionary = await _bake_one(spec, protected)
		if not bool(result.get("ok", false)):
			_baking = false
			_cache_error = String(result.get("error", "detail tile bake failed"))
			return result
		baked_count += 1
	_baking = false
	_coverage_dirty = true
	_rebuild_metrics()
	_cache_metrics["last_batch_ms"] = Time.get_ticks_msec() - started_ms
	_cache_metrics["last_batch_baked"] = baked_count
	return _cache_metrics.duplicate(true)


func _bake_one(spec: Dictionary, protected: Dictionary) -> Dictionary:
	var tile_id := String(spec.get("id", ""))
	var data_path := String(spec.get("data_path", ""))
	# AGDT 解压与数百万线段三角化只碰纯数据，放到 WorkerThreadPool；主线程继续刷新
	# loading UI / 战斗画面，完成后才在主线程提交一次静态 SubViewport。
	var task_id := WorkerThreadPool.add_task(
		func() -> void: DirectRenderer.prewarm(data_path), false, "map detail %s" % tile_id)
	while not WorkerThreadPool.is_task_completed(task_id):
		await get_tree().process_frame
	WorkerThreadPool.wait_for_task_completion(task_id)
	var direct_metrics: Dictionary = DirectRenderer.prewarm(data_path)
	if not bool(direct_metrics.get("ok", false)):
		return direct_metrics
	var baked: Dictionary = await _bake_tile(spec)
	DirectRenderer.release_prewarm(data_path)
	if not bool(baked.get("ok", false)):
		return baked
	while _cached_tiles.size() >= MAX_CACHE_TILES:
		if not _evict_oldest(protected):
			return {"ok": false, "error": "detail cache has no evictable tile"}
	_use_clock += 1
	_cached_tiles[tile_id] = {
		"id": tile_id,
		"rect": spec.get("rect", Rect2()),
		"texture": baked.get("texture"),
		"last_used": _use_clock,
		"triangles": int(direct_metrics.get("triangles", 0)),
		"bake_ms": int(baked.get("bake_ms", 0)),
		"readback_ms": int(baked.get("readback_ms", 0)),
		"image_worker_ms": int(baked.get("image_worker_ms", 0)),
		"upload_ms": int(baked.get("upload_ms", 0)),
	}
	return {"ok": true, "tile_id": tile_id}


func _bake_tile(spec: Dictionary) -> Dictionary:
	var detail_rect: Rect2 = spec.get("rect", Rect2())
	var data_path := String(spec.get("data_path", ""))
	if detail_rect.size.x <= 0.0 or detail_rect.size.y <= 0.0:
		return {"ok": false, "error": "invalid detail tile rect"}
	var started_ms := Time.get_ticks_msec()
	var source_viewport := SubViewport.new()
	source_viewport.name = "DetailSupersample_%s" % String(spec.get("id", "tile"))
	source_viewport.size = SOURCE_SIZE
	source_viewport.transparent_bg = true
	source_viewport.disable_3d = true
	source_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(source_viewport)

	var content := Node2D.new()
	content.name = "DetailSupersampleContent"
	content.scale = Vector2(SOURCE_SIZE) / detail_rect.size
	content.position = -detail_rect.position * content.scale
	source_viewport.add_child(content)
	var direct_renderer: Node2D = DirectRenderer.new()
	direct_renderer.name = "DetailCacheSource"
	content.add_child(direct_renderer)
	var setup_metrics: Dictionary = direct_renderer.setup(data_path)
	if not bool(setup_metrics.get("ok", false)):
		source_viewport.queue_free()
		return setup_metrics

	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	source_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED

	# 2× 超采样仍由源 viewport 保证；第二个一次性 viewport 在 GPU 上做线性降采样，
	# 只把 1536² 结果读回 CPU。避免运行中每块约 168 ms 的 CPU Lanczos 主线程尖峰。
	var downsample_viewport := SubViewport.new()
	downsample_viewport.name = "DetailDownsample_%s" % String(spec.get("id", "tile"))
	downsample_viewport.size = CACHE_CONTENT_SIZE
	downsample_viewport.transparent_bg = true
	downsample_viewport.disable_3d = true
	downsample_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(downsample_viewport)
	var sample_sprite := Sprite2D.new()
	sample_sprite.position = Vector2(CACHE_CONTENT_SIZE) * 0.5
	sample_sprite.texture = source_viewport.get_texture()
	sample_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	sample_sprite.scale = Vector2(CACHE_CONTENT_SIZE) / Vector2(SOURCE_SIZE)
	downsample_viewport.add_child(sample_sprite)
	downsample_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var readback_started_ms := Time.get_ticks_msec()
	var cached_image := downsample_viewport.get_texture().get_image()
	var readback_ms := Time.get_ticks_msec() - readback_started_ms
	if cached_image == null or cached_image.is_empty():
		source_viewport.queue_free()
		downsample_viewport.queue_free()
		return {"ok": false, "error": "downsample viewport readback failed"}
	var image_worker_started_ms := Time.get_ticks_msec()
	var padded_image := _prepare_cached_image(cached_image)
	var image_worker_ms := Time.get_ticks_msec() - image_worker_started_ms
	if padded_image == null or padded_image.is_empty():
		return {"ok": false, "error": "detail image padding failed"}
	var upload_started_ms := Time.get_ticks_msec()
	var texture := ImageTexture.create_from_image(padded_image)
	var upload_ms := Time.get_ticks_msec() - upload_started_ms
	source_viewport.queue_free()
	downsample_viewport.queue_free()
	await get_tree().process_frame
	return {
		"ok": texture != null,
		"texture": texture,
		"bake_ms": Time.get_ticks_msec() - started_ms,
		"readback_ms": readback_ms,
		"image_worker_ms": image_worker_ms,
		"upload_ms": upload_ms,
	}


func _refresh_camera_requests(zoom_value: float) -> void:
	var center := _camera.global_position
	if _last_request_center.x != INF \
			and center.distance_to(_last_request_center) < REQUEST_MOVE_THRESHOLD_PX \
			and absf(zoom_value - _last_request_zoom) < 0.03:
		return
	_last_request_center = center
	_last_request_zoom = zoom_value
	var viewport_size := get_viewport_rect().size / maxf(zoom_value, 0.001)
	var region := Rect2(center - viewport_size * 0.5, viewport_size).grow(PREFETCH_MARGIN_PX)
	var specs := _specs_intersecting(region)
	_limit_specs_nearest(specs, center)
	_protected_ids.clear()
	for spec_any in specs:
		var spec: Dictionary = spec_any
		var tile_id := String(spec.get("id", ""))
		_protected_ids[tile_id] = true
		if _cached_tiles.has(tile_id):
			_touch(tile_id)
			_attach_sprite(tile_id, false)
		elif not _queued_ids.has(tile_id):
			_request_queue.append(spec)
			_queued_ids[tile_id] = true
	if not _request_queue.is_empty() and not _draining:
		call_deferred("_drain_request_queue")


func _refresh_viewport_coverage(zoom_value: float) -> void:
	if _camera == null or zoom_value < FADE_ZOOM_START:
		_coverage_complete = false
		return
	var center := _camera.global_position
	if not _coverage_dirty and _last_coverage_center.x != INF \
			and center.distance_to(_last_coverage_center) < COVERAGE_CHECK_MOVE_PX \
			and absf(zoom_value - _last_coverage_zoom) < COVERAGE_CHECK_ZOOM_DELTA:
		return
	_coverage_dirty = false
	_last_coverage_center = center
	_last_coverage_zoom = zoom_value
	var region := viewport_region(center, get_viewport_rect().size, zoom_value)
	_coverage_complete = true
	for spec_any in _specs_intersecting(region):
		var tile_id := String((spec_any as Dictionary).get("id", ""))
		if not _cached_tiles.has(tile_id):
			_coverage_complete = false
			break


func _drain_request_queue() -> void:
	if _draining or _baking:
		return
	_draining = true
	while not _request_queue.is_empty():
		var spec: Dictionary = _request_queue.pop_front()
		var tile_id := String(spec.get("id", ""))
		_queued_ids.erase(tile_id)
		if _cached_tiles.has(tile_id):
			continue
		var result: Dictionary = await _bake_spec_list([spec], _protected_ids)
		if not bool(result.get("ok", false)):
			push_warning("Detail tile %s skipped: %s" % [tile_id, result.get("error", "unknown")])
			continue
		_attach_sprite(tile_id, true)
	_draining = false


func _attach_sprite(tile_id: String, fade_in: bool) -> void:
	if _sprites.has(tile_id) or not _cached_tiles.has(tile_id):
		return
	var tile: Dictionary = _cached_tiles[tile_id]
	var detail_rect: Rect2 = tile.get("rect", Rect2())
	var texture: Texture2D = tile.get("texture", null)
	if texture == null:
		return
	var cache_sprite := Sprite2D.new()
	cache_sprite.name = "DetailCached_%s" % tile_id
	cache_sprite.position = detail_rect.get_center()
	cache_sprite.texture = texture
	cache_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	# 只显示 1536² 内容区；4 px 外挤仅供双线性采样，不能把相邻瓦片重复
	# 覆盖到世界里，否则半透明 landuse 会在接缝两侧叠暗 4 px。
	cache_sprite.region_enabled = true
	cache_sprite.region_rect = Rect2(Vector2(CACHE_PADDING_PX, CACHE_PADDING_PX),
		Vector2(CACHE_CONTENT_SIZE))
	cache_sprite.scale = detail_rect.size / Vector2(CACHE_CONTENT_SIZE)
	# 超采样 detail 的大量半透明 landuse/建筑边缘在最终主画布上系统性偏暗。
	# 统一静态乘色只校准缓存纹理，不改 alpha、几何、draw call 或战斗期工作。
	cache_sprite.modulate = Color(
		DETAIL_COLOR_LIFT.r, DETAIL_COLOR_LIFT.g, DETAIL_COLOR_LIFT.b,
		0.0 if fade_in else 1.0)
	add_child(cache_sprite)
	_sprites[tile_id] = cache_sprite
	if fade_in:
		create_tween().tween_property(cache_sprite, "modulate:a", 1.0, TILE_APPEAR_SECONDS)
	z_index = 2


static func _extrude_image_border(image: Image) -> void:
	var inner_min := CACHE_PADDING_PX
	var inner_max_x := CACHE_PADDING_PX + CACHE_CONTENT_SIZE.x - 1
	var inner_max_y := CACHE_PADDING_PX + CACHE_CONTENT_SIZE.y - 1
	for x in range(inner_min, inner_max_x + 1):
		var top_color := image.get_pixel(x, inner_min)
		var bottom_color := image.get_pixel(x, inner_max_y)
		for padding in range(CACHE_PADDING_PX):
			image.set_pixel(x, padding, top_color)
			image.set_pixel(x, CACHE_SIZE.y - 1 - padding, bottom_color)
	for y in range(CACHE_SIZE.y):
		var left_color := image.get_pixel(inner_min, clampi(y, inner_min, inner_max_y))
		var right_color := image.get_pixel(inner_max_x, clampi(y, inner_min, inner_max_y))
		for padding in range(CACHE_PADDING_PX):
			image.set_pixel(padding, y, left_color)
			image.set_pixel(CACHE_SIZE.x - 1 - padding, y, right_color)


static func _prepare_cached_image(image: Image) -> Image:
	if image.get_format() != Image.FORMAT_RGBA8:
		image.convert(Image.FORMAT_RGBA8)
	var padded_image := Image.create_empty(CACHE_SIZE.x, CACHE_SIZE.y, false, Image.FORMAT_RGBA8)
	padded_image.blit_rect(image, Rect2i(Vector2i.ZERO, CACHE_CONTENT_SIZE),
		Vector2i(CACHE_PADDING_PX, CACHE_PADDING_PX))
	_extrude_image_border(padded_image)
	return padded_image


func _evict_oldest(protected: Dictionary) -> bool:
	var candidate_id := ""
	var candidate_clock := 9223372036854775807
	for tile_id_any in _cached_tiles:
		var tile_id := String(tile_id_any)
		if protected.has(tile_id):
			continue
		var clock := int((_cached_tiles[tile_id] as Dictionary).get("last_used", 0))
		if clock < candidate_clock:
			candidate_clock = clock
			candidate_id = tile_id
	if candidate_id == "":
		return false
	if _sprites.has(candidate_id):
		var sprite: Node = _sprites[candidate_id]
		if is_instance_valid(sprite):
			sprite.queue_free()
		_sprites.erase(candidate_id)
	_cached_tiles.erase(candidate_id)
	_coverage_dirty = true
	return true


static func _touch(tile_id: String) -> void:
	if not _cached_tiles.has(tile_id):
		return
	_use_clock += 1
	(_cached_tiles[tile_id] as Dictionary)["last_used"] = _use_clock


static func _load_tile_specs() -> bool:
	if not _tile_specs.is_empty():
		return true
	var file := FileAccess.open(MANIFEST_PATH, FileAccess.READ)
	if file == null:
		_cache_error = "cannot open %s" % MANIFEST_PATH
		return false
	var parsed = JSON.parse_string(file.get_as_text())
	file.close()
	if parsed == null or typeof(parsed) != TYPE_DICTIONARY:
		_cache_error = "detail tile manifest parse failed"
		return false
	for row_any in (parsed as Dictionary).get("tiles", []):
		var row: Dictionary = row_any
		var count_sum := 0
		for value_any in (row.get("counts", {}) as Dictionary).values():
			count_sum += int(value_any)
		if row.has("counts") and count_sum <= 0:
			continue
		var values: Array = row.get("rect", [])
		if values.size() != 4:
			_cache_error = "detail tile rect must contain x,y,w,h"
			_tile_specs.clear()
			return false
		var data_path := String(row.get("data_path", ""))
		if data_path == "" or not FileAccess.file_exists(data_path):
			_cache_error = "detail tile data missing: %s" % data_path
			_tile_specs.clear()
			return false
		_tile_specs.append({
			"id": String(row.get("id", "detail")),
			"rect": Rect2(float(values[0]), float(values[1]), float(values[2]), float(values[3])),
			"data_path": data_path,
		})
	if _tile_specs.is_empty():
		_cache_error = "detail tile manifest is empty"
		return false
	return true


static func _specs_intersecting(region: Rect2) -> Array:
	var result: Array = []
	for spec_any in _tile_specs:
		var spec: Dictionary = spec_any
		var tile_rect: Rect2 = spec.get("rect", Rect2())
		if tile_rect.intersects(region, true):
			result.append(spec)
	return result


static func _specs_for_regions(regions: Array) -> Array:
	var result: Array = []
	var seen: Dictionary = {}
	for region_any in regions:
		var region: Rect2 = region_any
		for spec_any in _specs_intersecting(region):
			var spec: Dictionary = spec_any
			var tile_id := String(spec.get("id", ""))
			if seen.has(tile_id):
				continue
			seen[tile_id] = true
			result.append(spec)
	return result


static func _limit_specs_nearest(specs: Array, center: Vector2, priority_points: Array = []) -> void:
	if specs.size() <= MAX_CACHE_TILES:
		return
	specs.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var rect_a: Rect2 = a.get("rect", Rect2())
		var rect_b: Rect2 = b.get("rect", Rect2())
		var priority_a := false
		var priority_b := false
		for point_any in priority_points:
			var point: Vector2 = point_any
			priority_a = priority_a or rect_a.has_point(point)
			priority_b = priority_b or rect_b.has_point(point)
		if priority_a != priority_b:
			return priority_a
		return rect_a.get_center().distance_squared_to(center) \
			< rect_b.get_center().distance_squared_to(center))
	specs.resize(MAX_CACHE_TILES)


static func _rebuild_metrics() -> void:
	var bytes_per_tile := CACHE_SIZE.x * CACHE_SIZE.y * 4
	var triangles := 0
	var max_bake_ms := 0
	var max_readback_ms := 0
	var max_image_worker_ms := 0
	var max_upload_ms := 0
	for tile_any in _cached_tiles.values():
		var tile := tile_any as Dictionary
		triangles += int(tile.get("triangles", 0))
		max_bake_ms = maxi(max_bake_ms, int(tile.get("bake_ms", 0)))
		max_readback_ms = maxi(max_readback_ms, int(tile.get("readback_ms", 0)))
		max_image_worker_ms = maxi(max_image_worker_ms, int(tile.get("image_worker_ms", 0)))
		max_upload_ms = maxi(max_upload_ms, int(tile.get("upload_ms", 0)))
	_cache_metrics = {
		"ok": not _cached_tiles.is_empty(),
		"cache_hit": false,
		"manifest_tile_count": _tile_specs.size(),
		"cached_tile_count": _cached_tiles.size(),
		"cache_bytes_rgba8": _cached_tiles.size() * bytes_per_tile,
		"max_cache_bytes_rgba8": MAX_CACHE_TILES * bytes_per_tile,
		"peak_bytes_rgba8": MAX_CACHE_TILES * bytes_per_tile + SOURCE_SIZE.x * SOURCE_SIZE.y * 4,
		"main_canvas_draw_calls_max": MAX_CACHE_TILES,
		"source_triangles_cached": triangles,
		"max_tile_bake_ms": max_bake_ms,
		"max_tile_readback_ms": max_readback_ms,
		"max_tile_image_worker_ms": max_image_worker_ms,
		"max_tile_upload_ms": max_upload_ms,
	}
