class_name TerminalPageShell
extends Control

## 局外整页 UI 共用的 CRT 终端壳。
## 复用主菜单的物理机壳与玻璃后处理，只暴露 23u × 30u 的安全内容区。

const MainMenuCrtShellScript := preload("res://scripts/ui/main_menu_crt_shell.gd")
const MainMenuCrtEffectScript := preload("res://scripts/ui/main_menu_crt_effect.gd")

const U_SIZE := Vector2(40.0, 18.0)
const CONTENT_SIZE := Vector2(U_SIZE.x * 23.0, U_SIZE.y * 30.0)
const SAFE_MARGIN := Vector2(U_SIZE.x, U_SIZE.y)

var content: Control


func _init() -> void:
	name = "TerminalPageShell"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_CENTER)
	position = -MainMenuCrtShellScript.SHELL_SIZE * 0.5
	size = MainMenuCrtShellScript.SHELL_SIZE
	_build_shell()


func _build_shell() -> void:
	var shell := MainMenuCrtShellScript.new()
	shell.name = "TerminalPhysicalShell"
	add_child(shell)

	var glass_background := ColorRect.new()
	glass_background.name = "TerminalGlassBackground"
	glass_background.position = MainMenuCrtShellScript.SCREEN_RECT.position
	glass_background.size = MainMenuCrtShellScript.SCREEN_RECT.size
	glass_background.color = Color("010202")
	glass_background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(glass_background)

	content = Control.new()
	content.name = "TerminalPageContent"
	content.position = MainMenuCrtShellScript.SCREEN_RECT.position + SAFE_MARGIN
	content.size = CONTENT_SIZE
	content.clip_contents = true
	content.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(content)

	var screen_background := ColorRect.new()
	screen_background.name = "TerminalPageBackground"
	screen_background.color = Color("010202")
	screen_background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screen_background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(screen_background)

	var effect := MainMenuCrtEffectScript.new()
	effect.name = "TerminalGlassEffect"
	effect.position = MainMenuCrtShellScript.SCREEN_RECT.position
	effect.size = MainMenuCrtShellScript.SCREEN_RECT.size
	add_child(effect)
