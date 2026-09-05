class_name LandCarrierBoss
extends BossEncounter

const UNIT_SCRIPT := preload("res://scripts/survivor/land_carrier_unit.gd")
const BASE_PARAMS: AircraftParams = preload("res://resources/aa_gun_params.tres")
const CARRIER_HP := 1800.0
const INITIAL_PARKED := 4
const INITIAL_LAUNCH := 2
const PERIODIC_LAUNCH_S := 120.0
const TOTAL_AIRWING_CAP := 8

var _carrier: Variant = null
var _scene_root: Node = null
var _launch_timer := PERIODIC_LAUNCH_S
var _aircraft_created_total := 0


func spawn(scene_root: Node, _player: Aircraft, bullet_manager: Node2D,
		missile_manager: Node2D, anchor: Vector2 = Vector2.INF) -> void:
	_scene_root = scene_root
	_carrier = UNIT_SCRIPT.new()
	var p := BASE_PARAMS.duplicate(true) as AircraftParams
	p.display_name = "LAND CARRIER"
	p.max_hp = CARRIER_HP
	p.radar_range = 2500.0
	p.radar_half_angle = 180.0
	p.gun = null
	_carrier.params = p
	_carrier.team = CombatUnit.TEAM_HOSTILE
	_carrier.callsign = "BEHEMOTH"
	_carrier.initial_heading_deg = initial_heading_deg
	_carrier.is_mission_target = true
	_carrier.set_meta(&"boss_unit", true)
	_carrier.set_meta(&"skip_far_cleanup", true)
	_carrier.set_meta(&"no_kill_reward", true)
	_carrier.set_meta(&"destruction_class", "large")
	var center := anchor if anchor != Vector2.INF else Vector2(6500.0, 0.0)
	_carrier.configure_patrol(center)
	scene_root.add_child(_carrier)
	_carrier.bullet_manager = bullet_manager
	_carrier.missile_manager = missile_manager
	_carrier.arm_mounts(scene_root, bullet_manager, missile_manager)
	_aircraft_created_total = _carrier.spawn_parked_aircraft(scene_root, INITIAL_PARKED)
	_launch_timer = PERIODIC_LAUNCH_S
	active = true
	hud_visible = false
	EventLogger.log_event("BOSS", "LandCarrierSpawn",
		"hp=%.0f parked=%d" % [CARRIER_HP, _carrier.parked_aircraft_count()])


func engage() -> void:
	if _carrier == null or not is_instance_valid(_carrier):
		return
	_carrier.launch_parked_aircraft(INITIAL_LAUNCH)
	EventLogger.log_event("BOSS", "LandCarrierEngaged", "initial launch=%d" % INITIAL_LAUNCH)


func update(delta: float) -> void:
	var raw: Variant = _carrier
	if typeof(raw) != TYPE_OBJECT or raw == null or not is_instance_valid(raw):
		active = false
		return
	if _carrier.is_destroyed:
		active = false
		return
	_launch_timer -= delta
	if _launch_timer > 0.0 or _aircraft_created_total >= TOTAL_AIRWING_CAP:
		return
	_launch_timer = PERIODIC_LAUNCH_S
	if _carrier.parked_aircraft_count() == 0:
		_aircraft_created_total += _carrier.spawn_parked_aircraft(_scene_root, 1)
	_carrier.launch_parked_aircraft(1)


func get_display_members() -> Array:
	var raw: Variant = _carrier
	if typeof(raw) == TYPE_OBJECT and raw != null and is_instance_valid(raw):
		return [_carrier]
	return []


func get_hud_entries() -> Array[Dictionary]:
	var raw: Variant = _carrier
	if typeof(raw) != TYPE_OBJECT or raw == null or not is_instance_valid(raw):
		return []
	return [{
		"name": "BEHEMOTH",
		"generation": 0,
		"hp": _carrier.hp,
		"max_hp": CARRIER_HP,
		"state": "AIRWING %d" % _carrier.parked_aircraft_count(),
		"altitude": 0.0,
		"seconds": maxf(_launch_timer, 0.0),
	}]


func set_player_ref(_p: Aircraft) -> void:
	# 航母本体与驻机不缓存玩家引用；放飞后由标准 Aircraft AI 自行选敌。
	pass
