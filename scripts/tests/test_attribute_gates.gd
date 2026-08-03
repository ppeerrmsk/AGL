extends RefCounted

## 无头行为验收：三轴属性系统（spec evolution-attribute-gates）
##
## 阶段 1（数据层）：收入公式 floor(LV/3) / 里程碑基准表结构 / 起手机覆写合并 / 轴点计数
## 后续阶段（卡片流/里程碑应用/换型重放/门槛双门）在此文件持续追加断言。
##
## 运行：godot --headless --path . -- --bench=attr_gates（或 --bench=all）

var _pass := 0
var _fail := 0


func run() -> void:
	print("\n════════ 三轴属性验收（收入 / 里程碑表 / 覆写 / 计数 / 应用与重放） ════════")
	_test_earnable_formula()
	_test_milestone_table_shape()
	_test_milestone_override_merge()
	_test_axis_point_counting()
	_test_milestone_apply_and_replay()
	_test_milestone_squad_wide()
	_test_card_axis_mapping()
	_test_classified_card_pity()
	_test_weapon_inventory()
	_test_evolution_gates()
	print("──────── 结果：%d 通过 / %d 失败 ────────" % [_pass, _fail])
	print("══════════════════════════════════════════════════\n")


# ── A. 收入公式 ──
func _test_earnable_formula() -> void:
	print("── A. 收入公式 points = min(floor(LV/3), 8)（v9 封顶，spec §2.2）──")
	var cases: Array = [[1, 0], [3, 1], [4, 1], [9, 3], [10, 3], [22, 7], [24, 8], [25, 8],
		[26, 8], [27, 8], [30, 8], [60, 8]]
	for c in cases:
		var got: int = SurvivorData.axis_points_earnable(int(c[0]))
		_check("LV%d → %d 点" % [c[0], c[1]], got == int(c[1]), "got %d" % got)


# ── B. 里程碑基准表结构 ──
func _test_milestone_table_shape() -> void:
	print("── B. 里程碑基准表：三轴各 6 档、档位 2/3/4/6/8/10、字段齐全 ──")
	for axis in SurvivorData.AXES:
		var tiers: Array = SurvivorData.milestones_for(axis)
		_check("%s 线共 6 档" % axis, tiers.size() == 6, "got %d" % tiers.size())
		var expected_pts: Array = [2, 3, 4, 6, 8, 10]
		var pts_ok := true
		var fields_ok := true
		for i in tiers.size():
			var t: Dictionary = tiers[i]
			if int(t.get("points", -1)) != int(expected_pts[i]):
				pts_ok = false
			if not (t.has("stat") and t.has("kind") and t.has("value")):
				fields_ok = false
		_check("%s 档位序列 2/3/4/6/8/10" % axis, pts_ok, "")
		_check("%s 每档含 stat/kind/value" % axis, fields_ok, "")
	# 抽查 v13 时间曲线：斗士早兑现、骑士后兑现。
	var glad: Array = SurvivorData.milestones_for(SurvivorData.AXIS_GLADIATOR)
	_check("斗士首档 = 机炮射程 ×1.20（早期享受）",
		str(glad[0]["stat"]) == "gun_range" and is_equal_approx(float(glad[0]["value"]), 1.20),
		str(glad[0]))
	var kni: Array = SurvivorData.milestones_for(SurvivorData.AXIS_KNIGHT)
	_check("骑士首档 = 雷达 ×1.10（前期铺垫）",
		str(kni[0]["stat"]) == "radar_range", str(kni[0]))
	_check("三条 3 点档 = HP/高度变化/经验",
		str(glad[1]["stat"]) == "max_hp" and is_equal_approx(float(glad[1]["value"]), 25.0) \
		and str(kni[1]["stat"]) == "alt_speed" \
		and str(SurvivorData.milestones_for(SurvivorData.AXIS_SCHEMER)[1]["stat"]) == "xp_mult", "")
	_check("骑士导弹资源延后到 6/8 点",
		str(kni[3]["stat"]) == "missile_count" and str(kni[4]["stat"]) == "missile_locks", "")
	var map := TacticalMap.new()
	_check("斗士 6 点 G 档 = +2.0",
		str(glad[3]["stat"]) == "max_g" and is_equal_approx(float(glad[3]["value"]), 2.0), str(glad[3]))
	_check("G +2.0 保留一位小数",
		map._fmt_milestone_value("max_g", 2.0, "add", false).ends_with("+2.0"), "")
	_check("armor +25 显示为伤害减免 +20%",
		map._fmt_milestone_value("armor", 25.0, "add", false).ends_with("+20%"), "")
	_check("失速速度 ×0.95 显示为 -5%",
		map._fmt_milestone_value("stall_speed", 0.95, "mult", false).ends_with("-5%"), "")
	map.free()


# ── C. 起手机覆写合并 ──
func _test_milestone_override_merge() -> void:
	print("── C. 起手机覆写：(axis,points) 同档替换、他档/他轴不动 ──")
	var profile := PlayableAircraft.new()
	profile.milestone_overrides = [
		{"axis": "gladiator", "points": 2, "stat": "max_hp", "kind": "add", "value": 40.0},
	]
	var merged: Array = SurvivorData.milestones_for(SurvivorData.AXIS_GLADIATOR, profile)
	_check("覆写档生效（斗士 2 点 → +40）", is_equal_approx(float(merged[0]["value"]), 40.0),
		str(merged[0]))
	_check("未覆写档保持基准（斗士 4 点仍 armor）",
		str(merged[2]["stat"]) == "armor", str(merged[2]))
	var kni: Array = SurvivorData.milestones_for(SurvivorData.AXIS_KNIGHT, profile)
	_check("他轴不受影响（骑士首档仍 radar_range）",
		str(kni[0]["stat"]) == "radar_range", str(kni[0]))
	_check("空覆写走基准表（不构造 profile 时同引用语义）",
		SurvivorData.milestones_for(SurvivorData.AXIS_SCHEMER).size() == 6, "")


# ── D. 轴点计数 ──
func _test_axis_point_counting() -> void:
	print("── D. SurvivorPlayer 轴点：加点/查询/未知轴防御 ──")
	var sp := SurvivorPlayer.new()
	sp.add_axis_point(SurvivorData.AXIS_GLADIATOR)
	sp.add_axis_point(SurvivorData.AXIS_GLADIATOR)
	sp.add_axis_point(SurvivorData.AXIS_KNIGHT)
	_check("斗士 2 点", sp.get_axis_points(SurvivorData.AXIS_GLADIATOR) == 2, "")
	_check("骑士 1 点", sp.get_axis_points(SurvivorData.AXIS_KNIGHT) == 1, "")
	_check("策士 0 点", sp.get_axis_points(SurvivorData.AXIS_SCHEMER) == 0, "")
	_check("合计 3 点", sp.total_axis_points() == 3, "got %d" % sp.total_axis_points())
	sp.add_axis_point(&"bogus_axis")
	_check("未知轴不计入合计", sp.total_axis_points() == 3, "got %d" % sp.total_axis_points())
	sp.free()


# ── E. 里程碑应用与换型重放（阶段 2）──
func _test_milestone_apply_and_replay() -> void:
	print("── E. 里程碑应用：增量 / 幂等 / 无机补挂 / 换型重放 ──")
	var sp := SurvivorPlayer.new()
	var ac := _make_test_aircraft()
	sp.aircraft = ac

	# 增量应用：斗士 2 点 → 机炮射程 ×1.20。
	var base_gun_range: float = ac.params.gun.max_range
	sp.add_axis_point(SurvivorData.AXIS_GLADIATOR)
	sp.add_axis_point(SurvivorData.AXIS_GLADIATOR)
	_check("斗士 2 点 → 机炮射程 ×1.20",
		is_equal_approx(ac.params.gun.max_range, base_gun_range * 1.20),
		"got %.1f" % ac.params.gun.max_range)
	_check("斗士首档不再抬 HP", is_equal_approx(ac.params.max_hp, 100.0),
		"got %.1f" % ac.params.max_hp)

	# 骑士 2/3/4 点只铺雷达、高度变化与速度；导弹资源尚未兑现。
	var base_climb: float = ac.params.climb_rate_max
	var base_speed: float = ac.params.max_speed
	sp.add_axis_point(SurvivorData.AXIS_KNIGHT)
	sp.add_axis_point(SurvivorData.AXIS_KNIGHT)
	_check("骑士 2 点 → 雷达 3000→3300", is_equal_approx(ac.params.radar_range, 3300.0),
		"got %.0f" % ac.params.radar_range)
	sp.add_axis_point(SurvivorData.AXIS_KNIGHT)
	_check("骑士 3 点 → 高度变化速度 ×1.10",
		is_equal_approx(ac.params.climb_rate_max, base_climb * 1.10),
		"got %.1f" % ac.params.climb_rate_max)
	sp.add_axis_point(SurvivorData.AXIS_KNIGHT)
	_check("骑士 4 点 → 极速 ×1.02", is_equal_approx(ac.params.max_speed, base_speed * 1.02),
		"got %.1f" % ac.params.max_speed)
	_check("骑士 4 点仍无导弹/锁数奖励",
		ac.params.missile.max_count == 4 and ac.max_simultaneous_locks == 1, "")
	# 策士 2 点 → flare +2（合计到 8 = 触顶）
	sp.add_axis_point(SurvivorData.AXIS_SCHEMER)
	sp.add_axis_point(SurvivorData.AXIS_SCHEMER)
	_check("策士 2 点 → 热诱弹 10→12", ac.params.flare.max_flares == 12,
		"got %d" % ac.params.flare.max_flares)
	# 收入封顶（spec §2.2 v9）：合计 8 后第 9 点被闸
	sp.add_axis_point(SurvivorData.AXIS_GLADIATOR)
	_check("封顶：第 9 点跳过（斗士仍 2）",
		sp.get_axis_points(SurvivorData.AXIS_GLADIATOR) == 2,
		"got %d" % sp.get_axis_points(SurvivorData.AXIS_GLADIATOR))
	_check("封顶：合计恒 = 8", sp.total_axis_points() == 8, "got %d" % sp.total_axis_points())

	# 换型重放：模拟 evolve() 换全新 params（新基线），重放后加成全部重挂
	var fresh := _make_fresh_params(130.0, 2, 6, 3500.0)
	ac.params = fresh
	ac.hp = 130.0
	ac.missiles_remaining = 2
	ac.flares_remaining = 6
	ac.max_simultaneous_locks = 1  # 模拟换型重放入口先归基础值
	var fresh_gun_range: float = fresh.gun.max_range
	var fresh_climb: float = fresh.climb_rate_max
	var fresh_speed: float = fresh.max_speed
	sp.reapply_all_milestones()
	_check("重放：新机机炮射程 ×1.20",
		is_equal_approx(ac.params.gun.max_range, fresh_gun_range * 1.20),
		"got %.1f" % ac.params.gun.max_range)
	_check("重放：新机雷达 3500→3850（×1.10）", is_equal_approx(ac.params.radar_range, 3850.0),
		"got %.0f" % ac.params.radar_range)
	_check("重放：新机高度变化 ×1.10 / 极速 ×1.02",
		is_equal_approx(ac.params.climb_rate_max, fresh_climb * 1.10)
		and is_equal_approx(ac.params.max_speed, fresh_speed * 1.02), "")
	_check("重放：新机热诱弹 6→8", ac.params.flare.max_flares == 8,
		"got %d" % ac.params.flare.max_flares)
	_check("重放：4 点骑士仍不增加导弹/锁数",
		ac.params.missile.max_count == 2 and ac.max_simultaneous_locks == 1, "")
	# 重放后幂等：再 apply_crossed 不重复
	sp.apply_crossed_milestones(SurvivorData.AXIS_GLADIATOR)
	_check("重放后 apply_crossed 幂等",
		is_equal_approx(ac.params.gun.max_range, fresh_gun_range * 1.20),
		"got %.1f" % ac.params.gun.max_range)

	# 无机补挂：没飞机时加的点不丢——飞机就位后 apply_crossed 补应用
	var sp2 := SurvivorPlayer.new()
	sp2.add_axis_point(SurvivorData.AXIS_GLADIATOR)
	sp2.add_axis_point(SurvivorData.AXIS_GLADIATOR)
	var ac2 := _make_test_aircraft()
	sp2.aircraft = ac2
	sp2.apply_crossed_milestones(SurvivorData.AXIS_GLADIATOR)
	_check("无机加点 → 就位补挂机炮射程 ×1.20",
		is_equal_approx(ac2.params.gun.max_range, base_gun_range * 1.20),
		"got %.1f" % ac2.params.gun.max_range)

	# 骑士专精到 8 点，才依次兑现挂弹与多目标锁定。
	var sp3 := SurvivorPlayer.new()
	var ac3 := _make_test_aircraft()
	sp3.aircraft = ac3
	for _i in 8:
		sp3.add_axis_point(SurvivorData.AXIS_KNIGHT)
	_check("骑士 6 点后导弹 4→5", ac3.params.missile.max_count == 5
		and ac3.missiles_remaining == 5, "")
	_check("骑士 8 点后锁数 1→2", ac3.max_simultaneous_locks == 2,
		"got %d" % ac3.max_simultaneous_locks)

	# 斗士 6 点深投：持续/结构 G 同步 +2.0，跨过可感知门槛。
	var sp4 := SurvivorPlayer.new()
	var ac4 := _make_test_aircraft()
	sp4.aircraft = ac4
	var base_g: float = ac4.params.max_g
	var base_structural_g: float = ac4.params.max_g_structural
	for _i in 6:
		sp4.add_axis_point(SurvivorData.AXIS_GLADIATOR)
	_check("斗士 6 点 → 持续/结构 G 均 +2.0",
		is_equal_approx(ac4.params.max_g, base_g + 2.0)
		and is_equal_approx(ac4.params.max_g_structural, base_structural_g + 2.0),
		"got %.1f/%.1f" % [ac4.params.max_g, ac4.params.max_g_structural])

	ac.free()
	ac2.free()
	ac3.free()
	ac4.free()
	sp.free()
	sp2.free()
	sp3.free()
	sp4.free()


# ── E2. 里程碑全队下发（2026-07-28：三轴加成跟玩家不跟机体，僚机同吃）──
func _test_milestone_squad_wide() -> void:
	print("── E2. 里程碑全队下发：僚机同吃 / 逐机记账 / 晚入队补挂 / 换帅不丢 ──")
	var sp := SurvivorPlayer.new()
	var lead := _make_test_aircraft()
	var wing := _make_test_aircraft()
	sp.aircraft = lead
	var roster: Array = [lead, wing]
	sp.milestone_targets_provider = func(): return roster
	var base_gun_range: float = lead.params.gun.max_range

	# 跨档 → 长机与僚机同时吃到
	sp.add_axis_point(SurvivorData.AXIS_GLADIATOR)
	sp.add_axis_point(SurvivorData.AXIS_GLADIATOR)
	_check("长机机炮射程 ×1.20", is_equal_approx(lead.params.gun.max_range, base_gun_range * 1.20),
		"got %.1f" % lead.params.gun.max_range)
	_check("僚机机炮射程 ×1.20（同吃）", is_equal_approx(wing.params.gun.max_range, base_gun_range * 1.20),
		"got %.1f" % wing.params.gun.max_range)

	# 逐机幂等：再跨同一档不重复叠
	sp.apply_crossed_milestones(SurvivorData.AXIS_GLADIATOR)
	_check("重复下发不叠加（僚机仍 ×1.20）",
		is_equal_approx(wing.params.gun.max_range, base_gun_range * 1.20),
		"got %.1f" % wing.params.gun.max_range)
	sp.add_axis_point(SurvivorData.AXIS_GLADIATOR)
	_check("斗士 3 点全队 HP +25（长机）", is_equal_approx(lead.params.max_hp, 125.0)
		and is_equal_approx(lead.hp, 125.0), "")
	_check("斗士 3 点全队 HP +25（僚机）", is_equal_approx(wing.params.max_hp, 125.0)
		and is_equal_approx(wing.hp, 125.0), "")
	sp.add_axis_point(SurvivorData.AXIS_GLADIATOR)
	_check("斗士 4 点全队 armor +25（长机）", is_equal_approx(lead.params.armor, 25.0),
		"got %.2f" % lead.params.armor)
	_check("斗士 4 点全队 armor +25（僚机）", is_equal_approx(wing.params.armor, 25.0),
		"got %.2f" % wing.params.armor)
	_check("长机复用复合装甲管线：100 机炮伤害减至 80",
		is_equal_approx(lead._apply_armor(100.0, 0.0), 80.0),
		"got %.2f" % lead._apply_armor(100.0, 0.0))
	_check("僚机复用复合装甲管线：100 机炮伤害减至 80",
		is_equal_approx(wing._apply_armor(100.0, 0.0), 80.0),
		"got %.2f" % wing._apply_armor(100.0, 0.0))

	# 晚入队：新僚机按当前进度全量补挂
	var late := _make_test_aircraft()
	sp.apply_all_milestones_to(late)
	_check("晚入队僚机补挂射程 ×1.20 + HP 100→125",
		is_equal_approx(late.params.gun.max_range, base_gun_range * 1.20)
		and is_equal_approx(late.params.max_hp, 125.0), "")
	_check("晚入队僚机补挂 armor +25", is_equal_approx(late.params.armor, 25.0),
		"got %.2f" % late.params.armor)
	sp.apply_all_milestones_to(late)
	_check("补挂幂等（射程仍 ×1.20 / HP 仍 125）",
		is_equal_approx(late.params.gun.max_range, base_gun_range * 1.20)
		and is_equal_approx(late.params.max_hp, 125.0), "")
	_check("armor 补挂幂等（仍 25）", is_equal_approx(late.params.armor, 25.0),
		"got %.2f" % late.params.armor)

	# 换帅：操控权移到僚机后，记账视图跟着走，且不会因"账已记满"漏挂新档
	sp.aircraft = wing
	var wing_done: Array = sp.applied_milestones.get(SurvivorData.AXIS_GLADIATOR, [])
	_check("换帅后记账视图 = 新操控机那本（含 2 档）", wing_done.has(2), str(wing_done))
	sp.add_axis_point(SurvivorData.AXIS_KNIGHT)
	sp.add_axis_point(SurvivorData.AXIS_KNIGHT)
	_check("换帅后新跨档仍下发（僚机雷达 3000→3300）",
		is_equal_approx(wing.params.radar_range, 3300.0), "got %.0f" % wing.params.radar_range)
	_check("换帅后新跨档也给旧长机（雷达 3000→3300）",
		is_equal_approx(lead.params.radar_range, 3300.0), "got %.0f" % lead.params.radar_range)
	sp.add_axis_point(SurvivorData.AXIS_KNIGHT)
	_check("骑士 3 点高度变化全队 ×1.10",
		is_equal_approx(lead.params.climb_rate_max, wing.params.climb_rate_max), "")
	sp.add_axis_point(SurvivorData.AXIS_KNIGHT)
	_check("骑士 4 点仍无导弹/锁数奖励",
		lead.params.missile.max_count == 4 and wing.params.missile.max_count == 4
		and lead.max_simultaneous_locks == 1 and wing.max_simultaneous_locks == 1, "")

	# 策士 XP 是玩家级单乘区：不按 roster 里的飞机数量重复相乘。
	sp.axis_points[SurvivorData.AXIS_SCHEMER] = 3
	_check("策士 3 点 XP ×1.10（全队仍只算一次）",
		is_equal_approx(sp.milestone_xp_multiplier(), 1.10),
		"got %.2f" % sp.milestone_xp_multiplier())

	# 6 点斗士深投独立 roster：验证新 G 档确实全队下发，而不只在单机应用器生效。
	var sp_g := SurvivorPlayer.new()
	var lead_g := _make_test_aircraft()
	var wing_g := _make_test_aircraft()
	sp_g.aircraft = lead_g
	sp_g.milestone_targets_provider = func(): return [lead_g, wing_g]
	var lead_base_g: float = lead_g.params.max_g
	var wing_base_g: float = wing_g.params.max_g
	for _i in 6:
		sp_g.add_axis_point(SurvivorData.AXIS_GLADIATOR)
	_check("斗士 6 点 G+2.0 下发长机", is_equal_approx(lead_g.params.max_g, lead_base_g + 2.0), "")
	_check("斗士 6 点 G+2.0 下发僚机", is_equal_approx(wing_g.params.max_g, wing_base_g + 2.0), "")

	lead.free()
	wing.free()
	late.free()
	lead_g.free()
	wing_g.free()
	sp.free()
	sp_g.free()


# ── F. 卡片轴映射与轴内抽卡（阶段 3）──
func _test_card_axis_mapping() -> void:
	print("── F. 卡片轴映射：全池覆盖 / 覆写 / 专注卡 / 轴内抽卡 ──")
	# 全池覆盖：每张升级卡都映射到三轴之一
	var counts: Dictionary = {
		SurvivorData.AXIS_GLADIATOR: 0, SurvivorData.AXIS_KNIGHT: 0, SurvivorData.AXIS_SCHEMER: 0,
	}
	var all_mapped := true
	for u in SurvivorData.UPGRADES:
		var a: StringName = SurvivorData.axis_of_upgrade(u)
		if not counts.has(a):
			all_mapped = false
			print("    ! 未映射卡：%s（axis=%s）" % [u.get("id"), a])
		else:
			counts[a] = int(counts[a]) + 1
	_check("全部升级卡映射到三轴之一", all_mapped, "")
	_check("三轴池皆非空（斗%d/骑%d/策%d）" % [
		counts[SurvivorData.AXIS_GLADIATOR], counts[SurvivorData.AXIS_KNIGHT], counts[SurvivorData.AXIS_SCHEMER]],
		int(counts[SurvivorData.AXIS_GLADIATOR]) > 0 and int(counts[SurvivorData.AXIS_KNIGHT]) > 0
		and int(counts[SurvivorData.AXIS_SCHEMER]) > 0, "")
	# 抽查：category 默认映射 + 逐 id 覆写
	var samples: Array = [
		["gun_damage", SurvivorData.AXIS_GLADIATOR],   # secondary → 斗士
		["hp_up", SurvivorData.AXIS_GLADIATOR],        # survival → 斗士
		["missile_count", SurvivorData.AXIS_KNIGHT],   # missile → 骑士
		["speed_up", SurvivorData.AXIS_KNIGHT],        # mobility → 骑士
		["flare_shield", SurvivorData.AXIS_SCHEMER],   # electronic_warfare → 策士
		["dogfight", SurvivorData.AXIS_GLADIATOR],     # 覆写：狗斗归斗士
		["fear_chills", SurvivorData.AXIS_SCHEMER],    # 覆写：心理战归策士
		["laser_range", SurvivorData.AXIS_SCHEMER],    # 覆写：激光归策士
	]
	for s in samples:
		var found := false
		for u in SurvivorData.UPGRADES:
			if str(u.get("id", "")) == str(s[0]):
				found = true
				_check("%s → %s" % [s[0], s[1]], SurvivorData.axis_of_upgrade(u) == s[1],
					"got %s" % SurvivorData.axis_of_upgrade(u))
				break
		if not found:
			_check("%s 存在于 UPGRADES" % s[0], false, "id 不存在")
	# 专注卡：显式 axis 字段最优先 + stat 特判标记
	var focus := SurvivorData.make_axis_focus_card(SurvivorData.AXIS_SCHEMER)
	_check("专注卡显式 axis 生效", SurvivorData.axis_of_upgrade(focus) == SurvivorData.AXIS_SCHEMER,
		str(focus))
	_check("专注卡 stat=axis_focus（不走 apply）", str(focus.get("stat")) == "axis_focus", "")
	# 轴内抽卡：结果必在池内；空池返回空
	var pool: Array = []
	for u in SurvivorData.UPGRADES:
		if SurvivorData.axis_of_upgrade(u) == SurvivorData.AXIS_KNIGHT:
			pool.append(u)
	var picked: Dictionary = SurvivorData.pick_card_for_axis(pool, {}, 5)
	var in_pool := false
	for u in pool:
		if str(u.get("id")) == str(picked.get("id")):
			in_pool = true
			break
	_check("轴内抽卡结果在池内", not picked.is_empty() and in_pool, str(picked.get("id")))
	_check("空池返回空 dict", SurvivorData.pick_card_for_axis([], {}, 5).is_empty(), "")


# ── I. 4 级金卡软 pity（spec classified-card-pity）──
func _test_classified_card_pity() -> void:
	print("── I. 4 级金卡软 pity：倍率 / 清零 / 入口隔离 / 10 分钟标定 ──")
	_check("未出 0 次 → ×1",
		is_equal_approx(SurvivorData.classified_pity_weight_multiplier(0), 1.0), "")
	_check("未出 1 次 → ×3",
		is_equal_approx(SurvivorData.classified_pity_weight_multiplier(1), 3.0), "")
	_check("未出 2 次 → ×5",
		is_equal_approx(SurvivorData.classified_pity_weight_multiplier(2), 5.0), "")
	_check("未出 3 次 → ×7",
		is_equal_approx(SurvivorData.classified_pity_weight_multiplier(3), 7.0), "")

	var stable := {"id": "stable", "rarity": SurvivorData.Rarity.STABLE}
	var gold := {"id": "gold", "rarity": SurvivorData.Rarity.CLASSIFIED}
	var nextgen := {"id": "nextgen", "rarity": SurvivorData.Rarity.NEXT_GEN}
	_check("普通三卡未见金 → 累计 +1",
		SurvivorData.classified_pity_next_misses([stable], 2) == 3, "")
	_check("任一普通卡见金 → 累计清零",
		SurvivorData.classified_pity_next_misses([stable, gold], 4) == 0, "")
	_check("NEXT_GEN 不冒充 4 级金卡清零",
		SurvivorData.classified_pity_next_misses([nextgen], 3) == 4, "")

	# 结构守门：自然升级必须显式开启 pity，且先结算普通三卡再追加第四槽；奖励升级走缺省关闭。
	var mode_src := FileAccess.get_file_as_string("res://scripts/survivor/survivor_mode.gd")
	var level_start := mode_src.find("func _on_player_leveled_up")
	var level_end := mode_src.find("func _roll_upgrade_choices", level_start)
	var level_flow := mode_src.substr(level_start, level_end - level_start) \
		if level_start >= 0 and level_end > level_start else ""
	var roll_pos := level_flow.find("_roll_axis_cards(true)")
	var signature_pos := level_flow.find("_append_signature_offer(cards)")
	_check("自然升级显式开启金卡 pity", roll_pos >= 0, "")
	_check("普通三卡 pity 先结算，专属第四槽后追加",
		roll_pos >= 0 and signature_pos > roll_pos, "")
	var bonus_start := mode_src.find("func _try_present_bonus_upgrade")
	var bonus_end := mode_src.find("func _apply_upgrade_choice", bonus_start)
	var bonus_flow := mode_src.substr(bonus_start, bonus_end - bonus_start) \
		if bonus_start >= 0 and bonus_end > bonus_start else ""
	_check("奖励升级走缺省关闭，不读写累计",
		bonus_flow.contains("_roll_axis_cards()") and not bonus_flow.contains("_roll_axis_cards(true)"), "")

	# 当前非专属普通初始池的固定种子统计；不套硬件/学说/流派过滤，复现 spec §3.3 标定口径。
	var avg_6 := _simulate_classified_pity_average(6, 2000)
	var avg_7 := _simulate_classified_pity_average(7, 2000)
	_check("LV18 六轮平均见金 1.90～2.20", avg_6 >= 1.90 and avg_6 <= 2.20,
		"got %.3f" % avg_6)
	_check("LV21 七轮平均见金 2.25～2.60", avg_7 >= 2.25 and avg_7 <= 2.60,
		"got %.3f" % avg_7)


func _simulate_classified_pity_average(event_count: int, runs: int) -> float:
	var by_axis: Dictionary = {}
	for axis in SurvivorData.AXES:
		by_axis[axis] = []
	for u in SurvivorData.UPGRADES:
		if bool(u.get("evolved", false)) or not SurvivorData.is_normal_random_candidate(u):
			continue
		var exclusive: Array = u.get("exclusive_to", [])
		if not exclusive.is_empty():
			continue
		(by_axis[SurvivorData.axis_of_upgrade(u)] as Array).append(u)

	seed(0xC1A551F1 + event_count)
	var gold_offers := 0
	for _run in runs:
		var misses := 0
		for _event in event_count:
			var cards: Array[Dictionary] = []
			var mult := SurvivorData.classified_pity_weight_multiplier(misses)
			for axis in SurvivorData.AXES:
				cards.append(SurvivorData.pick_card_for_axis(by_axis[axis], {}, 5, mult))
			var next_misses := SurvivorData.classified_pity_next_misses(cards, misses)
			if next_misses == 0:
				gold_offers += 1
			misses = next_misses
	return float(gold_offers) / float(runs)


# ── H. 进化属性门槛（spec evolution-attribute-gates §2.3：双门判定 + 树 JSON 完备性）──
func _test_evolution_gates() -> void:
	print("── H. 属性门槛：判定逻辑 / sum_gk 合计门 / 树 JSON 完备性 ──")
	# 判定逻辑（合成节点）
	var nd_single: Dictionary = {"gates": {"knight": 2}}
	_check("单轴门：1/2 不过", not EvolutionSystem.gates_passed(nd_single, {&"knight": 1}), "")
	_check("单轴门：2/2 过", EvolutionSystem.gates_passed(nd_single, {&"knight": 2}), "")
	var miss: Array = EvolutionSystem.gates_missing(nd_single, {&"knight": 0})
	_check("缺口结构 {key,have,need}", miss.size() == 1 and str(miss[0]["key"]) == "knight"
		and int(miss[0]["have"]) == 0 and int(miss[0]["need"]) == 2, str(miss))
	var nd_air: Dictionary = {"gates": {"gladiator": 1, "knight": 1, "sum_gk": 3}}
	_check("合计门：斗2骑0 不过（骑各1未满足）",
		not EvolutionSystem.gates_passed(nd_air, {&"gladiator": 2, &"knight": 0}), "")
	_check("合计门：斗2骑1 过（合计3 且各1）",
		EvolutionSystem.gates_passed(nd_air, {&"gladiator": 2, &"knight": 1}), "")
	_check("无 gates 字段 = 无门槛", EvolutionSystem.gates_passed({}, {}), "")
	# 树 JSON 完备性：tier1 无门槛、tier≥2 全部有门槛、x02 三轴各2
	var t1_clean := true
	var t2plus_gated := true
	for nd in EvolutionSystem.all_nodes():
		var tier: int = int(nd.get("tier", 1))
		var g: Dictionary = EvolutionSystem.gates_of(nd)
		if tier <= 1 and not g.is_empty():
			t1_clean = false
		if tier >= 2 and g.is_empty():
			t2plus_gated = false
			print("    ! 缺门槛节点：%s" % nd.get("id"))
	_check("tier1 起手机无门槛", t1_clean, "")
	_check("tier≥2 节点全部有门槛", t2plus_gated, "")
	var x02: Dictionary = EvolutionSystem.node_of(&"x02")
	var g02: Dictionary = EvolutionSystem.gates_of(x02)
	_check("x02 omni 三轴各 2", int(g02.get("gladiator", 0)) == 2 and int(g02.get("knight", 0)) == 2
		and int(g02.get("schemer", 0)) == 2, str(g02))
	# 可行性：tier 门槛消耗 ≤ 该 tier 最低等级的点数收入（LV10→3 / LV18→6）
	var feasible := true
	for nd in EvolutionSystem.all_nodes():
		var g2: Dictionary = EvolutionSystem.gates_of(nd)
		if g2.is_empty():
			continue
		var cost: int = 0
		for k in g2:
			var ks := String(k)
			if ks == "sum_gk" or ks == "sum_all":
				continue
			if ks == "any":
				var mn := 999
				for ak in (g2[k] as Dictionary):
					mn = mini(mn, int(g2[k][ak]))
				cost += mn
				continue
			cost += int(g2[k])
		cost = maxi(cost, int(g2.get("sum_gk", 0)))
		cost = maxi(cost, int(g2.get("sum_all", 0)))
		var income: int = SurvivorData.axis_points_earnable(EvolutionSystem.min_level_of(nd))
		if cost > income:
			feasible = false
			print("    ! 门槛超收入：%s cost=%d income=%d" % [nd.get("id"), cost, income])
	_check("全节点门槛消耗 ≤ 解锁等级点数收入（专注可达）", feasible, "")
	# 新门语义（41 机树）："any" 或门 + "sum_all" 三轴合计
	var fa18e: Dictionary = EvolutionSystem.node_of(&"fa18e")
	_check("F/A-18E 或门：单轴 1 点即过", EvolutionSystem.gates_passed(fa18e, {&"knight": 1}),
		str(EvolutionSystem.gates_of(fa18e)))
	_check("F/A-18E 或门：零点不过", not EvolutionSystem.gates_passed(fa18e, {}), "")
	var ax00: Dictionary = EvolutionSystem.node_of(&"ax00")
	_check("AX-00 各2且合计7：3/2/2 过", EvolutionSystem.gates_passed(ax00,
		{&"gladiator": 3, &"knight": 2, &"schemer": 2}), str(EvolutionSystem.gates_of(ax00)))
	_check("AX-00 各2且合计7：2/2/2 不过（合计 6）", not EvolutionSystem.gates_passed(ax00,
		{&"gladiator": 2, &"knight": 2, &"schemer": 2}), "")


# ── G. 局内武器库（spec inrun-weapon-inventory：快照/补挂/互斥/不重复/底线不入库）──
func _test_weapon_inventory() -> void:
	print("── G. 武器库：换型继承（含强化引用）/ 机尾互斥 / 同类不重复 / 底线不入库 ──")
	var sp := SurvivorPlayer.new()
	var ac := _make_test_aircraft()
	sp.aircraft = ac
	# 机上挂电磁炮（display_name 当强化标记：强化长在资源上，引用迁移=强化随行）
	var rg := EquipmentParams.new()
	rg.equipment_kind = "railgun"
	rg.display_name = "MK2_UPGRADED"
	var arr: Array[EquipmentParams] = [rg]
	ac.params.equipment = arr
	# 副槽 QMAAM
	var sm := MissileParams.new()
	sm.max_count = 6
	ac.params.secondary_missile = sm
	# 火箭（无 inrun_reward meta —— 模拟"机上就有的火箭"；2026-07-23 起一律入库跟人走，
	# 修 log 20260724_222103：Su-34→J-20 换型把火箭摘掉的 bug）
	var rk := RocketParams.new()
	rk.max_ammo = 24
	ac.params.rocket = rk

	sp.record_special_weapons()
	_check("电磁炮入库", sp.weapon_inventory.has(&"railgun"), str(sp.weapon_inventory.keys()))
	_check("QMAAM 入库", sp.weapon_inventory.has(&"secondary_missile"), "")
	_check("火箭入库（无 meta 门，一律跟人走）", sp.weapon_inventory.has(&"rocket"),
		str(sp.weapon_inventory.keys()))
	_check("底线武器不入库（无 gun/missile/flare key）",
		not sp.weapon_inventory.has(&"gun") and not sp.weapon_inventory.has(&"missile")
		and not sp.weapon_inventory.has(&"flare"), str(sp.weapon_inventory.keys()))

	# 换全新机（无装备无副槽）→ 补挂
	ac.params = _make_fresh_params(120.0, 3, 8, 3200.0)
	sp.remount_weapons()
	var mounted_rg := ac.params.get_equipment_of_kind("railgun")
	_check("新机补挂电磁炮", mounted_rg != null, "")
	_check("强化随引用迁移（标记不丢）", mounted_rg != null and mounted_rg.display_name == "MK2_UPGRADED",
		str(mounted_rg.display_name) if mounted_rg else "null")
	_check("新机补挂 QMAAM 且弹量=6", ac.params.secondary_missile != null
		and ac.secondary_missiles_remaining == 6, "got %d" % ac.secondary_missiles_remaining)
	_check("新机补挂火箭且弹量=24（进化不再摘火箭）", ac.params.rocket != null
		and ac.rockets_remaining == 24, "got %d" % ac.rockets_remaining)

	# 新机自带同类 → 不重复挂
	var innate := EquipmentParams.new()
	innate.equipment_kind = "railgun"
	innate.display_name = "INNATE"
	var arr2: Array[EquipmentParams] = [innate]
	var p3 := _make_fresh_params(100.0, 2, 6, 3000.0)
	p3.equipment = arr2
	ac.params = p3
	sp.remount_weapons()
	_check("新机自带电磁炮 → 不重复挂（数组仍 1 件）", ac.params.equipment.size() == 1,
		"got %d" % ac.params.equipment.size())

	# 机尾位互斥：库存漂浮雷，但新机已带忠诚僚机 → 不挂
	var torp := TorpedoParams.new()
	var ac2 := _make_test_aircraft()
	var sp2 := SurvivorPlayer.new()
	sp2.aircraft = ac2
	ac2.params.torpedo = torp
	sp2.record_special_weapons()
	_check("漂浮雷入库", sp2.weapon_inventory.has(&"torpedo"), "")
	var p4 := _make_fresh_params(100.0, 2, 6, 3000.0)
	p4.loyal_wingman = LoyalWingmanParams.new()
	ac2.params = p4
	sp2.remount_weapons()
	_check("机尾位被忠诚僚机占用 → 漂浮雷不挂（互斥守住）", ac2.params.torpedo == null, "")
	# 换到机尾位空的机 → 挂回
	ac2.params = _make_fresh_params(100.0, 2, 6, 3000.0)
	sp2.remount_weapons()
	_check("机尾位空 → 漂浮雷挂回", ac2.params.torpedo == torp, "")

	ac.free()
	ac2.free()
	sp.free()
	sp2.free()


func _make_test_aircraft() -> Aircraft:
	var ac := Aircraft.new()
	ac.params = _make_fresh_params(100.0, 4, 10, 3000.0)
	ac.hp = 100.0
	ac.missiles_remaining = 4
	ac.flares_remaining = 10
	return ac


func _make_fresh_params(hp: float, missiles: int, flares: int, radar: float) -> AircraftParams:
	var p := AircraftParams.new()
	p.max_hp = hp
	p.radar_range = radar
	p.gun = GunParams.new()
	p.missile = MissileParams.new()
	p.missile.max_count = missiles
	p.flare = FlareParams.new()
	p.flare.max_flares = flares
	return p


func _check(label: String, ok: bool, detail: String) -> void:
	if ok:
		_pass += 1
		print("  ✓ %s" % label)
	else:
		_fail += 1
		print("  ✗ %s — %s" % [label, detail])
