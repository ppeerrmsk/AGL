class_name EncounterDifficultyProbe
extends Node

## Encounter Director A/B 难度探针。
##
## 仅在 --bench=encounter_difficulty 中实例化，以 4Hz 读取 SurvivorMode 已维护的
## CombatUnit.all_units，不进入正式局，也不给 Aircraft 增加子节点/逐机 tick。

const SAMPLE_INTERVAL_S := 0.25

var _mode: Node = null
var _sample_timer := 0.0
var _elapsed := 0.0
var _samples := 0
var _enemy_alive_sum := 0.0
var _active_pressure_sum := 0.0
var _formation_wingmen_sum := 0.0
var _formation_retained_sum := 0.0
var _slot_error_sum := 0.0
var _slot_error_samples := 0
var _max_enemy_alive := 0
var _max_active_pressure := 0
var _max_slot_error_px := 0.0
var _first_contact_s := -1.0
var _unique_hostiles: Dictionary = {}
var _active_samples: Array[int] = []


func setup(mode: Node) -> void:
	_mode = mode
	process_physics_priority = 90
	set_physics_process(true)


func _physics_process(delta: float) -> void:
	_elapsed += delta
	_sample_timer -= delta
	if _sample_timer > 0.0:
		return
	_sample_timer += SAMPLE_INTERVAL_S
	_sample()


func _sample() -> void:
	if _mode == null or not is_instance_valid(_mode):
		return
	var enemy_alive := 0
	var active_pressure := 0
	var formation_wingmen := 0
	var formation_retained := 0
	for unit_value: Variant in CombatUnit.all_units:
		if typeof(unit_value) != TYPE_OBJECT or not is_instance_valid(unit_value) \
				or not (unit_value is Aircraft):
			continue
		var ac := unit_value as Aircraft
		if ac.is_destroyed or ac.team != CombatUnit.TEAM_HOSTILE:
			continue
		enemy_alive += 1
		_unique_hostiles[ac.get_instance_id()] = true
		var ai := _get_ai(ac)
		if _is_active_against_player(ac, ai):
			active_pressure += 1
		if ai == null or ai.squad == null or ai.squad.leader == ac or ai.squad_index <= 0:
			continue
		formation_wingmen += 1
		if ac.formation_mode:
			formation_retained += 1
		var slot := ai.squad.get_wingman_target(ai.squad_index)
		if slot != Vector2.INF:
			var error_px := ac.global_position.distance_to(slot)
			_slot_error_sum += error_px
			_slot_error_samples += 1
			_max_slot_error_px = maxf(_max_slot_error_px, error_px)

	_samples += 1
	_enemy_alive_sum += enemy_alive
	_active_pressure_sum += active_pressure
	_formation_wingmen_sum += formation_wingmen
	_formation_retained_sum += formation_retained
	_max_enemy_alive = maxi(_max_enemy_alive, enemy_alive)
	_max_active_pressure = maxi(_max_active_pressure, active_pressure)
	_active_samples.append(active_pressure)
	if active_pressure > 0 and _first_contact_s < 0.0:
		_first_contact_s = _elapsed


func finish() -> String:
	set_physics_process(false)
	var divisor := maxf(float(_samples), 1.0)
	var wingman_divisor := maxf(_formation_wingmen_sum, 1.0)
	var sorted_active := _active_samples.duplicate()
	sorted_active.sort()
	var p90_active := 0
	if not sorted_active.is_empty():
		var p90_index := mini(
			int(floor(float(sorted_active.size() - 1) * 0.90)), sorted_active.size() - 1)
		p90_active = sorted_active[p90_index]
	var stats := EventLogger.format_stats_summary()
	var summary := "encounter_difficulty seed=42 player_squad=%d response=%d token_budget=%d\n" % [
		_mode._squad_members_alive().size() if _mode.has_method("_squad_members_alive") else 1,
		_mode._spawner.get_response_level() if _mode._spawner else -1,
		_mode._spawner._get_token_budget() if _mode._spawner else -1,
	]
	summary += "difficulty unique_hostiles=%d avg_alive=%.2f max_alive=%d avg_active=%.2f p90_active=%d max_active=%d first_contact_s=%.2f kills=%d\n" % [
		_unique_hostiles.size(), _enemy_alive_sum / divisor, _max_enemy_alive,
		_active_pressure_sum / divisor, p90_active, _max_active_pressure,
		_first_contact_s, _mode._spawner.kill_count if _mode._spawner else 0,
	]
	summary += "cohesion retained_pct=%.2f avg_slot_error_px=%.2f max_slot_error_px=%.2f sampled_wingmen=%.0f\n" % [
		100.0 * _formation_retained_sum / wingman_divisor,
		_slot_error_sum / maxf(float(_slot_error_samples), 1.0),
		_max_slot_error_px, _formation_wingmen_sum,
	]
	if not stats.is_empty():
		summary += stats + "\n"
	return summary


func _is_active_against_player(ac: Aircraft, ai: AIController) -> bool:
	var target_value: Variant = ac.combat_target
	if typeof(target_value) == TYPE_OBJECT and target_value != null \
			and is_instance_valid(target_value) and target_value is CombatUnit \
			and (target_value as CombatUnit).team == CombatUnit.TEAM_PLAYER:
		return true
	if ac.formation_mode and ai != null and ai.squad != null:
		var leader_value: Variant = ai.squad.leader
		if typeof(leader_value) == TYPE_OBJECT and leader_value != null \
				and is_instance_valid(leader_value) and leader_value is Aircraft:
			var leader := leader_value as Aircraft
			var leader_target: Variant = leader.combat_target
			if typeof(leader_target) == TYPE_OBJECT and leader_target != null \
					and is_instance_valid(leader_target) and leader_target is CombatUnit \
					and (leader_target as CombatUnit).team == CombatUnit.TEAM_PLAYER:
				return true
	return false


func _get_ai(ac: Aircraft) -> AIController:
	for child in ac.get_children():
		if child is AIController:
			return child as AIController
	return null
