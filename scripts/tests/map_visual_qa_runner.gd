extends Node2D

## Godot 4.7 GL Compatibility 固定机位视觉采集器。
## 只能由 bench/run.cmd map_visual_qa ... Shadow Visual 启动；输出留在 tmp/。

const MapRenderer = preload("res://scripts/survivor/map_feature_renderer.gd")
const VectorRenderer = preload("res://scripts/survivor/map_vector_preview_renderer.gd")
const GoldSliceRenderer = preload("res://scripts/survivor/map_detail_tile_cache.gd")
const LegacyBuildingRenderer = preload("res://scripts/survivor/building_renderer.gd")
const OUTPUT_DIR := "res://tmp/map_visual_qa/runtime"
const CAPTURE_SIZE := Vector2i(1600, 900)
const WORLD_RECT := Rect2(Vector2(-15000.0, -15000.0), Vector2(30000.0, 30000.0))

const VIEWS := [
	{"id": "full", "label": "FULL", "center": Vector2.ZERO, "zoom": 0.03},
	{"id": "bay_operational", "label": "BAY OPERATIONAL", "center": Vector2.ZERO, "zoom": 0.20},
	{"id": "tokyo_operational", "label": "TOKYO OPERATIONAL", "center": Vector2(-1200.0, -8200.0), "zoom": 0.28},
	{"id": "haneda_airport", "label": "HANEDA AIRPORT", "center": Vector2(1100.0, -5850.0), "zoom": 0.38},
	{"id": "west_operational", "label": "WEST SHORE OPERATIONAL", "center": Vector2(-5000.0, -1800.0), "zoom": 0.28},
	{"id": "chiba_operational", "label": "CHIBA OPERATIONAL", "center": Vector2(7800.0, 1800.0), "zoom": 0.28},
	{"id": "yokohama_gold", "label": "YOKOHAMA 4KM GOLD", "center": Vector2(-5300.0, -700.0), "zoom": 0.80},
	{"id": "yokohama_east", "label": "YOKOHAMA EAST DETAIL", "center": Vector2(-3300.0, -700.0), "zoom": 0.80},
	{"id": "kawasaki_west", "label": "KAWASAKI WEST DETAIL", "center": Vector2(-5300.0, -2700.0), "zoom": 0.80},
	{"id": "kawasaki_east", "label": "KAWASAKI EAST DETAIL", "center": Vector2(-3300.0, -2700.0), "zoom": 0.80},
	{"id": "detail_seam", "label": "DETAIL FOUR-TILE SEAM", "center": Vector2(-4300.0, -1700.0), "zoom": 1.10},
	{"id": "tokyo_north", "label": "TOKYO NORTH DETAIL", "center": Vector2(-300.0, -9100.0), "zoom": 0.80},
	{"id": "chiba_east", "label": "CHIBA EAST DETAIL", "center": Vector2(13200.0, -1800.0), "zoom": 0.80},
	{"id": "audit_empty_chiba_east", "label": "AUDIT EMPTY CHIBA EAST", "center": Vector2(12700.0, -6700.0), "zoom": 0.80},
	{"id": "audit_empty_bay_reclaimed", "label": "AUDIT EMPTY BAY RECLAIMED", "center": Vector2(4700.0, -2700.0), "zoom": 0.80},
	{"id": "yokosuka_south", "label": "YOKOSUKA SOUTH DETAIL", "center": Vector2(-5200.0, 8500.0), "zoom": 0.80},
	{"id": "chiba_south", "label": "CHIBA SOUTH DETAIL", "center": Vector2(6500.0, 7600.0), "zoom": 0.80},
	{"id": "stable_0224", "label": "STABILITY 0.224", "center": Vector2(-5300.0, -700.0), "zoom": 0.224},
	{"id": "stable_0226", "label": "STABILITY 0.226", "center": Vector2(-5300.0, -700.0), "zoom": 0.226},
	{"id": "progress_020", "label": "PROGRESS 0.20 MASS", "center": Vector2(-4300.0, -1700.0), "zoom": 0.20},
	{"id": "progress_035", "label": "PROGRESS 0.35 ROOF START", "center": Vector2(-4300.0, -1700.0), "zoom": 0.35},
	{"id": "progress_050", "label": "PROGRESS 0.50 ROOF", "center": Vector2(-4300.0, -1700.0), "zoom": 0.50},
	{"id": "progress_065", "label": "PROGRESS 0.65 DEPTH", "center": Vector2(-4300.0, -1700.0), "zoom": 0.65},
	{"id": "progress_080", "label": "PROGRESS 0.80 DETAIL MID", "center": Vector2(-4300.0, -1700.0), "zoom": 0.80},
	{"id": "progress_098", "label": "PROGRESS 0.98 DETAIL FULL", "center": Vector2(-4300.0, -1700.0), "zoom": 0.98},
	{"id": "wheel_050", "label": "WHEEL 0.500", "center": Vector2(-4300.0, -1700.0), "zoom": 0.500},
	{"id": "wheel_055", "label": "WHEEL 0.550", "center": Vector2(-4300.0, -1700.0), "zoom": 0.550},
	{"id": "wheel_061", "label": "WHEEL 0.605", "center": Vector2(-4300.0, -1700.0), "zoom": 0.605},
	{"id": "wheel_067", "label": "WHEEL 0.666", "center": Vector2(-4300.0, -1700.0), "zoom": 0.666},
	{"id": "wheel_073", "label": "WHEEL 0.732", "center": Vector2(-4300.0, -1700.0), "zoom": 0.732},
	{"id": "wheel_081", "label": "WHEEL 0.805", "center": Vector2(-4300.0, -1700.0), "zoom": 0.805},
	{"id": "wheel_089", "label": "WHEEL 0.886", "center": Vector2(-4300.0, -1700.0), "zoom": 0.886},
	{"id": "wheel_097", "label": "WHEEL 0.974", "center": Vector2(-4300.0, -1700.0), "zoom": 0.974},
	{"id": "detail_start_before", "label": "DETAIL FADE 0.499", "center": Vector2(-4300.0, -1700.0), "zoom": 0.499},
	{"id": "detail_start_after", "label": "DETAIL FADE 0.501", "center": Vector2(-4300.0, -1700.0), "zoom": 0.501},
	{"id": "detail_end_before", "label": "DETAIL FADE 0.979", "center": Vector2(-4300.0, -1700.0), "zoom": 0.979},
	{"id": "detail_end_after", "label": "DETAIL FADE 0.981", "center": Vector2(-4300.0, -1700.0), "zoom": 0.981},
]

var _camera: Camera2D
var _renderer: MapFeatureRenderer
var _fail_count := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("_run")


func _run() -> void:
	DisplayServer.window_set_size(CAPTURE_SIZE)
	RenderingServer.set_default_clear_color(Color(0.08, 0.10, 0.11, 1.0))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))

	# Visual run does not pass through building_preloader; warm the same production packet here.
	var prewarm: Dictionary = VectorRenderer.prewarm_lod(VectorRenderer.LOD_OPERATIONAL, WORLD_RECT)
	if not bool(prewarm.get("ok", false)):
		_record_failure("Operational prewarm failed: %s" % prewarm)
		_finish()
		return

	_camera = Camera2D.new()
	_camera.name = "QaCamera"
	_camera.position_smoothing_enabled = false
	_camera.enabled = true
	add_child(_camera)

	# PNG reference must match the real survivor stack. The legacy fake-3D city
	# renderer is a separate camera-relative layer above the PNG basemap.
	if not LegacyBuildingRenderer.cache_is_ready():
		LegacyBuildingRenderer.cache_reset()
		while not LegacyBuildingRenderer.cache_step(200):
			pass
	var legacy_buildings: Node2D = LegacyBuildingRenderer.new()
	legacy_buildings.name = "QaLegacyBuildings"
	add_child(legacy_buildings)
	legacy_buildings.setup(_camera)

	# 先走与 building_preloader 相同的缓存流程，再创建正式 MapFeatureRenderer；
	# 这样截图验证的是游戏内 Shift+F10 的真实消费路径，不是测试专用叠层。
	var gold_prewarm: Node2D = GoldSliceRenderer.new()
	gold_prewarm.name = "YokohamaGoldPrewarm"
	add_child(gold_prewarm)
	var gold_metrics: Dictionary = await gold_prewarm.bake_cache()
	if not bool(gold_metrics.get("ok", false)):
		_record_failure("gold slice setup failed: %s" % gold_metrics)
	else:
		# QA 一次预热横滨/川崎代表区，避免截图把异步流送时间误判为缺图。
		gold_metrics = await gold_prewarm.bake_region(
			Rect2(Vector2(-6600.0, -4100.0), Vector2(4800.0, 5000.0)))
		if not bool(gold_metrics.get("ok", false)):
			_record_failure("west-shore QA detail setup failed: %s" % gold_metrics)
	gold_prewarm.queue_free()

	_renderer = MapRenderer.new()
	_renderer.name = "QaMapRenderer"
	add_child(_renderer)
	_renderer.setup(_camera, WORLD_RECT)
	var qa_detail_cache := _renderer.get_node_or_null("VectorMapDetailTile")
	if qa_detail_cache == null:
		_record_failure("production MapFeatureRenderer did not bind the prewarmed detail tile")
	else:
		# 截图器显式等待每个代表区烘焙，不同时启动正式游戏的后台流送队列。
		qa_detail_cache.set_streaming_enabled(false)

	var manifest_views: Array = []
	for mode_any in ["reference", "candidate"]:
		var mode := String(mode_any)
		var enable_vector: bool = mode == "candidate"
		# 189 组横滨假 3D 大楼是共享游戏地标层；两种底图必须用同一负载对拍。
		legacy_buildings.visible = true
		legacy_buildings.process_mode = Node.PROCESS_MODE_INHERIT
		if not _renderer.set_vector_preview_enabled(enable_vector):
			_record_failure("failed to switch map renderer to %s" % mode)
			break
		for view_any in VIEWS:
			var view: Dictionary = view_any
			var view_id := String(view["id"])
			_camera.position = view["center"]
			var zoom_value := float(view["zoom"])
			_camera.zoom = Vector2(zoom_value, zoom_value)
			if enable_vector and zoom_value >= 0.58:
				var detail_cache := _renderer.get_node_or_null("VectorMapDetailTile")
				if detail_cache != null:
					var world_size := Vector2(CAPTURE_SIZE) / zoom_value
					var detail_result: Dictionary = await detail_cache.bake_region(
						Rect2(_camera.position - world_size * 0.5, world_size).grow(120.0))
					if bool(detail_result.get("ok", false)):
						detail_cache.attach_cached()
					else:
						_record_failure("detail QA prewarm failed for %s: %s" % [view_id, detail_result])
			await _settle_frame()
			var filename := "%s_%s.png" % [mode, view_id]
			var error := _capture_png("%s/%s" % [OUTPUT_DIR, filename])
			if error != OK:
				_record_failure("save failed for %s (err=%d)" % [filename, error])
			else:
				print("[MapVisualQa] captured %s" % filename)
			manifest_views.append({
				"mode": mode,
				"id": view_id,
				"label": view["label"],
				"center": [view["center"].x, view["center"].y],
				"zoom": zoom_value,
				"file": filename,
			})
		if enable_vector:
			# 正式滚轮目标之间由 CameraController 连续插值；0.02 zoom 扫频抓淡入曲线内部尖峰。
			for sweep_index in range(25):
				var sweep_zoom := 0.50 + float(sweep_index) * 0.02
				var sweep_id := "sweep_%03d" % int(round(sweep_zoom * 1000.0))
				_camera.position = Vector2(-4300.0, -1700.0)
				_camera.zoom = Vector2(sweep_zoom, sweep_zoom)
				await _settle_frame()
				var sweep_filename := "candidate_%s.png" % sweep_id
				var sweep_error := _capture_png("%s/%s" % [OUTPUT_DIR, sweep_filename])
				if sweep_error != OK:
					_record_failure("save failed for %s (err=%d)" % [sweep_filename, sweep_error])
				manifest_views.append({
					"mode": "candidate",
					"id": sweep_id,
					"label": "ZOOM SWEEP %.2f" % sweep_zoom,
					"center": [-4300.0, -1700.0],
					"zoom": sweep_zoom,
					"file": sweep_filename,
				})
			await _capture_operational_layer_diagnostics()

	# Tab 使用独立 LOD_TAB 静态快照；不能用缩小后的主地图 Operational 冒充。
	var tab_snapshot_metrics: Dictionary = await _capture_tab_vector_snapshot()

	# 跨区正式路径必须能在 Tab 真暂停中完成，且相机 streaming 继续关闭。
	var paused_nav_detail_metrics: Dictionary = {}
	if _renderer.vector_preview_enabled:
		var paused_cache := _renderer.get_node_or_null("VectorMapDetailTile")
		if paused_cache == null:
			_record_failure("paused detail QA cannot find production cache")
		else:
			paused_cache.set_streaming_enabled(false)
			get_tree().paused = true
			var nav_point := Vector2(12500.0, -2300.0)
			var nav_region := GoldSliceRenderer.viewport_region(nav_point, Vector2(CAPTURE_SIZE))
			paused_nav_detail_metrics = await _renderer.prewarm_detail_regions([nav_region])
			var remained_paused := get_tree().paused
			get_tree().paused = false
			if not bool(paused_nav_detail_metrics.get("ok", false)):
				_record_failure("paused arbitrary-nav detail prewarm failed: %s" % paused_nav_detail_metrics)
			elif int(paused_nav_detail_metrics.get("last_batch_baked", 0)) <= 0:
				_record_failure("paused arbitrary-nav detail prewarm did not bake a new tile: %s" % paused_nav_detail_metrics)
			if not remained_paused:
				_record_failure("paused remote detail prewarm released the battle pause")
			if bool(paused_cache.get("_streaming_enabled")):
				_record_failure("paused remote detail prewarm enabled combat streaming")

	var manifest := {
		"schema_version": 1,
		"engine": Engine.get_version_info().get("string", "unknown"),
		"display_server": DisplayServer.get_name(),
		"rendering_method": ProjectSettings.get_setting("rendering/renderer/rendering_method", "unknown"),
		"capture_size": [CAPTURE_SIZE.x, CAPTURE_SIZE.y],
		"world_rect": [WORLD_RECT.position.x, WORLD_RECT.position.y, WORLD_RECT.size.x, WORLD_RECT.size.y],
		"views": manifest_views,
		"gold_slice_metrics": gold_metrics,
		"paused_nav_detail_metrics": paused_nav_detail_metrics,
		"tab_snapshot_metrics": tab_snapshot_metrics,
		"shared_gameplay_building_metrics": {
			"district_count": legacy_buildings.get("_districts").size(),
			"camera_relative": true,
			"candidate_uses_legacy_layer": true,
		},
		"stability_pairs": [
			["stable_0224", "stable_0226"],
			["detail_start_before", "detail_start_after"],
			["detail_end_before", "detail_end_after"],
		],
	}
	var manifest_file := FileAccess.open("%s/manifest.json" % OUTPUT_DIR, FileAccess.WRITE)
	if manifest_file == null:
		_record_failure("cannot write manifest")
	else:
		manifest_file.store_string(JSON.stringify(manifest, "  "))
		manifest_file.close()
	_finish()


func _capture_tab_vector_snapshot() -> Dictionary:
	print("[MapVisualQa] tab snapshot: create viewport")
	var viewport := SubViewport.new()
	viewport.name = "QaTabVectorSnapshot"
	viewport.size = Vector2i(1024, 1024)
	viewport.disable_3d = true
	viewport.transparent_bg = false
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(viewport)

	var camera := Camera2D.new()
	camera.position = WORLD_RECT.get_center()
	var fit_zoom := minf(1024.0 / WORLD_RECT.size.x, 1024.0 / WORLD_RECT.size.y)
	camera.zoom = Vector2.ONE * fit_zoom
	camera.enabled = true
	viewport.add_child(camera)

	var renderer := VectorRenderer.new()
	viewport.add_child(renderer)
	print("[MapVisualQa] tab snapshot: setup LOD_TAB")
	if not renderer.setup(camera, WORLD_RECT, VectorRenderer.LOD_TAB):
		viewport.queue_free()
		_record_failure("production LOD_TAB snapshot setup failed")
		return {"ok": false}
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	print("[MapVisualQa] tab snapshot: wait UPDATE_ONCE")
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	print("[MapVisualQa] tab snapshot: readback")
	var image := viewport.get_texture().get_image()
	var output_path := "%s/candidate_tab_static.png" % OUTPUT_DIR
	var error := image.save_png(output_path) if image != null and not image.is_empty() else ERR_CANT_CREATE
	print("[MapVisualQa] tab snapshot: saved err=%d" % error)
	var metrics: Dictionary = VectorRenderer.inspect_lod(VectorRenderer.LOD_TAB, WORLD_RECT)
	metrics["ok"] = error == OK
	metrics["file"] = "candidate_tab_static.png"
	metrics["fit_zoom"] = fit_zoom
	if error != OK:
		_record_failure("production LOD_TAB snapshot save failed: %d" % error)
	viewport.queue_free()
	return metrics


func _capture_operational_layer_diagnostics() -> void:
	var root := _renderer.get_node_or_null("VectorMapPreview/VectorMapLOD1")
	if root == null:
		_record_failure("cannot find Operational packet root for layer diagnostics")
		return
	_camera.position = Vector2(-5000.0, -1800.0)
	_camera.zoom = Vector2(0.28, 0.28)
	var stages := [
		["topology", ["sea", "land", "water", "land_inlay"]],
		["mass", ["sea", "land", "water", "land_inlay", "urban", "industrial", "aprons", "airport"]],
		["coast", ["sea", "land", "water", "land_inlay", "urban", "industrial", "aprons", "airport", "coast_"]],
	]
	for stage_any in stages:
		var stage: Array = stage_any
		var prefixes: Array = stage[1]
		for child_any in root.get_children():
			var child := child_any as CanvasItem
			var packet_name := String(child.name).to_lower()
			child.visible = false
			for prefix_any in prefixes:
				if packet_name.contains(String(prefix_any)):
					child.visible = true
					break
		await _settle_frame()
		var filename := "diagnostic_operational_%s.png" % String(stage[0])
		var error := _capture_png("%s/%s" % [OUTPUT_DIR, filename])
		if error != OK:
			_record_failure("layer diagnostic save failed for %s" % filename)
	for child_any in root.get_children():
		(child_any as CanvasItem).visible = true


func _settle_frame() -> void:
	# V37 Detail 根按 0.18s 平滑显隐；等待完整过渡后再截图，避免把两帧中间态
	# 误当成最终视觉。静态地图本身仍不 redraw。
	for _frame in range(14):
		await get_tree().process_frame
		await RenderingServer.frame_post_draw


func _capture_png(path: String) -> Error:
	var image := get_viewport().get_texture().get_image()
	if image == null or image.is_empty():
		return ERR_CANT_CREATE
	return image.save_png(path)


func _record_failure(message: String) -> void:
	_fail_count += 1
	printerr("[MapVisualQa] FAIL: %s" % message)


func _finish() -> void:
	print("[MapVisualQa] %s output=%s" % [
		"PASS" if _fail_count == 0 else "FAIL x%d" % _fail_count,
		ProjectSettings.globalize_path(OUTPUT_DIR),
	])
	await get_tree().process_frame
	get_tree().quit(0 if _fail_count == 0 else 1)
