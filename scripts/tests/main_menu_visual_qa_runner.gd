extends Node2D

const MainMenuCrtShellScript := preload("res://scripts/ui/main_menu_crt_shell.gd")

## 仅供 bench Visual：以中/英/日渲染入口主菜单的正式终端模式板并做基础几何审计。

const MainMenuScript := preload("res://scripts/main_menu.gd")
const OUTPUT_PATH := "res://bench/results/main_menu_visual.png"
const LOCALES := ["zh", "en", "ja"]


func _ready() -> void:
	DisplayServer.window_set_size(Vector2i(1920, 1080))
	var failures: Array[String] = []
	for locale in LOCALES:
		TranslationServer.set_locale(locale)
		var menu := MainMenuScript.new()
		menu.name = "MainMenuUnderTest_%s" % locale
		add_child(menu)

		for _frame in range(6):
			await get_tree().process_frame
		await RenderingServer.frame_post_draw

		_audit_menu(menu, locale, failures)
		var image := get_viewport().get_texture().get_image()
		var locale_path := "res://bench/results/main_menu_visual_%s.png" % locale
		var error := image.save_png(locale_path)
		if error != OK:
			failures.append("[%s] 截图保存失败：%d" % [locale, error])
		if locale == "zh":
			var canonical_error := image.save_png(OUTPUT_PATH)
			if canonical_error != OK:
				failures.append("[zh] 默认截图保存失败：%d" % canonical_error)
		print("[main_menu_visual] locale=%s screenshot=%s err=%d" % [
			locale, locale_path, error])
		menu.queue_free()
		await get_tree().process_frame

	for failure in failures:
		push_error("[main_menu_visual] %s" % failure)
	print("[main_menu_visual] locales=%d failures=%d" % [LOCALES.size(), failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)


func _audit_menu(menu: Node, locale: String, failures: Array[String]) -> void:
	var shell := menu.find_child("CrtDisplayShell", true, false) as Control
	var screen := menu.find_child("CrtScreenContent", true, false) as Control
	var system_board := menu.find_child("SystemTerminalBoard", true, false) as Control
	var glass_effect := menu.find_child("CrtGlassEffect", true, false) as ColorRect
	if shell == null or not shell.size.is_equal_approx(MainMenuCrtShellScript.SHELL_SIZE):
		failures.append("[%s] CRT 机壳缺失或尺寸错误" % locale)
	if screen == null or not screen.size.is_equal_approx(MainMenuScript.CRT_SCREEN_SIZE):
		failures.append("[%s] CRT 安全显示区缺失或尺寸错误" % locale)
	if system_board == null or not system_board.size.is_equal_approx(MainMenuScript.SYSTEM_BOARD_SIZE):
		failures.append("[%s] 右侧系统终端缺失或尺寸错误" % locale)
	if glass_effect == null or not glass_effect.size.is_equal_approx(
			MainMenuCrtShellScript.SCREEN_RECT.size):
		failures.append("[%s] CRT 凸面滤镜缺失或没有覆盖完整玻璃" % locale)
	var board := menu.find_child("ModeTerminalBoard", true, false) as Control
	if board == null:
		failures.append("[%s] 缺少 ModeTerminalBoard" % locale)
		return
	if not board.size.is_equal_approx(MainMenuScript.MODE_BOARD_SIZE):
		failures.append("[%s] 模式板尺寸错误：%s" % [locale, str(board.size)])
	var options := board.find_children("ModeOption*", "Button", true, false)
	if options.size() != 5:
		failures.append("[%s] 模式行数量应为 5，实际 %d" % [locale, options.size()])
		return
	for index in range(options.size()):
		var option := options[index] as Button
		var expected_y := MainMenuScript.U_SIZE.y \
			+ MainMenuScript.MODE_ROW_SIZE.y * float(index)
		if not is_equal_approx(option.position.y, expected_y):
			failures.append("[%s] 模式行 %d 的 Y 坐标错误：%.1f" % [
				locale, index + 1, option.position.y])
	if not (options[0] as Button).has_focus():
		failures.append("[%s] 首个可用模式没有默认键盘焦点" % locale)
