extends RefCounted

const SUPER_CANNON_SCRIPT := preload("res://scripts/survivor/tier3_super_cannon_part.gd")
const SIEGE_TANK_SCRIPT := preload("res://scripts/survivor/tier3_siege_tank.gd")

var _pass := 0
var _fail := 0


func run() -> void:
	print("\n════════ 三级战区全局威胁契约 ════════")
	_test_global_tier3_slot()
	_test_ground_profile_map_gate()
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
	zones.set_state(&"C", ZoneData.State.AVAILABLE)
	zones.debug_set_difficulty(&"C", 3, true)
	_check(zones.get_difficulty(&"C") == 3 and zones.active_tier3_zone_ids().size() == 2,
		"测试 seam 只有显式 allow_multiple_tier3 才能构造多源保护场")
	zones.set_state(&"AF_HANEDA", ZoneData.State.AVAILABLE)
	zones.set_airfield_difficulty(&"AF_HANEDA", 3)
	_check(zones.get_difficulty(&"AF_HANEDA") == 2,
		"机场热度定档与普通战区争用同一个 3★名额")


func _test_ground_profile_map_gate() -> void:
	_check(ZoneMission.tier3_ground_profile_for("default", 0.0) == &"super_cannon" \
		and ZoneMission.tier3_ground_profile_for("default", 0.99) == &"super_cannon",
		"东京湾/default 地面 3★固定为超级巨炮")
	_check(ZoneMission.tier3_ground_profile_for("desert_railway_preview", 0.1) == &"siege_tank" \
		and ZoneMission.tier3_ground_profile_for("desert_railway_preview", 0.9) == &"super_cannon",
		"沙漠地面 3★覆盖攻城坦克与超级巨炮两种编成")


func _test_super_cannon_contract() -> void:
	_check(ZoneMission.TIER3_CANNON_PART_OFFSETS.size() == 5 \
		and ZoneMission.TIER3_CANNON_PART_OFFSETS.count(Vector2.ZERO) == 1,
		"巨炮编成恰有四底座加一炮身五个锁定点")
	_check(not SUPER_CANNON_SCRIPT.target_in_range(SUPER_CANNON_SCRIPT.MIN_RANGE_PX - 1.0) \
		and SUPER_CANNON_SCRIPT.target_in_range(SUPER_CANNON_SCRIPT.MIN_RANGE_PX) \
		and SUPER_CANNON_SCRIPT.target_in_range(SUPER_CANNON_SCRIPT.MAX_RANGE_PX),
		"巨炮严格保留近身死区且能覆盖远距离玩家")
	_check(is_equal_approx(SUPER_CANNON_SCRIPT.point_distance_to_segment(
		Vector2(50.0, 20.0), Vector2.ZERO, Vector2(100.0, 0.0)), 20.0),
		"巨炮直线 AOE 与锁存弹道线段共用同一几何")
	var base = SUPER_CANNON_SCRIPT.new()
	base.configure(SUPER_CANNON_SCRIPT.PartKind.BASE, &"TEST")
	var body = SUPER_CANNON_SCRIPT.new()
	body.configure(SUPER_CANNON_SCRIPT.PartKind.BODY, &"TEST")
	_check(base.part_kind == SUPER_CANNON_SCRIPT.PartKind.BASE \
		and body.part_kind == SUPER_CANNON_SCRIPT.PartKind.BODY \
		and base.params == null and body.params == null,
		"只有炮身持有远程状态机；五点本身不偷偷安装 AA/SAM")
	base.free()
	body.free()


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
	source.configure(SUPER_CANNON_SCRIPT.PartKind.BODY, &"TEST")
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
	var body = SUPER_CANNON_SCRIPT.new()
	body.configure(SUPER_CANNON_SCRIPT.PartKind.BODY, &"TEST")
	body.set_meta(&"tier3_special_unit", true)
	mission._retire_tier3_unit(body, true)
	_check(not bool(body.get("_threat_enabled")) and body.is_queued_for_deletion(),
		"BOSS 转场先停火并取消在途巨炮状态，再直接移除特殊来源")
	body.free()
	mission.free()


func _check(ok: bool, label: String) -> void:
	if ok:
		_pass += 1
		print("  ✓ %s" % label)
	else:
		_fail += 1
		print("  ✗ %s" % label)
