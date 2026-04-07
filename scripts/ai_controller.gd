class_name AIController
extends Node

## AI 控制器：巡逻 / 交战（战术机动） / 导弹规避 状态机
## 交战时基于 Shaw《Fighter Combat》BFM 决策树选择战术机动

enum AIState { PATROL, ENGAGE, EVADE_MISSILE }
enum EngageTactic {
	LEAD_PURSUIT,    ## 前置追踪：积极闭合
	LAG_PURSUIT,     ## 滞后追踪：保持后半球不冲过
	LEAD_TURN,       ## 提前转弯：迎头时抢角度
	HIGH_YOYO,       ## 高悠悠：拉高防冲过
	LOW_YOYO,        ## 低悠悠：俯冲加速闭合
	BREAK_TURN,      ## 急转：被咬尾时防御
	EXTENSION,       ## 加速脱离：拉开距离
	SCISSORS,        ## 剪刀机动：近距反复交叉
}

# ── 基础巡逻 ──
@export var aircraft: Aircraft
@export var waypoints: PackedVector2Array = PackedVector2Array()
@export var patrol_altitude: float = 5000.0
@export var arrival_distance: float = 100.0

# ── 战斗 AI ──
@export var enable_combat: bool = false       ## 是否启用战斗AI
@export var aggression: float = 0.5           ## 攻击倾向 (0=被动, 1=激进)
@export var engage_cooldown: float = 15.0     ## 两次交战间隔（秒）
@export var engage_duration: float = 20.0     ## 单次交战最长时间（秒）
@export var evade_missiles: bool = false      ## 是否规避来袭导弹

# ── 飞行员能力 ──
@export var skill_level: float = 0.7          ## 战术水平 (0=菜鸟, 1=王牌)
@export var composure: float = 0.6            ## 冷静度/抗压 (0=易慌, 1=冰冷)

# ── 飞行员性格 ──
@export var focus: float = 0.6               ## 目标专注度 (0=容易分心, 1=死盯不放)
@export var self_preservation: float = 0.5   ## 自保意识 (0=不怕死, 1=保命优先)

# ── 内部状态 ──
var current_waypoint_index: int = 0
var _state: AIState = AIState.PATROL
var _engage_timer: float = 0.0           ## 当前交战已持续时间
var _cooldown_timer: float = 0.0         ## 交战冷却剩余
var _scan_timer: float = 0.0            ## 扫描计时器
var _evade_target_pos: Vector2 = Vector2.INF  ## 规避目标位置
var _current_target: Aircraft = null     ## 当前交战目标

# ── 战术机动状态 ──
var _tactic: EngageTactic = EngageTactic.LEAD_PURSUIT
var _tactic_timer: float = 0.0          ## 当前战术已持续时间
var _tactic_min_duration: float = 0.0   ## 当前战术最小持续时间（防抖动）
var _yoyo_phase: int = 0                ## Yo-Yo 阶段：0=拉高/俯冲, 1=恢复追踪
var _yoyo_base_alt: float = 0.0         ## Yo-Yo 开始时的高度
var _scissors_side: float = 1.0         ## 剪刀机动当前方向（1 或 -1）
var _scissors_reverse_timer: float = 0.0 ## 剪刀反转计时
var _extension_start_pos: Vector2 = Vector2.ZERO ## 脱离起始位置
var _prev_tactic: EngageTactic = EngageTactic.LEAD_PURSUIT ## 上一个战术（用于调试）
var _defensive_time: float = 0.0        ## 持续处于防御态势的累计时间
var _break_phase: int = 0               ## Break Turn 阶段：0=急转, 1=反转迎头
var _target_eval_timer: float = 0.0     ## 交战中目标重评估计时器

# ── 飞行员状态 ──
var _stress: float = 0.0                ## 当前压力值 (0~1)
var _prev_hp: float = -1.0              ## 上一帧 HP，用于检测受伤
var _drift_offset: Vector2 = Vector2.ZERO  ## 漂移噪声偏移（模拟判断失误）
var _drift_timer: float = 0.0           ## 漂移重采样计时器
var _drift_target: Vector2 = Vector2.ZERO  ## 漂移目标（平滑过渡用）
var _speed_error: float = 0.0           ## 当前速度误差系数
var _speed_error_timer: float = 0.0     ## 速度误差重采样计时器
var _alt_error: float = 0.0             ## 高度判断误差（米）

## 当前战术名称（供 DebugPanel 读取）
var current_tactic_name: String = ""
## 当前压力值（供 DebugPanel 读取）
var current_stress: float = 0.0

func _ready() -> void:
	if waypoints.is_empty():
		_generate_default_waypoints()
	if aircraft:
		aircraft.target_altitude = patrol_altitude
		_set_next_waypoint()
	_scan_timer = randf_range(1.0, 3.0)

func _physics_process(delta: float) -> void:
	if not aircraft or aircraft.is_destroyed:
		return

	_update_stress(delta)
	_update_drift(delta)

	match _state:
		AIState.PATROL:
			_process_patrol(delta)
		AIState.ENGAGE:
			_process_engage(delta)
		AIState.EVADE_MISSILE:
			_process_evade(delta)

# ══════════════════════════════════════════════
#  飞行员能力系统
# ══════════════════════════════════════════════

## 有效技能 = 基础技能 × 压力衰减
## composure=1 的飞行员完全不受压力影响
func _effective_skill() -> float:
	return skill_level * (1.0 - _stress * (1.0 - composure))

## 有效自保 = 基线自保 + 压力推升
## 压力越大越想保命，composure 低的人被压力推得更多
## 基线0.2的勇士在压力满时也会被推到~0.7
func _effective_self_preservation() -> float:
	var stress_push := _stress * (1.0 - composure) * 0.6
	return clampf(self_preservation + stress_push, 0.0, 1.0)

## 压力更新：根据战场态势累积/恢复
func _update_stress(delta: float) -> void:
	if _prev_hp < 0.0 and aircraft:
		_prev_hp = aircraft.hp

	var stress_delta := 0.0
	var under_threat := false

	if aircraft:
		# 被雷达锁定
		if aircraft.is_locked:
			stress_delta += 0.04 * delta
			under_threat = true

		# 有来袭导弹
		if evade_missiles and _check_incoming_missile():
			stress_delta += 0.1 * delta
			under_threat = true

		# 受到伤害（HP 下降）——按损失比例施压，而非固定值
		if _prev_hp > 0.0 and aircraft.hp < _prev_hp:
			var damage_ratio := (_prev_hp - aircraft.hp) / aircraft.params.max_hp if aircraft.params else 0.1
			stress_delta += clampf(damage_ratio * 0.5, 0.02, 0.15)
			under_threat = true
		_prev_hp = aircraft.hp

		# 高G持续（>7G）
		if aircraft.g_load > 7.0:
			stress_delta += 0.02 * delta

		# 战斗中持续累积
		if _state == AIState.ENGAGE:
			stress_delta += 0.005 * delta
			under_threat = true

	# 脱离威胁后恢复（比累积快，让飞行员能喘口气）
	if not under_threat:
		stress_delta -= 0.15 * delta

	_stress = clampf(_stress + stress_delta, 0.0, 1.0)
	current_stress = _stress

## 漂移噪声更新：模拟判断失误的缓慢偏移
func _update_drift(delta: float) -> void:
	var eff := _effective_skill()
	var error_magnitude := (1.0 - eff)

	# 位置漂移：每 0.5~2 秒重采样目标
	_drift_timer += delta
	var resample_interval := lerpf(0.5, 2.0, eff)  # 高技能 = 更稳定
	if _drift_timer >= resample_interval:
		_drift_timer = 0.0
		var angle := randf() * TAU
		var magnitude := error_magnitude * 200.0  # 最大偏移 200 像素（菜鸟满压力）
		_drift_target = Vector2(cos(angle), sin(angle)) * magnitude

	# 平滑过渡
	_drift_offset = _drift_offset.lerp(_drift_target, delta * 2.0)

	# 速度误差：每 1~3 秒重采样
	_speed_error_timer += delta
	var speed_resample := lerpf(1.0, 3.0, eff)
	if _speed_error_timer >= speed_resample:
		_speed_error_timer = 0.0
		_speed_error = randf_range(-1.0, 1.0) * error_magnitude * 0.2

	# 高度误差：每次战术切换时重新采样（在 _choose_tactic 中）

## 给目标位置加上漂移偏差
func _apply_position_error(pos: Vector2) -> Vector2:
	return pos + _drift_offset

## 给速度加上误差
func _apply_speed_error(speed_kmh: float) -> float:
	return speed_kmh * (1.0 + _speed_error)

## 给高度加上判断误差
func _apply_altitude_error(alt: float) -> float:
	return alt + _alt_error

# ══════════════════════════════════════════════
#  PATROL — 巡逻（保持原有逻辑）
# ══════════════════════════════════════════════

func _process_patrol(delta: float) -> void:
	if waypoints.is_empty():
		return

	var target_wp := waypoints[current_waypoint_index]
	var dist := aircraft.global_position.distance_to(target_wp)

	if dist < arrival_distance:
		current_waypoint_index = (current_waypoint_index + 1) % waypoints.size()
		_set_next_waypoint()
	else:
		aircraft.target_position = target_wp

	if _cooldown_timer > 0.0:
		_cooldown_timer -= delta

	if evade_missiles and _check_incoming_missile():
		_enter_evade()
		return

	if not enable_combat:
		return

	_scan_timer -= delta
	if _scan_timer <= 0.0:
		_scan_timer = lerpf(3.0, 1.0, aggression)
		_try_engage()

# ══════════════════════════════════════════════
#  ENGAGE — 交战（战术机动决策树）
# ══════════════════════════════════════════════

func _process_engage(delta: float) -> void:
	_engage_timer += delta
	_tactic_timer += delta
	_target_eval_timer += delta

	# 累积防御态势时间
	if _tactic in [EngageTactic.BREAK_TURN, EngageTactic.EXTENSION, EngageTactic.SCISSORS]:
		_defensive_time += delta
	else:
		_defensive_time = maxf(_defensive_time - delta * 0.5, 0.0)

	# ── 导弹规避（受 self_preservation 影响） ──
	if evade_missiles and _check_incoming_missile():
		# 低自保飞行员可能忽略来袭导弹继续攻击
		var evade_chance := lerpf(0.3, 1.0, _effective_self_preservation())
		if randf() < evade_chance or _state != AIState.ENGAGE:
			_disengage()
			_enter_evade()
			return

	# ── 被锁定警觉（高自保飞行员主动脱离） ──
	var _esp := _effective_self_preservation()
	if aircraft and aircraft.is_locked and _esp > 0.7:
		# 高自保 + 被锁定 → 如果不在防御战术中，立即切防御
		if _tactic not in [EngageTactic.BREAK_TURN, EngageTactic.EXTENSION, EngageTactic.SCISSORS]:
			var defense_chance := (_esp - 0.5) * 0.1
			if randf() < defense_chance:
				_tactic_timer = _tactic_min_duration  # 强制允许战术切换

	# 目标有效性检查
	if not _current_target or not is_instance_valid(_current_target) or _current_target.is_destroyed:
		_disengage()
		return

	# 超出范围脱离
	if aircraft.params:
		var max_range := aircraft.params.radar_range * 1.5
		var dist := aircraft.global_position.distance_to(_current_target.global_position)
		if dist > max_range:
			_disengage()
			return

	# 交战时间限制
	if _engage_timer > engage_duration:
		_disengage()
		return

	# ── 交战中目标重评估（受 focus 影响） ──
	var eval_interval := lerpf(3.0, 10.0, focus)  # 低专注=3秒重评，高专注=10秒
	if _target_eval_timer >= eval_interval:
		_target_eval_timer = 0.0
		_reevaluate_target()

	# ── 态势评估 ──
	var sit := _assess_situation()

	# ── 战术选择（带最小持续时间防抖） ──
	if _tactic_timer >= _tactic_min_duration:
		_choose_tactic(sit)

	# ── 执行当前战术 ──
	aircraft.ai_override_pursuit = true
	match _tactic:
		EngageTactic.LEAD_PURSUIT:
			_execute_lead_pursuit(sit)
		EngageTactic.LAG_PURSUIT:
			_execute_lag_pursuit(sit)
		EngageTactic.LEAD_TURN:
			_execute_lead_turn(sit)
		EngageTactic.HIGH_YOYO:
			_execute_high_yoyo(sit, delta)
		EngageTactic.LOW_YOYO:
			_execute_low_yoyo(sit, delta)
		EngageTactic.BREAK_TURN:
			_execute_break_turn(sit)
		EngageTactic.EXTENSION:
			_execute_extension(sit)
		EngageTactic.SCISSORS:
			_execute_scissors(sit, delta)

	# 更新战术名称（附带压力和技能信息）
	current_tactic_name = EngageTactic.keys()[_tactic]

# ══════════════════════════════════════════════
#  态势评估
# ══════════════════════════════════════════════

class SituationData:
	var dist_px: float          ## 距离（像素）
	var aspect_angle: float     ## 我在敌机的偏置角（0=正后方, PI=正前方）
	var my_aot: float           ## 敌机在我的攻击角（0=正前方, PI=正后方）
	var closing_rate: float     ## 闭合率（正=接近）
	var my_speed: float         ## 我的速度 m/s
	var tgt_speed: float        ## 敌机速度 m/s
	var speed_ratio: float      ## 速度比 我/敌
	var alt_diff: float         ## 高度差（正=我更高）
	var in_rear_hemi: bool      ## 我在敌机后半球
	var enemy_in_my_rear: bool  ## 敌机在我的后半球
	var tgt_pos: Vector2
	var tgt_fwd: Vector2
	var my_pos: Vector2
	var my_fwd: Vector2
	var to_target: Vector2      ## 归一化方向
	var gun_range_px: float
	var is_head_on: bool        ## 迎头接近

func _assess_situation() -> SituationData:
	var s := SituationData.new()
	s.my_pos = aircraft.global_position
	s.tgt_pos = _current_target.global_position
	s.dist_px = s.my_pos.distance_to(s.tgt_pos)
	s.to_target = (s.tgt_pos - s.my_pos).normalized()

	s.tgt_fwd = Vector2(sin(_current_target.heading), -cos(_current_target.heading))
	s.my_fwd = Vector2(sin(aircraft.heading), -cos(aircraft.heading))

	s.my_speed = aircraft.speed
	s.tgt_speed = _current_target.speed
	s.speed_ratio = s.my_speed / maxf(s.tgt_speed, 1.0)

	var my_speed_px := s.my_speed * Aircraft.PIXELS_PER_METER
	var tgt_speed_px := s.tgt_speed * Aircraft.PIXELS_PER_METER

	# 闭合率
	s.closing_rate = s.my_fwd.dot(s.to_target) * my_speed_px - s.tgt_fwd.dot(s.to_target) * tgt_speed_px

	# 我在敌机的偏置角（aspect angle）
	var to_me := (s.my_pos - s.tgt_pos).normalized()
	s.aspect_angle = acos(clampf(-s.tgt_fwd.dot(to_me), -1.0, 1.0))
	s.in_rear_hemi = s.aspect_angle < deg_to_rad(90.0)

	# 敌机在我的攻击角（AOT）
	var to_enemy := (s.tgt_pos - s.my_pos).normalized()
	s.my_aot = acos(clampf(s.my_fwd.dot(to_enemy), -1.0, 1.0))

	# 敌机是否在我的后半球
	s.enemy_in_my_rear = s.my_aot > deg_to_rad(90.0)

	# 高度差
	s.alt_diff = aircraft.altitude - _current_target.altitude

	# 机炮射程
	s.gun_range_px = 150.0
	if aircraft.params and aircraft.params.gun:
		s.gun_range_px = aircraft.params.gun.max_range * Aircraft.PIXELS_PER_METER

	# 迎头判定：双方都面朝对方（aspect > 120° 且 my_aot < 60°）
	s.is_head_on = s.aspect_angle > deg_to_rad(120.0) and s.my_aot < deg_to_rad(60.0) and s.closing_rate > 0

	return s

# ══════════════════════════════════════════════
#  战术选择决策树
# ══════════════════════════════════════════════

func _choose_tactic(s: SituationData) -> void:
	var new_tactic := _tactic
	var close_range := s.gun_range_px * 2.0
	var mid_range := s.gun_range_px * 5.0
	var aggression_factor := aggression  # 0~1

	var esp := _effective_self_preservation()

	# ── 0. 高自保 + 被锁定：即使没被咬尾也可能切防御 ──
	if aircraft.is_locked and esp > 0.6 and not s.enemy_in_my_rear:
		if esp > 0.85:
			new_tactic = EngageTactic.EXTENSION
		elif esp > 0.7:
			new_tactic = EngageTactic.BREAK_TURN

	# ── 1. 被咬尾检测（敌机在我后半球 + 距离近） ──
	elif s.enemy_in_my_rear and s.dist_px < mid_range:
		# 低自保飞行员被咬尾也可能反转迎头
		if esp < 0.3 and s.dist_px > close_range:
			new_tactic = EngageTactic.LEAD_TURN
		elif aircraft.hp < aircraft.params.max_hp * 0.4 or s.speed_ratio < 0.8:
			new_tactic = EngageTactic.EXTENSION
		elif _defensive_time > 5.0:
			if aggression_factor > 0.4 and esp < 0.6:
				new_tactic = EngageTactic.LEAD_TURN
				_defensive_time = 0.0
			else:
				new_tactic = EngageTactic.EXTENSION
				_defensive_time = 0.0
		elif s.dist_px < close_range and s.my_speed < 200.0 and s.tgt_speed < 200.0:
			new_tactic = EngageTactic.SCISSORS
		else:
			# 急转防御
			new_tactic = EngageTactic.BREAK_TURN

	# ── 2. 迎头接近 ──
	elif s.is_head_on:
		new_tactic = EngageTactic.LEAD_TURN

	# ── 3. 我在敌后半球（进攻位置） ──
	elif s.in_rear_hemi:
		if s.closing_rate > 80.0 and s.dist_px < close_range:
			# 闭合率过高 + 近距 → 高悠悠防冲过
			new_tactic = EngageTactic.HIGH_YOYO
		elif s.closing_rate > 50.0 and s.dist_px < mid_range and s.speed_ratio > 1.1:
			# 闭合但速度优势明显 → 滞后追踪
			new_tactic = EngageTactic.LAG_PURSUIT
		elif s.dist_px > mid_range and s.closing_rate < 20.0:
			# 远距离 + 闭合慢 → 低悠悠加速
			new_tactic = EngageTactic.LOW_YOYO
		else:
			# 正常追踪
			new_tactic = EngageTactic.LEAD_PURSUIT

	# ── 4. 侧面/其他位置 ──
	else:
		if s.dist_px > mid_range:
			new_tactic = EngageTactic.LEAD_PURSUIT
		elif s.dist_px < close_range and s.closing_rate > 60.0:
			new_tactic = EngageTactic.HIGH_YOYO
		elif s.dist_px > mid_range * 0.7 and s.closing_rate < 10.0:
			new_tactic = EngageTactic.LOW_YOYO
		else:
			new_tactic = EngageTactic.LEAD_PURSUIT

	# 激进度调整：激进 AI 更倾向进攻战术
	if aggression_factor > 0.7:
		if new_tactic == EngageTactic.EXTENSION and aircraft.hp > aircraft.params.max_hp * 0.25:
			new_tactic = EngageTactic.BREAK_TURN

	# ── 决策失误：有概率选到次优战术 ──
	var eff := _effective_skill()
	var mistake_chance := (1.0 - eff) * 0.15  # 最高 15% 失误率
	if randf() < mistake_chance and new_tactic != _tactic:
		new_tactic = _make_mistake(new_tactic)

	# 只在战术实际变化时重置
	if new_tactic != _tactic:
		_prev_tactic = _tactic
		_tactic = new_tactic
		_tactic_timer = 0.0
		_yoyo_phase = 0

		# 设置最小持续时间（低技能 = 反应迟钝，持续时间更长）
		var reaction_mult := 1.0 + (1.0 - eff) * 1.0  # 菜鸟 ×2.0, 王牌 ×1.05
		match _tactic:
			EngageTactic.LEAD_PURSUIT:
				_tactic_min_duration = 0.5 * reaction_mult
			EngageTactic.LAG_PURSUIT:
				_tactic_min_duration = 1.0 * reaction_mult
			EngageTactic.LEAD_TURN:
				_tactic_min_duration = 1.5 * reaction_mult
			EngageTactic.HIGH_YOYO:
				_tactic_min_duration = 2.0 * reaction_mult
				_yoyo_base_alt = aircraft.altitude
			EngageTactic.LOW_YOYO:
				_tactic_min_duration = 2.0 * reaction_mult
				_yoyo_base_alt = aircraft.altitude
			EngageTactic.BREAK_TURN:
				_tactic_min_duration = 1.5 * reaction_mult
				_break_phase = 0
			EngageTactic.EXTENSION:
				_tactic_min_duration = 3.0 * reaction_mult
				_extension_start_pos = aircraft.global_position
			EngageTactic.SCISSORS:
				_tactic_min_duration = 1.0 * reaction_mult
				_scissors_side = 1.0
				_scissors_reverse_timer = 0.0

		# 每次切换战术时重新采样高度误差
		_alt_error = randf_range(-1.0, 1.0) * (1.0 - eff) * 500.0

## 决策失误：返回一个"次优"战术替代正确选择
func _make_mistake(correct: EngageTactic) -> EngageTactic:
	# 每种正确战术对应的常见失误
	match correct:
		EngageTactic.HIGH_YOYO:
			# 该防冲过时继续追 → 冲过
			return EngageTactic.LEAD_PURSUIT
		EngageTactic.LAG_PURSUIT:
			# 该控制节奏时莽冲
			return EngageTactic.LEAD_PURSUIT
		EngageTactic.LOW_YOYO:
			# 该加速闭合时选了保守跟踪
			return EngageTactic.LAG_PURSUIT
		EngageTactic.BREAK_TURN:
			# 该急转时慌了选剪刀（犹豫不决）
			return EngageTactic.SCISSORS if randf() > 0.5 else EngageTactic.EXTENSION
		EngageTactic.EXTENSION:
			# 该跑时却转向（不甘心）
			return EngageTactic.BREAK_TURN
		EngageTactic.LEAD_TURN:
			# 该提前转时直冲（没有战术意识）
			return EngageTactic.LEAD_PURSUIT
		EngageTactic.SCISSORS:
			# 该剪刀时选了脱离（太慌张）
			return EngageTactic.EXTENSION
		_:
			return correct

# ══════════════════════════════════════════════
#  战术执行
# ══════════════════════════════════════════════

## 前置追踪：瞄准敌机前方，积极闭合距离
func _execute_lead_pursuit(s: SituationData) -> void:
	var my_speed_px := s.my_speed * Aircraft.PIXELS_PER_METER
	var tgt_speed_px := s.tgt_speed * Aircraft.PIXELS_PER_METER

	var lead_time := clampf(s.dist_px / maxf(my_speed_px, 50.0), 0.3, 3.0)
	var pursuit_pos := s.tgt_pos + s.tgt_fwd * tgt_speed_px * lead_time

	aircraft.target_position = _apply_position_error(pursuit_pos)
	aircraft.target_altitude = _current_target.altitude
	_set_engage_speed(s, 1.2)

## 滞后追踪：瞄准敌机后方，防止冲过，保持后半球位置
func _execute_lag_pursuit(s: SituationData) -> void:
	var lag_offset := maxf(80.0, s.gun_range_px * 0.4)
	var pursuit_pos := s.tgt_pos - s.tgt_fwd * lag_offset

	aircraft.target_position = _apply_position_error(pursuit_pos)
	aircraft.target_altitude = _current_target.altitude

	# 匹配敌机速度，略低以防冲过
	var target_speed_kmh := _current_target.speed * 3.6 * 0.95
	aircraft.target_speed_kmh = _apply_speed_error(clampf(target_speed_kmh, 400.0, aircraft.params.max_speed if aircraft.params else 2000.0))

## 提前转弯：迎头接近时提前转向敌机飞行路径后方
func _execute_lead_turn(s: SituationData) -> void:
	var tgt_speed_px := s.tgt_speed * Aircraft.PIXELS_PER_METER

	var pass_time := s.dist_px / maxf(s.closing_rate + 50.0, 100.0)
	var future_tgt_pos := s.tgt_pos + s.tgt_fwd * tgt_speed_px * pass_time
	var six_pos := future_tgt_pos - s.tgt_fwd * maxf(100.0, s.gun_range_px * 0.5)

	aircraft.target_position = _apply_position_error(six_pos)
	aircraft.target_altitude = _current_target.altitude
	_set_engage_speed(s, 1.0)

## 高悠悠：拉高减速防止冲过，然后俯冲回来继续追踪
func _execute_high_yoyo(s: SituationData, delta: float) -> void:
	if _yoyo_phase == 0:
		# 阶段0：拉高（高度受技能影响：菜鸟可能拉太高或太低）
		var climb_target := _yoyo_base_alt + _apply_altitude_error(1000.0)
		if aircraft.params:
			climb_target = clampf(climb_target, _yoyo_base_alt + 300.0, aircraft.params.max_altitude - 500.0)
		aircraft.target_altitude = climb_target

		var lag_pos := s.tgt_pos - s.tgt_fwd * s.gun_range_px * 0.6
		aircraft.target_position = _apply_position_error(lag_pos)

		aircraft.target_speed_kmh = _apply_speed_error(_current_target.speed * 3.6 * 0.85)

		if aircraft.altitude >= climb_target - 100.0 or _tactic_timer > 4.0:
			_yoyo_phase = 1
	else:
		# 阶段1：俯冲回来
		aircraft.target_altitude = _current_target.altitude
		var my_speed_px := s.my_speed * Aircraft.PIXELS_PER_METER
		var tgt_speed_px := s.tgt_speed * Aircraft.PIXELS_PER_METER
		var lead_time := clampf(s.dist_px / maxf(my_speed_px, 50.0), 0.3, 2.0)
		aircraft.target_position = _apply_position_error(s.tgt_pos + s.tgt_fwd * tgt_speed_px * lead_time)
		_set_engage_speed(s, 1.1)

		if absf(aircraft.altitude - _current_target.altitude) < 200.0:
			_tactic_timer = _tactic_min_duration

## 低悠悠：俯冲加速缩短距离，再拉高攻击
func _execute_low_yoyo(s: SituationData, delta: float) -> void:
	if _yoyo_phase == 0:
		# 阶段0：俯冲加速（深度受技能影响）
		var dive_target := _yoyo_base_alt - _apply_altitude_error(800.0)
		if aircraft.params:
			dive_target = clampf(dive_target, 1500.0, _yoyo_base_alt - 200.0)
		aircraft.target_altitude = dive_target

		var my_speed_px := s.my_speed * Aircraft.PIXELS_PER_METER
		var tgt_speed_px := s.tgt_speed * Aircraft.PIXELS_PER_METER
		var lead_time := clampf(s.dist_px / maxf(my_speed_px, 50.0), 0.5, 3.0)
		aircraft.target_position = _apply_position_error(s.tgt_pos + s.tgt_fwd * tgt_speed_px * lead_time)

		_set_engage_speed(s, 1.4)

		if aircraft.altitude <= dive_target + 100.0 or _tactic_timer > 4.0:
			_yoyo_phase = 1
	else:
		# 阶段1：拉高回到敌机高度
		aircraft.target_altitude = _current_target.altitude
		var my_speed_px := s.my_speed * Aircraft.PIXELS_PER_METER
		var tgt_speed_px := s.tgt_speed * Aircraft.PIXELS_PER_METER
		var lead_time := clampf(s.dist_px / maxf(my_speed_px, 50.0), 0.3, 2.0)
		aircraft.target_position = _apply_position_error(s.tgt_pos + s.tgt_fwd * tgt_speed_px * lead_time)
		_set_engage_speed(s, 1.1)

		if absf(aircraft.altitude - _current_target.altitude) < 200.0:
			_tactic_timer = _tactic_min_duration

## 急转脱离：被咬尾时急转增大偏置角，然后反转迎头
## Shaw 原则：Break Turn 是初始防御，之后必须反转或脱离，不能一直平转
func _execute_break_turn(s: SituationData) -> void:
	if _break_phase == 0 and _tactic_timer < 2.0:
		# 阶段0（前2秒）：急转垂直于威胁方向，建立偏置角
		var threat_dir := (aircraft.global_position - s.tgt_pos).normalized()
		var perp_a := Vector2(threat_dir.y, -threat_dir.x)
		var perp_b := Vector2(-threat_dir.y, threat_dir.x)

		var heading_a := atan2(perp_a.x, -perp_a.y)
		var heading_b := atan2(perp_b.x, -perp_b.y)
		var diff_a := absf(_angle_diff(heading_a, aircraft.heading))
		var diff_b := absf(_angle_diff(heading_b, aircraft.heading))
		var chosen_dir := perp_a if diff_a < diff_b else perp_b

		aircraft.target_position = _apply_position_error(aircraft.global_position + chosen_dir * 1500.0)

		if aircraft.altitude > 3000.0:
			aircraft.target_altitude = aircraft.altitude - 300.0
		else:
			aircraft.target_altitude = aircraft.altitude

		_set_engage_speed(s, 1.0)
	else:
		# 阶段1（2秒后）：反转迎头
		_break_phase = 1
		var tgt_speed_px := s.tgt_speed * Aircraft.PIXELS_PER_METER
		aircraft.target_position = _apply_position_error(s.tgt_pos + s.tgt_fwd * tgt_speed_px * 0.5)
		aircraft.target_altitude = _current_target.altitude
		_set_engage_speed(s, 1.3)

## 加速脱离：远离敌机拉开距离
func _execute_extension(s: SituationData) -> void:
	var away_dir := (aircraft.global_position - s.tgt_pos).normalized()
	# 低技能飞行员脱离方向可能有偏差
	aircraft.target_position = _apply_position_error(aircraft.global_position + away_dir * 2000.0)

	if aircraft.params:
		aircraft.target_speed_kmh = _apply_speed_error(aircraft.params.max_speed * 0.9)
	else:
		aircraft.target_speed_kmh = _apply_speed_error(1800.0)

	aircraft.target_altitude = aircraft.altitude + 200.0

	var separation := aircraft.global_position.distance_to(_extension_start_pos)
	if separation > 800.0 and s.dist_px > s.gun_range_px * 4.0:
		_tactic_timer = _tactic_min_duration

## 剪刀机动：近距反复交叉反转，利用低速优势抢位
func _execute_scissors(s: SituationData, delta: float) -> void:
	_scissors_reverse_timer += delta

	# 剪刀反转间隔（根据距离和速度调整）
	var reverse_interval := clampf(s.dist_px / maxf(s.my_speed * Aircraft.PIXELS_PER_METER, 30.0), 0.8, 2.5)

	if _scissors_reverse_timer >= reverse_interval:
		_scissors_side *= -1.0
		_scissors_reverse_timer = 0.0

	# 计算交叉方向：垂直于我与敌机连线
	var to_tgt_dir := s.to_target
	var cross_dir := Vector2(to_tgt_dir.y, -to_tgt_dir.x) * _scissors_side

	# 目标位置：侧向偏移 + 略微朝向敌机
	var scissors_pos := aircraft.global_position + cross_dir * 300.0 + to_tgt_dir * 50.0
	aircraft.target_position = _apply_position_error(scissors_pos)

	# 减速！剪刀机动中低速优势是关键（低技能飞行员可能减速不够）
	if aircraft.params:
		var min_safe_speed := aircraft.params.stall_speed_base * 1.3
		aircraft.target_speed_kmh = _apply_speed_error(min_safe_speed)
	else:
		aircraft.target_speed_kmh = _apply_speed_error(400.0)

	aircraft.target_altitude = _current_target.altitude

# ══════════════════════════════════════════════
#  速度管理辅助
# ══════════════════════════════════════════════

func _set_engage_speed(s: SituationData, mult: float) -> void:
	if not aircraft.params:
		aircraft.target_speed_kmh = _apply_speed_error(900.0 * mult)
		return
	var cruise := aircraft.params.cruise_speed
	var target := clampf(cruise * mult, aircraft.params.stall_speed_base * 1.2, aircraft.params.max_speed)
	aircraft.target_speed_kmh = _apply_speed_error(target)

# ══════════════════════════════════════════════
#  EVADE_MISSILE — 导弹规避（保持原有逻辑）
# ══════════════════════════════════════════════

func _process_evade(delta: float) -> void:
	var missile := _find_nearest_incoming_missile()
	if not missile:
		_exit_evade()
		return

	var missile_dir := (aircraft.global_position - missile.global_position).normalized()
	var evade_dir := Vector2(missile_dir.y, -missile_dir.x)

	var evade_heading_a := atan2(evade_dir.x, -evade_dir.y)
	var evade_heading_b := atan2(-evade_dir.x, evade_dir.y)
	var diff_a := absf(_angle_diff(evade_heading_a, aircraft.heading))
	var diff_b := absf(_angle_diff(evade_heading_b, aircraft.heading))
	var chosen_dir := evade_dir if diff_a < diff_b else -evade_dir

	_evade_target_pos = aircraft.global_position + chosen_dir * 2000.0
	aircraft.target_position = _evade_target_pos

	if aircraft.combat_target:
		aircraft.clear_combat_target()

	var alt_change := 1500.0 if aircraft.altitude < 6000.0 else -1500.0
	aircraft.target_altitude = aircraft.altitude + alt_change

func _enter_evade() -> void:
	_state = AIState.EVADE_MISSILE
	aircraft.ai_override_pursuit = false
	if aircraft.combat_target:
		aircraft.clear_combat_target()

func _exit_evade() -> void:
	aircraft.target_altitude = patrol_altitude
	if _current_target and is_instance_valid(_current_target) and not _current_target.is_destroyed:
		aircraft.set_combat_target(_current_target)
		_state = AIState.ENGAGE
		_tactic_timer = 0.0
	else:
		_current_target = null
		_state = AIState.PATROL
		aircraft.ai_override_pursuit = false
		_set_next_waypoint()

# ══════════════════════════════════════════════
#  交战管理
# ══════════════════════════════════════════════

func _try_engage() -> void:
	if _cooldown_timer > 0.0:
		return

	var best_target: Aircraft = null
	var best_score := -1.0
	var current_target_score := -1.0

	for target_key in aircraft.radar_targets:
		if not is_instance_valid(target_key):
			continue
		var target_ac: Aircraft = target_key
		if target_ac.is_destroyed or target_ac.team == aircraft.team:
			continue

		var lock_progress: float = aircraft.radar_targets[target_key]
		var lock_time: float = aircraft.params.lock_time if aircraft.params else 3.0

		var dist := aircraft.global_position.distance_to(target_ac.global_position)
		var dist_score := 1.0 / maxf(dist, 100.0) * 1000.0
		var lock_score := lock_progress / lock_time
		var score := lock_score * 2.0 + dist_score

		# 目标粘性：当前目标获得专注度加成
		if target_ac == _current_target:
			score += focus * 5.0
			current_target_score = score

		var min_lock_ratio := lerpf(1.0, 0.3, aggression)
		if lock_score < min_lock_ratio:
			continue

		if score > best_score:
			best_score = score
			best_target = target_ac

	if best_target:
		# 切换目标需要超越当前目标的粘性阈值
		if _current_target and is_instance_valid(_current_target) and not _current_target.is_destroyed:
			if best_target != _current_target and current_target_score > 0.0:
				var switch_threshold := focus * 2.0
				if best_score < current_target_score + switch_threshold:
					return  # 新目标不够优，维持当前目标

		_current_target = best_target
		aircraft.set_combat_target(best_target)
		_state = AIState.ENGAGE
		_engage_timer = 0.0
		_tactic = EngageTactic.LEAD_PURSUIT
		_tactic_timer = 0.0
		_tactic_min_duration = 0.5
		_target_eval_timer = 0.0
		aircraft.ai_override_pursuit = true

## 交战中重评估目标（受 focus 影响）
func _reevaluate_target() -> void:
	var best_target: Aircraft = null
	var best_score := -1.0
	var current_score := -1.0

	for target_key in aircraft.radar_targets:
		if not is_instance_valid(target_key):
			continue
		var target_ac: Aircraft = target_key
		if target_ac.is_destroyed or target_ac.team == aircraft.team:
			continue

		var lock_progress: float = aircraft.radar_targets[target_key]
		var lock_time: float = aircraft.params.lock_time if aircraft.params else 3.0

		var dist := aircraft.global_position.distance_to(target_ac.global_position)
		var dist_score := 1.0 / maxf(dist, 100.0) * 1000.0
		var lock_score := lock_progress / lock_time
		var score := lock_score * 2.0 + dist_score

		# 当前目标获得专注度粘性加成
		if target_ac == _current_target:
			score += focus * 5.0
			current_score = score

		if score > best_score:
			best_score = score
			best_target = target_ac

	if not best_target or best_target == _current_target:
		return

	# 必须显著优于当前目标才切换
	var switch_threshold := focus * 3.0
	if current_score > 0.0 and best_score < current_score + switch_threshold:
		return

	# 切换目标
	_current_target = best_target
	aircraft.set_combat_target(best_target)
	_tactic_timer = 0.0
	_yoyo_phase = 0

func _disengage() -> void:
	aircraft.clear_combat_target()
	aircraft.ai_override_pursuit = false
	_current_target = null
	_state = AIState.PATROL
	_cooldown_timer = engage_cooldown
	aircraft.target_altitude = patrol_altitude
	current_tactic_name = ""
	_set_next_waypoint()

# ══════════════════════════════════════════════
#  导弹威胁检测
# ══════════════════════════════════════════════

func _check_incoming_missile() -> bool:
	return _find_nearest_incoming_missile() != null

func _find_nearest_incoming_missile() -> Missile:
	var missile_manager := _get_missile_manager()
	if not missile_manager:
		return null

	var nearest: Missile = null
	var nearest_dist := 99999.0

	for child in missile_manager.get_children():
		if not child is Missile:
			continue
		var m: Missile = child
		if not m.is_active:
			continue
		if m.target != aircraft:
			continue
		var dist := m.global_position.distance_to(aircraft.global_position)
		if dist < nearest_dist:
			nearest_dist = dist
			nearest = m

	return nearest

func _get_missile_manager() -> MissileManager:
	var root := aircraft.get_parent()
	if not root:
		return null
	for child in root.get_children():
		if child is MissileManager:
			return child
	return null

# ══════════════════════════════════════════════
#  工具函数
# ══════════════════════════════════════════════

func _set_next_waypoint() -> void:
	if waypoints.is_empty():
		return
	aircraft.target_position = waypoints[current_waypoint_index]

func _generate_default_waypoints() -> void:
	var center := aircraft.global_position if aircraft else Vector2.ZERO
	var radius := 500.0
	waypoints = PackedVector2Array([
		center + Vector2(radius, -radius),
		center + Vector2(radius, radius),
		center + Vector2(-radius, radius),
		center + Vector2(-radius, -radius),
	])

static func _angle_diff(a: float, b: float) -> float:
	var d := fmod(a - b + PI, TAU)
	if d < 0:
		d += TAU
	return d - PI
