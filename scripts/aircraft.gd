class_name Aircraft
extends Node2D

const GRAVITY: float = 9.81
const PIXELS_PER_METER: float = 0.5  ## 1米 = 0.5像素

@export var params: AircraftParams
@export var team: int = 0  ## 0=友方, 1=敌方

# --- 状态 ---
var altitude: float = 5000.0        ## 米
var heading: float = 0.0            ## 弧度, 0=上(北)
var speed: float = 250.0            ## m/s (内部全部用m/s)
var vertical_speed: float = 0.0     ## m/s
var bank_angle: float = 0.0         ## 弧度
var g_load: float = 1.0
var hp: float = 100.0
var is_stalled: bool = false

# --- 目标 ---
var target_position: Vector2 = Vector2.INF  ## 世界坐标, INF=无目标
var target_altitude: float = 5000.0
var target_speed_kmh: float = 900.0  ## km/h, 玩家/AI设定

# --- 选择 ---
var selected: bool = false

# --- 雷达 ---
var is_hovered: bool = false             ## 鼠标悬停时为 true，显示雷达锥
var radar_targets: Dictionary = {}       ## { Aircraft: float } 累计照射时间
var is_locked: bool = false              ## 被至少一架敌机锁定
var locked_by: Array[Aircraft] = []      ## 锁定自己的敌机列表

func _ready() -> void:
	if params:
		hp = params.max_hp
		speed = params.cruise_speed / 3.6  # km/h -> m/s
		target_speed_kmh = params.cruise_speed

func _physics_process(delta: float) -> void:
	_update_target_heading()
	_update_bank(delta)
	_update_heading(delta)
	_update_speed(delta)
	_update_altitude(delta)
	_update_stall()
	_update_g_load()
	_apply_movement(delta)
	_update_visuals()
	queue_redraw()

# ========== 物理演算 ==========

func _update_target_heading() -> void:
	if target_position == Vector2.INF:
		return
	var diff := target_position - global_position
	var dist := diff.length()
	# 到达判定：至少150px，或当前速度下2秒的飞行距离
	var arrival_dist := maxf(150.0, speed * PIXELS_PER_METER * 2.0)
	if dist < arrival_dist:
		target_position = Vector2.INF
		return
	var _target_heading := atan2(diff.x, -diff.y)
	_cached_target_heading = _target_heading
	# 接近目标时衰减修正力度：在 arrival_dist ~ 3×arrival_dist 之间从 0 线性过渡到 1
	_proximity_damping = clampf((dist - arrival_dist) / (arrival_dist * 2.0), 0.0, 1.0)

var _cached_target_heading: float = 0.0
var _proximity_damping: float = 1.0

func _update_bank(delta: float) -> void:
	if target_position == Vector2.INF and abs(bank_angle) < 0.01:
		bank_angle = 0.0
		return

	var heading_diff := _angle_diff(_cached_target_heading, heading)

	if target_position == Vector2.INF:
		# 无目标，回正
		heading_diff = 0.0

	# 有目标时尽可能拉满G力极限转弯
	var max_bank := _max_bank_angle()
	var target_bank: float
	if abs(heading_diff) < 0.05:
		target_bank = 0.0
	elif abs(heading_diff) < 0.4:
		target_bank = sign(heading_diff) * max_bank * 0.3
	else:
		target_bank = sign(heading_diff) * max_bank

	# 关键：按接近程度衰减修正力度，越近越轻，消除振荡
	target_bank *= _proximity_damping

	# 滚转速率限制
	var roll_rate_val := params.roll_rate if params else 4.0
	var bank_diff := target_bank - bank_angle
	var max_roll := roll_rate_val * delta
	bank_angle += clampf(bank_diff, -max_roll, max_roll)

func _update_heading(delta: float) -> void:
	if abs(bank_angle) < 0.001:
		return
	# 转弯率 ω = g × tan(bank_angle) / speed
	var speed_ms := maxf(speed, 10.0)  # 防止除零
	var turn_rate := GRAVITY * tan(bank_angle) / speed_ms
	heading += turn_rate * delta
	# 归一化到 [-PI, PI]
	heading = fmod(heading + PI, TAU) - PI

func _update_speed(delta: float) -> void:
	var target_ms := target_speed_kmh / 3.6
	var max_speed_ms := _max_speed_at_altitude() / 3.6
	target_ms = minf(target_ms, max_speed_ms)

	var accel := params.acceleration if params else 50.0
	var speed_diff := target_ms - speed
	speed += clampf(speed_diff, -accel * delta, accel * delta)
	speed = maxf(speed, 0.0)

func _update_altitude(delta: float) -> void:
	var alt_diff := target_altitude - altitude
	var max_climb := params.climb_rate_max if params else 250.0
	# 简化：根据高度差决定爬升/下降
	var target_vs: float
	if abs(alt_diff) < 10.0:
		target_vs = 0.0
	else:
		target_vs = clampf(alt_diff * 0.1, -max_climb, max_climb)
	# 平滑过渡
	vertical_speed = lerpf(vertical_speed, target_vs, delta * 2.0)
	altitude += vertical_speed * delta
	altitude = maxf(altitude, 0.0)

func _update_stall() -> void:
	var stall_speed_ms := _stall_speed() / 3.6
	is_stalled = speed < stall_speed_ms
	if is_stalled:
		# 失速：丢高度，逐渐恢复速度
		altitude -= 50.0 * get_physics_process_delta_time()
		speed += 5.0 * get_physics_process_delta_time()
		altitude = maxf(altitude, 0.0)

func _update_g_load() -> void:
	if abs(bank_angle) < 0.001:
		g_load = 1.0
	else:
		g_load = 1.0 / cos(bank_angle)
		g_load = absf(g_load)

func _apply_movement(delta: float) -> void:
	# heading: 0=上(北), 顺时针为正
	# Godot 2D: x右, y下
	var velocity := Vector2(sin(heading), -cos(heading)) * speed * PIXELS_PER_METER
	global_position += velocity * delta

# ========== 辅助计算 ==========

func _max_bank_angle() -> float:
	var max_g_val := params.max_g if params else 9.0
	# G = 1/cos(bank) => bank = acos(1/G)
	return acos(1.0 / max_g_val)

func _stall_speed() -> float:
	# V_stall = V_base * sqrt(G)
	var base := params.stall_speed_base if params else 220.0
	return base * sqrt(maxf(g_load, 1.0))

func _max_speed_at_altitude() -> float:
	var max_spd := params.max_speed if params else 2100.0
	# 简化：高空速度略降
	var density_ratio := exp(-altitude / 8500.0)
	return max_spd * sqrt(density_ratio)

func _air_density_ratio() -> float:
	return exp(-altitude / 8500.0)

static func _angle_diff(target: float, current: float) -> float:
	var diff := fmod(target - current + PI, TAU) - PI
	return diff

# ========== 雷达 ==========

## 判断目标世界坐标是否在本机雷达锥内
func is_in_radar_cone(target_global_pos: Vector2) -> bool:
	var radar_r := params.radar_range if params else 300.0
	var half_deg := params.radar_half_angle if params else 30.0
	var half_rad := deg_to_rad(half_deg)

	var to_target := target_global_pos - global_position
	var dist := to_target.length()
	if dist > radar_r or dist < 1.0:
		return false

	# heading: 0=北(上), 顺时针正; atan2(x, -y) 与 heading 同系
	var angle_to := atan2(to_target.x, -to_target.y)
	var diff := absf(_angle_diff(angle_to, heading))
	return diff <= half_rad

# ========== 绘制 ==========

## 标签字体（延迟加载）
var _font: Font

func _draw() -> void:
	if not _font:
		_font = ThemeDB.fallback_font
	if is_hovered:
		_draw_radar_cone()
	_draw_target_line()
	_draw_aircraft_icon()
	_draw_lock_indicator()
	_draw_data_label()

func _draw_radar_cone() -> void:
	var radar_r := params.radar_range if params else 300.0
	var half_deg := params.radar_half_angle if params else 30.0
	var half_rad := deg_to_rad(half_deg)

	# 扇形在本地坐标绘制，飞机 rotation = heading
	# 本地坐标中飞机朝上（-Y），所以扇形中心轴 = -Y 方向 = -PI/2
	var center_angle := -PI / 2.0
	var start_angle := center_angle - half_rad
	var end_angle := center_angle + half_rad
	var segments := 24

	# 扇形颜色
	var cone_color: Color
	if team == 0:
		cone_color = Color(0.2, 0.7, 0.8, 0.12)
	else:
		cone_color = Color(0.8, 0.2, 0.2, 0.12)

	# 构建扇形多边形（圆心 + 弧线上的点）
	var points := PackedVector2Array()
	points.append(Vector2.ZERO)
	for i in range(segments + 1):
		var angle := start_angle + (end_angle - start_angle) * float(i) / float(segments)
		points.append(Vector2(cos(angle), sin(angle)) * radar_r)

	draw_colored_polygon(points, cone_color)

	# 扇形边缘线
	var edge_color := Color(cone_color, 0.35)
	draw_line(Vector2.ZERO, points[1], edge_color, 1.0, true)
	draw_line(Vector2.ZERO, points[points.size() - 1], edge_color, 1.0, true)
	# 弧线
	for i in range(1, points.size() - 1):
		draw_line(points[i], points[i + 1], edge_color, 1.0, true)

func _draw_lock_indicator() -> void:
	if not is_locked:
		return
	# 红色警告菱形，闪烁效果
	var blink := absf(sin(Time.get_ticks_msec() * 0.005))
	var alpha := lerpf(0.5, 1.0, blink)
	var warn_color := Color(1.0, 0.15, 0.1, alpha)
	var d := 22.0
	# 四个小三角围绕飞机
	var offsets: Array[Vector2] = [Vector2(0, -d), Vector2(d, 0), Vector2(0, d), Vector2(-d, 0)]
	var tri_size := 5.0
	for offset: Vector2 in offsets:
		var dir: Vector2 = offset.normalized()
		var perp: Vector2 = Vector2(-dir.y, dir.x)
		var tip: Vector2 = offset + dir * tri_size
		var base_a: Vector2 = offset + perp * tri_size * 0.6
		var base_b: Vector2 = offset - perp * tri_size * 0.6
		draw_colored_polygon(PackedVector2Array([tip, base_a, base_b]), warn_color)

func _draw_aircraft_icon() -> void:
	var color: Color = params.icon_color if params else Color.GREEN
	var outline_color := color.darkened(0.3)

	var size := 16.0

	# 高度缩放
	var max_alt := params.max_altitude if params else 15000.0
	var alt_factor := clampf(altitude / max_alt, 0.0, 1.0)
	var base_scale := lerpf(0.7, 1.3, alt_factor)

	# 滚转变形
	var bank_compress := cos(bank_angle)
	var sx := base_scale * bank_compress
	var sy := base_scale

	var xform := Transform2D(0.0, Vector2.ZERO)
	xform = xform.scaled(Vector2(sx, sy))

	# 机身主体（填充多边形）
	var body: PackedVector2Array = PackedVector2Array([
		Vector2(0, -size * 1.1),        # 机头尖端
		Vector2(size * 0.15, -size * 0.7),
		Vector2(size * 0.18, -size * 0.2),
		Vector2(size * 0.15, size * 0.5),
		Vector2(size * 0.20, size * 0.85),
		Vector2(0, size * 0.95),         # 尾喷口
		Vector2(-size * 0.20, size * 0.85),
		Vector2(-size * 0.15, size * 0.5),
		Vector2(-size * 0.18, -size * 0.2),
		Vector2(-size * 0.15, -size * 0.7),
	])

	# 主翼（三角翼，后掠）
	var wing_r: PackedVector2Array = PackedVector2Array([
		Vector2(size * 0.18, -size * 0.05),
		Vector2(size * 1.1, size * 0.25),
		Vector2(size * 0.9, size * 0.35),
		Vector2(size * 0.18, size * 0.20),
	])
	var wing_l: PackedVector2Array = PackedVector2Array([
		Vector2(-size * 0.18, -size * 0.05),
		Vector2(-size * 1.1, size * 0.25),
		Vector2(-size * 0.9, size * 0.35),
		Vector2(-size * 0.18, size * 0.20),
	])

	# 尾翼
	var tail_r: PackedVector2Array = PackedVector2Array([
		Vector2(size * 0.15, size * 0.55),
		Vector2(size * 0.55, size * 0.75),
		Vector2(size * 0.45, size * 0.85),
		Vector2(size * 0.18, size * 0.80),
	])
	var tail_l: PackedVector2Array = PackedVector2Array([
		Vector2(-size * 0.15, size * 0.55),
		Vector2(-size * 0.55, size * 0.75),
		Vector2(-size * 0.45, size * 0.85),
		Vector2(-size * 0.18, size * 0.80),
	])

	# 应用变换并绘制填充
	var parts := [body, wing_r, wing_l, tail_r, tail_l]
	for part in parts:
		var transformed: PackedVector2Array = PackedVector2Array()
		for p in part:
			transformed.append(xform * p)
		draw_colored_polygon(transformed, color)
		# 轮廓线
		for i in range(transformed.size()):
			var from := transformed[i]
			var to := transformed[(i + 1) % transformed.size()]
			draw_line(from, to, outline_color, 1.0, true)

	# 选中指示 - 细圆环
	if selected:
		var ring_color := color
		ring_color.a = 0.5
		draw_arc(Vector2.ZERO, size * 1.8 * base_scale, 0, TAU, 48, ring_color, 1.5)

## 在飞机旁边绘制数据标签框（逐行列出所有参数）
func _draw_data_label() -> void:
	var display_name: String = params.display_name if params else "???"
	var speed_kmh := speed * 3.6
	var heading_deg := rad_to_deg(heading)
	if heading_deg < 0:
		heading_deg += 360.0
	var mach := speed_kmh / 1225.0
	var status := "STALL" if is_stalled else ""

	# 逐行数据
	var lines: PackedStringArray = PackedStringArray()
	lines.append(display_name)
	lines.append("HDG %03d" % roundi(heading_deg))
	lines.append("%d kt" % roundi(speed_kmh * 0.5399))
	lines.append("M%.2f" % mach)
	lines.append("ALT %dm" % roundi(altitude))
	lines.append("G %.1f" % g_load)
	if status != "":
		lines.append(status)

	var inv_rot := -rotation
	var font_size := 11
	var line_height := 14.0
	var label_offset := Vector2(24, -12).rotated(inv_rot)

	# 测量最大宽度
	var max_w := 0.0
	for line in lines:
		var w := _font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		max_w = maxf(max_w, w)
	var box_w := max_w + 10.0
	var box_h := lines.size() * line_height + 6.0

	# 背景色（基于阵营）
	var bg_color: Color
	var text_color: Color
	if team == 0:
		bg_color = Color(0.1, 0.15, 0.35, 0.85)
		text_color = Color(0.8, 0.9, 1.0)
	else:
		bg_color = Color(0.35, 0.08, 0.08, 0.85)
		text_color = Color(1.0, 0.85, 0.85)

	draw_set_transform(label_offset, inv_rot, Vector2.ONE)
	draw_rect(Rect2(0, 0, box_w, box_h), bg_color)
	draw_rect(Rect2(0, 0, box_w, box_h), text_color * Color(1, 1, 1, 0.4), false, 1.0)

	for i in range(lines.size()):
		draw_string(_font, Vector2(5, 12 + i * line_height), lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, text_color)

	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func _draw_target_line() -> void:
	if target_position == Vector2.INF:
		return
	var color: Color = params.icon_color if params else Color.GREEN
	color.a = 0.45

	var local_target := to_local(target_position)

	# 实线轨迹线（参考 DCS 风格）
	draw_line(Vector2.ZERO, local_target, color, 1.5, true)

	# 目标点 - 小菱形标记
	var d := 6.0
	var diamond := PackedVector2Array([
		local_target + Vector2(0, -d),
		local_target + Vector2(d, 0),
		local_target + Vector2(0, d),
		local_target + Vector2(-d, 0),
	])
	draw_colored_polygon(diamond, Color(color, 0.6))
	for i in range(4):
		draw_line(diamond[i], diamond[(i + 1) % 4], color, 1.0)

func _update_visuals() -> void:
	rotation = heading
