class_name SchemerMultilock
extends RefCounted

## 常规航电 Schemer 的共享低频火控。注册单位只在生成/死亡边沿变化；无全场扫描、无逐机 Node。

const LOGIC_TICK_S: float = 0.20
const FIRE_GAP_S: float = 0.15
const EGRESS_S: float = 10.0

var _spawner
var _units: Array[Dictionary] = [] ## {ac, mode}
var _logic_accum: float = 0.0
var _queues: Dictionary = {}       ## Aircraft → Array[CombatUnit]
var _fire_timers: Dictionary = {}
var _egress_until: Dictionary = {} ## iid → game_time


func _init(spawner) -> void:
	_spawner = spawner


func register(ac: Aircraft, mode: String) -> void:
	_units.append({"ac": ac, "mode": mode})


func has_units() -> bool:
	return not _units.is_empty()


func shutdown() -> void:
	_units.clear()
	_queues.clear()
	_fire_timers.clear()
	_egress_until.clear()
	_spawner = null


func tick(delta: float) -> void:
	_update_queues(delta)
	_logic_accum += delta
	if _logic_accum < LOGIC_TICK_S:
		return
	_logic_accum = 0.0
	_prune_and_restore()
	if _units.is_empty():
		return
	var targets: Array = _spawner.mode._squad_members_alive()
	if targets.is_empty():
		return
	var groups: Dictionary = {}
	for entry in _units:
		var ac: Aircraft = entry["ac"]
		if _is_egressing(ac) or _queues.has(ac):
			continue
		var ai = _spawner._get_ai(ac)
		var key: int = ai.squad.get_instance_id() if ai and ai.squad else ac.get_instance_id()
		if not groups.has(key):
			groups[key] = []
		(groups[key] as Array).append(entry)
	for key in groups:
		var entries: Array = groups[key]
		var mode := str(entries[0]["mode"])
		if mode == "team3":
			_plan_team_three(entries, targets)
		else:
			for entry in entries:
				_plan_per_aircraft(entry["ac"], targets, 2)


func _plan_team_three(entries: Array, targets: Array) -> void:
	var assigned: Dictionary = {}
	var shots := 0
	for entry in entries:
		if shots >= 3:
			break
		var ac: Aircraft = entry["ac"]
		for target in targets:
			if assigned.has(target) or not _ready_for(ac, target):
				continue
			assigned[target] = true
			_start_queue(ac, [target])
			shots += 1
			break


func _plan_per_aircraft(ac: Aircraft, targets: Array, limit: int) -> void:
	var queue: Array = []
	for target in targets:
		if _ready_for(ac, target):
			queue.append(target)
			if queue.size() >= limit:
				break
	if not queue.is_empty():
		_start_queue(ac, queue)


func _ready_for(ac: Aircraft, target: CombatUnit) -> bool:
	return is_instance_valid(ac) and not ac.is_destroyed and is_instance_valid(target) \
			and not target.is_destroyed and not ac.is_sensor_engagement_obscured(target) \
			and ac.params != null and ac.params.missile != null and ac.missiles_remaining > 0 \
			and ac._missile_cooldown <= 0.0 and ac.radar_targets.has(target) \
			and float(ac.radar_targets[target]) >= ac.params.lock_time \
			and ac.is_in_radar_cone(target.global_position)


func _start_queue(ac: Aircraft, targets: Array) -> void:
	_queues[ac] = targets
	_fire_timers[ac] = 0.0


func _update_queues(delta: float) -> void:
	for ac_v in _queues.keys():
		if not is_instance_valid(ac_v) or (ac_v as Aircraft).is_destroyed:
			_queues.erase(ac_v)
			_fire_timers.erase(ac_v)
			continue
		var ac: Aircraft = ac_v
		var queue: Array = _queues[ac]
		var timer := float(_fire_timers.get(ac, 0.0)) - delta
		if timer <= 0.0 and not queue.is_empty():
			var target: CombatUnit = queue.pop_front()
			if is_instance_valid(target) and not target.is_destroyed \
					and not ac.is_sensor_engagement_obscured(target) \
					and ac.params and ac.params.missile and ac.missiles_remaining > 0:
				AircraftWeapons._fire_missile_at(ac, target, ac.params.missile)
			timer = FIRE_GAP_S
		_fire_timers[ac] = timer
		_queues[ac] = queue
		if queue.is_empty():
			_queues.erase(ac)
			_fire_timers.erase(ac)
			_enter_egress(ac)


func _enter_egress(ac: Aircraft) -> void:
	var now: float = _spawner.mode.game_time if _spawner and _spawner.mode else 0.0
	_egress_until[ac.get_instance_id()] = now + EGRESS_S
	ac.radar_targets.clear()
	ac.is_afterburner = true
	ac.ai_override_pursuit = true
	var ai = _spawner._get_ai(ac)
	if ai:
		ai.bvr_only = true
		ai.bvr_standoff_min_px_override = 3200.0
		ai.bvr_flee_distance_px_override = 4400.0


func _is_egressing(ac: Aircraft) -> bool:
	var now: float = _spawner.mode.game_time if _spawner and _spawner.mode else 0.0
	return now < float(_egress_until.get(ac.get_instance_id(), 0.0))


func _prune_and_restore() -> void:
	var now: float = _spawner.mode.game_time if _spawner and _spawner.mode else 0.0
	for i in range(_units.size() - 1, -1, -1):
		var ac: Aircraft = _units[i]["ac"]
		if not is_instance_valid(ac) or ac.is_destroyed:
			_units.remove_at(i)
			continue
		var iid := ac.get_instance_id()
		if _egress_until.has(iid) and now >= float(_egress_until[iid]):
			_egress_until.erase(iid)
			ac.is_afterburner = false
			ac.ai_override_pursuit = false
