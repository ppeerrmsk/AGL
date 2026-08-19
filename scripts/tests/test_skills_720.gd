extends RefCounted

const SurvivorModeScript = preload("res://scripts/survivor/survivor_mode.gd")

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
	_test_lock_count_upgrades()
	_test_close_range_lock()
	_test_axis_count_scaling()
	_test_t5_mechanisms()
	_test_berserk_virus()
	_test_altitude_actions_and_cycle()
	_test_overload_axis_and_terminals()
	_test_requires_skill_chain()
	_test_status_build_completion()
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
	ac.params.gun = GunParams.new()
	sp.aircraft = ac
	var base_range: float = ac.params.gun.max_range
	# 1 点 + 1 加成 → 进度 2 跨首档（斗士 2 档 = 机炮射程 ×1.20）
	sp.add_axis_point(SurvivorData.AXIS_GLADIATOR)
	_check("1 点未跨档（射程不变）", is_equal_approx(ac.params.gun.max_range, base_range),
		"got %.1f" % ac.params.gun.max_range)
	sp.add_milestone_bonus(SurvivorData.AXIS_GLADIATOR)
	_check("加成 +1 → 进度 2 跨首档（射程 ×1.20）",
		is_equal_approx(ac.params.gun.max_range, base_range * 1.20),
		"got %.1f" % ac.params.gun.max_range)
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
	_check("进度 3 跨第二档（HP 100→125）", is_equal_approx(ac.params.max_hp, 125.0),
		"got %.1f" % ac.params.max_hp)
	# 换型重放：全新 params 重挂时加成计入
	ac.params = _make_fresh_params(200.0)
	ac.params.gun = GunParams.new()
	ac.hp = 200.0
	var fresh_range: float = ac.params.gun.max_range
	sp.reapply_all_milestones()
	_check("换型重放含加成（射程 ×1.20 / hp 200→225）",
		is_equal_approx(ac.params.gun.max_range, fresh_range * 1.20)
		and is_equal_approx(ac.params.max_hp, 225.0), "")
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
	ab.kill_charge_bonus = 0.6
	ab.charge = 0.0
	ab.on_kill_charge()
	_check("检讨：击杀充能 0.8+0.6=1.4", is_equal_approx(ab.charge, 1.4), "got %.1f" % ab.charge)
	ab.duration_mult = 1.5
	ab.charge = AfterburnerCharge.CHARGE_MAX
	var ldr := _make_test_aircraft()
	var ok_act := ab.toggle(ldr)
	# 充能制：满能量(6s)在 ×1.5 减耗下可烧 9s；再 toggle 关闭
	_check("强化加力：满能量续航 6→9s", ok_act and ab.is_active() \
		and is_equal_approx(ab.remaining_seconds(), 9.0),
		"act=%s rem=%.1f" % [ok_act, ab.remaining_seconds()])
	ab.toggle(ldr)
	_check("充能制：激活中再按 → 关闭", not ab.is_active(), "active=%s" % ab.is_active())
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
	_check("适应：低位击杀 → 充能 +0.6", is_equal_approx(ab2.charge, 0.6), "got %.1f" % ab2.charge)
	victim.altitude = 9000.0
	killer.hp = 50.0
	SkillHooks.dispatch_on_kill(killer, victim)
	_check("适应：高位击杀 → +20 HP", is_equal_approx(killer.hp, 70.0), "got %.1f" % killer.hp)
	SkillHooks.afterburner = null
	killer.free()
	victim.free()


# ── F. 可叠加锁数技能（普通 +1 全队 / 蜂群 +3 王牌）──
func _test_lock_count_upgrades() -> void:
	print("── F. 锁数技能：多目标追踪 +1/层全队、导弹蜂群 +3 王牌 ──")
	var sp := SurvivorPlayer.new()
	var lead := _make_test_aircraft()
	var wing := _make_test_aircraft()
	for ac in [lead, wing]:
		ac.params.missile = MissileParams.new()
		ac.params.missile.max_count = 4
		ac.params.missile.max_g = 35.0
		ac.missiles_remaining = 4
	sp.aircraft = lead
	var multi: Dictionary = {}
	var swarm: Dictionary = {}
	for u in SurvivorData.UPGRADES:
		if str(u.get("id", "")) == "multi_lock":
			multi = u
		elif str(u.get("id", "")) == "missile_swarm":
			swarm = u
	_check("表中存在稳定级骑士 multi_lock", not multi.is_empty() \
		and int(multi.get("rarity", -1)) == SurvivorData.Rarity.STABLE \
		and SurvivorData.axis_of_upgrade(multi) == SurvivorData.AXIS_KNIGHT, str(multi))
	_check("multi_lock 每层 +1 / 上限 3", int(multi.get("value", 0)) == 1 \
		and int(multi.get("max_stacks", 0)) == 3, str(multi))
	_check("表中存在 missile_swarm", not swarm.is_empty(), "")
	_check("multi_lock 全队；missile_swarm 为王牌范围",
		str(multi.get("scope", "")) == ""
		and str(swarm.get("scope", "")) == "ace" and not swarm.has("classes"), str(swarm))
	for ac in [lead, wing]:
		sp.apply_upgrade_to(ac, multi)
		sp.apply_upgrade_to(ac, swarm)
	_check("长机锁数 1→5（+1 +3）", lead.max_simultaneous_locks == 5,
		"got %d" % lead.max_simultaneous_locks)
	_check("僚机同吃锁数 1→5", wing.max_simultaneous_locks == 5,
		"got %d" % wing.max_simultaneous_locks)
	_check("蜂群弹舱 4→8", lead.params.missile.max_count == 8,
		"got %d" % lead.params.missile.max_count)
	_check("蜂群追踪 G 35→29.75", is_equal_approx(lead.params.missile.max_g, 29.75),
		"got %.2f" % lead.params.missile.max_g)
	_check("齐射覆盖受锁数限制（2锁/5目标/9弹 → 2）",
		AircraftWeapons._salvo_fire_count(2, 5, 9) == 2, "")
	_check("齐射覆盖受目标与弹量限制",
		AircraftWeapons._salvo_fire_count(7, 3, 9) == 3 \
		and AircraftWeapons._salvo_fire_count(7, 9, 2) == 2, "")
	lead.free()
	wing.free()
	sp.free()


# ── F2. 近距捕获（斗士稳定技能）──
func _test_close_range_lock() -> void:
	print("── F2. 近距捕获：斗士稳定 / 全队 / 距离线性倍率 ──")
	var u: Dictionary = SurvivorData.upgrade_by_id("close_range_lock")
	_check("表中存在斗士稳定技能 close_range_lock", not u.is_empty()
		and int(u.get("rarity", -1)) == SurvivorData.Rarity.STABLE
		and SurvivorData.axis_of_upgrade(u) == SurvivorData.AXIS_GLADIATOR, str(u))
	_check("单层、全队、贴身上限 ×2", str(u.get("stat", "")) == "close_range_lock"
		and int(u.get("max_stacks", 0)) == 1
		and str(u.get("scope", "")) == ""
		and is_equal_approx(float(u.get("value", 0.0)), 2.0), str(u))
	_check("雷达边缘 ×1", is_equal_approx(
		SurvivorData.close_range_lock_mult(1000.0, 1000.0), 1.0), "")
	_check("半程 ×1.5", is_equal_approx(
		SurvivorData.close_range_lock_mult(500.0, 1000.0), 1.5), "")
	_check("四分之一程 ×1.75", is_equal_approx(
		SurvivorData.close_range_lock_mult(250.0, 1000.0), 1.75), "")
	_check("贴身与越界输入安全钳制",
		is_equal_approx(SurvivorData.close_range_lock_mult(0.0, 1000.0), 2.0)
		and is_equal_approx(SurvivorData.close_range_lock_mult(-50.0, 1000.0), 2.0)
		and is_equal_approx(SurvivorData.close_range_lock_mult(1500.0, 1000.0), 1.0), "")
	var sp := SurvivorPlayer.new()
	var lead := _make_test_aircraft()
	var wing := _make_test_aircraft()
	sp.aircraft = lead
	sp.apply_upgrade_to(lead, u)
	sp.apply_upgrade_to(wing, u)
	_check("长机与僚机同吃 ×2 上限",
		is_equal_approx(lead.close_range_lock_max_mult, 2.0)
		and is_equal_approx(wing.close_range_lock_max_mult, 2.0), "")
	lead.free()
	wing.free()
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
	# R 统一入口：胆大妄为无 flare → 严格 i-frame + 冷却 + 滚转动画
	var ac := _make_test_aircraft()
	ac.manual_dodge_active = true
	ac.flares_remaining = 0
	var manual_ok := ac.try_manual_maneuver()
	_check("R 统一入口：胆大妄为被调用", manual_ok, "")
	_check("R 闪避：0.25s 无敌窗", ac.status_effects.has(StatusEffects.INVINCIBLE), "")
	_check("R 闪避：进入冷却", ac._manual_dodge_cd > 0.0, "got %.2f" % ac._manual_dodge_cd)
	_check("R 闪避：滚转动画激活", ac._evade_roll_remaining > 0.0, "")
	_check("R 闪避：冷却中不可重复", not ac.try_manual_maneuver(), "")
	ac.free()
	# 眼镜蛇/J-Turn：不开 evasion/加力也能由 R 直接启动
	var ac_cobra := _make_test_aircraft()
	var cobra := CobraManeuver.new()
	ac_cobra.add_child(cobra)
	cobra._aircraft = ac_cobra  # bench 节点不进 SceneTree，手动完成 _ready 绑定
	ac_cobra.cobra_skill_active = true
	_check("R 眼镜蛇：无需 evasion/加力即可启动",
		not ac_cobra.evasion_mode and ac_cobra.try_manual_maneuver() and cobra.is_active, "")
	ac_cobra.free()
	var ac_herbst := _make_test_aircraft()
	var herbst := HerbstManeuver.new()
	ac_herbst.add_child(herbst)
	herbst._aircraft = ac_herbst
	ac_herbst.evasion_herbst_active = true
	_check("R J-Turn：无需 evasion/加力即可启动",
		not ac_herbst.evasion_mode and ac_herbst.try_manual_maneuver() and herbst.is_active, "")
	ac_herbst.free()
	# 控制身份真源：切控只需翻 AI.manual_control，手动/自动语义随之反转
	var ac_ctrl := _make_test_aircraft()
	var ctrl_ai := AIController.new()
	ac_ctrl._ai_ref = ctrl_ai
	ctrl_ai.manual_control = true
	_check("受控机使用 R 手动路径", ac_ctrl.is_manual_maneuver_controlled(), "")
	ctrl_ai.manual_control = false
	_check("AI 接管后恢复自动路径", not ac_ctrl.is_manual_maneuver_controlled(), "")
	ctrl_ai.free()
	ac_ctrl.free()
	# 五向互斥：任取一张后，其余四张都不再进池
	var cobra_u := SurvivorData.upgrade_by_id("cobra_skill")
	var herbst_u := SurvivorData.upgrade_by_id("evasion_herbst")
	var manual_u := SurvivorData.upgrade_by_id("manual_dodge")
	var roll_u := SurvivorData.upgrade_by_id("displacement_roll")
	var vertical_u := SurvivorData.upgrade_by_id("vertical_break")
	var flare_params := AircraftParams.new()
	flare_params.flare = FlareParams.new()
	_check("取眼镜蛇 → 其余四项主动机动不进池",
		not SurvivorData.is_upgrade_available_for(herbst_u, &"f16", flare_params, {"cobra_skill": 1}, [])
		and not SurvivorData.is_upgrade_available_for(manual_u, &"f16", flare_params, {"cobra_skill": 1}, [])
		and not SurvivorData.is_upgrade_available_for(roll_u, &"f16", flare_params, {"cobra_skill": 1}, [])
		and not SurvivorData.is_upgrade_available_for(vertical_u, &"f16", flare_params, {"cobra_skill": 1}, []), "")
	_check("取 J-Turn → 眼镜蛇/胆大妄为不进池",
		not SurvivorData.is_upgrade_available_for(cobra_u, &"f16", flare_params, {"evasion_herbst": 1}, [])
		and not SurvivorData.is_upgrade_available_for(manual_u, &"f16", flare_params, {"evasion_herbst": 1}, []), "")
	_check("取胆大妄为 → 眼镜蛇/J-Turn 不进池",
		not SurvivorData.is_upgrade_available_for(cobra_u, &"f16", flare_params, {"manual_dodge": 1}, [])
		and not SurvivorData.is_upgrade_available_for(herbst_u, &"f16", flare_params, {"manual_dodge": 1}, []), "")
	_check("取位移滚转/垂直越过 → 双向互斥完整",
		not SurvivorData.is_upgrade_available_for(vertical_u, &"f16", flare_params, {"displacement_roll": 1}, [])
		and not SurvivorData.is_upgrade_available_for(roll_u, &"f16", flare_params, {"vertical_break": 1}, [])
		and not SurvivorData.is_upgrade_available_for(cobra_u, &"f16", flare_params, {"vertical_break": 1}, []), "")
	# 位移滚转：平分固定向右、曲线净侧移 350px、ACTIVE 窗口拒绝新命中。
	var roll_ac := _make_test_aircraft()
	roll_ac.global_position = Vector2.ZERO
	roll_ac.heading = 0.0
	roll_ac.speed = 250.0
	roll_ac.displacement_roll_active = true
	var roll_started := roll_ac.try_manual_maneuver()
	var roll_hit_blocked := not roll_ac.can_accept_new_hit("gun") and not roll_ac.can_accept_new_hit("missile")
	var roll_hp := roll_ac.hp
	roll_ac.take_damage(10.0, null, "gun")
	var weapon_damage_blocked := is_equal_approx(roll_ac.hp, roll_hp)
	roll_ac.take_damage(3.0, roll_ac, "jam_field")
	var existing_effect_continues := is_equal_approx(roll_ac.hp, roll_hp - 3.0)
	for _i in range(23):
		roll_ac._advance_active_special_maneuver(0.05)
		AircraftPhysics.apply_movement(roll_ac, 0.05)
	_check("位移滚转：平分向右且净侧移 350px",
		roll_started and absf(roll_ac.global_position.x - 350.0) <= 5.0,
		"pos=%s" % roll_ac.global_position)
	_check("位移滚转：普通前向运动继续", roll_ac.global_position.y < -100.0, "pos=%s" % roll_ac.global_position)
	_check("位移滚转：ACTIVE 拒绝新命中且 EXIT 恢复", roll_hit_blocked and roll_ac.can_accept_new_hit("gun"), "")
	_check("位移滚转：武器伤害被兜底拦截但既有状态类伤害继续", weapon_damage_blocked and existing_effect_continues, "hp=%.1f" % roll_ac.hp)
	roll_ac.free()
	# 方向安全：右边界选左；角落两侧都非法时拒绝且不进冷却。
	var edge_roll := _make_test_aircraft()
	edge_roll.global_position = Vector2(MapBoundary.world_half_px() - 100.0, 0.0)
	edge_roll.heading = 0.0
	edge_roll.displacement_roll_active = true
	var edge_started := edge_roll.try_manual_maneuver()
	_check("位移滚转：靠右边界确定性选择左侧", edge_started and edge_roll._active_special_side < 0.0, "")
	edge_roll.free()
	var corner_roll := _make_test_aircraft()
	corner_roll.global_position = Vector2(MapBoundary.world_half_px() - 100.0, -MapBoundary.world_half_px() + 100.0)
	corner_roll.heading = deg_to_rad(45.0)
	corner_roll.displacement_roll_active = true
	_check("位移滚转：两侧均越界时拒绝且不消耗冷却",
		not corner_roll.try_manual_maneuver() and is_equal_approx(corner_roll._shared_maneuver_cooldown(), 0.0), "")
	corner_roll.free()
	# 垂直越过：LOW 拉升 900m；动作期高度命令排队到 EXIT。
	var vertical_ac := _make_test_aircraft()
	vertical_ac.altitude = 2000.0
	vertical_ac.target_altitude = 2000.0
	vertical_ac.vertical_break_active = true
	var vertical_started := vertical_ac.try_manual_maneuver()
	var vertical_published_climb := vertical_ac.altitude_action == Aircraft.AltitudeAction.CLIMB
	vertical_ac._advance_active_special_maneuver(0.65)
	var pitch_peak_visible := absf(vertical_ac._active_special_pitch_visual - 1.0) <= 0.01
	vertical_ac.target_altitude = 5500.0
	for _i in range(13):
		vertical_ac._advance_active_special_maneuver(0.05)
	_check("垂直越过：LOW 全程发布 CLIMB 且 EXIT 回 NONE",
		vertical_started and vertical_published_climb \
		and vertical_ac.altitude_action == Aircraft.AltitudeAction.NONE, "")
	_check("垂直越过：LOW 净拉升 900m", vertical_started and absf(vertical_ac.altitude - 2900.0) <= 10.0,
		"alt=%.1f" % vertical_ac.altitude)
	_check("垂直越过：动作中最新高度命令于 EXIT 生效", is_equal_approx(vertical_ac.target_altitude, 5500.0),
		"target=%.1f" % vertical_ac.target_altitude)
	_check("垂直越过：中点俯仰投影达到峰值且 EXIT 清零",
		pitch_peak_visible and is_zero_approx(vertical_ac._active_special_pitch_visual), "")
	vertical_ac.free()
	var dive_ac := _make_test_aircraft()
	dive_ac.altitude = 5500.0
	dive_ac.target_altitude = 5500.0
	dive_ac.vertical_break_active = true
	var dive_started := dive_ac.try_manual_maneuver()
	var vertical_published_dive := dive_ac.altitude_action == Aircraft.AltitudeAction.DIVE
	for _i in range(26):
		dive_ac._advance_active_special_maneuver(0.05)
	_check("垂直越过：MID 净俯冲 900m 且不突破有效顶速",
		dive_started and absf(dive_ac.altitude - 4600.0) <= 10.0
		and dive_ac.speed <= AircraftPhysics.effective_max_speed_kmh(dive_ac) / 3.6 + 0.01 \
		and vertical_published_dive and dive_ac.altitude_action == Aircraft.AltitudeAction.NONE,
		"alt=%.1f speed=%.1f" % [dive_ac.altitude, dive_ac.speed])
	dive_ac.free()
	var clipped_ac := _make_test_aircraft()
	clipped_ac.params.max_altitude = 2700.0
	clipped_ac.altitude = 2000.0
	clipped_ac.target_altitude = 2000.0
	clipped_ac.vertical_break_active = true
	var clipped_started := clipped_ac.try_manual_maneuver()
	for _i in range(26):
		clipped_ac._advance_active_special_maneuver(0.05)
	_check("垂直越过：可用空间 700m 时按边界裁切", clipped_started and absf(clipped_ac.altitude - 2700.0) <= 10.0, "")
	clipped_ac.free()
	var blocked_vertical := _make_test_aircraft()
	blocked_vertical.params.max_altitude = 2500.0
	blocked_vertical.altitude = 2000.0
	blocked_vertical.target_altitude = 2000.0
	blocked_vertical.vertical_break_active = true
	_check("垂直越过：可用空间不足 600m 时拒绝且无冷却",
		not blocked_vertical.try_manual_maneuver() and is_equal_approx(blocked_vertical._shared_maneuver_cooldown(), 0.0), "")
	blocked_vertical.free()
	# 同一 Squad 的第二架飞机不能靠切控绕过第一架刚启动的冷却。
	var shared_squad := Squad.new()
	var shared_a := _make_test_aircraft()
	var shared_b := _make_test_aircraft()
	var shared_ai_a := AIController.new()
	var shared_ai_b := AIController.new()
	shared_ai_a.squad = shared_squad
	shared_ai_b.squad = shared_squad
	shared_a._ai_ref = shared_ai_a
	shared_b._ai_ref = shared_ai_b
	shared_squad.leader = shared_a
	shared_squad.members = [shared_a, shared_b]
	shared_a.displacement_roll_active = true
	shared_b.displacement_roll_active = true
	var first_shared := shared_a.try_manual_maneuver()
	shared_squad.set_leader(shared_b)
	_check("主动机动：切控不能绕过小队共享冷却", first_shared and not shared_b.try_manual_maneuver()
		and shared_squad.active_maneuver_cooldown_s > 0.0, "")
	shared_ai_a.free()
	shared_ai_b.free()
	shared_a.free()
	shared_b.free()
	# 胆大妄为全队下发：每架 +6 flare，AI 僚机受威胁自动释放
	var sp := SurvivorPlayer.new()
	var ac2 := _make_test_aircraft()
	var wing2 := _make_test_aircraft()
	ac2.params.flare = FlareParams.new()
	ac2.params.flare.max_flares = 10
	ac2.flares_remaining = 10
	wing2.params.flare = FlareParams.new()
	wing2.params.flare.max_flares = 10
	wing2.flares_remaining = 10
	sp.aircraft = ac2
	var md: Dictionary = {}
	for u in SurvivorData.UPGRADES:
		if str(u.get("id", "")) == "manual_dodge":
			md = u
			break
	sp.apply_upgrade_to(ac2, md)
	sp.apply_upgrade_to(wing2, md)
	_check("胆大妄为全队应用：两机 flare 10→16 + 禁普通自动",
		ac2.params.flare.max_flares == 16 and ac2.manual_dodge_active
		and wing2.params.flare.max_flares == 16 and wing2.manual_dodge_active,
		"lead=%d wing=%d" % [ac2.params.flare.max_flares, wing2.params.flare.max_flares])
	_check("胆大妄为不再是 ace scope", str(md.get("scope", "")) == "", str(md.get("scope", "")))
	# 后方敌机正对僚机开炮 → AI 路径自动滚转；不要求加力/evasion。
	var tail_enemy := _make_test_aircraft()
	tail_enemy.team = CombatUnit.TEAM_HOSTILE
	tail_enemy.params.gun = GunParams.new()
	tail_enemy.params.gun.max_range = 2000.0
	tail_enemy.params.gun.fire_cone_half_angle = 15.0
	tail_enemy.global_position = Vector2(0.0, 100.0)
	tail_enemy.heading = 0.0
	tail_enemy.speed = 300.0
	tail_enemy.is_firing = true
	CombatUnit.all_units.append(tail_enemy)
	tail_enemy.combat_target = wing2
	tail_enemy.weapon_mode = Aircraft.WeaponMode.GUN
	wing2._update_manual_dodge_skill()
	_check("胆大妄为 AI 僚机：后方机炮威胁自动释放",
		wing2._manual_dodge_cd > 0.0 and wing2.status_effects.has(StatusEffects.INVINCIBLE), "")
	var ai_cobra := _make_test_aircraft()
	var ai_cobra_node := CobraManeuver.new()
	ai_cobra.add_child(ai_cobra_node)
	ai_cobra_node._aircraft = ai_cobra
	ai_cobra.cobra_skill_active = true
	tail_enemy.combat_target = ai_cobra
	ai_cobra._update_cobra_skill(0.0)
	_check("眼镜蛇 AI 僚机：无需加力/evasion，后方机炮威胁自动释放",
		not ai_cobra.evasion_mode and ai_cobra_node.is_active, "")
	var ai_herbst := _make_test_aircraft()
	var ai_herbst_node := HerbstManeuver.new()
	ai_herbst.add_child(ai_herbst_node)
	ai_herbst_node._aircraft = ai_herbst
	ai_herbst.evasion_herbst_active = true
	tail_enemy.combat_target = ai_herbst
	ai_herbst._update_evasion_herbst_skill(0.0)
	_check("J-Turn AI 僚机：无需加力/evasion，后方机炮威胁自动释放",
		not ai_herbst.evasion_mode and ai_herbst_node.is_active, "")
	var ai_roll := _make_test_aircraft()
	ai_roll.displacement_roll_active = true
	tail_enemy.combat_target = ai_roll
	ai_roll._update_active_special_maneuver(0.11)
	_check("位移滚转 AI 僚机：后方闭合威胁自动释放", ai_roll.is_active_special_maneuver(), "")
	var ai_vertical := _make_test_aircraft()
	ai_vertical.altitude = 2000.0
	ai_vertical.target_altitude = 2000.0
	ai_vertical.vertical_break_active = true
	tail_enemy.combat_target = ai_vertical
	tail_enemy.altitude = ai_vertical.altitude
	ai_vertical._update_active_special_maneuver(0.11)
	_check("垂直越过 AI 僚机：后方闭合威胁自动释放", ai_vertical.is_active_special_maneuver(), "")
	var controlled_cobra := _make_test_aircraft()
	var controlled_cobra_node := CobraManeuver.new()
	controlled_cobra.add_child(controlled_cobra_node)
	controlled_cobra_node._aircraft = controlled_cobra
	controlled_cobra.cobra_skill_active = true
	var controlled_ai := AIController.new()
	controlled_ai.manual_control = true
	controlled_cobra._ai_ref = controlled_ai
	tail_enemy.combat_target = controlled_cobra
	controlled_cobra._update_cobra_skill(0.0)
	var stayed_manual := not controlled_cobra_node.is_active
	var manual_started := controlled_cobra.try_manual_maneuver()
	_check("当前操控机：同一威胁不自动，按 R 才释放",
		stayed_manual and manual_started and controlled_cobra_node.is_active, "")
	CombatUnit.all_units.erase(tail_enemy)
	tail_enemy.free()
	ai_cobra.free()
	ai_herbst.free()
	ai_roll.free()
	ai_vertical.free()
	controlled_ai.free()
	controlled_cobra.free()
	ac2.free()
	wing2.free()
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


# ── I. 狂化病毒：动态僚机门 / FREE 锁定 / 机动与 CD / 击杀嗜血 / 接管边界 ──
func _test_berserk_virus() -> void:
	print("── I. 狂化病毒：动态僚机门 / FREE / 机动-CD / BLOODLUST / 切控 ──")
	var upgrade := SurvivorData.upgrade_by_id(SkillHooks.SKILL_BERSERK_VIRUS)
	_check("狂化病毒：次世代斗士战区奖励数据存在",
		not upgrade.is_empty() \
		and int(upgrade.get("rarity", -1)) == SurvivorData.Rarity.NEXT_GEN \
		and bool(upgrade.get("evolved", false)) \
		and SurvivorData.axis_of_upgrade(upgrade) == SurvivorData.AXIS_GLADIATOR \
		and int(upgrade.get("max_stacks", 0)) == 1, str(upgrade))

	var controlled := _make_test_aircraft()
	controlled.team = CombatUnit.TEAM_PLAYER
	controlled.squad_slot = 1
	var controlled_ai := AIController.new()
	controlled_ai.aircraft = controlled
	controlled_ai.manual_control = true
	controlled.add_child(controlled_ai)
	controlled._ai_ref = controlled_ai
	AircraftRenderer.player_ref = controlled

	var wing := _make_test_aircraft()
	wing.team = CombatUnit.TEAM_PLAYER
	wing.squad_slot = 2
	var wing_ai := AIController.new()
	wing_ai.aircraft = wing
	wing_ai.manual_control = false
	wing.add_child(wing_ai)
	wing._ai_ref = wing_ai

	var sq := Squad.new()
	sq.add_member(controlled)
	sq.add_member(wing)
	sq.leader = controlled
	controlled_ai.squad = sq
	wing_ai.squad = sq
	var sp := SurvivorPlayer.new()
	sp.aircraft = controlled
	sp.apply_upgrade_to(controlled, upgrade)
	sp.apply_upgrade_to(wing, upgrade)
	controlled.set_meta("upgrade_stacks", {SkillHooks.SKILL_BERSERK_VIRUS: 1})
	wing.set_meta("upgrade_stacks", {SkillHooks.SKILL_BERSERK_VIRUS: 1})

	_check("狂化病毒：亲控机持旗标但不吃效果，AI 僚机动态生效",
		controlled.berserk_virus_active and wing.berserk_virus_active \
		and not controlled.is_berserk_virus_wingman() and wing.is_berserk_virus_wingman(), "")
	_check("狂化病毒：获得时锁定 FREE + COMBAT_SPREAD",
		wing_ai.squad_engage_mode == AIController.SquadEngageMode.FREE \
		and sq.engage_mode == Squad.EngageMode.FREE \
		and sq.formation == Squad.Formation.COMBAT_SPREAD, "")

	var base_g := AircraftPhysics.effective_max_g(controlled)
	var base_struct_g := AircraftPhysics.effective_max_g_instant(controlled)
	var base_roll := AircraftPhysics.base_roll_rate(controlled)
	_check("狂化病毒：僚机持续/结构 G 与滚转均 ×1.25",
		is_equal_approx(AircraftPhysics.effective_max_g(wing), base_g * 1.25) \
		and is_equal_approx(AircraftPhysics.effective_max_g_instant(wing), base_struct_g * 1.25) \
		and is_equal_approx(AircraftPhysics.base_roll_rate(wing), base_roll * 1.25), "")
	_check("狂化病毒：僚机加减速 ×1.25，亲控机保持基线",
		is_equal_approx(AircraftPhysics.effective_accel_mult(wing, false), 1.25) \
		and is_equal_approx(AircraftPhysics.effective_decel_mult(wing), 1.25) \
		and is_equal_approx(AircraftPhysics.effective_accel_mult(controlled, false), 1.0) \
		and is_equal_approx(AircraftPhysics.effective_decel_mult(controlled), 1.0), "")
	_check("狂化病毒：weapon CD rate ×1.40 / flare rate ×1.50，不改 missile reload",
		is_equal_approx(wing.cd_rate("weapon"), 1.40) \
		and is_equal_approx(wing.cd_rate("flare"), 1.50) \
		and is_equal_approx(wing.cd_rate("missile_reload"), 1.0) \
		and is_equal_approx(controlled.cd_rate("weapon"), 1.0), "")

	var victim := _make_test_aircraft()
	victim.team = CombatUnit.TEAM_HOSTILE
	wing_ai.squad_engage_mode = AIController.SquadEngageMode.GUARD_REAR
	sq.engage_mode = Squad.EngageMode.GUARD_REAR
	sq.formation = Squad.Formation.WEDGE
	wing.combat_target = victim
	wing.commanded_target = victim
	wing.target_position = Vector2(321.0, -654.0)
	wing.enforce_berserk_virus_free_mode()
	_check("狂化病毒：FREE 兜底不清战斗/点名/移动命令",
		wing_ai.squad_engage_mode == AIController.SquadEngageMode.FREE \
		and sq.formation == Squad.Formation.COMBAT_SPREAD \
		and wing.combat_target == victim and wing.commanded_target == victim \
		and wing.target_position == Vector2(321.0, -654.0), "")
	_check("狂化病毒：复用 FREE 局部扫描与既有 leash，不做全图扫荡",
		is_equal_approx(AIController.SQUAD_FREE_SCAN_RANGE, 1500.0) \
		and is_equal_approx(AIController.SQUAD_LEASH_DIST, 1800.0) \
		and is_equal_approx(AIController.SQUAD_LEASH_HYSTERESIS, 0.5), "")
	SkillHooks.dispatch_on_kill(wing, victim)
	_check("狂化病毒：AI 僚机击杀进入标准 9 秒 BLOODLUST",
		is_equal_approx(float(wing.status_effects.get(StatusEffects.BLOODLUST, 0.0)),
			SkillHooks.KILL_BLOODLUST_DURATION), str(wing.status_effects))
	SkillHooks.dispatch_on_kill(controlled, victim)
	_check("狂化病毒：亲控机仅凭本技能击杀不触发 BLOODLUST",
		not controlled.status_effects.has(StatusEffects.BLOODLUST), str(controlled.status_effects))

	var mode := SurvivorModeScript.new()
	mode._squad = sq
	mode.player_aircraft = controlled
	mode.upgrade_stacks = {SkillHooks.SKILL_BERSERK_VIRUS: 1}
	mode._switch_control_to_slot(2)
	_check("狂化病毒：数字键主动接管被拒绝", mode.player_aircraft == controlled, "")
	controlled.is_destroyed = true
	sq.leader = wing
	mode._on_squad_leader_changed(wing)
	_check("狂化病毒：长机阵亡仍自动继任，新长机立即退出狂化倍率",
		mode.player_aircraft == wing and wing_ai.manual_control \
		and not wing.is_berserk_virus_wingman(), "")
	AircraftRenderer.player_ref = null
	ObjectiveContext.protectee = null
	mode.free()
	sp.free()
	victim.free()
	controlled.free()
	wing.free()


# ── I. 高度动作真源 / GUN_TAILED / 4 秒反制 / 高度能量循环 ──
func _test_altitude_actions_and_cycle() -> void:
	print("── I. 高度动作：统一状态 / 4 秒反制 / 双向资源循环 ──")
	var ac := _make_test_aircraft()
	ac.team = CombatUnit.TEAM_PLAYER
	ac.speed = 300.0
	ac.altitude = 5000.0
	ac.altitude_preference = Aircraft.AltitudePreference.PREFER_LOW
	ac.target_altitude = 6000.0
	AircraftPhysics.update_altitude(ac, 0.01)
	_check("Q 爬升命令前：未过 30m/s 不发布动作",
		ac.altitude_action == Aircraft.AltitudeAction.NONE \
		and ac.altitude_action_enter_serial == 0 and ac.vertical_speed < 30.0,
		"action=%s vs=%.1f serial=%d" % [ac.altitude_action_name(), ac.vertical_speed,
			ac.altitude_action_enter_serial])
	AircraftPhysics.update_altitude(ac, 0.1)
	_check("同档自然升高：即使过 30m/s 也保持 NONE",
		ac.altitude_action == Aircraft.AltitudeAction.NONE \
		and ac.altitude_action_enter_serial == 0 and ac.vertical_speed > 30.0,
		"action=%s vs=%.1f serial=%d" % [ac.altitude_action_name(), ac.vertical_speed,
			ac.altitude_action_enter_serial])
	ac.command_altitude_preference(Aircraft.AltitudePreference.PREFER_CLIMB)
	AircraftPhysics.update_altitude(ac, 0.01)
	var climb_serial: int = ac.altitude_action_enter_serial
	_check("Q LOW→HIGH：过 30m/s 后发布一次 CLIMB",
		ac.altitude_action == Aircraft.AltitudeAction.CLIMB and climb_serial == 1 \
		and ac.altitude_action_command == Aircraft.AltitudeAction.CLIMB,
		"action=%s vs=%.1f serial=%d" % [ac.altitude_action_name(), ac.vertical_speed, climb_serial])
	ac.target_altitude = 4000.0
	ac.command_altitude_preference(Aircraft.AltitudePreference.PREFER_LOW)
	AircraftPhysics.update_altitude(ac, 0.1)
	_check("Q HIGH→LOW：过 -30m/s 后发布一次 DIVE",
		ac.altitude_action == Aircraft.AltitudeAction.DIVE \
		and ac.altitude_action_enter_serial > climb_serial \
		and ac.altitude_action_command == Aircraft.AltitudeAction.DIVE,
		"action=%s vs=%.1f serial=%d" % [ac.altitude_action_name(), ac.vertical_speed,
			ac.altitude_action_enter_serial])
	ac.target_altitude = ac.altitude
	AircraftPhysics.update_altitude(ac, 0.1)
	var consumed_serial: int = ac.altitude_action_enter_serial
	ac.target_altitude = 4000.0
	ac.vertical_speed = -120.0
	AircraftPhysics.update_altitude(ac, 0.01)
	_check("同一 Q 命令消费后：再次自然俯冲不重入 DIVE",
		ac.altitude_action == Aircraft.AltitudeAction.NONE \
		and ac.altitude_action_command == Aircraft.AltitudeAction.NONE \
		and ac.altitude_action_enter_serial == consumed_serial,
		"action=%s command=%d serial=%d" % [ac.altitude_action_name(),
			ac.altitude_action_command, ac.altitude_action_enter_serial])
	ac.is_stalled = true
	ac.vertical_speed = -120.0
	AircraftPhysics.update_altitude(ac, 0.1)
	_check("失速强制下坠：状态保持 NONE",
		ac.altitude_action == Aircraft.AltitudeAction.NONE, ac.altitude_action_name())
	ac.is_stalled = false

	var attacker := _make_test_aircraft()
	attacker.team = CombatUnit.TEAM_HOSTILE
	attacker.params.gun = GunParams.new()
	attacker.params.gun.max_range = 2000.0
	attacker.params.gun.fire_cone_half_angle = 15.0
	attacker.params.gun.burst_count = 10
	attacker.global_position = Vector2(0.0, 200.0)
	attacker.altitude = ac.altitude
	attacker.heading = 0.0
	attacker.combat_target = ac
	attacker.weapon_mode = Aircraft.WeaponMode.GUN
	attacker.ammo = 20
	_check("GUN_TAILED：后方 GUN 意图 + 正式前置解成立",
		AircraftWeapons.is_gun_tailed_by(attacker, ac), "")
	attacker.global_position = Vector2(200.0, 0.0)
	_check("GUN_TAILED：侧向攻击者不成立",
		not AircraftWeapons.is_gun_tailed_by(attacker, ac), "")
	attacker.global_position = Vector2(0.0, 2000.0)
	_check("GUN_TAILED：正式机炮射程外不成立",
		not AircraftWeapons.is_gun_tailed_by(attacker, ac), "")
	attacker.global_position = Vector2(0.0, 200.0)
	attacker.ammo = 0
	_check("GUN_TAILED：无弹且没有已承诺梭不成立",
		not AircraftWeapons.is_gun_tailed_by(attacker, ac), "")
	attacker.ammo = 20
	attacker.weapon_mode = Aircraft.WeaponMode.MISSILE
	_check("GUN_TAILED：导弹意图不成立",
		not AircraftWeapons.is_gun_tailed_by(attacker, ac), "")
	attacker.weapon_mode = Aircraft.WeaponMode.GUN
	attacker._gun_burst_rounds_left = 5
	attacker._gun_burst_target_id = ac.get_instance_id()
	attacker._gun_lead_heading = 0.0
	ac._set_altitude_action(Aircraft.AltitudeAction.CLIMB)
	var attacker_heading_before := attacker.heading
	ac.report_gun_tailed(attacker)
	_check("CLIMB 反制：不传送、不强改攻击者航向或取消当前梭",
		is_equal_approx(attacker.heading, attacker_heading_before) \
		and attacker.combat_target == ac and attacker._gun_burst_rounds_left == 5, "")
	var status_ids: Array[StringName] = []
	for entry in AircraftRenderer.status_label_entries(ac):
		status_ids.append(StringName(entry.get("id", &"")))
	_check("状态栏：GUN_TAILED 保留，CLIMB 合并到详细 ALT 行",
		&"gun_tailed" in status_ids and &"altitude_climb" not in status_ids \
		and &"altitude_dive" not in status_ids, str(status_ids))
	ac.global_position.x = 100.0
	var frozen_ok := AircraftWeapons._refresh_committed_gun_aim(attacker, attacker.params.gun)
	_check("CLIMB 窗口：已承诺梭保留旧世界射向",
		frozen_ok and attacker._gun_climb_frozen_target_id == ac.get_instance_id() \
		and is_zero_approx(attacker._gun_lead_heading),
		"frozen=%d heading=%.3f" % [attacker._gun_climb_frozen_target_id,
			attacker._gun_lead_heading])
	ac._tick_climb_counter_window(4.01)
	_check("CLIMB 窗口：4 秒后关闭且不靠持续爬升刷新", not ac.climb_counter_window_active(), "")

	var missile := Missile.new()
	missile.params = MissileParams.new()
	missile.target = ac
	missile.is_active = true
	missile.has_guidance = true
	missile.global_position = Vector2(100.0, 300.0)
	missile.heading = 0.0
	missile.speed = 400.0
	ac.speed = 200.0
	ac.heading = 0.0
	ac._set_altitude_action(Aircraft.AltitudeAction.NONE)
	ac._set_altitude_action(Aircraft.AltitudeAction.CLIMB)
	_check("迫近导弹：60m/s + 3.5s 共用门可触发确定性失导",
		ac.try_climb_counter_missile(missile) and missile.climb_break_disrupted \
		and missile.is_flare_jammed and not missile.has_guidance, "")
	missile.free()
	ac._tick_climb_counter_window(4.01)
	var late_missile := Missile.new()
	late_missile.params = MissileParams.new()
	late_missile.target = ac
	late_missile.is_active = true
	late_missile.has_guidance = true
	late_missile.global_position = Vector2(100.0, 300.0)
	late_missile.heading = 0.0
	late_missile.speed = 400.0
	_check("迫近导弹：4 秒窗口结束后不再失导",
		not ac.try_climb_counter_missile(late_missile) \
		and not late_missile.climb_break_disrupted and late_missile.has_guidance, "")
	late_missile.free()

	ac.altitude = 5000.0
	attacker.altitude = 5500.0
	ac._set_altitude_action(Aircraft.AltitudeAction.NONE)
	AircraftFormation._update_altitude(ac, {"ldr": attacker, "b": 1.0}, 0.1)
	_check("编队自然追高度：即使过 30m/s 也保持 NONE",
		ac.altitude_action == Aircraft.AltitudeAction.NONE and ac.vertical_speed >= 30.0,
		"action=%s vs=%.1f" % [ac.altitude_action_name(), ac.vertical_speed])
	attacker._set_altitude_action(Aircraft.AltitudeAction.CLIMB)
	AircraftFormation._update_altitude(ac, {"ldr": attacker, "b": 1.0}, 0.1)
	_check("编队 Q 换档：僚机镜像长机 CLIMB",
		ac.altitude_action == Aircraft.AltitudeAction.CLIMB,
		"action=%s vs=%.1f" % [ac.altitude_action_name(), ac.vertical_speed])
	attacker._set_altitude_action(Aircraft.AltitudeAction.NONE)

	var cycle := SurvivorData.upgrade_by_id("altitude_energy_cycle")
	_check("高度能量循环：实验级单层 mobility/骑士定稿数据存在",
		not cycle.is_empty() and int(cycle.get("rarity", -1)) == SurvivorData.Rarity.EXPERIMENTAL \
		and int(cycle.get("max_stacks", 0)) == 1 \
		and str(cycle.get("category", "")) == "mobility" \
		and SurvivorData.axis_of_upgrade(cycle) == SurvivorData.AXIS_KNIGHT, str(cycle))
	ac.params.gun = GunParams.new()
	ac.params.gun.max_ammo = 100
	ac.ammo = 100
	var sp := SurvivorPlayer.new()
	sp.aircraft = ac
	sp.apply_upgrade_to(ac, cycle)
	ac._set_altitude_action(Aircraft.AltitudeAction.DIVE)
	AircraftWeapons.update_gun(ac, 1.0)
	_check("高度能量循环：DIVE 以 25发/s 越过基础弹仓", ac.ammo == 125,
		"ammo=%d" % ac.ammo)
	AircraftWeapons.update_gun(ac, 40.0)
	_check("高度能量循环：超储硬封顶 2×max_ammo", ac.ammo == 200,
		"ammo=%d" % ac.ammo)
	ac._set_altitude_action(Aircraft.AltitudeAction.NONE)
	AircraftWeapons.update_gun(ac, 1.0)
	_check("高度能量循环：NONE 不继续回机炮且不截断超储", ac.ammo == 200,
		"ammo=%d" % ac.ammo)
	ac.enable_gun_reload = true
	ac._gun_reload_active = true
	ac._gun_reload_timer = ac.gun_reload_duration
	AircraftWeapons.update_gun(ac, 0.01)
	_check("高度能量循环：基础整匣装填不截断合法超储", ac.ammo == 200,
		"ammo=%d" % ac.ammo)

	var ab := AfterburnerCharge.new()
	ab.charge = 0.0
	ab.update(1.0, 1.0, false, 0.2)
	_check("高度能量循环：停用加力时基础 0.2 + CLIMB 0.2 = 0.4/s",
		is_equal_approx(ab.charge, 0.4), "charge=%.2f" % ab.charge)
	ab.charge = AfterburnerCharge.CHARGE_MAX
	_check("高度能量循环：加力窗口可启动", ab.toggle(ac), "")
	ab.update(1.0, 1.0, false, 0.2)
	_check("高度能量循环：开加力爬升净耗 0.8/s",
		is_equal_approx(ab.charge, AfterburnerCharge.CHARGE_MAX - 0.8),
		"charge=%.2f" % ab.charge)
	ab.toggle(ac)
	sp.free()
	attacker.free()
	ac.free()


# ── J. 超载技能轴与终端闭合（2026-08-06：导弹流统一归骑士）──
func _test_overload_axis_and_terminals() -> void:
	print("── I. 超载：十二条全归骑士 / 同轴不重复 +1 / 八个来源均可解锁终端 ──")
	var overload_ids: Array[String] = [
		"cloud_overload", "skill_evade_missile_overload", "skill_flare_overload",
		"overload_duration_4x", "overload_extended_ammo", "overload_to_bloodlust",
		"jam_self_overload", "assassin_revenge", "sig_mig41", "storm_i", "storm_ii",
		"fire_control_saturation",
	]
	for uid in overload_ids:
		var u := SurvivorData.upgrade_by_id(uid)
		_check("%s 归骑士轴" % uid, not u.is_empty()
			and SurvivorData.axis_of_upgrade(u) == SurvivorData.AXIS_KNIGHT, str(u))

	var cloud := SurvivorData.upgrade_by_id("cloud_overload")
	var flare := SurvivorData.upgrade_by_id("skill_flare_overload")
	var resonance := SurvivorData.upgrade_by_id("overload_to_bloodlust")
	_check("云中超载/焰诱共振不再重复给骑士 +1",
		str(cloud.get("milestone_plus", "")) == ""
		and str(flare.get("milestone_plus", "")) == "", "仍有同轴 milestone_plus")
	_check("噬血共振保留斗士 +1 跨轴桥",
		str(resonance.get("milestone_plus", "")) == SurvivorData.AXIS_GLADIATOR,
		str(resonance.get("milestone_plus", "")))

	var overload_sources: Array[String] = [
		"cloud_overload", "skill_evade_missile_overload", "skill_flare_overload",
		"jam_self_overload", "assassin_revenge", "sig_mig41", "storm_i",
		"fire_control_saturation",
	]
	for terminal_id in ["overload_duration_4x", "overload_extended_ammo", "overload_to_bloodlust", "storm_ii"]:
		var terminal := SurvivorData.upgrade_by_id(terminal_id)
		var prereq: Array = terminal.get("requires_skill", []) as Array
		_check("%s 的超载来源前置完整" % terminal_id,
			prereq.size() == overload_sources.size()
			and overload_sources.all(func(source_id: String) -> bool: return prereq.has(source_id)),
			str(prereq))

	var saturation := SurvivorData.upgrade_by_id("fire_control_saturation")
	_check("火控饱和：实验级 / 骑士轴 / 王牌专属",
		int(saturation.get("rarity", -1)) == SurvivorData.Rarity.EXPERIMENTAL \
		and SurvivorData.axis_of_upgrade(saturation) == SurvivorData.AXIS_KNIGHT \
		and str(saturation.get("scope", "")) == "ace" and not saturation.has("classes"),
		str(saturation))
	var ac := _make_test_aircraft()
	ac.team = CombatUnit.TEAM_PLAYER
	ac.max_simultaneous_locks = 5
	ac.set_meta("upgrade_stacks", {"fire_control_saturation": 1})
	var targets: Array[Aircraft] = []
	for _i in SkillHooks.FIRE_CONTROL_SATURATION_LOCKS:
		var target := _make_test_aircraft()
		target.team = CombatUnit.TEAM_HOSTILE
		targets.append(target)
		ac.radar_targets[target] = ac.params.lock_time
	var state: Dictionary = {"cooldown": 0.0, "latched": false}
	_check("火控饱和：首次五锁触发 6s 超载并临时 +2 锁数",
		SkillHooks.try_fire_control_saturation(ac, state, 0.2) \
		and is_equal_approx(float(ac.status_effects.get(StatusEffects.OVERLOAD, 0.0)), 6.0) \
		and ac.effective_max_locks() == 7 \
		and is_equal_approx(float(state.get("cooldown", 0.0)), 20.0), str(state))
	ac.radar_targets.erase(targets.back())
	SkillHooks.try_fire_control_saturation(ac, state, 0.0)
	ac.radar_targets[targets.back()] = ac.params.lock_time
	_check("火控饱和：CD 内重新跨过五锁不重复触发",
		not SkillHooks.try_fire_control_saturation(ac, state, 0.0) \
		and is_equal_approx(float(state.get("cooldown", 0.0)), 20.0), str(state))
	StatusEffects.update(ac, 6.1)
	_check("火控饱和：超载结束即收回 +2 锁数", ac.effective_max_locks() == 5, "")
	ac.radar_targets.erase(targets.back())
	SkillHooks.try_fire_control_saturation(ac, state, 20.0)
	ac.radar_targets[targets.back()] = ac.params.lock_time
	_check("火控饱和：CD 结束且重新跨线后可再次触发",
		SkillHooks.try_fire_control_saturation(ac, state, 0.0), str(state))
	for target in targets:
		target.free()
	ac.free()


# ── J. 前置链（requires_skill）自洽性 —— 派生技必须挂在"能产生该状态的根技"上 ──
#     729 回归：共振反馈曾把前置写成超载入门技，只拿焰诱共振也会刷出，但玩家无 JAM 手段 → 永不触发。
func _test_requires_skill_chain() -> void:
	print("── J. requires_skill：id 有效性 + 共振反馈需 JAM 来源 ──")
	var all_ids: Dictionary = {}
	for u in SurvivorData.UPGRADES:
		all_ids[str(u.get("id", ""))] = true
	for u in SurvivorData.UPGRADES:
		var pre: Variant = u.get("requires_skill", null)
		if pre == null:
			continue
		for pid in pre:
			_check("%s 前置 %s 存在于表中" % [u.get("id", ""), pid],
				all_ids.has(str(pid)), "未知 id")

	# 全部会调 SkillHooks.on_player_jam_landed 的技能 = 合法 JAM 来源
	var jam_sources: Array = ["skill_flare_aoe_jam", "skill_gun_kill_flare_drop",
		"skill_missile_hit_aoe_jam", "skill_torpedo_aoe_jam", "head_on_jam",
		"jam_aura", "sig_rafale"]
	var jso: Dictionary = SurvivorData.upgrade_by_id("jam_self_overload")
	_check("共振反馈存在", not jso.is_empty(), "")
	var pre_list: Array = jso.get("requires_skill", []) as Array
	for s in jam_sources:
		_check("共振反馈前置含 JAM 来源 %s" % s, pre_list.has(s), "缺失")
	_check("共振反馈前置不含超载入门技（自身即超载来源）",
		not (pre_list.has("skill_flare_overload") or pre_list.has("cloud_overload")
			or pre_list.has("skill_evade_missile_overload")), "仍挂着超载前置")

	var knight: Array = [&"knight"]
	_check("只有焰诱共振（超载来源，无 JAM 手段）→ 不进池",
		not SurvivorData.is_upgrade_available_for(
			jso, &"f15", null, {"skill_flare_overload": 1}, knight), "")
	_check("持有寒蝉效应（JAM 来源）→ 进池",
		SurvivorData.is_upgrade_available_for(
			jso, &"f15", null, {"skill_missile_hit_aoe_jam": 1}, knight), "")


# ── K. 词条构筑闭环：嗜血基础 / 哒哒哒 / 暴风雨资源语义 / 嘘！闸门 ──
func _test_status_build_completion() -> void:
	print("── K. 词条构筑闭环：嗜血免弹 / 哒哒哒 / 暴风雨 / 嘘！ ──")
	var ac := _make_test_aircraft()
	ac.team = CombatUnit.TEAM_PLAYER
	ac.params.gun = GunParams.new()
	ac.params.gun.max_range = 1000.0
	ac.params.gun.fire_cone_half_angle = 10.0
	ac.set_meta("upgrade_stacks", {"ratatat": 1, "storm_i": 1})
	ac.apply_status(StatusEffects.BLOODLUST, 9.0)
	StatusEffects.update(ac, 0.0)
	_check("嗜血基础：玩家小队机炮/CIWS 进入免耗弹语义", ac.bloodlust_gun_ammo_free(), "")
	ac.ammo = 5
	AircraftWeapons._fire_gun_round(ac, ac.params.gun)
	_check("嗜血基础：普通机炮实际出膛不扣弹", ac.ammo == 5, "ammo=%d" % ac.ammo)
	_check("哒哒哒：射程 +500m / 射界半角 +8° / 间隔 ×0.70",
		is_equal_approx(ac.effective_gun_range_m(), 1500.0) \
		and is_equal_approx(ac.effective_gun_cone_half_angle_deg(), 18.0) \
		and is_equal_approx(ac.effective_gun_fire_interval(1.0), 0.70), "")
	ac.remove_status(StatusEffects.BLOODLUST)
	StatusEffects.update(ac, 0.0)
	AircraftWeapons._fire_gun_round(ac, ac.params.gun)
	_check("嗜血结束：免耗弹与哒哒哒全部回基线",
		not ac.bloodlust_gun_ammo_free() \
		and ac.ammo == 4 \
		and is_equal_approx(ac.effective_gun_range_m(), 1000.0) \
		and is_equal_approx(ac.effective_gun_cone_half_angle_deg(), 10.0), "")

	var ab := AfterburnerCharge.new()
	_check("暴风雨 I：加力可激活", ab.toggle(ac), "")
	ab.update(3.01)
	_check("暴风雨 I：单次激活实际耗能 3.0 后获得超载 8s",
		ac.has_status(StatusEffects.OVERLOAD) \
		and float(ac.status_effects.get(StatusEffects.OVERLOAD, 0.0)) >= 7.9, "")
	var charge_before: float = ab.charge
	ab.update(1.0, 1.0, true)
	_check("暴风雨 II：超载加力启用时不耗能", is_equal_approx(ab.charge, charge_before), "")
	ab.toggle(ac)
	ab.charge = 0.0
	ab.update(1.0, 1.0, true)
	_check("暴风雨 II：停用时被动充能 ×4", is_equal_approx(ab.charge, 0.8), "")

	var enemy := _make_test_aircraft()
	enemy.team = CombatUnit.TEAM_HOSTILE
	enemy.apply_status(StatusEffects.JAM, 5.0)
	StatusEffects.update(enemy, 0.0)
	SkillHooks.hush_active = true
	_check("嘘！：JAM 敌机热诱弹入口被封锁", SkillHooks.hush_blocks_flare(enemy), "")
	SkillHooks.hush_active = false
	ac.free()
	enemy.free()


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
