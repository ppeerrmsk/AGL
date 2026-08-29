extends RefCounted

## 无头僚机护卫规避测试（2026-06-16，spec wingman-escort-evasion）
## 验证护卫 flare 的纯判定/裁决逻辑（确定性、无需场景树）：
##   1. escort_jam_chance —— 近度概率公式
##   2. flare_ready —— flare 就绪门
##   3. _escort_missile_qualifies —— 合格目标导弹判定
##   4. _is_best_escort_for —— 全队裁决「一次只有一架」+ CD/范围兜底 + 平局决断
## 运行：godot --headless --path . -- --bench=escort
##
## 几何约定：1 像素 = 2 米（PPM=0.5）。长机在原点 heading=0（机头朝北 -y，前向=(0,-1)）。
## 导弹放在长机 +y（机尾后方）做尾追，heading=0 → 也朝 -y 追上来。

const PPM := 0.5
const FLARE_TRES := "res://resources/default_flare.tres"

var _pass := 0
var _fail := 0
var _shared_mm: Node2D = null   ## 共享 dummy missile_manager（Node2D 类型，flare_ready 只查非空）


func run() -> void:
	print("\n════════ 僚机护卫规避测试（wingman-escort-evasion） ════════")
	_shared_mm = Node2D.new()

	_test_jam_chance()
	_test_flare_ready()
	_test_missile_qualifies()
	_test_best_escort()
	_test_integration()
	_test_jam_rate()

	_shared_mm.free()
	print("──────── 结果：%d 通过 / %d 失败 ────────" % [_pass, _fail])
	print("══════════════════════════════════════════════════\n")


# ── 1. 近度 jam 概率公式 ──
func _test_jam_chance() -> void:
	print("── escort_jam_chance：贴脸 %.2f → 800m 趋 0 线性衰减 ──" % AircraftFlares.ESCORT_BASE_JAM)
	_approx("贴脸 d=0",      AircraftFlares.escort_jam_chance(0.0),   0.70, "= ESCORT_BASE_JAM")
	_approx("半程 d=400m",   AircraftFlares.escort_jam_chance(400.0), 0.35, "= 0.70×0.5")
	_approx("边缘 d=800m",   AircraftFlares.escort_jam_chance(800.0), 0.00, "范围边缘归零")
	_approx("超界 d=1000m",  AircraftFlares.escort_jam_chance(1000.0),0.00, "clamp 不为负")


# ── 2. flare 就绪门 ──
func _test_flare_ready() -> void:
	print("── flare_ready：玩家方 + 有 flare + 弹量/CD/隐身 ──")
	var w := _make_wingman(Vector2(100, 0))
	_check("就绪僚机", AircraftFlares.flare_ready(w), true, "team0+有弹+CD0")

	var w_enemy := _make_wingman(Vector2(100, 0)); w_enemy.team = 1
	_check("敌方机", AircraftFlares.flare_ready(w_enemy), false, "team≠0 不护卫")
	w_enemy.free()

	var w_noflare := _make_wingman(Vector2(100, 0)); w_noflare.flares_remaining = 0
	_check("无弹", AircraftFlares.flare_ready(w_noflare), false, "flares_remaining=0")
	w_noflare.free()

	var w_cd := _make_wingman(Vector2(100, 0)); w_cd._flare_cooldown = 3.0
	_check("CD 中", AircraftFlares.flare_ready(w_cd), false, "_flare_cooldown>0")
	w_cd.free()

	w.free()


# ── 3. 合格目标导弹判定 ──
func _test_missile_qualifies() -> void:
	print("── _escort_missile_qualifies：追长机 + 即将命中 + 未试过 ──")
	var leader := _make_leader()
	var w := _make_wingman(Vector2(100, 0))

	# 即将命中长机的快弹（尾追、闭合大、TTI 小）
	var m_imminent := _make_missile(Vector2(0, 200), 0.0, 1100.0, leader)
	_check("追长机·即将命中", AircraftFlares._escort_missile_qualifies(w, leader, m_imminent), true,
			"target=leader + TTI≤1.5s")

	# 同一枚但本机已试过 → 跳过
	w._escort_flare_tried[m_imminent.get_instance_id()] = true
	_check("已试过同弹", AircraftFlares._escort_missile_qualifies(w, leader, m_imminent), false,
			"_escort_flare_tried 单弹单次")
	w._escort_flare_tried.clear()

	# 追别人（target≠leader）→ 不护卫
	var other := _make_leader()
	var m_other := _make_missile(Vector2(0, 200), 0.0, 1100.0, other)
	_check("不追长机", AircraftFlares._escort_missile_qualifies(w, leader, m_other), false,
			"target≠leader")

	# 追长机但慢/远（追不上，不即将命中）→ 不护卫
	var m_slow := _make_missile(Vector2(0, 400), 0.0, 280.0, leader)  # 250<300 拉不近
	_check("慢弹追不上", AircraftFlares._escort_missile_qualifies(w, leader, m_slow), false,
			"闭合不足 → player_flare_should_trigger=false")

	# 已经失导 / 加力已接管 → 不替长机浪费护卫焰；资源仍保持就绪，避免僚机误入运动学规避
	m_imminent.has_guidance = false
	_check("失导不护卫", AircraftFlares._escort_missile_qualifies(w, leader, m_imminent), false,
			"结构威胁资格已失效")
	m_imminent.has_guidance = true
	leader.set_afterburner_mode_active(true)
	_check("长机加力中不护卫", AircraftFlares._escort_missile_qualifies(w, leader, m_imminent), false,
			"加力窗口接管防导弹")
	_check("加力中资源仍就绪", AircraftFlares.flare_ready(w), true,
			"不把暂缓投放误报成无 flare 兜底")
	leader.set_afterburner_mode_active(false)

	m_imminent.free(); m_other.free(); m_slow.free()
	other.free(); w.free(); leader.free()


# ── 4. 全队裁决「一次只有一架」──
func _test_best_escort() -> void:
	print("── _is_best_escort_for：同一枚导弹只有「离长机最近的就绪僚机」出手 ──")
	var leader := _make_leader()
	var m := _make_missile(Vector2(0, 200), 0.0, 1100.0, leader)  # 即将命中长机

	# 两架僚机：w_near 离长机 100px，w_far 离长机 300px，都在 800m(1600px) 内、都就绪
	var w_near := _make_wingman(Vector2(100, 0))
	var w_far := _make_wingman(Vector2(300, 0))
	var squad := _make_squad(leader, [w_near, w_far])

	_check("最近僚机出手", AircraftFlares._is_best_escort_for(w_near, leader, m), true, "100<300 → 最佳")
	_check("较远僚机让位", AircraftFlares._is_best_escort_for(w_far, leader, m), false, "有更近就绪者")

	# 最近者进 CD → 次近接手（顺序兜底）
	w_near._flare_cooldown = 3.0
	_check("最近进CD·次近接手", AircraftFlares._is_best_escort_for(w_far, leader, m), true,
			"最近者不就绪 → 次近成最佳")
	w_near._flare_cooldown = 0.0

	# 更近者超出 800m → 不算候选 → 远者成最佳
	w_near.global_position = Vector2(2000, 0)  # 4000m > 800m
	_check("更近者超界·远者出手", AircraftFlares._is_best_escort_for(w_far, leader, m), true,
			"超 800m 不算护卫候选")
	w_near.global_position = Vector2(100, 0)

	# 平局：两架等距 → 恰好一架通过（instance_id 决断）
	w_near.global_position = Vector2(100, 0)
	w_far.global_position = Vector2(-100, 0)  # 同为 100px
	var a := AircraftFlares._is_best_escort_for(w_near, leader, m)
	var b := AircraftFlares._is_best_escort_for(w_far, leader, m)
	_check("平局恰好一架", a != b, true, "等距用 instance_id 决断，不会 0 架也不会 2 架")

	squad = null
	if w_near._ai_ref: w_near._ai_ref.free()
	if w_far._ai_ref: w_far._ai_ref.free()
	m.free(); w_near.free(); w_far.free(); leader.free()


# ── 5. 端到端：真实 missile_manager + Missile 跑完整 try_cover_flare 链路 ──
func _test_integration() -> void:
	print("── try_cover_flare 端到端（真实 missile_manager 扫描 + 裁决 + 投焰）──")
	var leader := _make_leader()
	# 真实 Missile 挂进共享 missile_manager（追长机、即将命中）
	var m := _make_missile(Vector2(0, 200), 0.0, 1100.0, leader)
	_shared_mm.add_child(m)

	var w_near := _make_wingman(Vector2(100, 0))
	var w_far := _make_wingman(Vector2(300, 0))
	var squad := _make_squad(leader, [w_near, w_far])

	var far_ammo0: int = w_far.flares_remaining
	var near_ammo0: int = w_near.flares_remaining
	leader.set_afterburner_mode_active(true)
	var ab_fired := AircraftFlares.try_cover_flare(w_near, leader)
	_check("长机加力中不投护卫焰", ab_fired, false, "加力窗口独占导弹防御")
	_check("加力中近机弹量不变", w_near.flares_remaining == near_ammo0, true, "未消耗 flare")
	leader.set_afterburner_mode_active(false)

	# 先调较远的：裁决应让它给最近且就绪的 w_near 让位 → 不投、弹量不变
	var far_fired := AircraftFlares.try_cover_flare(w_far, leader)
	_check("远机扫描后让位", far_fired, false, "w_near 更近且就绪 → 不投焰")
	_check("远机弹量不变", w_far.flares_remaining == far_ammo0, true, "未消耗 flare")

	# 再调最近的：应真正投焰 → 返回 true、消耗弹、进 CD、记录该弹已试
	var near_fired := AircraftFlares.try_cover_flare(w_near, leader)
	_check("最近机投护卫焰", near_fired, true, "扫到合格弹 + 是最佳护卫者")
	_check("最近机消耗 flare", w_near.flares_remaining < near_ammo0, true, "弹量下降")
	_check("最近机进 CD", w_near._flare_cooldown > 0.0, true, "投焰即冷却")
	_check("记录单弹单次", w_near._escort_flare_tried.has(m.get_instance_id()), true, "_escort_flare_tried 标记")

	if w_near._ai_ref: w_near._ai_ref.free()
	if w_far._ai_ref: w_far._ai_ref.free()
	squad = null
	w_near.free(); w_far.free(); leader.free()
	_shared_mm.remove_child(m); m.free()


# ── 6. jam 应用率：贴脸(d=0)护卫焰对大量导弹的实际干扰率应 ≈ ESCORT_BASE_JAM ──
func _test_jam_rate() -> void:
	print("── release_cover jam 应用率（贴脸 d=0 期望 ≈ %.2f）──" % AircraftFlares.ESCORT_BASE_JAM)
	var leader := _make_leader()
	var w := _make_wingman(Vector2.ZERO)   # 贴脸长机 → jam_chance = ESCORT_BASE_JAM
	var n := 3000
	var jammed := 0
	for i in range(n):
		var m := _make_missile(Vector2(0, 200), 0.0, 1100.0, leader)
		w.flares_remaining = 4        # 每次补满，避免 CD/装填打断
		w._flare_cooldown = 0.0
		AircraftFlares.release_cover(w, leader, m, 0.0)
		if m.is_flare_jammed:
			jammed += 1
		m.free()
	var rate := float(jammed) / float(n)
	var ok := absf(rate - AircraftFlares.ESCORT_BASE_JAM) < 0.05
	if ok: _pass += 1
	else: _fail += 1
	print("  %s jam 率 %d/%d=%.3f（容差 ±0.05）— 贴脸应接近 %.2f" % [
		"✓" if ok else "✗", jammed, n, rate, AircraftFlares.ESCORT_BASE_JAM])
	w.free(); leader.free()


# ══════════════ 构造辅助 ══════════════

func _make_leader() -> Aircraft:
	var ac = load("res://scripts/aircraft.gd").new()
	ac.global_position = Vector2.ZERO
	ac.heading = 0.0
	ac.speed = 300.0
	ac.team = 0
	return ac


func _make_wingman(pos: Vector2) -> Aircraft:
	var ac = load("res://scripts/aircraft.gd").new()
	ac.global_position = pos
	ac.heading = 0.0
	ac.speed = 300.0
	ac.team = 0
	var p = AircraftParams.new()
	p.flare = load(FLARE_TRES)
	ac.params = p
	ac.flares_remaining = 4
	ac._flare_cooldown = 0.0
	ac.missile_manager = _shared_mm
	return ac


func _make_missile(pos: Vector2, hdg: float, spd: float, target) -> Missile:
	var m := Missile.new()
	m.global_position = pos
	m.heading = hdg
	m.speed = spd
	m.team = CombatUnit.TEAM_HOSTILE
	m.is_active = true
	m.has_guidance = true
	m.is_flare_jammed = false
	m.target = target
	return m


## 给每架僚机挂一个 AIController(.squad=squad) 并设 _ai_ref，供 _is_best_escort_for 遍历队友。
func _make_squad(leader: Aircraft, wingmen: Array) -> Squad:
	var squad := Squad.new()
	squad.leader = leader
	squad.members = [leader]
	for w in wingmen:
		squad.members.append(w)
	for w in wingmen:
		var ai = load("res://scripts/ai_controller.gd").new()
		ai.aircraft = w
		ai.squad = squad
		w._ai_ref = ai
	return squad


# ══════════════ 断言 ══════════════

func _check(name: String, got: bool, expect: bool, note: String) -> void:
	var ok := got == expect
	if ok: _pass += 1
	else: _fail += 1
	print("  %s %-20s 期望=%s 实际=%s — %s" % [
		"✓" if ok else "✗", name, str(expect), str(got), note])


func _approx(name: String, got: float, expect: float, note: String) -> void:
	var ok := absf(got - expect) < 0.001
	if ok: _pass += 1
	else: _fail += 1
	print("  %s %-20s 期望=%.3f 实际=%.3f — %s" % [
		"✓" if ok else "✗", name, expect, got, note])
