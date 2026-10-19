extends RefCounted

## 错相降频保真度对照（2026-10-20）：同一初值分别以 dense_battle_sim_divisor 1/2/3 × 全部相位、
## subset（现有精简分支）/ full（bench 诊断：命中相位走完整 LOD0 路径）驱动真实 Aircraft._physics_process，
## 量化 delta×N 积分对转弯、持续转、机炮节奏与导弹规避的影响。只报告指标、不设门：
## 显式运行 `bench\run.cmd sim_divisor_fidelity 1 900 Shadow Headless`（不进 all）。
## 结论与读法见 docs/handoffs/2026-10-20-sim-divisor-stagger.md。

const DT := 1.0 / 60.0
const PPM := CombatUnit.PIXELS_PER_METER
const TYPES := [["MiG-23", "res://resources/enemy_mig23.tres"], ["F-4E", "res://resources/enemy_f4e.tres"]]
const DIVISORS := [1, 2, 3]
const PATHS := ["subset", "full"]
const HIT_DIST_M := 30.0

var _pass := 0
var _fail := 0
var _world: Node2D
var _mm: MissileManager


class BulletStub:
	extends Node2D
	var shot_times: Array[float] = []
	var now: float = 0.0
	func spawn_bullet(_pos: Vector2, _dir: float, _speed: float, _shooter: Node, _dmg: float, _is_ciws: bool = false, _visual_only: bool = false, _life: float = 2.0) -> void:
		shot_times.append(now)


func run() -> void:
	print("\n════════ 错相降频保真度对照（divisor 1/2/3 × 相位 × subset/full） ════════")
	_world = Node2D.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(_world)
	_mm = MissileManager.new()
	for type in TYPES:
		_report_reversal(type[0], type[1])
		_report_sustained(type[0], type[1])
	_report_gun_cadence()
	for type in TYPES:
		_report_missile_break(type[0], type[1])
	_report_formation(TYPES[0][0], TYPES[0][1])
	_report_call_cost(TYPES[0][0], TYPES[0][1])
	_mm.free()
	_world.queue_free()
	print("──────── 结果：%d 通过 / %d 失败（纯指标报告，不设门） ────────" % [_pass, _fail])


# ── 公共：建机与按 divisor 设 meta ──

func _make(type_path: String, divisor: int, phase: int, path: String) -> Aircraft:
	var ac := Aircraft.new()
	ac.params = load(type_path).duplicate(true)
	SurvivorPlayableSetup.deep_dup_weapons(ac.params)
	ac.team = CombatUnit.TEAM_HOSTILE
	ac.set_physics_process(false)
	_world.add_child(ac)
	ac.set_physics_process(false)
	ac.position = Vector2.ZERO
	ac.heading = 0.0
	var cruise_kmh := AircraftPhysics.effective_cruise_speed_kmh(ac)
	ac.speed = cruise_kmh / 3.6
	ac.target_speed_kmh = cruise_kmh
	ac.altitude = 5500.0
	ac.target_altitude = 5500.0
	ac.use_tactical_planner = false
	ac.keep_target_on_arrival = true
	if divisor > 1:
		ac.set_meta(&"dense_battle_sim_divisor", divisor)
		ac.set_meta(&"dense_battle_sim_phase", phase)
		if path == "full":
			ac.set_meta(&"dense_battle_sim_full_path", true)
	return ac


func _variants() -> Array:
	var out := []
	for path in PATHS:
		for divisor in DIVISORS:
			if divisor == 1 and path == "full":
				continue
			var phases := []
			for p in range(divisor):
				phases.append(p)
			out.append({"path": path if divisor > 1 else "base", "divisor": divisor, "phases": phases})
	return out


static func _bearing(from: Vector2, to: Vector2) -> float:
	var d := to - from
	return atan2(d.x, -d.y)


# ── S1 180° 掉头：对准时间、峰值坡度/G、横向占位、回平残余坡度、轨迹偏差 ──

func _fly_reversal(type_path: String, divisor: int, phase: int, path: String) -> Dictionary:
	var ac := _make(type_path, divisor, phase, path)
	var target := Vector2(0.0, 10000.0 * PPM)  # 正后方 10 km
	ac.target_position = target
	var track := PackedVector2Array()
	var t_align := -1.0
	var first_response := -1.0
	var peak_bank := 0.0
	var peak_g := 0.0
	var max_lateral := 0.0
	var speed_at_align := 0.0
	var settle_bank := 0.0
	var steps := int(15.0 / DT)
	for i in range(steps):
		var t := float(i + 1) * DT
		ac._physics_process(DT)
		track.append(ac.global_position)
		if first_response < 0.0 and absf(ac.heading) > 1e-6:
			first_response = t
		peak_bank = maxf(peak_bank, absf(ac.bank_angle))
		peak_g = maxf(peak_g, ac.g_load)
		max_lateral = maxf(max_lateral, absf(ac.global_position.x) / PPM)
		var err := absf(angle_difference(ac.heading, _bearing(ac.global_position, target)))
		if t_align < 0.0 and t > 0.5 and err < deg_to_rad(5.0):
			t_align = t
			speed_at_align = ac.speed * 3.6
		if t_align > 0.0 and t >= t_align + 1.0 and t <= t_align + 3.0:
			settle_bank = maxf(settle_bank, absf(ac.bank_angle))
	ac.queue_free()
	_world.remove_child(ac)
	return {"track": track, "t_align": t_align, "latency_ms": first_response * 1000.0,
		"peak_bank": rad_to_deg(peak_bank), "peak_g": peak_g, "lateral_m": max_lateral,
		"speed_align": speed_at_align, "settle_bank": rad_to_deg(settle_bank)}


func _report_reversal(type_name: String, type_path: String) -> void:
	print("── S1 180° 掉头（%s，巡航速，目标正后方 10 km，15 s） ──" % type_name)
	print("  %-10s %8s %8s %8s %7s %8s %8s %8s %9s %9s" % ["变体", "对准s", "响应ms", "峰坡度°", "峰G",
		"横向m", "对准km/h", "回平坡°", "轨迹RMSm", "终点差m"])
	var ref: Dictionary = _fly_reversal(type_path, 1, 0, "base")
	for v in _variants():
		var rows := []
		for phase in v.phases:
			rows.append(ref if v.divisor == 1 else _fly_reversal(type_path, v.divisor, phase, v.path))
		var agg := {}
		for key in ["t_align", "latency_ms", "peak_bank", "peak_g", "lateral_m", "speed_align", "settle_bank"]:
			var worst := 0.0
			var total := 0.0
			for r in rows:
				total += float(r[key])
				worst = maxf(worst, float(r[key]))
			agg[key] = [total / rows.size(), worst]
		var rms_worst := 0.0
		var end_worst := 0.0
		for r in rows:
			var tr: PackedVector2Array = r.track
			var sq := 0.0
			for i in range(tr.size()):
				sq += tr[i].distance_squared_to(ref.track[i])
			rms_worst = maxf(rms_worst, sqrt(sq / tr.size()) / PPM)
			end_worst = maxf(end_worst, tr[tr.size() - 1].distance_to(ref.track[tr.size() - 1]) / PPM)
		print("  %-10s %8.2f %8.1f %8.1f %7.2f %8.0f %8.0f %8.2f %9.1f %9.1f" % [
			"%s/%d" % [v.path, v.divisor], agg.t_align[0], agg.latency_ms[1], agg.peak_bank[0], agg.peak_g[0],
			agg.lateral_m[0], agg.speed_align[0], agg.settle_bank[1], rms_worst, end_worst])


# ── S2 持续最大转：目标点恒在右侧 90°，测 5–20 s 平均转速 / 速度 / G ──

func _fly_sustained(type_path: String, divisor: int, phase: int, path: String) -> Dictionary:
	var ac := _make(type_path, divisor, phase, path)
	var unwrapped := 0.0
	var last_heading := ac.heading
	var start_heading := 0.0
	var speed_sum := 0.0
	var g_sum := 0.0
	var samples := 0
	var steps := int(20.0 / DT)
	for i in range(steps):
		var t := float(i + 1) * DT
		var fwd := Vector2(sin(ac.heading), -cos(ac.heading))
		ac.target_position = ac.global_position + fwd.rotated(PI / 2.0) * 3000.0 * PPM
		ac._physics_process(DT)
		unwrapped += angle_difference(last_heading, ac.heading)
		last_heading = ac.heading
		if t > 5.0:
			if samples == 0:
				start_heading = unwrapped
			speed_sum += ac.speed * 3.6
			g_sum += ac.g_load
			samples += 1
	ac.queue_free()
	_world.remove_child(ac)
	return {"rate": rad_to_deg(unwrapped - start_heading) / 15.0, "speed": speed_sum / samples, "g": g_sum / samples}


func _report_sustained(type_name: String, type_path: String) -> void:
	print("── S2 持续最大转（%s，目标点恒在右 90°，统计 5–20 s） ──" % type_name)
	var ref := _fly_sustained(type_path, 1, 0, "base")
	for v in _variants():
		var rates := []
		var speeds := []
		var gs := []
		for phase in v.phases:
			var r: Dictionary = ref if v.divisor == 1 else _fly_sustained(type_path, v.divisor, phase, v.path)
			rates.append(r.rate)
			speeds.append(r.speed)
			gs.append(r.g)
		print("  %-10s 转速 %6.2f°/s（相位 %s）速度 %5.0f km/h  G %4.2f  转速差 %+5.1f%%" % [
			"%s/%d" % [v.path, v.divisor], _mean(rates), _fmt_list(rates), _mean(speeds), _mean(gs),
			(_mean(rates) / ref.rate - 1.0) * 100.0])


# ── S3 机炮节奏：update_gun 每 N 步调用一次、delta×N（与两条路径的完整更新一致） ──

func _gun_series(fire_rate: float, burst: int, divisor: int, phase: int) -> Dictionary:
	var ac := Aircraft.new()
	# 玩家队伍不走敌方机炮停顿门：只测 update_gun 本身在 delta×N 下的节奏。
	ac.team = CombatUnit.TEAM_PLAYER
	var p := AircraftParams.new()
	var g := GunParams.new()
	g.fire_rate = fire_rate
	g.burst_count = burst
	g.muzzle_velocity = 1000.0
	g.max_range = 1000.0
	g.fire_cone_half_angle = 15.0
	p.gun = g
	ac.params = p
	ac.ammo = 100000
	var stub := BulletStub.new()
	ac.bullet_manager = stub
	ac.is_firing = true
	var max_per_call := 0
	var clumped := 0
	var steps := int(6.0 / DT)
	for i in range(steps):
		stub.now = float(i + 1) * DT
		if divisor > 1 and (i + 1 + phase) % divisor != 0:
			continue
		var before := stub.shot_times.size()
		AircraftWeapons.update_gun(ac, DT * float(divisor))
		var fired := stub.shot_times.size() - before
		max_per_call = maxi(max_per_call, fired)
		if fired >= 2:
			clumped += fired
	var t := stub.shot_times
	var span := t[burst - 1] - t[0] if t.size() >= burst else INF
	var out := {"shots": t.size(), "max_per_call": max_per_call, "burst_span": span,
		"clumped_pct": 100.0 * clumped / maxf(1.0, float(t.size()))}
	stub.free()
	ac.free()
	return out


func _report_gun_cadence() -> void:
	print("── S3 机炮节奏（is_firing 持续 6 s；每梭 10 发） ──")
	print("  %-14s %4s %14s %9s %10s %10s" % ["射速", "N", "发数", "单次最多", "首梭跨时s", "同帧成团%"])
	for rate in [600.0, 1200.0, 1800.0, 3000.0]:
		for divisor in DIVISORS:
			var shots := []
			var per_call := 0
			var spans := []
			var clumps := []
			for phase in range(divisor):
				var r := _gun_series(rate, 10, divisor, phase)
				shots.append(r.shots)
				per_call = maxi(per_call, int(r.max_per_call))
				spans.append(r.burst_span)
				clumps.append(r.clumped_pct)
			print("  %-14s %4d %14s %9d %10.3f %10.1f" % ["%d 发/分" % int(rate), divisor, _fmt_list(shots), per_call,
				_mean(spans), _mean(clumps)])


# ── S4 导弹 vs 破 S 规避：导弹每帧真实物理；目标在导弹 3 km 内转向垂直 LOS 方向 ──

func _fly_missile(type_path: String, divisor: int, phase: int, path: String, range_m: float, aspect_deg: float,
		msl_set: Array, break_m: float) -> Dictionary:
	var tgt := _make(type_path, divisor, phase, path)
	tgt.team = CombatUnit.TEAM_HOSTILE
	# 目标航向 = aspect：0° 背向发射机（尾追），90° 横穿，180° 迎头。
	tgt.heading = deg_to_rad(aspect_deg)
	tgt.target_position = tgt.global_position + Vector2(sin(tgt.heading), -cos(tgt.heading)) * 50000.0 * PPM
	var src: Aircraft = Aircraft.new()
	src.team = CombatUnit.TEAM_PLAYER
	src.global_position = Vector2(0.0, range_m * PPM)  # 发射机在目标正南
	src.heading = 0.0
	src.speed = 250.0
	src.params = AircraftParams.new()
	var msl: MissileParams = load("res://resources/default_missile.tres").duplicate()
	if float(msl_set[1]) > 0.0:
		msl.seeker_fov = float(msl_set[1])
		msl.max_g = float(msl_set[2])
	var m: Missile = _mm.spawn_missile(src, tgt, msl)
	var broke := false
	var min_dist := INF
	var hit := false
	var t := 0.0
	while t < msl.max_lifetime + 0.5:
		t += DT
		var d_m: float = m.global_position.distance_to(tgt.global_position) / PPM
		if not broke and d_m < break_m:
			broke = true
			# 破 S：转向与导弹视线垂直、背离导弹来向一侧
			var los := (tgt.global_position - m.global_position).normalized()
			var side := los.rotated(PI / 2.0)
			if side.dot(Vector2(sin(tgt.heading), -cos(tgt.heading))) < 0.0:
				side = -side
			tgt.target_position = tgt.global_position + side * 50000.0 * PPM
		tgt._physics_process(DT)
		m._physics_process(DT)
		if not m.is_active:
			break
		d_m = m.global_position.distance_to(tgt.global_position) / PPM
		min_dist = minf(min_dist, d_m)
		if d_m < HIT_DIST_M:
			hit = true
			break
	m.queue_free()
	if m.get_parent() == _mm:
		_mm.remove_child(m)
	src.free()
	tgt.queue_free()
	_world.remove_child(tgt)
	return {"hit": hit, "min_dist": min_dist, "t": t}


func _report_missile_break(type_name: String, type_path: String) -> void:
	# 由强到弱三组：默认弹 3 km 破 S / 旧版弹（fov60/g35）1.2 km / 弱弹（fov45/g20）0.6 km 最后一刻破 S。
	# 2026-10-20 实测三组在全部几何下都命中：单次脚本化破 S 打不掉导弹，本节只能约束命中时刻差，
	# 临界规避是否翻转要用真实 MissileEvasion 链（见 flare_impact_ab）另测。
	_report_missile_case(type_name, type_path, ["默认弹", 0.0, 0.0], 3000.0)
	_report_missile_case(type_name, type_path, ["fov60/g35", 60.0, 35.0], 1200.0)
	_report_missile_case(type_name, type_path, ["fov45/g20", 45.0, 20.0], 600.0)


func _report_missile_case(type_name: String, type_path: String, msl_set: Array, break_m: float) -> void:
	print("── S4 导弹 vs 破 S（%s；%s；%.1f km 破 S；距离 3/5/7 km × 目标朝向 0/45/90/135/180°） ──" % [
		type_name, msl_set[0], break_m / 1000.0])
	var geoms := []
	for r in [3000.0, 5000.0, 7000.0]:
		for a in [0.0, 45.0, 90.0, 135.0, 180.0]:
			geoms.append([r, a])
	var ref := []
	for geo in geoms:
		ref.append(_fly_missile(type_path, 1, 0, "base", geo[0], geo[1], msl_set, break_m))
	for v in _variants():
		var hits := 0
		var runs := 0
		var flips := 0
		var dmin_diff := []
		var dt_hit := []
		for phase in v.phases:
			for gi in range(geoms.size()):
				var r: Dictionary = ref[gi] if v.divisor == 1 else _fly_missile(type_path, v.divisor, phase, v.path, geoms[gi][0], geoms[gi][1], msl_set, break_m)
				runs += 1
				hits += int(r.hit)
				flips += int(bool(r.hit) != bool(ref[gi].hit))
				if not r.hit and not ref[gi].hit:
					dmin_diff.append(float(r.min_dist) - float(ref[gi].min_dist))
				elif r.hit and ref[gi].hit:
					dt_hit.append(absf(float(r.t) - float(ref[gi].t)) * 1000.0)
		var dt_max := 0.0
		for d in dt_hit:
			dt_max = maxf(dt_max, float(d))
		print("  %-10s 命中 %2d/%2d（%4.1f%%）与基线命中结果不同 %d 次；双命中时命中时刻差 均值 %5.1f / 最大 %5.1f ms；双脱靶最近距离差 %+6.1f m" % [
			"%s/%d" % [v.path, v.divisor], hits, runs, 100.0 * hits / runs, flips, _mean(dt_hit), dt_max, _mean(dmin_diff)])


# ── S5 编队跟随位移积分：长机全频直飞，僚机按 divisor 走 AircraftFormation.update_follow，
#    比较僚机实际位移与 ∫speed·dt；1.00 = 位移只积分一次。只测积分，不评价跟队质量。

func _fly_formation(type_path: String, divisor: int, phase: int, path: String) -> Dictionary:
	var leader := _make(type_path, 1, 0, "base")
	leader.target_position = Vector2(0.0, -200000.0 * PPM)
	var wing := _make(type_path, divisor, phase, path)
	wing.position = Vector2(100.0, 100.0)
	wing.set_formation_target(leader, Vector2(100.0, 100.0))
	var moved := 0.0
	var expected := 0.0
	var steps := int(10.0 / DT)
	for i in range(steps):
		var before := wing.global_position
		var speed_before := wing.speed
		leader._physics_process(DT)
		wing._physics_process(DT)
		moved += wing.global_position.distance_to(before)
		expected += 0.5 * (speed_before + wing.speed) * PPM * DT
	var out := {"ratio": moved / maxf(expected, 0.001), "formation": wing.formation_mode}
	for ac in [leader, wing]:
		ac.queue_free()
		_world.remove_child(ac)
	return out


func _report_formation(type_name: String, type_path: String) -> void:
	print("── S5 编队跟随位移积分（%s；10 s，实际位移 / ∫speed·dt，1.00 = 只积分一次） ──" % type_name)
	var variants := _variants()
	variants.append({"path": "subset", "divisor": 4, "phases": [0, 1, 2, 3]})  # The Crucible 现用 N=4
	for v in variants:
		var ratios := []
		var formation := true
		for phase in v.phases:
			var r := _fly_formation(type_path, v.divisor, phase, v.path)
			ratios.append(r.ratio)
			formation = formation and bool(r.formation)
		print("  %-10s 位移比 %s  全程编队态=%s" % ["%s/%d" % [v.path, v.divisor], _fmt_list(ratios), str(formation)])


# ── S6 单次调用成本：同一架机完整帧 vs 跳帧（无 AI、无交战目标；只给数量级，正式混战的完整帧更贵） ──

func _call_cost_us(type_path: String, divisor: int, path: String, calls: int) -> float:
	var ac := _make(type_path, divisor, 0, path)
	ac.target_position = Vector2(0.0, -200000.0 * PPM)
	for i in range(120):
		ac._physics_process(DT)
	var t0 := Time.get_ticks_usec()
	for i in range(calls):
		ac._physics_process(DT)
	var us := float(Time.get_ticks_usec() - t0) / calls
	ac.queue_free()
	_world.remove_child(ac)
	return us


func _report_call_cost(type_name: String, type_path: String) -> void:
	print("── S6 单次 _physics_process 成本（%s，无 AI，3000 次取均值） ──" % type_name)
	var full_us := _call_cost_us(type_path, 1, "base", 3000)
	# divisor 足够大时几乎全是跳帧，均值即跳帧成本。
	var skip_us := _call_cost_us(type_path, 100000, "subset", 3000)
	var sub_us := _call_cost_us(type_path, 3, "subset", 3000)
	var full3_us := _call_cost_us(type_path, 3, "full", 3000)
	print("  完整帧 %.1f µs  跳帧 %.1f µs（%.0f%%）  subset/3 均值 %.1f µs  full/3 均值 %.1f µs" % [
		full_us, skip_us, 100.0 * skip_us / maxf(full_us, 0.001), sub_us, full3_us])


static func _mean(values: Array) -> float:
	if values.is_empty():
		return 0.0
	var total := 0.0
	for v in values:
		total += float(v)
	return total / values.size()


static func _fmt_list(values: Array) -> String:
	var parts := PackedStringArray()
	for v in values:
		parts.append(("%.2f" % v) if typeof(v) == TYPE_FLOAT else str(v))
	return "/".join(parts)
