extends RefCounted

## 无头目标选择测试（spec target-engageability-selection §5 验收）
## 目的：自动验证"可命中性"评分 + 守后优先 + 锁定封顶，无需进引擎手测。
##
## 运行（经 BenchRunner，正常项目上下文 → autoload/class_name 可用）：
##   godot --headless --path . -- --bench=target_sel
##
## 覆盖：
##   A. 近偏轴 vs 远正对 → 选正对（align 主导，修"放着锁定的不打去够远的"）
##   C. 全等只差距离 → 选近（prox tiebreaker）
##   runaway. 锁定进度封顶 → 盯久(10×lock_time)不再碾压新锁(1×)
##   B. 队友超杀 → 导弹优先强降权；机炮优先不降权、不触发即时换目标
##   D. 守后优先 rear_threat_score：已咬 > 逼近 > 前方(0)
##
## 做法：裸构造对象（不入树），直接调 TargetSelection._score_candidate / SquadCoordination.rear_threat_score。

var _pass := 0
var _fail := 0


func run() -> void:
	print("\n════════ 目标选择验证测试 ════════")
	_test_align_beats_offaxis()
	_test_proximity_tiebreak()
	_test_lock_cap_no_runaway()
	_test_overkill_deprioritize()
	_test_rear_threat_priority()
	# ── 战场引力组（spec battlefield-gravity §5）──
	_test_gravity_curve()
	_test_gravity_band_isolation()
	_test_gravity_engage_floor()
	_test_gravity_feasibility_gate()
	_test_gravity_cloak_anchor()
	_test_gravity_nonaircraft_safety()
	_test_gravity_freed_reference_safety()
	_test_gravity_survival_sticky()
	_test_gravity_disabled_baseline()
	# ── 阶段 2：面 B 回防 + leash 松绑 ──
	_test_defend_protectee_assign()
	_test_defend_max_defenders_cap()
	_test_leash_widen_and_reanchor()
	print("──────── 结果：%d 通过 / %d 失败 ────────" % [_pass, _fail])
	print("════════════════════════════════\n")


func _check(label: String, cond: bool, detail: String = "") -> void:
	if cond:
		_pass += 1
		print("  ✓ %s %s" % [label, detail])
	else:
		_fail += 1
		print("  ✗ %s %s" % [label, detail])


## 构造一架带最小 params 的飞机（origin / team / heading 可指定）
func _mk_ac(pos: Vector2, team: int, heading: float) -> Aircraft:
	var ac = load("res://scripts/aircraft.gd").new()
	ac.team = team
	ac.altitude = 8000.0
	ac.global_position = pos
	ac.heading = heading
	ac.hp = 100.0
	var p = AircraftParams.new()
	p.lock_time = 3.0
	p.radar_half_angle = 30.0
	p.missile = load("res://resources/default_missile.tres")
	ac.params = p
	return ac


## 构造 AIController（聪明 planner 路径默认 aggression=0.5）
func _mk_ai(ac: Aircraft) -> AIController:
	var ai = AIController.new()
	ai.aircraft = ac
	ai.aggression = 0.5            # min_lock_ratio = 0.65
	ai.preferred_altitude_tier = -99
	ai.squad = null
	ai.squad_engage_mode = AIController.SquadEngageMode.FOLLOW_LEADER
	# _current_target 默认即 null；目标写入统一走 acquire_target/release_target 仲裁入口
	return ai


func _free_all(arr: Array) -> void:
	for o in arr:
		if is_instance_valid(o):
			o.free()


## ── A. 近但大偏轴 vs 远但正对 → 选正对 ──
## 修复前：score = lock*2 + dist，近者 dist 项略高 → 选近的(偏轴打不中)。
## 修复后：align 主导 → 正对者胜。
func _test_align_beats_offaxis() -> void:
	print("── A. 近偏轴 vs 远正对 ──")
	var me := _mk_ac(Vector2.ZERO, 0, 0.0)  # 机头朝北(0°)
	# 近(2000m=1000px)但 25° 偏轴：放在北偏东 25°
	var near := _mk_ac(Vector2(sin(deg_to_rad(25.0)) * 1000.0, -cos(deg_to_rad(25.0)) * 1000.0), 1, PI)
	# 远(3000m=1500px)但正前方(0°)：正北
	var far := _mk_ac(Vector2(0.0, -1500.0), 1, PI)
	near.altitude = 8000.0; far.altitude = 8000.0
	me.radar_targets[near] = 3.0  # 满锁
	me.radar_targets[far] = 3.0
	var ai := _mk_ai(me)
	var s_near := TargetSelection._score_candidate(ai, near, null, false)
	var s_far := TargetSelection._score_candidate(ai, far, null, false)
	_check("远正对 > 近偏轴", s_far > s_near,
			"s_far=%.3f s_near=%.3f" % [s_far, s_near])
	_free_all([me, near, far, ai])


## ── C. 全等只差距离 → 选近 ──
func _test_proximity_tiebreak() -> void:
	print("── C. 全等只差距离 → 选近 ──")
	var me := _mk_ac(Vector2.ZERO, 0, 0.0)
	var near := _mk_ac(Vector2(0.0, -750.0), 1, PI)   # 1500m 正前
	var far := _mk_ac(Vector2(0.0, -1750.0), 1, PI)   # 3500m 正前
	near.altitude = 8000.0; far.altitude = 8000.0
	me.radar_targets[near] = 3.0
	me.radar_targets[far] = 3.0
	var ai := _mk_ai(me)
	var s_near := TargetSelection._score_candidate(ai, near, null, false)
	var s_far := TargetSelection._score_candidate(ai, far, null, false)
	_check("近 > 远（prox tiebreak）", s_near > s_far,
			"s_near=%.3f s_far=%.3f" % [s_near, s_far])
	_free_all([me, near, far, ai])


## ── runaway. 锁定封顶：盯久不再碾压 ──
## 两个除 lock_progress 外全等的目标（一个 3s，一个 30s），lock01 封顶 → 同分。
func _test_lock_cap_no_runaway() -> void:
	print("── runaway. 锁定封顶 ──")
	var me := _mk_ac(Vector2.ZERO, 0, 0.0)
	var fresh := _mk_ac(Vector2(0.0, -1000.0), 1, PI)
	var stared := _mk_ac(Vector2(0.0, -1000.0), 1, PI)  # 同位置同朝向
	fresh.altitude = 8000.0; stared.altitude = 8000.0
	me.radar_targets[fresh] = 3.0     # 刚满锁
	me.radar_targets[stared] = 30.0   # 盯了很久（旧公式会爆分）
	var ai := _mk_ai(me)
	var s_fresh := TargetSelection._score_candidate(ai, fresh, null, false)
	var s_stared := TargetSelection._score_candidate(ai, stared, null, false)
	_check("盯久==新锁（lock01 封顶）", is_equal_approx(s_fresh, s_stared),
			"s_fresh=%.3f s_stared=%.3f" % [s_fresh, s_stared])
	_free_all([me, fresh, stared, ai])


## ── B. 队友超杀 → 强降权 ──
## 同一目标：无在途弹 vs 队友已发 80dmg 制导弹(目标 60hp) → 后者 ×OVERKILL_MULT。
func _test_overkill_deprioritize() -> void:
	print("── B. 队友超杀让路 ──")
	var me := _mk_ac(Vector2.ZERO, 0, 0.0)
	var tgt := _mk_ac(Vector2(0.0, -1000.0), 1, PI)
	tgt.altitude = 8000.0
	tgt.hp = 60.0
	tgt.survivor_missile_damage_cap = 0.0
	me.radar_targets[tgt] = 3.0
	var ai := _mk_ai(me)

	# 基线：无在途弹
	var mm := MissileManager.new()
	me.missile_manager = mm
	var s_base := TargetSelection._score_candidate(ai, tgt, null, false)

	# 队友 mate 发一枚制导 MRM(80) 砸 tgt → team_inbound >= hp
	var msl: MissileParams = load("res://resources/default_missile.tres")
	var mate := _mk_ac(Vector2(100.0, 0.0), 0, 0.0)
	var m := Missile.new()
	m.params = msl; m.source = mate; m.target = tgt; m.team = 0
	m.is_active = true; m.is_flare_jammed = false; m.has_guidance = true
	mm.add_child(m)
	var s_overkill := TargetSelection._score_candidate(ai, tgt, null, false)

	_check("导弹优先：超杀目标分骤降", s_overkill < s_base * 0.5,
			"s_base=%.3f s_overkill=%.3f (×%.2f)" % [s_base, s_overkill, s_overkill / maxf(s_base, 0.001)])

	# 机炮优先：同一枚在途导弹不把目标标成“已死”，评分与无在途基线一致。
	me.weapon_preference = Aircraft.WeaponPreference.PREFER_GUN
	var s_gun_priority := TargetSelection._score_candidate(ai, tgt, null, false)
	_check("机炮优先：忽略目标超杀降权", is_equal_approx(s_gun_priority, s_base),
			"s_base=%.3f s_gun=%.3f" % [s_base, s_gun_priority])

	# 武器层即使因 TEAM_OVERKILL 请求重评，机炮优先也不丢粘性；切回导弹优先才响应。
	ai._target_source = AIController.TargetSource.TS_SCORED
	ai._overkill_retarget_cd = 0.0
	ai._target_eval_timer = 0.0
	ai.request_overkill_retarget()
	_check("机炮优先：忽略即时换目标请求",
			is_zero_approx(ai._overkill_retarget_cd) and is_zero_approx(ai._target_eval_timer))
	me.weapon_preference = Aircraft.WeaponPreference.PREFER_MISSILE
	ai.request_overkill_retarget()
	_check("导弹优先：仍响应即时换目标请求",
			ai._overkill_retarget_cd > 0.0 and ai._target_eval_timer > 0.0)

	# 交战中重评闭环：机炮优先保留已超杀当前目标；导弹优先才转向等价的新鲜目标。
	var rival := _mk_ac(Vector2(0.0, -1000.0), 1, PI)
	rival.altitude = 8000.0
	rival.hp = 60.0
	me.radar_targets[rival] = 3.0
	ai.acquire_target(tgt, AIController.TargetSource.TS_SCORED, "test overkill sticky")
	me.weapon_preference = Aircraft.WeaponPreference.PREFER_GUN
	TargetSelection.reevaluate_target(ai)
	_check("机炮优先：交战重评仍咬当前目标", ai._current_target == tgt)
	me.weapon_preference = Aircraft.WeaponPreference.PREFER_MISSILE
	TargetSelection.reevaluate_target(ai)
	_check("导弹优先：交战重评让给新鲜目标", ai._current_target == rival)
	mm.free()  # 连带 free 子弹
	_free_all([me, tgt, rival, mate, ai])


## ── D. 守后优先 rear_threat_score：已咬 > 逼近 > 前方 ──
func _test_rear_threat_priority() -> void:
	print("── D. 守后优先（已咬>逼近>前方） ──")
	var leader := _mk_ac(Vector2.ZERO, 0, 0.0)  # 长机朝北
	# 后方(南=+y)600px：朝北飞(heading 0)=朝长机逼近
	var rear_enemy := _mk_ac(Vector2(0.0, 600.0), 1, 0.0)
	# 前方(北=-y)600px
	var front_enemy := _mk_ac(Vector2(0.0, -600.0), 1, 0.0)

	# 逼近（未咬）
	var s_approach := SquadCoordination.rear_threat_score(leader, rear_enemy)
	# 已咬长机
	leader.engaging_me[rear_enemy.get_instance_id()] = true
	var s_bite := SquadCoordination.rear_threat_score(leader, rear_enemy)
	# 前方
	var s_front := SquadCoordination.rear_threat_score(leader, front_enemy)

	_check("已咬 > 逼近", s_bite > s_approach, "bite=%.3f approach=%.3f" % [s_bite, s_approach])
	_check("逼近 > 前方(=0)", s_approach > s_front, "approach=%.3f front=%.3f" % [s_approach, s_front])
	_check("前方非威胁=0", is_equal_approx(s_front, 0.0), "front=%.3f" % s_front)
	_free_all([leader, rear_enemy, front_enemy])


# ══════════════════════════════════════════════
#  战场引力组（spec battlefield-gravity §5）
#  static 上下文跨测试存活 → 每个测试首尾必须 reset()
# ══════════════════════════════════════════════

## ── G1. 引力衰减曲线（§2.2）：R_CORE 内 1.0 / 线性段样例 / R_FAR 外 FLOOR ──
func _test_gravity_curve() -> void:
	print("── G1. 引力衰减曲线 ──")
	ObjectiveContext.reset()
	ObjectiveContext.enabled = true
	ObjectiveContext.has_objective = true
	ObjectiveContext.anchor = Vector2.ZERO
	var m_core := ObjectiveContext.gravity_mult(Vector2(1000, 0))
	var m_mid := ObjectiveContext.gravity_mult(Vector2(5000, 0))   # spec 样例：0.325
	var m_far := ObjectiveContext.gravity_mult(Vector2(7000, 0))
	_check("锚心内=1.0", is_equal_approx(m_core, 1.0), "m=%.3f" % m_core)
	_check("5000px≈0.325（spec 样例）", absf(m_mid - 0.325) < 0.001, "m=%.3f" % m_mid)
	_check("远界外=FLOOR", is_equal_approx(m_far, ObjectiveContext.GRAVITY_FLOOR), "m=%.3f" % m_far)
	ObjectiveContext.reset()


## ── G2. 带间隔离（§2.1）：生存 > 任务 > 顺手，且各带落在契约区间 ──
func _test_gravity_band_isolation() -> void:
	print("── G2. 三带隔离 ──")
	ObjectiveContext.reset()
	var me := _mk_ac(Vector2.ZERO, CombatUnit.TEAM_PLAYER, 0.0)
	# 三个几何全等的候选（正前 800px，满锁）——只差带归属
	var surv := _mk_ac(Vector2(0, -800), CombatUnit.TEAM_HOSTILE, PI)
	var obj := _mk_ac(Vector2(0, -800), CombatUnit.TEAM_HOSTILE, PI)
	var opp := _mk_ac(Vector2(0, -800), CombatUnit.TEAM_HOSTILE, PI)
	for t in [surv, obj, opp]:
		t.altitude = 8000.0
		me.radar_targets[t] = 3.0
	var ai := _mk_ai(me)
	ObjectiveContext.enabled = true
	ObjectiveContext.protectee = me
	ObjectiveContext.has_objective = true
	ObjectiveContext.anchor = Vector2.ZERO   # 锚在自己脚下 → opp 不吃衰减，测纯带差
	ObjectiveContext.member_ids[obj.get_instance_id()] = true
	me.engaging_me[surv.get_instance_id()] = surv
	var s_surv := TargetSelection._score_candidate(ai, surv, null, false)
	var s_obj := TargetSelection._score_candidate(ai, obj, null, false)
	var s_opp := TargetSelection._score_candidate(ai, opp, null, false)
	_check("生存 > 任务", s_surv > s_obj, "surv=%.1f obj=%.1f" % [s_surv, s_obj])
	_check("任务 > 顺手", s_obj > s_opp, "obj=%.1f opp=%.1f" % [s_obj, s_opp])
	_check("生存 ≥ 60（threat01 地板）", s_surv >= 60.0, "surv=%.1f" % s_surv)
	_check("任务 ≥ 40", s_obj >= ObjectiveContext.OBJECTIVE_BONUS, "obj=%.1f" % s_obj)
	_check("顺手 ≤ 1（base 上限）", s_opp <= 1.0, "opp=%.3f" % s_opp)
	ObjectiveContext.reset()
	_free_all([me, surv, obj, opp, ai])


## ── G3. 交战地板（§2.1.1 主病征场景）：候选表里只有远杂鱼 → 不交战 ──
## 无地板则 argmax 照选唯一候选（引力形同虚设）——这是 v2 复审修的致命洞。
func _test_gravity_engage_floor() -> void:
	print("── G3. 交战地板（地板拒远杂鱼 / 近战照打） ──")
	ObjectiveContext.reset()
	var me := _mk_ac(Vector2.ZERO, CombatUnit.TEAM_PLAYER, 0.0)
	var trash := _mk_ac(Vector2(0, -1000), CombatUnit.TEAM_HOSTILE, PI)  # 我正前 1000px，满锁
	trash.altitude = 8000.0
	me.radar_targets[trash] = 3.0
	var ai := _mk_ai(me)
	ObjectiveContext.enabled = true
	ObjectiveContext.protectee = me
	ObjectiveContext.has_objective = true
	ObjectiveContext.anchor = Vector2(8000, -1000)   # 主战场在 8000px 外 → trash 距锚 8000px → mult=0.10
	TargetSelection.try_engage(ai)
	_check("远离锚的唯一候选被地板拒绝", ai._current_target == null,
			"target=%s" % str(ai._current_target))
	# 负向对照：锚移到 trash 旁 → 同一候选正常交战（验证不是别的门挡的）
	ObjectiveContext.anchor = Vector2(0, -1000)
	TargetSelection.try_engage(ai)
	_check("锚旁同候选正常交战", ai._current_target == trash,
			"target=%s" % str(ai._current_target))
	ObjectiveContext.reset()
	_free_all([me, trash, ai])


## ── G4. leash 可行性门（§2.1.2）：编队僚机不选"追出 leash 必被拽回"的目标 ──
func _test_gravity_feasibility_gate() -> void:
	print("── G4. leash 可行性门 ──")
	ObjectiveContext.reset()
	var leader := _mk_ac(Vector2.ZERO, CombatUnit.TEAM_PLAYER, 0.0)
	var me := _mk_ac(Vector2(300, 0), CombatUnit.TEAM_PLAYER, 0.0)
	# 候选在僚机正前、但距长机 2500px（> 1800×0.9）
	var far_tgt := _mk_ac(Vector2(300, -2500), CombatUnit.TEAM_HOSTILE, PI)
	far_tgt.altitude = 8000.0
	me.radar_targets[far_tgt] = 3.0
	var ai := _mk_ai(me)
	var sq = load("res://scripts/squad.gd").new()
	sq.leader = leader
	ai.squad = sq
	ObjectiveContext.enabled = true
	ObjectiveContext.protectee = leader
	var s_gated := TargetSelection._score_candidate(ai, far_tgt, null, false)
	_check("leash 外候选被拒（-1）", s_gated < 0.0, "s=%.3f" % s_gated)
	# 同一候选若正在咬操控机（survival）→ 豁免可行性门
	leader.engaging_me[far_tgt.get_instance_id()] = far_tgt
	var s_surv := TargetSelection._score_candidate(ai, far_tgt, null, false)
	_check("survival 候选豁免可行性门", s_surv >= 60.0, "s=%.1f" % s_surv)
	ObjectiveContext.reset()
	_free_all([leader, me, far_tgt, ai])


## ── G5. 隐形不破功（§2.2）：锚=成员位置质心（与可锁性无关），远杂鱼仍被压 ──
func _test_gravity_cloak_anchor() -> void:
	print("── G5. 隐形窗口锚不破功 ──")
	ObjectiveContext.reset()
	ObjectiveContext.enabled = true
	var b1 := _mk_ac(Vector2(-1000, -4000), CombatUnit.TEAM_HOSTILE, 0.0)
	var b2 := _mk_ac(Vector2(1000, -4000), CombatUnit.TEAM_HOSTILE, 0.0)
	ObjectiveContext.set_boss_objective([b1, b2])
	_check("锚=存活成员质心", ObjectiveContext.anchor.is_equal_approx(Vector2(0, -4000)),
			"anchor=%s" % str(ObjectiveContext.anchor))
	_check("成员吃任务带", ObjectiveContext.is_objective(b1), "")
	var m_far := ObjectiveContext.gravity_mult(Vector2(0, -4000) + Vector2(8000, 0))
	_check("距锚 8000px 杂鱼压到 FLOOR", is_equal_approx(m_far, ObjectiveContext.GRAVITY_FLOOR),
			"m=%.3f" % m_far)
	# 成员全灭 → 退化为无任务（锚随 protectee，此处无 protectee → 无引力）
	b1.is_destroyed = true
	b2.is_destroyed = true
	ObjectiveContext.set_boss_objective([b1, b2])
	_check("全灭退化 no_objective", not ObjectiveContext.has_objective, "")
	ObjectiveContext.reset()
	_free_all([b1, b2])


## ── G6. 非飞机候选安全（§4）：GroundUnit 评分不崩、不误入生存带；可入任务带（航母 BOSS 语义） ──
func _test_gravity_nonaircraft_safety() -> void:
	print("── G6. 非飞机候选安全 ──")
	ObjectiveContext.reset()
	var me := _mk_ac(Vector2.ZERO, CombatUnit.TEAM_PLAYER, 0.0)
	var g = load("res://scripts/ground_unit.gd").new()
	g.team = CombatUnit.TEAM_HOSTILE
	g.global_position = Vector2(0, -1000)
	me.radar_targets[g] = 3.0
	var ai := _mk_ai(me)
	ObjectiveContext.enabled = true
	ObjectiveContext.protectee = me
	ObjectiveContext.has_objective = true
	ObjectiveContext.anchor = Vector2.ZERO
	# 即使把地面单位塞进 engaging_me（防御性场景）——类型门保证不入生存带
	me.engaging_me[g.get_instance_id()] = g
	var s := TargetSelection._score_candidate(ai, g, null, false)
	_check("地面候选评分不崩且 < 生存带", s >= 0.0 and s < 40.0, "s=%.3f" % s)
	_check("类型门：地面不算生存威胁", not ObjectiveContext.is_survival_threat(g), "")
	# 但可以是任务成员（航母 BOSS 的 NavalUnit/MountTarget 同路径）
	ObjectiveContext.member_ids[g.get_instance_id()] = true
	_check("地面/舰船可入任务带 +40", ObjectiveContext.band_bonus(g) >= 40.0,
			"bonus=%.1f" % ObjectiveContext.band_bonus(g))
	ObjectiveContext.reset()
	_free_all([me, g, ai])


## ── G6b. 已释放引用安全：生命周期边界谓词必须返回 false，不能在形参类型检查阶段硬崩 ──
func _test_gravity_freed_reference_safety() -> void:
	print("── G6b. 已释放引用边界安全 ──")
	ObjectiveContext.reset()
	var me := _mk_ac(Vector2.ZERO, CombatUnit.TEAM_PLAYER, 0.0)
	var ai := _mk_ai(me)
	var freed_target: Aircraft = Aircraft.new()
	ai._current_target = freed_target
	ObjectiveContext.enabled = true
	freed_target.free()
	_check("粘性读取已释放当前目标不崩且回落默认值",
			is_equal_approx(TargetSelection._sticky_for(ai), TargetSelection.STICKY_BONUS), "")
	_check("已释放目标不算任务成员", not ObjectiveContext.is_objective(freed_target), "")
	ObjectiveContext.reset()
	_free_all([me, ai])


## ── G7. 带感知粘性（§2.1.3）：当前目标是生存候选 → SURVIVAL_STICKY，否则原 STICKY_BONUS ──
func _test_gravity_survival_sticky() -> void:
	print("── G7. 带感知粘性 ──")
	ObjectiveContext.reset()
	var me := _mk_ac(Vector2.ZERO, CombatUnit.TEAM_PLAYER, 0.0)
	var chaser := _mk_ac(Vector2(0, 800), CombatUnit.TEAM_HOSTILE, 0.0)
	var ai := _mk_ai(me)
	ai._current_target = chaser   # 单测直写（绕过仲裁，仅测粘性读取）
	ObjectiveContext.enabled = true
	ObjectiveContext.protectee = me
	me.engaging_me[chaser.get_instance_id()] = chaser
	_check("生存目标粘性=SURVIVAL_STICKY",
			is_equal_approx(TargetSelection._sticky_for(ai), ObjectiveContext.SURVIVAL_STICKY), "")
	me.engaging_me.clear()
	_check("非生存目标粘性=STICKY_BONUS",
			is_equal_approx(TargetSelection._sticky_for(ai), TargetSelection.STICKY_BONUS), "")
	ObjectiveContext.reset()
	_free_all([me, chaser, ai])


## ── G8. 关闭即零变化（§4 生效门）：enabled=false 时评分与上下文内容无关 ──
func _test_gravity_disabled_baseline() -> void:
	print("── G8. 关闭即零变化（沙盒/敌方基线） ──")
	ObjectiveContext.reset()
	var me := _mk_ac(Vector2.ZERO, CombatUnit.TEAM_PLAYER, 0.0)
	var tgt := _mk_ac(Vector2(0, -1000), CombatUnit.TEAM_HOSTILE, PI)
	tgt.altitude = 8000.0
	me.radar_targets[tgt] = 3.0
	var ai := _mk_ai(me)
	var s_base := TargetSelection._score_candidate(ai, tgt, null, false)
	# 塞满上下文但 enabled=false → 分数必须一位不变
	ObjectiveContext.protectee = me
	ObjectiveContext.has_objective = true
	ObjectiveContext.anchor = Vector2(9000, 0)
	ObjectiveContext.member_ids[tgt.get_instance_id()] = true
	me.engaging_me[tgt.get_instance_id()] = tgt
	var s_off := TargetSelection._score_candidate(ai, tgt, null, false)
	_check("enabled=false → 评分逐位不变", is_equal_approx(s_base, s_off),
			"base=%.4f off=%.4f" % [s_base, s_off])
	ObjectiveContext.reset()
	_free_all([me, tgt, ai])


## ── G9. 面 B 回防指派（§3.3）：操控机被咬 → 僚机反咬追击者（绕开雷达锥/锁定门） ──
func _test_defend_protectee_assign() -> void:
	print("── G9. 面 B 回防指派 ──")
	ObjectiveContext.reset()
	var protectee := _mk_ac(Vector2.ZERO, CombatUnit.TEAM_PLAYER, 0.0)
	var me := _mk_ac(Vector2(500, 0), CombatUnit.TEAM_PLAYER, 0.0)
	var chaser := _mk_ac(Vector2(0, 800), CombatUnit.TEAM_HOSTILE, 0.0)
	var ai := _mk_ai(me)
	var sq = load("res://scripts/squad.gd").new()
	sq.leader = protectee
	sq.add_member(protectee)
	sq.add_member(me)
	ai.squad = sq
	ObjectiveContext.enabled = true
	ObjectiveContext.protectee = protectee
	protectee.engaging_me[chaser.get_instance_id()] = chaser
	# 注意：chaser 不在 me.radar_targets 里（锥外）——面 B 的核心价值就是绕开雷达锥
	var ok := SquadCoordination.try_defend_protectee(ai)
	_check("锥外追击者被指派", ok and ai._current_target == chaser,
			"ok=%s target=%s" % [str(ok), str(ai._current_target)])
	ObjectiveContext.reset()
	_free_all([protectee, me, chaser, ai])


## ── G10. 回防上限（§3.3）：≥MAX_DEFENDERS 已在反咬 → 不再抽调（防掏空火力） ──
func _test_defend_max_defenders_cap() -> void:
	print("── G10. MAX_DEFENDERS 上限 ──")
	ObjectiveContext.reset()
	var protectee := _mk_ac(Vector2.ZERO, CombatUnit.TEAM_PLAYER, 0.0)
	var me := _mk_ac(Vector2(500, 0), CombatUnit.TEAM_PLAYER, 0.0)
	var w2 := _mk_ac(Vector2(-500, 0), CombatUnit.TEAM_PLAYER, 0.0)
	var w3 := _mk_ac(Vector2(0, 500), CombatUnit.TEAM_PLAYER, 0.0)
	var c1 := _mk_ac(Vector2(0, 900), CombatUnit.TEAM_HOSTILE, 0.0)
	var c2 := _mk_ac(Vector2(200, 900), CombatUnit.TEAM_HOSTILE, 0.0)
	var c3 := _mk_ac(Vector2(-200, 900), CombatUnit.TEAM_HOSTILE, 0.0)
	var ai := _mk_ai(me)
	var ai2 := _mk_ai(w2)
	var ai3 := _mk_ai(w3)
	w2._ai_ref = ai2
	w3._ai_ref = ai3
	var sq = load("res://scripts/squad.gd").new()
	sq.leader = protectee
	for m in [protectee, me, w2, w3]:
		sq.add_member(m)
	ai.squad = sq
	ObjectiveContext.enabled = true
	ObjectiveContext.protectee = protectee
	for c in [c1, c2, c3]:
		protectee.engaging_me[c.get_instance_id()] = c
	# w2/w3 已各自反咬一个追击者（_count_defenders 按"当前目标 ∈ engaging_me"反查，无新状态字段）
	ai2._current_target = c2
	ai3._current_target = c3
	var ok := SquadCoordination.try_defend_protectee(ai)
	_check("已达上限(2) → 第三架不抽调", not ok and ai._current_target == null,
			"ok=%s" % str(ok))
	# 一架防守者转移目标后 → 名额空出，me 可以补位
	ai3._current_target = null
	var ok2 := SquadCoordination.try_defend_protectee(ai)
	_check("名额空出 → 补位反咬", ok2 and ai._current_target != null, "ok=%s" % str(ok2))
	ObjectiveContext.reset()
	_free_all([protectee, me, w2, w3, c1, c2, c3, ai, ai2, ai3])


## ── G11. leash 松绑（§3.4）：生存交战放宽 4200px 锚操控机 / 有 objective 重锚战场 / 无引力=旧行为 ──
func _test_leash_widen_and_reanchor() -> void:
	print("── G11. leash 松绑 ──")
	ObjectiveContext.reset()
	var leader := _mk_ac(Vector2(3000, 0), CombatUnit.TEAM_PLAYER, 0.0)
	var me := _mk_ac(Vector2.ZERO, CombatUnit.TEAM_PLAYER, 0.0)
	var chaser := _mk_ac(Vector2(3000, 800), CombatUnit.TEAM_HOSTILE, 0.0)
	var ai := _mk_ai(me)
	var sq = load("res://scripts/squad.gd").new()
	sq.leader = leader
	ai.squad = sq
	# 基线（无引力）：锚=长机，限距=SQUAD_LEASH_DIST
	var al0: Array = ai.leash_anchor_and_limit()
	_check("无引力=旧行为", al0[0] == leader.global_position \
			and is_equal_approx(al0[1], AIController.SQUAD_LEASH_DIST),
			"anchor=%s limit=%.0f" % [str(al0[0]), al0[1]])
	# 生存交战：目标咬操控机 → 限距 4200 常数、锚=操控机
	ObjectiveContext.enabled = true
	ObjectiveContext.protectee = leader
	leader.engaging_me[chaser.get_instance_id()] = chaser
	ai._current_target = chaser
	var al1: Array = ai.leash_anchor_and_limit()
	_check("生存交战放宽 4200px 锚操控机",
			al1[0] == leader.global_position and is_equal_approx(al1[1],
			ObjectiveContext.SURVIVAL_RANGE_PX + ObjectiveContext.BRACKET_SLACK_PX),
			"anchor=%s limit=%.0f" % [str(al1[0]), al1[1]])
	# 有 objective（非生存交战）：锚改引力锚，限距不变
	ai._current_target = null
	ObjectiveContext.has_objective = true
	ObjectiveContext.anchor = Vector2(9000, 9000)
	var al2: Array = ai.leash_anchor_and_limit()
	_check("objective 重锚战场中心", al2[0] == Vector2(9000, 9000) \
			and is_equal_approx(al2[1], AIController.SQUAD_LEASH_DIST),
			"anchor=%s limit=%.0f" % [str(al2[0]), al2[1]])
	ObjectiveContext.reset()
	_free_all([leader, me, chaser, ai])
