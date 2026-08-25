extends RefCounted

const SUPER_CANNON_SCRIPT := preload("res://scripts/survivor/tier3_super_cannon_part.gd")
const SIEGE_TANK_SCRIPT := preload("res://scripts/survivor/tier3_siege_tank.gd")

var _pass := 0
var _fail := 0


func run() -> void:
	print("\n════════ 三级战区全局威胁契约 ════════")
	_test_global_tier3_slot()
	_test_f6_atomic_profile_preset()
	_test_ground_profile_map_gate()
	_test_profile_text_contract()
	_test_super_cannon_contract()
	_test_siege_tank_contract()
	_test_long_range_vls_clone()
	_test_threat_neutralizes_before_mission_completion()
	_test_boss_transition_retirement()
	print("──────── 结果：%d 通过 / %d 失败 ────────" % [_pass, _fail])


func _test_global_tier3_slot() -> void:
	var zones := ZoneData.new(Callable(), false, true)
	zones.set_state(&"A", ZoneData.State.AVAILABLE)
	zones.set_state(&"B", ZoneData.State.AVAILABLE)
	zones.debug_set_difficulty(&"A", 3)
	zones.debug_set_difficulty(&"B", 3)
	_check(zones.get_difficulty(&"A") == 3 and zones.get_difficulty(&"B") == 2 \
		and zones.active_tier3_zone_ids() == [&"A"],
		"普通/Debug 开放共享唯一 3★槽，第二个候选降为 2★")
	zones.debug_mark_cleared(&"A")
	zones.debug_set_difficulty(&"B", 3)
	_check(zones.get_difficulty(&"B") == 3 and not zones.has_active_tier3(&"B"),
		"解决旧 3★后只向未来重定档释放名额")
	zones.set_state(&"D", ZoneData.State.AVAILABLE)
	var displaced := zones.debug_claim_tier3_slot(&"D")
	_check(displaced == [&"B"] and zones.get_difficulty(&"B") == 2 \
		and zones.get_difficulty(&"D") == 3 \
		and zones.active_tier3_zone_ids() == [&"D"],
		"F6 强制验收把唯一 3★槽从旧区转移到指定区")
	zones.set_state(&"C", ZoneData.State.AVAILABLE)
	zones.debug_set_difficulty(&"C", 3, true)
	_check(zones.get_difficulty(&"C") == 3 and zones.active_tier3_zone_ids().size() == 2,
		"测试 seam 只有显式 allow_multiple_tier3 才能构造多源保护场")
	zones.set_state(&"AF_HANEDA", ZoneData.State.AVAILABLE)
	zones.set_airfield_difficulty(&"AF_HANEDA", 3)
	_check(zones.get_difficulty(&"AF_HANEDA") == 2,
		"机场热度定档与普通战区争用同一个 3★名额")


func _test_f6_atomic_profile_preset() -> void:
	var cannon := SurvivorDebugZone.normalize_zone_change_request("air", 1, &"super_cannon")
	_check(cannon["mission_type"] == "ground" \
		and int(cannon["difficulty"]) == ZoneData.DIFFICULTY_MAX \
		and StringName(cannon["tier3_profile"]) == &"super_cannon",
		"F6 巨炮选项原子归一为 ground + 3★ + super_cannon")
	var automatic := SurvivorDebugZone.normalize_zone_change_request("naval", 2, &"auto")
	_check(automatic["mission_type"] == "naval" and int(automatic["difficulty"]) == 2 \
		and StringName(automatic["tier3_profile"]) == &"auto",
		"F6 自动 profile 保留用户显式选择的任务类型与星级")


func _test_ground_profile_map_gate() -> void:
	_check(ZoneMission.tier3_ground_profile_for("default", 0.0) == &"super_cannon" \
		and ZoneMission.tier3_ground_profile_for("default", 0.99) == &"super_cannon",
		"东京湾/default 地面 3★固定为超级巨炮")
	_check(ZoneMission.tier3_ground_profile_for("desert_railway_preview", 0.1) == &"siege_tank" \
		and ZoneMission.tier3_ground_profile_for("desert_railway_preview", 0.9) == &"super_cannon",
		"沙漠地面 3★覆盖攻城坦克与超级巨炮两种编成")


func _test_profile_text_contract() -> void:
	var mission := ZoneMission.new()
	var first := mission.resolve_tier3_profile(&"A", "ground", "desert_railway_preview", 0.1)
	var cached := mission.resolve_tier3_profile(&"A", "ground", "desert_railway_preview", 0.9)
	_check(first == &"siege_tank" and cached == first,
		"3★ profile 首次裁决后固化，Tab 简报与实体生成不会各抽一次")
	_check(mission.resolve_tier3_profile(&"A", "squadron") == &"deadair",
		"地形安全门改变 mission_type 时会丢弃旧简介并跟随真实空战 profile")
	var profiles: Array[StringName] = [
		&"super_cannon", &"siege_tank", &"long_range_vls", &"deadair"]
	var desc_keys: Dictionary = {}
	var start_keys: Dictionary = {}
	for profile in profiles:
		desc_keys[ZoneMission.mission_desc_key_for("ground", profile)] = true
		start_keys[ZoneMission.mission_started_fmt_key_for("ground", profile)] = true
	_check(desc_keys.size() == 4 and start_keys.size() == 4,
		"四类 3★任务各有独立 Tab 介绍与任务开始提示")
	_check(ZoneMission.mission_desc_key_for("naval") == "ZONE_MISSION_NAVAL" \
		and ZoneMission.mission_started_fmt_key_for("naval") \
			== "ZONE_MISSION_STARTED_NAVAL_FMT",
		"普通战区继续按真实 mission_type 选择对应介绍")
	mission.free()


func _test_super_cannon_contract() -> void:
	_check(ZoneMission.TIER3_CANNON_FOOTPRINT_OFFSETS.size() == 5 \
		and ZoneMission.TIER3_CANNON_FOOTPRINT_OFFSETS.count(Vector2.ZERO) == 1,
		"巨炮只生成一个 TGT，但部署仍校验完整底座占地")
	_check(not SUPER_CANNON_SCRIPT.target_in_range(SUPER_CANNON_SCRIPT.MIN_RANGE_PX - 1.0) \
		and SUPER_CANNON_SCRIPT.target_in_range(SUPER_CANNON_SCRIPT.MIN_RANGE_PX) \
		and SUPER_CANNON_SCRIPT.target_in_range(SUPER_CANNON_SCRIPT.MAX_RANGE_PX) \
		and SUPER_CANNON_SCRIPT.MAX_RANGE_PX == 44000.0,
		"巨炮严格保留近身死区并把远端射程扩到 88km")
	_check(is_equal_approx(SUPER_CANNON_SCRIPT.point_distance_to_segment(
		Vector2(50.0, 20.0), Vector2.ZERO, Vector2(100.0, 0.0)), 20.0),
		"巨炮直线 AOE 与锁存弹道线段共用同一几何")
	var cannon = SUPER_CANNON_SCRIPT.new()
	cannon.configure(&"TEST")
	var cannon_params := AircraftParams.new()
	cannon_params.display_name = SUPER_CANNON_SCRIPT.DISPLAY_NAME
	cannon.params = cannon_params
	_check(cannon._status_label_lines(true)[0] == "AURORA LANCE" \
		and cannon.ammo == 0 \
		and cannon.target_position == Vector2.INF,
		"巨炮战术状态栏固定使用英文 AURORA LANCE，且不伪装成普通 GUN")
	cannon._set_body_heading(0.75)
	_check(is_equal_approx(cannon.heading, 0.75) \
		and is_zero_approx(cannon.rotation),
		"固定基盘不随 heading 旋转，只有上层炮架消费朝向")
	_check(SUPER_CANNON_SCRIPT.AOE_RADIUS_PX == 90.0 \
		and SUPER_CANNON_SCRIPT.WARNING_FILL_S == 4.0 \
		and SUPER_CANNON_SCRIPT.WARNING_FLASH_S == 1.5 \
		and is_equal_approx(SUPER_CANNON_SCRIPT.warning_width_px(
			SUPER_CANNON_SCRIPT.WARNING_S), 4.0) \
		and is_equal_approx(SUPER_CANNON_SCRIPT.warning_width_px(
			SUPER_CANNON_SCRIPT.WARNING_FLASH_S), 180.0) \
		and not SUPER_CANNON_SCRIPT.warning_is_flashing(
			SUPER_CANNON_SCRIPT.WARNING_S) \
		and SUPER_CANNON_SCRIPT.warning_is_flashing(
			SUPER_CANNON_SCRIPT.WARNING_FLASH_S),
		"危险带减半并严格分为 4.0s 渐宽 + 1.5s 满宽闪烁")

	var leader := Aircraft.new()
	leader.team = CombatUnit.TEAM_PLAYER
	leader.callsign = "LEAD"
	leader.hp = 100.0
	leader.global_position = Vector2(0.0, -3000.0)
	leader.add_child(AIController.new())
	var wingman := Aircraft.new()
	wingman.team = CombatUnit.TEAM_PLAYER
	wingman.callsign = "WING"
	wingman.hp = 100.0
	wingman.global_position = Vector2(70.0, -4000.0)
	wingman.add_child(AIController.new())
	var outsider := Aircraft.new()
	outsider.team = CombatUnit.TEAM_PLAYER
	outsider.callsign = "OUT"
	outsider.hp = 100.0
	outsider.global_position = Vector2(120.0, -3500.0)
	var squad := SquadFactory.create()
	SquadFactory.register_leader(squad, leader)
	SquadFactory.register_wingman(squad, wingman)
	var candidates: Array[Aircraft] = cannon._eligible_aim_targets(leader)
	_check(candidates.size() == 2 and leader in candidates and wingman in candidates \
		and outsider not in candidates,
		"每轮瞄准只从存活长机与僚机中随机选取，不把同阵营外部单位混入目标池")

	CombatUnit.all_units.append(leader)
	CombatUnit.all_units.append(wingman)
	CombatUnit.all_units.append(outsider)
	cannon._begin_warning(Vector2(0.0, -5000.0), "LEAD")
	cannon._update_body_fire(SUPER_CANNON_SCRIPT.WARNING_FILL_S)
	_check(leader.hp == 100.0 and wingman.hp == 100.0 and outsider.hp == 100.0 \
		and int(cannon.get("_fire_state")) == SUPER_CANNON_SCRIPT.FireState.WARNING \
		and is_equal_approx(float(cannon.get("_warning_s")),
			SUPER_CANNON_SCRIPT.WARNING_FLASH_S),
		"4.0s 渐宽结束只进入满宽闪烁，不提前结算伤害")
	cannon._update_body_fire(SUPER_CANNON_SCRIPT.WARNING_FLASH_S)
	_check(leader.hp == 55.0 and wingman.hp == 55.0 and outsider.hp == 100.0 \
		and int(cannon.get("_fire_state")) == SUPER_CANNON_SCRIPT.FireState.FLIGHT \
		and float(cannon.get("_shot_progress_px")) == 0.0,
		"满宽闪烁结束同拍只结算 90px 半径危险带，弹迹尚未飞行也已受伤")
	_check(SUPER_CANNON_SCRIPT.PROJECTILE_SPEED_PX_S == 12000.0 \
		and SUPER_CANNON_SCRIPT.SHOT_OVERSHOOT_PX == 6000.0 \
		and SUPER_CANNON_SCRIPT.END_FADE_START < 1.0,
		"高速长条弹迹、目标后延伸与末端淡出参数集中可审计")
	CombatUnit.all_units.erase(leader)
	CombatUnit.all_units.erase(wingman)
	CombatUnit.all_units.erase(outsider)
	leader.free()
	wingman.free()
	outsider.free()
	cannon.free()


func _test_siege_tank_contract() -> void:
	var world := Node.new()
	var bullet_manager := BulletManager.new()
	var missile_manager := MissileManager.new()
	var tank = SIEGE_TANK_SCRIPT.new()
	tank.team = CombatUnit.TEAM_HOSTILE
	tank.configure(&"TEST")
	world.add_child(tank)
	tank.arm_mounts(world, bullet_manager, missile_manager)
	var mounts: Array = tank.get("_mounts")
	var ciws_count := 0
	var sam_count := 0
	var flak_count := 0
	var long_sam_ok := false
	for mount in mounts:
		if mount is AirburstAAUnit:
			flak_count += 1
		elif mount is SAMUnit:
			sam_count += 1
			long_sam_ok = mount.params != null and mount.params.missile != null \
				and mount.params.missile.max_range_rear == 32000.0 \
				and mount.local_mount_offset.length() < 30.0
		elif mount is AAGunUnit:
			ciws_count += 1
	_check(mounts.size() == 4 and ciws_count == 2 and sam_count == 1 and flak_count == 1,
		"攻城坦克挂载严格为 2×CIWS + 1×SAM + 1×空爆")
	_check(long_sam_ok, "SAM 的远来自 32km 武器射程，挂点仍贴在正常车体位置")
	var target := GroundUnit.new()
	target.team = CombatUnit.TEAM_ALLY
	target.hp = 80.0
	target.global_position = Vector2(300.0, 0.0)
	target.set_meta(&"zone_atmosphere_role", &"artillery")
	target.set_meta(&"zone_atmosphere_zone", &"TEST")
	CombatUnit.all_units.append(target)
	tank._begin_shell(target)
	var shell: Dictionary = tank.get("_shell")
	shell["end"] = target.global_position
	shell["age"] = shell["duration"]
	tank.set("_shell", shell)
	tank._update_shell(0.0)
	_check(target.is_destroyed, "攻城坦克主炮可信直击一炮摧毁一个气氛地面目标")
	CombatUnit.all_units.erase(target)
	target.free()
	tank.cease_tier3_threat()
	_check((tank.get("_mounts") as Array).is_empty(), "来源停止时四个防空挂点同拍消失")
	bullet_manager.free()
	missile_manager.free()
	world.free()


func _test_long_range_vls_clone() -> void:
	var source: NavalParams = load("res://resources/naval/destroyer_ddg.tres")
	var ordinary_range := 0.0
	for mount in source.mount_configs:
		if mount.weapon_type == WeaponMountParams.WeaponType.VLS_SALVO:
			ordinary_range = (mount.weapon_params as MissileParams).max_range_rear
			break
	var clone := ZoneMission._tier3_naval_params(source) as NavalParams
	var extended := true
	var vls_count := 0
	for mount in clone.mount_configs:
		if mount.weapon_type != WeaponMountParams.WeaponType.VLS_SALVO:
			continue
		vls_count += 1
		var missile := mount.weapon_params as MissileParams
		extended = extended and missile.max_range_rear == ZoneMission.TIER3_VLS_RANGE_M \
			and missile.max_lifetime >= ZoneMission.TIER3_VLS_LIFETIME_S
	_check(vls_count == 2 and extended and clone.has_meta(&"tier3_vls_source"),
		"3★ DDG 的真实 VLS 弹体获得 40km 航程与配套寿命")
	var source_still_ordinary := true
	for mount in source.mount_configs:
		if mount.weapon_type == WeaponMountParams.WeaponType.VLS_SALVO:
			source_still_ordinary = source_still_ordinary \
				and (mount.weapon_params as MissileParams).max_range_rear == ordinary_range
	_check(source_still_ordinary, "远程 VLS 使用深拷贝，不污染普通 1★/2★舰队资源")


func _test_threat_neutralizes_before_mission_completion() -> void:
	var mission := ZoneMission.new()
	var source = SUPER_CANNON_SCRIPT.new()
	source.configure(&"TEST")
	source.set_meta(&"tier3_threat_source", true)
	var ordinary := GroundUnit.new()
	mission._spawned_zones[&"TEST"] = [source, ordinary]
	var edges: Array[bool] = []
	mission.tier3_threat_changed.connect(func(_zone: StringName, _profile: StringName,
			active: bool): edges.append(active))
	mission._register_tier3_sources(&"TEST", &"super_cannon")
	source.is_destroyed = true
	mission._update_tier3_source_states(0.25)
	_check(edges == [true, false] and not mission._all_zone_units_destroyed(&"TEST"),
		"高威胁来源被毁即解除效果，但普通 TGT 存活时任务不会提前完成")
	ordinary.is_destroyed = true
	_check(mission._all_zone_units_destroyed(&"TEST"),
		"任务完成条件仍是该战区全部正式 TGT 清空")
	source.free()
	ordinary.free()
	mission.free()


func _test_boss_transition_retirement() -> void:
	var mission := ZoneMission.new()
	var cannon = SUPER_CANNON_SCRIPT.new()
	cannon.configure(&"TEST")
	cannon.set_meta(&"tier3_special_unit", true)
	mission._retire_tier3_unit(cannon, true)
	_check(not bool(cannon.get("_threat_enabled")) and cannon.is_queued_for_deletion(),
		"BOSS 转场先停火并取消在途巨炮状态，再直接移除特殊来源")
	cannon.free()
	mission.free()


func _check(ok: bool, label: String) -> void:
	if ok:
		_pass += 1
		print("  ✓ %s" % label)
	else:
		_fail += 1
		print("  ✗ %s" % label)
