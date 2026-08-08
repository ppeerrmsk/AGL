class_name BattlefieldAtmosphereExperiment
extends Node2D

## 生存模式内的空中 / 陆地 / 海上战场气氛实验。
## 只管理自己生成的 Debug 演员；目标和表演武器火控集中在 2Hz。
signal status_changed(text: String)

const AA_SCENE := preload("res://scenes/aa_gun_unit.tscn")
const SAM_SCENE := preload("res://scenes/sam_unit.tscn")
const AA_PARAMS: AircraftParams = preload("res://resources/aa_gun_params.tres")
const SAM_PARAMS: AircraftParams = preload("res://resources/sam_params.tres")
const ARTILLERY_SCRIPT := preload("res://scripts/survivor/atmosphere_artillery_unit.gd")
const FFG_SCRIPT := preload("res://scripts/naval/frigate_ship.gd")
const DDG_SCRIPT := preload("res://scripts/naval/destroyer_ship.gd")
const FFG_PARAMS: NavalParams = preload("res://resources/naval/frigate_ffg.tres")
const DDG_PARAMS: NavalParams = preload("res://resources/naval/destroyer_ddg.tres")

const ACTOR_GROUP := &"battlefield_atmosphere_actor"
const DAMAGE_MULT := 0.10
const RETARGET_TICK_S := 0.5
const CENTER_AHEAD_PX := 2200.0
const BOUNDARY_MARGIN_PX := 4200.0
const FIGHTER_SEPARATION_PX := 2400.0
const FIGHTER_LATERAL_PX := 260.0
const FIGHTER_TRAIL_PX := 240.0
const GROUND_LATERAL_PX := 950.0
const HELI_ORBIT_START_PX := 620.0
const DEBUG_HARDENED_HP := 900.0
const ARTILLERY_COUNT_PER_SIDE := 3
const ARTILLERY_LINE_SEPARATION_PX := 1700.0
const ARTILLERY_SLOT_PX := 180.0
const ARTILLERY_ROUTE_PX := 700.0
const ARTILLERY_RANGE_PX := 2600.0
const ARTILLERY_SHELL_TIME_S := 2.2
const ARTILLERY_DAMAGE := 6.0
const ARTILLERY_AOE_RADIUS_PX := 55.0
const NAVAL_GROUP_SEPARATION_PX := 1600.0
const NAVAL_ROUTE_PX := 2400.0
const NAVAL_GUN_TIME_S := 1.6
const NAVAL_GUN_DAMAGE := 1.8

var _mode: Node2D
var _spawner: SurvivorSpawner
var _actors: Array[Node] = []
var _fighters: Array[Aircraft] = []
var _helis: Array[Aircraft] = []
var _ground_targets: Array[GroundUnit] = []
var _artillery_units: Array[GroundUnit] = []
var _naval_units: Array[NavalUnit] = []
var _assigned_targets: Dictionary = {}
var _weapon_ready: Dictionary = {}
var _ballistic_shells: Array[Dictionary] = []
var _impact_flashes: Array[Dictionary] = []
var _battle_center := Vector2.ZERO
var _tick_accum := 0.0
var _run_id := 0
var _active := false
var _sample_kind := "air"


func setup(mode: Node2D, spawner: SurvivorSpawner) -> void:
	_mode = mode
	_spawner = spawner
	set_physics_process(false)


func launch_air_battle() -> bool:
	if not _begin_sample("air"):
		return false

	var player := _spawner.player_aircraft
	var axis := _player_forward()
	var lateral := Vector2(-axis.y, axis.x)
	_battle_center = MapBoundary.clamp_inside(
		player.global_position + axis * CENTER_AHEAD_PX, BOUNDARY_MARGIN_PX)

	var ally_ground_center := _battle_center - lateral * GROUND_LATERAL_PX
	var hostile_ground_center := _battle_center + lateral * GROUND_LATERAL_PX
	var ally_ground := _spawn_ground_anchor(CombatUnit.TEAM_ALLY, ally_ground_center, axis)
	var hostile_ground := _spawn_ground_anchor(CombatUnit.TEAM_HOSTILE, hostile_ground_center, -axis)
	_spawn_hardened_target(CombatUnit.TEAM_ALLY, ally_ground_center + axis * 340.0,
		StrategicTarget.TargetKind.BUNKER, "ALLY-HARDPOINT")
	_spawn_hardened_target(CombatUnit.TEAM_HOSTILE, hostile_ground_center - axis * 340.0,
		StrategicTarget.TargetKind.MISSILE_SILO, "HOSTILE-HARDPOINT")

	var ally_base := _battle_center - axis * (FIGHTER_SEPARATION_PX * 0.5)
	var hostile_base := _battle_center + axis * (FIGHTER_SEPARATION_PX * 0.5)
	_spawn_fighter_wedge(CombatUnit.TEAM_ALLY, SurvivorSpawner.EnemyType.F86,
		ally_base, axis, lateral, "SABRE")
	_spawn_fighter_wedge(CombatUnit.TEAM_HOSTILE, SurvivorSpawner.EnemyType.MIG23,
		hostile_base, -axis, -lateral, "FLOGGER")

	_spawn_heli_pair(CombatUnit.TEAM_ALLY, hostile_ground, hostile_ground_center, axis, lateral, "APACHE-A")
	_spawn_heli_pair(CombatUnit.TEAM_HOSTILE, ally_ground, ally_ground_center, -axis, -lateral, "APACHE-H")
	_spawn_bomber_pair(axis, lateral, ally_ground_center, hostile_ground_center)
	_refresh_assignments()
	_emit_status()
	EventLogger.log_event("ATMOSPHERE", "Launch",
		"run=%d center=%s actors=%d damage_mult=%.2f" % [_run_id, _battle_center, _actors.size(), DAMAGE_MULT])
	return true


func launch_ground_battle() -> bool:
	if not _begin_sample("ground"):
		return false
	var player := _spawner.player_aircraft
	var axis := _player_forward()
	var lateral := Vector2(-axis.y, axis.x)
	var desired := MapBoundary.clamp_inside(
		player.global_position + axis * 1600.0, BOUNDARY_MARGIN_PX)
	_battle_center = _find_land_battle_center(desired, axis, lateral)
	if _battle_center == Vector2.INF:
		clear_experiment(false)
		status_changed.emit("启动失败：附近没有可容纳 3v3 炮线的连续陆地")
		return false
	_spawn_artillery_line(CombatUnit.TEAM_ALLY,
		_battle_center - lateral * ARTILLERY_LINE_SEPARATION_PX * 0.5,
		lateral, axis, "ALLY-SPG")
	_spawn_artillery_line(CombatUnit.TEAM_HOSTILE,
		_battle_center + lateral * ARTILLERY_LINE_SEPARATION_PX * 0.5,
		-lateral, -axis, "HOSTILE-SPG")
	_emit_status()
	EventLogger.log_event("ATMOSPHERE", "GroundLaunch",
		"run=%d center=%s artillery=%d" % [_run_id, _battle_center, _artillery_units.size()])
	return true


func launch_naval_battle() -> bool:
	if not _begin_sample("naval"):
		return false
	var player := _spawner.player_aircraft
	var axis := _player_forward()
	var lateral := Vector2(-axis.y, axis.x)
	var desired := player.global_position + axis * 1800.0
	_battle_center = _find_water_battle_center(desired, axis, lateral)
	if _battle_center == Vector2.INF:
		clear_experiment(false)
		status_changed.emit("启动失败：附近没有可容纳双舰队航路的连续水域")
		return false
	_spawn_naval_group(CombatUnit.TEAM_ALLY,
		_battle_center - lateral * NAVAL_GROUP_SEPARATION_PX * 0.5,
		axis, lateral, "ALLY")
	_spawn_naval_group(CombatUnit.TEAM_HOSTILE,
		_battle_center + lateral * NAVAL_GROUP_SEPARATION_PX * 0.5,
		-axis, -lateral, "HOSTILE")
	_emit_status()
	EventLogger.log_event("ATMOSPHERE", "NavalLaunch",
		"run=%d center=%s ships=%d" % [_run_id, _battle_center, _naval_units.size()])
	return true


func _begin_sample(kind: String) -> bool:
	if _mode == null or not is_instance_valid(_mode) or _spawner == null \
			or not is_instance_valid(_spawner) or _spawner.player_aircraft == null \
			or not is_instance_valid(_spawner.player_aircraft) \
			or _spawner.player_aircraft.is_destroyed:
		return false
	clear_experiment(false)
	_run_id += 1
	_sample_kind = kind
	_active = true
	_tick_accum = 0.0
	set_physics_process(true)
	return true


func _player_forward() -> Vector2:
	var player := _spawner.player_aircraft
	var axis := Vector2(sin(player.heading), -cos(player.heading)).normalized()
	return Vector2.UP if axis.length_squared() < 0.5 else axis


func clear_experiment(emit_update: bool = true) -> void:
	_active = false
	set_physics_process(false)
	var actors_to_remove: Array[Node] = _actors.duplicate()
	_release_runtime_refs()
	for actor in actors_to_remove:
		if not is_instance_valid(actor):
			continue
		actor.queue_free()
	_ballistic_shells.clear()
	_impact_flashes.clear()
	queue_redraw()
	if emit_update:
		status_changed.emit("未运行")
		EventLogger.log_event("ATMOSPHERE", "Clear", "run=%d" % _run_id)


func _exit_tree() -> void:
	# 场景结束时 SceneTree 会统一销毁演员；这里只拆掉 directive/目标强引用，
	# 避免 RefCounted 指令把 sibling CombatUnit 留到 ObjectDB 清理阶段。
	_release_runtime_refs()


func _release_runtime_refs() -> void:
	for actor in _actors:
		if not is_instance_valid(actor):
			continue
		if actor is Aircraft:
			var ai: AIController = (actor as Aircraft)._get_ai_controller()
			if ai != null:
				ai.set_event_directive(null)
				ai.release_target(AIController.TargetSource.TS_DIRECTIVE,
					"battlefield atmosphere cleanup")
		elif actor is NavalUnit:
			(actor as NavalUnit).set_event_directive(null)
		if actor is CombatUnit:
			CombatUnit.release_target_refs(actor as CombatUnit)
	_actors.clear()
	_fighters.clear()
	_helis.clear()
	_ground_targets.clear()
	_artillery_units.clear()
	_naval_units.clear()
	_assigned_targets.clear()
	_weapon_ready.clear()


func is_active() -> bool:
	return _active


func _physics_process(delta: float) -> void:
	if not _active:
		return
	_update_ballistic_shells(delta)
	_update_impact_flashes(delta)
	_tick_accum += delta
	if _tick_accum < RETARGET_TICK_S:
		return
	var fire_delta := _tick_accum
	_tick_accum = 0.0
	_cleanup_refs()
	match _sample_kind:
		"air":
			_refresh_assignments()
		"ground":
			_update_artillery_fire_control(fire_delta)
		"naval":
			_update_naval_fire_control(fire_delta)
	_emit_status()


func _spawn_fighter_wedge(team: int, enemy_type: int, base: Vector2, forward: Vector2,
		lateral: Vector2, prefix: String) -> void:
	var slots := [
		Vector2.ZERO,
		-lateral * FIGHTER_LATERAL_PX - forward * FIGHTER_TRAIL_PX,
		lateral * FIGHTER_LATERAL_PX - forward * FIGHTER_TRAIL_PX,
	]
	var heading_deg := _heading_deg(forward)
	for i in range(slots.size()):
		var ac: Aircraft = _spawner._create_enemy(enemy_type, base + slots[i], heading_deg)
		_configure_ambient_aircraft(ac, team, "fighter")
		ac.callsign = "%s-%02d" % [prefix, i + 1]
		_fighters.append(ac)


func _spawn_heli_pair(team: int, targets: Array[GroundUnit], target_center: Vector2,
		forward: Vector2, lateral: Vector2, prefix: String) -> void:
	if targets.is_empty():
		return
	for i in range(2):
		var side := -1.0 if i == 0 else 1.0
		var pos := target_center - forward * HELI_ORBIT_START_PX \
			+ lateral * side * HELI_ORBIT_START_PX * 0.45
		var heli: Aircraft = _spawner._create_enemy(
			SurvivorSpawner.EnemyType.AH64, pos, _heading_deg(forward), 5)
		_configure_ambient_aircraft(heli, team, "rotorcraft")
		heli.callsign = "%s-%02d" % [prefix, i + 1]
		_spawner._configure_adds_unit(heli, target_center + forward * 2500.0,
			CombatUnit.AltitudeTier.LOW, heli.params.cruise_speed, "apache", "heli", 180.0)
		EventLogger.log_event("ATMOSPHERE", "RotorConfig",
			"unit=%s silhouette=%s rocket=%s" % [heli.callsign,
			str(heli.get_meta("silhouette", "")), str(heli.params.rocket != null)])
		var ai: AIController = heli._get_ai_controller()
		if ai != null:
			ai.enable_combat = true
			ai.acquire_target(targets[i % targets.size()], AIController.TargetSource.TS_DIRECTIVE,
				"battlefield atmosphere rotor assignment")
		_helis.append(heli)


func _spawn_ground_anchor(team: int, center: Vector2, forward: Vector2) -> Array[GroundUnit]:
	var units: Array[GroundUnit] = []
	var aa := _spawn_ground_unit(AA_SCENE, AA_PARAMS, team, center - forward * 120.0,
		"ALLY-AAA" if team == CombatUnit.TEAM_ALLY else "HOSTILE-AAA")
	var sam := _spawn_ground_unit(SAM_SCENE, SAM_PARAMS, team, center + forward * 180.0,
		"ALLY-SAM" if team == CombatUnit.TEAM_ALLY else "HOSTILE-SAM")
	if aa != null:
		units.append(aa)
	if sam != null:
		units.append(sam)
	return units


func _spawn_ground_unit(scene: PackedScene, base_params: AircraftParams, team: int,
		pos: Vector2, callsign: String) -> GroundUnit:
	var unit: GroundUnit = scene.instantiate()
	var p: AircraftParams = base_params.duplicate(true)
	_duplicate_and_scale_weapons(p)
	unit.params = p
	unit.team = team
	unit.position = pos
	unit.callsign = callsign
	unit.initial_heading_deg = _heading_deg(_battle_center - pos)
	_mark_actor(unit, "ground")
	_mode.add_child(unit)
	unit.bullet_manager = _spawner.bullet_manager
	unit.missile_manager = _spawner.missile_manager
	_ground_targets.append(unit)
	return unit


func _spawn_artillery_line(team: int, base: Vector2, enemy_direction: Vector2,
		route_axis: Vector2, prefix: String) -> void:
	for i in range(ARTILLERY_COUNT_PER_SIDE):
		var slot_offset := route_axis * (float(i) - 1.0) * ARTILLERY_SLOT_PX
		var pos := base + slot_offset
		var unit: GroundUnit = ARTILLERY_SCRIPT.new()
		var p: AircraftParams = AA_PARAMS.duplicate(true)
		p.display_name = "SPG"
		p.max_hp = 120.0
		p.radar_range = 0.0
		p.gun = null
		unit.params = p
		unit.team = team
		unit.position = pos
		unit.callsign = "%s-%02d" % [prefix, i + 1]
		unit.initial_heading_deg = _heading_deg(enemy_direction)
		unit.max_ground_speed = 3.0
		unit.call("configure_rail", pos, route_axis, ARTILLERY_ROUTE_PX * 0.5, 45.0)
		unit.set_meta("ambient_slot", i)
		_mark_actor(unit, "artillery")
		_mode.add_child(unit)
		unit.bullet_manager = _spawner.bullet_manager
		unit.missile_manager = _spawner.missile_manager
		_artillery_units.append(unit)
		_weapon_ready[_weapon_key("artillery", unit)] = 0.8 + float(i) * 0.7 \
			+ (0.35 if team == CombatUnit.TEAM_HOSTILE else 0.0)


func _spawn_naval_group(team: int, base: Vector2, forward: Vector2,
		lateral: Vector2, prefix: String) -> void:
	var leader := _spawn_atmosphere_ship(DDG_SCRIPT, DDG_PARAMS, team, base,
		forward, "%s-DDG" % prefix)
	if leader == null:
		return
	leader.waypoints = PackedVector2Array([
		base - forward * NAVAL_ROUTE_PX * 0.5,
		base + forward * NAVAL_ROUTE_PX * 0.5,
	])
	leader.target_position = leader.waypoints[0]
	var wing_pos := base - forward * 210.0 + lateral * 230.0
	var wing := _spawn_atmosphere_ship(FFG_SCRIPT, FFG_PARAMS, team, wing_pos,
		forward, "%s-FFG" % prefix)
	if wing != null:
		wing.formation_leader = leader
		wing.formation_offset = Vector2(-210.0, 230.0)


func _spawn_atmosphere_ship(ship_script: GDScript, base_params: NavalParams, team: int,
		pos: Vector2, forward: Vector2, callsign_prefix: String) -> NavalUnit:
	var ship: NavalUnit = ship_script.new()
	var p: NavalParams = base_params.duplicate(true)
	p.default_team = team
	ship.params = p
	ship.position = pos
	ship.initial_heading_deg = _heading_deg(forward)
	_mark_actor(ship, "naval")
	_mode.add_child(ship)
	ship.callsign = "%s-%s" % [callsign_prefix, ship.full_name]
	ship.bullet_manager = _spawner.bullet_manager
	ship.missile_manager = _spawner.missile_manager
	# 永久 PASSIVE 只关闭现有 SAM/CIWS/Flak；移动继续走 NavalUnit 正式航路。
	ship.set_event_directive(AIDirective.passive())
	_naval_units.append(ship)
	var stagger := float(_naval_units.size() % 2) * 0.6
	_weapon_ready[_weapon_key("naval_gun", ship)] = 0.8 + stagger
	return ship


func _find_land_battle_center(desired: Vector2, axis: Vector2, lateral: Vector2) -> Vector2:
	for radius_value in [0.0, 700.0, 1400.0, 2200.0, 3200.0, 4400.0]:
		var radius: float = float(radius_value)
		var samples: int = 1 if radius == 0.0 else 16
		for i in range(samples):
			var candidate: Vector2 = desired + Vector2.from_angle(float(i) * TAU / float(samples)) * radius
			candidate = MapBoundary.clamp_inside(candidate, BOUNDARY_MARGIN_PX)
			if _is_land_formation_region(candidate, axis, lateral):
				return candidate
	return Vector2.INF


func _is_land_formation_region(center: Vector2, axis: Vector2, lateral: Vector2) -> bool:
	for side_value in [-1.0, 1.0]:
		var side: float = float(side_value)
		var base: Vector2 = center + lateral * side * ARTILLERY_LINE_SEPARATION_PX * 0.5
		for slot_value in [-1.0, 0.0, 1.0]:
			var slot: float = float(slot_value)
			var pos: Vector2 = base + axis * slot * ARTILLERY_SLOT_PX
			for route_side_value in [-1.0, 0.0, 1.0]:
				var route_side: float = float(route_side_value)
				if not MapGeography.is_on_land_strict(
						pos + axis * route_side * ARTILLERY_ROUTE_PX * 0.5):
					return false
	return true


func _find_water_battle_center(desired: Vector2, axis: Vector2, lateral: Vector2) -> Vector2:
	for radius_value in [0.0, 700.0, 1400.0, 2400.0, 3600.0, 5000.0, 6500.0]:
		var radius: float = float(radius_value)
		var samples: int = 1 if radius == 0.0 else 16
		for i in range(samples):
			var candidate: Vector2 = desired + Vector2.from_angle(float(i) * TAU / float(samples)) * radius
			candidate = MapBoundary.clamp_inside(candidate, 2600.0)
			if _is_water_formation_region(candidate, axis, lateral):
				return candidate
	return Vector2.INF


func _is_water_formation_region(center: Vector2, axis: Vector2, lateral: Vector2) -> bool:
	for side_value in [-1.0, 1.0]:
		var side: float = float(side_value)
		var base: Vector2 = center + lateral * side * NAVAL_GROUP_SEPARATION_PX * 0.5
		for route_side_value in [-1.0, 0.0, 1.0]:
			var route_side: float = float(route_side_value)
			var pos: Vector2 = base + axis * route_side * NAVAL_ROUTE_PX * 0.5
			if MapGeography.is_on_land(pos) or MapGeography.is_on_land(pos - axis * 210.0 + lateral * 230.0):
				return false
	return true


func _spawn_hardened_target(team: int, pos: Vector2, kind: int, callsign: String) -> void:
	var target := _spawner.spawn_strategic_target(kind, team, pos) as StrategicTarget
	if target == null:
		return
	var p: AircraftParams = target.params.duplicate(true)
	p.max_hp = DEBUG_HARDENED_HP
	target.params = p
	target.hp = DEBUG_HARDENED_HP
	target.callsign = callsign
	target.is_mission_target = true
	_mark_actor(target, "hardened_target")
	target.queue_redraw()


func _spawn_bomber_pair(axis: Vector2, lateral: Vector2, ally_ground_center: Vector2,
		hostile_ground_center: Vector2) -> void:
	var ally_target := hostile_ground_center - axis * 340.0
	var hostile_target := ally_ground_center + axis * 340.0
	var ally_route := PackedVector2Array([
		ally_target - axis * 3600.0 - lateral * 220.0,
		ally_target - axis * 1200.0,
		ally_target,
		ally_target + axis * 2400.0,
	])
	var hostile_route := PackedVector2Array([
		hostile_target + axis * 3600.0 + lateral * 220.0,
		hostile_target + axis * 1200.0,
		hostile_target,
		hostile_target - axis * 2400.0,
	])
	_track_bomber_mission(_spawner.spawn_bomber_mission(
		CombatUnit.TEAM_ALLY, ally_route, ally_target, 1), "bomber")
	_track_bomber_mission(_spawner.spawn_bomber_mission(
		CombatUnit.TEAM_HOSTILE, hostile_route, hostile_target, 1), "bomber")


func _track_bomber_mission(mission: Node, role: String) -> void:
	if mission == null:
		return
	_track_actor(mission)
	var members_value: Variant = mission.get("_members")
	if not (members_value is Array):
		return
	for member_value in members_value:
		if member_value is Dictionary:
			var ac_value: Variant = (member_value as Dictionary).get("aircraft", null)
			if ac_value is Aircraft and is_instance_valid(ac_value):
				_configure_ambient_aircraft(ac_value as Aircraft, (ac_value as Aircraft).team, role)


func _update_artillery_fire_control(delta: float) -> void:
	for unit in _artillery_units:
		if not _is_live_experiment_unit(unit, "artillery"):
			continue
		var target := _matching_opposing_artillery(unit)
		if target == null:
			continue
		var to_target := target.global_position - unit.global_position
		unit.set("barrel_heading", atan2(to_target.x, -to_target.y))
		var key := _weapon_key("artillery", unit)
		var ready := maxf(float(_weapon_ready.get(key, 0.0)) - delta, 0.0)
		_weapon_ready[key] = ready
		if ready > 0.0 or to_target.length() > ARTILLERY_RANGE_PX:
			continue
		_spawn_ballistic_shell(unit, target, "artillery", ARTILLERY_SHELL_TIME_S,
			ARTILLERY_DAMAGE, ARTILLERY_AOE_RADIUS_PX, 22.0)
		var slot := int(unit.get_meta("ambient_slot", 0))
		_weapon_ready[key] = 4.5 + float(slot) * 0.5


func _update_naval_fire_control(delta: float) -> void:
	for ship in _naval_units:
		if not _is_live_experiment_unit(ship, "naval"):
			continue
		var target := _matching_opposing_ship(ship)
		if target == null:
			continue
		var gun_key := _weapon_key("naval_gun", ship)
		var gun_ready := maxf(float(_weapon_ready.get(gun_key, 0.0)) - delta, 0.0)
		_weapon_ready[gun_key] = gun_ready
		if gun_ready <= 0.0:
			_spawn_ballistic_shell(ship, target, "naval_gun", NAVAL_GUN_TIME_S,
				NAVAL_GUN_DAMAGE, 0.0, 0.0)
			_weapon_ready[gun_key] = 3.0 + float(ship.params.ship_class) * 0.8


func _matching_opposing_artillery(source: GroundUnit) -> GroundUnit:
	var slot := int(source.get_meta("ambient_slot", -1))
	var nearest: GroundUnit = null
	var nearest_d := INF
	for candidate in _artillery_units:
		if not _is_live_experiment_unit(candidate, "artillery") or not source.is_hostile_to(candidate):
			continue
		if int(candidate.get_meta("ambient_slot", -2)) == slot:
			return candidate
		var d := source.global_position.distance_squared_to(candidate.global_position)
		if d < nearest_d:
			nearest_d = d
			nearest = candidate
	return nearest


func _matching_opposing_ship(source: NavalUnit) -> NavalUnit:
	var nearest: NavalUnit = null
	var nearest_d := INF
	for candidate in _naval_units:
		if not _is_live_experiment_unit(candidate, "naval") or not source.is_hostile_to(candidate):
			continue
		if candidate.params != null and source.params != null \
				and candidate.params.ship_class == source.params.ship_class:
			return candidate
		var d := source.global_position.distance_squared_to(candidate.global_position)
		if d < nearest_d:
			nearest_d = d
			nearest = candidate
	return nearest


func _spawn_ballistic_shell(source: CombatUnit, target: CombatUnit, kind: String,
		duration: float, damage: float, radius_px: float, scatter_px: float) -> void:
	var scatter := Vector2.from_angle(randf() * TAU) * randf_range(0.0, scatter_px)
	_ballistic_shells.append({
		"start": source.global_position,
		"end": target.global_position + scatter,
		"age": 0.0,
		"duration": duration,
		"source_id": source.get_instance_id(),
		"source_team": source.team,
		"target_id": target.get_instance_id(),
		"kind": kind,
		"damage": damage,
		"radius_px": radius_px,
	})
	EventLogger.log_event("ATMOSPHERE", "Fire",
		"kind=%s source=%s target=%s damage=%.1f" % [kind, source.callsign, target.callsign, damage])
	queue_redraw()


func _update_ballistic_shells(delta: float) -> void:
	var changed := false
	for i in range(_ballistic_shells.size() - 1, -1, -1):
		var shell: Dictionary = _ballistic_shells[i]
		shell["age"] = float(shell["age"]) + delta
		changed = true
		if float(shell["age"]) >= float(shell["duration"]):
			_resolve_ballistic_impact(shell)
			_ballistic_shells.remove_at(i)
	if changed:
		queue_redraw()


func _resolve_ballistic_impact(shell: Dictionary) -> void:
	var impact_pos: Vector2 = shell["end"]
	var source_team := int(shell["source_team"])
	var attacker := _combat_from_id(int(shell["source_id"]))
	if String(shell["kind"]) == "artillery":
		var radius := float(shell["radius_px"])
		var hits := 0
		for target in _artillery_units:
			if not _is_live_experiment_unit(target, "artillery") \
					or not CombatUnit.teams_hostile(source_team, target.team) \
					or target.global_position.distance_to(impact_pos) > radius:
				continue
			target.take_damage(float(shell["damage"]), attacker, "artillery")
			hits += 1
		EventLogger.log_event("ATMOSPHERE", "ArtilleryImpact",
			"run=%d pos=%s hits=%d damage=%.1f" % [_run_id, impact_pos, hits, float(shell["damage"])])
	else:
		var target := _combat_from_id(int(shell["target_id"])) as NavalUnit
		if _is_live_experiment_unit(target, "naval") \
				and CombatUnit.teams_hostile(source_team, target.team):
			impact_pos = target.global_position
			if attacker != null:
				target.set_meta("_pending_attacker", attacker)
			target.set_meta("_last_damage_kind", "naval_gun")
			target.take_damage_at(float(shell["damage"]), impact_pos, 1.0, false)
			EventLogger.log_event("ATMOSPHERE", "NavalGunHit",
				"run=%d target=%s damage=%.1f" % [_run_id, target.callsign, float(shell["damage"])])
		_add_impact_flash(impact_pos, "naval_hit")
		return
	_add_impact_flash(impact_pos, String(shell["kind"]))


func _add_impact_flash(pos: Vector2, kind: String) -> void:
	_impact_flashes.append({"pos": pos, "kind": kind, "age": 0.0, "duration": 0.8})
	AudioManager.play_sfx_2d("bomb_distant", pos, 4.0)
	queue_redraw()


func _update_impact_flashes(delta: float) -> void:
	if _impact_flashes.is_empty():
		return
	for i in range(_impact_flashes.size() - 1, -1, -1):
		_impact_flashes[i]["age"] = float(_impact_flashes[i]["age"]) + delta
		if float(_impact_flashes[i]["age"]) >= float(_impact_flashes[i]["duration"]):
			_impact_flashes.remove_at(i)
	queue_redraw()


func _configure_ambient_aircraft(ac: Aircraft, team: int, role: String) -> void:
	ac.team = team
	_duplicate_and_scale_weapons(ac.params)
	if role == "rotorcraft" and ac.params != null:
		# 气氛实验 AH-64 只留 M230；不生成无制导火箭弹。
		ac.params.rocket = null
		ac.rockets_remaining = 0
	ac.set_meta("category", "adds")
	ac.set_meta("skip_far_cleanup", true)
	ac.set_meta("no_kill_reward", true)
	ac.set_meta("token_cost", 0)
	_mark_actor(ac, role)


func _duplicate_and_scale_weapons(p: AircraftParams) -> void:
	if p == null:
		return
	if p.gun != null:
		p.gun = p.gun.duplicate()
		p.gun.bullet_damage *= DAMAGE_MULT
	if p.missile != null:
		p.missile = p.missile.duplicate()
		p.missile.damage *= DAMAGE_MULT
	if p.secondary_missile != null:
		p.secondary_missile = p.secondary_missile.duplicate()
		p.secondary_missile.damage *= DAMAGE_MULT
	if p.rocket != null:
		p.rocket = p.rocket.duplicate()
		p.rocket.rocket_damage *= DAMAGE_MULT
		p.rocket.aoe_damage *= DAMAGE_MULT


func _mark_actor(actor: Node, role: String) -> void:
	actor.add_to_group(ACTOR_GROUP)
	actor.set_meta("ambient_engagement_id", _run_id)
	actor.set_meta("ambient_role", role)
	actor.set_meta("category", "adds")
	actor.set_meta("skip_far_cleanup", true)
	actor.set_meta("no_kill_reward", true)
	actor.set_meta("token_cost", 0)
	_track_actor(actor)


func _track_actor(actor: Node) -> void:
	if actor != null and not _actors.has(actor):
		_actors.append(actor)


func _refresh_assignments() -> void:
	for fighter in _fighters:
		if not _is_live_aircraft(fighter):
			continue
		var key := fighter.get_instance_id()
		var assigned_value: Variant = _assigned_targets.get(key, null)
		if assigned_value is Aircraft and _is_valid_fighter_target(fighter, assigned_value as Aircraft):
			continue
		var target := _nearest_opposing_fighter(fighter)
		var ai: AIController = fighter._get_ai_controller()
		if ai == null:
			continue
		if target != null:
			ai.set_event_directive(AIDirective.engage_target(target))
			_assigned_targets[key] = target
		else:
			ai.set_event_directive(AIDirective.patrol_ring(_battle_center, 900.0, 6))
			_assigned_targets.erase(key)
	_refresh_heli_assignments()


func _refresh_heli_assignments() -> void:
	for heli in _helis:
		if not _is_live_aircraft(heli):
			continue
		var ai: AIController = heli._get_ai_controller()
		if ai == null:
			continue
		var current: Variant = ai._current_target
		if current is GroundUnit and _is_valid_ground_target(heli, current as GroundUnit):
			continue
		var target := _nearest_opposing_ground(heli)
		if target != null:
			ai.enable_combat = true
			ai.acquire_target(target, AIController.TargetSource.TS_DIRECTIVE,
				"battlefield atmosphere rotor retarget")
		else:
			ai.enable_combat = false


func _nearest_opposing_fighter(source: Aircraft) -> Aircraft:
	var best: Aircraft = null
	var best_d := INF
	for candidate in _fighters:
		if not _is_valid_fighter_target(source, candidate):
			continue
		var d := source.global_position.distance_squared_to(candidate.global_position)
		if d < best_d:
			best_d = d
			best = candidate
	return best


func _nearest_opposing_ground(source: Aircraft) -> GroundUnit:
	var best: GroundUnit = null
	var best_d := INF
	for candidate in _ground_targets:
		if not _is_valid_ground_target(source, candidate):
			continue
		var d := source.global_position.distance_squared_to(candidate.global_position)
		if d < best_d:
			best_d = d
			best = candidate
	return best


func _is_valid_fighter_target(source: Aircraft, target: Aircraft) -> bool:
	return _is_live_aircraft(target) and source.is_hostile_to(target) \
		and int(target.get_meta("ambient_engagement_id", -1)) == _run_id \
		and str(target.get_meta("ambient_role", "")) == "fighter"


func _is_valid_ground_target(source: Aircraft, target: GroundUnit) -> bool:
	return is_instance_valid(target) and not target.is_destroyed and source.is_hostile_to(target) \
		and int(target.get_meta("ambient_engagement_id", -1)) == _run_id \
		and str(target.get_meta("ambient_role", "")) == "ground"


func _is_live_aircraft(ac: Aircraft) -> bool:
	return is_instance_valid(ac) and not ac.is_destroyed \
		and int(ac.get_meta("ambient_engagement_id", -1)) == _run_id


func _is_live_experiment_unit(unit: CombatUnit, role: String) -> bool:
	return unit != null and is_instance_valid(unit) and not unit.is_destroyed \
		and int(unit.get_meta("ambient_engagement_id", -1)) == _run_id \
		and str(unit.get_meta("ambient_role", "")) == role


func _cleanup_refs() -> void:
	var actors_kept: Array[Node] = []
	for actor in _actors:
		if is_instance_valid(actor) and not actor.is_queued_for_deletion():
			actors_kept.append(actor)
	_actors = actors_kept
	var fighters_kept: Array[Aircraft] = []
	for fighter in _fighters:
		if _is_live_aircraft(fighter):
			fighters_kept.append(fighter)
	_fighters = fighters_kept
	var helis_kept: Array[Aircraft] = []
	for heli in _helis:
		if _is_live_aircraft(heli):
			helis_kept.append(heli)
	_helis = helis_kept
	var ground_kept: Array[GroundUnit] = []
	for ground in _ground_targets:
		if is_instance_valid(ground) and not ground.is_destroyed:
			ground_kept.append(ground)
	_ground_targets = ground_kept
	var artillery_kept: Array[GroundUnit] = []
	for artillery in _artillery_units:
		if _is_live_experiment_unit(artillery, "artillery"):
			artillery_kept.append(artillery)
	_artillery_units = artillery_kept
	var naval_kept: Array[NavalUnit] = []
	for ship in _naval_units:
		if _is_live_experiment_unit(ship, "naval"):
			naval_kept.append(ship)
	_naval_units = naval_kept


func _emit_status() -> void:
	var air_alive := 0
	var ground_alive := 0
	var naval_alive := 0
	for actor in _actors:
		if not is_instance_valid(actor) or not (actor is CombatUnit) or (actor as CombatUnit).is_destroyed:
			continue
		if actor is Aircraft:
			air_alive += 1
		elif actor is NavalUnit:
			naval_alive += 1
		elif actor is GroundUnit:
			ground_alive += 1
	var label: String = String({"air": "空战", "ground": "炮战", "naval": "海战"}.get(
		_sample_kind, "实验"))
	var distance_km := 0.0
	if _spawner != null and is_instance_valid(_spawner) and _spawner.player_aircraft != null \
			and is_instance_valid(_spawner.player_aircraft):
		distance_km = _spawner.player_aircraft.global_position.distance_to(_battle_center) / 500.0
	status_changed.emit("%s运行中 · 中心距玩家%.1fkm · 空中%d 地面%d 舰船%d · 弹丸%d · AI伤害10%%" % [
		label, distance_km, air_alive, ground_alive, naval_alive,
		_ballistic_shells.size(),
	])


func _draw() -> void:
	for shell in _ballistic_shells:
		var t := clampf(float(shell["age"]) / maxf(float(shell["duration"]), 0.01), 0.0, 1.0)
		var pos: Vector2 = Vector2(shell["start"]).lerp(Vector2(shell["end"]), t)
		var arc := 4.0 * t * (1.0 - t)
		var color := Color(1.0, 0.68, 0.22, 0.95) if String(shell["kind"]) == "artillery" \
			else Color(0.88, 0.94, 1.0, 0.95)
		var travel_dir := (Vector2(shell["end"]) - Vector2(shell["start"])).normalized()
		var shell_length := lerpf(10.0, 16.0, arc)
		var shadow_offset := Vector2(6.0, 6.0) * (0.4 + arc)
		draw_line(pos + shadow_offset - travel_dir * shell_length, pos + shadow_offset,
			Color(0.08, 0.09, 0.1, 0.32), 2.4, true)
		draw_line(pos - travel_dir * shell_length, pos,
			Color(color.r, color.g, color.b, 0.72), 2.2, true)
		draw_line(pos - travel_dir * 4.0, pos,
			Color(1.0, 1.0, 1.0, 0.95), 1.0, true)
	for flash in _impact_flashes:
		var t := clampf(float(flash["age"]) / float(flash["duration"]), 0.0, 1.0)
		var pos: Vector2 = flash["pos"]
		var radius := lerpf(5.0, 28.0, t)
		var color := Color(1.0, 0.48, 0.12, (1.0 - t) * 0.85)
		draw_arc(pos, radius, 0.0, TAU, 24, color, 2.0, true)


static func _weapon_key(kind: String, unit: CombatUnit) -> String:
	return "%s:%d" % [kind, unit.get_instance_id()]


static func _combat_from_id(instance_id: int) -> CombatUnit:
	if instance_id <= 0:
		return null
	var obj := instance_from_id(instance_id)
	if obj == null or not is_instance_valid(obj) or not (obj is CombatUnit):
		return null
	return obj as CombatUnit


static func _heading_deg(direction: Vector2) -> float:
	if direction.length_squared() < 0.1:
		return 0.0
	return rad_to_deg(atan2(direction.x, -direction.y))
