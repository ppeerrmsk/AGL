class_name Aircraft
extends Node2D

const GRAVITY: float = 9.81
const PIXELS_PER_METER: float = 0.5  ## 1米 = 0.5像素

@export var params: AircraftParams
@export var team: int = 0  ## 0=友方, 1=敌方
@export var initial_heading_deg: float = 0.0  ## 度 初始航向（0=北, 90=东, 180=南）

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

# --- 燃油 / 加力 ---
var fuel: float = 3000.0
var is_afterburner: bool = false
var _ab_cooldown: float = 0.0        ## 加力状态切换冷却

# --- 战斗 ---
var combat_target: Aircraft = null  ## 锁定追踪的敌机
var is_firing: bool = false
var ammo: int = 500
var _fire_cooldown: float = 0.0
var _gun_lead_heading: float = 0.0  ## 前置射击方向（由 _update_combat 计算）
var _in_rear_hemisphere: bool = false  ## 是否处于敌机后半球（由 _update_combat 计算）
var bullet_manager: Node2D = null   ## 由 main.gd 注入

# --- 击毁 ---
var is_destroyed: bool = false
var _destroy_timer: float = 0.0
var _destroy_spin: float = 0.0      ## 坠落旋转速度

# --- 雷达 ---
var is_hovered: bool = false             ## 鼠标悬停时为 true，显示雷达锥
var radar_targets: Dictionary = {}       ## { Aircraft: float } 累计照射时间
var is_locked: bool = false              ## 被至少一架敌机锁定
var locked_by: Array[Aircraft] = []      ## 锁定自己的敌机列表

func _ready() -> void:
	heading = deg_to_rad(initial_heading_deg)
	rotation = heading
	if params:
		hp = params.max_hp
		speed = params.cruise_speed / 3.6  # km/h -> m/s
		target_speed_kmh = params.cruise_speed
		fuel = params.fuel_capacity
		if params.gun:
			ammo = params.gun.max_ammo

func _physics_process(delta: float) -> void:
	if is_destroyed:
		_update_destroy(delta)
		queue_redraw()
		return
	_update_combat(delta)
	_update_energy_management()
	_update_target_heading()
	_update_bank(delta)
	_update_heading(delta)
	_update_speed(delta)
	_update_altitude(delta)
	_update_fuel(delta)
	_update_stall()
	_update_g_load()
	_apply_movement(delta)
	_update_gun(delta)
	_update_visuals()
	queue_redraw()

# ========== 物理演算 ==========

func _update_target_heading() -> void:
	if target_position == Vector2.INF:
		return
	var diff := target_position - global_position
	var dist := diff.length()
	# 到达判定：至少150px，或当前速度下2秒的飞行距离
	# 追踪战斗目标时跳过到达清除（由 _update_combat 持续更新）
	var arrival_dist := maxf(150.0, speed * PIXELS_PER_METER * 2.0)
	if dist < arrival_dist and combat_target == null:
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

	var max_bank := _max_bank_angle()
	var in_combat := combat_target != null
	var target_bank: float

	if in_combat:
		var cb := _combat_params()
		# 战斗模式：根据激进度参数决定转弯力度
		var full_diff := cb.combat_full_bank_diff / cb.combat_bank_aggression
		var half_diff := cb.combat_half_bank_diff / cb.combat_bank_aggression
		if abs(heading_diff) < half_diff:
			target_bank = 0.0
		elif abs(heading_diff) < full_diff:
			var ratio: float = (abs(heading_diff) - half_diff) / (full_diff - half_diff)
			target_bank = sign(heading_diff) * max_bank * lerpf(0.4, 1.0, ratio)
		else:
			target_bank = sign(heading_diff) * max_bank
	else:
		# 巡航模式：温和修正
		if abs(heading_diff) < 0.05:
			target_bank = 0.0
		elif abs(heading_diff) < 0.4:
			target_bank = sign(heading_diff) * max_bank * 0.3
		else:
			target_bank = sign(heading_diff) * max_bank
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

	var accel_rate := params.acceleration if params else 50.0
	var decel_rate := params.deceleration if params else 80.0

	# 加力燃烧：提升加速度
	if is_afterburner:
		var ab_mult := params.afterburner_thrust_mult if params else 1.5
		accel_rate *= ab_mult

	# 高G机动阻力：拉G越大减速越快
	var g_drag := params.g_drag_factor if params else 3.0
	var g_decel := maxf(g_load - 1.0, 0.0) * g_drag  # 1G时无额外阻力
	decel_rate += g_decel

	# 非对称加减速
	var speed_diff := target_ms - speed
	if speed_diff >= 0:
		speed += minf(speed_diff, accel_rate * delta)
	else:
		speed += maxf(speed_diff, -decel_rate * delta)

	# 高度⇌速度耦合：爬升减速、俯冲加速
	var spd := maxf(speed, 10.0)
	var gravity_effect := GRAVITY * vertical_speed / spd
	speed -= gravity_effect * delta

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

# ========== 燃油 / 能量管理 ==========

## 带冷却的加力切换
func _set_afterburner(on: bool) -> void:
	if on == is_afterburner:
		return
	if _ab_cooldown > 0.0:
		return  # 冷却中，保持当前状态
	if on and fuel <= 0.0:
		return
	is_afterburner = on
	_ab_cooldown = _combat_params().ab_cooldown

func _update_fuel(delta: float) -> void:
	_ab_cooldown = maxf(_ab_cooldown - delta, 0.0)
	if fuel <= 0.0:
		fuel = 0.0
		is_afterburner = false
		return
	var rate: float
	if is_afterburner:
		rate = params.fuel_rate_afterburner if params else 8.0
	else:
		rate = params.fuel_rate_normal if params else 1.5
	fuel -= rate * delta
	if fuel <= 0.0:
		fuel = 0.0
		is_afterburner = false

## 自动能量管理：战斗时加力+俯冲换速，巡航时蓄能爬升
func _update_energy_management() -> void:
	var cb := _combat_params()
	var cruise := params.cruise_speed if params else 900.0

	if combat_target != null and is_instance_valid(combat_target) and not combat_target.is_destroyed:
		# ---- 战斗模式 ----
		var dist := global_position.distance_to(combat_target.global_position)
		var gun_range := _gun_range_px()
		var tgt_speed_ms := combat_target.speed
		var tgt_speed_kmh := tgt_speed_ms * 3.6

		var approach_speed := cruise * cb.approach_speed_mult
		var maneuver_speed := cruise * cb.maneuver_speed_mult
		var closing_speed := cruise * cb.closing_speed_mult
		# 防冲过速度上限：近距离时绝不能比敌机快太多
		var overshoot_cap := tgt_speed_kmh * cb.overshoot_speed_margin
		var decel_zone := gun_range * cb.overshoot_decel_range
		var ab_cutoff := gun_range * cb.overshoot_ab_range

		# 预估到达射程所需时间
		var my_speed_px := speed * PIXELS_PER_METER
		var tgt_fwd := Vector2(sin(combat_target.heading), -cos(combat_target.heading))
		var tgt_speed_px := tgt_speed_ms * PIXELS_PER_METER
		var to_tgt := (combat_target.global_position - global_position).normalized()
		var closure_px := Vector2(sin(heading), -cos(heading)).dot(to_tgt) * my_speed_px \
			- tgt_fwd.dot(to_tgt) * tgt_speed_px
		var time_to_range := (dist - gun_range) / maxf(closure_px, 1.0) if dist > gun_range else 0.0

		# ---- 计算朝目标的航向偏差 ----
		var heading_to_tgt := atan2(to_tgt.x, -to_tgt.y)
		var heading_diff_deg := absf(rad_to_deg(_angle_diff(heading_to_tgt, heading)))

		# ---- 转向减速：偏差大时减速收紧转弯 ----
		var turn_slow_min := deg_to_rad(cb.turn_slow_angle)
		var turn_slow_max := deg_to_rad(cb.turn_slow_max_angle)
		var turn_speed := cruise * cb.turn_slow_speed_mult
		var needs_big_turn := heading_diff_deg > cb.turn_slow_angle

		# ---- 距离相关的速度上限：远距离放宽，近距离收紧防冲过 ----
		var dist_ratio := clampf(dist / gun_range, 0.0, 3.0)
		var speed_limit: float
		if dist_ratio > 2.0:
			speed_limit = approach_speed
		elif dist_ratio > 1.0:
			var t := (dist_ratio - 1.0)
			speed_limit = lerpf(overshoot_cap, approach_speed, t)
		else:
			speed_limit = overshoot_cap

		# ---- 加速策略：击坠优先 ----
		var my_kmh := speed * 3.6
		# 冲过判定：近距离且不在后半球（敌机在我后方或侧后方）
		var has_overshot := not _in_rear_hemisphere and dist < gun_range * 1.5
		# 冲过恢复速度：降到敌机速度的 85%，让敌机"追上来"
		var recover_speed := tgt_speed_kmh * 0.85

		if is_firing:
			target_speed_kmh = maneuver_speed
			_set_afterburner(false)
		elif has_overshot:
			# 已冲过敌机：急刹 + 爬升减速，尽快落后于敌机
			target_speed_kmh = recover_speed
			_set_afterburner(false)
		elif needs_big_turn:
			# 需要大角度转向：减速换转弯率
			var turn_ratio := clampf(
				(heading_diff_deg - cb.turn_slow_angle) / (cb.turn_slow_max_angle - cb.turn_slow_angle),
				0.0, 1.0)
			target_speed_kmh = lerpf(maneuver_speed, turn_speed, turn_ratio)
			_set_afterburner(false)
		elif _in_rear_hemisphere:
			# 后半球优势：全力逼近
			target_speed_kmh = speed_limit
			_set_afterburner(my_kmh < speed_limit and fuel > 0.0)
		elif dist > gun_range:
			# 不在后半球，还没进射程：拦截接近
			if time_to_range > 4.0 or closure_px < 5.0:
				target_speed_kmh = approach_speed
				_set_afterburner(true)
			else:
				target_speed_kmh = speed_limit
				_set_afterburner(false)
		else:
			# 远距离且不在后半球：机动调整位置
			target_speed_kmh = maneuver_speed
			_set_afterburner(false)

		# ---- 高度⇌速度 能量转换 ----
		var my_kmh_now := speed * 3.6
		var desired_kmh := target_speed_kmh

		# 战斗高度基准：默认匹配敌机高度，能量转换可临时偏离
		var combat_alt := combat_target.altitude
		var alt_ceiling := combat_alt + cb.climb_brake_height * 2.0
		# 每帧先重置到敌机高度，确保不会卡在错误高度
		target_altitude = combat_alt

		# 能量转换：仅在需要时临时偏离战斗高度
		if has_overshot and my_kmh_now > desired_kmh:
			# 冲过 + 速度偏高：爬升消耗动能
			target_altitude = minf(combat_alt + cb.climb_brake_height * 1.5, alt_ceiling)
		elif my_kmh_now > desired_kmh * cb.climb_brake_overspeed:
			# 速度过高：爬升消耗动能
			var excess_ratio := (my_kmh_now - desired_kmh) / maxf(desired_kmh, 100.0)
			var climb_amount := cb.climb_brake_height * clampf(excess_ratio * 3.0, 0.3, 1.0)
			target_altitude = minf(combat_alt + climb_amount, alt_ceiling)
		elif my_kmh_now < tgt_speed_kmh * cb.dive_speed_ratio and altitude > cb.dive_min_altitude:
			# 速度过低：俯冲获取动能
			target_altitude = maxf(combat_alt - cb.dive_depth, cb.dive_floor)
		elif needs_big_turn and my_kmh_now > desired_kmh * 1.1:
			# 大角度转向且速度偏高：小幅爬升辅助减速
			target_altitude = minf(combat_alt + cb.climb_brake_height * 0.5, alt_ceiling)
	else:
		# ---- 巡航模式 ----
		_set_afterburner(false)
		target_speed_kmh = cruise

		var cruise_ms := cruise / 3.6
		if speed > cruise_ms * 1.1 and altitude < target_altitude - 100.0:
			pass
		elif speed > cruise_ms * cb.climb_speed_ratio and altitude < cb.climb_max_altitude:
			target_altitude = minf(altitude + 500.0, cb.climb_max_altitude)

# ========== 战斗 ==========

func set_combat_target(target: Aircraft) -> void:
	combat_target = target
	is_firing = false

func clear_combat_target() -> void:
	combat_target = null
	is_firing = false

## 追踪逻辑：三阶段 —— 拦截 / 咬尾 / 纯追击+机会射击
func _update_combat(_delta: float) -> void:
	if combat_target == null:
		return
	if not is_instance_valid(combat_target) or combat_target.is_destroyed:
		clear_combat_target()
		return

	var cb := _combat_params()
	var my_pos := global_position
	var tgt_pos := combat_target.global_position
	var dist := my_pos.distance_to(tgt_pos)

	# 基本向量
	var tgt_fwd := Vector2(sin(combat_target.heading), -cos(combat_target.heading))
	var my_fwd := Vector2(sin(heading), -cos(heading))
	var my_speed_px := speed * PIXELS_PER_METER
	var tgt_speed_px := combat_target.speed * PIXELS_PER_METER
	var to_target := (tgt_pos - my_pos).normalized()

	# 闭合率：正值=在接近，负值=在拉开
	var closing_rate := my_fwd.dot(to_target) * my_speed_px - tgt_fwd.dot(to_target) * tgt_speed_px

	# 后半球判定：我在敌机尾部方向的夹角
	# 0 = 正后方(六点钟), PI = 正前方(十二点钟)
	var to_me_dir := (my_pos - tgt_pos).normalized()
	var aspect_angle := acos(clampf(-tgt_fwd.dot(to_me_dir), -1.0, 1.0))
	var in_rear_hemisphere := aspect_angle < deg_to_rad(90.0)
	_in_rear_hemisphere = in_rear_hemisphere

	var gun_range := _gun_range_px()
	var pursuit_pos: Vector2

	if dist > gun_range * cb.intercept_range_mult:
		# ---- 远距离：前置拦截 ----
		var t := clampf(dist / maxf(my_speed_px, 50.0), 0.5, cb.intercept_lead_max)
		pursuit_pos = tgt_pos + tgt_fwd * tgt_speed_px * t
	elif closing_rate > my_speed_px * cb.closing_rate_threshold:
		# ---- 接近中且闭合率充裕：咬六点钟 ----
		var six_offset := maxf(80.0, gun_range * cb.six_oclock_offset_ratio)
		pursuit_pos = tgt_pos - tgt_fwd * six_offset
	else:
		# ---- 追不上 / 速度相近：纯追击 ----
		var lead_t := clampf(dist / maxf(my_speed_px, 50.0), 0.0, 2.0) * cb.pure_pursuit_lead_factor
		pursuit_pos = tgt_pos + tgt_fwd * tgt_speed_px * lead_t

	target_position = pursuit_pos

	# ---- 开火判定（对前置点） ----
	var gun := params.gun if params else null
	if gun and ammo > 0:
		var range_px := gun.max_range * PIXELS_PER_METER
		var base_cone := deg_to_rad(gun.fire_cone_half_angle)

		# 计算前置射击点：子弹飞到敌机位置需要的时间 × 敌机速度
		var bullet_speed_px := gun.muzzle_velocity * PIXELS_PER_METER
		var bullet_flight_time := dist / maxf(bullet_speed_px, 100.0)
		var lead_pos := tgt_pos + tgt_fwd * tgt_speed_px * bullet_flight_time

		# 机头与前置点的偏差
		var to_lead := lead_pos - my_pos
		var angle_to_lead := atan2(to_lead.x, -to_lead.y)
		var angle_diff := absf(_angle_diff(angle_to_lead, heading))
		var lead_dist := to_lead.length()

		var fire_cone: float
		var fire_range: float
		if in_rear_hemisphere or closing_rate > my_speed_px * cb.closing_rate_threshold:
			# 在后半球 或 闭合率充裕：标准射击，满射程
			fire_cone = base_cone
			fire_range = range_px
		else:
			# 侧面/正面且追不上：机会射击，缩短射程
			fire_cone = base_cone * cb.opportunity_cone_mult
			fire_range = range_px * cb.opportunity_range_mult

		# 高度差检查（米），超过 500m 不开火
		var alt_diff := absf(altitude - combat_target.altitude)
		is_firing = lead_dist <= fire_range and angle_diff <= fire_cone and alt_diff < 500.0
		# 缓存前置点供 _update_gun 使用
		_gun_lead_heading = angle_to_lead
	else:
		is_firing = false
		_gun_lead_heading = heading

## 战斗参数（带懒加载默认值）
var _default_combat: CombatParams

func _combat_params() -> CombatParams:
	if params and params.combat:
		return params.combat
	if not _default_combat:
		_default_combat = CombatParams.new()
	return _default_combat

## 机炮射程（像素）
func _gun_range_px() -> float:
	if params and params.gun:
		return params.gun.max_range * PIXELS_PER_METER
	return 500.0

## 射击更新
func _update_gun(delta: float) -> void:
	_fire_cooldown = maxf(_fire_cooldown - delta, 0.0)
	if not is_firing:
		return
	if not params or not params.gun:
		return
	if ammo <= 0:
		is_firing = false
		return
	if _fire_cooldown > 0.0:
		return

	var gun: GunParams = params.gun
	# 射速冷却：60 / fire_rate 秒
	_fire_cooldown = 60.0 / gun.fire_rate

	# 生成弹丸：朝前置射击方向发射
	if bullet_manager and bullet_manager.has_method("spawn_bullet"):
		var spread_rad := deg_to_rad(gun.spread_angle)
		var bullet_dir := _gun_lead_heading + randf_range(-spread_rad, spread_rad)
		var muzzle_pos := global_position + Vector2(sin(heading), -cos(heading)) * 20.0
		bullet_manager.spawn_bullet(muzzle_pos, bullet_dir, gun.muzzle_velocity, self, gun.bullet_damage)

	ammo -= 1

## 受到伤害
func take_damage(amount: float) -> void:
	if is_destroyed:
		return
	hp -= amount
	if hp <= 0.0:
		hp = 0.0
		_start_destroy()

func _start_destroy() -> void:
	is_destroyed = true
	is_firing = false
	combat_target = null
	_destroy_timer = 3.0
	_destroy_spin = randf_range(-4.0, 4.0)

func _update_destroy(delta: float) -> void:
	# 失控旋转下坠
	heading += _destroy_spin * delta
	altitude -= 300.0 * delta
	speed = maxf(speed - 20.0 * delta, 50.0)
	# 仍然移动
	var velocity := Vector2(sin(heading), -cos(heading)) * speed * PIXELS_PER_METER
	global_position += velocity * delta
	rotation = heading

	_destroy_timer -= delta
	if _destroy_timer <= 0.0 or altitude <= 0.0:
		queue_free()

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
	if is_destroyed:
		_draw_aircraft_icon_destroyed()
		return
	if is_hovered:
		_draw_radar_cone()
	_draw_target_line()
	_draw_aircraft_icon()
	_draw_lock_indicator()
	if is_firing:
		_draw_muzzle_flash()
	if is_afterburner:
		_draw_afterburner_glow()
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

func _draw_muzzle_flash() -> void:
	var flash_alpha := randf_range(0.6, 1.0)
	var flash_color := Color(1.0, 0.9, 0.3, flash_alpha)
	# 机头前方小闪光
	var tip := Vector2(0, -20.0)
	draw_circle(tip, 4.0, flash_color)
	var flash2 := Color(1.0, 0.6, 0.1, flash_alpha * 0.5)
	draw_circle(tip, 7.0, flash2)

func _draw_afterburner_glow() -> void:
	var flicker := randf_range(0.7, 1.0)
	var glow_color := Color(1.0, 0.5, 0.1, 0.8 * flicker)
	var core_color := Color(1.0, 0.85, 0.4, 0.9 * flicker)
	# 尾喷口位置（本地坐标，飞机朝 -Y）
	var tail := Vector2(0, 16.0)
	var flame_len := randf_range(10.0, 16.0)
	# 火焰三角
	var flame := PackedVector2Array([
		tail + Vector2(-3.0, 0),
		tail + Vector2(3.0, 0),
		tail + Vector2(0, flame_len),
	])
	draw_colored_polygon(flame, glow_color)
	# 内焰
	var inner := PackedVector2Array([
		tail + Vector2(-1.5, 0),
		tail + Vector2(1.5, 0),
		tail + Vector2(0, flame_len * 0.6),
	])
	draw_colored_polygon(inner, core_color)

func _draw_aircraft_icon_destroyed() -> void:
	# 灰色闪烁图标
	var blink := absf(sin(Time.get_ticks_msec() * 0.008))
	var gray := Color(0.5, 0.5, 0.5, lerpf(0.3, 0.7, blink))
	var size := 12.0
	var body := PackedVector2Array([
		Vector2(0, -size), Vector2(size * 0.5, size * 0.3),
		Vector2(0, size), Vector2(-size * 0.5, size * 0.3),
	])
	draw_colored_polygon(body, gray)

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
	if params and params.gun:
		lines.append("AMM %d" % ammo)
	lines.append("FUEL %d" % roundi(fuel))
	if is_afterburner:
		lines.append("AB")
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
	# 有战斗目标时：连接线指向敌机
	if combat_target and is_instance_valid(combat_target) and not combat_target.is_destroyed:
		var ct_color := Color(1.0, 0.4, 0.2, 0.6)
		var ct_local := to_local(combat_target.global_position)
		draw_line(Vector2.ZERO, ct_local, ct_color, 1.5, true)
		var ct_d := 8.0
		draw_line(ct_local + Vector2(-ct_d, 0), ct_local + Vector2(ct_d, 0), ct_color, 1.5)
		draw_line(ct_local + Vector2(0, -ct_d), ct_local + Vector2(0, ct_d), ct_color, 1.5)
		draw_circle(ct_local, ct_d, Color(ct_color, 0.2))
		return

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
