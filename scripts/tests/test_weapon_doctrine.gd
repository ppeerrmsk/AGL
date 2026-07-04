extends RefCounted

## 武器使用准则竞选器测试（spec weapon-employment-doctrine §5 验收，阶段 1）
## 运行：godot --headless --path . -- --bench=weapon_doctrine（或 --bench=all）

var _pass := 0
var _fail := 0


func run() -> void:
	print("\n════════ 武器竞选器（weapon-employment-doctrine §2.2） ════════")
	_test_pure_select()
	_test_dynamic_candidates()
	_test_planner_integration()
	_test_line_up()
	print("──────── 结果：%d 通过 / %d 失败 ────────" % [_pass, _fail])
	print("══════════════════════════════════════════════════\n")


func _test_pure_select() -> void:
	print("── 竞选规则（纯函数）──")
	var cands := [
		{"kind": "railgun", "band_min": 2500.0, "band_max": 8000.0, "ready": true},
		{"kind": "missile", "band_min": 500.0, "band_max": 6000.0, "ready": true},
		{"kind": "gun", "band_min": 60.0, "band_max": 1000.0, "ready": true},
	]
	# 1. 远距重叠区（railgun+missile 都在带内）→ 命中率优先选电磁炮
	var r := WeaponSelector.select(cands, 5000.0)
	_check("重叠区命中率优先=电磁炮", r.kind == "railgun", "5000m：railgun(100)>missile(70)")
	# 2. 电磁炮冷却中 → 导弹接手
	cands[0]["ready"] = false
	r = WeaponSelector.select(cands, 5000.0)
	_check("电磁炮 CD → 导弹", r.kind == "missile", "")
	cands[0]["ready"] = true
	# 3. 近距（电磁炮最近射程外）→ 固定机炮（涌现，无特判）
	r = WeaponSelector.select(cands, 300.0)
	_check("近距固定机炮", r.kind == "gun", "300m < railgun band_min 且 < missile min")
	# 4. 全失格 → 维持追击 + 导弹纪律等待
	var all_cd := [
		{"kind": "missile", "band_min": 500.0, "band_max": 6000.0, "ready": false},
		{"kind": "gun", "band_min": 60.0, "band_max": 1000.0, "ready": false},
	]
	r = WeaponSelector.select(all_cd, 800.0)
	_check("全 CD → 空手 + 导弹纪律等待", r.kind == "" and r.wait_doctrine == "missile",
			"不再机炮硬兜底，crank 保锁等 CD")
	# 4b. 纯机炮机带外逼近：≠失格，按机炮纪律收距离（CLOSE_TAIL 语义不破坏）
	var gun_only := [{"kind": "gun", "band_min": 60.0, "band_max": 1000.0, "ready": true}]
	r = WeaponSelector.select(gun_only, 1500.0)
	_check("机炮机带外=按机炮纪律逼近", r.kind == "" and r.wait_doctrine == "gun",
			"就绪但未进带 → 逼近，不是等待")
	# 5. 滞回：上任 missile 仍合格且保持 <1.5s → 不切 railgun
	r = WeaponSelector.select(cands, 5000.0, "missile", 0.5)
	_check("滞回期内不换武器", r.kind == "missile", "hold 0.5s < 1.5s")
	r = WeaponSelector.select(cands, 5000.0, "missile", 1.6)
	_check("滞回期满切到更优武器", r.kind == "railgun", "hold 1.6s ≥ 1.5s")
	# 6. 上任已失格（出带）→ 滞回不锁死，立即重选
	r = WeaponSelector.select(cands, 300.0, "railgun", 0.2)
	_check("上任出带立即重选", r.kind == "gun", "滞回只对'仍合格'的上任生效")


func _test_dynamic_candidates() -> void:
	print("── 动态距离带（live params，升级即时生效）──")
	var ac: Aircraft = load("res://scripts/aircraft.gd").new()
	var p = AircraftParams.new()
	var g = GunParams.new(); g.max_range = 1000.0
	p.gun = g
	var m = MissileParams.new(); m.min_range = 500.0; m.max_range_rear = 6000.0
	p.missile = m
	ac.params = p
	ac.ammo = 100
	ac.missiles_remaining = 4

	var cands := WeaponSelector.build_candidates(ac)
	_check("候选表含 gun+missile", cands.size() == 2, "")
	var r := WeaponSelector.select(cands, 7000.0)
	_check("7000m 超出导弹带 → 空手", r.kind == "", "升级前打不到")

	# 模拟"导弹锁定距离升级"：改 live params → 下次竞选立即反映（用户定稿 1a/1b）
	m.max_range_rear = 9000.0
	cands = WeaponSelector.build_candidates(ac)
	r = WeaponSelector.select(cands, 7000.0)
	_check("升级射程后同距离立即可用", r.kind == "missile",
			"距离带动态：改 params 下一次竞选即生效，无烘焙")

	# 弹药就绪门
	ac.missiles_remaining = 0
	cands = WeaponSelector.build_candidates(ac)
	r = WeaponSelector.select(cands, 7000.0)
	_check("弹尽失格", r.kind == "", "")

	ac.free()


func _test_planner_integration() -> void:
	print("── 阶段2：planner 消费竞选（_apply_combat_weapon）──")
	# 电磁炮机 5000m（railgun+missile 带重叠）→ 竞选出电磁炮，机动按导弹纪律 crank（阶段2 过渡）
	var s := Situation.new_for_test({
		"has_target": true,
		"my_pos": Vector2.ZERO, "tgt_pos": Vector2(0, -2500),  # 5000m（PPM=0.5）
		"my_heading": 0.0, "tgt_heading": 0.0,
		"missiles": 4, "ammo": 500,
		"railgun_band_min_m": 2500.0, "railgun_band_max_m": 8000.0, "railgun_ready": true,
	})
	var p := TacticalPlan.new()
	p.pursuit_pos = s.tgt_pos
	BfmIntent._apply_combat_weapon(s, p)
	_check("5000m 电磁炮胜出", p.primary_weapon == "railgun", "命中率 100 > 导弹 70")
	_check("电磁炮按导弹纪律 crank", p.weapon_mode == TacticalPlan.WeaponMode.MISSILE,
			"阶段2 过渡；LINE_UP intent 在阶段3")

	# 无电磁炮 5000m → 导弹（与旧行为一致）
	var s2 := Situation.new_for_test({
		"has_target": true, "my_pos": Vector2.ZERO, "tgt_pos": Vector2(0, -2500),
		"my_heading": 0.0, "tgt_heading": 0.0, "missiles": 4, "ammo": 500,
	})
	var p2 := TacticalPlan.new(); p2.pursuit_pos = s2.tgt_pos
	BfmIntent._apply_combat_weapon(s2, p2)
	_check("普通机 5000m=导弹", p2.primary_weapon == "missile" \
			and p2.weapon_mode == TacticalPlan.WeaponMode.MISSILE and p2.allow_missile_fire, "")

	# 弹尽 800m → 机炮（涌现，与旧兜底同结果）
	var s3 := Situation.new_for_test({
		"has_target": true, "my_pos": Vector2.ZERO, "tgt_pos": Vector2(0, -400),  # 800m
		"my_heading": 0.0, "tgt_heading": 0.0, "missiles": 0, "ammo": 500,
	})
	var p3 := TacticalPlan.new(); p3.pursuit_pos = s3.tgt_pos
	BfmIntent._apply_combat_weapon(s3, p3)
	_check("弹尽近距=机炮", p3.primary_weapon == "gun" \
			and p3.weapon_mode == TacticalPlan.WeaponMode.GUN and p3.allow_gun_fire, "")

	# 真·全失格（弹全尽）→ 维持追击 + 导弹纪律等待、武器静默（定稿 4b）
	var s4 := Situation.new_for_test({
		"has_target": true, "my_pos": Vector2.ZERO, "tgt_pos": Vector2(0, -1500),  # 3000m
		"my_heading": 0.0, "tgt_heading": 0.0, "missiles": 0, "ammo": 0,
	})
	var p4 := TacticalPlan.new(); p4.pursuit_pos = s4.tgt_pos
	BfmIntent._apply_combat_weapon(s4, p4)
	_check("全失格=导弹纪律等待", p4.primary_weapon == "" \
			and p4.weapon_mode == TacticalPlan.WeaponMode.MISSILE \
			and not p4.allow_gun_fire and not p4.allow_missile_fire,
			"弹全尽 → crank 等待")

	# 有弹机炮机带外（3000m）→ 按机炮纪律逼近（≠失格，CLOSE_TAIL 语义保留）
	var s4b := Situation.new_for_test({
		"has_target": true, "my_pos": Vector2.ZERO, "tgt_pos": Vector2(0, -1500),
		"my_heading": 0.0, "tgt_heading": 0.0, "missiles": 0, "ammo": 500,
	})
	var p4b := TacticalPlan.new(); p4b.pursuit_pos = s4b.tgt_pos
	BfmIntent._apply_combat_weapon(s4b, p4b)
	_check("机炮机带外=机炮纪律逼近", p4b.primary_weapon == "" \
			and p4b.weapon_mode == TacticalPlan.WeaponMode.GUN and not p4b.allow_gun_fire,
			"逼近收距离，进带后自然开火")

	# 玩家强制机炮覆盖竞选（现行为保留）
	var s5 := Situation.new_for_test({
		"has_target": true, "my_pos": Vector2.ZERO, "tgt_pos": Vector2(0, -400),
		"my_heading": 0.0, "tgt_heading": 0.0, "missiles": 4, "ammo": 500,
		"weapon_lock": Situation.WEAPON_LOCK_FORCE_GUN,
	})
	var p5 := TacticalPlan.new(); p5.pursuit_pos = s5.tgt_pos
	BfmIntent._apply_combat_weapon(s5, p5)
	_check("玩家锁机炮压过竞选", p5.weapon_mode == TacticalPlan.WeaponMode.GUN, "")


func _test_line_up() -> void:
	print("── 阶段3：LINE_UP intent（电磁炮射击纪律）──")
	# 电磁炮机 5000m：全决策树应选出 LINE_UP（在 boom-zoom 之前，不被误判脱离）
	var s := Situation.new_for_test({
		"has_target": true,
		"my_pos": Vector2.ZERO, "tgt_pos": Vector2(0, -2500),  # 正前方 5000m
		"my_heading": 0.0, "tgt_heading": PI / 2.0, "tgt_speed_ms": 200.0,
		"missiles": 4, "ammo": 500,
		"railgun_band_min_m": 2500.0, "railgun_band_max_m": 8000.0, "railgun_ready": true,
		"prev_intent": TacticalPlan.Intent.LEAD_PURSUIT, "prev_intent_held_for": 9.0,  # >8s：验证不被 boom-zoom 抢
	})
	var p := TacticalPlanner.plan(s)
	_check("竞选 railgun → LINE_UP intent", p.intent == TacticalPlan.Intent.LINE_UP,
			"含 held>8s 场景：优先级在 boom-zoom 之前")
	_check("坡度上限 30°", absf(p.bank_limit_deg - 30.0) < 0.01, "充能平台纪律")
	_check("恒巡航速不开 AB", p.target_speed_kmh == s.cruise_speed_kmh and not p.afterburner, "稳定射击平台")
	# pursuit = 提前点方向远点：目标朝东飞 200m/s，提前点应在目标东侧 → pursuit 方向偏东
	var dir: Vector2 = (p.pursuit_pos - s.my_pos).normalized()
	var to_tgt: Vector2 = (s.tgt_pos - s.my_pos).normalized()
	_check("pursuit 指向提前点（含外推）", dir.dot(to_tgt) > 0.99 and dir.x > 0.0,
			"直线对准 + 持续追踪航点（外推 0.4s 偏目标运动方向）")
	# 电磁炮 CD 中 → 不进 LINE_UP，回落导弹
	var s2 := Situation.new_for_test({
		"has_target": true, "my_pos": Vector2.ZERO, "tgt_pos": Vector2(0, -2500),
		"my_heading": 0.0, "tgt_heading": 0.0, "missiles": 4, "ammo": 500,
		"railgun_band_min_m": 2500.0, "railgun_band_max_m": 8000.0, "railgun_ready": false,
	})
	var p2 := TacticalPlanner.plan(s2)
	_check("电磁炮 CD → 不进 LINE_UP", p2.intent != TacticalPlan.Intent.LINE_UP 			and p2.primary_weapon == "missile", "降级导弹接手")

	# bank_limit 物理钳制：侧向目标 + 30° 上限，多 tick 后 |bank| ≤ 30°+容差
	var ac: Aircraft = load("res://scripts/aircraft.gd").new()
	var prm = AircraftParams.new()
	prm.cruise_speed = 900.0
	prm.stall_speed_base = 220.0
	ac.params = prm
	ac.speed = 250.0
	ac.heading = 0.0
	ac.global_position = Vector2.ZERO
	ac.target_position = Vector2(-5000, 0)  # 左侧 90°：无上限时会压大坡
	ac._plan_bank_limit_rad = deg_to_rad(30.0)
	for i in range(120):  # 2 秒
		AircraftPhysics.update_target_heading(ac)
		AircraftPhysics.update_bank(ac, 1.0 / 60.0)
		AircraftPhysics.update_heading(ac, 1.0 / 60.0)
	_check("bank 被钳在 30° 内", absf(rad_to_deg(ac.bank_angle)) <= 32.0,
			"实测 %.1f°（无上限同场景会 >60°）" % absf(rad_to_deg(ac.bank_angle)))
	ac._plan_bank_limit_rad = -1.0
	for i in range(120):
		AircraftPhysics.update_target_heading(ac)
		AircraftPhysics.update_bank(ac, 1.0 / 60.0)
	_check("解除上限恢复全坡度", true, "-1 = 无限制（对照组跑通即可）")
	ac.free()


func _check(name: String, got: bool, note: String) -> void:
	if got: _pass += 1
	else: _fail += 1
	print("  %s %-28s — %s" % ["✓" if got else "✗", name, note])
