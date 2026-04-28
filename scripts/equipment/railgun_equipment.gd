class_name RailgunEquipment
extends EquipmentParams

## 电磁炮装备（commit 8/13 — 第一个全新机制装备）
##
## 核心机制：
## 1. **Telegraph 充能**：进入开火意图 → 扇形 UI 从初始角度收缩为 0° （charge_duration 内）
## 2. **弹道锁定时机**：AT_CHARGE_START（敌人版，扇形开始就锁死轨迹）/
##    AT_FIRE_TIME（玩家版，开火瞬间才锁死）。决定玩家能否通过机动躲避
## 3. **Hitscan + 闪电视觉**：发射瞬间命中（projectile_speed = ∞），视觉是闪电抖动线
## 4. **穿透**：弹道路径上所有 CombatUnit / Missile / GroundUnit 都受伤
## 5. **冷却**：单发后 cooldown 秒不能再充能
##
## 状态住在 Aircraft.equipment_state["railgun"] 字典里（避免污染 Aircraft 字段）。
## 视觉由 AircraftRenderer.draw_railgun_telegraph + draw_railgun_beam 承担。

const STATE_KEY := "railgun"
const HIT_RADIUS_PX := 25.0   ## 线段命中半径（~50 米光束直径）
const BEAM_FADE_DURATION := 0.25  ## 视觉淡出时长（秒）
const TELEGRAPH_INITIAL_HALF_ANGLE_DEG := 30.0  ## 扇形初始半角

enum LockTrajectory {
	AT_CHARGE_START,  ## 敌人版：扇形开始时锁死目标位置（玩家可靠机动躲掉）
	AT_FIRE_TIME,     ## 玩家版：开火瞬间锁定（基本必中）
}


@export_group("基本")
@export var display_name: String = "电磁炮"
@export var damage: float = 60.0                 ## 单发伤害（玩家版 150，敌人版 50-70）
@export var max_range_m: float = 5000.0          ## 米 最大射程

@export_group("充能")
@export var charge_duration: float = 2.5         ## 秒 telegraph 时长（玩家 1.2 / 敌人 2.5）
@export var lock_trajectory_at: LockTrajectory = LockTrajectory.AT_CHARGE_START
@export var cooldown: float = 6.0                ## 秒 单发后冷却

@export_group("命中（仅 AT_FIRE_TIME 模式）")
## 高速目标 miss 概率 —— 玩家版本基本必中，但极速目标（>1500 km/h）会有少量散布
@export var fast_target_miss_speed_kmh: float = 1500.0
@export var fast_target_max_miss_chance: float = 0.15

@export_group("视觉")
@export var beam_color: Color = Color(0.7, 0.95, 1.0, 1.0)  ## 闪电色（蓝白）
@export var enemy_beam_color: Color = Color(1.0, 0.5, 0.4, 1.0) ## 敌方红色版


func _init() -> void:
	equipment_kind = "railgun"


# ─────────── 状态访问 ───────────

static func _ensure_state(ac) -> Dictionary:
	if not ac.equipment_state.has(STATE_KEY):
		ac.equipment_state[STATE_KEY] = {
			"cooldown": 0.0,
			"charging": false,
			"charge_progress": 0.0,
			"charge_target": null,
			"locked_aim_pos": Vector2.ZERO,
			"beam_start": Vector2.ZERO,
			"beam_end": Vector2.ZERO,
			"beam_fade": 0.0,
		}
	return ac.equipment_state[STATE_KEY]


# ─────────── 主循环 ───────────

func update(ac, delta: float) -> void:
	var s := _ensure_state(ac)
	# beam 视觉淡出
	if s["beam_fade"] > 0.0:
		s["beam_fade"] = maxf(s["beam_fade"] - delta, 0.0)
	# 冷却减时
	if s["cooldown"] > 0.0:
		s["cooldown"] = maxf(s["cooldown"] - delta, 0.0)

	if s["charging"]:
		_tick_charging(ac, s, delta)
	else:
		_try_start_charging(ac, s)


func _try_start_charging(ac, s: Dictionary) -> void:
	if s["cooldown"] > 0.0:
		return
	# 需要有效战斗目标
	var tgt = ac.combat_target
	if tgt == null or not is_instance_valid(tgt) or tgt.is_destroyed:
		return
	# 射程检查
	var dist: float = ac.global_position.distance_to(tgt.global_position)
	var range_px: float = max_range_m * CombatUnit.PIXELS_PER_METER
	if dist > range_px:
		return
	# 启动 charge
	s["charging"] = true
	s["charge_progress"] = 0.0
	s["charge_target"] = tgt
	if lock_trajectory_at == LockTrajectory.AT_CHARGE_START:
		s["locked_aim_pos"] = tgt.global_position  # 锁死位置 → 玩家可机动躲


func _tick_charging(ac, s: Dictionary, delta: float) -> void:
	# 目标失效 → 取消充能（无 cooldown 惩罚）
	var tgt = s["charge_target"]
	if tgt == null or not is_instance_valid(tgt) or tgt.is_destroyed:
		s["charging"] = false
		s["charge_progress"] = 0.0
		return
	# 推进进度
	s["charge_progress"] = clampf(s["charge_progress"] + delta / charge_duration, 0.0, 1.0)
	if s["charge_progress"] >= 1.0:
		_fire(ac, s)


func _fire(ac, s: Dictionary) -> void:
	var tgt = s["charge_target"]
	if tgt == null or not is_instance_valid(tgt) or tgt.is_destroyed:
		s["charging"] = false
		s["charge_progress"] = 0.0
		return

	# 决定终点
	var aim_pos: Vector2
	if lock_trajectory_at == LockTrajectory.AT_CHARGE_START:
		aim_pos = s["locked_aim_pos"]
	else:
		# AT_FIRE_TIME：开火瞬间锁定（基本必中）
		aim_pos = tgt.global_position
		# 极速目标加少量 miss 散布（玩家版的细节）
		if "speed" in tgt:
			var spd_kmh: float = float(tgt.speed) * 3.6
			if spd_kmh > fast_target_miss_speed_kmh:
				var miss_t: float = clampf(
					(spd_kmh - fast_target_miss_speed_kmh) / fast_target_miss_speed_kmh,
					0.0, 1.0)
				if randf() < fast_target_max_miss_chance * miss_t:
					# 横向偏移让 hitscan 错过
					var perp := (aim_pos - ac.global_position).orthogonal().normalized()
					aim_pos += perp * 80.0 * (1.0 if randf() < 0.5 else -1.0)

	# 弹道：从 ac 机头延长到 max_range（穿透到底）
	var muzzle: Vector2 = ac.global_position
	var dir: Vector2 = (aim_pos - muzzle).normalized()
	var range_px: float = max_range_m * CombatUnit.PIXELS_PER_METER
	var beam_end: Vector2 = muzzle + dir * range_px

	# Hitscan 命中检测：穿透 = 线段沿途所有 unit
	_apply_hitscan_damage(ac, muzzle, beam_end)

	# 写入视觉状态
	s["beam_start"] = muzzle
	s["beam_end"] = beam_end
	s["beam_fade"] = BEAM_FADE_DURATION

	# 进入冷却
	s["charging"] = false
	s["charge_progress"] = 0.0
	s["charge_target"] = null
	s["cooldown"] = cooldown

	EventLogger.log_event("RAILGUN", ac.callsign,
		"fire team=%d range=%dm" % [ac.team, int(beam_end.distance_to(muzzle) / CombatUnit.PIXELS_PER_METER)])


# ─────────── 命中检测 ───────────

func _apply_hitscan_damage(ac, beam_start: Vector2, beam_end: Vector2) -> void:
	# 1) 所有 CombatUnit（敌机 / 地面单位）
	for unit in CombatUnit.all_units:
		if not is_instance_valid(unit):
			continue
		if unit == ac:
			continue
		if unit.team == ac.team:
			continue
		if unit.is_destroyed:
			continue
		if unit is Aircraft and (unit as Aircraft).is_cloaked:
			continue
		var d := _point_to_segment_distance(unit.global_position, beam_start, beam_end)
		if d <= HIT_RADIUS_PX:
			unit.take_damage(damage, ac)

	# 2) 在飞导弹（如果当前 ac 持有 missile_manager 引用）
	var mm = ac.missile_manager
	if mm != null and is_instance_valid(mm):
		for child in mm.get_children():
			if not (child is Missile):
				continue
			var m: Missile = child
			if not m.is_active or m.team == ac.team:
				continue
			var d := _point_to_segment_distance(m.global_position, beam_start, beam_end)
			if d <= HIT_RADIUS_PX:
				# 导弹被电磁炮命中 → 直接销毁
				m.queue_free()


static func _point_to_segment_distance(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var len_sq := ab.length_squared()
	if len_sq <= 0.001:
		return p.distance_to(a)
	var t := clampf((p - a).dot(ab) / len_sq, 0.0, 1.0)
	var closest := a + ab * t
	return p.distance_to(closest)


# ─────────── 状态查询 ───────────

func cooldown_ratio(ac) -> float:
	var s = ac.equipment_state.get(STATE_KEY, null)
	if s == null or cooldown <= 0.0:
		return 1.0
	return clampf(1.0 - float(s["cooldown"]) / cooldown, 0.0, 1.0)


func desired_engagement(_situation):
	var pref := EngagementPreference.new()
	pref.preferred_intent = TacticalPlan.Intent.TAIL_CHASE
	pref.preferred_range_m = max_range_m * 0.7  # 略短于最大射程的甜点
	pref.priority = 0.8  # 高于导弹（0.7）
	pref.needs_lock = true
	pref.needs_los = true
	pref.rationale = "railgun"
	return pref
