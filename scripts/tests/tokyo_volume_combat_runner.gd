extends "res://scripts/survivor/survivor_mode.gd"
## 同一真实 Survivor 混战负载，移动测试锚点到已制作城区；不移动地图去假装命中负载。
const CITY_CENTER := Vector2(300, -13300)
const RenderClock := preload("res://scripts/tests/tokyo_render_clock.gd")
var _tokyo_profile := ""
var _city_center := CITY_CENTER
var _near_base_zoom := 1.2
var _actual_rotation_peak := 0.0
var _render_trace: RefCounted
var _static_shadow: RefCounted
var _baked_ao: RefCounted
var _draw_geometry_probe: RefCounted
var _wall_previous_usec := 0
var _wall_samples := 0
var _wall_total_usec := 0
var _wall_max_usec := 0
var _wall_below60 := 0
var _wall_intervals := PackedInt64Array()
var _wall_trace := false
var _wall_slow: Array[Dictionary] = []
var _frame_timeline: Array[Dictionary] = []
var _hlod_samples := 0
var _hlod_ground_frames := 0
var _hlod_hidden_frames := 0
var _hlod_waiting_frames := 0
var _hlod_budget_frames := 0
var _hlod_unqualified_frames := 0
var _hlod_expired_frames := 0
var _hlod_uncovered_frames := 0
var _hlod_quality_failures: Array[Dictionary] = []
var _hlod_gaps: Array[Dictionary] = []
var _hlod_gap_active := false
const WALL_SAMPLE_LIMIT := 120000


func _ready() -> void:
	# 仅显式诊断对照；不保存设置，不把禁用同步的结果冒充默认游戏性能。
	if OS.get_environment("AGL_TOKYO_DIAGNOSTIC_VSYNC")=="off":
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	_wall_trace = OS.get_environment("AGL_TOKYO_WALL_TRACE") == "1"
	_tokyo_profile = String(get_tree().get_meta("bench_scenario", "tokyo_volume_c1"))
	if OS.get_environment("AGL_TOKYO_BENCH_MID") == "1":
		_near_base_zoom = 0.9
	if OS.get_environment("AGL_TOKYO_BENCH_CLOSE") == "1" and _tokyo_profile.contains("_near"):
		_near_base_zoom = 2.4  # 只扩近景专项，实际命中LOD5；标准C1/原near不变。
	var previous_override := OS.get_environment("AGL_TOKYO_VOLUME")
	if _tokyo_profile.ends_with("baseline"):
		OS.set_environment("AGL_TOKYO_VOLUME", "off")
	elif _tokyo_profile.begins_with("tokyo_cells_"):
		OS.set_environment("AGL_TOKYO_VOLUME", "cells")
	seed(0xA61)
	var wide := _tokyo_profile.contains("_c2")
	_city_center = Vector2(300, -8000) if wide else CITY_CENTER
	if OS.get_environment("AGL_TOKYO_CELLS_VARIANT").begins_with("yokohama"):
		_city_center = Vector2(-5300, -700)
	elif OS.get_environment("AGL_TOKYO_CELLS_VARIANT").begins_with("kawasaki"):
		_city_center = Vector2(-4300, -2700)
	if OS.get_environment("AGL_TOKYO_BENCH_NORTH") == "1":
		_city_center = Vector2(-5600, -2900)
	if OS.get_environment("AGL_TOKYO_BENCH_WEST") == "1":
		_city_center = Vector2(-6550,-2200)
	if OS.get_environment("AGL_TOKYO_BENCH_WEST_EXTENSION") == "1":
		_city_center = Vector2(-7050,-2200)
	if OS.get_environment("AGL_TOKYO_BENCH_RESIDENTIAL") == "1":
		_city_center = Vector2(-6130,-2195)  # 只移动同负载锚点，保持演员/镜头节拍。
	if OS.get_environment("AGL_TOKYO_BENCH_LEGACY") == "1":
		_city_center = Vector2(-5800, -1025)  # 两组都实际覆盖旧楼交接区域。
	if OS.get_environment("AGL_TOKYO_BENCH_NORTHWEST") == "1":
		_city_center = Vector2(-6755,-3200)  # 同负载与巡检，只移动到已接入西北片区。
	get_tree().set_meta("bench_scenario", "battlefield_atmosphere_stress_48_24km" if wide else "battlefield_atmosphere_stress_36")
	super._ready()
	var requested_cap := OS.get_environment("AGL_TOKYO_DIAGNOSTIC_MAX_FPS")
	var cap := RenderClock.diagnostic_cap(requested_cap, DisplayServer.screen_get_refresh_rate())
	if cap < 0:
		push_error("Tokyo diagnostic frame cap rejected")
		get_tree().quit(1)
		return
	if cap > 0:
		Engine.max_fps = cap
	camera.ignore_rotation = false
	camera.force_update_scroll()
	if _map_features == null:
		_map_features = MapFeatureRenderer.new()
		_map_features.show_behind_parent = true
		add_child(_map_features)
		move_child(_map_features, 0)
		_map_features.setup(camera, _map_boundary.get_world_rect())
	OS.set_environment("AGL_TOKYO_VOLUME", previous_override)
	# 旧地图基准没有创建旧楼层；显示交接A/B必须显式为两组补同一正式BuildingRenderer。
	if OS.get_environment("AGL_TOKYO_BENCH_LEGACY") == "1":
		if not is_instance_valid(_building_renderer):
			_building_renderer = BuildingRenderer.new()
			_building_renderer.show_behind_parent = true
			add_child(_building_renderer)
			_building_renderer.setup(camera)
		if is_instance_valid(_map_features._tokyo_volume) and _map_features._tokyo_volume.has_method("bind_legacy"):
			if not _map_features._tokyo_volume.bind_legacy(_building_renderer):
				get_tree().quit(1)
				return
	# 只给显式诊断组停投影，正式地图及光照材质不变。
	if OS.get_environment("AGL_TOKYO_BOUNDED_LEGACY_BENCH") == "1":
		if OS.get_environment("AGL_TOKYO_BENCH_LEGACY") != "1" or not is_instance_valid(_building_renderer):
			get_tree().quit(1)
			return
		_building_renderer.bounded_roof_projection = true
		_building_renderer.cache_shadow_geometry = OS.get_environment("AGL_TOKYO_SHADOW_CACHE_BENCH") == "1"
		_building_renderer.queue_redraw()
	if OS.get_environment("AGL_TOKYO_BENCH_SHADOWS") == "off" and is_instance_valid(_map_features._tokyo_volume):
		_map_features._tokyo_volume._sun.shadow_enabled = false
	print("[Tokyo combat] profile=", _tokyo_profile, " volume=", _map_features._tokyo_volume != null)
	var static_directory := OS.get_environment("AGL_TOKYO_STATIC_SHADOW")
	if not static_directory.is_empty():
		# 该局部候选只测C1路径；不把单档遮罩带入尚未接线的近景巡航。
		if _tokyo_profile != "tokyo_cells_c1" or not is_instance_valid(_map_features._tokyo_volume):
			get_tree().quit(1)
			return
		_static_shadow = preload("res://scripts/experiments/tokyo_static_shadow.gd").new()
		if not _static_shadow.bind(_map_features._tokyo_volume, static_directory, 1.28):
			get_tree().quit(1)
			return
		_static_shadow.set_strength(0.5)
		tree_exiting.connect(_static_shadow.close, CONNECT_ONE_SHOT)
	var trace_mode := OS.get_environment("AGL_TOKYO_RENDER_TRACE")
	if OS.get_environment("AGL_TOKYO_DRAW_GEOMETRY_PROBE")=="1":
		_draw_geometry_probe=preload("res://scripts/tests/tokyo_draw_geometry_probe.gd").new()
		if not _draw_geometry_probe.setup(_map_features._tokyo_volume):
			get_tree().quit(1)
			return
		tree_exiting.connect(_draw_geometry_probe.close,CONNECT_ONE_SHOT)
	var ao_directory := OS.get_environment("AGL_TOKYO_AO")
	if OS.get_environment("AGL_TOKYO_AO_PRELOAD") != "":
		if not is_instance_valid(_map_features._tokyo_volume) or not _map_features._tokyo_volume.has_method("bind_legacy"):
			get_tree().quit(1)
			return
		_baked_ao = _map_features._tokyo_volume._preloaded_ao
		if _baked_ao == null or not _baked_ao.stats.get("preloaded", false):
			get_tree().quit(1)
			return
	if not ao_directory.is_empty():
		if _tokyo_profile != "tokyo_cells_c1" or not is_instance_valid(_map_features._tokyo_volume):
			get_tree().quit(1)
			return
		_baked_ao = preload("res://scripts/experiments/tokyo_baked_ao.gd").new()
		if not _baked_ao.bind_ao(_map_features._tokyo_volume, ao_directory, 1.28):
			get_tree().quit(1)
			return
		_baked_ao.strength(0.45)
	if trace_mode in ["phases", "backend"] and is_instance_valid(_map_features._tokyo_volume):
		_render_trace = load("res://scripts/tests/tokyo_render_trace.gd").new()
		var aircraft_view: Variant = _aircraft_volume_overlay._subviewport if is_instance_valid(_aircraft_volume_overlay) else null
		_render_trace.setup(get_viewport(), _map_features._tokyo_volume._viewport, trace_mode == "backend", aircraft_view)
		tree_exiting.connect(_render_trace.close, CONNECT_ONE_SHOT)


func _process(delta: float) -> void:
	# 所有东京性能入口都保留实际时钟硬门，不让delta摘要漏报卡顿。
	var now := Time.get_ticks_usec()
	var diagnostic_capture := PerfBuckets.extended_cpu_trace_enabled
	if _bench_elapsed >= 3.0:
		if _wall_previous_usec > 0:
			var interval := now - _wall_previous_usec
			_wall_samples += 1
			_wall_total_usec += interval
			_wall_max_usec = maxi(_wall_max_usec, interval)
			_wall_below60 += int(not RenderClock.frame_within_budget(interval))
			# 只复用既有帧首时钟和CPU桶；不连接渲染信号，避免改变待诊断的提交节拍。
			if _wall_trace and not RenderClock.frame_within_budget(interval):
				RenderClock.retain_slowest(_wall_slow, {"frame":PerfBuckets._trace_frame_index,
					"wall_us":interval,"physics_ticks":PerfBuckets._trace_physics_ticks,
					"cpu_buckets_us":PerfBuckets._trace_frame_us.duplicate(),
					"events":PerfBuckets._trace_frame_events.duplicate()})
			if _wall_intervals.size() < WALL_SAMPLE_LIMIT:
				_wall_intervals.append(interval)
			# 显式诊断逐帧留存；运行中不打印、不读回图像，结束后一次导出。
			if _wall_trace and _frame_timeline.size()<12000:
				var row := {"frame":PerfBuckets._trace_frame_index,"engine_frame":Engine.get_process_frames(),
					"begin_ticks_usec":_wall_previous_usec,"next_ticks_usec":now,
					"elapsed":_bench_elapsed,"wall_us":interval,"position":camera.global_position,"zoom":camera.zoom,
					"physics_ticks":PerfBuckets._trace_physics_ticks,"cpu_buckets_us":PerfBuckets._trace_frame_us.duplicate(),
					"events":PerfBuckets._trace_frame_events.duplicate(),"counts":PerfBuckets._trace_frame_counts.duplicate()}
				var overlay: Variant=_map_features._tokyo_volume if is_instance_valid(_map_features) else null
				if is_instance_valid(overlay) and overlay.has_method("_target_committed"):
					row["map"]={"visible":overlay._screen.visible,"catalog":overlay._committed_catalog,"target_catalog":overlay._target_catalog,
						"current":overlay._committed.duplicate(),"target":overlay._target.get("keys",[]).duplicate(),"committed":overlay._target_committed(),
						"reason":overlay._handoff_reason,"fallback":overlay._fallback,"scale":overlay.output_scale,
						"qualified":overlay.display_qualified,"covered":overlay.display_covered,"grace":overlay._display_grace}
				_frame_timeline.append(row)
		_wall_previous_usec = now
		if is_instance_valid(_map_features):
			var map: Variant = _map_features._tokyo_volume
			if is_instance_valid(map) and map.has_method("_target_committed"):
				_hlod_samples+=1
				_hlod_ground_frames+=int(not map._committed_cut.get("ground_images",PackedStringArray()).is_empty())
				_hlod_hidden_frames+=int(not map._screen.visible)
				_hlod_unqualified_frames+=int(map._screen.visible and not map.display_qualified)
				_hlod_expired_frames+=int(map._screen.visible and not map.display_qualified and not map._display_grace)
				_hlod_uncovered_frames+=int(map._screen.visible and not map.display_covered)
				if map._screen.visible and (not map.display_covered or (not map.display_qualified and not map._display_grace)) and _hlod_quality_failures.size()<32:
					_hlod_quality_failures.append({"elapsed":_bench_elapsed,"scale":map.output_scale,"catalog":map._committed_catalog,
						"qualified":map.display_qualified,"covered":map.display_covered,"grace":map._display_grace,"reason":map._handoff_reason})
				_hlod_waiting_frames+=int(not map._target_committed())
				_hlod_budget_frames+=int(map._fallback=="cut budget" or int(map._committed_cut.get("bytes",0))>map.display_budget \
					or int(map._committed_cut.get("triangles",0))>240000 or map._committed.size()>16)
				if not map._screen.visible:
					if not _hlod_gap_active and _hlod_gaps.size()<32:
						_hlod_gaps.append({"start":_bench_elapsed,"end":_bench_elapsed,"frames":0,
							"position":str(camera.global_position),"scale":map.output_scale,"catalog":map._target_catalog,
							"reason":map._handoff_reason,"fallback":map._fallback})
					_hlod_gap_active=true
					if not _hlod_gaps.is_empty():
						_hlod_gaps[-1].end=_bench_elapsed
						_hlod_gaps[-1].frames+=1
				else: _hlod_gap_active=false
	else:
		_wall_previous_usec = 0
	var diagnostic_before_render_trace_usec := Time.get_ticks_usec() if diagnostic_capture else 0
	if _render_trace != null:
		_render_trace.begin_frame(delta, now)
	var diagnostic_before_super_usec := Time.get_ticks_usec() if diagnostic_capture else 0
	super._process(delta)
	# 父类会清空帧桶；局部值跨过重置后记入从 now 开始的新帧，不重复计父类。
	if diagnostic_capture:
		PerfBuckets.tick("diagnostic.runner_own_before_render_trace", diagnostic_before_render_trace_usec - now)
		PerfBuckets.tick("diagnostic.render_trace_begin", diagnostic_before_super_usec - diagnostic_before_render_trace_usec)


func _bench_force_battlefield_atmosphere_stress() -> void:
	var members := 48 if _tokyo_profile.contains("_c2") else 36
	var span := 12000.0 if members == 48 else 4000.0
	var zoom_value := _near_base_zoom if _tokyo_profile.contains("_near") else 1050.0 / span
	print("[Tokyo combat] constructing ", members, "-actor city fixture")
	player_aircraft.global_position = _city_center
	player_aircraft.clear_trail()
	camera.global_position = _city_center
	_spawner._dynamic_enemy_cap = 0
	_bench_set_camera_zoom(zoom_value)
	_bench_enable_camera_patrol(span, 0.2625 if _tokyo_profile.contains("_near") else zoom_value, _city_center)
	var player_ai: AIController = player_aircraft._get_ai_controller()
	if player_ai != null:
		player_ai.enable_combat = false
		player_ai.release_target(AIController.TargetSource.TS_SCORED, "Tokyo map stress observer")
	_bench_atmosphere_experiment = BattlefieldAtmosphereExperimentScript.new()
	add_child(_bench_atmosphere_experiment)
	_bench_atmosphere_experiment.setup(self, _spawner)
	var launched: bool = _bench_atmosphere_experiment.launch_stress_battle(members, span, _city_center)
	if not launched:
		_bench_finish_now("terminal=tokyo_fixture_launch_failed\n", 1)
		return
	for child in get_children():
		if not child is Aircraft or child == player_aircraft or child.is_in_group(&"battlefield_atmosphere_actor"):
			continue
		child.global_position += _city_center
		child.clear_trail()
		child.invulnerable = true
		var ai: AIController = child._get_ai_controller()
		if ai != null:
			ai.enable_combat = false
			ai.release_target(AIController.TargetSource.TS_SCORED, "Tokyo map fixed baseline")


func _bench_update_camera_patrol() -> void:
	var previous_min := _bench_camera_patrol_min_zoom
	var previous_max := _bench_camera_patrol_max_zoom
	super._bench_update_camera_patrol()
	if _bench_elapsed >= 3.0:
		_actual_rotation_peak = maxf(_actual_rotation_peak, absf(rad_to_deg(camera.get_viewport().get_canvas_transform().get_rotation())))
	if not _tokyo_profile.contains("_near") or _bench_camera_patrol_span_px <= 0.0:
		return
	# 复用标准巡检节拍；只在独立近景专项将未触顶的倍率放大，标准 C1/C2 不变。
	var near_zoom := camera.zoom.x * (_near_base_zoom / 0.2625)
	_bench_set_camera_zoom(near_zoom)
	if _bench_elapsed >= 3.0:
		_bench_camera_patrol_min_zoom = minf(previous_min, near_zoom)
		_bench_camera_patrol_max_zoom = maxf(previous_max, near_zoom)


func _capture_city() -> void:
	var overlay: Variant = _map_features._tokyo_volume
	print("[Tokyo combat] live map=", overlay.debug_state() if is_instance_valid(overlay) else "2d baseline")
	get_viewport().get_texture().get_image().save_png("res://bench/results/" + _tokyo_profile + ".png")


static func cell_peak_within_budget(state: Dictionary) -> bool:
	# 最终机位可能已经缩回低档，不能用最终三角量代替整个移动过程的峰值。
	var peak := int(state.get("max_transition_triangles", -1))
	return peak >= 0 and peak <= 240000


func _bench_finish_now(summary: String, exit_code: int = 0) -> void:
	if _hlod_samples>0 or not OS.get_environment("AGL_TOKYO_HLOD_PACKAGE").is_empty():
		summary+="\ntokyo_hlod_visibility="+JSON.stringify({"samples":_hlod_samples,"hidden_frames":_hlod_hidden_frames,
			"native_ground_frames":_hlod_ground_frames,"waiting_frames":_hlod_waiting_frames,"budget_frames":_hlod_budget_frames,"gaps":_hlod_gaps,
			"unqualified_frames":_hlod_unqualified_frames,"expired_frames":_hlod_expired_frames,"uncovered_frames":_hlod_uncovered_frames,
			"quality_failures":_hlod_quality_failures})+"\n"
		if _hlod_samples==0 or _hlod_hidden_frames>0 or _hlod_budget_frames>0 or _hlod_expired_frames>0 or _hlod_uncovered_frames>0: exit_code=1
	if OS.get_environment("AGL_TOKYO_BENCH_LEGACY") == "1":
		summary += "\ntokyo_legacy=" + JSON.stringify({"present": is_instance_valid(_building_renderer),
			"visible": _building_renderer.is_visible_in_tree() if is_instance_valid(_building_renderer) else false,
			"bounded": _building_renderer.bounded_roof_projection if is_instance_valid(_building_renderer) else false,
			"shadow_cached": _building_renderer.cache_shadow_geometry if is_instance_valid(_building_renderer) else false,
			"shadow_builds": _building_renderer.shadow_cache_builds if is_instance_valid(_building_renderer) else 0,
			"sources": _building_renderer._districts.size() if is_instance_valid(_building_renderer) else 0,
			"hidden": _building_renderer._volume_sources.size() if is_instance_valid(_building_renderer) else 0}) + "\n"
		if not is_instance_valid(_building_renderer) or _building_renderer._districts.is_empty():
			exit_code = 1
	if _static_shadow != null:
		summary += "\ntokyo_static_shadow=" + JSON.stringify(_static_shadow.stats) + "\n"
	var quantiles := RenderClock.percentiles_usec(_wall_intervals)
	quantiles["complete"] = _wall_intervals.size() == _wall_samples
	summary += "\ntokyo_wall_percentiles=" + JSON.stringify(quantiles) + "\n"
	summary += "tokyo_shadow_control=" + OS.get_environment("AGL_TOKYO_BENCH_SHADOWS") + "\n"
	summary += "tokyo_vsync_diagnostic=" + JSON.stringify({"requested":OS.get_environment("AGL_TOKYO_DIAGNOSTIC_VSYNC"),"actual":DisplayServer.window_get_vsync_mode()}) + "\n"
	summary += "tokyo_pacing_diagnostic=" + JSON.stringify({"requested_cap":OS.get_environment("AGL_TOKYO_DIAGNOSTIC_MAX_FPS"),
		"actual_cap":Engine.max_fps,"refresh_hz":DisplayServer.screen_get_refresh_rate(),
		"window_mode":DisplayServer.window_get_mode(),"vrr_verified":false}) + "\n"
	summary += "\ntokyo_wall_clock=" + JSON.stringify({"samples": _wall_samples, "below60": _wall_below60,
		"avg_fps": _wall_samples * 1000000.0 / maxf(1.0, _wall_total_usec),
		"worst_fps": 1000000.0 / maxf(1.0, _wall_max_usec), "max_ms": _wall_max_usec / 1000.0}) + "\n"
	if _wall_samples == 0 or _wall_below60 > 0:
		exit_code = 1
	if _wall_trace:
		if is_instance_valid(missile_manager):
			summary+="\nmissile_hit_cost_us="+JSON.stringify(missile_manager.hit_cost_us)+"\n"
		summary += "\ntokyo_wall_trace=" + JSON.stringify({"diagnostic_only":true,
			"render_signal_hooks":false,"slow_records":_wall_slow,"considered":_wall_below60,
			"omitted":maxi(0,_wall_below60-_wall_slow.size())}) + "\n"
		summary+="\ntokyo_frame_timeline="+JSON.stringify({"diagnostic_only":true,"frames":_frame_timeline,
			"omitted":maxi(0,_wall_samples-_frame_timeline.size()),"sampling":"previous frame CPU/state at the next process boundary"})+"\n"
	if _render_trace != null:
		_render_trace.close()
		summary += "\n" + _render_trace.summary() + "\n"
	# 截图读回会阻塞 GPU；必须在性能采样已经完成后进行，不能把探针自身算进帧尖刺。
	if _draw_geometry_probe!=null:
		_draw_geometry_probe.close()
		var draw_state: Dictionary = _draw_geometry_probe.summary()
		summary += "\ntokyo_draw_geometry_probe="+JSON.stringify(draw_state)+"\n"
		if int(draw_state.underreported_frames)>0:
			exit_code=1
	_capture_city()
	var overlay: Variant = _map_features._tokyo_volume if is_instance_valid(_map_features) else null
	var map_state: Dictionary = overlay.debug_state() if is_instance_valid(overlay) else {}
	summary+="\ntokyo_map_planning="+JSON.stringify({"pipeline":map_state.get("map_planning",{}),
		"main_hlod_builds":map_state.get("hlod_solver_builds",0),"main_native_builds":map_state.get("native_solver_builds",0),
		"main_qualification_builds":map_state.get("qualification_builds",0)})+"\n"
	if is_instance_valid(overlay) and overlay.has_method("_pending_hlod_covers") and not overlay._selection_trace.is_empty():
		summary+="\ntokyo_selection_trace="+JSON.stringify({"diagnostic_only":true,"selections":overlay._selection_trace})+"\n"
	if _baked_ao != null:
		var total := int(map_state.stream.peak_bytes) + int(_baked_ao.stats.conservative_bytes)
		summary += "\ntokyo_baked_ao=" + JSON.stringify(_baked_ao.stats) + "\nao_geometry_peak_bytes=" + str(total) + "\n"
		if total > 96 * 1024 * 1024 or float(map_state.output_scale) > float(_baked_ao.stats.max_scale):
			exit_code = 1
	if not _tokyo_profile.ends_with("baseline") and (map_state.is_empty() or int(map_state.redraws) == 0):
		exit_code = 1
	if not summary.contains("segments=8/8") or not summary.contains("frames_below_60=0\n"):
		exit_code = 1
	if _actual_rotation_peak < 13.0:
		exit_code = 1
	if _tokyo_profile.begins_with("tokyo_cells") and not _tokyo_profile.ends_with("baseline") \
			and not cell_peak_within_budget(map_state):
		print("[Tokyo combat] cell peak exceeds 240000 or is unavailable: ", map_state.get("max_transition_triangles", -1))
		exit_code = 1
	if _tokyo_profile.contains("_near") and _near_base_zoom == 0.9 \
			and OS.get_environment("AGL_TOKYO_CELLS_VARIANT") in ["yokohama_mid", "yokohama_directional", "yokohama_adaptive", "yokohama_frustum", "yokohama_coverage", "yokohama_coverage_b", "yokohama_coverage_c", "yokohama_domes", "yokohama_domes_b", "yokohama_shadow_depth", "yokohama_dedup", "kawasaki", "kawasaki_strokes", "kawasaki_lod"] and not map_state.is_empty():
		if int(map_state.mid_binds) == 0 or int(map_state.full4_binds) == 0:
			exit_code = 1
	super._bench_finish_now(summary + "\ntokyo_profile=" + _tokyo_profile + "\ntokyo_near_base_zoom=" + str(_near_base_zoom)
		+ "\ntokyo_actual_rotation_max_deg=" + str(_actual_rotation_peak) + "\nmap=" + str(map_state) + "\n", exit_code)
