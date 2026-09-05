class_name DesertFrontController
extends Node2D

const ARTILLERY_SCRIPT := preload("res://scripts/survivor/atmosphere_artillery_unit.gd")
const BASE_PARAMS: AircraftParams = preload("res://resources/aa_gun_params.tres")

const FRONT_CENTER := Vector2(1200.0, -1800.0)
const ALLY_STAGING := Vector2(-5200.0, 3700.0)
const HOSTILE_STAGING := Vector2(6100.0, -8500.0)
const MAX_PER_SIDE := 9
const INITIAL_PER_SIDE := 3
const FACILITY_INITIAL_BATCH := 2
const FACILITY_PRODUCTION_S := 60.0
const HOSTILE_REINFORCEMENT_S := 75.0
const HELI_FIRST_S := 90.0
const HELI_INTERVAL_S := 150.0
const HELI_WAVE_SIZE := 4
const HELI_LIVE_CAP := 5
const FIRE_TICK_S := 0.5
const FIRE_INTERVAL_S := 4.5
const ARTILLERY_RANGE_PX := 2600.0
const SHELL_TRAVEL_S := 2.2
const SHELL_DAMAGE := 60.0
const SHELL_SCATTER_PX := 80.0
const DIRECT_HIT_RADIUS_PX := 24.0

var _mode: Node
var _spawner: Node
var _facilities: Dictionary = {}
var _allies: Array[GroundUnit] = []
var _hostiles: Array[GroundUnit] = []
var _helicopters: Array[Aircraft] = []
var _fire_ready: Dictionary = {}
var _shells: Array[Dictionary] = []
var _fire_accum: float = 0.0
var _hostile_timer := HOSTILE_REINFORCEMENT_S
var _heli_timer := HELI_FIRST_S
var _slot_serial: int = 0


func setup(mode: Node, spawner: Node) -> void:
	_mode = mode
	_spawner = spawner
	for i in range(INITIAL_PER_SIDE):
		_spawn_artillery(CombatUnit.TEAM_ALLY, ALLY_STAGING + Vector2(0.0, i * 110.0))
		_spawn_artillery(CombatUnit.TEAM_HOSTILE, HOSTILE_STAGING + Vector2(0.0, i * 110.0))
	EventLogger.log_event("DESERT_FRONT", "Setup", "initial=3v3")


func on_zone_captured(zone_id: StringName, center: Vector2) -> void:
	if _facilities.has(zone_id):
		return
	_facilities[zone_id] = {"center": center, "remaining": FACILITY_PRODUCTION_S}
	for i in range(FACILITY_INITIAL_BATCH):
		if _live_count(_allies) >= MAX_PER_SIDE:
			break
		_spawn_artillery(CombatUnit.TEAM_ALLY, center + Vector2(0.0, float(i) * 90.0))
	EventLogger.log_event("DESERT_FRONT", "FacilityCaptured",
		"zone=%s facilities=%d" % [zone_id, _facilities.size()])


func _physics_process(delta: float) -> void:
	if _mode == null or not is_instance_valid(_mode) or bool(_mode.get("is_game_over")):
		return
	_cleanup_refs()
	_update_production(delta)
	_update_helicopter_waves(delta)
	_update_shells(delta)
	_fire_accum += delta
	if _fire_accum >= FIRE_TICK_S:
		var step := _fire_accum
		_fire_accum = fmod(_fire_accum, FIRE_TICK_S)
		_update_artillery_fire(step)
	if not _shells.is_empty():
		queue_redraw()


func _update_production(delta: float) -> void:
	for zone_value in _facilities.keys().duplicate():
		var zid := StringName(zone_value)
		var entry: Dictionary = _facilities[zid]
		entry["remaining"] = float(entry["remaining"]) - delta
		if float(entry["remaining"]) <= 0.0:
			entry["remaining"] = FACILITY_PRODUCTION_S
			if _live_count(_allies) < MAX_PER_SIDE:
				_spawn_artillery(CombatUnit.TEAM_ALLY, Vector2(entry["center"]))
		_facilities[zid] = entry
	_hostile_timer -= delta
	if _hostile_timer <= 0.0:
		_hostile_timer += HOSTILE_REINFORCEMENT_S
		if _live_count(_hostiles) < MAX_PER_SIDE:
			_spawn_artillery(CombatUnit.TEAM_HOSTILE, HOSTILE_STAGING)


func _update_helicopter_waves(delta: float) -> void:
	if _mode.has_method("is_boss_phase") and bool(_mode.call("is_boss_phase")):
		return
	_heli_timer -= delta
	if _heli_timer > 0.0:
		return
	_heli_timer += HELI_INTERVAL_S
	var available := HELI_LIVE_CAP - _live_aircraft_count(_helicopters)
	var count := mini(HELI_WAVE_SIZE, available)
	for i in range(count):
		var angle := TAU * float(i) / float(HELI_WAVE_SIZE)
		var spawn_pos := FRONT_CENTER + Vector2.from_angle(angle) * 1500.0
		var heli: Aircraft = _spawner.call("spawn_atmosphere_ah64",
			CombatUnit.TEAM_HOSTILE, spawn_pos, rad_to_deg(angle + PI),
			&"DESERT_FRONT", FRONT_CENTER, 1100.0) as Aircraft
		if heli != null:
			_helicopters.append(heli)
	EventLogger.log_event("DESERT_FRONT", "HelicopterWave", "spawned=%d" % count)


func _spawn_artillery(team: int, spawn_pos: Vector2) -> GroundUnit:
	if _mode == null or not is_instance_valid(_mode):
		return null
	var safe_pos := MapGeography.find_ground_spawn_near(spawn_pos, 500.0)
	if safe_pos == Vector2.INF:
		return null
	var unit := ARTILLERY_SCRIPT.new() as GroundUnit
	var p := BASE_PARAMS.duplicate(true) as AircraftParams
	p.display_name = "SPG"
	p.max_hp = 60.0
	p.radar_range = 0.0
	p.gun = null
	unit.params = p
	unit.team = team
	unit.max_ground_speed = 12.0
	unit.global_position = safe_pos
	var side := -1.0 if team == CombatUnit.TEAM_ALLY else 1.0
	var lane := float(_slot_serial % MAX_PER_SIDE - MAX_PER_SIDE / 2) * 85.0
	var stop := FRONT_CENTER + Vector2(side * 520.0, lane)
	unit.waypoints = PackedVector2Array([stop])
	unit.callsign = "DESERT-%s-SPG-%02d" % ["ALLY" if team == CombatUnit.TEAM_ALLY else "HOSTILE", _slot_serial + 1]
	unit.set_meta("desert_front_actor", true)
	unit.set_meta("token_cost", 0)
	unit.set_meta("skip_far_cleanup", true)
	if team != CombatUnit.TEAM_HOSTILE:
		unit.set_meta("no_kill_reward", true)
	_mode.add_child(unit)
	unit.bullet_manager = _spawner.bullet_manager
	unit.missile_manager = _spawner.missile_manager
	_slot_serial += 1
	_fire_ready[unit.get_instance_id()] = float(_slot_serial % 9) * 0.45
	if team == CombatUnit.TEAM_ALLY:
		_allies.append(unit)
	else:
		_hostiles.append(unit)
	return unit


func _update_artillery_fire(delta: float) -> void:
	for source in _allies:
		_update_source(source, _hostiles, delta)
	for source in _hostiles:
		_update_source(source, _allies, delta)


func _update_source(source: GroundUnit, targets: Array[GroundUnit], delta: float) -> void:
	if not _is_live_ground(source):
		return
	var key := source.get_instance_id()
	var remaining := maxf(float(_fire_ready.get(key, 0.0)) - delta, 0.0)
	_fire_ready[key] = remaining
	var target := _nearest_target(source, targets)
	if target == null:
		return
	(source as AtmosphereArtilleryUnit).barrel_heading = atan2(
		(target.global_position - source.global_position).x,
		-(target.global_position - source.global_position).y)
	source.queue_redraw()
	if remaining > 0.0:
		return
	_fire_ready[key] = FIRE_INTERVAL_S
	var miss := Vector2.from_angle(randf() * TAU) * sqrt(randf()) * SHELL_SCATTER_PX
	_shells.append({
		"source_id": source.get_instance_id(), "source_team": source.team,
		"target_id": target.get_instance_id(), "start": source.global_position,
		"end": target.global_position + miss, "age": 0.0, "duration": SHELL_TRAVEL_S,
	})


func _update_shells(delta: float) -> void:
	for i in range(_shells.size() - 1, -1, -1):
		var shell: Dictionary = _shells[i]
		shell["age"] = float(shell["age"]) + delta
		if float(shell["age"]) >= float(shell["duration"]):
			_resolve_shell(shell)
			_shells.remove_at(i)
		else:
			_shells[i] = shell


func _resolve_shell(shell: Dictionary) -> void:
	var target_value: Variant = instance_from_id(int(shell["target_id"]))
	var source_value: Variant = instance_from_id(int(shell["source_id"]))
	if typeof(target_value) != TYPE_OBJECT or target_value == null or not is_instance_valid(target_value) \
			or not (target_value is GroundUnit) or typeof(source_value) != TYPE_OBJECT \
			or source_value == null or not is_instance_valid(source_value) \
			or not (source_value is CombatUnit):
		return
	var target := target_value as GroundUnit
	var source := source_value as CombatUnit
	if target.is_destroyed or not CombatUnit.teams_hostile(int(shell["source_team"]), target.team):
		return
	if target.global_position.distance_to(Vector2(shell["end"])) <= DIRECT_HIT_RADIUS_PX:
		target.take_damage(SHELL_DAMAGE, source, "desert_artillery")


func _nearest_target(source: GroundUnit, targets: Array[GroundUnit]) -> GroundUnit:
	var best: GroundUnit = null
	var best_d := ARTILLERY_RANGE_PX
	for target in targets:
		if not _is_live_ground(target):
			continue
		var d := source.global_position.distance_to(target.global_position)
		if d < best_d:
			best_d = d
			best = target
	return best


func _draw() -> void:
	var points := PackedVector2Array()
	var colors := PackedColorArray()
	for shell in _shells:
		var t := clampf(float(shell["age"]) / maxf(float(shell["duration"]), 0.01), 0.0, 1.0)
		var start := Vector2(shell["start"])
		var finish := Vector2(shell["end"])
		var pos := start.lerp(finish, t) + Vector2(0.0, -sin(t * PI) * 90.0)
		var previous := start.lerp(finish, maxf(t - 0.035, 0.0)) \
			+ Vector2(0.0, -sin(maxf(t - 0.035, 0.0) * PI) * 90.0)
		points.append(previous)
		points.append(pos)
		colors.append(Color(1.0, 0.48, 0.12, 0.72))
		colors.append(Color(1.0, 0.88, 0.42, 1.0))
	if points.size() >= 2:
		draw_multiline_colors(points, colors, 3.0, true)


func _cleanup_refs() -> void:
	_allies = _live_ground_array(_allies)
	_hostiles = _live_ground_array(_hostiles)
	var live_helis: Array[Aircraft] = []
	for value in _helicopters:
		if value != null and is_instance_valid(value) and not value.is_destroyed:
			live_helis.append(value)
	_helicopters = live_helis


func _live_ground_array(values: Array[GroundUnit]) -> Array[GroundUnit]:
	var out: Array[GroundUnit] = []
	for value in values:
		if _is_live_ground(value):
			out.append(value)
	return out


func _is_live_ground(value: Variant) -> bool:
	return typeof(value) == TYPE_OBJECT and value != null and is_instance_valid(value) \
		and value is GroundUnit and not (value as GroundUnit).is_destroyed


func _live_count(values: Array[GroundUnit]) -> int:
	var count := 0
	for value in values:
		if _is_live_ground(value):
			count += 1
	return count


func _live_aircraft_count(values: Array[Aircraft]) -> int:
	var count := 0
	for value in values:
		if value != null and is_instance_valid(value) and not value.is_destroyed:
			count += 1
	return count


func facility_count() -> int:
	return _facilities.size()


func live_ground_counts() -> Vector2i:
	return Vector2i(_live_count(_allies), _live_count(_hostiles))
