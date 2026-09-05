extends RefCounted

## 无头转弯物理仿真测试（2026-06-07）
## 目的：自动复现/量化"高G急转时机身颤抖"bug，无需进引擎手测。
##
## 运行（经 BenchRunner，正常项目上下文 → autoload 可用 → aircraft_physics 可编译）：
##   bench/run.cmd turn_physics 1 180 Shadow Headless
## `_run_sweep` 保留供临时调参接线；正式回归只走上述受锁 wrapper 命令。
##
## 做法：裸构造 Aircraft 实例（不入树、不触发 _ready），手填物理字段，逐帧调
## AircraftPhysics 静态函数，记录 heading/bank，分别统计：
## 1) 大坡度跨零反转；2) 同一侧快速收坡/加坡造成的 ≥0.75G 峰谷。
## 两种用户可见抽搐都进入自动失败门；低幅慢变化的“呼吸”只保留诊断计数。

const DT := 1.0 / 60.0

static var VERBOSE := true
static var QUIET := false   ## 扫参时静默逐条 print，只回收 net_sign
static var _last_sign := 0
static var _last_breath := 0
static var _last_g_twitch := 0
static var _breath_total := 0  ## 扫参用：累计同向呼吸（次要优化目标）
static var _gate_failures := 0

var _fail := 0


const PARAM_SET := [
	"res://resources/playable_f14_base.tres",   # 对照(玩家F-14，之前测平滑)
	"res://resources/enemy_su27.tres",          # 实战抖动机型
	"res://resources/enemy_f86.tres",           # 慢速机，SEAM-012 最明显
	"res://resources/enemy_mig23.tres",
]

func run() -> void:
	_fail = 0
	_gate_failures = 0
	var args := PackedStringArray()
	args.append_array(OS.get_cmdline_args())
	args.append_array(OS.get_cmdline_user_args())
	if args.has("--pd-sweep"):
		_run_sweep()
		return
	print("\n════════ 转弯物理仿真测试 ════════")
	var grand := 0
	for path in PARAM_SET:
		var params: Resource = load(path)
		if params == null:
			print("✗ 无法加载: ", path)
			continue
		print("── 机型: %s ──" % str(params.display_name))
		grand += _run_all(params)
	_fail = _gate_failures
	print("──────── 全机型总净 buzz = %d ────────" % grand)
	print("──────── 自动失败门 = %d ────────" % _fail)
	print("════════════════════════════════\n")


## 跑全场景，返回总净 buzz
static func _run_all(params: Resource) -> int:
	var t := 0
	t += _run_case("  J-turn 180°", params, PI, true)
	t += _run_case("  90° 急转", params, PI * 0.5, true)
	t += _run_case("  30° 缓转", params, PI / 6.0, true)
	t += _run_pursuit("  追转圈目标800", params, 800.0)
	t += _run_pursuit("  追转圈目标500(紧)", params, 500.0)
	t += _run_pursuit("  追转圈目标350(极紧)", params, 350.0)
	t += _run_s_turn("  S转(每0.8s反向)", params, 48)
	t += _run_s_turn("  S转(每0.5s反向)", params, 30)
	t += _run_pursuit_aitick("  AI分频追500(6f)", params, 500.0, 6)
	t += _run_pursuit_aitick("  AI分频追350(6f)", params, 350.0, 6)
	t += _run_pursuit_aitick("  AI分频追350(3f)", params, 350.0, 3)
	t += _run_pursuit("  爬升跟随移动航点800", params, 800.0, false, true)
	t += _run_near_target("  近目标200(战斗)", params, 200.0, true)
	return t


## PD 增益扫参：对每组 (kd_scale, ff, los_alpha) 跑全机型全场景，打印总净 buzz 表。
## 找出跨机型最稳的临界阻尼组合。
func _run_sweep() -> void:
	print("\n════════ PD 扫参（总净 buzz，越小越平滑）════════")
	QUIET = true
	AircraftPhysics.PD_KD_MAX = 2.5      # 放开 kd 上限，让 kd_scale 真正生效
	AircraftPhysics.TURN_RATE_FILT_ALPHA = 0.30
	# 扫 kp × kd_scale（ff=0，前馈实测各形态均为害）。单元格=符号反转/同向呼吸。
	# 符号反转(用户痛点"大坡反转")全场景须 ≤2(总≈28~33)；同向呼吸为结构性次要量，仅供参考。
	AircraftPhysics.PD_LOS_FF = 0.0
	AircraftPhysics.TURN_RATE_FILT_ALPHA = 0.30
	var kps := [1.5, 2.0, 2.5, 3.0, 4.0]
	var kd_scales := [2.0, 3.0, 4.0, 5.0]
	print("ff=0 D低通=0.30  单元格=符号反转/同向呼吸  (行=kp 列=kd_scale)")
	print("  kp\\kd_scale  | " + "  ".join(kd_scales.map(func(x): return "%8.1f" % x)))
	for kp in kps:
		var row := "  kp=%4.1f      |" % kp
		for kd_scale in kd_scales:
			AircraftPhysics.PD_KP_BASE = kp
			AircraftPhysics.PD_KD_SCALE = kd_scale
			_breath_total = 0
			var sign_total := 0
			for path in PARAM_SET:
				var params: Resource = load(path)
				if params:
					sign_total += _run_all(params)
			row += " %4d/%-4d" % [sign_total, _breath_total]
		print(row)
	print("════════════════════════════════\n")


static func _make_ac(params: Resource):
	var ac = load("res://scripts/aircraft.gd").new()
	ac.params = params
	ac.heading = 0.0
	ac.bank_angle = 0.0
	ac.altitude = 5000.0
	ac.speed = params.cruise_speed / 3.6
	ac.target_speed_kmh = params.cruise_speed
	ac.g_load = 1.0
	ac.is_stalled = false
	ac.tactical_aggression = 1.0
	ac.position = Vector2.ZERO
	return ac


static func _run_case(name: String, params: Resource, turn_angle: float, in_combat: bool) -> int:
	var ac = _make_ac(params)
	var tgt_dir := Vector2(sin(turn_angle), -cos(turn_angle))
	ac.target_position = ac.position + tgt_dir * 3000.0
	var dummy = null
	if in_combat:
		dummy = _make_ac(params)
		dummy.position = ac.target_position
		ac.combat_target = dummy
	var banks: Array = []
	var hdgs: Array = []
	for i in range(360):
		_step(ac)
		banks.append(ac.bank_angle)
		hdgs.append(ac.heading)
	var nb := _report(name, hdgs, banks)
	if dummy:
		dummy.free()
	ac.free()
	return nb


static func _run_s_turn(name: String, params: Resource, switch_frames: int) -> int:
	var ac = _make_ac(params)
	var dummy = _make_ac(params)
	ac.combat_target = dummy
	var banks: Array = []
	var hdgs: Array = []
	for i in range(600):
		var phase := int(i / switch_frames) % 2
		var ang := (PI * 0.5) if phase == 0 else (-PI * 0.5)
		var d := Vector2(sin(ac.heading + ang), -cos(ac.heading + ang))
		ac.target_position = ac.position + d * 3000.0
		dummy.position = ac.target_position
		_step(ac)
		banks.append(ac.bank_angle)
		hdgs.append(ac.heading)
	# S 转每 switch_frames 帧命令反向一次 → 预期 ~600/switch_frames 次"应有"反向，
	# 只统计超出这个基线的多余 buzz。
	var nb := _report(name, hdgs, banks, int(600.0 / float(switch_frames)))
	dummy.free()
	ac.free()
	return nb


## 真实战斗仿真：目标以固定半径转圈，本机用 combat 路径追击。
## target_position 跟随移动目标 → 持续诱发 target_heading 变化（实战颤抖最常出现的场景）。
static func _run_pursuit(
		name: String, params: Resource, radius: float,
		in_combat: bool = true, climb: bool = false) -> int:
	var ac = _make_ac(params)
	var dummy = _make_ac(params)
	if in_combat:
		ac.combat_target = dummy
	if climb:
		ac.target_altitude = 10000.0
	# 目标起始在前方 1500px，绕一个圆心转圈
	var center := Vector2(radius, -1500.0)
	var tgt_spd_ms: float = params.cruise_speed / 3.6
	var omega: float = tgt_spd_ms * CombatUnit.PIXELS_PER_METER / radius  # 角速度 rad/s
	var banks: Array = []
	var hdgs: Array = []
	for i in range(600):  # 10 秒
		var ang: float = omega * float(i) * DT
		dummy.position = center + Vector2(cos(ang), sin(ang)) * radius
		ac.target_position = dummy.position
		_step(ac)
		banks.append(ac.bank_angle)
		hdgs.append(ac.heading)
	var nb := _report(name, hdgs, banks)
	dummy.free()
	ac.free()
	return nb


## 实战最接近的隔离复现：紧转圈 bandit + 本机以 AI 分频(10Hz)重算 lead 点。
## target_position 每 ai_period 帧才跳一次到"目标当前位置 + 前置预测"，期间冻结 →
## heading_diff 走陈旧再跳变 → 正是 P 控制器过冲翻 bank 的实战诱因。
## 平滑控制器应吸收这种参考跳变；欠阻尼控制器会颤抖。
static func _run_pursuit_aitick(name: String, params: Resource, radius: float, ai_period: int) -> int:
	var ac = _make_ac(params)
	var dummy = _make_ac(params)
	ac.combat_target = dummy
	var center := Vector2(radius, -1500.0)
	var tgt_spd_ms: float = params.cruise_speed / 3.6
	var omega: float = tgt_spd_ms * CombatUnit.PIXELS_PER_METER / radius
	var lead_s: float = 0.6  # 前置预测秒数（模拟 pure_pursuit_lead）
	var banks: Array = []
	var hdgs: Array = []
	for i in range(600):
		var ang: float = omega * float(i) * DT
		dummy.position = center + Vector2(cos(ang), sin(ang)) * radius
		if i % ai_period == 0:
			# AI tick：重算 lead 点（目标当前位置沿其切向外推 lead_s 秒）
			var tang := Vector2(-sin(ang), cos(ang)) * (tgt_spd_ms * CombatUnit.PIXELS_PER_METER)
			ac.target_position = dummy.position + tang * lead_s
		_step(ac)
		banks.append(ac.bank_angle)
		hdgs.append(ac.heading)
	var nb := _report(name, hdgs, banks)
	dummy.free()
	ac.free()
	return nb


## 逼近近距目标点：目标固定在侧前方近距，keep_target_on_arrival 防清除，
## 飞机会绕着这个近点打转 —— 方位角对位置极敏感 → target_heading 发散 → bank 颤抖。
## 这是真实战斗(逼近 lead 点)/巡航(逼近 waypoint)颤抖的隔离复现。
static func _run_near_target(name: String, params: Resource, dist: float, in_combat: bool) -> int:
	var ac = _make_ac(params)
	ac.keep_target_on_arrival = true
	var tgt_pos: Vector2 = Vector2(dist * 0.7, -dist * 0.7)  # 右前方 45°(ac 起点在原点)
	ac.target_position = tgt_pos
	var dummy = null
	if in_combat:
		dummy = _make_ac(params)
		dummy.position = tgt_pos
		ac.combat_target = dummy
	var banks: Array = []
	var hdgs: Array = []
	for i in range(360):
		if in_combat:
			ac.target_position = dummy.position  # 战斗：每帧重指目标(模拟 combat_tracking)
		_step(ac)
		banks.append(ac.bank_angle)
		hdgs.append(ac.heading)
	var nb := _report(name, hdgs, banks)
	if dummy:
		dummy.free()
	ac.free()
	return nb


static func _step(ac) -> void:
	AircraftPhysics.update_target_heading(ac)
	AircraftPhysics.update_bank(ac, DT)
	AircraftPhysics.update_heading(ac, DT)
	AircraftPhysics.update_speed(ac, DT)
	AircraftPhysics.update_stall(ac)
	AircraftPhysics.update_altitude(ac, DT)
	AircraftPhysics.update_g_load(ac)
	AircraftPhysics.apply_movement(ac, DT)


## 幅度感知振荡指标：找 bank 的局部极值（速度反向点），只统计"从上一极值到本极值
## 摆幅 ≥ MIN_SWING_DEG"的真实来回，忽略顶在 cap 的数值微抖动。
## 颤抖 = 短时间内多次大摆幅反向。返回净 buzz（扣除命令式反向基线）。
static func _report(name: String, hdgs: Array, banks: Array, expected: int = 0) -> int:
	const MIN_SWING_DEG := 8.0
	var big_reversals := 0
	var last_ext: float = banks[0]      # 上一个极值
	var cur_dir := 0.0                    # 当前 bank 运动方向
	var run_peak: float = banks[0]        # 当前单调段的峰值
	for i in range(1, banks.size()):
		var dv: float = banks[i] - banks[i - 1]
		if absf(dv) < 0.0002:
			continue
		var d := signf(dv)
		if cur_dir == 0.0:
			cur_dir = d
		elif d != cur_dir:
			# 方向反转：结算上一段摆幅
			var swing := rad_to_deg(absf(run_peak - last_ext))
			if swing >= MIN_SWING_DEG:
				big_reversals += 1
			last_ext = run_peak
			cur_dir = d
		run_peak = banks[i]
	# 命令式反向（S 转）有预期基线；只把超出基线的算作 buzz
	var net_buzz: int = maxi(0, big_reversals - expected)
	# ── 符号反转指标（用户关心的"大坡反转"：机身从硬压一侧猛翻到硬压另一侧）──
	# 统计 bank 过零、且过零前后两侧极值都 ≥ SIGN_THRESH 的次数。同向幅度"呼吸"不计入。
	var sign_rev := _count_sign_reversals(banks)
	var net_sign: int = maxi(0, sign_rev - expected)
	_last_sign = net_sign
	_last_breath = maxi(0, net_buzz - net_sign)
	# G 是 bank 的非线性映射，80°附近几度变化就会跳数个 G；只数 0.2 秒内完成、
	# 摆幅 ≥0.75G 的快速局部极值反转，避免把正常滚入/滚出也误判成用户报告的抽搐。
	const MIN_G_SWING := 0.75
	const MAX_G_TWITCH_FRAMES := 12
	var g_reversals := 0
	var last_g_ext := absf(1.0 / cos(banks[0]))
	var last_g_ext_i := 0
	var cur_g_dir := 0.0
	var run_g_peak := last_g_ext
	for i in range(1, banks.size()):
		var g_now := absf(1.0 / cos(banks[i]))
		var g_prev := absf(1.0 / cos(banks[i - 1]))
		var dv := g_now - g_prev
		if absf(dv) < 0.002:
			continue
		var d := signf(dv)
		if cur_g_dir == 0.0:
			cur_g_dir = d
		elif d != cur_g_dir:
			if absf(run_g_peak - last_g_ext) >= MIN_G_SWING \
					and i - 1 - last_g_ext_i <= MAX_G_TWITCH_FRAMES:
				g_reversals += 1
			last_g_ext = run_g_peak
			last_g_ext_i = i - 1
			cur_g_dir = d
		run_g_peak = g_now
	_last_g_twitch = g_reversals
	_breath_total += _last_breath
	if QUIET:
		return net_sign   # 扫参/总分以"符号反转"为准（用户真正的 bug 度量）
	var smooth := net_sign <= 2 and (expected > 0 or _last_g_twitch <= 2)
	var verdict := "平滑 ✓" if smooth else "滚转/G 抽搐 ✗"
	var exp_str := (" (基线%d)" % expected) if expected > 0 else ""
	print("  [%-20s] 符号反转=%-2d%s 同向呼吸=%-2d G抽搐=%-2d 末bank=%.0f° → %s" % [
		name, net_sign, exp_str, maxi(0, net_buzz - net_sign), _last_g_twitch,
		rad_to_deg(banks[banks.size() - 1]), verdict])
	if net_sign > 2:
		_gate_failures += 1
		printerr("[turn_physics] FAIL %s: 大坡反转 %d > 2" % [name.strip_edges(), net_sign])
	# 非命令式转弯允许一次滚入/滚出；超过 2 次大幅 G 极值反转即是持续抽搐。
	if expected == 0 and _last_g_twitch > 2:
		_gate_failures += 1
		printerr("[turn_physics] FAIL %s: G 抽搐 %d > 2" % [name.strip_edges(), _last_g_twitch])
	if (net_sign > 2 or _last_g_twitch > 2) and VERBOSE:
		var line := "      轨迹(每6帧 bank°): "
		for i in range(0, banks.size(), 6):
			line += "%d " % int(rad_to_deg(banks[i]))
		print(line)
	return net_sign


## "大坡反转"计数：bank 符号翻转，且翻转前后两侧的局部极值幅度都 ≥ SIGN_THRESH。
## 这是用户真正抱怨的"机身从硬压左猛翻硬压右"，区别于同向的幅度呼吸。
static func _count_sign_reversals(banks: Array) -> int:
	const SIGN_THRESH := 0.26   # ≈15°：两侧都压过此角才算一次大坡反转
	var count := 0
	var last_strong_sign := 0.0   # 上一次达到 ±SIGN_THRESH 的符号
	for b in banks:
		if absf(b) >= SIGN_THRESH:
			var s := signf(b)
			if last_strong_sign != 0.0 and s != last_strong_sign:
				count += 1
			last_strong_sign = s
	return count
