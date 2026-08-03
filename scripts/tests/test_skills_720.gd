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
	_test_lock_count_upgrades()
	_test_close_range_lock()
	_test_axis_count_scaling()
	_test_t5_mechanisms()
	_test_requires_skill_chain()
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


# ── F. 可叠加锁数技能（普通 +1 / 蜂群 +3，均为全队）──
func _test_lock_count_upgrades() -> void:
	print("── F. 锁数技能：多目标追踪 +1/层、导弹蜂群 +3、默认全队 ──")
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
	_check("两技能均为默认全队范围", str(multi.get("scope", "")) == "" \
		and str(swarm.get("scope", "")) == "" and not swarm.has("classes"), str(swarm))
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
	# 三向互斥：任取一张后，其余两张都不再进池
	var cobra_u := SurvivorData.upgrade_by_id("cobra_skill")
	var herbst_u := SurvivorData.upgrade_by_id("evasion_herbst")
	var manual_u := SurvivorData.upgrade_by_id("manual_dodge")
	var flare_params := AircraftParams.new()
	flare_params.flare = FlareParams.new()
	_check("取眼镜蛇 → J-Turn/胆大妄为不进池",
		not SurvivorData.is_upgrade_available_for(herbst_u, &"f16", flare_params, {"cobra_skill": 1}, [])
		and not SurvivorData.is_upgrade_available_for(manual_u, &"f16", flare_params, {"cobra_skill": 1}, []), "")
	_check("取 J-Turn → 眼镜蛇/胆大妄为不进池",
		not SurvivorData.is_upgrade_available_for(cobra_u, &"f16", flare_params, {"evasion_herbst": 1}, [])
		and not SurvivorData.is_upgrade_available_for(manual_u, &"f16", flare_params, {"evasion_herbst": 1}, []), "")
	_check("取胆大妄为 → 眼镜蛇/J-Turn 不进池",
		not SurvivorData.is_upgrade_available_for(cobra_u, &"f16", flare_params, {"manual_dodge": 1}, [])
		and not SurvivorData.is_upgrade_available_for(herbst_u, &"f16", flare_params, {"manual_dodge": 1}, []), "")
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
	tail_enemy.global_position = Vector2(0.0, 100.0)
	tail_enemy.heading = 0.0
	tail_enemy.is_firing = true
	CombatUnit.all_units.append(tail_enemy)
	wing2._update_manual_dodge_skill()
	_check("胆大妄为 AI 僚机：后方机炮威胁自动释放",
		wing2._manual_dodge_cd > 0.0 and wing2.status_effects.has(StatusEffects.INVINCIBLE), "")
	var ai_cobra := _make_test_aircraft()
	var ai_cobra_node := CobraManeuver.new()
	ai_cobra.add_child(ai_cobra_node)
	ai_cobra_node._aircraft = ai_cobra
	ai_cobra.cobra_skill_active = true
	ai_cobra._update_cobra_skill(0.0)
	_check("眼镜蛇 AI 僚机：无需加力/evasion，后方机炮威胁自动释放",
		not ai_cobra.evasion_mode and ai_cobra_node.is_active, "")
	var ai_herbst := _make_test_aircraft()
	var ai_herbst_node := HerbstManeuver.new()
	ai_herbst.add_child(ai_herbst_node)
	ai_herbst_node._aircraft = ai_herbst
	ai_herbst.evasion_herbst_active = true
	ai_herbst._update_evasion_herbst_skill(0.0)
	_check("J-Turn AI 僚机：无需加力/evasion，后方机炮威胁自动释放",
		not ai_herbst.evasion_mode and ai_herbst_node.is_active, "")
	var controlled_cobra := _make_test_aircraft()
	var controlled_cobra_node := CobraManeuver.new()
	controlled_cobra.add_child(controlled_cobra_node)
	controlled_cobra_node._aircraft = controlled_cobra
	controlled_cobra.cobra_skill_active = true
	var controlled_ai := AIController.new()
	controlled_ai.manual_control = true
	controlled_cobra._ai_ref = controlled_ai
	controlled_cobra._update_cobra_skill(0.0)
	var stayed_manual := not controlled_cobra_node.is_active
	var manual_started := controlled_cobra.try_manual_maneuver()
	_check("当前操控机：同一威胁不自动，按 R 才释放",
		stayed_manual and manual_started and controlled_cobra_node.is_active, "")
	CombatUnit.all_units.erase(tail_enemy)
	tail_enemy.free()
	ai_cobra.free()
	ai_herbst.free()
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


# ── I. 前置链（requires_skill）自洽性 —— 派生技必须挂在"能产生该状态的根技"上 ──
#     729 回归：共振反馈曾把前置写成超载入门技，只拿焰诱共振也会刷出，但玩家无 JAM 手段 → 永不触发。
func _test_requires_skill_chain() -> void:
	print("── I. requires_skill：id 有效性 + 共振反馈需 JAM 来源 ──")
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
