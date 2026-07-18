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
	print("\n════════ 三轴属性验收（收入 / 里程碑表 / 覆写 / 计数） ════════")
	_test_earnable_formula()
	_test_milestone_table_shape()
	_test_milestone_override_merge()
	_test_axis_point_counting()
	print("──────── 结果：%d 通过 / %d 失败 ────────" % [_pass, _fail])
	print("══════════════════════════════════════════════════\n")


# ── A. 收入公式 ──
func _test_earnable_formula() -> void:
	print("── A. 收入公式 points = floor(LV/3) ──")
	var cases: Array = [[1, 0], [3, 1], [4, 1], [9, 3], [10, 3], [22, 7], [25, 8], [26, 8]]
	for c in cases:
		var got: int = SurvivorData.axis_points_earnable(int(c[0]))
		_check("LV%d → %d 点" % [c[0], c[1]], got == int(c[1]), "got %d" % got)


# ── B. 里程碑基准表结构 ──
func _test_milestone_table_shape() -> void:
	print("── B. 里程碑基准表：三轴各 5 档、档位 2/4/6/8/10、字段齐全 ──")
	for axis in SurvivorData.AXES:
		var tiers: Array = SurvivorData.milestones_for(axis)
		_check("%s 线共 5 档" % axis, tiers.size() == 5, "got %d" % tiers.size())
		var expected_pts: Array = [2, 4, 6, 8, 10]
		var pts_ok := true
		var fields_ok := true
		for i in tiers.size():
			var t: Dictionary = tiers[i]
			if int(t.get("points", -1)) != int(expected_pts[i]):
				pts_ok = false
			if not (t.has("stat") and t.has("kind") and t.has("value")):
				fields_ok = false
		_check("%s 档位序列 2/4/6/8/10" % axis, pts_ok, "")
		_check("%s 每档含 stat/kind/value" % axis, fields_ok, "")
	# 抽查陡递减排布：斗士首档=厚 HP、骑士首档=导弹资源
	var glad: Array = SurvivorData.milestones_for(SurvivorData.AXIS_GLADIATOR)
	_check("斗士首档 = max_hp +25（厚基础前置）",
		str(glad[0]["stat"]) == "max_hp" and is_equal_approx(float(glad[0]["value"]), 25.0),
		str(glad[0]))
	var kni: Array = SurvivorData.milestones_for(SurvivorData.AXIS_KNIGHT)
	_check("骑士首档 = missile_count +1（大额资源只在首档/预留）",
		str(kni[0]["stat"]) == "missile_count", str(kni[0]))


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
	_check("未覆写档保持基准（斗士 4 点仍 gun_damage）",
		str(merged[1]["stat"]) == "gun_damage", str(merged[1]))
	var kni: Array = SurvivorData.milestones_for(SurvivorData.AXIS_KNIGHT, profile)
	_check("他轴不受影响（骑士首档仍 missile_count）",
		str(kni[0]["stat"]) == "missile_count", str(kni[0]))
	_check("空覆写走基准表（不构造 profile 时同引用语义）",
		SurvivorData.milestones_for(SurvivorData.AXIS_SCHEMER).size() == 5, "")


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


func _check(label: String, ok: bool, detail: String) -> void:
	if ok:
		_pass += 1
		print("  ✓ %s" % label)
	else:
		_fail += 1
		print("  ✗ %s — %s" % [label, detail])
