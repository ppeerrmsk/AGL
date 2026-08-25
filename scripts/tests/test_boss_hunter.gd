extends RefCounted

## BOSS 猎手化 + Wraith 角色/执行失误 回归测试
## 权威源：specs/systems/boss-hunter-doctrine.md、specs/bosses/wraith-squadron.md、
##         specs/systems/ace-squadron-tier.md §2.2
##
## 契约：
##   1. PURSUE_UNIT verb：追会动的单位、【无抵达态】、目标失效自动释放、按间隔节流重取
##   2. 归巢已废除：AceSquad 状态机里不存在 ANCHOR_HOLD
##   3. 角色真实化：KNIGHT×2 + SNIPER×2；SNIPER 吃 BVR 站位带（4~6km），KNIGHT 不吃
##   4. 两个死 meta 已清除：combat_specialty（只写不读）/ f47_role（只读不写）
##   5. 热诱弹即命数：王牌 4 枚 × 每次 1 枚，且不自动装填
##   6. 执行失误：tier 标记同时开瞄准误差通路 + 写王牌枪法 0.85
##   7. 减速迟滞：进入治理区掷一次骰、迟滞期间不压速、离开治理区解除锁存
## 运行：godot --headless --path . -- --bench=boss_hunter（或 --bench=all）

var _pass := 0
var _fail := 0

class RadioMode extends Node:
	var _radio: RadioChatter = null


func run() -> void:
	print("\n════════ BOSS 猎手化 / Wraith 角色 / 执行失误 ════════")

	_test_pursue_verb()
	_test_no_anchor_hold()
	_test_ace_world_boundary()
	_test_ace_roles()
	_test_dead_metas_gone()
	_test_ace_flare_lives()
	_test_aim_error_opened()
	_test_decel_lag()
	_test_wraith_tactics_pure()
	_test_wraith_phase_machine()
	_test_wraith_cloak_cadence()
	_test_wraith_member_down_radio()
	_test_naval_engage_triggers()

	print("──────── 结果：%d 通过 / %d 失败 ────────" % [_pass, _fail])


func _test_wraith_member_down_radio() -> void:
	print("── J. WRAITH 首次减员无线电 ──")
	var mode := RadioMode.new()
	mode._radio = RadioChatter.new()
	mode._radio._ready()
	var squad := F47AceSquad.new()
	squad._scene_root = mode
	var member := Aircraft.new()
	member.callsign = "WRAITH-02"
	member.team = CombatUnit.TEAM_HOSTILE
	member.is_destroyed = true
	squad._on_member_destroyed(member)
	_check("首次减员由真实成员呼号入队", mode._radio.debug_queue_size() == 1, "")
	squad._on_member_destroyed(member)
	_check("同一战只播一次", mode._radio.debug_queue_size() == 1, "")
	member.free()
	squad = null
	mode._radio.free()
	mode.free()


func _test_wraith_cloak_cadence() -> void:
	print("── K. WRAITH cloak CD / 近距揭露 ──")
	var squad := F47AceSquad.new()
	var player := Aircraft.new()
	var member := Aircraft.new()
	player.team = CombatUnit.TEAM_PLAYER
	member.team = CombatUnit.TEAM_HOSTILE
	player.global_position = Vector2.ZERO
	member.global_position = Vector2(2000.0, 0.0)
	squad._player = player
	squad.members = [member]
	_check("cloak 严格 60s CD", is_equal_approx(squad.cloak_cycle, 60.0) \
			and is_zero_approx(squad.cloak_cycle_jitter), "无随机抖动")
	_check("cloak 渐变延长为 1s", is_equal_approx(squad.cloak_fade, 1.0), "")
	_check("Wraith 禁用导弹紧急绕 CD", not squad.cloak_emergency_enabled, "")
	squad._cloak_cd_timer = 0.1
	_check("CD 未归零不能使用", not squad._should_enter_cloak(), "剩余 0.1s")
	squad._cloak_cd_timer = 0.0
	_check("CD 归零且远距可使用", squad._should_enter_cloak(), "")
	squad._cloak_enter()
	squad._cloak_exit()
	_check("每次结束后重置 60s CD", is_equal_approx(squad._cloak_cd_timer, 60.0), "可重复使用")
	member.global_position = Vector2(SensorStealthController.PROXIMITY_REVEAL_PX - 1.0, 0.0)
	squad._cloak_cd_timer = 0.0
	_check("近距时禁止启动 cloak", not squad._should_enter_cloak(), "2000m 内强制显形")
	squad.squad_state = AceSquad.SquadState.CLOAK
	squad._cloak_remaining = 4.0
	_check("cloak 中进入近距圈提前显形",
		squad._decide_next_state(0.1) == AceSquad.SquadState.PURSUIT, "")
	squad.members.clear()
	member.free()
	player.free()
	squad = null


# ── 1. PURSUE_UNIT verb ──
func _test_pursue_verb() -> void:
	print("── A. PURSUE_UNIT 指令 ──")
	var tgt := Aircraft.new()
	tgt.global_position = Vector2(1000, 0)

	var d := AIDirective.pursue(tgt, 0.5)
	_check("工厂产出 PURSUE_UNIT", d.type == AIDirective.Type.PURSUE_UNIT,
			"type=%d" % d.type)
	_check("接近相武器冷", d.combat_disabled, "combat_disabled=true")
	_check("目标写入 params", d.params.get("target", null) == tgt, "params.target")
	_check("节流间隔可配", is_equal_approx(float(d.params["refresh_interval"]), 0.5), "0.5s")

	# 【无抵达态】—— PURSUE_UNIT 不得复用 FLY_TO_POINT 的 on_arrival 分派。
	# on_arrival 保持默认 RELEASE 且执行分支从不读它，是"追到了由上层裁定"的结构保证
	var d2 := AIDirective.pursue(tgt)
	_check("默认节流 0.5s", is_equal_approx(float(d2.params["refresh_interval"]), 0.5), "缺省值")

	# ── 执行分支：这才是"猎手真的会追"的证据 ──
	var hunter := Aircraft.new()
	hunter.global_position = Vector2.ZERO
	var ai := AIController.new()
	ai.aircraft = hunter
	ai.set_event_directive(AIDirective.pursue(tgt, 0.5))

	ai._process_directive(0.016)
	_check("首帧即锁定目标位置", hunter.target_position == Vector2(1000, 0),
			"target_position=%s" % str(hunter.target_position))

	# 节流：目标动了但没到重取间隔 → 仍飞旧快照点（避免每帧抖动打断转弯控制器）
	tgt.global_position = Vector2(1000, 3000)
	ai._process_directive(0.016)
	_check("节流内不重取", hunter.target_position == Vector2(1000, 0), "仍飞 0.5s 前的快照")

	# 走完节流间隔 → 重取新位置（追上会动的目标）
	ai._process_directive(0.5)
	_check("间隔到即重取新位置", hunter.target_position == Vector2(1000, 3000),
			"target_position=%s" % str(hunter.target_position))

	# 无抵达态：贴到目标身上也不得自行结束（"追到了"由上层接战触发器裁定）
	hunter.global_position = Vector2(1000, 3000)
	ai._process_directive(0.5)
	_check("贴脸也不自行结束", ai._directive != null and ai._directive.type == AIDirective.Type.PURSUE_UNIT,
			"无抵达态：不触发 on_arrival 分派")

	# 目标失效 → 自动释放，AI 无缝回归常规路由
	tgt.free()
	ai._process_directive(0.5)
	_check("目标失效自动释放", ai._directive == null, "野指针不得留在 params 里")

	ai.free()
	hunter.free()


# ── 2. 归巢已废除 ──
func _test_no_anchor_hold() -> void:
	print("── B. 归巢（ANCHOR_HOLD）已废除 ──")
	var names: Array = AceSquad.SquadState.keys()
	_check("状态机只剩三态", names.size() == 3, "现有 %s" % str(names))
	_check("不存在 ANCHOR_HOLD", not names.has("ANCHOR_HOLD"),
			"猎手无归巢：玩家跑多远都追")
	# 归巢半径常量也必须一并消失，否则下次有人会照着它再写一遍
	_check("ANCHOR_ENGAGEMENT_RADIUS 已删", not ("ANCHOR_ENGAGEMENT_RADIUS" in AceSquad),
			"leash 常量不得残留")


# ── 2.1 世界边缘收容（不是锚点 leash）──
func _test_ace_world_boundary() -> void:
	print("── B2. 王牌世界边缘收容 ──")
	var half := MapBoundary.world_half_px()
	var sq := AceSquad.new()
	var boss := Aircraft.new()
	var ai := AIController.new()
	ai.aircraft = boss
	boss.add_child(ai)
	boss._ai_ref = ai
	boss.callsign = "EDGE-01"
	boss.set_meta("category", "boss")
	# 新外圈只在真实边缘前 300px 收容；旧核心线（距真边缘 1000px）不再误触返场。
	boss.global_position = Vector2(
		-half + AceSquad.BOUNDARY_TRIGGER_PX - 10.0, 321.0)
	sq.members = [boss]
	sq.squad_state = AceSquad.SquadState.PURSUIT

	var recovery_pt := AceSquad.boundary_recovery_point(boss.global_position)
	_check("返场目标越过解除线",
			is_equal_approx(MapBoundary.distance_to_edge(recovery_pt), AceSquad.BOUNDARY_TARGET_MARGIN_PX),
			"edge=%.0fpx" % MapBoundary.distance_to_edge(recovery_pt))
	_check("先解除再触发抵达 HOLD",
			AceSquad.BOUNDARY_TARGET_MARGIN_PX - AceSquad.BOUNDARY_RECOVER_MARGIN_PX \
					> AceSquad.BOUNDARY_ARRIVAL_RADIUS_PX,
			"解除线与目标间距大于 arrival_radius")
	_check("返场点保留平行轴坐标", is_equal_approx(recovery_pt.y, 321.0),
			"不回 BOSS 锚点")

	var recovering := sq._update_boundary_recovery()
	_check("进入真实边缘转弯带即收容", recovering and sq._boundary_recovery_active,
			"edge=%.0fpx" % MapBoundary.distance_to_edge(boss.global_position))
	_check("下发真实 fly_to 返场", ai._directive != null \
			and ai._directive.type == AIDirective.Type.FLY_TO_POINT,
			"不用瞬移完成正常返场")
	_check("返场期间仍可交战", ai._directive != null and not ai._directive.combat_disabled,
			"只改导航，不给安全窗")

	# 模式级硬护栏不等越线，且不依赖玩家引用/encounter tick；也不得抢走返场 directive。
	boss.global_position = Vector2(-half + 20.0, 321.0)
	var touched_rail := SurvivorSpawner.enforce_boss_world_boundary(boss)
	_check("尚未越线即触发 40px 物理硬护栏", touched_rail \
			and is_equal_approx(MapBoundary.distance_to_edge(boss.global_position),
					SurvivorSpawner.BOUNDARY_HARD_CLAMP_MARGIN_PX),
			"edge=%.0fpx" % MapBoundary.distance_to_edge(boss.global_position))
	_check("模式级护栏不抢 BOSS directive", ai._directive != null,
			"只修物理事实，不接管战术")
	_check("触线后航向指向地图内", absf(angle_difference(boss.heading, PI * 0.5)) < 0.001,
			"左界应朝东")

	# 真正的每帧入口也必须在 player 缺失时继续守 BOSS；否则切控/阵亡窗口会再次漏出界。
	var rail_mode := Node2D.new()
	var rail_boss := Aircraft.new()
	rail_boss.team = CombatUnit.TEAM_HOSTILE
	rail_boss.set_meta("category", "boss")
	rail_boss.global_position = Vector2(-half + 10.0, -77.0)
	rail_mode.add_child(rail_boss)
	var rail_spawner := SurvivorSpawner.new()
	rail_spawner.mode = rail_mode
	rail_spawner.player_aircraft = null
	rail_spawner._update_boundary_discipline(0.016)
	_check("无玩家引用时模式级护栏仍生效",
			is_equal_approx(MapBoundary.distance_to_edge(rail_boss.global_position),
					SurvivorSpawner.BOUNDARY_HARD_CLAMP_MARGIN_PX),
			"edge=%.0fpx" % MapBoundary.distance_to_edge(rail_boss.global_position))
	rail_mode.free()
	rail_spawner.free()

	# 预测转弯失败越线：位置必须当帧回到边内 40px，航向朝东（左界的内侧）。
	boss.global_position = Vector2(-half - 500.0, 321.0)
	sq._update_boundary_recovery()
	_check("越线硬兜底回到边内 40px",
			is_equal_approx(MapBoundary.distance_to_edge(boss.global_position),
					AceSquad.BOUNDARY_HARD_CLAMP_MARGIN_PX),
			"edge=%.0fpx" % MapBoundary.distance_to_edge(boss.global_position))
	_check("越线后航向指向地图内", absf(angle_difference(boss.heading, PI * 0.5)) < 0.001,
			"左界应朝东")

	# 到达安全带后释放收容 directive；这证明它不是永久 leash / 归巢状态。
	boss.global_position = Vector2(-half + AceSquad.BOUNDARY_RECOVER_MARGIN_PX + 1.0, 321.0)
	var still_recovering := sq._update_boundary_recovery()
	_check("到达安全带即恢复自由追击", not still_recovering \
			and not sq._boundary_recovery_active and ai._directive == null,
			"无永久边界状态")

	# 非 BOSS 王牌支援同样继承 AceSquad，但撤离必须能物理飞出地图。
	boss.set_meta("category", "ace_support")
	boss.global_position = Vector2(-half - 500.0, 321.0)
	_check("ace_support 出界不被 BOSS 收容", not sq._update_boundary_recovery() \
			and ai._directive == null and MapBoundary.distance_to_edge(boss.global_position) < 0.0,
			"支援撤离仍归事件层管理")

	boss.free()


# ── 3. 角色真实化 ──
func _test_ace_roles() -> void:
	print("── C. KNIGHT / SNIPER 角色 ──")
	var sq := F47AceSquad.new()

	# 角色分配规则：前 2 架 KNIGHT，后 2 架 SNIPER（wraith spec §2.1）
	for i in range(4):
		var expect: int = AceSquad.AceRole.KNIGHT if i < 2 else AceSquad.AceRole.SNIPER
		var ac := Aircraft.new()
		var ai := AIController.new()
		ai.aircraft = ac
		ac.set_meta(AceSquad.ROLE_META, expect)
		sq._apply_role(ac, ai, expect)

		if expect == AceSquad.AceRole.KNIGHT:
			_check("KNIGHT#%d 机炮优先" % i, ac.prefer_gun_mode, "prefer_gun_mode=true")
			_check("KNIGHT#%d 被咬转身对抗" % i, not ai.bvr_only, "bvr_only=false（不脱离）")
		else:
			_check("SNIPER#%d 导弹优先" % i, not ac.prefer_gun_mode, "prefer_gun_mode=false")
			_check("SNIPER#%d 被咬拉开" % i, ai.bvr_only, "bvr_only=true")
			# 距离带 4000~6000 m。PIXELS_PER_METER=0.5 → 1px=2m
			var min_m: float = ai.bvr_standoff_min_px_override / CombatUnit.PIXELS_PER_METER
			var flee_m: float = ai.bvr_flee_distance_px_override / CombatUnit.PIXELS_PER_METER
			_check("SNIPER#%d 站位下限 4km" % i, is_equal_approx(min_m, 4000.0), "%.0f m" % min_m)
			_check("SNIPER#%d 拉开到 6km" % i, is_equal_approx(flee_m, 6000.0), "%.0f m" % flee_m)

		# tier 铁律：交战欲不得被角色调低（ace-squadron-tier §2.1，裁决见 wraith §2.2）
		_check("#%d 守 tier 交战欲下限" % i, ai.aggression >= 0.90, "aggression=%.2f" % ai.aggression)
		_check("#%d 守 tier 自保上限" % i, ai.self_preservation <= 0.25,
				"self_preservation=%.2f" % ai.self_preservation)
		_check("#%d 角色可回读" % i, AceSquad.role_of(ac) == expect, "role_of()")

		ai.free()
		ac.free()


# ── 4. 死 meta 已清除 ──
func _test_dead_metas_gone() -> void:
	print("── D. 两个死 meta 已清除 ──")
	var ac := Aircraft.new()
	var ai := AIController.new()
	ai.aircraft = ac

	# f47_role 曾是 is_boss_attacker 的兜底读取源，但【从来没有代码写过它】。
	# 现在兜底改读 ace_role —— 写进去必须真的生效，否则整条分支又变回死代码
	ac.set_meta(AceSquad.ROLE_META, AceSquad.AceRole.SNIPER)
	_check("角色 meta 驱动 is_boss_attacker", ai.is_boss_attacker(),
			"SNIPER → boss_attacker（此前读 f47_role，恒为假）")
	ac.remove_meta(AceSquad.ROLE_META)
	_check("无角色则不误判", not ai.is_boss_attacker(), "裸机 → false")

	# 旧 meta 名不得再被任何人写入
	_check("combat_specialty 不再写入", not ac.has_meta("combat_specialty"), "只写不读的死 meta")
	_check("f47_role 不再写入", not ac.has_meta("f47_role"), "只读不写的死 meta")

	ai.free()
	ac.free()


# ── 5. 热诱弹即命数 ──
func _test_ace_flare_lives() -> void:
	print("── E. 热诱弹即命数（4 命）──")
	var fp: FlareParams = load("res://resources/ace_flare.tres")
	_check("王牌专属 flare 资源存在", fp != null, "resources/ace_flare.tres")
	if fp == null:
		return
	_check("4 枚 = 4 条命", fp.max_flares == 4, "max_flares=%d" % fp.max_flares)
	_check("每次投放 1 枚", fp.burst_count == 1, "burst_count=%d（1 枚=1 命严格对应）" % fp.burst_count)
	# playtest log 20260722_005100 的病灶：max_flares=2 + burst_count=3
	# → mini(3,2)=2，第一次投放就打光全部弹量 = 实际只有 1 条命
	_check("单次投放不会打光弹匣", mini(fp.burst_count, fp.max_flares) < fp.max_flares,
			"mini(%d,%d)=%d < %d" % [fp.burst_count, fp.max_flares,
					mini(fp.burst_count, fp.max_flares), fp.max_flares])
	# 敌机 enable_flare_reload 恒 false → 耗尽永不补充
	var ac := Aircraft.new()
	_check("默认不自动装填", not ac.enable_flare_reload, "耗尽即防御归零")
	ac.free()


# ── 6. 瞄准误差通路已开门 ──
func _test_aim_error_opened() -> void:
	print("── F. 执行失误：机炮瞄准误差 ──")
	var ac := Aircraft.new()
	_check("默认关闭（杂兵不吃误差）", not ac.gun_aim_error_enabled, "gun_aim_error_enabled=false")

	AceTier.mark(ac)
	_check("tier 标记开误差通路", ac.gun_aim_error_enabled,
			"此前被 use_tactical_preference 门死，敌机零误差")
	_check("王牌枪法 0.85", is_equal_approx(ac.pilot_aim_skill, 0.85),
			"pilot_aim_skill=%.2f" % ac.pilot_aim_skill)
	# 梭起手误差 = lerp(5.0°, 0.5°, skill)
	var err_deg: float = lerpf(5.0, 0.5, ac.pilot_aim_skill)
	_check("对应 ±1.2° 梭级误差", absf(err_deg - 1.175) < 0.01, "%.3f°" % err_deg)
	# 开关必须与操控模式标志解耦 —— 混用正是原 bug 的根因
	_check("与战术偏好标志解耦", not ac.use_tactical_preference,
			"tier 标记不得顺带打开玩家的操控模式")
	ac.free()


# ── 7. 减速迟滞 ──
func _test_decel_lag() -> void:
	print("── G. 执行失误：减速迟滞 ──")
	var G = EngagementSpeedGovernor
	_check("迟滞概率 25%", is_equal_approx(G.DECEL_LAG_CHANCE, 0.25),
			"%.2f" % G.DECEL_LAG_CHANCE)
	_check("迟滞时长 0.6~1.2s",
			is_equal_approx(G.DECEL_LAG_MIN, 0.6) and is_equal_approx(G.DECEL_LAG_MAX, 1.2),
			"%.1f~%.1fs" % [G.DECEL_LAG_MIN, G.DECEL_LAG_MAX])

	var ac := Aircraft.new()
	# 治理区外：不掷骰、不锁存
	var s_far := _situation(9000.0)
	var p_far := _plan(2500.0)
	G.apply_with_lag(ac, s_far, p_far, 0.016)
	_check("治理区外不锁存", not ac._ace_decel_lag_latched, "6km 外不治理")
	_check("治理区外不压速", is_equal_approx(p_far.target_speed_kmh, 2500.0), "速度主张原样")

	# 治理区内：必定锁存（是否真迟滞取决于骰子）
	var s_near := _situation(1500.0)
	var p_near := _plan(2500.0)
	G.apply_with_lag(ac, s_near, p_near, 0.016)
	_check("进入治理区即锁存", ac._ace_decel_lag_latched, "本次进入只掷一次骰")

	# 强制进入迟滞态 → 必定不压速（冲过头）
	ac._ace_decel_lag_timer = 1.0
	var p_lag := _plan(2500.0)
	var capped: bool = G.apply_with_lag(ac, s_near, p_lag, 0.016)
	_check("迟滞期间不压速", not capped and is_equal_approx(p_lag.target_speed_kmh, 2500.0),
			"保持高速 → 冲过头，给玩家反咬窗口")
	_check("迟滞按 delta 倒数", ac._ace_decel_lag_timer < 1.0,
			"剩余 %.3fs" % ac._ace_decel_lag_timer)

	# 迟滞走完 → 正常压速
	ac._ace_decel_lag_timer = 0.0
	var p_after := _plan(2500.0)
	var capped2: bool = G.apply_with_lag(ac, s_near, p_after, 0.016)
	_check("迟滞结束恢复治理", capped2 and p_after.target_speed_kmh < 2500.0,
			"%.0f km/h" % p_after.target_speed_kmh)

	# 离开治理区 → 解除锁存，下次进入重新掷骰
	G.apply_with_lag(ac, s_far, _plan(2500.0), 0.016)
	_check("离开治理区解除锁存", not ac._ace_decel_lag_latched, "下次进入重新掷骰")
	ac.free()


# ── 8. Wraith 队级战术：纯几何 ──
func _test_wraith_tactics_pure() -> void:
	print("── H. Wraith 队级战术（纯函数几何）──")
	var W = WraithTactics

	# BAIT 指定与继任顺位（§3.2-1）：默认二号机（KNIGHT），阵亡顺位取存活 KNIGHT，再取 SNIPER
	var k0 := _role_ac(AceSquad.AceRole.KNIGHT)
	var k1 := _role_ac(AceSquad.AceRole.KNIGHT)
	var s0 := _role_ac(AceSquad.AceRole.SNIPER)
	var s1 := _role_ac(AceSquad.AceRole.SNIPER)
	_check("BAIT 默认二号机", W.pick_bait([k0, k1, s0, s1]) == k1, "KNIGHT 里的第二架")
	_check("BAIT 顺位取存活 KNIGHT", W.pick_bait([k0, s0, s1]) == k0, "二号机阵亡 → 长机顶上")
	_check("BAIT 末位取 SNIPER", W.pick_bait([s0, s1]) == s0, "KNIGHT 全灭 → SNIPER 当诱饵")
	_check("BAIT 空队安全", W.pick_bait([]) == null, "不崩")

	# 轴线必须用 heading 约定（0=北）—— 用 .angle() 会整体偏 90°
	var ax_n: float = W.axis_heading(Vector2.ZERO, Vector2(0, -100))   # 正北
	var ax_e: float = W.axis_heading(Vector2.ZERO, Vector2(100, 0))    # 正东
	_check("轴线 heading 约定：北=0°", absf(rad_to_deg(ax_n)) < 0.01, "%.2f°" % rad_to_deg(ax_n))
	_check("轴线 heading 约定：东=90°", absf(rad_to_deg(ax_e) - 90.0) < 0.01,
			"%.2f°" % rad_to_deg(ax_e))
	_check("轴线退化安全", is_equal_approx(W.axis_heading(Vector2.ZERO, Vector2.ZERO), 0.0), "同点→0")

	# 包围几何：三翼全部 ≥60° 离轴，且真的分在两侧（§3.2-3 / §3.2 的"为什么是 60°"）
	var brgs: Array = W.wing_bearings(0.0, 3)
	_check("三翼各得一个方位", brgs.size() == 3, "%d 个" % brgs.size())
	var all_ok := true
	var has_left := false
	var has_right := false
	for b in brgs:
		var off: float = rad_to_deg(float(b))
		if absf(off) < W.BRACKET_MIN_SPLIT_DEG - 0.01:
			all_ok = false
		if off > 0.0: has_right = true
		if off < 0.0: has_left = true
	_check("两翼均 ≥60° 离轴", all_ok,
			"偏角 %s" % str(brgs.map(func(b): return "%.0f°" % rad_to_deg(float(b)))))
	_check("真的分成左右两侧", has_left and has_right,
			"同侧=玩家一个转弯就能同时规避，包夹不成立")

	# 咬钩判定
	var p := Aircraft.new()
	p.global_position = Vector2.ZERO
	p.heading = 0.0                       # 机头朝北
	var bait := Aircraft.new()
	bait.global_position = Vector2(0, -1000)   # 正前方
	_check("正前方算咬住", W.is_biting(p, bait), "机头夹角 0°")
	bait.global_position = Vector2(1000, 0)    # 正右方 90°
	_check("侧向不算咬住", not W.is_biting(p, bait), "机头夹角 90° > 35°")
	_check("空引用安全", not W.is_biting(p, null), "不崩")

	# 退化检测的均值
	p.heading = 0.0
	var m1 := Aircraft.new(); m1.global_position = Vector2(0, 1000); m1.heading = 0.0
	var m2 := Aircraft.new(); m2.global_position = Vector2(0, 1000); m2.heading = 0.0
	# 两机都在目标【南边】且机头朝北 → 正对目标，偏角 0
	var avg0: float = W.average_nose_off_deg([m1, m2], Vector2.ZERO)
	_check("正对目标偏角 0", avg0 < 0.01, "%.1f°" % avg0)
	m1.heading = PI * 0.5   # 朝东 → 偏 90°
	var avg1: float = W.average_nose_off_deg([m1, m2], Vector2.ZERO)
	_check("均值按成员平均", absf(avg1 - 45.0) < 0.5, "%.1f°（90 与 0 的均值）" % avg1)
	_check("空队安全", is_equal_approx(W.average_nose_off_deg([], Vector2.ZERO), 0.0), "→0")

	# PERCH 高度档：目标 = 玩家 + 2000m，落到对应档
	_check("玩家低空 → 爬到 MID", W.perch_tier_for(2000.0) == CombatUnit.AltitudeTier.MID,
			"2000+2000=4000 → MID(5500)")
	_check("玩家高空 → 封顶 HIGH", W.perch_tier_for(9000.0) == CombatUnit.AltitudeTier.HIGH,
			"9000+2000 ≥ HIGH(10000)")

	for a in [k0, k1, s0, s1, p, bait, m1, m2]:
		a.free()


# ── 9. Wraith 相位机 ──
func _test_wraith_phase_machine() -> void:
	print("── I. Wraith 相位机（PERCH→BRACKET→PRESS→RESET）──")
	var W = WraithTactics
	# 数值锚定（spec §2.3 表）
	_check("PERCH 超时 12s", is_equal_approx(W.PERCH_TIMEOUT_S, 12.0), "%.0fs" % W.PERCH_TIMEOUT_S)
	_check("PERCH 达标高度差 1500m", is_equal_approx(W.PERCH_DONE_DIFF_M, 1500.0), "1500m")
	_check("BAIT 拉开 3000m", is_equal_approx(W.BRACKET_BAIT_DIST_M, 3000.0), "3000m")
	_check("收网需咬住 4s", is_equal_approx(W.BRACKET_BITE_S, 4.0), "4.0s")
	_check("BRACKET 超时 20s", is_equal_approx(W.BRACKET_TIMEOUT_S, 20.0), "20s")
	_check("PRESS 15s", is_equal_approx(W.PRESS_DURATION_S, 15.0), "15s")
	_check("RESET 8s", is_equal_approx(W.RESET_DURATION_S, 8.0), "8s")
	_check("退化阈值 50°/6s",
			is_equal_approx(W.DEGRADE_ANGLE_DEG, 50.0) and is_equal_approx(W.DEGRADE_HOLD_S, 6.0),
			"平均机头偏角 >50° 持续 6s")

	var sq := F47AceSquad.new()
	var player := Aircraft.new()
	player.global_position = Vector2.ZERO
	player.heading = 0.0
	player.altitude = 2000.0
	sq._player = player
	sq.combat_phase_active = true
	var mem: Array[Aircraft] = []
	for i in range(4):
		var m := _role_ac(AceSquad.AceRole.KNIGHT if i < 2 else AceSquad.AceRole.SNIPER)
		m.global_position = Vector2(0, 3000)
		m.altitude = 2000.0
		mem.append(m)
	sq.members = mem

	var t := WraithTactics.new()
	t.setup(sq)
	t.start()
	_check("起手在 PERCH", t.phase == W.Phase.PERCH, "建立高位优先")

	# 高度差达标 → BRACKET
	for m in mem:
		m.altitude = 2000.0 + W.PERCH_DONE_DIFF_M + 100.0
	t.update(0.1)
	_check("高度差达标即转 BRACKET", t.phase == W.Phase.BRACKET,
			"当前 %s" % W.PHASE_NAMES[t.phase])
	_check("BRACKET 指定了 BAIT", t._bait != null, "诱饵已就位")
	_check("BAIT 不开火", _directive_combat_disabled(t._bait),
			"combat_disabled=true —— 它的任务是被追")
	var wings_with_bearing := 0
	for m in mem:
		if m != t._bait and is_finite(m.surround_bearing_rad):
			wings_with_bearing += 1
	_check("三翼都拿到包围方位", wings_with_bearing == 3, "%d/3" % wings_with_bearing)

	# 玩家咬住 BAIT 满 4s → 收网转 PRESS
	player.global_position = t._bait.global_position + Vector2(0, 800)   # 在诱饵正南
	player.heading = 0.0                                                 # 机头朝北 = 对着诱饵
	for i in range(50):
		t.update(0.1)
		if t.phase != W.Phase.BRACKET:
			break
	_check("咬住 4s 即收网转 PRESS", t.phase == W.Phase.PRESS,
			"当前 %s（bite=%.1fs）" % [W.PHASE_NAMES[t.phase], t._bite_timer])
	var cleared := true
	for m in mem:
		if is_finite(m.surround_bearing_rad):
			cleared = false
	_check("PRESS 解除包围偏置", cleared, "压制相完全放手给 BFM")

	# PRESS 15s → RESET
	for i in range(200):
		t.update(0.1)
		if t.phase != W.Phase.PRESS:
			break
	_check("PRESS 满时转 RESET", t.phase == W.Phase.RESET, "当前 %s" % W.PHASE_NAMES[t.phase])
	_check("RESET 仍可开火", not _directive_combat_disabled(mem[0]),
			"脱离是几何行为，不是缴械")

	# RESET 8s → 回 PERCH（闭环，没有终止态）
	for i in range(120):
		t.update(0.1)
		if t.phase != W.Phase.RESET:
			break
	_check("RESET 满时回 PERCH", t.phase == W.Phase.PERCH, "四相闭环，无终止态")

	# 退化检测：全队机头偏角 >50° 持续 6s → 强制 RESET
	t.phase = W.Phase.PRESS
	t.phase_timer = 0.0
	t._degrade_timer = 0.0
	t._sample_timer = 0.0
	for m in mem:
		m.global_position = Vector2(0, 3000)
		m.heading = PI * 0.5        # 朝东，而玩家在正北 → 偏角 ~90°
	player.global_position = Vector2.ZERO
	var fired := false
	for i in range(200):
		t.update(0.1)
		if t.phase == W.Phase.RESET:
			fired = true
			break
	_check("退化 6s 必触发 RESET", fired, "根治共速绕圈死锁（log 20260720_172222）")

	t.stop()
	for m in mem:
		m.free()
	player.free()


func _role_ac(role: int) -> Aircraft:
	var ac := Aircraft.new()
	var ai := AIController.new()
	ai.aircraft = ac
	ac.add_child(ai)
	ac._ai_ref = ai
	ac.set_meta(AceSquad.ROLE_META, role)
	return ac


func _directive_combat_disabled(ac: Aircraft) -> bool:
	if ac == null or not is_instance_valid(ac):
		return false
	var ai: AIController = ac._get_ai_controller()
	if ai == null or ai._directive == null:
		return false
	return ai._directive.combat_disabled


func _situation(dist_m: float) -> Situation:
	var s := Situation.new()
	s.has_target = true
	s.dist_m = dist_m
	s.max_g = 12.0
	s.corner_speed_kmh = 623.0
	s.max_speed_kmh = 2800.0
	return s


func _plan(speed_kmh: float) -> TacticalPlan:
	var p := TacticalPlan.new()
	p.target_speed_kmh = speed_kmh
	p.afterburner = true
	return p


# ── 10. 舰队 BOSS 接战触发（T3 锁定 / T4 受伤）──
## 权威源：specs/systems/boss-hunter-doctrine.md §2.2 —— "打第一枪即接战"。
## 回归点：船体锁定免疫 + 伤害走 hull_hp/部件，通用触发器直读 is_locked/hp 对舰队 BOSS
## 全盲，导致玩家 10km 外锁舰齐射却要贴脸才 ENGAGED。两个聚合方法是根治。
func _test_naval_engage_triggers() -> void:
	print("── K. 舰队 BOSS 接战触发（T3/T4 不再对船全盲）──")
	var ship := NavalUnit.new()
	ship.hull_hp = 1000.0
	var m := WeaponMount.new()
	m.hp = 200.0
	ship.mounts.append(m)

	# T4：船体总血量池 = hull + 存活挂点，任一命中都拉低它
	var pool0: float = ship.boss_hp_pool()
	_check("boss_hp_pool 汇总 hull+挂点", is_equal_approx(pool0, 1200.0), "got %.0f" % pool0)
	m.hp = 120.0
	_check("挂点受伤 → 池下降（T4 可见）", ship.boss_hp_pool() < pool0,
			"pool=%.0f" % ship.boss_hp_pool())
	var pool1: float = ship.boss_hp_pool()
	ship.hull_hp = 800.0
	_check("船体受伤 → 池继续下降（T4 可见）", ship.boss_hp_pool() < pool1,
			"pool=%.0f" % ship.boss_hp_pool())

	# T3：船体直接锁定免疫，看的是挂点/弱点代理的锁定态
	_check("无代理锁定 → 未接战", not ship.is_engaged_by_lock(), "")
	var mt := MountTarget.new()
	mt.is_locked = true
	ship._mount_targets.append(mt)
	_check("挂点代理被锁 → 整船视为被锁（T3）", ship.is_engaged_by_lock(),
			"玩家 10km 外锁舰即接战")
	mt.is_locked = false
	_check("代理解锁 → 不再接战", not ship.is_engaged_by_lock(), "")

	mt.free()
	ship.free()


func _check(name: String, got: bool, note: String) -> void:
	if got: _pass += 1
	else: _fail += 1
	print("  %s %-30s — %s" % ["✓" if got else "✗", name, note])
