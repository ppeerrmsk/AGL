extends Node2D

## 1920×1080 真实渲染验收：机场留机专属技能 / 进化二选一决策台。

const OUTPUT_READY := "res://bench/results/evolution_decision_ready.png"
const OUTPUT_LOCKED := "res://bench/results/evolution_decision_license_locked.png"


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	DisplayServer.window_set_size(Vector2i(1920, 1080))
	TranslationServer.set_locale("zh")
	# 固定为空图鉴：可达远端必须以“？？？”留在树上，不能被误当成不可达路线裁掉。
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
	ui.show_offer(current, exits, 26, signature, true, false, history, points)
	ui.visible = true
	await _settle(8)
	var ready_ok := _layout_ok(ui) and not ui._signature_confirm.disabled \
		and not ui._done_button.disabled \
		and ui._done_button.text == tr("SETTLEMENT_RETAIN_CONFIRM") \
		and ui._tree.interactive and _tree_scope_ok(ui)
	var ready_error := await _capture(OUTPUT_READY)

	ui.show_offer(current, exits, 26, signature, false, false, history, points)
	await _settle(8)
	var locked_ok := _layout_ok(ui) and ui._signature_confirm.disabled \
		and not ui._done_button.disabled and ui._tree.interactive and _tree_scope_ok(ui)
	var locked_error := await _capture(OUTPUT_LOCKED)

	var ok := ready_ok and locked_ok and ready_error == OK and locked_error == OK
	print("[evolution_decision_visual] ready=%s locked=%s outputs=%s ok=%s" % [
		str(ready_ok), str(locked_ok), str([OUTPUT_READY, OUTPUT_LOCKED]), str(ok)])
	get_tree().quit(0 if ok else 1)


func _layout_ok(ui: EvolutionUI) -> bool:
	var viewport_rect := Rect2(Vector2.ZERO, Vector2(1920, 1080))
	var panel_rect := ui._panel.get_global_rect()
	return viewport_rect.encloses(panel_rect) \
		and panel_rect.size.x > 1800.0 and panel_rect.size.y > 1000.0 \
		and ui._evo_pane.size.x >= 500.0 \
		and ui._detail_pane.size.x >= EvolutionUI.DETAIL_WIDTH \
		and ui._decision_pane.size.x >= EvolutionUI.DECISION_WIDTH \
		and ui._subtitle != null \
		and not ui._subtitle.text.contains("EVOLUTION_SUBTITLE_FMT") \
		and not ui._signature_confirm.text.contains("SETTLEMENT_") \
		and not ui._done_button.text.contains("SETTLEMENT_")


func _tree_scope_ok(ui: EvolutionUI) -> bool:
	return ui._tree._rects.has(&"mig21f13") \
		and ui._tree._rects.has(&"mig23") \
		and ui._tree._rects.has(&"f16") \
		and ui._tree._rects.has(&"x44") \
		and not ui._tree._is_revealed(&"x44") \
		and not ui._tree._rects.has(&"f15") \
		and not ui._tree._rects.has(&"f14")


func _settle(frames: int = 5) -> void:
	for _frame in range(frames):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw


func _capture(path: String) -> int:
	await RenderingServer.frame_post_draw
	return get_viewport().get_texture().get_image().save_png(path)


func _draw() -> void:
	draw_rect(Rect2(0, 0, 1920, 1080), Color("02030a"), true)
	for x in range(0, 1921, 40):
		draw_line(Vector2(x, 0), Vector2(x, 1080), Color(0.08, 0.30, 0.36, 0.12), 1.0)
	for y in range(0, 1081, 40):
		draw_line(Vector2(0, y), Vector2(1920, y), Color(0.08, 0.30, 0.36, 0.12), 1.0)
