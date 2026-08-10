class_name ZoneAtmosphereCombat
extends Node2D

## 正式战区的集中式氛围战斗控制器。
## ZoneMission 负责生命周期，本类只在其既有 physics tick 中被 update；没有逐演员新 tick。

const ARTILLERY_SCRIPT := preload("res://scripts/survivor/atmosphere_artillery_unit.gd")
const AA_PARAMS: AircraftParams = preload("res://resources/aa_gun_params.tres")
const FFG_SCRIPT := preload("res://scripts/naval/frigate_ship.gd")
const DDG_SCRIPT := preload("res://scripts/naval/destroyer_ship.gd")
const FFG_PARAMS: NavalParams = preload("res://resources/naval/frigate_ffg.tres")
const DDG_PARAMS: NavalParams = preload("res://resources/naval/destroyer_ddg.tres")

const ACTOR_GROUP := &"zone_atmosphere_actor"
const TICK_S := 0.5
const DAMAGE_LIVE_ENTER_PX := 1500.0
const DAMAGE_LIVE_EXIT_PX := 1800.0
const ALLY_DAMAGE_MULT := 0.10

const ARTILLERY_COUNT := 3
const ARTILLERY_FORMATIONS: Array[StringName] = [&"staggered", &"echelon", &"wedge"]
const ARTILLERY_SLOT_MIN_PX := 165.0
const ARTILLERY_SLOT_MAX_PX := 235.0
const ARTILLERY_DEPTH_MIN_PX := 70.0
const ARTILLERY_DEPTH_MAX_PX := 140.0
const ARTILLERY_JITTER_PX := 25.0
const ARTILLERY_ROUTE_HALF_MIN_PX := 300.0
const ARTILLERY_ROUTE_HALF_MAX_PX := 380.0
const ARTILLERY_ROUTE_WIDTH_MIN_PX := 35.0
const ARTILLERY_ROUTE_WIDTH_MAX_PX := 55.0
const ARTILLERY_ROUTE_ANGLE_JITTER_RAD := 0.18
const ARTILLERY_PHASE_JITTER_RAD := 0.22
const ARTILLERY_INITIAL_CLEARANCE_PX := 100.0
const ARTILLERY_RANGE_PX := 2600.0
const ARTILLERY_SHELL_TIME_S := 2.2
const ARTILLERY_DAMAGE := 6.0
const ARTILLERY_AOE_RADIUS_PX := 55.0

const NAVAL_PATROL_RADII: Array = [240.0, 120.0, 0.0]
const NAVAL_WING_OFFSET := Vector2(-210.0, 230.0)
const NAVAL_GUN_TIME_S := 1.6
const NAVAL_GUN_DAMAGE := 1.8

var _mode: Node
var _spawner: SurvivorSpawner
var _engagements: Dictionary = {}
var _weapon_ready: Dictionary = {}
var _ballistic_shells: Array[Dictionary] = []
var _impact_flashes: Array[Dictionary] = []
var _tick_accum: float = 0.0


func setup(mode: Node, spawner: SurvivorSpawner) -> void:
	_mode = mode
	_spawner = spawner
	set_physics_process(false)


## 返回本次新增的气氛演员，便于 ZoneMission 做诊断与可见性安全撤离。
func register_zone(zone_id: StringName, mission_type: String, zone: Dictionary,
		existing_hostiles: Array, player: Aircraft) -> Array[CombatUnit]:
	if _engagements.has(zone_id):
		return []
	if mission_type == "bomber_escort":
		return []
	var kind := _kind_for_mission(mission_type)
	var hostiles: Array[CombatUnit] = []
	for value in existing_hostiles:
		var unit := _live_combat_unit(value)
		if unit != null:
			hostiles.append(unit)
	if hostiles.is_empty():
		return []
	var center: Vector2 = zone.get("center", Vector2.ZERO)
	var radius: float = float(zone.get("radius", 3500.0))
	var damage_live := _player_near(player, center, DAMAGE_LIVE_ENTER_PX)
	var entry := {
		"kind": kind,
		"center": center,
		"radius": radius,
		"hostiles": hostiles,
		"allies": [] as Array[CombatUnit],
		"opposition": [] as Array[CombatUnit],
		"damage_live": damage_live,
	}
	_engagements[zone_id] = entry
	var allies: Array[CombatUnit] = []
	var opposition: Array[CombatUnit] = []
	match kind:
		"ground":
			allies = _spawn_artillery_group(zone_id, center, radius,
				_average_position(hostiles, center), CombatUnit.TEAM_ALLY, "ALLY")
			opposition = _spawn_artillery_group(zone_id, center, radius,
				_average_position(allies, center), CombatUnit.TEAM_HOSTILE, "HOSTILE")
		"naval":
			allies = _spawn_allied_naval(zone_id, center, radius, hostiles)
	entry["allies"] = allies
	entry["opposition"] = opposition
	_engagements[zone_id] = entry
	_apply_damage_state(zone_id, entry, damage_live)
	EventLogger.log_event("ZONE_ATMOSPHERE", "Register",
		"zone=%s kind=%s hostiles=%d allies=%d opposition=%d live=%s" % [
			zone_id, kind, hostiles.size(), allies.size(), opposition.size(), str(damage_live)])
	var actors := allies.duplicate()
	actors.append_array(opposition)
	return actors


## 注销只拆控制权并返回新增演员；是否立即 free 由 ZoneMission 的可见性撤离铁律裁决。
func retire_zone(zone_id: StringName) -> Array[CombatUnit]:
	if not _engagements.has(zone_id):
		return []
	var entry: Dictionary = _engagements[zone_id]
	var hostiles: Array = entry.get("hostiles", [])
	for value in hostiles:
		var unit := _valid_combat_unit(value)
		if unit == null:
			continue
		if StringName(unit.get_meta(&"zone_atmosphere_zone", &"")) != zone_id:
			continue
		_clear_player_priority(unit)
		unit.remove_meta(CombatUnit.META_AMBIENT_DAMAGE_MULTIPLIER)
		unit.remove_meta(&"zone_atmosphere_zone")
	var allies: Array[CombatUnit] = []
	for value in entry.get("allies", []):
		var ally := _valid_combat_unit(value)
		if ally != null:
			ally.set_meta(CombatUnit.META_AMBIENT_DAMAGE_MULTIPLIER, 0.0)
			allies.append(ally)
	for value in entry.get("opposition", []):
		var actor := _valid_combat_unit(value)
		if actor != null:
			actor.set_meta(CombatUnit.META_AMBIENT_DAMAGE_MULTIPLIER, 0.0)
			allies.append(actor)
	for shell in _ballistic_shells:
		if StringName(shell.get("zone_id", &"")) == zone_id:
			shell["can_damage"] = false
	var prefix := "%s:" % zone_id
	for key in _weapon_ready.keys().duplicate():
		if String(key).begins_with(prefix):
			_weapon_ready.erase(key)
	_engagements.erase(zone_id)
	EventLogger.log_event("ZONE_ATMOSPHERE", "Retire",
		"zone=%s actors=%d" % [zone_id, allies.size()])
	return allies


func retire_all() -> Array[CombatUnit]:
	var allies: Array[CombatUnit] = []
	for zone_value in _engagements.keys().duplicate():
		allies.append_array(retire_zone(StringName(zone_value)))
	return allies


func update(delta: float, player: Aircraft) -> void:
	_update_ballistic_shells(delta)
	_update_impact_flashes(delta)
	_tick_accum += delta
	if _tick_accum < TICK_S:
		return
	var fire_delta := _tick_accum
	_tick_accum = fmod(_tick_accum, TICK_S)
	for zone_value in _engagements.keys().duplicate():
		var zone_id := StringName(zone_value)
		if not _engagements.has(zone_id):
			continue
		var entry: Dictionary = _engagements[zone_id]
		_cleanup_entry(entry)
		var hostiles: Array = entry.get("hostiles", [])
		if hostiles.is_empty() and String(entry.get("kind", "air")) != "ground":
			continue
		var live: bool = bool(entry.get("damage_live", false))
		var center: Vector2 = entry.get("center", Vector2.ZERO)
		if player != null and is_instance_valid(player) and not player.is_destroyed:
			var distance := player.global_position.distance_to(center)
			if live and distance >= DAMAGE_LIVE_EXIT_PX:
				live = false
			elif not live and distance <= DAMAGE_LIVE_ENTER_PX:
				live = true
		if live != bool(entry.get("damage_live", false)):
			entry["damage_live"] = live
			_apply_damage_state(zone_id, entry, live)
			EventLogger.log_event("ZONE_ATMOSPHERE", "DamageLOD",
				"zone=%s live=%s" % [zone_id, str(live)])
		_update_player_priority(entry, player, live)
		match String(entry.get("kind", "air")):
			"ground":
				_update_ground_fire(zone_id, entry, fire_delta)
			"naval":
				_update_naval_fire(zone_id, entry, fire_delta)
		_engagements[zone_id] = entry


func active_zone_count() -> int:
	return _engagements.size()


func actor_count(zone_id: StringName = &"") -> int:
	var count := 0
	for zid in _engagements:
		if zone_id != &"" and StringName(zid) != zone_id:
			continue
		var entry: Dictionary = _engagements[zid]
		for value in entry.get("allies", []):
			if _live_combat_unit(value) != null:
				count += 1
		for value in entry.get("opposition", []):
			if _live_combat_unit(value) != null:
				count += 1
	return count


## 返回战区里第一辆真实存活友军气氛单位；完成无线电必须在 retire_zone 前快照它。
func first_live_ally(zone_id: StringName) -> CombatUnit:
	if not _engagements.has(zone_id):
		return null
	var entry: Dictionary = _engagements[zone_id]
	for value in entry.get("allies", []):
		var ally := _live_combat_unit(value)
		if ally != null:
			return ally
	return null


func terrain_violation_count() -> int:
	var violations := 0
	for entry_value in _engagements.values():
		var entry: Dictionary = entry_value
		var actors: Array = entry.get("allies", []).duplicate()
		actors.append_array(entry.get("opposition", []))
		for value in actors:
			var unit := _valid_combat_unit(value)
			if unit == null:
				continue
			if unit is NavalUnit and MapGeography.is_on_land((unit as NavalUnit).global_position):
				violations += 1
			elif unit is GroundUnit and not MapGeography.is_ground_spawn_safe((unit as GroundUnit).global_position):
				violations += 1
	return violations


func _kind_for_mission(mission_type: String) -> String:
	if mission_type == "naval":
		return "naval"
	if mission_type == "ground" or mission_type == "airfield":
		return "ground"
	return "air"


func _player_near(player: Aircraft, center: Vector2, threshold: float) -> bool:
	return player != null and is_instance_valid(player) and not player.is_destroyed \
		and player.global_position.distance_to(center) <= threshold


func _cleanup_entry(entry: Dictionary) -> void:
	var kept_hostiles: Array[CombatUnit] = []
	for value in entry.get("hostiles", []):
		var unit := _live_combat_unit(value)
		if unit != null:
			kept_hostiles.append(unit)
	entry["hostiles"] = kept_hostiles
	var kept_allies: Array[CombatUnit] = []
	for value in entry.get("allies", []):
		var unit := _live_combat_unit(value)
		if unit != null:
			kept_allies.append(unit)
	entry["allies"] = kept_allies
	var kept_opposition: Array[CombatUnit] = []
	for value in entry.get("opposition", []):
		var unit := _live_combat_unit(value)
		if unit != null:
			kept_opposition.append(unit)
	entry["opposition"] = kept_opposition


func _apply_damage_state(zone_id: StringName, entry: Dictionary, live: bool) -> void:
	for value in entry.get("hostiles", []):
		var unit := _valid_combat_unit(value)
		if unit != null:
			unit.set_meta(&"zone_atmosphere_zone", zone_id)
			unit.set_meta(CombatUnit.META_AMBIENT_DAMAGE_MULTIPLIER, 1.0 if live else 0.0)
	for value in entry.get("allies", []):
		var unit := _valid_combat_unit(value)
		if unit != null:
			unit.set_meta(CombatUnit.META_AMBIENT_DAMAGE_MULTIPLIER,
				ALLY_DAMAGE_MULT if live else 0.0)
	for value in entry.get("opposition", []):
		var unit := _valid_combat_unit(value)
		if unit != null:
			unit.set_meta(CombatUnit.META_AMBIENT_DAMAGE_MULTIPLIER,
				1.0 if live else 0.0)


func _update_player_priority(entry: Dictionary, player: Aircraft, live: bool) -> void:
	for value in entry.get("hostiles", []):
		var unit := _valid_combat_unit(value)
		if unit == null:
			continue
		if live and player != null and is_instance_valid(player) and not player.is_destroyed:
			if unit is Aircraft:
				var ai := (unit as Aircraft)._get_ai_controller()
				if ai != null and ai.acquire_target(player, AIController.TargetSource.TS_DIRECTIVE,
						"zone atmosphere player priority"):
					unit.set_meta(&"zone_atmosphere_player_priority", true)
					unit.set_meta(&"zone_atmosphere_player_target_id", player.get_instance_id())
			else:
				unit.set_meta(CombatUnit.META_PREFERRED_COMBAT_TARGET, player)
				unit.set_meta(&"zone_atmosphere_player_priority", true)
		else:
			_clear_player_priority(unit)


func _clear_player_priority(unit: CombatUnit) -> void:
	if not bool(unit.get_meta(&"zone_atmosphere_player_priority", false)):
		return
	if unit is Aircraft:
		var ai := (unit as Aircraft)._get_ai_controller()
		var should_release := false
		var current_value: Variant = (unit as Aircraft).combat_target
		if typeof(current_value) != TYPE_OBJECT or current_value == null \
				or not is_instance_valid(current_value):
			should_release = true
		else:
			should_release = current_value.get_instance_id() == int(unit.get_meta(
				&"zone_atmosphere_player_target_id", -1))
		if ai != null and should_release:
			ai.release_target(AIController.TargetSource.TS_DIRECTIVE,
				"zone atmosphere player left")
	elif unit.has_meta(CombatUnit.META_PREFERRED_COMBAT_TARGET):
		unit.remove_meta(CombatUnit.META_PREFERRED_COMBAT_TARGET)
	unit.remove_meta(&"zone_atmosphere_player_priority")
	if unit.has_meta(&"zone_atmosphere_player_target_id"):
		unit.remove_meta(&"zone_atmosphere_player_target_id")


func _spawn_artillery_group(zone_id: StringName, center: Vector2, radius: float,
		opposing_center: Vector2, team: int, side_label: String) -> Array[CombatUnit]:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(randi()) ^ int(hash("%s:%s:%d" % [zone_id, side_label, team]))
	for count in range(ARTILLERY_COUNT, 0, -1):
		var plan := _find_land_artillery_plan(center, radius, opposing_center, count, rng)
		if plan.is_empty():
			continue
		var out: Array[CombatUnit] = []
		var tracks: Array = plan["tracks"]
		var formation: StringName = plan["formation"]
		var enemy_direction := (opposing_center - center).normalized()
		if enemy_direction.length_squared() < 0.5:
			enemy_direction = Vector2.UP
		for i in range(tracks.size()):
			var track: Dictionary = tracks[i]
			var unit: GroundUnit = ARTILLERY_SCRIPT.new()
			var params := AA_PARAMS.duplicate(true) as AircraftParams
			params.display_name = "SPG"
			params.max_hp = 120.0
			params.radar_range = 0.0
			params.gun = null
			unit.params = params
			unit.team = team
			unit.callsign = "ZONE-%s-%s-SPG-%02d" % [zone_id, side_label, i + 1]
			unit.initial_heading_deg = rad_to_deg(atan2(enemy_direction.x, -enemy_direction.y))
			unit.max_ground_speed = 3.0
			unit.call("configure_ellipse", track["center"], track["axis"],
				track["half_length"], track["half_width"], track["phase"])
			unit.set_meta(&"ambient_slot", i)
			unit.set_meta(&"ambient_formation", formation)
			_mark_actor(unit, zone_id, "artillery")
			_mode.add_child(unit)
			unit.bullet_manager = _spawner.bullet_manager
			unit.missile_manager = _spawner.missile_manager
			out.append(unit)
			_weapon_ready[_weapon_key(zone_id, "artillery", unit)] = 0.8 + float(i) * 0.7 \
				+ (0.35 if team == CombatUnit.TEAM_HOSTILE else 0.0)
		return out
	return []


func _find_land_artillery_plan(center: Vector2, radius: float, hostile_center: Vector2,
		count: int, rng: RandomNumberGenerator) -> Dictionary:
	var away := (center - hostile_center).normalized()
	if away.length_squared() < 0.5:
		away = Vector2.RIGHT
	var base_angle := away.angle() + rng.randf_range(-ARTILLERY_ROUTE_ANGLE_JITTER_RAD,
		ARTILLERY_ROUTE_ANGLE_JITTER_RAD)
	var offset_radius := minf(radius * rng.randf_range(0.23, 0.34), 760.0)
	var start_step := rng.randi_range(0, 15)
	for ring_mult in [1.0, 0.65, 0.35, 0.0]:
		for candidate in range(16):
			var step := (start_step + candidate) % 16
			var direction := Vector2.from_angle(base_angle + float(step) * TAU / 16.0)
			var route_axis := Vector2(-direction.y, direction.x)
			var lateral := Vector2(-route_axis.y, route_axis.x)
			var base := center + direction * offset_radius * float(ring_mult)
			var formation: StringName = ARTILLERY_FORMATIONS[
				rng.randi_range(0, ARTILLERY_FORMATIONS.size() - 1)]
			var spacing := rng.randf_range(ARTILLERY_SLOT_MIN_PX, ARTILLERY_SLOT_MAX_PX)
			var depth := rng.randf_range(ARTILLERY_DEPTH_MIN_PX, ARTILLERY_DEPTH_MAX_PX)
			var offsets := artillery_formation_offsets(formation, count, spacing, depth)
			var group_phase := rng.randf_range(0.0, TAU)
			var tracks: Array[Dictionary] = []
			var starts: Array[Vector2] = []
			var valid := true
			for i in range(count):
				var offset: Vector2 = offsets[i]
				var track_center := base + route_axis * offset.x + lateral * offset.y \
					+ route_axis * rng.randf_range(-ARTILLERY_JITTER_PX, ARTILLERY_JITTER_PX) \
					+ lateral * rng.randf_range(-ARTILLERY_JITTER_PX, ARTILLERY_JITTER_PX)
				var half_length := rng.randf_range(ARTILLERY_ROUTE_HALF_MIN_PX,
					ARTILLERY_ROUTE_HALF_MAX_PX)
				var half_width := rng.randf_range(ARTILLERY_ROUTE_WIDTH_MIN_PX,
					ARTILLERY_ROUTE_WIDTH_MAX_PX)
				var phase := fposmod(group_phase + float(i) * TAU / maxf(float(count), 1.0) \
					+ rng.randf_range(-ARTILLERY_PHASE_JITTER_RAD, ARTILLERY_PHASE_JITTER_RAD), TAU)
				var start := track_center + route_axis * cos(phase) * half_length \
					+ lateral * sin(phase) * half_width
				if not _land_ellipse_valid(track_center, route_axis, center, radius,
						half_length, half_width) or not _point_clear_of_all(start, starts,
						ARTILLERY_INITIAL_CLEARANCE_PX):
					valid = false
					break
				starts.append(start)
				tracks.append({
					"center": track_center,
					"axis": route_axis,
					"half_length": half_length,
					"half_width": half_width,
					"phase": phase,
				})
			if valid:
				return {"tracks": tracks, "formation": formation}
	return {}


## 返回局部编队偏移：x=轨道长轴纵深，y=轨道横向。只在生成时计算一次。
static func artillery_formation_offsets(formation: StringName, count: int, spacing: float,
		depth: float) -> Array[Vector2]:
	var offsets: Array[Vector2] = []
	if count <= 0:
		return offsets
	if count == 1:
		return [Vector2.ZERO]
	for i in range(count):
		var slot := float(i) - float(count - 1) * 0.5
		match formation:
			&"echelon":
				offsets.append(Vector2(slot * depth, slot * spacing))
			&"wedge":
				if count == 2:
					offsets.append(Vector2(float(i) * depth, slot * spacing))
				else:
					offsets.append(Vector2(absf(slot) * depth, slot * spacing))
			_:
				var stagger := -1.0 if i % 2 == 0 else 1.0
				offsets.append(Vector2(stagger * depth * 0.4, slot * spacing))
	return offsets


static func _point_clear_of_all(point: Vector2, others: Array[Vector2], clearance: float) -> bool:
	for other in others:
		if point.distance_to(other) < clearance:
			return false
	return true


func _land_ellipse_valid(origin: Vector2, route_axis: Vector2, zone_center: Vector2,
		zone_radius: float, half_length: float = 350.0, half_width: float = 45.0) -> bool:
	var lateral := Vector2(-route_axis.y, route_axis.x)
	# 出生点加 16 个椭圆相位；不仅检查端点，避免轨道中段穿水。
	for i in range(16):
		var phase := float(i) * TAU / 16.0
		var pos := origin + route_axis * cos(phase) * half_length \
			+ lateral * sin(phase) * half_width
		if pos.distance_to(zone_center) > zone_radius * 0.9 \
				or not MapGeography.is_ground_spawn_safe(pos):
			return false
	return true


func _spawn_allied_naval(zone_id: StringName, center: Vector2, radius: float,
		hostiles: Array[CombatUnit]) -> Array[CombatUnit]:
	var hostile_center := _average_position(hostiles, center)
	var away := (center - hostile_center).normalized()
	if away.length_squared() < 0.5:
		away = Vector2.RIGHT
	var desired := center + away * minf(radius * 0.22, 700.0)
	var heading := atan2(-away.x, away.y)
	var nudge_radius := minf(radius * 0.24, 800.0)
	var nudges := NavalPlacement.ring_nudges([0.0, nudge_radius * 0.5, nudge_radius])
	var offsets: Array = [NAVAL_WING_OFFSET]
	var placement := NavalPlacement.pick_placement(desired, nudges, NAVAL_PATROL_RADII,
		offsets, heading)
	if int(placement.get("land", -1)) != 0:
		offsets = []
		placement = NavalPlacement.pick_placement(desired, nudges, NAVAL_PATROL_RADII,
			offsets, heading)
	if int(placement.get("land", -1)) != 0:
		return []
	var patrol_center: Vector2 = placement["center"]
	var patrol_radius: float = float(placement["ring"])
	var leader_pos := NavalPlacement.leader_pos(patrol_center, patrol_radius, heading)
	var forward := Vector2(sin(heading), -cos(heading))
	var lateral := Vector2(cos(heading), sin(heading))
	var leader := _spawn_ship(zone_id, DDG_SCRIPT, DDG_PARAMS, leader_pos, heading,
		"ZONE-%s-DDG" % zone_id)
	if leader == null:
		return []
	if patrol_radius > 1.0:
		leader.patrol_center = patrol_center
		leader.patrol_radius = patrol_radius
	leader.set_meta(&"ambient_patrol_center", patrol_center)
	var out: Array[CombatUnit] = [leader]
	if not offsets.is_empty():
		var wing_pos := leader_pos + forward * NAVAL_WING_OFFSET.x + lateral * NAVAL_WING_OFFSET.y
		var wing := _spawn_ship(zone_id, FFG_SCRIPT, FFG_PARAMS, wing_pos, heading,
			"ZONE-%s-FFG" % zone_id)
		if wing != null:
			wing.formation_leader = leader
			wing.formation_offset = NAVAL_WING_OFFSET
			wing.set_meta(&"ambient_patrol_center", patrol_center)
			out.append(wing)
	return out


func _spawn_ship(zone_id: StringName, script: GDScript, base_params: NavalParams,
		pos: Vector2, heading: float, callsign: String) -> NavalUnit:
	var ship := script.new() as NavalUnit
	if ship == null:
		return null
	var params := base_params.duplicate(true) as NavalParams
	params.default_team = CombatUnit.TEAM_ALLY
	ship.params = params
	ship.position = pos
	ship.initial_heading_deg = rad_to_deg(heading)
	_mark_actor(ship, zone_id, "naval")
	_mode.add_child(ship)
	ship.callsign = callsign
	ship.bullet_manager = _spawner.bullet_manager
	ship.missile_manager = _spawner.missile_manager
	# 正式挂点保持关闭；对舰表演由本控制器统一生成低成本弹道。
	ship.set_event_directive(AIDirective.passive())
	_weapon_ready[_weapon_key(zone_id, "naval_gun", ship)] = 0.8 \
		+ float(ship.params.ship_class) * 0.25
	return ship


func _mark_actor(unit: CombatUnit, zone_id: StringName, role: String) -> void:
	unit.add_to_group(ACTOR_GROUP)
	unit.set_meta(&"zone_atmosphere_zone", zone_id)
	unit.set_meta(&"zone_atmosphere_role", role)
	unit.set_meta(&"category", "zone_atmosphere")
	# 气氛演员的敌我身份是编成契约，不得因中弹、机场解放或动态转换机制倒戈。
	unit.set_meta(CombatUnit.META_FACTION_CONVERSION_LOCKED, true)
	unit.set_meta(&"skip_far_cleanup", true)
	unit.set_meta(&"no_kill_reward", true)
	unit.set_meta(&"token_cost", 0)


func _average_position(units: Array[CombatUnit], fallback: Vector2) -> Vector2:
	var total := Vector2.ZERO
	var count := 0
	for unit in units:
		if is_instance_valid(unit) and not unit.is_destroyed:
			total += unit.global_position
			count += 1
	return total / float(count) if count > 0 else fallback


func _update_ground_fire(zone_id: StringName, entry: Dictionary, delta: float) -> void:
	var allies := _units_of_type(entry.get("allies", []), GroundUnit)
	var hostiles := _units_of_type(entry.get("opposition", []), GroundUnit)
	for source_value in allies:
		var source := source_value as GroundUnit
		var target := _nearest_opponent(source, hostiles) as GroundUnit
		if target != null:
			_update_artillery_source(zone_id, source, target, delta, true)
	for source_value in hostiles:
		var source := source_value as GroundUnit
		var target := _nearest_opponent(source, allies) as GroundUnit
		if target != null:
			_update_artillery_source(zone_id, source, target, delta, false)


func _update_artillery_source(zone_id: StringName, source: GroundUnit, target: GroundUnit,
		delta: float, source_is_ally: bool) -> void:
	if not is_instance_valid(source) or source.is_destroyed or not is_instance_valid(target) \
			or target.is_destroyed:
		return
	var to_target := target.global_position - source.global_position
	if source.has_method("set") and "barrel_heading" in source:
		source.set("barrel_heading", atan2(to_target.x, -to_target.y))
	var key := _weapon_key(zone_id, "artillery", source)
	var ready := maxf(float(_weapon_ready.get(key, 0.0)) - delta, 0.0)
	_weapon_ready[key] = ready
	if ready > 0.0 or to_target.length() > ARTILLERY_RANGE_PX:
		return
	_spawn_shell(zone_id, source, target, "artillery", ARTILLERY_SHELL_TIME_S,
		ARTILLERY_DAMAGE, ARTILLERY_AOE_RADIUS_PX, 22.0, source_is_ally,
		bool(_engagements[zone_id].get("damage_live", false)))
	var slot := int(source.get_meta(&"ambient_slot", source.get_instance_id() % 3))
	_weapon_ready[key] = 4.5 + float(slot) * 0.5


func _update_naval_fire(zone_id: StringName, entry: Dictionary, delta: float) -> void:
	var allies := _units_of_type(entry.get("allies", []), NavalUnit)
	var hostiles := _units_of_type(entry.get("hostiles", []), NavalUnit)
	for source_value in allies:
		var source := source_value as NavalUnit
		var target := _nearest_opponent(source, hostiles) as NavalUnit
		if target != null:
			_update_naval_source(zone_id, source, target, delta, true)
	for source_value in hostiles:
		var source := source_value as NavalUnit
		var target := _nearest_opponent(source, allies) as NavalUnit
		if target != null:
			_update_naval_source(zone_id, source, target, delta, false)


func _update_naval_source(zone_id: StringName, source: NavalUnit, target: NavalUnit,
		delta: float, source_is_ally: bool) -> void:
	var key := _weapon_key(zone_id, "naval_gun", source)
	var ready := maxf(float(_weapon_ready.get(key, 0.8)) - delta, 0.0)
	_weapon_ready[key] = ready
	if ready > 0.0:
		return
	_spawn_shell(zone_id, source, target, "naval_gun", NAVAL_GUN_TIME_S,
		NAVAL_GUN_DAMAGE, 0.0, 0.0, source_is_ally,
		bool(_engagements[zone_id].get("damage_live", false)))
	_weapon_ready[key] = 3.0 + float(source.params.ship_class) * 0.8


func _units_of_type(values: Array, expected: Variant) -> Array:
	var out: Array = []
	for value in values:
		var unit := _live_combat_unit(value)
		if unit != null and is_instance_of(unit, expected):
			out.append(unit)
	return out


func _nearest_opponent(source: CombatUnit, candidates: Array) -> CombatUnit:
	var best: CombatUnit = null
	var best_d := INF
	for value in candidates:
		var candidate := _live_combat_unit(value)
		if candidate == null:
			continue
		if not source.is_hostile_to(candidate):
			continue
		var d := source.global_position.distance_squared_to(candidate.global_position)
		if d < best_d:
			best_d = d
			best = candidate
	return best


func _weapon_key(zone_id: StringName, kind: String, source: CombatUnit) -> String:
	return "%s:%s:%d" % [zone_id, kind, source.get_instance_id()]


func _spawn_shell(zone_id: StringName, source: CombatUnit, target: CombatUnit, kind: String,
		duration: float, damage: float, radius_px: float, scatter_px: float,
		source_is_ally: bool, can_damage: bool) -> void:
	var scatter := Vector2.from_angle(randf() * TAU) * randf_range(0.0, scatter_px)
	_ballistic_shells.append({
		"zone_id": zone_id,
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
		"source_is_ally": source_is_ally,
		"can_damage": can_damage,
	})
	EventLogger.log_event("ZONE_ATMOSPHERE", "Fire",
		"zone=%s kind=%s source=%s target=%s live=%s" % [
			zone_id, kind, source.callsign, target.callsign, str(can_damage)])
	_queue_redraw_if_visible()


func _update_ballistic_shells(delta: float) -> void:
	var changed := false
	var removed := false
	for i in range(_ballistic_shells.size() - 1, -1, -1):
		var shell: Dictionary = _ballistic_shells[i]
		shell["age"] = float(shell["age"]) + delta
		changed = true
		if float(shell["age"]) >= float(shell["duration"]):
			_resolve_shell(shell)
			_ballistic_shells.remove_at(i)
			removed = true
	if changed:
		_queue_redraw_if_visible(removed)


func _resolve_shell(shell: Dictionary) -> void:
	var impact_pos: Vector2 = shell["end"]
	if not bool(shell.get("can_damage", false)):
		_add_impact_flash(impact_pos, String(shell["kind"]))
		return
	var target := instance_from_id(int(shell["target_id"])) as CombatUnit
	var source := instance_from_id(int(shell["source_id"])) as CombatUnit
	if target == null or not is_instance_valid(target) or target.is_destroyed \
			or not CombatUnit.teams_hostile(int(shell["source_team"]), target.team):
		_add_impact_flash(impact_pos, String(shell["kind"]))
		return
	if String(shell["kind"]) == "artillery" \
			and target.global_position.distance_to(impact_pos) > float(shell["radius_px"]):
		_add_impact_flash(impact_pos, "artillery")
		return
	impact_pos = target.global_position if String(shell["kind"]) == "naval_gun" else impact_pos
	var formal_target := bool(shell.get("source_is_ally", false)) \
		and target.has_meta(&"zone_mission")
	if formal_target:
		if target is NavalUnit:
			(target as NavalUnit).take_atmosphere_damage_at(float(shell["damage"]), impact_pos)
		else:
			target.take_atmosphere_damage(float(shell["damage"]), source, String(shell["kind"]))
	elif target is NavalUnit:
		if source != null and is_instance_valid(source):
			target.set_meta(&"_pending_attacker", source)
			target.set_meta(&"_last_damage_kind", "naval_gun")
		(target as NavalUnit).take_damage_at(float(shell["damage"]), impact_pos, 1.0, false)
	else:
		target.take_damage(float(shell["damage"]), CombatUnit.safe_attacker(source),
			String(shell["kind"]))
	_add_impact_flash(impact_pos, String(shell["kind"]))


func _add_impact_flash(pos: Vector2, kind: String) -> void:
	_impact_flashes.append({"pos": pos, "kind": kind, "age": 0.0, "duration": 0.8})
	AudioManager.play_sfx_2d("bomb_distant", pos, 4.0)
	_queue_redraw_if_visible()


func _update_impact_flashes(delta: float) -> void:
	if _impact_flashes.is_empty():
		return
	var removed := false
	for i in range(_impact_flashes.size() - 1, -1, -1):
		_impact_flashes[i]["age"] = float(_impact_flashes[i]["age"]) + delta
		if float(_impact_flashes[i]["age"]) >= float(_impact_flashes[i]["duration"]):
			_impact_flashes.remove_at(i)
			removed = true
	_queue_redraw_if_visible(removed)


func _queue_redraw_if_visible(force_clear: bool = false) -> void:
	if force_clear or _mode == null or not is_instance_valid(_mode) \
			or not _mode.has_method("is_world_pos_visible"):
		queue_redraw()
		return
	for shell in _ballistic_shells:
		var t := clampf(float(shell["age"]) / maxf(float(shell["duration"]), 0.01), 0.0, 1.0)
		var pos: Vector2 = Vector2(shell["start"]).lerp(Vector2(shell["end"]), t)
		if _mode.is_world_pos_visible(pos, 40.0):
			queue_redraw()
			return
	for flash in _impact_flashes:
		if _mode.is_world_pos_visible(Vector2(flash["pos"]), 40.0):
			queue_redraw()
			return


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
		draw_line(pos - travel_dir * 4.0, pos, Color.WHITE, 1.0, true)
	for flash in _impact_flashes:
		var t := clampf(float(flash["age"]) / float(flash["duration"]), 0.0, 1.0)
		var pos: Vector2 = flash["pos"]
		var radius := lerpf(8.0, 42.0, t)
		var color := Color(1.0, 0.55, 0.12, (1.0 - t) * 0.85)
		draw_circle(pos, maxf(3.0, radius * 0.28), Color(color.r, color.g, color.b, color.a * 0.35))
		draw_arc(pos, radius, 0.0, TAU, 24, color, 2.0, true)


## Dictionary / Array 会跨帧保留已释放对象；任何类型判断都必须在有效性检查之后。
static func _valid_combat_unit(value: Variant) -> CombatUnit:
	if typeof(value) != TYPE_OBJECT or value == null or not is_instance_valid(value):
		return null
	if not (value is CombatUnit):
		return null
	return value as CombatUnit


static func _live_combat_unit(value: Variant) -> CombatUnit:
	var unit := _valid_combat_unit(value)
	return unit if unit != null and not unit.is_destroyed else null


func _exit_tree() -> void:
	retire_all()
