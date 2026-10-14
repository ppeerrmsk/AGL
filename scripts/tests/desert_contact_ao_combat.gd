extends "res://scripts/survivor/survivor_mode.gd"
## 相同36成员与8段巡检，只把整场平移到真正的AO工业区，禁止用画外效果验性能。
const CENTER := Vector2(4800, 400)
const Pair := preload("res://scripts/tests/volume_map_performance.gd")
var _map_pair: Node


func _ready() -> void:
	_allow_formal_aircraft_volume = false
	get_tree().set_meta(BenchRunner.VOLUME_EXPERIMENT_META, true)
	get_tree().set_meta("ugc_map_path", "res://resources/maps/desert_railway_preview.aglmap")
	get_tree().set_meta("survivor_map_id", "desert_railway_preview")
	get_tree().set_meta("bench_scenario", "battlefield_atmosphere_stress_36")
	get_tree().set_meta("map_preview_only", false)
	seed(0xA61)
	super._ready()
	camera.ignore_rotation = false
	camera.force_update_scroll()
	_map_pair = Pair.new()
	add_child(_map_pair)
	_map_pair.setup(self, "volume_map_3d_c1")


func _bench_force_battlefield_atmosphere_stress() -> void:
	player_aircraft.global_position = CENTER
	player_aircraft.clear_trail()
	camera.global_position = CENTER
	_spawner._dynamic_enemy_cap = 0
	_bench_set_camera_zoom(0.2625)
	_bench_enable_camera_patrol(4000, 0.2625, CENTER)
	var ai: AIController = player_aircraft._get_ai_controller()
	if ai != null:
		ai.enable_combat = false
		ai.release_target(AIController.TargetSource.TS_SCORED, "AO map stress observer")
	_bench_atmosphere_experiment = BattlefieldAtmosphereExperimentScript.new()
	add_child(_bench_atmosphere_experiment)
	_bench_atmosphere_experiment.setup(self, _spawner)
	if not _bench_atmosphere_experiment.launch_stress_battle(36, 4000, CENTER):
		_bench_finish_now("terminal=ao_fixture_launch_failed\n", 1)


func _bench_finish_now(summary: String, exit_code: int = 0) -> void:
	var probe: Node = _map_pair._live_probe() if is_instance_valid(_map_pair) else null
	var material: Material = probe._root_map.material_override if is_instance_valid(probe) else null
	var enabled: bool = material is ShaderMaterial and material.get_shader_parameter("contact_ao_strength") == 0.65
	var expected := OS.get_environment("AGL_MAP_CONTACT_AO").to_lower() not in ["off", "0", "false"]
	if enabled != expected or not summary.contains("segments=8/8") or not summary.contains("frames_below_60=0\n"):
		exit_code = 1
	get_viewport().get_texture().get_image().save_png("res://bench/results/desert_contact_ao_c1.png")
	var state: String = _map_pair.summary() if is_instance_valid(_map_pair) else "missing map"
	super._bench_finish_now(summary + "contact_ao_active=" + str(enabled) + " center=" + str(CENTER) + "\n" + state, exit_code)
