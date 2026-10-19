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
const ORDINARY_ZONE_CHANCE := 0.30
## 当前第三图仍以 preview id 运行；正式毕业时保留该 id 即自动沿用决战全覆盖。
const DECISIVE_MAP_IDS: Array[StringName] = [&"ocean_islands_preview", &"desert_railway_preview"]
const TICK_S := 0.5
const DAMAGE_LIVE_ENTER_PX := 1500.0
const DAMAGE_LIVE_EXIT_PX := 1800.0
const ALLY_DAMAGE_MULT := 0.10
const HELICOPTER_SPAWN_RADIUS_PX := 1100.0
const HELICOPTER_PATROL_RADIUS_PX := 900.0

static func enabled_for_roll(force_all: bool, roll: float) -> bool:
	return force_all or clampf(roll, 0.0, 1.0) < ORDINARY_ZONE_CHANCE

static func cached_enabled(cache: Dictionary, zone_id: StringName, roll: float) -> bool:
	if cache.has(zone_id):
		return bool(cache[zone_id])
	var enabled := enabled_for_roll(false, roll)
	cache[zone_id] = enabled
	return enabled

static func is_decisive_map(map_id: String) -> bool:
	return DECISIVE_MAP_IDS.has(StringName(map_id))

## 四种构图等权：纯地面、仅友军、仅敌军、双方直升机。
static func helicopter_sides_for_roll(roll: float) -> Dictionary:
	var bucket := mini(int(clampf(roll, 0.0, 0.999999) * 4.0), 3)
	return {
		"ally": bucket == 1 or bucket == 3,
		"hostile": bucket == 2 or bucket == 3,
	}

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
const ARTILLERY_HP := 60.0
const ARTILLERY_DAMAGE := 60.0
const ARTILLERY_DIRECT_HIT_RADIUS_PX := 24.0
const ARTILLERY_SCATTER_PX := 80.0

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
## 正式首刷的地面炮兵分片任务：zone_id → {stage, search, hostile_seed}
var _artillery_jobs: Dictionary = {}


func setup(mode: Node, spawner: SurvivorSpawner) -> void:
	_mode = mode
	_spawner = spawner
	set_physics_process(false)


## 返回本次新增的气氛演员，便于 ZoneMission 做诊断与可见性安全撤离。
## deferred=true（正式首刷）：地面战区的友/敌炮兵阵位搜索与生成转入分片任务，由
## advance_pending 按帧预算推进；全局随机数（两组炮兵种子、直升机两侧骰）与直升机生成
## 仍在本调用内按原顺序完成，最终编成与一次性登记逐值相同。返回值只含已生成的演员。
func register_zone(zone_id: StringName, mission_type: String, zone: Dictionary,
		existing_hostiles: Array, player: Aircraft, deferred: bool = false) -> Array[CombatUnit]:
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
	var artillery_job: Dictionary = {}
	match kind:
		"ground":
			# 原顺序的全局随机：友军炮兵种子 → 敌方炮兵种子 → 直升机两侧骰 → 直升机生成。
			# 炮兵阵位只用各自的局部 RNG，搜索与生成可以安全地后移/分片。
			var ally_seed := _artillery_seed(zone_id, "ALLY", CombatUnit.TEAM_ALLY)
			var hostile_seed := _artillery_seed(zone_id, "HOSTILE", CombatUnit.TEAM_HOSTILE)
			var heli_sides := helicopter_sides_for_roll(randf())
			if bool(heli_sides["ally"]):
				var ally_heli := _spawn_atmosphere_helicopter(zone_id, center, radius,
					CombatUnit.TEAM_ALLY, -1.0)
				if ally_heli != null:
					allies.append(ally_heli)
			if bool(heli_sides["hostile"]):
				var hostile_heli := _spawn_atmosphere_helicopter(zone_id, center, radius,
					CombatUnit.TEAM_HOSTILE, 1.0)
				if hostile_heli != null:
					opposition.append(hostile_heli)
			artillery_job = {
				"stage": "ally",
				"search": ArtilleryPlanSearch.new(center, radius,
					_average_position(hostiles, center), ally_seed),
				"hostile_seed": hostile_seed,
			}
		"naval":
			allies = _spawn_allied_naval(zone_id, center, radius, hostiles)
	entry["allies"] = allies
	entry["opposition"] = opposition
	_engagements[zone_id] = entry
	_apply_damage_state(zone_id, entry, damage_live)
	if not artillery_job.is_empty():
		_artillery_jobs[zone_id] = artillery_job
		if not deferred:
			_finish_artillery_job(zone_id)
		return _actors_of(_engagements.get(zone_id, {}))
	_log_register(zone_id, entry)
	return _actors_of(entry)


func _actors_of(entry: Dictionary) -> Array[CombatUnit]:
	var actors: Array[CombatUnit] = []
	for value in entry.get("allies", []):
		actors.append(value)
	for value in entry.get("opposition", []):
		actors.append(value)
	return actors


func _log_register(zone_id: StringName, entry: Dictionary) -> void:
	EventLogger.log_event("ZONE_ATMOSPHERE", "Register",
		"zone=%s kind=%s hostiles=%d allies=%d opposition=%d live=%s" % [
			zone_id, String(entry.get("kind", "")), (entry.get("hostiles", []) as Array).size(),
			(entry.get("allies", []) as Array).size(), (entry.get("opposition", []) as Array).size(),
			str(bool(entry.get("damage_live", false)))])


## 正式首刷的炮兵分片任务是否仍在进行。
func has_pending(zone_id: StringName = &"") -> bool:
	if zone_id == &"":
		return not _artillery_jobs.is_empty()
	return _artillery_jobs.has(zone_id)


## 在截止时刻前推进炮兵分片任务；返回本次新生成的单位数。unit_budget 用尽后不再生成。
func advance_pending(deadline_usec: int, unit_budget: int) -> int:
	var spawned := 0
	for zone_value in _artillery_jobs.keys().duplicate():
		if Time.get_ticks_usec() >= deadline_usec or spawned >= unit_budget:
			break
		spawned += _step_artillery_job(StringName(zone_value), deadline_usec)
	return spawned


## Debug / 专项入口：把某战区（或全部）未完成的炮兵任务一次跑完。
func finish_pending(zone_id: StringName = &"") -> void:
	for zone_value in _artillery_jobs.keys().duplicate():
		if zone_id == &"" or StringName(zone_value) == zone_id:
			_finish_artillery_job(StringName(zone_value))


func _finish_artillery_job(zone_id: StringName) -> void:
	while _artillery_jobs.has(zone_id):
		_step_artillery_job(zone_id, -1)


## 推进一个战区的炮兵任务：先搜友军阵位并生成，再以友军实际位置为对向中心搜敌方阵位。
## 返回本步新生成的单位数；两组都结束后合并进登记并补齐伤害状态。
func _step_artillery_job(zone_id: StringName, deadline_usec: int) -> int:
	var job: Dictionary = _artillery_jobs.get(zone_id, {})
	if job.is_empty() or not _engagements.has(zone_id):
		_artillery_jobs.erase(zone_id)
		return 0
	var search: ArtilleryPlanSearch = job["search"]
	if not search.step(deadline_usec):
		return 0
	var entry: Dictionary = _engagements[zone_id]
	var center: Vector2 = entry["center"]
	var spawned := 0
	if String(job["stage"]) == "ally":
		var ally_artillery := _spawn_artillery_units(zone_id, search.plan, center,
			search.hostile_center, CombatUnit.TEAM_ALLY, "ALLY")
		spawned = ally_artillery.size()
		var allies: Array[CombatUnit] = ally_artillery.duplicate()
		for value in entry.get("allies", []):
			allies.append(value)
		entry["allies"] = allies
		job["stage"] = "hostile"
		job["search"] = ArtilleryPlanSearch.new(center, float(entry["radius"]),
			_average_position(ally_artillery, center), int(job["hostile_seed"]))
		_artillery_jobs[zone_id] = job
	else:
		var hostile_artillery := _spawn_artillery_units(zone_id, search.plan, center,
			search.hostile_center, CombatUnit.TEAM_HOSTILE, "HOSTILE")
		spawned = hostile_artillery.size()
		var opposition: Array[CombatUnit] = hostile_artillery.duplicate()
		for value in entry.get("opposition", []):
			opposition.append(value)
		entry["opposition"] = opposition
		_artillery_jobs.erase(zone_id)
		_apply_damage_state(zone_id, entry, bool(entry.get("damage_live", false)))
		_log_register(zone_id, entry)
	_engagements[zone_id] = entry
	return spawned


## 注销只拆控制权并返回新增演员；是否立即 free 由 ZoneMission 的可见性撤离铁律裁决。
func retire_zone(zone_id: StringName) -> Array[CombatUnit]:
	# 未完成的炮兵分片任务随注销一起作废；已生成的演员照常交回撤离队列。
	_artillery_jobs.erase(zone_id)
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


## 炮兵阵位种子：与原实现相同，消耗一次全局 randi()。
static func _artillery_seed(zone_id: StringName, side_label: String, team: int) -> int:
	return int(randi()) ^ int(hash("%s:%s:%d" % [zone_id, side_label, team]))


func _spawn_artillery_units(zone_id: StringName, plan: Dictionary, center: Vector2,
		opposing_center: Vector2, team: int, side_label: String) -> Array[CombatUnit]:
	var out: Array[CombatUnit] = []
	if plan.is_empty():
		return out
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
		params.max_hp = ARTILLERY_HP
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


func _spawn_atmosphere_helicopter(zone_id: StringName, center: Vector2, radius: float,
		team: int, side: float) -> Aircraft:
	if _spawner == null:
		return null
	var spawn_radius := minf(HELICOPTER_SPAWN_RADIUS_PX, radius * 0.42)
	var spawn_pos := center + Vector2(spawn_radius * side, -spawn_radius * 0.35)
	var to_center := (center - spawn_pos).normalized()
	var heading_deg := rad_to_deg(atan2(to_center.x, -to_center.y))
	var heli := _spawner.spawn_atmosphere_ah64(team, spawn_pos, heading_deg, zone_id,
		center, minf(HELICOPTER_PATROL_RADIUS_PX, radius * 0.35))
	if heli == null:
		return null
	_mark_actor(heli, zone_id, "helicopter", team == CombatUnit.TEAM_HOSTILE)
	return heli


## 炮兵阵位搜索的可分片版本：逐个椭圆采样点推进，局部 RNG 的抽取顺序与一次性穷举完全相同
## （test_zone_atmosphere_combat 对照原实现逐值验证）。step(deadline_usec) 到点即返回，
## deadline_usec < 0 表示一次跑完；finished 后 plan 为 {tracks, formation}，全部数量档无解时为空。
class ArtilleryPlanSearch extends RefCounted:
	const RING_MULTS: Array[float] = [1.0, 0.65, 0.35, 0.0]
	const CANDIDATES := 16
	const ELLIPSE_SAMPLES := 16

	var center: Vector2
	var radius: float
	var hostile_center: Vector2
	var rng := RandomNumberGenerator.new()
	var count := ZoneAtmosphereCombat.ARTILLERY_COUNT
	var finished := false
	var plan: Dictionary = {}
	var _count_ready := false
	var _base_angle := 0.0
	var _offset_radius := 0.0
	var _start_step := 0
	var _ring := 0
	var _candidate := 0
	var _candidate_ready := false
	var _route_axis := Vector2.ZERO
	var _lateral := Vector2.ZERO
	var _base := Vector2.ZERO
	var _formation: StringName = &""
	var _offsets: Array[Vector2] = []
	var _group_phase := 0.0
	var _tracks: Array[Dictionary] = []
	var _starts: Array[Vector2] = []
	var _track_ready := false
	var _track: Dictionary = {}
	var _start := Vector2.ZERO
	var _point := 0

	func _init(p_center: Vector2, p_radius: float, p_hostile_center: Vector2, seed_value: int) -> void:
		center = p_center
		radius = p_radius
		hostile_center = p_hostile_center
		rng.seed = seed_value

	func step(deadline_usec: int) -> bool:
		while not finished:
			_advance()
			if deadline_usec >= 0 and Time.get_ticks_usec() >= deadline_usec:
				break
		return finished

	func _advance() -> void:
		if count < 1:
			finished = true
			return
		if not _count_ready:
			var away := (center - hostile_center).normalized()
			if away.length_squared() < 0.5:
				away = Vector2.RIGHT
			_base_angle = away.angle() + rng.randf_range(
				-ZoneAtmosphereCombat.ARTILLERY_ROUTE_ANGLE_JITTER_RAD,
				ZoneAtmosphereCombat.ARTILLERY_ROUTE_ANGLE_JITTER_RAD)
			_offset_radius = minf(radius * rng.randf_range(0.23, 0.34), 760.0)
			_start_step = rng.randi_range(0, 15)
			_ring = 0
			_candidate = 0
			_candidate_ready = false
			_count_ready = true
			return
		if _ring >= RING_MULTS.size():
			count -= 1
			_count_ready = false
			return
		if not _candidate_ready:
			var step_index := (_start_step + _candidate) % CANDIDATES
			var direction := Vector2.from_angle(_base_angle + float(step_index) * TAU / 16.0)
			_route_axis = Vector2(-direction.y, direction.x)
			_lateral = Vector2(-_route_axis.y, _route_axis.x)
			_base = center + direction * _offset_radius * float(RING_MULTS[_ring])
			_formation = ZoneAtmosphereCombat.ARTILLERY_FORMATIONS[
				rng.randi_range(0, ZoneAtmosphereCombat.ARTILLERY_FORMATIONS.size() - 1)]
			var spacing := rng.randf_range(ZoneAtmosphereCombat.ARTILLERY_SLOT_MIN_PX,
				ZoneAtmosphereCombat.ARTILLERY_SLOT_MAX_PX)
			var depth := rng.randf_range(ZoneAtmosphereCombat.ARTILLERY_DEPTH_MIN_PX,
				ZoneAtmosphereCombat.ARTILLERY_DEPTH_MAX_PX)
			_offsets = ZoneAtmosphereCombat.artillery_formation_offsets(_formation, count, spacing, depth)
			_group_phase = rng.randf_range(0.0, TAU)
			_tracks = []
			_starts = []
			_track_ready = false
			_candidate_ready = true
			return
		if _tracks.size() >= count:
			plan = {"tracks": _tracks, "formation": _formation}
			finished = true
			return
		if not _track_ready:
			var i := _tracks.size()
			var offset: Vector2 = _offsets[i]
			var track_center := _base + _route_axis * offset.x + _lateral * offset.y \
				+ _route_axis * rng.randf_range(-ZoneAtmosphereCombat.ARTILLERY_JITTER_PX,
					ZoneAtmosphereCombat.ARTILLERY_JITTER_PX) \
				+ _lateral * rng.randf_range(-ZoneAtmosphereCombat.ARTILLERY_JITTER_PX,
					ZoneAtmosphereCombat.ARTILLERY_JITTER_PX)
			var half_length := rng.randf_range(ZoneAtmosphereCombat.ARTILLERY_ROUTE_HALF_MIN_PX,
				ZoneAtmosphereCombat.ARTILLERY_ROUTE_HALF_MAX_PX)
			var half_width := rng.randf_range(ZoneAtmosphereCombat.ARTILLERY_ROUTE_WIDTH_MIN_PX,
				ZoneAtmosphereCombat.ARTILLERY_ROUTE_WIDTH_MAX_PX)
			var phase := fposmod(_group_phase + float(i) * TAU / maxf(float(count), 1.0) \
				+ rng.randf_range(-ZoneAtmosphereCombat.ARTILLERY_PHASE_JITTER_RAD,
					ZoneAtmosphereCombat.ARTILLERY_PHASE_JITTER_RAD), TAU)
			_start = track_center + _route_axis * cos(phase) * half_length \
				+ _lateral * sin(phase) * half_width
			_track = {
				"center": track_center,
				"axis": _route_axis,
				"half_length": half_length,
				"half_width": half_width,
				"phase": phase,
			}
			_point = 0
			_track_ready = true
			return
		if _point < ELLIPSE_SAMPLES:
			# 与原 _land_ellipse_valid 同一判定：轨道椭圆 16 个相位逐点验陆地与战区内圈。
			var sample_phase := float(_point) * TAU / 16.0
			var track_center: Vector2 = _track["center"]
			var pos := track_center + _route_axis * cos(sample_phase) * float(_track["half_length"]) \
				+ _lateral * sin(sample_phase) * float(_track["half_width"])
			if pos.distance_to(center) > radius * 0.9 or not MapGeography.is_ground_spawn_safe(pos):
				_next_candidate()
			else:
				_point += 1
			return
		if not ZoneAtmosphereCombat._point_clear_of_all(_start, _starts,
				ZoneAtmosphereCombat.ARTILLERY_INITIAL_CLEARANCE_PX):
			_next_candidate()
			return
		_starts.append(_start)
		_tracks.append(_track)
		_track_ready = false

	func _next_candidate() -> void:
		_candidate += 1
		_candidate_ready = false
		if _candidate >= CANDIDATES:
			_candidate = 0
			_ring += 1


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


func _mark_actor(unit: CombatUnit, zone_id: StringName, role: String,
		rewardable_hostile: bool = false) -> void:
	unit.add_to_group(ACTOR_GROUP)
	unit.set_meta(&"zone_atmosphere_zone", zone_id)
	unit.set_meta(&"zone_atmosphere_role", role)
	unit.set_meta(&"category", "zone_atmosphere")
	# 气氛演员的敌我身份是编成契约，不得因中弹、机场解放或动态转换机制倒戈。
	unit.set_meta(CombatUnit.META_FACTION_CONVERSION_LOCKED, true)
	unit.set_meta(&"skip_far_cleanup", true)
	if rewardable_hostile:
		unit.remove_meta(&"no_kill_reward")
	else:
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
		ARTILLERY_DAMAGE, ARTILLERY_DIRECT_HIT_RADIUS_PX, ARTILLERY_SCATTER_PX, source_is_ally,
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
