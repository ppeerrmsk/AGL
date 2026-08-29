extends Node2D

## 真实 Godot 渲染验收：同一 1920×1080 画布采集基础三轴卡、机体适配第四卡、词条浮层与确认插槽动画。

const MilestoneAxisCounterScript := preload("res://scripts/survivor/milestone_axis_counter.gd")
const BottomExperiencePanelScript := preload("res://scripts/survivor/bottom_experience_panel.gd")
const SurvivorHUDScript := preload("res://scripts/survivor/survivor_hud.gd")
const OUTPUT_THREE := "res://bench/results/upgrade_media_cards_3.png"
const OUTPUT_FOUR := "res://bench/results/upgrade_media_cards_4_airframe.png"
const OUTPUT_BOOT := "res://bench/results/upgrade_media_boot_scan.png"
const OUTPUT_THREE_HOVER := "res://bench/results/upgrade_media_cards_3_hover.png"
const OUTPUT_INSERT := "res://bench/results/upgrade_media_card_insert.png"


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	DisplayServer.window_set_size(Vector2i(1920, 1080))
	TranslationServer.set_locale("zh")
	_build_progression_target()
	var ui := SurvivorUpgradeUI.new()
	add_child(ui)

	var three: Array[Dictionary] = [
		SurvivorData.upgrade_by_id("hp_up"),
		SurvivorData.upgrade_by_id("cloud_overload"),
		SurvivorData.upgrade_by_id("flare_shield"),
	]
	var selection_ceiling_ok := three.all(func(choice: Dictionary) -> bool:
		return SurvivorData.get_rarity(choice) <= SurvivorData.Rarity.CLASSIFIED)
	ui.show_choices(three)
	await _settle()
	var entrance_lock_ok := ui._input_locked and ui._buttons[0].disabled and ui._buttons[2].disabled
	var errors: Array[int] = [await _capture(OUTPUT_THREE)]
	var airframe_bonus := SurvivorData.upgrade_by_id("speed_up").duplicate(true)
	airframe_bonus["airframe_bonus_offer"] = true
	airframe_bonus["airframe_bonus_axis"] = "knight"
	var four: Array[Dictionary] = three.duplicate()
	four.append(airframe_bonus)
	ui.show_choices(four)
	await _settle()
	var fourth_layout_ok := ui._buttons[3].visible and ui._source_badges[3].visible \
		and ui.get_transition_elements().size() == 5
	errors.append(await _capture(OUTPUT_FOUR))
	ui.show_choices(three)
	await _settle()

	ui._play_media_boot(0)
	await _settle(4)
	errors.append(await _capture(OUTPUT_BOOT))

	await get_tree().create_timer(
		SurvivorUpgradeUI.INPUT_UNLOCK_DELAY_S + 0.10, true, false, true).timeout
	await _settle(2)
	var unlock_ok := not ui._input_locked and not ui._buttons[0].disabled
	ui._set_card_hovered(1, true)
	await _settle(12)
	var note_popup_ok := _note_popup_clear_of_cards(ui, 1)
	errors.append(await _capture(OUTPUT_THREE_HOVER))
	ui._set_card_hovered(1, false)

	ui.upgrade_selected.connect(func(_upgrade: Dictionary) -> void:
		ui.set_meta("visual_selection_emitted", true))
	var insert_start_x := ui._media_roots[1].get_global_rect().get_center().x
	ui._on_choice_pressed(1)
	await get_tree().create_timer(
		SurvivorUpgradeUI.CONFIRM_INSERT_DURATION_S * 0.55, true, false, true).timeout
	await get_tree().process_frame
	var insert_media: Control = ui._media_roots[1]
	var direct_insert_ok := is_equal_approx(insert_media.modulate.a, 1.0) \
		and absf(insert_media.get_global_rect().get_center().x - insert_start_x) < 1.0 \
		and insert_media.scale.y < insert_media.scale.x
	errors.append(await _capture(OUTPUT_INSERT))
	await get_tree().create_timer(
		SurvivorUpgradeUI.CONFIRM_INSERT_DURATION_S * 0.55, true, false, true).timeout
	await _settle(2)

	var ok := selection_ceiling_ok and entrance_lock_ok and fourth_layout_ok \
		and unlock_ok and note_popup_ok and direct_insert_ok \
		and bool(ui.get_meta("visual_selection_emitted", false))
	print("[upgrade_media_visual] checks ceiling=%s entrance=%s fourth=%s unlock=%s note=%s direct=%s emitted=%s" % [
		str(selection_ceiling_ok), str(entrance_lock_ok), str(fourth_layout_ok), str(unlock_ok), str(note_popup_ok), str(direct_insert_ok),
		str(bool(ui.get_meta("visual_selection_emitted", false)))])
	for error in errors:
		ok = ok and error == OK
	print("[upgrade_media_visual] outputs=%s ok=%s" % [str([
		OUTPUT_THREE, OUTPUT_FOUR, OUTPUT_BOOT, OUTPUT_THREE_HOVER, OUTPUT_INSERT]), str(ok)])
	get_tree().quit(0 if ok else 1)


func _build_progression_target() -> void:
	var viewport_size := Vector2(1920, 1080)
	var bottom_bar_rect: Rect2 = SurvivorHUDScript.bottom_bar_rect(viewport_size)
	var bottom_bar := ColorRect.new()
	bottom_bar.color = ThemeColors.UI_BLOCK_BACKGROUND
	bottom_bar.position = bottom_bar_rect.position
	bottom_bar.size = bottom_bar_rect.size
	add_child(bottom_bar)

	var progression_player := SurvivorPlayer.new()
	progression_player.level = 7
	progression_player.xp = 84
	progression_player.xp_to_next = 160
	progression_player.axis_points[SurvivorData.AXIS_GLADIATOR] = 3
	progression_player.axis_points[SurvivorData.AXIS_KNIGHT] = 2
	progression_player.axis_points[SurvivorData.AXIS_SCHEMER] = 1
	var experience_panel = BottomExperiencePanelScript.new()
	experience_panel.position = SurvivorHUDScript.bottom_progress_rect(viewport_size).position
	add_child(experience_panel)
	experience_panel.update_display(progression_player, true)
	var axis_counter = MilestoneAxisCounterScript.new()
	axis_counter.position = SurvivorHUDScript.bottom_axis_rect(viewport_size).position
	add_child(axis_counter)
	axis_counter.update_display(progression_player)
	progression_player.free()


func _settle(frames: int = 5) -> void:
	for _frame in range(frames):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw


func _note_popup_clear_of_cards(ui: SurvivorUpgradeUI, note_index: int) -> bool:
	if not ui._note_panels[note_index].visible:
		return false
	var popup_rect: Rect2 = ui._note_panels[note_index].get_global_rect()
	for button in ui._buttons:
		if button.visible and popup_rect.intersects(button.get_global_rect()):
			return false
	return true


func _capture(path: String) -> int:
	await RenderingServer.frame_post_draw
	return get_viewport().get_texture().get_image().save_png(path)


func _draw() -> void:
	# 静态 Y2K 机舱底板；仅测试场景构建一次，不进入正式 UI。
	draw_rect(Rect2(0, 0, 1920, 1080), Color("02030a"), true)
	for x in range(0, 1921, 40):
		draw_line(Vector2(x, 0), Vector2(x, 1080), Color(0.08, 0.30, 0.36, 0.12), 1.0)
	for y in range(0, 1081, 40):
		draw_line(Vector2(0, y), Vector2(1920, y), Color(0.08, 0.30, 0.36, 0.12), 1.0)
	draw_rect(Rect2(92, 72, 1736, 936), Color(0.20, 0.86, 0.96, 0.18), false, 1.0)
	draw_rect(Rect2(116, 96, 1688, 888), Color(0.96, 0.24, 0.50, 0.10), false, 1.0)
