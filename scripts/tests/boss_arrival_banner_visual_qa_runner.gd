extends Node2D

## 仅供 bench Visual：固定采集 Mother Goose 逐窗节拍，以及各 BOSS 的身份/palette 终态。

const BossArrivalBannerScript := preload("res://scripts/ui/boss_arrival_banner.gd")


func _ready() -> void:
	DisplayServer.window_set_size(Vector2i(1920, 1080))
	TranslationServer.set_locale("en")
	_build_backdrop()

	var banner = BossArrivalBannerScript.new()
	add_child(banner)
	for _frame in range(3):
		await get_tree().process_frame

	banner.show_identity(
		"BOSS_BANNER_MOTHER_GOOSE_NAME",
		"BOSS_BANNER_MOTHER_GOOSE_ROLE",
		"GOOSE")
	var step_02_err: Error = await _capture(
		banner, 0.28, "res://bench/results/boss_arrival_banner_step_02.png")
	var step_05_err: Error = await _capture(
		banner, 0.63, "res://bench/results/boss_arrival_banner_step_05.png")
	var final_err: Error = await _capture(
		banner, 1.0, "res://bench/results/boss_arrival_banner_final.png")
	banner.show_identity(
		"BOSS_BANNER_WRAITH_NAME",
		"BOSS_BANNER_WRAITH_ROLE",
		"WRAITH",
		"BOSS_BANNER_WRAITH_MOTTO",
		"wraith_blue")
	var wraith_step_err: Error = await _capture(
		banner, 0.63, "res://bench/results/boss_arrival_banner_wraith_step_05.png")
	var wraith_final_err: Error = await _capture(
		banner, 1.0, "res://bench/results/boss_arrival_banner_wraith_final.png")
	banner.show_identity(
		"BOSS_BANNER_CSG_NAME",
		"BOSS_BANNER_CSG_ROLE",
		"CSG",
		"BOSS_BANNER_CSG_MOTTO",
		"terminal_green")
	var csg_final_err: Error = await _capture(
		banner, 1.0, "res://bench/results/boss_arrival_banner_csg_final.png")
	banner.show_identity(
		"BOSS_BANNER_BLACK_STAR_NAME",
		"BOSS_BANNER_BLACK_STAR_ROLE",
		"HYPER-A",
		"BOSS_BANNER_BLACK_STAR_MOTTO",
		"black_star")
	var black_star_final_err: Error = await _capture(
		banner, 1.0, "res://bench/results/boss_arrival_banner_black_star_final.png")

	get_tree().quit(0 if step_02_err == OK and step_05_err == OK and final_err == OK \
		and wraith_step_err == OK and wraith_final_err == OK and csg_final_err == OK \
		and black_star_final_err == OK else 1)


func _capture(banner: BossArrivalBanner, progress: float, path: String) -> Error:
	banner.set_reveal_progress(progress)
	await RenderingServer.frame_post_draw
	var err := get_viewport().get_texture().get_image().save_png(path)
	print("[boss_arrival_banner_visual] progress=%.2f path=%s err=%d" % [progress, path, err])
	return err


func _build_backdrop() -> void:
	var background := ColorRect.new()
	background.color = Color("081014")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)

	# 只提供接近实战的低对比战术网格；横幅本身仍是截图唯一焦点。
	for x in range(0, 1921, 40):
		var vertical := ColorRect.new()
		vertical.color = Color(0.0, 1.0, 0.25, 0.055)
		vertical.position = Vector2(float(x), 0.0)
		vertical.size = Vector2(1.0, 1080.0)
		vertical.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(vertical)
	for y in range(0, 1081, 36):
		var horizontal := ColorRect.new()
		horizontal.color = Color(0.0, 1.0, 0.25, 0.045)
		horizontal.position = Vector2(0.0, float(y))
		horizontal.size = Vector2(1920.0, 1.0)
		horizontal.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(horizontal)

	var contact := Label.new()
	contact.text = "TACTICAL FEED // CONTACT LOST // CHANNEL OVERRIDDEN"
	contact.position = Vector2(48.0, 1012.0)
	contact.size = Vector2(900.0, 28.0)
	contact.add_theme_font_override("font", TerminalText.SILKSCREEN_FONT_SOURCE)
	contact.add_theme_font_size_override("font_size", 15)
	contact.add_theme_color_override("font_color", Color(0.0, 1.0, 0.25, 0.3))
	add_child(contact)
