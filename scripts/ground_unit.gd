class_name GroundUnit
extends CombatUnit

## 地面单位基类：SAM、AA、雷达站、车辆等
## 高度固定为 0（GROUND 档），可缓慢地面移动，拥有雷达和机炮

@export var params: AircraftParams  ## 复用 AircraftParams 提供雷达/机炮参数
@export var initial_heading_deg: float = 0.0

# --- 移动 ---
var target_position: Vector2 = Vector2.INF
var max_ground_speed: float = 5.0  ## m/s（地面移动极慢）

# --- 路径移动 ---
var waypoints: PackedVector2Array = PackedVector2Array()
var current_waypoint_index: int = 0
var arrival_distance: float = 20.0  ## 到达判定距离（像素）

# --- 车队跟随 ---
var convoy_leader: GroundUnit = null  ## 跟随的前车（非 null 时进入跟随模式）
var convoy_follow_distance: float = 40.0  ## 跟随间距（像素）

# --- 战斗 ---
var combat_target: CombatUnit = null
var is_firing: bool = false
var ammo: int = 500
var _fire_cooldown: float = 0.0
var _gun_lead_heading: float = 0.0
var bullet_manager: Node2D = null
var missile_manager: Node2D = null

# --- 击毁 ---
var _destroy_timer: float = 0.0

# --- 视觉 ---
var _font: Font

func _ready() -> void:
	# 图层：地面单位画在飞机下面（空中单位永远覆盖地面/海面）
	z_index = -10

	altitude = 0.0
	flat_altitude = true
	speed = 0.0
	heading = deg_to_rad(initial_heading_deg)
	rotation = heading
	if params:
		hp = params.max_hp
		if params.gun:
			ammo = params.gun.max_ammo

func _physics_process(delta: float) -> void:
	if is_destroyed:
		_update_destroy(delta)
		queue_redraw()
		return

	_update_movement(delta)
	_update_target_selection()
	_update_combat(delta)
	_update_gun(delta)
	queue_redraw()

# ========== 移动 ==========

func _update_movement(delta: float) -> void:
	# 车队跟随模式：追踪前车
	if convoy_leader and is_instance_valid(convoy_leader) and not convoy_leader.is_destroyed:
		var leader_back := Vector2(sin(convoy_leader.heading), -cos(convoy_leader.heading)) * -convoy_follow_distance
		target_position = convoy_leader.global_position + leader_back
	elif not waypoints.is_empty():
		# 路径移动模式
		var wp := waypoints[current_waypoint_index]
		if global_position.distance_to(wp) < arrival_distance:
			current_waypoint_index = (current_waypoint_index + 1) % waypoints.size()
		target_position = waypoints[current_waypoint_index]

	if target_position == Vector2.INF:
		speed = 0.0
		return

	var to_target := target_position - global_position
	var dist := to_target.length()

	if dist < 5.0:
		speed = 0.0
		return

	# 朝向目标缓慢转向
	var target_heading := atan2(to_target.x, -to_target.y)
	var diff := angle_difference(heading, target_heading)
	var turn_rate := 1.0  # rad/s
	heading += clampf(diff, -turn_rate * delta, turn_rate * delta)

	speed = max_ground_speed
	var vel := Vector2(sin(heading), -cos(heading)) * speed * PIXELS_PER_METER
	global_position += vel * delta
	rotation = heading

# ========== 高度 ==========

func get_altitude_tier() -> int:
	return AltitudeTier.GROUND

# ========== 自动目标选择 ==========

## 简单 AI：从已锁定目标中选最近的敌方
func _update_target_selection() -> void:
	# 当前目标仍有效且已锁定 → 保持
	if combat_target and is_instance_valid(combat_target) and not combat_target.is_destroyed:
		var lock_time_val := params.lock_time if params else 3.0
		if radar_targets.get(combat_target, 0.0) >= lock_time_val:
			return

	# 寻找新目标
	combat_target = null
	var best_dist := INF
	var lock_time_val := params.lock_time if params else 3.0
	for target_key in radar_targets:
		if radar_targets[target_key] < lock_time_val:
			continue
		if not is_instance_valid(target_key):
			continue
		var target_unit: CombatUnit = target_key
		if target_unit.is_destroyed or target_unit.team == team:
			continue
		var d := global_position.distance_to(target_unit.global_position)
		if d < best_dist:
			best_dist = d
			combat_target = target_unit

# ========== 战斗 ==========

func _update_combat(_delta: float) -> void:
	if combat_target == null or not is_instance_valid(combat_target) or combat_target.is_destroyed:
		combat_target = null
		is_firing = false
		return

	if not params or not params.gun:
		is_firing = false
		return

	# 射程检查
	var to_target := combat_target.global_position - global_position
	var dist_px := to_target.length()
	var gun_range_px := params.gun.max_range * PIXELS_PER_METER

	if dist_px > gun_range_px * 1.2:
		is_firing = false
		return

	# 前置量计算
	var tgt_vel := Vector2(sin(combat_target.heading), -cos(combat_target.heading)) * combat_target.speed * PIXELS_PER_METER
	var bullet_speed := params.gun.muzzle_velocity * PIXELS_PER_METER
	var time_to_target := dist_px / maxf(bullet_speed, 1.0)
	var lead_pos := combat_target.global_position + tgt_vel * time_to_target
	var angle_to_lead := atan2((lead_pos - global_position).x, -(lead_pos - global_position).y)

	# 火控角检查
	var fire_cone := deg_to_rad(params.gun.fire_cone_half_angle)
	var angle_diff := absf(angle_difference(heading, angle_to_lead))

	_gun_lead_heading = angle_to_lead
	is_firing = dist_px <= gun_range_px and angle_diff <= fire_cone

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

	var base_spread := deg_to_rad(params.gun.spread_angle)
	# 高度惩罚：目标越高，散布越大（地面炮仰射更难命中）
	#   LOW  (0)  → ×1.0（基准）
	#   MID  (1)  → ×1.8（明显降低命中率）
	#   HIGH (2)  → ×3.0（极难命中，几乎只是骚扰）
	var alt_spread_mult := 1.0
	if combat_target and is_instance_valid(combat_target):
		var tgt_tier := combat_target.get_altitude_tier()
		if tgt_tier == AltitudeTier.MID:
			alt_spread_mult = 1.8
		elif tgt_tier >= AltitudeTier.HIGH:
			alt_spread_mult = 3.0
	var spread := base_spread * alt_spread_mult
	var dir := _gun_lead_heading + randf_range(-spread, spread)
	var muzzle_pos := global_position + Vector2(sin(heading), -cos(heading)) * 10.0
	bullet_manager.spawn_bullet(muzzle_pos, dir, params.gun.muzzle_velocity, self, params.gun.bullet_damage)

# ========== 伤害 ==========

func take_damage(amount: float) -> void:
	if is_destroyed:
		return
	hp -= amount
	if hp <= 0.0:
		hp = 0.0
		_start_destroy()

## 导弹/火箭等战斗部伤害：对地面单位一击必杀
## 设计意图（2026-04-21）：地面单位都是软目标（无装甲、无机动），
## 任何导弹命中都应该摧毁。HP 缩放只影响机炮对耗，不该让导弹需要多发补刀。
## 详见 docs/changelogs/player-ai-log.md
func take_missile_damage(_amount: float) -> void:
	if is_destroyed:
		return
	hp = 0.0
	_start_destroy()

func _start_destroy() -> void:
	is_destroyed = true
	is_firing = false
	combat_target = null
	_destroy_timer = 2.0
	# 不画殉爆闪光：爆炸特效只属于"被爆炸物击杀"的情况，由导弹/火箭/AOE 伤害源自行触发

func _update_destroy(delta: float) -> void:
	_destroy_timer -= delta
	if _destroy_timer <= 0.0:
		queue_free()

func _on_destroyed() -> void:
	_start_destroy()

# ========== 雷达 ==========

func is_in_radar_cone(target_global_pos: Vector2) -> bool:
	var radar_r := params.radar_range if params else 300.0
	var half_deg := params.radar_half_angle if params else 30.0
	var half_rad := deg_to_rad(half_deg)

	var to_target := target_global_pos - global_position
	var dist := to_target.length()
	if dist > radar_r or dist < 1.0:
		return false

	var angle_to := atan2(to_target.x, -to_target.y)
	var diff := absf(angle_difference(angle_to, heading))
	return diff <= half_rad

# ========== 绘制 ==========

func _draw() -> void:
	if is_destroyed:
		_draw_destroyed()
		return
	_draw_cloud_shadow()
	if is_hovered:
		_draw_radar_cone()
	_draw_ground_icon()
	_draw_lock_indicator()
	AircraftRenderer.draw_target_bracket(self, is_mission_target)
	_draw_data_label()

## 云下方阴影：淡灰蓝椭圆，暗示有云飘过地面单位头顶
func _draw_cloud_shadow() -> void:
	var weather := get_tree().get_first_node_in_group("weather")
	if weather == null or not weather.has_method("sample_density"):
		return
	var density: float = weather.sample_density(global_position)
	if density <= 0.0:
		return
	draw_circle(Vector2(4.0, 5.0), 18.0, Color(0.35, 0.42, 0.52, 0.22 * density))

func _draw_radar_cone() -> void:
	if not params:
		return
	var radar_r := params.radar_range
	var half_deg := params.radar_half_angle
	if radar_r <= 0.0:
		return

	var half_rad := deg_to_rad(half_deg)
	var segments := 24
	var color := GameConstants.team_radar_color(team, 0.12)

	# 绘制扇形（需要抵消节点自身旋转，因为雷达锥跟随 heading）
	var points := PackedVector2Array()
	points.append(Vector2.ZERO)
	for i in range(segments + 1):
		var t := float(i) / segments
		var angle := -half_rad + t * half_rad * 2.0
		points.append(Vector2(sin(angle), -cos(angle)) * radar_r)
	draw_colored_polygon(points, color)

	# 边线
	var edge_color := color * Color(1, 1, 1, 3.0)
	draw_line(Vector2.ZERO, Vector2(sin(-half_rad), -cos(-half_rad)) * radar_r, edge_color, 1.0)
	draw_line(Vector2.ZERO, Vector2(sin(half_rad), -cos(half_rad)) * radar_r, edge_color, 1.0)

func _draw_ground_icon() -> void:
	var color: Color = params.icon_color if params else Color.YELLOW
	var size := 10.0

	# 方形图标（区别于飞机三角）
	var half := size * 0.5
	var body := PackedVector2Array([
		Vector2(-half, -half),
		Vector2(half, -half),
		Vector2(half, half),
		Vector2(-half, half),
	])
	draw_colored_polygon(body, color)

	# 方向指示线
	var front := Vector2(0, -size * 0.8)
	draw_line(Vector2.ZERO, front, color.lightened(0.3), 1.5)

## 被锁定指示器：复用 AircraftRenderer.draw_lock_box（绿→红，随进度旋转收缩）
func _draw_lock_indicator() -> void:
	var p: float = clampf(incoming_lock_progress, 0.0, 1.0)
	if p <= 0.0 and not is_locked:
		return
	draw_set_transform(Vector2.ZERO, -rotation, Vector2.ONE)
	AircraftRenderer.draw_lock_box(self, p, is_locked)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func _draw_destroyed() -> void:
	var color := Color(0.5, 0.5, 0.5, 0.5)
	var size := 8.0
	draw_line(Vector2(-size, -size), Vector2(size, size), color, 2.0)
	draw_line(Vector2(size, -size), Vector2(-size, size), color, 2.0)

func _draw_data_label() -> void:
	if not _font:
		_font = ThemeDB.fallback_font

	var display_name: String = params.display_name if params else "GND"
	var font_size := 10
	var line_height := 12.0
	var label_offset := Vector2(14, -8)

	# 计算到玩家（team 0）的距离 —— 用全局 player_ref，避免每帧扫 parent.get_children()
	var dist_m := 0.0
	var pref := AircraftRenderer.player_ref
	if pref and is_instance_valid(pref) and not pref.is_destroyed:
		dist_m = global_position.distance_to(pref.global_position) / PIXELS_PER_METER

	var lines: PackedStringArray = PackedStringArray()
	# 名称
	lines.append(display_name)
	# 高度（地面单位永远 GND）
	lines.append("ALT GND")
	# 距离
	if dist_m < 1000.0:
		lines.append("RNG %dm" % roundi(dist_m))
	else:
		lines.append("RNG %.1fkm" % (dist_m / 1000.0))
	# 弹药
	if ammo > 0:
		lines.append("GUN %d" % ammo)

	var inv_rot := -rotation
	# 缩放补偿：标签大小不随摄像机缩放变化（与 AircraftRenderer.draw_data_label 一致）
	var zoom_scale := get_viewport_transform().get_scale()
	var inv_zoom := 1.0 / maxf(zoom_scale.x, 0.01)
	var max_w := 0.0
	for line in lines:
		var w := _font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		max_w = maxf(max_w, w)
	var box_w := max_w + 6.0
	var box_h := lines.size() * line_height + 4.0

	var _glc := GameConstants.ground_label_colors(team)
	var text_color: Color = _glc[0]
	var bg_color: Color = _glc[1]

	var rotated_offset := (label_offset * inv_zoom).rotated(inv_rot)
	var scale_v := Vector2(inv_zoom, inv_zoom)
	draw_set_transform(rotated_offset, inv_rot, scale_v)
	draw_rect(Rect2(-1, -1, box_w, box_h), bg_color)
	for i in lines.size():
		draw_string(_font, Vector2(2, 10 + i * line_height), lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, text_color)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
