extends RefCounted

## 无头武器行为测试（2026-06-13）
## 目的：自动验证 2026-06-13 武器有效性根因修复的三处改动，无需进引擎手测。
##
## 运行（经 BenchRunner，正常项目上下文 → autoload 可用）：
##   godot --headless --path . -- --bench=weapon
##
## 覆盖：
##   A. team_inbound_damage 过滤丢锁导弹 —— 射空的导弹不再封锁队友补射
##   B. spawn_missile 急转发射朝 LOS —— 滚转中发弹不再继承"甩出去的机头"
##   C. _apply_combat_weapon 机炮目标本体守卫 —— 目标侧后离轴时不对空放空
##
## 做法：裸构造对象（不入树、不触发 _ready），直接调被测函数断言输出。

var _pass := 0
var _fail := 0


func run() -> void:
	print("\n════════ 武器行为验证测试 ════════")
	_test_team_inbound_guidance_filter()
	_test_spawn_heading_during_roll()
	_test_chain_warhead_snapshot()
	_test_x44_gun_penetration_snapshot()
	_test_gunship_scans_ground_units()
	_test_gunship_squad_ground_volley()
	_test_gun_target_ahead_guard()
	_test_crank_no_side_flip()
	print("──────── 结果：%d 通过 / %d 失败 ────────" % [_pass, _fail])
	print("════════════════════════════════\n")


func _check(label: String, cond: bool, detail: String = "") -> void:
	if cond:
		_pass += 1
		print("  ✓ %s %s" % [label, detail])
	else:
		_fail += 1
		print("  ✗ %s %s" % [label, detail])


## ── A. team_inbound_damage 只计入仍持有制导的导弹 ──
## 场景：队友 S 对目标 T(50hp) 发两枚 MRM(80dmg)：M1 仍制导、M2 已丢锁(射空)。
## 修复前：返回 160（两枚都算）→ 全队 TEAM_OVERKILL 自封锁，目标却不死。
## 修复后：返回 80（只算 M1）→ M2 射空不再封锁，队友可补射。
func _test_team_inbound_guidance_filter() -> void:
	print("── A. team_inbound 丢锁过滤 ──")
	var mm := MissileManager.new()
	var msl: MissileParams = load("res://resources/default_missile.tres")
	var S = load("res://scripts/aircraft.gd").new()
	S.team = 0
	var T = load("res://scripts/aircraft.gd").new()
	T.team = 1
	T.survivor_missile_damage_cap = 0.0  # 不 cap，用满伤

	var m1 := Missile.new()
	m1.params = msl; m1.source = S; m1.target = T; m1.team = 0
	m1.is_active = true; m1.is_flare_jammed = false; m1.has_guidance = true
	var m2 := Missile.new()
	m2.params = msl; m2.source = S; m2.target = T; m2.team = 0
	m2.is_active = true; m2.is_flare_jammed = false; m2.has_guidance = false  # 丢锁

	mm.add_child(m1)
	mm.add_child(m2)

	var inbound: float = mm.team_inbound_damage(T, 0, null)
	_check("两枚在飞(1 制导/1 丢锁) → 只计制导那枚",
			is_equal_approx(inbound, msl.damage),
			"inbound=%.0f 期望=%.0f(单枚)" % [inbound, msl.damage])

	# 反向：两枚都制导 → 全计入（确保过滤没把正常在飞也漏掉）
	m2.has_guidance = true
	var inbound2: float = mm.team_inbound_damage(T, 0, null)
	_check("两枚都制导 → 全计入",
			is_equal_approx(inbound2, msl.damage * 2.0),
			"inbound=%.0f 期望=%.0f" % [inbound2, msl.damage * 2.0])

	mm.free()  # 连带 free 子 missile + S/T
	S.free(); T.free()


## ── B. 急转/大坡度发射时导弹朝 LOS 出膛 ──
## 场景：发射机机头朝北(0°)，但正以 150°/s 滚转 + 80° 坡度；目标在正东(+90°)。
## 修复前：missile.heading = source.heading = 0°（朝北，与目标差 90° → 盲飞段甩出 FOV 射空）。
## 修复后：检测到急转 → missile.heading 指向 LOS ≈ +90°（朝目标）。
## 对照：平飞(0 坡度/0 滚转)发射 → 仍用机头朝向(0°)，不受影响。
func _test_spawn_heading_during_roll() -> void:
	print("── B. 急转发射朝 LOS ──")
	var mm := MissileManager.new()
	var msl: MissileParams = load("res://resources/default_missile.tres")

	# 目标在正东：bearing = atan2(dx, -dy) = atan2(4000, 0) = +PI/2 (+90°)
	var T = load("res://scripts/aircraft.gd").new()
	T.team = 1; T.altitude = 8000.0
	T.global_position = Vector2(4000.0, 0.0)

	# 急转发射机：机头朝北但在猛滚转
	var S = load("res://scripts/aircraft.gd").new()
	S.team = 0; S.altitude = 8000.0; S.speed = 200.0
	S.global_position = Vector2.ZERO
	S.heading = 0.0
	S.bank_angle = deg_to_rad(80.0)
	S._bank_rate_rad_s = deg_to_rad(150.0)
	S.in_building = false
	var m := mm.spawn_missile(S, T, msl)
	var want := PI * 0.5
	var err_deg := rad_to_deg(absf(_angle_diff(m.heading, want)))
	_check("急转中发射 → heading 指向目标(LOS≈+90°)",
			err_deg < 5.0,
			"heading=%.0f° 目标方位=+90° 误差=%.1f°" % [rad_to_deg(m.heading), err_deg])

	# 对照：平飞发射 → 仍用机头朝向(0°/北)
	var S2 = load("res://scripts/aircraft.gd").new()
	S2.team = 0; S2.altitude = 8000.0; S2.speed = 200.0
	S2.global_position = Vector2.ZERO
	S2.heading = 0.0
	S2.bank_angle = 0.0
	S2._bank_rate_rad_s = 0.0
	S2.in_building = false
	var m2 := mm.spawn_missile(S2, T, msl)
	var err2_deg := rad_to_deg(absf(_angle_diff(m2.heading, 0.0)))
	_check("平飞发射 → heading 维持机头(0°)，不受修复影响",
			err2_deg < 1.0,
			"heading=%.1f° 期望=0°" % rad_to_deg(m2.heading))

	mm.free()
	S.free(); S2.free(); T.free()


## ── C. 连锁弹头的直穿能力按发射者快照，命中后原子切入直飞且同目标只记一次 ──
func _test_chain_warhead_snapshot() -> void:
	print("── C. 连锁弹头直穿快照 + 命中状态 ──")
	var mm := MissileManager.new()
	var msl: MissileParams = load("res://resources/default_missile.tres")
	var source = load("res://scripts/aircraft.gd").new()
	source.team = 0; source.altitude = 8000.0; source.speed = 200.0
	source.missile_chain_active = true
	var target = load("res://scripts/aircraft.gd").new()
	target.team = 1; target.altitude = 8000.0
	target.global_position = Vector2(0.0, -1000.0)

	var missile := mm.spawn_missile(source, target, msl)
	_check("持有连锁弹头的发射者 → 在飞弹获得直穿快照", missile.penetrates_after_hit, "")
	missile.continue_after_penetration(target)
	_check("命中后清目标并关闭制导、保留活动态",
		missile.target == null and not missile.has_guidance and missile.is_active,
		"active=%s guidance=%s" % [str(missile.is_active), str(missile.has_guidance)])
	_check("命中目标进入逐弹去重集合", missile.already_penetrated(target)
		and missile.penetration_hit_count == 1, "hits=%d" % missile.penetration_hit_count)
	missile.remember_penetration_hit(target)
	_check("同一目标重复登记不增加命中数", missile.penetration_hit_count == 1,
		"hits=%d" % missile.penetration_hit_count)

	var plain_source = load("res://scripts/aircraft.gd").new()
	plain_source.team = 0; plain_source.altitude = 8000.0; plain_source.speed = 200.0
	var plain := mm.spawn_missile(plain_source, target, msl)
	_check("未持有技能的发射者 → 普通弹不穿透", not plain.penetrates_after_hit, "")

	mm.free()
	source.free(); plain_source.free(); target.free()


## ── D. X-44 普通机炮弹穿透按发射瞬间快照，CIWS 明确排除 ──
func _test_x44_gun_penetration_snapshot() -> void:
	print("── D. X-44 机炮弹穿透快照 ──")
	var bm := BulletManager.new()
	var source = load("res://scripts/aircraft.gd").new()
	source.team = 0
	source.altitude = 8000.0
	source.gun_bullet_penetration_active = true
	bm.spawn_bullet(Vector2.ZERO, 0.0, 900.0, source, 10.0)
	bm.spawn_bullet(Vector2.ZERO, 0.0, 900.0, source, 10.0, true)
	_check("X-44 普通机炮弹获得穿透快照",
		bool(bm._bullets[0].get("pierces_units", false)), "")
	_check("X-44 CIWS 子弹不穿透",
		not bool(bm._bullets[1].get("pierces_units", false)), "")
	bm.free()
	source.free()


## ── E. 炮艇模式自动扫描 GroundUnit；普通机炮仍仅自动扫描飞机 ──
func _test_gunship_scans_ground_units() -> void:
	print("── E. 炮艇模式对地自动扫描 ──")
	var source := load("res://scripts/aircraft.gd").new() as Aircraft
	source.team = CombatUnit.TEAM_PLAYER
	source.heading = 0.0
	source.global_position = Vector2.ZERO
	source.use_tactical_preference = true
	source.weapon_mode = Aircraft.WeaponMode.GUN
	source.params = AircraftParams.new()
	source.params.gun = GunParams.new()
	source.params.gun.max_range = 1000.0
	source.params.gun.muzzle_velocity = 1000.0
	source.params.gun.fire_cone_half_angle = 180.0
	source.params.gun.spread_angle = 0.0
	source.gunship_mode_active = true

	var ground := GroundUnit.new()
	ground.team = CombatUnit.TEAM_HOSTILE
	ground.global_position = Vector2(400.0, 0.0)  # 正右侧 90°，在 1000m=500px 射程内
	CombatUnit.all_units = [source, ground]
	AircraftWeapons.auto_gun_scan(source)
	_check("炮艇模式无需点名即可侧射地面单位", source.is_firing,
		"firing=%s lead=%.0f°" % [source.is_firing, rad_to_deg(source._gun_lead_heading)])

	# 真正跑梭射执行层：扫描后的下一 tick 即使 planner 把 lead 重置回机头，
	# 已承诺梭也必须继续追随右侧目标，且炮口出生点随射向旋转。
	var bullets := BulletManager.new()
	source.bullet_manager = bullets
	source._sfx_gun_cd = 999.0  # 无头测试不创建一次性 AudioStreamPlayer，避免退出时残留
	AircraftWeapons.update_gun(source, 1.0 / 60.0)
	var first_vel: Vector2 = bullets._bullets[0]["vel"] if not bullets._bullets.is_empty() else Vector2.ZERO
	var first_pos: Vector2 = bullets._bullets[0]["pos"] if not bullets._bullets.is_empty() else Vector2.ZERO
	_check("炮艇侧射首弹朝右而非朝机头", first_vel.x > absf(first_vel.y) * 4.0,
		"vel=%s" % first_vel)
	_check("炮艇侧射炮口随射向旋转", first_pos.x > 15.0 and absf(first_pos.y) < 5.0,
		"spawn=%s" % first_pos)
	source._gun_lead_heading = source.heading  # 模拟下一帧战术计划回写机头方向
	source.is_firing = false
	AircraftWeapons.update_gun(source, 0.05)
	var last_vel: Vector2 = bullets._bullets[-1]["vel"] if not bullets._bullets.is_empty() else Vector2.ZERO
	_check("3Hz 扫描间隔内剩余梭持续追随侧面目标", last_vel.x > absf(last_vel.y) * 4.0,
		"vel=%s rounds=%d" % [last_vel, source._gun_burst_rounds_left])

	# 组合回归：近防炮必须保持正面小锥，不能继承炮艇的 180° 射界。
	var missile_manager := MissileManager.new()
	source.missile_manager = missile_manager
	source.gun_ciws_active = true
	source._ciws_cooldown = 0.0
	bullets._bullets.clear()
	var side_missile := Missile.new()
	side_missile.team = CombatUnit.TEAM_HOSTILE
	side_missile.target = source
	side_missile.is_active = true
	side_missile.global_position = Vector2(200.0, 0.0)
	missile_manager.add_child(side_missile)
	AircraftWeapons.update_ciws(source, 1.0 / 60.0)
	_check("炮艇模式不把近防炮扩成侧向反导", bullets._bullets.is_empty(),
		"ciws_bullets=%d" % bullets._bullets.size())

	var front_missile := Missile.new()
	front_missile.team = CombatUnit.TEAM_HOSTILE
	front_missile.target = source
	front_missile.is_active = true
	front_missile.global_position = Vector2(0.0, -200.0)
	missile_manager.add_child(front_missile)
	source._ciws_cooldown = 0.0
	AircraftWeapons.update_ciws(source, 1.0 / 60.0)
	_check("近防炮原有正面反导仍生效", bullets._bullets.size() == 1
		and bool(bullets._bullets[0].get("is_ciws", false)),
		"ciws_bullets=%d" % bullets._bullets.size())

	missile_manager.free()
	bullets.free()
	source.bullet_manager = null
	source.missile_manager = null
	source.gun_ciws_active = false
	source._gun_burst_rounds_left = 0
	source._fire_cooldown = 0.0

	# 全队 fantasy：AI 僚机即使已有一个射程外空中战术目标，也应让独立炮塔
	# 扫描并锁存圈内更近的地面单位，不要求攻击命令或 use_tactical_preference。
	var wing := load("res://scripts/aircraft.gd").new() as Aircraft
	wing.team = CombatUnit.TEAM_PLAYER
	wing.heading = 0.0
	wing.global_position = Vector2.ZERO
	wing.use_tactical_preference = false
	wing.use_tactical_planner = true
	wing.weapon_mode = Aircraft.WeaponMode.MISSILE  # 独立炮塔不得被 planner 当前主武器模式静默
	wing.params = AircraftParams.new()
	wing.params.gun = GunParams.new()
	wing.params.gun.max_range = 1000.0
	wing.params.gun.muzzle_velocity = 1000.0
	wing.params.gun.fire_cone_half_angle = 180.0
	wing.params.gun.spread_angle = 0.0
	wing.gunship_mode_active = true
	var distant_air := load("res://scripts/aircraft.gd").new() as Aircraft
	distant_air.team = CombatUnit.TEAM_HOSTILE
	distant_air.global_position = Vector2(0.0, -800.0)  # 1600m，超出 1000m 机炮射程
	distant_air.altitude = wing.altitude
	wing.combat_target = distant_air
	CombatUnit.all_units = [wing, ground, distant_air]
	AircraftWeapons.auto_gun_scan(wing)
	_check("AI 僚机炮艇无需战术许可即可扫描地面单位", wing.is_firing,
		"firing=%s" % wing.is_firing)
	_check("炮艇不被射程外空中 combat_target 锁死扫描池",
		wing._auto_gun_target_id == ground.get_instance_id(),
		"scan_id=%d ground_id=%d" % [wing._auto_gun_target_id, ground.get_instance_id()])
	var wing_bullets := BulletManager.new()
	wing.bullet_manager = wing_bullets
	wing._sfx_gun_cd = 999.0
	AircraftWeapons.update_gun(wing, 1.0 / 60.0)
	_check("炮艇整梭优先承诺独立扫描目标而非战术目标",
		wing._gun_burst_target_id == ground.get_instance_id(),
		"burst_id=%d ground_id=%d" % [wing._gun_burst_target_id, ground.get_instance_id()])
	wing_bullets.free()
	wing.bullet_manager = null
	wing.combat_target = null
	distant_air.free()
	wing.free()

	source.gunship_mode_active = false
	source.is_firing = false
	source._auto_gun_scan_timer = 0.0
	AircraftWeapons.auto_gun_scan(source)
	_check("普通机炮不自动扫描地面单位", not source.is_firing,
		"firing=%s" % source.is_firing)

	var air_target := load("res://scripts/aircraft.gd").new() as Aircraft
	air_target.team = CombatUnit.TEAM_HOSTILE
	air_target.global_position = Vector2(0.0, -400.0)
	air_target.altitude = source.altitude
	CombatUnit.all_units = [source, air_target]
	source.is_firing = false
	source._auto_gun_scan_timer = 0.0
	AircraftWeapons.auto_gun_scan(source)
	_check("普通机炮原有对空扫描不回归", source.is_firing,
		"firing=%s" % source.is_firing)

	var hardened := StrategicTarget.new()
	hardened.team = CombatUnit.TEAM_HOSTILE
	hardened.global_position = Vector2(-400.0, 0.0)
	CombatUnit.all_units = [source, hardened]
	source.gunship_mode_active = true
	source.is_firing = false
	source._auto_gun_scan_timer = 0.0
	AircraftWeapons.auto_gun_scan(source)
	_check("炮艇模式不攻击锁定免疫地面目标", not source.is_firing,
		"firing=%s" % source.is_firing)

	CombatUnit.all_units.clear()
	hardened.free()
	air_target.free()
	ground.free()
	source.free()


## ── F. 四机炮艇编队对地独立齐射 ──
func _test_gunship_squad_ground_volley() -> void:
	print("── F. 四机炮艇编队对地独立齐射 ──")
	var bullets := BulletManager.new()
	var gunners: Array[Aircraft] = []
	var grounds: Array[GroundUnit] = []
	var all_units: Array[CombatUnit] = []
	var ground_ids: Dictionary = {}
	var distant_air := load("res://scripts/aircraft.gd").new() as Aircraft
	distant_air.team = CombatUnit.TEAM_HOSTILE
	distant_air.global_position = Vector2(0.0, -1200.0)
	all_units.append(distant_air)
	for i in range(4):
		var ac := load("res://scripts/aircraft.gd").new() as Aircraft
		ac.team = CombatUnit.TEAM_PLAYER
		ac.global_position = Vector2(float(i) * 120.0, 0.0)
		ac.heading = 0.0
		ac.use_tactical_preference = i == 0
		ac.use_tactical_planner = true
		ac.weapon_mode = Aircraft.WeaponMode.GUN if i == 0 else Aircraft.WeaponMode.MISSILE
		ac.params = AircraftParams.new()
		ac.params.gun = GunParams.new()
		ac.params.gun.max_range = 1000.0
		ac.params.gun.muzzle_velocity = 1000.0
		ac.params.gun.fire_cone_half_angle = 180.0
		ac.params.gun.spread_angle = 0.0
		ac.gunship_mode_active = true
		ac.combat_target = distant_air
		ac.bullet_manager = bullets
		ac._sfx_gun_cd = 999.0
		gunners.append(ac)
		all_units.append(ac)
		var ground := GroundUnit.new()
		ground.team = CombatUnit.TEAM_HOSTILE
		ground.global_position = ac.global_position + Vector2(200.0, 0.0)
		grounds.append(ground)
		ground_ids[ground.get_instance_id()] = true
		all_units.append(ground)
	CombatUnit.all_units = all_units
	var all_committed_ground := true
	for i in range(gunners.size()):
		var ac := gunners[i]
		if i == 0:
			AircraftWeapons.auto_gun_scan(ac)
			AircraftWeapons.update_gun(ac, 1.0 / 60.0)
		else:
			# 编队僚机在真实主循环的 LOD0/1/2 提前返回分支走这个入口。
			AircraftWeapons.update_passive_gunship(ac, 1.0 / 60.0)
		if not ground_ids.has(ac._gun_burst_target_id):
			all_committed_ground = false
	_check("当前机 + 3 AI 僚机均独立向圈内地面单位出膛",
		all_committed_ground and bullets._bullets.size() >= 4,
		"ground_committed=%s bullets=%d" % [all_committed_ground, bullets._bullets.size()])
	var aircraft_source := FileAccess.get_file_as_string("res://scripts/aircraft.gd")
	var passive_entry_count := aircraft_source.count("AircraftWeapons.update_passive_gunship(self, delta)")
	_check("编队与屏外 LOD 主循环均接入炮艇专用入口", passive_entry_count >= 5,
		"main_loop_entries=%d" % passive_entry_count)
	CombatUnit.all_units.clear()
	for ac in gunners:
		ac.combat_target = null
		ac.bullet_manager = null
		ac.free()
	for ground in grounds:
		ground.free()
	distant_air.free()
	bullets.free()


## ── G. 机炮要求目标本体大致在机头前方 ──
## 场景：前置预测点落进 5° 火控锥，但目标本体在 60° 离轴(侧后)。
## 修复前：gun_in_cone 只看前置点 → 允许开火 → 对空放空。
## 修复后：额外要求 aim_align ≥ 0.7(<45° 离轴) → 不开火。
## 对照：目标在 10° 离轴(基本对准) → 允许开火。
func _test_gun_target_ahead_guard() -> void:
	print("── G. 机炮目标本体守卫 ──")

	# 前置点：机头前方 3°（在 5° 锥内）。my_pos 原点、my_heading 北(0)。
	var lead_pt := Vector2(sin(deg_to_rad(3.0)) * 1000.0, -cos(deg_to_rad(3.0)) * 1000.0)

	# (1) 目标侧后 60° 离轴：aim_align = cos(60°) = 0.5 < 0.7 → 不开火
	var s_off := _make_gun_situation(0.5)
	var p_off := TacticalPlan.new()
	p_off.pursuit_pos = lead_pt
	BfmIntent._apply_combat_weapon(s_off, p_off)
	_check("目标 60° 离轴(前置点却在锥内) → 不开火",
			p_off.allow_gun_fire == false,
			"allow_gun_fire=%s" % str(p_off.allow_gun_fire))

	# (2) 目标 10° 离轴：aim_align = cos(10°) ≈ 0.985 ≥ 0.7 → 开火
	var s_on := _make_gun_situation(cos(deg_to_rad(10.0)))
	var p_on := TacticalPlan.new()
	p_on.pursuit_pos = lead_pt
	BfmIntent._apply_combat_weapon(s_on, p_on)
	_check("目标 10° 离轴(基本对准) → 开火",
			p_on.allow_gun_fire == true,
			"allow_gun_fire=%s" % str(p_on.allow_gun_fire))


## ── H. SEAM-013：导弹 crank 追踪点不再左右翻号 ──
## 让机头相对目标 LOS 的偏角 nose_off 从 +20° 平滑扫到 −20°（目标横扫过机头），
## 每步调 _missile_engage_pos，记录返回追踪点的方位（aim 航向）。
## 修复前：nose_off 过零时 crank 侧从 +crank 翻到 −crank → aim 航向跳变 ~2×crank(=30°)。
## 修复后：aim 航向随 nose_off 连续变化，相邻步跳变应远小于阈值（无翻号）。
func _test_crank_no_side_flip() -> void:
	print("── H. crank 追踪点无翻号(SEAM-013) ──")
	# 目标锁定、在 crank 包络内（min×1.5=750m < dist=2000m < max×0.7=5600m），雷达半角 30°→crank 15°
	var dist_px := 2000.0 * CombatUnit.PIXELS_PER_METER
	var tgt_pos := Vector2(0.0, -dist_px)  # 正北方向（LOS=0°）
	var max_step_deg := 0.0
	var prev_aim := INF
	var flips := 0
	for off_deg in range(20, -21, -1):  # +20 → -20
		var s := Situation.new()
		s.target_locked = true
		s.dist_m = 2000.0
		s.missile_min_range_m = 500.0
		s.missile_max_range_m = 8000.0
		s.radar_half_angle_deg = 30.0
		s.my_pos = Vector2.ZERO
		s.my_heading = deg_to_rad(float(off_deg))  # LOS=0，机头偏 off_deg → nose_off=off_deg
		s.my_fwd = Vector2(sin(s.my_heading), -cos(s.my_heading))
		s.tgt_pos = tgt_pos
		s.to_target_dir = (tgt_pos - s.my_pos).normalized()
		var aim_pt: Vector2 = BfmIntent._missile_engage_pos(s)
		var aim_hdg := atan2(aim_pt.x, -aim_pt.y)
		if prev_aim != INF:
			var step := rad_to_deg(absf(_angle_diff(aim_hdg, prev_aim)))
			max_step_deg = maxf(max_step_deg, step)
			if step > 10.0:  # 相邻 1° 步进出现 >10° 跳变 = 离散翻号
				flips += 1
		prev_aim = aim_hdg
	_check("nose_off 扫过 0 → aim 航向连续（无离散翻号）",
			flips == 0,
			"翻号次数=%d 最大相邻步进=%.1f°(阈值<10°)" % [flips, max_step_deg])


## 构造一个"机炮模式、距离在枪程内、无导弹包络"的 Situation
func _make_gun_situation(aim_align: float) -> Situation:
	var s := Situation.new()
	s.missiles = 0                 # 无导弹 → 竞选出机炮
	s.ammo = 500                   # 机炮就绪（武器竞选制的弹药门，2026-07-04）
	s.dist_m = 500.0               # 在枪程(1000m)内、>60m
	s.gun_range_m = 1000.0
	s.missile_min_range_m = 500.0
	s.missile_max_range_m = 8000.0
	s.my_pos = Vector2.ZERO
	s.my_heading = 0.0
	s.aim_align = aim_align
	return s


static func _angle_diff(a: float, b: float) -> float:
	var d := fmod(a - b + PI, TAU)
	if d < 0:
		d += TAU
	return d - PI
