class_name Tier3SiegeTank
extends GroundUnit

const CIWS_SCRIPT := preload("res://scripts/survivor/tier3_siege_ciws.gd")
const SAM_SCRIPT := preload("res://scripts/survivor/tier3_siege_sam.gd")
const FLAK_SCRIPT := preload("res://scripts/survivor/tier3_siege_flak.gd")
const AA_BASE_PARAMS: AircraftParams = preload("res://resources/aa_gun_params.tres")
const SAM_BASE_PARAMS: AircraftParams = preload("res://resources/sam_params.tres")
const FLAK_BASE_PARAMS: AircraftParams = preload("res://resources/airburst_aa_params.tres")

## 集中调校值。独立主炮是正式三级威胁，不读取气氛 3/3.6km 伤害 LOD。
const MAIN_GUN_SCAN_S := 1.0
const MAIN_GUN_RANGE_PX := 7000.0
const MAIN_GUN_COOLDOWN_S := 7.0
const MAIN_GUN_FLIGHT_S := 2.2
const MAIN_GUN_SCATTER_PX := 18.0
const MAIN_GUN_DIRECT_RADIUS_PX := 30.0

var zone_id: StringName = &""
var _mounts: Array[CombatUnit] = []
var _main_scan_s: float = 0.0
var _main_cooldown_s: float = 2.5
var _main_target: GroundUnit
var _shell: Dictionary = {}
var _impact_flash_s: float = 0.0
var _threat_enabled: bool = true


func configure(p_zone_id: StringName) -> void:
	zone_id = p_zone_id
	max_ground_speed = 4.0


func arm_mounts(world: Node, bullet_mgr: Node2D, missile_mgr: Node2D) -> void:
	if world == null or not _mounts.is_empty():
		return
	_spawn_ciws(world, bullet_mgr, Vector2(-25.0, -8.0))
	_spawn_ciws(world, bullet_mgr, Vector2(25.0, -8.0))
	_spawn_sam(world, missile_mgr, Vector2(0.0, 20.0))
	_spawn_flak(world, bullet_mgr, Vector2(0.0, -25.0))


func _spawn_ciws(world: Node, bullet_mgr: Node2D, offset: Vector2) -> void:
	var mount = CIWS_SCRIPT.new()
	var p := AA_BASE_PARAMS.duplicate(true) as AircraftParams
	p.display_name = "CIWS"
	p.max_hp = 999999.0
	p.radar_range = 0.0
	if p.gun != null:
		p.gun = p.gun.duplicate(true)
		p.gun.max_range = 2600.0
		p.gun.fire_rate = 2000.0
		p.gun.bullet_damage = 3.0
		p.gun.spread_angle = 5.0
		p.gun.max_ammo = 2000
	mount.params = p
	mount.bullet_manager = bullet_mgr
	mount.configure(self, offset)
	world.add_child(mount)
	_mounts.append(mount)


func _spawn_sam(world: Node, missile_mgr: Node2D, offset: Vector2) -> void:
	var mount = SAM_SCRIPT.new()
	var p := SAM_BASE_PARAMS.duplicate(true) as AircraftParams
	p.display_name = "LR-SAM"
	p.max_hp = 999999.0
	p.radar_range = 18000.0
	p.lock_time = 2.8
	if p.missile != null:
		p.missile = p.missile.duplicate(true)
		p.missile.max_range_rear = 32000.0
		p.missile.max_count = 8
		p.missile.cooldown = 7.0
	mount.params = p
	mount.missile_manager = missile_mgr
	mount.configure(self, offset)
	world.add_child(mount)
	_mounts.append(mount)


func _spawn_flak(world: Node, bullet_mgr: Node2D, offset: Vector2) -> void:
	var mount = FLAK_SCRIPT.new()
	var p := FLAK_BASE_PARAMS.duplicate(true) as AircraftParams
	p.display_name = "AIRBURST"
	p.max_hp = 999999.0
	mount.params = p
	mount.bullet_manager = bullet_mgr
	mount.configure(self, offset)
	world.add_child(mount)
	_mounts.append(mount)


func _physics_process_impl(delta: float) -> void:
	super._physics_process_impl(delta)
	if is_destroyed or not _threat_enabled:
		return
	_impact_flash_s = maxf(_impact_flash_s - delta, 0.0)
	if not _shell.is_empty():
		_update_shell(delta)
		return
	_main_cooldown_s = maxf(_main_cooldown_s - delta, 0.0)
	_main_scan_s = maxf(_main_scan_s - delta, 0.0)
	if _main_scan_s <= 0.0:
		_main_scan_s = MAIN_GUN_SCAN_S
		_main_target = _nearest_atmosphere_ground_ally()
	if _main_cooldown_s <= 0.0 and _main_target != null \
			and is_instance_valid(_main_target) and not _main_target.is_destroyed:
		_begin_shell(_main_target)


func _nearest_atmosphere_ground_ally() -> GroundUnit:
	var best: GroundUnit = null
	var best_d := MAIN_GUN_RANGE_PX
	for unit in CombatUnit.all_units:
		if unit == null or not is_instance_valid(unit) or not (unit is GroundUnit) \
				or unit.is_destroyed or unit.team != CombatUnit.TEAM_ALLY:
			continue
		if String(unit.get_meta(&"zone_atmosphere_role", "")) == "" \
				or StringName(unit.get_meta(&"zone_atmosphere_zone", &"")) != zone_id:
			continue
		var d := global_position.distance_to(unit.global_position)
		if d < best_d:
			best_d = d
			best = unit as GroundUnit
	return best


func _begin_shell(target: GroundUnit) -> void:
	var target_snapshot := target.global_position
	var to_target := target_snapshot - global_position
	if to_target.length() > MAIN_GUN_RANGE_PX or to_target.length_squared() < 1.0:
		return
	var lateral := Vector2(-to_target.normalized().y, to_target.normalized().x)
	var impact := target_snapshot + lateral * randf_range(-MAIN_GUN_SCATTER_PX,
		MAIN_GUN_SCATTER_PX)
	_shell = {
		"start": global_position,
		"end": impact,
		"age": 0.0,
		"duration": MAIN_GUN_FLIGHT_S,
		"target_id": target.get_instance_id(),
	}
	_main_cooldown_s = MAIN_GUN_COOLDOWN_S
	EventLogger.log_event("TIER3", "SiegeMainGunFire",
		"zone=%s source=%s target=%s" % [zone_id, callsign, target.callsign])


func _update_shell(delta: float) -> void:
	_shell["age"] = float(_shell["age"]) + delta
	if float(_shell["age"]) < float(_shell["duration"]):
		return
	var impact: Vector2 = _shell["end"]
	var raw_target: Variant = instance_from_id(int(_shell["target_id"]))
	if typeof(raw_target) == TYPE_OBJECT and raw_target != null and is_instance_valid(raw_target) \
			and raw_target is GroundUnit and not (raw_target as GroundUnit).is_destroyed:
		var target := raw_target as GroundUnit
		if target.global_position.distance_to(impact) <= MAIN_GUN_DIRECT_RADIUS_PX:
			target.take_damage(maxf(target.hp, 1.0) + 1.0, self, "artillery")
			EventLogger.log_event("TIER3", "SiegeMainGunHit",
				"zone=%s target=%s lethal=true" % [zone_id, target.callsign])
	_shell.clear()
	_impact_flash_s = 0.8


func cease_tier3_threat() -> void:
	_threat_enabled = false
	_shell.clear()
	_main_target = null
	for mount in _mounts:
		if mount != null and is_instance_valid(mount):
			mount.queue_free()
	_mounts.clear()
	queue_redraw()


func _start_destroy() -> void:
	cease_tier3_threat()
	super._start_destroy()


func _draw_ground_icon() -> void:
	var color := Color(0.92, 0.31, 0.12)
	draw_rect(Rect2(-35.0, -24.0, 70.0, 48.0), color.darkened(0.55), true)
	draw_rect(Rect2(-35.0, -24.0, 70.0, 48.0), color, false, 2.0)
	for x in [-25.0, -8.0, 8.0, 25.0]:
		draw_circle(Vector2(x, 22.0), 6.0, Color(0.16, 0.18, 0.20))
	draw_circle(Vector2.ZERO, 16.0, color.darkened(0.25))
	draw_line(Vector2.ZERO, Vector2(0.0, -44.0), color.lightened(0.3), 7.0)
	# 四个挂点的机位标记：左右 CIWS、后 SAM、前空爆。
	draw_circle(Vector2(-25.0, -8.0), 4.0, Color.WHITE)
	draw_circle(Vector2(25.0, -8.0), 4.0, Color.WHITE)
	draw_rect(Rect2(-4.0, 16.0, 8.0, 8.0), Color(1.0, 0.32, 0.14), true)
	draw_arc(Vector2(0.0, -25.0), 5.0, 0.0, TAU, 12, Color(0.72, 0.86, 1.0), 1.5)


func _draw_impl() -> void:
	super._draw_impl()
	if not _shell.is_empty():
		var start := to_local(Vector2(_shell["start"]))
		var end := to_local(Vector2(_shell["end"]))
		var t := clampf(float(_shell["age"]) / maxf(float(_shell["duration"]), 0.01), 0.0, 1.0)
		var projectile := start.lerp(end, t)
		draw_line(start, projectile, Color(1.0, 0.62, 0.18, 0.7), 2.0)
		draw_circle(projectile, 6.0, Color(1.0, 0.82, 0.35))
	if _impact_flash_s > 0.0:
		var alpha := clampf(_impact_flash_s / 0.8, 0.0, 1.0)
		draw_circle(Vector2.ZERO, 28.0 * (1.0 - alpha), Color(1.0, 0.42, 0.12, alpha))
