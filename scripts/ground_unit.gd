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
var _compact_data_label_active: bool = false


func _should_draw_compact_data_label() -> bool:
	var view_scale := AircraftRenderer.label_lod_scale(self)
	_compact_data_label_active = AircraftRenderer.next_compact_label_state(
		_compact_data_label_active, view_scale)
	return AircraftRenderer.compact_label_visible(_compact_data_label_active,
		Input.is_key_pressed(KEY_ALT))

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
	var perf_detail := PerfBuckets.detail_capture_enabled()
	var perf_t0 := Time.get_ticks_usec() if perf_detail else 0
	_physics_process_impl(delta)
	if perf_detail:
		PerfBuckets.tick("ground_phys", Time.get_ticks_usec() - perf_t0)


func _physics_process_impl(delta: float) -> void:
	if is_destroyed:
		_update_destroy(delta)
		queue_redraw()
		return

	StatusEffects.tick(self, delta)
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

## 跨帧目标引用可能已经释放；必须先以 Variant 验证，再收窄到战斗单位类型。
func _live_combat_unit_ref(value: Variant) -> CombatUnit:
	if typeof(value) != TYPE_OBJECT or value == null or not is_instance_valid(value):
		return null
	if not (value is CombatUnit):
		return null
	var unit := value as CombatUnit
	return unit if not unit.is_destroyed else null


## 防空子类共用的 Aircraft 目标边界。
func _live_aircraft_ref(value: Variant) -> Aircraft:
	var unit := _live_combat_unit_ref(value)
	return unit as Aircraft if unit is Aircraft else null

## 简单 AI：从已锁定目标中选最近的敌方
func _update_target_selection() -> void:
	# 通用高优先目标 seam：正式战区气氛层近距时写入玩家；仍要求本单位真实锁定。
	var preferred_value: Variant = get_meta(CombatUnit.META_PREFERRED_COMBAT_TARGET) \
		if has_meta(CombatUnit.META_PREFERRED_COMBAT_TARGET) else null
	var preferred := _live_combat_unit_ref(preferred_value)
	if preferred != null:
		var preferred_lock := params.lock_time if params else 3.0
		if is_hostile_to(preferred) \
				and radar_targets.get(preferred, 0.0) >= preferred_lock:
			combat_target = preferred
			return
	# 当前目标仍有效且已锁定 → 保持
	var current_value: Variant = combat_target
	var current := _live_combat_unit_ref(current_value)
	if current != null:
		var lock_time_val := params.lock_time if params else 3.0
		if radar_targets.get(current, 0.0) >= lock_time_val:
			return

	# 寻找新目标
	combat_target = null
	var best_dist := INF
	var lock_time_val := params.lock_time if params else 3.0
	for target_key in radar_targets:
		var target_unit := _live_combat_unit_ref(target_key)
		if target_unit == null or radar_targets.get(target_unit, 0.0) < lock_time_val \
				or not is_hostile_to(target_unit):
			continue
		var d := global_position.distance_to(target_unit.global_position)
		if d < best_dist:
			best_dist = d
			combat_target = target_unit

# ========== 战斗 ==========

func _update_combat(_delta: float) -> void:
	var target_value: Variant = combat_target
	var target := _live_combat_unit_ref(target_value)
	if target == null:
		combat_target = null
		is_firing = false
		return

	if not params or not params.gun:
		is_firing = false
		return

	# 射程检查
	var to_target := target.global_position - global_position
	var dist_px := to_target.length()
	var gun_range_px := params.gun.max_range * PIXELS_PER_METER

	if dist_px > gun_range_px * 1.2:
		is_firing = false
		return

	# 前置量计算
	var tgt_vel := Vector2(sin(target.heading), -cos(target.heading)) * target.speed * PIXELS_PER_METER
	var bullet_speed := params.gun.muzzle_velocity * PIXELS_PER_METER
	var time_to_target := dist_px / maxf(bullet_speed, 1.0)
	var lead_pos := target.global_position + tgt_vel * time_to_target
	var angle_to_lead := atan2((lead_pos - global_position).x, -(lead_pos - global_position).y)

	# 火控角检查
	var fire_cone := deg_to_rad(params.gun.fire_cone_half_angle)
	var angle_diff := absf(angle_difference(heading, angle_to_lead))

	_gun_lead_heading = angle_to_lead
	is_firing = dist_px <= gun_range_px and angle_diff <= fire_cone

func _update_gun(delta: float) -> void:
	# JAM 干扰：地面单位也封锁机炮
	if status_jam_active:
		is_firing = false
		_fire_cooldown = maxf(_fire_cooldown - delta, 0.0)
		return
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
	var target_value: Variant = combat_target
	var target := _live_combat_unit_ref(target_value)
	if target != null:
		var tgt_tier := target.get_altitude_tier()
		if tgt_tier == AltitudeTier.MID:
			alt_spread_mult = 1.8
		elif tgt_tier >= AltitudeTier.HIGH:
			alt_spread_mult = 3.0
	var spread := base_spread * alt_spread_mult
	var dir := _gun_lead_heading + randf_range(-spread, spread)
	var muzzle_pos := global_position + Vector2(sin(heading), -cos(heading)) * 10.0
	bullet_manager.spawn_bullet(muzzle_pos, dir, params.gun.muzzle_velocity, self, params.gun.bullet_damage)

# ========== 伤害 ==========

func take_damage(amount: float, attacker: Node = null, kind: String = "") -> void:
	if is_destroyed:
		return
	if attacker != null:
		set_meta("_pending_attacker", attacker)
	if kind != "":
		set_meta("_last_damage_kind", kind)
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
	# 与飞机击杀归因保持同一语义：只有有效攻击者才写入 team；自然销毁不伪装成玩家击杀。
	var attacker: Node = null
	if has_meta("_pending_attacker"):
		attacker = CombatUnit.safe_attacker(get_meta("_pending_attacker"))
	if attacker is CombatUnit:
		set_meta("kill_attacker_team", (attacker as CombatUnit).team)
		set_meta("kill_attacker_id", attacker.get_instance_id())
	if has_meta("_pending_attacker"):
		remove_meta("_pending_attacker")
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
	var perf_detail := PerfBuckets.detail_capture_enabled()
	var perf_t0 := Time.get_ticks_usec() if perf_detail else 0
	_draw_impl()
	if perf_detail:
		PerfBuckets.tick("ground_draw", Time.get_ticks_usec() - perf_t0)


func _draw_impl() -> void:
	if is_destroyed:
		_draw_destroyed()
		return
	_draw_cloud_shadow()
	if is_hovered:
		_draw_radar_cone()
	_draw_ground_icon()
	_draw_lock_indicator()
	AircraftRenderer.draw_target_bracket(self, is_mission_target)
	AircraftRenderer.draw_status_icons(self)
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
	var inv_zoom: float = AircraftRenderer.screen_space_inverse_scale(self)
	draw_set_transform(Vector2.ZERO, -rotation, Vector2.ONE * inv_zoom)
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
	var compact := _should_draw_compact_data_label()
	var xform := get_global_transform_with_canvas()
	var view_scale := xform.basis_xform(Vector2.RIGHT).length()
	var screen_offset := AircraftRenderer.unit_status_screen_offset_for(
		_status_label_icon_radius_world(), view_scale, xform.origin)
	AircraftRenderer.draw_unit_status_panel(self, _font,
		_status_label_lines(compact), team, screen_offset)


## 子类只覆写内容，不得再复制状态栏几何、旋转或缩放代码。
func _status_label_lines(compact: bool) -> PackedStringArray:
	var display_name: String = params.display_name if params else "GND"
	var lines := PackedStringArray([display_name])
	if compact:
		return lines
	lines.append("ALT GND")
	var dist_m := _status_label_distance_m()
	if dist_m < 1000.0:
		lines.append("RNG %dm" % roundi(dist_m))
	else:
		lines.append("RNG %.1fkm" % (dist_m / 1000.0))
	if ammo > 0:
		lines.append("GUN %d" % ammo)
	return lines


func _status_label_distance_m() -> float:
	var pref := AircraftRenderer.safe_player_ref()
	if pref == null or pref.is_destroyed:
		return 0.0
	return global_position.distance_to(pref.global_position) / PIXELS_PER_METER


func _status_label_icon_radius_world() -> float:
	return 18.0
