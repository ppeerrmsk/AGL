extends RefCounted

## POLTERGEIST 队级战术（死锁单机换手）回归测试
## 权威源：docs/specs/bosses/poltergeist-squadron.md
##
## 契约：
##   1. nose_off_deg 纯几何：正前 ~0° / 正侧 ~90° / 正后 ~180°
##   2. 死锁换手：共速绕圈持续达阈值 → 恰好【1 架】被派去换手（爬升 HIGH + 拉开）
##   3. 同时换手上限：任一刻正在换手的架数 ≤ MAX_CONCURRENT_RESET（灵魂：绝不同时变慢）
##   4. 排除项：无 combat_target（起飞保护期）/ 无敌 的成员不参与死锁判定
## 运行：godot --headless --path . -- --bench=poltergeist_tactics（或 --bench=all）

var _pass := 0
var _fail := 0


func run() -> void:
	print("\n════════ POLTERGEIST 死锁换手 ════════")
	_test_nose_off_pure()
	_test_relay_break()
	_test_max_concurrent_and_exclusions()
	print("──────── 结果：%d 通过 / %d 失败 ────────" % [_pass, _fail])


# ── 1. 纯几何 ──
func _test_nose_off_pure() -> void:
	print("── A. nose_off_deg 纯函数 ──")
	var P = PoltergeistTactics
	var m := Aircraft.new()
	m.global_position = Vector2.ZERO
	m.heading = 0.0   # 机头朝北（0=北）

	# 目标在正北（正前方）→ 偏角 0
	_check("正前方 ~0°", P.nose_off_deg(m, Vector2(0, -1000)) < 0.5,
			"%.1f°" % P.nose_off_deg(m, Vector2(0, -1000)))
	# 目标在正东（正右侧）→ 偏角 ~90
	_check("正侧方 ~90°", absf(P.nose_off_deg(m, Vector2(1000, 0)) - 90.0) < 0.5,
			"%.1f°" % P.nose_off_deg(m, Vector2(1000, 0)))
	# 目标在正南（正后方）→ 偏角 ~180
	_check("正后方 ~180°", absf(P.nose_off_deg(m, Vector2(0, 1000)) - 180.0) < 0.5,
			"%.1f°" % P.nose_off_deg(m, Vector2(0, 1000)))
	# 同点退化安全
	_check("同点退化 →0", P.nose_off_deg(m, Vector2.ZERO) == 0.0, "不崩")
	m.free()


# ── 2. 死锁换手：共速绕圈 → 恰好 1 架换手 ──
func _test_relay_break() -> void:
	print("── B. 死锁 → 单机换手（其余继续压）──")
	var P = PoltergeistTactics
	var sq := _make_squad()
	# 两架都在玩家附近、机头垂直于连线（永远咬不住 = tp_brg ±90° 死锁）
	var a := _orbiting_member(sq, Vector2(0, -800))   # 玩家北侧 1600m，机头朝东
	var b := _orbiting_member(sq, Vector2(0, 800))    # 玩家南侧 1600m，机头朝东

	var tac := P.new()
	tac.setup(sq)
	tac.start()

	# 阈值前：连续采样但未达 DEADLOCK_HOLD_S → 无人换手
	# HOLD=4.0 / SAMPLE=0.5 → 需 8 次采样才达标；先跑 7 次
	for _i in range(7):
		tac.update(0.5)
	_check("未达持续阈值不换手", _count_resetting(tac, sq) == 0,
			"7×0.5s=3.5s < 4.0s，还没人被拽出来")

	# 第 8 次采样 → 达标 → 派发换手
	tac.update(0.5)
	_check("达标后恰好 1 架换手", _count_resetting(tac, sq) == 1,
			"正在换手 %d 架（灵魂：绝不两架一起变慢）" % _count_resetting(tac, sq))

	# 换手机被顶到 HIGH 档（爬升攒能量）
	var mover := a if tac._reset_timer.has(a.get_instance_id()) else b
	_check("换手机爬升到 HIGH", mover.target_altitude_tier == CombatUnit.AltitudeTier.HIGH,
			"target_tier=%d" % mover.target_altitude_tier)

	_free_squad(sq, [a, b])


# ── 3. 同时上限 + 排除项 ──
func _test_max_concurrent_and_exclusions() -> void:
	print("── C. 同时换手上限 & 排除项 ──")
	var P = PoltergeistTactics
	var sq := _make_squad()
	var a := _orbiting_member(sq, Vector2(0, -800))
	var b := _orbiting_member(sq, Vector2(0, 800))

	var tac := P.new()
	tac.setup(sq)
	tac.start()

	# 跑足够长时间让死锁反复达标；无论怎么跑，同时换手数永远 ≤ 上限
	var max_seen := 0
	for _i in range(40):
		tac.update(0.5)
		max_seen = maxi(max_seen, _count_resetting(tac, sq))
	_check("同时换手数不超上限", max_seen <= P.MAX_CONCURRENT_RESET,
			"峰值 %d ≤ %d" % [max_seen, P.MAX_CONCURRENT_RESET])
	_free_squad(sq, [a, b])

	# 排除项：无 combat_target（起飞保护期）的成员永不进入死锁
	var sq2 := _make_squad()
	var c := _orbiting_member(sq2, Vector2(0, -800))
	c.combat_target = null   # 模拟起飞保护期
	var tac2 := P.new()
	tac2.setup(sq2)
	tac2.start()
	for _i in range(12):
		tac2.update(0.5)
	_check("无 combat_target 不被换手", _count_resetting(tac2, sq2) == 0,
			"起飞保护期成员不该被拽去换手")
	_free_squad(sq2, [c])


# ══════════════════════════════════════════════
#  夹具
# ══════════════════════════════════════════════

func _make_squad() -> AceSquad:
	var sq := AceSquad.new()             # BossEncounter extends RefCounted → 自动释放
	sq.display_name = "TEST-PLTGST"
	sq.combat_phase_active = true
	var player := Aircraft.new()
	player.global_position = Vector2.ZERO
	sq._player = player
	sq.members = []
	return sq

## 造一架"共速绕圈"成员：贴近玩家、机头朝东（垂直于连线 → 永远咬不住）
func _orbiting_member(sq: AceSquad, offset_px: Vector2) -> Aircraft:
	var m := Aircraft.new()
	m.global_position = offset_px        # 800px = 1600m，在 DEADLOCK_MAX_DIST(4000m) 内
	m.heading = PI * 0.5                 # 朝东；连线是南北 → 机头偏角 ~90° > 55°
	m.combat_target = sq._player
	sq.members.append(m)
	return m

func _count_resetting(tac, sq: AceSquad) -> int:
	var n := 0
	for m in sq.members:
		if tac._reset_timer.get((m as Aircraft).get_instance_id(), 0.0) > 0.0:
			n += 1
	return n

func _free_squad(sq: AceSquad, members: Array) -> void:
	for m in members:
		(m as Aircraft).free()
	if is_instance_valid(sq._player):
		sq._player.free()


func _check(label: String, ok: bool, detail: String = "") -> void:
	if ok:
		_pass += 1
		print("  ✅ %s" % label)
	else:
		_fail += 1
		print("  ❌ %s  — %s" % [label, detail])
