extends "res://scripts/survivor/survivor_mode.gd"
## 独立 BOSS 实战评估：正式编队/构筑/事件/伤害，只有测试采样，不改平衡。

var _assessment_boss := "ORION"
var _assessment_seed := 42
var _assessment_limit := 120.0
var _assessment_start := -1.0
var _assessment_first_damage := -1.0
var _assessment_next_sample := 0.0
var _assessment_event_cursor := 0
var _assessment_initial: Array[Dictionary] = []
var _assessment_player_names: Dictionary = {}
var _assessment_timeline: Array[Dictionary] = []
var _assessment_events: Array[Dictionary] = []
var _assessment_manifest: Dictionary = {}
var _assessment_seen_missiles: Dictionary = {}
var _assessment_rail_previous := 0
var _assessment_rail_shots := 0
var _assessment_laser_previous: Dictionary = {}
var _assessment_laser_activations := 0
var _assessment_intercepts := 0
var _assessment_ace_peak := 0
var _assessment_capture := false
var _assessment_output := ""
var _assessment_max_g := 0.0
var _assessment_min_radius := INF
var _assessment_previous_heading := INF
var _assessment_admm_phase_seconds := [0.0, 0.0, 0.0]
var _assessment_rail_charge_seconds := 0.0


func _ready() -> void:
	_assessment_boss = OS.get_environment("AGL_BOSS_COMPARE_ID")
	if _assessment_boss.is_empty():
		_assessment_boss = "ORION"
	var seed_text := OS.get_environment("AGL_BOSS_COMPARE_SEED")
	_assessment_seed = 42 if seed_text.is_empty() else int(seed_text)
	_assessment_limit = float(get_tree().get_meta("bench_duration", 120.0))
	_assessment_output = OS.get_environment("AGL_BOSS_COMPARE_OUT")
	seed(_assessment_seed)
	get_tree().root.size = Vector2i(1600, 900)
	# 复用已有真实战斗 bench 的地图/无敌关闭/演出暂停协议，结果仍由 boss_comparison 输出。
	get_tree().set_meta("bench_scenario", "orion_visual")
	get_tree().set_meta("boss_debug_mode", true)
	get_tree().set_meta("boss_debug_id", "THE_CRUCIBLE" if _assessment_boss == "ORION" else _assessment_boss)
	get_tree().set_meta("boss_debug_scenario", "orion_solo" if _assessment_boss == "ORION" else "full")
	get_tree().set_meta("boss_debug_node_id", "f47")
	get_tree().set_meta("survivor_aircraft_resource", "res://resources/player/playable_f47.tres")
	get_tree().set_meta("survivor_map_id", "desert_railway_preview")
	get_tree().set_meta("ugc_map_path", "res://resources/maps/desert_railway_preview.aglmap")
	get_tree().set_meta("map_preview_only", false)
	super._ready()


func _setup_boss_debug_scenario() -> void:
	seed(_assessment_seed)
	var offset := player_aircraft.global_position
	for raw: Variant in _squad.members:
		var ac := _assessment_aircraft(raw)
		if ac != null:
			ac.global_position -= offset
			ac.clear_trail()
	player_aircraft.global_position = Vector2.ZERO
	camera.global_position = Vector2.ZERO
	super._setup_boss_debug_scenario()
	# 配对实验跳过开场表演：在任何战斗物理帧前归还演员状态，并走正式 ENGAGED 入口。
	Presentation.clear_all()
	var event: GameEvent = _event_director.find_by_name("boss_encounter")
	if event is BossEncounterEvent and event.phase == BossEncounterEvent.Phase.PRE_STAGE:
		event._enter_engaged()
	_assessment_manifest = {"node": String(_boss_debug_node_id), "level": _boss_debug_level,
		"weapons": _boss_debug_weapons.duplicate(), "skills": _boss_debug_picks.duplicate(),
		"theme": _boss_debug_theme, "axes": survivor_player.axis_points.duplicate(),
		"prior_defeats": 0, "seed": _assessment_seed,
		"engaged": event is BossEncounterEvent and event.phase == BossEncounterEvent.Phase.ENGAGED,
		"approach": OS.get_environment("AGL_BOSS_COMPARE_APPROACH")}
	for raw: Variant in _squad.members:
		var ac := _assessment_aircraft(raw)
		if ac != null:
			_assessment_player_names[ac._log_name()] = true
			_assessment_initial.append({"id": ac.get_instance_id(), "name": ac._log_name(),
				"max_hp": ac.params.max_hp, "hp": ac.hp, "invulnerable": ac.invulnerable})
	_assessment_manifest["squad"] = _assessment_initial.duplicate(true)
	_assessment_event_cursor = EventLogger._event_next_id
	_assessment_start = _bench_elapsed
	_bench_duration = _assessment_start + _assessment_limit
	_assessment_manifest["boss_start"] = _assessment_snapshot()
	print("[BossComparison] build=" + JSON.stringify(_assessment_manifest))


func _setup_bench_scenario() -> void:
	super._setup_bench_scenario()
	seed(_assessment_seed + 10000)
	# 补充样本：模拟玩家一次正式全队突击指令，随后仍由原有 AI 与武器自行执行。
	if OS.get_environment("AGL_BOSS_COMPARE_APPROACH") == "attack":
		var boss: BossEncounter = _spawner.get_boss()
		if boss != null:
			for raw: Variant in boss.get_display_members():
				var target := _assessment_aircraft(raw)
				if target != null and not target.is_destroyed:
					_squad_cmd.command_attack_all(target, Situation.POSTURE_ASSAULT)
					break


func _on_squad_leader_changed(new_leader: Aircraft) -> void:
	super._on_squad_leader_changed(new_leader)
	# 正式换帅会把新机交给人类；自动战斗样本继续由该机现有 AI 驾驶。
	if is_instance_valid(new_leader) and new_leader == player_aircraft:
		var ai := new_leader._get_ai_controller()
		if ai != null:
			ai.manual_control = false


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if _bench_finished or _spawner == null:
		return
	var boss: BossEncounter = _spawner.get_boss()
	if boss == null:
		return
	if _assessment_start < 0.0 and boss.hud_visible:
		_assessment_start = _bench_elapsed
		_assessment_event_cursor = EventLogger._event_next_id
		_bench_duration = _assessment_start + _assessment_limit
		_assessment_manifest["boss_start"] = _assessment_snapshot()
		print("[BossComparison] engaged=" + JSON.stringify(_assessment_manifest.boss_start))
	if _assessment_start < 0.0:
		return
	_assessment_read_events()
	if boss is TheCrucibleEncounter and boss.orion != null:
		var controller: RefCounted = boss.orion
		var body: Aircraft = controller.body()
		if body != null and not body.is_destroyed:
			_assessment_max_g = maxf(_assessment_max_g, absf(body.g_load))
			if is_finite(_assessment_previous_heading):
				var rate := absf(wrapf(body.heading - _assessment_previous_heading, -PI, PI)) / delta
				if rate > 0.1 and body.speed > 50.0:
					_assessment_min_radius = minf(_assessment_min_radius, body.speed / rate)
			_assessment_previous_heading = body.heading
		_assessment_admm_phase_seconds[controller._admm_phase] += delta
		if controller._rail_elapsed >= 0.0:
			_assessment_rail_charge_seconds += delta
		for id: int in controller._owned_missile_ids:
			_assessment_seen_missiles[id] = true
		var fired: int = controller._rail_fired
		if fired > _assessment_rail_previous:
			_assessment_rail_shots += fired - _assessment_rail_previous
		_assessment_rail_previous = fired
		for i in range(controller.lasers.size()):
			var laser: RefCounted = controller.lasers[i]
			var phase: int = laser.phase
			if phase == 2 and int(_assessment_laser_previous.get(i, -1)) != 2:
				_assessment_laser_activations += 1
			_assessment_laser_previous[i] = phase
			_assessment_intercepts += laser.intercept_points.size()
	if _bench_elapsed >= _assessment_next_sample:
		_assessment_next_sample = _bench_elapsed + 1.0
		_assessment_timeline.append(_assessment_snapshot())
	if not _assessment_capture and _assessment_first_damage >= 0.0 \
			and _bench_elapsed - _assessment_first_damage >= 2.0 \
			and DisplayServer.get_name() != "headless":
		_assessment_capture = true
		_assessment_screenshot()


func _assessment_read_events() -> void:
	for id in range(_assessment_event_cursor, EventLogger._event_next_id):
		var event: Dictionary = EventLogger._events.get(id, {})
		if String(event.get("category", "")) in ["DAMAGE", "KILL", "MISSILE", "RAILGUN", "CONTROL_TAKEOVER"]:
			var row := event.duplicate(true)
			row["engaged_seconds"] = _bench_elapsed - _assessment_start
			row["player_squad"] = _assessment_player_names.has(String(row.get("subject", "")))
			_assessment_events.append(row)
			if row.category == "DAMAGE" and _assessment_first_damage < 0.0:
				_assessment_first_damage = _bench_elapsed
	_assessment_event_cursor = EventLogger._event_next_id


func _assessment_aircraft(raw: Variant) -> Aircraft:
	if typeof(raw) != TYPE_OBJECT or not is_instance_valid(raw) or not raw is Aircraft:
		return null
	return raw as Aircraft


func _assessment_snapshot() -> Dictionary:
	var squad: Array[Dictionary] = []
	var remaining_hp := 0.0
	var alive := 0
	for row in _assessment_initial:
		var raw: Variant = instance_from_id(int(row.id))
		var ac := _assessment_aircraft(raw)
		var hp := ac.hp if ac != null and not ac.is_destroyed else 0.0
		remaining_hp += maxf(hp, 0.0)
		alive += int(hp > 0.0)
		squad.append({"name": row.name, "hp": hp})
	var enemies: Array[Dictionary] = []
	var aces := 0
	# 初始化同帧全局单位缓存尚未刷新；从正式 encounter 演员表补齐，按实例去重。
	var units: Array = CombatUnit.all_units.duplicate()
	var encounter: BossEncounter = _spawner.get_boss() if _spawner != null else null
	if encounter != null:
		units.append_array(encounter.get_display_members())
	var seen: Dictionary = {}
	for raw: Variant in units:
		var ac := _assessment_aircraft(raw)
		if ac == null or ac.is_destroyed or ac.is_player_squad():
			continue
		if seen.has(ac.get_instance_id()):
			continue
		seen[ac.get_instance_id()] = true
		aces += int(ac.has_meta("crucible_profile"))
		enemies.append({"name": ac._log_name(), "hp": ac.hp, "max_hp": ac.params.max_hp,
			"speed_kmh": ac.speed * 3.6, "target_speed_kmh": ac.target_speed_kmh, "g": ac.g_load,
			"type": String(ac.get_meta("enemy_type", "")),
			"distance_to_player_px": ac.global_position.distance_to(player_aircraft.global_position)
				if is_instance_valid(player_aircraft) else -1.0})
	_assessment_ace_peak = maxi(_assessment_ace_peak, aces)
	return {"seconds": maxf(0.0, _bench_elapsed - _assessment_start),
		"squad_hp": remaining_hp, "squad_alive": alive, "squad": squad, "enemies": enemies,
		"ace_count": aces}


func _assessment_screenshot() -> void:
	var boss: BossEncounter = _spawner.get_boss()
	if boss is TheCrucibleEncounter and boss.orion != null:
		var body: Aircraft = boss.orion.body()
		if body != null and is_instance_valid(player_aircraft):
			_camera_ctrl.follow_enabled = false
			camera.global_position = (body.global_position + player_aircraft.global_position) * 0.5
			_bench_set_camera_zoom(0.4)
	await RenderingServer.frame_post_draw
	var path := "res://bench/results/boss_comparison_%s_%d.png" % [_assessment_boss, _assessment_seed]
	get_viewport().get_texture().get_image().save_png(path)


func _bench_finish_now(summary: String, exit_code: int = 0) -> void:
	if _bench_finished:
		return
	_assessment_read_events()
	var outcome := "victory" if _is_victory else ("defeat" if is_game_over else "timeout")
	var valid := _assessment_start >= 0.0 and not _assessment_initial.is_empty()
	valid = valid and bool(_assessment_manifest.get("engaged", false))
	if summary.contains("unexpected_tree_pause") or summary.contains("upgrade_pause_stuck"):
		valid = false
	var final := _assessment_snapshot()
	if _assessment_boss == "ORION":
		valid = valid and _assessment_ace_peak == 0
		var start: Dictionary = _assessment_manifest.get("boss_start", {})
		valid = valid and start.get("enemies", []).size() == 3
		for enemy in start.get("enemies", []):
			valid = valid and is_equal_approx(float(enemy.hp), float(enemy.max_hp))
	for row in _assessment_initial:
		valid = valid and not bool(row.invulnerable)
	var result := {"boss": _assessment_boss, "seed": _assessment_seed, "valid": valid,
		"observation_limit": _assessment_limit,
		"outcome": outcome, "engaged_seconds": maxf(0.0, _bench_elapsed - _assessment_start),
		"first_damage_seconds": _assessment_first_damage - _assessment_start if _assessment_first_damage >= 0.0 else -1.0,
		"combat_seconds": _bench_elapsed - _assessment_first_damage if _assessment_first_damage >= 0.0 else -1.0,
		"manifest": _assessment_manifest, "final": final, "timeline": _assessment_timeline,
		"ace_peak": _assessment_ace_peak, "orion_admm_launched": _assessment_seen_missiles.size(),
		"orion_rail_shots": _assessment_rail_shots, "fang_laser_activations": _assessment_laser_activations,
		"fang_missile_intercepts": _assessment_intercepts, "weapon_stats": EventLogger._stats.duplicate(true),
		"orion_max_g": _assessment_max_g,
		"orion_min_turn_radius_m": _assessment_min_radius if is_finite(_assessment_min_radius) else -1.0,
		"orion_admm_phase_seconds": _assessment_admm_phase_seconds,
		"orion_rail_charge_seconds": _assessment_rail_charge_seconds,
		"events": _assessment_events, "terminal": summary}
	var path := _assessment_output
	if path.is_empty():
		path = "res://bench/results/boss_comparison_%s_%d.json" % [_assessment_boss, _assessment_seed]
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(result, "\t"))
	else:
		valid = false
	print("[BossComparison] boss=%s seed=%d valid=%s outcome=%s engaged=%.2fs combat=%.2fs hp=%.1f alive=%d ADMM=%d rail=%d beams=%d intercepts=%d ACE=%d" % [
		_assessment_boss, _assessment_seed, valid, outcome, result.engaged_seconds, result.combat_seconds,
		final.squad_hp, final.squad_alive, _assessment_seen_missiles.size(), _assessment_rail_shots,
		_assessment_laser_activations, _assessment_intercepts, _assessment_ace_peak])
	# 玩家战败/到达观察上限也是有效评估样本；运行时错误仍由 wrapper 硬门拒绝。
	super._bench_finish_now(summary + "assessment_file=%s\n" % path, 0 if valid else 1)
