class_name SAMUnit
extends GroundUnit

## 防空导弹车：360° 圆形雷达覆盖，范围内锁定即发射

var missiles_remaining: int = 4
var _missile_cooldown: float = 0.0

func _ready() -> void:
	super._ready()
	if params and params.missile:
		missiles_remaining = params.missile.max_count

func _physics_process(delta: float) -> void:
	if is_destroyed:
		_update_destroy(delta)
		queue_redraw()
		return

	StatusEffects.tick(self, delta)
	_update_movement(delta)
	_update_target_selection()
	_update_sam_missile(delta)
	update_lock_line_state(delta)
	queue_redraw()

## SAM 导弹发射
func _update_sam_missile(delta: float) -> void:
	_missile_cooldown = maxf(_missile_cooldown - delta, 0.0)

	# JAM 干扰：封锁导弹发射
	if status_jam_active:
		return
	if not missile_manager or not params or not params.missile:
		return
	if missiles_remaining <= 0:
		return
	if _missile_cooldown > 0.0:
		return
	if combat_target == null or not is_instance_valid(combat_target) or combat_target.is_destroyed:
		return

	# ── 保险 1：目标必须仍在雷达范围内（防止因为锁定衰减滞后而打空）
	if not is_in_radar_cone(combat_target.global_position):
		combat_target = null
		return

	# ── 保险 2：目标不能处于"锁定免疫"/光学隐形状态
	if combat_target.is_lock_immune():
		combat_target = null
		return
	if combat_target is Aircraft and combat_target.is_cloaked:
		combat_target = null
		return

	# ── 保险 3：距离要在导弹有效射程内（min/max）
	var dist_px := global_position.distance_to(combat_target.global_position)
	var dist_m := dist_px / PIXELS_PER_METER
	var max_range_m := params.missile.max_range_rear * params.missile.front_rear_ratio
	if dist_m < params.missile.min_range or dist_m > max_range_m:
		return

	# 检查锁定
	var lock_time_val := params.lock_time if params else 3.0
	var lock_progress: float = radar_targets.get(combat_target, 0.0)
	if lock_progress < lock_time_val:
		return

	# 检查是否已有在飞导弹
	if missile_manager.has_active_missile_at(self, combat_target):
		return

	# 发射
	missile_manager.spawn_missile(self, combat_target, params.missile)
	notify_missile_fired_at(combat_target)
	missiles_remaining -= 1
	_missile_cooldown = params.missile.cooldown

## SAM 360° 圆形雷达：只检查距离，不检查角度
func is_in_radar_cone(target_global_pos: Vector2) -> bool:
	var radar_r := params.radar_range if params else 5000.0
	var dist := global_position.distance_to(target_global_pos)
	return dist <= radar_r and dist > 1.0

## SAM 装载导弹（影响锁定线显示）
func has_missile_capability() -> bool:
	return params != null and params.missile != null and missiles_remaining > 0

## 覆写 CombatUnit：SAM 能否对玩家发射导弹
func _lock_line_can_engage_player() -> bool:
	if not has_missile_capability():
		return false
	if _missile_cooldown > 0.05:
		return false
	var pref: Aircraft = AircraftRenderer.player_ref
	if pref == null:
		return false
	return combat_target == pref

## SAM 不用机炮
func _update_combat(_delta: float) -> void:
	pass

func _update_gun(_delta: float) -> void:
	pass

# ========== 绘制 ==========

func _draw() -> void:
	if is_destroyed:
		_draw_destroyed()
		return
	if is_hovered:
		_draw_radar_circle()
	_draw_sam_icon()
	_draw_lock_indicator()
	AircraftRenderer.draw_target_bracket(self, is_mission_target)
	AircraftRenderer.draw_status_icons(self)
	_draw_data_label()

## 圆形雷达范围（替代扇形）
func _draw_radar_circle() -> void:
	if not params:
		return
	var radar_r := params.radar_range
	if radar_r <= 0.0:
		return

	var color := GameConstants.team_radar_color(team, 0.08)

	# 填充圆
	var segments := 48
	var points := PackedVector2Array()
	for i in range(segments):
		var angle := float(i) / segments * TAU
		# 抵消节点旋转
		points.append(Vector2(cos(angle), sin(angle)).rotated(-rotation) * radar_r)
	draw_colored_polygon(points, color)

	# 边线
	var edge_color := Color(color.r, color.g, color.b, 0.25)
	for i in range(segments):
		var a0 := float(i) / segments * TAU
		var a1 := float(i + 1) / segments * TAU
		var p0 := Vector2(cos(a0), sin(a0)).rotated(-rotation) * radar_r
		var p1 := Vector2(cos(a1), sin(a1)).rotated(-rotation) * radar_r
		draw_line(p0, p1, edge_color, 1.0)

func _draw_sam_icon() -> void:
	var color: Color = params.icon_color if params else Color.RED
	var size := 10.0

	# 底盘方块
	var half := size * 0.5
	var body := PackedVector2Array([
		Vector2(-half, -half),
		Vector2(half, -half),
		Vector2(half, half),
		Vector2(-half, half),
	])
	draw_colored_polygon(body, color.darkened(0.2))

	# 中心菱形标记（表示导弹发射器）
	var d := size * 0.3
	var diamond := PackedVector2Array([
		Vector2(0, -d),
		Vector2(d, 0),
		Vector2(0, d),
		Vector2(-d, 0),
	])
	draw_colored_polygon(diamond, color.lightened(0.3))

func _draw_data_label() -> void:
	if not _font:
		_font = ThemeDB.fallback_font

	var display_name: String = params.display_name if params else "SAM"
	var font_size := 10
	var line_height := 12.0
	var label_offset := Vector2(14, -8)

	# 计算到玩家（team 0）的距离
	var dist_m := 0.0
	var parent_node := get_parent()
	if parent_node:
		for node in parent_node.get_children():
			if node is Aircraft and node.is_player_squad() and not node.is_destroyed:
				dist_m = global_position.distance_to(node.global_position) / PIXELS_PER_METER
				break

	var lines: PackedStringArray = PackedStringArray()
	# 名称
	lines.append(display_name)
	if not _should_draw_compact_data_label():
		# 高度
		lines.append("ALT GND")
		# 距离
		if dist_m < 1000.0:
			lines.append("RNG %dm" % roundi(dist_m))
		else:
			lines.append("RNG %.1fkm" % (dist_m / 1000.0))
		# 导弹数
		lines.append("MSL %d" % missiles_remaining)

	var inv_rot := -rotation
	# 缩放补偿：标签大小不随摄像机缩放变化（与 ground_unit.gd 一致）
	var zoom_scale := get_viewport_transform().get_scale()
	var inv_zoom := 1.0 / maxf(zoom_scale.x, 0.01)
	var max_w := 0.0
	for line in lines:
		var w := _font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		max_w = maxf(max_w, w)
	var box_w := max_w + 6.0
	var box_h := lines.size() * line_height + 4.0

	# FactionPalette 统一（友好阵营 0/2 冷色系 / 敌暖色系）
	var _lc := GameConstants.ground_label_colors(team)
	var text_color: Color = _lc[0]
	var bg_color: Color = _lc[1]

	var rotated_offset := (label_offset * inv_zoom).rotated(inv_rot)
	var scale_v := Vector2(inv_zoom, inv_zoom)
	draw_set_transform(rotated_offset, inv_rot, scale_v)
	draw_rect(Rect2(-1, -1, box_w, box_h), bg_color)
	for i in lines.size():
		draw_string(_font, Vector2(2, 10 + i * line_height), lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, text_color)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
