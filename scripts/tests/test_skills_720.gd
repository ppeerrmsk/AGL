extends RefCounted

## 无头行为验收：720 技能整改批（spec skills-720-rework）
##
## T1 归属底座：品类身份映射 / 归属生效谓词（scope/classes/ace/squad_once）/
##             "+1 轴进度"双计数（cap=2、gates 隔离、判档、换型重放）/ 卡池品类门控
## 后续批（T2 数据表约定 / T4 计数缩放 / T5 新机制）在此文件持续追加断言。
##
## 运行：godot --headless --path . -- --bench=skills720（或 --bench=all）

var _pass := 0
var _fail := 0


func run() -> void:
	print("\n════════ 720 技能整改批（品类身份 / 归属谓词 / +1 轴进度 / 池门控） ════════")
	_test_class_identity()
	_test_applies_to_predicate()
	_test_milestone_bonus_double_count()
	_test_pool_class_gate()
	_test_t3_hooks()
	_test_ace_strip_roundtrip()
	_test_axis_count_scaling()
	_test_t5_mechanisms()
	print("──────── 结果：%d 通过 / %d 失败 ────────" % [_pass, _fail])
	print("══════════════════════════════════════════════════\n")


# ── A. 品类身份映射（机种类 → 轴集合，spec §1.2 / ownership §2.8）──
func _test_class_identity() -> void:
	print("── A. 品类身份：attack=斗 / ew=策 / range=骑 / air·bridge·carrier=斗骑 / stealth=骑策 / omni·legend=三系 ──")
	var cases: Array = [
		["a10", [&"gladiator"]],
		["f16", [&"schemer"]],
		["f14", [&"knight"]],
		["f15", [&"gladiator", &"knight"]],
		["fa18e", [&"gladiator", &"knight"]],
		["x90", [&"gladiator", &"knight"]],
		["x77", [&"knight", &"schemer"]],
		["x02", [&"gladiator", &"knight", &"schemer"]],
		["ax00", [&"gladiator", &"knight", &"schemer"]],
	]
	for c in cases:
		var got: Array = EvolutionSystem.class_identity_of_profile(StringName(str(c[0])))
		_check("%s → %s" % [c[0], c[1]], got == (c[1] as Array), "got %s" % [got])
	_check("未知档案 → 空身份（不吃品类技）",
		EvolutionSystem.class_identity_of_profile(&"nope").is_empty(), "")


# ── B. 归属生效谓词（纯函数，_distribute / 生效子集 meta 重建共用）──
func _test_applies_to_predicate() -> void:
	print("── B. upgrade_applies_to_machine：通用 / 品类 / 王牌 / 单实例 / 组合 ──")
	var glad_id: Array = [&"gladiator"]
	var sch_id: Array = [&"schemer"]
	var u_plain: Dictionary = {"id": "x", "stat": "s"}
	_check("通用：任何机生效", SurvivorData.upgrade_applies_to_machine(u_plain, [], false), "")
	var u_cls: Dictionary = {"id": "x", "classes": ["schemer"]}
	_check("策士限定：斗士机不生效",
		not SurvivorData.upgrade_applies_to_machine(u_cls, glad_id, true), "")
	_check("策士限定：策士僚机生效",
		SurvivorData.upgrade_applies_to_machine(u_cls, sch_id, false), "")
	var u_ace: Dictionary = {"id": "x", "scope": "ace"}
	_check("王牌：操控机生效", SurvivorData.upgrade_applies_to_machine(u_ace, [], true), "")
	_check("王牌：僚机不生效", not SurvivorData.upgrade_applies_to_machine(u_ace, glad_id, false), "")
	var u_combo: Dictionary = {"id": "x", "scope": "ace", "classes": ["knight"]}
	_check("骑士∩王牌：骑士操控机生效",
		SurvivorData.upgrade_applies_to_machine(u_combo, [&"knight"], true), "")
	_check("骑士∩王牌：斗士操控机不生效",
		not SurvivorData.upgrade_applies_to_machine(u_combo, glad_id, true), "")
	var u_once: Dictionary = {"id": "x", "scope": "squad_once"}
	_check("队级单实例：不落任何单机（账本级消费）",
		not SurvivorData.upgrade_applies_to_machine(u_once, glad_id, true), "")


# ── C. "+1 轴进度"双计数（spec §1.1：cap=2 定案；gates 只认纯点）──
func _test_milestone_bonus_double_count() -> void:
	print("── C. milestone_bonus：cap=2 / gates 隔离 / 判档=点+加成 / 换型重放含加成 ──")
	var sp := SurvivorPlayer.new()
	var ac := _make_test_aircraft()
	sp.aircraft = ac
	# 1 点 + 1 加成 → 进度 2 跨首档（斗士 2 档 = max_hp +25）
	sp.add_axis_point(SurvivorData.AXIS_GLADIATOR)
	_check("1 点未跨档（hp 100）", is_equal_approx(ac.params.max_hp, 100.0),
		"got %.1f" % ac.params.max_hp)
	sp.add_milestone_bonus(SurvivorData.AXIS_GLADIATOR)
	_check("加成 +1 → 进度 2 跨首档（hp 125）", is_equal_approx(ac.params.max_hp, 125.0),
		"got %.1f" % ac.params.max_hp)
	_check("门槛点数不变（双计数隔离）",
		sp.get_axis_points(SurvivorData.AXIS_GLADIATOR) == 1, "")
	_check("里程碑进度 = 2", sp.get_milestone_progress(SurvivorData.AXIS_GLADIATOR) == 2, "")
	# gates 用 axis_points 纯点：2 点门 1点+1加成不过
	var nd: Dictionary = {"gates": {"gladiator": 2}}
	_check("gates 只认纯点：1点+1加成过不了 2 点门",
		not EvolutionSystem.gates_passed(nd, sp.axis_points), "")
	# cap=2：第 3 次浪费
	sp.add_milestone_bonus(SurvivorData.AXIS_GLADIATOR)
	sp.add_milestone_bonus(SurvivorData.AXIS_GLADIATOR)
	_check("cap=2（第 3 次 +1 浪费）",
		int(sp.milestone_bonus[SurvivorData.AXIS_GLADIATOR]) == 2,
		"got %d" % int(sp.milestone_bonus[SurvivorData.AXIS_GLADIATOR]))
	_check("进度 = 3（1点+2加成）", sp.get_milestone_progress(SurvivorData.AXIS_GLADIATOR) == 3, "")
	# 换型重放：全新 params 重挂时加成计入
	ac.params = _make_fresh_params(200.0)
	ac.hp = 200.0
	sp.reapply_all_milestones()
	_check("换型重放含加成（hp 200→225）", is_equal_approx(ac.params.max_hp, 225.0),
		"got %.1f" % ac.params.max_hp)
	# 未知轴防御
	sp.add_milestone_bonus(&"bogus")
	_check("未知轴不崩不计", sp.get_milestone_progress(SurvivorData.AXIS_GLADIATOR) == 3, "")
	ac.free()
	sp.free()


# ── D. 卡池品类门控（ownership §2.8 实装草图 4）──
func _test_pool_class_gate() -> void:
	print("── D. is_upgrade_available_for：squad_classes 相交判定 ──")
	var u: Dictionary = {"id": "x", "classes": ["schemer"]}
	_check("队里无策士机 → 不进池",
		not SurvivorData.is_upgrade_available_for(u, &"f15", null, {}, [&"gladiator", &"knight"]), "")
	_check("队里有策士机 → 进池",
		SurvivorData.is_upgrade_available_for(u, &"f15", null, {}, [&"schemer"]), "")
	_check("未提供 squad_classes → 不过滤（debug 兼容通道）",
		SurvivorData.is_upgrade_available_for(u, &"f15", null, {}, []), "")
	_check("无 classes 技能不受门控影响",
		SurvivorData.is_upgrade_available_for({"id": "y"}, &"f15", null, {}, [&"gladiator"]), "")


# ── E. T3 钩子（spec §6 T3：AB 修正 / 免耗弹窗 / QAAM 嗜血 / 适应回能 / 升级回复挂点在 mode）──
func _test_t3_hooks() -> void:
	print("── E. T3 钩子：AB 账本修正 / 免耗弹窗口 / QAAM 嗜血 / 适应回能 ──")
	var ab := AfterburnerCharge.new()
	ab.kill_charge_bonus = 3.0
	ab.charge = 0.0
	ab.on_kill_charge()
	_check("检讨：击杀充能 4+3=7", is_equal_approx(ab.charge, 7.0), "got %.1f" % ab.charge)
	ab.window_duration_mult = 1.5
	ab.charge = AfterburnerCharge.CHARGE_MAX
	var ldr := _make_test_aircraft()
	var ok_act := ab.try_activate(ldr)
	_check("强化加力：窗口 6→9s", ok_act and is_equal_approx(ab.window_left, 9.0),
		"act=%s left=%.1f" % [ok_act, ab.window_left])
	ldr.free()

	var ac := _make_test_aircraft()
	ac.params.gun = GunParams.new()
	_check("免耗弹窗口：无技能 → false", not SkillHooks.in_free_missile_window(ac), "")
	ac.set_meta("upgrade_stacks", {"gun_out_free_missile": 1})
	ac._gun_reload_active = true
	_check("免耗弹窗口：技能+装填中 → true", SkillHooks.in_free_missile_window(ac), "")
	ac._gun_reload_active = false
	_check("免耗弹窗口：装填结束 → false", not SkillHooks.in_free_missile_window(ac), "")
	ac.free()

	var killer := _make_test_aircraft()
	killer.set_meta("upgrade_stacks", {"qmaam_bloodlust": 1, "adapt_energy": 1})
	killer.altitude = 5000.0
	var victim := _make_test_aircraft()
	victim.team = 1
	victim.set_meta("_last_damage_kind", "qmaam")
	victim.altitude = 1000.0
	var ab2 := AfterburnerCharge.new()
	ab2.charge = 0.0
	SkillHooks.afterburner = ab2
	SkillHooks.dispatch_on_kill(killer, victim)
	_check("QAAM 嗜血：格斗弹击杀 → BLOODLUST",
		killer.status_effects.has(StatusEffects.BLOODLUST), "")
	_check("适应：低位击杀 → 充能 +3", is_equal_approx(ab2.charge, 3.0), "got %.1f" % ab2.charge)
	victim.altitude = 9000.0
	killer.hp = 50.0
	SkillHooks.dispatch_on_kill(killer, victim)
	_check("适应：高位击杀 → +20 HP", is_equal_approx(killer.hp, 70.0), "got %.1f" % killer.hp)
	SkillHooks.afterburner = null
	killer.free()
	victim.free()


# ── F. 王牌字段技 strip 往返（T2 落库 + T1 迁移机制的配对验证）──
func _test_ace_strip_roundtrip() -> void:
	print("── F. 王牌字段技 strip：missile_swarm 应用→剥离 参数还原 ──")
	var sp := SurvivorPlayer.new()
	var ac := _make_test_aircraft()
	ac.params.missile = MissileParams.new()
	ac.params.missile.max_count = 4
	ac.params.missile.max_g = 35.0
	ac.missiles_remaining = 4
	sp.aircraft = ac
	var swarm: Dictionary = {}
	for u in SurvivorData.UPGRADES:
		if str(u.get("id", "")) == "missile_swarm":
			swarm = u
			break
	_check("表中存在 missile_swarm", not swarm.is_empty(), "")
	sp.apply_upgrade_to(ac, swarm)
	_check("应用：弹舱 4→8", ac.params.missile.max_count == 8, "got %d" % ac.params.missile.max_count)
	_check("应用：齐射锁数 ≥8", ac.max_simultaneous_locks >= 8, "got %d" % ac.max_simultaneous_locks)
	sp.strip_upgrade_from(ac, swarm)
	_check("剥离：弹舱回 4", ac.params.missile.max_count == 4, "got %d" % ac.params.missile.max_count)
	_check("剥离：追踪罚回吐（max_g≈35）", is_equal_approx(ac.params.missile.max_g, 35.0),
		"got %.2f" % ac.params.missile.max_g)
	_check("剥离：锁数回 1", ac.max_simultaneous_locks == 1, "")
	ac.free()
	sp.free()


# ── G. T4 按轴计数缩放（recompute_axis_count_skills；spec §6 T4）──
func _test_axis_count_scaling() -> void:
	print("── G. T4 计数缩放：历战者 / 全速推进 / 电子战专家 / 武器大师 ──")
	var ac := _make_test_aircraft()
	ac.params.gun = GunParams.new()
	ac.params.missile = MissileParams.new()
	# 历战者：斗士轴 3 技（veteran_hp 自身 + hp_up + gun_damage）→ +15 HP
	var stacks: Dictionary = {"veteran_hp": 1, "hp_up": 1, "gun_damage": 1}
	SurvivorData.recompute_axis_count_skills(ac, stacks)
	_check("历战者：斗士轴 3 技 → max_hp 100→115", is_equal_approx(ac.params.max_hp, 115.0),
		"got %.1f" % ac.params.max_hp)
	SurvivorData.recompute_axis_count_skills(ac, stacks)
	_check("历战者：重算幂等（仍 115）", is_equal_approx(ac.params.max_hp, 115.0),
		"got %.1f" % ac.params.max_hp)
	stacks["kill_heal"] = 1
	SurvivorData.recompute_axis_count_skills(ac, stacks)
	_check("历战者：+1 斗士技 → 120", is_equal_approx(ac.params.max_hp, 120.0),
		"got %.1f" % ac.params.max_hp)
	# 全速推进：骑士轴 2 技（speed_by_knight 自身 + missile_count）→ ×1.10
	stacks["speed_by_knight"] = 1
	stacks["missile_count"] = 1
	SurvivorData.recompute_axis_count_skills(ac, stacks)
	_check("全速推进：骑士轴 2 技 → ×1.10", is_equal_approx(ac.speed_by_knight_mult, 1.10),
		"got %.2f" % ac.speed_by_knight_mult)
	# 电子战专家：策士轴 1 技（自身）→ +50px（=100m）
	stacks["ew_expert"] = 1
	SurvivorData.recompute_axis_count_skills(ac, stacks)
	_check("电子战专家：策士轴 1 技 → +50px", is_equal_approx(ac.ew_expert_radar_bonus_px, 50.0),
		"got %.0f" % ac.ew_expert_radar_bonus_px)
	# 武器大师：gun+missile 2 件 → CD ×0.90（起手 -10% 与 spec 一致）
	stacks["weapon_master"] = 1
	SurvivorData.recompute_axis_count_skills(ac, stacks)
	_check("武器大师：起手 gun+msl → CD ×0.90", is_equal_approx(ac.weapon_master_cd_mult, 0.90),
		"got %.2f" % ac.weapon_master_cd_mult)
	# 清空 → 全部回默认（零 buff 行为不变 + 历战者差量收回）
	SurvivorData.recompute_axis_count_skills(ac, {})
	_check("清空：速度/雷达/CD 回默认", is_equal_approx(ac.speed_by_knight_mult, 1.0)
		and is_equal_approx(ac.ew_expert_radar_bonus_px, 0.0)
		and is_equal_approx(ac.weapon_master_cd_mult, 1.0), "")
	_check("清空：历战者差量收回（HP 回 100）", is_equal_approx(ac.params.max_hp, 100.0),
		"got %.1f" % ac.params.max_hp)
	ac.free()


# ── H. T5 新机制（spec §6 T5：胆大妄为 / 二段推进 / 电磁炮双发；机炮吊舱走 playtest）──
func _test_t5_mechanisms() -> void:
	print("── H. T5 新机制：胆大妄为 / 二段推进 / 电磁炮双发 ──")
	# 胆大妄为：无 flare → 严格 i-frame + 冷却 + 滚转动画
	var ac := _make_test_aircraft()
	ac.manual_dodge_active = true
	ac.flares_remaining = 0
	ac.do_manual_dodge()
	_check("R 闪避：0.25s 无敌窗", ac.status_effects.has(StatusEffects.INVINCIBLE), "")
	_check("R 闪避：进入冷却", ac._manual_dodge_cd > 0.0, "got %.2f" % ac._manual_dodge_cd)
	_check("R 闪避：滚转动画激活", ac._evade_roll_remaining > 0.0, "")
	ac.free()
	# 胆大妄为 apply/strip 往返：flare +6 收回 + 自动 flare 恢复
	var sp := SurvivorPlayer.new()
	var ac2 := _make_test_aircraft()
	ac2.params.flare = FlareParams.new()
	ac2.params.flare.max_flares = 10
	ac2.flares_remaining = 10
	sp.aircraft = ac2
	var md: Dictionary = {}
	for u in SurvivorData.UPGRADES:
		if str(u.get("id", "")) == "manual_dodge":
			md = u
			break
	sp.apply_upgrade_to(ac2, md)
	_check("胆大妄为应用：flare 10→16 + 禁自动",
		ac2.params.flare.max_flares == 16 and ac2.manual_dodge_active,
		"got %d" % ac2.params.flare.max_flares)
	sp.strip_upgrade_from(ac2, md)
	_check("胆大妄为剥离：flare 回 10 + 恢复自动",
		ac2.params.flare.max_flares == 10 and not ac2.manual_dodge_active,
		"got %d" % ac2.params.flare.max_flares)
	ac2.free()
	sp.free()
	# 二段推进：转弯渐强曲线（关=×1 / 0s=×1 / ≥6.25s=×1.5 封顶）
	var m := Missile.new()
	m.second_stage = false
	m.age = 10.0
	_check("二段关闭：G ×1", is_equal_approx(m._second_stage_g_mult(), 1.0), "")
	m.second_stage = true
	m.age = 0.0
	_check("二段 0s：×1", is_equal_approx(m._second_stage_g_mult(), 1.0), "")
	m.age = 10.0
	_check("二段 10s：×1.5 封顶", is_equal_approx(m._second_stage_g_mult(), 1.5),
		"got %.2f" % m._second_stage_g_mult())
	m.free()
	# 电磁炮双发：升级写到装备资源位
	var sp2 := SurvivorPlayer.new()
	var ac3 := _make_test_aircraft()
	var rg := RailgunEquipment.new()
	var eq_arr: Array[EquipmentParams] = [rg]
	ac3.params.equipment = eq_arr
	sp2.aircraft = ac3
	var rd: Dictionary = {}
	for u in SurvivorData.UPGRADES:
		if str(u.get("id", "")) == "railgun_double":
			rd = u
			break
	_check("双发：默认关闭", not rg.double_shot, "")
	sp2.apply_upgrade_to(ac3, rd)
	_check("双发：升级后装备 double_shot=true", rg.double_shot, "")
	ac3.free()
	sp2.free()


func _make_test_aircraft() -> Aircraft:
	var ac := Aircraft.new()
	ac.params = _make_fresh_params(100.0)
	ac.hp = 100.0
	return ac


func _make_fresh_params(hp: float) -> AircraftParams:
	var p := AircraftParams.new()
	p.max_hp = hp
	return p


func _check(label: String, ok: bool, detail: String) -> void:
	if ok:
		_pass += 1
		print("  ✓ %s" % label)
	else:
		_fail += 1
		print("  ✗ %s — %s" % [label, detail])
