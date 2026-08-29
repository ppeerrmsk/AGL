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
	# 选机视觉样本只在内存中临时解锁四架 T0，确保截图和结构断言覆盖开局礼包文案；
	# 不调用 debug_grant（会写用户存档），页面释放后恢复原账本。
	var owned_snapshot: Dictionary = {}
	if capture_id == "aircraft_select":
		owned_snapshot = (MetaShop.get("_owned") as Dictionary).duplicate(true)
		var preview_owned := owned_snapshot.duplicate(true)
		for item_id in [MetaShop.ITEM_MIG21F13, MetaShop.ITEM_F104C,
				MetaShop.ITEM_J35F, MetaShop.ITEM_EA6B]:
			preview_owned[item_id] = true
		MetaShop.set("_owned", preview_owned)
	var page := packed.instantiate()
	add_child(page)
	await _settle()
	if page.find_child("TerminalPageShell", true, false) == null:
		_failures.append("%s 未使用共享终端页壳" % capture_id)
	if capture_id == "aircraft_select":
		var cards := page.get("_cards_container") as GridContainer
		if cards == null or cards.get_child_count() != 8:
			_failures.append("aircraft_select 未渲染八张正常局机型卡")
		elif cards.columns != 3:
			_failures.append("aircraft_select 全息窗旁不是三列卡片布局")
		else:
			var scroll := cards.get_parent() as ScrollContainer
			if scroll == null or scroll.get_h_scroll_bar().visible:
				_failures.append("aircraft_select 三列内容触发了横向滚动")
			if scroll == null or not scroll.get_v_scroll_bar().visible:
				_failures.append("aircraft_select 八卡没有可用的纵向滚动")
		var preview := page.get("_hologram_preview") as Control
		if preview == null:
			_failures.append("aircraft_select 缺少正式全息机体预览")
		elif not bool(preview.call("has_model_texture")):
			_failures.append("aircraft_select 默认已解锁机没有加载真实轮廓")
		elif String(preview.call("displayed_airframe")).is_empty():
			_failures.append("aircraft_select 全息机体预览没有机型名")
		if cards != null and preview != null:
			var rendered_list: Array = page.get("_list")
			var benefit_count := 0
			for i in range(rendered_list.size()):
				var entry: Dictionary = rendered_list[i]
				var benefit_label := (cards.get_child(i) as PanelContainer).find_child(
					"StartingBenefit", true, false) as Label
				var expects_benefit: bool = String(entry.get("id", "")) in [
					"mig21f13", "f104c", "j35f", "ea6b"]
				if benefit_label != null:
					benefit_count += 1
				if expects_benefit != (benefit_label != null):
					_failures.append("aircraft_select 起手机礼包行与档案不一致: %s" %
						String(entry.get("id", "")))
				elif benefit_label != null and benefit_label.text.strip_edges().is_empty():
					_failures.append("aircraft_select 起手机礼包文案为空: %s" %
						String(entry.get("id", "")))
			if benefit_count != 4:
				_failures.append("aircraft_select 没有恰好显示四条 T0 开局礼包")
			# 锁定卡泄露只需抽查第一张；与上面的八卡礼包计数分开，避免提前 break。
			for i in range(rendered_list.size()):
				var entry: Dictionary = rendered_list[i]
				if not entry.get("locked", false) and not entry.get("dev_locked", false):
					continue
				(cards.get_child(i) as PanelContainer).mouse_entered.emit()
				if bool(preview.call("has_model_texture")):
					_failures.append("aircraft_select 锁定卡悬停泄露了机体轮廓")
				break
			# 测试直接喂档案，不改变正式锁定门；守 EA-6B 在全息窗能解析同一张生产 PNG。
			var ea6b_profile := load(
				"res://resources/player/playable_ea6b.tres") as PlayableAircraft
			preview.call("show_profile", ea6b_profile, 7, rendered_list.size())
			if not bool(preview.call("has_model_texture")):
				_failures.append("aircraft_select EA-6B 全息窗没有解析正式轮廓")
			page.call("_show_initial_preview")
			# 最终证据图停在第二排，让四架 T0 的开局礼包文案直接可见。
			var benefit_scroll := cards.get_parent() as ScrollContainer
			if benefit_scroll != null:
				benefit_scroll.scroll_vertical = int(benefit_scroll.get_v_scroll_bar().max_value)
				await _settle(3)
	await _save(capture_id)
	page.queue_free()
	await get_tree().process_frame
	if capture_id == "aircraft_select":
		MetaShop.set("_owned", owned_snapshot)


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
