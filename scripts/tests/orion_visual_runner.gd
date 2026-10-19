extends "res://scripts/survivor/survivor_mode.gd"
## 正式 Survivor + Debug 子阶段；保留真实 AI / 武器 / 伤害并采集实际 GL 画面。

var _orion_clock := preload("res://scripts/tests/map_frame_clock.gd").new()
var _orion_capture_started := false
var _orion_frames := 0
var _orion_peak_missiles := 0
var _orion_peak_units := 0
var _orion_capture_enabled := OS.get_environment("AGL_ORION_CAPTURE") != "0"


func _ready() -> void:
	super._ready()
	PerfBuckets.configure_frame_trace(true)


func _setup_boss_debug_scenario() -> void:
	# 必须在正式遭遇出生之前整体平移玩家小队，避免随后 bench 归零使战团相隔 30km。
	seed(42)
	var offset := player_aircraft.global_position
	if _squad != null:
		for member in _squad.members:
			if is_instance_valid(member):
				member.global_position -= offset
				member.clear_trail()
	player_aircraft.global_position = Vector2.ZERO
	camera.global_position = Vector2.ZERO
	super._setup_boss_debug_scenario()


func _process(delta: float) -> void:
	# 在父类 begin_render_frame 清桶之前记录上一完整帧，避免尖峰归因是空表。
	_orion_clock.observe(_orion_frames > 0 and _bench_elapsed > 8.0)
	super._process(delta)
	var boss: Variant = _spawner._boss if _spawner != null else null
	if typeof(boss) != TYPE_OBJECT or not is_instance_valid(boss) \
			or not boss is TheCrucibleEncounter or not boss.orion_started:
		return
	var enabled: bool = boss._engaged and boss.orion.active
	if enabled:
		var host: Aircraft = boss.orion.body()
		if host != null:
			_camera_ctrl.follow_enabled = false
			camera.global_position = host.global_position
			_bench_set_camera_zoom(0.65)
		_orion_frames += 1
		_orion_peak_missiles = maxi(_orion_peak_missiles, boss.orion._owned_missile_ids.size())
		_orion_peak_units = maxi(_orion_peak_units, CombatUnit.all_units.size())
		if _orion_capture_enabled and not _orion_capture_started:
			_orion_capture_started = true
			_capture_orion()


func _capture_orion() -> void:
	for index in range(3):
		await get_tree().create_timer(4.0).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://bench/results/orion_combat_%d.png" % index)


func _bench_finish_now(summary: String, exit_code: int = 0) -> void:
	var result := _orion_clock.report()
	if summary.contains("terminal=game_over") and summary.contains("victory=true"):
		exit_code = 0
	summary += "orion_frames=%d\norion_peak_missiles=%d\norion_peak_units=%d\norion_wall=%s\n" \
		% [_orion_frames, _orion_peak_missiles, _orion_peak_units, JSON.stringify(result)]
	if _orion_frames == 0 or _orion_peak_missiles == 0:
		exit_code = 1
	if not _orion_capture_enabled and not bool(result.passed):
		exit_code = 1
	super._bench_finish_now(summary, exit_code)
