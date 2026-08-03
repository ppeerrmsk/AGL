extends RefCounted

## BOSS 通关强化分层纯数据 + MQ-111 累计拦截回归。
## 运行：bench/run.cmd boss_progression

var _pass: int = 0
var _fail: int = 0

func run() -> void:
	print("\n════════ BOSS 通关强化测试 ════════")
	_test_progression_counts()
	_test_carrier_composition()
	_test_goose_variant_gate()
	_test_mq111_cumulative_intercept()
	print("──────── 结果：%d 通过 / %d 失败 ────────" % [_pass, _fail])

func _test_progression_counts() -> void:
	var enc := BossEncounter.new()
	enc.configure_progression(-3)
	_check("负次数钳到 0", enc.prior_defeats == 0, "got=%d" % enc.prior_defeats)
	enc.configure_progression(2)
	_check("完整次数保留", enc.prior_defeats == 2, "got=%d" % enc.prior_defeats)
	_check("Wraith 初见无支援", F47AceSquad.support_count_for_progression(0) == 0, "")
	_check("Wraith 首败后双支援", F47AceSquad.support_count_for_progression(1) == 2, "")
	_check("Wraith 二败暂沿用双支援", F47AceSquad.support_count_for_progression(2) == 2, "")

func _test_carrier_composition() -> void:
	var first: Dictionary = CarrierStrikeGroup.escort_counts_for_progression(0)
	_check("航母初见无 CG", int(first["cg"]) == 0, str(first))
	_check("航母初见 2 DDG", int(first["ddg"]) == 2, str(first))
	_check("航母初见 6 FFG", int(first["ffg"]) == 6, str(first))
	var enhanced: Dictionary = CarrierStrikeGroup.escort_counts_for_progression(1)
	_check("航母首败后 2 CG", int(enhanced["cg"]) == 2, str(enhanced))
	_check("航母首败后 2 DDG", int(enhanced["ddg"]) == 2, str(enhanced))
	_check("航母首败后 8 FFG", int(enhanced["ffg"]) == 8, str(enhanced))
	_check("航母二败暂沿用强化 1", CarrierStrikeGroup.escort_counts_for_progression(2) == enhanced, "")

func _test_goose_variant_gate() -> void:
	var first: Array = MotherGooseUAVSwarm.variant_weights_for_progression(0)
	_check("Goose 初见禁激光", int(first[MotherGooseUAVSwarm.Variant.MQ_111_LASER]) == 0, str(first))
	_check("Goose 初见禁电磁炮", int(first[MotherGooseUAVSwarm.Variant.MQ_112_RAILGUN]) == 0, str(first))
	var enhanced: Array = MotherGooseUAVSwarm.variant_weights_for_progression(1)
	_check("Goose 首败后激光权重 15", int(enhanced[MotherGooseUAVSwarm.Variant.MQ_111_LASER]) == 15,
		str(enhanced))
	_check("Goose 首败后电磁炮权重 15", int(enhanced[MotherGooseUAVSwarm.Variant.MQ_112_RAILGUN]) == 15,
		str(enhanced))
	_check("Goose 二败暂沿用强化 1",
		MotherGooseUAVSwarm.variant_weights_for_progression(2) == enhanced, "")

func _test_mq111_cumulative_intercept() -> void:
	var laser: LaserEquipment = load("res://resources/uav_mg_laser.tres") as LaserEquipment
	_check("MQ-111 开启直接拦截", laser != null and laser.intercepts_missiles_directly, "")
	if laser == null:
		return
	var holder := Node2D.new()
	var missile := Missile.new()
	missile.intercept_hp = 10.0
	holder.add_child(missile)
	laser._apply_laser_effect(null, missile, 4.0, false)
	_check("首段照射先减速", missile._laser_slow_timer > 0.0, "timer=%.2f" % missile._laser_slow_timer)
	_check("首段照射累计扣拦截 HP", is_equal_approx(missile.intercept_hp, 6.0),
		"hp=%.1f" % missile.intercept_hp)
	_check("未到阈值不销毁", not missile.is_queued_for_deletion(), "")
	laser._apply_laser_effect(null, missile, 6.0, false)
	_check("累计到阈值后销毁", missile.is_queued_for_deletion(), "hp=%.1f" % missile.intercept_hp)
	holder.queue_free()

func _check(label: String, ok: bool, detail: String) -> void:
	if ok:
		_pass += 1
		print("  ✓ %s" % label)
	else:
		_fail += 1
		printerr("  ✗ %s%s" % [label, " — %s" % detail if not detail.is_empty() else ""])
