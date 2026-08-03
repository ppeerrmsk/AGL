extends RefCounted

## 无头行为验收：轮盘位置命令的加速与禁入区（spec: docs/specs/systems/command-wheel.md §2.7/§2.7.1/§3.7）
##
## - 紧急集合：全队 command_sprint（effective 速度 ×1.4，accessor 注入）→ 到达 arrival_radius 逐机解除
## - 撤离此区：圈内成员 sprint + 径向出圈目标 / 圈外成员不生效 → 出圈逐机解除；
##   撤离圈成为限时禁入区：AI 自主搜敌（_find_target）过滤圈内、到时/新广播命令解除
## - 防守此区：TRANSIT 不加速；到区后全队分头领圈内目标，击杀后接续，
##   圈外不获取、越界回防、清空后继续盘旋守备
##
## 运行：godot --headless --path . -- --bench=wheel_orders（或 --bench=all）

var _pass := 0
var _fail := 0
var _root: Node2D = null
var _saved_units: Array = []


class StubMode extends Node:
	var selected_aircraft: Array[Aircraft] = []
	var player_aircraft: Aircraft = null
	var upgrade_stacks: Dictionary = {}


func run() -> void:
	print("\n════════ 轮盘位置命令验收（加速 / 禁入区） ════════")
	_root = Node2D.new()
	_saved_units = CombatUnit.all_units.duplicate()
	_test_regroup_sprint()
	_test_evacuate_sprint_and_zone()
	_test_guard_no_sprint()
	_test_guard_area_clear()
	CombatUnit.all_units.clear()
	for u in _saved_units:
		CombatUnit.all_units.append(u)
	_root.free()
	_root = null
	print("──────── 结果：%d 通过 / %d 失败 ────────" % [_pass, _fail])
	print("══════════════════════════════════════════════════\n")


# ── A. 紧急集合：全队冲刺 + 到达逐机解除 ──
func _test_regroup_sprint() -> void:
	print("── A. 紧急集合：全队全力加速 → 到达解除 ──")
	var a: Array = [_make_ac(Vector2.ZERO), _make_ac(Vector2(200, 0))]
	var c := _make_controller(a)
	CombatUnit.all_units.clear()
	var point := Vector2(4000, 0)
	c.command_regroup(point)
	_check("全队 command_sprint 置位", a[0].command_sprint and a[1].command_sprint, "2 机冲刺")
	var base: float = a[0].params.max_speed
	var boosted: float = AircraftPhysics.effective_max_speed_kmh(a[0])
	_check("有效顶速经 accessor 抬升（AI 战术层可感知）", boosted > base * 1.3,
		"%.0f → %.0f km/h" % [base, boosted])
	# a0 抵达集合点（arrival 600px 内）→ 该机解除，a1 仍冲刺
	a[0].position = point + Vector2(100, 0)
	c.tick(0.5)
	_check("到达者解除冲刺（逐机先到先解除）", not a[0].command_sprint and a[1].command_sprint,
		"a0 解除 / a1 保持")
	# a1 也到 → 全解除
	a[1].position = point
	c.tick(0.5)
	_check("全员到达 → 冲刺状态归零", not a[1].command_sprint, "a1 解除")
	_cleanup(c)


# ── B. 撤离此区：圈内冲刺散出 + 禁入区过滤 ──
func _test_evacuate_sprint_and_zone() -> void:
	print("── B. 撤离此区：圈内加速散出 / 圈外不生效 / 禁入区决策过滤 ──")
	var inside = _make_ac(Vector2(200, 0))       # 距圈心 200px（圈内）
	var outside = _make_ac(Vector2(4000, 0))     # 距圈心 4000px（1500px 圈外）
	var a: Array = [inside, outside]
	var c := _make_controller(a)
	var zone_enemy := _make_enemy(Vector2(300, 100))    # 禁入圈内敌机
	var free_enemy := _make_enemy(Vector2(2500, 0))     # 圈外敌机
	CombatUnit.all_units.clear()
	for u in [zone_enemy, free_enemy]:
		CombatUnit.all_units.append(u)

	var point := Vector2.ZERO
	c.command_evacuate(point)
	_check("圈内成员冲刺 + 径向出圈目标", inside.command_sprint and inside.target_position != Vector2.INF,
		"target=(%.0f, %.0f)" % [inside.target_position.x, inside.target_position.y])
	_check("圈外成员不生效（不冲刺、航点不动）",
		not outside.command_sprint and outside.target_position == Vector2.INF, "outside 未受扰动")
	_check("禁入区激活 + 圈框标记已生成", c._evac_zone_active() and c._zone_marker != null, "20s 计时")
	# AI 自主搜敌过滤圈内：从 (600,0) 搜 3000px——圈内敌 316px 远近于圈外敌 1900px，
	# 无过滤必选圈内敌；过滤生效则跳到圈外敌
	var picked: CombatUnit = c._find_target(Vector2(600, 0), 3000.0)
	_check("自主搜敌跳过禁入圈内目标", picked == free_enemy, "选中圈外敌")
	# 出圈解除冲刺
	inside.position = Vector2(1700, 0)
	c.tick(0.5)
	_check("出圈者解除冲刺", not inside.command_sprint, "inside 已出圈")
	# 到时解除：把计时拨到过期
	c._evac_zone_until_ms = Time.get_ticks_msec() - 1
	var picked2: CombatUnit = c._find_target(Vector2(600, 0), 3000.0)
	_check("禁入区到时自动解除（搜敌恢复圈内）", picked2 == zone_enemy, "重新选中原圈内敌")
	# 新广播命令终止禁入区
	c.command_evacuate(point)   # 重新激活
	var active_before: bool = c._evac_zone_active()
	c.command_regroup(Vector2(5000, 5000))
	_check("新广播命令终止禁入区", active_before and not c._evac_zone_active(), "regroup 清除 zone")
	_cleanup(c)


# ── C. 防守 TRANSIT 不加速 ──
func _test_guard_no_sprint() -> void:
	print("── C. 防守此区：TRANSIT 普通速度（无加速条款）──")
	var a: Array = [_make_ac(Vector2.ZERO)]
	var c := _make_controller(a)
	CombatUnit.all_units.clear()
	c.command_guard(Vector2(3000, 0))
	_check("防守前往不冲刺", not a[0].command_sprint and a[0].target_position == Vector2(3000, 0),
		"普通巡航 TRANSIT")
	_cleanup(c)


# ── D. 防守区域清剿：自主分火 → 击杀接续 → 越界/清空回防 ──
func _test_guard_area_clear() -> void:
	print("── D. 防守此区：自主搜索并全歼圈内敌人 ──")
	var a: Array = [_make_ac(Vector2(-200, 0)), _make_ac(Vector2(200, 0))]
	var c := _make_controller(a)
	var e1 := _make_enemy(Vector2(300, 0))
	var e2 := _make_enemy(Vector2(-400, 0))
	var e3 := _make_enemy(Vector2(0, 700))
	var outside := _make_enemy(Vector2(1800, 0))   # guard 1500px 圈外
	CombatUnit.all_units.clear()
	for u in [e1, e2, e3, outside]:
		CombatUnit.all_units.append(u)

	c.command_guard(Vector2.ZERO)
	c.tick(0.5)
	_check("到区后当前操控机也会自主领目标",
			a[0].commanded_target in [e1, e2, e3], "玩家机已投入清剿")
	_check("多机优先分头接战",
			a[0].commanded_target != null and a[1].commanded_target != null \
				and a[0].commanded_target != a[1].commanded_target, "首轮目标不同")
	_check("圈外敌人不进入清剿池",
			a[0].commanded_target != outside and a[1].commanded_target != outside, "outside 未被获取")

	# 击毁 a0 当前目标：下一 tick 应自动领取尚未被 a1 认领的第三个圈内目标。
	var first_target: CombatUnit = a[0].commanded_target
	first_target.is_destroyed = true
	c.tick(0.5)
	_check("击杀后自动接续下一个圈内目标",
			a[0].commanded_target != null and a[0].commanded_target != first_target \
				and a[0].commanded_target != a[1].commanded_target \
				and a[0].commanded_target != outside, "清剿链继续")

	# 把 a1 的活目标拖出 3.45km leash：应放弃且绝不改追同一个圈外目标。
	var escaped: CombatUnit = a[1].commanded_target
	escaped.position = Vector2(1800, 300)
	c.tick(0.5)
	_check("目标越界后放弃追击",
			a[1].commanded_target != escaped and a[1].combat_target != escaped, "越界目标已释放")

	# 清空所有圈内目标：任务仍激活，但借用的铁律目标全部回收并回圆心守备。
	for enemy in [e1, e2, e3]:
		enemy.is_destroyed = true
	c.tick(0.5)
	_check("圈内全灭后回收目标并继续守备",
			a[0].commanded_target == null and a[1].commanded_target == null \
				and c._guard_point == Vector2.ZERO, "清空后 guard standing order 仍在")
	_cleanup(c)


# ── 工具 ──

func _make_ac(pos: Vector2):
	var ac = load("res://scripts/aircraft.gd").new()
	var p := AircraftParams.new()
	p.max_speed = 2100.0
	p.cruise_speed = 900.0
	ac.params = p
	ac.heading = 0.0
	ac.altitude = 5000.0
	ac.speed = 250.0
	ac.target_position = Vector2.INF
	ac.position = pos
	_root.add_child(ac)
	return ac


func _make_enemy(pos: Vector2) -> CombatUnit:
	var t := CombatUnit.new()
	t.team = 1
	t.position = pos
	_root.add_child(t)
	return t


func _make_controller(members: Array) -> SquadCommandController:
	var mode := StubMode.new()
	_root.add_child(mode)
	for ac in members:
		mode.selected_aircraft.append(ac)
	mode.player_aircraft = members[0]
	var c := SquadCommandController.new()
	_root.add_child(c)
	c.setup(mode, RtsCommandParams.new())
	c.wheel_params = CommandWheelParams.new()
	return c


func _cleanup(c: SquadCommandController) -> void:
	c._clear_sprint()
	c._clear_evac_zone()
	c._end_spread()


func _check(name: String, ok: bool, note: String) -> void:
	if ok:
		_pass += 1
		print("  ✓ %s — %s" % [name, note])
	else:
		_fail += 1
		print("  ✗ %s — %s" % [name, note])
