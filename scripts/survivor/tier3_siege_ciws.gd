class_name Tier3SiegeCIWS
extends AAGunUnit

var owner_tank: GroundUnit
var local_mount_offset: Vector2 = Vector2.ZERO
var _engaged_missile: Missile
var _acquire_s: float = 0.0
var _fire_s: float = 0.0
var _shot_counter: int = 0

const INTERCEPT_RANGE_PX := 1400.0
const ACQUIRE_INTERVAL_S := 0.15
const FIRE_INTERVAL_S := 0.03
const BULLET_SPEED_MS := 900.0
const REAL_BULLET_CYCLE := 2
const INTERCEPT_DAMAGE := 10.0
const MISSILE_SPREAD_RAD := deg_to_rad(5.0)

func configure(owner: GroundUnit, offset: Vector2) -> void:
	owner_tank = owner
	local_mount_offset = offset
	team = owner.team
	set_meta(&"tier3_child_mount", true)
	set_meta(&"no_kill_reward", true)
	set_meta(&"token_cost", 0)

func _physics_process(delta: float) -> void:
	if owner_tank == null or not is_instance_valid(owner_tank) or owner_tank.is_destroyed:
		_release_engaged_missile()
		queue_free()
		return
	global_position = owner_tank.global_position + local_mount_offset.rotated(owner_tank.heading)
	heading = owner_tank.heading
	rotation = heading
	StatusEffects.tick(self, delta)
	_acquire_s = maxf(_acquire_s - delta, 0.0)
	_fire_s = maxf(_fire_s - delta, 0.0)
	if not _missile_is_threat(_engaged_missile):
		_release_engaged_missile()
	if _engaged_missile == null and _acquire_s <= 0.0:
		_acquire_s = ACQUIRE_INTERVAL_S
		_engaged_missile = _nearest_incoming_missile()
		if _engaged_missile != null:
			_engaged_missile.set_meta(&"tier3_ciws_engaged_by", get_instance_id())
	if _engaged_missile != null:
		_update_intercept_fire(delta)
	else:
		# 无来弹时保留 CIWS 的近距对空扫射角色；仍复用 AAGunUnit 的真实弹道。
		_update_aa_target_selection(delta)
		_update_turret(delta)
		_update_combat(delta)
		_update_gun(delta)
	queue_redraw()


func _nearest_incoming_missile() -> Missile:
	var best: Missile = null
	var best_d := INTERCEPT_RANGE_PX
	for missile in Missile.active_missiles:
		if not _missile_is_threat(missile):
			continue
		var claimed := int(missile.get_meta(&"tier3_ciws_engaged_by", 0))
		if claimed != 0 and claimed != get_instance_id():
			var claimer := instance_from_id(claimed)
			if typeof(claimer) == TYPE_OBJECT and claimer != null and is_instance_valid(claimer):
				continue
		var d := global_position.distance_to(missile.global_position)
		if d < best_d:
			best_d = d
			best = missile
	return best


func _missile_is_threat(missile: Missile) -> bool:
	if missile == null or not is_instance_valid(missile) or not missile.is_active \
			or missile.is_flare_jammed or not CombatUnit.teams_hostile(missile.team, team):
		return false
	var to_tank := owner_tank.global_position - missile.global_position
	if to_tank.length() > INTERCEPT_RANGE_PX or to_tank.length_squared() < 1.0:
		return to_tank.length_squared() < 1.0
	var missile_fwd := Vector2(sin(missile.heading), -cos(missile.heading))
	return missile_fwd.dot(to_tank.normalized()) > 0.0


func _update_intercept_fire(delta: float) -> void:
	var to_missile := _engaged_missile.global_position - global_position
	var desired := atan2(to_missile.x, -to_missile.y)
	turret_heading = rotate_toward(turret_heading, desired, TURRET_TURN_RATE * delta)
	if _fire_s > 0.0 or bullet_manager == null or status_jam_active:
		return
	_shot_counter += 1
	var real_bullet := _shot_counter % REAL_BULLET_CYCLE == 0
	var direction := desired + randf_range(-MISSILE_SPREAD_RAD, MISSILE_SPREAD_RAD)
	var muzzle := global_position + Vector2(sin(turret_heading), -cos(turret_heading)) * 13.0
	bullet_manager.spawn_bullet(muzzle, direction, BULLET_SPEED_MS, self,
		INTERCEPT_DAMAGE if real_bullet else 0.0, true, not real_bullet)
	_fire_s = FIRE_INTERVAL_S


func _release_engaged_missile() -> void:
	if _engaged_missile != null and is_instance_valid(_engaged_missile) \
			and int(_engaged_missile.get_meta(&"tier3_ciws_engaged_by", 0)) == get_instance_id():
		_engaged_missile.remove_meta(&"tier3_ciws_engaged_by")
	_engaged_missile = null

func is_lock_immune() -> bool:
	return true

func take_damage(_amount: float, _attacker: Node = null, _kind: String = "") -> void:
	pass

func take_missile_damage(_amount: float) -> void:
	pass

func _draw() -> void:
	var color := Color(1.0, 0.44, 0.16)
	draw_circle(Vector2.ZERO, 7.0, color.darkened(0.45))
	draw_line(Vector2.ZERO, Vector2(sin(turret_heading - rotation),
		-cos(turret_heading - rotation)) * 13.0, color, 3.0)
