extends RefCounted

## 热诱弹改版影响 A/B 报告（显式 bench，不进入 all）。
##
## A = 旧即时版：普通敌机 release 成功后立即按 calc_jam_chance 判定；王牌立即 100% jam。
## B = 调整前真实 break：原始 release 失误 × 15%→95% 等级 roll。
## C = 当前真实 break：release 仅小概率失误 × 80%→95% 等级 roll；仍必须完成真实机动。
##
## 生存判定使用正式 Missile 物理；命中用相对运动线段扫过正式引信半径，避免 60Hz 穿步。
## 战斗力用 8 秒观察窗内“非 EVADE 且 combat_target 已恢复”的秒数衡量。
## 运行：bench/run.cmd flare_impact_ab 1 180 Shadow Headless

const DT := 1.0 / 60.0
const HORIZON_S := 8.0
const PPM := CombatUnit.PIXELS_PER_METER
const MISSILE_SPEED_MS := 1100.0

const DISTANCES_M: Array[float] = [3000.0, 800.0, 300.0]
const PILOT_ROWS: Array[Dictionary] = [
	{"id": "low", "label": "低级最差纪律", "params": "res://resources/enemy_f100.tres",
		"skill": 0.30, "fail": 0.85, "ace": false},
	{"id": "mid", "label": "中级标准纪律", "params": "res://resources/enemy_f16.tres",
		"skill": 0.60, "fail": 0.50, "ace": false},
	{"id": "high", "label": "高级 Su-35", "params": "res://resources/enemy_su35.tres",
		"skill": 0.90, "fail": 0.10, "ace": false},
	{"id": "ace", "label": "王牌 Su-35", "params": "res://resources/enemy_su35.tres",
		"skill": 0.95, "fail": 0.00, "ace": true},
]

var _fail := 0
var _long_range_rows: Array[Dictionary] = []


func run() -> void:
	print("\n════════ 敌机热诱弹改版影响 A/B ════════")
	print("同一尾追几何；MRM 1100m/s；敌机真实物理 break；观察窗 %.0fs" % HORIZON_S)
	print("生存率含 release 失误；前版=低成功率真实 break；当前=高可靠真实 break")
	for distance_m in DISTANCES_M:
		print("\n── 初始来弹距离 %.0fm ──" % distance_m)
		print("  %-13s | 旧即时 | 前版 | 当前 | 当前-前版 | 前攻s | 当前攻s | break | 无jam" % "敌机")
		for row in PILOT_ROWS:
			var result := _compare_row(row, distance_m)
			print("  %-13s | %6.1f%% | %5.1f%% | %5.1f%% | %+8.1fpp | %5.2f | %7.2f | %5s | %s" % [
				row["label"], float(result["old_survival"]) * 100.0,
				float(result["previous_survival"]) * 100.0,
				float(result["new_survival"]) * 100.0,
				(float(result["new_survival"]) - float(result["previous_survival"])) * 100.0,
				result["previous_attack_s"], result["new_attack_s"],
				("%.2fs" % float(result["break_time_s"])) if float(result["break_time_s"]) >= 0.0 else "未达门",
				"脱靶" if bool(result["no_jam_survived"]) else "命中",
			])
		if is_equal_approx(distance_m, 3000.0):
			_long_range_rows = _rows_for_distance(distance_m)

	_print_sequential_projection()
	_run_pending_cost_probe()
	_check_report_sanity()
	print("──────── 报告完整性：失败 %d ────────" % _fail)
	print("══════════════════════════════════════\n")


func _rows_for_distance(distance_m: float) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for row in PILOT_ROWS:
		out.append(_compare_row(row, distance_m))
	return out


func _compare_row(row: Dictionary, distance_m: float) -> Dictionary:
	var no_jam := _simulate_branch(row, distance_m, &"no_jam")
	var new_success := _simulate_branch(row, distance_m, &"new_success")
	var old_jam: float = 1.0 if bool(row["ace"]) else _old_jam_chance(row, distance_m)
	var previous_release_p: float = 1.0 - float(row["fail"])
	var current_release_p: float = 1.0 \
		- AircraftFlares.enemy_release_fail_chance_for_configured(float(row["fail"]))
	var old_success_p: float = previous_release_p * old_jam
	var previous_break_chance: float = lerpf(0.15, 0.95, clampf(float(row["skill"]), 0.0, 1.0))
	var previous_roll_p: float = previous_release_p * previous_break_chance
	var new_roll_p: float = current_release_p * AircraftFlares.enemy_flare_break_chance_for_skill(
		float(row["skill"]))
	var no_jam_survival: float = 1.0 if bool(no_jam["survived"]) else 0.0
	var new_success_survival: float = 1.0 if bool(new_success["survived"]) else 0.0
	return {
		"id": row["id"],
		"old_jam": old_jam,
		"old_success_p": old_success_p,
		"previous_roll_p": previous_roll_p,
		"new_roll_p": new_roll_p,
		"old_survival": old_success_p + (1.0 - old_success_p) * no_jam_survival,
		"previous_survival": previous_roll_p * new_success_survival
			+ (1.0 - previous_roll_p) * no_jam_survival,
		"new_survival": new_roll_p * new_success_survival
			+ (1.0 - new_roll_p) * no_jam_survival,
		"old_attack_s": old_success_p * HORIZON_S
			+ (1.0 - old_success_p) * float(no_jam["attack_s"]),
		"previous_attack_s": previous_roll_p * float(new_success["attack_s"])
			+ (1.0 - previous_roll_p) * float(no_jam["attack_s"]),
		"new_attack_s": new_roll_p * float(new_success["attack_s"])
			+ (1.0 - new_roll_p) * float(no_jam["attack_s"]),
		"break_time_s": new_success["break_time_s"],
		"new_success_survived": new_success["survived"],
		"no_jam_survived": no_jam["survived"],
		"no_jam_attack_s": no_jam["attack_s"],
	}


func _old_jam_chance(row: Dictionary, distance_m: float) -> float:
	var ac := _make_aircraft(String(row["params"]), float(row["skill"]))
	var m := _make_missile(ac, distance_m)
	var chance: float = AircraftFlares.calc_jam_chance(ac, m)
	m.free()
	ac.free()
	return chance


func _simulate_branch(row: Dictionary, distance_m: float, branch: StringName) -> Dictionary:
	var root := Node2D.new()
	var scene_root: Window = BenchRunner.get_tree().root
	scene_root.add_child(root)
	var manager := MissileManager.new()
	root.add_child(manager)
	var enemy := _make_aircraft(String(row["params"]), float(row["skill"]))
	root.add_child(enemy)
	var opponent := _make_aircraft("res://resources/playable_f14_base.tres", 1.0)
	opponent.team = CombatUnit.TEAM_PLAYER
	opponent.global_position = Vector2(0.0, -5000.0)
	root.add_child(opponent)
	enemy.combat_target = opponent
	var ai := AIController.new()
	ai.aircraft = enemy
	ai.skill_level = float(row["skill"])
	ai.composure = 1.0
	ai.focus = 1.0
	ai.situational_awareness = 1.0
	ai._current_target = opponent
	enemy._ai_ref = ai
	enemy.add_child(ai)
	var missile := _make_missile(enemy, distance_m)
	missile.source = opponent
	manager.add_child(missile)
	MissileEvasion.enter_evade(ai)
	if branch == &"old_success":
		missile.is_flare_jammed = true
	elif branch == &"new_success":
		missile.begin_enemy_flare_break(enemy, true,
			AircraftFlares.enemy_flare_break_chance_for_skill(float(row["skill"])))

	var survived := true
	var attack_s := 0.0
	var evasion_s := 0.0
	var break_time_s := -1.0
	var elapsed := 0.0
	var fuse_px: float = missile.params.proximity_fuse_radius * PPM
	for _frame in range(int(HORIZON_S / DT)):
		var prev_rel: Vector2 = missile.global_position - enemy.global_position
		MissileEvasion.process_evade(ai, DT)
		if ai._evading:
			evasion_s += DT
			enemy.target_speed_kmh = AircraftPhysics.effective_max_speed_kmh(enemy)
			AircraftPhysics.set_afterburner(enemy, true)
		enemy._resolve_intents(DT)
		_step_aircraft(enemy)
		missile._physics_process(DT)
		elapsed += DT
		if break_time_s < 0.0 and missile.is_flare_jammed:
			break_time_s = elapsed
		if not ai._evading and enemy.combat_target == opponent:
			attack_s += DT
		if not missile.is_flare_jammed:
			var next_rel: Vector2 = missile.global_position - enemy.global_position
			if _relative_segment_distance(prev_rel, next_rel) < fuse_px \
					and absf(missile.altitude - enemy.altitude) < missile.params.proximity_fuse_alt:
				survived = false
				break

	var lateral_m: float = absf(enemy.global_position.x) / PPM
	enemy.remove_child(ai)
	manager.remove_child(missile)
	root.remove_child(enemy)
	root.remove_child(opponent)
	ai.free()
	missile.free()
	enemy.free()
	opponent.free()
	manager.free()
	scene_root.remove_child(root)
	root.free()
	return {
		"survived": survived,
		"attack_s": attack_s,
		"evasion_s": evasion_s,
		"break_time_s": break_time_s,
		"lateral_m": lateral_m,
	}


func _make_aircraft(params_path: String, skill: float) -> Aircraft:
	var ac := Aircraft.new()
	ac.params = (load(params_path) as AircraftParams).duplicate(true)
	ac.team = CombatUnit.TEAM_HOSTILE
	ac.heading = 0.0
	ac.bank_angle = 0.0
	ac.altitude = 5000.0
	ac.target_altitude = 5000.0
	ac.speed = ac.params.cruise_speed / 3.6
	ac.target_speed_kmh = ac.params.cruise_speed
	ac.target_position = Vector2.INF
	ac.g_load = 1.0
	ac.use_tactical_planner = true
	ac.tactical_aggression = skill
	ac.global_position = Vector2.ZERO
	return ac


func _make_missile(target_ac: Aircraft, distance_m: float) -> Missile:
	var m := Missile.new()
	m.params = (load("res://resources/default_missile.tres") as MissileParams).duplicate(true)
	m.target = target_ac
	m.team = CombatUnit.TEAM_PLAYER
	m.global_position = Vector2(0.0, distance_m * PPM)
	m.heading = 0.0
	m.speed = MISSILE_SPEED_MS
	m.altitude = target_ac.altitude
	m.age = 1.0
	var los := target_ac.global_position - m.global_position
	m._prev_los_angle = atan2(los.x, -los.y)
	return m


func _step_aircraft(ac: Aircraft) -> void:
	AircraftPhysics.update_target_heading(ac)
	AircraftPhysics.update_bank(ac, DT)
	AircraftPhysics.update_heading(ac, DT)
	AircraftPhysics.update_speed(ac, DT)
	AircraftPhysics.update_g_load(ac)
	AircraftPhysics.update_altitude(ac, DT)
	AircraftPhysics.apply_movement(ac, DT)


func _relative_segment_distance(a: Vector2, b: Vector2) -> float:
	var d := b - a
	var denom := d.length_squared()
	if denom <= 0.000001:
		return a.length()
	var t := clampf(-a.dot(d) / denom, 0.0, 1.0)
	return (a + d * t).length()


func _print_sequential_projection() -> void:
	if _long_range_rows.is_empty():
		return
	var ace_row: Dictionary = _long_range_rows[-1]
	var old_one: float = float(ace_row["old_survival"])
	var previous_one: float = float(ace_row["previous_survival"])
	var new_one: float = float(ace_row["new_survival"])
	print("\n── 王牌/BOSS 导弹防御层连续尝试投影（3000m、每发间隔足够；不计额外 HP/隐形）──")
	for count in [1, 2, 4]:
		print("  %d 次来袭：旧即时 %.1f%% / 前版 %.1f%% / 当前 %.1f%%" % [count,
			pow(old_one, count) * 100.0, pow(previous_one, count) * 100.0,
			pow(new_one, count) * 100.0])
	print("  注意：同批齐射在新版没有旧 BOSS 的 1s 全弹穿透窗，实际会比该顺序投影更危险。")


func _run_pending_cost_probe() -> void:
	const MISSILE_COUNT := 256
	const LOOPS := 1500
	var ac := _make_aircraft("res://resources/enemy_su35.tres", 0.9)
	var idle: Array[Missile] = []
	var active: Array[Missile] = []
	for _i in range(MISSILE_COUNT):
		var mi := Missile.new()
		mi.target = ac
		idle.append(mi)
		var ma := Missile.new()
		ma.target = ac
		ma.begin_enemy_flare_break(ac, true, 0.87)
		active.append(ma)
	var idle_samples: Array[float] = []
	var active_samples: Array[float] = []
	for _round in range(5):
		var t0 := Time.get_ticks_usec()
		for _loop in range(LOOPS):
			for m in idle:
				m.update_enemy_flare_break(0.0)
		idle_samples.append(float(Time.get_ticks_usec() - t0))
		var t1 := Time.get_ticks_usec()
		for _loop in range(LOOPS):
			for m in active:
				m.update_enemy_flare_break(0.0)
		active_samples.append(float(Time.get_ticks_usec() - t1))
	var calls := float(MISSILE_COUNT * LOOPS)
	var idle_us: float = _median(idle_samples) / calls
	var active_us: float = _median(active_samples) / calls
	print("\n── pending O(1) 微基准（中位数，256 弹 × 1500 次 × 5 轮）──")
	print("  无 pending 早退：%.4f µs/弹帧；active pending：%.4f µs/弹帧" % [idle_us, active_us])
	print("  100 枚同时 active pending 的保守估算：%.3f ms/物理帧" % [active_us * 100.0 / 1000.0])
	for m in idle:
		m.free()
	for m in active:
		m.free()
	ac.free()


func _median(values: Array[float]) -> float:
	values.sort()
	return values[values.size() / 2]


func _check_report_sanity() -> void:
	var valid := _long_range_rows.size() == PILOT_ROWS.size()
	for row in _long_range_rows:
		valid = valid and float(row["old_survival"]) >= 0.0 \
			and float(row["old_survival"]) <= 1.0 \
			and float(row["previous_survival"]) >= 0.0 \
			and float(row["previous_survival"]) <= 1.0 \
			and float(row["new_survival"]) >= 0.0 \
			and float(row["new_survival"]) <= 1.0
	if not valid:
		_fail += 1
	print("  %s A/B 概率与真实物理样本完整" % ("✓" if valid else "✗"))
