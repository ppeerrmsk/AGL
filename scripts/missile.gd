class_name Missile
extends Node2D

const PIXELS_PER_METER: float = 0.5
const GRAVITY: float = 9.81

var params: MissileParams
var source: Aircraft          ## 发射机（SARH 需要持续照射）
var target: Aircraft          ## 目标
var team: int = 0

var heading: float = 0.0     ## 弧度, 0=北
var speed: float = 300.0     ## m/s
var altitude: float = 5000.0 ## 米
var age: float = 0.0         ## 存活时间
var is_active: bool = true
var has_guidance: bool = true

var _prev_los_angle: float = 0.0  ## 上一帧 LOS 角（有限差分算角速率）
var _trail_points: Array[Vector2] = []  ## 烟迹全局坐标
const MAX_TRAIL_POINTS: int = 50

func _physics_process(delta: float) -> void:
	if not is_active:
		return

	age += delta

	# 1) 存活时间检查
	if age > params.max_lifetime:
		is_active = false
		return

	# 2) 动力阶段
	if age < params.motor_burn_time:
		speed = minf(speed + params.motor_acceleration * delta, params.max_speed)
	else:
		speed = maxf(speed - params.drag_deceleration * delta, 0.0)

	# 3) 能量耗尽
	if speed < 80.0:
		is_active = false
		return

	# 4) SARH 照射检查
	if target == null or not is_instance_valid(target) or target.is_destroyed:
		has_guidance = false
	elif source == null or not is_instance_valid(source) or source.is_destroyed:
		has_guidance = false
	else:
		var lock_progress: float = source.radar_targets.get(target, 0.0)
		has_guidance = lock_progress >= source.params.lock_time

	# 5) 制导
	if has_guidance and is_instance_valid(target) and age > params.guidance_delay:
		var los := target.global_position - global_position
		var dist_px := los.length()
		var dist_m := dist_px / PIXELS_PER_METER

		if dist_m < 200.0:
			# 近距纯追踪，避免 PN 振荡
			var pure_heading := atan2(los.x, -los.y)
			var diff := _angle_diff(pure_heading, heading)
			var max_turn := params.max_g * GRAVITY / maxf(speed, 50.0) * delta
			heading += clampf(diff, -max_turn, max_turn)
		else:
			# 比例导引 (PN)
			var los_angle := atan2(los.x, -los.y)
			var omega := _angle_diff(los_angle, _prev_los_angle) / delta  # LOS 角速率

			# 闭合速度
			var los_dir := los.normalized()
			var my_vel := Vector2(sin(heading), -cos(heading)) * speed * PIXELS_PER_METER
			var tgt_vel := Vector2(sin(target.heading), -cos(target.heading)) * target.speed * PIXELS_PER_METER
			var rel_vel := tgt_vel - my_vel
			var v_closure := -rel_vel.dot(los_dir)

			# 指令加速度
			var a_cmd := params.nav_constant * v_closure * omega / maxf(dist_px, 1.0) * dist_px
			# 上面简化：a_cmd = N * V_closure * omega (omega 已经是 rad/s)
			a_cmd = params.nav_constant * v_closure * omega

			# 限幅
			var max_accel := params.max_g * GRAVITY
			a_cmd = clampf(a_cmd, -max_accel, max_accel)

			# 转弯率 = a / v
			var turn_rate := a_cmd / maxf(speed, 50.0)
			heading += turn_rate * delta

			_prev_los_angle = los_angle

	# 6) 高度趋近
	if has_guidance and target != null and is_instance_valid(target):
		altitude += (target.altitude - altitude) * 3.0 * delta

	# 7) 位移
	var vel_dir := Vector2(sin(heading), -cos(heading))
	global_position += vel_dir * speed * PIXELS_PER_METER * delta
	rotation = heading

	# 8) 烟迹
	_trail_points.append(global_position)
	if _trail_points.size() > MAX_TRAIL_POINTS:
		_trail_points.remove_at(0)

	queue_redraw()

func _draw() -> void:
	if not is_active:
		return
	_draw_trail()
	_draw_body()
	if age < params.motor_burn_time:
		_draw_motor_flame()

func _draw_trail() -> void:
	if _trail_points.size() < 2:
		return
	var count := _trail_points.size()
	for i in range(count - 1):
		var alpha := float(i) / float(count) * 0.4
		var color := Color(0.7, 0.7, 0.7, alpha)
		var from := to_local(_trail_points[i])
		var to := to_local(_trail_points[i + 1])
		draw_line(from, to, color, 1.5)

func _draw_body() -> void:
	var color := Color(1.0, 0.5, 0.1) if team == 0 else Color(1.0, 0.2, 0.2)
	var size := 5.0
	var body := PackedVector2Array([
		Vector2(0, -size),       # 弹头
		Vector2(size * 0.4, 0),  # 右
		Vector2(0, size * 0.6),  # 尾
		Vector2(-size * 0.4, 0), # 左
	])
	draw_colored_polygon(body, color)

func _draw_motor_flame() -> void:
	var flicker := randf_range(0.6, 1.0)
	var glow := Color(1.0, 0.5, 0.1, 0.7 * flicker)
	var tail := Vector2(0, 5.0)
	var flame_len := randf_range(6.0, 10.0)
	var flame := PackedVector2Array([
		tail + Vector2(-2.0, 0),
		tail + Vector2(2.0, 0),
		tail + Vector2(0, flame_len),
	])
	draw_colored_polygon(flame, glow)

## 角度差（-PI 到 PI）
static func _angle_diff(a: float, b: float) -> float:
	var d := fmod(a - b + PI, TAU)
	if d < 0:
		d += TAU
	return d - PI
