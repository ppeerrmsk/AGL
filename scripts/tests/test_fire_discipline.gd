extends RefCounted

## 无头行为验收：火力纪律（log 20260712_181952 溢出/直升机空转两病灶的回归门）
##
## A. 导弹超杀记账含自己：team_inbound_damage(exclude=null) 把自己的在飞弹算进账——
##    小目标不再"自己连发 2 枚"；被 flare 干扰(jammed)/丢制导的弹不计账（补射价值保留）
## B. 慢速空目标 joust 路由：直升机档（≤100m/s）空中目标路由攻击跑 pass；
##    快速机/面目标/无目标不受影响
##
## 运行：godot --headless --path . -- --bench=fire_discipline（或 --bench=all）

var _pass := 0
var _fail := 0
var _root: Node2D = null


func run() -> void:
	print("\n════════ 火力纪律验收（超杀记账 / 慢目标 pass 路由） ════════")
	_root = Node2D.new()
	_test_inbound_accounting()
	_test_slow_air_routing()
	_root.free()
	_root = null
	print("──────── 结果：%d 通过 / %d 失败 ────────" % [_pass, _fail])
	print("══════════════════════════════════════════════════\n")


# ── A. 在途伤害记账 ──
func _test_inbound_accounting() -> void:
	print("── A. 超杀记账：含自己在飞弹 / jammed 与丢制导不计 ──")
	var mm := MissileManager.new()
	_root.add_child(mm)
	var shooter := _make_unit(0)
	var mate := _make_unit(0)
	var tgt := _make_unit(1)
	tgt.hp = 70.0

	var m1 := _make_missile(shooter, tgt, 80.0)   # 自己的在飞弹
	mm.add_child(m1)
	var incl: float = mm.team_inbound_damage(tgt, 0, null)
	var excl: float = mm.team_inbound_damage(tgt, 0, shooter)
	_check("exclude=null 时自己的在飞弹计入记账", incl >= 80.0, "inbound=%.0f" % incl)
	_check("exclude=self 时不计（旧语义仍可用）", excl == 0.0, "inbound=%.0f" % excl)
	_check("单枚在飞已超杀 70hp 小目标（第二枚会被 TEAM_OVERKILL 挡）", incl >= tgt.hp,
		"%.0f >= %.0f" % [incl, tgt.hp])

	# jammed：被热诱弹干扰的弹不计账 → 补射价值保留
	m1.is_flare_jammed = true
	var after_jam: float = mm.team_inbound_damage(tgt, 0, null)
	_check("被 flare 干扰的弹不计账（允许补射）", after_jam == 0.0, "inbound=%.0f" % after_jam)

	# 丢制导：必定射空的弹不计账（防连封）
	m1.is_flare_jammed = false
	m1.has_guidance = false
	var after_lost: float = mm.team_inbound_damage(tgt, 0, null)
	_check("丢制导的弹不计账（防全队被射空弹连封）", after_lost == 0.0, "inbound=%.0f" % after_lost)

	# 队友的弹照常计入（跨机不通气的旧漏洞由 exclude=null 一并覆盖）
	m1.has_guidance = true
	var m2 := _make_missile(mate, tgt, 80.0)
	mm.add_child(m2)
	var both: float = mm.team_inbound_damage(tgt, 0, null)
	_check("自己 + 队友在飞弹合并记账", both >= 160.0, "inbound=%.0f" % both)

	mm.queue_free()
	shooter.queue_free()
	mate.queue_free()
	tgt.queue_free()


# ── B. 慢速空目标 joust 路由判定 ──
func _test_slow_air_routing() -> void:
	print("── B. 慢速空目标（直升机档）→ joust pass 路由 ──")
	var ai := AIController.new()   # 不入树，不触发 _ready；_slow_air_joust 只读 _current_target
	var heli = _make_ac(60.0)      # 直升机档 60 m/s
	var jet = _make_ac(300.0)      # 喷气机 300 m/s
	var ground := _make_unit(1)    # 面目标（非 Aircraft）
	ground.speed = 0.0

	ai._current_target = heli
	_check("直升机档（60m/s）→ 路由 joust", ai._slow_air_joust(), "≤100m/s")
	ai._current_target = jet
	_check("快速机（300m/s）→ 不路由", not ai._slow_air_joust(), "走正常 BFM")
	ai._current_target = ground
	_check("面目标 → 不路由（归 ground_strafe pass）", not ai._slow_air_joust(), "非 Aircraft")
	ai._current_target = null
	_check("无目标 → 不路由", not ai._slow_air_joust(), "null 安全")

	ai.free()
	heli.queue_free()
	jet.queue_free()
	ground.queue_free()


# ── 工具 ──

func _make_unit(team_id: int) -> CombatUnit:
	var u := CombatUnit.new()
	u.team = team_id
	_root.add_child(u)
	return u


func _make_ac(speed_ms: float):
	var ac = load("res://scripts/aircraft.gd").new()
	ac.params = AircraftParams.new()
	ac.speed = speed_ms
	ac.altitude = 2000.0
	_root.add_child(ac)
	return ac


func _make_missile(src: CombatUnit, tgt: CombatUnit, dmg: float) -> Missile:
	var m := Missile.new()
	var p := MissileParams.new()
	p.damage = dmg
	m.params = p
	m.source = src
	m.target = tgt
	m.is_active = true
	m.has_guidance = true
	m.is_flare_jammed = false
	return m


func _check(name: String, ok: bool, note: String) -> void:
	if ok:
		_pass += 1
		print("  ✓ %s — %s" % [name, note])
	else:
		_fail += 1
		print("  ✗ %s — %s" % [name, note])
