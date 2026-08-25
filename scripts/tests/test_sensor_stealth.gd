extends RefCounted

const SENSOR_STEALTH_SCRIPT := preload(
	"res://scripts/survivor/sensor_stealth_controller.gd")
const ACE_SQUAD_SCRIPT := preload("res://scripts/survivor/ace_squad.gd")
const CINEMATIC_CAST_SCRIPT := preload("res://scripts/presentation/cinematic_cast.gd")

var _pass := 0
var _fail := 0


func run() -> void:
	print("\n════════ 敌机传感器隐形契约 ════════")
	_test_roster()
	_test_grace_and_reveal()
	_test_proximity_reveal()
	_test_observer_boundaries()
	_test_counter_stealth_skills()
	_test_ghost_buster_team_hp()
	_test_hidden_combat_target_write_gate()
	_test_radar_hint_contract()
	_test_player_reference_release()
	_test_batched_reference_release()
	_test_wraith_release_edges()
	_test_wraith_cloak_owner_edge()
	_test_presentation_actor_isolation()
	_test_visual_and_guidance_contract()
	print("──────── 结果：%d 通过 / %d 失败 ────────" % [_pass, _fail])


func _test_roster() -> void:
	var enabled_paths := [
		"res://resources/enemy_f22.tres",
		"res://resources/enemy_f35.tres",
		"res://resources/enemy_su57.tres",
		"res://resources/enemy_j20.tres",
		"res://resources/enemy_f47.tres",
		"res://resources/enemy_yf23.tres",
	]
	for path in enabled_paths:
		var params := load(path) as AircraftParams
		_check(params != null and params.sensor_stealth_enabled,
			"首批资源开启：%s" % path.get_file())
	for path in ["res://resources/enemy_a12.tres"]:
		var params := load(path) as AircraftParams
		_check(params != null and not params.sensor_stealth_enabled,
			"既有契约未误开：%s" % path.get_file())


func _test_grace_and_reveal() -> void:
	var controller = SENSOR_STEALTH_SCRIPT.new()
	var target := _make_aircraft(CombatUnit.TEAM_HOSTILE, true, false)
	var units: Array[CombatUnit] = [target]
	for _i in range(24):
		controller.begin_radar_tick()
		controller.finish_radar_tick(0.2, units)
	_check(not target.is_hidden_from_player_sensors(), "失联 4.8s 仍保留接触")
	controller.begin_radar_tick()
	controller.finish_radar_tick(0.2, units)
	_check(target.is_hidden_from_player_sensors(), "失联 5.0s 进入逻辑隐形")
	var observer := _make_aircraft(CombatUnit.TEAM_PLAYER, false, true)
	controller.begin_radar_tick()
	controller.observe(observer, target, true)
	controller.finish_radar_tick(0.2, units)
	_check(not target.is_hidden_from_player_sensors() \
		and is_zero_approx(target.sensor_contact_lost_s),
		"任一有效玩家雷达照射立即恢复接触")
	observer.free()
	target.free()


func _test_proximity_reveal() -> void:
	var controller = SENSOR_STEALTH_SCRIPT.new()
	var target := _make_aircraft(CombatUnit.TEAM_HOSTILE, true, false)
	var observer := _make_aircraft(CombatUnit.TEAM_PLAYER, false, false)
	target.global_position = Vector2.ZERO
	observer.global_position = Vector2(SensorStealthController.PROXIMITY_REVEAL_PX - 1.0, 0.0)
	var units: Array[CombatUnit] = [observer, target]
	for _i in range(30):
		controller.begin_radar_tick()
		controller.finish_radar_tick(0.2, units)
	_check(not target.is_hidden_from_player_sensors() and is_zero_approx(target.sensor_contact_lost_s),
		"2000m 近距圈内无雷达也保持显形")
	observer.global_position = Vector2(SensorStealthController.PROXIMITY_REVEAL_PX + 1.0, 0.0)
	for _i in range(25):
		controller.begin_radar_tick()
		controller.finish_radar_tick(0.2, units)
	_check(target.is_hidden_from_player_sensors(), "离开近距圈满 5s 才隐形")
	observer.status_jam_active = true
	observer.global_position = Vector2(SensorStealthController.PROXIMITY_REVEAL_PX - 1.0, 0.0)
	controller.begin_radar_tick()
	controller.finish_radar_tick(0.2, units)
	_check(not target.is_hidden_from_player_sensors(), "近距揭露不受 JAM 影响")
	observer.free()
	target.free()


func _test_observer_boundaries() -> void:
	var controller = SENSOR_STEALTH_SCRIPT.new()
	var target := _make_aircraft(CombatUnit.TEAM_HOSTILE, true, false)
	var observer := _make_aircraft(CombatUnit.TEAM_PLAYER, false, true)
	var units: Array[CombatUnit] = [target]
	target.set_sensor_contact_hidden(true, 0.0)

	observer.status_jam_active = true
	controller.begin_radar_tick()
	controller.observe(observer, target, true)
	_check(target.is_hidden_from_player_sensors(), "JAM 来源不能揭露")
	observer.status_jam_active = false
	controller.begin_radar_tick()
	controller.observe(observer, target, false)
	_check(target.is_hidden_from_player_sensors(), "锥外来源不能揭露")
	observer.sensor_shroud_id = 1
	controller.begin_radar_tick()
	controller.observe(observer, target, true)
	_check(target.is_hidden_from_player_sensors(), "Snowblind 幕外来源不能揭露")
	observer.sensor_shroud_id = 0
	observer.params.missile = null
	controller.begin_radar_tick()
	controller.observe(observer, target, true)
	_check(target.is_hidden_from_player_sensors(), "无锁定武器来源不能揭露")
	observer.params.missile = load("res://resources/default_missile.tres")
	controller.begin_radar_tick()
	controller.observe(observer, target, true)
	controller.finish_radar_tick(0.2, units)
	_check(not target.is_hidden_from_player_sensors(), "边界解除后可正常揭露")
	target.set_sensor_contact_hidden(true, 0.0)
	_check(observer.is_sensor_engagement_obscured(target), "玩家观察者被隐形门遮蔽")
	_check(not target.is_sensor_engagement_obscured(observer), "隐形敌机仍可观察玩家")
	_check(not target.is_lock_immune(), "传感器隐形不污染全局锁定免疫")
	observer.free()
	target.free()


func _test_hidden_combat_target_write_gate() -> void:
	var target := _make_aircraft(CombatUnit.TEAM_HOSTILE, true, false)
	var observer := _make_aircraft(CombatUnit.TEAM_PLAYER, false, true)
	var enemy_observer := _make_aircraft(CombatUnit.TEAM_HOSTILE, false, true)
	observer.set_combat_target(target)
	_check(observer.combat_target == target, "显形目标允许写入玩家 combat_target")
	target.is_cloaked = true
	observer.set_combat_target(target)
	_check(observer.combat_target == null, "光学隐形目标拒绝重新写入玩家 combat_target")
	target.is_cloaked = false
	target.set_sensor_contact_hidden(true, 0.0)
	observer.commanded_target = target
	observer.set_combat_target(target)
	_check(observer.combat_target == null and observer.commanded_target == target,
		"传感器隐形拒绝重挂 combat_target 但不篡改短窗点名")
	enemy_observer.set_combat_target(target)
	_check(enemy_observer.combat_target == target, "敌方自身目标写入不受玩家传感器门影响")
	observer.free()
	enemy_observer.free()
	target.free()


func _test_counter_stealth_skills() -> void:
	var counter := SurvivorData.upgrade_by_id("counter_stealth")
	var ghost := SurvivorData.upgrade_by_id("ghost_buster")
	_check(not counter.is_empty() and SurvivorData.get_rarity(counter) == SurvivorData.Rarity.STABLE \
		and SurvivorData.axis_of_upgrade(counter) == SurvivorData.AXIS_SCHEMER,
		"反隐身技能数据：稳定 / 策士")
	_check(not ghost.is_empty() and SurvivorData.get_rarity(ghost) == SurvivorData.Rarity.ADVANCED \
		and SurvivorData.axis_of_upgrade(ghost) == SurvivorData.AXIS_GLADIATOR,
		"捉鬼者技能数据：先进 / 斗士")

	var controller = SENSOR_STEALTH_SCRIPT.new()
	var target := _make_aircraft(CombatUnit.TEAM_HOSTILE, true, false)
	var observer := _make_aircraft(CombatUnit.TEAM_PLAYER, false, true)
	observer.global_position = Vector2.ZERO
	observer.heading = 0.0
	observer.altitude = 5500.0
	observer.params.radar_range = 1000.0
	target.global_position = Vector2(0.0, -1150.0)
	target.set_sensor_contact_hidden(true, 0.0)
	observer.set_meta("upgrade_stacks", {"counter_stealth": 1})
	var units: Array[CombatUnit] = [observer, target]
	controller.begin_radar_tick()
	controller.observe(observer, target, false)
	controller.finish_radar_tick(0.2, units)
	_check(not target.is_hidden_from_player_sensors(),
		"反隐身将隐形目标侦测距离扩到基础雷达的 120%")
	target.set_sensor_contact_hidden(true, 0.0)
	target.global_position = Vector2(0.0, -1210.0)
	controller.begin_radar_tick()
	controller.observe(observer, target, false)
	_check(target.is_hidden_from_player_sensors(), "反隐身不越过 120% 侦测上限")

	target.global_position = Vector2(3000.0, -1000.0)
	target.is_cloaked = true
	target._cloak_alpha = 0.0
	target.radar_targets[observer] = target.params.lock_time
	controller.begin_radar_tick()
	controller.finish_radar_tick(0.2, units)
	_check(not target.is_hidden_from_player_sensors() \
		and target.counter_stealth_revealed and not target.is_cloaked \
		and is_equal_approx(target._cloak_alpha, 1.0),
		"隐形单位完整锁定队员时向全队现形并压过光学 cloak")

	observer.set_meta("upgrade_stacks", {"ghost_buster": 1})
	observer.combat_target = target
	for _i in range(30):
		controller.begin_radar_tick()
		controller.finish_radar_tick(0.2, units)
	_check(not target.is_hidden_from_player_sensors(),
		"捉鬼者保持当前 combat_target 暴露")
	observer.combat_target = null
	target.radar_targets.clear()
	for _i in range(25):
		controller.begin_radar_tick()
		controller.finish_radar_tick(0.2, units)
	_check(target.is_hidden_from_player_sensors() and not target.counter_stealth_revealed,
		"解除交战后恢复标准失联隐藏")
	observer.free()
	target.free()


func _test_ghost_buster_team_hp() -> void:
	var old_units: Array[CombatUnit] = CombatUnit.all_units
	SkillHooks.ghost_buster_team_hp_gained = 0.0
	var killer := _make_aircraft(CombatUnit.TEAM_PLAYER, false, true)
	var wingman := _make_aircraft(CombatUnit.TEAM_PLAYER, false, true)
	var victim := _make_aircraft(CombatUnit.TEAM_HOSTILE, true, false)
	killer.hp = 100.0
	wingman.hp = 100.0
	killer.params.max_hp = 100.0
	wingman.params.max_hp = 100.0
	killer.set_meta("upgrade_stacks", {"ghost_buster": 1})
	wingman.set_meta("upgrade_stacks", {"ghost_buster": 1})
	var active_units: Array[CombatUnit] = [killer, wingman, victim]
	CombatUnit.all_units = active_units
	SkillHooks.dispatch_on_kill(killer, victim)
	_check(is_equal_approx(SkillHooks.ghost_buster_team_hp_gained, 10.0) \
		and is_equal_approx(killer.params.max_hp, 110.0) \
		and is_equal_approx(wingman.params.max_hp, 110.0),
		"击杀隐形单位令全队永久最大生命 +10")
	var late_member := _make_aircraft(CombatUnit.TEAM_PLAYER, false, true)
	late_member.hp = 100.0
	late_member.params.max_hp = 100.0
	late_member.set_meta("upgrade_stacks", {"ghost_buster": 1})
	SkillHooks.sync_ghost_buster_team_hp_bonus(late_member)
	_check(is_equal_approx(late_member.params.max_hp, 110.0),
		"后入队成员同步队级永久生命账本")
	var ordinary := _make_aircraft(CombatUnit.TEAM_HOSTILE, false, false)
	SkillHooks.dispatch_on_kill(killer, ordinary)
	_check(is_equal_approx(SkillHooks.ghost_buster_team_hp_gained, 10.0),
		"普通目标击杀不触发捉鬼者")
	CombatUnit.all_units = old_units
	SkillHooks.ghost_buster_team_hp_gained = 0.0
	killer.free()
	wingman.free()
	victim.free()
	late_member.free()
	ordinary.free()


func _test_radar_hint_contract() -> void:
	var target := _make_aircraft(CombatUnit.TEAM_HOSTILE, true, false)
	_check(not SurvivorHUD.RadarDisplay.stealth_hint_contact_for(target),
		"显形敌机不冒充雷达隐形提示")
	target.set_sensor_contact_hidden(true, 0.0)
	_check(SurvivorHUD.RadarDisplay.stealth_hint_contact_for(target),
		"传感器隐形仍进入左下雷达提示")
	target.set_sensor_contact_hidden(false, 0.0)
	target.is_cloaked = true
	_check(SurvivorHUD.RadarDisplay.stealth_hint_contact_for(target),
		"Wraith 光学 cloak 仍进入左下雷达提示")
	target.free()


func _test_player_reference_release() -> void:
	var controller = SENSOR_STEALTH_SCRIPT.new()
	var target := _make_aircraft(CombatUnit.TEAM_HOSTILE, true, false)
	var observer := _make_aircraft(CombatUnit.TEAM_PLAYER, false, true)
	observer.global_position = Vector2(4000.0, -1000.0)
	observer.radar_targets[target] = 2.0
	observer.secondary_radar_targets[target] = 1.0
	observer.combat_target = target
	observer.commanded_target = target
	observer.attack_posture = Situation.POSTURE_ASSAULT
	observer.target_position = target.global_position
	target.combat_target = observer
	var units: Array[CombatUnit] = [observer, target]
	for _i in range(25):
		controller.begin_radar_tick()
		controller.finish_radar_tick(0.2, units)
	_check(not observer.radar_targets.has(target) \
		and not observer.secondary_radar_targets.has(target),
		"隐形沿清除玩家主副锁")
	_check(observer.combat_target == null and observer.commanded_target == null \
		and observer.target_position == Vector2.INF,
		"隐形沿清除玩家作战/命令追踪")
	_check(observer.attack_posture == Situation.POSTURE_AUTO,
		"目标命令附属姿态一并复位")
	_check(target.combat_target == observer, "敌机自身攻击目标不受影响")
	observer.free()
	target.free()


func _test_batched_reference_release() -> void:
	var target_a := _make_aircraft(CombatUnit.TEAM_HOSTILE, true, false)
	var target_b := _make_aircraft(CombatUnit.TEAM_HOSTILE, true, false)
	var observer := _make_aircraft(CombatUnit.TEAM_PLAYER, false, true)
	observer.radar_targets[target_a] = 2.0
	observer.radar_targets[target_b] = 1.0
	observer.secondary_radar_targets[target_a] = 1.0
	observer.secondary_radar_targets[target_b] = 1.0
	observer.combat_target = target_a
	observer.commanded_target = target_b
	observer.attack_posture = Situation.POSTURE_ASSAULT
	var targets: Array[Aircraft] = [target_a, target_b]
	var units: Array[CombatUnit] = [observer, target_a, target_b]
	SENSOR_STEALTH_SCRIPT.release_player_sensor_refs_batch(targets, units, true)
	_check(observer.radar_targets.is_empty() and observer.secondary_radar_targets.is_empty(),
		"同帧多目标隐形批量清除全部主副锁")
	_check(observer.combat_target == null and observer.commanded_target == null \
		and observer.attack_posture == Situation.POSTURE_AUTO,
		"同帧多目标隐形一次收束作战目标与点名")
	observer.free()
	target_a.free()
	target_b.free()


func _test_wraith_release_edges() -> void:
	var target := _make_aircraft(CombatUnit.TEAM_HOSTILE, true, false)
	var observer := _make_aircraft(CombatUnit.TEAM_PLAYER, false, true)
	var enemy_observer := _make_aircraft(CombatUnit.TEAM_HOSTILE, false, true)
	observer.radar_targets[target] = 2.0
	observer.secondary_radar_targets[target] = 1.0
	observer.combat_target = target
	observer.commanded_target = target
	enemy_observer.combat_target = target
	var units: Array[CombatUnit] = [observer, enemy_observer, target]
	SENSOR_STEALTH_SCRIPT.release_player_sensor_refs(target, units, false)
	_check(observer.combat_target == null and observer.commanded_target == target,
		"Wraith 光学隐身沿清 combat_target、保留短窗点名")
	_check(not observer.radar_targets.has(target) \
		and not observer.secondary_radar_targets.has(target),
		"Wraith 光学隐身沿清全体玩家主副锁")
	_check(enemy_observer.combat_target == target,
		"Wraith 隐形不清敌方观察者目标")
	observer.combat_target = target
	SENSOR_STEALTH_SCRIPT.release_player_sensor_refs(target, units, true)
	_check(observer.combat_target == null and observer.commanded_target == null,
		"F-47 传感器硬失联清 combat_target 与点名")
	observer.free()
	enemy_observer.free()
	target.free()


func _test_wraith_cloak_owner_edge() -> void:
	var boss = ACE_SQUAD_SCRIPT.new()
	var target := _make_aircraft(CombatUnit.TEAM_HOSTILE, true, false)
	var observer := _make_aircraft(CombatUnit.TEAM_PLAYER, false, true)
	var trail := TrailRibbon.new()
	target._trail_ribbon = trail
	observer.radar_targets[target] = 2.0
	observer.secondary_radar_targets[target] = 1.0
	observer.combat_target = target
	observer.commanded_target = target
	var boss_members: Array[Aircraft] = [target]
	boss.members = boss_members
	boss.cloak_duration = 5.5
	boss.cloak_fade = 0.5
	boss._cloak_remaining = 4.0
	var old_units: Array[CombatUnit] = CombatUnit.all_units
	var active_units: Array[CombatUnit] = [observer, target]
	CombatUnit.all_units = active_units
	boss._cloak_update(0.0)
	_check(target.is_cloaked and observer.combat_target == null \
		and observer.commanded_target == target,
		"Wraith 实际 cloak owner 在逻辑沿清 combat_target、挂起点名")
	_check(not trail.visible and not trail.is_processing(),
		"Wraith 完全光学隐身停止尾迹采样")
	observer.combat_target = target
	target.set_counter_stealth_revealed(true)
	boss._cloak_update(0.0)
	_check(not target.is_cloaked and is_equal_approx(target._cloak_alpha, 1.0) \
		and observer.combat_target == target and trail.visible and trail.is_processing(),
		"反隐现形压过 Wraith cloak 并保留 combat_target")
	target.set_counter_stealth_revealed(false)
	boss._cloak_update(0.0)
	_check(target.is_cloaked, "反隐条件解除后 Wraith cloak 按原周期恢复")
	boss._cloak_remaining = 0.1
	boss._cloak_update(0.0)
	_check(not target.is_cloaked and trail.visible and trail.is_processing(),
		"Wraith 光学显形恢复尾迹且不覆盖传感器状态")
	CombatUnit.all_units = old_units
	boss.members.clear()
	boss = null
	observer.free()
	trail.free()
	target._trail_ribbon = null
	target.free()


func _test_presentation_actor_isolation() -> void:
	var controller = SENSOR_STEALTH_SCRIPT.new()
	var actor := _make_aircraft(CombatUnit.TEAM_HOSTILE, true, false)
	var trail := TrailRibbon.new()
	actor._trail_ribbon = trail
	actor.sensor_contact_lost_s = 1.2
	actor.set_sensor_contact_hidden(true, 0.0)
	var cast = CINEMATIC_CAST_SCRIPT.new()
	var actors: Array = [actor]
	cast.bind(actors, RefCounted.new())
	_check(actor.has_meta(CombatUnit.META_PRESENTATION_ACTOR_ACTIVE) \
		and not actor.is_hidden_from_player_sensors(),
		"导演 bind 建立虚拟演员所有权并绕过真实隐形门")
	_check(trail.visible and trail.is_processing() \
		and is_equal_approx(trail.self_modulate.a, 1.0),
		"导演演员即使战斗侧已隐形仍显示并采样尾迹")
	var units: Array[CombatUnit] = [actor]
	for _i in range(10):
		controller.begin_radar_tick()
		controller.finish_radar_tick(0.2, units)
	_check(is_equal_approx(actor.sensor_contact_lost_s, 1.2),
		"导演所有权窗口冻结真实战斗失联计时")
	cast.release()
	_check(not actor.has_meta(CombatUnit.META_PRESENTATION_ACTOR_ACTIVE) \
		and actor.is_hidden_from_player_sensors(),
		"导演 release 清所有权并恢复既存真实隐形状态")
	_check(not trail.visible and not trail.is_processing(),
		"退出虚拟环境后按真实隐形状态恢复尾迹门")
	trail.free()
	actor._trail_ribbon = null
	actor.free()


func _test_visual_and_guidance_contract() -> void:
	var target := _make_aircraft(CombatUnit.TEAM_HOSTILE, true, false)
	var trail := TrailRibbon.new()
	target._trail_ribbon = trail
	target.set_sensor_contact_hidden(true, 0.0)
	_check(not trail.is_processing() and not trail.visible,
		"完全隐形停止尾迹采样与绘制")
	target.set_sensor_contact_hidden(false, 0.0)
	_check(trail.is_processing() and trail.visible,
		"显形从空尾迹恢复采样")
	_check(Missile.target_breaks_guidance(false, true),
		"传感器失联令在飞导弹失导")
	_check(not Missile.target_breaks_guidance(false, false),
		"普通可见目标保持导引")
	_check(not target.sensor_hidden, "新状态不覆盖 Snowblind 所有权字段")
	trail.free()
	target.free()


func _make_aircraft(team: int, stealth_enabled: bool,
		lock_capable: bool) -> Aircraft:
	var ac := Aircraft.new()
	ac.team = team
	ac.global_position = Vector2(1000.0, -1000.0)
	ac.params = AircraftParams.new()
	ac.params.sensor_stealth_enabled = stealth_enabled
	if lock_capable:
		ac.params.missile = load("res://resources/default_missile.tres")
	return ac


func _check(ok: bool, label: String) -> void:
	if ok:
		_pass += 1
		print("  ✓ %s" % label)
	else:
		_fail += 1
		print("  ✗ %s" % label)
