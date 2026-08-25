class_name SensorStealthController
extends RefCounted

## 敌机传感器隐形的单一低频控制器。
## observe() 骑现有雷达配对；finish_radar_tick() 只做一次 O(N) 收束。

const LOST_CONTACT_GRACE_S: float = 5.0
const CONTACT_FADE_S: float = Aircraft.SENSOR_CONTACT_FADE_S
const COUNTER_STEALTH_RANGE_MULT: float = 1.20
const PROXIMITY_REVEAL_PX: float = 1000.0  ## 2000m：近距目视强制揭露，不受 JAM/武器能力影响

var _observed_ids: Dictionary = {}
var _counter_observed_ttl: Dictionary = {}


func begin_radar_tick() -> void:
	_observed_ids.clear()


func observe(shooter: CombatUnit, target: CombatUnit, in_cone: bool) -> void:
	if shooter == null or target == null:
		return
	if not is_instance_valid(shooter) or not is_instance_valid(target):
		return
	if not (shooter is Aircraft) or not (target is Aircraft):
		return
	var observer := shooter as Aircraft
	var stealth := target as Aircraft
	if stealth.has_meta(CombatUnit.META_PRESENTATION_ACTOR_ACTIVE):
		return
	if observer.is_sensor_shroud_obscured(stealth):
		return
	if not observer.is_player_squad() or observer.status_jam_active:
		return
	if observer.params == null or not observer.params.has_lock_capable_weapon():
		return
	if stealth.params == null or not stealth.params.sensor_stealth_enabled:
		return
	if stealth.team != CombatUnit.TEAM_HOSTILE or not observer.is_hostile_to(stealth):
		return
	if not in_cone and not _counter_stealth_extended_contact(observer, stealth):
		return
	_observed_ids[stealth.get_instance_id()] = true
	if _has_skill(observer, SkillHooks.SKILL_COUNTER_STEALTH):
		_counter_observed_ttl[stealth.get_instance_id()] = 1.0
	stealth.sensor_contact_lost_s = 0.0
	stealth.set_sensor_contact_hidden(false, CONTACT_FADE_S)


func finish_radar_tick(step_delta: float, all_units: Array[CombatUnit]) -> void:
	for target_id in _counter_observed_ttl.keys():
		var remaining: float = float(_counter_observed_ttl[target_id]) - step_delta
		if remaining > 0.0:
			_counter_observed_ttl[target_id] = remaining
		else:
			_counter_observed_ttl.erase(target_id)
	var newly_hidden_targets: Array[Aircraft] = []
	var player_observers: Array[Aircraft] = []
	for raw in all_units:
		if is_instance_valid(raw) and raw is Aircraft:
			var observer := raw as Aircraft
			if not observer.is_destroyed and observer.is_player_squad():
				player_observers.append(observer)
	for raw in all_units:
		if not is_instance_valid(raw) or not (raw is Aircraft):
			continue
		var stealth := raw as Aircraft
		if stealth.is_destroyed or stealth.team != CombatUnit.TEAM_HOSTILE \
				or stealth.params == null or not stealth.params.sensor_stealth_enabled:
			continue
		# 导演拥有的是虚拟演员：冻结真实战斗失联时钟，也不触发目标释放。
		if stealth.has_meta(CombatUnit.META_PRESENTATION_ACTOR_ACTIVE):
			continue
		var counter_revealed: bool = _counter_observed_ttl.has(stealth.get_instance_id()) \
			or _revealed_by_counter_stealth(stealth, player_observers) \
			or _held_by_ghost_buster(stealth, player_observers)
		stealth.set_counter_stealth_revealed(counter_revealed)
		if _observed_ids.has(stealth.get_instance_id()) \
				or _has_close_player_contact(stealth, player_observers) \
				or counter_revealed:
			stealth.sensor_contact_lost_s = 0.0
			stealth.set_sensor_contact_hidden(false, CONTACT_FADE_S)
			continue
		stealth.sensor_contact_lost_s = minf(
			stealth.sensor_contact_lost_s + step_delta, LOST_CONTACT_GRACE_S)
		if stealth.sensor_contact_lost_s < LOST_CONTACT_GRACE_S:
			continue
		var newly_hidden := not stealth.is_hidden_from_player_sensors()
		stealth.set_sensor_contact_hidden(true, CONTACT_FADE_S)
		if newly_hidden:
			newly_hidden_targets.append(stealth)
	if not newly_hidden_targets.is_empty():
		release_player_sensor_refs_batch(newly_hidden_targets, all_units, true)


static func _has_close_player_contact(target: Aircraft,
		player_observers: Array[Aircraft]) -> bool:
	var reveal_dist_sq := PROXIMITY_REVEAL_PX * PROXIMITY_REVEAL_PX
	for observer in player_observers:
		if is_instance_valid(observer) \
				and observer.global_position.distance_squared_to(target.global_position) <= reveal_dist_sq:
			return true
	return false


static func _counter_stealth_extended_contact(observer: Aircraft,
		target: Aircraft) -> bool:
	if not _has_skill(observer, SkillHooks.SKILL_COUNTER_STEALTH) \
			or observer.params == null:
		return false
	var to_target: Vector2 = target.global_position - observer.global_position
	var range_mult: float = COUNTER_STEALTH_RANGE_MULT * target.ecm_range_mult
	if to_target.length() > observer.effective_radar_range_px() * range_mult \
			or to_target.length_squared() < 1.0:
		return false
	var bearing: float = atan2(to_target.x, -to_target.y)
	return absf(angle_difference(observer.heading, bearing)) \
		<= deg_to_rad(observer.params.radar_half_angle)


static func _revealed_by_counter_stealth(target: Aircraft,
		player_observers: Array[Aircraft]) -> bool:
	var lock_threshold: float = target.params.lock_time if target.params else 3.0
	for observer in player_observers:
		if is_instance_valid(observer) \
				and _has_skill(observer, SkillHooks.SKILL_COUNTER_STEALTH) \
				and float(target.radar_targets.get(observer, 0.0)) >= lock_threshold:
			return true
	return false


static func _held_by_ghost_buster(target: Aircraft,
		player_observers: Array[Aircraft]) -> bool:
	for observer in player_observers:
		if is_instance_valid(observer) \
				and _has_skill(observer, SkillHooks.SKILL_GHOST_BUSTER) \
				and observer.combat_target == target:
			return true
	return false


static func _has_skill(ac: Aircraft, skill_id: String) -> bool:
	if ac == null or not ac.has_meta("upgrade_stacks"):
		return false
	var stacks: Dictionary = ac.get_meta("upgrade_stacks")
	return int(stacks.get(skill_id, 0)) > 0


## 隐形沿统一释放玩家侧作战引用。传感器硬失联清点名；Wraith 光学短窗只挂起点名。
static func release_player_sensor_refs(target: Aircraft, all_units: Array[CombatUnit],
		clear_commanded: bool = true) -> void:
	var targets: Array[Aircraft] = [target]
	release_player_sensor_refs_batch(targets, all_units, clear_commanded)


## 同一隐形沿先收集全部目标，再只扫描一次玩家观察者，避免 S 个目标造成 S×N 全场清理。
static func release_player_sensor_refs_batch(targets: Array[Aircraft],
		all_units: Array[CombatUnit], clear_commanded: bool = true,
		reason: String = "sensor contact lost") -> void:
	var target_ids: Dictionary = {}
	for target in targets:
		if target != null and is_instance_valid(target):
			target_ids[target.get_instance_id()] = true
	if target_ids.is_empty():
		return
	for raw in all_units:
		if not is_instance_valid(raw) or not (raw is Aircraft):
			continue
		var observer := raw as Aircraft
		if observer.is_destroyed or not observer.is_player_squad():
			continue
		for target in targets:
			if target != null and is_instance_valid(target):
				observer.radar_targets.erase(target)
				observer.secondary_radar_targets.erase(target)
		var held_target := _target_is_in_batch(observer.combat_target, target_ids)
		var commanded := _target_is_in_batch(observer.commanded_target, target_ids)
		var ai := observer._ai_ref
		if ai != null and is_instance_valid(ai) \
				and _target_is_in_batch(ai._current_target, target_ids):
			ai.release_target(AIController.TargetSource.TS_COMMANDED,
				reason)
		elif held_target:
			observer.clear_combat_target()
		if commanded and clear_commanded:
			observer.commanded_target = null
			observer.attack_posture = Situation.POSTURE_AUTO
			observer.surround_bearing_rad = INF
		if held_target or commanded:
			observer.target_position = Vector2.INF


static func _target_is_in_batch(value: CombatUnit, target_ids: Dictionary) -> bool:
	return value != null and is_instance_valid(value) \
		and target_ids.has(value.get_instance_id())
