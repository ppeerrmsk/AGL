extends "res://scripts/survivor/survivor_mode.gd"
## 同一36人混合负载置于海岛基地；真实地图/天气/飞机层，不减战斗工作量。
const CENTER := Vector2(-10300, -6500)
var _profile := ""
var _rotation_peak := 0.0
var _wall_clock := preload("res://scripts/tests/map_frame_clock.gd").new()
var _render_trace: RefCounted


func _process(delta: float) -> void:
	_wall_clock.observe(_bench_elapsed >= 3.0)
	if _render_trace != null:
		_render_trace.begin_frame(delta)
	super._process(delta)


func _exit_tree() -> void:
	if _render_trace != null:
		_render_trace.close()
	super._exit_tree()


func _ready() -> void:
	_profile = String(get_tree().get_meta("bench_scenario", "ocean_volume_c1"))
	OS.set_environment("AGL_OCEAN_VOLUME", "off" if _profile.ends_with("baseline") else "on")
	get_tree().set_meta("ugc_map_path", "res://resources/maps/ocean_islands_preview.aglmap")
	get_tree().set_meta("survivor_map_id", "ocean_islands_preview")
	get_tree().set_meta("bench_scenario", "battlefield_atmosphere_stress_48_24km" if _profile.contains("c2") else "battlefield_atmosphere_stress_36")
	get_tree().set_meta("map_preview_only", false)
	seed(0xA61)
	super._ready()
	camera.ignore_rotation = false
	camera.force_update_scroll()
	if _map_features == null:
		_map_features = MapFeatureRenderer.new()
		_map_features.show_behind_parent = true
		_map_features.ugc_vector_only = true
		_map_features.basemap_map_key = "ocean"
		_map_features.basemap_meta_path = "res://resources/maps/ocean_islands_bg_v2.json"
		_map_features.ugc_overlay_layers = UgcLoader.overlay_layers_from(_ugc_doc)
		_map_features.ugc_palette = _ugc_doc.style.get("palette", {}).duplicate(true)
		add_child(_map_features)
		move_child(_map_features, 0)
		_map_features.volume_document_path = _ugc_source_path
		_map_features.setup(camera, _map_boundary.get_world_rect())
	if _profile.ends_with("baseline") and _building_renderer == null:
		_building_renderer = BuildingRenderer.new()
		_building_renderer.show_behind_parent = true
		_building_renderer.perspective_k = 0.015
		add_child(_building_renderer)
		_building_renderer.setup(camera)
	print("[Ocean combat] profile=", _profile, " native_map=", is_instance_valid(_map_features._ocean_volume))
	if OS.get_environment("AGL_MAP_GPU_TRACE") == "1":
		_render_trace = preload("res://scripts/tests/tokyo_render_trace.gd").new()
		_render_trace.setup(get_viewport(), _map_features._ocean_volume._viewport, true)


func _bench_force_battlefield_atmosphere_stress() -> void:
	var center := Vector2.ZERO if _profile.contains("c2") else CENTER
	var span := 12000.0 if _profile.contains("c2") else 4000.0
	var count := 48 if _profile.contains("c2") else 36
	var zoom_value := 0.20 if _profile.contains("c2") else 0.2625
	player_aircraft.global_position = center
	player_aircraft.clear_trail()
	camera.global_position = center
	_spawner._dynamic_enemy_cap = 0
	_bench_set_camera_zoom(zoom_value)
	_bench_enable_camera_patrol(span, zoom_value, center)
	var ai: AIController = player_aircraft._get_ai_controller()
	if ai != null:
		ai.enable_combat = false
		ai.release_target(AIController.TargetSource.TS_SCORED, "Ocean map stress observer")
	_bench_atmosphere_experiment = BattlefieldAtmosphereExperimentScript.new()
	add_child(_bench_atmosphere_experiment)
	_bench_atmosphere_experiment.setup(self, _spawner)
	if not _bench_atmosphere_experiment.launch_stress_battle(count, span, center):
		_bench_finish_now("terminal=ocean_fixture_launch_failed\n", 1)


func _bench_update_camera_patrol() -> void:
	super._bench_update_camera_patrol()
	if _bench_elapsed >= 3.0:
		_rotation_peak = maxf(_rotation_peak, absf(rad_to_deg(camera.get_viewport().get_canvas_transform().get_rotation())))


func _bench_finish_now(summary: String, exit_code: int = 0) -> void:
	if _render_trace != null:
		_render_trace.close()
		summary += _render_trace.summary() + "\n"
	var wall := _wall_clock.report()
	summary += "map_wall_clock=" + JSON.stringify(wall) + "\n"
	if not wall.passed:
		exit_code = 1
	var overlay: Variant = _map_features._ocean_volume if is_instance_valid(_map_features) else null
	var state: Dictionary = overlay.debug_state() if is_instance_valid(overlay) else {}
	if not _profile.ends_with("baseline") and (state.is_empty() or int(state.get("misses", 1)) != 0):
		exit_code = 1
	var expected_ao := OS.get_environment("AGL_MAP_CONTACT_AO").to_lower() not in ["off", "0", "false"]
	if not _profile.ends_with("baseline") and state.get("contact_ao_active", false) != expected_ao:
		exit_code = 1
	if not summary.contains("segments=8/8") or not summary.contains("frames_below_60=0\n") or _rotation_peak < 13.0:
		exit_code = 1
	# 性能采样结束后才读回，避免把截图尖峰误算作地图负载。
	get_viewport().get_texture().get_image().save_png("res://bench/results/" + _profile + ".png")
	super._bench_finish_now(summary + "ocean_profile=" + _profile + "\nocean_map=" + str(state)
		+ "\nocean_rotation_max_deg=" + str(_rotation_peak) + "\n", exit_code)
