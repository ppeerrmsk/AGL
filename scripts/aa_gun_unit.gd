class_name AAGunUnit
extends GroundUnit

## 高射炮车：炮管独立旋转，短程高射速机炮攻击
## 无雷达，直接攻击射程内的敌对目标，命中率低但火力密集

var turret_heading: float = 0.0
const TURRET_TURN_RATE := 3.0  ## rad/s 炮管旋转速度
var _scan_timer: float = 0.0
const SCAN_INTERVAL := 0.5    ## 目标扫描间隔

func _ready() -> void:
	super._ready()
	turret_heading = heading

func _physics_process(delta: float) -> void:
	if is_destroyed:
		_update_destroy(delta)
		queue_redraw()
		return

	_update_movement(delta)
	_update_aa_target_selection(delta)
	_update_turret(delta)
	_update_combat(delta)
	_update_gun(delta)
	queue_redraw()

## AA 无雷达，直接扫描射程内最近的敌方目标
func _update_aa_target_selection(delta: float) -> void:
	# 当前目标仍在射程内 → 保持
	if combat_target and is_instance_valid(combat_target) and not combat_target.is_destroyed:
		var dist := global_position.distance_to(combat_target.global_position)
		var attack_range := (params.gun.max_range if params and params.gun else 600.0) * PIXELS_PER_METER
		if dist < attack_range * 1.5:
			return

	# 定期扫描
	_scan_timer -= delta
	if _scan_timer > 0.0:
		return
	_scan_timer = SCAN_INTERVAL

	combat_target = null
	var attack_range := (params.gun.max_range if params and params.gun else 600.0) * PIXELS_PER_METER * 1.5
	var best_dist := attack_range
	if not get_parent():
		return

	for child in get_parent().get_children():
		if not child is CombatUnit:
			continue
		if child == self or child.team == team or child.is_destroyed:
			continue
		var d := global_position.distance_to(child.global_position)
		if d < best_dist:
			best_dist = d
			combat_target = child

## AA 不需要雷达锁定，跳过父类的 _update_target_selection
func _update_target_selection() -> void:
	pass

## AA 无雷达
func is_in_radar_cone(_target_global_pos: Vector2) -> bool:
	return false

## 炮管追踪目标 / 无目标时缓慢旋转
func _update_turret(delta: float) -> void:
	if combat_target and is_instance_valid(combat_target) and not combat_target.is_destroyed:
		# 追踪前置点
		var to_target := combat_target.global_position - global_position
		var dist_px := to_target.length()
		var tgt_vel := Vector2(sin(combat_target.heading), -cos(combat_target.heading)) * combat_target.speed * PIXELS_PER_METER
		var bullet_speed := (params.gun.muzzle_velocity if params and params.gun else 700.0) * PIXELS_PER_METER
		var time_to_target := dist_px / maxf(bullet_speed, 1.0)
		var lead_pos := combat_target.global_position + tgt_vel * time_to_target
		var target_angle := atan2((lead_pos - global_position).x, -(lead_pos - global_position).y)
		var diff := angle_difference(turret_heading, target_angle)
		turret_heading += clampf(diff, -TURRET_TURN_RATE * delta, TURRET_TURN_RATE * delta)
	else:
		# 无目标：缓慢旋转
		turret_heading += 0.8 * delta

## 覆写战斗检查：有目标就开火（明知打不中也象征性射击）
func _update_combat(_delta: float) -> void:
	if combat_target == null or not is_instance_valid(combat_target) or combat_target.is_destroyed:
		combat_target = null
		is_firing = false
		return

	if not params or not params.gun:
		is_firing = false
		return

	var to_target := combat_target.global_position - global_position
	var dist_px := to_target.length()
	var gun_range_px := params.gun.max_range * PIXELS_PER_METER

	if dist_px > gun_range_px * 1.5:
		is_firing = false
		return

	# 前置量
	var tgt_vel := Vector2(sin(combat_target.heading), -cos(combat_target.heading)) * combat_target.speed * PIXELS_PER_METER
	var bullet_speed := params.gun.muzzle_velocity * PIXELS_PER_METER
	var time_to_target := dist_px / maxf(bullet_speed, 1.0)
	var lead_pos := combat_target.global_position + tgt_vel * time_to_target
	var angle_to_lead := atan2((lead_pos - global_position).x, -(lead_pos - global_position).y)

	_gun_lead_heading = angle_to_lead

	# 炮管大致对准就开火（宽松判定，象征性射击）
	var angle_diff := absf(angle_difference(turret_heading, angle_to_lead))
	is_firing = angle_diff < deg_to_rad(25.0)  # 25° 内就开火

## 覆写射击：从炮管方向发射
func _update_gun(delta: float) -> void:
	if not is_firing or not bullet_manager or not params or not params.gun:
		_fire_cooldown = maxf(_fire_cooldown - delta, 0.0)
		return

	_fire_cooldown -= delta
	if _fire_cooldown > 0.0:
		return
	if ammo <= 0:
		is_firing = false
		return

	var interval := 60.0 / params.gun.fire_rate
	_fire_cooldown = interval
	ammo -= 1

	var spread := deg_to_rad(params.gun.spread_angle)
	var dir := _gun_lead_heading + randf_range(-spread, spread)
	var muzzle_pos := global_position + Vector2(sin(turret_heading), -cos(turret_heading)) * 10.0
	bullet_manager.spawn_bullet(muzzle_pos, dir, params.gun.muzzle_velocity, self, params.gun.bullet_damage)

# ========== 绘制 ==========

func _draw() -> void:
	if is_destroyed:
		_draw_destroyed()
		return
	if is_hovered:
		_draw_attack_range()
	_draw_aa_icon()
	_draw_data_label()

## 绘制攻击范围圆（不是雷达锥）
func _draw_attack_range() -> void:
	if not params or not params.gun:
		return
	var range_px := params.gun.max_range * PIXELS_PER_METER
	var color: Color
	if team == 0:
		color = Color(0.2, 0.7, 0.8, 0.08)
	else:
		color = Color(0.8, 0.5, 0.1, 0.08)

	var segments := 32
	var points := PackedVector2Array()
	for i in range(segments):
		var angle := float(i) / segments * TAU
		points.append(Vector2(cos(angle), sin(angle)).rotated(-rotation) * range_px)
	draw_colored_polygon(points, color)

	var edge_color := Color(color.r, color.g, color.b, 0.25)
	for i in range(segments):
		var a0 := float(i) / segments * TAU
		var a1 := float(i + 1) / segments * TAU
		var p0 := Vector2(cos(a0), sin(a0)).rotated(-rotation) * range_px
		var p1 := Vector2(cos(a1), sin(a1)).rotated(-rotation) * range_px
		draw_line(p0, p1, edge_color, 1.0)

func _draw_aa_icon() -> void:
	var color: Color = params.icon_color if params else Color.ORANGE
	var size := 10.0

	# 底盘
	var chassis_half := size * 0.5
	var chassis := PackedVector2Array([
		Vector2(-chassis_half, -chassis_half * 0.7),
		Vector2(chassis_half, -chassis_half * 0.7),
		Vector2(chassis_half, chassis_half * 0.7),
		Vector2(-chassis_half, chassis_half * 0.7),
	])
	draw_colored_polygon(chassis, color.darkened(0.3))

	# 炮管（粗线条，独立旋转）
	var turret_rel := turret_heading - heading
	var barrel_start := Vector2(0, 0).rotated(turret_rel)
	var barrel_end := Vector2(0, -size * 1.2).rotated(turret_rel)
	draw_line(barrel_start, barrel_end, color.lightened(0.2), 2.5)

	# 炮座圆点
	draw_circle(Vector2.ZERO, size * 0.2, color)
