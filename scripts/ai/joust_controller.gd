class_name JoustController
extends RefCounted

## 攻击跑（joust）行为原语 —— spec: docs/specs/systems/joust-attack-run.md
##
## RUN_IN（机头对准进入火力窗）→ BREAK（脱离拉开）→ 折返循环。
## 解决两个病灶：
##   A. standoff 切向轨道 vs "锁定/充能要机头对准"的结构矛盾
##      （MQ-112 全场 0 充能死锁，log 183044）
##   B. Lancer 骑士型打带跑靠 engage_duration 定时器伪装，突击段姿态无对准承诺
##
## 只写 movement 契约字段（target_position / target_speed_kmh / orbit_speed_cap）；
## 武器链（机炮锥门/导弹锁定/电磁炮充能）在"机头恰好对准"的姿态下自然满足，零改动。
## 高度不主张——沿用宿主既有高度逻辑。
## 防御行为（Herbst / 躲弹 / 机炮防御 / EVADE 状态）在两条路径的钩子之前，永远压过 joust。

enum Phase { RUN_IN, BREAK }

const GIVEUP_HOLD_S := 2.0        ## 闭合率低于阈值持续此时长才判放弃（防瞬时抖动）
const BREAK_MAX_S := 12.0         ## BREAK 超时强制折返（目标追着我拉不开时转身面对）
const BREAK_EXTEND_PX := 1500.0   ## BREAK 外推点距离（每 tick 刷新）
const LEAD_FACTOR := 0.6          ## RUN_IN 前置系数（微 lead；精确对准由武器层守卫接管）
const LEAD_TIME_MAX_S := 3.0      ## lead 外推时间上限（远距闭合慢时防 lead 点飞出地图）
const FALLBACK_OUTER_PX := 2000.0 ## 无武器兜底包络
const INNER_FLOOR_PX := 200.0     ## 机炮/兜底内缘地板（穿越扫射防撞）


## 每决策 tick 调用（两条路径钩子：simple hunter 块 / _process_engage BFM 块）。
## 返回 true = 本 tick movement 已由 joust 接管（宿主跳过自己的走位/速度逻辑）。
static func update(ai: AIController, delta: float) -> bool:
	var ac: Aircraft = ai.aircraft
	var tgt = ai._current_target
	if ac == null or tgt == null or not is_instance_valid(tgt) or tgt.is_destroyed:
		return false
	var dist: float = ac.global_position.distance_to(tgt.global_position)

	# 包络动态解析（SEAM-001 / weapon-doctrine 原则 2：实时读装备 live params，禁止烘焙）
	var outer: float = _resolve_outer_px(ac)
	var inner: float = maxf(ai.joust_break_range_px, _resolve_inner_px(ac))
	var reentry: float = ai.joust_reentry_range_px if ai.joust_reentry_range_px > 0.0 else outer * 1.3

	# 电磁炮充能保持窗：charging / awaiting_fire 期间禁止切 BREAK（承诺弹道优先，
	# 甩头 = 白费充能；此时"充能稳头守卫"多半已钉住机头，joust 只维持相位不动）
	var railgun_busy: bool = _railgun_busy(ac)

	if ai._joust_phase == Phase.RUN_IN:
		# 超时只计火力窗内时间：远程转场（>outer 段）不烧预算，否则从 reentry/spawn
		# 飞回来的路上就把 15s 用光，刚进带就被切 BREAK（bench 实测踩过）
		if dist <= outer:
			ai._joust_run_timer += delta
		# 闭合放弃（骑士语义"闭合不够就脱离"）：仅火力窗外判定
		var giveup: bool = false
		if ai.joust_giveup_closing_mps > 0.0 and dist > outer:
			var closing_mps: float = _closing_mps(ac, tgt)
			if closing_mps < ai.joust_giveup_closing_mps:
				ai._joust_lowclose_timer += delta
				giveup = ai._joust_lowclose_timer >= GIVEUP_HOLD_S
			else:
				ai._joust_lowclose_timer = 0.0
		if not railgun_busy and (dist <= inner or ai._joust_run_timer > ai.joust_run_max_s or giveup):
			ai._joust_phase = Phase.BREAK
			ai._joust_run_timer = 0.0
			ai._joust_lowclose_timer = 0.0
			EventLogger.log_event("AI_TACTIC", ai._log_name(),
				"joust RUN_IN→BREAK (dist=%.0fpx inner=%.0f%s)" % [
					dist, inner, " giveup" if giveup else ""])
	else:  # BREAK
		ai._joust_run_timer += delta
		if dist >= reentry or ai._joust_run_timer > BREAK_MAX_S:
			ai._joust_phase = Phase.RUN_IN
			ai._joust_run_timer = 0.0
			ai._joust_lowclose_timer = 0.0
			EventLogger.log_event("AI_TACTIC", ai._log_name(),
				"joust BREAK→RUN_IN (dist=%.0fpx reentry=%.0f)" % [dist, reentry])

	# ── movement 契约 ──
	ac.orbit_speed_cap = 0.0   # 清旧 standoff 轨道残留限速
	if ai._joust_phase == Phase.RUN_IN:
		# 目标 lead 前置点：微 lead 保证追的是"路径提前点"而不是尾烟
		var tgt_vel_px: Vector2 = _unit_velocity_px(tgt)
		var closing_px: float = maxf(_closing_mps(ac, tgt) * CombatUnit.PIXELS_PER_METER,
				ac.speed * CombatUnit.PIXELS_PER_METER * 0.5)
		var lead_time: float = minf(dist / maxf(closing_px, 1.0), LEAD_TIME_MAX_S)
		ac.target_position = tgt.global_position + tgt_vel_px * lead_time * LEAD_FACTOR
		# 两段速：火力窗外全速闭合（cruise 可能追不上目标，bench 实测吊在带外），
		# 入带后才降到 run 速（稳定锁定/充能平台）
		if dist > outer:
			ac.target_speed_kmh = AircraftPhysics.effective_max_speed_kmh(ac)
		elif ai.joust_run_speed_kmh > 0.0:
			ac.target_speed_kmh = ai.joust_run_speed_kmh
		else:
			ac.target_speed_kmh = AircraftPhysics.effective_cruise_speed_kmh(ac)
	else:
		# 远离目标方向外推；近图边时朝地图中心 lerp（同 BFM FEAR 边界守卫公式）
		var away: Vector2 = (ac.global_position - tgt.global_position).normalized()
		if away == Vector2.ZERO:
			away = Vector2(sin(ac.heading), -cos(ac.heading))
		var edge_dist: float = MapBoundary.distance_to_edge(ac.global_position)
		if edge_dist <= MapBoundary.AI_EDGE_TURN_MARGIN_PX:
			var inward: Vector2 = (Vector2.ZERO - ac.global_position).normalized()
			if away.dot(inward) < 0.0:
				var blend: float = clampf(1.0 - edge_dist / MapBoundary.AI_EDGE_TURN_MARGIN_PX, 0.3, 1.0)
				away = away.lerp(inward, blend).normalized()
		ac.target_position = ac.global_position + away * BREAK_EXTEND_PX
		if ai.joust_break_speed_kmh > 0.0:
			ac.target_speed_kmh = ai.joust_break_speed_kmh
		else:
			ac.target_speed_kmh = AircraftPhysics.effective_max_speed_kmh(ac)
	return true


## 火力窗外缘（px）：主武器最大射程。电磁炮 > 导弹 > 机炮 优先（与竞选距离带同序）
static func _resolve_outer_px(ac: Aircraft) -> float:
	if ac.params == null:
		return FALLBACK_OUTER_PX
	var rg = ac.params.get_equipment_of_kind("railgun")
	if rg != null:
		return rg._effective_max_range_m(ac) * CombatUnit.PIXELS_PER_METER
	if ac.params.missile != null and "max_range" in ac.params.missile:
		return float(ac.params.missile.max_range) * CombatUnit.PIXELS_PER_METER
	if ac.params.gun != null and "max_range" in ac.params.gun:
		return ac.effective_gun_range_m() * CombatUnit.PIXELS_PER_METER
	return FALLBACK_OUTER_PX


## 脱离内缘（px）：主武器最小交战距离
static func _resolve_inner_px(ac: Aircraft) -> float:
	if ac.params == null:
		return INNER_FLOOR_PX
	var rg = ac.params.get_equipment_of_kind("railgun")
	if rg != null:
		return maxf(rg.min_engage_range_m * CombatUnit.PIXELS_PER_METER, INNER_FLOOR_PX)
	if ac.params.missile != null and "min_range" in ac.params.missile:
		return maxf(float(ac.params.missile.min_range) * CombatUnit.PIXELS_PER_METER, INNER_FLOOR_PX)
	return INNER_FLOOR_PX


## 闭合率（m/s，正 = 在接近）
static func _closing_mps(ac: Aircraft, tgt) -> float:
	var to_tgt: Vector2 = (tgt.global_position - ac.global_position)
	if to_tgt.length_squared() < 1.0:
		return 0.0
	var dir: Vector2 = to_tgt.normalized()
	var my_vel: Vector2 = Vector2(sin(ac.heading), -cos(ac.heading)) * ac.speed
	var tgt_vel: Vector2 = Vector2.ZERO
	if "heading" in tgt and "speed" in tgt:
		tgt_vel = Vector2(sin(tgt.heading), -cos(tgt.heading)) * tgt.speed
	return (my_vel - tgt_vel).dot(dir)


## 目标速度向量（px/s）
static func _unit_velocity_px(tgt) -> Vector2:
	if "heading" in tgt and "speed" in tgt:
		return Vector2(sin(tgt.heading), -cos(tgt.heading)) * tgt.speed * CombatUnit.PIXELS_PER_METER
	return Vector2.ZERO


static func _railgun_busy(ac: Aircraft) -> bool:
	var s = ac.equipment_state.get(RailgunEquipment.STATE_KEY, null)
	if s == null:
		return false
	return bool(s.get("charging", false)) or bool(s.get("awaiting_fire", false))
