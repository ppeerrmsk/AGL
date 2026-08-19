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
	var ok: bool = boss_err == OK and select_err == OK and tab_err == OK and select_ok and tab_ok
	Presentation.clear_all()
	mode.queue_free()
	for _frame in range(3):
		await get_tree().process_frame
	get_tree().quit(0 if ok else 1)
