extends Node2D

## 仅供 bench Visual：渲染入口主菜单的正式终端模式板并做基础几何审计。

const MainMenuScript := preload("res://scripts/main_menu.gd")
const OUTPUT_PATH := "res://bench/results/main_menu_visual.png"


func _ready() -> void:
	DisplayServer.window_set_size(Vector2i(1920, 1080))
	TranslationServer.set_locale("zh")

	var menu := MainMenuScript.new()
	menu.name = "MainMenuUnderTest"
	add_child(menu)

	for _frame in range(6):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw

	var failures: Array[String] = []
	var shell := menu.find_child("CrtDisplayShell", true, false) as Control
	var screen := menu.find_child("CrtScreenContent", true, false) as Control
	var system_board := menu.find_child("SystemTerminalBoard", true, false) as Control
	var glass_effect := menu.find_child("CrtGlassEffect", true, false) as ColorRect
	if shell == null or not shell.size.is_equal_approx(MainMenuCrtShell.SHELL_SIZE):
		failures.append("CRT 机壳缺失或尺寸错误")
	if screen == null or not screen.size.is_equal_approx(MainMenuScript.CRT_SCREEN_SIZE):
		failures.append("CRT 安全显示区缺失或尺寸错误")
	if system_board == null or not system_board.size.is_equal_approx(MainMenuScript.SYSTEM_BOARD_SIZE):
		failures.append("右侧系统终端缺失或尺寸错误")
	if glass_effect == null or not glass_effect.size.is_equal_approx(MainMenuCrtShell.SCREEN_RECT.size):
		failures.append("CRT 凸面滤镜缺失或没有覆盖完整玻璃")
	var board := menu.find_child("ModeTerminalBoard", true, false) as Control
	if board == null:
		failures.append("缺少 ModeTerminalBoard")
	else:
		if not board.size.is_equal_approx(MainMenuScript.MODE_BOARD_SIZE):
			failures.append("模式板尺寸错误：%s" % str(board.size))
		var options := board.find_children("ModeOption*", "Button", true, false)
		if options.size() != 5:
			failures.append("模式行数量应为 5，实际 %d" % options.size())
		else:
			for index in range(options.size()):
				var option := options[index] as Button
				var expected_y := MainMenuScript.U_SIZE.y \
					+ MainMenuScript.MODE_ROW_SIZE.y * float(index)
				if not is_equal_approx(option.position.y, expected_y):
					failures.append("模式行 %d 的 Y 坐标错误：%.1f" % [
						index + 1, option.position.y])
			if not (options[0] as Button).has_focus():
				failures.append("首个可用模式没有默认键盘焦点")

	var image := get_viewport().get_texture().get_image()
	var error := image.save_png(OUTPUT_PATH)
	if error != OK:
		failures.append("截图保存失败：%d" % error)

	for failure in failures:
		push_error("[main_menu_visual] %s" % failure)
	print("[main_menu_visual] screenshot=%s err=%d failures=%d" % [
		OUTPUT_PATH, error, failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)
