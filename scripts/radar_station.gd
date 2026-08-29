class_name RadarStation
extends GroundUnit

## 雷达站：大范围雷达，数据链共享锁定信息给附近友方地面单位
## 无武器，不选定目标

@export var datalink_range: float = 4000.0  ## 数据链共享距离（像素）
var _dish_rotation: float = 0.0             ## 雷达盘旋转动画
const DISH_SPIN_RATE := 1.5                 ## rad/s 雷达盘转速
const DATALINK_INTERVAL := 0.5              ## 数据链更新间隔
var _datalink_timer: float = 0.0

func _ready() -> void:
	super._ready()
	_dish_rotation = randf() * TAU  # 随机初始角度

func _physics_process(delta: float) -> void:
	if is_destroyed:
		_update_destroy(delta)
		queue_redraw()
		return

	_update_movement(delta)
	_update_dish(delta)
	_update_datalink(delta)
	queue_redraw()

## 雷达盘持续旋转
func _update_dish(delta: float) -> void:
	_dish_rotation += DISH_SPIN_RATE * delta
	if _dish_rotation > TAU:
		_dish_rotation -= TAU

## 数据链共享：将锁定目标信息注入附近友方地面单位
func _update_datalink(delta: float) -> void:
	_datalink_timer -= delta
	if _datalink_timer > 0.0:
		return
	_datalink_timer = DATALINK_INTERVAL

	if not get_parent():
		return

	var lock_time_val := params.lock_time if params else 3.0

	# 收集自己已锁定的目标
	var locked_targets: Dictionary = {}  # { CombatUnit: float }
	for target_key in radar_targets:
		var progress: float = radar_targets[target_key]
		if progress >= lock_time_val:
			locked_targets[target_key] = progress

	if locked_targets.is_empty():
		return

	# 扫描附近友方地面单位
	for child in get_parent().get_children():
		if child == self:
			continue
		if not child is GroundUnit:
			continue
		var gu: GroundUnit = child
		if gu.is_destroyed or gu.team != team:
			continue
		if global_position.distance_to(gu.global_position) > datalink_range:
			continue

		# 注入锁定信息（cap 在对方 lock_time - 0.5，不立刻触发开火）
		var gu_lock_time := gu.params.lock_time if gu.params else 3.0
		var inject_cap := maxf(gu_lock_time - 0.5, 0.1)
		for target_key in locked_targets:
			if not is_instance_valid(target_key):
				continue
			var existing: float = gu.radar_targets.get(target_key, 0.0)
			# 只提升，不覆盖已有更高的值
			if existing < inject_cap:
				gu.radar_targets[target_key] = maxf(existing, inject_cap)

## 雷达站不选定目标
func _update_target_selection() -> void:
	combat_target = null

## 无武器
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
		_draw_radar_cone()
	_draw_radar_icon()
	_draw_datalink_range()
	_draw_data_label()

func _draw_radar_icon() -> void:
	var color: Color = params.icon_color if params else Color.CYAN
	var size := 10.0

	# 底座（小方块）
	var base_half := size * 0.35
	var base := PackedVector2Array([
		Vector2(-base_half, -base_half),
		Vector2(base_half, -base_half),
		Vector2(base_half, base_half),
		Vector2(-base_half, base_half),
	])
	draw_colored_polygon(base, color.darkened(0.4))

	# 旋转雷达盘（扇形弧线）
	var dish_rel := _dish_rotation - heading  # 相对底盘旋转
	var dish_radius := size * 0.8
	var dish_start := dish_rel - 0.4
	var dish_end := dish_rel + 0.4
	var segments := 8
	for i in range(segments):
		var t0 := lerpf(dish_start, dish_end, float(i) / segments)
		var t1 := lerpf(dish_start, dish_end, float(i + 1) / segments)
		var p0 := Vector2(sin(t0), -cos(t0)) * dish_radius
		var p1 := Vector2(sin(t1), -cos(t1)) * dish_radius
		draw_line(p0, p1, color, 2.0)

	# 雷达盘中心到弧线中心的连线
	var dish_center := Vector2(sin(dish_rel), -cos(dish_rel)) * dish_radius * 0.5
	draw_line(Vector2.ZERO, dish_center, color.darkened(0.2), 1.5)

	# 中心点
	draw_circle(Vector2.ZERO, 2.0, color)

## 绘制数据链范围（虚线圆）
func _draw_datalink_range() -> void:
	var color := GameConstants.team_datalink_color(team)
	var radius := datalink_range
	# 简化：绘制点状圆
	var segments := 32
	for i in range(segments):
		var angle := float(i) / segments * TAU
		var p := Vector2(cos(angle), sin(angle)) * radius
		# 每隔一段画一段弧
		if i % 2 == 0:
			var next_angle := float(i + 1) / segments * TAU
			var p2 := Vector2(cos(next_angle), sin(next_angle)) * radius
			# 需要反向旋转来抵消节点自身旋转
			draw_line(p.rotated(-rotation), p2.rotated(-rotation), color, 1.0)

func _status_label_lines(compact: bool) -> PackedStringArray:
	var display_name: String = params.display_name if params else "RADAR"
	var lines := PackedStringArray([
		AircraftRenderer.english_status_identity(display_name, "RADAR")])
	if compact:
		return lines
	lines.append(AircraftRenderer.status_hp_text(
		hp, params.max_hp if params else hp))
	var lock_time_val := params.lock_time if params else 3.0
	var locked_count := 0
	for key in radar_targets:
		if radar_targets[key] >= lock_time_val:
			locked_count += 1
	if locked_count > 0:
		lines.append("TRK %d" % locked_count)
	lines.append("DATA LINK ACTIVE" if datalink_range > 0.0 else "DATA LINK OFFLINE")
	return lines
