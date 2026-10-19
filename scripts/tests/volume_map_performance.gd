extends Node
## 真正的纯2D/3D沙漠对照；不借用旧的“2D飞机+3D地图”场景作基线。
const Probe := preload("res://scripts/experiments/volume_world_probe.gd")
var _mode_ref: WeakRef
var _probe_ref: WeakRef
var _is_3d := false
var _setup_ms := 0.0
var _wall_clock := preload("res://scripts/tests/map_frame_clock.gd").new()


var _timing_viewport: RID
var _timing_last_frame := 0
var _timing_skipped_frames := 0
var _timing_count := 0
var _timing_gpu_nonzero := 0
var _timing_invalid := 0
var _timing_totals: Array[float] = [0.0, 0.0, 0.0]
var _timing_peaks: Array[float] = [0.0, 0.0, 0.0]
var _coverage_count := 0
var _coverage_invalid := 0
var _coverage_visible_frames := 0
var _coverage_shadow_frames := 0
var _coverage_shadow_draw_frames := 0
# 固定四槽：可见primitives/draws、阴影primitives/draws，不保存逐帧历史。
var _coverage_totals: Array[int] = [0, 0, 0, 0]
var _coverage_minima: Array[int] = [0, 0, 0, 0]
var _coverage_maxima: Array[int] = [0, 0, 0, 0]
var bodies_enabled: bool:
	get: return _is_3d
var max_projection_error_px: float:
	get:
		var probe := _live_probe()
		return probe.max_projection_error_px if probe != null else 0.0
var max_body_count: int:
	get:
		var probe := _live_probe()
		return probe.max_body_count if probe != null else 0


func setup(mode: Node, scenario: String) -> void:
	process_priority = -100
	var started := Time.get_ticks_usec()
	_mode_ref = weakref(mode)
	_is_3d = scenario.begins_with("volume_map_3d_")
	var doc: MapDocument = mode._ugc_doc
	if OS.get_environment("AGL_WEATHER_STORM_TEST") == "1":
		mode._weather.set_debug_midgame(300.0,600.0)
	assert(doc != null, "paired map must enter through real UGC geography")
	assert(mode._map_features == null and mode._building_renderer == null, "fixture must not duplicate map owners")
	var features := MapFeatureRenderer.new()
	features.show_behind_parent = true
	features.ugc_vector_only = true
	features.use_basemap = true
	features.basemap_map_key = String(doc.basemap.tile_map_key)
	features.basemap_meta_path = String(doc.basemap.meta_path)
	features.ugc_overlay_layers = UgcLoader.overlay_layers_from(doc)
	features.ugc_palette = doc.style.get("palette", {}).duplicate(true)
	mode.add_child(features)
	mode.move_child(features, 0)
	mode._map_features = features
	features.setup(mode.camera, mode._map_boundary.get_world_rect())
	var buildings := BuildingRenderer.new()
	buildings.show_behind_parent = true
	buildings.perspective_k = 0.015
	mode.add_child(buildings)
	mode._building_renderer = buildings
	buildings.setup(mode.camera)
	if _is_3d:
		var probe := Probe.new()
		add_child(probe)
		probe.setup(mode, "volume_3d_c2" if scenario.ends_with("c2") else "volume_3d_c1")
		_probe_ref = weakref(probe)
	else:
		assert(get_viewport().get_camera_3d() == null, "pure 2D baseline must not create a Camera3D")
	_setup_ms = (Time.get_ticks_usec() - started) / 1000.0
	print("[Map pair] pure_2d=", not _is_3d, " setup_ms=", _setup_ms)
	if OS.get_environment("AGL_VOLUME_RENDER_TIMING") == "1":
		assert(DisplayServer.get_name() != "headless", "render timing requires actual Visual rendering")
		_timing_viewport = get_viewport().get_viewport_rid()
		RenderingServer.viewport_set_measure_render_time(_timing_viewport, true)
		RenderingServer.frame_post_draw.connect(_sample_render_times)


func _process(_delta: float) -> void:
	var mode: Variant = _mode_ref.get_ref() if _mode_ref != null else null
	if typeof(mode) == TYPE_OBJECT and is_instance_valid(mode):
		_wall_clock.observe(mode._bench_elapsed >= 3.0)


func _live_probe() -> Node:
	var value: Variant = _probe_ref.get_ref() if _probe_ref != null else null
	return value if typeof(value) == TYPE_OBJECT and is_instance_valid(value) else null


func summary() -> String:
	var mode: Variant = _mode_ref.get_ref() if _mode_ref != null else null
	if typeof(mode) != TYPE_OBJECT or not is_instance_valid(mode):
		return "map_pair owner_released=true"
	var result := "map_pair pure_2d=%s camera3d=%s source=desert_railway_preview setup_ms=%.3f\n%s" % [
		not _is_3d, get_viewport().get_camera_3d() != null, _setup_ms,
		str(mode._map_features._raster_basemap.debug_state())]
	var probe := _live_probe()
	if probe != null:
		var state: Dictionary = probe._satellite_ground.debug_state()
		assert(state.prebuilt_terrain and state.archive_misses == 0,
			"3D performance sample must exercise current prebuilt terrain, not silent fallback")
	return result + ("\n" + probe.summary() if probe != null else "") + "\n" + _timing_report() \
		+ "\nmap_wall_clock=" + JSON.stringify(_wall_clock.report())


func _sample_render_times() -> void:
	if not _timing_viewport.is_valid():
		return
	var mode: Variant = _mode_ref.get_ref() if _mode_ref != null else null
	if typeof(mode) != TYPE_OBJECT or not is_instance_valid(mode):
		return
	if not _accept_render_frame(int(mode._bench_render_frames)):
		return
	_record_render_sample(RenderingServer.viewport_get_measured_render_time_cpu(_timing_viewport),
		RenderingServer.viewport_get_measured_render_time_gpu(_timing_viewport),
		RenderingServer.get_frame_setup_time_cpu())
	var viewport := get_viewport()
	_record_render_coverage(
		viewport.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE, Viewport.RENDER_INFO_PRIMITIVES_IN_FRAME),
		viewport.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE, Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME),
		viewport.get_render_info(Viewport.RENDER_INFO_TYPE_SHADOW, Viewport.RENDER_INFO_PRIMITIVES_IN_FRAME),
		viewport.get_render_info(Viewport.RENDER_INFO_TYPE_SHADOW, Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME),
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME))


func _accept_render_frame(frame: int) -> bool:
	# 与正式 FPS 窗口共用帧号：启动卡顿时墙钟和物理预热时间并不相等。
	if frame <= _timing_last_frame:
		return false
	_timing_skipped_frames += frame - _timing_last_frame - 1
	_timing_last_frame = frame
	return true


func _record_render_sample(cpu_ms: float, gpu_ms: float, setup_ms: float) -> void:
	if not is_finite(cpu_ms) or not is_finite(gpu_ms) or not is_finite(setup_ms) \
		or minf(cpu_ms, minf(gpu_ms, setup_ms)) < 0.0:
		_timing_invalid += 1
		return
	_timing_count += 1
	_timing_gpu_nonzero += int(gpu_ms > 0.0)
	# 三个固定槽位原地累计，诊断本身不逐帧分配临时数组。
	_timing_totals[0] += cpu_ms
	_timing_totals[1] += gpu_ms
	_timing_totals[2] += setup_ms
	_timing_peaks[0] = maxf(_timing_peaks[0], cpu_ms)
	_timing_peaks[1] = maxf(_timing_peaks[1], gpu_ms)
	_timing_peaks[2] = maxf(_timing_peaks[2], setup_ms)


func _record_render_coverage(visible_primitives: int, visible_draws: int,
		shadow_primitives: int, shadow_draws: int, global_draws: int) -> void:
	if mini(visible_primitives, mini(visible_draws, mini(shadow_primitives, shadow_draws))) < 0 \
		or global_draws < visible_draws + shadow_draws:
		_coverage_invalid += 1
		return
	_coverage_count += 1
	_coverage_visible_frames += int(visible_primitives > 0 and visible_draws > 0)
	# GL 4.7.2 将阴影draw累计在VISIBLE槽，SHADOW draw槽为零，不能据此判定无阴影。
	_coverage_shadow_frames += int(shadow_primitives > 0)
	_coverage_shadow_draw_frames += int(shadow_draws > 0)
	_record_coverage_slot(0, visible_primitives)
	_record_coverage_slot(1, visible_draws)
	_record_coverage_slot(2, shadow_primitives)
	_record_coverage_slot(3, shadow_draws)


func _record_coverage_slot(slot: int, value: int) -> void:
	_coverage_totals[slot] += value
	_coverage_minima[slot] = value if _coverage_count == 1 else mini(_coverage_minima[slot], value)
	_coverage_maxima[slot] = maxi(_coverage_maxima[slot], value)


func _coverage_report() -> String:
	var divisor := float(maxi(1, _coverage_count))
	var result := "render_coverage samples=%d invalid=%d visible_geometry_frames=%d shadow_geometry_frames=%d shadow_draw_counter_frames=%d pass_draw_attribution=raw_backend_counters proof=render_lists_and_draw_submission_not_screen_presentation" % [
		_coverage_count, _coverage_invalid, _coverage_visible_frames, _coverage_shadow_frames, _coverage_shadow_draw_frames]
	# 仅结果阶段格式化；影子通道可重复绘制同一物体，不能解读为唯一几何量。
	var names := ["visible_primitives", "visible_draws", "shadow_primitives", "shadow_draws"]
	for slot in range(4):
		result += " %s_avg=%.2f %s_min=%d %s_max=%d" % [names[slot], _coverage_totals[slot] / divisor,
			names[slot], _coverage_minima[slot], names[slot], _coverage_maxima[slot]]
	return result


func _timing_report() -> String:
	if not _timing_viewport.is_valid():
		return "render_timing=off"
	var divisor := float(maxi(1, _timing_count))
	return "render_timing=on sample_window=bench_render_frames samples=%d frames_seen=%d skipped_frames=%d gpu_nonzero=%d invalid=%d cpu_avg_ms=%.4f gpu_avg_ms=%.4f setup_avg_ms=%.4f cpu_max_ms=%.4f gpu_max_ms=%.4f setup_max_ms=%.4f diagnostic_only=true" % [
		_timing_count, _timing_last_frame, _timing_skipped_frames, _timing_gpu_nonzero, _timing_invalid,
		_timing_totals[0] / divisor, _timing_totals[1] / divisor, _timing_totals[2] / divisor,
		_timing_peaks[0], _timing_peaks[1], _timing_peaks[2]] + "\n" + _coverage_report()


func _exit_tree() -> void:
	if RenderingServer.frame_post_draw.is_connected(_sample_render_times):
		RenderingServer.frame_post_draw.disconnect(_sample_render_times)
	if _timing_viewport.is_valid():
		RenderingServer.viewport_set_measure_render_time(_timing_viewport, false)
		_timing_viewport = RID()


func _capture(_index: int) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://bench/results/volume_map_%s.png" % ("3d" if _is_3d else "2d"))
