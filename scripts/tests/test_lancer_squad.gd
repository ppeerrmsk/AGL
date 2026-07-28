extends RefCounted

## 无头验收：骑士队级掠袭战术（spec events/ace-lancer-mig31 §3.1/§3.2/§5）
##
## A. profile 数据：vulture 行编成/装备/时段与 spec 一致（无炮/导弹6/8机/横列/后期档）
## B. 齐射分配纯函数：round-robin 覆盖（8v4 每人 2 发 / 8v9 互异 / 0 目标安全）
## C. 裸物理步进 sim：8 架真 Aircraft（MiG-31 params）+ 真 AircraftPhysics 逐帧步进，
##    AI 层只做"PATROL 航点→target_position"的最小胶水（test_joust 同款模型），
##    VOLLEY 的导弹发射用弹药递减模拟（导弹链路不在本测范围）。验收：
##    ≥3 轮 CHARGE→VOLLEY→EXTEND 循环不死锁 / 每波齐射目标分配互异均匀 /
##    EXTEND 真拉开 ≥ D_EXTEND / 弹尽判定
##
## 运行：godot --headless --path . -- --bench=lancer_squad（或 --bench=all）

const DT := 1.0 / 60.0
const AI_PERIOD := 3          ## AI 胶水 20Hz（同 simple_ai 分频惯例）
const SIM_SECONDS := 200.0

var _pass := 0
var _fail := 0
var _root: Node2D = null
var _registered_units: Array = []   ## 手动塞进 CombatUnit.all_units 的目标（收尾清理）


func run() -> void:
	print("\n════════ 骑士掠袭中队（VULTURE：横列冲锋/齐射分配/掠远回转/弹尽） ════════")
	_test_profile_row()
	_test_assign_pure()
	_test_element_parsing()
	_test_orion_tiers()
	_test_pass_cycle_sim()
	print("──────── 结果：%d 通过 / %d 失败 ────────" % [_pass, _fail])
	print("══════════════════════════════════════════════════\n")


# ── A. profile 数据 ──
func _test_profile_row() -> void:
	print("── A. vulture profile 行 ──")
	var p: Dictionary = AceSquadProfiles.get_profile("vulture")
	_check("已实装进调度池", bool(p.get("implemented", false)), "")
	_check("编成 8 机", int(p.get("squad_size", 0)) == 8, "%d" % int(p.get("squad_size", 0)))
	_check("纯导弹无机炮", String(p.get("gun", "")) == "none", String(p.get("gun", "")))
	_check("载弹 6 发/机", int(p.get("missile_count", 0)) == 6, "%d" % int(p.get("missile_count", 0)))
	_check("横列阵型", String(p.get("formation", "")) == "line", String(p.get("formation", "")))
	_check("lancer 战术", String(p.get("tactics", "")) == "lancer", String(p.get("tactics", "")))
	_check("后期档 400s", is_equal_approx(float(p.get("pool_time", 0.0)), 400.0),
		"%.0f" % float(p.get("pool_time", 0.0)))
	_check("机型 MIG31", int(p.get("enemy_type", -1)) == SurvivorSpawner.EnemyType.MIG31, "")


# ── B. 齐射分配纯函数（spec §3.2 round-robin）──
func _test_assign_pure() -> void:
	print("── B. 齐射目标分配 ──")
	# 8 攻 4 目标：每个目标恰被点名 2 次（玩家 4 机小队每人挨 2 发）
	var m84 := LancerSquadTactics.assign_targets(8, 4)
	var counts := {}
	for t in m84:
		counts[t] = int(counts.get(t, 0)) + 1
	var even := true
	for t in range(4):
		if int(counts.get(t, 0)) != 2:
			even = false
	_check("8v4 每目标恰 2 发", even, str(counts))
	# 8 攻 9 目标：8 个互异（至多 8 人被点名）
	var m89 := LancerSquadTactics.assign_targets(8, 9)
	var uniq := {}
	for t in m89:
		uniq[t] = true
	_check("8v9 目标互异", uniq.size() == 8, "%d 个不同目标" % uniq.size())
	# 0 目标安全（不除零）
	var m80 := LancerSquadTactics.assign_targets(8, 0)
	_check("0 目标不崩", m80.size() == 8, "")


# ── B2. 混编 element 解析（tier §3.7 混编条款：2NDWAVE / GIMMICK / GOOFIGHTERS）──
func _test_element_parsing() -> void:
	print("── B2. 混编 element 解析 ──")
	var ET = SurvivorSpawner.EnemyType
	var R = AceSquad.AceRole
	# 2NDWAVE：Teacher F-4E 斗士长机 + F-15 ×4 学员骑士
	var w := AceSupportSquad.new("2ndwave")
	_check("2ndwave 编成 5 机", w.squad_size == 5, "%d" % w.squad_size)
	_check("2ndwave 槽 0 = F-4E（Teacher）", w._member_type(0) == ET.F4E, "")
	_check("2ndwave 槽 1~4 = F-15", w._member_type(1) == ET.F15 and w._member_type(4) == ET.F15, "")
	_check("Teacher 角色 KNIGHT", w._member_role(0) == R.KNIGHT, "")
	_check("学员角色 NONE（骑士中性）", w._member_role(1) == R.NONE and w._member_role(4) == R.NONE, "")
	_check("2ndwave 挂掠袭战术", w._lancer != null, "学员 element 有 lancer")
	# GIMMICK：F-16 狙击 ×2（含长机 BLUFF）+ 幻影 2000 斗士 ×2
	var g := AceSupportSquad.new("gimmick")
	_check("gimmick 编成 4 机", g.squad_size == 4, "%d" % g.squad_size)
	_check("gimmick 槽 0/1 = F-16 狙击（SNIPER 站位带）",
		g._member_type(0) == ET.F16 and g._member_role(0) == R.SNIPER \
		and g._member_role(1) == R.SNIPER, "")
	_check("gimmick 槽 2/3 = 幻影斗士（KNIGHT）",
		g._member_type(2) == ET.MIRAGE2000 and g._member_role(2) == R.KNIGHT \
		and g._member_role(3) == R.KNIGHT, "")
	_check("gimmick 无掠袭模块", g._lancer == null, "狙击≠骑士")
	# GOOFIGHTERS：Su-47 ×2 斗士（无混编）
	var f := AceSupportSquad.new("goofighters")
	_check("goofighters Su-47 ×2 斗士", f.squad_size == 2 \
		and f._member_type(0) == ET.SU47 and f._member_role(0) == R.KNIGHT, "")
	# MARATHON 回归：沿用基类前 2 KNIGHT / 后排 SNIPER（既有落地行为不变）
	var m := AceSupportSquad.new("marathon")
	_check("marathon 角色沿用基类", m._member_role(0) == R.KNIGHT and m._member_role(1) == R.KNIGHT \
		and m._member_role(2) == R.SNIPER and m._member_role(4) == R.SNIPER, "")


# ── B3. 宿敌 ORION 档位表（spec events/ace-orion §2.3）──
func _test_orion_tiers() -> void:
	print("── B3. ORION 成长档位 ──")
	var t0: Dictionary = OrionNemesisEvent.tier_for(0)
	_check("白板档：仅机炮无 flare", int(t0["missiles"]) == 0 and int(t0["flares"]) == 0 \
		and is_equal_approx(float(t0["mult"]), 1.0), "ai=%.2f" % float(t0["ai"]))
	_check("档内恒定", OrionNemesisEvent.tier_for(4) == t0, "N=4 仍白板")
	_check("N=5 进档 II", is_equal_approx(float(OrionNemesisEvent.tier_for(5)["ai"]), 0.50), "")
	# 单调性：AI / 闪避 / 性能乘数随 N 不减
	var mono := true
	var prev: Dictionary = {}
	for n in [0, 5, 15, 30, 50, 98]:
		var t: Dictionary = OrionNemesisEvent.tier_for(n)
		if not prev.is_empty():
			if float(t["ai"]) < float(prev["ai"]) or float(t["dodge"]) < float(prev["dodge"]) \
					or float(t["mult"]) < float(prev["mult"]):
				mono = false
		prev = t
	_check("档位单调不回退", mono, "ai/dodge/mult 随 N 爬升")
	_check("封顶档：顶格 AI + 0.50 闪避", is_equal_approx(float(OrionNemesisEvent.tier_for(120)["ai"]), 1.0) \
		and is_equal_approx(float(OrionNemesisEvent.tier_for(120)["dodge"]), 0.50), "")
	# 机号进位与封顶
	_check("机号 Cre-01 起步", OrionNemesisEvent.designation(0) == "Cre-01",
		OrionNemesisEvent.designation(0))
	_check("机号随计数进位", OrionNemesisEvent.designation(42) == "Cre-43",
		OrionNemesisEvent.designation(42))
	_check("机号封顶 Cre-99", OrionNemesisEvent.designation(150) == "Cre-99",
		OrionNemesisEvent.designation(150))


# ── C. 裸物理步进 sim：完整掠袭循环 ──
func _test_pass_cycle_sim() -> void:
	print("── C. 掠袭循环 sim（真物理步进） ──")
	_root = Node2D.new()

	# 玩家小队 4 机（慢速盘旋，team=玩家；手动注册进 all_units 供战术层索敌）
	var targets: Array = []
	for i in range(4):
		var tp := AircraftParams.new()
		tp.cruise_speed = 500.0
		tp.max_speed = 900.0
		var t = _make_ac(tp, Vector2(i * 400.0 - 600.0, 0.0), PI * 0.5)
		t.speed = 140.0
		t.team = CombatUnit.TEAM_PLAYER
		CombatUnit.all_units.append(t)
		_registered_units.append(t)
		targets.append(t)

	# VULTURE 8 机（真 MiG-31 params，横列于目标南方 6000px、机头朝北）
	var squad := AceSupportSquad.new("vulture")
	var mig_res: AircraftParams = load("res://resources/enemy_mig31.tres")
	for i in range(8):
		var p: AircraftParams = mig_res.duplicate(true)
		p.gun = null
		var m = _make_ac(p, Vector2(i * 600.0 - 2100.0, 6000.0), 0.0)
		m.speed = 500.0
		m.missiles_remaining = 6
		var ai := _make_ai(m, null)
		m.set_meta(&"ace_tactics_owned", true)   # 正式路径由 _configure_spawn 打标
		squad.members.append(m)
		squad.all_members.append(m)
	var tac: LancerSquadTactics = squad._lancer
	_check("lancer 战术已挂载", tac != null, "")
	if tac == null:
		_cleanup()
		return

	tac.enter()
	_check("入场即 CHARGE", tac.phase == LancerSquadTactics.Phase.CHARGE, "")

	# sim 主循环
	var phase_seq: Array = [tac.phase]
	var volley_assign_ok := true      ## 每波分配：4 目标各被点名 2 次
	var volley_fire_t: Dictionary = {}  ## iid → 本波"瞄准中"累计时长（1s 后模拟发射）
	var max_extend_dist := 0.0
	var frames := int(SIM_SECONDS * 60.0)
	for f in range(frames):
		# 战术层（自带 0.5s 分频）
		tac.update(DT)
		if phase_seq[-1] != tac.phase:
			phase_seq.append(tac.phase)
			if tac.phase == LancerSquadTactics.Phase.VOLLEY:
				volley_fire_t.clear()
				if not _volley_assignment_even(squad, targets):
					volley_assign_ok = false
		# AI 胶水（20Hz）：PATROL 航点 / ENGAGE 目标 → target_position
		if f % AI_PERIOD == 0:
			for m in squad.members:
				var ai = m._get_ai_controller()
				if ai == null:
					continue
				if ai._current_target != null and is_instance_valid(ai._current_target):
					m.target_position = ai._current_target.global_position
					# 模拟发射：对准 1s 后弹药 -1（真实导弹链路不在本测范围）
					var iid: int = m.get_instance_id()
					volley_fire_t[iid] = float(volley_fire_t.get(iid, 0.0)) + DT * AI_PERIOD
					if volley_fire_t[iid] >= 1.0 and m.missiles_remaining > 0 \
							and tac.phase == LancerSquadTactics.Phase.VOLLEY:
						m.missiles_remaining -= 1
						volley_fire_t[iid] = -999.0   # 本波只射一发
				elif not ai.waypoints.is_empty():
					m.target_position = ai.waypoints[0]
		# 真物理步进
		for m in squad.members:
			_step(m)
		# 目标慢速盘旋
		for t in targets:
			t.heading += 0.15 * DT
			var v: Vector2 = Vector2(sin(t.heading), -cos(t.heading)) * 140.0 * CombatUnit.PIXELS_PER_METER
			t.position += v * DT
		# EXTEND 拉开观测
		if tac.phase == LancerSquadTactics.Phase.EXTEND:
			max_extend_dist = maxf(max_extend_dist, _min_dist(squad, targets))
		if f % 1800 == 0:
			print("    [%5.1fs] phase=%s minDist=%5.0f ammo=%s" % [
				f * DT, LancerSquadTactics.PHASE_NAMES[tac.phase],
				_min_dist(squad, targets), str(squad.members[0].missiles_remaining)])

	# 循环计数：CHARGE→VOLLEY→EXTEND→CHARGE 为一轮
	var cycles := 0
	for i in range(phase_seq.size()):
		if phase_seq[i] == LancerSquadTactics.Phase.EXTEND:
			cycles += 1
	_check("≥3 轮完整掠袭循环", cycles >= 3, "EXTEND 出现 %d 次，相序=%s" % [cycles, str(phase_seq)])
	_check("每波齐射分配均匀互异", volley_assign_ok, "8v4 → 每目标 2 发")
	_check("EXTEND 真拉开 ≥ D_EXTEND", max_extend_dist >= LancerSquadTactics.D_EXTEND_PX,
		"最大拉开 %.0f px（阈 %.0f）" % [max_extend_dist, LancerSquadTactics.D_EXTEND_PX])
	_check("循环中弹药递减", squad.members[0].missiles_remaining < 6,
		"剩 %d/6" % squad.members[0].missiles_remaining)
	# 弹尽判定（手动清空验证判定层；6 波全程 sim 属 playtest 范围）
	for m in squad.members:
		m.missiles_remaining = 0
	_check("弹尽判定", squad.is_ammo_dry(), "全员 0 弹 → 撤离触发条件成立")
	_check("有弹不误判", not _make_dry_false_positive(squad), "任一成员有弹 → 不 dry")

	_cleanup()


## 齐射入窗帧：验证分配互异均匀（4 目标各被点名 2 次）
func _volley_assignment_even(squad, targets: Array) -> bool:
	var counts := {}
	for m in squad.members:
		var ai = m._get_ai_controller()
		if ai == null or ai._current_target == null:
			continue
		var key := (ai._current_target as Object).get_instance_id()
		counts[key] = int(counts.get(key, 0)) + 1
	if counts.size() != targets.size():
		return false
	for k in counts:
		if int(counts[k]) != 2:
			return false
	return true

func _make_dry_false_positive(squad) -> bool:
	squad.members[0].missiles_remaining = 1
	var dry: bool = squad.is_ammo_dry()
	squad.members[0].missiles_remaining = 0
	return dry

func _min_dist(squad, targets: Array) -> float:
	var best := INF
	for m in squad.members:
		for t in targets:
			best = minf(best, m.global_position.distance_to(t.global_position))
	return best

func _cleanup() -> void:
	for u in _registered_units:
		CombatUnit.all_units.erase(u)
	_registered_units.clear()
	_root.free()
	_root = null


# ── harness（test_joust 同款）──

func _make_ac(params: AircraftParams, pos: Vector2, hdg: float):
	var ac = load("res://scripts/aircraft.gd").new()
	ac.params = params
	ac.heading = hdg
	ac.bank_angle = 0.0
	ac.altitude = 5000.0
	ac.speed = params.cruise_speed / 3.6
	ac.target_speed_kmh = params.cruise_speed
	ac.g_load = 1.0
	ac.tactical_aggression = 1.0
	ac.position = pos
	_root.add_child(ac)
	return ac

func _make_ai(ac, tgt) -> AIController:
	var ai: AIController = load("res://scripts/ai_controller.gd").new()
	ai.aircraft = ac
	ai._current_target = tgt
	ac._ai_ref = ai
	ac.add_child(ai)
	return ai

func _step(ac) -> void:
	AircraftPhysics.update_target_heading(ac)
	AircraftPhysics.update_bank(ac, DT)
	AircraftPhysics.update_heading(ac, DT)
	AircraftPhysics.update_speed(ac, DT)
	AircraftPhysics.update_g_load(ac)
	AircraftPhysics.apply_movement(ac, DT)


func _check(name: String, got: bool, note: String) -> void:
	if got: _pass += 1
	else: _fail += 1
	print("  %s %-28s — %s" % ["✓" if got else "✗", name, note])
