extends RefCounted

## 无头行为验收：火力分配（spec: docs/specs/systems/command-wheel.md §3.6）
##
## FOCUS = 全队统一咬同一目标（铁律通道）+ 包围轴分离：≥2 机、散开阵型时按
##         "目标→小队质心"基准分配绝对进入方位，相邻 ≥45°；TIGHT 阵型不包围。
##         消费端 TacticalPlanner._apply_surround_axis：远于收敛距时飞向自己扇区门点。
## SPREAD = 以按下目标为锚点的目标池内各自接敌：少人打的优先（让路）+ 粘性防乒乓 +
##         单点点名退出分火管理（铁律保护）+ 池清空命令结束。
##
## 运行：godot --headless --path . -- --bench=fire_alloc（或 --bench=all）

var _pass := 0
var _fail := 0
var _root: Node2D = null
var _saved_units: Array = []


## 控制器只动态读 selected_aircraft / player_aircraft，用 stub 即可（无编队 →
## _squad_members 退化为 selected，正好把成员集置于测试控制下）
class StubMode extends Node:
	var selected_aircraft: Array[Aircraft] = []
	var player_aircraft: Aircraft = null


func run() -> void:
	print("\n════════ 火力分配验收（FOCUS 包围 / SPREAD 各自接敌） ════════")
	_root = Node2D.new()
	_saved_units = CombatUnit.all_units.duplicate()
	_test_focus_surround()
	_test_focus_tight_no_surround()
	_test_planner_surround_gate()
	_test_spread_flow()
	CombatUnit.all_units.clear()
	for u in _saved_units:
		CombatUnit.all_units.append(u)
	_root.free()
	_root = null
	print("──────── 结果：%d 通过 / %d 失败 ────────" % [_pass, _fail])
	print("══════════════════════════════════════════════════\n")


# ── A. FOCUS 包围轴分配 ──
func _test_focus_surround() -> void:
	print("── A. FOCUS 集火：包围轴分配（相邻 ≥45°）──")
	var a: Array = [_make_ac(Vector2.ZERO), _make_ac(Vector2(100, 0)), _make_ac(Vector2(-100, 0))]
	var tgt := _make_enemy(Vector2(0, -2000))
	var c := _make_controller(a)
	c.fire_allocation = SquadCommandController.FireAllocation.FOCUS
	c.command_attack_all(tgt, Situation.POSTURE_AUTO)

	var all_cmd := true
	var all_finite := true
	for ac in a:
		if ac.commanded_target != tgt:
			all_cmd = false
		if not is_finite(ac.surround_bearing_rad):
			all_finite = false
	_check("全队 commanded_target 统一咬点名目标", all_cmd, "3 机")
	_check("包围方位全部已分配", all_finite, "bearings=[%d°, %d°, %d°]" % [
		int(rad_to_deg(a[0].surround_bearing_rad)), int(rad_to_deg(a[1].surround_bearing_rad)),
		int(rad_to_deg(a[2].surround_bearing_rad))])
	var min_sep := 999.0
	for i in a.size():
		for j in range(i + 1, a.size()):
			min_sep = minf(min_sep, _sep_deg(a[i].surround_bearing_rad, a[j].surround_bearing_rad))
	_check("相邻攻击轴分离 ≥45°（杜绝追尾长蛇）", min_sep >= 44.0, "最小间隔 %.0f°" % min_sep)
	# 新命令清除包围方位
	c.command_move(Vector2(500, 500))
	_check("移动命令清除包围方位", not is_finite(a[0].surround_bearing_rad), "bearing 归 INF")
	_cleanup(c)


# ── B. TIGHT 阵型不包围 ──
func _test_focus_tight_no_surround() -> void:
	print("── B. TIGHT 紧密阵型：不分配包围轴（阵型纪律优先）──")
	var a: Array = [_make_ac(Vector2.ZERO), _make_ac(Vector2(100, 0))]
	var tgt := _make_enemy(Vector2(0, -2000))
	var c := _make_controller(a)
	c.fire_allocation = SquadCommandController.FireAllocation.FOCUS
	c.formation_tight = true
	c.command_attack_all(tgt, Situation.POSTURE_AUTO)
	_check("TIGHT 下包围方位不分配（整队单轴）",
		not is_finite(a[0].surround_bearing_rad) and not is_finite(a[1].surround_bearing_rad), "全 INF")
	_cleanup(c)


# ── C. planner 包围门点几何 ──
func _test_planner_surround_gate() -> void:
	print("── C. planner 门点：远距偏置到扇区 / 近距收敛 / 面攻击不叠加 ──")
	var s := Situation.new()
	s.has_target = true
	s.dist_m = 3000.0
	s.tgt_pos = Vector2(0, -1000)
	s.surround_bearing = deg_to_rad(90.0)   # 正东进入
	var p := TacticalPlan.new()
	p.intent = TacticalPlan.Intent.TAIL_CHASE
	p.pursuit_pos = s.tgt_pos
	var out: TacticalPlan = TacticalPlanner._apply_surround_axis(s, p)
	var expect := s.tgt_pos + Vector2(1.0, 0.0) * (TacticalPlanner.SURROUND_GATE_M * CombatUnit.PIXELS_PER_METER)
	_check("远距 → pursuit 改到自己扇区门点（东侧 1.3km）",
		out.pursuit_pos.distance_to(expect) < 1.0,
		"pursuit=(%.0f, %.0f)" % [out.pursuit_pos.x, out.pursuit_pos.y])
	# 近距收敛：不偏置
	var s2 := Situation.new()
	s2.has_target = true
	s2.dist_m = 1000.0
	s2.tgt_pos = Vector2(0, -1000)
	s2.surround_bearing = deg_to_rad(90.0)
	var p2 := TacticalPlan.new()
	p2.intent = TacticalPlan.Intent.TAIL_CHASE
	p2.pursuit_pos = s2.tgt_pos
	var out2: TacticalPlan = TacticalPlanner._apply_surround_axis(s2, p2)
	_check("近距（<1.5km）→ 解除偏置收敛攻击", out2.pursuit_pos == s2.tgt_pos, "pursuit 未改")
	# 面攻击 pass 不叠加包围门（有自己的几何承诺）
	var p3 := TacticalPlan.new()
	p3.intent = TacticalPlan.Intent.GROUND_STRAFE
	p3.pursuit_pos = s.tgt_pos
	var out3: TacticalPlan = TacticalPlanner._apply_surround_axis(s, p3)
	_check("GROUND_STRAFE 不叠加包围门", out3.pursuit_pos == s.tgt_pos, "pursuit 未改")


# ── D. SPREAD 分火全流程 ──
func _test_spread_flow() -> void:
	print("── D. SPREAD 分火：池内各自接敌 / 让路 / 死亡重挑 / 点名保护 / 池空结束 ──")
	var a: Array = [_make_ac(Vector2.ZERO), _make_ac(Vector2(150, 0)), _make_ac(Vector2(-150, 0))]
	var anchor := _make_enemy(Vector2(0, -1500))
	var e2 := _make_enemy(Vector2(300, -1600))
	var e3 := _make_enemy(Vector2(-300, -1400))
	var e4 := _make_enemy(Vector2(200, -1200))
	var far := _make_enemy(Vector2(6000, -1500))   # 池外（> 2000px 锚点半径）
	CombatUnit.all_units.clear()
	for u in [anchor, e2, e3, e4, far]:
		CombatUnit.all_units.append(u)

	var c := _make_controller(a)
	c.fire_allocation = SquadCommandController.FireAllocation.SPREAD
	c.command_attack_all(anchor, Situation.POSTURE_STANDOFF)

	var in_pool := true
	var postures_ok := true
	var seen := {}
	for ac in a:
		var t: CombatUnit = ac.commanded_target
		if t == null or t == far:
			in_pool = false
		else:
			seen[t] = true
		if ac.attack_posture != Situation.POSTURE_STANDOFF:
			postures_ok = false
	_check("各机都在池内选到目标（池外远敌绝不选）", in_pool, "3 机均有池内目标")
	_check("让路生效：3 机目标互不相同（池 4 选 3）", seen.size() == 3, "distinct=%d" % seen.size())
	_check("姿态随分火命令写入（STANDOFF）", postures_ok, "3 机 posture=1")

	# 死亡重挑 + 粘性
	var a0_tgt: CombatUnit = a[0].commanded_target
	var a1_tgt: CombatUnit = a[1].commanded_target
	a0_tgt.is_destroyed = true
	c.tick(0.5)
	var a0_new: CombatUnit = a[0].commanded_target
	_check("目标阵亡 → 池内重挑存活目标", a0_new != null and a0_new != a0_tgt and not a0_new.is_destroyed,
		"重挑成功")
	_check("粘性：其余成员目标不动（防乒乓）", a[1].commanded_target == a1_tgt, "a1 目标未变")

	# 单点点名保护：点名后退出分火管理，tick 不得夺走
	c.command_attack(e4)   # stub 下 selected=全体：全体点名 e4 → 全体退出分火管理
	c.tick(0.5)
	var named_kept := true
	for ac in a:
		if ac.commanded_target != e4:
			named_kept = false
	_check("单点点名后分火不再夺走目标（铁律保护）", named_kept, "全体保持点名目标")

	# 池清空 → 命令结束
	for u in [anchor, e2, e3, e4]:
		u.is_destroyed = true
	c.tick(0.5)
	c.tick(0.5)
	_check("池清空 → 分火命令结束", not c._spread_active, "_spread_active=false")
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
	c._end_spread()


static func _sep_deg(a: float, b: float) -> float:
	return absf(rad_to_deg(wrapf(a - b, -PI, PI)))


func _check(name: String, ok: bool, note: String) -> void:
	if ok:
		_pass += 1
		print("  ✓ %s — %s" % [name, note])
	else:
		_fail += 1
		print("  ✗ %s — %s" % [name, note])
