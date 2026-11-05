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
	var trail := TrailRibbon.new()
	trail._visibility_fade_in = 1.0
	for i in range(80):
		trail.add_point(Vector2(i * 8, sin(i * 0.1) * 12), 0.0, i * 0.01)
	trail._rebuild_cached_geometry()
	var topology := trail._cached_indices.duplicate()
	var vertices := trail._cached_verts.duplicate()
	var colors := trail._cached_colors.duplicate()
	_check(topology.size() == 474 and topology.slice(468) == PackedInt32Array([156,157,158,157,159,158]),
		"满长度尾迹连接末端不缺面")
	trail.add_point(Vector2(650, 25), 0.0, 0.8)
	trail.ribbon_width *= 1.5
	trail.ribbon_color.a *= 0.5
	trail._rebuild_cached_geometry()
	_check(trail._cached_indices == topology and trail._cached_verts != vertices and trail._cached_colors != colors,
		"滑动采样和样式变化保留连接但更新真实几何颜色")
	for step in [2,4,1]:
		trail._cached_point_step = step
		trail._rebuild_cached_geometry()
		var expected_points := ceili(79.0 / step) + 1
		_check(trail._cached_indices.size() == (expected_points - 1) * 6
			and trail._cached_indices[-2] == expected_points * 2 - 1
			and trail._cached_indices[-1] == expected_points * 2 - 2,
			"视距档切换重新匹配首尾顶点 step=%d" % step)
	trail.clear_trail()
	trail._rebuild_cached_geometry()
	_check(trail._cached_indices.is_empty(), "清空尾迹清除旧连接")
	trail.add_point(Vector2.ZERO, 0, 0)
	trail.add_point(Vector2(10, 10), 0, 0)
	trail._rebuild_cached_geometry()
	_check(trail._cached_indices == PackedInt32Array([0,1,2,1,3,2]), "重生双点尾迹不保留长网格")
	trail.free()
	print("──────── 结果：%d 通过 / %d 失败 ────────\n" % [_passed, _failed])
	return {"passed": _passed, "failed": _failed}


func _check(ok: bool, label: String) -> void:
	if ok:
		_passed += 1
		print("  ✓ %s" % label)
	else:
		_failed += 1
		print("  ✗ %s" % label)
