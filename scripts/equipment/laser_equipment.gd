class_name LaserEquipment
extends EquipmentParams

## 360° 激光照射器（commit 9/13 — 第二个全新机制装备）
##
## 核心机制：
## 1. **全向 DoT**：无锥角约束，扫描射程内所有目标，每帧应用 dps × delta
## 2. **距离衰减**：dps_max（贴脸） → dps_min（满射程），falloff_exp 控制曲线
## 3. **多目标限制**：max_simultaneous_targets 上限（防 N² 爆炸 + 过强）
## 4. **Target filter**：can_target_aircraft / missiles / ground，按用途配置
##    - X-02 玩家：全 true（全能武器）
##    - 激光 UAV（拦截特化）：只 missiles=true
## 5. **过热**：连续输出累加 heat，到 max 进入冷却 → 必须等散热到阈值才能再开
## 6. **云层削弱**：调 WeatherSystem.sample_density 拿目标处云密度 →
##    damage × (1 - density×0.7)，beam 视觉变细
##
## 状态住在 Aircraft.equipment_state["laser"]，视觉由 AircraftRenderer.draw_laser_beams 承担。

const STATE_KEY := "laser"

@export_group("基本")
@export var max_range_m: float = 1500.0

@export_group("伤害")
@export var dps_max: float = 150.0       ## 0 距离 dps
@export var dps_min: float = 20.0        ## 满射程 dps
@export var falloff_exp: float = 1.5     ## damage = (dps_max-dps_min) * (1-d/r)^exp + dps_min

@export_group("目标过滤")
@export var can_target_aircraft: bool = true
@export var can_target_missiles: bool = true
@export var can_target_ground: bool = true
@export var max_simultaneous_targets: int = 8

@export_group("过热")
@export var heat_max: float = 100.0
@export var heat_per_second: float = 35.0           ## 输出时累加（约 2.85s 满）
@export var heat_cooldown_per_second: float = 25.0  ## 静止时散热（满冷却 4.0s）
@export var overheat_exit_threshold: float = 0.3    ## 散热到 max × 此值才能再开火

@export_group("云层削弱")
@export var cloud_damage_factor_min: float = 0.30   ## 满云时伤害保留比例（密度 1.0 → ×0.30）
@export var cloud_beam_thickness_factor_min: float = 0.40

@export_group("视觉")
@export var beam_color: Color = Color(0.9, 1.0, 0.7, 1.0)  ## 黄绿激光（区别于电磁炮蓝白）
@export var beam_thickness_base: float = 2.5


func _init() -> void:
	equipment_kind = "laser"


# ─────────── 状态访问 ───────────

static func _ensure_state(ac) -> Dictionary:
	if not ac.equipment_state.has(STATE_KEY):
		ac.equipment_state[STATE_KEY] = {
			"heat": 0.0,
			"overheating": false,
			"active_beams": [],  # Array of Dictionary {unit, end_pos, thickness, alpha}
		}
	return ac.equipment_state[STATE_KEY]


# ─────────── 主循环 ───────────

func update(ac, delta: float) -> void:
	var s := _ensure_state(ac)
	var beams: Array = []  # 本帧重新算
	var firing := false

	if s["overheating"]:
		# 强制散热阶段
		s["heat"] = maxf(s["heat"] - heat_cooldown_per_second * delta, 0.0)
		if s["heat"] <= heat_max * overheat_exit_threshold:
			s["overheating"] = false
	else:
		# 正常扫描 + 输出
		var picks := _pick_targets(ac)
		if picks.size() > 0:
			firing = true
			var weather := _find_weather()
			for pick in picks:
				var unit = pick["unit"]
				var dist: float = pick["dist"]
				# 距离衰减
				var range_px: float = max_range_m * CombatUnit.PIXELS_PER_METER
				var t: float = clampf(1.0 - dist / range_px, 0.0, 1.0)
				var falloff: float = pow(t, falloff_exp)
				var dps: float = dps_min + (dps_max - dps_min) * falloff
				# 云层削弱
				var cloud_d: float = 0.0
				if weather != null:
					cloud_d = weather.sample_density(unit.global_position)
				var cloud_damage_mult: float = lerpf(1.0, cloud_damage_factor_min, cloud_d)
				var dmg: float = dps * cloud_damage_mult * delta
				# 应用伤害
				_apply_laser_damage(ac, unit, dmg)
				# 视觉记录
				var thickness: float = beam_thickness_base * lerpf(1.0, cloud_beam_thickness_factor_min, cloud_d)
				beams.append({
					"unit": unit,
					"thickness": thickness,
					"alpha": 0.6 + 0.4 * falloff,
				})
			# 累计热量
			s["heat"] += heat_per_second * delta
			if s["heat"] >= heat_max:
				s["heat"] = heat_max
				s["overheating"] = true

		# 不开火时也散热（但比强制散热慢一半）
		if not firing:
			s["heat"] = maxf(s["heat"] - heat_cooldown_per_second * 0.5 * delta, 0.0)

	s["active_beams"] = beams


# ─────────── 目标选择 ───────────

func _pick_targets(ac) -> Array:
	var picks: Array = []
	var range_px: float = max_range_m * CombatUnit.PIXELS_PER_METER
	var origin: Vector2 = ac.global_position

	# Aircraft + 地面单位
	if can_target_aircraft or can_target_ground:
		for unit in CombatUnit.all_units:
			if not is_instance_valid(unit) or unit == ac or unit.team == ac.team:
				continue
			if unit.is_destroyed:
				continue
			if unit is Aircraft:
				if not can_target_aircraft:
					continue
				if (unit as Aircraft).is_cloaked:
					continue
			elif unit is GroundUnit:
				if not can_target_ground:
					continue
			var d: float = origin.distance_to(unit.global_position)
			if d > range_px or d < 1.0:
				continue
			picks.append({"unit": unit, "dist": d})

	# 在飞导弹
	if can_target_missiles and ac.missile_manager != null and is_instance_valid(ac.missile_manager):
		for child in ac.missile_manager.get_children():
			if not (child is Missile):
				continue
			var m: Missile = child
			if not m.is_active or m.team == ac.team:
				continue
			var d: float = origin.distance_to(m.global_position)
			if d > range_px or d < 1.0:
				continue
			picks.append({"unit": m, "dist": d})

	# 按距离排序，取最近 N 个
	picks.sort_custom(func(a, b): return a["dist"] < b["dist"])
	if picks.size() > max_simultaneous_targets:
		picks.resize(max_simultaneous_targets)
	return picks


func _apply_laser_damage(ac, target, damage: float) -> void:
	# 导弹：消耗 intercept_hp（与 BulletManager CIWS 一致）
	if target is Missile:
		var m: Missile = target
		m.intercept_hp -= damage
		if m.intercept_hp <= 0.0:
			m.queue_free()
		return
	# CombatUnit：标准 take_damage
	target.take_damage(damage)


func _find_weather() -> WeatherSystem:
	var loop := Engine.get_main_loop()
	if loop == null:
		return null
	var nodes: Array = loop.get_nodes_in_group("weather")
	if nodes.size() == 0:
		return null
	var n = nodes[0]
	if n is WeatherSystem:
		return n
	return null


# ─────────── 状态查询 ───────────

func heat_ratio(ac) -> float:
	var s = ac.equipment_state.get(STATE_KEY, null)
	if s == null:
		return 0.0
	return clampf(float(s["heat"]) / heat_max, 0.0, 1.0)


func is_overheating(ac) -> bool:
	var s = ac.equipment_state.get(STATE_KEY, null)
	return s != null and s.get("overheating", false)


func desired_engagement(_situation):
	var pref := EngagementPreference.new()
	pref.preferred_intent = TacticalPlan.Intent.CLOSE_TAIL
	pref.preferred_range_m = max_range_m * 0.4  # 贴近最大化伤害
	pref.priority = 0.6  # 与机炮同档
	pref.needs_lock = false
	pref.needs_los = true
	pref.rationale = "laser"
	return pref
