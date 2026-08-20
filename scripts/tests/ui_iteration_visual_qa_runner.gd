extends Node

## 规范后旧 UI 全量翻修的 Visual QA：逐页走正式脚本并保存真实截图。

const HudPreferencesScript := preload("res://scripts/ui/hud_preferences.gd")
const MainMenuScript := preload("res://scripts/main_menu.gd")
const AudioSettingsPanelScript := preload("res://scripts/audio/audio_settings_panel.gd")
const HudColorSettingsPanelScript := preload("res://scripts/ui/hud_color_settings_panel.gd")
const PauseMenuScript := preload("res://scripts/survivor/pause_menu.gd")
const SurvivorHudScript := preload("res://scripts/survivor/survivor_hud.gd")

const PAGE_SCENES := [
	{"id": "map_select", "path": "res://scenes/survivor_map_select.tscn"},
	{"id": "aircraft_select", "path": "res://scenes/survivor_select.tscn"},
	{"id": "archive", "path": "res://scenes/archive.tscn"},
	{"id": "meta_shop", "path": "res://scenes/meta_shop.tscn"},
]

var _failures: Array[String] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	DisplayServer.window_set_size(Vector2i(1920, 1080))
	TranslationServer.set_locale("zh")
	HudPreferencesScript.reset_for_test()
	if not HudPreferencesScript.hud_color().is_equal_approx(HudPreferencesScript.PRESET_WHITE):
		_failures.append("新档默认 HUD 主色不是白色")
	for spec in PAGE_SCENES:
		await _capture_scene(String(spec["id"]), String(spec["path"]))
	await _capture_settings("audio_settings")
	await _capture_settings("hud_color_settings")
	await _capture_pause()
	await _capture_result("game_over", false)
	await _capture_result("victory", true)
	for failure in _failures:
		push_error("[ui_iteration_visual] %s" % failure)
	print("[ui_iteration_visual] captures=9 failures=%d" % _failures.size())
	get_tree().quit(0 if _failures.is_empty() else 1)


func _capture_scene(capture_id: String, scene_path: String) -> void:
	var packed := load(scene_path) as PackedScene
	if packed == null:
		_failures.append("%s 场景无法加载" % capture_id)
		return
	var page := packed.instantiate()
	add_child(page)
	await _settle()
	if page.find_child("TerminalPageShell", true, false) == null:
		_failures.append("%s 未使用共享终端页壳" % capture_id)
	await _save(capture_id)
	page.queue_free()
	await get_tree().process_frame


func _capture_settings(capture_id: String) -> void:
	var menu := MainMenuScript.new()
	add_child(menu)
	await _settle(3)
	var panel: CanvasLayer
	if capture_id == "audio_settings":
		panel = AudioSettingsPanelScript.new()
	else:
		panel = HudColorSettingsPanelScript.new()
	menu.add_child(panel)
	await get_tree().process_frame
	panel.call("open")
	await _settle(3)
	var expected_name := "TerminalAudioSettings" if capture_id == "audio_settings" \
		else "TerminalHudColorSettings"
	if panel.find_child(expected_name, true, false) == null:
		_failures.append("%s 未使用共享终端弹层" % capture_id)
	await _save(capture_id)
	menu.queue_free()
	await get_tree().process_frame


func _capture_pause() -> void:
	var background := ColorRect.new()
	background.color = Color("071017")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var pause := PauseMenuScript.new()
	add_child(pause)
	await get_tree().process_frame
	pause.open()
	await _settle(36)
	await _save("pause")
	Presentation.clear_all()
	pause.queue_free()
	background.queue_free()
	await get_tree().process_frame


func _capture_result(capture_id: String, victory: bool) -> void:
	var background := ColorRect.new()
	background.color = Color("071017")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var hud := SurvivorHudScript.new()
	add_child(hud)
	await _settle(3)
	if victory:
		hud.show_victory(18, 754.0, 143, 2860, 286, "WRAITH_SQUADRON")
	else:
		hud.show_game_over(11, 438.0, 67, 1340, 134)
	await _settle(40)
	var result_panel := hud.get("_game_over_panel") as Control
	if result_panel == null:
		_failures.append("%s 结算面板未创建" % capture_id)
	else:
		var rect := result_panel.get_global_rect()
		var viewport_size := Vector2(get_viewport().get_visible_rect().size)
		if rect.position.x < 0.0 or rect.position.y < 0.0 \
				or rect.end.x > viewport_size.x or rect.end.y > viewport_size.y:
			_failures.append("%s 结算面板越出视口：%s" % [capture_id, rect])
	await _save(capture_id)
	hud.queue_free()
	background.queue_free()
	await get_tree().process_frame


func _settle(frames: int = 6) -> void:
	for _frame in range(frames):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw


func _save(capture_id: String) -> void:
	var path := "res://bench/results/ui_iteration_%s.png" % capture_id
	var error := get_viewport().get_texture().get_image().save_png(path)
	if error != OK:
		_failures.append("%s 截图保存失败：%d" % [capture_id, error])
	print("[ui_iteration_visual] id=%s path=%s err=%d" % [capture_id, path, error])
