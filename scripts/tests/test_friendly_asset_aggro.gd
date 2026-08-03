extends RefCounted

## 友军设施区域仇恨无头测试。
## 运行：godot --headless --path . -- --bench=friendly_asset_aggro（或 --bench=all）

var _pass := 0
var _fail := 0


func run() -> void:
	print("\n════════ 友军设施区域仇恨 ════════")
	_test_quota_formula()
	_test_activation_assignment_and_hysteresis()
	_test_friendly_carrier_hp_override()
	print("──────── 结果：%d 通过 / %d 失败 ────────" % [_pass, _fail])
	print("══════════════════════════════════════════════════\n")


func _test_quota_formula() -> void:
	var expected := [0, 0, 1, 1, 1, 1, 2, 2, 2, 3, 3, 3, 3]
	for h in range(expected.size()):
		_check("配额 H=%d" % h, FriendlyAssetAggro.quota_for(h) == expected[h],
			"got=%d want=%d" % [FriendlyAssetAggro.quota_for(h), expected[h]])


func _test_activation_assignment_and_hysteresis() -> void:
	var director := FriendlyAssetAggro.new()
	var player := _make_aircraft(CombatUnit.TEAM_PLAYER, Vector2(5000.0, 0.0))
	var target := GroundUnit.new()
	target.team = CombatUnit.TEAM_ALLY
	target.callsign = "ALLY-SAM"
	target.global_position = Vector2.ZERO
	director.register_airfield(&"airfield_a", Vector2.ZERO)
	director.register_target(&"airfield_a", target)

	var units: Array[CombatUnit] = [player, target]
	var hostiles: Array[Aircraft] = []
	for i in range(5):
		var ac := _make_aircraft(CombatUnit.TEAM_HOSTILE, Vector2(800.0 + i * 80.0, 0.0))
		ac.callsign = "H%d" % i
		hostiles.append(ac)
		units.append(ac)

	director.tick(1.0, player, units)
	_check("玩家远离时组保持 DORMANT", not director.is_group_active(&"airfield_a"), "")
	_check("DORMANT 目标拒绝自主获取",
		not hostiles[0]._ai_ref.acquire_target(target, AIController.TargetSource.TS_SCORED), "")

	player.global_position = Vector2.ZERO
	director.tick(1.0, player, units)
	_check("进入 2000px 激活", director.is_group_active(&"airfield_a"), "")
	_check("5 架敌机只分流 1 架", _asset_assignment_count(hostiles) == 1,
		"assigned=%d" % _asset_assignment_count(hostiles))

	var sixth := _make_aircraft(CombatUnit.TEAM_HOSTILE, Vector2(1200.0, 0.0))
	sixth.callsign = "H5"
	hostiles.append(sixth)
	units.append(sixth)
	director.tick(1.0, player, units)
	_check("6 架敌机分流 2 架", _asset_assignment_count(hostiles) == 2,
		"assigned=%d" % _asset_assignment_count(hostiles))
	var departing := _first_asset_attacker(hostiles)
	departing.global_position = Vector2(6100.0, 0.0)
	director.tick(1.0, player, units)
	_check("离开 6000px 参与圈立即释放", departing._ai_ref.get_target_source() != AIController.TargetSource.TS_ASSET, "")
	_check("参与圈内剩 5 架时配额回落为 1", _asset_assignment_count(hostiles) == 1,
		"assigned=%d" % _asset_assignment_count(hostiles))
	departing.global_position = Vector2(800.0, 0.0)
	director.tick(1.0, player, units)
	_check("返回参与圈后恢复 H=6 配额", _asset_assignment_count(hostiles) == 2,
		"assigned=%d" % _asset_assignment_count(hostiles))

	# 第二个 ACTIVE 据点重叠时仍共享一个 Q；9 架最多 3 架。
	var target_b := GroundUnit.new()
	target_b.team = CombatUnit.TEAM_ALLY
	target_b.callsign = "ALLY-AA"
	target_b.global_position = Vector2(100.0, 0.0)
	director.register_airfield(&"airfield_b", target_b.global_position)
	director.register_target(&"airfield_b", target_b)
	units.append(target_b)
	for i in range(3):
		var ac := _make_aircraft(CombatUnit.TEAM_HOSTILE, Vector2(1400.0 + i * 60.0, 0.0))
		ac.callsign = "HX%d" % i
		hostiles.append(ac)
		units.append(ac)
	director.tick(1.0, player, units)
	_check("重叠据点 9 架共享总配额 3", _asset_assignment_count(hostiles) == 3,
		"assigned=%d" % _asset_assignment_count(hostiles))

	# 退出圈外 7 秒仍 ACTIVE，第 8 秒才释放。
	player.global_position = Vector2(2700.0, 0.0)
	for _i in range(7):
		director.tick(1.0, player, units)
	_check("退出宽限 7s 仍 ACTIVE", director.is_group_active(&"airfield_a"), "")
	director.tick(1.0, player, units)
	_check("退出宽限 8s 转 DORMANT", not director.is_group_active(&"airfield_a"), "")
	_check("离场后释放所有设施目标", _asset_assignment_count(hostiles) == 0,
		"assigned=%d" % _asset_assignment_count(hostiles))

	director.reset()
	for ac in hostiles:
		ac.free()
	player.free()
	target.free()
	target_b.free()


func _test_friendly_carrier_hp_override() -> void:
	var base: NavalParams = load("res://resources/naval/carrier_cv.tres")
	var friendly: NavalParams = base.duplicate(true)
	friendly.default_team = CombatUnit.TEAM_PLAYER
	friendly.hull_hp_max = 300.0
	_check("敌方航母资源仍为 1200 HP", is_equal_approx(base.hull_hp_max, 1200.0),
		"base=%.0f" % base.hull_hp_max)
	_check("友军复制体可覆写为 300 HP", is_equal_approx(friendly.hull_hp_max, 300.0),
		"friendly=%.0f" % friendly.hull_hp_max)


func _make_aircraft(team: int, pos: Vector2) -> Aircraft:
	var ac := Aircraft.new()
	ac.team = team
	ac.global_position = pos
	var ai := AIController.new()
	ai.aircraft = ac
	ac._ai_ref = ai
	ac.add_child(ai)
	return ac


func _asset_assignment_count(hostiles: Array[Aircraft]) -> int:
	var count := 0
	for ac in hostiles:
		if ac._ai_ref != null and ac._ai_ref.get_target_source() == AIController.TargetSource.TS_ASSET:
			count += 1
	return count


func _first_asset_attacker(hostiles: Array[Aircraft]) -> Aircraft:
	for ac in hostiles:
		if ac._ai_ref != null and ac._ai_ref.get_target_source() == AIController.TargetSource.TS_ASSET:
			return ac
	return null


func _check(name: String, got: bool, note: String) -> void:
	if got:
		_pass += 1
	else:
		_fail += 1
	print("  %s %-32s — %s" % ["✓" if got else "✗", name, note])
