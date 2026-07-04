extends RefCounted

## 控制意图仲裁器单元测试（Phase 1 Step 1，2026-07-04）
## 验证 Aircraft.submit_intent / withdraw_intent / _resolve_intents 的核心契约：
##   1. 按字段仲裁（EVADE 只主张 pursuit，speed/AB 仍归 TACTIC —— 分权协作）
##   2. 优先级表生效（EVADE > TACTIC；BRAKE 速度/AB 满优先、pursuit=25 让位 EVADE）
##   3. sticky（不重新提交下次 resolve 仍生效 —— AI 分频写/60Hz 读的根治）
##   4. withdraw 对称（撤 EVADE 后 pursuit 回落 TACTIC）
##   5. 不主张不碰（无人主张的字段保留既有直写值 —— 与未迁移写入者共存）
##   6. AB 走 set_afterburner 守卫（SLOW 状态主张开 AB 被物理守卫挡下）
## 运行：godot --headless --path . -- --bench=intent（或 --bench=all）

const DT := 1.0 / 60.0

var _pass := 0
var _fail := 0


func run() -> void:
	print("\n════════ 控制意图仲裁器（Phase 1 Step 1） ════════")
	var ac := _make()

	# ── 1. TACTIC 三字段全主张 ──
	var t := ControlIntent.new()
	t.pursuit_pos = Vector2(100, 200)
	t.target_speed_kmh = 800.0
	t.afterburner = 1
	ac.submit_intent(ControlIntent.SOURCE_TACTIC, t)
	ac._resolve_intents(DT)
	_check("TACTIC 主张 pursuit", ac.target_position == Vector2(100, 200), "")
	_check("TACTIC 主张 speed", ac.target_speed_kmh == 800.0, "")
	_check("TACTIC 主张 AB", ac.is_afterburner, "set_afterburner 守卫通过后置 true")

	# ── 2. EVADE 只主张 pursuit：分权协作 ──
	var e := ControlIntent.new()
	e.pursuit_pos = Vector2(-500, 0)
	ac.submit_intent(ControlIntent.SOURCE_EVADE, e)
	ac._resolve_intents(DT)
	_check("EVADE 压过 TACTIC 的 pursuit", ac.target_position == Vector2(-500, 0), "30 > 20")
	_check("speed 仍归 TACTIC", ac.target_speed_kmh == 800.0, "EVADE 未主张 speed")

	# ── 3. sticky：都不重新提交，再 resolve 仍生效 ──
	ac.target_position = Vector2.ZERO  # 模拟外部直写
	ac._resolve_intents(DT)
	_check("sticky：EVADE 槽跨帧有效", ac.target_position == Vector2(-500, 0),
			"AI 分频写/60Hz 读——主张在两次 tick 之间保持")

	# ── 4. withdraw 对称 ──
	ac.withdraw_intent(ControlIntent.SOURCE_EVADE)
	ac._resolve_intents(DT)
	_check("撤 EVADE 后 pursuit 回落 TACTIC", ac.target_position == Vector2(100, 200), "")

	# ── 5. BRAKE 桥接：速度/AB 满优先，pursuit=25 让位 EVADE ──
	ac.hard_brake = true
	# AB 关闭主张同样走 set_afterburner 守卫（冷却期内连关也被挡——迁移前同语义，
	# 物理无害：update_speed 急刹时本就不吃 AB 推力）。清冷却后主张即生效。
	ac._ab_cooldown = 0.0
	ac._resolve_intents(DT)
	_check("BRAKE 压 speed", ac.target_speed_kmh == 0.0, "40 > 20")
	_check("BRAKE 压 AB=false", not ac.is_afterburner, "冷却清零后守卫放行")
	_check("BRAKE 清 pursuit（无 EVADE 时）", ac.target_position == Vector2.INF,
			"clear_pursuit：保持航向")
	ac.submit_intent(ControlIntent.SOURCE_EVADE, e)
	ac._resolve_intents(DT)
	_check("EVADE 几何压过 BRAKE 的清航点", ac.target_position == Vector2(-500, 0),
			"pursuit_pri 25 < 30——急刹+规避时蛇形几何仍生效（与旧帧序等价）")
	ac.hard_brake = false
	ac.withdraw_intent(ControlIntent.SOURCE_EVADE)
	ac._resolve_intents(DT)
	_check("松刹后 BRAKE 槽自动清除", ac.target_speed_kmh == 800.0, "speed 回落 TACTIC")

	# ── 6. 不主张不碰：与未迁移直写者共存 ──
	var t2 := ControlIntent.new()
	t2.pursuit_pos = Vector2.INF  # 不主张（CRUISE/EVADE intent 语义）
	t2.target_speed_kmh = 600.0
	t2.afterburner = 0
	ac.submit_intent(ControlIntent.SOURCE_TACTIC, t2)
	ac.target_position = Vector2(777, 777)  # 模拟未迁移写入者（BOSS/RTS/编队）直写
	ac._resolve_intents(DT)
	_check("无人主张的 pursuit 保留直写值", ac.target_position == Vector2(777, 777),
			"共存原则：resolve 不碰未主张字段")

	# ── 7. AB 主张过 set_afterburner 守卫（SLOW 禁开） ──
	var t3 := ControlIntent.new()
	t3.afterburner = 1
	ac.submit_intent(ControlIntent.SOURCE_TACTIC, t3)
	ac.status_slow_active = true
	ac.is_afterburner = false
	ac._resolve_intents(DT)
	_check("SLOW 状态 AB 主张被守卫挡下", not ac.is_afterburner,
			"意图仲裁不绕过物理守卫（set_afterburner 三重检查）")
	ac.status_slow_active = false

	ac.free()
	print("──────── 结果：%d 通过 / %d 失败 ────────" % [_pass, _fail])
	print("══════════════════════════════════════════════════\n")


func _make() -> Aircraft:
	var ac: Aircraft = load("res://scripts/aircraft.gd").new()
	var p = AircraftParams.new()
	p.cruise_speed = 900.0
	p.stall_speed_base = 220.0
	ac.params = p
	ac.speed = 250.0
	ac.fuel = 100.0
	ac.team = 0
	return ac


func _check(name: String, got: bool, note: String) -> void:
	if got: _pass += 1
	else: _fail += 1
	print("  %s %-28s — %s" % ["✓" if got else "✗", name, note])
