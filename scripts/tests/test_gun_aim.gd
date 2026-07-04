extends RefCounted

## 机炮瞄准回归测试（2026-07-04 修"机炮侧射"，log 230431 [230.9] Orbit aim_vs_nose=-74°）
## 契约：
##   1. 机炮永远瞄 combat_target 的提前点，绝不瞄战术追踪点（crank/侧向位偏 90° 也不受影响）
##   2. 固定机炮物理锥门：提前点偏机头超过 gun.fire_cone_half_angle → 不开火
##   3. 无 combat_target → 沿机头（且 plan 不允许时不开火）
## 运行：godot --headless --path . -- --bench=gun_aim（或 --bench=all）

var _pass := 0
var _fail := 0


func run() -> void:
	print("\n════════ 机炮瞄准（瞄目标提前点 + 机头锥门） ════════")

	# ── 1. 追踪点偏 90°，机炮仍瞄正前方的目标 ──
	var ac := _make_shooter()
	var tgt := _make_target(Vector2(0, -800))  # 正前方（heading=0 朝 -y）
	ac.combat_target = tgt
	var plan := TacticalPlan.new()
	plan.allow_gun_fire = true
	plan.pursuit_pos = ac.global_position + Vector2(-2000, 0)  # 追踪点在左侧 90°（crank/侧向位）
	ac._apply_tactical_plan(plan)
	var aim_vs_nose := absf(rad_to_deg(Aircraft._angle_diff(ac._gun_lead_heading, ac.heading)))
	_check("瞄准≈机头（不瞄侧向追踪点）", aim_vs_nose < 10.0,
			"aim_vs_nose=%.1f°（修复前会是 90°）" % aim_vs_nose)
	_check("锥内正常开火", ac.is_firing, "")

	# ── 2. 目标在侧面 90° → 锥门禁射 ──
	var tgt_side := _make_target(ac.global_position + Vector2(-800, 0))
	ac.combat_target = tgt_side
	ac._apply_tactical_plan(plan)
	var aim_side := absf(rad_to_deg(Aircraft._angle_diff(ac._gun_lead_heading, ac.heading)))
	_check("瞄准指向侧面目标", aim_side > 60.0, "aim_vs_nose=%.1f°" % aim_side)
	_check("锥外禁射（固定机炮不能侧射）", not ac.is_firing,
			"物理锥门：偏机头 > fire_cone_half_angle 不开火")

	# ── 3. 无目标 → 沿机头 + 不开火 ──
	ac.combat_target = null
	ac._apply_tactical_plan(plan)
	_check("无目标沿机头", absf(Aircraft._angle_diff(ac._gun_lead_heading, ac.heading)) < 0.01, "")
	_check("无目标不开火", not ac.is_firing, "aim_ok=false")

	tgt.free(); tgt_side.free(); ac.free()
	print("──────── 结果：%d 通过 / %d 失败 ────────" % [_pass, _fail])
	print("══════════════════════════════════════════════════\n")


func _make_shooter() -> Aircraft:
	var ac: Aircraft = load("res://scripts/aircraft.gd").new()
	ac.team = 0
	ac.heading = 0.0
	ac.speed = 250.0
	ac.global_position = Vector2.ZERO
	var p = AircraftParams.new()
	var g = GunParams.new()
	g.muzzle_velocity = 1000.0
	g.fire_cone_half_angle = 15.0
	g.max_range = 1000.0
	p.gun = g
	p.cruise_speed = 900.0
	p.stall_speed_base = 220.0
	ac.params = p
	ac.ammo = 100
	return ac


func _make_target(pos: Vector2) -> Aircraft:
	var t: Aircraft = load("res://scripts/aircraft.gd").new()
	t.team = 1
	t.global_position = pos
	t.heading = 0.0
	t.speed = 0.0  # 静止目标：提前点 = 目标本身，断言几何干净
	return t


func _check(name: String, got: bool, note: String) -> void:
	if got: _pass += 1
	else: _fail += 1
	print("  %s %-28s — %s" % ["✓" if got else "✗", name, note])
