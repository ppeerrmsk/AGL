extends RefCounted

## 无头智能放焰测试（2026-06-14）
## 验证 AircraftFlares.player_flare_should_trigger：玩家方只对"会命中且即将到达"的导弹放焰，
## 对慢速/追不上的导弹不放（不浪费）。
## 运行：godot --headless --path . -- --bench=flare
##
## 几何约定：ac 在原点、heading=0（机头朝北 -y、前向=(0,-1)）。
## 1 像素 = 2 米（PIXELS_PER_METER=0.5）。导弹放在 +y（机尾后方）做尾追，heading=0 表示也朝 -y 追。

const PPM := 0.5

var _pass := 0
var _fail := 0


func run() -> void:
	print("\n════════ 智能放焰(TTI)测试 ════════")
	print("阈值：TTI≤%.1fs 放 / 距离≤%.0fm 兜底放 / 闭合<%.0fm·s⁻¹ 不放" % [
		AircraftFlares.FLARE_TTI_THRESHOLD, AircraftFlares.FLARE_MIN_DIST_M,
		AircraftFlares.FLARE_MIN_CLOSING_MS])

	# (ac_spd, m_dist_px, m_spd, m_hdg, 期望放焰?, 说明)
	# ac 始终 heading=0 speed=300m/s；导弹位置 (0, +dist_px) 在机尾后方
	_case("慢速追不上(浪费案例)", 300.0, 400.0, 250.0, 0.0, false,
			"导弹 250<本机 300，间距在拉大 → 不放")
	_case("快弹远距(3km)",        300.0, 1500.0, 1100.0, 0.0, false,
			"闭合 800，但 TTI=3.75s 还早 → 等")
	_case("快弹TTI1.2s",           300.0, 480.0, 1100.0, 0.0, false,
			"闭合 800，TTI=1.2s>1.0 → 继续等")
	_case("快弹TTI0.8s",           300.0, 320.0, 1100.0, 0.0, true,
			"闭合 800，TTI=0.8s≤1.0 → 放")
	_case("慢弹但逼近·贴脸200m",  300.0, 100.0, 350.0, 0.0, true,
			"闭合 50，TTI=4s 但距离=200m 触兜底 → 放")
	_case("慢弹逼近·仍在300m",    300.0, 150.0, 350.0, 0.0, false,
			"闭合 50，TTI=6s 且 300m>200m → 等")
	_case("慢弹逼近·仍远800m",    300.0, 400.0, 350.0, 0.0, false,
			"闭合 50，TTI=16s 且 800m>200m → 等（进 200m 才放）")
	_test_player_threat_eligibility()
	_test_player_auto_release_path()

	_test_enemy_break_chance()
	_test_enemy_break_actions()
	_test_enemy_release_path()
	_test_enemy_break_pending()
	_test_visual_side_launch()

	print("── 规避(加速散开)威胁门：只对逼近且即将到达的导弹散开 ──")
	print("阈值：TTI≤%.1fs 且 闭合≥%.0fm·s⁻¹ 才散开" % [
		MissileEvasion.EVADE_TTI_THRESHOLD, MissileEvasion.EVADE_MIN_CLOSING_MS])
	# ac heading=0 speed=250m/s（巡航）；导弹在机尾后方 +y 追击
	_evade_case("慢弹追不上",     250.0, 400.0, 280.0, false, "闭合 30<60 → 不散开(留阵型,flare 兜底)")
	_evade_case("快弹远(TTI5.9s)", 250.0, 2500.0, 1100.0, false, "闭合 850 但 TTI 5.9s 还早 → 不散开")
	_evade_case("快弹中距(TTI4s)", 250.0, 1700.0, 1100.0, false, "TTI 4.0s>3.5 → 再等等")
	_evade_case("快弹临近(TTI1.9s)",250.0, 800.0, 1100.0, true,  "闭合 850,TTI 1.9s≤3.5 → 散开")

	print("──────── 结果：%d 通过 / %d 失败 ────────" % [_pass, _fail])
	print("════════════════════════════════\n")


func _test_player_threat_eligibility() -> void:
	print("── 玩家阵营资格门：失导/错目标/友军/加力窗口不浪费热诱弹 ──")
	var ac = load("res://scripts/aircraft.gd").new()
	ac.global_position = Vector2.ZERO
	ac.heading = 0.0
	ac.speed = 300.0
	ac.team = CombatUnit.TEAM_PLAYER
	var m := Missile.new()
	m.global_position = Vector2(0.0, 200.0)
	m.heading = 0.0
	m.speed = 1100.0
	m.team = CombatUnit.TEAM_HOSTILE
	m.target = ac
	m.is_active = true
	m.has_guidance = true
	_record(AircraftFlares.player_flare_should_trigger(ac, m), "真实末段来袭会投焰")
	m.has_guidance = false
	_record(not AircraftFlares.player_flare_should_trigger(ac, m), "已经失导不投焰")
	m.has_guidance = true
	m.team = CombatUnit.TEAM_PLAYER
	_record(not AircraftFlares.player_flare_should_trigger(ac, m), "同阵营导弹不投焰")
	m.team = CombatUnit.TEAM_HOSTILE
	m.target = null
	_record(not AircraftFlares.player_flare_should_trigger(ac, m), "目标不匹配不投焰")
	m.target = ac
	ac.set_afterburner_mode_active(true)
	_record(not AircraftFlares.player_flare_should_trigger(ac, m), "加力窗口接管时不投焰")
	ac.set_afterburner_mode_active(false)
	_record(AircraftFlares.player_flare_should_trigger(ac, m), "退出加力后真实威胁恢复投焰")
	m.free()
	ac.free()


func _test_player_auto_release_path() -> void:
	print("── 玩家自动投放链路：加力中保留库存，退出后才释放 ──")
	var ac = load("res://scripts/aircraft.gd").new()
	ac.global_position = Vector2.ZERO
	ac.heading = 0.0
	ac.speed = 300.0
	ac.team = CombatUnit.TEAM_PLAYER
	ac.params = AircraftParams.new()
	ac.params.flare = FlareParams.new()
	ac.params.flare.max_flares = 2
	ac.params.flare.burst_count = 1
	ac.params.flare.fail_chance = 0.0
	ac.flares_remaining = 2
	var mm := Node2D.new()
	ac.missile_manager = mm
	var m := Missile.new()
	m.params = MissileParams.new()
	m.global_position = Vector2(0.0, 200.0)
	m.heading = 0.0
	m.speed = 1100.0
	m.team = CombatUnit.TEAM_HOSTILE
	m.target = ac
	m.is_active = true
	m.has_guidance = true
	mm.add_child(m)
	ac.set_afterburner_mode_active(true)
	AircraftFlares.update(ac, 0.0)
	_record(ac.flares_remaining == 2 and ac._flare_cooldown == 0.0,
		"加力中真实末段来袭也不消耗")
	ac.set_afterburner_mode_active(false)
	AircraftFlares.update(ac, 0.0)
	_record(ac.flares_remaining == 1 and ac._flare_cooldown > 0.0,
		"退出加力后同一威胁正常消耗并进 CD")
	ac.team = CombatUnit.TEAM_ALLY
	ac.flares_remaining = 2
	ac._flare_cooldown = 0.0
	m.is_flare_jammed = false
	AircraftFlares.update(ac, 0.0)
	_record(ac.flares_remaining == 1, "TEAM_ALLY 友军也走智能自动投放链")
	mm.remove_child(m)
	m.free()
	mm.free()
	ac.free()


func _test_enemy_break_chance() -> void:
	print("── 敌机 break 成功率随有效操控水平单调提升 ──")
	for row in [[0.0, 0.80], [0.3, 0.845], [0.6, 0.89], [0.9, 0.935], [1.0, 0.95]]:
		var got: float = AircraftFlares.enemy_flare_break_chance_for_skill(float(row[0]))
		var expect: float = float(row[1])
		_record(is_equal_approx(got, expect), "S=%.1f → %.0f%%（期望 %.0f%%）" % [
			float(row[0]), got * 100.0, expect * 100.0])
	print("── 敌机配置失误只保留为小概率不投焰 ──")
	for row in [[0.85, 0.085], [0.50, 0.05], [0.10, 0.01], [0.0, 0.0]]:
		var got: float = AircraftFlares.enemy_release_fail_chance_for_configured(float(row[0]))
		var expect: float = float(row[1])
		_record(is_equal_approx(got, expect), "配置 %.0f%% → 实际不投 %.1f%%" % [
			float(row[0]) * 100.0, got * 100.0])


func _test_enemy_break_actions() -> void:
	print("── 敌机必须真实改变航向/横移/速度/高度，才能兑现投焰 ──")
	var ac = load("res://scripts/aircraft.gd").new()
	var start_pos := Vector2.ZERO
	var start_heading := 0.0
	var start_speed := 250.0
	var start_altitude := 5000.0
	ac.global_position = start_pos
	ac.heading = start_heading
	ac.speed = start_speed
	ac.altitude = start_altitude
	_record(Missile.enemy_flare_break_action(start_pos, start_heading, start_speed,
		start_altitude, ac) == &"", "原轨迹不合格")
	ac.heading = deg_to_rad(22.0)
	_record(Missile.enemy_flare_break_action(start_pos, start_heading, start_speed,
		start_altitude, ac) == &"turn", "累计转向 22° 合格")
	ac.heading = start_heading
	ac.global_position = Vector2(120.0, -40.0)
	_record(Missile.enemy_flare_break_action(start_pos, start_heading, start_speed,
		start_altitude, ac) == &"lateral", "横向偏移 120px 合格")
	ac.global_position = start_pos
	ac.speed = 295.0
	_record(Missile.enemy_flare_break_action(start_pos, start_heading, start_speed,
		start_altitude, ac) == &"speed", "增速 45m/s 合格")
	ac.speed = start_speed
	ac.altitude = 5450.0
	_record(Missile.enemy_flare_break_action(start_pos, start_heading, start_speed,
		start_altitude, ac) == &"altitude", "高度变化 450m 合格")
	ac.free()


func _test_enemy_break_pending() -> void:
	print("── pending 期间仍可命中；动作 + 等级 roll 同时通过才 jam ──")
	var ac = load("res://scripts/aircraft.gd").new()
	ac.global_position = Vector2.ZERO
	ac.heading = 0.0
	ac.speed = 250.0
	ac.altitude = 5000.0
	var m := Missile.new()
	m.target = ac
	_record(m.begin_enemy_flare_break(ac, true, 0.95), "成功建立 pending")
	m.update_enemy_flare_break(0.20)
	_record(m.enemy_flare_break_pending and not m.is_flare_jammed,
		"未机动时保持制导与碰撞资格")
	ac.heading = deg_to_rad(25.0)
	m.update_enemy_flare_break(0.05)
	_record(not m.enemy_flare_break_pending and m.is_flare_jammed and not m.has_guidance,
		"真实转向 + roll 通过后才失导")
	m.free()

	var m_fail := Missile.new()
	m_fail.target = ac
	ac.heading = 0.0
	_record(m_fail.begin_enemy_flare_break(ac, false, 0.39), "低级失败样本建立 pending")
	ac.heading = deg_to_rad(25.0)
	m_fail.update_enemy_flare_break(0.20)
	_record(not m_fail.enemy_flare_break_pending and not m_fail.is_flare_jammed,
		"动作达门但等级 roll 失败仍继续追踪")
	m_fail.free()

	var m_timeout := Missile.new()
	m_timeout.target = ac
	ac.heading = 0.0
	_record(m_timeout.begin_enemy_flare_break(ac, true, 0.95), "无动作超时样本建立 pending")
	m_timeout.update_enemy_flare_break(Missile.ENEMY_FLARE_BREAK_WINDOW_S)
	_record(not m_timeout.enemy_flare_break_pending and not m_timeout.is_flare_jammed,
		"roll 通过但轨迹未变，1.25s 后仍不失导")
	m_timeout.free()
	ac.free()

	var ac_freed = load("res://scripts/aircraft.gd").new()
	var m_freed := Missile.new()
	m_freed.target = ac_freed
	_record(m_freed.begin_enemy_flare_break(ac_freed, true, 0.95),
		"目标释放样本建立 pending")
	ac_freed.free()
	m_freed.update_enemy_flare_break(0.1)
	_record(not m_freed.enemy_flare_break_pending,
		"目标已释放后安全清除 pending，不读取 freed object")
	m_freed.free()


func _test_enemy_release_path() -> void:
	print("── 正式 release 分流：敌机只建 pending，玩家保留即时语义 ──")
	var enemy = load("res://scripts/aircraft.gd").new()
	enemy.team = CombatUnit.TEAM_HOSTILE
	enemy.params = AircraftParams.new()
	enemy.params.flare = FlareParams.new()
	enemy.params.flare.max_flares = 1
	enemy.params.flare.burst_count = 1
	enemy.flares_remaining = 1
	var enemy_ai := AIController.new()
	enemy_ai.aircraft = enemy
	enemy_ai.skill_level = 0.9
	enemy_ai.composure = 1.0
	enemy._ai_ref = enemy_ai
	enemy.add_child(enemy_ai)
	var enemy_missile := Missile.new()
	enemy_missile.target = enemy
	AircraftFlares.release(enemy, enemy_missile)
	_record(enemy_missile.enemy_flare_break_pending and not enemy_missile.is_flare_jammed,
		"敌机投焰不瞬时 jam")
	_record(enemy.missile_phase_timer <= 0.0, "敌机投焰没有碰撞穿透窗")
	_record(enemy_ai._evading, "敌机实际投焰后进入局部 break")
	enemy_missile.free()
	enemy.free()

	var player = load("res://scripts/aircraft.gd").new()
	player.team = CombatUnit.TEAM_PLAYER
	player.params = AircraftParams.new()
	player.params.flare = FlareParams.new()
	player.params.flare.max_flares = 1
	player.params.flare.burst_count = 1
	player.flares_remaining = 1
	player.flares_guaranteed = true
	var player_missile := Missile.new()
	player_missile.target = player
	player_missile.global_position = Vector2(0.0, -100.0)
	AircraftFlares.release(player, player_missile)
	_record(player_missile.is_flare_jammed and player.missile_phase_timer > 0.0,
		"玩家保留即时 jam 与既有穿透窗")
	player_missile.free()
	player.free()


func _test_visual_side_launch() -> void:
	print("── 十枚视觉焰弹延长到 0.90s，并从两侧抛射 ──")
	var ac = load("res://scripts/aircraft.gd").new()
	AircraftFlares._queue_visual_burst(ac)
	_record(ac._flare_spawn_queue.size() == 6 \
		and is_equal_approx(float(ac._flare_spawn_queue[-1]["delay"]), 0.90),
		"六波末波 delay=0.90s")
	AircraftFlares._spawn_wave(ac, Vector2.ZERO, 0.0, 2, 0)
	var left_vel: Vector2 = ac._flare_particles[0]["vel"]
	var right_vel: Vector2 = ac._flare_particles[1]["vel"]
	var lives_ok: bool = true
	for p in ac._flare_particles:
		var life: float = float(p["life"])
		lives_ok = lives_ok and life >= AircraftFlares.FLARE_LIFE_MIN \
			and life <= AircraftFlares.FLARE_LIFE_MAX
	_record(left_vel.x < 0.0 and right_vel.x > 0.0, "双枚波左右各一")
	_record(lives_ok, "粒子寿命全部落在 3.0–4.8s")
	ac.free()


func _record(ok: bool, note: String) -> void:
	if ok:
		_pass += 1
	else:
		_fail += 1
	print("  %s %s" % ["✓" if ok else "✗", note])


func _evade_case(name: String, ac_spd: float, m_dist_px: float, m_spd: float,
		expect: bool, note: String) -> void:
	var ac = load("res://scripts/aircraft.gd").new()
	ac.global_position = Vector2.ZERO
	ac.heading = 0.0
	ac.speed = ac_spd
	ac.team = 0
	var m := Missile.new()
	m.global_position = Vector2(0.0, m_dist_px)
	m.heading = 0.0
	m.speed = m_spd
	var got: bool = MissileEvasion._is_evasion_threat(ac, m)
	var ok := got == expect
	if ok: _pass += 1
	else: _fail += 1
	print("  %s %-18s 距离=%.0fm 期望=%s 实际=%s — %s" % [
		"✓" if ok else "✗", name, m_dist_px / PPM,
		"散开" if expect else "不散开", "散开" if got else "不散开", note])
	m.free(); ac.free()


func _case(name: String, ac_spd: float, m_dist_px: float, m_spd: float,
		m_hdg_deg: float, expect: bool, note: String) -> void:
	var ac = load("res://scripts/aircraft.gd").new()
	ac.global_position = Vector2.ZERO
	ac.heading = 0.0
	ac.speed = ac_spd
	ac.team = CombatUnit.TEAM_PLAYER
	var m := Missile.new()
	m.global_position = Vector2(0.0, m_dist_px)   # 机尾后方 +y
	m.heading = deg_to_rad(m_hdg_deg)
	m.speed = m_spd
	m.team = CombatUnit.TEAM_HOSTILE
	m.target = ac
	m.is_active = true
	m.has_guidance = true
	var got: bool = AircraftFlares.player_flare_should_trigger(ac, m)
	var dist_m := m_dist_px / PPM
	var ok := got == expect
	if ok: _pass += 1
	else: _fail += 1
	print("  %s %-22s 距离=%.0fm 期望=%s 实际=%s — %s" % [
		"✓" if ok else "✗", name, dist_m,
		"放" if expect else "不放", "放" if got else "不放", note])
	m.free(); ac.free()
