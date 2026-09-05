extends Node

## 仅供 bench Visual：走真实 Boss Debug 三段链路，采集 Boss 选择、T4 选机与战斗中 Tab build。

const BOSS_DEBUG_SCENE := preload("res://scenes/boss_debug_select.tscn")
const SURVIVOR_SELECT_SCENE := preload("res://scenes/survivor_select.tscn")
const SURVIVOR_MODE_SCENE := preload("res://scenes/survivor_mode.tscn")


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Visual bench 自身的路由 meta 不能漏进下方真实 SurvivorMode，否则会误走压力场。
	for meta_key in ["bench_mode", "bench_scenario", "bench_duration"]:
		if get_tree().has_meta(meta_key):
			get_tree().remove_meta(meta_key)
	DisplayServer.window_set_size(Vector2i(1920, 1080))
	TranslationServer.set_locale("zh")
	var screen := BOSS_DEBUG_SCENE.instantiate()
	add_child(screen)
	for _frame in range(4):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var boss_path := "res://bench/results/boss_debug_select_black_star.png"
	var boss_err := get_viewport().get_texture().get_image().save_png(boss_path)
	print("[boss_debug_select_visual] boss_path=%s err=%d" % [boss_path, boss_err])
	screen.queue_free()
	await get_tree().process_frame

	# 第二段：沿真实 meta 入口渲染七架 T4 参考机。
	get_tree().set_meta("boss_debug_mode", true)
	get_tree().set_meta("boss_debug_id", "WRAITH_SQUADRON")
	get_tree().set_meta("boss_debug_scenario", "full")
	get_tree().set_meta("survivor_map_id", "boss_debug")
	var selector := SURVIVOR_SELECT_SCENE.instantiate()
	add_child(selector)
	for _frame in range(4):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var select_path := "res://bench/results/boss_debug_t4_select.png"
	var select_err := get_viewport().get_texture().get_image().save_png(select_path)
	var select_ok: bool = selector._list.size() == BossDebugBuilds.reference_nodes().size()
	print("[boss_debug_select_visual] t4_path=%s err=%d cards=%d" % [
		select_path, select_err, selector._list.size()])
	selector.queue_free()
	await get_tree().process_frame

	# 第三段：直接进入真实 SurvivorMode，确认四机编队与随机武器都真实落地，并显示在 Tab。
	get_tree().set_meta("survivor_aircraft_resource", "res://resources/player/playable_f47.tres")
	get_tree().set_meta("boss_debug_node_id", "f47")
	get_tree().set_meta("boss_debug_level", 17)
	var mode := SURVIVOR_MODE_SCENE.instantiate()
	add_child(mode)
	# 用户契约：Boss Debug 参考态必须是至少四机，而不是单架 T4 样本。
	for _frame in range(2):
		await get_tree().process_frame
	var formation_size: int = mode._squad_members_alive().size()
	var formation_ok: bool = formation_size >= mode.BOSS_DEBUG_MIN_SQUAD_SIZE
	var weapons_mounted: bool = mode._boss_debug_weapons.size() == 2 \
		and mode._boss_debug_weapons.all(func(weapon_id: String) -> bool:
			return BossDebugBuilds.is_weapon_mounted(mode.player_aircraft.params, weapon_id))
	# 等真实到场演出完成后再开 Tab，避免用面板转场主动打断 Boss arrival。
	for _frame in range(478):
		await get_tree().process_frame
	var tab_ok: bool = mode._tactical_map != null \
		and mode._boss_debug_picks.size() == SurvivorData.axis_points_earnable(17) \
		and formation_ok and weapons_mounted
	if mode._tactical_map:
		mode._tactical_map.open()
	for _frame in range(12):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var tab_path := "res://bench/results/boss_debug_tab_build.png"
	var tab_err := get_viewport().get_texture().get_image().save_png(tab_path)
	print("[boss_debug_select_visual] tab_path=%s err=%d weapons=%s picks=%d squad=%d tactical=%s" % [
		tab_path, tab_err, str(mode._boss_debug_weapons), mode._boss_debug_picks.size(), formation_size,
		str(mode._tactical_map != null)])
	var base_ok: bool = boss_err == OK and select_err == OK and tab_err == OK and select_ok and tab_ok
	Presentation.clear_all()
	mode.queue_free()
	for _frame in range(3):
		await get_tree().process_frame

	# 第四段：海洋 FINAL WAR 真场景。先在生成完成帧核对编成，再让真实战斗跑 6 秒采图。
	get_tree().set_meta("boss_debug_mode", true)
	get_tree().set_meta("boss_debug_id", "BLACK_STAR")
	get_tree().set_meta("boss_debug_scenario", "final_war")
	get_tree().set_meta("survivor_map_id", "ocean_islands_preview")
	get_tree().set_meta("ugc_map_path", "res://resources/maps/ocean_islands_preview.aglmap")
	get_tree().set_meta("map_preview_only", false)
	get_tree().set_meta("survivor_aircraft_resource", "res://resources/player/playable_f47.tres")
	get_tree().set_meta("boss_debug_node_id", "f47")
	get_tree().set_meta("boss_debug_level", 17)
	var final_war := SURVIVOR_MODE_SCENE.instantiate()
	add_child(final_war)
	for _frame in range(3):
		await get_tree().process_frame
	var role_counts: Dictionary = {}
	var naval_on_water := true
	var vulnerable_roles := true
	for unit in final_war.get_children():
		if unit == null or not is_instance_valid(unit) or not unit.has_meta("final_war_role"):
			continue
		var role := String(unit.get_meta("final_war_role"))
		role_counts[role] = int(role_counts.get(role, 0)) + 1
		if unit is Aircraft and (unit as Aircraft).invulnerable:
			vulnerable_roles = false
		if unit is NavalUnit and MapGeography.is_on_land((unit as NavalUnit).global_position):
			naval_on_water = false
	var primary_node := EvolutionSystem.node_of(final_war._boss_debug_node_id)
	var final_war_ok: bool = final_war._map_id == "ocean_islands_preview" \
		and final_war._ugc_doc != null and final_war._map_features != null \
		and int(primary_node.get("tier", 0)) == 5 \
		and final_war._squad_members_alive().size() == 4 \
		and final_war._boss_debug_weapons.size() == 3 \
		and final_war._boss_debug_picks.size() == SurvivorData.AXIS_POINT_CAP \
		and int(role_counts.get("support_player", 0)) == 4 \
		and int(role_counts.get("ordinary_ally", 0)) == 4 \
		and int(role_counts.get("enemy_force", 0)) == 6 \
		and int(role_counts.get("ally_naval", 0)) == 2 \
		and int(role_counts.get("enemy_naval", 0)) == 2 \
		and naval_on_water and vulnerable_roles
	PerfBuckets.configure_runtime_panel(true)
	for _frame in range(360):
		await get_tree().process_frame
	var perf_stats := PerfBuckets.runtime_frame_stats()
	PerfBuckets.configure_runtime_panel(false)
	final_war_ok = final_war_ok and int(perf_stats.get("samples", 0)) == 120 \
		and int(perf_stats.get("below_60", 0)) == 0
	await RenderingServer.frame_post_draw
	var final_path := "res://bench/results/boss_debug_final_war_ocean.png"
	var final_err := get_viewport().get_texture().get_image().save_png(final_path)
	print("[boss_debug_select_visual] final_path=%s err=%d primary=%s level=%d weapons=%d picks=%d squad=%d roles=%s map=%s doc=%s features=%s water=%s vulnerable=%s perf=%s base=%s final=%s" % [
		final_path, final_err, final_war._boss_debug_node_id, final_war._boss_debug_level,
		final_war._boss_debug_weapons.size(), final_war._boss_debug_picks.size(),
		final_war._squad_members_alive().size(), str(role_counts), final_war._map_id,
		str(final_war._ugc_doc != null), str(final_war._map_features != null),
		str(naval_on_water), str(vulnerable_roles), str(perf_stats), str(base_ok), str(final_war_ok)])
	Presentation.clear_all()
	final_war.queue_free()
	for _frame in range(3):
		await get_tree().process_frame

	# 第五段：超级武器列车真实沙漠 Boss Debug，验收底图铁路、十四节超长编组与活动车钩。
	get_tree().set_meta("boss_debug_mode", true)
	get_tree().set_meta("boss_debug_id", "ARMORED_TRAIN")
	get_tree().set_meta("boss_debug_scenario", "full")
	get_tree().set_meta("survivor_map_id", "desert_railway_preview")
	get_tree().set_meta("ugc_map_path", "res://resources/maps/desert_railway_preview.aglmap")
	get_tree().set_meta("map_preview_only", false)
	get_tree().set_meta("survivor_aircraft_resource", "res://resources/player/playable_f47.tres")
	get_tree().set_meta("boss_debug_node_id", "f47")
	get_tree().set_meta("boss_debug_level", 17)
	var desert_train := SURVIVOR_MODE_SCENE.instantiate()
	add_child(desert_train)
	var arrival_state_ready := await _wait_for_train_arrival_state(desert_train, 5000)
	var train_encounter: BossEncounter = desert_train._spawner.get_boss()
	var train_members: Array = train_encounter.get_display_members() if train_encounter else []
	var train_manager: Variant = train_encounter._train if train_encounter is ArmoredTrainBoss else null
	await RenderingServer.frame_post_draw
	var arrival_path := "res://bench/results/boss_debug_armored_train_arrival.png"
	var arrival_err := get_viewport().get_texture().get_image().save_png(arrival_path)
	var arrival_ingress: bool = typeof(train_manager) == TYPE_OBJECT \
		and train_manager != null and is_instance_valid(train_manager) \
		and bool(train_manager.arrival_ingress_active)
	var safe_view := get_viewport().get_visible_rect().grow(-180.0)
	var canvas_transform := get_viewport().get_canvas_transform()
	var all_train_in_frame := train_members.size() == 14
	var train_screen_bounds := Rect2()
	for member in train_members:
		var member_screen: Vector2 = canvas_transform * member.global_position
		if train_screen_bounds.size == Vector2.ZERO:
			train_screen_bounds = Rect2(member_screen, Vector2.ONE)
		else:
			train_screen_bounds = train_screen_bounds.expand(member_screen)
		all_train_in_frame = all_train_in_frame \
			and safe_view.has_point(member_screen)
	var arrival_follow_ok: bool = arrival_state_ready and train_members.size() > 6 \
		and desert_train._camera_ctrl.cine_target == train_members[6] \
		and is_equal_approx(desert_train._camera_ctrl.target_zoom, 0.26) \
		and arrival_ingress and all_train_in_frame
	print("[boss_debug_select_visual] train_arrival_path=%s err=%d state_ready=%s follow_center=%s all_in_frame=%s zoom=%.2f ingress=%s screen_center=%s actor6=%s bounds=%s" % [
		arrival_path, arrival_err, str(arrival_state_ready),
		str(arrival_follow_ok), str(all_train_in_frame),
		desert_train._camera_ctrl.target_zoom,
		str(arrival_ingress), str(desert_train.camera.get_screen_center_position()),
		str(train_members[6].global_position if train_members.size() > 6 else Vector2.INF),
		str(train_screen_bounds)])
	var train_ok: bool = desert_train._map_id == "desert_railway_preview" \
		and desert_train._ugc_doc != null and desert_train._map_features != null \
		and train_encounter != null and train_encounter.boss_id == "ARMORED_TRAIN" \
		and train_encounter.active and train_members.size() == 14 \
		and typeof(train_manager) == TYPE_OBJECT and train_manager != null \
		and is_instance_valid(train_manager) and float(train_manager.route_progress) > 0.0 \
		and arrival_err == OK and arrival_follow_ok
	if typeof(train_manager) == TYPE_OBJECT and train_manager != null \
			and is_instance_valid(train_manager) and not train_members.is_empty():
		# Visual 定位到铁路中段弯道；十四节的前后转向架仍全部压在正式底图铁路上。
		train_manager._traveled_px = train_manager._route_length_px * 0.45
		train_manager._update_movement(0.0)
		Presentation.clear_all()
		desert_train._camera_ctrl.set_follow_target(train_members[-1])
		desert_train._camera_ctrl.snap_to_follow()
		desert_train.camera.global_position = train_members[-1].global_position
		desert_train._camera_ctrl.target_zoom = 0.48
		desert_train._camera_ctrl._base_zoom = 0.48
		desert_train.camera.zoom = Vector2(0.48, 0.48)
	PerfBuckets.configure_runtime_panel(true)
	for _frame in range(240):
		await get_tree().process_frame
	var train_perf := PerfBuckets.runtime_frame_stats()
	PerfBuckets.configure_runtime_panel(false)
	train_ok = train_ok and int(train_perf.get("samples", 0)) == 120 \
		and int(train_perf.get("below_60", 0)) == 0
	await RenderingServer.frame_post_draw
	var train_path := "res://bench/results/boss_debug_armored_train_desert.png"
	var train_err := get_viewport().get_texture().get_image().save_png(train_path)
	print("[boss_debug_select_visual] train_path=%s err=%d map=%s members=%d active=%s progress=%.3f train_pos=%s camera_pos=%s visible=%s perf=%s" % [
		train_path, train_err, desert_train._map_id, train_members.size(),
		str(train_encounter.active if train_encounter else false),
		float(train_manager.route_progress) if typeof(train_manager) == TYPE_OBJECT \
			and train_manager != null and is_instance_valid(train_manager) else -1.0,
		str(train_members[-1].global_position) if not train_members.is_empty() else "none",
		str(desert_train.camera.global_position),
		str(train_members[0].visible) if not train_members.is_empty() else "none",
		str(train_perf)])
	Presentation.clear_all()
	desert_train.queue_free()
	for _frame in range(3):
		await get_tree().process_frame

	# 第六段：独立陆地航母。验收连续履带陆战平台与真实停机/起飞，明确不复用列车编组。
	get_tree().set_meta("boss_debug_mode", true)
	get_tree().set_meta("boss_debug_id", "LAND_CARRIER")
	get_tree().set_meta("boss_debug_scenario", "full")
	get_tree().set_meta("survivor_map_id", "desert_railway_preview")
	get_tree().set_meta("ugc_map_path", "res://resources/maps/desert_railway_preview.aglmap")
	get_tree().set_meta("map_preview_only", false)
	get_tree().set_meta("survivor_aircraft_resource", "res://resources/player/playable_f47.tres")
	get_tree().set_meta("boss_debug_node_id", "f47")
	get_tree().set_meta("boss_debug_level", 17)
	var desert_carrier := SURVIVOR_MODE_SCENE.instantiate()
	add_child(desert_carrier)
	for _frame in range(420):
		await get_tree().process_frame
	var carrier_encounter: BossEncounter = desert_carrier._spawner.get_boss()
	var carrier_members: Array = carrier_encounter.get_display_members() if carrier_encounter else []
	var carrier_ok: bool = desert_carrier._map_id == "desert_railway_preview" \
		and desert_carrier._ugc_doc != null and desert_carrier._map_features != null \
		and carrier_encounter != null and carrier_encounter.boss_id == "LAND_CARRIER" \
		and carrier_encounter.active and carrier_members.size() == 1 \
		and is_instance_valid(carrier_members[0]) \
		and carrier_members[0].parked_aircraft_count() == 2 # 接战后首波两架已真实起飞
	if not carrier_members.is_empty() and is_instance_valid(carrier_members[0]):
		Presentation.clear_all()
		desert_carrier._camera_ctrl.set_follow_target(carrier_members[0])
		desert_carrier._camera_ctrl.snap_to_follow()
		desert_carrier.camera.global_position = carrier_members[0].global_position
		desert_carrier._camera_ctrl.target_zoom = 0.72
		desert_carrier._camera_ctrl._base_zoom = 0.72
		desert_carrier.camera.zoom = Vector2(0.72, 0.72)
	for _frame in range(4):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var carrier_path := "res://bench/results/boss_debug_land_carrier_desert.png"
	var carrier_err := get_viewport().get_texture().get_image().save_png(carrier_path)
	print("[boss_debug_select_visual] land_carrier_path=%s err=%d map=%s members=%d active=%s parked=%d pos=%s camera_pos=%s visible=%s" % [
		carrier_path, carrier_err, desert_carrier._map_id, carrier_members.size(),
		str(carrier_encounter.active if carrier_encounter else false),
		carrier_members[0].parked_aircraft_count() if not carrier_members.is_empty() else -1,
		str(carrier_members[0].global_position) if not carrier_members.is_empty() else "none",
		str(desert_carrier.camera.global_position),
		str(carrier_members[0].visible) if not carrier_members.is_empty() else "none"])
	Presentation.clear_all()
	desert_carrier.queue_free()
	for _frame in range(3):
		await get_tree().process_frame
	get_tree().quit(0 if base_ok and final_war_ok and final_err == OK \
		and train_ok and train_err == OK and carrier_ok and carrier_err == OK else 1)


func _wait_for_train_arrival_state(mode: Variant, timeout_ms: int) -> bool:
	var deadline := Time.get_ticks_msec() + maxi(timeout_ms, 1)
	while Time.get_ticks_msec() < deadline:
		if typeof(mode) != TYPE_OBJECT or mode == null or not is_instance_valid(mode):
			return false
		var spawner_raw: Variant = mode.get("_spawner")
		if typeof(spawner_raw) != TYPE_OBJECT or spawner_raw == null \
				or not is_instance_valid(spawner_raw):
			await get_tree().process_frame
			continue
		var encounter: BossEncounter = spawner_raw.get_boss()
		var members: Array = encounter.get_display_members() if encounter else []
		var manager: Variant = encounter._train if encounter is ArmoredTrainBoss else null
		var safe_view := get_viewport().get_visible_rect().grow(-180.0)
		var canvas_transform := get_viewport().get_canvas_transform()
		var all_in_frame := members.size() == 14
		for member in members:
			all_in_frame = all_in_frame and safe_view.has_point(
				canvas_transform * member.global_position)
		if members.size() > 6 and typeof(manager) == TYPE_OBJECT and manager != null \
				and is_instance_valid(manager) and bool(manager.arrival_ingress_active) \
				and mode._camera_ctrl.cine_target == members[6] \
				and is_equal_approx(mode._camera_ctrl.target_zoom, 0.26) \
				and is_equal_approx(mode.camera.zoom.x, 0.26) and all_in_frame:
			return true
		await get_tree().process_frame
	return false
