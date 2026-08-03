class_name AirburstAAUnit
extends AAGunUnit

## 远距空爆高炮：冻结一次误差较大的火控解，三连发炮弹按引信时间爆成 AOE。
const ACQUIRE_INTERVAL := 0.5
const MIN_RANGE_PX := 800.0 * PIXELS_PER_METER
const MAX_RANGE_PX := 5000.0 * PIXELS_PER_METER
const SHELL_SPEED_MS := 450.0
const BURST_SIZE := 3
const BURST_INTERVAL := 0.25
const BURST_COOLDOWN := 4.0
const TURRET_RATE := 1.2
const ALIGN_GATE := deg_to_rad(18.0)
## 误差可以让整组落空，但不能让炮口看起来朝随机方向射击。
## 组级偏差最多离开冻结预瞄方位 7°，单发再抖动最多 1.5°。
const MAX_GROUP_AIM_ERROR := deg_to_rad(7.0)
const MAX_SHELL_AIM_JITTER := deg_to_rad(1.5)

var _burst_remaining := 0
var _salvo_timer := 0.0
var _burst_cooldown := 0.0
var _solution_pos := Vector2.ZERO
var _solution_altitude := 0.0
var _shared_fuse_error := 0.0
var _burst_id := 0
var _desired_fire_heading := 0.0

func _physics_process(delta: float) -> void:
	if is_destroyed:
		_update_destroy(delta)
		queue_redraw()
		return
	StatusEffects.tick(self, delta)
	_update_movement(delta)
	_update_aa_target_selection(delta)
	_update_turret(delta)
	_update_airburst_weapon(delta)
	queue_redraw()

func _update_aa_target_selection(delta: float) -> void:
	if combat_target and is_instance_valid(combat_target) and not combat_target.is_destroyed:
		var held_d := global_position.distance_to(combat_target.global_position)
		if held_d >= MIN_RANGE_PX and held_d <= MAX_RANGE_PX * 1.1:
			return
	_scan_timer -= delta
	if _scan_timer > 0.0:
		return
	_scan_timer = ACQUIRE_INTERVAL
	combat_target = null
	var best_d := MAX_RANGE_PX
	for unit in CombatUnit.all_units:
		if not is_instance_valid(unit) or not (unit is Aircraft) or unit.is_destroyed:
			continue
		if not is_hostile_to(unit) or unit.is_lock_immune():
			continue
		var d := global_position.distance_to(unit.global_position)
		if d >= MIN_RANGE_PX and d < best_d:
			best_d = d
			combat_target = unit

func _update_turret(delta: float) -> void:
	var desired := turret_heading + 0.25 * delta
	if combat_target and is_instance_valid(combat_target) and not combat_target.is_destroyed:
		var to_target := combat_target.global_position - global_position
		var travel := to_target.length() / (SHELL_SPEED_MS * PIXELS_PER_METER)
		var target_vel := Vector2(sin(combat_target.heading), -cos(combat_target.heading)) \
				* combat_target.speed * PIXELS_PER_METER
		if combat_target is Aircraft and (combat_target as Aircraft).params \
				and (combat_target as Aircraft).params.flight_model == AircraftParams.FlightModel.ROTORCRAFT:
			target_vel = (combat_target as Aircraft).rotorcraft_velocity * PIXELS_PER_METER
		var lead := combat_target.global_position + target_vel * travel
		desired = atan2((lead - global_position).x, -(lead - global_position).y)
	_desired_fire_heading = desired
	turret_heading += clampf(angle_difference(turret_heading, desired), -TURRET_RATE * delta, TURRET_RATE * delta)

func _update_airburst_weapon(delta: float) -> void:
	_burst_cooldown = maxf(_burst_cooldown - delta, 0.0)
	_salvo_timer = maxf(_salvo_timer - delta, 0.0)
	if status_jam_active or bullet_manager == null or ammo <= 0:
		return
	if _burst_remaining > 0:
		if _salvo_timer <= 0.0:
			_fire_airburst_shell()
			_burst_remaining -= 1
			_salvo_timer = BURST_INTERVAL
		return
	if _burst_cooldown > 0.0 or combat_target == null or not is_instance_valid(combat_target) \
			or combat_target.is_destroyed:
		return
	var to_target := combat_target.global_position - global_position
	var dist := to_target.length()
	if dist < MIN_RANGE_PX or dist > MAX_RANGE_PX:
		return
	if absf(angle_difference(turret_heading, _desired_fire_heading)) > ALIGN_GATE:
		return
	_begin_burst(combat_target as Aircraft)

func _begin_burst(target: Aircraft) -> void:
	var to_target := target.global_position - global_position
	var distance_m := to_target.length() / PIXELS_PER_METER
	var travel := to_target.length() / (SHELL_SPEED_MS * PIXELS_PER_METER)
	var target_vel := Vector2(sin(target.heading), -cos(target.heading)) * target.speed * PIXELS_PER_METER
	if target.params and target.params.flight_model == AircraftParams.FlightModel.ROTORCRAFT:
		target_vel = target.rotorcraft_velocity * PIXELS_PER_METER
	var predicted := target.global_position + target_vel * travel
	var shot_dir := (predicted - global_position).normalized()
	var lateral := Vector2(-shot_dir.y, shot_dir.x)
	var group_error_m := minf(500.0, 220.0 + 0.05 * distance_m)
	var predicted_distance_m := global_position.distance_to(predicted) / PIXELS_PER_METER
	group_error_m = minf(group_error_m, tan(MAX_GROUP_AIM_ERROR) * predicted_distance_m)
	_solution_pos = predicted + lateral * randf_range(-group_error_m, group_error_m) * PIXELS_PER_METER
	_solution_altitude = target.altitude
	_shared_fuse_error = randf_range(-0.35, 0.35)
	_burst_id += 1
	_burst_remaining = mini(BURST_SIZE, ammo)
	_salvo_timer = 0.0
	_burst_cooldown = BURST_COOLDOWN

func _fire_airburst_shell() -> void:
	if ammo <= 0:
		return
	var to_solution := _solution_pos - global_position
	var base_dir := atan2(to_solution.x, -to_solution.y)
	var right := Vector2(cos(base_dir), sin(base_dir))
	var solution_distance_m := to_solution.length() / PIXELS_PER_METER
	var shell_jitter_m := minf(60.0, tan(MAX_SHELL_AIM_JITTER) * solution_distance_m)
	var per_shell_pos := _solution_pos + right * randf_range(-shell_jitter_m, shell_jitter_m) * PIXELS_PER_METER
	var direction := atan2((per_shell_pos - global_position).x, -(per_shell_pos - global_position).y)
	var fuse := global_position.distance_to(per_shell_pos) / (SHELL_SPEED_MS * PIXELS_PER_METER) \
			+ _shared_fuse_error + randf_range(-0.08, 0.08)
	var muzzle := global_position + Vector2(sin(turret_heading), -cos(turret_heading)) * 18.0
	bullet_manager.spawn_airburst_shell(muzzle, direction, SHELL_SPEED_MS, self,
		maxf(fuse, 0.25), _solution_altitude, 220.0, 75.0, _burst_id)
	ammo -= 1

func _draw() -> void:
	if is_destroyed:
		_draw_destroyed()
		return
	if is_hovered:
		_draw_attack_range()
	_draw_aa_icon()
	# 蓝白双环标识空爆火炮，避免与近程 ZU-23 混淆。
	draw_arc(Vector2.ZERO, 14.0, 0, TAU, 24, Color(0.65, 0.86, 1.0, 0.8), 1.5)
	draw_arc(Vector2.ZERO, 18.0, 0, TAU, 24, Color(0.65, 0.86, 1.0, 0.35), 1.0)
	_draw_lock_indicator()
	AircraftRenderer.draw_target_bracket(self, is_mission_target)
	AircraftRenderer.draw_status_icons(self)
	_draw_data_label()
