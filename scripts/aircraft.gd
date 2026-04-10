class_name Aircraft
extends CombatUnit

@export var params: AircraftParams
@export var initial_heading_deg: float = 0.0  ## 度 初始航向（0=北, 90=东, 180=南）

# --- 状态 ---
var vertical_speed: float = 0.0     ## m/s
var bank_angle: float = 0.0         ## 弧度
var _committed_turn_sign: float = 0.0  ## 转弯方向锁定：0=未锁定, +1/-1=锁定方向
var g_load: float = 1.0
var is_stalled: bool = false
var _stall_recovery_timer: float = 0.0  ## 失速恢复冷却（防止反复失速抽搐）
var pilot_stamina: float = 100.0  ## 飞行员当前耐力

# --- 目标 ---
var target_position: Vector2 = Vector2.INF  ## 世界坐标, INF=无目标
var keep_target_on_arrival: bool = false    ## true=外部管理target_position，到达时不清除
var formation_mode: bool = false            ## true=编队托管模式，直接复制长机状态
var _formation_leader: Aircraft = null      ## 编队长机引用（formation_mode时使用）
var _formation_blend: float = 1.0           ## 编队混合度（0=自主, 1=完全托管，用于过渡）
var _formation_jitter_phase: float = 0.0    ## 个体扰动相位
var target_altitude: float = 5000.0
var target_speed_kmh: float = 900.0  ## km/h, 玩家/AI设定
var target_altitude_tier: int = AltitudeTier.MID   ## 目标高度档位（flat_altitude时使用）

# --- 选择 ---
var selected: bool = false

# --- 燃油 / 加力 ---
var fuel: float = 3000.0
var is_afterburner: bool = false
var _ab_cooldown: float = 0.0        ## 加力状态切换冷却

# --- 战斗 ---
var combat_target: CombatUnit = null  ## 锁定追踪的敌机/地面单位
var is_firing: bool = false
var ammo: int = 500
var _fire_cooldown: float = 0.0
var _gun_lead_heading: float = 0.0  ## 前置射击方向（由 _update_combat 计算）
var _in_rear_hemisphere: bool = false  ## 是否处于敌机后半球（由 _update_combat 计算）
var ai_override_pursuit: bool = false  ## AI 战术机动时跳过自动追踪，由 AI 直接控制 target_position
var bullet_manager: Node2D = null   ## 由 main.gd 注入
var missile_manager: Node2D = null  ## 由 main.gd 注入

# --- 导弹 ---
enum WeaponMode { MISSILE, GUN }
var weapon_mode: int = WeaponMode.GUN
var missiles_remaining: int = 0
var secondary_missiles_remaining: int = 0  ## 副导弹（空对地等）剩余数
var _missile_cooldown: float = 0.0
var _crank_timer: float = 0.0          ## 发射后保持照射计时（秒），> 0 时飞机维持稳定航向
const CRANK_DURATION: float = 8.0      ## 发射后保持照射的时长
const LOCK_STABLE_BUFFER: float = 1.0  ## 锁定后额外稳定时间才允许发射

# --- 导弹装填（生存模式）---
var enable_missile_reload: bool = false     ## 生存模式启用自动装填
var _missile_reload_active: bool = false
var _missile_reload_timer: float = 0.0
var missile_reload_duration: float = 20.0   ## 装填总时间（可通过升级缩短）
var missile_reload_progress: float = 0.0    ## 0.0-1.0, HUD 读取用

# --- 多目标锁定（生存模式升级）---
var max_simultaneous_locks: int = 1

# --- 击毁 ---
var _destroy_timer: float = 0.0
var _destroy_spin: float = 0.0      ## 坠落旋转速度

# --- 雷达 ---

# --- 热诱弹 ---
var flares_remaining: int = 0
var _flare_cooldown: float = 0.0
var _flare_particles: Array[Dictionary] = []  ## { pos: Vector2, vel: Vector2, life: float, bright: bool }
var _flare_spawn_queue: Array[Dictionary] = []  ## 待释放粒子队列 { delay: float, heading: float, pos: Vector2 }
var flares_guaranteed: bool = false  ## 生存模式：玩家热诱弹 100% 干扰
var enable_flare_reload: bool = false  ## 生存模式：热诱弹用完后自动装填
var flare_reload_progress: float = 0.0  ## 0.0-1.0, HUD 读取用
var enable_gun_reload: bool = false      ## 生存模式：机炮弹药持续恢复
var gun_regen_rate: float = 2.0          ## 每秒恢复弹药数
var _gun_regen_accum: float = 0.0        ## 恢复累计（不足1发时累积）
var infinite_fuel: bool = false      ## 生存模式：无限燃油
var bullet_dodge_chance: float = 0.0  ## 机炮弹丸闪避概率（装甲强化升级）
var flare_lock_immunity: float = 0.0  ## 释放热诱弹后的锁定免疫时间（秒）
var _lock_immunity_timer: float = 0.0  ## 当前剩余锁定免疫时间
var kill_heal_amount: float = 0.0     ## 击杀敌机时回复的HP
var gun_extra_barrels: int = 0        ## 额外机炮管数（多管齐射进化）
var missile_bounce_count: int = 0     ## 导弹弹跳次数（连锁弹头进化）
var no_stamina: bool = false         ## 跳过耐力系统（UAV 等）
var survivor_missile_damage_cap: float = 0.0  ## 生存模式：导弹伤害上限（0=不限制）
var survivor_bullet_damage_cap: float = 0.0   ## 生存模式：机炮伤害上限（0=不限制）
var hide_data_label: bool = false    ## 隐藏飞机旁的数据标签（HUD 替代显示）

# --- 战术偏好（生存模式玩家手动控制）---
enum WeaponPreference { PREFER_MISSILE, PREFER_GUN }
enum AltitudePreference { PREFER_CLIMB, PREFER_LOW }

var use_tactical_preference: bool = false       ## 启用战术偏好系统（仅玩家飞机）
var weapon_preference: int = WeaponPreference.PREFER_MISSILE
var altitude_preference: int = AltitudePreference.PREFER_CLIMB
var evasion_mode: bool = false
var _evasion_override: bool = false             ## 玩家手动点击临时覆盖规避
var _evasion_sway_timer: float = 0.0            ## S型机动计时器

# --- LOD ---
var lod_level: int = 0  ## 0=完整, 1=简化（编队僚机巡航）, 2=最小化（屏幕外）
var _lod_frame: int = 0  ## LOD 帧计数器

# --- 战术提示弹窗 ---
var _tactic_popup_text: String = ""
var _tactic_popup_timer: float = 0.0
const TACTIC_POPUP_DURATION: float = 2.0  ## 提示显示时长（秒）

var _trail_ribbon: TrailRibbon

func _ready() -> void:
	# 分配唯一 callsign
	if callsign == "":
		callsign = CallsignDB.allocate()
	speed = 250.0  # 默认速度 m/s（会被 params 覆盖）
	altitude = 5000.0  # 默认高度
	hp = 100.0
	heading = deg_to_rad(initial_heading_deg)
	rotation = heading
	if params:
		hp = params.max_hp
		speed = params.cruise_speed / 3.6  # km/h -> m/s
		target_speed_kmh = params.cruise_speed
		fuel = params.fuel_capacity
		if params.gun:
			ammo = params.gun.max_ammo
		if params.missile:
			missiles_remaining = params.missile.max_count
		if params.secondary_missile:
			secondary_missiles_remaining = params.secondary_missile.max_count
		if params.flare:
			flares_remaining = params.flare.max_flares
		pilot_stamina = params.pilot_stamina
	# 轨迹丝带
	_trail_ribbon = TrailRibbon.new()
	_trail_ribbon.ribbon_width = 8.0
	_trail_ribbon.max_points = 150
	if team == 0:
		_trail_ribbon.ribbon_color = Color(0.3, 0.5, 1.0, 0.6)  # 蓝色
	else:
		_trail_ribbon.ribbon_color = Color(1.0, 0.25, 0.25, 0.6)  # 红色
	add_child(_trail_ribbon)

func show_tactic_popup(text: String) -> void:
	_tactic_popup_text = text
	_tactic_popup_timer = TACTIC_POPUP_DURATION

func _physics_process(delta: float) -> void:
	_lod_frame += 1
	if _tactic_popup_timer > 0.0:
		_tactic_popup_timer -= delta
	if is_destroyed:
		_update_destroy(delta)
		queue_redraw()
		return

	# LOD 2（屏幕外）：每3帧完整处理，其余帧仅位移
	if lod_level >= 2:
		if _lod_frame % 3 != 0:
			_apply_movement(delta)
			# 玩家飞机即使屏幕外也要画锁定线
			if selected and combat_target != null:
				queue_redraw()
			return
		# 每3帧做一次完整更新（但跳过视觉和扫描）
		_update_weapon_mode()
		_update_combat(delta)
		_update_energy_management()
		_update_target_heading()
		_update_bank(delta)
		_update_heading(delta)
		_update_speed(delta)
		_update_altitude(delta)
		_update_fuel(delta)
		_update_stall()
		_check_ground_crash()
		_update_g_load()
		_apply_movement(delta)
		if combat_target != null:
			_update_gun(delta)
			_update_missile(delta)
		_update_flares(delta)
		# 玩家飞机即使屏幕外也要画锁定线
		if selected and combat_target != null:
			queue_redraw()
		return

	# LOD 1（编队僚机巡航）
	if lod_level == 1:
		var every3 := _lod_frame % 3 == 0

		if formation_mode and _formation_leader:
			# ── 编队托管模式 ──
			# 三段式：
			#   >REJOIN_DIST   → 纯追击归队
			#   CLOSE~REJOIN   → 航向追踪 + 自然银行转弯（中距机动）
			#   <CLOSE_DIST    → 航向同步长机 + 微量漂移修正
			var ldr: Aircraft = _formation_leader
			var b := _formation_blend  # 0=自主飞行过渡, 1=正常编队

			# 计算离阵型槽位的距离
			var slot_dist := 0.0
			if target_position != Vector2.INF:
				slot_dist = global_position.distance_to(target_position)

			# 微扰动：基于个体相位的缓慢正弦波
			var t := float(_lod_frame) * 0.02
			var jitter_heading := sin(t + _formation_jitter_phase) * 0.008
			var jitter_bank := sin(t * 0.7 + _formation_jitter_phase + 1.0) * 0.015

			const CLOSE_DIST := 50.0    # 以内纯航向同步
			const REJOIN_DIST := 800.0  # 以外纯追击归队

			if b < 0.05 or slot_dist > REJOIN_DIST:
				# 极远或过渡初期：纯追击归队
				if target_position != Vector2.INF and slot_dist > 10.0:
					var to_slot := (target_position - global_position).normalized()
					var slot_heading := atan2(to_slot.x, -to_slot.y)
					heading = lerp_angle(heading, slot_heading, 4.0 * delta)
					var hdiff := _angle_diff(slot_heading, heading)
					var max_bank_val := _max_bank_angle()
					var desired_bank := signf(hdiff) * max_bank_val * clampf(absf(hdiff) * 2.0, 0.0, 0.7)
					bank_angle = lerpf(bank_angle, desired_bank, 4.0 * delta)
			elif slot_dist > CLOSE_DIST:
				# 中距离：航向追踪槽位（航向 + 自然银行转弯，模拟真实飞机机动）
				var to_slot := (target_position - global_position).normalized()
				var slot_heading := atan2(to_slot.x, -to_slot.y)
				var ldr_heading := ldr.heading + jitter_heading
				# 距离越远越偏向槽位航向，越近越偏向长机航向
				var proximity := clampf((slot_dist - CLOSE_DIST) / (REJOIN_DIST - CLOSE_DIST), 0.0, 1.0)
				var blend_ratio := clampf(proximity * 1.2, 0.15, 0.85)
				var blended_heading := lerp_angle(ldr_heading, slot_heading, blend_ratio)
				heading = lerp_angle(heading, blended_heading, 5.0 * delta)

				# 坡度根据目标航向与当前航向的差值自然响应
				var hdiff := _angle_diff(blended_heading, heading)
				var max_bank_val := _max_bank_angle()
				var desired_bank := signf(hdiff) * max_bank_val * clampf(absf(hdiff) * 2.5, 0.0, 0.75)
				bank_angle = lerpf(bank_angle, desired_bank, 4.0 * delta)
			else:
				# 近距离：航向直接同步长机
				var target_hdg := ldr.heading + jitter_heading
				var target_bnk := ldr.bank_angle + jitter_bank
				var rate := minf(b * 8.0 * delta, 1.0)
				heading = lerp_angle(heading, target_hdg, rate)
				bank_angle = lerpf(bank_angle, target_bnk, rate)

			# 速度：根据槽位距离分档
			var jitter_speed := sin(t * 0.5 + _formation_jitter_phase + 2.0) * ldr.speed * 0.005
			if slot_dist > REJOIN_DIST:
				# 归队：大幅加速
				var max_spd := (params.max_speed if params else 2100.0) / 3.6
				var chase_speed := minf(ldr.speed * 1.4, max_spd)
				speed = lerpf(speed, chase_speed, 4.0 * delta)
			elif slot_dist > 200.0:
				# 远追赶
				speed = lerpf(speed, ldr.speed * 1.15 + jitter_speed, 4.0 * delta)
			elif slot_dist > CLOSE_DIST:
				# 中距追赶
				speed = lerpf(speed, ldr.speed * 1.05 + jitter_speed, 3.0 * delta)
			else:
				# 近距：匹配长机速度
				speed = lerpf(speed, ldr.speed + jitter_speed, (3.0 + b * 3.0) * delta)

			# 高度同步
			altitude = lerpf(altitude, ldr.altitude, (2.0 + b * 2.0) * delta)

			# 正常位移（全部位移通过 _apply_movement 走飞行物理）
			_apply_movement(delta)

			# 近距离微漂移：仅最后 50px 内做细微槽位对齐（很弱，避免平移感）
			if target_position != Vector2.INF and slot_dist > 3.0 and slot_dist < CLOSE_DIST and b > 0.05:
				var correction_dir := (target_position - global_position).normalized()
				var strength := clampf(slot_dist / CLOSE_DIST, 0.1, 1.0) * b * 0.4
				var correction_speed := speed * PIXELS_PER_METER * 0.15 * strength
				var move_px := minf(correction_speed * delta, slot_dist)
				global_position += correction_dir * move_px

			if every3:
				_update_fuel(delta)
				_update_g_load()
			_update_visuals()
			queue_redraw()
			return

		# ── 非编队 LOD 1（降低运算频率） ──
		_update_weapon_mode()
		if combat_target != null:
			_update_combat(delta)
		if every3:
			_update_energy_management()
		_update_target_heading()
		_update_bank(delta)
		_update_heading(delta)
		_update_speed(delta)
		if every3:
			_update_altitude(delta)
			_update_fuel(delta)
			_update_stall()
			_check_ground_crash()
			_update_g_load()
		_apply_movement(delta)
		if combat_target != null:
			_auto_gun_scan()
			_update_gun(delta)
			_update_missile(delta)
		if every3:
			_update_flares(delta)
		_update_visuals()
		queue_redraw()
		return

	# LOD 0（完整）：玩家 / 交战中
	_update_weapon_mode()
	_update_evasion(delta)
	_update_combat(delta)
	_update_energy_management()
	_update_target_heading()
	_update_bank(delta)
	_update_heading(delta)
	_update_speed(delta)
	_update_altitude(delta)
	_update_fuel(delta)
	_update_stall()
	_check_ground_crash()
	_update_g_load()
	_apply_movement(delta)
	_auto_gun_scan()
	_update_gun(delta)
	_update_missile(delta)
	_update_flares(delta)
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
	if dist < arrival_dist and combat_target == null and not keep_target_on_arrival:
		target_position = Vector2.INF
		_evasion_override = false  # 到达目标后恢复规避
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
		_committed_turn_sign = 0.0

	# 转弯方向锁定：防止目标在正后方时 heading_diff 符号逐帧跳动导致滚转振荡
	# 当偏差 > ~143° 时锁定转弯方向，当偏差 < ~86° 时解锁
	if abs(heading_diff) > 2.5:
		if _committed_turn_sign == 0.0:
			_committed_turn_sign = signf(heading_diff)
		heading_diff = absf(heading_diff) * _committed_turn_sign
	elif abs(heading_diff) < 1.5:
		_committed_turn_sign = 0.0

	var max_bank := _max_bank_angle()
	var in_combat := combat_target != null
	var target_bank: float

	# 大角度转弯时限制最大坡度到持续G水平，防止追踪时拉极端G螺旋
	# 只有小角度精确对准时才允许使用结构极限G
	if in_combat and abs(heading_diff) > 0.5:
		var sustained_g := params.max_g if params else 9.0
		# 大角度转弯使用较温和的G限制（持续G的70%），节省能量
		var turn_g := lerpf(sustained_g * 0.7, sustained_g, clampf((PI - abs(heading_diff)) / (PI - 0.5), 0.0, 1.0))
		var sustained_bank := acos(1.0 / maxf(turn_g, 1.01))
		max_bank = minf(max_bank, sustained_bank)

	if in_combat:
		var cb := _combat_params()
		var full_diff := cb.combat_full_bank_diff / cb.combat_bank_aggression
		var half_diff := cb.combat_half_bank_diff / cb.combat_bank_aggression

		if use_tactical_preference:
			# 战术偏好模式（玩家控制）：始终使用激进转弯，不受导弹阶段影响
			if abs(heading_diff) < half_diff:
				target_bank = 0.0
			elif abs(heading_diff) < full_diff:
				var bank_ratio: float = (abs(heading_diff) - half_diff) / (full_diff - half_diff)
				target_bank = sign(heading_diff) * max_bank * lerpf(0.4, 1.0, bank_ratio)
			else:
				target_bank = sign(heading_diff) * max_bank
		elif weapon_mode == WeaponMode.MISSILE:
			# 导弹模式分三阶段：接近→照射→保持
			var msl_phase := _get_missile_phase()
			if msl_phase == 0:
				# 接近阶段：积极机动（与机炮模式相同）
				if abs(heading_diff) < half_diff:
					target_bank = 0.0
				elif abs(heading_diff) < full_diff:
					var bank_ratio: float = (abs(heading_diff) - half_diff) / (full_diff - half_diff)
					target_bank = sign(heading_diff) * max_bank * lerpf(0.4, 1.0, bank_ratio)
				else:
					target_bank = sign(heading_diff) * max_bank
			elif msl_phase == 1:
				# 照射阶段：目标在锥内累积锁定，适度稳定
				if abs(heading_diff) < 0.03:
					target_bank = 0.0
				else:
					target_bank = sign(heading_diff) * max_bank * clampf(abs(heading_diff) * 3.0, 0.2, 0.6)
			else:
				# 保持阶段（已锁定/crank）：极稳定
				if abs(heading_diff) < 0.02:
					target_bank = 0.0
				else:
					target_bank = sign(heading_diff) * max_bank * clampf(abs(heading_diff) * 2.0, 0.1, 0.35)
		else:
			# 机炮模式：激进转弯
			if abs(heading_diff) < half_diff:
				target_bank = 0.0
			elif abs(heading_diff) < full_diff:
				var gun_bank_ratio: float = (abs(heading_diff) - half_diff) / (full_diff - half_diff)
				target_bank = sign(heading_diff) * max_bank * lerpf(0.4, 1.0, gun_bank_ratio)
			else:
				target_bank = sign(heading_diff) * max_bank
	elif formation_mode:
		# 编队跟随模式：积极转弯追赶阵型位置
		if abs(heading_diff) < 0.03:
			target_bank = 0.0
		elif abs(heading_diff) < 0.2:
			target_bank = sign(heading_diff) * max_bank * lerpf(0.3, 0.8, abs(heading_diff) / 0.2)
		else:
			target_bank = sign(heading_diff) * max_bank * 0.9
	else:
		# 巡航模式：温和修正
		if abs(heading_diff) < 0.05:
			target_bank = 0.0
		elif abs(heading_diff) < 0.4:
			target_bank = sign(heading_diff) * max_bank * 0.3
		else:
			target_bank = sign(heading_diff) * max_bank
		target_bank *= _proximity_damping

	# 失速时：强制回正（机翼失去升力，无法维持侧倾）
	if is_stalled:
		target_bank = 0.0
	elif _stall_recovery_timer > 0.0:
		# 失速恢复期：逐渐恢复机动能力，防止立即拉G再次失速
		var recovery_ratio := 1.0 - clampf(_stall_recovery_timer / 1.0, 0.0, 1.0)
		target_bank *= recovery_ratio  # 线性恢复，更快回复机动能力

	# 滚转速率限制
	var roll_rate_val := params.roll_rate if params else 4.0

	# 低速时滚转速率也下降
	var stall_ms := _stall_speed() / 3.6
	if speed < stall_ms:
		var ctrl := clampf(speed / maxf(stall_ms, 1.0), 0.1, 1.0)
		roll_rate_val *= ctrl

	var bank_diff := target_bank - bank_angle
	var max_roll := roll_rate_val * delta
	bank_angle += clampf(bank_diff, -max_roll, max_roll)

func _update_heading(delta: float) -> void:
	if abs(bank_angle) < 0.001:
		return
	# 转弯率 ω = g × tan(bank_angle) / speed
	var speed_ms := maxf(speed, 1.0)  # 防止除零
	var turn_rate := GRAVITY * tan(bank_angle) / speed_ms

	# 低速时操控性急剧下降：速度低于失速速度时，转向能力线性衰减
	var stall_ms := _stall_speed() / 3.6
	if speed < stall_ms:
		var control_ratio := clampf(speed / maxf(stall_ms, 1.0), 0.0, 1.0)
		# 平方衰减：速度越低，操控越差
		turn_rate *= control_ratio * control_ratio

	heading += turn_rate * delta
	# 归一化到 [-PI, PI]
	heading = fmod(heading + PI, TAU) - PI

func _update_speed(delta: float) -> void:
	var target_ms := target_speed_kmh / 3.6
	var max_speed_ms := _max_speed_at_altitude() / 3.6
	target_ms = minf(target_ms, max_speed_ms)

	# 安全速度下限：永远不主动减速到失速速度以下
	var stall_base_ms := (params.stall_speed_base if params else 220.0) / 3.6
	var min_safe_ms := stall_base_ms * 1.3  # 130% 失速速度作为安全余量
	target_ms = maxf(target_ms, min_safe_ms)

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
	var was_stalled := is_stalled
	is_stalled = speed < stall_speed_ms
	if is_stalled:
		var delta := get_physics_process_delta_time()
		# 失速严重程度（0=刚失速, 1=完全停止）
		var severity := 1.0 - clampf(speed / maxf(stall_speed_ms, 1.0), 0.0, 1.0)

		# 强制机头下压俯冲（设置 vertical_speed，让重力耦合把高度转成速度）
		# 不直接修改 altitude —— _update_altitude 已经处理了
		var dive_rate := lerpf(-100.0, -250.0, severity)
		vertical_speed = minf(vertical_speed, dive_rate)

		# 失速时侧倾不稳定
		bank_angle += randf_range(-1.0, 1.0) * severity * 2.0 * delta

		_stall_recovery_timer = 1.0  # 脱离失速后 1 秒内限制机动
	elif _stall_recovery_timer > 0.0:
		_stall_recovery_timer -= get_physics_process_delta_time()

func _update_g_load() -> void:
	if abs(bank_angle) < 0.001:
		g_load = 1.0
	else:
		g_load = 1.0 / cos(bank_angle)
		g_load = absf(g_load)
	if not no_stamina:
		_update_pilot_stamina(get_physics_process_delta_time())

func _update_pilot_stamina(delta: float) -> void:
	var sustained_g := params.max_g if params else 9.0
	var max_stam := params.pilot_stamina if params else 100.0
	if g_load > sustained_g:
		# 超过持续耐受G时消耗耐力，G力越高消耗越快
		var excess_ratio := (g_load - sustained_g) / maxf(_effective_max_g() - sustained_g, 0.1)
		var drain := (params.stamina_drain_rate if params else 25.0) * excess_ratio
		pilot_stamina = maxf(pilot_stamina - drain * delta, 0.0)
	else:
		# 低于持续耐受G时恢复耐力
		var recovery := params.stamina_recovery_rate if params else 10.0
		pilot_stamina = minf(pilot_stamina + recovery * delta, max_stam)

func _apply_movement(delta: float) -> void:
	# heading: 0=上(北), 顺时针为正
	# Godot 2D: x右, y下
	var velocity := Vector2(sin(heading), -cos(heading)) * speed * PIXELS_PER_METER
	global_position += velocity * delta

# ========== 辅助计算 ==========

func _max_bank_angle() -> float:
	var max_g_val := _effective_max_g()
	# G = 1/cos(bank) => bank = acos(1/G)
	var g_limited_bank := acos(1.0 / max_g_val)

	# 速度限制：不允许拉到会导致失速的G力
	# 失速速度 V_stall = V_base * sqrt(G)，所以允许的最大G = (V_current / V_base)²
	# 留 20% 安全余量防止拉G后立即失速抽搐
	var stall_base := (params.stall_speed_base if params else 220.0) / 3.6  # m/s
	var safe_margin := 1.2  # 保留20%速度余量
	if speed > stall_base * safe_margin:
		var effective_speed := speed / safe_margin  # 用折减后的速度计算允许G
		var max_g_for_speed := (effective_speed / stall_base) * (effective_speed / stall_base)
		var speed_limited_bank := acos(1.0 / maxf(max_g_for_speed, 1.01))
		return minf(g_limited_bank, speed_limited_bank)
	else:
		# 速度接近/低于安全线，线性衰减到几乎不能拉G
		var ratio := clampf(speed / (stall_base * safe_margin), 0.0, 1.0)
		return 0.1 + ratio * 0.2  # 0.1~0.3 rad (约6°~17°)

func _effective_max_g() -> float:
	## 根据飞行员耐力在 sustained G 与 structural G 之间插值
	var sustained := params.max_g if params else 9.0
	var structural := params.max_g_structural if params else 12.0
	var max_stam := params.pilot_stamina if params else 100.0
	var ratio := pilot_stamina / maxf(max_stam, 0.01)
	return sustained + (structural - sustained) * ratio

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

## 设置目标高度档位（同步 target_altitude 到档位对应值）
func set_target_tier(tier: int) -> void:
	target_altitude_tier = clampi(tier, AltitudeTier.LOW, AltitudeTier.HIGH)
	target_altitude = TIER_ALTITUDE[target_altitude_tier]

## 获取比当前档位高一档（上限 HIGH）
func tier_above() -> int:
	return mini(get_altitude_tier() + 1, AltitudeTier.HIGH)

## 获取比当前档位低一档（下限 LOW）
func tier_below() -> int:
	return maxi(get_altitude_tier() - 1, AltitudeTier.LOW)

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
	if infinite_fuel:
		return
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
		# 地面攻击模式：保持中等速度，不做复杂能量管理
		if combat_target is GroundUnit:
			var cruise_ms := cruise / 3.6
			target_speed_kmh = cruise * 0.7  # 攻击速度 = 巡航 70%
			_set_afterburner(false)
			return
		# AI 战术机动模式：AI 控制器已设定速度，仅管理加力燃烧器
		if ai_override_pursuit:
			var my_kmh := speed * 3.6
			_set_afterburner(my_kmh < target_speed_kmh - 50.0 and fuel > 0.0)
			return
		# ---- 战斗模式 ----
		var dist := Aircraft.effective_distance_px(global_position, altitude, combat_target.global_position, combat_target.altitude)
		var gun_range := _gun_range_px()
		var tgt_speed_ms := combat_target.speed
		var tgt_speed_kmh := tgt_speed_ms * 3.6

		# 战斗最低安全速度：不允许因追踪慢速目标而降到失速边缘
		var stall_base_kmh := params.stall_speed_base if params else 220.0
		var combat_min_kmh := stall_base_kmh * 1.8  # 180% 失速速度，留足高G机动余量

		var is_missile_mode := weapon_mode == WeaponMode.MISSILE

		# 预估到达射程所需时间
		var my_speed_px := speed * PIXELS_PER_METER
		var tgt_fwd := Vector2(sin(combat_target.heading), -cos(combat_target.heading))
		var tgt_speed_px := tgt_speed_ms * PIXELS_PER_METER
		var to_tgt := (combat_target.global_position - global_position).normalized()
		var closure_px := Vector2(sin(heading), -cos(heading)).dot(to_tgt) * my_speed_px \
			- tgt_fwd.dot(to_tgt) * tgt_speed_px

		# ---- 计算朝目标的航向偏差 ----
		var heading_to_tgt := atan2(to_tgt.x, -to_tgt.y)
		var heading_diff_deg := absf(rad_to_deg(_angle_diff(heading_to_tgt, heading)))

		var my_kmh := speed * 3.6
		var turn_speed := cruise * cb.turn_slow_speed_mult
		var needs_big_turn := heading_diff_deg > cb.turn_slow_angle

		var approach_speed := cruise * cb.approach_speed_mult

		if use_tactical_preference and is_missile_mode:
			# ======== 战术偏好：导弹模式简化能量管理 ========
			# 不区分导弹阶段，保持巡航速度，大转弯时减速
			if needs_big_turn:
				var msl_turn_ratio := clampf(
					(heading_diff_deg - cb.turn_slow_angle) / (cb.turn_slow_max_angle - cb.turn_slow_angle),
					0.0, 1.0)
				target_speed_kmh = lerpf(cruise, turn_speed, msl_turn_ratio)
				_set_afterburner(false)
			else:
				target_speed_kmh = cruise
				_set_afterburner(false)
			target_speed_kmh = maxf(target_speed_kmh, combat_min_kmh)
		elif is_missile_mode:
			# ======== AI 导弹模式能量管理（分阶段） ========
			var msl_phase := _get_missile_phase()

			if msl_phase == 0:
				# 接近阶段：积极接近，但在射程内减速
				var msl_ideal := 1500.0  # 理想接战距离（像素）
				if params and params.missile:
					msl_ideal = params.missile.max_range_rear * 0.3 * PIXELS_PER_METER
				if needs_big_turn:
					var msl_turn_ratio := clampf(
						(heading_diff_deg - cb.turn_slow_angle) / (cb.turn_slow_max_angle - cb.turn_slow_angle),
						0.0, 1.0)
					target_speed_kmh = lerpf(cruise, turn_speed, msl_turn_ratio)
					_set_afterburner(false)
				elif dist > msl_ideal * 2.0:
					# 远距离：加力接近
					target_speed_kmh = approach_speed
					_set_afterburner(my_kmh < approach_speed and fuel > 0.0)
				elif dist > msl_ideal:
					# 中距离：巡航接近，不加力
					target_speed_kmh = cruise
					_set_afterburner(false)
				else:
					# 已在理想射程内：匹配目标速度，不再闭合
					var tgt_kmh := combat_target.speed * 3.6 if combat_target else cruise
					target_speed_kmh = maxf(tgt_kmh, cruise * 0.8)
					_set_afterburner(false)
			elif msl_phase == 1:
				# 照射阶段：巡航速度，不加力，保持平稳
				target_speed_kmh = cruise
				_set_afterburner(false)
			else:
				# 保持阶段（已锁定/crank）：略低于巡航，极稳定
				target_speed_kmh = cruise * 0.95
				_set_afterburner(false)

			# 导弹模式也保底战斗最低速度
			target_speed_kmh = maxf(target_speed_kmh, combat_min_kmh)
			# 高度匹配敌机
			if flat_altitude:
				set_target_tier(combat_target.get_altitude_tier())
			else:
				target_altitude = combat_target.altitude
		else:
			# ======== 机炮模式能量管理（原有逻辑） ========
			var maneuver_speed := cruise * cb.maneuver_speed_mult
			var overshoot_cap := tgt_speed_kmh * cb.overshoot_speed_margin

			# 距离相关的速度上限
			var dist_ratio := clampf(dist / gun_range, 0.0, 3.0)
			var speed_limit: float
			if dist_ratio > 2.0:
				speed_limit = approach_speed
			elif dist_ratio > 1.0:
				var t := (dist_ratio - 1.0)
				speed_limit = lerpf(overshoot_cap, approach_speed, t)
			else:
				speed_limit = overshoot_cap

			var has_overshot := not _in_rear_hemisphere and dist < gun_range * 1.5
			var recover_speed := tgt_speed_kmh * 0.85

			if is_firing:
				target_speed_kmh = maneuver_speed
				_set_afterburner(false)
			elif has_overshot:
				target_speed_kmh = recover_speed
				_set_afterburner(false)
			elif needs_big_turn:
				var turn_ratio := clampf(
					(heading_diff_deg - cb.turn_slow_angle) / (cb.turn_slow_max_angle - cb.turn_slow_angle),
					0.0, 1.0)
				target_speed_kmh = lerpf(maneuver_speed, turn_speed, turn_ratio)
				_set_afterburner(false)
			elif _in_rear_hemisphere:
				var max_kmh := params.max_speed if params else 2100.0
				if dist > gun_range * 0.5:
					target_speed_kmh = max_kmh
					_set_afterburner(fuel > 0.0)
				else:
					target_speed_kmh = overshoot_cap
					_set_afterburner(false)
			elif dist > gun_range * cb.intercept_range_mult:
				target_speed_kmh = approach_speed
				_set_afterburner(my_kmh < approach_speed and fuel > 0.0)
			else:
				target_speed_kmh = maneuver_speed
				_set_afterburner(false)

			# 战斗速度下限：防止追踪慢速目标时降到失速边缘抽搐
			target_speed_kmh = maxf(target_speed_kmh, combat_min_kmh)

			# ---- 高度⇌速度 能量转换（仅机炮模式） ----
			var my_kmh_now := speed * 3.6
			var desired_kmh := target_speed_kmh

			if flat_altitude:
				# 扁平模式：用档位切换实现能量转换
				var tgt_tier := combat_target.get_altitude_tier()
				set_target_tier(tgt_tier)
				if has_overshot and my_kmh_now > desired_kmh:
					set_target_tier(tier_above())  # 爬升减速
				elif my_kmh_now > desired_kmh * cb.climb_brake_overspeed:
					set_target_tier(tier_above())  # 爬升刹车
				elif my_kmh_now < tgt_speed_kmh * cb.dive_speed_ratio:
					set_target_tier(tier_below())  # 俯冲换速
				elif needs_big_turn and my_kmh_now > desired_kmh * 1.1:
					set_target_tier(tier_above())  # 转弯前爬升
			else:
				var combat_alt := combat_target.altitude
				var alt_ceiling := combat_alt + cb.climb_brake_height * 2.0
				target_altitude = combat_alt

				if has_overshot and my_kmh_now > desired_kmh:
					target_altitude = minf(combat_alt + cb.climb_brake_height * 1.5, alt_ceiling)
				elif my_kmh_now > desired_kmh * cb.climb_brake_overspeed:
					var excess_ratio := (my_kmh_now - desired_kmh) / maxf(desired_kmh, 100.0)
					var climb_amount := cb.climb_brake_height * clampf(excess_ratio * 3.0, 0.3, 1.0)
					target_altitude = minf(combat_alt + climb_amount, alt_ceiling)
				elif my_kmh_now < tgt_speed_kmh * cb.dive_speed_ratio and altitude > cb.dive_min_altitude:
					target_altitude = maxf(combat_alt - cb.dive_depth, cb.dive_floor)
				elif needs_big_turn and my_kmh_now > desired_kmh * 1.1:
					target_altitude = minf(combat_alt + cb.climb_brake_height * 0.5, alt_ceiling)
	else:
		# ---- 巡航模式 ----
		# 编队跟随时由AI控制器管理速度和高度，跳过自主能量管理
		if formation_mode:
			return
		_set_afterburner(false)
		target_speed_kmh = cruise

		if flat_altitude:
			if use_tactical_preference:
				# 战术偏好：按玩家设定调整巡航高度
				match altitude_preference:
					AltitudePreference.PREFER_CLIMB:
						set_target_tier(AltitudeTier.HIGH)
					AltitudePreference.PREFER_LOW:
						set_target_tier(AltitudeTier.LOW)
			else:
				# 扁平模式：富余速度时升档蓄能
				var cruise_ms := cruise / 3.6
				if speed > cruise_ms * cb.climb_speed_ratio and get_altitude_tier() < AltitudeTier.HIGH:
					set_target_tier(tier_above())
		else:
			var cruise_ms := cruise / 3.6
			if speed > cruise_ms * 1.1 and altitude < target_altitude - 100.0:
				pass
			elif speed > cruise_ms * cb.climb_speed_ratio and altitude < cb.climb_max_altitude:
				target_altitude = minf(altitude + 500.0, cb.climb_max_altitude)

# ========== 战斗 ==========

func _log_name() -> String:
	var side := "Friend" if team == 0 else "Enemy"
	var dn: String = params.display_name if params else "???"
	return "%s/%s[%s]" % [side, dn, callsign]

func _log_unit_name(unit: CombatUnit) -> String:
	if not unit or not is_instance_valid(unit):
		return "None"
	if unit is Aircraft:
		var ac: Aircraft = unit
		var side := "Friend" if ac.team == 0 else "Enemy"
		var dn: String = ac.params.display_name if ac.params else "???"
		return "%s/%s[%s]" % [side, dn, ac.callsign]
	return unit.name

func set_combat_target(target: CombatUnit) -> void:
	combat_target = target
	is_firing = false
	_strafe_state = 0  # 重置舔地状态机

func clear_combat_target() -> void:
	combat_target = null
	_committed_turn_sign = 0.0
	is_firing = false
	_strafe_state = 0

## 追踪逻辑：三阶段 —— 拦截 / 咬尾 / 纯追击+机会射击
func _update_combat(_delta: float) -> void:
	if combat_target == null:
		return
	if not is_instance_valid(combat_target) or combat_target.is_destroyed:
		clear_combat_target()
		target_position = Vector2.INF  # 目标被击毁，停止直飞
		return

	# 地面目标 → 舔地攻击（strafing run）
	if combat_target is GroundUnit:
		_update_combat_ground_attack()
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

	var is_missile_mode := weapon_mode == WeaponMode.MISSILE

	# 战术偏好模式（玩家手动控制）：简化直追，不做 crank 侧飞
	if use_tactical_preference:
		var lead_time := clampf(dist / maxf(my_speed_px, 50.0), 0.3, 2.0)
		target_position = tgt_pos + tgt_fwd * tgt_speed_px * lead_time
	elif not ai_override_pursuit:
		var gun_range := _gun_range_px()
		var eff_range := _effective_range_px()
		var pursuit_pos: Vector2
		var six_offset := maxf(80.0, eff_range * cb.six_oclock_offset_ratio)

		# 大角度转向：当目标在后方（航向偏差>90°）时，先直接转向目标位置
		# 避免追踪六点钟/前置点导致追踪点不断偏移形成螺旋
		var heading_to_tgt := atan2(to_target.x, -to_target.y)
		var heading_diff_to_tgt := absf(_angle_diff(heading_to_tgt, heading))
		if heading_diff_to_tgt > deg_to_rad(90.0):
			target_position = tgt_pos
			return

		if is_missile_mode:
			# ---- 导弹模式（分阶段追踪 + 距离保持） ----
			var msl_phase := _get_missile_phase()
			var msl := params.missile
			var min_range_px := msl.min_range * PIXELS_PER_METER if msl else 250.0
			var ideal_range_px := msl.max_range_rear * 0.3 * PIXELS_PER_METER if msl else 500.0

			if dist < min_range_px:
				# 太近：拉开距离，垂直于目标航向脱离
				var away := (my_pos - tgt_pos).normalized()
				pursuit_pos = my_pos + away * ideal_range_px * 0.5
			elif dist < ideal_range_px and msl_phase >= 1:
				# 已在射程内且正在锁定/已发射：保持当前距离，不再接近
				# 沿目标侧面平行飞行（crank 机动）
				var perp := Vector2(-tgt_fwd.y, tgt_fwd.x)  # 目标航向的垂直方向
				var side: float = sign(perp.dot(my_pos - tgt_pos))  # 我在目标的哪一侧
				if side == 0:
					side = 1.0
				pursuit_pos = tgt_pos + perp * side * dist * 0.8 + tgt_fwd * tgt_speed_px * 1.0
			elif msl_phase == 0:
				# 接近阶段：拦截追踪，但限制最小保持距离
				var intercept_lead := clampf(dist / maxf(my_speed_px, 50.0), 0.5, cb.intercept_lead_max)
				pursuit_pos = tgt_pos + tgt_fwd * tgt_speed_px * intercept_lead
			elif msl_phase == 1:
				# 照射阶段：温和跟踪
				var lead_time := clampf(dist / maxf(my_speed_px + tgt_speed_px, 100.0), 0.2, 1.5)
				pursuit_pos = tgt_pos + tgt_fwd * tgt_speed_px * lead_time
			else:
				# 保持阶段（已发射）：维持距离
				pursuit_pos = tgt_pos
		else:
			# ---- 机炮模式追踪（原有逻辑） ----
			six_offset = maxf(80.0, _gun_range_px() * cb.six_oclock_offset_ratio)
			if dist > _gun_range_px() * cb.intercept_range_mult:
				if in_rear_hemisphere:
					var t := clampf(dist / maxf(my_speed_px, 50.0), 0.5, cb.intercept_lead_max)
					pursuit_pos = tgt_pos + tgt_fwd * tgt_speed_px * t
				else:
					pursuit_pos = tgt_pos - tgt_fwd * six_offset
			elif in_rear_hemisphere:
				pursuit_pos = tgt_pos - tgt_fwd * six_offset
			else:
				pursuit_pos = tgt_pos - tgt_fwd * six_offset

		target_position = pursuit_pos

	# ---- 开火判定（对前置点）—— 仅机炮模式 ----
	var gun := params.gun if params else null
	if gun and ammo > 0 and not is_missile_mode:
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

		# 高度差检查（米），超过 500m 不开火（扁平高度模式下忽略）
		var alt_diff := absf(altitude - combat_target.altitude)
		is_firing = lead_dist <= fire_range and angle_diff <= fire_cone and (flat_altitude or alt_diff < 500.0)
		# 缓存前置点供 _update_gun 使用
		_gun_lead_heading = angle_to_lead
	else:
		is_firing = false
		_gun_lead_heading = heading

## ========== 地面攻击（Strafing Run） ==========
## 飞机对地面静止/慢速目标的攻击模式：
## 1. 从远处直线飞向目标（进入跑道）
## 2. 飞越目标上空，途中开火
## 3. 越过后直线延伸脱离
## 4. 掉头回来进行下一轮

var _strafe_state: int = 0       ## 0=进入, 1=攻击, 2=脱离, 3=掉头
var _strafe_extend_dist: float = 0.0  ## 脱离时已飞距离
const STRAFE_ATTACK_RANGE := 1500.0   ## 像素，开始攻击判定距离
const STRAFE_EXTEND_RANGE := 800.0    ## 像素，越过后继续直飞距离
const STRAFE_APPROACH_RANGE := 3000.0 ## 像素，进入跑道对准距离

func _update_combat_ground_attack() -> void:
	var my_pos := global_position
	var tgt_pos := combat_target.global_position
	var dist := my_pos.distance_to(tgt_pos)
	var my_fwd := Vector2(sin(heading), -cos(heading))
	var to_target := (tgt_pos - my_pos).normalized()
	var is_missile_mode := weapon_mode == WeaponMode.MISSILE

	# 目标是否在前方（点积 > 0 = 前方）
	var dot_fwd := my_fwd.dot(to_target)
	var heading_to_tgt := atan2(to_target.x, -to_target.y)
	var heading_diff := absf(_angle_diff(heading_to_tgt, heading))

	# 状态机
	match _strafe_state:
		0:  # 进入：远距离对准目标
			if dist < STRAFE_ATTACK_RANGE and heading_diff < deg_to_rad(30.0):
				_strafe_state = 1  # 进入攻击阶段
			else:
				# 对准目标直飞
				target_position = tgt_pos
		1:  # 攻击：直线飞向/飞越目标
			target_position = tgt_pos
			# 检查是否已经飞过目标（目标在身后）
			if dot_fwd < -0.2 and dist > 50.0:
				_strafe_state = 2
				_strafe_extend_dist = 0.0
		2:  # 脱离：越过后继续直飞一段距离
			# 保持当前方向直飞
			target_position = my_pos + my_fwd * 1000.0
			_strafe_extend_dist += speed * PIXELS_PER_METER * get_physics_process_delta_time()
			if _strafe_extend_dist > STRAFE_EXTEND_RANGE:
				_strafe_state = 3
		3:  # 掉头：转向目标准备下一轮
			target_position = tgt_pos
			if heading_diff < deg_to_rad(45.0) and dist > STRAFE_ATTACK_RANGE * 0.8:
				_strafe_state = 0  # 回到进入阶段

	# ---- 高度管理：攻击时降低高度 ----
	if flat_altitude:
		if _strafe_state <= 1:
			set_target_tier(AltitudeTier.LOW)  # 攻击时降到低空
		else:
			# 脱离/掉头时根据偏好恢复
			if altitude_preference == AltitudePreference.PREFER_CLIMB:
				set_target_tier(AltitudeTier.MID)
	else:
		if _strafe_state <= 1:
			target_altitude = 1500.0  # 低空进入
		else:
			target_altitude = 3000.0  # 脱离时爬升

	# ---- 开火判定 ----
	is_firing = false
	_gun_lead_heading = heading

	# 导弹模式：远距离锁定发射
	if is_missile_mode:
		# 导弹发射由 _update_missile 处理，这里不设 is_firing
		pass
	else:
		# 机炮：攻击阶段 + 在范围内 + 机头对准 → 开火
		var gun := params.gun if params else null
		if gun and ammo > 0 and _strafe_state <= 1:
			var range_px := gun.max_range * PIXELS_PER_METER
			var fire_cone := deg_to_rad(gun.fire_cone_half_angle * 1.5)  # 对地放宽火控角
			if dist < range_px and heading_diff < fire_cone:
				is_firing = true
				_gun_lead_heading = heading_to_tgt  # 地面目标静止，直接瞄

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
## 无交战目标时自动扫描：前方有敌机就开火
func _auto_gun_scan() -> void:
	# 已有交战目标时由 _update_combat 处理开火
	if combat_target != null and is_instance_valid(combat_target) and not combat_target.is_destroyed:
		return
	# 导弹模式不自动扫射
	if weapon_mode == WeaponMode.MISSILE:
		is_firing = false
		return
	if not params or not params.gun or ammo <= 0:
		is_firing = false
		return

	var gun: GunParams = params.gun
	var range_px := gun.max_range * PIXELS_PER_METER
	var fire_cone := deg_to_rad(gun.fire_cone_half_angle)
	var bullet_speed_px := gun.muzzle_velocity * PIXELS_PER_METER
	var my_pos := global_position
	var my_fwd := Vector2(sin(heading), -cos(heading))

	var best_target: Aircraft = null
	var best_angle := fire_cone

	var parent := get_parent()
	if not parent:
		is_firing = false
		return

	for child in parent.get_children():
		if not child is Aircraft:
			continue
		var ac: Aircraft = child
		if ac.team == team or ac.is_destroyed:
			continue

		var to_ac := ac.global_position - my_pos
		var dist := to_ac.length()
		if dist > range_px or dist < 10.0:
			continue

		# 高度差检查（扁平高度模式下忽略）
		if not flat_altitude and absf(altitude - ac.altitude) > 500.0:
			continue

		# 前置点计算
		var tgt_fwd := Vector2(sin(ac.heading), -cos(ac.heading))
		var tgt_speed_px := ac.speed * PIXELS_PER_METER
		var flight_time := dist / maxf(bullet_speed_px, 100.0)
		var lead_pos := ac.global_position + tgt_fwd * tgt_speed_px * flight_time

		var to_lead := lead_pos - my_pos
		var angle_to_lead := atan2(to_lead.x, -to_lead.y)
		var angle_diff := absf(_angle_diff(angle_to_lead, heading))

		if angle_diff < best_angle:
			best_angle = angle_diff
			best_target = ac
			_gun_lead_heading = angle_to_lead

	is_firing = best_target != null

func _update_gun(delta: float) -> void:
	_fire_cooldown = maxf(_fire_cooldown - delta, 0.0)
	# 弹药持续恢复
	if enable_gun_reload and params and params.gun and ammo < params.gun.max_ammo:
		_gun_regen_accum += gun_regen_rate * delta
		var add := int(_gun_regen_accum)
		if add > 0:
			ammo = mini(ammo + add, params.gun.max_ammo)
			_gun_regen_accum -= float(add)
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
		# 多管齐射：额外射出左右偏角子弹
		if gun_extra_barrels >= 2:
			var fan_angle := deg_to_rad(15.0)
			var dir_l := _gun_lead_heading - fan_angle + randf_range(-spread_rad, spread_rad)
			var dir_r := _gun_lead_heading + fan_angle + randf_range(-spread_rad, spread_rad)
			bullet_manager.spawn_bullet(muzzle_pos, dir_l, gun.muzzle_velocity, self, gun.bullet_damage)
			bullet_manager.spawn_bullet(muzzle_pos, dir_r, gun.muzzle_velocity, self, gun.bullet_damage)

	ammo -= 1
	if gun_extra_barrels >= 2:
		ammo -= 2
	ammo = maxi(ammo, 0)

## 导弹射程（像素）
func _missile_range_px() -> float:
	if params and params.missile:
		# 使用后半球射程的 60% 作为理想交战距离参考
		return params.missile.max_range_rear * 0.6 * PIXELS_PER_METER
	return 500.0

## 当前武器有效交战距离（像素）
func _effective_range_px() -> float:
	if weapon_mode == WeaponMode.MISSILE:
		return _missile_range_px()
	return _gun_range_px()

## 导弹交战阶段：0=接近（积极机动），1=照射（目标在锥内），2=保持（已锁定/crank）
func _get_missile_phase() -> int:
	if is_cranking():
		return 2
	if combat_target == null or not is_instance_valid(combat_target):
		return 0
	var lock_progress: float = radar_targets.get(combat_target, 0.0)
	var lock_time_val: float = params.lock_time if params else 3.0
	if lock_progress >= lock_time_val:
		# 已锁定
		return 2
	if lock_progress > 0.0:
		# 目标在锥内，正在累积
		return 1
	# 目标不在锥内
	return 0

## 判断是否已经近到应该用机炮（非常严格，防止模式震荡）
func _should_use_gun() -> bool:
	if combat_target == null or not is_instance_valid(combat_target):
		return false
	if combat_target.is_destroyed:
		return false
	var dist := global_position.distance_to(combat_target.global_position)
	var gun_range := _gun_range_px()
	# 只有在机炮射程内才考虑（不是 1.2 倍，是 0.8 倍——必须非常近）
	return dist < gun_range * 0.8

## 武器模式判定（每帧最先执行，确保 combat 和 energy 读到正确模式）
func _update_weapon_mode() -> void:
	# 战术偏好模式（生存模式玩家）
	if use_tactical_preference:
		_update_weapon_mode_tactical()
		return

	# AI / 沙盒模式：原有自动切换逻辑
	# 根据目标类型判断"可用导弹数"：空中目标只能用 AAM（主），地面目标两种皆可
	var target_is_ground: bool = combat_target != null and is_instance_valid(combat_target) and combat_target is GroundUnit
	var usable_missiles: int = 0
	if params:
		if target_is_ground:
			usable_missiles = missiles_remaining + secondary_missiles_remaining
		else:
			# 空中目标（或无目标）：仅 AAM 算数，AGM 不能打飞机
			usable_missiles = missiles_remaining
	if (not params or (not params.missile and not params.secondary_missile)) or usable_missiles <= 0:
		weapon_mode = WeaponMode.GUN
		return
	if _crank_timer > 0.0:
		weapon_mode = WeaponMode.MISSILE
		return
	if weapon_mode == WeaponMode.GUN and usable_missiles > 0:
		if combat_target and is_instance_valid(combat_target) and not combat_target.is_destroyed:
			var dist := global_position.distance_to(combat_target.global_position)
			var gun_range := _gun_range_px()
			if dist > gun_range * 2.0:
				weapon_mode = WeaponMode.MISSILE
		else:
			weapon_mode = WeaponMode.MISSILE
		return
	if _should_use_gun():
		weapon_mode = WeaponMode.GUN
	else:
		weapon_mode = WeaponMode.MISSILE

## 战术偏好武器模式：玩家手动控制，简洁明确
func _update_weapon_mode_tactical() -> void:
	match weapon_preference:
		WeaponPreference.PREFER_MISSILE:
			if (missiles_remaining + secondary_missiles_remaining) > 0 or _crank_timer > 0.0:
				weapon_mode = WeaponMode.MISSILE
			else:
				weapon_mode = WeaponMode.GUN  # 导弹打完临时用机炮
		WeaponPreference.PREFER_GUN:
			weapon_mode = WeaponMode.GUN

## 是否正在保持照射（发射后维持锁定阶段）
func is_cranking() -> bool:
	return _crank_timer > 0.0

## 规避模式更新（生存模式玩家）
func _update_evasion(delta: float) -> void:
	if not use_tactical_preference or not evasion_mode:
		return

	# 检测来袭导弹
	var incoming_missile: Node2D = null
	var closest_dist := INF
	if missile_manager:
		for child in missile_manager.get_children():
			if child is Missile:
				var m: Missile = child as Missile
				if m.is_active and m.target == self:
					var d := global_position.distance_squared_to(m.global_position)
					if d < closest_dist:
						closest_dist = d
						incoming_missile = m

	if incoming_missile:
		# 有来袭导弹：垂直于导弹轨迹方向规避
		_evasion_override = false  # 导弹来袭时强制规避
		var missile_dir := (global_position - incoming_missile.global_position).normalized()
		var evade_dir := Vector2(missile_dir.y, -missile_dir.x)
		# 选择与当前航向最近的规避方向
		var evade_heading_a := atan2(evade_dir.x, -evade_dir.y)
		var evade_heading_b := atan2(-evade_dir.x, evade_dir.y)
		var diff_a := absf(angle_difference(heading, evade_heading_a))
		var diff_b := absf(angle_difference(heading, evade_heading_b))
		var chosen_dir := evade_dir if diff_a < diff_b else -evade_dir
		target_position = global_position + chosen_dir * 2000.0
		# 高度规避：切换档位
		if flat_altitude:
			if get_altitude_tier() == AltitudeTier.LOW:
				set_target_tier(AltitudeTier.HIGH)
			else:
				set_target_tier(AltitudeTier.LOW)
	elif not _evasion_override:
		# 无来袭导弹、无玩家手动覆盖：S 型机动
		_evasion_sway_timer += delta
		var sway_period := 3.0  # 每3秒切换方向
		var sway_angle := sin(_evasion_sway_timer * TAU / sway_period) * 0.8  # ±0.8弧度偏转
		var sway_heading := heading + sway_angle
		target_position = global_position + Vector2(sin(sway_heading), -cos(sway_heading)) * 1500.0

## 导弹更新（发射逻辑）
## SARH 导弹：一次只锁定一个目标，选最容易命中的
func _update_missile(delta: float) -> void:
	_missile_cooldown = maxf(_missile_cooldown - delta, 0.0)
	_crank_timer = maxf(_crank_timer - delta, 0.0)

	# 导弹装填系统（生存模式）
	if enable_missile_reload and _missile_reload_active:
		_missile_reload_timer += delta
		missile_reload_progress = clampf(_missile_reload_timer / missile_reload_duration, 0.0, 1.0)
		if _missile_reload_timer >= missile_reload_duration:
			missiles_remaining = params.missile.max_count if params and params.missile else 0
			_missile_reload_active = false
			_missile_reload_timer = 0.0
			missile_reload_progress = 0.0
		return

	# 机炮优先模式下不自动发射导弹
	if use_tactical_preference and weapon_preference == WeaponPreference.PREFER_GUN:
		return
	if weapon_mode != WeaponMode.MISSILE:
		return
	if _missile_cooldown > 0.0:
		return
	if not missile_manager:
		return

	# 选择导弹类型：地面目标用副导弹（AGM），空中目标用主导弹（AAM）
	var msl: MissileParams = null
	var use_secondary := false
	if combat_target and is_instance_valid(combat_target) and combat_target is GroundUnit:
		# 目标是地面单位 → 优先用副导弹
		if params and params.secondary_missile and secondary_missiles_remaining > 0:
			msl = params.secondary_missile
			use_secondary = true
		elif params and params.missile and missiles_remaining > 0:
			msl = params.missile  # 无副导弹时 fallback 到主导弹
	else:
		# 空中目标 → 只能用主导弹（AAM）。AGM 等副导弹是对地武器，不 fallback
		if params and params.missile and missiles_remaining > 0:
			msl = params.missile

	if msl == null:
		return

	# 多目标齐射（max_simultaneous_locks > 1 时）
	# 战术偏好模式下跳过齐射，只对 combat_target 发射（玩家手动指定目标）
	if max_simultaneous_locks > 1 and not use_tactical_preference:
		_fire_multi_lock_salvo(msl)
		return

	# 必须有明确的交战目标才允许发射导弹（玩家点击敌机设定）
	if combat_target == null or not is_instance_valid(combat_target) or combat_target.is_destroyed:
		return

	if missile_manager.has_active_missile_at(self, combat_target):
		return

	if not _is_in_missile_envelope(combat_target, msl):
		return

	if not is_in_radar_cone(combat_target.global_position):
		return

	var lock_progress: float = radar_targets.get(combat_target, 0.0)
	if lock_progress < params.lock_time + LOCK_STABLE_BUFFER:
		return

	_fire_missile_at(combat_target, msl, use_secondary)

## 对指定目标发射一枚导弹
func _fire_missile_at(target_unit: CombatUnit, msl: MissileParams, is_secondary: bool = false) -> void:
	var dist_m := global_position.distance_to(target_unit.global_position) / PIXELS_PER_METER
	var remaining := (secondary_missiles_remaining - 1) if is_secondary else (missiles_remaining - 1)
	EventLogger.log_event("MISSILE", _log_name(),
		"fired %s → %s (range=%.0fm, remaining=%d)" % [
			msl.display_name if msl.display_name else "missile",
			_log_unit_name(target_unit), dist_m, remaining])
	missile_manager.spawn_missile(self, target_unit, msl)
	if is_secondary:
		secondary_missiles_remaining -= 1
	else:
		missiles_remaining -= 1
	_missile_cooldown = msl.cooldown
	_crank_timer = CRANK_DURATION
	# 装填触发
	if enable_missile_reload and missiles_remaining <= 0:
		_missile_reload_active = true
		_missile_reload_timer = 0.0
		missile_reload_progress = 0.0


## 多目标齐射：选出多个已锁定目标，每个目标发射一枚
func _fire_multi_lock_salvo(msl: MissileParams) -> void:
	var locked_targets: Array[CombatUnit] = []
	var lock_threshold := params.lock_time + LOCK_STABLE_BUFFER

	for target_key in radar_targets:
		if not is_instance_valid(target_key):
			continue
		var target_unit: CombatUnit = target_key as CombatUnit
		if target_unit == null or target_unit.is_destroyed:
			continue
		if target_unit.team == team:
			continue
		if radar_targets[target_key] < lock_threshold:
			continue
		if not is_in_radar_cone(target_unit.global_position):
			continue
		if not _is_in_missile_envelope(target_unit, msl):
			continue
		if missile_manager.has_active_missile_at(self, target_unit):
			continue
		locked_targets.append(target_unit)

	if locked_targets.is_empty():
		return

	# 按距离排序，优先打近的
	locked_targets.sort_custom(func(a: CombatUnit, b: CombatUnit) -> bool:
		return global_position.distance_squared_to(a.global_position) < global_position.distance_squared_to(b.global_position)
	)

	var fire_count := mini(mini(locked_targets.size(), max_simultaneous_locks), missiles_remaining)
	for i in range(fire_count):
		missile_manager.spawn_missile(self, locked_targets[i], msl)
		missiles_remaining -= 1

	if fire_count > 0:
		_missile_cooldown = msl.cooldown
		_crank_timer = CRANK_DURATION
		# 装填触发
		if enable_missile_reload and missiles_remaining <= 0:
			_missile_reload_active = true
			_missile_reload_timer = 0.0
			missile_reload_progress = 0.0

## 从雷达锁定的目标中选出最优的一个（命中概率最高）
## 评分标准：距离近 + 机头偏差小 + 锁定时间长 = 分高
func _select_best_missile_target() -> CombatUnit:
	var best: CombatUnit = null
	var best_score: float = -1.0
	var my_fwd := Vector2(sin(heading), -cos(heading))

	for target_key in radar_targets:
		if not is_instance_valid(target_key):
			continue
		var target_unit: CombatUnit = target_key as CombatUnit
		if target_unit == null or target_unit.is_destroyed:
			continue
		if target_unit.team == team:
			continue
		# 必须有一定锁定累积（至少在锥内待过一会儿）
		var lock_progress: float = radar_targets[target_key]
		if lock_progress < 0.5:
			continue

		var to_tgt := (target_unit.global_position - global_position)
		var dist := to_tgt.length()
		if dist < 1.0:
			continue

		# 机头偏差（越小越好）
		var angle_to_tgt := atan2(to_tgt.x, -to_tgt.y)
		var nose_diff := absf(_angle_diff(angle_to_tgt, heading))

		# 闭合率（正值=接近，越高越好命中）
		var tgt_fwd := Vector2(sin(target_unit.heading), -cos(target_unit.heading))
		var tgt_speed_px := target_unit.speed * PIXELS_PER_METER
		var my_speed_px := speed * PIXELS_PER_METER
		var to_tgt_dir := to_tgt.normalized()
		var closing := my_fwd.dot(to_tgt_dir) * my_speed_px - tgt_fwd.dot(to_tgt_dir) * tgt_speed_px

		# 评分：距离近（归一化）+ 偏差小 + 闭合率高 + 锁定时间长
		var dist_score := clampf(1.0 - dist / 10000.0, 0.0, 1.0)
		var angle_score := clampf(1.0 - nose_diff / deg_to_rad(60.0), 0.0, 1.0)
		var closing_score := clampf(closing / 500.0, -0.5, 1.0)
		var lock_score := clampf(lock_progress / 5.0, 0.0, 1.0)

		var score := dist_score * 0.25 + angle_score * 0.35 + closing_score * 0.25 + lock_score * 0.15

		if score > best_score:
			best_score = score
			best = target_unit

	return best

## 检查目标是否在导弹射程包线内
func _is_in_missile_envelope(target_unit: CombatUnit, msl: MissileParams) -> bool:
	var dist_px := global_position.distance_to(target_unit.global_position)
	var dist_m := dist_px / PIXELS_PER_METER

	if dist_m < msl.min_range:
		return false

	# TAA（目标纵横角）
	var tgt_fwd := Vector2(sin(target_unit.heading), -cos(target_unit.heading))
	var to_me := (global_position - target_unit.global_position).normalized()
	var taa_rad := acos(clampf(-tgt_fwd.dot(to_me), -1.0, 1.0))
	var taa_deg := rad_to_deg(taa_rad)

	# 最大射程
	var max_range: float
	if taa_deg <= 90.0:
		var t := taa_deg / 90.0
		max_range = msl.max_range_rear * msl.front_rear_ratio * (1.0 - t) + msl.max_range_rear * t
	else:
		max_range = msl.max_range_rear

	# 高度射程加成（扁平模式下固定中档基准）
	var alt_factor: float
	if flat_altitude:
		alt_factor = 1.5
	else:
		alt_factor = clampf(1.0 + (altitude / 12000.0) * 1.5, 1.0, 3.0)
	max_range *= alt_factor

	if dist_m > max_range:
		return false

	# 高度差限制（扁平模式下忽略）
	if not flat_altitude and absf(altitude - target_unit.altitude) > 3000.0:
		return false

	return true

## 受到伤害（通用）
func take_damage(amount: float) -> void:
	if is_destroyed:
		return
	if survivor_missile_damage_cap > 0.0:
		amount = minf(amount, survivor_missile_damage_cap)
	_apply_damage(amount)

## 受到机炮伤害（可被装甲闪避）
func take_bullet_damage(amount: float) -> void:
	if is_destroyed:
		return
	if bullet_dodge_chance > 0.0 and randf() < bullet_dodge_chance:
		return  # 装甲偏转，无视伤害
	if survivor_bullet_damage_cap > 0.0:
		amount = minf(amount, survivor_bullet_damage_cap)
	_apply_damage(amount)

func _apply_damage(amount: float) -> void:
	var old_hp := hp
	hp -= amount
	EventLogger.log_event("DAMAGE", _log_name(),
		"took %.0f damage (hp=%.0f→%.0f)" % [amount, old_hp, hp])
	if hp <= 0.0:
		hp = 0.0
		_start_destroy()

func _check_ground_crash() -> void:
	# 高度为 0 且非起飞状态 → 坠地
	if altitude <= 0.0 and not is_destroyed:
		altitude = 0.0
		_start_destroy()

func _start_destroy() -> void:
	EventLogger.log_event("DESTROY", _log_name(),
		"destroyed (alt=%.0fm, spd=%.0fm/s)" % [altitude, speed])
	# 回收 callsign
	CallsignDB.recycle(callsign)
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
	_draw_flare_particles()
	if hide_data_label:
		_draw_data_label_minimal()
	else:
		_draw_data_label()
	_draw_tactic_popup()

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

func _draw_flare_particles() -> void:
	for p in _flare_particles:
		var pos: Vector2 = p["pos"]
		var life: float = p["life"]
		var is_bright: bool = p.get("bright", false)
		var local_pos := to_local(pos)
		var alpha := clampf(life / 1.5, 0.0, 1.0)
		if is_bright:
			# 核心亮点：大且白亮
			var size := lerpf(2.0, 5.0, alpha)
			var core := Color(1.0, 1.0, 0.9, alpha * 0.95)
			draw_circle(local_pos, size, core)
			# 外发光
			var glow := Color(1.0, 0.7, 0.2, alpha * 0.3)
			draw_circle(local_pos, size * 2.5, glow)
		else:
			# 拖尾：橙黄色，较小
			var size := lerpf(1.0, 3.0, alpha)
			var color := Color(1.0, 0.8, 0.3, alpha * 0.7)
			draw_circle(local_pos, size, color)

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

	# 高度缩放：以 5000m 为基准（scale=1.0），低空缩小、高空放大
	# 使用 sqrt 曲线让中低空的变化更明显
	var ref_alt := 5000.0
	var max_alt := params.max_altitude if params else 15000.0
	var alt_ratio := clampf(altitude / max_alt, 0.0, 1.0)
	var ref_ratio := ref_alt / max_alt
	# 基准以下：0.65~1.0，基准以上：1.0~1.4
	var base_scale: float
	if alt_ratio <= ref_ratio:
		base_scale = lerpf(0.65, 1.0, sqrt(alt_ratio / ref_ratio))
	else:
		base_scale = lerpf(1.0, 1.4, (alt_ratio - ref_ratio) / (1.0 - ref_ratio))

	# 滚转变形
	var bank_compress := cos(bank_angle)
	var sx := base_scale * bank_compress
	var sy := base_scale

	var xform := Transform2D(0.0, Vector2.ZERO)
	xform = xform.scaled(Vector2(sx, sy))

	# 指挥 UAV（哨兵）使用独立的飞翼外观
	var is_commander: bool = has_meta("enemy_type") and get_meta("enemy_type") == "uav_commander"
	if is_commander:
		_draw_commander_icon(color, outline_color, size, base_scale, xform)
		return

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

## 指挥 UAV "哨兵" 专用飞翼外观
func _draw_commander_icon(color: Color, outline_color: Color, size: float, base_scale: float, xform: Transform2D) -> void:
	var s := size  # 简写

	# ── 飞翼主体：宽扁的 V 形无尾翼体 ──
	# 从机头到两侧翼尖再收回，一体化飞翼造型
	var wing_body: PackedVector2Array = PackedVector2Array([
		Vector2(0, -s * 0.7),              # 机头（钝头）
		Vector2(s * 0.2, -s * 0.5),        # 机头右侧
		Vector2(s * 1.3, s * 0.1),         # 右翼前缘尖端（宽展）
		Vector2(s * 1.2, s * 0.25),        # 右翼后缘
		Vector2(s * 0.5, s * 0.2),         # 右翼根部后缘
		Vector2(s * 0.15, s * 0.5),        # 右侧尾部
		Vector2(0, s * 0.4),               # 尾部中心（浅 V 形凹口）
		Vector2(-s * 0.15, s * 0.5),       # 左侧尾部
		Vector2(-s * 0.5, s * 0.2),        # 左翼根部后缘
		Vector2(-s * 1.2, s * 0.25),       # 左翼后缘
		Vector2(-s * 1.3, s * 0.1),        # 左翼前缘尖端
		Vector2(-s * 0.2, -s * 0.5),       # 机头左侧
	])

	# 应用缩放变换并绘制
	var transformed: PackedVector2Array = PackedVector2Array()
	for p in wing_body:
		transformed.append(xform * p)
	draw_colored_polygon(transformed, color)
	# 轮廓线
	for i in range(transformed.size()):
		var from := transformed[i]
		var to := transformed[(i + 1) % transformed.size()]
		draw_line(from, to, outline_color, 1.0, true)

	# ── 机背中线标记（传感器/天线阵列） ──
	var accent := color.lightened(0.3)
	accent.a = 0.6
	var line_from := xform * Vector2(0, -s * 0.4)
	var line_to := xform * Vector2(0, s * 0.25)
	draw_line(line_from, line_to, accent, 1.5, true)

	# ── 天线顶点标记 ──
	var antenna_base := xform * Vector2(0, -s * 0.7)
	var antenna_tip := xform * Vector2(0, -s * 1.1)
	draw_line(antenna_base, antenna_tip, accent, 1.0, true)
	draw_circle(antenna_tip, 2.5 * base_scale, accent)

	# 选中指示
	if selected:
		var ring_color := color
		ring_color.a = 0.5
		draw_arc(Vector2.ZERO, s * 1.8 * base_scale, 0, TAU, 48, ring_color, 1.5)

## 在飞机旁边绘制数据标签框（逐行列出所有参数）
## 是否使用精简标签（无导弹/无热诱弹的简单单位）
func _is_minimal_label() -> bool:
	if not params:
		return false
	return params.missile == null and params.flare == null

## 生存模式玩家用精简标签：只显示朝向、速度、高度、G、耐力
func _draw_data_label_minimal() -> void:
	var speed_kmh := speed * 3.6
	var heading_deg := rad_to_deg(heading)
	if heading_deg < 0:
		heading_deg += 360.0

	var lines := PackedStringArray()
	lines.append(callsign)
	lines.append("HDG %03d" % roundi(heading_deg))
	lines.append("%d kt" % roundi(speed_kmh * 0.5399))
	if flat_altitude:
		lines.append("ALT %s" % TIER_NAMES[get_altitude_tier()])
	else:
		lines.append("ALT %dm" % roundi(altitude))
	lines.append("G %.1f" % g_load)
	var max_stam := params.pilot_stamina if params else 100.0
	lines.append("STA %d%%" % roundi(pilot_stamina / maxf(max_stam, 0.01) * 100.0))

	var inv_rot := -rotation
	var font_size := 11
	var line_height := 14.0
	# 缩放补偿
	var zoom_scale := get_viewport_transform().get_scale()
	var inv_zoom := 1.0 / maxf(zoom_scale.x, 0.01)
	var label_offset := Vector2(24 * inv_zoom, -12 * inv_zoom).rotated(inv_rot)

	var max_w := 0.0
	for line in lines:
		var w := _font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		max_w = maxf(max_w, w)

	var scale_v := Vector2(inv_zoom, inv_zoom)
	var team_color: Color = params.icon_color if params else Color.GREEN
	var bg_color := Color(team_color.r * 0.15, team_color.g * 0.15, team_color.b * 0.2, 0.7)

	draw_set_transform(label_offset, inv_rot, scale_v)
	draw_rect(Rect2(-2, -2, max_w + 6, lines.size() * line_height + 4), bg_color)
	for i in range(lines.size()):
		draw_string(_font, Vector2(0, i * line_height + 11), lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(0.85, 0.9, 0.85, 0.9))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

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
	lines.append("%s [%s]" % [callsign, display_name])
	if not _is_minimal_label():
		lines.append("HDG %03d" % roundi(heading_deg))
	lines.append("%d kt" % roundi(speed_kmh * 0.5399))
	if not _is_minimal_label():
		lines.append("M%.2f" % mach)
	if flat_altitude:
		lines.append("ALT %s" % TIER_NAMES[get_altitude_tier()])
	else:
		lines.append("ALT %dm" % roundi(altitude))
	lines.append("G %.1f/%.0f" % [g_load, _effective_max_g()])
	if not _is_minimal_label() and not no_stamina:
		var max_stam := params.pilot_stamina if params else 100.0
		lines.append("STA %d%%" % roundi(pilot_stamina / maxf(max_stam, 0.01) * 100.0))
	if params and params.missile:
		lines.append("MSL %d" % missiles_remaining)
	if params and params.gun:
		lines.append("AMM %d" % ammo)
	if params and params.flare:
		lines.append("FLR %d" % flares_remaining)
	if not infinite_fuel:
		lines.append("FUEL %d" % roundi(fuel))
	if is_afterburner and not infinite_fuel:
		lines.append("AB")
	if status != "":
		lines.append(status)

	var inv_rot := -rotation
	var font_size := 11
	var line_height := 14.0
	# 缩放补偿：标签大小不随摄像机缩放变化
	var zoom_scale := get_viewport_transform().get_scale()
	var inv_zoom := 1.0 / maxf(zoom_scale.x, 0.01)
	var label_offset := Vector2(24 * inv_zoom, -12 * inv_zoom).rotated(inv_rot)

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

	var scale_v := Vector2(inv_zoom, inv_zoom)
	draw_set_transform(label_offset, inv_rot, scale_v)
	draw_rect(Rect2(0, 0, box_w, box_h), bg_color)
	draw_rect(Rect2(0, 0, box_w, box_h), text_color * Color(1, 1, 1, 0.4), false, 1.0)

	for i in range(lines.size()):
		draw_string(_font, Vector2(5, 12 + i * line_height), lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, text_color)

	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func _draw_tactic_popup() -> void:
	if _tactic_popup_timer <= 0.0 or _tactic_popup_text == "":
		return
	var inv_rot := -rotation
	var font_size := 12
	# 渐隐：最后 0.5 秒淡出
	var alpha := clampf(_tactic_popup_timer / 0.5, 0.0, 1.0)
	# 上浮效果：随时间向上飘
	var elapsed := TACTIC_POPUP_DURATION - _tactic_popup_timer
	var float_offset := elapsed * 15.0  # 向上飘动速度
	var text_w := _font.get_string_size(_tactic_popup_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var popup_pos := Vector2(-text_w * 0.5, -30.0 - float_offset).rotated(inv_rot)
	var bg_color := Color(0.1, 0.1, 0.1, 0.7 * alpha)
	var text_color := Color(1.0, 0.9, 0.3, alpha)
	var pad := Vector2(4, 2)
	draw_set_transform(popup_pos, inv_rot, Vector2.ONE)
	draw_rect(Rect2(-pad.x, -12 - pad.y, text_w + pad.x * 2, 14 + pad.y * 2), bg_color)
	draw_string(_font, Vector2(0, 0), _tactic_popup_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, text_color)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func _draw_target_line() -> void:
	if not selected and team != 0:
		return

	# 有战斗目标时：连接线指向敌机
	if combat_target and is_instance_valid(combat_target) and not combat_target.is_destroyed:
		var ct_color := Color(0.3, 0.6, 1.0, 0.6) if team == 0 else Color(1.0, 0.3, 0.2, 0.6)
		var ct_local := to_local(combat_target.global_position)
		draw_line(Vector2.ZERO, ct_local, ct_color, 1.5, true)
		var ct_d := 8.0
		draw_line(ct_local + Vector2(-ct_d, 0), ct_local + Vector2(ct_d, 0), ct_color, 1.5)
		draw_line(ct_local + Vector2(0, -ct_d), ct_local + Vector2(0, ct_d), ct_color, 1.5)
		draw_circle(ct_local, ct_d, Color(ct_color, 0.2))
		return

	if target_position == Vector2.INF:
		return

	if team != 0:
		return

	# 编队僚机不显示预测线/航点：它们跟随长机指令，target_position 只是阵型槽位
	if formation_mode:
		return

	var color: Color = params.icon_color if params else Color.GREEN

	var local_target := to_local(target_position)

	# 预测飞行路径
	_draw_predicted_path(local_target, color)

	# 航点标记 — 十字 + 圆环
	var d := 10.0
	var marker_color := Color(0.3, 0.8, 1.0, 0.7)
	draw_circle(local_target, d, Color(marker_color, 0.15))
	draw_arc(local_target, d, 0, TAU, 32, marker_color, 1.5)
	draw_line(local_target + Vector2(-d * 1.3, 0), local_target + Vector2(d * 1.3, 0), marker_color, 1.0)
	draw_line(local_target + Vector2(0, -d * 1.3), local_target + Vector2(0, d * 1.3), marker_color, 1.0)

## 绘制预测飞行路径：模拟转弯弧线 + 直线段
## 模拟真实物理：滚转速率、速度衰减、G力限制
func _draw_predicted_path(local_target: Vector2, base_color: Color) -> void:
	var path_color := Color(base_color.r, base_color.g, base_color.b, 0.35)

	# 模拟参数（从当前飞机状态初始化）
	var sim_heading := heading
	var sim_pos := global_position
	var sim_speed := maxf(speed, 50.0)  # m/s
	var sim_bank := bank_angle          # 当前坡度
	var roll_rate_val := params.roll_rate if params else 4.0
	var accel_rate := params.acceleration if params else 50.0
	var decel_rate := params.deceleration if params else 80.0
	var cruise_ms := (params.cruise_speed if params else 900.0) / 3.6
	var stall_base_ms := (params.stall_speed_base if params else 220.0) / 3.6

	var step := 0.08  # 更细的模拟步长
	var max_steps := 180
	var record_interval := 3  # 每3步记录一个点

	var points := PackedVector2Array()
	points.append(Vector2.ZERO)

	for i in range(max_steps):
		var to_tgt := target_position - sim_pos
		var dist_to_tgt := to_tgt.length()
		if dist_to_tgt < sim_speed * PIXELS_PER_METER * step * 2.0:
			points.append(to_local(sim_pos))
			break

		# 目标航向
		var tgt_heading := atan2(to_tgt.x, -to_tgt.y)
		var hdiff := _angle_diff(tgt_heading, sim_heading)

		# 模拟目标坡度（与实际 _update_bank 逻辑一致）
		var max_bank_sim := _max_bank_angle_at_speed(sim_speed, stall_base_ms)
		var target_bank: float
		if abs(hdiff) < 0.05:
			target_bank = 0.0
		elif abs(hdiff) < 0.4:
			target_bank = sign(hdiff) * max_bank_sim * 0.3
		else:
			target_bank = sign(hdiff) * max_bank_sim
		# 接近目标时衰减坡度
		var prox := clampf((dist_to_tgt - 150.0) / 300.0, 0.0, 1.0)
		target_bank *= prox

		# 滚转速率限制
		var bank_diff := target_bank - sim_bank
		var max_roll := roll_rate_val * step
		sim_bank += clampf(bank_diff, -max_roll, max_roll)

		# 转弯（基于当前坡度）
		if abs(sim_bank) > 0.001:
			var turn_rate := GRAVITY * tan(sim_bank) / maxf(sim_speed, 1.0)
			sim_heading += turn_rate * step
			sim_heading = fmod(sim_heading + PI, TAU) - PI

		# 速度模拟：转弯时减速（G力阻力），直飞时恢复巡航速度
		var current_g := 1.0 / maxf(cos(sim_bank), 0.01)
		var drag_decel := (current_g - 1.0) * 8.0  # G力越大减速越快
		var target_speed := cruise_ms
		if sim_speed > target_speed:
			sim_speed -= (decel_rate * 0.5 + drag_decel) * step
		else:
			sim_speed += accel_rate * 0.3 * step
		sim_speed = maxf(sim_speed, stall_base_ms * 1.3)

		# 前进
		var vel := Vector2(sin(sim_heading), -cos(sim_heading)) * sim_speed * PIXELS_PER_METER
		sim_pos += vel * step

		if i % record_interval == 0:
			points.append(to_local(sim_pos))

	# 绘制路径（虚线效果：交替绘制段）
	if points.size() >= 2:
		for i in range(points.size() - 1):
			if i % 2 == 0:
				var alpha := lerpf(0.4, 0.1, float(i) / float(points.size()))
				var seg_color := Color(path_color.r, path_color.g, path_color.b, alpha)
				draw_line(points[i], points[i + 1], seg_color, 1.5)

## 计算指定速度下的最大坡度角（预测线用）
func _max_bank_angle_at_speed(spd: float, stall_base_ms: float) -> float:
	var max_g_val := _effective_max_g()
	var g_limited_bank := acos(1.0 / max_g_val)
	var safe_margin := 1.2
	if spd > stall_base_ms * safe_margin:
		var effective_speed := spd / safe_margin
		var max_g_for_speed := (effective_speed / stall_base_ms) * (effective_speed / stall_base_ms)
		var speed_limited_bank := acos(1.0 / maxf(max_g_for_speed, 1.01))
		return minf(g_limited_bank, speed_limited_bank)
	else:
		var ratio := clampf(spd / (stall_base_ms * safe_margin), 0.0, 1.0)
		return 0.1 + ratio * 0.2

# ========== 热诱弹系统 ==========

func is_lock_immune() -> bool:
	return _lock_immunity_timer > 0.0

func _update_flares(delta: float) -> void:
	# 更新锁定免疫计时
	if _lock_immunity_timer > 0.0:
		_lock_immunity_timer = maxf(_lock_immunity_timer - delta, 0.0)

	# 更新粒子
	_update_flare_particles(delta)

	# 冷却
	_flare_cooldown = maxf(_flare_cooldown - delta, 0.0)

	if not params or not params.flare:
		return

	# 热诱弹装填（生存模式）：用完后等冷却结束自动补满
	if enable_flare_reload and flares_remaining <= 0:
		if _flare_cooldown > 0.0:
			flare_reload_progress = 1.0 - (_flare_cooldown / params.flare.cooldown)
		else:
			flares_remaining = params.flare.max_flares
			flare_reload_progress = 0.0
		return

	flare_reload_progress = 0.0
	if flares_remaining <= 0:
		return
	if _flare_cooldown > 0.0:
		return
	if not missile_manager:
		return

	# 检测来袭导弹
	var nearest_missile: Missile = null
	var nearest_dist := 99999.0
	for child in missile_manager.get_children():
		if not child is Missile:
			continue
		var m: Missile = child
		if not m.is_active or m.is_flare_jammed:
			continue
		if m.target != self:
			continue
		var dist_px := m.global_position.distance_to(global_position)
		if dist_px < nearest_dist:
			nearest_dist = dist_px
			nearest_missile = m

	if not nearest_missile:
		return

	# 根据飞行员性格计算释放距离（米）
	var fp := params.flare
	var release_dist_m := lerpf(fp.calm_distance, fp.panic_distance, fp.nervousness)
	var release_dist_px := release_dist_m * PIXELS_PER_METER

	if nearest_dist > release_dist_px:
		return

	# 释放！
	_release_flares()

func _release_flares() -> void:
	var fp := params.flare
	var count := mini(fp.burst_count, flares_remaining)
	flares_remaining -= count
	_flare_cooldown = fp.cooldown
	EventLogger.log_event("FLARE", _log_name(),
		"deployed %d flares (remaining=%d)" % [count, flares_remaining])

	# 电子对抗升级：释放热诱弹时清除所有雷达锁定 + 启动锁定免疫
	if flare_lock_immunity > 0.0:
		_lock_immunity_timer = flare_lock_immunity
		# 清除所有敌机对自己的雷达锁定
		for ac_ref in locked_by.duplicate():
			if is_instance_valid(ac_ref):
				ac_ref.radar_targets.erase(self)
		locked_by.clear()
		is_locked = false

	# 分批释放视觉粒子（模拟热诱弹逐颗弹出）
	var burst_waves := 6  # 分6波释放
	var wave_interval := 0.12  # 每波间隔0.12秒
	for w in range(burst_waves):
		_flare_spawn_queue.append({
			"delay": float(w) * wave_interval,
			"heading": heading,  # 记录释放时的航向
			"pos": global_position,  # 记录释放时的位置（会被更新）
		})

	# 对每枚来袭导弹判定干扰
	if not missile_manager:
		return
	for child in missile_manager.get_children():
		if not child is Missile:
			continue
		var m: Missile = child
		if not m.is_active or m.is_flare_jammed:
			continue
		if m.target != self:
			continue

		var jam_chance: float
		if flares_guaranteed:
			# 后侧方来袭导弹100%干扰，正面不保证
			var missile_to_me := (global_position - m.global_position).normalized()
			var my_fwd := Vector2(sin(heading), -cos(heading))
			var dot := my_fwd.dot(missile_to_me)
			# dot > 0 = 导弹从正面来，dot < 0 = 导弹从后方追
			if dot <= 0.3:  # 后方 + 侧方（约±70°后半球）
				jam_chance = 1.0
			else:
				jam_chance = _calc_jam_chance(m)  # 正面用普通概率
		else:
			jam_chance = _calc_jam_chance(m)
		if randf() < jam_chance:
			m.is_flare_jammed = true
			var msl_name: String = m.params.display_name if m.params else "MSL"
			EventLogger.log_event("MISSILE", msl_name,
				"flare jammed (target was %s, jam_chance=%.0f%%)" % [
					_log_name(), jam_chance * 100.0])

func _calc_jam_chance(m: Missile) -> float:
	var fp := params.flare
	var chance := fp.base_jam_chance

	# 导弹来袭角度：从侧/后方追来更容易被干扰
	var missile_to_me := (global_position - m.global_position).normalized()
	var my_fwd := Vector2(sin(heading), -cos(heading))
	var dot := my_fwd.dot(missile_to_me)
	# dot > 0 = 导弹从前方来（正面迎击，难干扰）
	# dot < 0 = 导弹从后方追（尾追，容易干扰）
	if dot < 0.0:
		chance += fp.aspect_bonus

	# 正在大幅机动增加干扰率
	if g_load > 4.0:
		chance += fp.maneuvering_bonus

	# 极近距离惩罚
	var dist_m := m.global_position.distance_to(global_position) / PIXELS_PER_METER
	if dist_m < 150.0:
		chance -= fp.close_range_penalty

	# 导弹低能量（发动机熄火后）更容易被干扰
	if m.age > m.params.motor_burn_time:
		chance += fp.low_energy_bonus

	return clampf(chance, 0.05, 0.95)

## 热诱弹冷却比例（0=就绪, 1=刚释放），HUD 读取用
func get_flare_cooldown_ratio() -> float:
	if not params or not params.flare or params.flare.cooldown <= 0.0:
		return 0.0
	return clampf(_flare_cooldown / params.flare.cooldown, 0.0, 1.0)

func _update_flare_particles(delta: float) -> void:
	# 处理延迟释放队列
	var remaining_queue: Array[Dictionary] = []
	for q in _flare_spawn_queue:
		q["delay"] -= delta
		q["pos"] = global_position  # 每帧更新为飞机当前位置（跟随飞机）
		q["heading"] = heading       # 更新为当前航向
		if float(q["delay"]) <= 0.0:
			_spawn_flare_wave(q["pos"] as Vector2, float(q["heading"]))
		else:
			remaining_queue.append(q)
	_flare_spawn_queue = remaining_queue

	# 更新已有粒子
	var kept: Array[Dictionary] = []
	for p in _flare_particles:
		p["life"] -= delta
		if float(p["life"]) <= 0.0:
			continue
		p["pos"] = (p["pos"] as Vector2) + (p["vel"] as Vector2) * delta
		# 减速 + 轻微随机漂移
		var vel: Vector2 = p["vel"] as Vector2
		vel *= 0.96
		vel += Vector2(randf_range(-3.0, 3.0), randf_range(-3.0, 3.0))
		p["vel"] = vel
		kept.append(p)
	_flare_particles = kept

## 生成一波热诱弹粒子（从飞机当前位置向后方喷射）
func _spawn_flare_wave(spawn_pos: Vector2, spawn_heading: float) -> void:
	var back_dir := Vector2(-sin(spawn_heading), cos(spawn_heading))
	var perp := Vector2(back_dir.y, -back_dir.x)
	# 每波 2-3 颗粒子
	var wave_count := randi_range(2, 3)
	for k in range(wave_count):
		var spread := randf_range(-0.6, 0.6)
		var vel := (back_dir + perp * spread) * randf_range(70.0, 130.0)
		var is_bright := k == 0  # 每波第一颗最亮
		_flare_particles.append({
			"pos": spawn_pos + back_dir * randf_range(8.0, 15.0) + perp * randf_range(-4.0, 4.0),
			"vel": vel,
			"life": randf_range(2.0, 3.5),
			"bright": is_bright,
		})

func _update_visuals() -> void:
	rotation = heading
