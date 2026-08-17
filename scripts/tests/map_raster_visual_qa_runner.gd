extends Node2D

## 三张正式 PNG / 无损瓦片候选的固定机位 A/B。输出只写 tmp/，不改生产状态。

const MapRenderer = preload("res://scripts/survivor/map_feature_renderer.gd")
const RasterRenderer = preload("res://scripts/survivor/raster_basemap_renderer.gd")
const TacticalRenderer = preload("res://scripts/survivor/tactical_map.gd")
const LegacyBuildingRenderer = preload("res://scripts/survivor/building_renderer.gd")
const OUTPUT_DIR := "res://tmp/map_visual_qa/raster"
const CAPTURE_SIZE := Vector2i(1600, 900)
const WORLD_RECT := Rect2(Vector2(-15000.0, -15000.0), Vector2(30000.0, 30000.0))
const OPERATIONAL_CAPTURE_ZOOM := 0.18
const BATTLE_CAPTURE_ZOOM := 0.26
const ZOOM_SWEEP_VALUES := [
	0.06, 0.079, 0.081, 0.099, 0.101, 0.104, 0.105, 0.106, 0.107, 0.108,
	0.11, 0.115, 0.12, 0.125, 0.18, 0.199, 0.201, 0.22, 0.239, 0.241,
	0.26, 0.32, 0.36, 0.40,
]
const OPERATIONAL_AUDIT_UVS := [
	Vector2(0.18, 0.18), Vector2(0.50, 0.18), Vector2(0.82, 0.18),
	Vector2(0.18, 0.50), Vector2(0.50, 0.50), Vector2(0.82, 0.50),
	Vector2(0.18, 0.82), Vector2(0.50, 0.82), Vector2(0.82, 0.82),
]

const MAPS := {
	"tokyo": {
		"png": "res://resources/maps/tokyo_bay_bg.png",
		"meta": "res://resources/maps/tokyo_bay_bg.json",
		"document": "",
		"detail_uv": Vector2(0.40, 0.38),
		"landmark_center": Vector2(-3400.0, -4050.0),
		"landmark_zoom": 0.82,
		"building_districts": 189,
	},
	"desert": {
		"png": "res://resources/maps/desert_railway_bg_v2.png",
		"meta": "res://resources/maps/desert_railway_bg_v2.json",
		"document": "res://resources/maps/desert_railway_preview.aglmap",
		"detail_uv": Vector2(0.72, 0.43),
		"landmark_center": Vector2(4800.0, 450.0),
		"landmark_zoom": 0.82,
		"building_districts": 15,
	},
	"ocean": {
		"png": "res://resources/maps/ocean_islands_bg_v2.png",
		"meta": "res://resources/maps/ocean_islands_bg_v2.json",
		"document": "res://resources/maps/ocean_islands_preview.aglmap",
		"detail_uv": Vector2(0.63, 0.20),
		"landmark_center": Vector2(-10700.0, -6500.0),
		"landmark_zoom": 0.72,
		"building_districts": 16,
	},
}

var _camera: Camera2D
var _renderer: MapFeatureRenderer
var _buildings: Node2D
var _map_document: MapDocument
var _fail_count := 0
var _views: Array[Dictionary] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("_run")


func _run() -> void:
	DisplayServer.window_set_size(CAPTURE_SIZE)
	RenderingServer.set_default_clear_color(Color(0.08, 0.10, 0.11, 1.0))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))
	_camera = Camera2D.new()
	_camera.name = "RasterQaCamera"
	_camera.position_smoothing_enabled = false
	_camera.enabled = true
	add_child(_camera)

	for map_key_any in MAPS:
		var map_key := String(map_key_any)
		var config: Dictionary = MAPS[map_key]
		await _run_map(map_key, config)
		await _capture_tab_snapshots(map_key, config)
		await _verify_tactical_toggle(map_key, config)

	var manifest := {
		"schema_version": 1,
		"engine": Engine.get_version_info().get("string", "unknown"),
		"rendering_method": ProjectSettings.get_setting("rendering/renderer/rendering_method", "unknown"),
		"capture_size": [CAPTURE_SIZE.x, CAPTURE_SIZE.y],
		"transition_duration_s": RasterRenderer.TRANSITION_S,
		"views": _views,
	}
	var file := FileAccess.open("%s/manifest.json" % OUTPUT_DIR, FileAccess.WRITE)
	if file == null:
		_record_failure("cannot write raster manifest")
	else:
		file.store_string(JSON.stringify(manifest, "  "))
		file.close()
	print("[MapRasterVisualQa] %s output=%s" % [
		"PASS" if _fail_count == 0 else "FAIL x%d" % _fail_count,
		ProjectSettings.globalize_path(OUTPUT_DIR),
	])
	await get_tree().process_frame
	get_tree().quit(0 if _fail_count == 0 else 1)


func _prepare_map_layers(map_key: String, config: Dictionary) -> void:
	if is_instance_valid(_buildings):
		_buildings.queue_free()
		_buildings = null
		await get_tree().process_frame
	# MapGeography / BuildingRenderer 都是进程级静态注入；每张图先恢复官方态，
	# 再按与 survivor_mode 完全相同的 MapDocument 路径注入，防止上一图污染下一图。
	UgcLoader.clear()
	_map_document = null
	var document_path := String(config.get("document", ""))
	if not document_path.is_empty():
		_map_document = UgcLoader.load_map(document_path)
		if _map_document == null or _map_document.rejected:
			_record_failure("%s MapDocument load failed: %s" % [map_key, document_path])
			_map_document = null
		else:
			UgcLoader.apply_geography(_map_document)
			UgcLoader.apply_buildings(_map_document)
	if not LegacyBuildingRenderer.cache_is_ready():
		while not LegacyBuildingRenderer.cache_step(200):
			pass
	_buildings = LegacyBuildingRenderer.new()
	_buildings.name = "RasterQaBuildings_%s" % map_key
	if _map_document != null:
		_buildings.perspective_k = 0.015
	add_child(_buildings)
	_buildings.setup(_camera)
	var district_count := (_buildings.get("_districts") as Array).size()
	var expected_count := int(config.get("building_districts", -1))
	if district_count != expected_count:
		_record_failure("%s building districts %d != expected %d" % [
			map_key, district_count, expected_count])


func _run_map(map_key: String, config: Dictionary) -> void:
	await _prepare_map_layers(map_key, config)
	if _renderer != null:
		_renderer.queue_free()
		await get_tree().process_frame
	_renderer = MapRenderer.new()
	_renderer.name = "RasterQa_%s" % map_key
	_renderer.basemap_png_path = String(config.png)
	_renderer.basemap_meta_path = String(config.meta)
	_renderer.ugc_vector_only = _map_document != null
	if _map_document != null:
		_renderer.ugc_overlay_layers = UgcLoader.overlay_layers_from(_map_document)
		_renderer.ugc_palette = _map_document.style.get("palette", {}).duplicate(true)
	add_child(_renderer)
	_renderer.setup(_camera, WORLD_RECT)
	_buildings.visible = true
	for _frame in range(4):
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
	var basemap_rect: Rect2 = _renderer.get("_basemap_world_rect")
	if basemap_rect.size.x <= 0.0:
		_record_failure("%s did not resolve basemap world rect" % map_key)
		return
	var fit_zoom := minf(
		float(CAPTURE_SIZE.x) / basemap_rect.size.x,
		float(CAPTURE_SIZE.y) / basemap_rect.size.y) * 0.96
	var detail_uv: Vector2 = config.detail_uv
	var detail_center := basemap_rect.position + detail_uv * basemap_rect.size
	var positions := [
		{"id": "full", "center": basemap_rect.get_center(), "zoom": fit_zoom},
		{"id": "operational", "center": detail_center, "zoom": OPERATIONAL_CAPTURE_ZOOM},
		{"id": "battle", "center": detail_center, "zoom": BATTLE_CAPTURE_ZOOM},
		{"id": "detail", "center": detail_center, "zoom": 0.82},
		{"id": "landmark", "center": config.landmark_center,
			"zoom": float(config.landmark_zoom)},
	]
	for index in range(OPERATIONAL_AUDIT_UVS.size()):
		var uv: Vector2 = OPERATIONAL_AUDIT_UVS[index]
		positions.append({
			"id": "operational_grid_%02d" % index,
			"center": basemap_rect.position + uv * basemap_rect.size,
			"zoom": OPERATIONAL_CAPTURE_ZOOM,
		})
	for mode_any in ["reference", "candidate"]:
		var mode := String(mode_any)
		var candidate: bool = mode == "candidate"
		if candidate:
			# 新建 renderer，并在首帧 _draw 前打开候选：验证不会先解码 8704² 旧 PNG。
			_renderer.queue_free()
			await get_tree().process_frame
			_renderer = MapRenderer.new()
			_renderer.name = "RasterQa_%s_candidate_startup" % map_key
			_renderer.basemap_png_path = String(config.png)
			_renderer.basemap_meta_path = String(config.meta)
			_renderer.ugc_vector_only = _map_document != null
			if _map_document != null:
				_renderer.ugc_overlay_layers = UgcLoader.overlay_layers_from(_map_document)
				_renderer.ugc_palette = _map_document.style.get("palette", {}).duplicate(true)
			add_child(_renderer)
			_renderer.setup(_camera, WORLD_RECT)
			_renderer.raster_preview_enabled = true
			await _settle(4)
			if _renderer.get("_basemap_sprite") != null:
				_record_failure("%s candidate startup decoded legacy PNG" % map_key)
		for view_any in positions:
			var view: Dictionary = view_any
			_camera.position = view.center
			var zoom_value := float(view.zoom)
			_camera.zoom = Vector2.ONE * zoom_value
			var expected_lod := _expected_lod_for_view(String(view.id))
			if candidate:
				if not await _wait_raster_stable(expected_lod, 300):
					_record_failure("%s candidate %s did not settle at %s" % [
						map_key, String(view.id), expected_lod])
			else:
				await _settle(5)
			var filename := "%s_%s_%s.png" % [map_key, mode, String(view.id)]
			var error := _capture_png("%s/%s" % [OUTPUT_DIR, filename])
			if error != OK:
				_record_failure("save failed: %s err=%d" % [filename, error])
			var resident := 0
			var raster_state: Dictionary = {}
			var raster_node: Node = _renderer.get_node_or_null("RasterBasemapPreview")
			if raster_node != null:
				resident = raster_node.resident_tile_count()
				raster_state = raster_node.debug_state()
			if resident > RasterRenderer.HARD_RESIDENT_TILES:
				_record_failure("%s %s %s exceeded hard tile cap: %d" % [map_key, mode, String(view.id), resident])
			_assert_raster_state("%s %s %s" % [map_key, mode, String(view.id)], raster_state)
			_views.append({
				"map": map_key,
				"mode": mode,
				"id": String(view.id),
				"zoom": zoom_value,
				"center": [view.center.x, view.center.y],
				"resident_tiles": resident,
				"raster_state": raster_state,
				"file": filename,
			})
		await _capture_temporal_stability(map_key, detail_center, mode, candidate)
		if map_key == "tokyo" and not candidate:
			await _capture_reference_zoom_sweep(detail_center)

	if map_key == "tokyo":
		# 连续跨越两个 LOD 重叠带，抓取缩放亮度稳定性。
		_renderer.set_raster_preview_enabled(true)
		_camera.position = detail_center
		for zoom_value in ZOOM_SWEEP_VALUES:
			_camera.zoom = Vector2.ONE * float(zoom_value)
			var expected_lod := _expected_lod_for_ascending_sweep(float(zoom_value))
			if not await _wait_raster_stable(expected_lod, 300):
				_record_failure("tokyo zoom %.3f did not settle at %s" % [
					float(zoom_value), expected_lod])
			var raster_node: Node = _renderer.get_node_or_null("RasterBasemapPreview")
			if raster_node != null and raster_node.resident_tile_count() > RasterRenderer.HARD_RESIDENT_TILES:
				_record_failure("tokyo zoom %.3f exceeded hard tile cap: %d" % [
					float(zoom_value), raster_node.resident_tile_count()])
			var filename := "tokyo_candidate_zoom_%03d.png" % int(round(float(zoom_value) * 1000.0))
			var error := _capture_png("%s/%s" % [OUTPUT_DIR, filename])
			if error != OK:
				_record_failure("zoom sweep save failed: %s" % filename)
			var raster_state: Dictionary = raster_node.debug_state() if raster_node != null else {}
			_assert_raster_state("tokyo zoom %.3f" % float(zoom_value), raster_state)
			_views.append({
				"map": map_key,
				"mode": "candidate_zoom",
				"id": "zoom_%03d" % int(round(float(zoom_value) * 1000.0)),
				"zoom": float(zoom_value),
				"center": [detail_center.x, detail_center.y],
				"raster_state": raster_state,
				"file": filename,
			})
		await _capture_transition_samples(0.06, 0.108, "strategic", "operational", "strategic_operational")
		await _capture_transition_samples(0.22, 0.241, "operational", "detail", "operational_detail")
		await _capture_transition_samples(0.30, 0.199, "detail", "operational", "detail_operational")
		await _capture_transition_samples(0.12, 0.079, "operational", "strategic", "operational_strategic")

	# 用户实际使用的是运行中 Shift+F8 往返；候选直启通过还不足以证明回滚。
	_camera.position = detail_center
	_camera.zoom = Vector2.ONE * BATTLE_CAPTURE_ZOOM
	if not _renderer.set_raster_preview_enabled(false):
		_record_failure("%s main rollback toggle returned false" % map_key)
	await _settle(6)
	var legacy_sprite = _renderer.get("_basemap_sprite")
	if legacy_sprite == null or not bool(legacy_sprite.visible):
		_record_failure("%s main rollback did not restore visible PNG" % map_key)
	var raster_node := _renderer.get_node_or_null("RasterBasemapPreview")
	if raster_node != null and bool(raster_node.get("_active")):
		_record_failure("%s main rollback left streamed renderer active" % map_key)
	var rollback_filename := "%s_rollback_battle.png" % map_key
	var rollback_error := _capture_png("%s/%s" % [OUTPUT_DIR, rollback_filename])
	if rollback_error != OK:
		_record_failure("%s main rollback save failed: %d" % [map_key, rollback_error])
	_views.append({
		"map": map_key,
		"mode": "rollback",
		"id": "battle",
		"zoom": BATTLE_CAPTURE_ZOOM,
		"center": [detail_center.x, detail_center.y],
		"file": rollback_filename,
	})
	if not _renderer.set_raster_preview_enabled(true):
		_record_failure("%s main re-enable after rollback returned false" % map_key)
	elif not await _wait_raster_stable("detail", 300):
		_record_failure("%s main re-enable after rollback did not settle" % map_key)


func _capture_temporal_stability(
		map_key: String, center: Vector2, mode: String, candidate: bool) -> void:
	# 正式 PNG 与候选颗粒都必须锁在世界空间。间隔半秒抓同一固定机位，
	# 任何一条路径重新引入 TIME、闪烁或滚轮亮度呼吸都要失败。
	_camera.position = center
	_camera.zoom = Vector2.ONE * BATTLE_CAPTURE_ZOOM
	if candidate and not await _wait_raster_stable("detail", 300):
		_record_failure("%s %s temporal probe did not settle" % [map_key, mode])
		return
	elif not candidate:
		await _settle(5)
	for phase in ["a", "b"]:
		if phase == "b":
			await get_tree().create_timer(0.5, true, false, true).timeout
			await _settle(2)
		var filename := "%s_%s_temporal_battle_%s.png" % [map_key, mode, phase]
		var error := _capture_png("%s/%s" % [OUTPUT_DIR, filename])
		if error != OK:
			_record_failure("%s %s temporal %s save failed: %d" % [
				map_key, mode, phase, error])
		_views.append({
			"map": map_key,
			"mode": "%s_temporal" % mode,
			"id": "battle_%s" % phase,
			"zoom": BATTLE_CAPTURE_ZOOM,
			"center": [center.x, center.y],
			"file": filename,
		})


func _capture_reference_zoom_sweep(detail_center: Vector2) -> void:
	# 正式 PNG 也走完全相同的滚轮采样点。后处理用它扣除相机缩放自身的采样变化，
	# 防止把整图路径本来也存在的亮度变化误判成候选 LOD 跳变。
	_camera.position = detail_center
	for zoom_value in ZOOM_SWEEP_VALUES:
		_camera.zoom = Vector2.ONE * float(zoom_value)
		await _settle(5)
		var filename := "tokyo_reference_zoom_%03d.png" % int(round(float(zoom_value) * 1000.0))
		var error := _capture_png("%s/%s" % [OUTPUT_DIR, filename])
		if error != OK:
			_record_failure("reference zoom sweep save failed: %s" % filename)
		_views.append({
			"map": "tokyo",
			"mode": "reference_zoom",
			"id": "zoom_%03d" % int(round(float(zoom_value) * 1000.0)),
			"zoom": float(zoom_value),
			"center": [detail_center.x, detail_center.y],
			"file": filename,
		})


func _capture_tab_snapshots(map_key: String, config: Dictionary) -> void:
	var manifest := RasterRenderer.load_manifest(map_key)
	if manifest.is_empty():
		_record_failure("%s tab manifest missing" % map_key)
		return
	var levels: Dictionary = manifest.get("levels", {}) as Dictionary
	var strategic: Dictionary = levels.get("strategic", {}) as Dictionary
	var tiles: Array = strategic.get("tiles", []) as Array
	if tiles.is_empty():
		_record_failure("%s strategic tile missing" % map_key)
		return
	var record := tiles[0] as Dictionary
	var path := "%s/%s/%s" % [RasterRenderer.ROOT_PATH, map_key, String(record.path)]
	var candidate_texture := RasterRenderer.load_texture(path)
	var reference_texture := RasterRenderer.load_texture(String(config.png))
	if candidate_texture == null:
		_record_failure("%s strategic texture load failed" % map_key)
		return
	if reference_texture == null:
		_record_failure("%s reference tab texture load failed" % map_key)
		return
	for mode in ["reference", "candidate"]:
		var texture := reference_texture if mode == "reference" else candidate_texture
		var viewport := SubViewport.new()
		# TacticalMap 正式面板固定 680×680；按实际终端分辨率比较，避免用非生产 1024 视口夸大差异。
		viewport.size = Vector2i(680, 680)
		viewport.disable_3d = true
		viewport.transparent_bg = false
		viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		add_child(viewport)
		var texture_rect := TextureRect.new()
		texture_rect.size = Vector2(680.0, 680.0)
		texture_rect.texture = texture
		texture_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		texture_rect.stretch_mode = TextureRect.STRETCH_SCALE
		texture_rect.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		texture_rect.self_modulate = Color(0.72, 0.76, 0.75, 1.0)
		viewport.add_child(texture_rect)
		viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
		await _settle(4)
		var image := viewport.get_texture().get_image()
		var filename := "%s_%s_tab.png" % [map_key, mode]
		var error := image.save_png("%s/%s" % [OUTPUT_DIR, filename]) \
			if image != null and not image.is_empty() else ERR_CANT_CREATE
		if error != OK:
			_record_failure("%s %s tab save failed: %d" % [map_key, mode, error])
		_views.append({"map": map_key, "mode": mode, "id": "tab", "file": filename})
		viewport.queue_free()
		await get_tree().process_frame


func _verify_tactical_toggle(map_key: String, config: Dictionary) -> void:
	var tactical := TacticalRenderer.new()
	tactical.name = "RasterQaTactical_%s" % map_key
	tactical.basemap_png_path = String(config.png)
	tactical.basemap_meta_path = String(config.meta)
	add_child(tactical)
	await get_tree().process_frame
	tactical.setup(WORLD_RECT, null, null, null)
	if not tactical.set_raster_preview_enabled(true):
		_record_failure("%s TacticalMap enable returned false" % map_key)
	elif tactical.get("_mm_raster_tex") == null:
		_record_failure("%s TacticalMap did not bind Strategic texture" % map_key)
	if not tactical.set_raster_preview_enabled(false):
		_record_failure("%s TacticalMap disable returned false" % map_key)
	elif tactical.get("_mm_raster_tex") != null:
		_record_failure("%s TacticalMap did not release Strategic binding" % map_key)
	if not tactical.set_raster_preview_enabled(true):
		_record_failure("%s TacticalMap re-enable returned false" % map_key)
	tactical.queue_free()
	await get_tree().process_frame


func _capture_transition_samples(
		from_zoom: float,
		to_zoom: float,
		from_lod: String,
		to_lod: String,
		label: String) -> void:
	_camera.zoom = Vector2.ONE * from_zoom
	if not await _wait_raster_stable(from_lod, 300):
		_record_failure("tokyo transition %s did not settle at %s" % [label, from_lod])
		return
	_camera.zoom = Vector2.ONE * to_zoom
	if not await _wait_raster_transition(to_lod, 300):
		_record_failure("tokyo transition %s did not start toward %s" % [label, to_lod])
		return
	var alpha_ranges := {
		25: Vector2(0.10, 0.40),
		50: Vector2(0.35, 0.65),
		75: Vector2(0.60, 0.90),
	}
	for sample_percent in [25, 50, 75]:
		# 不能按墙钟固定睡 0.25 段：Visual 窗口帧调度会让 75% 样本漂到
		# 0.95 以上。逐帧读取生产 renderer 的真实 alpha，首次进入目标窗即截图。
		var state: Dictionary = {}
		var next_alpha := -1.0
		var allowed := alpha_ranges[sample_percent] as Vector2
		var deadline_ms := Time.get_ticks_msec() + int(ceil(
				(RasterRenderer.TRANSITION_S + 0.20) * 1000.0))
		var frame_count := 0
		while frame_count < 600 and Time.get_ticks_msec() < deadline_ms:
			await get_tree().process_frame
			await RenderingServer.frame_post_draw
			frame_count += 1
			var raster_node: Node = _renderer.get_node_or_null("RasterBasemapPreview")
			state = raster_node.debug_state() if raster_node != null else {}
			var sampled_layers: Dictionary = state.get("layers", {}) as Dictionary
			if to_lod == "strategic":
				var sampled_old: Dictionary = sampled_layers.get(from_lod, {}) as Dictionary
				next_alpha = 1.0 - float(sampled_old.get("alpha", 2.0))
			else:
				var sampled_next: Dictionary = sampled_layers.get(to_lod, {}) as Dictionary
				next_alpha = float(sampled_next.get("alpha", -1.0))
			if next_alpha >= allowed.x:
				break
		_assert_raster_state("tokyo transition %s@%d" % [label, sample_percent], state)
		var layers: Dictionary = state.get("layers", {}) as Dictionary
		var next_state: Dictionary = layers.get(to_lod, {}) as Dictionary
		var old_state: Dictionary = layers.get(from_lod, {}) as Dictionary
		var old_alpha := float(old_state.get("alpha", -1.0))
		next_alpha = 1.0 - old_alpha if to_lod == "strategic" \
				else float(next_state.get("alpha", -1.0))
		if next_alpha < allowed.x or next_alpha > allowed.y:
			_record_failure("tokyo transition %s@%d alpha %.3f outside %.2f..%.2f" % [
				label, sample_percent, next_alpha, allowed.x, allowed.y])
		if from_lod != "strategic":
			if to_lod == "strategic" and absf(old_alpha + next_alpha - 1.0) > 0.05:
				_record_failure("tokyo transition %s@%d reveal old/progress %.3f/%.3f" % [
					label, sample_percent, old_alpha, next_alpha])
			elif to_lod != "strategic" and absf(old_alpha - 1.0) > 0.05:
				_record_failure("tokyo transition %s@%d cover old alpha %.3f != 1" % [
					label, sample_percent, old_alpha])
			var old_z := int(old_state.get("z_index", 0))
			var next_z := int(next_state.get("z_index", 0))
			if to_lod != "strategic" and next_z <= old_z:
				_record_failure("tokyo transition %s@%d target z %d <= old z %d" % [
					label, sample_percent, next_z, old_z])
		var filename := "tokyo_transition_%s_%02d.png" % [label, sample_percent]
		var error := _capture_png("%s/%s" % [OUTPUT_DIR, filename])
		if error != OK:
			_record_failure("tokyo transition sample save failed: %s" % filename)
		_views.append({
			"map": "tokyo",
			"mode": "candidate_transition",
			"id": "%s_%02d" % [label, sample_percent],
			"transition": label,
			"sample_fraction": float(sample_percent) / 100.0,
			"zoom": to_zoom,
			"raster_state": state,
			"file": filename,
		})
	if not await _wait_raster_stable(to_lod, 300):
		_record_failure("tokyo transition %s did not finish at %s" % [label, to_lod])


func _assert_raster_state(context: String, state: Dictionary) -> void:
	if state.is_empty():
		_record_failure("%s missing raster debug state" % context)
		return
	var peak := int(state.get("peak_resident_tiles", 0))
	if peak > RasterRenderer.HARD_RESIDENT_TILES:
		_record_failure("%s peak resident %d exceeded hard cap %d" % [
			context, peak, RasterRenderer.HARD_RESIDENT_TILES])
	if bool(state.get("transitioning", false)):
		var required_count := (state.get("required_keys", []) as Array).size()
		var visible_count := int(state.get("visible_tile_count", 0))
		if required_count != visible_count:
			_record_failure("%s transition coverage truncated visible=%d required=%d" % [
				context, visible_count, required_count])


func _expected_lod_for_ascending_sweep(zoom: float) -> String:
	# 1920x1080 逻辑视口中，7680 Operational 在 0.106 仍超过 12 格；
	# 0.107 起降至 12 格以内。验收必须服从可见覆盖与硬内存门。
	if zoom < 0.107:
		return "strategic"
	if zoom < RasterRenderer.DETAIL_ENTER_ZOOM:
		return "operational"
	return "detail"


func _expected_lod_for_view(view_id: String) -> String:
	if view_id == "full":
		return "strategic"
	if view_id in ["battle", "detail", "landmark"]:
		return "detail"
	return "operational"


func _settle(frames: int) -> void:
	for _frame in range(frames):
		await get_tree().process_frame
		await RenderingServer.frame_post_draw


func _wait_raster_stable(expected_lod: String, max_frames: int) -> bool:
	# Shadow/Visual 在高端 GPU 上可远超 60 FPS；只按帧数等待会在生产淡变
	# 淡入结束前误报超时。保留帧上限语义，同时至少覆盖等价 60 FPS 墙钟时间。
	var deadline_ms := Time.get_ticks_msec() + int(ceil(float(max_frames) / 60.0 * 1000.0))
	var frame_count := 0
	while frame_count < max_frames or Time.get_ticks_msec() < deadline_ms:
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		frame_count += 1
		var raster_node: Node = _renderer.get_node_or_null("RasterBasemapPreview")
		if raster_node == null:
			continue
		var state: Dictionary = raster_node.debug_state()
		if String(state.get("current_lod", "")) == expected_lod \
				and String(state.get("target_lod", "")) == expected_lod \
				and not bool(state.get("transitioning", true)) \
				and int(state.get("pending_count", 1)) == 0 \
				and (state.get("missing_keys", []) as Array).is_empty():
			# LOD 层完成切换后，新进入视口的单块瓦片仍会继续淡入。等待完整淡入周期，
			# 避免把半透明瓦片误当成稳定画面并参与 PNG 对比。
			await get_tree().create_timer(RasterRenderer.TRANSITION_S + 0.02).timeout
			await RenderingServer.frame_post_draw
			var settled_state: Dictionary = raster_node.debug_state()
			if String(settled_state.get("current_lod", "")) == expected_lod \
					and String(settled_state.get("target_lod", "")) == expected_lod \
					and not bool(settled_state.get("transitioning", true)) \
					and int(settled_state.get("pending_count", 1)) == 0 \
					and (settled_state.get("missing_keys", []) as Array).is_empty():
				return true
	var raster_node: Node = _renderer.get_node_or_null("RasterBasemapPreview")
	var timeout_state: Dictionary = raster_node.debug_state() if raster_node != null else {}
	printerr("[MapRasterVisualQa] settle timeout expected=%s state=%s" % [
		expected_lod, JSON.stringify(timeout_state)])
	return false


func _wait_raster_transition(expected_target_lod: String, max_frames: int) -> bool:
	var deadline_ms := Time.get_ticks_msec() + int(ceil(float(max_frames) / 60.0 * 1000.0))
	var frame_count := 0
	while frame_count < max_frames or Time.get_ticks_msec() < deadline_ms:
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		frame_count += 1
		var raster_node: Node = _renderer.get_node_or_null("RasterBasemapPreview")
		if raster_node == null:
			continue
		var state: Dictionary = raster_node.debug_state()
		if String(state.get("target_lod", "")) == expected_target_lod \
				and bool(state.get("transitioning", false)):
			return true
	var raster_node: Node = _renderer.get_node_or_null("RasterBasemapPreview")
	var timeout_state: Dictionary = raster_node.debug_state() if raster_node != null else {}
	printerr("[MapRasterVisualQa] transition timeout expected=%s state=%s" % [
		expected_target_lod, JSON.stringify(timeout_state)])
	return false


func _capture_png(path: String) -> Error:
	var image := get_viewport().get_texture().get_image()
	if image == null or image.is_empty():
		return ERR_CANT_CREATE
	return image.save_png(path)


func _record_failure(message: String) -> void:
	_fail_count += 1
	printerr("[MapRasterVisualQa] FAIL: %s" % message)
