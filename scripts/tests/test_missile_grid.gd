extends RefCounted

## 导弹空间 broad-phase 契约：候选不得漏掉真实引信范围目标，并保持 target_list 首命中顺序。

var _passed := 0
var _failed := 0
var _spawned: Array[CombatUnit] = []


func run() -> Dictionary:
	print("\n════════ 导弹命中空间网格测试 ════════")
	_test_nearby_superset_and_far_cull()
	_test_naval_always_present()
	_test_target_order_preserved()
	_cleanup()
	print("──────── 结果：%d 通过 / %d 失败 ────────\n" % [_passed, _failed])
	return {"passed": _passed, "failed": _failed}


func _make_unit(pos: Vector2) -> CombatUnit:
	var unit := CombatUnit.new()
	unit.position = pos
	_spawned.append(unit)
	return unit


func _make_ship(pos: Vector2) -> NavalUnit:
	var ship := NavalUnit.new()
	ship.position = pos
	_spawned.append(ship)
	return ship


func _manager_with(units: Array[CombatUnit]) -> MissileManager:
	var manager := MissileManager.new()
	manager.target_list = units
	manager._rebuild_target_grid()
	return manager


func _test_nearby_superset_and_far_cull() -> void:
	var near := _make_unit(Vector2(20, 0))
	var adjacent_cell := _make_unit(Vector2(260, 0))
	var far := _make_unit(Vector2(2000, 0))
	var manager := _manager_with([near, adjacent_cell, far])
	var candidates: Array = manager._ordered_target_candidates(Vector2.ZERO).duplicate()
	_check(candidates.has(near), "引信附近单位进入候选")
	_check(candidates.has(adjacent_cell), "相邻网格单位进入保守候选")
	_check(not candidates.has(far), "远距小单位被 broad-phase 剔除")
	manager.free()


func _test_naval_always_present() -> void:
	var ship := _make_ship(Vector2(5000, 0))
	var manager := _manager_with([ship])
	var candidates: Array = manager._ordered_target_candidates(Vector2.ZERO).duplicate()
	_check(candidates.has(ship), "远距舰船仍进入 large_units 候选")
	manager.free()


func _test_target_order_preserved() -> void:
	var first := _make_unit(Vector2(10, 0))
	var ship := _make_ship(Vector2(0, 0))
	var second := _make_unit(Vector2(15, 0))
	var manager := _manager_with([first, ship, second])
	var candidates: Array = manager._ordered_target_candidates(Vector2.ZERO).duplicate()
	_check(candidates.size() == 3, "重叠目标候选数量保持完整")
	_check(candidates.size() == 3 and candidates[0] == first \
		and candidates[1] == ship and candidates[2] == second,
		"候选顺序与 target_list 完全一致")
	manager.free()


func _cleanup() -> void:
	for unit in _spawned:
		if is_instance_valid(unit):
			unit.free()
	_spawned.clear()


func _check(ok: bool, label: String) -> void:
	if ok:
		_passed += 1
		print("  ✓ %s" % label)
	else:
		_failed += 1
		print("  ✗ %s" % label)
