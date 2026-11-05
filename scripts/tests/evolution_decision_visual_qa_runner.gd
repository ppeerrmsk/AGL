extends Node2D

const ModelPreview := preload("res://scripts/survivor/aircraft_model_preview.gd")

## 中英日、桌面/小窗口：真实鼠标悬停、未知机保密、选择保留、浮窗边界与关闭清理。
var _failures := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	AircraftCodex._loaded = true
	AircraftCodex._discovered.clear()
	var ui := EvolutionUI.new()
	add_child(ui)
	await _settle(2)
	var current := EvolutionSystem.node_of(&"f16")
	var exits := EvolutionSystem.exits_of(&"f16")
	var signature := SurvivorData.signature_upgrade_for_aircraft(&"f16")
	var points := {&"gladiator": 8, &"knight": 8, &"schemer": 8}
	var history := [&"mig21f13", &"mig23", &"f16"]
	for resolution in [Vector2i(1920, 1080), Vector2i(1280, 720)]:
		get_window().content_scale_size = resolution
		DisplayServer.window_set_size(resolution)
		await _settle(4)
		for locale in ["zh", "en", "ja"]:
			TranslationServer.set_locale(locale)
			for state in ["evolution", "repair", "locked", "full"]:
				var evolution: bool = state == "evolution"
				ui.show_offer(current, exits, 26 if evolution else 1, signature,
					state != "locked", false, history, points, {}, state != "locked", state != "full")
				ui.visible = true
				await _settle(8)
				if evolution:
					await _move_to_node(ui, &"f35")
					_check(ui._popover.visible and ui._detail.shown_node == &"f35"
						and ui._evo_selected == &"", "real hover opens detail without selecting")
					var click := InputEventMouseButton.new()
					click.position = _node_center(ui, &"f35")
					click.button_index = MOUSE_BUTTON_LEFT
					click.pressed = true
					get_viewport().push_input(click)
					click = click.duplicate()
					click.pressed = false
					get_viewport().push_input(click)
					await _settle(2)
					_check(ui._evo_selected == &"f35", "real click selects eligible aircraft")
					_check(_popover_ok(ui), "hover popover stays inside viewport")
					_check(ui._tree._models[&"f35"].has_model()
						and (ui._detail.get_node("AircraftModel") as ModelPreview).model_key == "f35",
						"tree and hover show the selected aircraft model")
					await _capture("res://bench/results/evolution_hover_%s_%d.png" % [locale, resolution.x])
					var leave := InputEventMouseMotion.new()
					leave.position = Vector2(80, 80)
					get_viewport().push_input(leave)
					await get_tree().create_timer(0.25, true, false, true).timeout
					_check(not ui._popover.visible, "leaving closes hover information")
					await _move_to_node(ui, &"f16")
					_check(ui._evo_selected == &"f35" and ui._detail.shown_node == &"f16",
						"hovering current airframe preserves selection")
					await _move_to_node(ui, &"x44")
					await get_tree().create_timer(0.25, true, false, true).timeout
					_check(not ui._popover.visible, "unknown aircraft has no information leak")
					_check(not ui._tree._models.has(&"x44"), "unknown aircraft has no model leak")
					ui._focus_current()
					await _settle(3)
					_check(_focused_models_ok(ui), "current and direct candidates fit vertically")
				_check(_layout_ok(ui), "%s %s %s layout" % [locale, resolution, state])
				_check(ui._tree.interactive and ui._evolution_ready == evolution
					and ui._wingman_confirm.disabled == (state in ["locked", "full"]),
					"binary decision state")
				await _capture("res://bench/results/evolution_decision_%s_%s_%d.png" % [locale, state, resolution.x])
				# 四边位置检查走同一个浮窗入口，包含很长的专属说明。
				for corner in [Vector2(0, 0), Vector2(resolution.x - 10, 0),
					Vector2(0, resolution.y - 10), Vector2(resolution.x - 10, resolution.y - 10)]:
					ui._on_tree_node_hovered(&"f35", Rect2(corner, Vector2(10, 10)))
					await _settle(2)
					_check(_popover_ok(ui), "popover edge clamp")
				ui.visible = false
				_check(not ui._popover.visible and ui._hover_node == &"", "closing clears popover")
	await _capture_model_gallery()
	print("[evolution_decision_visual] failures=%d" % _failures)
	AudioManager.request_quit(0 if _failures == 0 else 1)


## 全树逐机陈列，检查缺 PNG 的已有模型不会变成空白或同一架通用图标。
func _capture_model_gallery() -> void:
	get_window().content_scale_size = Vector2i(1920, 1080)
	DisplayServer.window_set_size(Vector2i(1920, 1080))
	TranslationServer.set_locale("zh")
	var gallery := Control.new()
	add_child(gallery)
	var index := 0
	for nd in EvolutionSystem.all_nodes():
		var position := Vector2(20 + (index % 10) * 188, 20 + floori(index / 10.0) * 204)
		var model := ModelPreview.new()
		model.position = position + Vector2(18, 0)
		model.size = Vector2(152, 162)
		model.modulate = HudPreferences.hud_color()
		model.show_profile(AircraftDB.get_profile(StringName(nd.get("profile", ""))))
		gallery.add_child(model)
		_check(model.has_model(), "gallery model " + String(nd.get("id", "")))
		var label := TerminalText.new()
		label.position = position + Vector2(0, 162)
		label.size = Vector2(188, 36)
		label.layout_text = "MMMMMMMMMMMM"
		label.font_face = TerminalText.FontFace.CHAKRA_PETCH_MEDIUM
		label.font_color = HudPreferences.hud_color()
		label.text = tr(String(nd.get("name_key", "")))
		gallery.add_child(label)
		index += 1
	await _settle(3)
	await _capture("res://bench/results/evolution_models_zh_1920.png")
	gallery.queue_free()
	await get_tree().process_frame


func _move_to_node(ui: EvolutionUI, id: StringName) -> void:
	ui._hide_popover()
	ui._tree.clear_hover()
	var rect: Rect2 = ui._tree._rects[id]
	ui._tree_scroll.scroll_horizontal = maxi(0, int(rect.get_center().x - ui._tree_scroll.size.x * 0.5))
	ui._tree_scroll.scroll_vertical = maxi(0, int(rect.get_center().y - ui._tree_scroll.size.y * 0.5))
	await _settle(4)
	var motion := InputEventMouseMotion.new()
	motion.position = _node_center(ui, id)
	get_viewport().push_input(motion)
	await _settle(3)


func _node_center(ui: EvolutionUI, id: StringName) -> Vector2:
	return ui._tree.global_position + (ui._tree._rects[id] as Rect2).get_center()


func _layout_ok(ui: EvolutionUI) -> bool:
	var viewport_rect := get_viewport_rect()
	var panel_rect := ui._panel.get_global_rect()
	return viewport_rect.encloses(panel_rect) and ui._evo_pane.size.x >= 320.0 \
		and ui._decision_pane.size.x >= EvolutionUI.DECISION_WIDTH \
		and panel_rect.encloses(ui._wingman_confirm.get_global_rect()) \
		and (ui._evo_confirm == null or panel_rect.encloses(ui._evo_confirm.get_global_rect())) \
		and (ui._repair_confirm == null or panel_rect.encloses(ui._repair_confirm.get_global_rect())) \
		and panel_rect.encloses(ui._tree_scroll.get_global_rect()) \
		and not ui._subtitle.text.contains("EVO_STATION_CONTEXT") \
		and not ui._wingman_confirm.text.contains("EVO_CONFIRM") \
		and not ui._tree._is_revealed(&"x44") and not ui._tree._rects.has(&"f15")


func _focused_models_ok(ui: EvolutionUI) -> bool:
	var scroll_rect := ui._tree_scroll.get_global_rect()
	var available_bottom := scroll_rect.end.y - ui._tree_scroll.get_h_scroll_bar().size.y
	for id in [&"f16", &"f35"]:
		var rect: Rect2 = ui._tree._rects[id]
		rect.position += ui._tree.global_position
		if rect.position.y < scroll_rect.position.y or rect.end.y > available_bottom:
			return false
	return true


func _popover_ok(ui: EvolutionUI) -> bool:
	return ui._popover.visible and get_viewport_rect().encloses(ui._popover.get_global_rect()) \
		and ui._detail.size.x <= ui._popover_scroll.size.x


func _settle(frames: int = 5) -> void:
	for _frame in range(frames):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw


func _capture(path: String) -> void:
	await RenderingServer.frame_post_draw
	_check(get_viewport().get_texture().get_image().save_png(path) == OK, "capture " + path)


func _check(ok: bool, label: String) -> void:
	if not ok:
		_failures += 1
		print("[evolution_decision_visual] FAIL " + label)


func _draw() -> void:
	draw_rect(Rect2(0, 0, 1920, 1080), Color("090c0d"), true)
