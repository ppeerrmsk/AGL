class_name HyperABoss
extends BossEncounter

const HyperAThreatOverlayScript = preload("res://scripts/survivor/hyper_a_threat_overlay.gd")

## Black Star / Hyper-A：双根、三次二分、集中式特殊行为编排。
## 所有特殊状态由本 encounter 一次更新；每架飞机只保留共享 Aircraft/AIController 循环。

const PARAM_PATHS: Array[String] = [
	"res://resources/enemy_hyper_a_g0.tres",
	"res://resources/enemy_hyper_a_g1.tres",
	"res://resources/enemy_hyper_a_g2.tres",
	"res://resources/enemy_hyper_a_g3.tres",
]

const COMBAT_ALTITUDE := 5500.0
const DESCENT_START_ALTITUDE := 30000.0
const HIDE_ALTITUDE := 15000.0
const DESCENT_DURATION := 4.0
const SECOND_ROOT_DELAY := 18.0
const REENTRY_COOLDOWN := 40.0
const REENTRY_COOLDOWN_JITTER := 10.0
const REENTRY_QUEUE_SPACING := 12.0
const CLIMB_DURATION := 2.5
const HIGH_ALTITUDE_HOLD_MIN := 7.0
const HIGH_ALTITUDE_HOLD_MAX := 10.0
const SPLIT_DELAY := 0.65
const CHILD_SEPARATION_PX := 160.0
const CHILD_HEADING_OFFSET := deg_to_rad(18.0)
const CHILD_GUARD_DURATION := 0.8

const DASH_TELEGRAPH_DURATION := 2.4
const DASH_ALIGN_TIMEOUT := 12.0
const DASH_ALIGN_TOLERANCE := deg_to_rad(6.0)
const DASH_CHARGE_CRUISE_MULT := 0.45
const DASH_CHARGE_STALL_MULT := 1.35
const DASH_CHARGE_SPEED_CAP_KMH := 600.0
const DASH_DURATION := 1.2
const DASH_DISTANCE_PX := 3200.0
const DASH_WIDTH_PX := 140.0 * CombatUnit.PIXELS_PER_METER
const DASH_DAMAGE := 55.0
const BRAKE_SHOCKWAVE_RADIUS_M := 900.0
const BRAKE_SHOCKWAVE_RADIUS_PX := BRAKE_SHOCKWAVE_RADIUS_M * CombatUnit.PIXELS_PER_METER
const BRAKE_SHOCKWAVE_HALF_ANGLE := deg_to_rad(55.0)
const BRAKE_SHOCKWAVE_DAMAGE := 45.0
const BRAKE_SHOCKWAVE_VISUAL_DURATION := 0.65
const POST_DASH_DELAY := 1.2
const COOLDOWN_APPROACH_DISTANCE_PX := 700.0
const COOLDOWN_APPROACH_MAX := 5.0
const COOLDOWN_DURATION := 6.0
const MAX_CONCURRENT_DASH := 2
const ROCKETS_PER_SIDE := 5
const ROCKET_DAMAGE := 24.0
const ROCKET_SPEED_MS := 420.0
const ROCKET_RANGE_M := 2400.0

const ROOT_AOE_RADIUS_M := 1200.0
const ROOT_AOE_DAMAGE := 60.0
const REENTRY_RADIUS_M: Array[float] = [0.0, 900.0, 700.0, 0.0]
const REENTRY_DAMAGE: Array[float] = [0.0, 50.0, 40.0, 0.0]
const LOCK_CAPACITY: Array[int] = [8, 4, 2, 1]
const FIRST_DASH_DELAY: Array[float] = [9.0, 8.0, 7.0, 0.0]
const DASH_COOLDOWN: Array[float] = [12.0, 10.0, 9.0, 0.0]
const META_SATURATION_SALVO: StringName = &"hyper_a_saturation_salvo"
const META_G0_OMNIDIRECTIONAL_SALVO: StringName = &"hyper_a_g0_omnidirectional_salvo"
const META_WEAPONS_ENABLED: StringName = &"hyper_a_weapons_enabled"
const META_FORCE_HIDDEN_VISUAL: StringName = &"force_hidden_visual"

const STATE_STAGED := "STAGED"
const STATE_DESCENT := "DESCENT"
const STATE_FIGHTER := "FIGHTER"
const STATE_CLIMB := "CLIMB"
const STATE_HIGH_ALTITUDE_HOLD := "HIGH_ALTITUDE_HOLD"
const STATE_TELEGRAPH := "TELEGRAPH"
const STATE_DASH := "DASH"
const STATE_POST_DASH := "POST_DASH"
const STATE_COOLDOWN_POSITIONING := "COOLDOWN_POSITIONING"
const STATE_COOLDOWN := "COOLDOWN"

var _scene_root: Node = null
var _aircraft_scene: PackedScene = null
var _player: Aircraft = null
var _bullet_mgr: BulletManager = null
var _missile_mgr: MissileManager = null
var _overlay = null

## instance_id → 运行时记录。记录中的 ac 必须先做 Variant 有效性净化再强转。
var _records: Dictionary = {}
var _pending_splits: Array[Dictionary] = []
var _flashes: Array[Dictionary] = []
var _engaged: bool = false
var _pending_roots: int = 2
var _roots_arrived: int = 0
var _second_root_timer: float = -1.0
var _terminal_g3_defeated: int = 0
var _expected_terminal_g3: int = 16
var _root_b_started: bool = false
var _debug_scenario: String = "full"
var _last_update_frame: int = -1


func _init() -> void:
	display_name = "BLACK STAR // HYPER-A"
	callsign_prefix = "HYPER-A"
	bgm_track = "boss"


func configure_debug_scenario(scenario: String) -> void:
	_debug_scenario = scenario if not scenario.is_empty() else "full"


func spawn(scene_root: Node, aircraft_scene: PackedScene, _create_enemy_func: Callable,
		player: Aircraft, bullet_mgr: BulletManager, missile_mgr: MissileManager,
		_squads: Array[Squad], anchor: Vector2 = Vector2.INF) -> void:
	if active or scene_root == null or aircraft_scene == null:
		return
	_scene_root = scene_root
	_aircraft_scene = aircraft_scene
	_player = player
	_bullet_mgr = bullet_mgr
	_missile_mgr = missile_mgr
	active = true
	var spawn_pos := anchor if anchor != Vector2.INF else (
		_player.global_position + Vector2.UP * 2200.0 if _player else Vector2.ZERO)
	_overlay = HyperAThreatOverlayScript.new()
	_overlay.name = "HyperAThreatOverlay"
	_scene_root.add_child(_overlay)
	var staged := _spawn_body(0, "Hyper-A1", 1, spawn_pos,
		deg_to_rad(initial_heading_deg), false)
	if staged.is_empty():
		active = false
		return
	_set_hidden(staged, true)
	staged["state"] = STATE_STAGED


func engage() -> void:
	_engaged = true
	if _debug_scenario == "full":
		var root_a := _record_by_path("Hyper-A1")
		if not root_a.is_empty():
			_begin_descent(root_a, true)
	else:
		_apply_debug_start()


func update(delta: float) -> void:
	if not active:
		return
	# Event 与 Spawner 都可能在同一物理帧推进 encounter；本 BOSS 的秒表必须只走一次。
	var frame := Engine.get_physics_frames()
	if frame == _last_update_frame:
		return
	_last_update_frame = frame
	_update_flashes(delta)
	if not _engaged:
		_sync_overlay()
		return

	if _second_root_timer >= 0.0 and not _root_b_started:
		_second_root_timer -= delta
		if _second_root_timer <= 0.0:
			_start_second_root()

	var remove_ids: Array[int] = []
	for key in _records.keys():
		var record: Dictionary = _records[key]
		var ac := _aircraft_from(record)
		if ac == null:
			remove_ids.append(int(key))
			continue
		if ac.is_destroyed:
			_handle_body_defeated(record)
			remove_ids.append(int(key))
			continue
		_update_spawn_guard(record, delta)
		_update_body(record, ac, delta)
	for id in remove_ids:
		_records.erase(id)

	_update_pending_splits(delta)
	_sync_overlay()
	_check_victory()


func set_player_ref(p: Aircraft) -> void:
	_player = p


func get_display_members() -> Array:
	var out: Array = []
	for record in _sorted_records():
		var ac := _aircraft_from(record)
		if ac != null and not ac.is_destroyed:
			out.append(ac)
	return out


## SurvivorHUD 的通用自定义 BOSS 条目协议。
func get_hud_entries() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for record in _sorted_records():
		var ac := _aircraft_from(record)
		if ac == null or ac.is_destroyed:
			continue
		out.append({
			"name": String(record.get("path", ac.callsign)),
			"generation": int(record.get("generation", 0)),
			"hp": ac.hp,
			"max_hp": ac.params.max_hp if ac.params else 1.0,
			"state": _hud_state(record, ac),
			"altitude": ac.altitude,
			"seconds": maxf(float(record.get("timer", 0.0)), 0.0),
		})
	return out


func generation_counts() -> PackedInt32Array:
	var counts := PackedInt32Array([0, 0, 0, 0])
	for record in _records.values():
		var ac := _aircraft_from(record)
		if ac != null and not ac.is_destroyed:
			var generation: int = int(record.get("generation", 0))
			counts[generation] += 1
	return counts


func pending_split_count() -> int:
	return _pending_splits.size()


func terminal_defeated_count() -> int:
	return _terminal_g3_defeated


func _spawn_body(generation: int, path: String, root_index: int, pos: Vector2,
		heading: float, combat_enabled: bool = true) -> Dictionary:
	if generation < 0 or generation >= PARAM_PATHS.size():
		return {}
	var base := load(PARAM_PATHS[generation]) as AircraftParams
	if base == null:
		push_error("HyperABoss: missing params %s" % PARAM_PATHS[generation])
		return {}
	var p := base.duplicate(true) as AircraftParams
	if p.combat:
		p.combat = p.combat.duplicate()
	var ac := _aircraft_scene.instantiate() as Aircraft
	if ac == null:
		return {}
	ac.params = p
	ac.team = CombatUnit.TEAM_HOSTILE
	ac.position = pos
	ac.initial_heading_deg = rad_to_deg(heading)
	ac.altitude = COMBAT_ALTITUDE
	ac.flat_altitude = true
	ac.set_target_tier(CombatUnit.AltitudeTier.MID)
	ac.infinite_fuel = true
	ac.infinite_ammo = false
	ac.enable_missile_reload = true
	ac.missile_reload_duration = 20.0
	ac.enable_gun_reload = true
	ac.gun_reload_duration = 20.0
	ac.max_simultaneous_locks = LOCK_CAPACITY[generation]
	ac.is_mission_target = true
	ac.no_pilot = true
	ac.callsign = path
	ac.bullet_manager = _bullet_mgr
	ac.missile_manager = _missile_mgr
	ac.set_meta("enemy_type", "hyper_a")
	ac.set_meta("category", "boss")
	ac.set_meta("skip_far_cleanup", true)
	ac.set_meta("no_kill_reward", true)
	ac.set_meta("silhouette", "hyper_a")
	ac.set_meta("hyper_a_generation", generation)
	ac.set_meta("saturation_attacker", true)
	ac.set_meta(META_SATURATION_SALVO, true)
	ac.set_meta(&"fear_immune", true)
	if generation == 0:
		ac.set_meta(META_G0_OMNIDIRECTIONAL_SALVO, true)
	ac.set_meta(META_WEAPONS_ENABLED, combat_enabled)
	_scene_root.add_child(ac)

	var ai := AIController.new()
	ai.name = "AIController"
	ai.aircraft = ac
	ai.patrol_altitude = COMBAT_ALTITUDE
	ai.enable_combat = combat_enabled
	ai.evade_missiles = generation >= 2
	ai.aggression = [1.0, 0.94, 0.88, 0.82][generation]
	ai.engage_cooldown = [0.5, 0.8, 1.0, 1.2][generation]
	ai.engage_duration = 999.0
	ai.skill_level = [0.96, 0.90, 0.84, 0.76][generation]
	ai.composure = [0.95, 0.90, 0.84, 0.76][generation]
	ai.focus = [1.0, 0.94, 0.88, 0.80][generation]
	ai.self_preservation = [0.15, 0.22, 0.30, 0.38][generation]
	ai.situational_awareness = [1.0, 0.95, 0.88, 0.80][generation]
	var center := _player.global_position if _valid_player() else pos
	ai.waypoints = PackedVector2Array([
		center + Vector2(1200, -1200), center + Vector2(1200, 1200),
		center + Vector2(-1200, 1200), center + Vector2(-1200, -1200),
	])
	ac.add_child(ai)
	ac.use_tactical_planner = true
	ac.invulnerable = true

	var record := {
		"ac": ac,
		"generation": generation,
		"path": path,
		"root": root_index,
		"state": STATE_FIGHTER,
		"timer": 0.0,
		"special_cd": FIRST_DASH_DELAY[generation] + randf_range(0.0, 2.5),
		"reentry_cd": REENTRY_COOLDOWN + randf_range(0.0, REENTRY_COOLDOWN_JITTER),
		"spawn_guard": CHILD_GUARD_DURATION,
		"guard_owned": true,
		"death_handled": false,
		"rockets_fired": false,
		"dash_hits": {},
	}
	_records[ac.get_instance_id()] = record
	if not combat_enabled:
		_set_combat(record, false)
	return record


func _update_body(record: Dictionary, ac: Aircraft, delta: float) -> void:
	var state: String = String(record.get("state", STATE_FIGHTER))
	match state:
		STATE_DESCENT:
			_update_descent(record, ac, delta)
		STATE_CLIMB:
			_update_climb(record, ac, delta)
		STATE_HIGH_ALTITUDE_HOLD:
			_update_high_altitude_hold(record, ac, delta)
		STATE_TELEGRAPH:
			_update_telegraph(record, ac, delta)
		STATE_DASH:
			_update_dash(record, ac, delta)
		STATE_POST_DASH:
			record["timer"] = float(record["timer"]) - delta
			if float(record["timer"]) <= 0.0:
				_enter_cooldown_positioning(record, ac)
		STATE_COOLDOWN_POSITIONING:
			_update_cooldown_positioning(record, ac, delta)
		STATE_COOLDOWN:
			record["timer"] = float(record["timer"]) - delta
			if float(record["timer"]) <= 0.0:
				_enter_fighter(record, ac)
		STATE_FIGHTER:
			_update_fighter(record, ac, delta)


func _update_fighter(record: Dictionary, ac: Aircraft, delta: float) -> void:
	var generation: int = int(record["generation"])
	if generation >= 3:
		return
	record["special_cd"] = float(record["special_cd"]) - delta
	if generation in [1, 2]:
		# 另一架占用高空序列时暂停本机倒计时，避免多分裂体排队连续轰炸。
		if not _has_active_descent():
			record["reentry_cd"] = float(record["reentry_cd"]) - delta
			if float(record["reentry_cd"]) <= 0.0:
				_begin_climb(record, ac)
				return
	if float(record["special_cd"]) <= 0.0 and _dash_slot_count() < MAX_CONCURRENT_DASH \
			and not _has_active_descent():
		_begin_dash_telegraph(record, ac)


func _begin_descent(record: Dictionary, root_arrival: bool) -> void:
	var ac := _aircraft_from(record)
	if ac == null:
		return
	record["state"] = STATE_DESCENT
	record["timer"] = DESCENT_DURATION
	record["root_arrival"] = root_arrival
	record["aoe_center"] = _player.global_position if _valid_player() else ac.global_position
	var generation: int = int(record["generation"])
	var radius_m := ROOT_AOE_RADIUS_M if root_arrival else REENTRY_RADIUS_M[generation]
	record["aoe_radius_px"] = radius_m * CombatUnit.PIXELS_PER_METER
	record["aoe_damage"] = ROOT_AOE_DAMAGE if root_arrival else REENTRY_DAMAGE[generation]
	ac.global_position = record["aoe_center"]
	ac.altitude = DESCENT_START_ALTITUDE
	_set_hidden(record, true)
	_set_combat(record, false)


func _update_descent(record: Dictionary, ac: Aircraft, delta: float) -> void:
	record["timer"] = float(record["timer"]) - delta
	var ratio := clampf(1.0 - float(record["timer"]) / DESCENT_DURATION, 0.0, 1.0)
	ac.altitude = lerpf(DESCENT_START_ALTITUDE, COMBAT_ALTITUDE, ratio)
	ac.global_position = record.get("aoe_center", ac.global_position)
	if float(record["timer"]) > 0.0:
		return
	var center: Vector2 = record.get("aoe_center", ac.global_position)
	var radius_px: float = float(record.get("aoe_radius_px", 0.0))
	_apply_aoe(ac, center, radius_px, float(record.get("aoe_damage", 0.0)))
	_add_flash(center, radius_px)
	_set_hidden(record, false)
	ac.global_position = center
	ac.altitude = COMBAT_ALTITUDE
	_enter_fighter(record, ac)
	if bool(record.get("root_arrival", false)):
		_pending_roots = maxi(_pending_roots - 1, 0)
		_roots_arrived += 1
		if int(record.get("root", 1)) == 1 and not _root_b_started:
			_second_root_timer = SECOND_ROOT_DELAY
	else:
		record["reentry_cd"] = REENTRY_COOLDOWN \
			+ randf_range(0.0, REENTRY_COOLDOWN_JITTER)
	EventLogger.log_event("BOSS", String(record["path"]),
		"atmospheric impact radius=%.0fm damage=%.0f" % [
			radius_px / CombatUnit.PIXELS_PER_METER, float(record.get("aoe_damage", 0.0))])


func _begin_climb(record: Dictionary, ac: Aircraft) -> void:
	record["state"] = STATE_CLIMB
	record["timer"] = CLIMB_DURATION
	record["climb_start_altitude"] = ac.altitude
	_stagger_other_reentries(record)
	_set_combat(record, false)
	ac.target_speed_kmh = ac.params.cruise_speed if ac.params else 1200.0


func _update_climb(record: Dictionary, ac: Aircraft, delta: float) -> void:
	record["timer"] = float(record["timer"]) - delta
	var ratio := clampf(1.0 - float(record["timer"]) / CLIMB_DURATION, 0.0, 1.0)
	ac.altitude = lerpf(float(record.get("climb_start_altitude", COMBAT_ALTITUDE)),
		DESCENT_START_ALTITUDE, ratio)
	if ac.altitude >= HIDE_ALTITUDE and ac.visible:
		_set_hidden(record, true)
	if float(record["timer"]) <= 0.0:
		_begin_high_altitude_hold(record, ac)


func _begin_high_altitude_hold(record: Dictionary, ac: Aircraft) -> void:
	record["state"] = STATE_HIGH_ALTITUDE_HOLD
	record["timer"] = randf_range(HIGH_ALTITUDE_HOLD_MIN, HIGH_ALTITUDE_HOLD_MAX)
	ac.altitude = DESCENT_START_ALTITUDE
	ac.target_position = Vector2.INF
	_set_hidden(record, true)
	_set_combat(record, false)
	EventLogger.log_event("BOSS", String(record["path"]),
		"high altitude hold %.1fs before dive" % float(record["timer"]))


func _stagger_other_reentries(active_record: Dictionary) -> void:
	var active_path := String(active_record.get("path", ""))
	for raw_record in _records.values():
		var other: Dictionary = raw_record
		if String(other.get("path", "")) == active_path:
			continue
		if int(other.get("generation", 0)) not in [1, 2] \
				or String(other.get("state", "")) != STATE_FIGHTER:
			continue
		other["reentry_cd"] = maxf(float(other.get("reentry_cd", 0.0)),
			REENTRY_QUEUE_SPACING)


func _update_high_altitude_hold(record: Dictionary, _ac: Aircraft, delta: float) -> void:
	record["timer"] = float(record["timer"]) - delta
	if float(record["timer"]) <= 0.0:
		_begin_descent(record, false)


func _begin_dash_telegraph(record: Dictionary, ac: Aircraft) -> void:
	var target_pos := _player.global_position if _valid_player() else ac.global_position + Vector2.UP
	var dir := (target_pos - ac.global_position).normalized()
	if dir.length_squared() < 0.5:
		dir = Vector2(sin(ac.heading), -cos(ac.heading))
	record["state"] = STATE_TELEGRAPH
	record["timer"] = DASH_TELEGRAPH_DURATION
	record["telegraph_elapsed"] = 0.0
	record["dash_from"] = ac.global_position
	record["dash_to"] = ac.global_position + dir * DASH_DISTANCE_PX
	record["dash_dir"] = dir
	var stall_kmh: float = ac.params.stall_speed_base if ac.params else 220.0
	var cruise_kmh: float = ac.params.cruise_speed if ac.params else 1200.0
	record["charge_speed_kmh"] = maxf(stall_kmh * DASH_CHARGE_STALL_MULT,
		minf(cruise_kmh * DASH_CHARGE_CRUISE_MULT, DASH_CHARGE_SPEED_CAP_KMH))
	record["rockets_fired"] = false
	record["dash_hits"] = {}
	record["brake_wave_fired"] = false
	_set_combat(record, false)
	# 蓄力仍走共享飞机物理：减速、可受击，并真实滚转对准锁存攻击线。
	# 禁止归零速度或直接改 heading；背向且 12 秒仍对不准就取消本轮。
	ac.target_position = ac.global_position + dir * DASH_DISTANCE_PX
	ac.target_speed_kmh = float(record["charge_speed_kmh"])
	ac.is_afterburner = false
	EventLogger.log_event("BOSS", String(record["path"]),
		"hyper dash charge nose=%.0f° line=%.0f° speed=%.0fkm/h" % [
			rad_to_deg(ac.heading), rad_to_deg(atan2(dir.x, -dir.y)), ac.speed * 3.6])


func _update_telegraph(record: Dictionary, ac: Aircraft, delta: float) -> void:
	var elapsed: float = float(record.get("telegraph_elapsed", 0.0)) + delta
	record["telegraph_elapsed"] = elapsed
	record["timer"] = maxf(DASH_TELEGRAPH_DURATION - elapsed, 0.0)
	var dir: Vector2 = record.get("dash_dir", Vector2.UP)
	# 飞机在真实转弯中仍会前移，危险线近端必须跟随当前机位；方向保持锁存。
	record["dash_from"] = ac.global_position
	record["dash_to"] = ac.global_position + dir * DASH_DISTANCE_PX
	ac.target_position = record["dash_to"]
	ac.target_speed_kmh = float(record.get("charge_speed_kmh", DASH_CHARGE_SPEED_CAP_KMH))
	ac.is_afterburner = false
	var desired_heading := atan2(dir.x, -dir.y)
	var aligned := absf(angle_difference(ac.heading, desired_heading)) <= DASH_ALIGN_TOLERANCE
	if elapsed < DASH_TELEGRAPH_DURATION or not aligned:
		if elapsed >= DASH_ALIGN_TIMEOUT:
			record["special_cd"] = 3.0
			_enter_fighter(record, ac)
			EventLogger.log_event("BOSS", String(record["path"]),
				"hyper dash cancelled: alignment timeout")
		return
	record["state"] = STATE_DASH
	record["timer"] = DASH_DURATION
	ac.global_position = record["dash_from"]
	ac.target_position = Vector2.INF
	ac.speed = DASH_DISTANCE_PX / CombatUnit.PIXELS_PER_METER / DASH_DURATION
	ac.clear_trail()
	EventLogger.log_event("BOSS", String(record["path"]),
		"hyper dash launch charge=%.1fs align=%.1f°" % [
			elapsed, rad_to_deg(absf(angle_difference(ac.heading, desired_heading)))])


func _update_dash(record: Dictionary, ac: Aircraft, delta: float) -> void:
	var old_pos := ac.global_position
	record["timer"] = float(record["timer"]) - delta
	var ratio := clampf(1.0 - float(record["timer"]) / DASH_DURATION, 0.0, 1.0)
	var new_pos: Vector2 = (record["dash_from"] as Vector2).lerp(record["dash_to"], ratio)
	ac.global_position = new_pos
	ac.speed = DASH_DISTANCE_PX / CombatUnit.PIXELS_PER_METER / DASH_DURATION
	_apply_dash_sweep(record, ac, old_pos, new_pos)
	if ratio >= 0.33 and not bool(record.get("rockets_fired", false)) \
			and int(record["generation"]) <= 1:
		record["rockets_fired"] = true
		_fire_lateral_rockets(record, ac)
	if float(record["timer"]) > 0.0:
		return
	ac.global_position = record["dash_to"]
	_trigger_brake_shockwave(record, ac)
	ac.speed = (ac.params.cruise_speed if ac.params else 1200.0) / 3.6
	ac.target_speed_kmh = ac.params.cruise_speed if ac.params else 1200.0
	record["state"] = STATE_POST_DASH
	record["timer"] = POST_DASH_DELAY
	record["special_cd"] = DASH_COOLDOWN[int(record["generation"])]


func _apply_dash_sweep(record: Dictionary, source: Aircraft, from: Vector2, to: Vector2) -> void:
	var hit_ids: Dictionary = record.get("dash_hits", {})
	for raw in CombatUnit.all_units:
		if typeof(raw) != TYPE_OBJECT or not is_instance_valid(raw):
			continue
		var unit := raw as CombatUnit
		if unit == null or unit.is_destroyed or not source.is_hostile_to(unit):
			continue
		var id := unit.get_instance_id()
		if hit_ids.has(id):
			continue
		if _distance_to_segment(unit.global_position, from, to) <= DASH_WIDTH_PX * 0.5:
			hit_ids[id] = true
			unit.take_damage(DASH_DAMAGE, source, "aoe")
	record["dash_hits"] = hit_ids


func _trigger_brake_shockwave(record: Dictionary, source: Aircraft) -> void:
	if bool(record.get("brake_wave_fired", false)):
		return
	record["brake_wave_fired"] = true
	var center: Vector2 = record.get("dash_to", source.global_position)
	var dir: Vector2 = record.get("dash_dir",
		Vector2(sin(source.heading), -cos(source.heading)))
	dir = dir.normalized()
	var hit_count := 0
	if _debug_scenario == "brake_wave" and _valid_player():
		var player_offset := _player.global_position - center
		EventLogger.log_event("BOSS", String(record.get("path", "Hyper-A")),
			"brake probe d=%.0fm off=%.1f° hostile=%s in_sector=%s" % [
				player_offset.length() / CombatUnit.PIXELS_PER_METER,
				rad_to_deg(dir.angle_to(player_offset.normalized())),
				str(source.is_hostile_to(_player)),
				str(_point_in_sector(_player.global_position, center, dir,
					BRAKE_SHOCKWAVE_RADIUS_PX, BRAKE_SHOCKWAVE_HALF_ANGLE))])
	for raw in CombatUnit.all_units:
		if typeof(raw) != TYPE_OBJECT or not is_instance_valid(raw):
			continue
		var unit := raw as CombatUnit
		if unit == null or unit.is_destroyed or not source.is_hostile_to(unit):
			continue
		if not _point_in_sector(unit.global_position, center, dir,
				BRAKE_SHOCKWAVE_RADIUS_PX, BRAKE_SHOCKWAVE_HALF_ANGLE):
			continue
		unit.take_damage(BRAKE_SHOCKWAVE_DAMAGE, source, "aoe")
		hit_count += 1
	_add_brake_flash(center, dir)
	EventLogger.log_event("BOSS", String(record.get("path", "Hyper-A")),
		"brake shockwave radius=%.0fm arc=%.0f° damage=%.0f hits=%d" % [
			BRAKE_SHOCKWAVE_RADIUS_M, rad_to_deg(BRAKE_SHOCKWAVE_HALF_ANGLE) * 2.0,
			BRAKE_SHOCKWAVE_DAMAGE, hit_count])


func _fire_lateral_rockets(record: Dictionary, ac: Aircraft) -> void:
	if _bullet_mgr == null:
		return
	var dir: Vector2 = record.get("dash_dir", Vector2.UP)
	var side := Vector2(-dir.y, dir.x)
	var friendlies := _living_friendlies()
	for sign_value in [-1.0, 1.0]:
		var target_pos := _side_target(friendlies, ac.global_position, side, sign_value)
		for i in range(ROCKETS_PER_SIDE):
			var offset: Vector2 = side * sign_value * (22.0 + float(i) * 4.0)
			var aim: Vector2 = target_pos + side * sign_value * randf_range(-90.0, 90.0) \
				+ dir * randf_range(-120.0, 120.0)
			var rocket_dir: Vector2 = (aim - (ac.global_position + offset)).normalized()
			var heading := atan2(rocket_dir.x, -rocket_dir.y)
			_bullet_mgr.spawn_rocket(ac.global_position + offset, heading, ROCKET_SPEED_MS,
				ac, ROCKET_DAMAGE, ROCKET_RANGE_M)
	EventLogger.log_event("BOSS", String(record["path"]), "hyper dash rockets 5L + 5R")


func _enter_cooldown_positioning(record: Dictionary, ac: Aircraft) -> void:
	record["state"] = STATE_COOLDOWN_POSITIONING
	record["timer"] = COOLDOWN_APPROACH_MAX
	_set_combat(record, false)


func _update_cooldown_positioning(record: Dictionary, ac: Aircraft, delta: float) -> void:
	record["timer"] = float(record["timer"]) - delta
	if _valid_player():
		ac.target_position = _player.global_position
		ac.target_speed_kmh = ac.params.cruise_speed if ac.params else 1000.0
		if ac.global_position.distance_to(_player.global_position) <= COOLDOWN_APPROACH_DISTANCE_PX:
			_enter_cooldown(record, ac)
			return
	if float(record["timer"]) <= 0.0:
		_enter_cooldown(record, ac)


func _enter_cooldown(record: Dictionary, ac: Aircraft) -> void:
	record["state"] = STATE_COOLDOWN
	record["timer"] = COOLDOWN_DURATION
	# BOSS 主动散热必须绕过未来外部 debuff 免疫，直接写标准状态账本。
	ac.status_effects[StatusEffects.SLOW] = COOLDOWN_DURATION
	ac.status_initial_durations[StatusEffects.SLOW] = COOLDOWN_DURATION
	_set_combat(record, true)
	EventLogger.log_event("BOSS", String(record["path"]), "cooldown SLOW %.1fs" % COOLDOWN_DURATION)


func _enter_fighter(record: Dictionary, ac: Aircraft) -> void:
	record["state"] = STATE_FIGHTER
	record["timer"] = 0.0
	_set_combat(record, true)
	ac.target_position = Vector2.INF


func _handle_body_defeated(record: Dictionary) -> void:
	if bool(record.get("death_handled", false)):
		return
	record["death_handled"] = true
	var generation: int = int(record["generation"])
	var ac := _aircraft_from(record)
	var pos: Vector2 = ac.global_position if ac != null else Vector2.ZERO
	var heading: float = ac.heading if ac != null else 0.0
	_add_flash(pos, 240.0 if generation == 0 else 150.0)
	if generation >= 3:
		_terminal_g3_defeated += 1
		return
	_pending_splits.append({
		"timer": SPLIT_DELAY,
		"generation": generation + 1,
		"path": String(record["path"]),
		"root": int(record["root"]),
		"pos": pos,
		"heading": heading,
	})
	EventLogger.log_event("BOSS", String(record["path"]), "split scheduled G%d→G%d" % [
		generation, generation + 1])


func _update_pending_splits(delta: float) -> void:
	for i in range(_pending_splits.size() - 1, -1, -1):
		var split: Dictionary = _pending_splits[i]
		split["timer"] = float(split["timer"]) - delta
		if float(split["timer"]) > 0.0:
			continue
		var pos: Vector2 = split["pos"]
		var heading: float = float(split["heading"])
		var side := Vector2(cos(heading), sin(heading))
		for child_index in [1, 2]:
			var sign_value := -1.0 if child_index == 1 else 1.0
			var child_heading := heading + CHILD_HEADING_OFFSET * sign_value
			var child := _spawn_body(int(split["generation"]),
				"%s.%d" % [split["path"], child_index],
				int(split["root"]), pos + side * CHILD_SEPARATION_PX * sign_value,
				child_heading, true)
			# G0→G1 首次生成就是一次从不可见高空落下的入场；同帧隐藏，
			# 状态栏 / 危险区先于机体出现，撞击完成后才进入常态战斗。
			if int(split["generation"]) == 1 and not child.is_empty():
				_begin_descent(child, false)
		_pending_splits.remove_at(i)


func _start_second_root() -> void:
	if _root_b_started:
		return
	_root_b_started = true
	var center := _player.global_position if _valid_player() else Vector2.ZERO
	var record := _spawn_body(0, "Hyper-A2", 2, center,
		deg_to_rad(initial_heading_deg + 180.0), false)
	if not record.is_empty():
		_begin_descent(record, true)


func _apply_debug_start() -> void:
	_clear_records_for_debug()
	_pending_roots = 0
	_roots_arrived = 2
	_terminal_g3_defeated = 0
	var center := _player.global_position + Vector2.UP * 1500.0 if _valid_player() else Vector2.ZERO
	match _debug_scenario:
		"g0_weapons":
			_expected_terminal_g3 = 8
			# 置于玩家前方并背向玩家，验证 G0 全向锁定 / 离轴发射；不注入锁定进度。
			var player_fwd := Vector2(sin(_player.heading), -cos(_player.heading)) \
					if _valid_player() else Vector2.UP
			var g0_pos := (_player.global_position + player_fwd * 1600.0) \
					if _valid_player() else center
			var g0_heading := _player.heading if _valid_player() else 0.0
			var g0 := _spawn_body(0, "Hyper-A1", 1, g0_pos, g0_heading, true)
			var g0_ac := _aircraft_from(g0)
			if g0_ac != null and _valid_player():
				# 玩家位于正后方，不注入雷达锁；专项 bench 覆盖真实全向锁定与发射链。
				g0_ac.combat_target = _player
				g0_ac.target_position = _player.global_position
				g0["special_cd"] = 999.0
		"second_root":
			_expected_terminal_g3 = 16
			_pending_roots = 1
			_roots_arrived = 1
			var root_a := _spawn_body(0, "Hyper-A1", 1, center + Vector2.LEFT * 900.0, 0.0, true)
			_enter_fighter(root_a, _aircraft_from(root_a))
			_root_b_started = false
			_second_root_timer = 0.0
		"g1_reentry":
			_expected_terminal_g3 = 4
			var g1 := _spawn_body(1, "Hyper-A1.1", 1, center, 0.0, true)
			_begin_climb(g1, _aircraft_from(g1))
		"g1_weapons":
			_expected_terminal_g3 = 4
			var g1_pos := _player.global_position + Vector2.UP * 2500.0 \
					if _valid_player() else center
			var g1 := _spawn_body(1, "Hyper-A1.1", 1, g1_pos, PI, true)
			var g1_ac := _aircraft_from(g1)
			if g1_ac != null:
				# 拉远并降到安全巡航速度，保证 2.1s 锁定完成前不会掠过玩家；
				# 不注入锁定进度，雷达与发射仍走普通运行时链路。
				g1_ac.use_tactical_planner = false
				var g1_ai := g1_ac.get_node_or_null("AIController") as AIController
				if g1_ai:
					g1_ai.enable_combat = false
					g1_ai.set_process(false)
					g1_ai.set_physics_process(false)
				g1_ac.target_position = _player.global_position if _valid_player() \
						else g1_ac.global_position + Vector2.DOWN * 4000.0
				g1_ac.speed = 600.0 / 3.6
				g1_ac.target_speed_kmh = 600.0
				g1["special_cd"] = 999.0
				g1["reentry_cd"] = 999.0
		"g2_dash":
			_expected_terminal_g3 = 2
			var g2 := _spawn_body(2, "Hyper-A1.1.1", 1, center, 0.0, true)
			_begin_dash_telegraph(g2, _aircraft_from(g2))
		"brake_wave":
			_expected_terminal_g3 = 2
			# 预留扇区半径与蓄力滑行距离，抵消 2.4 秒共享物理蓄力时的前移；
			# 冲刺路径仍停在玩家前方，玩家只会被终点冲击波覆盖。
			var brake_offset := DASH_DISTANCE_PX + BRAKE_SHOCKWAVE_RADIUS_PX * 1.6
			var brake_pos := _player.global_position + Vector2.UP * brake_offset \
					if _valid_player() else center
			var brake := _spawn_body(2, "Hyper-A1.1.1", 1, brake_pos, PI, true)
			_begin_dash_telegraph(brake, _aircraft_from(brake))
		"g3":
			_expected_terminal_g3 = 1
			_spawn_body(3, "Hyper-A1.1.1.1", 1, center, 0.0, true)
		"cooldown":
			_expected_terminal_g3 = 2
			var cool := _spawn_body(2, "Hyper-A1.1.1", 1, center, 0.0, true)
			_enter_cooldown(cool, _aircraft_from(cool))
		"stress_g3":
			_expected_terminal_g3 = 16
			for i in range(16):
				var angle := TAU * float(i) / 16.0
				var stress := _spawn_body(3, "Hyper-S%02d" % (i + 1),
					1 if i < 8 else 2, center + Vector2.from_angle(angle) * 2100.0,
					angle + PI, true)
				stress["spawn_guard"] = 999.0
		_:
			_expected_terminal_g3 = 8
			_spawn_body(0, "Hyper-A1", 1, center, 0.0, true)


func _clear_records_for_debug() -> void:
	for record in _records.values():
		var ac := _aircraft_from(record)
		if ac != null:
			ac.queue_free()
	_records.clear()
	_pending_splits.clear()
	_second_root_timer = -1.0
	_root_b_started = true


func _set_hidden(record: Dictionary, hidden: bool) -> void:
	var ac := _aircraft_from(record)
	if ac == null:
		return
	ac.visible = not hidden
	ac.invulnerable = hidden
	if hidden:
		ac.set_meta(META_FORCE_HIDDEN_VISUAL, true)
		ac.set_meta(&"lock_immune_override", true)
	else:
		ac.remove_meta(META_FORCE_HIDDEN_VISUAL)
		ac.remove_meta(&"lock_immune_override")


func _set_combat(record: Dictionary, enabled: bool) -> void:
	var ac := _aircraft_from(record)
	if ac == null:
		return
	ac.set_meta(META_WEAPONS_ENABLED, enabled)
	var ai := ac.get_node_or_null("AIController") as AIController
	if ai:
		ai.enable_combat = enabled
	if not enabled:
		ac.combat_target = null
		ac.commanded_target = null
		ac.is_firing = false


func _update_spawn_guard(record: Dictionary, delta: float) -> void:
	var remain: float = float(record.get("spawn_guard", 0.0))
	if remain <= 0.0:
		return
	remain -= delta
	record["spawn_guard"] = remain
	var ac := _aircraft_from(record)
	if ac == null:
		return
	if not bool(record.get("guard_owned", false)) and not ac.invulnerable:
		ac.invulnerable = true
		record["guard_owned"] = true
	if remain <= 0.0 and bool(record.get("guard_owned", false)) \
			and String(record.get("state", "")) not in [
				STATE_DESCENT, STATE_HIGH_ALTITUDE_HOLD, STATE_STAGED]:
		ac.invulnerable = false
		record["guard_owned"] = false


func _apply_aoe(source: Aircraft, center: Vector2, radius_px: float, damage: float) -> void:
	if radius_px <= 0.0 or damage <= 0.0:
		return
	for raw in CombatUnit.all_units:
		if typeof(raw) != TYPE_OBJECT or not is_instance_valid(raw):
			continue
		var unit := raw as CombatUnit
		if unit == null or unit.is_destroyed or not source.is_hostile_to(unit):
			continue
		if unit.global_position.distance_to(center) > radius_px:
			continue
		unit.take_damage(damage, source, "aoe")
		var hit_heading: float = unit.heading if unit is Aircraft else 0.0
		ExplosionVFX.emit(_scene_root.get_tree(), unit.global_position, hit_heading, 1.6)


func _add_flash(center: Vector2, radius_px: float) -> void:
	_flashes.append({"kind": "radial", "center": center, "radius_px": radius_px,
		"life": 0.7, "max_life": 0.7})
	if _flashes.size() > 8:
		_flashes.pop_front()


func _add_brake_flash(center: Vector2, dir: Vector2) -> void:
	_flashes.append({
		"kind": "brake_shockwave",
		"center": center,
		"dir": dir,
		"radius_px": BRAKE_SHOCKWAVE_RADIUS_PX,
		"half_angle": BRAKE_SHOCKWAVE_HALF_ANGLE,
		"life": BRAKE_SHOCKWAVE_VISUAL_DURATION,
		"max_life": BRAKE_SHOCKWAVE_VISUAL_DURATION,
	})
	if _flashes.size() > 8:
		_flashes.pop_front()


func _update_flashes(delta: float) -> void:
	for i in range(_flashes.size() - 1, -1, -1):
		_flashes[i]["life"] = float(_flashes[i]["life"]) - delta
		if float(_flashes[i]["life"]) <= 0.0:
			_flashes.remove_at(i)


func _sync_overlay() -> void:
	if _overlay == null or not is_instance_valid(_overlay):
		return
	var aoes: Array = []
	var lines: Array = []
	for record in _records.values():
		var state := String(record.get("state", ""))
		if state == STATE_DESCENT:
			aoes.append({
				"center": record.get("aoe_center", Vector2.ZERO),
				"radius_px": float(record.get("aoe_radius_px", 0.0)),
				"ratio": clampf(1.0 - float(record.get("timer", 0.0)) / DESCENT_DURATION, 0.0, 1.0),
			})
		elif state in [STATE_TELEGRAPH, STATE_DASH]:
			lines.append({
				"from": record.get("dash_from", Vector2.ZERO),
				"to": record.get("dash_to", Vector2.ZERO),
				"dir": record.get("dash_dir", Vector2.UP),
				"width_px": DASH_WIDTH_PX,
				"brake_radius_px": BRAKE_SHOCKWAVE_RADIUS_PX,
				"brake_half_angle": BRAKE_SHOCKWAVE_HALF_ANGLE,
				"progress": 1.0 if state == STATE_DASH else clampf(
					float(record.get("telegraph_elapsed", 0.0)) / DASH_TELEGRAPH_DURATION,
					0.0, 1.0),
			})
	var flashes: Array = []
	for flash in _flashes:
		var snapshot := {
			"kind": flash.get("kind", "radial"),
			"center": flash["center"], "radius_px": flash["radius_px"],
			"ratio": 1.0 - float(flash["life"]) / float(flash["max_life"]),
		}
		if String(flash.get("kind", "radial")) == "brake_shockwave":
			snapshot["dir"] = flash.get("dir", Vector2.UP)
			snapshot["half_angle"] = flash.get("half_angle", BRAKE_SHOCKWAVE_HALF_ANGLE)
		flashes.append(snapshot)
	_overlay.sync(aoes, lines, flashes)


func _check_victory() -> void:
	if _pending_roots > 0 or not _pending_splits.is_empty() or not _records.is_empty():
		return
	if _roots_arrived < 2 or _terminal_g3_defeated < _expected_terminal_g3:
		return
	active = false
	if _overlay and is_instance_valid(_overlay):
		_overlay.queue_free()
	EventLogger.log_event("BOSS", display_name,
		"defeated terminals=%d" % _terminal_g3_defeated)


func _has_active_descent() -> bool:
	for record in _records.values():
		if String(record.get("state", "")) in [
				STATE_CLIMB, STATE_HIGH_ALTITUDE_HOLD, STATE_DESCENT]:
			return true
	return false


func _dash_slot_count() -> int:
	var count := 0
	for record in _records.values():
		if String(record.get("state", "")) in [STATE_TELEGRAPH, STATE_DASH]:
			count += 1
	return count


func _record_by_path(path: String) -> Dictionary:
	for record in _records.values():
		if String(record.get("path", "")) == path:
			return record
	return {}


func _sorted_records() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for record in _records.values():
		out.append(record)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return String(a.get("path", "")) < String(b.get("path", "")))
	return out


func _aircraft_from(record: Dictionary) -> Aircraft:
	var raw: Variant = record.get("ac", null)
	if typeof(raw) != TYPE_OBJECT or not is_instance_valid(raw):
		return null
	return raw as Aircraft


func _valid_player() -> bool:
	return _player != null and is_instance_valid(_player) and not _player.is_destroyed


func _living_friendlies() -> Array[CombatUnit]:
	var out: Array[CombatUnit] = []
	for raw in CombatUnit.all_units:
		if typeof(raw) != TYPE_OBJECT or not is_instance_valid(raw):
			continue
		var unit := raw as CombatUnit
		if unit != null and not unit.is_destroyed and unit.team != CombatUnit.TEAM_HOSTILE:
			out.append(unit)
	return out


func _side_target(friendlies: Array[CombatUnit], origin: Vector2, side: Vector2,
		sign_value: float) -> Vector2:
	var best: CombatUnit = null
	var best_d2 := INF
	for unit in friendlies:
		var rel := unit.global_position - origin
		if rel.dot(side) * sign_value <= 0.0:
			continue
		var d2 := rel.length_squared()
		if d2 < best_d2:
			best_d2 = d2
			best = unit
	if best != null:
		return best.global_position
	if _valid_player():
		return _player.global_position + side * sign_value * 520.0
	return origin + side * sign_value * 900.0


func _hud_state(record: Dictionary, ac: Aircraft) -> String:
	match String(record.get("state", "")):
		STATE_STAGED, STATE_DESCENT:
			return "DESCENT"
		STATE_CLIMB:
			return "CLIMB"
		STATE_HIGH_ALTITUDE_HOLD:
			return "HIGH HOLD"
		STATE_TELEGRAPH:
			return "LOCKED LINE"
		STATE_DASH:
			return "HYPER DASH"
		STATE_POST_DASH, STATE_COOLDOWN_POSITIONING:
			return "VENT APPROACH"
		STATE_COOLDOWN:
			return "SLOW / VENT"
		_:
			return "DOGFIGHT" if int(record.get("generation", 0)) == 3 else "FIGHTER"


static func _distance_to_segment(point: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	if ab.length_squared() <= 0.0001:
		return point.distance_to(a)
	var t := clampf((point - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
	return point.distance_to(a + ab * t)


static func _point_in_sector(point: Vector2, center: Vector2, dir: Vector2,
		radius_px: float, half_angle: float) -> bool:
	var offset := point - center
	var distance_sq := offset.length_squared()
	if radius_px <= 0.0 or distance_sq > radius_px * radius_px:
		return false
	if distance_sq <= 0.0001:
		return true
	var forward := dir.normalized()
	if forward.length_squared() <= 0.5:
		return false
	return offset.normalized().dot(forward) >= cos(half_angle)
