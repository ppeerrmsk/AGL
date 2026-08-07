class_name EvolutionGrowthBenchmark
extends RefCounted

## 14 分钟进化成长单局记录器（spec evolution-growth-benchmark）。
## 只在 bench `evolution_growth` 中实例化；不新增常驻 Node / process。

const SETTLEMENT_INTERVAL_S: float = 60.0
const COMBAT_SAMPLE_INTERVAL_S: float = 1.0
const VALID_COMBAT_RATIO: float = 0.80

const PROFILE_PATHS: Dictionary = {
	"f15": "res://resources/playable_f15.tres",
	"f14": "res://resources/playable_f14.tres",
	"a6e": "res://resources/player/playable_a6e.tres",
	"mirage3": "res://resources/player/playable_mirage3.tres",
}

## 固定路线同时固定每 3 级的选卡轴；四条路线覆盖斗士、骑士、策士。
const ROUTES: Dictionary = {
	"f15": {
		"axis": &"gladiator",
		"nodes": [&"f15", &"f15e", &"a12", &"faxx", &"x44"],
	},
	"f14": {
		"axis": &"knight",
		"nodes": [&"f14", &"mig31", &"j20", &"mig41", &"x21"],
	},
	"a6e": {
		"axis": &"gladiator",
		"nodes": [&"a6e", &"a10", &"a12", &"faxx", &"x44"],
	},
	"mirage3": {
		"axis": &"schemer",
		"nodes": [&"mirage3", &"f16", &"f35", &"fcas", &"x13"],
	},
}

var starter_id: String = ""
var squad_size: int = 1
var seed_value: int = 1
var run_id: String = ""
var route_axis: StringName = &""
var route_nodes: Array = []
var expected_duration_s: float = 840.0

var _mode: Node
var _route_index: int = 0
var _settlement_elapsed: float = 0.0
var _combat_sample_elapsed: float = 0.0
var _combat_seconds: float = 0.0
var _enemy_present_last_sample: bool = false
var _ace_kills: int = 0
var _wingman_kills: int = 0
var _missed_settlements: int = 0
var _missing_axis_counts: Dictionary = {
	"gladiator": 0,
	"knight": 0,
	"schemer": 0,
}
var _missing_axis_wait_s: Dictionary = {
	"gladiator": 0.0,
	"knight": 0.0,
	"schemer": 0.0,
}
var _first_tier_times: Dictionary = {
	"2": -1.0,
	"3": -1.0,
	"4": -1.0,
	"5": -1.0,
}
var _configured: bool = false
var _finished: bool = false


func configure_from_environment(duration_s: float) -> bool:
	starter_id = OS.get_environment("AGL_GROWTH_STARTER").strip_edges().to_lower()
	run_id = OS.get_environment("AGL_GROWTH_RUN_ID").strip_edges()
	var squad_text := OS.get_environment("AGL_GROWTH_SQUAD_SIZE").strip_edges()
	var seed_text := OS.get_environment("AGL_GROWTH_SEED").strip_edges()
	if not PROFILE_PATHS.has(starter_id) or not ROUTES.has(starter_id):
		push_error("[GrowthBench] invalid starter: %s" % starter_id)
		return false
	if run_id == "" or not run_id.is_valid_filename():
		push_error("[GrowthBench] invalid run id: %s" % run_id)
		return false
	if not squad_text.is_valid_int() or not seed_text.is_valid_int():
		push_error("[GrowthBench] squad/seed must be integers")
		return false
	squad_size = int(squad_text)
	seed_value = int(seed_text)
	if squad_size not in [1, 3, 5, 9] or seed_value <= 0:
		push_error("[GrowthBench] unsupported squad=%d seed=%d" % [squad_size, seed_value])
		return false
	var route: Dictionary = ROUTES[starter_id]
	route_axis = StringName(route["axis"])
	route_nodes = (route["nodes"] as Array).duplicate()
	expected_duration_s = maxf(1.0, duration_s)
	_configured = true
	return true


func profile_path() -> String:
	return String(PROFILE_PATHS.get(starter_id, ""))


func apply_squad_size(profile: PlayableAircraft) -> PlayableAircraft:
	var adjusted: PlayableAircraft = profile.duplicate()
	adjusted.wingman_count = squad_size - 1
	return adjusted


func setup(mode: Node) -> bool:
	if not _configured or mode == null or mode.survivor_player == null:
		return false
	_mode = mode
	var start_node := EvolutionSystem.node_id_for_profile(mode._player_profile_id)
	if start_node != StringName(route_nodes[0]):
		push_error("[GrowthBench] profile/tree mismatch: %s != %s" % [start_node, route_nodes[0]])
		return false
	mode.player_aircraft.set_meta("evo_node", start_node)
	mode.player_aircraft.set_meta("evo_history", [start_node])
	if not EventLogger.kill_recorded.is_connected(_on_kill_recorded):
		EventLogger.kill_recorded.connect(_on_kill_recorded)
	print("[GrowthBench] run=%s starter=%s squad=%d seed=%d axis=%s route=%s" % [
		run_id, starter_id, squad_size, seed_value, route_axis, route_nodes])
	return true


func handle_level_up() -> void:
	if _finished or _mode == null:
		return
	var player: SurvivorPlayer = _mode.survivor_player
	if player.level % 3 == 0:
		var cards: Array[Dictionary] = _mode._roll_axis_cards(true)
		var pick: Dictionary = {}
		for card in cards:
			if SurvivorData.axis_of_upgrade(card) == route_axis:
				pick = card
				break
		if pick.is_empty() and not cards.is_empty():
			pick = cards[0]
		if not pick.is_empty():
			if String(pick.get("stat", "")) != "axis_focus":
				_mode._apply_upgrade_choice(pick)
			player.add_axis_point(SurvivorData.axis_of_upgrade(pick), _mode._player_profile)
	player.consume_level_up_display()


func tick(delta: float) -> void:
	if _finished or _mode == null:
		return
	_settlement_elapsed += delta
	_combat_sample_elapsed += delta
	if _enemy_present_last_sample:
		_combat_seconds += delta
	if _combat_sample_elapsed >= COMBAT_SAMPLE_INTERVAL_S:
		_combat_sample_elapsed = fmod(_combat_sample_elapsed, COMBAT_SAMPLE_INTERVAL_S)
		_enemy_present_last_sample = _mode._count_enemy_alive() > 0
	_accumulate_axis_wait(delta)
	if _settlement_elapsed >= SETTLEMENT_INTERVAL_S:
		_settlement_elapsed = fmod(_settlement_elapsed, SETTLEMENT_INTERVAL_S)
		_try_fixed_route_evolution()


func _try_fixed_route_evolution() -> void:
	if _route_index + 1 >= route_nodes.size():
		return
	var next_id: StringName = StringName(route_nodes[_route_index + 1])
	var next_node: Dictionary = EvolutionSystem.node_of(next_id)
	var level: int = _mode.survivor_player.level
	if level < EvolutionSystem.min_level_of(next_node):
		return
	var missing := EvolutionSystem.gates_missing(next_node, _mode.survivor_player.axis_points)
	if not missing.is_empty():
		_missed_settlements += 1
		for gap in missing:
			var key := String(gap.get("key", ""))
			if _missing_axis_counts.has(key):
				_missing_axis_counts[key] = int(_missing_axis_counts[key]) + 1
		return
	_mode._on_settlement_evolution(next_id)
	var applied: StringName = _mode.player_aircraft.get_meta("evo_node", &"")
	if applied != next_id:
		push_error("[GrowthBench] evolution failed: expected=%s actual=%s" % [next_id, applied])
		return
	_route_index += 1
	var tier := int(next_node.get("tier", 1))
	if tier >= 2 and float(_first_tier_times.get(str(tier), -1.0)) < 0.0:
		_first_tier_times[str(tier)] = _mode._bench_elapsed


func _accumulate_axis_wait(delta: float) -> void:
	if _route_index + 1 >= route_nodes.size():
		return
	var next_node := EvolutionSystem.node_of(StringName(route_nodes[_route_index + 1]))
	if _mode.survivor_player.level < EvolutionSystem.min_level_of(next_node):
		return
	for gap in EvolutionSystem.gates_missing(next_node, _mode.survivor_player.axis_points):
		var key := String(gap.get("key", ""))
		if _missing_axis_wait_s.has(key):
			_missing_axis_wait_s[key] = float(_missing_axis_wait_s[key]) + delta


func finish(terminal: String) -> String:
	if _finished:
		return "growth_result_already_written=true\n"
	_finished = true
	if EventLogger.kill_recorded.is_connected(_on_kill_recorded):
		EventLogger.kill_recorded.disconnect(_on_kill_recorded)
	var player: SurvivorPlayer = _mode.survivor_player
	var elapsed: float = _mode._bench_elapsed
	var combat_ratio: float = _combat_seconds / maxf(elapsed, 0.001)
	var survived: bool = not bool(_mode.is_game_over) \
		and not (_mode._squad_members_alive() as Array).is_empty()
	var reached_duration: bool = elapsed + 0.05 >= expected_duration_s
	var invalid_reasons: Array[String] = []
	if not survived:
		invalid_reasons.append("squad_destroyed")
	if not reached_duration:
		invalid_reasons.append("duration_short")
	if combat_ratio < VALID_COMBAT_RATIO:
		invalid_reasons.append("combat_ratio_below_0.80")
	var final_node: StringName = _mode.player_aircraft.get_meta("evo_node", route_nodes[_route_index]) \
		if is_instance_valid(_mode.player_aircraft) else StringName(route_nodes[_route_index])
	var final_tier := int(EvolutionSystem.node_of(final_node).get("tier", 1))
	var xp_progress := float(player.xp) / maxf(float(player.xp_to_next), 1.0) * 100.0
	var total_kills := _ace_kills + _wingman_kills
	var result: Dictionary = {
		"schema_version": 1,
		"run_id": run_id,
		"starter": starter_id,
		"squad_size": squad_size,
		"seed": seed_value,
		"route_axis": String(route_axis),
		"route": route_nodes.map(func(x): return String(x)),
		"terminal": terminal,
		"valid": invalid_reasons.is_empty(),
		"invalid_reasons": invalid_reasons,
		"elapsed_s": elapsed,
		"expected_duration_s": expected_duration_s,
		"combat_seconds": _combat_seconds,
		"combat_ratio": combat_ratio,
		"survived": survived,
		"final_level": player.level,
		"level_progress_pct": xp_progress,
		"total_xp": player.total_xp_gained,
		"kills_total": total_kills,
		"kills_per_min": float(total_kills) / maxf(elapsed / 60.0, 0.001),
		"ace_kills": _ace_kills,
		"wingman_kills": _wingman_kills,
		"final_node": String(final_node),
		"final_tier": final_tier,
		"first_tier_time_s": _first_tier_times,
		"axis_points": {
			"gladiator": player.get_axis_points(SurvivorData.AXIS_GLADIATOR),
			"knight": player.get_axis_points(SurvivorData.AXIS_KNIGHT),
			"schemer": player.get_axis_points(SurvivorData.AXIS_SCHEMER),
		},
		"missed_settlements": _missed_settlements,
		"missing_axis_counts": _missing_axis_counts,
		"missing_axis_wait_s": _missing_axis_wait_s,
		"normal_rules": {
			"debug_xp": false,
			"invulnerable": false,
			"forced_level": false,
			"forced_resources": false,
			"fixed_step_fps": 60,
		},
	}
	_write_result(result)
	return "growth_run_id=%s growth_valid=%s growth_json=%s combat_ratio=%.4f final_level=%d final_tier=%d total_xp=%d kills=%d\n" % [
		run_id, str(result["valid"]), _result_path(), combat_ratio, player.level,
		final_tier, player.total_xp_gained, total_kills]


func _write_result(result: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://bench/results"))
	var file := FileAccess.open(_result_path(), FileAccess.WRITE)
	if file == null:
		push_error("[GrowthBench] cannot write %s" % _result_path())
		return
	file.store_string(JSON.stringify(result, "\t"))
	file.store_string("\n")
	file.close()
	print("[GrowthBench] wrote %s" % ProjectSettings.globalize_path(_result_path()))


func _result_path() -> String:
	return "res://bench/results/evolution_growth_%s.json" % run_id


func _on_kill_recorded(killer: String, _victim: String, _weapon_kind: String,
		killer_team: int, victim_team: int, _victim_voiced: bool) -> void:
	if killer_team != CombatUnit.TEAM_PLAYER or victim_team != CombatUnit.TEAM_HOSTILE:
		return
	if killer == "Ultra":
		_ace_kills += 1
	else:
		_wingman_kills += 1
