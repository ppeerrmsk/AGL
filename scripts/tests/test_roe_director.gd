extends RefCounted

const EncounterDirectorScript = preload("res://scripts/survivor/encounter_director.gd")

## ROE 全图察觉与交战规则回归（spec global-awareness-roe）
## 覆盖：热度纯函数、直属小队 XP/Token/出击规模 + 姿态派生 + 感知门（察觉/守区 leash）
## 运行：godot --headless --path . -- --bench=roe（或 --bench=all）

var _pass := 0
var _fail := 0


func run() -> void:
	print("\n════════ ROE 察觉与交战规则（热度/姿态/感知门） ════════")

	_test_heat_math()
	_test_squad_balance_math()
	_test_encounter_director_math()
	_test_formation_assault_keeps_squad()
	_test_posture_derive()
	_test_scored_engage_gate()

	print("──────── 结果：%d 通过 / %d 失败 ────────" % [_pass, _fail])
	print("══════════════════════════════════════════════════\n")


# ── 1. 热度纯函数 ──

func _test_heat_math() -> void:
	# 配额映射：round(2 + 10 × h/100)，值域 2~12
	_check("配额 h=0 → 2", RoeDirector.quota_for_heat(0.0) == 2, "")
	_check("配额 h=50 → 7", RoeDirector.quota_for_heat(50.0) == 7, "")
	_check("配额 h=100 → 12", RoeDirector.quota_for_heat(100.0) == 12, "")
	_check("配额越界钳制", RoeDirector.quota_for_heat(999.0) == 12, "")

	# 等级地板：min(75, 5L)
	_check("地板 Lv1 = 5", RoeDirector.heat_floor_for_level(1) == 5.0, "")
	_check("地板 Lv10 = 50", RoeDirector.heat_floor_for_level(10) == 50.0, "")
	_check("地板 Lv15 = 75（封顶）", RoeDirector.heat_floor_for_level(15) == 75.0, "")
	_check("地板 Lv30 = 75（封顶）", RoeDirector.heat_floor_for_level(30) == 75.0, "")

	# 静默基线 ≈ 既有配额曲线 max(3, 2+L/2)（数值连续性，spec §2.4 表）
	for lv_pair in [[1, 3], [6, 5], [10, 7], [15, 10]]:
		var lv: int = lv_pair[0]
		var want: int = lv_pair[1]
		var q := RoeDirector.quota_for_heat(RoeDirector.heat_floor_for_level(lv))
		_check("静默基线 Lv%d 配额=%d（旧曲线对拍）" % [lv, want], q == want, "实际=%d" % q)

	# 衰减：宽限内不掉，宽限外 -2/s，地板兜底
	_check("宽限内不衰减", RoeDirector.step_heat_value(50.0, 3.0, 1, 1.0) == 50.0, "")
	_check("宽限外 -2/s", is_equal_approx(RoeDirector.step_heat_value(50.0, 10.0, 1, 1.0), 48.0), "")
	_check("衰减不破地板", RoeDirector.step_heat_value(51.0, 999.0, 10, 1.0) >= 50.0, "Lv10 地板=50")
	_check("低于地板抬升", RoeDirector.step_heat_value(10.0, 0.0, 10, 1.0) == 50.0, "地板是硬下限")

	# 实例账本：add_heat 累积 + 100 封顶
	var d := RoeDirector.new(null)
	d.add_heat(30.0)
	_check("add_heat 累积", d.heat == 30.0, "")
	d.add_heat(999.0)
	_check("heat 封顶 100", d.heat == 100.0, "")
	_check("实例配额取 heat", d.hunter_quota() == 12, "")


func _test_squad_balance_math() -> void:
	_check("单机 XP 倍率 = 1", is_equal_approx(SurvivorData.squad_xp_multiplier(1), 1.0), "")
	_check("3 机 XP 倍率 = 0.5", is_equal_approx(SurvivorData.squad_xp_multiplier(3), 0.5), "")
	_check("9 机 XP 倍率 = 0.2", is_equal_approx(SurvivorData.squad_xp_multiplier(9), 0.2), "")
	_check("9 机 Token 加成 = 24", SurvivorData.squad_token_bonus(9) == 24, "")
	_check("Lv5 / 9 机热度地板 = 73", SurvivorData.squad_heat_floor(5, 9) == 73.0, "")
	_check("高等级大队热度地板封顶 100", SurvivorData.squad_heat_floor(15, 9) == 100.0, "")
	_check("响应层级取等级与热度较高者", SurvivorData.response_level(5, 73.0) == 15, "")
	_check("Hunter 优先承压最低目标", SurvivorData.least_pressure_target_index([3, 1, 2], [10.0, 999.0, 1.0]) == 1, "")
	_check("Hunter 同压优先最近目标", SurvivorData.least_pressure_target_index([1, 1, 1], [30.0, 10.0, 20.0]) == 1, "")

	# 无扰动时对拍表格累计阈值；扰动本身由实现钳在 [0.85, 1.15]。
	_check("单机玩家 roll .59 → 敌单机", SurvivorData.pick_enemy_formation_class(1, 1.0, 1.0, 1.0, 0.59) == 1, "")
	_check("单机玩家 roll .61 → 敌双机", SurvivorData.pick_enemy_formation_class(1, 1.0, 1.0, 1.0, 0.61) == 2, "")
	_check("单机玩家 roll .90 → 敌 flight", SurvivorData.pick_enemy_formation_class(1, 1.0, 1.0, 1.0, 0.90) == 3, "")
	_check("9 机玩家 roll .14 → 敌单机", SurvivorData.pick_enemy_formation_class(9, 1.0, 1.0, 1.0, 0.14) == 1, "")
	_check("9 机玩家 roll .40 → 敌 flight", SurvivorData.pick_enemy_formation_class(9, 1.0, 1.0, 1.0, 0.40) == 3, "")
	_check("flight 65% 为 3 机", SurvivorData.pick_enemy_flight_size(0.64) == 3, "")
	_check("flight 35% 为 4 机", SurvivorData.pick_enemy_flight_size(0.65) == 4, "")
	_check("静默衰减不破小队地板", RoeDirector.step_heat_value(70.0, 999.0, 5, 1.0, 9) == 73.0, "")

	var attacker: Aircraft = load("res://scripts/aircraft.gd").new()
	attacker.team = CombatUnit.TEAM_ALLY
	var ground: GroundUnit = load("res://scripts/ground_unit.gd").new()
	ground.take_damage(999.0, attacker, "gun")
	_check("地面目标保留第三方攻击队伍", int(ground.get_meta("kill_attacker_team", -1)) == CombatUnit.TEAM_ALLY, "")
	var natural_ground: GroundUnit = load("res://scripts/ground_unit.gd").new()
	natural_ground.take_damage(999.0)
	_check("地面目标自然毁伤无击杀归因", not natural_ground.has_meta("kill_attacker_team"), "")
	natural_ground.free()
	ground.free()
	attacker.free()


func _test_encounter_director_math() -> void:
	print("── Encounter Director：PR / Lethal Slot / Flight 解析 ──")
	_check("Token 迁移公式 1/4/9 → 1.0/1.75/3.0",
		is_equal_approx(EncounterDirectorScript.pressure_cost_from_token(1), 1.0) \
			and is_equal_approx(EncounterDirectorScript.pressure_cost_from_token(4), 1.75) \
			and is_equal_approx(EncounterDirectorScript.pressure_cost_from_token(9), 3.0), "")
	_check("临时友军不进入 PR target 参数；直属 1→4 只按 N 提升",
		EncounterDirectorScript.pressure_target_for(4, 50.0) \
			> EncounterDirectorScript.pressure_target_for(1, 50.0), "target 只接收直属 N")
	_check("单机 PR 基线与 N=4/Heat78 原目标不变",
		is_equal_approx(EncounterDirectorScript.pressure_target_for(1, 0.0), 3.2) \
			and is_equal_approx(EncounterDirectorScript.pressure_target_for(4, 78.0), 7.925), "")
	_check("N>=4 开局驻防稳定三机；小队不足时保留 2～3 机 roll",
		EncounterDirectorScript.opening_garrison_size_for(4, 2) == 3 \
			and EncounterDirectorScript.opening_garrison_size_for(1, 2) == 2 \
			and EncounterDirectorScript.opening_garrison_size_for(3, 3) == 3, "")
	_check("Heat 提升致命攻击容量但封顶 6.5",
		EncounterDirectorScript.lethal_capacity_for(4, 80.0) \
			> EncounterDirectorScript.lethal_capacity_for(4, 20.0) \
			and EncounterDirectorScript.lethal_capacity_for(99, 100.0) == 6.5, "")
	_check("N>=4/Heat>=60 的 4 机包按 roll 可解析 2+2",
		EncounterDirectorScript.resolve_flight_elements(4, 60.0, 4, 0.59) == [2, 2], "")
	_check("单机玩家或低 Heat 保持单 Element，不硬镜像",
		EncounterDirectorScript.resolve_flight_elements(1, 100.0, 4, 0.0) == [4] \
			and EncounterDirectorScript.resolve_flight_elements(4, 59.9, 4, 0.0) == [4], "")
	_check("PR 缺口门通过后，完整包 headroom 服从 1.30 倍 Spike Cap",
		is_equal_approx(EncounterDirectorScript.pressure_headroom(5.0, 8.0), 5.4) \
			and is_equal_approx(EncounterDirectorScript.pressure_headroom(8.0, 8.0), 2.4), "")
	_check("Global Recovery 只由敌对 Presence 真正清零触发",
		EncounterDirectorScript.should_begin_global_recovery(3, 0) \
			and not EncounterDirectorScript.should_begin_global_recovery(3, 2) \
			and not EncounterDirectorScript.should_begin_global_recovery(0, 0), "")


func _test_formation_assault_keeps_squad() -> void:
	print("── 编队优先：共享目标不夺走僚机导航权 ──")
	var leader := Aircraft.new()
	var wing := Aircraft.new()
	var target := CombatUnit.new()
	leader.team = CombatUnit.TEAM_HOSTILE
	wing.team = CombatUnit.TEAM_HOSTILE
	target.team = CombatUnit.TEAM_PLAYER
	leader.params = AircraftParams.new()
	wing.params = AircraftParams.new()
	var ai := AIController.new()
	ai.aircraft = wing
	ai.enable_combat = true
	ai.evade_missiles = false
	ai._defense_scan_timer = 1.0
	ai.squad_engage_mode = AIController.SquadEngageMode.FOLLOW_LEADER
	wing.use_tactical_planner = true
	wing._ai_ref = ai
	wing.add_child(ai)
	var sq := SquadFactory.create(Squad.Formation.WEDGE, Squad.EngageMode.FOLLOW_LEADER)
	SquadFactory.register_leader(sq, leader)
	SquadFactory.register_wingman(sq, wing, true)
	leader.set_combat_target(target)
	SquadCoordination.process_squad_follow(ai, 0.1)
	_check("FOLLOW_LEADER 僚机保留 SQUAD_FOLLOW 与 formation_mode",
		ai._state == AIController.AIState.SQUAD_FOLLOW and wing.formation_mode, "")
	_check("共享目标只进入火控，战术标记为 FORMATION_ASSAULT",
		wing.combat_target == target and not wing.ai_override_pursuit \
			and ai.current_tactic_name == "TACTIC_FORMATION_ASSAULT", "")
	leader.free()
	wing.free()
	target.free()


# ── 2. 姿态派生 ──

func _test_posture_derive() -> void:
	var d := RoeDirector.new(null)
	var ac: Aircraft = load("res://scripts/aircraft.gd").new()

	_check("无 meta → 豁免 \"\"", d._derive_posture(ac) == "", "")
	ac.set_meta("category", "reinforcement")
	ac.set_meta("reinf_phase", "transit")
	_check("增援 transit → transit", d._derive_posture(ac) == "transit", "")
	ac.set_meta("reinf_phase", "onstation")
	_check("增援 onstation → patrol", d._derive_posture(ac) == "patrol", "")
	ac.set_meta("reinf_phase", "egress")
	_check("增援 egress → egress", d._derive_posture(ac) == "egress", "")
	ac.set_meta(&"roe_hunt", true)
	_check("roe_hunt 压倒一切 → hunt", d._derive_posture(ac) == "hunt", "")
	ac.remove_meta(&"roe_hunt")
	ac.set_meta("category", "zone_air")
	_check("zone_air → garrison", d._derive_posture(ac) == "garrison", "")
	ac.set_meta("category", "adds")
	_check("adds → 豁免 \"\"", d._derive_posture(ac) == "", "")

	ac.free()


# ── 3. 感知门（ai_controller._roe_allows_scored_engage）──

func _test_scored_engage_gate() -> void:
	var ai: AIController = load("res://scripts/ai_controller.gd").new()
	var ac: Aircraft = load("res://scripts/aircraft.gd").new()
	var tgt: Aircraft = load("res://scripts/aircraft.gd").new()
	ai.aircraft = ac
	ac.team = CombatUnit.TEAM_HOSTILE
	tgt.team = CombatUnit.TEAM_PLAYER
	tgt.global_position = Vector2(1500, 0)
	var now := EventLogger.get_game_time()

	_check("无姿态 meta → 放行（沙盒/F5/adds 不受约束）", ai._roe_allows_scored_engage(tgt), "")

	ac.set_meta(&"roe_posture", "hunt")
	_check("hunt → 放行（全知）", ai._roe_allows_scored_engage(tgt), "")

	ac.set_meta(&"roe_posture", "patrol")
	ac.set_meta(&"roe_aware_until", -1.0)
	_check("patrol 未察觉 → 拒", not ai._roe_allows_scored_engage(tgt), "")
	ac.set_meta(&"roe_aware_until", now + 999.0)
	_check("patrol 已察觉 → 放行", ai._roe_allows_scored_engage(tgt), "")

	# 守区：察觉 + 目标出圈（zone.radius + 750px leash）→ 拒；圈内 → 放行
	ac.set_meta(&"roe_posture", "garrison")
	ac.set_meta(&"roe_zone_center", Vector2.ZERO)
	ac.set_meta(&"roe_zone_radius_px", 1000.0)
	tgt.global_position = Vector2(3000, 0)
	_check("garrison 目标出圈(3000 > 1750) → 拒", not ai._roe_allows_scored_engage(tgt), "")
	tgt.global_position = Vector2(1500, 0)
	_check("garrison 目标圈内(1500 ≤ 1750) → 放行", ai._roe_allows_scored_engage(tgt), "")
	ac.set_meta(&"roe_aware_until", -1.0)
	_check("garrison 未察觉 → 圈内也拒", not ai._roe_allows_scored_engage(tgt), "")

	tgt.free()
	ac.free()
	ai.free()


func _check(name: String, ok: bool, detail: String) -> void:
	if ok:
		_pass += 1
		print("  ✓ %s %s" % [name, detail])
	else:
		_fail += 1
		print("  ✗ %s %s" % [name, detail])
