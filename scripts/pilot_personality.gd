class_name PilotPersonality
extends RefCounted

## 飞行员心理/性格系统
## 从 ai_controller.gd 提取：压力/态势感知/判断误差
## 性格特征（skill_level/composure/focus 等 @export）保留在 AIController，
## 由 survivor_spawner 设置；本类仅负责**派生状态**与**更新逻辑**。

# ── 压力 ──
var stress: float = 0.0                   ## 当前压力值 (0~1)
var prev_hp: float = -1.0                 ## 上一帧 HP，用于检测受伤

# ── 判断误差状态 ──
var drift_offset: Vector2 = Vector2.ZERO  ## 漂移噪声偏移（模拟判断失误）
var drift_timer: float = 0.0              ## 漂移重采样计时器
var drift_target: Vector2 = Vector2.ZERO  ## 漂移目标（平滑过渡用）
var speed_error: float = 0.0              ## 当前速度误差系数
var speed_error_timer: float = 0.0        ## 速度误差重采样计时器
var alt_error: float = 0.0                ## 高度判断误差（米）

# ── 态势感知内部状态 ──
var sa_check_timer: float = 0.0           ## 下次"检查六点钟"计时
var rear_threat_aware: bool = false        ## 当前是否意识到后方威胁
var lock_aware: bool = false               ## 当前是否意识到被锁定
var sa_lock_delay: float = 0.0            ## 锁定告警意识延迟剩余
var missile_aware: bool = false            ## 当前是否意识到来袭导弹
var sa_missile_delay: float = 0.0         ## 导弹来袭意识延迟剩余
var sa_threats_known: int = 0              ## 感知到的威胁数量（不一定等于实际数量）

# ── Debug 面板读取 ──
var current_stress: float = 0.0
var current_sa_level: float = 0.0

# ══════════════════════════════════════════════
#  能力派生：受压力/耐力影响的有效值
# ══════════════════════════════════════════════

## 有效技能 = 基础技能 × 压力衰减
## composure=1 的飞行员完全不受压力影响
func effective_skill(skill_level: float, composure: float) -> float:
	return skill_level * (1.0 - stress * (1.0 - composure))

## 有效自保 = 基线自保 + 压力推升
## 压力越大越想保命，composure 低的人被压力推得更多
## 基线0.2的勇士在压力满时也会被推到~0.7
func effective_self_preservation(self_preservation: float, composure: float) -> float:
	var stress_push := stress * (1.0 - composure) * 0.6
	return clampf(self_preservation + stress_push, 0.0, 1.0)

## 有效态势感知 = 基础SA × 压力衰减 × 疲劳衰减
## 压力大、耐力低的飞行员视野变窄
func effective_sa(situational_awareness: float, composure: float, aircraft: Aircraft) -> float:
	var stress_penalty := stress * (1.0 - composure) * 0.4
	var stamina_penalty := 0.0
	if aircraft and aircraft.pilot_stamina < 50.0:
		stamina_penalty = (1.0 - aircraft.pilot_stamina / 50.0) * 0.2
	var sa := situational_awareness * (1.0 - stress_penalty - stamina_penalty)
	current_sa_level = clampf(sa, 0.05, 1.0)
	return current_sa_level

## 导弹感知距离：低SA飞行员只有导弹非常近时才注意到
func missile_aware_range(situational_awareness: float, composure: float, aircraft: Aircraft) -> float:
	var esa := effective_sa(situational_awareness, composure, aircraft)
	return lerpf(300.0, 1200.0, esa)  # 300px（近身才发现） ~ 1200px（远距离就察觉）

# ══════════════════════════════════════════════
#  每帧更新
# ══════════════════════════════════════════════

## 态势感知更新：周期性"检查六点钟"
## 高SA飞行员频繁扫视四周，低SA飞行员只盯着前方
## ai 参数用于读取当前战术状态（追踪时专注度更高）和检测来袭导弹
func update_situational_awareness(ai: AIController, delta: float) -> void:
	var aircraft := ai.aircraft
	var esa := effective_sa(ai.situational_awareness, ai.composure, aircraft)

	# ── 后方威胁感知（"检查六点钟"周期） ──
	sa_check_timer -= delta
	if sa_check_timer <= 0.0:
		# 检查间隔：王牌1.5秒一次，菜鸟5秒一次
		sa_check_timer = lerpf(5.0, 1.5, esa)
		# 检查成功率：高SA几乎不会遗漏，低SA经常检查失败
		var check_success_chance := 0.3 + esa * 0.7  # 最低30%，最高100%
		if ai._state == AIController.AIState.ENGAGE and ai._tactic in [AIController.EngageTactic.LEAD_PURSUIT, AIController.EngageTactic.LEAD_TURN]:
			# 专注追踪时更容易忽略后方
			check_success_chance *= 0.7
		rear_threat_aware = randf() < check_success_chance

	# ── 锁定告警感知 ──
	if aircraft and aircraft.is_locked:
		if not lock_aware:
			sa_lock_delay -= delta
			if sa_lock_delay <= 0.0:
				lock_aware = true
		# 锁定告警反应延迟：高SA几乎立即反应，低SA需要1~3秒
	else:
		lock_aware = false
		sa_lock_delay = lerpf(3.0, 0.2, esa)

	# ── 导弹来袭感知 ──
	var actual_missile := MissileEvasion.find_nearest_incoming_missile(ai)
	if actual_missile:
		if not missile_aware:
			sa_missile_delay -= delta
			if sa_missile_delay <= 0.0:
				missile_aware = true
			# 导弹从后方来时更难察觉
			elif actual_missile.global_position.distance_to(aircraft.global_position) < missile_aware_range(ai.situational_awareness, ai.composure, aircraft):
				missile_aware = true  # 足够近时任何人都能察觉
	else:
		missile_aware = false
		sa_missile_delay = lerpf(2.5, 0.3, esa)

	# ── 感知到的威胁数量（低SA飞行员可能漏数） ──
	var actual_threats := 0
	if aircraft:
		for target_key in aircraft.radar_targets:
			if is_instance_valid(target_key):
				var t: CombatUnit = target_key
				if not t.is_destroyed and t.team != aircraft.team:
					actual_threats += 1
	# 高SA感知全部，低SA可能少算（只关注眼前那个）
	var perceive_ratio := 0.5 + esa * 0.5
	sa_threats_known = ceili(actual_threats * perceive_ratio)

## 压力更新：根据战场态势累积/恢复
func update_stress(ai: AIController, delta: float) -> void:
	var aircraft := ai.aircraft
	if prev_hp < 0.0 and aircraft:
		prev_hp = aircraft.hp
	# 生存模式：禁用压力系统（敌机不会因压力崩溃/降低技能）
	if aircraft and aircraft.flat_altitude:
		stress = 0.0
		current_stress = 0.0
		return

	var stress_delta := 0.0
	var under_threat := false

	if aircraft:
		# 被雷达锁定（需要飞行员意识到才产生压力）
		if lock_aware:
			stress_delta += 0.04 * delta
			under_threat = true

		# 有来袭导弹（需要飞行员察觉到才产生压力）
		if ai.evade_missiles and missile_aware:
			stress_delta += 0.1 * delta
			under_threat = true

		# 受到伤害（HP 下降）——按损失比例施压，而非固定值
		# 挨打是最直接的态势感知来源——再迟钝的飞行员也会因疼痛惊醒
		if prev_hp > 0.0 and aircraft.hp < prev_hp:
			var damage_ratio := (prev_hp - aircraft.hp) / aircraft.params.max_hp if aircraft.params else 0.1
			stress_delta += clampf(damage_ratio * 0.5, 0.02, 0.15)
			under_threat = true
			# 受伤强制唤醒态势感知
			rear_threat_aware = true
			lock_aware = aircraft.is_locked
			missile_aware = MissileEvasion.check_incoming_missile(ai)
		prev_hp = aircraft.hp

		# 高G持续（>7G）
		if aircraft.g_load > 7.0:
			stress_delta += 0.02 * delta

		# 战斗中持续累积
		if ai._state == AIController.AIState.ENGAGE:
			stress_delta += 0.005 * delta
			under_threat = true

	# 脱离威胁后恢复
	if not under_threat:
		stress_delta -= 0.25 * delta

	stress = clampf(stress + stress_delta, 0.0, 1.0)
	current_stress = stress

## 漂移噪声更新：模拟判断失误的缓慢偏移
func update_drift(ai: AIController, delta: float) -> void:
	var eff := effective_skill(ai.skill_level, ai.composure)
	var error_magnitude := (1.0 - eff)

	# 位置漂移：每 0.5~2 秒重采样目标
	drift_timer += delta
	var resample_interval := lerpf(0.5, 2.0, eff)  # 高技能 = 更稳定
	if drift_timer >= resample_interval:
		drift_timer = 0.0
		var angle := randf() * TAU
		var magnitude := error_magnitude * 200.0  # 最大偏移 200 像素（菜鸟满压力）
		drift_target = Vector2(cos(angle), sin(angle)) * magnitude

	# 平滑过渡
	drift_offset = drift_offset.lerp(drift_target, delta * 2.0)

	# 速度误差：每 1~3 秒重采样
	speed_error_timer += delta
	var speed_resample := lerpf(1.0, 3.0, eff)
	if speed_error_timer >= speed_resample:
		speed_error_timer = 0.0
		speed_error = randf_range(-1.0, 1.0) * error_magnitude * 0.2

	# 高度误差：每次战术切换时重新采样（在 _choose_tactic 中）

# ══════════════════════════════════════════════
#  误差应用（供 AIController 在瞄准/速度计算时调用）
# ══════════════════════════════════════════════

## 给目标位置加上漂移偏差
func apply_position_error(pos: Vector2, is_boss: bool) -> Vector2:
	if is_boss:
		return pos  # BOSS 攻击手：零误差，精确追踪
	return pos + drift_offset

## 给速度加上误差
func apply_speed_error(speed_kmh: float, is_boss: bool) -> float:
	if is_boss:
		return speed_kmh  # BOSS 攻击手：零误差
	return speed_kmh * (1.0 + speed_error)

## 给高度加上判断误差
func apply_altitude_error(alt: float) -> float:
	return alt + alt_error
