extends RefCounted

var _passed := 0
var _failed := 0


func run() -> Dictionary:
	print("\n════════ 尾迹几何 LOD 测试 ════════")
	_check(TrailRibbon.geometry_point_step_for(0.35, false, false) == 1,
		"常规视距保持全精度")
	_check(TrailRibbon.geometry_point_step_for(0.20, false, false) == 2,
		"战略远景普通飞机尾迹隔点连接")
	_check(TrailRibbon.geometry_point_step_for(0.20, false, false, true) == 4,
		"战略远景普通导弹尾迹四点连接")
	_check(TrailRibbon.geometry_point_step_for(0.20, true, false) == 1,
		"玩家 Boss Sentinel 本体保持全精度")
	_check(TrailRibbon.geometry_point_step_for(0.20, false, true) == 1,
		"玩家发射导弹保持全精度")
	_check(TrailRibbon.geometry_point_step_for(0.20, true, false, true) == 1,
		"真实来袭导弹保持全精度")
	_check(TrailRibbon.SAMPLE_PHASE_SLOTS == 8,
		"导弹尾迹批次沿用八相采样分桶")
	print("──────── 结果：%d 通过 / %d 失败 ────────\n" % [_passed, _failed])
	return {"passed": _passed, "failed": _failed}


func _check(ok: bool, label: String) -> void:
	if ok:
		_passed += 1
		print("  ✓ %s" % label)
	else:
		_failed += 1
		print("  ✗ %s" % label)
