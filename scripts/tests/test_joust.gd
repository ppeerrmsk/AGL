extends RefCounted

## 无头验收：攻击跑行为原语（spec: docs/specs/systems/joust-attack-run.md §5）
##
## A. MQ-112 死锁修复 —— 电磁炮包络 joust vs 匀速直飞目标：
##    对准窗 ≥ 充能链 5.1s（锁 2s + 充能 2.5s + 锁定相位 0.6s）+ 完整循环 +
##    真实 RailgunEquipment 步进实弹 ≥1 发（对照 log 183044 全场 0 充能）
## B. 骑士节奏 —— 机炮包络 joust vs 横穿目标：60s ≥2 个完整循环 + 每轮机炮窗
## C. 闭合放弃 —— 目标 2× 速度逃逸：give-up 判定转 BREAK，不死追
##
## 运行：godot --headless --path . -- --bench=joust（或 --bench=all）
## 步进模型：AI tick 每 3 帧（÷3 分频 ×3 delta 补偿，同真实 simple_ai），物理 60Hz
## （_step 序列与 test_turn_physics 一致）。雷达锁用锥角×lock_time 积分模拟
## （±radar_half_angle 内累积 / 出锥 2× 衰减），is_locked 喂给真实电磁炮状态机。

const DT := 1.0 / 60.0
const AI_PERIOD := 3

var _pass := 0
var _fail := 0
var _root: Node2D = null


func run() -> void:
	print("\n════════ 攻击跑 joust 验收（RUN_IN/BREAK 循环 + 武器窗） ════════")
	_root = Node2D.new()
	_test_railgun_deadlock_fixed()
	_test_gun_lancer_rhythm()
	_test_giveup()
	_root.free()
	_root = null
	print("──────── 结果：%d 通过 / %d 失败 ────────" % [_pass, _fail])
	print("══════════════════════════════════════════════════\n")


# ── A. MQ-112 死锁修复 ──
func _test_railgun_deadlock_fixed() -> void:
	print("── A. 电磁炮包络：对准窗 ≥ 充能链 + 实弹 ──")
	var p := _uav_railgun_params()
	var ac = _make_ac(p, Vector2.ZERO, 0.0)
	var tp := AircraftParams.new()
	tp.cruise_speed = 900.0
	tp.max_speed = 1800.0
	var tgt = _make_ac(tp, Vector2(0, -3500), PI / 2.0)  # 目标在前方 3500px，向东横飞
	tgt.speed = 250.0
	ac.combat_target = tgt
	var ai = _make_ai(ac, tgt)
	ai.joust_enabled = true

	var rg: RailgunEquipment = p.get_equipment_of_kind("railgun")
	var lock_t := 0.0
	var fires := 0
	var prev_beam := 0.0
	var window := 0.0
	var max_window := 0.0
	var phase_seq: Array = [ai._joust_phase]
	var inner := 750.0   # min_engage 1500m × 0.5
	var outer := 2500.0  # 雷达 5000m × 0.5

	for i in range(90 * 60):
		if i % AI_PERIOD == 0:
			JoustController.update(ai, DT * AI_PERIOD)
		if phase_seq[-1] != ai._joust_phase:
			phase_seq.append(ai._joust_phase)
		_step(ac)
		_move_straight(tgt)

		var dist: float = ac.global_position.distance_to(tgt.global_position)
		var nose_off: float = _nose_off_deg(ac, tgt)
		# 雷达锁模拟：±radar_half_angle 且 ≤ 雷达距离 → 累积；否则 2× 衰减
		if nose_off <= p.radar_half_angle and dist <= outer:
			lock_t = minf(lock_t + DT, p.lock_time + 1.0)
		else:
			lock_t = maxf(lock_t - DT * 2.0, 0.0)
		tgt.is_locked = lock_t >= p.lock_time
		# 锁定稳定窗：雷达锥 ±25° 且在火力包络内。开火锥 ±8° 只在充能启动一瞬需要
		# （uav_railgun charge_persistent=true，充能期不查锥），实弹计数是最终裁决
		if nose_off <= p.radar_half_angle and dist >= inner and dist <= outer:
			window += DT
			max_window = maxf(max_window, window)
		else:
			window = 0.0
		# 真实电磁炮状态机步进
		rg.update(ac, DT)
		var s: Dictionary = ac.equipment_state.get("railgun", {})
		var beam: float = s.get("beam_fade", 0.0)
		if beam > prev_beam:
			fires += 1
		prev_beam = beam
		if i % 600 == 0:
			print("    [%5.1fs] dist=%4.0f nose=%5.1f° lock_t=%.1f locked=%s chg=%s prog=%.2f await=%s cd=%.1f turn=%4.1f°/s ph=%d" % [
				float(i) * DT, dist, nose_off, lock_t, str(tgt.is_locked),
				str(s.get("charging", false)), s.get("charge_progress", 0.0),
				str(s.get("awaiting_fire", false)), s.get("cooldown", 0.0),
				rad_to_deg(ac._turn_rate_filt), ai._joust_phase])

	var cycles := _count_cycles(phase_seq)
	_check("锁定稳定窗 ≥ 充能链 5.1s", max_window >= 5.1,
		"最长稳定窗 %.1fs（锁2s+充能2.5s+相位0.6s）" % max_window)
	_check("完整 RUN_IN→BREAK→RUN_IN 循环 ≥1", cycles >= 1, "循环数=%d" % cycles)
	_check("电磁炮实弹 ≥1（log 183044 死锁对照=0）", fires >= 1, "90s 内开火 %d 发" % fires)
	_free_pair(ac, tgt)


# ── B. 骑士节奏（机炮 lancer）──
func _test_gun_lancer_rhythm() -> void:
	print("── B. 机炮包络：冲锋-脱离-折返节奏 ──")
	var p := AircraftParams.new()
	p.max_speed = 2100.0
	p.cruise_speed = 1000.0
	var gun := GunParams.new()
	gun.max_range = 1200.0
	p.gun = gun
	var ac = _make_ac(p, Vector2.ZERO, 0.0)
	var tp := AircraftParams.new()
	tp.cruise_speed = 900.0
	tp.max_speed = 1800.0
	var tgt = _make_ac(tp, Vector2(0, -2500), PI / 2.0)
	tgt.speed = 250.0
	ac.combat_target = tgt
	var ai = _make_ai(ac, tgt)
	ai.joust_enabled = true
	ai.joust_run_speed_kmh = p.max_speed * 0.9
	ai.joust_giveup_closing_mps = 60.0

	var phase_seq: Array = [ai._joust_phase]
	var window := 0.0
	var pass_windows: Array = []   # 每次离开窗时记录本段窗长
	var gun_range_px: float = gun.max_range * CombatUnit.PIXELS_PER_METER

	for i in range(60 * 60):
		if i % AI_PERIOD == 0:
			JoustController.update(ai, DT * AI_PERIOD)
		if phase_seq[-1] != ai._joust_phase:
			phase_seq.append(ai._joust_phase)
		_step(ac)
		_move_straight(tgt)
		var dist: float = ac.global_position.distance_to(tgt.global_position)
		if _nose_off_deg(ac, tgt) <= 10.0 and dist <= gun_range_px:
			window += DT
		else:
			if window > 0.0:
				pass_windows.append(window)
			window = 0.0
	if window > 0.0:
		pass_windows.append(window)

	var cycles := _count_cycles(phase_seq)
	var best := 0.0
	for w in pass_windows:
		best = maxf(best, w)
	_check("完整循环 ≥2（60s）", cycles >= 2, "循环数=%d" % cycles)
	_check("单轮机炮窗 ≥0.6s", best >= 0.6,
		"最长机炮窗 %.2fs（共 %d 段）" % [best, pass_windows.size()])
	_free_pair(ac, tgt)


# ── C. 闭合放弃 ──
func _test_giveup() -> void:
	print("── C. 闭合放弃：追不上 2s 即转 BREAK ──")
	var p := AircraftParams.new()
	p.max_speed = 1400.0
	p.cruise_speed = 750.0
	var gun := GunParams.new()
	gun.max_range = 1200.0
	p.gun = gun
	var ac = _make_ac(p, Vector2.ZERO, 0.0)
	ac.speed = 200.0
	var tp := AircraftParams.new()
	tp.max_speed = 2800.0
	tp.cruise_speed = 1800.0
	var tgt = _make_ac(tp, Vector2(0, -1500), 0.0)  # 正前方，同向逃逸
	tgt.speed = 500.0                               # 2.5× 拉开
	ac.combat_target = tgt
	var ai = _make_ai(ac, tgt)
	ai.joust_enabled = true
	ai.joust_giveup_closing_mps = 60.0

	var gave_up_at := -1.0
	for i in range(20 * 60):
		if i % AI_PERIOD == 0:
			JoustController.update(ai, DT * AI_PERIOD)
		_step(ac)
		_move_straight(tgt)
		if gave_up_at < 0.0 and ai._joust_phase == JoustController.Phase.BREAK:
			gave_up_at = float(i) * DT
	_check("give-up 触发（追不上不死追）", gave_up_at >= 0.0, "t=%.1fs 转 BREAK" % gave_up_at)
	_check("give-up 及时（<8s）", gave_up_at >= 0.0 and gave_up_at < 8.0,
		"阈值持续 2s + 出包络判定" if gave_up_at >= 0.0 else "未触发")
	_free_pair(ac, tgt)


# ── 工具 ──

func _uav_railgun_params() -> AircraftParams:
	var p := AircraftParams.new()
	p.max_speed = 1400.0
	p.cruise_speed = 750.0
	p.radar_range = 5000.0
	p.radar_half_angle = 25.0
	p.lock_time = 2.0
	p.equipment = [load("res://resources/uav_railgun.tres").duplicate(true)]
	return p


func _make_ac(params: AircraftParams, pos: Vector2, hdg: float):
	var ac = load("res://scripts/aircraft.gd").new()
	ac.params = params
	ac.heading = hdg
	ac.bank_angle = 0.0
	ac.altitude = 5000.0
	ac.speed = params.cruise_speed / 3.6
	ac.target_speed_kmh = params.cruise_speed
	ac.g_load = 1.0
	ac.tactical_aggression = 1.0
	ac.position = pos
	_root.add_child(ac)
	return ac


func _make_ai(ac, tgt) -> AIController:
	var ai: AIController = load("res://scripts/ai_controller.gd").new()
	ai.aircraft = ac
	ai._current_target = tgt
	ac._ai_ref = ai
	ac.add_child(ai)
	return ai


func _step(ac) -> void:
	AircraftPhysics.update_target_heading(ac)
	AircraftPhysics.update_bank(ac, DT)
	AircraftPhysics.update_heading(ac, DT)
	AircraftPhysics.update_speed(ac, DT)
	AircraftPhysics.update_g_load(ac)
	AircraftPhysics.apply_movement(ac, DT)


func _move_straight(tgt) -> void:
	var v: Vector2 = Vector2(sin(tgt.heading), -cos(tgt.heading)) * float(tgt.speed) * CombatUnit.PIXELS_PER_METER
	tgt.position += v * DT


func _nose_off_deg(ac, tgt) -> float:
	var to_tgt: Vector2 = tgt.global_position - ac.global_position
	var brg := atan2(to_tgt.x, -to_tgt.y)
	var diff := wrapf(brg - ac.heading, -PI, PI)
	return absf(rad_to_deg(diff))


## 完整循环 = phase 序列里 RUN_IN(0)→BREAK(1)→RUN_IN(0) 的次数
func _count_cycles(seq: Array) -> int:
	var n := 0
	for i in range(seq.size() - 2):
		if seq[i] == JoustController.Phase.RUN_IN and seq[i + 1] == JoustController.Phase.BREAK \
				and seq[i + 2] == JoustController.Phase.RUN_IN:
			n += 1
	return n


func _free_pair(ac, tgt) -> void:
	_root.remove_child(ac)
	_root.remove_child(tgt)
	ac.free()
	tgt.free()


func _check(name: String, ok: bool, note: String) -> void:
	if ok:
		_pass += 1
		print("  ✓ %s — %s" % [name, note])
	else:
		_fail += 1
		print("  ✗ %s — %s" % [name, note])
