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
##   B. 队友超杀 → 强降权（×OVERKILL_MULT）
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
	ai._current_target = null
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

	_check("超杀目标分骤降", s_overkill < s_base * 0.5,
			"s_base=%.3f s_overkill=%.3f (×%.2f)" % [s_base, s_overkill, s_overkill / maxf(s_base, 0.001)])
	mm.free()  # 连带 free 子弹
	_free_all([me, tgt, mate, ai])


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
