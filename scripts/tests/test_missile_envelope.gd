extends RefCounted

## MRM 导弹包络仿真（2026-07-05，裁决"命中率低是 AI 发射纪律还是导弹性能"）
## 用**真实 missile.gd 物理**（非复刻公式）手动步进：
##   变量 A：发射几何（距离 2/5/8/11km × 目标行为 尾追直线/横穿6G × 离轴 0°/40°crank）
##   变量 B：导弹参数（OLD fov60/g35 vs NEW fov90/g45）
## 判定逻辑：
##   理想几何（0° 离轴近距）都打不中 → 导弹性能问题
##   理想几何能中、AI 实际几何（远距/横穿/crank）打不中 → 发射纪律问题
## 实战锚点：log 122049 发射距离 min=760m 中位=4766m max=11460m（n=25）
## 运行：godot --headless --path . -- --bench=missile_env（或 --bench=all）

const DT := 1.0 / 60.0
const PPM := 0.5
const HIT_DIST_M := 30.0     ## 近炸判定（fuse 20m + 余量）
const TGT_SPEED := 250.0     ## 目标 250 m/s（典型战斗机）

var _pass := 0
var _fail := 0
var _mm: MissileManager = null


func run() -> void:
	print("\n════════ MRM 包络仿真（真实 missile.gd 物理步进） ════════")
	_mm = MissileManager.new()

	var scenarios := [
		# [标签, 距离m, 目标模式, 发射离轴deg]
		["2km 尾追直线", 2000.0, "flee", 0.0],
		["2km 横穿6G", 2000.0, "beam6g", 0.0],
		["5km 尾追直线", 5000.0, "flee", 0.0],
		["5km 横穿6G", 5000.0, "beam6g", 0.0],
		["5km 横穿6G+离轴10°", 5000.0, "beam6g", 10.0],
		["5km 横穿6G+离轴20°", 5000.0, "beam6g", 20.0],   # 玩家方发射质量门边界（X-02=22°）
		["5km 横穿6G+离轴28°", 5000.0, "beam6g", 28.0],   # FOV60 半角(30°)边缘
		["5km 横穿6G+crank40°", 5000.0, "beam6g", 40.0],  # 敌方无门发射（玩家方被 block）
		["8km 尾追直线", 8000.0, "flee", 0.0],
		["8km 横穿6G", 8000.0, "beam6g", 0.0],
		["11km 尾追直线", 11000.0, "flee", 0.0],
	]
	var param_sets := [
		["OLD(fov60/g35)", 60.0, 35.0],
		["NEW(fov90/g45)", 90.0, 45.0],
	]

	var results := {}  # pset → {label → result}
	for pset in param_sets:
		print("── 参数集 %s ──" % pset[0])
		var set_res := {}
		for sc in scenarios:
			var r := _simulate(String(sc[0]), float(sc[1]), String(sc[2]), float(sc[3]),
					float(pset[1]), float(pset[2]))
			set_res[sc[0]] = r
			print("  %-22s %s  min_dist=%4.0fm  t=%4.1fs%s" % [
				sc[0], "HIT " if r.hit else "MISS", r.min_dist, r.t,
				("  [" + r.why + "]") if not r.hit else ""])
		results[pset[0]] = set_res

	# ── 裁决断言 ──
	var new_res: Dictionary = results["NEW(fov90/g45)"]
	var old_res: Dictionary = results["OLD(fov60/g35)"]
	_check("基线理智：NEW 2km 尾追直线必中", new_res["2km 尾追直线"].hit, "")
	# 性能裁决：理想几何（0° 离轴、≤5km）NEW 参数命中数
	var ideal := ["2km 尾追直线", "2km 横穿6G", "5km 尾追直线", "5km 横穿6G"]
	var ideal_hits := 0
	for k in ideal:
		if new_res[k].hit: ideal_hits += 1
	_check("理想几何 ≥3/4 命中（性能达标线）", ideal_hits >= 3,
			"%d/4——若此项挂 = 导弹性能问题实锤" % ideal_hits)
	# 2026-08-19：离架方向已与发射门 / planner 共享两轮 TTI 前置点。
	# 历史 OLD 参数在 20°+6G 的丢锁带已被更准确的离架几何闭合，不能再把“OLD 必须 miss”
	# 当成永久回归条件；当前门改为两组参数在合法发射窗口内都必须命中。
	_check("20°离轴边界带：OLD 共享前置后命中", old_res["5km 横穿6G+离轴20°"].hit,
			"共享离架前置点应闭合历史边界带")
	_check("20°离轴边界带：NEW 命中", new_res["5km 横穿6G+离轴20°"].hit,
			"正式 FOV 90 参数保持命中")

	print("\n══ 裁决摘要 ══")
	var old_hits := 0
	var new_hits := 0
	for k in old_res:
		if old_res[k].hit: old_hits += 1
		if new_res[k].hit: new_hits += 1
	print("  OLD 参数总命中 %d/%d | NEW 参数总命中 %d/%d（参数贡献 = %+d）" % [
		old_hits, old_res.size(), new_hits, new_res.size(), new_hits - old_hits])
	print("  理想几何(≤5km,0°离轴) NEW: %d/4 | 远距(8-11km) NEW: %d/3 | crank40°: %s" % [
		ideal_hits,
		int(new_res["8km 尾追直线"].hit) + int(new_res["8km 横穿6G"].hit) + int(new_res["11km 尾追直线"].hit),
		"HIT" if new_res["5km 横穿6G+crank40°"].hit else "MISS"])

	_mm.free()
	print("──────── 结果：%d 通过 / %d 失败 ────────" % [_pass, _fail])
	print("══════════════════════════════════════════════════\n")


## 单场仿真：真实 Missile 节点 + 手动步进物理；目标按模式运动
func _simulate(_label: String, dist_m: float, tgt_mode: String, off_axis_deg: float,
		fov: float, max_g: float) -> Dictionary:
	var msl: MissileParams = load("res://resources/default_missile.tres").duplicate()
	msl.seeker_fov = fov
	msl.max_g = max_g

	# 目标在正北 dist 处
	var tgt: Aircraft = load("res://scripts/aircraft.gd").new()
	tgt.team = 1
	tgt.global_position = Vector2(0, -dist_m * PPM)
	tgt.speed = TGT_SPEED
	match tgt_mode:
		"flee":
			tgt.heading = 0.0            # 背向发射机直线逃
		"beam6g":
			tgt.heading = PI / 2.0       # 初始横穿（垂直 LOS），随后持续 6G 左转

	# 发射机：原点，机头指向目标 ± 离轴
	var src: Aircraft = load("res://scripts/aircraft.gd").new()
	src.team = 0
	src.global_position = Vector2.ZERO
	src.heading = deg_to_rad(off_axis_deg)   # LOS 朝北 = 0
	src.speed = 250.0
	src.params = AircraftParams.new()

	var m: Missile = _mm.spawn_missile(src, tgt, msl)

	var min_dist := INF
	var t := 0.0
	var hit := false
	var why := ""
	while t < msl.max_lifetime + 0.5:
		t += DT
		# 目标运动
		if tgt_mode == "beam6g":
			tgt.heading += (9.81 * 6.0 / TGT_SPEED) * DT  # 6G 持续转
		tgt.global_position += Vector2(sin(tgt.heading), -cos(tgt.heading)) * TGT_SPEED * PPM * DT
		# 真实导弹物理
		m._physics_process(DT)
		if not m.is_active:
			why = "provider 失效"
			break
		var d_m: float = m.global_position.distance_to(tgt.global_position) / PPM
		min_dist = minf(min_dist, d_m)
		if d_m < HIT_DIST_M:
			hit = true
			break
	if not hit and why == "":
		if m._guidance_ever_lost:
			why = "FOV 丢锁"
		elif min_dist > dist_m * 0.5:
			why = "追不上(能量/几何)"
		else:
			why = "PN 极限(min %.0fm)" % min_dist

	m.queue_free()
	_mm.remove_child(m) if m.get_parent() == _mm else null
	src.free()
	tgt.free()
	return {"hit": hit, "min_dist": min_dist if min_dist != INF else -1.0, "t": t, "why": why}


func _check(name: String, got: bool, note: String) -> void:
	if got: _pass += 1
	else: _fail += 1
	print("  %s %-28s — %s" % ["✓" if got else "✗", name, note])
