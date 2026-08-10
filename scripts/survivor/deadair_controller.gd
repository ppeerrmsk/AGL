class_name DeadairController
extends RefCounted

## DEADAIR 的唯一运行时控制器。Spawner 持有并 tick；5Hz 扫 CombatUnit 注册表与 Missile 注册表。

const FieldVisual = preload("res://scripts/survivor/deadair_field_visual.gd")

const RADIUS_PX: float = 1500.0
const UNIT_THRESHOLD_S: float = 8.0
const MISSILE_RATE: float = 4.0
const OUTSIDE_GRACE_S: float = 1.0
const UNIT_DECAY_PER_S: float = 2.0
const JAM_REFRESH_S: float = 0.5
const PRESSURE_RADIUS_PX: float = 1000.0
const ESCAPE_DISTANCE_PX: float = 2250.0
const TICK_INTERVAL_S: float = 0.2

var _spawner
var _host: Aircraft = null
var _tick_accum: float = 0.0
var _unit_exposure: Dictionary = {} ## instance_id → 等效暴露秒数
var _unit_outside: Dictionary = {}  ## instance_id → 离场秒数
var _missile_exposure: Dictionary = {} ## instance_id → 等效暴露秒数


func _init(spawner) -> void:
	_spawner = spawner


func register(host: Aircraft) -> void:
	if host == null or not is_instance_valid(host):
		return
	if _host != null and is_instance_valid(_host) and _host != host:
		push_warning("[DEADAIR] 同场只支持一个干扰场，忽略重复本体 %s" % host.callsign)
		return
	_host = host
	_tick_accum = TICK_INTERVAL_S


func refresh_now() -> void:
	_tick_accum = TICK_INTERVAL_S
	tick(0.0)


func has_active_state() -> bool:
	return (_host != null and is_instance_valid(_host)) \
		or not _unit_exposure.is_empty() or not _missile_exposure.is_empty()


func field_snapshot() -> Dictionary:
	if _host == null or not is_instance_valid(_host) or _host.is_destroyed:
		return {}
	return {"position": _host.global_position, "radius_px": RADIUS_PX}


func shutdown() -> void:
	_clear_all_exposure()
	_host = null
	_spawner = null


func tick(delta: float) -> void:
	_tick_accum += delta
	if _tick_accum < TICK_INTERVAL_S:
		return
	var step := _tick_accum
	_tick_accum = 0.0
	var host := _find_host()
	if host == null:
		_clear_all_exposure()
		_host = null
		return
	_tick_units(host, step)
	_tick_missiles(host, step)
	_order_escape_if_pressured(host)


## 纯函数：单位入圈累积、离圈宽限与衰减，供无头边界测试。
static func next_unit_exposure(exposure: float, outside_s: float, inside: bool,
		delta: float) -> Dictionary:
	if inside:
		return {"exposure": minf(exposure + delta, UNIT_THRESHOLD_S), "outside": 0.0}
	var next_outside := outside_s + delta
	if next_outside <= OUTSIDE_GRACE_S:
		return {"exposure": exposure, "outside": next_outside}
	return {"exposure": maxf(exposure - UNIT_DECAY_PER_S * delta, 0.0),
		"outside": next_outside}


static func next_missile_exposure(exposure: float, inside: bool, delta: float) -> float:
	return minf(exposure + MISSILE_RATE * delta, UNIT_THRESHOLD_S) if inside else 0.0


func _find_host() -> Aircraft:
	if _host != null and is_instance_valid(_host):
		if not _host.is_destroyed:
			return _host
		FieldVisual.collapse(_host)
	for unit_any in CombatUnit.all_units:
		var unit: Variant = unit_any
		if not is_instance_valid(unit) or not unit is Aircraft:
			continue
		var aircraft := unit as Aircraft
		if not aircraft.is_destroyed and str(aircraft.get_meta("enemy_type", "")) == "deadair":
			_host = aircraft
			return aircraft
	return null


func _tick_units(host: Aircraft, step: float) -> void:
	var inside_ids: Dictionary = {}
	var radius_sq := RADIUS_PX * RADIUS_PX
	for unit_any in CombatUnit.all_units:
		var unit: Variant = unit_any
		if not is_instance_valid(unit) or not unit is CombatUnit:
			continue
		var target := unit as CombatUnit
		if target.is_destroyed or not host.is_hostile_to(target):
			continue
		var id := target.get_instance_id()
		if target.global_position.distance_squared_to(host.global_position) > radius_sq:
			continue
		inside_ids[id] = true
		var state := next_unit_exposure(float(_unit_exposure.get(id, 0.0)), 0.0, true, step)
		var exposure := float(state["exposure"])
		_unit_exposure[id] = exposure
		_unit_outside[id] = 0.0
		target.set_deadair_exposure_ratio(exposure / UNIT_THRESHOLD_S)
		if exposure >= UNIT_THRESHOLD_S - 0.001:
			target.apply_status(StatusEffects.JAM, JAM_REFRESH_S)

	for id_any in _unit_exposure.keys():
		var id := int(id_any)
		if inside_ids.has(id):
			continue
		var target_any: Variant = instance_from_id(id)
		if not is_instance_valid(target_any) or not target_any is CombatUnit:
			_unit_exposure.erase(id)
			_unit_outside.erase(id)
			continue
		var target := target_any as CombatUnit
		var state := next_unit_exposure(float(_unit_exposure[id]),
			float(_unit_outside.get(id, 0.0)), false, step)
		var exposure := float(state["exposure"])
		_unit_exposure[id] = exposure
		_unit_outside[id] = float(state["outside"])
		target.set_deadair_exposure_ratio(exposure / UNIT_THRESHOLD_S)
		if exposure <= 0.0:
			_unit_exposure.erase(id)
			_unit_outside.erase(id)


func _tick_missiles(host: Aircraft, step: float) -> void:
	var inside_ids: Dictionary = {}
	var radius_sq := RADIUS_PX * RADIUS_PX
	for missile_any in Missile.active_missiles:
		var missile: Variant = missile_any
		if not is_instance_valid(missile) or not missile is Missile:
			continue
		var guided := missile as Missile
		if not guided.is_active or guided.is_flare_jammed or not guided.has_guidance \
				or not CombatUnit.teams_hostile(host.team, guided.team):
			continue
		var id := guided.get_instance_id()
		if guided.global_position.distance_squared_to(host.global_position) > radius_sq:
			continue
		inside_ids[id] = true
		var exposure := next_missile_exposure(float(_missile_exposure.get(id, 0.0)), true, step)
		_missile_exposure[id] = exposure
		guided.set_deadair_exposure_ratio(exposure / UNIT_THRESHOLD_S)
		if exposure >= UNIT_THRESHOLD_S - 0.001:
			guided.jam_by_deadair()
			_missile_exposure.erase(id)

	for id_any in _missile_exposure.keys():
		var id := int(id_any)
		if inside_ids.has(id):
			continue
		var missile_any: Variant = instance_from_id(id)
		if is_instance_valid(missile_any) and missile_any is Missile:
			(missile_any as Missile).set_deadair_exposure_ratio(0.0)
		_missile_exposure.erase(id)


func _order_escape_if_pressured(host: Aircraft) -> void:
	var nearest: CombatUnit = null
	var best_sq := PRESSURE_RADIUS_PX * PRESSURE_RADIUS_PX
	for unit_any in CombatUnit.all_units:
		var unit: Variant = unit_any
		if not is_instance_valid(unit) or not unit is CombatUnit:
			continue
		var candidate := unit as CombatUnit
		if candidate.is_destroyed or not host.is_hostile_to(candidate):
			continue
		var distance_sq := host.global_position.distance_squared_to(candidate.global_position)
		if distance_sq < best_sq:
			nearest = candidate
			best_sq = distance_sq
	if nearest == null:
		return
	var away := (host.global_position - nearest.global_position).normalized()
	if away == Vector2.ZERO:
		away = Vector2.RIGHT
	var ai = _spawner._get_ai(host) if _spawner else null
	if ai:
		ai.enable_combat = false
		ai.evade_missiles = false
		ai.waypoints = PackedVector2Array([host.global_position + away * ESCAPE_DISTANCE_PX])
	host.is_afterburner = false
	host.target_speed_kmh = host.params.max_speed if host.params else 650.0


func _clear_all_exposure() -> void:
	for id_any in _unit_exposure.keys():
		var unit_any: Variant = instance_from_id(int(id_any))
		if is_instance_valid(unit_any) and unit_any is CombatUnit:
			(unit_any as CombatUnit).set_deadair_exposure_ratio(0.0)
	for id_any in _missile_exposure.keys():
		var missile_any: Variant = instance_from_id(int(id_any))
		if is_instance_valid(missile_any) and missile_any is Missile:
			(missile_any as Missile).set_deadair_exposure_ratio(0.0)
	_unit_exposure.clear()
	_unit_outside.clear()
	_missile_exposure.clear()
