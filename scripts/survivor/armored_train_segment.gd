class_name ArmoredTrainSegment
extends GroundUnit

## 武装列车的一节真实锁定/伤害目标。接战后全车可锁定，
## 但只有当前车尾能接收新命中；其余段在伤害入口 fail-closed。

var train_manager: Variant = null
var segment_index: int = -1
var targetable: bool = false
var damageable: bool = false
var detached: bool = false
var _last_deflect_msec: int = 0
var _bogie_half_span_px: float = 88.0
var _detach_velocity_px_s: Vector2 = Vector2.ZERO
var _detach_spin_rad_s: float = 0.0

const SEGMENT_LENGTH_PX := 236.0
const SEGMENT_WIDTH_PX := 84.0
const LOCOMOTIVE_INDEX := 0
const DRIVE_TENDER_INDEX := 1
const RAILGUN_INDEX := 2
const VLS_ALPHA_INDEX := 3
const VLS_BRAVO_INDEX := 4
const RADAR_INDEX := 5
const FIRE_CONTROL_INDEX := 6
const FLAK_ALPHA_INDEX := 7
const FLAK_BRAVO_INDEX := 8
const CIWS_ALPHA_INDEX := 9
const CIWS_BRAVO_INDEX := 10
const ARMORED_MAGAZINE_INDEX := 11
const TAIL_BATTERY_INDEX := 12
const REAR_GUARD_INDEX := 13


func configure(manager: Node, index: int) -> void:
	train_manager = manager
	segment_index = index
	callsign = "IRON SERPENT-%02d" % (index + 1)
	is_mission_target = false
	set_meta("boss_unit", true)
	set_meta("skip_far_cleanup", true)
	set_meta("no_kill_reward", true)
	set_meta("destruction_class", "large")
	set_meta(CombatUnit.META_FACTION_CONVERSION_LOCKED, true)


func _physics_process(delta: float) -> void:
	if is_destroyed:
		if detached:
			global_position += _detach_velocity_px_s * delta
			rotation += _detach_spin_rad_s * delta
			_detach_velocity_px_s *= exp(-1.2 * delta)
			_detach_spin_rad_s *= exp(-0.8 * delta)
		_update_destroy(delta)
		queue_redraw()
		return
	StatusEffects.tick(self, delta)
	queue_redraw()


func set_train_pose(world_position: Vector2, world_heading: float,
		world_speed: float, bogie_half_span_px: float = 88.0) -> void:
	if detached:
		return
	global_position = world_position
	heading = world_heading
	rotation = world_heading
	speed = world_speed
	_bogie_half_span_px = bogie_half_span_px
	queue_redraw()


func set_targetable(value: bool) -> void:
	targetable = value and not is_destroyed
	is_mission_target = targetable
	if not targetable:
		is_locked = false
		incoming_lock_progress = 0.0
	queue_redraw()


func set_damageable(value: bool) -> void:
	damageable = value and targetable and not is_destroyed
	queue_redraw()


func can_accept_new_hit(_kind: String) -> bool:
	return damageable and not is_destroyed


func is_lock_immune() -> bool:
	return not targetable or is_destroyed


func take_damage(amount: float, attacker: Node = null, kind: String = "") -> void:
	if not can_accept_new_hit(kind):
		_deflect_hit()
		return
	super.take_damage(amount, attacker, kind)


func take_missile_damage(amount: float) -> void:
	# 装甲列车每节按真实伤害结算，不继承普通 GroundUnit 的导弹一发必杀。
	take_damage(amount, null, "missile")


func take_atmosphere_damage(amount: float, attacker: Node = null,
		kind: String = "") -> void:
	if not can_accept_new_hit(kind):
		return
	super.take_atmosphere_damage(amount, attacker, kind)


func _deflect_hit() -> void:
	var now := Time.get_ticks_msec()
	if now - _last_deflect_msec < 350:
		return
	_last_deflect_msec = now
	EventLogger.log_event("BOSS", "ArmoredTrainArmorDeflect",
		"segment=%d active_tail=%d" % [segment_index + 1, _manager_active_tail() + 1])
	queue_redraw()


func _start_destroy() -> void:
	if is_destroyed:
		return
	super._start_destroy()
	targetable = false
	damageable = false
	is_mission_target = false
	is_locked = false
	incoming_lock_progress = 0.0
	_detach_from_train()
	var manager: Variant = train_manager
	if typeof(manager) == TYPE_OBJECT and manager != null and is_instance_valid(manager) \
			and manager.has_method("on_segment_broken"):
		manager.on_segment_broken(segment_index, self)


func _detach_from_train() -> void:
	if detached:
		return
	detached = true
	var forward := Vector2(sin(heading), -cos(heading))
	var side := Vector2(forward.y, -forward.x)
	var side_sign := -1.0 if segment_index % 2 == 0 else 1.0
	_detach_velocity_px_s = forward * speed * GameConstants.PIXELS_PER_METER * 0.72 \
		+ side * side_sign * 30.0
	_detach_spin_rad_s = side_sign * 0.42


func mount_world_pose(local_offset: Vector2) -> Dictionary:
	return {"position": global_position + local_offset.rotated(heading),
		"heading": heading}


func _draw_cloud_shadow() -> void:
	pass


func _draw_ground_icon() -> void:
	var hostile := GameConstants.team_color(team)
	var exposed_color := Color(0.25, 0.21, 0.18)
	var locked_color := Color(0.13, 0.14, 0.15)
	var armor := exposed_color if targetable else locked_color
	var half_w := SEGMENT_WIDTH_PX * 0.5
	var half_l := SEGMENT_LENGTH_PX * 0.5
	var body := Rect2(-half_w, -half_l, half_w * 2.0, half_l * 2.0)
	draw_rect(body, armor, true)
	var border := hostile if damageable else hostile.darkened(0.18 if targetable else 0.48)
	draw_rect(body, border, false, 3.0 if damageable else 2.0)
	# 两组转向架的位置来自铁路前后双采样点；长车厢过弯时轮组仍压在轨道上。
	for y in [-_bogie_half_span_px, _bogie_half_span_px]:
		draw_rect(Rect2(-half_w - 4.0, y - 11.0, half_w * 2.0 + 8.0, 22.0),
			Color(0.07, 0.08, 0.09), true)
		for x in [-half_w - 3.0, half_w + 3.0]:
			draw_circle(Vector2(x, y - 5.0), 4.5, Color(0.02, 0.03, 0.03))
			draw_circle(Vector2(x, y + 5.0), 4.5, Color(0.02, 0.03, 0.03))
	# 车钩端部留出明确空隙，实际连接线由 manager 在车体下层跨弯绘制。
	draw_line(Vector2(0.0, -half_l), Vector2(0.0, -half_l - 8.0),
		Color(0.08, 0.09, 0.10), 5.0)
	draw_line(Vector2(0.0, half_l), Vector2(0.0, half_l + 8.0),
		Color(0.08, 0.09, 0.10), 5.0)
	_draw_theme(segment_index, hostile)
	if not targetable:
		# 进场阶段的深色交叉装甲梁；接战后全车都移除遮挡。
		draw_line(Vector2(-half_w + 5.0, -half_l + 8.0),
			Vector2(half_w - 5.0, half_l - 8.0), Color(hostile, 0.34), 2.0)
		draw_line(Vector2(half_w - 5.0, -half_l + 8.0),
			Vector2(-half_w + 5.0, half_l - 8.0), Color(hostile, 0.34), 2.0)
	elif damageable:
		# 尾节是唯一可打断段，用四角弱点标记区别于其他可锁定车厢。
		var bracket := hostile.lightened(0.35)
		for x in [-half_w - 6.0, half_w + 6.0]:
			var inward := 12.0 if x < 0.0 else -12.0
			for y in [-half_l - 6.0, half_l + 6.0]:
				var inward_y := 18.0 if y < 0.0 else -18.0
				draw_line(Vector2(x, y), Vector2(x + inward, y), bracket, 3.0)
				draw_line(Vector2(x, y), Vector2(x, y + inward_y), bracket, 3.0)


func _draw_theme(index: int, color: Color) -> void:
	match index:
		LOCOMOTIVE_INDEX:
			# 斜切装甲车鼻、驾驶窗与纵向散热栅。
			draw_colored_polygon(PackedVector2Array([
				Vector2(-42.0, -96.0), Vector2(-26.0, -118.0),
				Vector2(26.0, -118.0), Vector2(42.0, -96.0)]), color.darkened(0.28))
			draw_rect(Rect2(-28.0, -94.0, 56.0, 14.0), color.darkened(0.55), true)
			for y in [-58.0, -38.0, -18.0, 2.0, 22.0, 42.0, 62.0]:
				draw_line(Vector2(-26.0, y), Vector2(26.0, y), color.darkened(0.18), 2.0)
		DRIVE_TENDER_INDEX:
			for x in [-24.0, 24.0]:
				draw_line(Vector2(x, -88.0), Vector2(x, 88.0), color.darkened(0.08), 4.0)
			for y in [-72.0, -24.0, 24.0, 72.0]:
				draw_rect(Rect2(-30.0, y - 10.0, 60.0, 20.0), color.darkened(0.42), true)
		RAILGUN_INDEX:
			for y in [-72.0, 72.0]:
				draw_circle(Vector2(0.0, y), 10.0, color.darkened(0.48))
				draw_arc(Vector2(0.0, y), 10.0, 0.0, TAU, 16, color, 2.0)
			var manager: Variant = train_manager
			var world_heading := heading
			if typeof(manager) == TYPE_OBJECT and manager != null and is_instance_valid(manager) \
					and manager.has_method("railgun_heading"):
				world_heading = float(manager.railgun_heading())
			draw_set_transform(Vector2.ZERO, angle_difference(rotation, world_heading))
			draw_circle(Vector2.ZERO, 18.0, color.darkened(0.42))
			draw_line(Vector2(-8.0, -8.0), Vector2(-8.0, -72.0), color, 5.0)
			draw_line(Vector2(8.0, -8.0), Vector2(8.0, -72.0), color, 5.0)
			draw_line(Vector2(-8.0, -70.0), Vector2(8.0, -70.0), color.lightened(0.35), 4.0)
			draw_set_transform(Vector2.ZERO, 0.0)
		VLS_ALPHA_INDEX, VLS_BRAVO_INDEX:
			var stagger := -8.0 if index == VLS_ALPHA_INDEX else 8.0
			for x in [-23.0, 23.0]:
				for y in [-78.0, -26.0, 26.0, 78.0]:
					draw_rect(Rect2(x - 9.0, y + stagger - 9.0, 18.0, 18.0),
						color.darkened(0.44), true)
					draw_rect(Rect2(x - 9.0, y + stagger - 9.0, 18.0, 18.0),
						color, false, 1.5)
		RADAR_INDEX:
			draw_rect(Rect2(-30.0, -72.0, 60.0, 144.0), color.darkened(0.42), true)
			draw_line(Vector2.ZERO, Vector2(0.0, -84.0), color.lightened(0.25), 3.0)
			draw_arc(Vector2(0.0, -83.0), 22.0, PI, TAU, 18, color, 3.0)
			draw_circle(Vector2(0.0, -83.0), 3.0, color.lightened(0.45))
		FIRE_CONTROL_INDEX:
			for y in [-52.0, 52.0]:
				draw_circle(Vector2.ZERO + Vector2(0.0, y), 13.0, color.darkened(0.40))
				draw_arc(Vector2(0.0, y), 16.0, PI, TAU, 18, color, 3.0)
			draw_line(Vector2(0.0, -68.0), Vector2(0.0, 68.0), color.lightened(0.2), 2.0)
		FLAK_ALPHA_INDEX, FLAK_BRAVO_INDEX:
			for y in [-52.0, 52.0]:
				draw_circle(Vector2(0.0, y), 15.0, color.darkened(0.42))
				draw_line(Vector2(-7.0, y), Vector2(-7.0, y - 25.0), color, 4.0)
				draw_line(Vector2(7.0, y), Vector2(7.0, y - 25.0), color, 4.0)
		CIWS_ALPHA_INDEX, CIWS_BRAVO_INDEX:
			draw_circle(Vector2.ZERO, 15.0, color.darkened(0.45))
			draw_arc(Vector2.ZERO, 15.0, 0.0, TAU, 20, color, 2.0)
			draw_circle(Vector2(0.0, 42.0), 8.0, color.darkened(0.22))
			draw_line(Vector2.ZERO, Vector2(0.0, -37.0), color.lightened(0.25), 5.0)
		ARMORED_MAGAZINE_INDEX:
			for y in [-78.0, -42.0, -6.0, 30.0, 66.0]:
				draw_rect(Rect2(-30.0, y - 13.0, 60.0, 26.0), color.darkened(0.46), true)
				draw_line(Vector2(-34.0, y + 16.0), Vector2(34.0, y + 16.0), color, 2.0)
		TAIL_BATTERY_INDEX:
			for y in [-58.0, 58.0]:
				draw_circle(Vector2(0.0, y), 13.0, color.darkened(0.45))
				draw_line(Vector2(0.0, y), Vector2(0.0, y + 40.0), color, 5.0)
		REAR_GUARD_INDEX:
			draw_colored_polygon(PackedVector2Array([
				Vector2(-42.0, 96.0), Vector2(-26.0, 118.0),
				Vector2(26.0, 118.0), Vector2(42.0, 96.0)]), color.darkened(0.32))
			draw_circle(Vector2(0.0, 54.0), 13.0, color.darkened(0.45))
			draw_line(Vector2(0.0, 54.0), Vector2(0.0, 108.0), color, 5.0)


func _draw_data_label() -> void:
	# 十四块并排标签会重新形成“一坨”；常态显示尾节，
	# 其他车厢在悬停或锁定时再显示。
	if not damageable and not is_hovered and not is_locked:
		return
	super._draw_data_label()


func _status_label_lines(compact: bool) -> PackedStringArray:
	var name := params.display_name if params else "TRAIN CAR"
	var lines := PackedStringArray([name])
	if compact:
		return lines
	if damageable:
		lines.append(AircraftRenderer.status_hp_text(hp, params.max_hp if params else hp))
		lines.append("BREAKABLE %d/14" % (segment_index + 1))
	elif targetable:
		lines.append("LINKED ARMOR")
		lines.append("BREAK CAR %02d FIRST" % (_manager_active_tail() + 1))
	else:
		lines.append("STAGED")
	var manager: Variant = train_manager
	if typeof(manager) == TYPE_OBJECT and manager != null and is_instance_valid(manager) \
			and manager.has_method("current_speed_kmh"):
		lines.append(AircraftRenderer.status_ground_speed_text(
			float(manager.current_speed_kmh()) / 3.6))
	return lines


func _status_label_icon_radius_world() -> float:
	return 82.0


func _manager_active_tail() -> int:
	var manager: Variant = train_manager
	if typeof(manager) == TYPE_OBJECT and manager != null and is_instance_valid(manager) \
			and manager.has_method("active_tail_index"):
		return int(manager.active_tail_index())
	return -1
