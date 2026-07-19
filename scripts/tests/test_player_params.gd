extends RefCounted

## 无头验收：resources/player/ 41 份玩家机 params（spec player-aircraft-power-curve §2 v7 矩阵）
## 全量加载 / 矩阵锚点抽查 / 同族链逐轴单调 / 雷达走廊 / 王冠不越位 / 攻击线火箭
## 运行：godot --headless --path . -- --bench=player_params（或 --bench=all）

var _pass := 0
var _fail := 0

const IDS: Array[String] = [
	"f14", "f15", "a6e", "mirage3",
	"mirage2000", "f15c", "f15e", "fa18e", "f16", "gripen_c", "su27", "a10",
	"rafale", "tornado", "typhoon", "su34", "viggen", "mig31", "harrier",
	"f15smtd", "su35", "f35", "gripen_e", "f22", "su57", "j20", "a12",
	"yf23", "f47", "mig41", "fcas", "gcap", "j36",
	"x09", "x13", "x02", "x21", "x44", "x77", "x90", "ax00",
]


func run() -> void:
	print("\n════════ 玩家机 params 验收（41 机矩阵 v7） ════════")
	var p: Dictionary = {}
	var all_loaded := true
	for id in IDS:
		var res = load("res://resources/player/player_%s.tres" % id)
		if res == null or not (res is AircraftParams):
			all_loaded = false
			print("    ! 加载失败：%s" % id)
			continue
		p[id] = res
	_check("41 份全部加载为 AircraftParams", all_loaded and p.size() == 41, "got %d" % p.size())
	if p.size() != 41:
		_finish()
		return

	# 锚点抽查（矩阵 §2 直写值）
	_check("F-14 锚点（110HP/2000/雷达3600/锥32/锁2.8/弹4）",
		_row_eq(p["f14"], 110, 2000, 3600, 32, 2.8, 4), _row_str(p["f14"]))
	_check("X-13 航电王（雷达5000/锥46/锁1.4）",
		is_equal_approx(p["x13"].radar_range, 5000.0) and is_equal_approx(p["x13"].radar_half_angle, 46.0)
		and is_equal_approx(p["x13"].lock_time, 1.4), _row_str(p["x13"]))
	_check("X-44 全谱最肉（HP 200）", is_equal_approx(p["x44"].max_hp, 200.0), "")
	_check("鹞失速地板 140（全谱最低签名）", is_equal_approx(p["harrier"].stall_speed_base, 140.0),
		"got %.0f" % p["harrier"].stall_speed_base)
	_check("其余机失速地板 220（模板）", is_equal_approx(p["a6e"].stall_speed_base, 220.0), "")

	# 结构极限 = 持续 G + 3（全谱规则）
	var structural_ok := true
	for id in IDS:
		if not is_equal_approx(p[id].max_g_structural, p[id].max_g + 3.0):
			structural_ok = false
	_check("全谱 max_g_structural = max_g + 3", structural_ok, "")

	# 雷达走廊 2800~5000
	var corridor_ok := true
	for id in IDS:
		if p[id].radar_range < 2800.0 or p[id].radar_range > 5000.0:
			corridor_ok = false
			print("    ! 走廊越界：%s radar=%.0f" % [id, p[id].radar_range])
	_check("雷达走廊 2800~5000 全谱在带内", corridor_ok, "")

	# 同族链逐轴单调（同类纯升级规则 §1.3 抽查）
	_check("F-15→F-15C→S/MTD 逐轴不倒退",
		_chain_monotonic(p, ["f15", "f15c", "f15smtd"]), "")
	_check("鹰狮 C→E 逐轴不倒退", _chain_monotonic(p, ["gripen_c", "gripen_e"]), "")
	_check("远程线 F-14→MiG-31→J-20→MiG-41→X-21 速度递增",
		p["f14"].max_speed < p["mig31"].max_speed and p["mig31"].max_speed < p["j20"].max_speed
		and p["j20"].max_speed < p["mig41"].max_speed and p["mig41"].max_speed < p["x21"].max_speed, "")

	# 王冠不越位：AX-00 全轴第二（不夺任何单项冠军）
	_check("AX-00 不夺极速冠（< X-21）", p["ax00"].max_speed < p["x21"].max_speed, "")
	_check("AX-00 不夺航电冠（雷达 < X-13）", p["ax00"].radar_range < p["x13"].radar_range, "")
	_check("AX-00 不夺 G 冠（< X-09）", p["ax00"].max_g < p["x09"].max_g, "")
	_check("AX-00 不夺肉冠（HP < X-44）", p["ax00"].max_hp < p["x44"].max_hp, "")

	# 弹数（内联 missile 单一权威源）+ 攻击线火箭
	_check("弹数抽查（F-14=4 / MiG-41=6 / F-15=2）",
		p["f14"].missile.max_count == 4 and p["mig41"].missile.max_count == 6
		and p["f15"].missile.max_count == 2, "")
	_check("攻击线带火箭（A-10/狂风/X-44）非攻击不带（F-22）",
		p["a10"].rocket != null and p["tornado"].rocket != null and p["x44"].rocket != null
		and p["f22"].rocket == null, "")
	_finish()


func _row_eq(prm: AircraftParams, hp: float, spd: float, radar: float, cone: float, lock: float, msl: int) -> bool:
	return is_equal_approx(prm.max_hp, hp) and is_equal_approx(prm.max_speed, spd) \
		and is_equal_approx(prm.radar_range, radar) and is_equal_approx(prm.radar_half_angle, cone) \
		and is_equal_approx(prm.lock_time, lock) and prm.missile != null and prm.missile.max_count == msl


func _row_str(prm: AircraftParams) -> String:
	return "hp=%.0f spd=%.0f radar=%.0f cone=%.0f lock=%.1f" % [
		prm.max_hp, prm.max_speed, prm.radar_range, prm.radar_half_angle, prm.lock_time]


## 同族链每轴 ≥ 前代（HP/极速/巡航/加速/G/雷达/锥；锁定耗时 ≤ 前代）
func _chain_monotonic(p: Dictionary, chain: Array) -> bool:
	for i in range(1, chain.size()):
		var a: AircraftParams = p[chain[i - 1]]
		var b: AircraftParams = p[chain[i]]
		if b.max_hp < a.max_hp or b.max_speed < a.max_speed or b.cruise_speed < a.cruise_speed \
			or b.acceleration < a.acceleration or b.max_g < a.max_g \
			or b.radar_range < a.radar_range or b.radar_half_angle < a.radar_half_angle \
			or b.lock_time > a.lock_time:
			print("    ! 倒退：%s → %s" % [chain[i - 1], chain[i]])
			return false
	return true


func _finish() -> void:
	print("──────── 结果：%d 通过 / %d 失败 ────────" % [_pass, _fail])
	print("══════════════════════════════════════════════════\n")


func _check(label: String, ok: bool, detail: String) -> void:
	if ok:
		_pass += 1
		print("  ✓ %s" % label)
	else:
		_fail += 1
		print("  ✗ %s — %s" % [label, detail])
