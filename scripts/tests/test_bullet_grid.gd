extends RefCounted

## 无头验收：命中广相网格（UnitGrid）与"暴力全扫"命中等价（2026-07-24 航母群掉帧修复 ③）
##
## 核心不变量（保证子弹碰撞不漏判）：
##   对任意查询点 pos，UnitGrid 的候选集（large_units + pos 的 3×3 邻格小单位）
##   必然包含"距 pos <= GRID_CELL_SIZE 的所有小单位" + 全部大单位（NavalUnit）。
##   因为真实命中半径（≤ 20px）远小于 GRID_CELL_SIZE(256)，命中集 ⊆ 候选集 ⊆ 全场，
##   所以对候选集做与旧代码完全相同的距离/半径判定 → 命中结果与遍历 combat_unit_list 逐字节等价。
##
## 运行：godot --headless --path . -- --bench=bullet_grid（或 --bench=all）

const CELL := 256.0    # 与 BulletManager.GRID_CELL_SIZE 对齐

var _pass := 0
var _fail := 0
var _spawned: Array = []   # 需要手动 free 的孤儿节点


func run() -> void:
	print("\n════════ 命中广相网格 等价性验收 ════════")
	_test_neighborhood_superset()
	_test_hit_radius_equivalence()
	_test_large_units_always_present()
	_test_destroyed_excluded()
	_test_empty_grid()
	_cleanup()
	print("──────── 结果：%d 通过 / %d 失败 ────────" % [_pass, _fail])
	print("══════════════════════════════════════════════════\n")


func _check(cond: bool, label: String) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		printerr("  ✗ FAIL: %s" % label)


# ── 造孤儿单位（不入树 → 不触发 _ready；global_position == position）──
func _make_small(pos: Vector2) -> CombatUnit:
	var u := CombatUnit.new()
	u.position = pos
	_spawned.append(u)
	return u

func _make_naval(pos: Vector2) -> NavalUnit:
	var u := NavalUnit.new()
	u.position = pos
	_spawned.append(u)
	return u

func _cleanup() -> void:
	for u in _spawned:
		if is_instance_valid(u):
			u.free()
	_spawned.clear()


# ── A. 邻域超集：距查询点 <= CELL 的小单位必在候选集里 ──
func _test_neighborhood_superset() -> void:
	print("── A. 3×3 邻域 ⊇ {距查询点 ≤ CELL 的小单位} ──")
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260724
	var units: Array = []
	for i in range(300):
		# 覆盖负坐标（世界坐标可为负，floori 分格必须正确处理）
		units.append(_make_small(Vector2(rng.randf_range(-8000, 8000), rng.randf_range(-8000, 8000))))
	var naval: Array = []
	for i in range(8):
		naval.append(_make_naval(Vector2(rng.randf_range(-8000, 8000), rng.randf_range(-8000, 8000))))
	var all_units: Array = units.duplicate()
	all_units.append_array(naval)

	var grid := UnitGrid.new()
	grid.rebuild(all_units, CELL)

	var misses := 0
	var buf: Array = []
	for q in range(400):
		var pos := Vector2(rng.randf_range(-8000, 8000), rng.randf_range(-8000, 8000))
		buf.clear()
		grid.query_into(pos, buf)
		# 暴力：所有距 pos <= CELL 的小单位都必须在 buf 里
		for u in units:
			if pos.distance_to(u.global_position) <= CELL:
				if not buf.has(u):
					misses += 1
	_check(misses == 0, "A 邻域漏判 %d 个（应为 0）" % misses)


# ── B. 真实命中半径等价：hit_r=20 时，候选集过滤结果 == 全场过滤结果 ──
func _test_hit_radius_equivalence() -> void:
	print("── B. hit_r=20 候选集命中 == 全场命中 ──")
	var rng := RandomNumberGenerator.new()
	rng.seed = 777
	var units: Array = []
	# 故意做几簇密集单位，制造"多个单位挤在命中半径内"的极端情况
	for c in range(20):
		var center := Vector2(rng.randf_range(-6000, 6000), rng.randf_range(-6000, 6000))
		for k in range(15):
			units.append(_make_small(center + Vector2(rng.randf_range(-40, 40), rng.randf_range(-40, 40))))
	var naval: Array = [_make_naval(Vector2(0, 0)), _make_naval(Vector2(3000, -2000))]
	var all_units: Array = units.duplicate()
	all_units.append_array(naval)

	var grid := UnitGrid.new()
	grid.rebuild(all_units, CELL)

	var hit_r := 20.0
	var mismatch := 0
	var buf: Array = []
	# 查询点就用每个单位自身位置（子弹命中场景：弹落在单位附近）
	for u0 in units:
		var pos: Vector2 = u0.global_position
		# 全场暴力命中集（含大单位，大单位这里用同一 hit_r 简化，仅验证集合等价性）
		var brute: Array = []
		for u in all_units:
			if pos.distance_to(u.global_position) < hit_r:
				brute.append(u)
		# 广相：large_units + 邻格
		buf.clear()
		buf.append_array(grid.large_units)
		grid.query_into(pos, buf)
		var grid_hits: Array = []
		for u in buf:
			if pos.distance_to(u.global_position) < hit_r:
				grid_hits.append(u)
		# 集合相等（顺序无关）
		if brute.size() != grid_hits.size():
			mismatch += 1
		else:
			for u in brute:
				if not grid_hits.has(u):
					mismatch += 1
					break
	_check(mismatch == 0, "B 命中集不等 %d 处（应为 0）" % mismatch)


# ── C. 大单位（NavalUnit）恒在 large_units，不入网格 ──
func _test_large_units_always_present() -> void:
	print("── C. NavalUnit → large_units（恒扫）──")
	var n1 := _make_naval(Vector2(500, 500))
	var n2 := _make_naval(Vector2(-9000, 9000))
	var s1 := _make_small(Vector2(500, 500))
	var grid := UnitGrid.new()
	grid.rebuild([n1, n2, s1], CELL)
	_check(grid.large_units.has(n1) and grid.large_units.has(n2), "C 两艘船都应在 large_units")
	_check(not grid.large_units.has(s1), "C 小单位不应进 large_units")
	# 远在天边的船也要能被查到（通过 large_units 恒扫，与查询点无关）
	var buf: Array = []
	buf.append_array(grid.large_units)
	grid.query_into(Vector2(500, 500), buf)
	_check(buf.has(n2), "C 远处船必须靠 large_units 恒扫命中（不依赖邻格）")


# ── D. is_destroyed / 无效单位被 rebuild 过滤掉 ──
func _test_destroyed_excluded() -> void:
	print("── D. is_destroyed 单位不进候选 ──")
	var alive := _make_small(Vector2(100, 100))
	var dead := _make_small(Vector2(110, 100))
	dead.is_destroyed = true
	var grid := UnitGrid.new()
	grid.rebuild([alive, dead], CELL)
	var buf: Array = []
	grid.query_into(Vector2(105, 100), buf)
	_check(buf.has(alive), "D 存活单位应在候选")
	_check(not buf.has(dead), "D 已毁单位不应在候选")


# ── E. 空网格查询不崩、返回空 ──
func _test_empty_grid() -> void:
	print("── E. 空网格 ──")
	var grid := UnitGrid.new()
	grid.rebuild([], CELL)
	var buf: Array = []
	grid.query_into(Vector2(0, 0), buf)
	_check(buf.is_empty() and grid.large_units.is_empty(), "E 空网格候选应为空")
