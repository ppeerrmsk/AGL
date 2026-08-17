class_name LaserEquipment
extends EquipmentParams

## 360° 激光照射器（commit 9/13 — 第二个全新机制装备）
##
## 核心机制（2026-05-04 重做）：
## 1. **默认效果 = SLOW（减速）**：
##    - 飞机被光束扫到时持续刷 SLOW 状态（0.4s 续期），脱离光束 0.4s 后消失。
##      SLOW 把目标速度 cap 到 350 km/h + 屏蔽 AB（见 status_effects.gd）
##    - 导弹被光束扫到时由 LaserEquipment 续期 Missile._laser_slow_timer (0.5s)，
##      每秒流失最大速度的 35%，降至 20% 时失能；转弯 G cap 50%。
##    把"激光武器"重新定位成软压制 / 控制型武器，不再是 DPS / CIWS
## 2. **地面目标**：始终不参与自动目标选择（"激光不熔化坦克"）。
## 3. **SKILL_LASER_DAMAGE 升级**：
##    - 飞机 + 地面：在 SLOW 之外额外应用旧的 DPS 伤害（DoT 输出回归）
##    - 导弹：在 SLOW 之外额外消耗 intercept_hp（CIWS 拦截能力回归）
## 4. **距离衰减**：dps_max → dps_min（仅在 skill 启用时生效，影响伤害和视觉，slow 不衰减）
## 5. **多目标限制 / 过热 / 云层削弱**：保持原状
##
## 状态住在 Aircraft.equipment_state["laser"]，视觉由 AircraftRenderer.draw_laser_beams 承担。

const STATE_KEY := "laser"
const FactionTransitionScript = preload("res://scripts/events/faction_transition.gd")
const HACK_THRESHOLD_S := 2.5
const HACK_GRACE_S := 0.30
const HACK_DECAY_PER_S := 1.0
const META_HACK_PROGRESS: StringName = &"laser_hack_progress"
const META_HACK_LAST_TOUCH_MS: StringName = &"laser_hack_last_touch_ms"
const META_HACK_LAST_FRAME: StringName = &"laser_hack_last_frame"

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
## 装备直接拦截导弹（不依赖玩家技能 SKILL_LASER_DAMAGE）：扣 intercept_hp，可击毁
## 用途：敌方 Aegis UAV 等"专职拦截"激光。玩家 X-02 默认 false，靠技能解锁伤害
@export var intercepts_missiles_directly: bool = false

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
			# 检查玩家是否持有"激光也造成伤害"技能（仅 team 0 玩家飞机生效）
			var damage_skill_active: bool = _has_damage_skill(ac)
			var hack_skill_active: bool = _has_hack_skill(ac)
			if damage_skill_active and hack_skill_active:
				hack_skill_active = false
				if not ac.has_meta(&"laser_skill_conflict_warned"):
					ac.set_meta(&"laser_skill_conflict_warned", true)
					push_warning("LaserEquipment: damage/hack coexist; damage branch wins")
			var hack_focus = _select_hack_focus(ac, picks) if hack_skill_active else null
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
				# 应用效果：默认 SLOW；导弹拦截照旧；技能解锁 DPS 伤害
				_apply_laser_effect(ac, unit, dmg, damage_skill_active)
				var hack_ratio := 0.0
				if unit == hack_focus:
					hack_ratio = _advance_hack(ac, unit as Aircraft, delta)
				# 视觉记录
				var thickness: float = beam_thickness_base * lerpf(1.0, cloud_beam_thickness_factor_min, cloud_d)
				beams.append({
					"unit": unit,
					"thickness": thickness,
					"alpha": 0.6 + 0.4 * falloff,
					"hack_focus": unit == hack_focus,
					"hack_ratio": hack_ratio,
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
			if not is_instance_valid(unit) or unit == ac or not CombatUnit.teams_hostile(unit.team, ac.team):
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
			if not m.is_active or not CombatUnit.teams_hostile(m.team, ac.team):
				continue
			var d: float = origin.distance_to(m.global_position)
			if d > range_px or d < 1.0:
				continue
			picks.append({"unit": m, "dist": d})

	# 按距离排序，取最近 N 个
	picks.sort_custom(func(a, b): return a["dist"] < b["dist"])
	if _has_hack_skill(ac) and not _has_damage_skill(ac):
		_prioritize_hack_preference(ac, picks)
	if picks.size() > max_simultaneous_targets:
		picks.resize(max_simultaneous_targets)
	return picks


func _prioritize_hack_preference(ac: Aircraft, picks: Array) -> void:
	# combat_target 优先于 commanded_target；从后往前 push_front 可保持这一顺序。
	for preferred in [ac.commanded_target, ac.combat_target]:
		if not _is_hack_eligible(preferred):
			continue
		for i in range(picks.size()):
			if picks[i]["unit"] == preferred:
				var pick = picks.pop_at(i)
				picks.push_front(pick)
				break


## 默认效果 = SLOW（每帧刷新短暂 SLOW 状态，脱离光束自然消失）
## 导弹也获得 SLOW（速度 cap + 转弯 G cap，让玩家有时间机动闪开），但不直接拦截
## 技能解锁 = 在 SLOW 之外额外应用旧的 DPS 伤害（导弹回归 intercept_hp 拦截）
func _apply_laser_effect(ac, target, damage: float, damage_skill_active: bool) -> void:
	# 导弹：默认走 _laser_slow_timer（速度 + G 双 cap），玩家可机动闪开
	# 技能解锁后才走 intercept_hp 击落（与 CIWS 同语义）
	if target is Missile:
		var m: Missile = target
		m._laser_slow_timer = SkillHooks.LASER_MISSILE_SLOW_DURATION
		if intercepts_missiles_directly or damage_skill_active:
			m.intercept_hp -= damage
			if m.intercept_hp <= 0.0:
				m.is_active = false
				m.queue_free()
		return
	# Aircraft：默认 SLOW；技能解锁时额外加 DPS 伤害
	if target is Aircraft:
		if not target.can_accept_new_hit("laser"):
			return
		# 飞机被光束扫到 → 短暂 SLOW（每帧刷新；脱离 0.4s 自动消失）
		target.apply_status(StatusEffects.SLOW, SkillHooks.LASER_SLOW_REFRESH_DURATION)
		# 允许激光把目标压过普通 105% 安全地板；真正失速/掉高仍由统一飞行物理结算。
		target.set_meta(&"laser_stall_pressure_until_ms",
			Time.get_ticks_msec() + int(SkillHooks.LASER_SLOW_REFRESH_DURATION * 1000.0))
	if damage_skill_active:
		# 玩家解锁"激光致伤"：飞机 + 地面单位都吃完整 DPS
		# take_damage_from 走归因入口 — 触发恐惧扩散 / 寒颤 / 击杀回血等下游技能
		var laser_src: Node = CombatUnit.safe_attacker(ac)
		if target.has_method("take_damage_from"):
			target.take_damage_from(damage, laser_src, "laser")
		else:
			target.take_damage(damage, laser_src, "laser")


## 检测 source 飞机是否持有"激光致伤"技能（仅玩家系 team 0 生效）
func _has_damage_skill(ac) -> bool:
	if ac == null or not is_instance_valid(ac):
		return false
	if not ac.is_player_squad():
		return false
	if not ac.has_meta("upgrade_stacks"):
		return false
	var stacks: Dictionary = ac.get_meta("upgrade_stacks")
	return int(stacks.get(SkillHooks.SKILL_LASER_DAMAGE, 0)) > 0


func _has_hack_skill(ac) -> bool:
	if ac == null or not is_instance_valid(ac) or not ac.is_player_squad():
		return false
	if not ac.has_meta("upgrade_stacks"):
		return false
	var stacks: Dictionary = ac.get_meta("upgrade_stacks")
	return int(stacks.get(SkillHooks.SKILL_LASER_HACK, 0)) > 0


func _select_hack_focus(ac: Aircraft, picks: Array):
	for preferred in [ac.combat_target, ac.commanded_target]:
		if _is_hack_eligible(preferred):
			for pick in picks:
				if pick["unit"] == preferred:
					return preferred
	for pick in picks:
		if _is_hack_eligible(pick["unit"]):
			return pick["unit"]
	return null


static func _is_hack_eligible(unit) -> bool:
	if not unit is Aircraft or not is_instance_valid(unit) or unit.is_destroyed:
		return false
	if unit.team != CombatUnit.TEAM_HOSTILE:
		return false
	var enemy_type := String(unit.get_meta("enemy_type", ""))
	return enemy_type == "uav" or enemy_type == "ucav"


func _advance_hack(source: Aircraft, target: Aircraft, delta: float) -> float:
	if not _is_hack_eligible(target):
		return 0.0
	var now_ms := Time.get_ticks_msec()
	var progress := float(target.get_meta(META_HACK_PROGRESS, 0.0))
	var last_touch_ms := int(target.get_meta(META_HACK_LAST_TOUCH_MS, now_ms))
	var gap_s := maxf(float(now_ms - last_touch_ms) / 1000.0, 0.0)
	if gap_s > HACK_GRACE_S:
		progress = maxf(progress - (gap_s - HACK_GRACE_S) * HACK_DECAY_PER_S, 0.0)
	var physics_frame := Engine.get_physics_frames()
	if int(target.get_meta(META_HACK_LAST_FRAME, -1)) != physics_frame:
		progress += delta
		target.set_meta(META_HACK_LAST_FRAME, physics_frame)
	target.set_meta(META_HACK_PROGRESS, progress)
	target.set_meta(META_HACK_LAST_TOUCH_MS, now_ms)
	if progress < HACK_THRESHOLD_S:
		return clampf(progress / HACK_THRESHOLD_S, 0.0, 1.0)

	var enemy_type := String(target.get_meta("enemy_type", "uav"))
	var reason := "laser_hack_mq110" if enemy_type == "ucav" else "laser_hack_mq109"
	if not FactionTransitionScript.convert(target, CombatUnit.TEAM_ALLY, reason, source):
		return 0.0
	target.remove_meta(META_HACK_PROGRESS)
	target.remove_meta(META_HACK_LAST_TOUCH_MS)
	target.remove_meta(META_HACK_LAST_FRAME)
	target.show_tactic_popup(tr("TACTIC_HACKED"))
	var host := source.get_parent()
	if host != null and host.has_method("adopt_hacked_ally"):
		host.adopt_hacked_ally(target)
	return 1.0


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
