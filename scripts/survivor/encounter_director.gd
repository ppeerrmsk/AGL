class_name EncounterDirector
extends RefCounted

## 生存模式 Encounter 的集中式 2Hz 压力账本。
##
## - 不实例化/释放单位；Spawner 仍负责具体出生与退场。
## - Token/实例上限仍是 Spawn Budget 硬门，Director 只补“玩家当前承压”这一维。
## - CombatUnit.all_units 由 SurvivorMode 维护；本类不扫场景树、不挂逐机节点。

enum PressureState { DORMANT, APPROACHING, ACTIVE_PLAYER, ACTIVE_ALLY_ONLY, DISENGAGING, RETREATING }

const DIRECTOR_TICK_S := 0.5
const TELEMETRY_INTERVAL_S := 5.0
const RECOVERY_DEFAULT_S := 10.0
const GLOBAL_PACKAGE_COOLDOWN_MIN_S := 10.0
const GLOBAL_PACKAGE_COOLDOWN_MAX_S := 18.0
const SPAWN_DEFICIT_THRESHOLD := 1.5
const SPIKE_MULT := 1.30
const DISENGAGE_GRACE_S := 4.0
const PLAYER_TARGET_PROTECTION_S := 8.0
const LETHAL_OWNER_COOLDOWN_S := 3.0
const LETHAL_LEASE_S := 0.75

static var _active: EncounterDirector = null

var _spawner: Node = null
var _mode: Node = null
var _tick_timer := 0.0
var _telemetry_timer := 0.0
var _recovery_remaining := 0.0
var _global_cooldown_remaining := 0.0
var _package_serial := 0
var _pressure_total := 0.0
var _pressure_target := 3.0
var _presence_hostile := 0
var _presence_all_aircraft := 0
var _active_player_units := 0
var _previous_presence_hostile := 0
var _state_by_unit: Dictionary = {}
var _disengage_until: Dictionary = {}
var _lethal_leases: Dictionary = {}
var _lethal_cooldowns: Dictionary = {}
var _last_denial := ""


func _init(spawner: Node) -> void:
	_spawner = spawner
	_mode = spawner.mode if spawner else null
	_active = self


func shutdown() -> void:
	if _active == self:
		_active = null
	_spawner = null
	_mode = null
	_state_by_unit.clear()
	_disengage_until.clear()
	_lethal_leases.clear()
	_lethal_cooldowns.clear()


func tick(delta: float) -> void:
	_recovery_remaining = maxf(_recovery_remaining - delta, 0.0)
	_global_cooldown_remaining = maxf(_global_cooldown_remaining - delta, 0.0)
	_tick_timer -= delta
	_telemetry_timer -= delta
	if _tick_timer > 0.0:
		return
	_tick_timer += DIRECTOR_TICK_S
	_recompute()
	if _telemetry_timer <= 0.0:
		_telemetry_timer += TELEMETRY_INTERVAL_S
		EventLogger.log_event("DIRECTOR", "Snapshot",
			"pr=%.2f/%.2f active=%d hostile=%d all_air=%d recovery=%.1f cd=%.1f deny=%s" % [
				_pressure_total, _pressure_target, _active_player_units, _presence_hostile,
				_presence_all_aircraft, _recovery_remaining, _global_cooldown_remaining,
				_last_denial if not _last_denial.is_empty() else "none"])


func global_admission(package_pressure: float, package_presence: int) -> Dictionary:
	if _mode == null or not is_instance_valid(_mode) or _spawner == null:
		return _deny("no_context")
	if _mode.has_method("is_boss_phase") and bool(_mode.is_boss_phase()):
		return _deny("boss")
	if _mode.has_method("is_ace_encounter_active") and bool(_mode.is_ace_encounter_active()):
		return _deny("ace_reserved")
	if _spawner.zone_mission != null and _spawner.zone_mission.is_player_in_active_mission():
		return _deny("mission_reserved")
	if _recovery_remaining > 0.0:
		return _deny("recovery")
	if _global_cooldown_remaining > 0.0:
		return _deny("package_cooldown")
	if _presence_hostile + package_presence > SurvivorData.MAX_ENEMIES_DEFAULT:
		return _deny("presence_soft_cap")
	var deficit := _pressure_target - _pressure_total
	if deficit < SPAWN_DEFICIT_THRESHOLD:
		return _deny("pressure_full")
	# Package 不拆半包；候选定案前可按 headroom 解析为较小的完整 Element。
	if package_pressure > global_pressure_headroom():
		return _deny("package_too_heavy")
	_last_denial = ""
	return {"admitted": true, "deficit": deficit, "target": _pressure_target}


func global_pressure_headroom() -> float:
	return pressure_headroom(_pressure_total, _pressure_target)


static func pressure_headroom(current_pressure: float, target_pressure: float) -> float:
	# 1.5 PR 是“是否可刷”的缺口门，不是整包越线幅度；完整包只受 1.30× Spike Cap。
	return maxf(0.0, target_pressure * SPIKE_MULT - current_pressure)


static func should_begin_global_recovery(previous_presence: int, current_presence: int) -> bool:
	return previous_presence > 0 and current_presence == 0


func commit_global_package(package_id: StringName) -> void:
	_global_cooldown_remaining = randf_range(
		GLOBAL_PACKAGE_COOLDOWN_MIN_S, GLOBAL_PACKAGE_COOLDOWN_MAX_S)
	_last_denial = ""
	EventLogger.log_event("DIRECTOR", "PackageCommit",
		"id=%s pr=%.2f/%.2f cooldown=%.1f" % [
			String(package_id), _pressure_total, _pressure_target, _global_cooldown_remaining])


func consume_denied_opportunity(reason: String = "") -> void:
	# 禁止 Spawn Debt：生成时机失败后仍消耗短机会，不在下一帧集中补刷。
	_global_cooldown_remaining = maxf(_global_cooldown_remaining, randf_range(
		GLOBAL_PACKAGE_COOLDOWN_MIN_S, GLOBAL_PACKAGE_COOLDOWN_MAX_S))
	if not reason.is_empty():
		_last_denial = reason


func next_package_id(theme: String) -> StringName:
	_package_serial += 1
	return StringName("global_%04d_%s" % [_package_serial, theme])


func begin_recovery(seconds: float = RECOVERY_DEFAULT_S) -> void:
	_recovery_remaining = maxf(_recovery_remaining, clampf(seconds, 8.0, 12.0))


func pressure_snapshot() -> Dictionary:
	return {
		"current": _pressure_total,
		"target": _pressure_target,
		"hostile_aircraft": _presence_hostile,
		"all_aircraft": _presence_all_aircraft,
		"active_player_units": _active_player_units,
		"recovery_s": _recovery_remaining,
		"global_cooldown_s": _global_cooldown_remaining,
		"last_denial": _last_denial,
	}


static func pressure_cost_from_token(token_cost: int, support_body: bool = false,
		commander: bool = false) -> float:
	if commander:
		return 2.25
	if support_body:
		return 1.5
	return clampf(0.75 + 0.25 * float(maxi(token_cost, 1)), 1.0, 3.0)


static func pressure_target_for(player_squad_size: int, heat: float,
		encounter_mult: float = 1.0) -> float:
	# 临时友军不进入玩家直属 N；平均攻击者的微调由开局完整 Element 承担。
	var base_pr := 4.0 + 0.75 * float(maxi(player_squad_size, 1) - 1)
	var heat_mult := 0.80 + 0.006 * clampf(heat, 0.0, 100.0)
	return clampf(base_pr * heat_mult * encounter_mult, 3.0, 12.0)


static func lethal_capacity_for(player_squad_size: int, heat: float) -> float:
	var heat_bonus := 0.0
	if heat >= 80.0:
		heat_bonus = 1.5
	elif heat >= 60.0:
		heat_bonus = 1.0
	elif heat >= 30.0:
		heat_bonus = 0.5
	return clampf(2.5 + 0.35 * float(maxi(player_squad_size, 1) - 1) + heat_bonus, 2.5, 6.5)


static func resolve_flight_elements(player_squad_size: int, heat: float,
		flight_size: int, split_roll: float) -> Array[int]:
	if flight_size == 4 and player_squad_size >= 4 and heat >= 60.0 \
			and split_roll < 0.60:
		return [2, 2]
	return [clampi(flight_size, 1, 4)]


static func opening_garrison_size_for(player_squad_size: int, rolled_size: int) -> int:
	# 多机玩家稳定多一名早期攻击者；保留单机/双机局的既有 2～3 机抽样。
	if player_squad_size >= 4:
		return 3
	return clampi(rolled_size, 2, 3)


static func request_lethal_attack(attacker: Aircraft, target: CombatUnit,
		cost: float = 1.0) -> bool:
	if _active == null:
		return true
	return _active._request_lethal_attack(attacker, target, cost)


func _request_lethal_attack(attacker: Aircraft, target: CombatUnit, cost: float) -> bool:
	if attacker == null or target == null or attacker.team != CombatUnit.TEAM_HOSTILE \
			or target.team != CombatUnit.TEAM_PLAYER:
		return true
	var ai: AIController = attacker._get_ai_controller()
	if str(attacker.get_meta("category", "")) == "boss" or (ai != null and ai.is_boss_attacker()):
		return true
	var now: float = float(_mode.game_time) if _mode != null and "game_time" in _mode else 0.0
	_cleanup_lethal(now)
	var owner_id: int = attacker.get_instance_id()
	# 同一次 0.75s 攻击承诺内允许多弹齐射继续离架；只在新 Run 开始时重新竞争容量。
	if _lethal_leases.has(owner_id):
		return true
	if now < float(_lethal_cooldowns.get(owner_id, 0.0)):
		return false
	var used: float = 0.0
	for lease_value: Variant in _lethal_leases.values():
		if typeof(lease_value) == TYPE_DICTIONARY:
			used += float((lease_value as Dictionary).get("cost", 0.0))
	var heat: float = float(_spawner._roe.heat) if _spawner != null and _spawner._roe != null else 0.0
	var player_n: int = int(_spawner.player_squad_size()) if _spawner != null else 1
	if used + cost > lethal_capacity_for(player_n, heat) + 0.001:
		return false
	_lethal_leases[owner_id] = {"until": now + LETHAL_LEASE_S, "cost": cost}
	_lethal_cooldowns[owner_id] = now + LETHAL_OWNER_COOLDOWN_S
	return true


func _cleanup_lethal(now: float) -> void:
	for key in _lethal_leases.keys():
		if now >= float((_lethal_leases[key] as Dictionary).get("until", 0.0)):
			_lethal_leases.erase(key)
	for key in _lethal_cooldowns.keys():
		if now >= float(_lethal_cooldowns[key]):
			_lethal_cooldowns.erase(key)


func _recompute() -> void:
	var now: float = float(_mode.game_time) if _mode != null and "game_time" in _mode else 0.0
	var heat: float = float(_spawner._roe.heat) if _spawner != null and _spawner._roe != null else 0.0
	_pressure_target = pressure_target_for(_spawner.player_squad_size() if _spawner else 1, heat)
	_pressure_total = 0.0
	_presence_hostile = 0
	_presence_all_aircraft = 0
	_active_player_units = 0
	var live_ids: Dictionary = {}
	for unit_value: Variant in CombatUnit.all_units:
		if typeof(unit_value) != TYPE_OBJECT or not is_instance_valid(unit_value) \
				or not (unit_value is Aircraft):
			continue
		var ac := unit_value as Aircraft
		if ac.is_destroyed:
			continue
		_presence_all_aircraft += 1
		if ac.team != CombatUnit.TEAM_HOSTILE:
			continue
		_presence_hostile += 1
		var uid := ac.get_instance_id()
		live_ids[uid] = true
		var state := _derive_state(ac, now)
		_state_by_unit[uid] = state
		var mult := _pressure_multiplier(state)
		if state == PressureState.ACTIVE_PLAYER:
			_active_player_units += 1
		var row := EnemyPoolRegistry.row_for_type(int(ac.get_meta("enemy_type_idx", -1)))
		var support_body := bool(row.get("support_body", false))
		var commander := int(ac.get_meta("enemy_type_idx", -1)) == 4
		_pressure_total += pressure_cost_from_token(
			int(ac.get_meta("token_cost", row.get("token_cost", 1))), support_body, commander) * mult
	for uid in _state_by_unit.keys():
		if not live_ids.has(uid):
			_state_by_unit.erase(uid)
			_disengage_until.erase(uid)
	_cleanup_lethal(now)
	# 只有完整清空 Global 敌对 Presence 才创建恢复窗；暂时失锁/改打友军不是战斗终态。
	if should_begin_global_recovery(_previous_presence_hostile, _presence_hostile):
		begin_recovery()
	_previous_presence_hostile = _presence_hostile


func _derive_state(ac: Aircraft, now: float) -> int:
	var phase := str(ac.get_meta("reinf_phase", ""))
	if phase == "egress" or bool(ac.get_meta("encounter_retreating", false)):
		return PressureState.RETREATING
	var ai := ac._get_ai_controller()
	var target_value: Variant = ac.combat_target
	var active_player := _targets_team(target_value, CombatUnit.TEAM_PLAYER)
	var active_ally := _targets_team(target_value, CombatUnit.TEAM_ALLY)
	if not active_player and ac.formation_mode and ai != null and ai.squad != null:
		var leader_value: Variant = ai.squad.leader
		if typeof(leader_value) == TYPE_OBJECT and leader_value != null \
				and is_instance_valid(leader_value) and leader_value is Aircraft:
			active_player = _targets_team((leader_value as Aircraft).combat_target, CombatUnit.TEAM_PLAYER)
			active_ally = _targets_team((leader_value as Aircraft).combat_target, CombatUnit.TEAM_ALLY)
	var uid := ac.get_instance_id()
	if active_player:
		_disengage_until[uid] = now + DISENGAGE_GRACE_S
		return PressureState.ACTIVE_PLAYER
	if active_ally:
		return PressureState.ACTIVE_ALLY_ONLY
	if now < float(_disengage_until.get(uid, 0.0)):
		return PressureState.DISENGAGING
	if phase == "transit" or bool(ac.get_meta("encounter_approaching", false)):
		return PressureState.APPROACHING
	return PressureState.DORMANT


func _targets_team(target_value: Variant, team: int) -> bool:
	return typeof(target_value) == TYPE_OBJECT and target_value != null \
		and is_instance_valid(target_value) and target_value is CombatUnit \
		and (target_value as CombatUnit).team == team


func _pressure_multiplier(state: int) -> float:
	match state:
		PressureState.APPROACHING:
			return 0.5
		PressureState.ACTIVE_PLAYER:
			return 1.0
		PressureState.ACTIVE_ALLY_ONLY:
			return 0.25
		PressureState.DISENGAGING:
			return 0.5
		_:
			return 0.0


func _deny(reason: String) -> Dictionary:
	_last_denial = reason
	return {"admitted": false, "reason": reason, "target": _pressure_target,
		"current": _pressure_total}
