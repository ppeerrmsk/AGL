extends RefCounted

## 无头行为验收：TIGHT 整队齐射（spec: docs/specs/systems/formation-discipline.md §3.1）
##
## - TIGHT+集火：只有长机接命令目标，僚机留在编队（整队进入由编队跟随涌现）
## - 齐射触发器 = 长机开火：开窗 volley_window_s，僚机被临时授予 combat_target
##   （volley_fire_active 豁免编队防御清除）在槽位里释放
## - 窗口到时回收 = 禁补射；长机停火 ≥ rearm_quiet 才允许下一轮开窗（防连环开窗）
## - ASSAULT 豁免（缠斗不成阵，走普通集火广播）；目标阵亡齐射结束
##
## 运行：godot --headless --path . -- --bench=tight_volley（或 --bench=all）

var _pass := 0
var _fail := 0
var _root: Node2D = null


class StubMode extends Node:
	var selected_aircraft: Array[Aircraft] = []
	var player_aircraft: Aircraft = null


func run() -> void:
	print("\n════════ TIGHT 整队齐射验收（formation-discipline） ════════")
	_root = Node2D.new()
	_test_volley_cycle()
	_test_assault_exempt()
	_root.free()
	_root = null
	print("──────── 结果：%d 通过 / %d 失败 ────────" % [_pass, _fail])
	print("══════════════════════════════════════════════════\n")


# ── A. 齐射全周期 ──
func _test_volley_cycle() -> void:
	print("── A. TIGHT 集火：长机独持目标 → 开火开窗 → 到时回收 → 安静期再武装 ──")
	var leader = _make_ac(Vector2.ZERO)
	var w1 = _make_ac(Vector2(120, 0))
	var w2 = _make_ac(Vector2(-120, 0))
	var a: Array = [leader, w1, w2]
	var tgt := _make_enemy(Vector2(0, -3000))
	var c := _make_controller(a)
	c.formation_tight = true
	c.fire_allocation = SquadCommandController.FireAllocation.FOCUS
	c.command_attack_all(tgt, Situation.POSTURE_STANDOFF)

	_check("长机独持命令目标 + 姿态", leader.commanded_target == tgt \
			and leader.attack_posture == Situation.POSTURE_STANDOFF, "leader 铁律")
	_check("僚机不接目标（留在编队整队进入）",
		w1.commanded_target == null and w1.combat_target == null \
			and w2.commanded_target == null, "僚机编队跟随")

	# 长机未开火 → 不开窗
	c.tick(0.5)
	_check("长机未开火 → 无齐射窗口", not w1.volley_fire_active, "hold")

	# 长机开火 → 开窗：僚机获临时开火权
	leader.is_firing = true
	c.tick(0.5)
	_check("长机开火 → 齐射窗口开启（僚机获临时目标+开火权）",
		w1.volley_fire_active and w1.combat_target == tgt \
			and w2.volley_fire_active and w2.combat_target == tgt, "2 僚机齐射")

	# 窗口到时 → 回收（禁补射）
	c._volley_until_ms = Time.get_ticks_msec() - 1
	c.tick(0.5)
	_check("窗口到时 → 回收开火权 + 清临时目标（禁补射）",
		not w1.volley_fire_active and w1.combat_target == null, "僚机回编队武器静默")

	# 长机连续开火但刚齐射完 → 安静期不足不重开（防连环开窗）
	c.tick(0.5)
	_check("安静期不足 → 不连环开窗", not w1.volley_fire_active, "quiet<2s")

	# 长机停火 2.5s 后再开火 → 第二轮齐射
	leader.is_firing = false
	for i in 5:
		c.tick(0.5)
	leader.is_firing = true
	c.tick(0.5)
	_check("停火 ≥2s 后再开火 → 第二轮齐射窗口", w1.volley_fire_active and w1.combat_target == tgt,
		"pass 节奏成立")

	# 目标阵亡 → 齐射结束 + 回收
	tgt.is_destroyed = true
	c.tick(0.5)
	_check("目标阵亡 → 齐射结束、僚机权回收", not w1.volley_fire_active and c._tight_target == null,
		"tight 清理")
	c._end_tight()
	c._end_spread()


# ── B. ASSAULT 豁免 ──
func _test_assault_exempt() -> void:
	print("── B. TIGHT + 突击：豁免齐射（缠斗不成阵）→ 普通集火广播 ──")
	var a: Array = [_make_ac(Vector2.ZERO), _make_ac(Vector2(120, 0))]
	var tgt := _make_enemy(Vector2(0, -2000))
	var c := _make_controller(a)
	c.formation_tight = true
	c.command_attack_all(tgt, Situation.POSTURE_ASSAULT)
	_check("突击下全员照常接命令目标（FREE 语义）",
		a[0].commanded_target == tgt and a[1].commanded_target == tgt, "普通广播集火")
	_check("未进入齐射状态", c._tight_target == null, "tight 未激活")
	c._end_tight()


# ── 工具 ──

func _make_ac(pos: Vector2):
	var ac = load("res://scripts/aircraft.gd").new()
	var p := AircraftParams.new()
	p.max_speed = 2100.0
	p.cruise_speed = 900.0
	ac.params = p
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


func _check(name: String, ok: bool, note: String) -> void:
	if ok:
		_pass += 1
		print("  ✓ %s — %s" % [name, note])
	else:
		_fail += 1
		print("  ✗ %s — %s" % [name, note])
