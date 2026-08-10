class_name AtmosphereArtilleryUnit
extends GroundUnit

## 战场气氛实验用自行火炮外观。
## 路径移动、受击和状态栏完全复用 GroundUnit；射击由共享实验控制器以 2Hz 调度。

var barrel_heading: float = 0.0
var rail_center := Vector2.INF
var rail_axis := Vector2.UP
var rail_lateral := Vector2.RIGHT
var rail_half_length: float = 350.0
var rail_half_width: float = 45.0
var rail_phase: float = 0.0


func take_missile_damage(amount: float) -> void:
	# 压测编队必须保持成员数稳定，避免正式战区的偶发导弹一击必杀污染容量统计。
	if bool(get_meta("stress_invulnerable", false)):
		return
	super.take_missile_damage(amount)


func configure_rail(start_pos: Vector2, long_axis: Vector2, half_length: float = 350.0,
		half_width: float = 45.0) -> void:
	rail_axis = long_axis.normalized()
	if rail_axis.length_squared() < 0.5:
		rail_axis = Vector2.UP
	rail_lateral = Vector2(-rail_axis.y, rail_axis.x)
	rail_half_length = maxf(half_length, 1.0)
	rail_half_width = maxf(half_width, 1.0)
	# phase=0 位于长轴正端；反推中心保证配置后不瞬移。
	rail_center = start_pos - rail_axis * rail_half_length
	rail_phase = 0.0


## 正式战区使用的中心式配置：允许每门炮拥有不同轨道尺寸与初始相位，出生即在解析轨道上。
## 只改变一次性初始化数据；后续仍走同一条 O(1) 解析式移动，不增加运行时决策。
func configure_ellipse(center_pos: Vector2, long_axis: Vector2, half_length: float,
		half_width: float, start_phase: float) -> void:
	rail_axis = long_axis.normalized()
	if rail_axis.length_squared() < 0.5:
		rail_axis = Vector2.UP
	rail_lateral = Vector2(-rail_axis.y, rail_axis.x)
	rail_half_length = maxf(half_length, 1.0)
	rail_half_width = maxf(half_width, 1.0)
	rail_center = center_pos
	rail_phase = fposmod(start_phase, TAU)
	position = rail_center + rail_axis * cos(rail_phase) * rail_half_length \
		+ rail_lateral * sin(rail_phase) * rail_half_width


func _update_movement(delta: float) -> void:
	if rail_center == Vector2.INF:
		super._update_movement(delta)
		return
	# 解析式椭圆：每帧位置直接由 phase 求值，没有 waypoint 过冲和累计漂移。
	# 用当前切线长度换算角速度，使世界线速度近似恒定。
	var tangent_per_rad := -rail_axis * sin(rail_phase) * rail_half_length \
		+ rail_lateral * cos(rail_phase) * rail_half_width
	var speed_px := max_ground_speed * PIXELS_PER_METER
	rail_phase = fposmod(rail_phase + speed_px / maxf(tangent_per_rad.length(), 1.0) * delta, TAU)
	global_position = rail_center + rail_axis * cos(rail_phase) * rail_half_length \
		+ rail_lateral * sin(rail_phase) * rail_half_width
	var tangent := -rail_axis * sin(rail_phase) * rail_half_length \
		+ rail_lateral * cos(rail_phase) * rail_half_width
	if tangent.length_squared() > 0.01:
		heading = atan2(tangent.x, -tangent.y)
		rotation = heading
	speed = max_ground_speed


func _draw_ground_icon() -> void:
	var color: Color = GameConstants.team_color(team)
	var outline := color.darkened(0.4)
	# 履带底盘
	draw_rect(Rect2(-7.0, -6.0, 14.0, 12.0), color)
	draw_rect(Rect2(-7.0, -6.0, 14.0, 12.0), outline, false, 1.5)
	draw_line(Vector2(-6.0, -7.5), Vector2(6.0, -7.5), outline, 2.0)
	draw_line(Vector2(-6.0, 7.5), Vector2(6.0, 7.5), outline, 2.0)
	# 炮塔与独立炮管；抵消车体 rotation 后按世界方向指向当前炮击目标。
	draw_circle(Vector2.ZERO, 4.2, color.lightened(0.12))
	var local_barrel := barrel_heading - heading
	var barrel_dir := Vector2(sin(local_barrel), -cos(local_barrel))
	draw_line(barrel_dir * 2.0, barrel_dir * 17.0, color.lightened(0.35), 2.3, true)
	draw_circle(barrel_dir * 17.0, 1.8, Color(1.0, 0.78, 0.3, 0.9))
