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
	get_tree().quit(0 if base_ok and final_war_ok and final_err == OK else 1)
