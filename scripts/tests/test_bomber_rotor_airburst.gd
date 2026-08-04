extends RefCounted

const StrategicTargetScript = preload("res://scripts/strategic_target.gd")
const BomberMissionScript = preload("res://scripts/survivor/bomber_mission.gd")

var _pass := 0
var _fail := 0
var _spawned: Array = []

func run() -> void:
	print("\n════════ 轰炸 / 旋翼机 / 空爆炮验收 ════════")
	_test_strategic_damage_gate()
	_test_rotorcraft_translation()
	_test_special_projectile_contracts()
	_test_airburst_aim_and_effectiveness()
	_test_naval_flak_mount()
	_test_visual_scale()
	_cleanup()
	print("──────── 结果：%d 通过 / %d 失败 ────────" % [_pass, _fail])
	print("══════════════════════════════════════════\n")

func _check(cond: bool, label: String) -> void:
	if cond:
		_pass += 1
		print("  ✓ %s" % label)
	else:
		_fail += 1
		printerr("  ✗ FAIL: %s" % label)

func _cleanup() -> void:
	for node in _spawned:
		if is_instance_valid(node):
			node.free()
	_spawned.clear()

func _test_strategic_damage_gate() -> void:
	print("── A. 战略硬目标双重权限门 ──")
	var target = StrategicTargetScript.new()
	target.params = load("res://resources/strategic_target_params.tres")
	target.hp = 150.0
	target.team = CombatUnit.TEAM_HOSTILE
	var player := CombatUnit.new()
	player.team = CombatUnit.TEAM_PLAYER
	_spawned.append_array([target, player])
	target.take_damage(999.0, player, "gun")
	_check(is_equal_approx(target.hp, 150.0), "机炮伤害被拒绝")
	target.take_missile_damage(999.0)
	_check(is_equal_approx(target.hp, 150.0), "导弹一击必杀入口被拒绝")
	_check(target.is_lock_immune(), "永久不可锁定")
	target.take_bomber_damage(75.0, CombatUnit.TEAM_PLAYER, player)
	_check(is_equal_approx(target.hp, 75.0), "第一枚敌对轰炸弹保留 75 HP")
	target.take_bomber_damage(75.0, CombatUnit.TEAM_HOSTILE, null)
	_check(is_equal_approx(target.hp, 75.0), "同阵营轰炸弹不伤害")

func _test_rotorcraft_translation() -> void:
	print("── B. 旋翼机速度/机头解耦 ──")
	var ac := Aircraft.new()
	ac.params = load("res://resources/enemy_ah64.tres").duplicate(true)
	ac.heading = 0.0 # 机头朝北
	ac.target_position = Vector2(500, 0) # 向东平移
	ac.rotorcraft_aim_position = Vector2(0, -500) # 继续瞄北
	ac.target_speed_kmh = 180.0
	ac.target_altitude_tier = CombatUnit.AltitudeTier.LOW
	ac.altitude = 2000.0
	_spawned.append(ac)
	AircraftPhysics.update_rotorcraft(ac, 1.0)
	_check(ac.global_position.x > 0.0 and absf(ac.global_position.y) < 0.01, "可沿机头侧向平移")
	var velocity_heading := atan2(ac.rotorcraft_velocity.x, -ac.rotorcraft_velocity.y)
	_check(absf(rad_to_deg(ac.heading)) < 10.0 and absf(angle_difference(ac.heading, velocity_heading)) > deg_to_rad(60.0),
		"平移时机头仍朝瞄准点而非速度方向")
	ac.target_position = ac.global_position
	ac.target_speed_kmh = 0.0
	for i in range(4):
		AircraftPhysics.update_rotorcraft(ac, 1.0)
	_check(ac.speed <= 0.01, "可刹停至悬停")

func _test_special_projectile_contracts() -> void:
	print("── C. 炸弹/空爆弹数据契约 ──")
	var bm := BulletManager.new()
	var src := CombatUnit.new()
	src.team = CombatUnit.TEAM_HOSTILE
	src.altitude = 10000.0
	_spawned.append_array([bm, src])
	bm.spawn_bomber_bomb(Vector2.ZERO, Vector2(100, 0), src, 3.2, 160.0, 75.0)
	_check(bm._bombs.size() == 1 and is_equal_approx(float(bm._bombs[0]["radius_px"]), 80.0),
		"炸弹 160m 半径正确换算为 80px")
	bm.spawn_airburst_shell(Vector2.ZERO, 0.0, 450.0, src, 2.0, 5500.0, 220.0, 75.0, 7)
	_check(bm._airburst_shells.size() == 1 and is_equal_approx(float(bm._airburst_shells[0]["radius_px"]), 110.0),
		"空爆 220m 半径正确换算为 110px")
	_check(int(bm._airburst_shells[0]["burst_id"]) == 7, "三连发共享 burst id")
	var mission = BomberMissionScript.new()
	_spawned.append(mission)
	var exit := mission._egress_point(PackedVector2Array([Vector2.ZERO, Vector2(0, -1000)]), Vector2.ZERO)
	_check(exit.y < -5000.0, "任务完成后沿末段继续飞出地图")

func _test_airburst_aim_and_effectiveness() -> void:
	print("── D. 空爆炮射向约束 / 3000m 横穿实效 ──")
	var gun := AirburstAAUnit.new()
	var target := Aircraft.new()
	var bm := BulletManager.new()
	gun.bullet_manager = bm
	gun.ammo = 10000
	gun.team = CombatUnit.TEAM_HOSTILE
	gun.global_position = Vector2.ZERO
	target.params = AircraftParams.new()
	target.team = CombatUnit.TEAM_PLAYER
	target.global_position = Vector2(0.0, -3000.0 * CombatUnit.PIXELS_PER_METER)
	target.heading = PI * 0.5 # 向东横穿
	target.speed = 250.0
	target.altitude = 5500.0
	_spawned.append_array([gun, target, bm])

	var target_vel := Vector2(sin(target.heading), -cos(target.heading)) \
			* target.speed * CombatUnit.PIXELS_PER_METER
	var nominal_travel := gun.global_position.distance_to(target.global_position) \
			/ (AirburstAAUnit.SHELL_SPEED_MS * CombatUnit.PIXELS_PER_METER)
	var nominal_aim := target.global_position + target_vel * nominal_travel
	var nominal_heading := atan2(nominal_aim.x, -nominal_aim.y)
	var max_departure_error := 0.0
	var group_hits := 0
	var groups := 240
	seed(20260803)
	for group in range(groups):
		bm._airburst_shells.clear()
		gun._begin_burst(target)
		var group_hit := false
		for shell_index in range(AirburstAAUnit.BURST_SIZE):
			gun._fire_airburst_shell()
			var shell: Dictionary = bm._airburst_shells.back()
			var shell_vel: Vector2 = shell["vel"]
			var shell_heading := atan2(shell_vel.x, -shell_vel.y)
			max_departure_error = maxf(max_departure_error,
				absf(angle_difference(nominal_heading, shell_heading)))
			var fuse_time := float(shell["life"])
			var detonation_pos: Vector2 = shell["pos"] + shell_vel * fuse_time
			# 后两发仍用第一发冻结解，目标则在 0.25s 组内间隔中继续飞行。
			var target_at_burst := target.global_position + target_vel \
					* (fuse_time + float(shell_index) * AirburstAAUnit.BURST_INTERVAL)
			if detonation_pos.distance_to(target_at_burst) <= float(shell["radius_px"]):
				group_hit = true
		if group_hit:
			group_hits += 1
	var hit_rate := float(group_hits) / float(groups)
	_check(max_departure_error <= AirburstAAUnit.MAX_GROUP_AIM_ERROR \
			+ AirburstAAUnit.MAX_SHELL_AIM_JITTER + deg_to_rad(0.1),
		"所有炮弹都朝冻结预瞄空域发射（随机偏角 ≤ 8.6°）")
	_check(group_hits > 0 and group_hits < groups,
		"3000m / 250m·s 横穿样本同时存在命中组和落空组")
	print("    实测：%d 组中 %d 组至少一发覆盖，组命中率 %.1f%%；最大随机偏角 %.2f°" % [
		groups, group_hits, hit_rate * 100.0, rad_to_deg(max_departure_error)])
	randomize()

func _test_naval_flak_mount() -> void:
	print("── E. DDG 舰载 Flak 挂点 / 炮组状态 ──")
	var params: NavalParams = load("res://resources/naval/destroyer_ddg.tres").duplicate(true)
	var type_counts := {
		WeaponMountParams.WeaponType.VLS_SALVO: 0,
		WeaponMountParams.WeaponType.CIWS: 0,
		WeaponMountParams.WeaponType.NAVAL_FLAK: 0,
	}
	for cfg in params.mount_configs:
		if type_counts.has(cfg.weapon_type):
			type_counts[cfg.weapon_type] = int(type_counts[cfg.weapon_type]) + 1
	_check(params.mount_configs.size() == 4
			and int(type_counts[WeaponMountParams.WeaponType.VLS_SALVO]) == 2
			and int(type_counts[WeaponMountParams.WeaponType.CIWS]) == 1
			and int(type_counts[WeaponMountParams.WeaponType.NAVAL_FLAK]) == 1,
		"DDG 固定为 2×VLS + 1×CIWS + 1×Flak（总挂点仍为 4）")

	var ship := NavalUnit.new()
	ship.params = params
	ship.team = CombatUnit.TEAM_HOSTILE
	ship.heading = 0.0
	var flak_mount: WeaponMount = null
	for cfg in params.mount_configs:
		var mount := WeaponMount.new()
		mount.initialize(cfg)
		ship.mounts.append(mount)
		if cfg.weapon_type == WeaponMountParams.WeaponType.NAVAL_FLAK:
			flak_mount = mount
	var bullets := BulletManager.new()
	ship.bullet_manager = bullets
	var target := Aircraft.new()
	target.params = AircraftParams.new()
	target.team = CombatUnit.TEAM_PLAYER
	target.global_position = Vector2(0.0, -3000.0 * CombatUnit.PIXELS_PER_METER)
	target.heading = PI * 0.5
	target.speed = 250.0
	target.altitude = 5500.0
	_spawned.append_array([ship, bullets, target])
	CombatUnit.all_units = [ship, target]
	seed(20260804)

	ship._update_subsystems(1.0 / 60.0)
	_check(flak_mount != null and is_equal_approx(flak_mount.hp, 30.0),
		"Flak 原位继承被替换 CIWS 的 30 HP")
	_check(bullets._airburst_shells.size() == 1 and flak_mount.flak_remaining == 2
			and is_equal_approx(flak_mount.fire_cooldown, NavalWeapons.NAVAL_FLAK_BURST_COOLDOWN),
		"捕获目标后首弹立即出膛并冻结余下两发，6s 冷却从炮组开始计时")
	_check(bullets._bullets.is_empty()
			and bullets._airburst_shells[0]["source"] == ship,
		"舰载 Flak 走 airburst 管线且不生成 CIWS 拦截弹")

	ship._update_subsystems(0.24)
	ship._update_subsystems(0.02)
	ship._update_subsystems(0.25)
	_check(bullets._airburst_shells.size() == 3 and flak_mount.flak_remaining == 0,
		"后两发按 0.25s 组内间隔完成三连发")
	ship._update_subsystems(5.48)
	_check(bullets._airburst_shells.size() == 3,
		"6s 组间冷却结束前不得开始下一组")
	CombatUnit.all_units = []
	randomize()

func _test_visual_scale() -> void:
	print("── F. 统一视觉尺度 ──")
	var fighter := Aircraft.new()
	fighter.params = AircraftParams.new()
	fighter.altitude = 5500.0
	var bomber := Aircraft.new()
	bomber.params = load("res://resources/enemy_tu160.tres")
	bomber.set_meta("silhouette", "bomber")
	bomber.altitude = 5500.0
	_spawned.append_array([fighter, bomber])
	var fighter_extent := 36.0 * AircraftRenderer.visual_model_scale(fighter)
	var bomber_extent := 70.0 * AircraftRenderer.visual_model_scale(bomber)
	_check(bomber_extent > fighter_extent,
		"Tu-160 视觉轮廓大于普通战斗机")
	_check(is_equal_approx(AircraftRenderer.altitude_base_scale(fighter), 1.0), "MID 高度倍率为 1.0")
