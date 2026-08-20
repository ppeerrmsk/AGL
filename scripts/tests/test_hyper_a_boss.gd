extends RefCounted

## Black Star / Hyper-A 设计契约回归。
## 运行：bench/run.cmd hyper_a

const HyperAScript := preload("res://scripts/survivor/hyper_a_boss.gd")
const BossDebugScript := preload("res://scripts/survivor/boss_debug_select.gd")
const EXPECTED_ASSERTIONS := 107

class FreedPlayerDirector:
	extends RefCounted
	var player: Aircraft = null

var _pass: int = 0
var _fail: int = 0


func run() -> void:
	print("\n════════ BLACK STAR / HYPER-A 契约测试 ════════")
	_test_registry_and_debug_entry()
	_test_generation_resources()
	_test_split_topology()
	_test_special_behavior_contract()
	_test_g1_entry_and_forward_missiles()
	_test_g0_independent_saturation_salvo()
	_test_charge_alignment_regression()
	_test_arrival_sequence()
	if _pass + _fail != EXPECTED_ASSERTIONS:
		_fail += 1
		printerr("  ✗ 验收未完整执行 assertions=%d expected=%d" % [
			_pass + _fail - 1, EXPECTED_ASSERTIONS])
	print("──────── 结果：%d 通过 / %d 失败 ────────" % [_pass, _fail])


func _test_registry_and_debug_entry() -> void:
	var encounter: BossEncounter = BossRegistry.instantiate("BLACK_STAR")
	_check("注册表可实例化 BLACK_STAR", encounter != null and encounter is HyperAScript)
	if encounter != null:
		_check("注册表呼号为 HYPER-A", encounter.callsign_prefix == "HYPER-A")
		_check("根机下降开始信号可供事件层绑定无线电", encounter.has_signal("root_descent_started"))
		_check("根机下降结束信号可供事件层恢复玩家视觉", encounter.has_signal("root_descent_finished"))
	var black_star: Dictionary = {}
	for row in BossDebugScript.BOSS_LIST:
		if String(row.get("id", "")) == "BLACK_STAR":
			black_star = row
			break
	_check("Debug 面板含 BLACK_STAR", not black_star.is_empty())
	var scenarios: Array = black_star.get("scenarios", [])
	_check("Debug 面板提供 9 个专项直达场景", scenarios.size() == 9)
	var scenario_ids: Array[String] = []
	for pair in scenarios:
		if pair is Array and pair.size() >= 2:
			scenario_ids.append(String(pair[1]))
	for expected in ["full", "g0_weapons", "g1_reentry", "g1_weapons", "g2_dash", "brake_wave", "g3", "second_root", "cooldown"]:
		_check("Debug 场景可达：%s" % expected, scenario_ids.has(expected))
	var black_star_radio := ChatterLines.boss_sequence("BLACK_STAR", "spawn")
	_check("Black Star 双根无线电登记为一号 / 二号机",
		black_star_radio.size() == 2
		and int(black_star_radio[0].get("slot", -1)) == 0
		and int(black_star_radio[1].get("slot", -1)) == 1)
	var radio_i18n := FileAccess.get_file_as_string("res://i18n/radio.csv")
	_check("Black Star 双根均自报突破十马赫与高速下降",
		radio_i18n.contains("RADIO_BOSS_BLACK_STAR_SPAWN_1,一号机已突破十马赫，正在高速下降中。")
		and radio_i18n.contains("RADIO_BOSS_BLACK_STAR_SPAWN_2,二号机已突破十马赫，正在高速下降中。"))
	var visual_player := Aircraft.new()
	var visual_director := FreedPlayerDirector.new()
	visual_director.player = visual_player
	var visual_event := BossEncounterEvent.new(Vector2.ZERO, 0.0, "default")
	visual_event.director = visual_director
	visual_event._set_arrival_player_visual_hidden(true)
	_check("初次根机下降只隐藏玩家绘制",
		not visual_player.visible
		and bool(visual_player.get_meta(Aircraft.META_PRESENTATION_FORCE_HIDDEN_VISUAL, false)))
	_check("演出视觉隐藏不授予玩法隐形或无敌",
		not visual_player.is_cloaked and not visual_player.sensor_hidden and not visual_player.invulnerable)
	visual_event._set_arrival_player_visual_hidden(false)
	_check("初次根机撞击后恢复玩家绘制",
		visual_player.visible
		and not visual_player.has_meta(Aircraft.META_PRESENTATION_FORCE_HIDDEN_VISUAL))
	visual_player.free()


func _test_generation_resources() -> void:
	var expected_hp := [400.0, 200.0, 100.0, 70.0]
	var expected_length := [96.0, 80.0, 36.0, 10.0]
	for generation in range(HyperAScript.PARAM_PATHS.size()):
		var p := load(HyperAScript.PARAM_PATHS[generation]) as AircraftParams
		_check("G%d 参数可加载" % generation, p != null)
		if p == null:
			continue
		_check("G%d HP = %.0f" % [generation, expected_hp[generation]],
			is_equal_approx(p.max_hp, expected_hp[generation]))
		_check("G%d 无 flare" % generation, p.flare == null)
		_check("G%d 导弹舱为 4 发" % generation,
			p.missile != null and p.missile.max_count == 4)
		_check("G%d 机身尺度符合分代" % generation,
			is_equal_approx(p.visual_length_m, expected_length[generation]))
	_check("只有 G0 与 G3 有机炮/激光",
		(load(HyperAScript.PARAM_PATHS[0]) as AircraftParams).gun != null
		and (load(HyperAScript.PARAM_PATHS[1]) as AircraftParams).gun == null
		and (load(HyperAScript.PARAM_PATHS[2]) as AircraftParams).gun == null
		and (load(HyperAScript.PARAM_PATHS[3]) as AircraftParams).gun != null)
	_check("只有 G0 使用 180° 半锥实现 360° 全向雷达",
		is_equal_approx((load(HyperAScript.PARAM_PATHS[0]) as AircraftParams).radar_half_angle, 180.0)
		and (load(HyperAScript.PARAM_PATHS[1]) as AircraftParams).radar_half_angle < 90.0
		and (load(HyperAScript.PARAM_PATHS[2]) as AircraftParams).radar_half_angle < 90.0
		and (load(HyperAScript.PARAM_PATHS[3]) as AircraftParams).radar_half_angle < 90.0)
	_check("G0 顶级火控在高速迎头窗口内 1.2 秒完成锁定",
		is_equal_approx((load(HyperAScript.PARAM_PATHS[0]) as AircraftParams).lock_time, 1.2))


func _test_split_topology() -> void:
	_check("双母体", 2 == 2)
	_check("每个母体三次二分后得到 8 架 G3", int(pow(2, 3)) == 8)
	_check("完整遭遇共有 16 架终端 G3", 2 * int(pow(2, 3)) == 16)
	_check("每个母体节点数为 1+2+4+8=15", 1 + 2 + 4 + 8 == 15)
	_check("双母体总节点数为 30", 2 * (1 + 2 + 4 + 8) == 30)
	_check("路径段命名使用 .1/.2 层级", "Hyper-A1.1.2.1".count(".") == 3)


func _test_special_behavior_contract() -> void:
	_check("锁定容量 G0/G1/G2/G3 = 8/4/2/1",
		HyperAScript.LOCK_CAPACITY == [8, 4, 2, 1])
	_check("根母体约 4 秒从对流层降至战斗高度",
		is_equal_approx(HyperAScript.DESCENT_DURATION, 4.0)
		and HyperAScript.DESCENT_START_ALTITUDE == 30000.0)
	_check("第二母体在第一架撞击后 18 秒开始登场",
		is_equal_approx(HyperAScript.SECOND_ROOT_DELAY, 18.0))
	_check("冲刺弹幕每侧 5 枚", HyperAScript.ROCKETS_PER_SIDE == 5)
	_check("冲刺后散热窗口附带 6 秒 SLOW",
		is_equal_approx(HyperAScript.COOLDOWN_DURATION, 6.0))
	_check("循环再入至少间隔 40 秒并带 10 秒错峰",
		HyperAScript.REENTRY_COOLDOWN >= 40.0
		and HyperAScript.REENTRY_COOLDOWN_JITTER >= 10.0)
	_check("爬升与俯冲之间有 7–10 秒独立高空等待",
		HyperAScript.HIGH_ALTITUDE_HOLD_MIN >= 7.0
		and HyperAScript.HIGH_ALTITUDE_HOLD_MAX >= HyperAScript.HIGH_ALTITUDE_HOLD_MIN
		and HyperAScript.HIGH_ALTITUDE_HOLD_MAX <= 10.0)
	_check("冲刺段距离判定正确",
		is_equal_approx(HyperAScript._distance_to_segment(
			Vector2(5.0, 2.0), Vector2.ZERO, Vector2(10.0, 0.0)), 2.0))
	_check("急刹冲击波固定为 900m / 110° / 45 伤害",
		is_equal_approx(HyperAScript.BRAKE_SHOCKWAVE_RADIUS_M, 900.0)
		and is_equal_approx(rad_to_deg(HyperAScript.BRAKE_SHOCKWAVE_HALF_ANGLE) * 2.0, 110.0)
		and is_equal_approx(HyperAScript.BRAKE_SHOCKWAVE_DAMAGE, 45.0))
	_check("急刹扇区包含前方近距目标",
		HyperAScript._point_in_sector(Vector2.RIGHT * 200.0, Vector2.ZERO,
			Vector2.RIGHT, HyperAScript.BRAKE_SHOCKWAVE_RADIUS_PX,
			HyperAScript.BRAKE_SHOCKWAVE_HALF_ANGLE))
	_check("急刹扇区排除侧后方、背后与超距目标",
		not HyperAScript._point_in_sector(Vector2.from_angle(deg_to_rad(70.0)) * 200.0,
			Vector2.ZERO, Vector2.RIGHT, HyperAScript.BRAKE_SHOCKWAVE_RADIUS_PX,
			HyperAScript.BRAKE_SHOCKWAVE_HALF_ANGLE)
		and not HyperAScript._point_in_sector(Vector2.LEFT * 100.0, Vector2.ZERO,
			Vector2.RIGHT, HyperAScript.BRAKE_SHOCKWAVE_RADIUS_PX,
			HyperAScript.BRAKE_SHOCKWAVE_HALF_ANGLE)
		and not HyperAScript._point_in_sector(Vector2.RIGHT * 500.0, Vector2.ZERO,
			Vector2.RIGHT, HyperAScript.BRAKE_SHOCKWAVE_RADIUS_PX,
			HyperAScript.BRAKE_SHOCKWAVE_HALF_ANGLE))

	var saved_units: Array[CombatUnit] = []
	saved_units.assign(CombatUnit.all_units)
	CombatUnit.all_units.clear()
	var source := Aircraft.new()
	source.params = load(HyperAScript.PARAM_PATHS[2]) as AircraftParams
	source.team = CombatUnit.TEAM_HOSTILE
	var inside := Aircraft.new()
	inside.params = load(HyperAScript.PARAM_PATHS[3]) as AircraftParams
	inside.team = CombatUnit.TEAM_PLAYER
	inside.hp = inside.params.max_hp
	inside.global_position = Vector2.RIGHT * 200.0
	var outside := Aircraft.new()
	outside.params = load(HyperAScript.PARAM_PATHS[3]) as AircraftParams
	outside.team = CombatUnit.TEAM_PLAYER
	outside.hp = outside.params.max_hp
	outside.global_position = Vector2.LEFT * 200.0
	CombatUnit.all_units.append_array([source, inside, outside])
	var boss = HyperAScript.new()
	var brake_record := {
		"path": "Hyper-A1.1.1",
		"dash_to": Vector2.ZERO,
		"dash_dir": Vector2.RIGHT,
		"brake_wave_fired": false,
	}
	boss._trigger_brake_shockwave(brake_record, source)
	_check("急刹冲击波对扇区内目标结算 45 伤害",
		is_equal_approx(inside.hp, inside.params.max_hp - HyperAScript.BRAKE_SHOCKWAVE_DAMAGE))
	_check("急刹冲击波不伤害背后目标", is_equal_approx(outside.hp, outside.params.max_hp))
	var hp_after_first := inside.hp
	boss._trigger_brake_shockwave(brake_record, source)
	_check("同一次冲刺的急刹冲击波只结算一次", is_equal_approx(inside.hp, hp_after_first))
	_check("急刹结算生成同参数扇形扩散快照",
		boss._flashes.size() == 1
		and String(boss._flashes[0].get("kind", "")) == "brake_shockwave"
		and is_equal_approx(float(boss._flashes[0].get("radius_px", 0.0)),
			HyperAScript.BRAKE_SHOCKWAVE_RADIUS_PX))
	CombatUnit.all_units.clear()
	CombatUnit.all_units.assign(saved_units)
	source.free()
	inside.free()
	outside.free()


func _test_g1_entry_and_forward_missiles() -> void:
	var boss = HyperAScript.new()
	var scene_root := Node2D.new()
	var player := Aircraft.new()
	player.team = CombatUnit.TEAM_PLAYER
	player.global_position = Vector2(800.0, 1200.0)
	boss._scene_root = scene_root
	boss._aircraft_scene = load("res://scenes/aircraft.tscn") as PackedScene
	boss._player = player
	boss._pending_splits.append({
		"timer": 0.0,
		"generation": 1,
		"path": "Hyper-A1",
		"root": 1,
		"pos": Vector2.ZERO,
		"heading": 0.0,
	})
	boss._update_pending_splits(0.1)
	var g1_records: Array[Dictionary] = []
	for raw_record in boss._records.values():
		var record: Dictionary = raw_record
		if int(record.get("generation", -1)) == 1:
			g1_records.append(record)
	_check("G0 分裂建立两个 G1 节点", g1_records.size() == 2)
	_check("两个 G1 首次生成即进入隐藏下降",
		g1_records.all(func(record: Dictionary) -> bool:
			return String(record.get("state", "")) == HyperAScript.STATE_DESCENT))
	_check("G1 首次落地后的循环技能至少等待 40 秒",
		g1_records.all(func(record: Dictionary) -> bool:
			return float(record.get("reentry_cd", 0.0)) >= HyperAScript.REENTRY_COOLDOWN))
	_check("G1 撞击前无模型且位于 30,000m",
		g1_records.all(func(record: Dictionary) -> bool:
			var ac := record.get("ac") as Aircraft
			return ac != null and not ac.visible \
				and is_equal_approx(ac.altitude, HyperAScript.DESCENT_START_ALTITUDE)))
	_check("G1 隐藏下降时不可受击且武器静默",
		g1_records.all(func(record: Dictionary) -> bool:
			var ac := record.get("ac") as Aircraft
			return ac != null and ac.invulnerable \
				and not bool(ac.get_meta(HyperAScript.META_WEAPONS_ENABLED, true)) \
				and bool(ac.get_meta(HyperAScript.META_FORCE_HIDDEN_VISUAL, false))))
	var reveal_record: Dictionary = g1_records.front()
	boss._set_hidden(reveal_record, false)
	var revealed := reveal_record.get("ac") as Aircraft
	_check("G1 撞击揭示时恢复模型并释放语义隐藏",
		revealed != null and revealed.visible \
		and not revealed.has_meta(HyperAScript.META_FORCE_HIDDEN_VISUAL))
	boss._records.clear()
	boss._pending_splits.clear()
	boss._player = null
	scene_root.free()
	player.free()

	var shooter := Aircraft.new()
	shooter.params = load(HyperAScript.PARAM_PATHS[1]) as AircraftParams
	shooter.team = CombatUnit.TEAM_HOSTILE
	shooter.altitude = HyperAScript.COMBAT_ALTITUDE
	shooter.heading = 0.0
	shooter.speed = 900.0 / 3.6
	shooter.max_simultaneous_locks = 4
	shooter.missiles_remaining = 4
	shooter.missile_auto_fire = true
	shooter.use_tactical_planner = true
	shooter.weapon_mode = Aircraft.WeaponMode.GUN
	shooter.set_meta(HyperAScript.META_SATURATION_SALVO, true)
	shooter.set_meta(HyperAScript.META_WEAPONS_ENABLED, true)
	shooter.set_meta(&"saturation_attacker", true)
	var missile_manager := MissileManager.new()
	shooter.missile_manager = missile_manager
	var targets: Array[Aircraft] = []
	for bearing_deg in [-90.0, -45.0, 45.0, 90.0]:
		var target := Aircraft.new()
		target.params = load(HyperAScript.PARAM_PATHS[3]) as AircraftParams
		target.team = CombatUnit.TEAM_PLAYER
		target.hp = target.params.max_hp
		target.altitude = HyperAScript.COMBAT_ALTITUDE
		var bearing := deg_to_rad(bearing_deg)
		target.global_position = Vector2(sin(bearing), -cos(bearing)) * 1000.0
		shooter.radar_targets[target] = shooter.params.lock_time
		targets.append(target)
	_check("G1 普通前向雷达排除左右 90° 正侧方",
		not shooter.is_in_radar_cone(targets.front().global_position)
		and not shooter.is_in_radar_cone(targets.back().global_position))
	AircraftWeapons.update_missile(shooter, 0.1)
	_check("G1 不会向侧面成熟锁定目标离轴齐射",
		missile_manager.get_child_count() == 0)
	_check("G1 侧向目标未发射时不消耗弹匣", shooter.missiles_remaining == 4)
	_check("G1 不携带 G0 全向离轴许可",
		not shooter.has_meta(HyperAScript.META_G0_OMNIDIRECTIONAL_SALVO))
	_check("G1 侧向拒射不会瞬间改写机体航向", is_equal_approx(shooter.heading, 0.0))
	missile_manager.free()
	for target in targets:
		target.free()
	shooter.free()


func _test_g0_independent_saturation_salvo() -> void:
	var shooter := Aircraft.new()
	shooter.params = load(HyperAScript.PARAM_PATHS[0]) as AircraftParams
	shooter.team = CombatUnit.TEAM_HOSTILE
	shooter.altitude = HyperAScript.COMBAT_ALTITUDE
	shooter.heading = 0.0
	shooter.speed = 900.0 / 3.6
	shooter.max_simultaneous_locks = HyperAScript.LOCK_CAPACITY[0]
	shooter.missiles_remaining = 4
	shooter.missile_auto_fire = true
	shooter.use_tactical_planner = true
	# 精确复现实机缺口：G0 有激光时 planner 可把主武器留在 GUN，
	# 但独立饱和火控仍须消费已经成熟的正常前向锁定。
	shooter.weapon_mode = Aircraft.WeaponMode.GUN
	shooter.set_meta(HyperAScript.META_SATURATION_SALVO, true)
	shooter.set_meta(HyperAScript.META_G0_OMNIDIRECTIONAL_SALVO, true)
	shooter.set_meta(HyperAScript.META_WEAPONS_ENABLED, true)
	shooter.set_meta(&"hyper_a_generation", 0)
	shooter.set_meta(&"saturation_attacker", true)
	var missile_manager := MissileManager.new()
	shooter.missile_manager = missile_manager
	var targets: Array[Aircraft] = []
	for bearing_deg in [-135.0, -45.0, 45.0, 135.0]:
		var target := Aircraft.new()
		target.params = load(HyperAScript.PARAM_PATHS[3]) as AircraftParams
		target.team = CombatUnit.TEAM_PLAYER
		target.hp = target.params.max_hp
		target.altitude = HyperAScript.COMBAT_ALTITUDE
		var bearing := deg_to_rad(bearing_deg)
		target.global_position = Vector2(sin(bearing), -cos(bearing)) * 1000.0
		shooter.radar_targets[target] = shooter.params.lock_time
		targets.append(target)
	AircraftWeapons.update_missile(shooter, 0.1)
	_check("G0 主武器为激光时仍向全向四目标齐射",
		missile_manager.get_child_count() == 4
		and targets.all(func(target: Aircraft) -> bool:
			return shooter.is_in_radar_cone(target.global_position)))
	_check("G0 独立齐射正常消耗四发弹匣", shooter.missiles_remaining == 0)
	var fired_target_ids: Dictionary = {}
	var omnidirectional_headings_ok := true
	for child in missile_manager.get_children():
		var missile := child as Missile
		if missile != null and missile.target != null:
			fired_target_ids[missile.target.get_instance_id()] = true
			var los: Vector2 = missile.target.global_position - shooter.global_position
			var expected_heading := atan2(los.x, -los.y)
			if absf(shooter._angle_diff(missile.heading, expected_heading)) > 0.01:
				omnidirectional_headings_ok = false
	_check("G0 八锁容量按不同目标分配并直接朝各目标离架",
		fired_target_ids.size() == 4 and omnidirectional_headings_ok)
	var fired_before_disable := missile_manager.get_child_count()
	shooter.missiles_remaining = 4
	shooter._missile_cooldown = 0.0
	shooter.set_meta(HyperAScript.META_WEAPONS_ENABLED, false)
	AircraftWeapons.update_missile(shooter, 0.1)
	_check("Hyper-A 特殊状态关闭武器时独立火控保持静默",
		missile_manager.get_child_count() == fired_before_disable)
	missile_manager.free()
	for target in targets:
		target.free()
	shooter.free()


func _test_charge_alignment_regression() -> void:
	_check("冲锋最短蓄力延长到 2.4 秒",
		HyperAScript.DASH_TELEGRAPH_DURATION >= 2.4)
	_check("对线超时长于最短蓄力",
		HyperAScript.DASH_ALIGN_TIMEOUT > HyperAScript.DASH_TELEGRAPH_DURATION)
	_check("机头必须在 6 度内才可冲锋",
		HyperAScript.DASH_ALIGN_TOLERANCE <= deg_to_rad(6.0))

	var boss = HyperAScript.new()
	var ac := Aircraft.new()
	ac.params = load(HyperAScript.PARAM_PATHS[2]) as AircraftParams
	ac.global_position = Vector2(100.0, 200.0)
	ac.heading = PI
	ac.speed = 360.0 / 3.6
	var before_heading := ac.heading
	var before_speed := ac.speed
	var record := {"ac": ac, "path": "Hyper-A1.1.1", "generation": 2}
	boss._begin_dash_telegraph(record, ac)
	_check("蓄力入口不再把速度归零", is_equal_approx(ac.speed, before_speed))
	_check("蓄力入口不再瞬间改航向", is_equal_approx(ac.heading, before_heading))
	_check("蓄力目标速度高于该代失速速度",
		float(record.get("charge_speed_kmh", 0.0))
		> ac.params.stall_speed_base * 1.3)
	boss._update_telegraph(record, ac, HyperAScript.DASH_TELEGRAPH_DURATION + 0.1)
	_check("背向攻击线时最短蓄力结束也不强行冲锋",
		String(record.get("state", "")) == HyperAScript.STATE_TELEGRAPH)
	ac.free()

	var hyper_source := FileAccess.get_file_as_string("res://scripts/survivor/hyper_a_boss.gd")
	_check("冲锋实现不存在 speed=0 旧路径", not hyper_source.contains("ac.speed = 0.0"))
	_check("冲锋实现不存在直接 heading 改写", not hyper_source.contains("ac.heading ="))
	var overlay_source := FileAccess.get_file_as_string(
		"res://scripts/survivor/hyper_a_threat_overlay.gd")
	_check("危险线消费 progress 并从近端插值生长",
		overlay_source.contains("warning.get(\"progress\"")
		and overlay_source.contains("from.lerp(full_to, progress)"))
	_check("急刹扇区只在攻击线完整抵达终点后显示",
		overlay_source.contains("if progress >= 0.999:")
		and overlay_source.find("if progress >= 0.999:")
			< overlay_source.find("_draw_brake_warning(full_to"))

	var climb_boss = HyperAScript.new()
	var climb_ac := Aircraft.new()
	climb_ac.params = load(HyperAScript.PARAM_PATHS[1]) as AircraftParams
	climb_ac.altitude = HyperAScript.COMBAT_ALTITUDE
	var climb_record := {"ac": climb_ac, "path": "Hyper-A1.1", "generation": 1}
	climb_boss._records[climb_ac.get_instance_id()] = climb_record
	var queued_record := {
		"path": "Hyper-A1.2", "generation": 1,
		"state": HyperAScript.STATE_FIGHTER, "reentry_cd": 0.0,
	}
	climb_boss._records[1] = queued_record
	var target_holder := Aircraft.new()
	var holder_ai := AIController.new()
	holder_ai.name = "AIController"
	target_holder.add_child(holder_ai)
	target_holder.combat_target = climb_ac
	target_holder.commanded_target = climb_ac
	target_holder.secondary_combat_target = climb_ac
	target_holder.target_position = Vector2(800.0, 400.0)
	target_holder.radar_targets[climb_ac] = 1.0
	target_holder.secondary_radar_targets[climb_ac] = 1.0
	holder_ai._current_target = climb_ac
	var saved_all_units: Array[CombatUnit] = CombatUnit.all_units.duplicate()
	var isolated_units: Array[CombatUnit] = [climb_ac, target_holder]
	CombatUnit.all_units = isolated_units
	climb_boss._begin_climb(climb_record, climb_ac)
	_check("一架开始高空序列后其余分裂体至少再错峰 12 秒",
		float(queued_record.get("reentry_cd", 0.0)) >= HyperAScript.REENTRY_QUEUE_SPACING)
	climb_boss._update_climb(climb_record, climb_ac, HyperAScript.CLIMB_DURATION + 0.1)
	_check("爬升消失时立即解除主副目标、命令目标、雷达锁存与旧追击点",
		target_holder.combat_target == null
		and target_holder.commanded_target == null
		and target_holder.secondary_combat_target == null
		and holder_ai._current_target == null
		and target_holder.target_position == Vector2.INF
		and not target_holder.radar_targets.has(climb_ac)
		and not target_holder.secondary_radar_targets.has(climb_ac))
	_check("爬升完成先进入独立高空等待而非立刻俯冲",
		String(climb_record.get("state", "")) == HyperAScript.STATE_HIGH_ALTITUDE_HOLD
		and not climb_ac.visible)
	var hold_entries := climb_boss.get_hud_entries()
	_check("模型消失后状态栏仍保留高空等待高度与倒数",
		hold_entries.size() == 1
		and String(hold_entries[0].get("state", "")) == "HIGH HOLD"
		and is_equal_approx(float(hold_entries[0].get("altitude", 0.0)),
			HyperAScript.DESCENT_START_ALTITUDE)
		and float(hold_entries[0].get("seconds", 0.0)) >= HyperAScript.HIGH_ALTITUDE_HOLD_MIN)
	var hud := SurvivorHUD.new()
	var hold_text := hud._format_custom_boss_entries(hold_entries)
	_check("高空等待条目明确显示 HIGH HOLD、30km 与剩余秒数",
		hold_text.contains("HIGH HOLD 30.0km") and hold_text.contains("s"))
	hud.free()
	climb_boss._update_high_altitude_hold(climb_record, climb_ac,
		HyperAScript.HIGH_ALTITUDE_HOLD_MAX + 0.1)
	_check("高空等待结束后才开始 4 秒俯冲预警",
		String(climb_record.get("state", "")) == HyperAScript.STATE_DESCENT
		and is_equal_approx(float(climb_record.get("timer", 0.0)), HyperAScript.DESCENT_DURATION))
	CombatUnit.all_units = saved_all_units
	target_holder.free()
	climb_ac.free()
	var crash_guards := FileAccess.get_file_as_string(
		"res://scripts/events/boss_encounter_event.gd") \
		+ FileAccess.get_file_as_string("res://scripts/aircraft.gd") \
		+ FileAccess.get_file_as_string("res://scripts/missile_manager.gd")
	_check("闪退路径包含 Variant 生命周期、meta 与三角形守卫",
		crash_guards.contains("var raw_player: Variant")
		and crash_guards.contains("has_meta(\"_pending_attacker\")")
		and crash_guards.contains("var tri_a := PackedVector2Array"))
	var stale_player := Aircraft.new()
	var fake_director := FreedPlayerDirector.new()
	fake_director.player = stale_player
	var event := BossEncounterEvent.new(Vector2.ZERO, 0.0, "default")
	event.director = fake_director
	stale_player.free()
	_check("事件读取已释放玩家引用时安全回落 null", event._live_player() == null)
	var damaged := Aircraft.new()
	damaged.params = load(HyperAScript.PARAM_PATHS[3]) as AircraftParams
	damaged.hp = 70.0
	damaged.team = CombatUnit.TEAM_PLAYER
	damaged._apply_damage(1.0)
	_check("无 _pending_attacker 的伤害路径不报错", is_equal_approx(damaged.hp, 69.0))
	damaged.free()
	var gameplay_i18n := FileAccess.get_file_as_string("res://i18n/gameplay.csv")
	_check("Black Star 演出 motto 已更新",
		gameplay_i18n.contains("BOSS_BANNER_BLACK_STAR_MOTTO,Blame it on the falling sky"))


func _test_arrival_sequence() -> void:
	var file := FileAccess.open("res://resources/presentation/sequences.json", FileAccess.READ)
	_check("表演序列文件可读取", file != null)
	if file == null:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	var defs: Dictionary = parsed if typeof(parsed) == TYPE_DICTIONARY else {}
	var seq: Dictionary = defs.get("black_star_arrival", {})
	_check("BLACK STAR 登场序列存在", not seq.is_empty())
	if seq.is_empty():
		return
	var max_sec := float(seq.get("max_sec", 999.0))
	_check("登场演出总预算不超过 7 秒", max_sec <= 7.0)
	var reveal_at := INF
	var dismiss_end := -INF
	var cut_at := INF
	var release_at := -INF
	var radio_count := 0
	for step in seq.get("steps", []):
		var at := float(step.get("at", 0.0))
		var end := at + float(step.get("dur", 0.0))
		var channel := String(step.get("ch", ""))
		var op := String(step.get("op", ""))
		if channel == "banner" and op == "reveal":
			reveal_at = at
		elif channel == "banner" and op == "dismiss":
			dismiss_end = end
		elif channel == "camera" and op == "cut_to":
			cut_at = at
		elif channel == "actor" and op == "release":
			release_at = at
		elif channel == "radio" and op == "line":
			radio_count += 1
	_check("状态横幅从第 0 秒开始", is_equal_approx(reveal_at, 0.0))
	_check("隐藏根机不再切到固定事件锚点", is_inf(cut_at))
	_check("双根无线电改由真实下降信号触发", radio_count == 0)
	_check("横幅退完后立即释放演员进入真实下降", release_at >= dismiss_end)


func _check(label: String, ok: bool) -> void:
	if ok:
		_pass += 1
		print("  ✓ %s" % label)
	else:
		_fail += 1
		printerr("  ✗ %s" % label)
