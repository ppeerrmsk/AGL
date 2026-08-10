extends Node2D

const HudPreferencesScript := preload("res://scripts/ui/hud_preferences.gd")
const HudColorSettingsPanelScript := preload("res://scripts/ui/hud_color_settings_panel.gd")
const TerminalGridOverlayScript := preload("res://scripts/ui/terminal_grid_overlay.gd")
const TerminalTextScript := preload("res://scripts/ui/terminal_text.gd")
const MainMenuCrtShellScript := preload("res://scripts/ui/main_menu_crt_shell.gd")
const MainMenuCrtEffectScript := preload("res://scripts/ui/main_menu_crt_effect.gd")
const MainMenuScopeDisplayScript := preload("res://scripts/ui/main_menu_scope_display.gd")

## 主菜单：游戏入口，选择游戏模式

# --- 视觉参数 ---
const U_SIZE := Vector2(40.0, 18.0)
const Q_SIZE := Vector2(18.0, 18.0)
const CRT_SCREEN_SIZE := Vector2(U_SIZE.x * 23.0, U_SIZE.y * 30.0)
const CRT_SAFE_MARGIN := Vector2(U_SIZE.x, U_SIZE.y)
const HEADER_PANEL_SIZE := Vector2(CRT_SCREEN_SIZE.x, U_SIZE.y * 6.0)
const MODE_ROW_SIZE := Vector2(U_SIZE.x * 15.0, U_SIZE.y * 4.0)
const MODE_BOARD_SIZE := Vector2(MODE_ROW_SIZE.x, U_SIZE.y + MODE_ROW_SIZE.y * 5.0)
const SYSTEM_BOARD_SIZE := Vector2(U_SIZE.x * 8.0, MODE_BOARD_SIZE.y)
const FOOTER_PANEL_SIZE := Vector2(CRT_SCREEN_SIZE.x, U_SIZE.y * 3.0)
const MODE_INDEX_WIDTH := U_SIZE.x * 2.0
const MODE_STATUS_WIDTH := U_SIZE.x * 2.0
const MODE_INFO_WIDTH := MODE_ROW_SIZE.x - MODE_INDEX_WIDTH - MODE_STATUS_WIDTH
const DANGER_COLOR := Color("ff493d")

# --- UI ---
var _canvas: CanvasLayer
var _screen_content: Control
var _mode_container: Control
var _mode_grid_overlay: TerminalGridOverlay
var _system_grid_overlay: TerminalGridOverlay
var _mode_buttons: Array[Button] = []
var _terminal_text_nodes: Array[TerminalText] = []
var _terminal_overlays: Array[TerminalGridOverlay] = []
var _aux_buttons: Array[Button] = []
var _accent_fill_blocks: Array[ColorRect] = []
var _scope_display: MainMenuScopeDisplay
var _merit_value_text: TerminalText
var _speed_unit_button: Button
var _hud_color_button: Button

func _ready() -> void:
	RenderingServer.set_default_clear_color(ThemeColors.SCENE_BG)
	CombatUnit.reset_id_allocator()
	CallsignDB.reset()
	_build_ui()


## ── Debug 快捷键（开发用） ──
## Ctrl + M           → +1000 功勋
## Ctrl + Shift + M   → -1000 功勋（夹底 0）
## Ctrl + Alt + M     → 功勋归零
## Ctrl + U           → 本次运行解锁全部敌人图鉴（不改战绩）
## Ctrl + Shift + U   → 恢复按真实战绩解锁
## 注：仅在主菜单的 Debug build 生效。
func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	if not OS.is_debug_build() or not event.ctrl_pressed:
		return
	if event.keycode == KEY_U:
		var unlock_all: bool = not event.shift_pressed
		EnemyCodex.debug_set_unlock_all(unlock_all)
		_show_toast("[debug] codex %s" % ("unlock all" if unlock_all else "restore progress"))
		get_viewport().set_input_as_handled()
		return
	if event.keycode != KEY_M:
		return
	var delta: int = 1000
	var msg: String = ""
	if event.alt_pressed:
		MeritLedger.debug_reset()
		msg = "[debug] merit reset → 0"
	elif event.shift_pressed:
		var cur: int = MeritLedger.get_total()
		var sub: int = mini(delta, cur)
		MeritLedger.debug_add(-sub)
		msg = "[debug] merit -%d → %d" % [sub, MeritLedger.get_total()]
	else:
		MeritLedger.debug_add(delta)
		msg = "[debug] merit +%d → %d" % [delta, MeritLedger.get_total()]
	_show_toast(msg)
	get_viewport().set_input_as_handled()


func _build_ui() -> void:
	_canvas = CanvasLayer.new()
	_canvas.layer = 10
	add_child(_canvas)

	var shell := MainMenuCrtShellScript.new() as MainMenuCrtShell
	shell.name = "CrtDisplayShell"
	shell.set_anchors_preset(Control.PRESET_CENTER)
	shell.position = -MainMenuCrtShellScript.SHELL_SIZE * 0.5
	_canvas.add_child(shell)
	var glass_background := ColorRect.new()
	glass_background.name = "CrtGlassBackground"
	glass_background.set_anchors_preset(Control.PRESET_CENTER)
	glass_background.position = -MainMenuCrtShellScript.SHELL_SIZE * 0.5 \
		+ MainMenuCrtShellScript.SCREEN_RECT.position
	glass_background.size = MainMenuCrtShellScript.SCREEN_RECT.size
	glass_background.color = Color("010302")
	glass_background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.add_child(glass_background)

	_screen_content = Control.new()
	_screen_content.name = "CrtScreenContent"
	_screen_content.set_anchors_preset(Control.PRESET_CENTER)
	_screen_content.position = -MainMenuCrtShellScript.SHELL_SIZE * 0.5 \
		+ MainMenuCrtShellScript.SCREEN_RECT.position + CRT_SAFE_MARGIN
	_screen_content.size = CRT_SCREEN_SIZE
	_screen_content.clip_contents = true
	_canvas.add_child(_screen_content)
	var screen_background := ColorRect.new()
	screen_background.color = Color("020503")
	screen_background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screen_background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_screen_content.add_child(screen_background)

	_build_terminal_header(_screen_content)

	# 左侧模式台：15u × 21u，顶部 1u + 五条 4u 模式行。
	_mode_container = Control.new()
	_mode_container.name = "ModeTerminalBoard"
	_mode_container.position = Vector2(0.0, HEADER_PANEL_SIZE.y)
	_mode_container.size = MODE_BOARD_SIZE
	_screen_content.add_child(_mode_container)
	_add_block_background(_mode_container, Rect2(Vector2.ZERO, MODE_BOARD_SIZE))

	_add_terminal_text(
		_mode_container,
		tr("MENU_MODE_LABEL"),
		Rect2(Vector2.ZERO, Vector2(MODE_BOARD_SIZE.x, U_SIZE.y)),
		TerminalTextScript.FontFace.SILKSCREEN,
		TerminalTextScript.SizeRule.ONE_U_FIXED_15,
		HORIZONTAL_ALIGNMENT_LEFT
	)
	_mode_grid_overlay = TerminalGridOverlayScript.new() as TerminalGridOverlay
	_mode_grid_overlay.name = "ModeTerminalGrid"
	_mode_grid_overlay.size = MODE_BOARD_SIZE
	_mode_grid_overlay.regions = [Rect2(Vector2.ZERO, Vector2(MODE_BOARD_SIZE.x, U_SIZE.y))]
	_mode_container.add_child(_mode_grid_overlay)
	_terminal_overlays.append(_mode_grid_overlay)

	# 生存模式为主显示，入口顺序与旧主菜单保持一致。
	_add_mode_button(tr("MENU_MODE_SURVIVOR_NAME"), tr("MENU_MODE_SURVIVOR_DESC"), _on_survivor_pressed)
	_add_mode_button(tr("MENU_MODE_EDITOR_NAME"), tr("MENU_MODE_EDITOR_DESC"), _on_editor_pressed)
	_add_mode_button(tr("MENU_META_SHOP_NAME"), tr("MENU_META_SHOP_DESC"), _on_meta_shop_pressed)
	_add_mode_button(tr("MENU_ARCHIVE_NAME"), tr("MENU_ARCHIVE_DESC"), _on_archive_pressed)
	_add_mode_button(tr("MENU_MODE_MISSION_NAME"), tr("MENU_MODE_MISSION_DESC"), Callable(), true)
	_mode_grid_overlay.move_to_front()
	if not _mode_buttons.is_empty():
		call_deferred("_focus_default_mode")

	_build_system_panel(_screen_content)
	_build_terminal_footer(_screen_content)

	# 最后绘制局部屏幕采样层：只扭曲 CRT 内屏，机壳保持物理直线。
	var effect := MainMenuCrtEffectScript.new() as MainMenuCrtEffect
	effect.name = "CrtGlassEffect"
	effect.set_anchors_preset(Control.PRESET_CENTER)
	effect.position = -MainMenuCrtShellScript.SHELL_SIZE * 0.5 \
		+ MainMenuCrtShellScript.SCREEN_RECT.position
	effect.size = MainMenuCrtShellScript.SCREEN_RECT.size
	_canvas.add_child(effect)
	_refresh_terminal_palette()


func _build_terminal_header(parent: Control) -> void:
	var panel := Control.new()
	panel.name = "HeaderTerminalPanel"
	panel.size = HEADER_PANEL_SIZE
	parent.add_child(panel)
	_add_block_background(panel, Rect2(Vector2.ZERO, HEADER_PANEL_SIZE))

	var classification_rect := Rect2(Vector2.ZERO, Vector2(HEADER_PANEL_SIZE.x, U_SIZE.y))
	var title_rect := Rect2(Vector2(0.0, U_SIZE.y), Vector2(U_SIZE.x * 15.0, U_SIZE.y * 5.0))
	var merit_title_rect := Rect2(
		Vector2(U_SIZE.x * 15.0, U_SIZE.y), Vector2(U_SIZE.x * 4.0, U_SIZE.y))
	var merit_value_rect := Rect2(
		Vector2(U_SIZE.x * 15.0, U_SIZE.y * 2.0), Vector2(U_SIZE.x * 4.0, U_SIZE.y * 4.0))
	var access_title_rect := Rect2(
		Vector2(U_SIZE.x * 19.0, U_SIZE.y), Vector2(U_SIZE.x * 4.0, U_SIZE.y))
	var access_value_rect := Rect2(
		Vector2(U_SIZE.x * 19.0, U_SIZE.y * 2.0), Vector2(U_SIZE.x * 4.0, U_SIZE.y * 4.0))

	_add_terminal_text(
		panel,
		tr("MENU_SUBTITLE"),
		classification_rect,
		TerminalTextScript.FontFace.THEME,
		TerminalTextScript.SizeRule.ONE_U_FIXED_15,
		HORIZONTAL_ALIGNMENT_LEFT
	)
	_add_terminal_text(
		panel,
		tr("MENU_TITLE"),
		title_rect,
		TerminalTextScript.FontFace.CHAKRA_PETCH_BOLD,
		TerminalTextScript.SizeRule.VISIBLE_INK_FILL,
		HORIZONTAL_ALIGNMENT_CENTER,
		tr("MENU_TITLE")
	)
	_build_merit_display(panel, merit_title_rect, merit_value_rect)
	_add_terminal_text(
		panel,
		tr("MENU_ACCESS_LABEL"),
		access_title_rect,
		TerminalTextScript.FontFace.SILKSCREEN,
		TerminalTextScript.SizeRule.ONE_U_FIXED_15,
		HORIZONTAL_ALIGNMENT_LEFT
	)
	var access_background := _add_block_background(panel, access_value_rect)
	access_background.color = HudPreferencesScript.hud_color()
	_accent_fill_blocks.append(access_background)
	var access_text := _add_terminal_text(
		panel,
		tr("MENU_TERMINAL_READY"),
		access_value_rect,
		TerminalTextScript.FontFace.SILKSCREEN,
		TerminalTextScript.SizeRule.ONE_U_FIXED_15,
		HORIZONTAL_ALIGNMENT_CENTER
	)
	access_text.set_meta("uses_terminal_accent", false)
	access_text.font_color = ThemeColors.UI_TERMINAL_INVERSE

	var grid := TerminalGridOverlayScript.new() as TerminalGridOverlay
	grid.name = "HeaderTerminalGrid"
	grid.size = HEADER_PANEL_SIZE
	grid.regions = [classification_rect, title_rect, merit_title_rect, merit_value_rect,
		access_title_rect, access_value_rect]
	grid.override_regions = [access_value_rect]
	grid.override_color = ThemeColors.UI_TERMINAL_INVERSE
	panel.add_child(grid)
	_terminal_overlays.append(grid)


func _build_system_panel(parent: Control) -> void:
	var panel := Control.new()
	panel.name = "SystemTerminalBoard"
	panel.position = Vector2(MODE_BOARD_SIZE.x, HEADER_PANEL_SIZE.y)
	panel.size = SYSTEM_BOARD_SIZE
	parent.add_child(panel)
	_add_block_background(panel, Rect2(Vector2.ZERO, SYSTEM_BOARD_SIZE))

	var scope_title_rect := Rect2(Vector2.ZERO, Vector2(SYSTEM_BOARD_SIZE.x, U_SIZE.y))
	var scope_rect := Rect2(Vector2(0.0, U_SIZE.y), Vector2(SYSTEM_BOARD_SIZE.x, U_SIZE.y * 11.0))
	var settings_title_rect := Rect2(
		Vector2(0.0, U_SIZE.y * 12.0), Vector2(SYSTEM_BOARD_SIZE.x, U_SIZE.y))
	_add_terminal_text(panel, tr("MENU_SYSTEM_LABEL"), scope_title_rect,
		TerminalTextScript.FontFace.SILKSCREEN,
		TerminalTextScript.SizeRule.ONE_U_FIXED_15, HORIZONTAL_ALIGNMENT_LEFT)
	_add_terminal_text(panel, tr("MENU_TERMINAL_SETTINGS_LABEL"), settings_title_rect,
		TerminalTextScript.FontFace.SILKSCREEN,
		TerminalTextScript.SizeRule.ONE_U_FIXED_15, HORIZONTAL_ALIGNMENT_LEFT)

	_scope_display = MainMenuScopeDisplayScript.new() as MainMenuScopeDisplay
	_scope_display.name = "TerminalScopeDisplay"
	_scope_display.position = scope_rect.position
	_scope_display.size = scope_rect.size
	panel.add_child(_scope_display)

	_build_language_switcher(panel)
	_build_audio_button(panel)
	_build_sandbox_corner_button(panel)

	_system_grid_overlay = TerminalGridOverlayScript.new() as TerminalGridOverlay
	_system_grid_overlay.name = "SystemTerminalGrid"
	_system_grid_overlay.size = SYSTEM_BOARD_SIZE
	_system_grid_overlay.regions = [
		scope_title_rect,
		scope_rect,
		settings_title_rect,
		Rect2(0.0, U_SIZE.y * 13.0, U_SIZE.x * 2.0, U_SIZE.y * 2.0),
		Rect2(U_SIZE.x * 2.0, U_SIZE.y * 13.0, U_SIZE.x * 3.0, U_SIZE.y * 2.0),
		Rect2(U_SIZE.x * 5.0, U_SIZE.y * 13.0, U_SIZE.x * 3.0, U_SIZE.y * 2.0),
		Rect2(0.0, U_SIZE.y * 15.0, U_SIZE.x * 4.0, U_SIZE.y * 2.0),
		Rect2(U_SIZE.x * 4.0, U_SIZE.y * 15.0, U_SIZE.x * 4.0, U_SIZE.y * 2.0),
		Rect2(0.0, U_SIZE.y * 17.0, U_SIZE.x * 4.0, U_SIZE.y * 2.0),
		Rect2(U_SIZE.x * 4.0, U_SIZE.y * 17.0, U_SIZE.x * 4.0, U_SIZE.y * 2.0),
		Rect2(0.0, U_SIZE.y * 19.0, U_SIZE.x * 8.0, U_SIZE.y * 2.0),
	]
	panel.add_child(_system_grid_overlay)
	_terminal_overlays.append(_system_grid_overlay)
	_refresh_system_grid_overrides()


func _build_terminal_footer(parent: Control) -> void:
	var panel := Control.new()
	panel.name = "TerminalLogPanel"
	panel.position = Vector2(0.0, U_SIZE.y * 27.0)
	panel.size = FOOTER_PANEL_SIZE
	parent.add_child(panel)
	_add_block_background(panel, Rect2(Vector2.ZERO, FOOTER_PANEL_SIZE))
	var title_rect := Rect2(Vector2.ZERO, Vector2(FOOTER_PANEL_SIZE.x, U_SIZE.y))
	var body_rect := Rect2(
		Vector2(0.0, U_SIZE.y), Vector2(FOOTER_PANEL_SIZE.x, U_SIZE.y * 2.0))
	_add_terminal_text(panel, tr("MENU_SYSTEM_LOG_LABEL"), title_rect,
		TerminalTextScript.FontFace.SILKSCREEN,
		TerminalTextScript.SizeRule.ONE_U_FIXED_15, HORIZONTAL_ALIGNMENT_LEFT)
	_add_terminal_text(panel, tr("MENU_VERSION"), body_rect,
		TerminalTextScript.FontFace.THEME,
		TerminalTextScript.SizeRule.ONE_U_FIXED_15, HORIZONTAL_ALIGNMENT_LEFT)
	var grid := TerminalGridOverlayScript.new() as TerminalGridOverlay
	grid.name = "TerminalLogGrid"
	grid.size = FOOTER_PANEL_SIZE
	grid.regions = [title_rect, body_rect]
	panel.add_child(grid)
	_terminal_overlays.append(grid)


func _add_block_background(parent: Control, rect: Rect2) -> ColorRect:
	var block := ColorRect.new()
	block.position = rect.position
	block.size = rect.size
	block.color = ThemeColors.UI_BLOCK_BACKGROUND
	block.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(block)
	return block


func _add_terminal_text(parent: Control, value: String, rect: Rect2, font_face: int,
		size_rule: int, alignment: HorizontalAlignment,
		layout_value: String = "") -> TerminalText:
	var terminal_text := TerminalTextScript.new() as TerminalText
	terminal_text.position = rect.position
	terminal_text.size = rect.size
	terminal_text.text = value
	terminal_text.layout_text = value if layout_value.is_empty() else layout_value
	terminal_text.font_face = font_face
	terminal_text.size_rule = size_rule
	terminal_text.horizontal_alignment = alignment
	terminal_text.font_color = HudPreferencesScript.hud_color()
	terminal_text.set_meta("uses_terminal_accent", true)
	parent.add_child(terminal_text)
	_terminal_text_nodes.append(terminal_text)
	return terminal_text

## 右侧终端语言排：中 / EN / 日（文字不翻译，保持识别性）。
func _build_language_switcher(parent: Control) -> void:
	var current_locale: String = LocaleManager.get_current_locale()
	var options := [
		{"code": "zh", "label": "中", "rect": Rect2(0.0, U_SIZE.y * 13.0, U_SIZE.x * 2.0, U_SIZE.y * 2.0)},
		{"code": "en", "label": "EN", "rect": Rect2(U_SIZE.x * 2.0, U_SIZE.y * 13.0, U_SIZE.x * 3.0, U_SIZE.y * 2.0)},
		{"code": "ja", "label": "日", "rect": Rect2(U_SIZE.x * 5.0, U_SIZE.y * 13.0, U_SIZE.x * 3.0, U_SIZE.y * 2.0)},
	]
	for opt in options:
		var is_active: bool = (opt["code"] == current_locale)
		var code_capture: String = opt["code"]
		_add_aux_terminal_button(parent, opt["rect"], opt["label"],
			func(): LocaleManager.set_locale_persistent(code_capture), is_active)

## 右侧终端设置：两行 4u × 2u 功能键。
func _build_audio_button(parent: Control) -> void:
	var audio_rect := Rect2(0.0, U_SIZE.y * 15.0, U_SIZE.x * 4.0, U_SIZE.y * 2.0)
	var speed_rect := Rect2(U_SIZE.x * 4.0, U_SIZE.y * 15.0, U_SIZE.x * 4.0, U_SIZE.y * 2.0)
	var color_rect := Rect2(0.0, U_SIZE.y * 17.0, U_SIZE.x * 4.0, U_SIZE.y * 2.0)
	var reset_rect := Rect2(U_SIZE.x * 4.0, U_SIZE.y * 17.0, U_SIZE.x * 4.0, U_SIZE.y * 2.0)
	_add_aux_terminal_button(parent, audio_rect, tr("MENU_AUDIO_BUTTON"), _on_audio_settings_pressed)
	_speed_unit_button = _add_aux_terminal_button(parent, speed_rect, "", _on_speed_unit_pressed)
	_hud_color_button = _add_aux_terminal_button(
		parent, color_rect, tr("MENU_HUD_COLOR_BUTTON"), _on_hud_color_pressed)
	_add_aux_terminal_button(parent, reset_rect, tr("MENU_RESET_SAVE_BUTTON"),
		_on_reset_save_pressed, false, true)
	_refresh_hud_settings_buttons()


func _add_aux_terminal_button(parent: Control, rect: Rect2, label_text: String,
		callback: Callable, selected: bool = false, danger: bool = false) -> Button:
	var btn := Button.new()
	btn.position = rect.position
	btn.size = rect.size
	btn.text = ""
	btn.focus_mode = Control.FOCUS_ALL
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var empty_style := StyleBoxEmpty.new()
	for style_name in ["normal", "hover", "pressed", "focus", "disabled"]:
		btn.add_theme_stylebox_override(style_name, empty_style)
	var local_rect := Rect2(Vector2.ZERO, rect.size)
	var background := _add_block_background(btn, local_rect)
	background.color = Color.TRANSPARENT
	var text_node := _add_terminal_text(btn, label_text, local_rect,
		TerminalTextScript.FontFace.THEME,
		TerminalTextScript.SizeRule.ONE_U_FIXED_15, HORIZONTAL_ALIGNMENT_CENTER)
	btn.set_meta("aux_background", background)
	btn.set_meta("aux_text", text_node)
	btn.set_meta("terminal_grid_rect", rect)
	btn.set_meta("terminal_active", selected)
	btn.set_meta("terminal_danger", danger)
	btn.mouse_entered.connect(func(): _refresh_aux_button_visual(btn))
	btn.mouse_exited.connect(func(): _refresh_aux_button_visual(btn))
	btn.focus_entered.connect(func(): _refresh_aux_button_visual(btn))
	btn.focus_exited.connect(func(): _refresh_aux_button_visual(btn))
	if callback.is_valid():
		btn.pressed.connect(callback)
	parent.add_child(btn)
	_aux_buttons.append(btn)
	_refresh_aux_button_visual(btn)
	return btn


func _refresh_aux_button_visual(btn: Button) -> void:
	if not is_instance_valid(btn):
		return
	var danger := bool(btn.get_meta("terminal_danger", false))
	var active := bool(btn.get_meta("terminal_active", false)) or btn.is_hovered() or btn.has_focus()
	var accent: Color = DANGER_COLOR if danger else HudPreferencesScript.hud_color()
	var background: ColorRect = btn.get_meta("aux_background") as ColorRect
	var text_node: TerminalText = btn.get_meta("aux_text") as TerminalText
	background.color = accent if active else Color.TRANSPARENT
	text_node.font_color = ThemeColors.UI_TERMINAL_INVERSE if active else accent
	_refresh_system_grid_overrides()


func _refresh_system_grid_overrides() -> void:
	if not is_instance_valid(_system_grid_overlay):
		return
	var override_regions: Array[Rect2] = []
	for btn in _aux_buttons:
		if is_instance_valid(btn) and (bool(btn.get_meta("terminal_active", false)) \
				or btn.is_hovered() or btn.has_focus()):
			override_regions.append(btn.get_meta("terminal_grid_rect") as Rect2)
	_system_grid_overlay.override_color = ThemeColors.UI_TERMINAL_INVERSE
	_system_grid_overlay.override_regions = override_regions


func _set_aux_button_text(btn: Button, value: String) -> void:
	if not is_instance_valid(btn):
		return
	var text_node: TerminalText = btn.get_meta("aux_text") as TerminalText
	if is_instance_valid(text_node):
		text_node.text = value
		text_node.layout_text = value


func _refresh_hud_settings_buttons() -> void:
	if _speed_unit_button:
		var speed_fmt := tr("MENU_SPEED_UNIT_FMT")
		if not speed_fmt.contains("%s"):
			speed_fmt = "SPEED %s"
		_set_aux_button_text(
			_speed_unit_button, speed_fmt % ("KT" if HudPreferencesScript.uses_knots() else "KM/H"))
	if _hud_color_button:
		_set_aux_button_text(_hud_color_button, tr("MENU_HUD_COLOR_BUTTON"))
	_refresh_terminal_palette()

## 要在重置时删除的存档文件列表（保留 locale.cfg / audio.cfg / hud.cfg 用户偏好）
## tutorial.cfg 走文件删除；merit/loadout 走 ledger.debug_reset()（同时清内存 + 重写 cfg）
const RESET_SAVE_FILES := [
	"user://tutorial.cfg",
]

func _on_reset_save_pressed() -> void:
	var dlg := ConfirmationDialog.new()
	dlg.dialog_text = tr("MENU_RESET_SAVE_CONFIRM")
	dlg.ok_button_text = tr("MENU_RESET_SAVE_CONFIRM_BTN")
	dlg.cancel_button_text = tr("MENU_RESET_SAVE_CANCEL")
	dlg.title = tr("MENU_RESET_SAVE_BUTTON")
	_canvas.add_child(dlg)
	dlg.confirmed.connect(func():
		var removed := 0
		for path in RESET_SAVE_FILES:
			if FileAccess.file_exists(path):
				DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
				removed += 1
		# AutoLoad 已在内存里持有这些 ledger 状态，单删 cfg 不够，必须调 debug_reset
		MeritLedger.debug_reset()
		removed += 1
		CareerArchive.debug_reset()
		removed += 1
		MetaShop.debug_reset()
		removed += 1
		_show_toast(tr("MENU_RESET_SAVE_OK") % removed)
		dlg.queue_free())
	dlg.canceled.connect(func(): dlg.queue_free())
	dlg.popup_centered()

func _show_toast(text: String) -> void:
	var wrap := PanelContainer.new()
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.05, 0.1, 0.05, 0.92)
	bg.border_color = Color(0.4, 0.9, 0.4, 0.6)
	bg.set_border_width_all(1)
	bg.set_corner_radius_all(3)
	bg.set_content_margin_all(10)
	wrap.add_theme_stylebox_override("panel", bg)
	wrap.set_anchors_preset(Control.PRESET_CENTER_TOP)
	wrap.position = Vector2(-140, 80)
	wrap.custom_minimum_size = Vector2(280, 0)
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 14)
	lbl.add_theme_color_override("font_color", Color(0.8, 1.0, 0.6))
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	wrap.add_child(lbl)
	_canvas.add_child(wrap)
	var tw := create_tween()
	tw.tween_interval(1.8)
	tw.tween_property(wrap, "modulate:a", 0.0, 0.5)
	tw.tween_callback(wrap.queue_free)

func _on_audio_settings_pressed() -> void:
	var panel = preload("res://scripts/audio/audio_settings_panel.gd").new()
	add_child(panel)
	panel.closed.connect(panel.queue_free)
	panel.open()


func _on_speed_unit_pressed() -> void:
	HudPreferencesScript.cycle_speed_unit()
	_refresh_hud_settings_buttons()


func _on_hud_color_pressed() -> void:
	var panel = HudColorSettingsPanelScript.new()
	add_child(panel)
	panel.closed.connect(func():
		_refresh_hud_settings_buttons()
		panel.queue_free())
	panel.open()


func _focus_default_mode() -> void:
	if not is_inside_tree() or _mode_buttons.is_empty():
		return
	var first_button := _mode_buttons[0]
	if is_instance_valid(first_button) and first_button.is_inside_tree():
		first_button.grab_focus()

func _add_mode_button(title: String, desc: String, callback: Callable, disabled := false) -> void:
	var mode_index := _mode_buttons.size()
	var board_y := U_SIZE.y + MODE_ROW_SIZE.y * float(mode_index)
	var row_rect := Rect2(Vector2(0.0, board_y), MODE_ROW_SIZE)
	var index_rect := Rect2(row_rect.position, Vector2(MODE_INDEX_WIDTH, MODE_ROW_SIZE.y))
	var title_rect := Rect2(
		row_rect.position + Vector2(MODE_INDEX_WIDTH, 0.0), Vector2(MODE_INFO_WIDTH, U_SIZE.y))
	var desc_rect := Rect2(
		row_rect.position + Vector2(MODE_INDEX_WIDTH, U_SIZE.y),
		Vector2(MODE_INFO_WIDTH, U_SIZE.y * 3.0))
	var status_rect := Rect2(
		row_rect.position + Vector2(MODE_INDEX_WIDTH + MODE_INFO_WIDTH, 0.0),
		Vector2(MODE_STATUS_WIDTH, MODE_ROW_SIZE.y))

	var btn := Button.new()
	btn.name = "ModeOption%02d" % (mode_index + 1)
	btn.position = row_rect.position
	btn.size = row_rect.size
	btn.text = ""
	btn.disabled = disabled
	btn.focus_mode = Control.FOCUS_NONE if disabled else Control.FOCUS_ALL
	btn.mouse_default_cursor_shape = Control.CURSOR_FORBIDDEN if disabled else Control.CURSOR_POINTING_HAND
	btn.clip_contents = true
	var empty_style := StyleBoxEmpty.new()
	for style_name in ["normal", "hover", "pressed", "focus", "disabled"]:
		btn.add_theme_stylebox_override(style_name, empty_style)

	var local_index_rect := Rect2(Vector2.ZERO, index_rect.size)
	var local_title_rect := Rect2(Vector2(MODE_INDEX_WIDTH, 0.0), title_rect.size)
	var local_desc_rect := Rect2(Vector2(MODE_INDEX_WIDTH, U_SIZE.y), desc_rect.size)
	var local_status_rect := Rect2(
		Vector2(MODE_INDEX_WIDTH + MODE_INFO_WIDTH, 0.0), status_rect.size)
	var index_background := _add_block_background(btn, local_index_rect)
	index_background.color = Color.TRANSPARENT
	var status_background := _add_block_background(btn, local_status_rect)
	status_background.color = Color.TRANSPARENT
	var index_text := _add_terminal_text(
		btn,
		"%02d" % (mode_index + 1),
		local_index_rect,
		TerminalTextScript.FontFace.CHAKRA_PETCH_BOLD,
		TerminalTextScript.SizeRule.VISIBLE_INK_FILL,
		HORIZONTAL_ALIGNMENT_CENTER,
		"99"
	)
	var title_text := _add_terminal_text(
		btn,
		title,
		local_title_rect,
		TerminalTextScript.FontFace.SILKSCREEN,
		TerminalTextScript.SizeRule.ONE_U_FIXED_15,
		HORIZONTAL_ALIGNMENT_LEFT
	)
	var desc_text := _add_terminal_text(
		btn,
		desc,
		local_desc_rect,
		TerminalTextScript.FontFace.THEME,
		TerminalTextScript.SizeRule.ONE_U_FIXED_15,
		HORIZONTAL_ALIGNMENT_LEFT
	)
	var status_text := _add_terminal_text(
		btn,
		"--" if disabled else ">",
		local_status_rect,
		TerminalTextScript.FontFace.SILKSCREEN,
		TerminalTextScript.SizeRule.ONE_U_FIXED_15,
		HORIZONTAL_ALIGNMENT_CENTER
	)

	btn.set_meta("mode_index_background", index_background)
	btn.set_meta("mode_status_background", status_background)
	btn.set_meta("mode_index_text", index_text)
	btn.set_meta("mode_title_text", title_text)
	btn.set_meta("mode_desc_text", desc_text)
	btn.set_meta("mode_status_text", status_text)
	btn.set_meta("mode_index_rect", index_rect)
	btn.set_meta("mode_status_rect", status_rect)
	btn.mouse_entered.connect(func(): _refresh_mode_button_visual(btn))
	btn.mouse_exited.connect(func(): _refresh_mode_button_visual(btn))
	btn.focus_entered.connect(func(): _refresh_mode_button_visual(btn))
	btn.focus_exited.connect(func(): _refresh_mode_button_visual(btn))

	if not disabled and callback.is_valid():
		btn.pressed.connect(callback)

	_mode_container.add_child(btn)
	_mode_buttons.append(btn)
	var regions := _mode_grid_overlay.regions.duplicate()
	regions.append_array([row_rect, index_rect, title_rect, desc_rect, status_rect])
	_mode_grid_overlay.regions = regions
	_refresh_mode_button_visual(btn)


func _refresh_mode_button_visual(btn: Button) -> void:
	if not is_instance_valid(btn):
		return
	var active := not btn.disabled and (btn.is_hovered() or btn.has_focus())
	var accent: Color = HudPreferencesScript.hud_color()
	var idle_color := ThemeColors.UI_INACTIVE_DIGIT if btn.disabled else accent
	var index_background: ColorRect = btn.get_meta("mode_index_background") as ColorRect
	var status_background: ColorRect = btn.get_meta("mode_status_background") as ColorRect
	index_background.color = accent if active else Color.TRANSPARENT
	status_background.color = accent if active else Color.TRANSPARENT

	var index_text: TerminalText = btn.get_meta("mode_index_text") as TerminalText
	var title_text: TerminalText = btn.get_meta("mode_title_text") as TerminalText
	var desc_text: TerminalText = btn.get_meta("mode_desc_text") as TerminalText
	var status_text: TerminalText = btn.get_meta("mode_status_text") as TerminalText
	index_text.font_color = ThemeColors.UI_TERMINAL_INVERSE if active else idle_color
	status_text.font_color = ThemeColors.UI_TERMINAL_INVERSE if active else idle_color
	title_text.font_color = idle_color
	desc_text.font_color = idle_color
	_refresh_mode_grid_overrides()


func _refresh_mode_grid_overrides() -> void:
	if not is_instance_valid(_mode_grid_overlay):
		return
	var override_regions: Array[Rect2] = []
	for btn in _mode_buttons:
		if is_instance_valid(btn) and not btn.disabled and (btn.is_hovered() or btn.has_focus()):
			override_regions.append(btn.get_meta("mode_index_rect") as Rect2)
			override_regions.append(btn.get_meta("mode_status_rect") as Rect2)
	_mode_grid_overlay.override_color = ThemeColors.UI_TERMINAL_INVERSE
	_mode_grid_overlay.override_regions = override_regions


func _refresh_terminal_palette() -> void:
	var accent: Color = HudPreferencesScript.hud_color()
	for terminal_text in _terminal_text_nodes:
		if is_instance_valid(terminal_text) and bool(terminal_text.get_meta("uses_terminal_accent", false)):
			terminal_text.font_color = accent
	for overlay in _terminal_overlays:
		if is_instance_valid(overlay):
			overlay.line_color = accent
	for block in _accent_fill_blocks:
		if is_instance_valid(block):
			block.color = accent
	if is_instance_valid(_scope_display):
		_scope_display.accent = accent
	for btn in _aux_buttons:
		_refresh_aux_button_visual(btn)
	for btn in _mode_buttons:
		_refresh_mode_button_visual(btn)
	_refresh_system_grid_overrides()

func _on_sandbox_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/main.tscn")

func _on_meta_shop_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/meta_shop.tscn")

func _on_archive_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/archive.tscn")

## 沙盒测试入口收进右侧维护终端，不再悬浮在机壳外。
func _build_sandbox_corner_button(parent: Control) -> void:
	var sandbox_rect := Rect2(
		0.0, U_SIZE.y * 19.0, U_SIZE.x * 8.0, U_SIZE.y * 2.0)
	_add_aux_terminal_button(
		parent, sandbox_rect, tr("MENU_MODE_SANDBOX_NAME"), _on_sandbox_pressed)

func _on_survivor_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/survivor_map_select.tscn")


func _on_editor_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/map_editor.tscn")

## 标题仪表右侧的功勋读数：1u 小标题 + 4u 主数字。
func _build_merit_display(parent: Control, title_rect: Rect2, value_rect: Rect2) -> void:
	_add_terminal_text(
		parent,
		tr("MENU_MERIT_LABEL"),
		title_rect,
		TerminalTextScript.FontFace.SILKSCREEN,
		TerminalTextScript.SizeRule.ONE_U_FIXED_15,
		HORIZONTAL_ALIGNMENT_LEFT
	)
	_merit_value_text = _add_terminal_text(
		parent,
		str(MeritLedger.get_total()),
		value_rect,
		TerminalTextScript.FontFace.CHAKRA_PETCH_BOLD,
		TerminalTextScript.SizeRule.VISIBLE_INK_FILL,
		HORIZONTAL_ALIGNMENT_CENTER,
		"99999999"
	)

	# 余额变化时实时刷新（如果以后加调试按钮 / 改装界面跳回主菜单）。
	MeritLedger.merit_changed.connect(func(total: int, _delta: int):
		if is_instance_valid(_merit_value_text):
			_merit_value_text.text = str(total))
