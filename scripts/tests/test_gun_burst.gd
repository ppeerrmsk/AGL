extends RefCounted

## 机炮梭射节奏回归测试（specs/weapons/gun-burst-fire.md）
## 契约：
##   1. 梭结构：burst_count 发按 intra 密集出弹，然后梭间 CD（fire_rate 越高两者越短）
##   2. 平均射速守恒：长期出弹速率 = fire_rate（DPS/弹药消耗与旧匀速点射一致）
##   3. 梭承诺：火控窗口只开一帧也打完整梭（根治"一闪只漏一发孤弹"）
##   4. 硬中止：evasion / 弹尽 / 目标被毁 立即掐断残梭
## 运行：godot --headless --path . -- --bench=gun_burst（或 --bench=all）

var _pass := 0
var _fail := 0

const DT := 1.0 / 60.0


## 计数用 bullet_manager 桩：只记录出弹时刻
class BulletStub:
	extends Node2D
	var shot_times: Array[float] = []
	var now: float = 0.0
	# 签名对齐真身 BulletManager.spawn_bullet（含 is_ciws / visual_only / life_seconds 可选参）
	func spawn_bullet(_pos: Vector2, _dir: float, _speed: float, _shooter: Node, _dmg: float, _is_ciws: bool = false, _visual_only: bool = false, _life: float = 2.0) -> void:
		shot_times.append(now)


func run() -> void:
	print("\n════════ 机炮梭射节奏（burst 结构 + 承诺 + 守恒） ════════")

	# ── 1. 梭结构：600 发/分 × burst 10 → 梭内 ~0.03s / 梭间 ~0.70s ──
	var ac := _make_shooter(600.0, 10)
	var stub: BulletStub = ac.bullet_manager
	ac.is_firing = true
	_tick(ac, 3.0)
	var t := stub.shot_times
	var burst1_span := t[9] - t[0] if t.size() >= 10 else INF
	var gap := t[10] - t[9] if t.size() >= 11 else INF
	_check("首梭 10 发密集出弹", t.size() >= 11 and burst1_span < 0.40,
			"10 发跨时 %.2fs（匀速点射会是 0.90s）" % burst1_span)
	_check("梭间 CD ≈ 0.70s", absf(gap - 0.70) < 0.10, "gap=%.2fs" % gap)
	# 平均射速守恒：3s @600/分 ≈ 30 发
	_check("平均射速守恒（600/分 → 3s ≈ 30 发）", absf(t.size() - 30) <= 2, "实际 %d 发" % t.size())
	_free(ac)

	# ── 2. 射速↑ → 梭内更密 + 梭间更短（用户两条铁律） ──
	var ac2 := _make_shooter(1800.0, 10)
	var stub2: BulletStub = ac2.bullet_manager
	ac2.is_firing = true
	_tick(ac2, 3.0)
	var t2 := stub2.shot_times
	var burst2_span := t2[9] - t2[0] if t2.size() >= 10 else INF
	var gap2 := t2[10] - t2[9] if t2.size() >= 11 else INF
	_check("1800/分：梭内更密", burst2_span < burst1_span - 0.05,
			"10 发跨时 %.2fs（600/分时 %.2fs）" % [burst2_span, burst1_span])
	_check("1800/分：梭间 CD 更短 ≈ 0.17s", gap2 < gap - 0.3 and absf(gap2 - 0.167) < 0.08,
			"gap=%.2fs（600/分时 %.2fs）" % [gap2, gap])
	_check("平均射速守恒（1800/分 → 3s ≈ 90 发）", absf(t2.size() - 90) <= 5, "实际 %d 发" % t2.size())
	_free(ac2)

	# ── 3. 梭承诺：is_firing 只开 1 帧 → 仍打完整梭 ──
	var ac3 := _make_shooter(600.0, 10)
	var stub3: BulletStub = ac3.bullet_manager
	ac3.is_firing = true
	_tick(ac3, DT)          # 一帧：梭起始 + 第一发
	ac3.is_firing = false   # 火控窗口立即关闭
	_tick(ac3, 2.0)
	_check("梭承诺：窗口开 1 帧仍打完整梭", stub3.shot_times.size() == 10,
			"出弹 %d 发（旧实现只有 1 发孤弹）" % stub3.shot_times.size())
	_free(ac3)

	# ── 4. evasion 掐断残梭 ──
	var ac4 := _make_shooter(600.0, 10)
	var stub4: BulletStub = ac4.bullet_manager
	ac4.is_firing = true
	_tick(ac4, DT * 6)      # ~3 发出膛
	var before := stub4.shot_times.size()
	ac4.evasion_mode = true
	ac4.is_firing = false   # auto_gun_scan 的规避静默会这么做
	_tick(ac4, 1.0)
	_check("evasion 立即掐断残梭", stub4.shot_times.size() == before and before < 10,
			"掐断前 %d 发，掐断后无增发" % before)
	_free(ac4)

	# ── 5. 弹尽掐断（burst 10 但只剩 4 发） ──
	var ac5 := _make_shooter(600.0, 10)
	var stub5: BulletStub = ac5.bullet_manager
	ac5.ammo = 4
	ac5.is_firing = true
	_tick(ac5, 2.0)
	_check("弹尽掐断（仅 4 发弹药）", stub5.shot_times.size() == 4,
			"出弹 %d 发" % stub5.shot_times.size())
	_free(ac5)

	# ── 6. 目标被毁掐断残梭（回归：Verge 击杀 UAV-09 后 ~5 发对空放枪，log 204752）──
	# 梭承诺打满 10 发，但目标 5 发内被击毁 → 剩余弹绝不能沿机头喷入空域。
	var ac6 := _make_shooter(600.0, 10)
	var stub6: BulletStub = ac6.bullet_manager
	var tgt6 := CombatUnit.new()   # 敌方目标桩：只需 is_destroyed / global_position
	tgt6.team = 0
	tgt6.global_position = Vector2(0, -300)
	ac6.combat_target = tgt6
	ac6.is_firing = true
	_tick(ac6, DT * 6)             # ~3 发出膛，梭仍承诺中
	var before6 := stub6.shot_times.size()
	tgt6.is_destroyed = true       # 目标被这一梭打死
	ac6.is_firing = false          # _apply_tactical_plan 下一帧会这么写（aim_ok=false）
	_tick(ac6, 1.0)
	_check("目标被毁掐断残梭", stub6.shot_times.size() == before6 and before6 < 10,
			"击毁前 %d 发，击毁后无增发（旧实现会补喷 ~%d 发对空）" % [before6, 10 - before6])
	tgt6.free()
	_free(ac6)

	print("──────── 结果：%d 通过 / %d 失败 ────────" % [_pass, _fail])
	print("══════════════════════════════════════════════════\n")


func _tick(ac: Aircraft, seconds: float) -> void:
	var stub: BulletStub = ac.bullet_manager
	var steps := int(round(seconds / DT))
	for i in range(steps):
		stub.now += DT
		AircraftWeapons.update_gun(ac, DT)


func _make_shooter(fire_rate: float, burst_count: int) -> Aircraft:
	var ac: Aircraft = load("res://scripts/aircraft.gd").new()
	ac.team = 1  # 敌方：绕开玩家侧 regen/减伤窗口分支，纯测节奏
	ac.heading = 0.0
	ac.global_position = Vector2.ZERO
	var p = AircraftParams.new()
	var g = GunParams.new()
	g.fire_rate = fire_rate
	g.burst_count = burst_count
	g.muzzle_velocity = 1000.0
	p.gun = g
	ac.params = p
	ac.ammo = 10000
	ac.bullet_manager = BulletStub.new()
	return ac


func _free(ac: Aircraft) -> void:
	ac.bullet_manager.free()
	ac.free()


func _check(name: String, got: bool, note: String) -> void:
	if got: _pass += 1
	else: _fail += 1
	print("  %s %-28s — %s" % ["✓" if got else "✗", name, note])
