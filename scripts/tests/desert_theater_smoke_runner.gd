extends Node

const SURVIVOR_MODE_SCENE := preload("res://scenes/survivor_mode.tscn")
const BOSS_SCRIPT := preload("res://scripts/survivor/the_crucible_boss.gd")
const ACE_BAR_PATH := "res://scripts/survivor/ace_battle_bar.gd"
const DESERT_AIRFIELD_EXPECTED := {
	&"AF_HANEDA": {"center": Vector2(8672.0, 4318.0), "name_key": "DOCK_NEWMAN_NAME"},
	&"AF_KISARAZU": {"center": Vector2(-8500.0, -1500.0), "name_key": "DOCK_WESTERN_RIDGE_NAME"},
	&"AF_CHOFU": {"center": Vector2(-3000.0, 12000.0), "name_key": "DOCK_OPHTHALMIA_NAME"},
}
const AIRFIELD_RAIL_CLEARANCE_PX := 2500.0
const AIRFIELD_BUILDING_CLEARANCE_PX := 1200.0

var _pass := 0
var _fail := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().set_meta("survivor_map_id", "desert_railway_preview")
	get_tree().set_meta("ugc_map_path", "res://resources/maps/desert_railway_preview.aglmap")
	get_tree().set_meta("map_preview_only", false)
	get_tree().set_meta("survivor_aircraft_resource", "res://resources/player/playable_f15c.tres")
	var mode = SURVIVOR_MODE_SCENE.instantiate()
	add_child(mode)
	for _frame in range(4):
		await get_tree().process_frame
	if mode._zone_data == null or mode._desert_front == null:
		_check("沙漠正式入口完成初始化", false)
		mode.queue_free()
		await get_tree().process_frame
		get_tree().quit(1)
		return

	_check("沙漠正式入口构造地图与战区", mode._map_id == "desert_railway_preview"
		and not mode._map_preview_only and mode._ugc_doc != null and mode._zone_data != null)
	_check("沙漠移除 naval 槽并复用中队任务", mode._zone_data.get_mission_type(&"E") == "squadron")
	_check("集中地面战线控制器已接线", mode._desert_front != null)
	_check("沙漠保留三座机场名额", ZoneData.AIRFIELD_IDS.size() == 3,
		"count=%d" % ZoneData.AIRFIELD_IDS.size())
	_check("沙漠地图绘制三座机场跑道", mode._ugc_doc.airports.size() == 3,
		"count=%d" % mode._ugc_doc.airports.size())
	_check("沙漠地图提供三份本地机场定义", mode._ugc_doc.zones.size() == 3,
		"count=%d" % mode._ugc_doc.zones.size())
	var airport_centers: Dictionary = {}
	var airport_name_keys: Dictionary = {}
	for airport_id in ZoneData.AIRFIELD_IDS:
		var airport_zone: Dictionary = mode._zone_data.get_zone_by_id(airport_id)
		var airport_center: Vector2 = airport_zone.get("center", Vector2.INF)
		var expected: Dictionary = DESERT_AIRFIELD_EXPECTED.get(airport_id, {})
		airport_centers[airport_id] = airport_center
		airport_name_keys[String(airport_zone.get("name_key", ""))] = true
		_check("%s 开局可解放且位于沙漠陆地" % airport_id,
			mode._zone_data.get_state(airport_id) == ZoneData.State.AVAILABLE
			and mode._zone_data.get_mission_type(airport_id) == "airfield"
			and airport_center != Vector2.INF
			and MapGeography.is_on_land(airport_center), str(airport_center))
		_check("%s 使用沙漠本地名称与地理坐标" % airport_id,
			not expected.is_empty()
			and airport_center == expected.get("center", Vector2.INF)
			and String(airport_zone.get("name_key", "")) == String(expected.get("name_key", ""))
			and String(airport_zone.get("dock_name_key", "")) == String(expected.get("name_key", "")),
			"center=%s key=%s" % [airport_center, airport_zone.get("name_key", "")])
	_check("三座沙漠机场名称互不重复且没有日本地名", airport_name_keys.size() == 3
		and not airport_name_keys.has("DOCK_HANEDA_NAME")
		and not airport_name_keys.has("DOCK_KISARAZU_NAME")
		and not airport_name_keys.has("DOCK_CHOFU_NAME"), str(airport_name_keys.keys()))
	var railway_points := PackedVector2Array()
	for point_data in mode._ugc_doc.railways[0].get("points", []):
		railway_points.append(Vector2(float(point_data[0]), float(point_data[1])))
	for airport_index in range(mini(mode._ugc_doc.airports.size(), ZoneData.AIRFIELD_IDS.size())):
		var airport_entry: Dictionary = mode._ugc_doc.airports[airport_index]
		var polygon_data: Array = airport_entry.get("polygon", [])
		var polygon_center := Vector2.ZERO
		for point_data in polygon_data:
			polygon_center += Vector2(float(point_data[0]), float(point_data[1]))
		if not polygon_data.is_empty():
			polygon_center /= float(polygon_data.size())
		var visual_airport_id: StringName = ZoneData.AIRFIELD_IDS[airport_index]
		var zone_center: Vector2 = airport_centers.get(visual_airport_id, Vector2.INF)
		_check("%s 跑道与机场战区对齐" % visual_airport_id,
			polygon_data.size() >= 4 and polygon_center.distance_to(zone_center) <= 1.0,
			"runway=%s zone=%s" % [polygon_center, zone_center])
		var rail_clearance := _distance_to_polyline(zone_center, railway_points)
		var building_clearance := _distance_to_buildings(zone_center, mode._ugc_doc.buildings)
		var mountain_clear := _point_clear_of_polygons(zone_center,
			mode._ugc_doc.layer_polygons.get("mountain", []))
		_check("%s 避开铁路、建筑和山体" % visual_airport_id,
			rail_clearance >= AIRFIELD_RAIL_CLEARANCE_PX
			and building_clearance >= AIRFIELD_BUILDING_CLEARANCE_PX
			and mountain_clear,
			"rail=%.0f building=%.0f mountain_clear=%s" % [rail_clearance,
				building_clearance, str(mountain_clear)])
	var initial: Vector2i = mode._desert_front.live_ground_counts()
	_check("开局中央战线为 3v3", initial == Vector2i(3, 3), str(initial))

	mode._desert_front.on_zone_captured(&"A", Vector2(-5200.0, 3700.0))
	var captured: Vector2i = mode._desert_front.live_ground_counts()
	_check("攻克设施立即生产两辆友军 SPG", captured == Vector2i(5, 3), str(captured))
	mode._desert_front.call("_update_production", 60.0)
	var produced: Vector2i = mode._desert_front.live_ground_counts()
	_check("设施 60 秒续产一辆", produced.x == 6, str(produced))

	mode._desert_front.call("_update_helicopter_waves", 90.0)
	var heli_count: int = mode._desert_front.get("_helicopters").size()
	_check("首批真实生成四架 AH-64", heli_count == 4, "count=%d" % heli_count)

	mode.game_time = 100.0
	mode._zone_data.debug_set_available(&"A")
	mode._zone_data.set_mission_type(&"A", "squadron")
	mode._on_zone_mission_completed(&"A")
	_check("中队支线不改变标准倒计时", is_equal_approx(mode.game_time, 100.0),
		"time=%.1f" % mode.game_time)
	mode._zone_data.debug_set_available(&"B")
	mode._zone_data.set_mission_type(&"B", "bomber_escort")
	mode._on_zone_mission_completed(&"B")
	_check("护送支线不改变标准倒计时", is_equal_approx(mode.game_time, 100.0),
		"time=%.1f" % mode.game_time)

	# The Crucible 必须走正式 SurvivorSpawner 与真实 Aircraft 场景，不能只验证注册表。
	var crucible_spawn_center: Vector2 = mode.player_aircraft.global_position
	var crucible_spawn_heading: float = mode.player_aircraft.heading
	var crucible := BossRegistry.instantiate("THE_CRUCIBLE")
	mode._spawner._spawn_boss(crucible, mode.player_aircraft.global_position, true)
	await get_tree().process_frame
	var opening_roster_size := _profile_aircraft_total_through(3)
	_check("The Crucible 开场预生成前三支真实 Ace 队供切镜",
		crucible != null and crucible.active
		and crucible.get_display_members().size() == opening_roster_size,
		"members=%d expected=%d" % [crucible.get_display_members().size(), opening_roster_size])
	var staged_are_dormant := true
	for staged in crucible.get_display_members():
		staged_are_dormant = staged_are_dormant and not bool(staged.get_meta("crucible_active", false))
	_check("The Crucible 开场预生成队不会提前参战", staged_are_dormant)
	var radio_text_before: String = mode._radio.debug_current_text()
	var radio_queue_before: int = mode._radio.debug_queue_size()
	var crucible_event := BossEncounterEvent.new(mode.player_aircraft.global_position, 0.0,
		"desert_railway_preview", "THE_CRUCIBLE")
	crucible_event.encounter = crucible
	mode.on_boss_engaged(crucible_event)
	_check("The Crucible 接战不回退播放默认 BOSS 无线电",
		mode._radio.debug_current_text() == radio_text_before
		and mode._radio.debug_queue_size() == radio_queue_before)
	crucible.engage()
	var opening_targets_ok := true
	var opening_spawn_geometry_ok := true
	var opening_squads: Array = crucible.get("_squads")
	for squad_index in range(mini(3, opening_squads.size())):
		var opening_squad := opening_squads[squad_index] as AceSupportSquad
		if opening_squad == null:
			opening_targets_ok = false
			opening_spawn_geometry_ok = false
			continue
		var actual_spawn: Vector2 = opening_squad.entry_origin_override
		var spawn_offset := actual_spawn - crucible_spawn_center
		var spawn_distance := spawn_offset.length()
		var relative_bearing := wrapf(rad_to_deg(
			atan2(spawn_offset.x, -spawn_offset.y) - crucible_spawn_heading), -180.0, 180.0)
		var side_semantics_ok := (squad_index == 0 and relative_bearing < 0.0) \
			or (squad_index == 1 and absf(relative_bearing) <= 15.0) \
			or (squad_index == 2 and relative_bearing > 0.0)
		opening_spawn_geometry_ok = opening_spawn_geometry_ok \
			and spawn_distance >= BOSS_SCRIPT.ENTRY_DISTANCE_PX - 1.0 \
			and spawn_distance <= BOSS_SCRIPT.ENTRY_DISTANCE_MAX_PX + 1.0 \
			and absf(relative_bearing) <= BOSS_SCRIPT.ENTRY_ALLOWED_MAX_DEG \
			and side_semantics_ok \
			and MapBoundary.is_safe_inside(actual_spawn, 1200.0) \
			and not mode.is_world_pos_visible(actual_spawn)
		for opening_member in opening_squad.members:
			if not is_instance_valid(opening_member):
				opening_targets_ok = false
				opening_spawn_geometry_ok = false
				continue
			opening_spawn_geometry_ok = opening_spawn_geometry_ok \
				and not mode.is_world_pos_visible(opening_member.global_position) \
				and MapBoundary.is_safe_inside(opening_member.global_position, 1200.0)
			var opening_ai := opening_member._get_ai_controller()
			var opening_target: Variant = opening_ai.get("_current_target") if opening_ai else null
			opening_targets_ok = opening_targets_ok \
				and typeof(opening_target) == TYPE_OBJECT and opening_target != null \
				and is_instance_valid(opening_target) \
				and not (opening_target as CombatUnit).is_player_squad() \
				and (opening_target as CombatUnit).team != opening_member.team
	_check("The Crucible 首发三队保持相对航向语义并在当前镜头外生成",
		opening_spawn_geometry_ok)
	_check("The Crucible 开局第一帧只选择其它 Ace 队目标", opening_targets_ok)
	crucible.update(BOSS_SCRIPT.OPENING_MELEE_DURATION_S - 0.1)
	var before_switch_excludes_player: bool = crucible.is_opening_melee_active()
	for opening_member in crucible.get_display_members():
		if not is_instance_valid(opening_member) or (opening_member as Aircraft).is_destroyed:
			continue
		var opening_ai := (opening_member as Aircraft)._get_ai_controller()
		var opening_target: Variant = opening_ai.get("_current_target") if opening_ai else null
		before_switch_excludes_player = before_switch_excludes_player \
			and typeof(opening_target) == TYPE_OBJECT and opening_target != null \
			and is_instance_valid(opening_target) \
			and not (opening_target as CombatUnit).is_player_squad()
	_check("8 秒混战窗结束前不会中途盯上玩家", before_switch_excludes_player)
	crucible.update(0.1)
	var assigned_player_hunters := 0
	var player_hunters_locked := 0
	var mixed_fighters_on_player := 0
	for opening_member in crucible.get_display_members():
		if not is_instance_valid(opening_member) or (opening_member as Aircraft).is_destroyed:
			continue
		var is_player_hunter := bool(
			(opening_member as Aircraft).get_meta("crucible_player_hunter", false))
		if is_player_hunter:
			assigned_player_hunters += 1
		var opening_ai := (opening_member as Aircraft)._get_ai_controller()
		var opening_target: Variant = opening_ai.get("_current_target") if opening_ai else null
		if typeof(opening_target) == TYPE_OBJECT and opening_target != null \
				and is_instance_valid(opening_target) \
				and (opening_target as CombatUnit).is_player_squad():
			if is_player_hunter:
				player_hunters_locked += 1
			else:
				mixed_fighters_on_player += 1
	_check("8 秒结束沿每支活跃队仅一机盯玩家，其余继续 FFA",
		not crucible.is_opening_melee_active()
		and assigned_player_hunters == opening_squads.size()
		and player_hunters_locked == assigned_player_hunters
		and mixed_fighters_on_player == 0,
		"assigned=%d locked=%d mixed_on_player=%d" % [
			assigned_player_hunters, player_hunters_locked, mixed_fighters_on_player])
	var backstab_bait: Aircraft = null
	var opportunist: Aircraft = null
	for member_variant in crucible.get_display_members():
		var member := member_variant as Aircraft
		if member == null or member.is_destroyed:
			continue
		if backstab_bait == null and bool(member.get_meta("crucible_player_hunter", false)):
			backstab_bait = member
		elif opportunist == null and not bool(member.get_meta("crucible_player_hunter", false)) \
				and (backstab_bait == null or member.team != backstab_bait.team):
			opportunist = member
	if backstab_bait != null and opportunist != null:
		var staging_center: Vector2 = mode.player_aircraft.global_position
		var staging_index := 0
		for member_variant in crucible.get_display_members():
			var member := member_variant as Aircraft
			if member == null or member.is_destroyed:
				continue
			member.global_position = staging_center + Vector2(
				-700.0 + float(staging_index) * 125.0, -1200.0)
			member.heading = PI
			staging_index += 1
		backstab_bait.global_position = staging_center + Vector2(0.0, -500.0)
		backstab_bait.heading = 0.0
		opportunist.global_position = backstab_bait.global_position + Vector2(0.0, 500.0)
		crucible.call("_retarget_all", true)
	var opportunist_target: Variant = null
	if opportunist != null:
		var opportunist_ai := opportunist._get_ai_controller()
		opportunist_target = opportunist_ai.get("_current_target") if opportunist_ai else null
	_check("混战位会从后方抢攻正在缠住玩家的敌方 Ace",
		backstab_bait != null and opportunist != null
		and typeof(opportunist_target) == TYPE_OBJECT and opportunist_target != null
		and is_instance_valid(opportunist_target) and opportunist_target == backstab_bait)
	var successor: Aircraft = null
	var successor_target: Variant = null
	if backstab_bait != null:
		var vacated_team := backstab_bait.team
		backstab_bait.is_destroyed = true
		crucible.call("_retarget_all", true)
		for member_variant in crucible.get_display_members():
			var member := member_variant as Aircraft
			if member != null and not member.is_destroyed and member.team == vacated_team \
					and bool(member.get_meta("crucible_player_hunter", false)):
				successor = member
				var successor_ai := successor._get_ai_controller()
				successor_target = successor_ai.get("_current_target") if successor_ai else null
				break
		backstab_bait.is_destroyed = false
		crucible.call("_retarget_all", true)
	_check("玩家猎手阵亡后同队存活 Ace 立即接班",
		successor != null and successor != backstab_bait
		and typeof(successor_target) == TYPE_OBJECT and successor_target != null
		and is_instance_valid(successor_target)
		and (successor_target as CombatUnit).is_player_squad())
	var opening_hud_entries: Array[Dictionary] = crucible.get_hud_entries()
	var opening_hud_members := _crucible_hud_member_count(opening_hud_entries)
	_check("熔炉 HUD 只显示首批三队，未入场队不占位",
		opening_hud_entries.size() == 3 and opening_hud_members == opening_roster_size,
		"entries=%d members=%d expected=%d" % [
			opening_hud_entries.size(), opening_hud_members, opening_roster_size])
	# 正式 BossEncounterEvent 在 ENGAGED 相位开放 HUD；本测试手动直达接战，显式补同一状态。
	crucible.hud_visible = true
	mode.hud._update_boss_panel()
	await get_tree().process_frame
	var shared_bar_ui: bool = mode.hud._crucible_ace_bars.size() == 3
	var regular_bar_path: String = String(mode.hud._ace_panel.get_script().resource_path)
	for bar in mode.hud._crucible_ace_bars:
		shared_bar_ui = shared_bar_ui \
			and String(bar.get_script().resource_path) == ACE_BAR_PATH \
			and String(bar.get_script().resource_path) == regular_bar_path
	_check("熔炉三队精确复用常规地图王牌中队条控件", shared_bar_ui,
		"path=%s" % regular_bar_path)
	crucible.update(6.0)
	_check("未灭队时不会按绝对时间堆入新敌机",
		crucible.get_display_members().size() == opening_roster_size)
	for member_index in range(5):
		(crucible.get_display_members()[member_index] as Aircraft).is_destroyed = true
	crucible.update(2.9)
	_check("空位出现后三秒前不补队",
		crucible.get_display_members().size() == opening_roster_size)
	crucible.update(0.1)
	_check("空位出现三秒后只补一队",
		crucible.get_display_members().size() == _profile_aircraft_total_through(4)
		and crucible.get_hud_entries().size() == 3)
	var max_active_entries := crucible.get_hud_entries().size()
	while crucible.get_display_members().size() < _profile_aircraft_total_through(
			BOSS_SCRIPT.PROFILE_ORDER.size()):
		var active_squads: Array = crucible.get("_squads")
		var squad_eliminated := false
		for squad_variant in active_squads:
			var squad := squad_variant as AceSupportSquad
			if squad == null or not squad.active:
				continue
			for member in squad.members:
				if is_instance_valid(member):
					member.is_destroyed = true
			squad_eliminated = true
			break
		if not squad_eliminated:
			break
		crucible.update(BOSS_SCRIPT.REINFORCEMENT_DELAY_S)
		max_active_entries = maxi(max_active_entries, crucible.get_hud_entries().size())
	crucible.update(0.6)
	_check("The Crucible 全部波次与高击坠检查均不产生无线电",
		mode._radio.debug_current_text() == radio_text_before
		and mode._radio.debug_queue_size() == radio_queue_before)
	await get_tree().process_frame
	var crucible_members: Array = crucible.get_display_members()
	var faction_counts: Dictionary = {}
	var all_high_lod := crucible_members.size() == 73
	var dense_phase_counts: Dictionary = {}
	var player_hunters := 0
	var all_active := true
	var themed_new_members := 0
	var ido_members := 0
	var ido_all_networked := true
	var hounds: Array[Aircraft] = []
	for member_variant in crucible_members:
		var member: Variant = member_variant
		if typeof(member) != TYPE_OBJECT or not is_instance_valid(member):
			all_high_lod = false
			continue
		var ac := member as Aircraft
		faction_counts[ac.team] = int(faction_counts.get(ac.team, 0)) + 1
		if bool(ac.get_meta("crucible_player_hunter", false)):
			player_hunters += 1
		all_active = all_active and bool(ac.get_meta("crucible_active", false))
		if String(ac.get_meta("crucible_profile", "")) in ["moirai", "lash", "ido", "undertow",
				"croupier", "tallyman", "palimpsest", "quorum", "deadeye", "mirror", "funeral"]:
			if ac.has_meta("ace_theme_state"):
				themed_new_members += 1
		if String(ac.get_meta("crucible_profile", "")) == "ido":
			ido_members += 1
			ido_all_networked = ido_all_networked and ac.no_pilot and ac.flares_remaining == 2
		var is_hound := String(ac.get_meta("crucible_profile", "")) == "hound"
		if is_hound:
			hounds.append(ac)
		else:
			var dense_phase := int(ac.get_meta(&"dense_battle_sim_phase", -1))
			dense_phase_counts[dense_phase] = int(dense_phase_counts.get(dense_phase, 0)) + 1
			all_high_lod = all_high_lod \
				and int(ac.get_meta(&"dense_battle_sim_divisor", 0)) == 4
		all_high_lod = all_high_lod and ac.lod_level == 0 \
			and bool(ac.get_meta("crucible_high_lod", false))
	_check("The Crucible 18 队依次补齐共 73 架", crucible_members.size() == 73,
		"count=%d" % crucible_members.size())
	_check("The Crucible 18 个 FFA 阵营均已落地", faction_counts.size() == 18,
		str(faction_counts))
	_check("The Crucible 全员保持高 LOD", all_high_lod)
	_check("常规 71 架完整模拟均匀错分四相",
		dense_phase_counts == {0: 18, 1: 18, 2: 18, 3: 17}, str(dense_phase_counts))
	_check("接力终段仍仅由每支活跃队一机盯玩家",
		player_hunters == crucible.get_hud_entries().size(),
		"hunters=%d active_squads=%d" % [
			player_hunters, crucible.get_hud_entries().size()])
	var hound_boss_grade := hounds.size() == 2
	for hound in hounds:
		var hound_ai := hound._get_ai_controller()
		hound_boss_grade = hound_boss_grade \
			and hound.callsign in ["Hound-1", "Hound-2"] \
			and is_equal_approx(hound.params.max_hp, AceTier.MAX_HP) \
			and hound.flares_remaining == 3 \
			and hound.params.missile != null and hound.params.missile.max_count == 10 \
			and bool(hound.get_meta(&"ace_boss_grade", false)) \
			and int(hound.get_meta(&"dense_battle_sim_divisor", 0)) == 1 \
			and hound_ai != null and hound_ai.ai_tick_divisor == 1 \
			and is_equal_approx(hound_ai.skill_level, 1.0) \
			and is_equal_approx(hound_ai.composure, 1.0) \
			and is_equal_approx(hound_ai.focus, 1.0) \
			and is_equal_approx(hound_ai.situational_awareness, 1.0) \
			and hound_ai._scaling_class_cached == AIController.AIScaleClass.IMMUNE
	_check("敌对 Hound 双机获得 Boss 级生存、火力与完整 AI 频率", hound_boss_grade)
	var hound_roles_ok := hounds.size() == 2
	var hound_vengeance_ok := false
	if hound_roles_ok:
		hound_roles_ok = String(hounds[0].get_meta("ace_theme_state", "")) == "OVERWATCH" \
			and String(hounds[1].get_meta("ace_theme_state", "")) == "PURSUER"
		hounds[0].is_destroyed = true
		var hound_squads: Array = crucible.get("_squads")
		for squad_variant in hound_squads:
			var squad := squad_variant as AceSupportSquad
			if squad != null and squad.profile_id == "hound":
				squad.update_theme(0.6, false)
				break
		hound_vengeance_ok = String(hounds[1].get_meta("ace_theme_state", "")) == "VENGEANCE"
		hounds[0].is_destroyed = false
	_check("Hound 双机以远距监视/近身追杀协同背叛玩家", hound_roles_ok)
	_check("Hound 任一机被击毁后幸存者进入复仇强攻", hound_vengeance_ok)
	_check("The Crucible 全程最多三队同屏", max_active_entries <= 3,
		"max=%d" % max_active_entries)
	_check("The Crucible 所有已生成队均经过正式激活", all_active)
	var full_hud_entries: Array[Dictionary] = crucible.get_hud_entries()
	var first_hud_members: Array = full_hud_entries[0].get("members", []) \
		if not full_hud_entries.is_empty() else []
	var first_live_profile := String(full_hud_entries[0].get("id", "")) \
		if not full_hud_entries.is_empty() else ""
	var first_member: Aircraft = null
	for candidate in crucible_members:
		var candidate_ac := candidate as Aircraft
		if candidate_ac != null and not candidate_ac.is_destroyed \
				and String(candidate_ac.get_meta("crucible_profile", "")) == first_live_profile:
			first_member = candidate_ac
			break
	first_member.kill_tally = 3
	var kill_snapshot: Array[Dictionary] = crucible.get_hud_entries()
	var kill_members: Array = kill_snapshot[0].get("members", [])
	_check("熔炉中队条逐机暴露真实击坠数",
		not kill_members.is_empty() and int((kill_members[0] as Dictionary).get("kills", -1)) == 3)
	first_member.is_destroyed = true
	var death_snapshot: Array[Dictionary] = crucible.get_hud_entries()
	var death_members: Array = death_snapshot[0].get("members", [])
	_check("击毁成员立即从中队条移除且不占暗槽",
		death_members.size() == first_hud_members.size() - 1,
		"before=%d after=%d" % [first_hud_members.size(), death_members.size()])
	first_member.is_destroyed = false
	for candidate in crucible_members:
		var candidate_ac := candidate as Aircraft
		if candidate_ac != null \
				and String(candidate_ac.get_meta("crucible_profile", "")) == first_live_profile:
			candidate_ac.is_destroyed = true
	var squad_death_snapshot: Array[Dictionary] = crucible.get_hud_entries()
	_check("中队全灭后整条从顶部队列移除",
		squad_death_snapshot.size() == full_hud_entries.size() - 1
		and (squad_death_snapshot.is_empty()
			or String(squad_death_snapshot[0].get("id", "")) != first_live_profile))
	for candidate in crucible_members:
		var candidate_ac := candidate as Aircraft
		if candidate_ac != null \
				and String(candidate_ac.get_meta("crucible_profile", "")) == first_live_profile:
			candidate_ac.is_destroyed = false

	# 真实玩家主雷达必须把 FFA team 3+ 当敌人；旧 bug 会让目标可见但永远不进候选桶。
	var radar_target := first_member
	radar_target.global_position = mode.player_aircraft.global_position \
		+ Vector2(BOSS_SCRIPT.REENTRY_RADIUS_PX + 200.0, 0.0)
	crucible.update(BOSS_SCRIPT.RETARGET_INTERVAL_S)
	var reentry_ai := radar_target._get_ai_controller()
	_check("飞出主战圈的存活 Ace 会被强制拉回玩家附近",
		reentry_ai != null and reentry_ai._current_target == mode.player_aircraft)
	mode.player_aircraft.global_position = Vector2.ZERO
	mode.player_aircraft.heading = 0.0
	mode.player_aircraft.altitude = 5500.0
	radar_target.global_position = Vector2(0.0, -500.0)
	radar_target.altitude = 5500.0
	radar_target._lock_immunity_timer = 0.0
	radar_target.is_cloaked = false
	radar_target.sensor_hidden = false
	mode.player_aircraft.radar_targets.clear()
	mode._radar_lock_phase = 0
	mode._radar_lock_accum = 0.0
	mode._update_aircraft_list()
	for _radar_tick in range(16):
		mode._update_radar_locks(0.2)
	_check("玩家导弹雷达可锁定 The Crucible FFA Ace",
		float(mode.player_aircraft.radar_targets.get(radar_target, 0.0))
			>= mode.player_aircraft.params.lock_time,
		"progress=%.2f threshold=%.2f" % [
			float(mode.player_aircraft.radar_targets.get(radar_target, 0.0)),
			mode.player_aircraft.params.lock_time])
	_check("扩编 44 架全部获得队级主题状态", themed_new_members == 44,
		"themed=%d" % themed_new_members)
	_check("IDO 八节点共用两次防御并保持无人属性",
		ido_members == 8 and ido_all_networked, "members=%d" % ido_members)

	var docks_before: int = mode._dock_points.size()
	for airport_id in ZoneData.AIRFIELD_IDS:
		mode._liberate_airfield(airport_id)
		_check("%s 可独立解放" % airport_id,
			mode._zone_data.get_state(airport_id) == ZoneData.State.CLEARED)
	var new_airfield_docks := 0
	for dock_value in mode._dock_points:
		if dock_value != null and is_instance_valid(dock_value) \
				and String(dock_value.get("dock_kind")) == "airfield":
			new_airfield_docks += 1
	_check("三座机场各生成一个独立补给点",
		mode._dock_points.size() == docks_before + 3 and new_airfield_docks >= 3,
		"before=%d after=%d airfield=%d" % [docks_before,
			mode._dock_points.size(), new_airfield_docks])

	# 最终 Hound 也必须属于同一个全歼门；跨真实帧与下一次单位缓存刷新后保持终态。
	for member_variant in crucible_members:
		if is_instance_valid(member_variant) and member_variant is Aircraft:
			(member_variant as Aircraft).is_destroyed = true
	crucible.update(BOSS_SCRIPT.RETARGET_INTERVAL_S)
	await get_tree().process_frame
	mode._update_aircraft_list()
	_check("18 队 73 架全灭后才结束 The Crucible 且 HUD 清空",
		not crucible.active and crucible.get_hud_entries().is_empty())

	print("[DesertTheaterSmoke] result pass=%d fail=%d" % [_pass, _fail])
	Presentation.clear_all()
	mode.queue_free()
	for _frame in range(3):
		await get_tree().process_frame
	get_tree().quit(0 if _fail == 0 else 1)


func _check(label: String, condition: bool, detail: String = "") -> void:
	if condition:
		_pass += 1
		print("  ✓ %s %s" % [label, detail])
	else:
		_fail += 1
		print("  ✗ %s %s" % [label, detail])


func _crucible_hud_member_count(entries: Array[Dictionary]) -> int:
	var total := 0
	for entry in entries:
		var members: Array = entry.get("members", [])
		total += members.size()
	return total


func _profile_aircraft_total_through(profile_count: int) -> int:
	var total := 0
	for profile_index in range(mini(profile_count, BOSS_SCRIPT.PROFILE_ORDER.size())):
		var profile: Dictionary = AceSquadProfiles.get_profile(
			BOSS_SCRIPT.PROFILE_ORDER[profile_index])
		var elements: Array = profile.get("elements", [])
		if elements.is_empty():
			total += int(profile.get("squad_size", 0))
			continue
		for element in elements:
			total += int((element as Dictionary).get("count", 0))
	return total


func _distance_to_polyline(point: Vector2, polyline: PackedVector2Array) -> float:
	var best := INF
	for index in range(polyline.size() - 1):
		best = minf(best, point.distance_to(
			Geometry2D.get_closest_point_to_segment(point, polyline[index], polyline[index + 1])))
	return best


func _distance_to_buildings(point: Vector2, buildings: Array) -> float:
	var best := INF
	for building_any in buildings:
		if not building_any is Dictionary:
			continue
		var polygon := PackedVector2Array()
		for point_data in building_any.get("footprint", []):
			polygon.append(Vector2(float(point_data[0]), float(point_data[1])))
		if polygon.size() < 3:
			continue
		if Geometry2D.is_point_in_polygon(point, polygon):
			return 0.0
		polygon.append(polygon[0])
		best = minf(best, _distance_to_polyline(point, polygon))
	return best


func _point_clear_of_polygons(point: Vector2, polygons: Array) -> bool:
	for polygon_any in polygons:
		var polygon: PackedVector2Array = polygon_any
		if polygon.size() >= 3 and Geometry2D.is_point_in_polygon(point, polygon):
			return false
	return true
