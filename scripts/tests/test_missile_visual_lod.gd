extends RefCounted

var _passed := 0
var _failed := 0


func run() -> Dictionary:
	print("\n════════ 导弹视觉 LOD 测试 ════════")
	_check(Missile.data_label_visible_at_scale(0.30, false),
		"常规视距保留导弹数据标签")
	_check(not Missile.data_label_visible_at_scale(0.20, false),
		"战略远景省略非关键导弹数据标签")
	_check(Missile.data_label_visible_at_scale(0.20, true),
		"战略远景保留玩家发射导弹标签")
	_check(not Missile.data_label_visible_at_scale(0.20, false),
		"战略远景由独立来袭图形承担敌弹警告")
	_check(Missile.data_label_visible_at_scale(0.20, false, true),
		"强制完整显示覆盖战略远景 LOD")
	_check(not Missile.body_detail_visible_at_scale(0.20, false, false),
		"战略远景普通导弹使用单轮廓弹体")
	_check(Missile.body_detail_visible_at_scale(0.20, true, false),
		"战略远景保留玩家导弹完整翼面")
	_check(Missile.body_detail_visible_at_scale(0.20, false, true),
		"战略远景保留真实来袭导弹完整警告弹体")
	print("──────── 结果：%d 通过 / %d 失败 ────────\n" % [_passed, _failed])
	return {"passed": _passed, "failed": _failed}


func _check(ok: bool, label: String) -> void:
	if ok:
		_passed += 1
		print("  ✓ %s" % label)
	else:
		_failed += 1
		print("  ✗ %s" % label)
