extends RefCounted

## 纯机炮狗斗成长沙盒。
##
## 目的：用真实 Situation → TacticalPlanner → AircraftPhysics 链做属性 A/B，回答：
## 1. 最大 G / 滚转 / 失速 / 减速 / G 阻力强化是否转化为更多机炮解算窗口；
## 2. 当前 planner 是否会根据自身机动优势改变缠斗方法；
## 3. “全员盘旋半径速度治理 + 转弯优势感知”候选策略是否值得进入正式设计。
##
## 注意：候选策略只住在 bench，不修改正式玩法。机炮指标使用正式 planner 的 is_firing
## 门（允许开火 + 真实提前角进入固定机炮锥）并再验射程；不生成 BulletManager 实弹，避免
## 随机散布/伤害把飞行与决策差异污染掉。
##
## 运行：bench/run.cmd dogfight_growth 5 120

const DT := 1.0 / 60.0
# LOD0（玩家 / 正在交战的僚机）在 aircraft._physics_process_impl 中每物理帧跑 planner。
# 旧行为 bench 常用 ÷3，但会漏掉固定机炮 ±5° 的短射击窗，本沙盒必须按正式 60Hz。
const AI_PERIOD := 1
const SIM_SECONDS := 50.0
const WARMUP_SECONDS := 5.0
const GRAVITY := 9.81

const SCENARIOS: Array[Dictionary] = [
	{
		"name": "横切接敌",
		"a_pos": Vector2(0.0, 800.0), "a_hdg": 0.0,
		"b_pos": Vector2(0.0, -800.0), "b_hdg": PI / 2.0,
	},
	{
		"name": "对头交汇",
		"a_pos": Vector2(0.0, 900.0), "a_hdg": 0.0,
		"b_pos": Vector2(0.0, -900.0), "b_hdg": PI,
	},
	{
		"name": "被占六点",
		"a_pos": Vector2(0.0, -100.0), "a_hdg": 0.0,
		"b_pos": Vector2(0.0, 650.0), "b_hdg": 0.0,
	},
]

const BUILDS: Array[Dictionary] = [
	{"id": "base", "label": "基础"},
	{"id": "milestone_g", "label": "里程碑G+2.0"},
	{"id": "g_only", "label": "仅G+3"},
	{"id": "maneuver2", "label": "机动强化×2"},
	{"id": "dogfight3", "label": "格斗大师×3"},
	{"id": "full", "label": "机动×2+格斗×3"},
]

var _pass := 0
var _fail := 0
var _root: Node2D = null


func run() -> void:
	print("\n════════ 纯机炮狗斗成长沙盒（双 AI / 属性 A-B） ════════")
	_root = Node2D.new()
	var current_rows: Array[Dictionary] = []
	var adaptive_rows: Array[Dictionary] = []
	for build in BUILDS:
		current_rows.append(_run_build(build, false))
		adaptive_rows.append(_run_build(build, true))
	_print_table("A. 当前正式 TacticalPlanner", current_rows)
	_print_table("B. bench 候选：属性画像分型 + 转弯优势感知", adaptive_rows)
	_print_deltas(current_rows, adaptive_rows)
	var wing_current := _run_wingman_probe(0)
	var wing_fire_fix := _run_wingman_probe(1)
	var wing_adaptive := _run_wingman_probe(2)
	_print_wingman_probe(wing_current, wing_fire_fix, wing_adaptive)
	_check_integrity(current_rows, adaptive_rows)
	_check("真实僚机协同路由能取得机炮窗", float(wing_current["fire_s"]) > 0.0,
		"当前 %.2fs / 候选 %.2fs" % [wing_current["fire_s"], wing_adaptive["fire_s"]])
	Situation.sim_time_override = -1.0
	_root.free()
	_root = null
	print("──────── 完整性：%d 通过 / %d 失败 ────────" % [_pass, _fail])
	print("══════════════════════════════════════════════════\n")


func _run_build(build: Dictionary, adaptive: bool) -> Dictionary:
	var totals := _new_metrics()
	for scenario in SCENARIOS:
		var one := _run_duel(build, scenario, adaptive)
		_accumulate(totals, one)
	var count := float(SCENARIOS.size())
	for key in ["fire_s", "first_fire_s", "tail_s", "avg_nose_deg", "avg_speed_kmh",
			"min_speed_kmh", "low_energy_s", "overspeed_turn_s", "high_g_bleed_kmh_s",
			"samples", "high_g_s"]:
		totals[key] = float(totals[key]) / count
	# 离散“获得一次机会”的数量也按场景平均，便于横向比较。
	totals["gun_windows"] = float(totals["gun_windows"]) / count
	totals["intent_switches"] = float(totals["intent_switches"]) / count
	totals["label"] = String(build["label"])
	return totals


func _run_duel(build: Dictionary, scenario: Dictionary, adaptive: bool) -> Dictionary:
	var actor_params: AircraftParams = _build_params(String(build["id"]))
	var target_params: AircraftParams = _build_params("base")
	var actor := _make_aircraft(actor_params, scenario["a_pos"], float(scenario["a_hdg"]), CombatUnit.TEAM_PLAYER)
	var target := _make_aircraft(target_params, scenario["b_pos"], float(scenario["b_hdg"]), CombatUnit.TEAM_HOSTILE)
	actor.combat_target = target
	target.combat_target = actor
	var actor_ai := _make_ai(actor, target)
	var target_ai := _make_ai(target, actor)
	var out := _new_metrics()
	var was_firing := false
	var first_fire := -1.0
	var prev_intent := -1
	var prev_speed_kmh: float = actor.speed * 3.6
	var frames := int(SIM_SECONDS / DT)
	for frame in range(frames):
		var sim_t := float(frame) * DT
		Situation.sim_time_override = sim_t
		if frame % AI_PERIOD == 0:
			var actor_intent := _plan_step(actor, adaptive)
			_plan_step(target, adaptive)
			if prev_intent >= 0 and actor_intent != prev_intent:
				out["intent_switches"] = float(out["intent_switches"]) + 1.0
			prev_intent = actor_intent
		_step_physics(actor)
		_step_physics(target)

		if sim_t < WARMUP_SECONDS:
			prev_speed_kmh = actor.speed * 3.6
			continue
		var dist_m: float = actor.global_position.distance_to(target.global_position) / CombatUnit.PIXELS_PER_METER
		var gun_range_m: float = actor.params.gun.max_range
		var firing: bool = actor.is_firing and dist_m <= gun_range_m
		if firing:
			out["fire_s"] = float(out["fire_s"]) + DT
			if not was_firing:
				out["gun_windows"] = float(out["gun_windows"]) + 1.0
				if first_fire < 0.0:
					first_fire = sim_t - WARMUP_SECONDS
		was_firing = firing

		var s := Situation.from_aircraft(actor)
		var lead_hdg: float = AircraftWeapons.lead_heading(actor, target, actor.params.gun.muzzle_velocity)
		var lead_off_deg: float = absf(rad_to_deg(Aircraft._angle_diff(lead_hdg, actor.heading)))
		out["avg_nose_deg"] = float(out["avg_nose_deg"]) + lead_off_deg
		var actor_speed_kmh: float = actor.speed * 3.6
		out["avg_speed_kmh"] = float(out["avg_speed_kmh"]) + actor_speed_kmh
		out["min_speed_kmh"] = minf(float(out["min_speed_kmh"]), actor_speed_kmh)
		out["samples"] = float(out["samples"]) + 1.0

		if s.in_rear_hemisphere and s.aim_align >= cos(deg_to_rad(15.0)) and dist_m <= gun_range_m * 1.5:
			out["tail_s"] = float(out["tail_s"]) + DT
		var physical_corner: float = AircraftPhysics.corner_speed_kmh(actor)
		if absf(actor.bank_angle) >= deg_to_rad(45.0) and actor_speed_kmh < physical_corner * 0.90:
			out["low_energy_s"] = float(out["low_energy_s"]) + DT
		if lead_off_deg > 30.0 and _turn_radius_at_speed(actor_speed_kmh, s.max_g) > dist_m * 0.70:
			out["overspeed_turn_s"] = float(out["overspeed_turn_s"]) + DT
		if actor.g_load >= 3.0:
			out["high_g_s"] = float(out["high_g_s"]) + DT
			var loss_kmh: float = maxf(prev_speed_kmh - actor_speed_kmh, 0.0)
			out["high_g_bleed_kmh_s"] = float(out["high_g_bleed_kmh_s"]) + loss_kmh
		prev_speed_kmh = actor_speed_kmh

	out["first_fire_s"] = first_fire if first_fire >= 0.0 else SIM_SECONDS - WARMUP_SECONDS
	var samples: float = maxf(float(out["samples"]), 1.0)
	out["avg_nose_deg"] = float(out["avg_nose_deg"]) / samples
	out["avg_speed_kmh"] = float(out["avg_speed_kmh"]) / samples
	# 把累计每帧速度下降换成高 G 秒均掉速，低值代表能量保持更好。
	var high_g_s: float = maxf(float(out["high_g_s"]), DT)
	out["high_g_bleed_kmh_s"] = float(out["high_g_bleed_kmh_s"]) / high_g_s
	_free_pair(actor, target, actor_ai, target_ai)
	return out


## 2v1 僚机探针：长机和一号僚机共享 full build、共同攻击基础 F-14。
## 通过真实 Squad 反向引用让 Situation 进入 is_wingman/following_leader_target/FLANK_LEFT 路由。
func _run_wingman_probe(mode: int) -> Dictionary:
	var adaptive: bool = mode >= 2
	var fix_fire_permission: bool = mode >= 1
	var leader := _make_aircraft(_build_params("full"), Vector2(100.0, 850.0), 0.0, CombatUnit.TEAM_PLAYER)
	var wing := _make_aircraft(_build_params("full"), Vector2(-180.0, 980.0), 0.0, CombatUnit.TEAM_PLAYER)
	var target := _make_aircraft(_build_params("base"), Vector2(0.0, -850.0), PI / 2.0, CombatUnit.TEAM_HOSTILE)
	leader.combat_target = target
	wing.combat_target = target
	target.combat_target = leader
	var leader_ai := _make_ai(leader, target)
	var wing_ai := _make_ai(wing, target)
	var target_ai := _make_ai(target, leader)
	var squad := SquadFactory.form_up(leader, [wing], Squad.Formation.COMBAT_SPREAD,
			Squad.EngageMode.FOLLOW_LEADER, 300.0, false)
	wing_ai._squad_lateral_role = AIController.SquadRole.FLANK_LEFT
	var out := {"fire_s": 0.0, "first_fire_s": SIM_SECONDS - WARMUP_SECONDS,
			"tail_s": 0.0, "avg_nose_deg": 0.0, "samples": 0.0, "windows": 0.0,
			"solution_s": 0.0, "blocked_s": 0.0, "intents": {}, "solution_intents": {}}
	var was_firing := false
	var first_fire := -1.0
	var last_wing_intent := -1
	var frames := int(SIM_SECONDS / DT)
	for frame in range(frames):
		var sim_t := float(frame) * DT
		Situation.sim_time_override = sim_t
		if frame % AI_PERIOD == 0:
			_plan_step(leader, adaptive, fix_fire_permission)
			var wing_intent: int = _plan_step(wing, adaptive, fix_fire_permission)
			last_wing_intent = wing_intent
			var intent_name: String = TacticalPlan.intent_name(wing_intent)
			var intent_counts: Dictionary = out["intents"]
			intent_counts[intent_name] = int(intent_counts.get(intent_name, 0)) + 1
			_plan_step(target, adaptive, fix_fire_permission)
		_step_physics(leader)
		_step_physics(wing)
		_step_physics(target)
		if sim_t < WARMUP_SECONDS:
			continue
		var dist_m: float = wing.global_position.distance_to(target.global_position) / CombatUnit.PIXELS_PER_METER
		var firing: bool = wing.is_firing and dist_m <= wing.params.gun.max_range
		if firing:
			out["fire_s"] = float(out["fire_s"]) + DT
			if not was_firing:
				out["windows"] = float(out["windows"]) + 1.0
				if first_fire < 0.0:
					first_fire = sim_t - WARMUP_SECONDS
		was_firing = firing
		var s := Situation.from_aircraft(wing)
		if s.in_rear_hemisphere and s.aim_align >= cos(deg_to_rad(15.0)) \
				and dist_m <= wing.params.gun.max_range * 1.5:
			out["tail_s"] = float(out["tail_s"]) + DT
		var lead_hdg: float = AircraftWeapons.lead_heading(wing, target, wing.params.gun.muzzle_velocity)
		var lead_off_deg: float = absf(rad_to_deg(Aircraft._angle_diff(lead_hdg, wing.heading)))
		out["avg_nose_deg"] = float(out["avg_nose_deg"]) + lead_off_deg
		var has_solution: bool = lead_off_deg <= wing.params.gun.fire_cone_half_angle \
				and dist_m <= wing.params.gun.max_range
		if has_solution:
			out["solution_s"] = float(out["solution_s"]) + DT
			var solution_counts: Dictionary = out["solution_intents"]
			var solution_intent_name: String = TacticalPlan.intent_name(last_wing_intent)
			solution_counts[solution_intent_name] = int(solution_counts.get(solution_intent_name, 0)) + 1
			if not firing:
				out["blocked_s"] = float(out["blocked_s"]) + DT
		out["samples"] = float(out["samples"]) + 1.0
	out["first_fire_s"] = first_fire if first_fire >= 0.0 else SIM_SECONDS - WARMUP_SECONDS
	out["avg_nose_deg"] = float(out["avg_nose_deg"]) / maxf(float(out["samples"]), 1.0)
	# 保持引用到清理结束，避免 Resource 提前析构；不需要显式 free。
	if squad == null:
		_fail += 1
	_free_three(leader, wing, target, leader_ai, wing_ai, target_ai)
	return out


func _plan_step(ac: Aircraft, adaptive: bool, fix_fire_permission: bool = false) -> int:
	var s := Situation.from_aircraft(ac)
	var dogfight_mode := 0
	if adaptive:
		dogfight_mode = _dogfight_capability_mode(ac)
		# 紧半径型具备持续缠斗资本：按属性把战术承诺抬到 Gladiator 档，避免仍被固定
		# personality 的 boom-zoom/co-turn breaker 过早赶出战斗。真实 overshoot 脱离不读此值。
		if dogfight_mode >= 2:
			s.ai_aggression = maxf(s.ai_aggression, 0.90)
	var plan := TacticalPlanner.plan(s, Vector2.INF)
	if adaptive:
		var can_commit: bool = dogfight_mode > 0 and _has_observable_turn_opportunity(s)
		plan = _attribute_aware_plan(s, plan, can_commit)
		var is_turn_fight: bool = plan.intent == TacticalPlan.Intent.WIDE_TURN \
				or plan.intent == TacticalPlan.Intent.LEAD_TURN \
				or plan.intent == TacticalPlan.Intent.LEAD_PURSUIT \
				or plan.intent == TacticalPlan.Intent.LAG_PURSUIT
		# 画像 2：低失速+强减速构成“紧半径型”，允许持续压到 AI corner 切内圈。
		# 画像 1：只有 G/滚转优势的“能量转向型”，仍以物理 corner 为地板，避免能量抽干。
		# 已进入 CLOSE_TAIL/TAIL_CHASE 后禁止治理：此时任务从“转进内圈”切成“闭合射程”，
		# 继续压 corner 会让强机在目标屁股后面追不上，尾位很好却始终没有机炮窗口。
		if dogfight_mode >= 2 and is_turn_fight and s.heading_diff_to_target_deg > 20.0:
			EngagementSpeedGovernor.apply(s, plan)
		elif dogfight_mode == 1 and can_commit:
			EngagementSpeedGovernor.apply(s, plan)
			plan.target_speed_kmh = maxf(plan.target_speed_kmh, s.corner_speed_kmh * 1.2)
	if adaptive or fix_fire_permission:
		# 候选火控修正：常规追击的许可必须看真实机炮提前解，不能看带 250m 僚机横移的
		# 战术 pursuit_pos。Lag/Extend/Merge 等主动禁射 intent 不在白名单内，纪律保持不变。
		_refresh_gun_permission_from_weapon_solution(ac, s, plan)
	if plan.intent != ac._bfm_prev_intent:
		ac._bfm_prev_intent = plan.intent
		ac._bfm_intent_started_at = Situation.now()
	if plan.trigger_extend_seconds > 0.0:
		ac._bfm_extend_until = Situation.now() + plan.trigger_extend_seconds
	ac._apply_tactical_plan(plan)
	ac._resolve_intents(DT)
	ac._last_plan = plan
	return plan.intent


func _refresh_gun_permission_from_weapon_solution(ac: Aircraft, s: Situation, plan: TacticalPlan) -> void:
	if plan.weapon_mode != TacticalPlan.WeaponMode.GUN:
		return
	if plan.intent != TacticalPlan.Intent.TAIL_CHASE \
			and plan.intent != TacticalPlan.Intent.CLOSE_TAIL \
			and plan.intent != TacticalPlan.Intent.LEAD_TURN \
			and plan.intent != TacticalPlan.Intent.LEAD_PURSUIT:
		return
	var lead_hdg: float = AircraftWeapons.lead_heading(ac, ac.combat_target, ac.params.gun.muzzle_velocity)
	var lead_off: float = absf(rad_to_deg(Aircraft._angle_diff(lead_hdg, ac.heading)))
	plan.allow_gun_fire = s.dist_m > 60.0 and s.dist_m <= s.gun_range_m \
			and lead_off <= ac.params.gun.fire_cone_half_angle and s.aim_align >= BfmIntent.GUN_TARGET_AHEAD_MIN


## 候选：只在 planner 已经选中侧翼缠斗时比较双方转弯圆。
## - 我方最小半径显著更小：不再机械走 lag，切内圈 lead，兑现高机动属性；
## - 我方明显更大：把过于乐观的 lead 改成 lag，避免高能量外圈死追。
## 复用现有 BFM primitive，不新增状态机。
func _attribute_aware_plan(s: Situation, original: TacticalPlan, can_commit: bool) -> TacticalPlan:
	if not s.has_target or s.tgt_is_surface or s.dist_m > s.gun_range_m * 3.0:
		return original
	if absf(s.tgt_bank_deg) < 35.0 or s.aspect_angle_deg < 55.0 or s.aspect_angle_deg > 135.0:
		return original
	var own_radius: float = _turn_radius_at_speed(s.corner_speed_kmh * 1.2, s.max_g)
	var target_bank: float = deg_to_rad(absf(s.tgt_bank_deg))
	var target_lat: float = GRAVITY * maxf(tan(target_bank), 0.1)
	var target_radius: float = s.tgt_speed_ms * s.tgt_speed_ms / target_lat
	if can_commit and own_radius < target_radius * 0.78 and original.intent == TacticalPlan.Intent.LAG_PURSUIT:
		var lead := BfmIntent.lead_pursuit(s)
		lead.rationale += " | bench属性感知：半径占优切内圈"
		return lead
	if own_radius > target_radius * 1.25 and original.intent == TacticalPlan.Intent.LEAD_PURSUIT:
		var lag := BfmIntent.lag_pursuit(s)
		lag.rationale += " | bench属性感知：半径劣势走lag"
		return lag
	return original


## 理论能力画像（不读技能 ID）：把转率、最小半径、滚转、减速与当前目标逐项比较。
## 0=无显著优势；1=能量转向型（G/滚转强但半径/减速普通）；2=紧半径型。
func _dogfight_capability_mode(ac: Aircraft) -> int:
	var target: Aircraft = ac.combat_target as Aircraft
	if target == null or target.params == null:
		return 0
	var own_g: float = AircraftPhysics.effective_max_g(ac)
	var target_g: float = AircraftPhysics.effective_max_g(target)
	var own_corner_ms: float = AircraftPhysics.corner_speed_kmh(ac) / 3.6
	var target_corner_ms: float = AircraftPhysics.corner_speed_kmh(target) / 3.6
	var own_lat: float = GRAVITY * sqrt(maxf(own_g * own_g - 1.0, 0.01))
	var target_lat: float = GRAVITY * sqrt(maxf(target_g * target_g - 1.0, 0.01))
	var turn_rate_ratio: float = (own_lat / own_corner_ms) / maxf(target_lat / target_corner_ms, 0.001)
	var own_radius: float = own_corner_ms * own_corner_ms / own_lat
	var target_radius: float = target_corner_ms * target_corner_ms / target_lat
	var radius_advantage: float = target_radius / maxf(own_radius, 1.0)
	var roll_ratio: float = ac.params.roll_rate / maxf(target.params.roll_rate, 0.1)
	var decel_ratio: float = ac.params.deceleration / maxf(target.params.deceleration, 0.1)
	var score: float = turn_rate_ratio * 0.40 + radius_advantage * 0.35 \
			+ roll_ratio * 0.15 + decel_ratio * 0.10
	if score <= 1.06:
		return 0
	if radius_advantage >= 1.20 and decel_ratio >= 1.20:
		return 2
	return 1


## 当前几何是否出现切内圈机会。能力画像决定“能不能”，观测运动学决定“现在该不该”。
func _has_observable_turn_opportunity(s: Situation) -> bool:
	if not s.has_target or s.dist_m > s.gun_range_m * 3.0:
		return false
	if absf(s.tgt_bank_deg) < 35.0 or s.aspect_angle_deg < 55.0 or s.aspect_angle_deg > 135.0:
		return false
	var own_corner_ms: float = s.corner_speed_kmh * 1.2 / 3.6
	var own_lateral: float = GRAVITY * sqrt(maxf(s.max_g * s.max_g - 1.0, 0.01))
	var own_turn_rate: float = own_lateral / maxf(own_corner_ms, 1.0)
	var own_radius: float = own_corner_ms * own_corner_ms / own_lateral
	var target_bank: float = deg_to_rad(absf(s.tgt_bank_deg))
	var target_lateral: float = GRAVITY * maxf(tan(target_bank), 0.1)
	var target_speed: float = maxf(s.tgt_speed_ms, 50.0)
	var target_turn_rate: float = target_lateral / target_speed
	var target_radius: float = target_speed * target_speed / target_lateral
	return own_turn_rate > target_turn_rate * 1.15 or own_radius < target_radius * 0.85


func _build_params(build_id: String) -> AircraftParams:
	var p: AircraftParams = load("res://resources/playable_f14_base.tres").duplicate(true)
	match build_id:
		"milestone_g":
			p.max_g += 2.0
			p.max_g_structural += 2.0
		"g_only":
			p.max_g += 3.0
			p.max_g_structural += 3.0
		"maneuver2":
			p.max_g += 3.0
			p.max_g_structural += 3.0
			p.roll_rate *= 1.3 * 1.3
		"dogfight3":
			_apply_dogfight_stack(p, 3)
		"full":
			p.max_g += 3.0
			p.max_g_structural += 3.0
			p.roll_rate *= 1.3 * 1.3
			_apply_dogfight_stack(p, 3)
	return p


func _apply_dogfight_stack(p: AircraftParams, stacks: int) -> void:
	for _i in range(stacks):
		p.stall_speed_base *= 0.88
		p.deceleration *= 1.30
		p.g_drag_factor *= 0.85
		# 同正式技能一起写入；当前 TacticalPlanner 路径不会消费这两个字段，bench 会暴露这一点。
		p.combat.overshoot_speed_margin *= 0.97
		p.combat.turn_slow_speed_mult *= 0.90


func _make_aircraft(params: AircraftParams, pos: Vector2, hdg: float, team_id: int) -> Aircraft:
	var ac: Aircraft = load("res://scripts/aircraft.gd").new()
	ac.params = params
	ac.team = team_id
	ac.heading = hdg
	ac.bank_angle = 0.0
	ac.altitude = 5000.0
	ac.target_altitude = 5000.0
	ac.flat_altitude = true
	ac.speed = params.cruise_speed / 3.6
	ac.target_speed_kmh = params.cruise_speed
	ac.g_load = 1.0
	ac.tactical_aggression = 1.0
	ac.use_tactical_planner = true
	ac.target_position = Vector2.INF
	ac.position = pos
	ac.ammo = 9999
	ac.missiles_remaining = 0
	ac.fuel = 9999.0
	_root.add_child(ac)
	return ac


func _make_ai(ac: Aircraft, target: Aircraft) -> AIController:
	var ai: AIController = load("res://scripts/ai_controller.gd").new()
	ai.aircraft = ac
	ai._current_target = target
	ai.aggression = 0.75
	ac._ai_ref = ai
	ac.add_child(ai)
	return ai


func _step_physics(ac: Aircraft) -> void:
	AircraftPhysics.update_target_heading(ac)
	AircraftPhysics.update_bank(ac, DT)
	AircraftPhysics.update_heading(ac, DT)
	AircraftPhysics.update_speed(ac, DT)
	AircraftPhysics.update_g_load(ac)
	AircraftPhysics.update_altitude(ac, DT)
	AircraftPhysics.apply_movement(ac, DT)


func _turn_radius_at_speed(speed_kmh: float, max_g: float) -> float:
	if max_g <= 1.01:
		return INF
	var speed_ms: float = speed_kmh / 3.6
	return speed_ms * speed_ms / (GRAVITY * sqrt(max_g * max_g - 1.0))


func _new_metrics() -> Dictionary:
	return {
		"fire_s": 0.0,
		"first_fire_s": 0.0,
		"gun_windows": 0.0,
		"tail_s": 0.0,
		"avg_nose_deg": 0.0,
		"avg_speed_kmh": 0.0,
		"min_speed_kmh": INF,
		"low_energy_s": 0.0,
		"overspeed_turn_s": 0.0,
		"high_g_bleed_kmh_s": 0.0,
		"high_g_s": 0.0,
		"samples": 0.0,
		"intent_switches": 0.0,
	}


func _accumulate(dst: Dictionary, src: Dictionary) -> void:
	for key in src:
		if key == "min_speed_kmh":
			dst[key] = minf(float(dst[key]), float(src[key]))
		else:
			dst[key] = float(dst.get(key, 0.0)) + float(src[key])


func _print_table(title: String, rows: Array[Dictionary]) -> void:
	print("── %s ──" % title)
	print("  %-17s | 开火秒 | 首次 | 窗口 | 尾位秒 | 机头差 | 均速 | 最低 | 低能量 | 半径过大 | 高G掉速" % "Build")
	for r in rows:
		print("  %-17s | %6.2f | %4.1f | %4.1f | %6.2f | %5.1f° | %4.0f | %4.0f | %6.2f | %8.2f | %7.1f" % [
			r["label"], r["fire_s"], r["first_fire_s"], r["gun_windows"], r["tail_s"],
			r["avg_nose_deg"], r["avg_speed_kmh"], r["min_speed_kmh"], r["low_energy_s"],
			r["overspeed_turn_s"], r["high_g_bleed_kmh_s"]])


func _print_deltas(current: Array[Dictionary], adaptive: Array[Dictionary]) -> void:
	print("── C. 候选策略相对当前的开火窗口变化 ──")
	for i in range(current.size()):
		var base_fire: float = float(current[i]["fire_s"])
		var new_fire: float = float(adaptive[i]["fire_s"])
		var pct: float = (new_fire - base_fire) / maxf(base_fire, 0.01) * 100.0
		print("  %-17s  %6.2fs → %6.2fs  (%+.0f%%)" % [current[i]["label"], base_fire, new_fire, pct])


func _print_wingman_probe(current: Dictionary, fire_fix: Dictionary, adaptive: Dictionary) -> void:
	print("── D. 真实 Squad 一号僚机（full build，2v1）──")
	print("  当前：开火 %.2fs / 几何解 %.2fs / 被火控拒绝 %.2fs / 首次 %.1fs / 尾位 %.2fs / 机头差 %.1f°" % [
		current["fire_s"], current["solution_s"], current["blocked_s"], current["first_fire_s"],
		current["tail_s"], current["avg_nose_deg"]])
	print("        intents=%s" % str(current["intents"]))
	print("        几何解所在intent=%s" % str(current["solution_intents"]))
	print("  仅修火控：开火 %.2fs / 几何解 %.2fs / 被拒绝 %.2fs / 首次 %.1fs / 尾位 %.2fs / 机头差 %.1f°" % [
		fire_fix["fire_s"], fire_fix["solution_s"], fire_fix["blocked_s"], fire_fix["first_fire_s"],
		fire_fix["tail_s"], fire_fix["avg_nose_deg"]])
	print("  候选：开火 %.2fs / 几何解 %.2fs / 被火控拒绝 %.2fs / 首次 %.1fs / 尾位 %.2fs / 机头差 %.1f°" % [
		adaptive["fire_s"], adaptive["solution_s"], adaptive["blocked_s"], adaptive["first_fire_s"],
		adaptive["tail_s"], adaptive["avg_nose_deg"]])
	print("        intents=%s" % str(adaptive["intents"]))
	print("        几何解所在intent=%s" % str(adaptive["solution_intents"]))


func _check_integrity(current: Array[Dictionary], adaptive: Array[Dictionary]) -> void:
	var all_valid := true
	for rows in [current, adaptive]:
		for r in rows:
			if is_nan(float(r["avg_nose_deg"])) or is_inf(float(r["avg_nose_deg"])) \
					or is_nan(float(r["avg_speed_kmh"])) or float(r["min_speed_kmh"]) <= 0.0:
				all_valid = false
	_check("所有对照完成且无 NaN/零速", all_valid, "6 builds × 2 planners × 3 openings × 50s")
	_check("基础组能产生真实机炮解算窗", float(current[0]["fire_s"]) > 0.0,
		"当前基础组平均 %.2fs" % float(current[0]["fire_s"]))


func _free_pair(actor: Aircraft, target: Aircraft, actor_ai: AIController, target_ai: AIController) -> void:
	actor.remove_child(actor_ai)
	target.remove_child(target_ai)
	_root.remove_child(actor)
	_root.remove_child(target)
	actor_ai.free()
	target_ai.free()
	actor.free()
	target.free()


func _free_three(leader: Aircraft, wing: Aircraft, target: Aircraft, leader_ai: AIController,
		wing_ai: AIController, target_ai: AIController) -> void:
	leader.remove_child(leader_ai)
	wing.remove_child(wing_ai)
	target.remove_child(target_ai)
	_root.remove_child(leader)
	_root.remove_child(wing)
	_root.remove_child(target)
	leader_ai.free()
	wing_ai.free()
	target_ai.free()
	leader.free()
	wing.free()
	target.free()


func _check(name: String, ok: bool, note: String) -> void:
	if ok:
		_pass += 1
	else:
		_fail += 1
	print("  %s %s — %s" % ["✓" if ok else "✗", name, note])
