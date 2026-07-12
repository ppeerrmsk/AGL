extends RefCounted

## ROE 全图察觉与交战规则回归（spec global-awareness-roe）
## 覆盖：热度纯函数（配额/地板/衰减/连续性）+ 姿态派生 + 感知门（察觉/守区 leash）
## 运行：godot --headless --path . -- --bench=roe（或 --bench=all）

var _pass := 0
var _fail := 0


func run() -> void:
	print("\n════════ ROE 察觉与交战规则（热度/姿态/感知门） ════════")

	_test_heat_math()
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
