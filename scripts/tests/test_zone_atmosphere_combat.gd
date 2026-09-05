extends RefCounted

const ZONE_ATMOSPHERE_SCRIPT := preload("res://scripts/survivor/zone_atmosphere_combat.gd")

var _pass := 0
var _fail := 0


func run() -> void:
	print("\n════════ 正式战区氛围战斗契约 ════════")
	_test_frequency_gate()
	_test_helicopter_compositions()
	_test_helicopter_reward_identity()
	_test_launch_multiplier()
	_test_helicopter_projectile_boundaries()
	_test_nonlethal_target_damage()
	_test_observed_artillery_damage()
	_test_zero_damage_bullet_fast_path()
	_test_preferred_ground_target()
	_test_air_defense_only_targets_aircraft()
	_test_player_lock_state_filter()
	_test_atmosphere_faction_is_fixed()
	_test_artillery_formation_variants()
	_test_port_water_exclusion()
	_test_air_zone_reuse_and_retire()
	_test_live_ally_lookup()
	print("──────── 结果：%d 通过 / %d 失败 ────────" % [_pass, _fail])


func _test_frequency_gate() -> void:
	var atmosphere_source := FileAccess.get_file_as_string(
		"res://scripts/survivor/zone_atmosphere_combat.gd")
	var mission_source := FileAccess.get_file_as_string(
		"res://scripts/survivor/zone_mission.gd")
	var mode_source := FileAccess.get_file_as_string(
		"res://scripts/survivor/survivor_mode.gd")
	_check(atmosphere_source.contains("const ORDINARY_ZONE_CHANCE := 0.30") \
			and atmosphere_source.contains("roll, 0.0, 1.0) < ORDINARY_ZONE_CHANCE"),
		"普通地图气氛战区严格使用 30% 阈值")
	_check(atmosphere_source.contains("&\"ocean_islands_preview\"") \
			and atmosphere_source.contains("&\"desert_railway_preview\"") \
			and ZoneAtmosphereCombat.is_decisive_map("desert_railway_preview") \
			and mode_source.contains("ZoneAtmosphereCombat.is_decisive_map(_map_id)"),
		"海洋群岛与沙漠正式图全覆盖，普通地图不强制")
	_check(mission_source.contains("if _zone_atmosphere_enabled.has(zone_id):") \
			and mission_source.contains("ZONE_ATMOSPHERE_SCRIPT.cached_enabled(") \
			and mission_source.contains("if not _zone_atmosphere_enabled_for_zone(zone_id):"),
		"同一战区只抽一次，刷新继续使用本局缓存结果")


func _test_helicopter_compositions() -> void:
	var signatures: Dictionary = {}
	for roll in [0.0, 0.25, 0.50, 0.75]:
		var sides := ZoneAtmosphereCombat.helicopter_sides_for_roll(roll)
		signatures["%s/%s" % [sides["ally"], sides["hostile"]]] = true
	_check(signatures.size() == 4, "地面气氛层覆盖纯地面、仅友军、仅敌军、双方直升机四种组合")


func _test_helicopter_reward_identity() -> void:
	var controller: Node2D = ZONE_ATMOSPHERE_SCRIPT.new()
	var hostile := Aircraft.new()
	var ally := Aircraft.new()
	controller.call("_mark_actor", hostile, &"TEST", "helicopter", true)
	controller.call("_mark_actor", ally, &"TEST", "helicopter", false)
	_check(not hostile.has_meta(&"no_kill_reward") and int(hostile.get_meta(&"token_cost", -1)) == 0 \
			and bool(ally.get_meta(&"no_kill_reward", false)),
		"敌对气氛直升机保留 AH-64 经验资格，友军关闭奖励且双方均不占 Token")
	hostile.free()
	ally.free()
	controller.free()


func _test_helicopter_projectile_boundaries() -> void:
	var projectile := {
		"ground_targets_only": true,
		"ambient_tgt_nonlethal": true,
		"source": null,
	}
	var aircraft := Aircraft.new()
	var formal := GroundUnit.new()
	formal.hp = 20.0
	formal.set_meta(&"zone_mission", &"TEST")
	var atmosphere := GroundUnit.new()
	atmosphere.hp = 20.0
	var manager := BulletManager.new()
	_check(not BulletManager.projectile_allows_target(projectile, aircraft) \
		and BulletManager.projectile_allows_target(projectile, formal),
		"对地直升机弹丸永不碰撞 Aircraft，只允许 GroundUnit")
	manager._apply_projectile_damage(formal, 99.0, projectile, "gun")
	manager._apply_projectile_damage(atmosphere, 99.0, projectile, "gun")
	_check(formal.hp == 1.0 and not formal.is_destroyed,
		"直升机攻击正式地面 TGT 最低保留 1 HP")
	_check(atmosphere.is_destroyed,
		"直升机可以真实摧毁敌对地面气氛演员")
	manager.free()
	aircraft.free()
	formal.free()
	atmosphere.free()
func _test_launch_multiplier() -> void:
	var source := CombatUnit.new()
	_check(absf(CombatUnit.ambient_damage_multiplier(source) - 1.0) < 0.001,
		"无气氛标记的正式单位保持 100% 伤害")
	source.set_meta(CombatUnit.META_AMBIENT_DAMAGE_MULTIPLIER, 0.0)
	_check(CombatUnit.ambient_damage_multiplier(source) == 0.0,
		"远距气氛武器发射快照为 0%")
	source.set_meta(CombatUnit.META_AMBIENT_DAMAGE_MULTIPLIER, 0.10)
	_check(absf(CombatUnit.ambient_damage_multiplier(source) - 0.10) < 0.001,
		"友军气氛武器近距发射快照为 10%")
	source.set_meta("ambient_damage_lod_exempt", true)
	_check(CombatUnit.ambient_damage_multiplier(source) == 1.0,
		"轰炸任务显式豁免保持 100%")
	source.free()


func _test_nonlethal_target_damage() -> void:
	var ground := GroundUnit.new()
	ground.hp = 12.0
	ground.take_atmosphere_damage(99.0, null, "artillery")
	_check(ground.hp == 1.0 and not ground.is_destroyed,
		"地面 TGT 被气氛炮火压到 1 HP 但不被击毁")
	ground.free()
	var ship := NavalUnit.new()
	ship.hull_hp_max = 100.0
	ship.hull_hp = 8.0
	ship.take_atmosphere_damage_at(99.0, Vector2.ZERO)
	_check(ship.hull_hp == 1.0 and not ship.is_destroyed,
		"舰船 TGT 气氛伤害只磨船体到 1，不触碰击毁链")
	ship.free()


func _test_observed_artillery_damage() -> void:
	var controller: Node2D = ZONE_ATMOSPHERE_SCRIPT.new()
	var source := GroundUnit.new()
	var target := GroundUnit.new()
	source.team = CombatUnit.TEAM_ALLY
	target.team = CombatUnit.TEAM_HOSTILE
	source.global_position = Vector2.ZERO
	target.global_position = Vector2(100.0, 0.0)
	target.hp = 60.0
	controller.set("_engagements", {
		&"TEST-ARTILLERY": {"damage_live": true},
	})
	controller.call("_update_artillery_source", &"TEST-ARTILLERY", source, target, 0.5, true)
	var shells: Array = controller.get("_ballistic_shells")
	var generated: Dictionary = shells[0] if not shells.is_empty() else {}
	_check(not generated.is_empty() and is_equal_approx(float(generated.get("damage", 0.0)), 60.0) \
			and is_equal_approx(float(generated.get("radius_px", 0.0)), 24.0) \
			and Vector2(generated.get("end", Vector2.INF)).distance_to(target.global_position) <= 80.0,
		"近距气氛炮弹使用 60 伤害、24px 直击窗与 80px 散布，不再稳定蹭血")
	var direct_shell := generated.duplicate()
	direct_shell["end"] = target.global_position
	controller.call("_resolve_shell", direct_shell)
	_check(target.is_destroyed and target.hp == 0.0,
		"玩家近距观察时，气氛 SPG 被一发可信直击明确摧毁")
	var miss_target := GroundUnit.new()
	miss_target.team = CombatUnit.TEAM_HOSTILE
	miss_target.global_position = Vector2(100.0, 0.0)
	miss_target.hp = 60.0
	var miss_shell := direct_shell.duplicate()
	miss_shell["target_id"] = miss_target.get_instance_id()
	miss_shell["end"] = miss_target.global_position + Vector2(25.0, 0.0)
	controller.call("_resolve_shell", miss_shell)
	_check(miss_target.hp == 60.0 and not miss_target.is_destroyed,
		"直击窗外的近失弹只演出爆点，不累计假伤害")
	var far_target := GroundUnit.new()
	far_target.team = CombatUnit.TEAM_HOSTILE
	far_target.global_position = Vector2(100.0, 0.0)
	far_target.hp = 60.0
	var far_shell := direct_shell.duplicate()
	far_shell["target_id"] = far_target.get_instance_id()
	far_shell["end"] = far_target.global_position
	far_shell["can_damage"] = false
	controller.call("_resolve_shell", far_shell)
	_check(far_target.hp == 60.0 and not far_target.is_destroyed,
		"玩家远离时即使视觉弹道直击，双方 SPG 仍不在画外互相磨血")
	source.free()
	target.free()
	miss_target.free()
	far_target.free()
	controller.free()


func _test_zero_damage_bullet_fast_path() -> void:
	var manager := BulletManager.new()
	var source := CombatUnit.new()
	source.set_meta(CombatUnit.META_AMBIENT_DAMAGE_MULTIPLIER, 0.0)
	manager.spawn_bullet(Vector2.ZERO, 0.0, 500.0, source, 60.0)
	_check(manager.visual_bullet_count() == 1 and manager._bullets.is_empty(),
		"远距仍生成弹道，但直接进入零碰撞 visual_only 快路径")
	source.free()
	manager.free()


func _test_preferred_ground_target() -> void:
	var gunner := GroundUnit.new()
	gunner.team = CombatUnit.TEAM_HOSTILE
	gunner.params = AircraftParams.new()
	gunner.params.lock_time = 1.0
	var ordinary := Aircraft.new()
	ordinary.team = CombatUnit.TEAM_ALLY
	ordinary.global_position = Vector2(10.0, 0.0)
	var player := Aircraft.new()
	player.team = CombatUnit.TEAM_PLAYER
	player.global_position = Vector2(100.0, 0.0)
	gunner.radar_targets[ordinary] = 2.0
	gunner.radar_targets[player] = 2.0
	gunner.set_meta(CombatUnit.META_PREFERRED_COMBAT_TARGET, player)
	gunner._update_target_selection()
	_check(gunner.combat_target == player,
		"近距 preferred target 优先玩家而不是更近的普通友军")
	var expired := Aircraft.new()
	expired.team = CombatUnit.TEAM_PLAYER
	gunner.radar_targets[expired] = 2.0
	gunner.set_meta(CombatUnit.META_PREFERRED_COMBAT_TARGET, expired)
	gunner.combat_target = expired
	expired.free()
	gunner._update_target_selection()
	_check(gunner.combat_target == ordinary,
		"GroundUnit 会越过已释放的 preferred/current 引用并重新选取存活目标")
	gunner.free()
	ordinary.free()
	player.free()


func _test_air_defense_only_targets_aircraft() -> void:
	var root := Node.new()
	var aa := AAGunUnit.new()
	aa.team = CombatUnit.TEAM_HOSTILE
	aa.params = AircraftParams.new()
	aa.params.gun = GunParams.new()
	aa.params.gun.max_range = 5000.0
	var ground := GroundUnit.new()
	ground.team = CombatUnit.TEAM_ALLY
	ground.global_position = Vector2(10.0, 0.0)
	var aircraft := Aircraft.new()
	aircraft.team = CombatUnit.TEAM_PLAYER
	aircraft.global_position = Vector2(100.0, 0.0)
	root.add_child(aa)
	root.add_child(ground)
	root.add_child(aircraft)
	# AA 正式路径读取 CombatUnit 维护式注册表，不再扫描共同父节点。
	CombatUnit.all_units.append(aa)
	CombatUnit.all_units.append(ground)
	CombatUnit.all_units.append(aircraft)
	aa.combat_target = ground
	aa._update_aa_target_selection(1.0)
	_check(aa.combat_target == aircraft,
		"AA 忽略更近的地面单位，只选择敌方 Aircraft")
	var expired_aa := Aircraft.new()
	aa.combat_target = expired_aa
	expired_aa.free()
	aa._scan_timer = 0.0
	aa._update_aa_target_selection(1.0)
	_check(aa.combat_target == aircraft,
		"AA 会清理已释放的跨帧目标并继续扫描存活 Aircraft")

	var sam := SAMUnit.new()
	sam.team = CombatUnit.TEAM_HOSTILE
	sam.params = AircraftParams.new()
	sam.radar_targets[ground] = 10.0
	sam.radar_targets[aircraft] = 10.0
	sam.set_meta(CombatUnit.META_PREFERRED_COMBAT_TARGET, ground)
	sam._update_target_selection()
	_check(sam.combat_target == aircraft,
		"SAM 忽略 preferred 地面目标，只选择雷达内敌方 Aircraft")
	var expired_sam := Aircraft.new()
	sam.radar_targets[expired_sam] = 10.0
	sam.set_meta(CombatUnit.META_PREFERRED_COMBAT_TARGET, expired_sam)
	sam.combat_target = expired_sam
	expired_sam.free()
	sam._update_target_selection()
	_check(sam.combat_target == aircraft,
		"SAM 选敌会跳过已释放的 preferred/current/radar 引用")
	var expired_launch := Aircraft.new()
	sam.combat_target = expired_launch
	expired_launch.free()
	sam.params.missile = MissileParams.new()
	sam.missile_manager = Node2D.new()
	sam._update_sam_missile(0.0)
	_check(sam.combat_target == null,
		"SAM 发射门会安全清理已释放目标，而不会先执行 is 类型判断")
	sam.missile_manager.free()
	sam.free()
	CombatUnit.all_units.erase(aa)
	CombatUnit.all_units.erase(ground)
	CombatUnit.all_units.erase(aircraft)
	root.free()


func _test_player_lock_state_filter() -> void:
	var player := Aircraft.new()
	player.team = CombatUnit.TEAM_PLAYER
	var ally := GroundUnit.new()
	ally.team = CombatUnit.TEAM_ALLY
	var hostile := GroundUnit.new()
	hostile.team = CombatUnit.TEAM_HOSTILE
	_check(CombatUnit.tracks_player_lock_state(player, hostile) \
		and CombatUnit.tracks_player_lock_state(hostile, player),
		"PLAYER↔HOSTILE 锁定会进入玩家可见/可反应状态")
	_check(not CombatUnit.tracks_player_lock_state(ally, hostile) \
		and not CombatUnit.tracks_player_lock_state(hostile, ally),
		"ALLY↔HOSTILE 仍可战术交战，但不生成玩家锁框状态")
	hostile.accumulate_player_lock_state(ally, 1.0, true)
	_check(not hostile.is_locked and hostile.incoming_lock_progress == 0.0 \
		and hostile.locked_by.is_empty(),
		"AI 互锁汇总不会污染 is_locked / 进度 / locked_by")
	hostile.accumulate_player_lock_state(player, 0.5, false)
	_check(not hostile.is_locked and is_equal_approx(hostile.incoming_lock_progress, 0.5),
		"玩家阵营照射会写入未满锁进度框")
	hostile.accumulate_player_lock_state(player, 1.0, true)
	_check(hostile.is_locked and hostile.locked_by.has(player),
		"玩家阵营满锁会写入红框与锁定来源")
	player.free()
	ally.free()
	hostile.free()


func _test_atmosphere_faction_is_fixed() -> void:
	var actor := GroundUnit.new()
	actor.team = CombatUnit.TEAM_HOSTILE
	actor.set_meta(CombatUnit.META_FACTION_CONVERSION_LOCKED, true)
	var changed := FactionTransition.convert(actor, CombatUnit.TEAM_ALLY, "test_damage_conversion")
	_check(not changed and actor.team == CombatUnit.TEAM_HOSTILE,
		"气氛 SPG 的固定阵营契约拒绝中弹后倒戈")
	actor.free()


func _test_artillery_formation_variants() -> void:
	var signatures: Dictionary = {}
	for formation in [&"staggered", &"echelon", &"wedge"]:
		var offsets := ZoneAtmosphereCombat.artillery_formation_offsets(formation, 3, 200.0, 100.0)
		var unique: Dictionary = {}
		for offset in offsets:
			unique[offset] = true
		_check(offsets.size() == 3 and unique.size() == 3,
			"SPG %s 阵型为三处独立槽位" % formation)
		signatures[str(offsets)] = true
	_check(signatures.size() == 3, "三种 SPG 阵型几何互不相同")
	var first := AtmosphereArtilleryUnit.new()
	var second := AtmosphereArtilleryUnit.new()
	first.configure_ellipse(Vector2.ZERO, Vector2.RIGHT, 340.0, 45.0, 0.0)
	second.configure_ellipse(Vector2.ZERO, Vector2.RIGHT, 340.0, 45.0, TAU / 3.0)
	_check(first.position.distance_to(second.position) > 100.0,
		"错开的初始轨道相位不会让多门 SPG 叠在同一点")
	first.free()
	second.free()


func _test_port_water_exclusion() -> void:
	var port_water_false_positive := Vector2.INF
	var shore_clearance_rejection := Vector2.INF
	var east_coast_safe_land := Vector2.INF
	for y in range(-7000, 7001, 100):
		for x in range(-7000, 7001, 100):
			var p := Vector2(x, y)
			if MapGeography.is_on_solid_land(p) \
					and not MapGeography.is_ground_spawn_safe(p, 0.0):
				port_water_false_positive = p
			if MapGeography.is_ground_spawn_safe(p, 0.0) \
					and not MapGeography.is_ground_spawn_safe(p):
				shore_clearance_rejection = p
			if port_water_false_positive != Vector2.INF \
					and shore_clearance_rejection != Vector2.INF:
				break
		if port_water_false_positive != Vector2.INF \
				and shore_clearance_rejection != Vector2.INF:
			break
	_check(port_water_false_positive != Vector2.INF,
		"港池水面即使命中旧实体陆地交集，也会被精细水面环排除")
	_check(shore_clearance_rejection != Vector2.INF,
		"贴岸点即使中心在陆地，也因周围 50px 不连续而禁止部署")
	for y in range(-7400, 7401, 100):
		for x in range(2500, 7401, 100):
			var p := Vector2(x, y)
			if MapGeography.is_ground_spawn_safe(p):
				east_coast_safe_land = p
				break
		if east_coast_safe_land != Vector2.INF:
			break
	_check(east_coast_safe_land != Vector2.INF,
		"东京湾东岸仍保留可部署安全陆地样本 %s" % east_coast_safe_land)


func _test_air_zone_reuse_and_retire() -> void:
	var controller: Node2D = ZONE_ATMOSPHERE_SCRIPT.new()
	var mode := Node.new()
	controller.call("setup", mode, null)
	var hostile := GroundUnit.new()
	hostile.team = CombatUnit.TEAM_HOSTILE
	var allies: Array = controller.call("register_zone", &"TEST-AIR", "air", {
		"center": Vector2.ZERO,
		"radius": 2500.0,
	}, [hostile], null)
	_check(allies.is_empty() and int(controller.call("active_zone_count")) == 1,
		"空战只登记既有敌军，不新增任何气氛演员")
	_check(CombatUnit.ambient_damage_multiplier(hostile) == 0.0,
		"玩家不在战区时，既有敌军新发武器保持零有效伤害")
	controller.call("retire_zone", &"TEST-AIR")
	_check(int(controller.call("active_zone_count")) == 0 \
		and not hostile.has_meta(CombatUnit.META_AMBIENT_DAMAGE_MULTIPLIER),
		"战区注销会恢复既有敌军并清空控制器登记")
	hostile.free()
	controller.free()
	mode.free()


func _test_live_ally_lookup() -> void:
	var controller: Node2D = ZONE_ATMOSPHERE_SCRIPT.new()
	var freed := GroundUnit.new()
	var destroyed := GroundUnit.new()
	var survivor := GroundUnit.new()
	destroyed.is_destroyed = true
	controller.set("_engagements", {
		&"TEST-GROUND": {
			"kind": "air",
			"hostiles": [freed],
			"allies": [freed, destroyed, survivor],
			"opposition": [freed],
			"damage_live": false,
		},
	})
	freed.free()
	controller.call("update", 0.5, null)
	_check(controller.call("first_live_ally", &"TEST-GROUND") == survivor,
		"跨帧缓存先剔除已释放实例，地面无线电仍返回真实存活友军")
	_check(int(controller.call("actor_count", &"TEST-GROUND")) == 1,
		"已释放和已击毁气氛演员不计入存活数")
	survivor.is_destroyed = true
	_check(controller.call("first_live_ally", &"TEST-GROUND") == null,
		"友军全灭时感谢无线电保持静默")
	destroyed.free()
	survivor.free()
	controller.free()


func _check(ok: bool, label: String) -> void:
	if ok:
		_pass += 1
		print("  ✓ %s" % label)
	else:
		_fail += 1
		print("  ✗ %s" % label)
