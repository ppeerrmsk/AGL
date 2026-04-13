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
var _overshoot_timer: float = 0.0   ## 近距过顶 extension 计时（秒），>0 时强制沿机头直飞脱离
var ai_override_pursuit: bool = false  ## AI 战术机动时跳过自动追踪，由 AI 直接控制 target_position
var bullet_manager: Node2D = null   ## 由 main.gd 注入
var missile_manager: Node2D = null  ## 由 main.gd 注入

# --- 火箭弹（无制导副武器） ---
var rockets_remaining: int = 0
var _rocket_burst_cooldown: float = 0.0  ## 齐射冷却
var _rocket_queue: Array[Dictionary] = []  ## 待发射火箭队列 { delay: float, heading: float, pos: Vector2 }

# --- 导弹 ---
enum WeaponMode { MISSILE, GUN }
var weapon_mode: int = WeaponMode.GUN
var missiles_remaining: int = 0
var secondary_missiles_remaining: int = 0  ## 副导弹（空对地等）剩余数
var _missile_cooldown: float = 0.0
var _crank_timer: float = 0.0          ## 发射后保持照射计时（秒），> 0 时飞机维持稳定航向
const CRANK_DURATION: float = 8.0      ## 发射后保持照射的时长
const LOCK_STABLE_BUFFER: float = 1.0  ## 锁定后额外稳定时间才允许发射（AI）

# --- 近距过顶（extension）---
## 高速机追慢速机时常会完全重叠：此时追击前置点和机炮前置点都会退化为零向量，
## 导致航向噪声 + 机炮在重叠状态下乱射刷伤害（子弹出膛瞬间进 HIT_RADIUS）。
## 距离低于阈值时强制沿机头直飞一段时间，脱离后由正常追击逻辑自然掉头回来。
const OVERSHOOT_DIST_PX: float = 80.0           ## 像素 触发过顶 extension 的距离（≈160m）
const OVERSHOOT_EXTEND_TIME: float = 1.2        ## 秒  extension 持续时间
const OVERSHOOT_EXTEND_DIST_PX: float = 2000.0  ## 像素 extension 直飞目标点投射距离
const MIN_GUN_FIRE_DIST_PX: float = 60.0        ## 像素 低于此距离强制不开火（≈120m）

# 诊断：玩家有目标但无法开火时节流日志
var _msl_block_log_timer: float = 0.0
var _msl_last_block_reason: String = ""
const MSL_BLOCK_LOG_INTERVAL: float = 2.0  ## 最多每 2 秒记录一次阻塞原因

# --- 导弹装填（生存模式）---
var enable_missile_reload: bool = false     ## 生存模式启用自动装填
var _missile_reload_active: bool = false
var _missile_reload_timer: float = 0.0
var missile_reload_duration: float = 20.0   ## 装填总时间（可通过升级缩短）
var missile_reload_progress: float = 0.0    ## 0.0-1.0, HUD 读取用

# --- 机炮攻击提交（生存模式导弹优先）---
## 进入机炮模式向目标发起攻击时锁定为 true，完成这次攻击（飞过目标）前不切回导弹模式
## 防止导弹装填好的瞬间中途切换，造成攻击跑断
var _gun_pass_committed: bool = false

# --- 多目标锁定（生存模式升级）---
var max_simultaneous_locks: int = 1

## 战术偏好模式下是否自动发射导弹（玩家可在战术面板切换）
## ON（默认）：齐射路径自动挑锁定目标开火，玩家无需点击
## OFF：只对玩家手动指定的 combat_target 发射
var missile_auto_fire: bool = true

# --- 击毁 ---
var _destroy_timer: float = 0.0
var _destroy_spin: float = 0.0      ## 坠落旋转速度

# --- 雷达 ---

# --- 热诱弹 ---
var flares_remaining: int = 0
var _flare_cooldown: float = 0.0
var _flare_particles: Array[Dictionary] = []  ## { pos: Vector2, vel: Vector2, life: float, bright: bool }
var _flare_spawn_queue: Array[Dictionary] = []  ## 待释放粒子队列 { delay: float, heading: float, pos: Vector2 }
var _flare_ignored_missiles: Dictionary = {}  ## 失误判定已拒绝的导弹 { instance_id: true }
var _flare_ignored_cleanup: float = 0.0       ## 清理计时器
var flares_guaranteed: bool = false  ## 生存模式：玩家热诱弹 100% 干扰
var enable_flare_reload: bool = false  ## 生存模式：热诱弹用完后自动装填
var flare_reload_progress: float = 0.0  ## 0.0-1.0, HUD 读取用
## 热诱弹释放后的导弹穿透窗口（秒）。>0 时所有导弹的近炸引信判定跳过此单位，
## 用于解决"已被干扰的导弹靠惯性直飞穿过慢速玩家"的问题。
## 只对 flares_guaranteed 的玩家生效（在 _release_flares 中启动）
const MISSILE_PHASE_DURATION: float = 1.0
var missile_phase_timer: float = 0.0
var enable_gun_reload: bool = false      ## 生存模式：机炮弹药耗尽后整匣装填
var _gun_reload_active: bool = false
var _gun_reload_timer: float = 0.0
var gun_reload_duration: float = 25.0    ## 装填总时间（比导弹略久；可通过升级缩短）
var gun_reload_progress: float = 0.0     ## 0.0-1.0, HUD 读取用
var infinite_fuel: bool = false      ## 生存模式：无限燃油
var bullet_dodge_chance: float = 0.0  ## 机炮弹丸闪避概率（装甲强化升级）
var flare_lock_immunity: float = 0.0  ## 释放热诱弹后的锁定免疫时间（秒）
var _lock_immunity_timer: float = 0.0  ## 当前剩余锁定免疫时间
var kill_heal_amount: float = 0.0     ## 击杀敌机时回复的HP
var gun_extra_barrels: int = 0        ## 额外机炮管数（多管齐射进化）
var missile_bounce_count: int = 0     ## 导弹弹跳次数（连锁弹头进化）
var missile_proximity_aoe: bool = false  ## 近炸引信进化：导弹爆炸产生 AOE
var gun_ciws_active: bool = false        ## 近防炮进化：自动拦截正面来袭导弹
var _ciws_cooldown: float = 0.0          ## CIWS 射速冷却（独立于正常机炮）
var no_stamina: bool = false         ## 跳过耐力系统（UAV 等）
var survivor_missile_damage_cap: float = 0.0  ## 生存模式：导弹伤害上限（0=不限制）
var survivor_bullet_damage_cap: float = 0.0   ## 生存模式：机炮伤害上限（0=不限制）
var hide_data_label: bool = false    ## 隐藏飞机旁的数据标签（HUD 替代显示）

# --- 战术偏好（生存模式玩家手动控制）---
enum WeaponPreference { PREFER_MISSILE, PREFER_GUN }
enum AltitudePreference { PREFER_CLIMB, PREFER_LOW }

var use_tactical_preference: bool = false       ## 启用战术偏好系统（仅玩家飞机）
## 战术激进度 [0..1]：
##   - 1.0 = 完全激进（解除 G 限制，维持角点速度，最小转弯半径）
##   - 0.0 = 保守（沿用原 70% 持续 G 限制与 turn_slow_speed 能量策略）
##   - 默认 1.0，保证没有 AI 的玩家飞机（survivor 模式）开箱即用最激进
##   - AI 控制器每帧根据 effective_skill × aggression 写入此值，使沙盒 AI 随飞行员属性调整
var tactical_aggression: float = 1.0
var weapon_preference: int = WeaponPreference.PREFER_MISSILE
var altitude_preference: int = AltitudePreference.PREFER_CLIMB
var evasion_mode: bool = false
var _evasion_override: bool = false             ## 玩家手动点击临时覆盖规避
var _evasion_sway_timer: float = 0.0            ## S型机动计时器
var _evade_roll_phase: float = 0.0              ## 规避原地滚转相位（弧度，绘制时叠加到 bank）
var _evade_roll_remaining: float = 0.0          ## 当前滚转动画剩余秒数
var _evade_roll_cooldown: float = 0.0           ## 下次触发滚转的冷却秒数
var _evade_last_missile_id: int = 0             ## 上次触发滚转的来袭导弹实例 id（避免同一导弹重复触发）
const _EVADE_ROLL_DURATION: float = 1.4         ## 单次滚转动画时长（秒，约 1 圈）
const _EVADE_ROLL_COOLDOWN: float = 1.2         ## 两次滚转之间的冷却
const _EVADE_ROLL_TRIGGER_PX: float = 700.0     ## 来袭导弹接近到此距离才触发滚转

# --- LOD ---
var lod_level: int = 0  ## 0=完整, 1=简化（编队僚机巡航）, 2=最小化（屏幕外）
var _lod_frame: int = 0  ## LOD 帧计数器

# --- 编队调试（survivor_mode F11 切换）---
## 打开后会缓存 LOD 1 编队分支的中间状态并在 _draw 中渲染调试覆盖层。
## 仅用于排查"机头乱扭"类问题，正常游戏请保持 false。
var formation_debug: bool = false
var _dbg_branch: String = ""        ## CLOSE / MID / FAR / OFF
var _dbg_slot_pos: Vector2 = Vector2.INF
var _dbg_slot_dist: float = 0.0
var _dbg_slot_heading: float = 0.0  ## 槽位方位角
var _dbg_blended_heading: float = 0.0  ## 中距分支的混合目标航向
var _dbg_target_heading: float = 0.0  ## 实际写入 lerp_angle 的目标航向
var _dbg_hdiff: float = 0.0
var _dbg_desired_bank: float = 0.0
var _dbg_blend_ratio: float = 0.0
var _dbg_chase_target_kmh: float = 0.0
var _dbg_log_timer: float = 0.0    ## 控制台限频打印计时器

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
		if params.rocket:
			rockets_remaining = params.rocket.max_ammo
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

## 获取挂载的战术机动模块（如有）
func get_maneuver() -> CobraManeuver:
	for child in get_children():
		if child is CobraManeuver:
			return child
	return null

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
			_update_rocket(delta)
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
			#   >REJOIN_DIST   → 纯追击归队（仅 b<0.05 的脱离重融合用）
			#   CLOSE~REJOIN   → 长机航向 + 横向偏置（leader-local frame，避免 bearing flip）
			#   <CLOSE_DIST    → 航向同步长机 + 微量漂移修正
			var ldr: Aircraft = _formation_leader
			var b := _formation_blend  # 0=自主飞行过渡, 1=正常编队

			# 计算离阵型槽位的距离
			var slot_dist := 0.0
			if target_position != Vector2.INF:
				slot_dist = global_position.distance_to(target_position)

			# 槽位在长机本地坐标系下的偏移（相对僚机）
			# slot_local.x > 0 → 槽位在僚机右侧（leader frame），需向右偏置
			# slot_local.y > 0 → 槽位在僚机后方，僚机需减速让槽位追上
			# slot_local.y < 0 → 槽位在僚机前方，僚机需加速追上
			# 关键：用"长机本地坐标"而不是"飞机→槽位的世界方位角"
			# 后者在长机转弯时 slot 绕长机切向移动 → 方位角剧烈摆动 → 旧 MID 分支机头乱扭
			var slot_local := Vector2.ZERO
			if target_position != Vector2.INF:
				slot_local = (target_position - global_position).rotated(-ldr.heading)

			# 微扰动：基于个体相位的缓慢正弦波
			var t := float(_lod_frame) * 0.02
			var jitter_heading := sin(t + _formation_jitter_phase) * 0.008
			var jitter_bank := sin(t * 0.7 + _formation_jitter_phase + 1.0) * 0.015

			const CLOSE_DIST := 50.0    # 以内纯航向同步
			const REJOIN_DIST := 800.0  # 以外纯追击归队
			const LEAD_BIAS_DIST := 250.0  # 横向偏置的虚拟前视距离（越大→偏置越温和）
			const MAX_BIAS := PI / 3.0     # 横向偏置最大角度（60°）

			# 调试：永远缓存槽位/分支等中间状态（开销可忽略，让 F12 快照不依赖 F11）
			_dbg_slot_pos = target_position
			_dbg_slot_dist = slot_dist
			_dbg_blend_ratio = 0.0
			_dbg_blended_heading = 0.0
			_dbg_slot_heading = 0.0

			# ── 先算好目标航向（由分支决定），然后用统一的"物理层 rate-limit"落位 ──
			# 这样无论走哪个分支，bank/heading 都受 roll_rate / max_g / 协同转弯公式约束，
			# 绝对不会发生瞬间 ±60° bank 或 ±180° 航向跳的情况。
			# 对刚出战的僚机尤其关键——之前 combat 离开时 bank 可能还在 ±80°，
			# 如果用 lerp(bank, 0, 4*delta) 会在几帧内抽回到 0，超过结构 G 极限。
			var target_heading: float = heading  # 默认不变
			var max_bank_ratio := 0.75           # 由分支调整

			if slot_dist > REJOIN_DIST:
				# 真正远距离：纯追击归队
				_dbg_branch = "FAR"
				if target_position != Vector2.INF and slot_dist > 10.0:
					var to_slot := (target_position - global_position).normalized()
					target_heading = atan2(to_slot.x, -to_slot.y)
					max_bank_ratio = 0.7
					_dbg_slot_heading = target_heading
			elif slot_dist > CLOSE_DIST:
				# 中距离：长机航向 + 横向偏置（leader-local frame）
				_dbg_branch = "MID"
				var bias_angle := atan2(slot_local.x, LEAD_BIAS_DIST)
				bias_angle = clampf(bias_angle, -MAX_BIAS, MAX_BIAS)
				target_heading = ldr.heading + jitter_heading + bias_angle
				max_bank_ratio = 0.75
				_dbg_slot_heading = bias_angle      # 复用字段：横向偏置角
				_dbg_blend_ratio = bias_angle / MAX_BIAS
				_dbg_blended_heading = target_heading
			else:
				# 近距离：直接跟长机航向
				_dbg_branch = "CLOSE"
				target_heading = ldr.heading + jitter_heading
				max_bank_ratio = 0.6

			_dbg_target_heading = target_heading

			# ── 统一"平滑且有物理限制"的落位 ──
			# 设计权衡：
			#   - 纯物理公式 (g·tan(bank)/TAS) 在编队中过慢：F-14 在 84° bank 也只有 ~21°/s，
			#     180° 归队要 9 秒，期间僚机会漂得很远。
			#   - 纯 lerp 没有上限，combat 刚结束从 ±80° bank 一瞬间归零，非物理突兀。
			# 折中：
			#   - heading 用 lerp 追目标，但角速度被 FORMATION_MAX_TURN_RATE (1.5 rad/s ≈ 86°/s) 硬夹。
			#     即使大 hdiff 也能在 2 秒左右 180° 翻转，够快但不突兀。
			#   - bank 由当前的 hdiff 自然推出（视觉），并按 params.roll_rate 严格限制滚转速率。
			#     保证 bank 过渡"真实飞机能做到"的那种感觉。
			var hdiff := _angle_diff(target_heading, heading)
			var max_bank_val := _max_bank_angle()
			var roll_rate_limit := params.roll_rate if params else 3.0

			const FORMATION_MAX_TURN_RATE := 1.5   # rad/s，编队归队的角速度硬上限
			const FORMATION_LERP_K := 5.0          # hdiff lerp 增益
			var desired_step := hdiff * FORMATION_LERP_K * delta
			var max_step := FORMATION_MAX_TURN_RATE * delta
			if absf(desired_step) > max_step:
				desired_step = signf(desired_step) * max_step
			heading = wrapf(heading + desired_step, -PI, PI)

			# 用更新后的 hdiff 推 desired_bank（和航向变化匹配，视觉一致）
			var hdiff_after := _angle_diff(target_heading, heading)
			var desired_bank := signf(hdiff_after) * max_bank_val * clampf(absf(hdiff_after) * 2.5, 0.0, max_bank_ratio)
			if _dbg_branch == "CLOSE":
				# 近距离让 bank 额外向长机 bank 靠拢，编队视觉更统一
				var ldr_target_bnk := ldr.bank_angle + jitter_bank
				desired_bank = lerpf(desired_bank, ldr_target_bnk, 0.6)
			_dbg_hdiff = hdiff
			_dbg_desired_bank = desired_bank

			# Bank 变化 rate-limit：严格 ≤ roll_rate
			# 这保留了用户要求的"不能超过物理极限"——bank 的变化速率永远 ≤ 飞机结构允许的滚转速率。
			var bank_step := clampf(desired_bank - bank_angle, -roll_rate_limit * delta, roll_rate_limit * delta)
			bank_angle += bank_step

			# 速度：根据 leader-local 纵向偏移调档
			# fwd_offset > 0 → 槽位在僚机前方（leader frame）→ 加速追
			# fwd_offset < 0 → 僚机已经超前于槽位 → 必须能减速（旧版只会加速）
			# 重要：所有目标速度都必须 clamp 到 _max_speed_at_altitude，
			# 否则在"长机阵亡 → 僚机(带 1.15x 超速)晋升为新长机"的循环中
			# 速度会被不断放大，后期出现 Mach 8+ 的暴走（见 2026-04-11 修复）
			var max_ms := _max_speed_at_altitude() / 3.6
			var jitter_speed := sin(t * 0.5 + _formation_jitter_phase + 2.0) * ldr.speed * 0.005
			var fwd_offset := -slot_local.y  # >0 = 槽位在前
			var chase_target: float
			var chase_rate: float
			if slot_dist > REJOIN_DIST:
				# 归队：大幅加速
				chase_target = ldr.speed * 1.4
				chase_rate = 4.0
			elif fwd_offset > 200.0:
				# 槽位远在前方
				chase_target = ldr.speed * 1.15 + jitter_speed
				chase_rate = 4.0
			elif fwd_offset > 50.0:
				# 槽位前方
				chase_target = ldr.speed * 1.05 + jitter_speed
				chase_rate = 3.0
			elif fwd_offset < -50.0:
				# 僚机超前于槽位 → 减速等槽位追上
				chase_target = ldr.speed * 0.92 + jitter_speed
				chase_rate = 3.0
			else:
				# 纵向基本对齐：匹配长机速度
				chase_target = ldr.speed + jitter_speed
				chase_rate = 3.0 + b * 3.0
			chase_target = clampf(chase_target, 0.0, max_ms)
			speed = lerpf(speed, chase_target, chase_rate * delta)
			# 同步 target_speed_kmh，避免 LOD 切换回 0 时残留的过期目标速度
			# 让 _update_speed 能无缝接管，而不是慢慢 decel 追老目标
			target_speed_kmh = speed * 3.6

			_dbg_chase_target_kmh = chase_target * 3.6

			# 调试：每秒一次把核心数值打到 EventLogger（仅在 formation_debug=true 时）
			if formation_debug:
				_dbg_log_timer -= delta
				if _dbg_log_timer <= 0.0:
					_dbg_log_timer = 1.0
					EventLogger.log_event("FORM_DBG", callsign,
						"branch=%s slot_d=%.0f b=%.2f hdg=%d→%d Δ=%+.1f° dbank=%+.0f° bank=%+.0f° spd=%d/%d ldrG=%.1f" % [
							_dbg_branch,
							_dbg_slot_dist,
							b,
							int(rad_to_deg(heading)),
							int(rad_to_deg(_dbg_target_heading)),
							rad_to_deg(_dbg_hdiff),
							rad_to_deg(_dbg_desired_bank),
							rad_to_deg(bank_angle),
							int(speed * 3.6),
							int(_max_speed_at_altitude()),
							ldr.g_load if is_instance_valid(ldr) else 0.0,
						])

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
			_update_rocket(delta)
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
	_update_ciws(delta)
	_update_rocket(delta)
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

	# ── 预测式过冲补偿（critical damping）──
	# 真实飞行员会"预读"自己当前的转弯率：在到达目标航向**之前**就开始回正坡度，
	# 这样反馈环路才不会沿着 sinusoidal 摆动。
	# 1. 估算当前转弯率 ω = g·tan(bank)/V
	# 2. 估算把当前坡度从 |bank| 滚回 0 需要的时间 t_roll = |bank|/roll_rate
	# 3. 三角积分：滚出过程中航向再走 (ω · t_roll)/2 弧度
	# 4. 把这个预测量从 heading_diff 里扣掉，让下面的 P 控制器把"未来航向"对准目标
	# 注：仅在 anticipated_change 与 heading_diff 同号时扣（即正在朝目标转），
	#     避免在反向初动时把扣减算反。
	if absf(bank_angle) > 0.05 and absf(heading_diff) > 0.001:
		var rr_val := params.roll_rate if params else 4.0
		var stall_ms_pre := _stall_speed() / 3.6
		if speed < stall_ms_pre:
			var ctrl_pre := clampf(speed / maxf(stall_ms_pre, 1.0), 0.1, 1.0)
			rr_val *= ctrl_pre
		var current_turn_rate := GRAVITY * tan(bank_angle) / maxf(speed, 50.0)
		var t_roll := absf(bank_angle) / maxf(rr_val, 0.5)
		var anticipated_change := current_turn_rate * t_roll * 0.5
		if signf(anticipated_change) == signf(heading_diff):
			# 不让补偿超过 heading_diff 本身（避免反符号过冲）
			if absf(anticipated_change) >= absf(heading_diff):
				heading_diff = 0.0
			else:
				heading_diff -= anticipated_change

	var max_bank := _max_bank_angle()
	var in_combat := combat_target != null
	var target_bank: float

	# 大角度转弯时限制最大坡度到持续G水平，防止追踪时拉极端G螺旋
	# 只有小角度精确对准时才允许使用结构极限G
	# tactical_aggression 控制限制的强度：
	#   1.0 = 完全解除限制，拉到结构 G 上限（survivor 玩家默认）
	#   0.0 = 完全应用 70% 持续 G 限制（保守 AI）
	#   中间 = 按因子在两者之间插值（沙盒 AI 随飞行员属性动态调整）
	if in_combat and abs(heading_diff) > 0.5 and tactical_aggression < 0.999:
		var sustained_g := params.max_g if params else 9.0
		var turn_g_capped := lerpf(sustained_g * 0.7, sustained_g, clampf((PI - abs(heading_diff)) / (PI - 0.5), 0.0, 1.0))
		var turn_g_full := _effective_max_g()
		var turn_g := lerpf(turn_g_capped, turn_g_full, clampf(tactical_aggression, 0.0, 1.0))
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
	elif use_tactical_preference:
		# 玩家巡航模式（点击移动）：最激进的转弯，忽略距离衰减
		# 目的：最快到达点击位置，拉满 G 以获得最小转弯半径
		if abs(heading_diff) < 0.02:
			target_bank = 0.0
		elif abs(heading_diff) < 0.15:
			var player_ratio: float = (abs(heading_diff) - 0.02) / (0.15 - 0.02)
			target_bank = sign(heading_diff) * max_bank * lerpf(0.5, 1.0, player_ratio)
		else:
			target_bank = sign(heading_diff) * max_bank
		# 不应用 _proximity_damping：玩家要始终满 G 转弯
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
	var _m := get_maneuver()
	if _m and _m.is_active:
		return  # 战术机动期间速度由模块控制
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
	var _m := get_maneuver()
	if _m and _m.is_active:
		return  # 战术机动期间 G 力由模块直接设置
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

## 角点速度（km/h）：能承受当前 G 极限而不被 _max_bank_angle 速度限制卡住的最低速度
## V_corner = V_stall_base × safe_margin × sqrt(G_effective)
## 大 G 转弯时应维持此速度以获得最小转弯半径（不过分减速导致 G 被速度钳制）
func _corner_speed_kmh() -> float:
	var g_target := _effective_max_g()
	var stall_base_kmh := params.stall_speed_base if params else 220.0
	# safe_margin 与 _max_bank_angle 保持一致（1.2）
	return stall_base_kmh * 1.2 * sqrt(maxf(g_target, 1.0))

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
	# 规范化角度差到 [-PI, PI]
	# 旧版用 fmod 在负数情况下返回负值，会让 target/current 跨越 ±π 边界时
	# 得到 |diff| > π 的结果（观测到 off_axis=268° 的 log bug）
	# wrapf 正确处理正负两侧的 wrap
	return wrapf(target - current, -PI, PI)

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
			# ======== 战术偏好：导弹模式能量管理（v8 — corner speed for turn）========
			# 物理事实：最快转弯率在**角点速度 (corner speed)**，不是 cruise 也不是 approach
			#   ω_max = V/R, R_min = V²/(g×√(G²-1))
			#   → ω ∝ 1/V （G 固定情况下），所以越慢越好
			#   但是 V 太低 → 速度 G 封顶 (V/V_stall/1.2)² 把 G 压下去 → ω 反而变小
			#   corner speed 是这两条曲线的交点：V = V_stall × 1.2 × √G
			# 所以未对准时用 corner speed 获得最小转弯半径和最大角速度
			# AB 只在加速到 corner 的过程中用（帮助快速进入最优转弯态）
			var corner_kmh := _corner_speed_kmh()
			var eff_range_px := _effective_missile_range_px()

			# match_kmh: 敌机速度 + 50 kmh 小余量
			var match_kmh := clampf(tgt_speed_kmh + 50.0, combat_min_kmh, cruise)

			# 检查是否已有弹在飞向此目标
			var has_inflight_missile := false
			if missile_manager:
				has_inflight_missile = missile_manager.has_active_missile_at(self, combat_target)

			# 对准窗口：航向偏差小于此值才算"已对准"，可以减速累积锁定
			var align_window_deg := 35.0
			var is_aligned := heading_diff_deg <= align_window_deg

			# turn_target: corner speed 与 cruise×0.85 的较大值，保证在 V_stall G 封顶之上
			var turn_target_kmh := maxf(corner_kmh, cruise * 0.85)

			if has_inflight_missile:
				# 发射后：稳定 match，不继续冲
				target_speed_kmh = match_kmh
				_set_afterburner(false)
			elif not is_aligned:
				# 未对准：用 corner speed（最大角速度点）
				# 如果当前速度低于 corner，用加力快速拉上来（加力服务于转弯，不是冲距离）
				target_speed_kmh = turn_target_kmh
				_set_afterburner(my_kmh < turn_target_kmh - 40.0 and fuel > 0.0)
			elif dist > eff_range_px:
				# 对准但超出雷达范围：cruise 稳步推进
				target_speed_kmh = cruise
				_set_afterburner(false)
			else:
				# 对准且在雷达范围内：match 稳定累积锁定
				target_speed_kmh = match_kmh
				_set_afterburner(false)
			target_speed_kmh = maxf(target_speed_kmh, combat_min_kmh)
		elif is_missile_mode:
			# ======== AI / 沙盒 导弹模式能量管理（v9 sync with tactical）========
			# 和玩家战术偏好统一：距离带 + corner speed 转弯 + match speed 稳锁
			# 区别：AI 的加力辅助转弯由 tactical_aggression 门控（pilot attrs 决定是否激进）
			var corner_kmh := _corner_speed_kmh()
			var eff_range_px := _effective_missile_range_px()

			# match_kmh: 敌机速度 + 50 kmh 小余量
			var match_kmh := clampf(tgt_speed_kmh + 50.0, combat_min_kmh, cruise)

			# 对准窗口：航向偏差小于此值才算"已对准"
			var align_window_deg := 35.0
			var is_aligned := heading_diff_deg <= align_window_deg

			# turn_target: corner speed
			var turn_target_kmh := maxf(corner_kmh, cruise * 0.85)

			if not is_aligned:
				# 未对准：corner speed 最大转弯率
				target_speed_kmh = turn_target_kmh
				# AI 只在高 aggression（ace 飞行员）时才用加力辅助转弯
				if tactical_aggression > 0.6:
					_set_afterburner(my_kmh < turn_target_kmh - 40.0 and fuel > 0.0)
				else:
					_set_afterburner(false)
			elif dist > eff_range_px * 1.3 and tactical_aggression > 0.6:
				# 真正远距离（超出有效射程 30%）+ 对准 + 激进 AI → 加力冲刺闭合
				target_speed_kmh = approach_speed
				_set_afterburner(my_kmh < approach_speed and fuel > 0.0)
			elif dist > eff_range_px:
				# 对准但超出雷达范围：cruise 稳步推进
				target_speed_kmh = cruise
				_set_afterburner(false)
			else:
				# 对准且在雷达范围内：match 稳定累积锁定
				target_speed_kmh = match_kmh
				_set_afterburner(false)

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
				var conservative_spd := lerpf(maneuver_speed, turn_speed, turn_ratio)
				# tactical_aggression 高 → 维持角点速度获得最小半径
				if tactical_aggression > 0.01:
					var corner_kmh := _corner_speed_kmh()
					var aggressive_spd := maxf(corner_kmh, cruise * 0.9)
					target_speed_kmh = lerpf(conservative_spd, aggressive_spd, clampf(tactical_aggression, 0.0, 1.0))
				else:
					target_speed_kmh = conservative_spd
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

		# 玩家战术偏好巡航（点击移动）：距离目标远且航向对齐时开加力冲刺
		if use_tactical_preference and target_position != Vector2.INF:
			var diff_to_tgt := target_position - global_position
			var dist_to_tgt := diff_to_tgt.length()
			var hdg_to_tgt := atan2(diff_to_tgt.x, -diff_to_tgt.y)
			var hdiff_deg := absf(rad_to_deg(_angle_diff(hdg_to_tgt, heading)))
			var approach_spd := cruise * cb.approach_speed_mult
			var my_kmh_cr := speed * 3.6
			var corner_kmh_cr := _corner_speed_kmh()

			if hdiff_deg > cb.turn_slow_angle:
				# 大角度转弯：维持角点速度，拉满结构 G 获得最小转弯半径
				target_speed_kmh = maxf(corner_kmh_cr, cruise * 0.9)
				_set_afterburner(false)
			elif dist_to_tgt > 800.0:
				# 远距离直线冲刺：开加力
				target_speed_kmh = approach_spd
				_set_afterburner(my_kmh_cr < approach_spd and fuel > 0.0)
			else:
				target_speed_kmh = cruise
				_set_afterburner(false)
		else:
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
	_overshoot_timer = 0.0
	_gun_pass_committed = false  # 切目标时解除机炮提交锁定

func clear_combat_target() -> void:
	combat_target = null
	_committed_turn_sign = 0.0
	is_firing = false
	_strafe_state = 0
	_overshoot_timer = 0.0
	_gun_pass_committed = false  # 清目标时解除机炮提交锁定

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

	# ---- 近距过顶 extension ----
	# 与目标距离小于阈值时追击/开火都会退化，强制沿机头直飞一段时间脱离，
	# 让正常追击逻辑在飞出后（target 落到后半球 heading_diff>90°）掉头重新接敌。
	_overshoot_timer = maxf(_overshoot_timer - _delta, 0.0)
	if dist < OVERSHOOT_DIST_PX:
		_overshoot_timer = OVERSHOOT_EXTEND_TIME
	if _overshoot_timer > 0.0:
		target_position = my_pos + my_fwd * OVERSHOOT_EXTEND_DIST_PX
		is_firing = false
		_gun_lead_heading = heading
		return

	var is_missile_mode := weapon_mode == WeaponMode.MISSILE

	# 战术偏好模式（玩家手动控制）：按武器模式动态选择拦截方案
	# - 导弹模式：纯前置拦截点，保持锁定和追踪（发射后 cooldown 结束能立刻再射）
	# - 机炮模式：根据距离+前后半球动态切换六点钟偏移 / lead turn，避免死执行
	#   导致的"冲过去→overshoot→再冲回来"循环
	if use_tactical_preference:
		if is_missile_mode:
			var lead_time := clampf(dist / maxf(my_speed_px, 50.0), 0.3, 1.5)
			target_position = tgt_pos + tgt_fwd * tgt_speed_px * lead_time
		else:
			target_position = _choose_dogfight_pursuit_pos(
					my_pos, dist, tgt_pos, tgt_fwd, tgt_speed_px, my_speed_px, in_rear_hemisphere)
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
			# v9 sync: ideal_range 基于雷达有效射程（和 tactical/energy_management 一致）
			var msl_phase := _get_missile_phase()
			var msl := params.missile
			var min_range_px := msl.min_range * PIXELS_PER_METER if msl else 250.0
			var ideal_range_px := _effective_missile_range_px() * 0.55 if msl else 500.0

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
			# ---- 机炮模式追踪：复用距离+速度感知的动态追踪 ----
			pursuit_pos = _choose_dogfight_pursuit_pos(
					my_pos, dist, tgt_pos, tgt_fwd, tgt_speed_px, my_speed_px, in_rear_hemisphere)

		target_position = pursuit_pos

	# ---- 开火判定（对前置点）—— 仅机炮模式 ----
	var gun := params.gun if params else null
	if gun and ammo > 0 and not is_missile_mode:
		var range_px := gun.max_range * PIXELS_PER_METER
		var base_cone := deg_to_rad(gun.fire_cone_half_angle)

		# 计算前置射击点（两轮迭代修正）：
		# 第一轮用到目标距离估算飞行时间，第二轮用到前置点距离修正，
		# 解决追击高速目标时前置量不足、子弹落在目标后方的问题
		var bullet_speed_px := gun.muzzle_velocity * PIXELS_PER_METER
		var t1 := dist / maxf(bullet_speed_px, 100.0)
		var lead1 := tgt_pos + tgt_fwd * tgt_speed_px * t1
		var t2 := my_pos.distance_to(lead1) / maxf(bullet_speed_px, 100.0)
		var lead_pos := tgt_pos + tgt_fwd * tgt_speed_px * t2

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
		# 射程检查用到目标的实际距离（dist），不用到前置点的距离（lead_dist），
		# 因为迭代修正后前置点更远，用 lead_dist 会误判超出射程导致不开火
		is_firing = dist > MIN_GUN_FIRE_DIST_PX and dist <= fire_range and angle_diff <= fire_cone and (flat_altitude or alt_diff < 500.0)
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

## 战术偏好机炮狗斗的动态拦截点选择
## 根据距离与相对位置在"前置拦截"和"六点钟偏移"之间连续过渡：
## - 后半球：瞄动态六点钟偏移。距离越近 offset 越大（自动 break-out 脱离过顶），
##           距离到达 2×gun_range 时收敛到 0.3×gun_range 的紧追
## - 前半球远距：lead intercept 拉近
## - 前半球近距：侧向 lag，垂直于敌机航向推开一侧后再咬尾
## 每帧重算，没有粘滞决策；插值连续，不会在阈值上震荡
func _choose_dogfight_pursuit_pos(
		my_pos: Vector2,
		dist: float,
		tgt_pos: Vector2,
		tgt_fwd: Vector2,
		tgt_speed_px: float,
		my_speed_px: float,
		in_rear: bool
) -> Vector2:
	var gun_range := _gun_range_px()

	# ── 距离分段：远距追实际位置，中距过渡，近距精确战术 ──
	# 阈值受敌机速度影响：
	#   速度比 = 敌机速度 / 我的速度（>1 表示敌机更快）
	#   敌机越快 → 阈值越大 → 维持直追更久（否则追不上）
	#   敌机越慢 → 阈值越小 → 更早切入战术追踪
	var speed_ratio := clampf(tgt_speed_px / maxf(my_speed_px, 50.0), 0.5, 2.0)
	var far_threshold := gun_range * lerpf(2.0, 4.0, clampf(speed_ratio - 0.5, 0.0, 1.0))
	var tactic_threshold := gun_range * lerpf(1.0, 2.0, clampf(speed_ratio - 0.5, 0.0, 1.0))

	if dist > far_threshold:
		# 远距：直追目标实际位置，最短路径闭合距离
		return tgt_pos

	# 计算近距战术目标点
	var tactic_pos: Vector2
	if in_rear:
		# 后半球：六点钟偏移，距离越近偏移越大防过顶
		var t_six := clampf(dist / (gun_range * 2.0), 0.0, 1.0)
		var offset_ratio := lerpf(1.8, 0.3, t_six)
		var six_offset := maxf(80.0, gun_range * offset_ratio)
		tactic_pos = tgt_pos - tgt_fwd * six_offset
	else:
		# 前半球近距：前置拦截点（利用改进的两轮迭代获得更准的前置量）
		var bullet_speed_px := 525.0  # 默认值
		if params and params.gun:
			bullet_speed_px = params.gun.muzzle_velocity * PIXELS_PER_METER
		var t1 := dist / maxf(bullet_speed_px, 100.0)
		var lead1 := tgt_pos + tgt_fwd * tgt_speed_px * t1
		var t2 := my_pos.distance_to(lead1) / maxf(bullet_speed_px, 100.0)
		tactic_pos = tgt_pos + tgt_fwd * tgt_speed_px * t2

	if dist > tactic_threshold:
		# 中距过渡：目标实际位置与战术点之间线性混合
		var blend := clampf((dist - tactic_threshold) / (far_threshold - tactic_threshold), 0.0, 1.0)
		return tgt_pos.lerp(tactic_pos, 1.0 - blend)

	# 近距：完全使用战术目标点
	return tactic_pos

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
	# 整匣装填（生存模式）：弹药耗尽 → 进入 CD → 一次性补满
	if enable_gun_reload and _gun_reload_active:
		_gun_reload_timer += delta
		gun_reload_progress = clampf(_gun_reload_timer / gun_reload_duration, 0.0, 1.0)
		if _gun_reload_timer >= gun_reload_duration:
			if params and params.gun:
				ammo = params.gun.max_ammo
			_gun_reload_active = false
			_gun_reload_timer = 0.0
			gun_reload_progress = 0.0
		is_firing = false
		return
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
	# 弹药耗尽 → 进入装填 CD（生存模式）
	if enable_gun_reload and ammo <= 0 and not _gun_reload_active:
		_gun_reload_active = true
		_gun_reload_timer = 0.0
		gun_reload_progress = 0.0

## ========== CIWS 近防炮（进化技能：自动拦截正面来袭导弹） ==========
## 不转机头，只拦截恰好在机炮锥内的导弹。与手动射击并行，共用弹药池。
func _update_ciws(delta: float) -> void:
	if not gun_ciws_active or not missile_manager or not params or not params.gun:
		return
	if ammo <= 0 or _gun_reload_active:
		return

	_ciws_cooldown = maxf(_ciws_cooldown - delta, 0.0)
	if _ciws_cooldown > 0.0:
		return

	var gun: GunParams = params.gun
	var range_px := gun.max_range * PIXELS_PER_METER
	var cone_rad := deg_to_rad(gun.fire_cone_half_angle)
	var my_fwd := Vector2(sin(heading), -cos(heading))

	# 找正面锥内最近的来袭导弹
	var best_missile: Missile = null
	var best_dist := INF
	for child in missile_manager.get_children():
		if not (child is Missile):
			continue
		var m: Missile = child as Missile
		if not m.is_active or m.is_flare_jammed or m.team == team:
			continue
		if m.target != self:
			continue
		var to_m := (m.global_position - global_position).normalized()
		var angle := acos(clampf(my_fwd.dot(to_m), -1.0, 1.0))
		if angle > cone_rad:
			continue
		var dist := global_position.distance_to(m.global_position)
		if dist > range_px or dist > best_dist:
			continue
		best_dist = dist
		best_missile = m

	if not best_missile:
		return

	# 前置射击：导弹速度快，需要精确前置
	var m_fwd := Vector2(sin(best_missile.heading), -cos(best_missile.heading))
	var m_speed_px := best_missile.speed * PIXELS_PER_METER
	var bullet_speed_px := gun.muzzle_velocity * PIXELS_PER_METER
	var t := best_dist / maxf(bullet_speed_px, 100.0)
	var lead_pos := best_missile.global_position + m_fwd * m_speed_px * t
	var lead_dir := (lead_pos - global_position).normalized()
	var fire_heading := atan2(lead_dir.x, -lead_dir.y)

	# 前置点也必须在锥内
	var lead_angle := acos(clampf(my_fwd.dot(lead_dir), -1.0, 1.0))
	if lead_angle > cone_rad:
		return

	# 发射 CIWS 子弹（带 is_ciws 标记，仅这种子弹碰撞导弹）
	_ciws_cooldown = 60.0 / gun.fire_rate
	var spread_rad := deg_to_rad(gun.spread_angle)
	var bullet_dir := fire_heading + randf_range(-spread_rad, spread_rad)
	var muzzle_pos := global_position + Vector2(sin(heading), -cos(heading)) * 20.0
	bullet_manager.spawn_bullet(muzzle_pos, bullet_dir, gun.muzzle_velocity, self, gun.bullet_damage, true)
	ammo -= 1
	ammo = maxi(ammo, 0)
	if enable_gun_reload and ammo <= 0 and not _gun_reload_active:
		_gun_reload_active = true
		_gun_reload_timer = 0.0
		gun_reload_progress = 0.0

## ========== 火箭弹（无制导副武器） ==========
## 对空中或地面目标发射一串无制导火箭。散布很大，命中率故意调低。
## 发射时机：有战斗目标 + 目标在机头前方 + 距离在火箭弹射程内 + 齐射冷却归零。
## 齐射内部通过 _rocket_queue 按间隔连发，不立即一次性射出。
func _update_rocket(delta: float) -> void:
	if not params or not params.rocket:
		return
	var rk: RocketParams = params.rocket
	_rocket_burst_cooldown = maxf(_rocket_burst_cooldown - delta, 0.0)

	# 发射待发射队列中的火箭（delay 到了就出膛）
	if not _rocket_queue.is_empty():
		var i := _rocket_queue.size() - 1
		while i >= 0:
			var q: Dictionary = _rocket_queue[i]
			q["delay"] = float(q["delay"]) - delta
			if q["delay"] <= 0.0:
				_launch_rocket(q["heading"], q["pos"])
				_rocket_queue.remove_at(i)
			i -= 1

	# 新齐射判定
	if rockets_remaining <= 0:
		return
	if _rocket_burst_cooldown > 0.0:
		return
	if combat_target == null or not is_instance_valid(combat_target) or combat_target.is_destroyed:
		return
	# crank / 导弹发射阶段不打火箭，避免动作冲突
	if _crank_timer > 0.0:
		return

	var tgt_pos := combat_target.global_position
	var dist_px := global_position.distance_to(tgt_pos)
	var dist_m := dist_px / PIXELS_PER_METER

	# 距离过滤
	if dist_m < rk.min_range or dist_m > rk.max_fire_range:
		return

	# 高度差过滤（扁平高度模式忽略；地面目标忽略）
	if not flat_altitude and not (combat_target is GroundUnit):
		if absf(altitude - combat_target.altitude) > 800.0:
			return

	# 机头偏角过滤：目标必须在机头前方的 fire_cone_half_angle 内
	var to_tgt := (tgt_pos - global_position).normalized()
	var hdg_to_tgt := atan2(to_tgt.x, -to_tgt.y)
	var angle_diff := absf(_angle_diff(hdg_to_tgt, heading))
	if angle_diff > deg_to_rad(rk.fire_cone_half_angle):
		return

	# 启动齐射：随机决定本次齐射枚数，入队延迟发射
	var burst_n: int = randi_range(rk.burst_count_min, rk.burst_count_max)
	burst_n = mini(burst_n, rockets_remaining)
	if burst_n <= 0:
		return

	for n in range(burst_n):
		_rocket_queue.append({
			"delay": float(n) * rk.burst_interval,
			"heading": hdg_to_tgt,  ## 朝目标方向发射（由 _launch_rocket 再加散布）
			"pos": global_position,
		})
	_rocket_burst_cooldown = rk.burst_cooldown

## 真正把一发火箭弹交给 BulletManager
func _launch_rocket(base_heading: float, _queued_pos: Vector2) -> void:
	if not params or not params.rocket or rockets_remaining <= 0:
		return
	if not bullet_manager or not bullet_manager.has_method("spawn_rocket"):
		return
	var rk: RocketParams = params.rocket
	var spread_rad := deg_to_rad(rk.spread_angle)
	var dir := base_heading + randf_range(-spread_rad, spread_rad)
	var muzzle_pos := global_position + Vector2(sin(heading), -cos(heading)) * 24.0
	bullet_manager.spawn_rocket(muzzle_pos, dir, rk.muzzle_velocity, self, rk.rocket_damage, rk.max_range)
	rockets_remaining -= 1

## 导弹射程（像素）
func _missile_range_px() -> float:
	if params and params.missile:
		# 使用后半球射程的 60% 作为理想交战距离参考
		return params.missile.max_range_rear * 0.6 * PIXELS_PER_METER
	return 500.0

## 有效导弹交战距离（像素）= min(导弹射程, 雷达范围)
## 导弹虽可飞远但雷达外无法锁定，所以真正可打击距离由雷达限制
## 扁平模式下导弹射程有 alt_factor=1.5 加成，与 _is_in_missile_envelope 一致
## ⚠ 单位注意：missile.max_range_rear 是米，radar_range 是像素（见 aircraft_params.gd:44）
func _effective_missile_range_px() -> float:
	if not params or not params.missile:
		return 1500.0
	var missile_range_m: float = params.missile.max_range_rear
	if flat_altitude:
		missile_range_m *= 1.5
	var missile_range_px := missile_range_m * PIXELS_PER_METER  # 米 → 像素
	var radar_range_px: float = params.radar_range               # 已经是像素，不要再乘
	return minf(missile_range_px, radar_range_px)

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

	# AI / 沙盒模式（v9 sync with tactical）
	# 规则：默认偏好导弹；只在 _missile_cannot_hit_but_gun_can() 为真时切机炮
	# 根据目标类型判断"可用导弹数"：空中目标只能用 AAM（主），地面目标两种皆可
	var target_is_ground: bool = combat_target != null and is_instance_valid(combat_target) and combat_target is GroundUnit
	var usable_missiles: int = 0
	if params:
		if target_is_ground:
			usable_missiles = missiles_remaining + secondary_missiles_remaining
		else:
			usable_missiles = missiles_remaining  # 空中只能用 AAM
	# 完全无导弹（弹药为零或无武器） → 机炮
	if (not params or (not params.missile and not params.secondary_missile)) or usable_missiles <= 0:
		weapon_mode = WeaponMode.GUN
		return
	# 发射后 crank 阶段：保持导弹模式稳定照射
	if _crank_timer > 0.0:
		weapon_mode = WeaponMode.MISSILE
		return
	# 与战术偏好同源的回退规则：导弹打不到但机炮能 → 机炮
	if _missile_cannot_hit_but_gun_can():
		weapon_mode = WeaponMode.GUN
	else:
		weapon_mode = WeaponMode.MISSILE

## 战术偏好武器模式：玩家手动控制，简洁明确
func _update_weapon_mode_tactical() -> void:
	match weapon_preference:
		WeaponPreference.PREFER_MISSILE:
			var has_missile := (missiles_remaining + secondary_missiles_remaining) > 0
			var reloading := enable_missile_reload and _missile_reload_active

			# 机炮攻击提交状态维护：飞过目标后解除
			if _gun_pass_committed and _is_gun_pass_finished():
				_gun_pass_committed = false

			# 装填中 或 正在完成机炮攻击 → 保持机炮模式
			if reloading or _gun_pass_committed:
				weapon_mode = WeaponMode.GUN
				# 装填中且接近目标 → 提交这次机炮攻击
				# 一旦提交，即使装填好了也要完成这套攻击再切回导弹
				if reloading and _should_commit_gun_pass():
					_gun_pass_committed = true
			elif not has_missile and _crank_timer <= 0.0:
				# 导弹打完：用机炮应急
				weapon_mode = WeaponMode.GUN
			elif _crank_timer > 0.0:
				# 保持 crank 状态
				weapon_mode = WeaponMode.MISSILE
			elif _missile_cannot_hit_but_gun_can():
				# 导弹优先回退规则：导弹打不中（太近/太远/出锥）但机炮能打 → 用机炮
				weapon_mode = WeaponMode.GUN
			else:
				weapon_mode = WeaponMode.MISSILE
		WeaponPreference.PREFER_GUN:
			weapon_mode = WeaponMode.GUN
			_gun_pass_committed = false

## 导弹优先回退：导弹打不中但机炮能打 → 切机炮
## 用户规则："同样距离内两者都能命中则优先导弹；导弹不能命中但机炮能则用机炮"
## 主要触发：目标在导弹 min_range 以内（太近）且在机炮射程内
## 为避免 flip-flop，不考虑"暂时出锥"这种瞬时情况
## hysteresis: 已在 GUN 模式时，需要 dist > min_range + 150 才切回 MISSILE
func _missile_cannot_hit_but_gun_can() -> bool:
	if combat_target == null or not is_instance_valid(combat_target) or combat_target.is_destroyed:
		return false
	if not params or not params.gun:
		return false  # 无机炮可切
	var dist_m := global_position.distance_to(combat_target.global_position) / PIXELS_PER_METER
	var gun_range_m: float = params.gun.max_range
	if dist_m > gun_range_m:
		return false  # 机炮也打不到
	if not params.missile:
		return true  # 无导弹只能用机炮
	# 核心规则：dist 太近（进不了导弹 min_range）且机炮能打 → 用机炮
	var min_threshold: float = params.missile.min_range
	# 滞回：已在机炮模式时，需要飞出 min_range + 150m 才切回导弹
	if weapon_mode == WeaponMode.GUN:
		min_threshold += 150.0
	if dist_m < min_threshold:
		return true
	return false

## 是否应当提交这次机炮攻击：有目标且已接近机炮射程范围
func _should_commit_gun_pass() -> bool:
	if combat_target == null or not is_instance_valid(combat_target) or combat_target.is_destroyed:
		return false
	var dist := global_position.distance_to(combat_target.global_position)
	# 接近机炮射程（2 倍范围内）视为开始攻击，进入提交
	return dist < _gun_range_px() * 2.0

## 机炮攻击是否已完成：目标在身后且拉开距离，或目标失效
func _is_gun_pass_finished() -> bool:
	if combat_target == null or not is_instance_valid(combat_target) or combat_target.is_destroyed:
		return true
	var to_tgt := combat_target.global_position - global_position
	var dist := to_tgt.length()
	if dist < 1.0:
		return false
	var my_fwd := Vector2(sin(heading), -cos(heading))
	var fwd_dot := my_fwd.dot(to_tgt / dist)
	# 目标在身后 (dot < -0.2 ≈ 超过机尾 100° 锥内) 且 已拉开到机炮射程外 → 飞过完成
	return fwd_dot < -0.2 and dist > _gun_range_px()

## 是否正在保持照射（发射后维持锁定阶段）
func is_cranking() -> bool:
	return _crank_timer > 0.0

## 切换规避模式：进入时清空当前指令（等同右键"解除任务"），离开时不动作
## 供 HUD 按钮 / 键位 / 点击逻辑统一调用
func set_evasion_mode(enabled: bool) -> void:
	evasion_mode = enabled
	if enabled:
		# 取消当前移动指令和交战目标，专心躲避
		clear_combat_target()
		target_position = Vector2.INF
		_evasion_override = false
	# 关闭时不动作，玩家可手动指定新目标

## 规避模式更新（生存模式玩家）
func _update_evasion(delta: float) -> void:
	# 冷却与动画倒计时
	_evade_roll_cooldown = maxf(_evade_roll_cooldown - delta, 0.0)
	if _evade_roll_remaining > 0.0:
		# 正在滚转：按固定速率推进相位（一圈 / _EVADE_ROLL_DURATION）
		var roll_speed := TAU / _EVADE_ROLL_DURATION
		_evade_roll_phase += roll_speed * delta
		if _evade_roll_phase > PI:
			_evade_roll_phase -= TAU
		_evade_roll_remaining -= delta
		if _evade_roll_remaining <= 0.0:
			_evade_roll_remaining = 0.0
			_evade_roll_cooldown = _EVADE_ROLL_COOLDOWN
	else:
		# 无滚转：相位平滑回正（机翼水平）
		_evade_roll_phase = lerp_angle(_evade_roll_phase, 0.0, clampf(delta * 6.0, 0.0, 1.0))
		if absf(_evade_roll_phase) < 0.02:
			_evade_roll_phase = 0.0

	if not use_tactical_preference or not evasion_mode:
		return

	# 检测来袭导弹（最近的一枚）
	var incoming_missile: Missile = null
	var closest_dist := INF
	if missile_manager:
		for child in missile_manager.get_children():
			if child is Missile:
				var m: Missile = child as Missile
				if m.is_active and not m.is_flare_jammed and m.target == self:
					var d := global_position.distance_squared_to(m.global_position)
					if d < closest_dist:
						closest_dist = d
						incoming_missile = m

	if incoming_missile:
		var dist_px := sqrt(closest_dist)
		# 触发一次短促的桶滚动画：导弹首次进入触发距离 + 冷却就绪 + 不同的来袭导弹
		var mid := incoming_missile.get_instance_id()
		if dist_px < _EVADE_ROLL_TRIGGER_PX \
				and _evade_roll_cooldown <= 0.0 \
				and _evade_roll_remaining <= 0.0 \
				and mid != _evade_last_missile_id:
			_evade_roll_remaining = _EVADE_ROLL_DURATION
			_evade_last_missile_id = mid

		# 规避方向：垂直于导弹来袭方向
		var missile_dir := (global_position - incoming_missile.global_position).normalized()
		var evade_dir := Vector2(missile_dir.y, -missile_dir.x)
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
	else:
		# 无来袭导弹：S 型机动，不依赖 _evasion_override（该标志已废弃）
		_evade_last_missile_id = 0
		_evasion_sway_timer += delta
		var sway_period := 3.0
		var sway_angle := sin(_evasion_sway_timer * TAU / sway_period) * 0.8
		var sway_heading := heading + sway_angle
		target_position = global_position + Vector2(sin(sway_heading), -cos(sway_heading)) * 1500.0

## 节流记录玩家导弹发射被阻塞的原因（每 MSL_BLOCK_LOG_INTERVAL 最多一次）
## 同一 reason 连续触发时不重复记录，直到 reason 改变或间隔到期
func _log_msl_block(reason: String, detail: String) -> void:
	if not use_tactical_preference:
		return
	if combat_target == null or not is_instance_valid(combat_target):
		return
	if _msl_block_log_timer > 0.0 and _msl_last_block_reason == reason:
		return
	_msl_block_log_timer = MSL_BLOCK_LOG_INTERVAL
	_msl_last_block_reason = reason
	var tgt_name := _log_unit_name(combat_target)
	EventLogger.log_event("MSL_BLOCK", _log_name(),
		"%s → %s: %s" % [reason, tgt_name, detail])

## 威胁态势快照：转储所有正在攻击玩家的导弹 + 所有正在锁定/已锁定玩家的敌方单位
## 在导弹开火时打到日志，便于事后排查"为什么打了这一发"
func _log_threat_picture(context: String) -> void:
	if not missile_manager:
		return

	# 1. 正在攻击我的导弹（target == self 的在飞导弹）
	var attacking: Array[String] = []
	for child in missile_manager.get_children():
		if child is Missile:
			var m: Missile = child as Missile
			if not m.is_active or m.target != self:
				continue
			var msl_name: String = m.params.display_name if m.params and m.params.display_name else "MSL"
			var src_label := "?"
			var src_dist := 0.0
			if is_instance_valid(m.source):
				src_label = _log_unit_name(m.source)
				src_dist = global_position.distance_to(m.source.global_position) / PIXELS_PER_METER
			var time_to_impact := global_position.distance_to(m.global_position) / maxf(m.speed * PIXELS_PER_METER, 1.0)
			attacking.append("%s<-%s @%.0fm eta=%.1fs" % [msl_name, src_label, src_dist, time_to_impact])

	# 2. 正在/准备锁定我的敌方单位（其 radar_targets 里有 self）
	var locking: Array[String] = []
	for unit in missile_manager.target_list:
		if not is_instance_valid(unit) or unit.is_destroyed:
			continue
		if unit.team == team:
			continue
		var their_lock: float = unit.radar_targets.get(self, 0.0)
		if their_lock <= 0.0:
			continue
		var their_lock_time := 3.0
		if unit is Aircraft and unit.params:
			their_lock_time = unit.params.lock_time
		elif unit is GroundUnit and unit.params:
			their_lock_time = unit.params.lock_time
		var status := "LOCKED" if their_lock >= their_lock_time else "locking"
		var dist := global_position.distance_to(unit.global_position) / PIXELS_PER_METER
		locking.append("%s %s=%.1f/%.1fs @%.0fm" % [
			_log_unit_name(unit), status, their_lock, their_lock_time, dist])

	if attacking.is_empty() and locking.is_empty():
		return  # 无威胁就不打日志

	var parts: Array[String] = ["[%s]" % context]
	if not attacking.is_empty():
		parts.append("attacking=[%s]" % "; ".join(attacking))
	if not locking.is_empty():
		parts.append("locking=[%s]" % "; ".join(locking))
	EventLogger.log_event("THREAT", _log_name(), " ".join(parts))

## 导弹更新（发射逻辑）
## SARH 导弹：一次只锁定一个目标，选最容易命中的
func _update_missile(delta: float) -> void:
	_missile_cooldown = maxf(_missile_cooldown - delta, 0.0)
	_crank_timer = maxf(_crank_timer - delta, 0.0)
	_msl_block_log_timer = maxf(_msl_block_log_timer - delta, 0.0)

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
		_log_msl_block("WEAPON_MODE", "mode=%d" % weapon_mode)
		return
	if _missile_cooldown > 0.0:
		_log_msl_block("COOLDOWN", "cd=%.2fs" % _missile_cooldown)
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
		_log_msl_block("NO_MSL", "missiles_remaining=%d" % missiles_remaining)
		return

	# 战术偏好模式 + 自动发射开启：走齐射路径
	# - 无多目标追踪升级：齐射循环自动挑一枚最合适的目标开火
	# - 有升级：对所有锁定目标同时发射
	# 这条路径无需玩家点击 combat_target，完全自动
	# 关闭自动发射时跳过这里，直接走下方单发路径——多锁定升级因此被临时禁用，
	# 玩家只会对手点的 combat_target 开火
	if use_tactical_preference and missile_auto_fire:
		if _fire_multi_lock_salvo(msl):
			return
		# 多锁定升级下齐射就是完整路径：齐射没找到目标也不要 fall-through，
		# 否则下一帧（齐射不设冷却）单发路径会绕过 has_active_missile_at 检查
		# 对 combat_target 重复开火，造成同一目标连发两枚的浪费 bug。
		if max_simultaneous_locks > 1:
			return
		# 无升级时允许 fall-through 到单发（让玩家手点的目标仍能由单发路径打中）

	# 必须有明确的交战目标才允许发射导弹（玩家点击敌机设定）
	if combat_target == null or not is_instance_valid(combat_target) or combat_target.is_destroyed:
		return

	# 每目标在飞限制：AI 始终限 1 枚；玩家自动发射也限 1 枚（防浪费）
	# 玩家手动点击目标不受此限（允许补射）
	if missile_manager.has_active_missile_at(self, combat_target):
		if not use_tactical_preference or missile_auto_fire:
			_log_msl_block("ACTIVE_MSL", "already 1 in flight")
			return

	# 机炮正在对 combat_target 开火时不发射导弹（避免机炮击毁后还补一发）
	if use_tactical_preference and is_firing:
		_log_msl_block("GUN_ACTIVE", "shooting combat_target with gun")
		return

	var _dist_m := global_position.distance_to(combat_target.global_position) / PIXELS_PER_METER
	if not _is_in_missile_envelope(combat_target, msl):
		# 判断超射程还是低于最小射程
		var envelope_detail := ""
		if _dist_m < msl.min_range:
			envelope_detail = "too_close dist=%.0fm min=%.0fm" % [_dist_m, msl.min_range]
		else:
			envelope_detail = "out_of_envelope dist=%.0fm" % _dist_m
		_log_msl_block("ENVELOPE", envelope_detail)
		return

	if not is_in_radar_cone(combat_target.global_position):
		var to_tgt := combat_target.global_position - global_position
		var hdg_to_tgt := atan2(to_tgt.x, -to_tgt.y)
		var off_axis_deg := absf(rad_to_deg(_angle_diff(hdg_to_tgt, heading)))
		_log_msl_block("OFF_CONE", "dist=%.0fm off_axis=%.0f°" % [_dist_m, off_axis_deg])
		return

	var lock_progress: float = radar_targets.get(combat_target, 0.0)
	# 玩家战术偏好模式：跳过 1 秒稳定 buffer，只要 lock_time 到就开火
	# 原因：buffer 是给 AI 的"防抖"，玩家手动决策不需要
	# 节省 1 秒让玩家能在更远距离发射
	var lock_threshold: float = params.lock_time
	if not use_tactical_preference:
		lock_threshold += LOCK_STABLE_BUFFER
	if lock_progress < lock_threshold:
		_log_msl_block("LOCK", "dist=%.0fm lock=%.2fs/%.2fs" % [
			_dist_m, lock_progress, lock_threshold])
		return

	_fire_missile_at(combat_target, msl, use_secondary)
	if use_tactical_preference:
		_log_threat_picture("after single-fire")
	# 开火成功：清除阻塞原因缓存
	_msl_last_block_reason = ""

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
## 返回是否至少发射了一枚导弹
func _fire_multi_lock_salvo(msl: MissileParams) -> bool:
	var locked_targets: Array[CombatUnit] = []
	# 锁定阈值：AI 模式额外加 1 秒稳定缓冲；玩家战术偏好模式直接用 lock_time，
	# 与单发路径保持一致——否则齐射路径要求更高，combat_target 经常 fall-through
	# 到单发路径，单发路径会设满冷却，把 3 秒内才能成熟的兄弟目标全堵死。
	# lock_time 本身就要持续在锥内追踪 1.25 秒，沿途瞬时穿越的目标到不了阈值。
	var lock_threshold := params.lock_time
	if not use_tactical_preference:
		lock_threshold += LOCK_STABLE_BUFFER

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
		# 锁定框 = 完整雷达锥：只要目标当前在雷达锥内且锁定已稳定，就算"在射击位置"
		if not is_in_radar_cone(target_unit.global_position):
			continue
		if not _is_in_missile_envelope(target_unit, msl):
			continue
		if missile_manager.has_active_missile_at(self, target_unit):
			continue
		# 机炮正在射击 combat_target 时，不给 combat_target 发导弹（避免浪费）；
		# 齐射仍可打其他锁定目标
		if use_tactical_preference and is_firing and target_unit == combat_target:
			continue
		locked_targets.append(target_unit)

	if locked_targets.is_empty():
		return false

	# 玩家战术偏好 + 显式指定了 combat_target：
	# 要求 combat_target 必须出现在发射列表里，否则整个齐射取消。
	# 例外 1：combat_target 已经有在飞导弹（说明上一轮已经打过它了），允许齐射打其他目标
	# 例外 2：机炮正在打 combat_target（is_firing），允许齐射打其他目标
	if use_tactical_preference and combat_target != null \
			and is_instance_valid(combat_target) and not combat_target.is_destroyed:
		if locked_targets.find(combat_target) == -1:
			var combat_target_busy: bool = missile_manager.has_active_missile_at(self, combat_target) \
					or is_firing
			if not combat_target_busy:
				return false

	# 按距离排序，优先打近的
	locked_targets.sort_custom(func(a: CombatUnit, b: CombatUnit) -> bool:
		return global_position.distance_squared_to(a.global_position) < global_position.distance_squared_to(b.global_position)
	)

	# 战术偏好模式：把玩家手点的 combat_target 提到列表最前面（如果它在列表里）
	if use_tactical_preference and combat_target != null and is_instance_valid(combat_target):
		var idx := locked_targets.find(combat_target)
		if idx > 0:
			locked_targets.remove_at(idx)
			locked_targets.insert(0, combat_target)

	# 有多目标追踪升级（max_simultaneous_locks > 1）时，对所有锁定目标一起发射，
	# 只受剩余导弹数限制；无升级时仍按老逻辑只打 1 枚。
	var max_fire: int
	if max_simultaneous_locks > 1:
		max_fire = locked_targets.size()
	else:
		max_fire = 1
	var fire_count := mini(max_fire, missiles_remaining)
	var msl_display: String = msl.display_name if msl.display_name else "missile"
	# 规范化到 [0, 360°)，与游戏内 HDG 显示一致
	var hdg_deg := fposmod(rad_to_deg(heading), 360.0)
	for i in range(fire_count):
		var tgt: CombatUnit = locked_targets[i]
		var dist_m := global_position.distance_to(tgt.global_position) / PIXELS_PER_METER
		# 诊断：目标相对机头的偏角（用于排查"导弹方向跟目标对不上"的反馈）
		var to_tgt := tgt.global_position - global_position
		var hdg_to_tgt := atan2(to_tgt.x, -to_tgt.y)
		var off_axis_deg := rad_to_deg(_angle_diff(hdg_to_tgt, heading))
		var tgt_abs_brg := fposmod(rad_to_deg(hdg_to_tgt), 360.0)
		var lock_val: float = radar_targets.get(tgt, 0.0)
		EventLogger.log_event("MISSILE", _log_name(),
			"fired %s → %s (range=%.0fm, remaining=%d, salvo %d/%d, hdg=%03.0f° tgt_brg=%03.0f° tgt_off=%+.0f° lock=%.2fs)" % [
				msl_display, _log_unit_name(tgt), dist_m,
				missiles_remaining - 1, i + 1, fire_count,
				hdg_deg, tgt_abs_brg, off_axis_deg, lock_val])
		missile_manager.spawn_missile(self, tgt, msl)
		missiles_remaining -= 1

	if fire_count > 0:
		# 多目标追踪升级下跳过冷却，允许新锁定好的目标下一帧立刻开火；
		# 单锁定模式仍保留正常冷却（防止无升级时变相连发）
		if max_simultaneous_locks <= 1:
			_missile_cooldown = msl.cooldown
		_crank_timer = CRANK_DURATION
		# 装填触发
		if enable_missile_reload and missiles_remaining <= 0:
			_missile_reload_active = true
			_missile_reload_timer = 0.0
			missile_reload_progress = 0.0
		if use_tactical_preference:
			_log_threat_picture("after salvo x%d" % fire_count)
		return true
	return false

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
## 闪避率累加来源：
##   - 基础 bullet_dodge_chance（含生存模式 20% 主角基础 + 装甲强化升级）
##   - 规避模式额外 +20%（战术面板开启“回避/规避模式”时生效）
##   - HIGH 高度档位额外 +20%（高空机炮更难命中）
func take_bullet_damage(amount: float) -> void:
	if is_destroyed:
		return
	var effective_dodge: float = bullet_dodge_chance
	if use_tactical_preference and evasion_mode:
		effective_dodge += 0.20  # 规避模式加成
	if get_altitude_tier() == AltitudeTier.HIGH:
		effective_dodge += 0.20  # HIGH 高度加成
	if effective_dodge > 0.0 and randf() < effective_dodge:
		return  # 装甲偏转/规避，无视伤害
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
		_draw_gun_cone()
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
	if formation_debug:
		_draw_formation_debug()

## 编队调试覆盖层（仅 formation_debug=true 时绘制）
## 显示：当前分支、阵型槽位、当前/目标航向射线、bank 差异
##
## 注：_draw 已在飞机的 local space（rotation=heading）下运行。
## 想要绘制"机头朝上"的本地几何（航向射线/槽位连线），直接使用 local 坐标即可：
##   - 当前 heading 在 local 中始终是 (0, -L)
##   - 槽位 local = (slot_world - global_position).rotated(-rotation)
## 想要文本不跟随机身旋转，用 draw_set_transform 反旋转回世界对齐。
func _draw_formation_debug() -> void:
	# ── 1. 阵型槽位标记 + 连线（local space）──
	if _dbg_slot_pos != Vector2.INF and _dbg_slot_dist > 0.0:
		var slot_local := (_dbg_slot_pos - global_position).rotated(-rotation)
		var slot_color := Color(1.0, 0.4, 0.0, 0.7)  # 橙色
		draw_line(Vector2.ZERO, slot_local, slot_color, 1.5)
		# 槽位 X 标记
		var sx := 8.0
		draw_line(slot_local + Vector2(-sx, -sx), slot_local + Vector2(sx, sx), slot_color, 2.0)
		draw_line(slot_local + Vector2(-sx, sx), slot_local + Vector2(sx, -sx), slot_color, 2.0)
		# CLOSE_DIST 阈值圆
		draw_arc(slot_local, 50.0, 0, TAU, 32, Color(0.2, 1.0, 0.5, 0.4), 1.0)

	# ── 2. 当前/目标 heading 射线（local space，机头朝 -Y）──
	var ray_len := 80.0
	# 当前 heading 在 local 中始终朝上
	draw_line(Vector2.ZERO, Vector2(0, -ray_len), Color(0.4, 0.7, 1.0, 0.85), 2.0)
	# 目标 heading 相对当前的角度差
	var rel := _dbg_target_heading - heading
	var tgt_dir := Vector2(sin(rel), -cos(rel)) * ray_len
	draw_line(Vector2.ZERO, tgt_dir, Color(1.0, 0.9, 0.2, 0.85), 2.0)

	# ── 3. 文本面板（用 transform 反旋转 + 缩放补偿，保持世界对齐 + 同屏字号）──
	var inv_rot := -rotation
	var zoom_scale := get_viewport_transform().get_scale()
	var inv_zoom := 1.0 / maxf(zoom_scale.x, 0.01)
	var label_offset := Vector2(-110 * inv_zoom, 36 * inv_zoom).rotated(inv_rot)
	draw_set_transform(label_offset, inv_rot, Vector2(inv_zoom, inv_zoom))

	var lines := PackedStringArray()
	lines.append("[%s]" % _dbg_branch)
	lines.append("slot_d=%d" % int(_dbg_slot_dist))
	lines.append("hdg→%d Δ%+.1f°" % [int(rad_to_deg(_dbg_target_heading)), rad_to_deg(_dbg_hdiff)])
	lines.append("bank %+.0f→%+.0f" % [rad_to_deg(bank_angle), rad_to_deg(_dbg_desired_bank)])
	if _dbg_branch == "MID":
		# 复用 _dbg_slot_heading 字段：现在是横向偏置角度（不再是世界方位角）
		lines.append("bias=%+.0f°" % rad_to_deg(_dbg_slot_heading))
	lines.append("spd→%d/%d" % [int(_dbg_chase_target_kmh), int(speed * 3.6)])

	var line_h := 12.0
	var max_w := 110.0
	draw_rect(Rect2(Vector2(-2, -2), Vector2(max_w + 4, lines.size() * line_h + 4)),
		Color(0.0, 0.0, 0.0, 0.65))
	for i in range(lines.size()):
		var color := Color(1.0, 0.9, 0.5, 1.0)
		if i == 0:
			match _dbg_branch:
				"CLOSE": color = Color(0.4, 1.0, 0.5, 1.0)
				"MID":   color = Color(1.0, 0.9, 0.3, 1.0)
				"FAR":   color = Color(1.0, 0.5, 0.3, 1.0)
		draw_string(_font, Vector2(0, i * line_h + 9), lines[i],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 10, color)

	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

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

func _draw_gun_cone() -> void:
	if not params or not params.gun:
		return
	if team != 0:
		return  # 只对友方显示机炮射程锥
	var gun_r := params.gun.max_range * PIXELS_PER_METER
	var half_rad := deg_to_rad(params.gun.fire_cone_half_angle)

	var center_angle := -PI / 2.0
	var start_angle := center_angle - half_rad
	var end_angle := center_angle + half_rad
	var segments := 16

	var cone_color := Color(0.9, 0.7, 0.2, 0.15)

	var points := PackedVector2Array()
	points.append(Vector2.ZERO)
	for i in range(segments + 1):
		var angle := start_angle + (end_angle - start_angle) * float(i) / float(segments)
		points.append(Vector2(cos(angle), sin(angle)) * gun_r)

	draw_colored_polygon(points, cone_color)

	var edge_color := Color(cone_color, 0.4)
	draw_line(Vector2.ZERO, points[1], edge_color, 1.0, true)
	draw_line(Vector2.ZERO, points[points.size() - 1], edge_color, 1.0, true)
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

	# 滚转变形（常规 bank + 规避时的原地滚转相位）
	var bank_compress := cos(bank_angle + _evade_roll_phase)
	var sx := base_scale * bank_compress
	var sy := base_scale
	# 战术机动视觉效果：俯视视角下 Y 轴压缩（模拟机头大仰角）
	var _mv := get_maneuver()
	if _mv and _mv.visual_offset > 0.0:
		sy *= lerpf(1.0, 0.35, _mv.visual_offset)

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
	var status := "STALL" if is_stalled else ""

	# 计算到玩家（team 0）的距离（米）
	var dist_m := 0.0
	for node in get_parent().get_children():
		if node is Aircraft and node != self and node.team == 0 and not node.is_destroyed:
			dist_m = global_position.distance_to(node.global_position) / PIXELS_PER_METER
			break

	# 统一标签格式（所有飞机通用）
	var lines: PackedStringArray = PackedStringArray()
	# 第 1 行：代号 + 机种
	lines.append("%s [%s]" % [callsign, display_name])
	# 第 2 行：速度（kt）
	lines.append("%d kt" % roundi(speed_kmh * 0.5399))
	# 第 3 行：朝向
	lines.append("HDG %03d" % roundi(heading_deg))
	# 第 4 行：高度
	if flat_altitude:
		lines.append("ALT %s" % TIER_NAMES[get_altitude_tier()])
	else:
		lines.append("ALT %dm" % roundi(altitude))
	# 第 5 行：距离（到玩家）
	if dist_m < 1000.0:
		lines.append("RNG %dm" % roundi(dist_m))
	else:
		lines.append("RNG %.1fkm" % (dist_m / 1000.0))
	# 第 6 行：热诱弹
	if params and params.flare:
		lines.append("FLR %d" % flares_remaining)
	# 失速提示
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
	# 定期清理失误记录中已失效的导弹引用
	_flare_ignored_cleanup += delta
	if _flare_ignored_cleanup >= 2.0:
		_flare_ignored_cleanup = 0.0
		var to_remove: Array = []
		for mid in _flare_ignored_missiles:
			if not is_instance_id_valid(mid):
				to_remove.append(mid)
		for mid in to_remove:
			_flare_ignored_missiles.erase(mid)
	# 更新锁定免疫计时
	if _lock_immunity_timer > 0.0:
		_lock_immunity_timer = maxf(_lock_immunity_timer - delta, 0.0)
	# 更新导弹穿透计时（flare 后 1 秒所有导弹都会直接穿过）
	if missile_phase_timer > 0.0:
		missile_phase_timer = maxf(missile_phase_timer - delta, 0.0)

	# 更新粒子
	_update_flare_particles(delta)

	# 冷却
	_flare_cooldown = maxf(_flare_cooldown - delta, 0.0)

	if not params or not params.flare:
		return

	# 热诱弹装填（生存模式）：用完后等装填时间结束自动补满
	if enable_flare_reload and flares_remaining <= 0:
		if _flare_cooldown > 0.0:
			flare_reload_progress = 1.0 - (_flare_cooldown / params.flare.reload_time)
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
	# 战术机动中不释放热诱弹（机动本身提供免疫）
	var _mf := get_maneuver()
	if _mf and _mf.is_active:
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

	# 失误判定：飞行员未能及时释放热诱弹
	if fp.fail_chance > 0.0:
		var mid := nearest_missile.get_instance_id()
		if _flare_ignored_missiles.has(mid):
			return  # 已判定失误的导弹不再重试
		var actual_fail := fp.fail_chance
		# Lancer 型对头冲刺时更警觉，降低失误率
		if fp.head_on_fail_reduction > 0.0:
			var my_dir := Vector2(sin(heading), -cos(heading))
			var missile_dir := (nearest_missile.global_position - global_position).normalized()
			if my_dir.dot(missile_dir) > 0.5:
				actual_fail = maxf(actual_fail - fp.head_on_fail_reduction, 0.0)
		if randf() < actual_fail:
			_flare_ignored_missiles[mid] = true
			return

	# 释放！只针对触发释放的这枚最近导弹判定干扰
	_release_flares(nearest_missile)

## target_missile：本次释放"瞄准"的那枚来袭导弹。
## 设计约定：一次热诱弹释放只能诱骗一枚导弹（flare 是一次性诱饵），
## 不会连带把同期在飞的其它导弹全部干扰——那样玩家连射两发都会一起失效。
## 这样玩家的第二发导弹仍然保有制导，能继续飞向敌机。
func _release_flares(target_missile: Missile = null) -> void:
	var fp := params.flare
	var count := mini(fp.burst_count, flares_remaining)
	flares_remaining -= count
	# 用完后进入长装填冷却，否则用正常释放间隔
	if flares_remaining <= 0 and enable_flare_reload:
		_flare_cooldown = fp.reload_time
	else:
		_flare_cooldown = fp.cooldown
	EventLogger.log_event("FLARE", _log_name(),
		"deployed %d flares (remaining=%d)" % [count, flares_remaining])

	# 只有玩家（flares_guaranteed）获得 1 秒导弹穿透：
	# 解决已被 jammed 的导弹靠惯性直飞穿过慢速玩家仍然命中的问题
	if flares_guaranteed:
		missile_phase_timer = MISSILE_PHASE_DURATION

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

	# 只对触发释放的这枚导弹判定干扰（一发 flare 一发诱骗）
	if target_missile == null or not is_instance_valid(target_missile):
		return
	if not target_missile.is_active or target_missile.is_flare_jammed:
		return
	if target_missile.target != self:
		return

	var jam_chance: float
	if flares_guaranteed:
		# 后侧方 + 斜前方来袭导弹 100% 干扰，只有接近正面对冲才走概率
		var missile_to_me := (global_position - target_missile.global_position).normalized()
		var my_fwd := Vector2(sin(heading), -cos(heading))
		var dot := my_fwd.dot(missile_to_me)
		# dot > 0 = 导弹从正面来，dot < 0 = 导弹从后方追
		# 阈值 0.6 ≈ 约 ±53° 前方锥外都 100%，只有很正面对冲才看概率
		if dot <= 0.6:
			jam_chance = 1.0
		else:
			jam_chance = _calc_jam_chance(target_missile)  # 正面用普通概率
	else:
		jam_chance = _calc_jam_chance(target_missile)
	if randf() < jam_chance:
		target_missile.is_flare_jammed = true
		var msl_name: String = target_missile.params.display_name if target_missile.params else "MSL"
		EventLogger.log_event("MISSILE", msl_name,
			"flare jammed (target was %s, jam_chance=%.0f%%)" % [
				_log_name(), jam_chance * 100.0])
		# 热诱弹成功干扰时触发一次滚转动画（视觉上"侧身躲避"）
		if _evade_roll_remaining <= 0.0 and _evade_roll_cooldown <= 0.0:
			_evade_roll_remaining = _EVADE_ROLL_DURATION

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
	# 装填中用 reload_time 作分母，否则用 cooldown
	var divisor := params.flare.reload_time if (enable_flare_reload and flares_remaining <= 0) else params.flare.cooldown
	return clampf(_flare_cooldown / divisor, 0.0, 1.0)

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
