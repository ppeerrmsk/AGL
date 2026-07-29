extends RefCounted

## 无头行为验收：舰队编队运动（治"整支航母舰队原地旋转"）
##
## 事故回顾：僚舰是**刚体跟随**（_update_formation_follow 直接复制 leader.heading 并按偏移摆位），
## 而旗舰原本走"直线往返 + 端点 180° U-turn"。CV turn_rate=0.05 rad/s 掉头一次要 63 s，
## 期间最外圈僚舰（偏移 1556 px）以 0.05×1556 ≈ 78 px/s（≈560 km/h、自身航速 20 倍）绕圈 ——
## 玩家看到的就是"航母战打一会儿，整支舰队全都在旋转"。
##
## 现在两道闸：
##   1. NavalUnit._effective_turn_rate() —— 旗舰转速按最外圈僚舰切向线速度上限收紧（通用，覆盖所有编队）
##   2. CSG 旗舰改环形巡航（patrol_center/patrol_radius）—— 恒定盘旋，全程不掉头
##
## 真实步进：直接逐帧调 NavalUnit._update_movement(dt)（60 Hz），不做几何近似。
##
## 运行：godot --headless --path . -- --bench=naval_formation（或 --bench=all）

const DT := 1.0 / 60.0
const CSG := preload("res://scripts/survivor/carrier_strike_group.gd")
const CV_PARAMS_PATH := "res://resources/naval/carrier_cv.tres"
const FFG_PARAMS_PATH := "res://resources/naval/frigate_ffg.tres"

## 视觉验收阈值（比实现里的硬上限留一点余量）
const MAX_FLEET_ROT_DPS := 0.35        ## 整队转位角速度上限（°/s）—— 肉眼不该看出"在转"
const MAX_ESCORT_SPEED_PXS := 12.0     ## 僚舰对地速度上限（px/s ≈ 24 m/s ≈ 47 kn）

var _pass := 0
var _fail := 0
var _root: Node2D = null


func run() -> void:
	print("\n════════ 舰队编队运动验收（反原地旋转） ════════")
	_root = Node2D.new()
	_test_csg_ring_patrol()
	_test_uturn_no_whip()
	_test_solo_ship_unchanged()
	_root.free()
	_root = null
	print("──────── 结果：%d 通过 / %d 失败 ────────" % [_pass, _fail])
	print("══════════════════════════════════════════════════\n")


# ── A. CSG 环形巡航：整队只有极缓慢转位，僚舰不被甩飞 ──
func _test_csg_ring_patrol() -> void:
	print("── A. CSG 环形巡航（15 分钟步进） ──")
	var anchor := Vector2.ZERO
	var r: float = CSG.CV_PATROL_RING_RADIUS
	# place_heading = 0（朝北）→ stb = (1,0) → CV 出生在锚点正左方圆周上，切线朝北
	var cv := _make_ship(CV_PARAMS_PATH, anchor - Vector2(r, 0.0), 0.0)
	cv.patrol_center = anchor
	cv.patrol_radius = r
	var escorts := _make_escorts(cv, CSG.ESCORT_OFFSETS)

	var stats := _step_fleet(cv, escorts, 900.0)
	var radius_err: float = maxf(absf(stats["cv_r_min"] - r), absf(stats["cv_r_max"] - r))

	print("   转位 %.3f°/s（上限 %.2f）| 僚舰最快 %.1f px/s（上限 %.1f）| 圆周半径 %.0f~%.0f（目标 %.0f）| 离锚点最远 %.0f px | 累计转过 %.2f 圈" % [
		stats["max_rot_dps"], MAX_FLEET_ROT_DPS, stats["max_escort_speed"], MAX_ESCORT_SPEED_PXS,
		stats["cv_r_min"], stats["cv_r_max"], r, stats["max_dist_anchor"], stats["turns"]])

	_check("整队转位角速度 ≤ %.2f°/s" % MAX_FLEET_ROT_DPS, stats["max_rot_dps"] <= MAX_FLEET_ROT_DPS)
	_check("僚舰对地速度 ≤ %.0f px/s（不被甩飞）" % MAX_ESCORT_SPEED_PXS,
		stats["max_escort_speed"] <= MAX_ESCORT_SPEED_PXS)
	_check("旗舰稳定贴在巡航圆上（半径误差 ≤ 120 px，实测 %.0f）" % radius_err, radius_err <= 120.0)
	_check("舰队不脱 BOSS 圈（最远 ≤ 2450 px，实测 %.0f）" % stats["max_dist_anchor"],
		stats["max_dist_anchor"] <= 2450.0)
	_check("确实在慢慢盘旋（15 分钟转 ≥ 0.5 圈，实测 %.2f）" % stats["turns"], stats["turns"] >= 0.5)
	# 全程单向：一次都不该出现"掉头"（U-turn 是事故根因）
	_check("全程无掉头（航向单调推进）", stats["reversals"] == 0)


# ── B. 直线往返 U-turn 也不再甩僚舰（转速上限兜底，覆盖 zone_mission 舰队）──
func _test_uturn_no_whip() -> void:
	print("── B. 直线往返 U-turn：转速上限兜底 ──")
	# 旗舰出生就贴在南端点上 → 第一秒内立刻要掉头 180°
	var cv := _make_ship(CV_PARAMS_PATH, Vector2(0.0, 3000.0), 180.0)
	cv.waypoints = PackedVector2Array([Vector2(0.0, 3000.0), Vector2(0.0, -3000.0)])
	var escorts := _make_escorts(cv, CSG.ESCORT_OFFSETS)

	var r_max: float = 0.0
	for off in CSG.ESCORT_OFFSETS:
		r_max = maxf(r_max, (off as Vector2).length())
	var uncapped: float = cv.params.turn_rate * r_max   ## 旧行为下最外圈僚舰的切向速度

	var stats := _step_fleet(cv, escorts, 300.0)
	print("   转位 %.3f°/s | 僚舰最快 %.1f px/s（旧行为 %.0f px/s ≈ %.0f km/h）" % [
		stats["max_rot_dps"], stats["max_escort_speed"], uncapped, uncapped * 2.0 * 3.6])

	_check("U-turn 中僚舰对地速度 ≤ %.0f px/s" % MAX_ESCORT_SPEED_PXS,
		stats["max_escort_speed"] <= MAX_ESCORT_SPEED_PXS)
	_check("U-turn 中整队转位 ≤ %.2f°/s" % MAX_FLEET_ROT_DPS, stats["max_rot_dps"] <= MAX_FLEET_ROT_DPS)
	_check("旧行为确实会超标（回归基准 %.0f px/s > %.0f）" % [uncapped, MAX_ESCORT_SPEED_PXS],
		uncapped > MAX_ESCORT_SPEED_PXS)


# ── C. 无僚舰的独立船不受影响 ──
func _test_solo_ship_unchanged() -> void:
	print("── C. 独立单船（无僚舰）转速不变 ──")
	var solo := _make_ship(FFG_PARAMS_PATH, Vector2.ZERO, 0.0)
	var eff: float = solo._effective_turn_rate()
	_check("单船 turn_rate 原样透传（%.3f == %.3f）" % [eff, solo.params.turn_rate],
		is_equal_approx(eff, solo.params.turn_rate))


# ══════════════════════════════════════════════
#  步进 / 工具
# ══════════════════════════════════════════════

## 逐帧推进整支舰队，回收视觉指标
func _step_fleet(cv: NavalUnit, escorts: Array, seconds: float) -> Dictionary:
	var anchor: Vector2 = cv.patrol_center if cv.patrol_center != Vector2.INF else Vector2.ZERO
	var max_rot: float = 0.0
	var max_escort_speed: float = 0.0
	var cv_r_min: float = INF
	var cv_r_max: float = 0.0
	var max_dist: float = 0.0
	var total_turn: float = 0.0
	var reversals: int = 0
	var prev_hdg: float = cv.heading
	var prev_pos: Array = []
	for e in escorts:
		prev_pos.append((e as NavalUnit).position)

	var frames: int = int(seconds / DT)
	for i in range(frames):
		cv._update_movement(DT)
		var d_hdg: float = angle_difference(prev_hdg, cv.heading)
		prev_hdg = cv.heading
		# 前 30 帧是入圈瞬态（僚舰还没自注册到 leader），不计入指标
		if i > 30:
			max_rot = maxf(max_rot, absf(d_hdg) / DT)
			total_turn += d_hdg
			if d_hdg * total_turn < 0.0 and absf(d_hdg) > 1e-6:
				reversals += 1
			var cv_r: float = cv.position.distance_to(anchor)
			cv_r_min = minf(cv_r_min, cv_r)
			cv_r_max = maxf(cv_r_max, cv_r)
			max_dist = maxf(max_dist, cv_r)

		for j in range(escorts.size()):
			var e: NavalUnit = escorts[j]
			e._update_movement(DT)
			if i > 30:
				max_escort_speed = maxf(max_escort_speed, e.position.distance_to(prev_pos[j]) / DT)
				max_dist = maxf(max_dist, e.position.distance_to(anchor))
			prev_pos[j] = e.position

	return {
		"max_rot_dps": rad_to_deg(max_rot),
		"max_escort_speed": max_escort_speed,
		"cv_r_min": cv_r_min if cv_r_min != INF else 0.0,
		"cv_r_max": cv_r_max,
		"max_dist_anchor": max_dist,
		"turns": absf(total_turn) / TAU,
		"reversals": reversals,
	}


func _make_ship(params_path: String, pos: Vector2, heading_deg: float) -> NavalUnit:
	var ship: NavalUnit = NavalUnit.new()
	ship.params = load(params_path)
	ship.position = pos
	ship.heading = deg_to_rad(heading_deg)
	ship.rotation = ship.heading
	_root.add_child(ship)   ## _root 不在场景树里 → 不触发 _ready（挂点/锁定代理与本测试无关）
	return ship


func _make_escorts(leader: NavalUnit, offsets: Array) -> Array:
	var fwd := Vector2(sin(leader.heading), -cos(leader.heading))
	var stb := Vector2(cos(leader.heading), sin(leader.heading))
	var out: Array = []
	for off in offsets:
		var o: Vector2 = off
		var e := _make_ship(FFG_PARAMS_PATH, leader.position + fwd * o.x + stb * o.y,
			rad_to_deg(leader.heading))
		e.formation_leader = leader
		e.formation_offset = o
		out.append(e)
	return out


func _check(label: String, ok: bool) -> void:
	if ok:
		_pass += 1
		print("   ✓ %s" % label)
	else:
		_fail += 1
		printerr("   ✗ %s" % label)
