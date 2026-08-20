extends RefCounted

var _passed := 0
var _failed := 0


func run() -> Dictionary:
	print("\n════════ 目标标记 LOD 测试 ════════")
	_check(AircraftRenderer.target_marker_detail_visible_at_scale(0.35, false),
		"常规视距显示完整端点标记")
	_check(not AircraftRenderer.target_marker_detail_visible_at_scale(0.20, false),
		"战略远景普通友军只保留主连线")
	_check(AircraftRenderer.target_marker_detail_visible_at_scale(0.20, true),
		"当前操控机始终显示完整端点标记")
	_check(AircraftRenderer.target_marker_detail_visible_at_scale(0.20, false, true),
		"强制完整显示覆盖战略 LOD")
	_check(not NavalUnit.mount_detail_visible_at_scale(0.20),
		"战略远景舰船挂点批量显示位置与存活状态")
	_check(NavalUnit.mount_detail_visible_at_scale(0.35),
		"常规视距保留舰船挂点武器类型细节")
	_check(NavalUnit.mount_detail_visible_at_scale(0.20, true),
		"强制完整显示覆盖舰船挂点 LOD")
	print("──────── 结果：%d 通过 / %d 失败 ────────\n" % [_passed, _failed])
	return {"passed": _passed, "failed": _failed}


func _check(ok: bool, label: String) -> void:
	if ok:
		_passed += 1
		print("  ✓ %s" % label)
	else:
		_failed += 1
		print("  ✗ %s" % label)
