class_name F22Multilock
extends RefCounted

## F-22 队级四锁控制器。由 SurvivorSpawner 驱动：常态 5Hz 决策，只有 0.15s 齐射队列活跃时逐帧推进计时。
## 不创建 Node、不挂逐机 process，不重复全场雷达扫描；锁定进度复用生存模式既有 5Hz radar_targets。

const LOGIC_INTERVAL: float = 0.20
const FIRE_INTERVAL: float = 0.15
const EGRESS_SECONDS: float = 12.0
const PRESS_ABORT_RANGE_PX: float = 1500.0 ## 3000m × 0.5px/m
const STANDOFF_MIN_PX: float = 5000.0
const FLEE_DISTANCE_PX: float = 6000.0
const MAX_LOCKS_PER_AIRCRAFT: int = 4

var spawner
var _logic_accum: float = 0.0
var _group_states: Dictionary = {} ## squad iid → {phase, until, queues, timers, members}
var _units: Array[Aircraft] = []    ## 生成边沿登记；避免 5Hz 全场 get_children 扫描


func _init(p_spawner) -> void:
	spawner = p_spawner


func register(aircraft: Aircraft) -> void:
	if is_instance_valid(aircraft) and aircraft not in _units:
		_units.append(aircraft)


func shutdown() -> void:
	_units.clear()
	_group_states.clear()
	spawner = null


## 纯函数：eligibility[member][target]，返回每架飞机分到的目标索引；目标全局唯一、每机≤4。
static func allocate_unique_targets(eligibility: Array, target_count: int) -> Array:
	var result: Array = []
	for _member in eligibility:
		result.append([])
	for target_idx in range(target_count):
		var best_member: int = -1
		var best_load: int = MAX_LOCKS_PER_AIRCRAFT + 1
		for member_idx in range(eligibility.size()):
			var row: Array = eligibility[member_idx]
			if target_idx >= row.size() or not bool(row[target_idx]):
				continue
			var load_now: int = (result[member_idx] as Array).size()
			if load_now < MAX_LOCKS_PER_AIRCRAFT and load_now < best_load:
				best_load = load_now
				best_member = member_idx
		if best_member >= 0:
			(result[best_member] as Array).append(target_idx)
	return result


func tick(delta: float) -> void:
	_update_execution(delta)
	_logic_accum += delta
	if _logic_accum < LOGIC_INTERVAL:
		return
	_logic_accum = 0.0
	_logic_step()


func _update_execution(delta: float) -> void:
	for group_key in _group_states.keys():
		var state: Dictionary = _group_states[group_key]
		if str(state.get("phase", "setup")) != "execute":
			continue
		var queues: Dictionary = state["queues"]
		var timers: Dictionary = state["timers"]
		var any_pending := false
		for aircraft_v in queues.keys():
			if not is_instance_valid(aircraft_v) or (aircraft_v as Aircraft).is_destroyed:
				queues.erase(aircraft_v)
				timers.erase(aircraft_v)
				continue
			var aircraft: Aircraft = aircraft_v
			var queue: Array = queues[aircraft]
			var timer: float = float(timers.get(aircraft, 0.0)) - delta
			if not queue.is_empty() and timer <= 0.0:
				var target: CombatUnit = queue.pop_front()
				if is_instance_valid(target) and not target.is_destroyed \
						and not aircraft.is_sensor_engagement_obscured(target) \
						and aircraft.params and aircraft.params.missile \
						and aircraft.missiles_remaining > 0:
					AircraftWeapons._fire_missile_at(aircraft, target, aircraft.params.missile)
				timer = FIRE_INTERVAL
			timers[aircraft] = timer
			queues[aircraft] = queue
			if not queue.is_empty():
				any_pending = true
		if not any_pending:
			_enter_egress(state, float(spawner.mode.game_time))


func _logic_step() -> void:
	if spawner == null or spawner.mode == null or not is_instance_valid(spawner.mode):
		return
	var groups: Dictionary = {}
	for i in range(_units.size() - 1, -1, -1):
		var aircraft := _units[i]
		if not is_instance_valid(aircraft) or aircraft.is_destroyed:
			_units.remove_at(i)
			continue
		var ai = spawner._get_ai(aircraft)
		var group_key: int = ai.squad.get_instance_id() if ai and ai.squad else aircraft.get_instance_id()
		if not groups.has(group_key):
			groups[group_key] = []
		(groups[group_key] as Array).append(aircraft)

	for stale_key in _group_states.keys():
		if not groups.has(stale_key):
			_group_states.erase(stale_key)
	var player_targets: Array = spawner.mode.call("_squad_members_alive") \
		if spawner.mode.has_method("_squad_members_alive") else [spawner.player_aircraft]
	if player_targets.is_empty():
		return
	var now: float = float(spawner.mode.game_time)
	for group_key in groups:
		var members: Array = groups[group_key]
		var state: Dictionary = _group_states.get(group_key, {
			"phase": "setup", "until": 0.0, "queues": {}, "timers": {}, "members": members})
		state["members"] = members
		_group_states[group_key] = state
		var phase: String = str(state["phase"])
		if phase == "execute":
			continue
		if phase == "egress":
			if now < float(state["until"]):
				continue
			state["phase"] = "setup"
			for aircraft_v in members:
				var aircraft: Aircraft = aircraft_v
				aircraft.is_afterburner = false
				aircraft.ai_override_pursuit = false

		if _is_pressed(members, player_targets):
			_enter_egress(state, now)
			continue
		var eligibility: Array = []
		for aircraft_v in members:
			var aircraft: Aircraft = aircraft_v
			var row: Array = []
			for target_v in player_targets:
				var target: Aircraft = target_v
				var ready: bool = aircraft._missile_cooldown <= 0.0 \
						and aircraft.missiles_remaining > 0 \
						and aircraft.radar_targets.has(target) \
						and float(aircraft.radar_targets[target]) >= aircraft.params.lock_time \
						and aircraft.is_in_radar_cone(target.global_position)
				row.append(ready)
			eligibility.append(row)
		var allocation: Array = allocate_unique_targets(eligibility, player_targets.size())
		var queues: Dictionary = {}
		var timers: Dictionary = {}
		var total_shots := 0
		for member_idx in range(members.size()):
			var target_queue: Array = []
			for target_idx in allocation[member_idx]:
				target_queue.append(player_targets[target_idx])
			if not target_queue.is_empty():
				queues[members[member_idx]] = target_queue
				timers[members[member_idx]] = 0.0
				total_shots += target_queue.size()
		if total_shots > 0:
			state["phase"] = "execute"
			state["queues"] = queues
			state["timers"] = timers
			EventLogger.log_event("F22", "Volley",
				"aircraft=%d targets=%d shots=%d" % [members.size(), player_targets.size(), total_shots])


func _is_pressed(members: Array, player_targets: Array) -> bool:
	var press_d2: float = PRESS_ABORT_RANGE_PX * PRESS_ABORT_RANGE_PX
	for aircraft_v in members:
		var aircraft: Aircraft = aircraft_v
		for target_v in player_targets:
			var target: Aircraft = target_v
			if aircraft.global_position.distance_squared_to(target.global_position) <= press_d2:
				return true
	return false


func _enter_egress(state: Dictionary, now: float) -> void:
	state["phase"] = "egress"
	state["until"] = now + EGRESS_SECONDS
	state["queues"] = {}
	state["timers"] = {}
	for aircraft_v in state.get("members", []):
		if not is_instance_valid(aircraft_v):
			continue
		var aircraft: Aircraft = aircraft_v
		aircraft.radar_targets.clear()
		aircraft.is_afterburner = true
		aircraft.ai_override_pursuit = true
		var ai = spawner._get_ai(aircraft)
		if ai:
			ai.bvr_only = true
			ai.bvr_standoff_min_px_override = STANDOFF_MIN_PX
			ai.bvr_flee_distance_px_override = FLEE_DISTANCE_PX
	EventLogger.log_event("F22", "Egress", "until=%.1f" % float(state["until"]))
