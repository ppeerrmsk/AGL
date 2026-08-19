extends RefCounted

## BOSS 通关强化分层 + Mother Goose VLS 定距空爆 + MQ-111 累计拦截/过热回归。
## 运行：bench/run.cmd boss_progression

var _pass: int = 0
var _fail: int = 0


class LaserHost:
	extends Node2D
	var team: int = CombatUnit.TEAM_HOSTILE
	var equipment_state: Dictionary = {}
	var missile_manager: MissileManager = null

	func is_player_squad() -> bool:
		return false

func run() -> void:
	print("\n════════ BOSS 通关强化测试 ════════")
	_test_progression_counts()
	_test_wraith_support_deployment()
	_test_carrier_composition()
	_test_goose_variant_gate()
	_test_goose_vls_distance_airburst()
	_test_mq111_cumulative_intercept()
	_test_mq111_player_heat_cycle()
	print("──────── 结果：%d 通过 / %d 失败 ────────" % [_pass, _fail])

func _test_progression_counts() -> void:
	var enc := BossEncounter.new()
	enc.configure_progression(-3)
	_check("负次数钳到 0", enc.prior_defeats == 0, "got=%d" % enc.prior_defeats)
	enc.configure_progression(2)
	_check("完整次数保留", enc.prior_defeats == 2, "got=%d" % enc.prior_defeats)
	_check("Wraith 初见无支援", F47AceSquad.support_count_for_progression(0) == 0, "")
	_check("Wraith 首败后双支援", F47AceSquad.support_count_for_progression(1) == 2, "")
	_check("Wraith 二败暂沿用双支援", F47AceSquad.support_count_for_progression(2) == 2, "")

func _test_wraith_support_deployment() -> void:
	var player_pos := Vector2.ZERO
	var wraith_center := Vector2(0.0, -3600.0)
	var positions := F47AceSquad.support_spawn_positions(player_pos, wraith_center, Vector2.UP)
	_check("Wraith 支援几何返回双机", positions.size() == 2, str(positions))
	if positions.size() != 2:
		return
	var away := (wraith_center - player_pos).normalized()
	var lateral := Vector2(-away.y, away.x)
	var center := (positions[0] + positions[1]) * 0.5
	_check("YF-23 位于 Wraith 后方", (center - wraith_center).dot(away)
		>= F47AceSquad.YF23_SUPPORT_TRAILING_PX - 0.1, "center=%s" % center)
	_check("YF-23 不在玩家近处闪现", center.distance_to(player_pos)
		>= F47AceSquad.YF23_SUPPORT_MIN_PLAYER_DISTANCE_PX, "distance=%.1f" % center.length())
	_check("YF-23 在后方轴两侧对称潜伏",
		is_equal_approx((positions[0] - center).dot(lateral),
			-(positions[1] - center).dot(lateral)), str(positions))
	var support := Aircraft.new()
	support.set_meta(&"lock_immune_override", true)
	F47AceSquad.configure_progression_support_aircraft(support, 0)
	_check("YF-23 支援按普通飞机规则可锁定",
		not support.has_meta(&"lock_immune_override") and not support.is_lock_immune(), "")
	support.free()

func _test_carrier_composition() -> void:
	var first: Dictionary = CarrierStrikeGroup.escort_counts_for_progression(0)
	_check("航母初见无 CG", int(first["cg"]) == 0, str(first))
	_check("航母初见 2 DDG", int(first["ddg"]) == 2, str(first))
	_check("航母初见 6 FFG", int(first["ffg"]) == 6, str(first))
	var enhanced: Dictionary = CarrierStrikeGroup.escort_counts_for_progression(1)
	_check("航母首败后 2 CG", int(enhanced["cg"]) == 2, str(enhanced))
	_check("航母首败后 2 DDG", int(enhanced["ddg"]) == 2, str(enhanced))
	_check("航母首败后 8 FFG", int(enhanced["ffg"]) == 8, str(enhanced))
	_check("航母二败暂沿用强化 1", CarrierStrikeGroup.escort_counts_for_progression(2) == enhanced, "")

func _test_goose_variant_gate() -> void:
	var first: Array = MotherGooseUAVSwarm.variant_weights_for_progression(0)
	_check("Goose 初见禁激光", int(first[MotherGooseUAVSwarm.Variant.MQ_111_LASER]) == 0, str(first))
	_check("Goose 初见禁电磁炮", int(first[MotherGooseUAVSwarm.Variant.MQ_112_RAILGUN]) == 0, str(first))
	var enhanced: Array = MotherGooseUAVSwarm.variant_weights_for_progression(1)
	_check("Goose 首败后激光权重 15", int(enhanced[MotherGooseUAVSwarm.Variant.MQ_111_LASER]) == 15,
		str(enhanced))
	_check("Goose 首败后电磁炮权重 15", int(enhanced[MotherGooseUAVSwarm.Variant.MQ_112_RAILGUN]) == 15,
		str(enhanced))
	_check("Goose 二败暂沿用强化 1",
		MotherGooseUAVSwarm.variant_weights_for_progression(2) == enhanced, "")

func _test_mq111_cumulative_intercept() -> void:
	var laser: LaserEquipment = load("res://resources/uav_mg_laser.tres") as LaserEquipment
	_check("MQ-111 开启直接拦截", laser != null and laser.intercepts_missiles_directly, "")
	if laser == null:
		return
	var holder := Node2D.new()
	var missile := Missile.new()
	missile.intercept_hp = 10.0
	holder.add_child(missile)
	laser._apply_laser_effect(null, missile, 4.0, false)
	_check("首段照射先减速", missile._laser_slow_timer > 0.0, "timer=%.2f" % missile._laser_slow_timer)
	_check("首段照射累计扣拦截 HP", is_equal_approx(missile.intercept_hp, 6.0),
		"hp=%.1f" % missile.intercept_hp)
	_check("未到阈值不销毁", not missile.is_queued_for_deletion(), "")
	laser._apply_laser_effect(null, missile, 6.0, false)
	_check("累计到阈值后销毁", missile.is_queued_for_deletion(), "hp=%.1f" % missile.intercept_hp)
	_check("拦截阈值归零立即失效", not missile.is_active, "active=%s" % missile.is_active)
	holder.queue_free()


func _test_goose_vls_distance_airburst() -> void:
	var p: MissileParams = load("res://resources/goose_vls_missile.tres") as MissileParams
	_check("GOOSE-VLS 参数可加载", p != null, "")
	if p == null:
		return
	_check("GOOSE-VLS 近身停火 3000m",
		is_equal_approx(p.distance_airburst_min_launch_range_m, 3000.0),
		"got=%.0f" % p.distance_airburst_min_launch_range_m)
	_check("GOOSE-VLS 累计飞行 8000m 自爆",
		is_equal_approx(p.distance_airburst_distance_m, 8000.0),
		"got=%.0f" % p.distance_airburst_distance_m)
	_check("GOOSE-VLS AOE 800m/1.5s",
		is_equal_approx(p.distance_airburst_radius_m, 800.0)
		and is_equal_approx(p.distance_airburst_duration_s, 1.5),
		"radius=%.0f duration=%.1f" % [p.distance_airburst_radius_m, p.distance_airburst_duration_s])

	var near_px := (p.distance_airburst_min_launch_range_m - 1.0) * GameConstants.PIXELS_PER_METER
	var edge_px := p.distance_airburst_min_launch_range_m * GameConstants.PIXELS_PER_METER
	_check("玩家近身时 VLS 停火",
		not MotherGooseController.vls_can_launch_at_distance(near_px, p), "")
	_check("玩家到 3000m 边界可起射",
		MotherGooseController.vls_can_launch_at_distance(edge_px, p), "")

	var missile := Missile.new()
	missile.params = p
	missile.distance_traveled_px = p.distance_airburst_distance_m \
		* GameConstants.PIXELS_PER_METER - 0.1
	_check("8000m 前不触发定距空爆", not MissileManager.distance_airburst_ready(missile), "")
	missile.distance_traveled_px += 0.1
	_check("累计路径到 8000m 触发定距空爆", MissileManager.distance_airburst_ready(missile), "")
	missile.free()

	var manager := MissileManager.new()
	manager._spawn_aoe(Vector2.ZERO, 5500.0, p.damage, CombatUnit.TEAM_HOSTILE,
		null, null, p.distance_airburst_radius_m, p.distance_airburst_duration_s, "GOOSE-VLS")
	var zone: Dictionary = manager._aoe_zones[0]
	_check("GOOSE-VLS AOE 使用逐弹覆盖半径",
		is_equal_approx(float(zone["radius_px"]), 800.0 * GameConstants.PIXELS_PER_METER),
		"radius_px=%.1f" % float(zone["radius_px"]))
	_check("GOOSE-VLS AOE 使用逐弹覆盖持续时间",
		is_equal_approx(float(zone["max_time"]), 1.5),
		"duration=%.1f" % float(zone["max_time"]))
	var victim := CombatUnit.new()
	victim.team = CombatUnit.TEAM_PLAYER
	victim.hp = 100.0
	victim.altitude = 5500.0
	manager._apply_aoe_damage(victim, zone)
	_check("远距落区内玩家真实承受 AOE 伤害", is_equal_approx(victim.hp, 78.0),
		"hp=%.1f" % victim.hp)
	manager.free()
	victim.free()


func _test_mq111_player_heat_cycle() -> void:
	var laser: LaserEquipment = load("res://resources/uav_mg_laser.tres") as LaserEquipment
	var player_laser: LaserEquipment = load("res://resources/x02_laser.tres") as LaserEquipment
	_check("MQ-111 与玩家激光热量参数一致", laser != null and player_laser != null
		and is_equal_approx(laser.heat_max, player_laser.heat_max)
		and is_equal_approx(laser.heat_per_second, player_laser.heat_per_second)
		and is_equal_approx(laser.heat_cooldown_per_second, player_laser.heat_cooldown_per_second)
		and is_equal_approx(laser.overheat_exit_threshold, player_laser.overheat_exit_threshold), "")
	if laser == null:
		return

	var host := LaserHost.new()
	var manager := MissileManager.new()
	var target := Missile.new()
	target.params = load("res://resources/default_missile.tres") as MissileParams
	target.team = CombatUnit.TEAM_ALLY
	target.intercept_hp = 10000.0
	target.global_position = Vector2(100.0, 0.0)
	manager.add_child(target)
	host.missile_manager = manager

	laser.update(host, 3.0)
	var state: Dictionary = host.equipment_state[LaserEquipment.STATE_KEY]
	_check("MQ-111 连续照射会过热停火", bool(state["overheating"])
		and is_equal_approx(float(state["heat"]), laser.heat_max), str(state))
	laser.update(host, 3.0)
	_check("MQ-111 冷到 30% 以下解除过热", not bool(state["overheating"])
		and float(state["heat"]) <= laser.heat_max * laser.overheat_exit_threshold, str(state))
	laser.update(host, 0.1)
	_check("MQ-111 解除过热后恢复拦截光束", (state["active_beams"] as Array).size() == 1, str(state))

	manager.free()
	host.free()

func _check(label: String, ok: bool, detail: String) -> void:
	if ok:
		_pass += 1
		print("  ✓ %s" % label)
	else:
		_fail += 1
		printerr("  ✗ %s%s" % [label, " — %s" % detail if not detail.is_empty() else ""])
