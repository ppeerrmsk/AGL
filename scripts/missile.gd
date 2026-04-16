class_name Missile
extends Node2D

const PIXELS_PER_METER: float = 0.5
const GRAVITY: float = 9.81

var params: MissileParams
var source: CombatUnit        ## 发射单位（SARH 需要持续照射）
var target: CombatUnit        ## 目标
var team: int = 0

var heading: float = 0.0     ## 弧度, 0=北
var speed: float = 300.0     ## m/s
var altitude: float = 5000.0 ## 米
var age: float = 0.0         ## 存活时间
var is_active: bool = true
var has_guidance: bool = true
var is_flare_jammed: bool = false  ## 被热诱弹干扰，永久失去制导
var bounces_remaining: int = 0     ## 剩余弹跳次数（连锁弹头进化）
var proximity_aoe: bool = false    ## 近炸引信：爆炸时产生 AOE 区域

var _prev_los_angle: float = 0.0  ## 上一帧 LOS 角（有限差分算角速率）
var _prev_heading: float = 0.0   ## 上一帧航向（用于计算模拟 bank）
var bank_angle: float = 0.0      ## 模拟 bank（由航向变化率推算）
var _trail_ribbon: TrailRibbon
var _font: Font

func _ready() -> void:
	_trail_ribbon = TrailRibbon.new()
	_trail_ribbon.ribbon_width = 3.0
	_trail_ribbon.max_points = 80
	_trail_ribbon.sample_interval = 0.03
	var trail_color := Color(0.3, 0.5, 1.0, 0.4) if team == 0 else Color(1.0, 0.25, 0.25, 0.4)
	_trail_ribbon.ribbon_color = trail_color
	add_child(_trail_ribbon)
	_prev_heading = heading

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

	# 3) 能量耗尽（发动机燃烧阶段跳过，允许地面发射的低初速导弹加速）
	if speed < 80.0 and age >= params.motor_burn_time:
		is_active = false
		return

	# 4) 制导模式判定
	if params.fire_and_forget:
		# 发射后不管（AGM 等）：不需要持续照射，不受热诱弹干扰
		if target == null or not is_instance_valid(target) or target.is_destroyed:
			has_guidance = false
		else:
			has_guidance = true
	else:
		# SARH 照射检查 + 热诱弹干扰
		if is_flare_jammed:
			has_guidance = false
		elif target == null or not is_instance_valid(target) or target.is_destroyed:
			has_guidance = false
		elif source == null or not is_instance_valid(source) or source.is_destroyed:
			has_guidance = false
		else:
			var lock_progress: float = source.radar_targets.get(target, 0.0)
			var lock_time_val: float = 3.0
			if source is Aircraft and source.params:
				lock_time_val = source.params.lock_time
			elif source is GroundUnit and source.params:
				lock_time_val = source.params.lock_time
			has_guidance = lock_progress >= lock_time_val

	# 5) 制导
	if has_guidance and is_instance_valid(target) and age > params.guidance_delay:
		var los := target.global_position - global_position
		var dist_px := los.length()
		var dist_m := dist_px / PIXELS_PER_METER

		# 发射后不管 + 目标静止/慢速 → 纯追踪（最精确）
		var target_is_slow := target.speed < 10.0
		if params.fire_and_forget and target_is_slow:
			# 对静止目标直接纯追踪，不用 PN（避免数值误差）
			var pure_heading := atan2(los.x, -los.y)
			var diff := _angle_diff(pure_heading, heading)
			var max_turn := params.max_g * GRAVITY / maxf(speed, 50.0) * delta
			heading += clampf(diff, -max_turn, max_turn)
		else:
			# 低空目标：地面杂波干扰导引头，降低追踪过载
			var effective_max_g := params.max_g * _guidance_degradation()

			if dist_m < 200.0:
				# 近距纯追踪，避免 PN 振荡
				var pure_heading := atan2(los.x, -los.y)
				var diff := _angle_diff(pure_heading, heading)
				var max_turn := effective_max_g * GRAVITY / maxf(speed, 50.0) * delta
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
				var a_cmd := params.nav_constant * v_closure * omega
				var max_accel := effective_max_g * GRAVITY
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

	# 8) 模拟 bank（航向变化率 → 侧倾感）
	var hdg_diff := _angle_diff(heading, _prev_heading)
	var turn_rate_now := hdg_diff / maxf(delta, 0.001)
	bank_angle = clampf(turn_rate_now * 0.5, -1.0, 1.0)  # 轻微扭转
	_prev_heading = heading

	queue_redraw()

func _draw() -> void:
	if not is_active:
		return
	_draw_body()
	if age < params.motor_burn_time:
		_draw_motor_flame()
	_draw_data_label()

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

func _draw_data_label() -> void:
	if not _font:
		_font = ThemeDB.fallback_font
	var display_name: String = params.display_name if params else "MSL"
	var heading_deg := rad_to_deg(heading)
	if heading_deg < 0:
		heading_deg += 360.0

	# 到目标的距离
	var dist_to_tgt_m := 0.0
	if target and is_instance_valid(target) and not target.is_destroyed:
		dist_to_tgt_m = global_position.distance_to(target.global_position) / 0.5  # PIXELS_PER_METER

	# 高度：优先使用目标的 flat_altitude 模式判断（生存模式用 tier 标签）
	var alt_str: String
	var use_flat := target and is_instance_valid(target) and target.flat_altitude
	if use_flat:
		var tier := CombatUnit.AltitudeTier.MID
		if altitude < 3500.0:
			tier = CombatUnit.AltitudeTier.LOW
		elif altitude >= 7500.0:
			tier = CombatUnit.AltitudeTier.HIGH
		alt_str = "ALT %s" % CombatUnit.TIER_NAMES[tier]
	else:
		alt_str = "ALT %dm" % roundi(altitude)

	var speed_kmh := speed * 3.6
	var mach := speed_kmh / 1225.0
	var time_left := params.max_lifetime - age if params else 0.0

	var lines: PackedStringArray = PackedStringArray()
	lines.append(display_name)
	lines.append("HDG %03d" % roundi(heading_deg))
	lines.append("M%.2f" % mach)
	# 高度
	lines.append(alt_str)
	# 到目标距离
	if dist_to_tgt_m > 0.0:
		if dist_to_tgt_m < 1000.0:
			lines.append("RNG %dm" % roundi(dist_to_tgt_m))
		else:
			lines.append("RNG %.1fkm" % (dist_to_tgt_m / 1000.0))
	# 制导状态
	if has_guidance:
		lines.append("GUIDE")
	elif is_flare_jammed:
		lines.append("JAMMED")
	else:
		lines.append("NO GDE")
	# 发动机状态
	if params and age < params.motor_burn_time:
		lines.append("MOTOR")
	else:
		lines.append("COAST")

	var inv_rot := -rotation
	var font_size := 10
	var line_height := 12.0
	var label_offset := Vector2(14, -8).rotated(inv_rot)

	var max_w := 0.0
	for line in lines:
		var w := _font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		max_w = maxf(max_w, w)
	var box_w := max_w + 8.0
	var box_h := lines.size() * line_height + 4.0

	var bg_color: Color
	var text_color: Color
	if team == 0:
		bg_color = Color(0.1, 0.2, 0.3, 0.75)
		text_color = Color(0.7, 0.85, 1.0)
	else:
		bg_color = Color(0.3, 0.08, 0.08, 0.75)
		text_color = Color(1.0, 0.8, 0.8)

	draw_set_transform(label_offset, inv_rot, Vector2.ONE)
	draw_rect(Rect2(0, 0, box_w, box_h), bg_color)
	draw_rect(Rect2(0, 0, box_w, box_h), text_color * Color(1, 1, 1, 0.3), false, 1.0)

	for i in range(lines.size()):
		draw_string(_font, Vector2(4, 10 + i * line_height), lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, text_color)

	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

## 低空目标导引头性能衰减（地面杂波干扰）
## 仅在扁平高度模式（生存模式）下生效
func _guidance_degradation() -> float:
	if not is_instance_valid(target) or not target.flat_altitude:
		return 1.0
	var tier := target.get_altitude_tier()
	match tier:
		CombatUnit.AltitudeTier.GROUND:
			return 0.5  # 地面目标：严重杂波
		CombatUnit.AltitudeTier.LOW:
			return 0.7  # 低空目标：中等杂波
		_:
			return 1.0

## 角度差（-PI 到 PI）
static func _angle_diff(a: float, b: float) -> float:
	var d := fmod(a - b + PI, TAU)
	if d < 0:
		d += TAU
	return d - PI
