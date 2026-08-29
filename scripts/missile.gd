class_name Missile
extends Node2D

## DEADAIR 5Hz 控制器使用的维护式注册表，避免每 tick 扫 MissileManager 子节点。
static var active_missiles: Array[Missile] = []

const PIXELS_PER_METER: float = GameConstants.PIXELS_PER_METER
const GRAVITY: float = GameConstants.GRAVITY
## 战略远景只省略非关键导弹的两行数据标签；弹体、尾迹、命中和来袭警告不受影响。
const DATA_LABEL_MIN_VIEW_SCALE: float = 0.26
## 小于该缩放时，普通导弹只保留弹体轮廓 + 尾迹；玩家弹和真实来袭弹仍画完整翼面/尾焰。
const BODY_DETAIL_MIN_VIEW_SCALE: float = 0.26
var params: MissileParams
var source: CombatUnit        ## 发射单位（SARH 需要持续照射）
var target: CombatUnit        ## 目标
var team: int = 0

var heading: float = 0.0     ## 弧度, 0=北
var speed: float = 300.0     ## m/s
var altitude: float = 5000.0 ## 米
var age: float = 0.0         ## 存活时间
var distance_traveled_px: float = 0.0 ## 实际累计路径；定距空爆不能用出生点直线位移代替
var is_active: bool = true
var has_guidance: bool = true
var is_flare_jammed: bool = false  ## 被热诱弹干扰，永久失去制导
var climb_break_disrupted: bool = false ## 被 CLIMB 反制：永久失导且禁止签名技重索敌
var _guidance_ever_lost: bool = false  ## 飞行中曾丢制导(出 FOV/照射中断)——脱靶日志区分"末段丢锁"vs"全程制导仍脱靶"
## 敌机投焰不会立刻 jam；本弹保存一次有限 break 快照，真实轨迹达门且等级 roll 通过后才失导。
var enemy_flare_break_pending: bool = false
var _enemy_flare_break_target_id: int = 0
var _enemy_flare_break_start_pos: Vector2 = Vector2.ZERO
var _enemy_flare_break_start_heading: float = 0.0
var _enemy_flare_break_start_speed: float = 0.0
var _enemy_flare_break_start_altitude: float = 0.0
var _enemy_flare_break_elapsed: float = 0.0
var _enemy_flare_break_roll_passed: bool = false
var _enemy_flare_break_chance: float = 0.0
const ENEMY_FLARE_BREAK_WINDOW_S: float = 1.25
const ENEMY_FLARE_BREAK_HEADING_RAD: float = deg_to_rad(22.0)
const ENEMY_FLARE_BREAK_LATERAL_PX: float = 120.0
const ENEMY_FLARE_BREAK_SPEED_MIN_MS: float = 45.0
const ENEMY_FLARE_BREAK_SPEED_RATIO: float = 0.18
const ENEMY_FLARE_BREAK_ALTITUDE_M: float = 450.0
## ── 722 批签名技能（spec aircraft-signature-skills，spawn_missile 按发射者技能打标）──
var sig_silent: bool = false          ## 夜枭（X-09）：敌机对本弹无警觉（不规避、不投焰）
var sig_retarget_armed: bool = false  ## 超越地平（X-21）：被 flare 偏转后可重索敌（每弹一次）
var _sig_retarget_timer: float = 0.0  ## 超越地平：偏转后直飞累计秒数（≥2s 触发重索敌）
var bounces_remaining: int = 0     ## 剩余弹跳次数（连锁弹头进化）
var proximity_aoe: bool = false    ## 近炸引信：爆炸时产生 AOE 区域
var penetrates_after_hit: bool = false ## 连锁弹头：命中后保留实体并沿原航向继续飞行
var penetration_hit_count: int = 0     ## 已完成的穿透命中数；至少一次后寿命耗尽不再误记脱靶
var _penetrated_unit_ids: Dictionary = {} ## 同一枚导弹对同一目标最多结算一次伤害

## CIWS 拦截累积伤害 —— 只有 CIWS 子弹能减这个，归零时导弹 is_active=false
## 并非通用受击血量：导弹仍然是"一发命中目标即爆炸"，这里只表示"被拦截弹击落"
## 初始值在 _ready 时从 params.intercept_hp 读取（所有型号 / 队伍共用同一套机制）
var intercept_hp: float = 60.0

## ── VLS 三段式弹道状态（仅 params.is_vls_salvo=true 的导弹用）──
## 0 = VERTICAL（垂直爬升），1 = TRANSITION（过渡俯冲），2 = TERMINAL（末端追踪）
var vls_phase: int = 0
var _vls_phase_timer: float = 0.0
## 发射瞬间锁死的玩家位置（不会更新）—— 阶段 2 朝这个点倾斜
var vls_locked_point: Vector2 = Vector2.INF
## 每发齐射弹的速度随机系数，0.8~1.2 之间 —— 让齐射弹错开，不重叠
var speed_multiplier: float = 1.0

var _prev_los_angle: float = 0.0  ## 上一帧 LOS 角（有限差分算角速率）
var _prev_heading: float = 0.0   ## 上一帧航向（用于计算模拟 bank）
var bank_angle: float = 0.0      ## 模拟 bank（由航向变化率推算）
var _trail_ribbon: TrailRibbon
var _deadair_base_trail_color: Color = Color.WHITE
var deadair_exposure_ratio: float = 0.0
var _font: Font

## VLS phase 0/1 降帧 tick 状态（详见 SurvivorData.ENABLE_VLS_LOW_RATE_TICK）
var _vls_low_rate_counter: int = 0
const VLS_LOW_RATE_DIVISOR: int = 3   ## 60Hz / 3 = 20Hz

## 缓存的 MissileManager 引用（首次 _physics_process 时解析）
var _mm = null

## 寿命到期 / 能量耗尽 / 制导彻底丢失时进入 coasting fade，而不是瞬间消失。
## 命中爆炸由 MissileManager 直接 queue_free，已有 ExplosionVFX 替代视觉，不走 fade。
const FADE_OUT_DURATION: float = 0.5
var _fading_out: bool = false

## 激光减速计时（敌方激光照射导弹时由 LaserEquipment 写入）
## > 0 时导弹每秒流失 35% 最大速度、max_g ×0.5；降至最大速度 20% 时失能。
var _laser_slow_timer: float = 0.0
var _fade_timer: float = 0.0

## AWACS 支援 buff（spec global-awareness-roe §2.6c）：发射瞬间 shooter 在预警机
## 8000m 圈内 → 追踪 G ×1.25，弹全程生效（快照式，spawn_missile 写入，不逐帧查询）
var awacs_g_mult: float = 1.0
var is_secondary_weapon: bool = false  ## 副槽 QAAM 发射（kind 归因 "qmaam"，720 批）
var second_stage: bool = false         ## 二段推进（720 批）：一段燃尽后续推 + 转弯渐强


## 二段推进转弯渐强：飞行时间线性升到 +50%（~6s 拉满）——"距离越远越准"
func _second_stage_g_mult() -> float:
	return (1.0 + minf(age * 0.08, 0.5)) if second_stage else 1.0


## DEC-003 的纯规则入口；RadarDisplay 与世界警告必须共享同一语义。
static func incoming_warning_rule(active: bool, guided: bool, flare_jammed: bool,
		target_matches: bool, hostile: bool, closing: bool, vls_preterminal: bool) -> bool:
	return active and guided and not flare_jammed and target_matches and hostile \
		and (closing or vls_preterminal)


func is_incoming_warning_for(player: CombatUnit) -> bool:
	if player == null or not is_instance_valid(player) or player.is_destroyed:
		return false
	var to_player: Vector2 = player.global_position - global_position
	var closing := true
	if to_player.length_squared() > 1.0:
		var missile_fwd := Vector2(sin(heading), -cos(heading))
		closing = missile_fwd.dot(to_player.normalized()) > 0.0
	var vls_preterminal: bool = params != null and params.is_vls_salvo and vls_phase < 2
	return incoming_warning_rule(is_active, has_guidance, is_flare_jammed,
		target == player, CombatUnit.teams_hostile(team, player.team), closing, vls_preterminal)

## ── 云层穿越累计衰减 ──
var _cloud_guidance_loss: float = 0.0   ## 0~(1-FLOOR) 累加不回复

## 建筑遮挡相关
## spawn 时检查源是否在街区内：是则导弹永久免疫建筑拦截（"从内部射出"规则）
var spawned_in_building: bool = false
## spawn 时记录发射源的高度档位 — 用于查建筑拦截概率
var source_tier: int = 0  # CombatUnit.AltitudeTier
## 上一帧是否在街区内 — 用来检测"从外部进入"事件，每次进入触发一次 roll
var _was_in_building: bool = false
const CLOUD_LOSS_PER_SECOND: float = 0.12
const CLOUD_LOSS_FLOOR: float = 0.3     ## 至少保留 30% 追踪

func _ready() -> void:
	active_missiles.append(self)
	_trail_ribbon = TrailRibbon.new()
	_trail_ribbon.ribbon_width = 3.0
	# Perf: 220 → 80 (匹配 aircraft 默认值)；33Hz 采样 → 16Hz。
	# 战斗中可有 15-20 枚导弹同时在飞，每枚 220 点尾迹每帧重建 → 见 perf_buckets dump
	# trail_draw 占了 3.8ms/帧 (~50% 帧预算)，主要被 missile 拉爆
	_trail_ribbon.max_points = 80
	_trail_ribbon.sample_interval = 0.06
	var trail_color := Color(GameConstants.team_trail_color(team), 0.4)
	_trail_ribbon.ribbon_color = trail_color
	_deadair_base_trail_color = trail_color
	add_child(_trail_ribbon)
	var parent_manager := get_parent()
	if parent_manager != null and parent_manager.has_method("register_missile_trail"):
		parent_manager.register_missile_trail(_trail_ribbon)
	_prev_heading = heading
	# 从 params 读取拦截抗性（不同型号可以配置不同的抗 CIWS 能力）
	if params:
		intercept_hp = params.intercept_hp

func _exit_tree() -> void:
	active_missiles.erase(self)

func set_deadair_exposure_ratio(value: float) -> void:
	deadair_exposure_ratio = clampf(value, 0.0, 1.0)
	if _trail_ribbon:
		var jam_color := Color(0.62, 1.0, 0.25, _deadair_base_trail_color.a)
		_trail_ribbon.ribbon_color = _deadair_base_trail_color.lerp(jam_color, deadair_exposure_ratio)

func jam_by_deadair() -> void:
	set_deadair_exposure_ratio(1.0)
	is_flare_jammed = true
	has_guidance = false
	EventLogger.log_event("DEADAIR", _unit_name(source), "guided missile accumulated JAM and lost guidance")

func disrupt_by_climb_break() -> void:
	if climb_break_disrupted:
		return
	climb_break_disrupted = true
	is_flare_jammed = true # 复用“失导弹无害”命中/CIWS/补射契约，但不消耗热诱弹
	has_guidance = false
	_guidance_ever_lost = true
	sig_retarget_armed = false
	enemy_flare_break_pending = false


## 敌机投焰只开始一次 break 观察窗；pending 期间导弹仍有制导、警告与碰撞资格。
func begin_enemy_flare_break(ac: Aircraft, roll_passed: bool, chance: float) -> bool:
	if ac == null or not is_instance_valid(ac) or not is_active or is_flare_jammed \
			or target != ac:
		return false
	enemy_flare_break_pending = true
	_enemy_flare_break_target_id = ac.get_instance_id()
	_enemy_flare_break_start_pos = ac.global_position
	_enemy_flare_break_start_heading = ac.heading
	_enemy_flare_break_start_speed = ac.speed
	_enemy_flare_break_start_altitude = ac.altitude
	_enemy_flare_break_elapsed = 0.0
	_enemy_flare_break_roll_passed = roll_passed
	_enemy_flare_break_chance = clampf(chance, 0.0, 1.0)
	return true


## 返回本次相对原航迹已经完成的 break 类型；空串表示轨迹变化尚未达门。
static func enemy_flare_break_action(start_pos: Vector2, start_heading: float,
		start_speed: float, start_altitude: float, ac: Aircraft) -> StringName:
	if ac == null or not is_instance_valid(ac):
		return &""
	var heading_delta: float = absf(wrapf(ac.heading - start_heading, -PI, PI))
	if heading_delta >= ENEMY_FLARE_BREAK_HEADING_RAD:
		return &"turn"
	var start_fwd := Vector2(sin(start_heading), -cos(start_heading))
	var start_perp := Vector2(start_fwd.y, -start_fwd.x)
	var lateral_px: float = absf((ac.global_position - start_pos).dot(start_perp))
	if lateral_px >= ENEMY_FLARE_BREAK_LATERAL_PX:
		return &"lateral"
	var speed_gate: float = maxf(ENEMY_FLARE_BREAK_SPEED_MIN_MS,
		start_speed * ENEMY_FLARE_BREAK_SPEED_RATIO)
	if ac.speed - start_speed >= speed_gate:
		return &"speed"
	if absf(ac.altitude - start_altitude) >= ENEMY_FLARE_BREAK_ALTITUDE_M:
		return &"altitude"
	return &""


## 由真实 Missile 物理 tick 驱动；失败不改变制导，成功才切换 jammed 无害契约。
func update_enemy_flare_break(delta: float) -> void:
	if not enemy_flare_break_pending:
		return
	var target_value: Variant = target
	if typeof(target_value) != TYPE_OBJECT or target_value == null \
			or not is_instance_valid(target_value) or not target_value is Aircraft:
		enemy_flare_break_pending = false
		return
	var ac := target_value as Aircraft
	if ac.get_instance_id() != _enemy_flare_break_target_id or ac.is_destroyed \
			or not is_active or is_flare_jammed:
		enemy_flare_break_pending = false
		return
	_enemy_flare_break_elapsed += delta
	var action: StringName = enemy_flare_break_action(_enemy_flare_break_start_pos,
		_enemy_flare_break_start_heading, _enemy_flare_break_start_speed,
		_enemy_flare_break_start_altitude, ac)
	if action != &"":
		enemy_flare_break_pending = false
		var msl_name: String = params.display_name if params else "MSL"
		if _enemy_flare_break_roll_passed:
			is_flare_jammed = true
			has_guidance = false
			_guidance_ever_lost = true
			ac._trigger_evasion_roll()
			EventLogger.log_event("MISSILE", msl_name,
				"enemy flare break SUCCESS (target=%s action=%s chance=%.0f%%)" % [
					ac._log_name(), action, _enemy_flare_break_chance * 100.0])
		else:
			EventLogger.log_event("MISSILE", msl_name,
				"enemy flare break FAILED skill roll (target=%s action=%s chance=%.0f%%)" % [
					ac._log_name(), action, _enemy_flare_break_chance * 100.0])
		return
	if _enemy_flare_break_elapsed >= ENEMY_FLARE_BREAK_WINDOW_S:
		enemy_flare_break_pending = false
		var timeout_name: String = params.display_name if params else "MSL"
		EventLogger.log_event("MISSILE", timeout_name,
			"enemy flare break FAILED no maneuver (target=%s window=%.2fs)" % [
				ac._log_name(), ENEMY_FLARE_BREAK_WINDOW_S])

func _physics_process(delta: float) -> void:
	if not is_active:
		return

	age += delta
	update_enemy_flare_break(delta)

	# 激光减速倒数：VLS / 渐隐 / 主路径都需要倒计时（否则 VLS 弹被照射后永久减速）
	# 倒数放在所有分支之前，确保 timer 不被旁路
	_laser_slow_timer = maxf(_laser_slow_timer - delta, 0.0)

	# 缓存 MissileManager 引用（用于读取帧级共享快照；CSG/VLS 群弹优化）
	if _mm == null:
		_mm = get_parent()

	# 渐隐 coasting：寿命到期/能量耗尽进入此分支，跳过制导，仅按当前速度滑行 + 淡出
	if _fading_out:
		_fade_timer -= delta
		var ratio: float = clampf(_fade_timer / FADE_OUT_DURATION, 0.0, 1.0)
		modulate.a = ratio  # 影响自身 + 子节点 (TrailRibbon)
		if _fade_timer <= 0.0:
			is_active = false  # 让 MissileManager 下一帧 queue_free
			return
		# 继续滑行（无制导）：靠现有 heading + speed 平移，缓慢减速
		speed = maxf(speed - params.drag_deceleration * delta, 0.0)
		var fwd_f := Vector2(sin(heading), -cos(heading))
		var fade_step := fwd_f * speed * PIXELS_PER_METER * delta
		global_position += fade_step
		distance_traveled_px += fade_step.length()
		queue_redraw()
		return

	# VLS 齐射弹：前两段完全接管物理（第三段 TERMINAL 走标准 PN 路径下沉到 params.nav_constant 决定）
	if params and params.is_vls_salvo and vls_phase < 2:
		# phase 0/1 是确定性弹道（爬升+固定点转向），可降帧 tick
		if SurvivorData.ENABLE_VLS_LOW_RATE_TICK:
			_vls_low_rate_counter += 1
			if _vls_low_rate_counter < VLS_LOW_RATE_DIVISOR:
				return
			# 累积 N 帧 delta 一次性传入，保证位移/速度积分总量不变
			_update_vls_non_terminal(delta * _vls_low_rate_counter)
			_vls_low_rate_counter = 0
		else:
			_update_vls_non_terminal(delta)
		return
	# 进入 TERMINAL（或非 VLS 弹）后立刻恢复 60Hz tick，重置降帧计数
	_vls_low_rate_counter = 0
	# 每枚导弹按自身目标做 O(1) 复核；不由 Aircraft 扫描 MissileManager。
	var climb_target_value: Variant = target
	if not climb_break_disrupted and typeof(climb_target_value) == TYPE_OBJECT \
			and climb_target_value != null and is_instance_valid(climb_target_value) \
			and climb_target_value is Aircraft:
		(climb_target_value as Aircraft).try_climb_counter_missile(self)

	# 0) 遮蔽物穿越：普通云只在 HIGH、沙尘暴只在 LOW；追踪能力永久衰减（不回复）。
	# get_in_cloud 走 MissileManager 的 256px×高度档网格快照（同帧同区域只查一次）
	if _cloud_guidance_loss < 1.0 - CLOUD_LOSS_FLOOR:
		if _mm and _mm.has_method("get_in_cloud"):
			if _mm.get_in_cloud(global_position, altitude):
				_cloud_guidance_loss = minf(_cloud_guidance_loss + CLOUD_LOSS_PER_SECOND * delta, 1.0 - CLOUD_LOSS_FLOOR)

	# 0.5) 激光减速倍率（_laser_slow_timer 已在函数顶部倒数，这里仅取当前帧的 mult）
	var _laser_speed_mult: float = SkillHooks.LASER_MISSILE_SPEED_MULT if _laser_slow_timer > 0.0 else 1.0
	var _laser_g_mult: float = SkillHooks.LASER_MISSILE_G_MULT if _laser_slow_timer > 0.0 else 1.0
	if _laser_slow_timer > 0.0:
		speed = maxf(speed - params.max_speed * SkillHooks.LASER_MISSILE_SPEED_DRAIN_PER_S * delta, 0.0)
		if speed <= params.max_speed * SkillHooks.LASER_MISSILE_DESTROY_RATIO:
			_start_fade_out("激光失能")
			return

	# 1) 存活时间检查 → 进入渐隐 coasting，而不是瞬间消失
	if age > params.max_lifetime:
		_start_fade_out("寿命耗尽")
		return

	# 2) 动力阶段
	if age < params.motor_burn_time:
		speed = minf(speed + params.motor_acceleration * delta, params.max_speed * _laser_speed_mult)
	elif second_stage:
		# 二段推进（720 批）：一段燃尽后温和续推——越飞越快（cap ×1.2），远射反而更凶
		speed = minf(speed + params.motor_acceleration * 0.4 * delta,
			params.max_speed * 1.2 * _laser_speed_mult)
	else:
		speed = maxf(speed - params.drag_deceleration * delta, 0.0)
	# 激光减速生效时强制 cap（即使在制动段也限上限，防止突然脱离激光后速度暴涨）
	if _laser_slow_timer > 0.0:
		speed = minf(speed, params.max_speed * _laser_speed_mult)

	# 3) 能量耗尽（发动机燃烧阶段跳过，允许地面发射的低初速导弹加速）→ 渐隐
	if speed < 80.0 and age >= params.motor_burn_time:
		_start_fade_out("能量耗尽")
		return

	# ── 解析目标状态（优先从 MissileManager 帧快照读，未命中走直接属性）──
	# 同源同目标的多枚导弹（VLS 齐射 / 玩家多弹齐射）共用同一份快照，避免每枚重复查询
	var t_valid: bool = is_instance_valid(target) and target != null
	var t_pos: Vector2 = global_position
	var t_heading: float = 0.0
	var t_speed: float = 0.0
	var t_alt: float = altitude
	var t_destroyed: bool = true
	var t_is_aircraft: bool = false
	var t_is_cloaked: bool = false
	var t_sensor_contact_hidden: bool = false
	var t_flat_altitude: bool = false
	var t_alt_tier: int = 0
	if t_valid:
		var snap: Dictionary = _mm.get_target_snap(target) if (_mm and _mm.has_method("get_target_snap")) else {}
		if snap.is_empty():
			t_pos = target.global_position
			t_heading = target.heading
			t_speed = target.speed
			t_alt = target.altitude
			t_destroyed = target.is_destroyed
			t_is_aircraft = target is Aircraft
			t_is_cloaked = t_is_aircraft and (target as Aircraft).is_cloaked
			t_sensor_contact_hidden = t_is_aircraft \
				and (target as Aircraft).is_hidden_from_player_sensors()
			t_flat_altitude = target.flat_altitude
			t_alt_tier = target.get_altitude_tier()
		else:
			t_pos = snap["pos"]
			t_heading = snap["heading"]
			t_speed = snap["speed"]
			t_alt = snap["alt"]
			t_destroyed = snap["is_destroyed"]
			t_is_aircraft = snap["is_aircraft"]
			t_is_cloaked = snap["is_cloaked"]
			t_sensor_contact_hidden = snap.get("sensor_contact_hidden", false)
			t_flat_altitude = snap["flat_altitude"]
			t_alt_tier = snap["alt_tier"]

	# 4) 制导模式判定
	if climb_break_disrupted:
		has_guidance = false
	elif params.fire_and_forget:
		# 发射后不管（AGM 等）：不需要持续照射，不受热诱弹干扰
		if not t_valid or t_destroyed:
			has_guidance = false
		elif target_breaks_guidance(t_is_cloaked, t_sensor_contact_hidden):
			has_guidance = false  # 光学隐形：导弹丢失制导
		else:
			has_guidance = true
	else:
		# SARH 照射检查 + 热诱弹干扰
		if is_flare_jammed:
			has_guidance = false
			# 722 sig_x21·超越地平：被偏转后直飞 2s → 导引头 FOV 内重索敌（每弹一次）
			if sig_retarget_armed and not climb_break_disrupted:
				_sig_retarget_timer += get_physics_process_delta_time()
				if _sig_retarget_timer >= 2.0:
					sig_retarget_armed = false
					var new_tgt: CombatUnit = _sig_find_retarget()
					if new_tgt != null:
						target = new_tgt
						is_flare_jammed = false
						has_guidance = true
						set_deadair_exposure_ratio(0.0)
						EventLogger.log_event("MISSILE", _unit_name(new_tgt),
							"超越地平：被偏转导弹重索敌 → %s" % _unit_name(new_tgt))
		elif not t_valid or t_destroyed:
			has_guidance = false
		elif target_breaks_guidance(t_is_cloaked, t_sensor_contact_hidden):
			has_guidance = false  # 光学隐形：SARH 导弹丢失
		elif source == null or not is_instance_valid(source) or source.is_destroyed:
			has_guidance = false
		else:
			var lock_progress: float = -1.0
			if _mm and _mm.has_method("get_lock_progress"):
				lock_progress = _mm.get_lock_progress(source, target)
			if lock_progress < 0.0:
				lock_progress = source.radar_targets.get(target, 0.0)
			var lock_time_val: float = 3.0
			if source is Aircraft and source.params:
				lock_time_val = source.params.lock_time
			elif source is GroundUnit and source.params:
				lock_time_val = source.params.lock_time
			has_guidance = lock_progress >= lock_time_val

	# 4b) Seeker FOV：目标脱离导引头视场 → 导弹丢锁
	# 仅在制导阶段（发射后 guidance_delay 之后）生效；丢锁后惯性飞行直到 max_lifetime
	if has_guidance and age > params.guidance_delay and t_valid:
		var los_tgt := t_pos - global_position
		if los_tgt.length() > 1.0:
			var tgt_angle := atan2(los_tgt.x, -los_tgt.y)
			var off := absf(_angle_diff(tgt_angle, heading))
			if off > deg_to_rad(params.seeker_fov * 0.5):
				has_guidance = false
				_guidance_ever_lost = true  # 标记末段丢锁（脱靶日志据此归类）

	# 5) 制导
	if has_guidance and t_valid and age > params.guidance_delay:
		var los := t_pos - global_position
		var dist_px := los.length()
		var dist_m := dist_px / PIXELS_PER_METER

		# 发射后不管 + 目标静止/慢速 → 纯追踪（最精确）
		var target_is_slow := t_speed < 10.0
		if params.fire_and_forget and target_is_slow:
			# 对静止目标直接纯追踪，不用 PN（避免数值误差）
			var pure_heading := atan2(los.x, -los.y)
			var diff := _angle_diff(pure_heading, heading)
			var max_turn := params.max_g * _second_stage_g_mult() * _laser_g_mult * awacs_g_mult * GRAVITY / maxf(speed, 50.0) * delta
			heading += clampf(diff, -max_turn, max_turn)
		else:
			# 低空目标：地面杂波干扰导引头，降低追踪过载
			var effective_max_g := params.max_g * _second_stage_g_mult() * _guidance_degradation_for(t_flat_altitude, t_alt_tier) * _laser_g_mult * awacs_g_mult

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
				var tgt_vel := Vector2(sin(t_heading), -cos(t_heading)) * t_speed * PIXELS_PER_METER
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
	if has_guidance and t_valid:
		altitude += (t_alt - altitude) * 3.0 * delta

	# 7) 位移
	var vel_dir := Vector2(sin(heading), -cos(heading))
	var flight_step := vel_dir * speed * PIXELS_PER_METER * delta
	global_position += flight_step
	distance_traveled_px += flight_step.length()
	rotation = heading

	# 8) 模拟 bank（航向变化率 → 侧倾感）
	var hdg_diff := _angle_diff(heading, _prev_heading)
	var turn_rate_now := hdg_diff / maxf(delta, 0.001)
	bank_angle = clampf(turn_rate_now * 0.5, -1.0, 1.0)  # 轻微扭转
	_prev_heading = heading

	queue_redraw()


## 记录穿透弹已经伤害过的目标；连锁弹头优先转向时也必须记住，防止之后穿回同一目标。
func remember_penetration_hit(hit_unit: CombatUnit) -> void:
	if hit_unit != null and is_instance_valid(hit_unit):
		var uid := hit_unit.get_instance_id()
		if not _penetrated_unit_ids.has(uid):
			_penetrated_unit_ids[uid] = true
			penetration_hit_count += 1


## 连锁弹头命中后的原子状态切换：记住目标、解除制导，保留当前航向与速度继续飞行。
func continue_after_penetration(hit_unit: CombatUnit) -> void:
	remember_penetration_hit(hit_unit)
	target = null
	has_guidance = false


## 命中检测侧调用：防止导弹在大型目标或低帧率重叠区内逐帧重复伤害同一单位。
func already_penetrated(unit: CombatUnit) -> bool:
	return unit != null and _penetrated_unit_ids.has(unit.get_instance_id())


## 反导伤害的唯一生命值入口；返回 true 表示本次把导弹击毁。
## CIWS 使用渐隐，持续激光使用立即回收，视觉爆点仍由命中武器在返回 true 后各自播放。
func take_intercept_damage(amount: float, fade_out_on_destroy: bool) -> bool:
	if not is_active or amount <= 0.0:
		return false
	intercept_hp -= amount
	if intercept_hp > 0.0:
		return false
	return destroy_from_intercept(fade_out_on_destroy)


## 电磁炮等一击反导入口；集中维护 active / guidance / 回收状态。
func destroy_from_intercept(fade_out_on_destroy: bool) -> bool:
	if not is_active or _fading_out:
		return false
	if fade_out_on_destroy:
		_start_fade_out("被近防拦截")
	else:
		is_active = false
		has_guidance = false
		queue_free()
	return true

## 光学隐形与玩家侧传感器失联都让现有导引解算立即失效；弹体仍按惯性继续飞行。
static func target_breaks_guidance(is_cloaked: bool,
		sensor_contact_hidden: bool) -> bool:
	return is_cloaked or sensor_contact_hidden

## 722 sig_x21·超越地平：重索敌——导引头 FOV 内、4000px 内最近的敌方单位（TEAM_HOSTILE）
func _sig_find_retarget() -> CombatUnit:
	var fov_rad: float = deg_to_rad(params.seeker_fov if params else 30.0)
	var fwd := Vector2(sin(heading), -cos(heading))
	var best: CombatUnit = null
	var best_d: float = INF
	for u in CombatUnit.all_units:
		if u == null or not is_instance_valid(u) or u.is_destroyed:
			continue
		if u.team != CombatUnit.TEAM_HOSTILE or u.is_lock_immune():
			continue
		if source != null and is_instance_valid(source) \
				and source.is_sensor_engagement_obscured(u):
			continue
		var to_u: Vector2 = u.global_position - global_position
		var d: float = to_u.length()
		if d < 1.0 or d > 4000.0:
			continue
		if absf(fwd.angle_to(to_u)) > fov_rad:
			continue
		if d < best_d:
			best_d = d
			best = u
	return best


## 进入渐隐滑行状态：寿命到期 / 能量耗尽时调用，替代瞬间 is_active=false。
## 命中爆炸路径不走这里（MissileManager 直接 queue_free，由 ExplosionVFX 替代视觉）
func _start_fade_out(reason: String = "") -> void:
	if _fading_out:
		return
	_fading_out = true
	_fade_timer = FADE_OUT_DURATION
	# 普通弹 fade 必是未命中；穿透弹至少命中过一次后自然耗尽，不应再记脱靶。
	if penetration_hit_count <= 0:
		_log_miss(reason)
	has_guidance = false  # 渐隐期间不再做任何制导

## 记录一次"导弹未命中即消失"，并归类原因（让"射空"在日志里可见——
## 否则一枚丢锁的弹是静默消失的，正是 team_inbound 幽灵封锁那类 bug 难发现的根源）。
func _log_miss(reason: String) -> void:
	var msl_name: String = params.display_name if params else "MSL"
	var src_name: String = _unit_name(source)
	var cause: String = reason
	var tgt_name: String = "?"
	if not is_instance_valid(target) or target == null:
		cause = "目标已消失"
	elif target.is_destroyed:
		tgt_name = _unit_name(target)
		cause = "目标已被摧毁(火力浪费)"
	else:
		tgt_name = _unit_name(target)
		if is_flare_jammed:
			cause = "热诱弹干扰" + ("/" + reason if reason != "" else "")
		elif _guidance_ever_lost:
			cause = "末段丢锁(出导引头FOV)" + ("/" + reason if reason != "" else "")
	EventLogger.log_event("MISSILE", src_name if src_name != "" else msl_name,
			"%s 脱靶 → %s (%s)" % [msl_name, tgt_name, cause])
	if src_name != "":
		EventLogger.tally(src_name, "msl_miss")

## 把单位格式化成 "Friend/F-14[Solar]" 风格名（与 GUN/MISSILE hit 日志一致）
func _unit_name(unit) -> String:
	if not is_instance_valid(unit) or unit == null:
		return ""
	if unit is Aircraft and unit.params:
		var side := "Friend" if unit.team == 0 else "Enemy"
		return "%s/%s[%s]" % [side, unit.params.display_name, unit.callsign]
	if "callsign" in unit and unit.callsign != "":
		return String(unit.callsign)
	return String(unit.name)

## ════════════════════════════════════════════════════════════
##  VLS 三段式弹道（阶段 1 VERTICAL + 阶段 2 TRANSITION）
## ════════════════════════════════════════════════════════════
## 阶段 1（VERTICAL）：维持初始朝向（发射时统一朝世界北），50% 速度爬升；画面上一串"火柱冲天"
## 阶段 2（TRANSITION）：朝 vls_locked_point 转向（弹道弯曲），速度爬升到满；不追踪移动的玩家
## 阶段 3（TERMINAL）：回到 _physics_process 主流程走标准 PN（nav_constant 低 → 末端精度差）
## 每发齐射弹的 speed_multiplier 在 NavalWeapons._fire_one_vls_missile 随机设定，打散弹道观感
func _update_vls_non_terminal(delta: float) -> void:
	_vls_phase_timer += delta

	# 激光减速倍率（laser timer 已在 _physics_process 顶部倒数）
	var _laser_speed_mult_vls: float = SkillHooks.LASER_MISSILE_SPEED_MULT if _laser_slow_timer > 0.0 else 1.0
	var _laser_g_mult_vls: float = SkillHooks.LASER_MISSILE_G_MULT if _laser_slow_timer > 0.0 else 1.0
	if _laser_slow_timer > 0.0:
		speed = maxf(speed - params.max_speed * SkillHooks.LASER_MISSILE_SPEED_DRAIN_PER_S * delta, 0.0)
		if speed <= params.max_speed * SkillHooks.LASER_MISSILE_DESTROY_RATIO:
			_start_fade_out("激光失能")
			return

	match vls_phase:
		0:  # VERTICAL 爬升段：维持初始 heading，速度爬到 max_speed 的 50%
			speed = minf(speed + params.motor_acceleration * delta, params.max_speed * 0.5 * _laser_speed_mult_vls)
			if _vls_phase_timer >= params.vls_climb_time:
				vls_phase = 1
				_vls_phase_timer = 0.0
		1:  # TRANSITION 过渡段：朝锁定点转向，速度爬满
			if vls_locked_point != Vector2.INF:
				var to_pt: Vector2 = vls_locked_point - global_position
				if to_pt.length() > 1.0:
					var target_hdg: float = atan2(to_pt.x, -to_pt.y)
					var diff: float = atan2(sin(target_hdg - heading), cos(target_hdg - heading))
					var max_turn: float = deg_to_rad(params.vls_transition_turn_rate_degs) * _laser_g_mult_vls * delta
					heading += clampf(diff, -max_turn, max_turn)
			speed = minf(speed + params.motor_acceleration * delta, params.max_speed * _laser_speed_mult_vls)
			if _vls_phase_timer >= params.vls_transition_time:
				vls_phase = 2
				_vls_phase_timer = 0.0
				# 切末端前：重置 PN 的 LOS 角以避免第一帧爆转
				if target and is_instance_valid(target):
					var los: Vector2 = target.global_position - global_position
					if los.length() > 1.0:
						_prev_los_angle = atan2(los.x, -los.y)

	# 位移（两段共用）—— 乘 speed_multiplier 让齐射弹各自快慢不同
	var fwd := Vector2(sin(heading), -cos(heading))
	var actual_speed: float = speed * speed_multiplier
	var vls_step := fwd * actual_speed * PIXELS_PER_METER * delta
	global_position += vls_step
	distance_traveled_px += vls_step.length()

	# 视觉尾迹更新（模拟轻微"侧滚"）
	var hdg_diff: float = _angle_diff(heading, _prev_heading)
	var turn_rate_now: float = hdg_diff / maxf(delta, 0.001)
	bank_angle = clampf(turn_rate_now * 0.5, -1.0, 1.0)
	_prev_heading = heading

	queue_redraw()

func _draw() -> void:
	var perf_detail := PerfBuckets.detail_capture_enabled()
	var perf_t0 := Time.get_ticks_usec() if perf_detail else 0
	_draw_impl()
	if perf_detail:
		PerfBuckets.tick("missile_draw", Time.get_ticks_usec() - perf_t0)


func _draw_impl() -> void:
	if not is_active:
		return
	_draw_body()
	var player: Aircraft = AircraftRenderer.safe_player_ref()
	var player_owned := player != null and is_instance_valid(source) and source == player
	var incoming := is_incoming_warning_for(player)
	var full_body_detail := body_detail_visible_at_scale(
		AircraftRenderer.label_lod_scale(self), player_owned, incoming,
		Input.is_key_pressed(KEY_ALT))
	if full_body_detail:
		_draw_body_fins()
	if full_body_detail and age < params.motor_burn_time:
		_draw_motor_flame()
	if _should_draw_data_label():
		PerfBuckets.count("missile_labels_drawn")
		_draw_data_label()
	_draw_incoming_warning()


static func data_label_visible_at_scale(view_scale: float, player_owned: bool,
		force_full: bool = false) -> bool:
	return force_full or view_scale >= DATA_LABEL_MIN_VIEW_SCALE \
		or player_owned


static func body_detail_visible_at_scale(view_scale: float, player_owned: bool,
		incoming_warning: bool, force_full: bool = false) -> bool:
	return force_full or view_scale >= BODY_DETAIL_MIN_VIEW_SCALE \
		or player_owned or incoming_warning


func _should_draw_data_label() -> bool:
	var player: Aircraft = AircraftRenderer.safe_player_ref()
	var player_owned := player != null and is_instance_valid(source) and source == player
	return data_label_visible_at_scale(AircraftRenderer.label_lod_scale(self),
		player_owned, Input.is_key_pressed(KEY_ALT))


## 真实在途导弹警告：一弹一线一三角，不聚合、不去重。
func _draw_incoming_warning() -> void:
	var player: Aircraft = AircraftRenderer.safe_player_ref()
	if not is_incoming_warning_for(player):
		return
	PerfBuckets.count("missile_warnings_drawn")

	var flash: bool = age < LockWarning.FLASH_DURATION
	var blink_hz: float = LockWarning.FLASH_BLINK_HZ if flash else LockWarning.PRE_LAUNCH_BLINK_HZ
	var blink_amp: float = 0.45 if flash else 0.35
	var blink_base: float = 0.55 if flash else 0.65
	var blink: float = blink_base + blink_amp * sin(
		Time.get_ticks_msec() * 0.001 * TAU * blink_hz)
	var line_color := Color(LockWarning.COLOR_RGB, 0.55 * blink)
	var inv_zoom: float = AircraftRenderer.screen_space_inverse_scale(self)
	var line_width: float = (LockWarning.FLASH_LINE_WIDTH if flash \
		else LockWarning.PRE_LAUNCH_LINE_WIDTH) * inv_zoom
	var local_player: Vector2 = to_local(player.global_position)
	# 线长保留世界空间，只把线宽和玩家端点符号补偿为固定屏幕尺寸。
	draw_line(Vector2.ZERO, local_player, line_color, line_width, true)
	var marker_radius: float = (LockWarning.FLASH_MARKER_RADIUS if flash \
		else LockWarning.PRE_LAUNCH_MARKER_RADIUS) * inv_zoom
	draw_multiline(PackedVector2Array([
		local_player + Vector2(-marker_radius, 0),
		local_player + Vector2(marker_radius, 0),
		local_player + Vector2(0, -marker_radius),
		local_player + Vector2(0, marker_radius),
	]), line_color, line_width)
	draw_arc(local_player, marker_radius, 0.0, TAU, 20,
		Color(line_color, 0.7 * blink), 1.2 * inv_zoom, true)

	# 三角锚定玩家，但朝向真实导弹世界方向。每枚导弹独立提交一枚。
	var toward_missile: Vector2 = global_position - player.global_position
	if toward_missile.length_squared() <= 1.0:
		return
	var direction := toward_missile.normalized()
	var perp := Vector2(-direction.y, direction.x)
	var arrow_blink: float = absf(sin(Time.get_ticks_msec() * 0.008))
	var arrow_color := Color(1.0, 0.25, 0.2, lerpf(0.6, 1.0, arrow_blink))
	var radius := LockWarning.DIRECTION_ARROW_RADIUS
	var size := LockWarning.DIRECTION_ARROW_SIZE
	draw_set_transform(local_player, -rotation, Vector2.ONE * inv_zoom)
	var tip := direction * (radius + size)
	var base_a := direction * radius + perp * size * 0.7
	var base_b := direction * radius - perp * size * 0.7
	draw_colored_polygon(PackedVector2Array([tip, base_a, base_b]), arrow_color)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func _draw_body() -> void:
	# 细长"子弹+尾翼"造型，heading=0 朝上，与飞机圆点图标明显区分
	var color := GameConstants.missile_body_color(team)
	var length := 10.0   ## 弹身总长
	var nose := 3.0      ## 头锥长度
	var w := 1.2         ## 弹身半宽
	var half_len := length * 0.5

	# 弹身：尖头五边形（尖锥 + 矩形身）
	var body := PackedVector2Array([
		Vector2(0, -half_len),               # 尖头
		Vector2(w, -half_len + nose),        # 头锥右肩
		Vector2(w, half_len),                # 右后
		Vector2(-w, half_len),               # 左后
		Vector2(-w, -half_len + nose),       # 头锥左肩
	])
	draw_colored_polygon(body, color)



func _draw_body_fins() -> void:
	var color := GameConstants.missile_body_color(team)
	var length := 10.0
	var nose := 3.0
	var half_len := length * 0.5
	# 前翼（中段十字）
	var mid_fin := 2.0
	var mid_y := -half_len + nose + 1.5
	# 尾翼（后段十字，稍宽）
	var tail_fin := 2.6
	var tail_y := half_len - 0.8
	# 两段合为一次 Canvas 提交；统一 1.3px 是原 1.2/1.4 的视觉中值。
	draw_multiline(PackedVector2Array([
		Vector2(-mid_fin, mid_y), Vector2(mid_fin, mid_y),
		Vector2(-tail_fin, tail_y), Vector2(tail_fin, tail_y),
	]), color, 1.3)

func _draw_motor_flame() -> void:
	var flicker := lerpf(0.6, 1.0, AircraftRenderer.visual_noise01(self, 41))
	var glow := Color(1.0, 0.5, 0.1, 0.7 * flicker)
	var tail := Vector2(0, 5.0)
	var flame_len := lerpf(6.0, 10.0, AircraftRenderer.visual_noise01(self, 47))
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

	# 到目标的距离
	var dist_to_tgt_m := 0.0
	if target and is_instance_valid(target) and not target.is_destroyed:
		dist_to_tgt_m = global_position.distance_to(target.global_position) / 0.5  # PIXELS_PER_METER

	var lines := PackedStringArray([
		AircraftRenderer.english_status_identity(display_name, "MISSILE"),
		AircraftRenderer.status_speed_knots_text(speed),
		AircraftRenderer.status_range_text(dist_to_tgt_m, dist_to_tgt_m > 0.0),
		"GUIDED" if has_guidance else "UNGUIDED",
	])
	var xform := get_global_transform_with_canvas()
	var view_scale := xform.basis_xform(Vector2.RIGHT).length()
	var screen_offset := AircraftRenderer.unit_status_screen_offset_for(
		10.0, view_scale, xform.origin)
	AircraftRenderer.draw_unit_status_panel(self, _font, lines, team,
		screen_offset, {}, false, GameConstants.missile_label_colors(team))

## 低空目标导引头性能衰减（地面杂波干扰 + 云层穿越累计损耗）
## 低空衰减仅在扁平高度模式（生存模式）下生效
## 优先用 _guidance_degradation_for() — 由 _physics_process 传入已解析的 (flat, tier) 避免重复属性查
func _guidance_degradation() -> float:
	var t_flat: bool = false
	var t_tier: int = 0
	if is_instance_valid(target):
		t_flat = target.flat_altitude
		t_tier = target.get_altitude_tier()
	return _guidance_degradation_for(t_flat, t_tier)

func _guidance_degradation_for(t_flat: bool, t_tier: int) -> float:
	var base := 1.0
	if t_flat:
		match t_tier:
			CombatUnit.AltitudeTier.GROUND:
				base = 0.5  # 地面目标：严重杂波
			CombatUnit.AltitudeTier.LOW:
				base = 0.7  # 低空目标：中等杂波
	# 云层穿越衰减：每次穿过都累加，不回复
	return base * (1.0 - _cloud_guidance_loss)

## 角度差（-PI 到 PI）
static func _angle_diff(a: float, b: float) -> float:
	var d := fmod(a - b + PI, TAU)
	if d < 0:
		d += TAU
	return d - PI
