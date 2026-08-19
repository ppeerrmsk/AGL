class_name BossArrivalBanner
extends CanvasLayer

## BOSS 登场前导身份横幅（spec ui-transition §2.0.1）。
## 只消费注册表提供的显示 key / 呼号；禁止在这里按 boss id 分支。

const TerminalTextScript := preload("res://scripts/ui/terminal_text.gd")
const TerminalGridOverlayScript := preload("res://scripts/ui/terminal_grid_overlay.gd")

const LAYER := 24
const U_WIDTH := 40.0
const U_HEIGHT := 18.0
const MAIN_MAX_WIDTH := 32.0 * U_WIDTH
const MAIN_HEIGHT := 10.0 * U_HEIGHT
const EDGE_MARGIN := 2.0 * U_WIDTH
const MAIN_TEXT_X := 142.0
const MAIN_NAME_Y := 40.0
const MAIN_NAME_HEIGHT := 54.0
const MAIN_ROLE_Y := 104.0
const MAIN_ROLE_HEIGHT := 18.0
const MAIN_CALLSIGN_Y := 141.0
const MAIN_CALLSIGN_HEIGHT := 18.0
const WINDOW_COUNT := 5
const WINDOW_HEIGHT := 2.0 * U_HEIGHT
## reveal 的归一化节拍：每个警告窗完成压入后，下一个才开始。
const WINDOW_REVEAL_STAGGER := 0.145
const WINDOW_REVEAL_DURATION := 0.140
const MAIN_REVEAL_START := 0.720
const MAIN_REVEAL_DURATION := 0.230
const MOTTO_REVEAL_START := 0.830
const MOTTO_REVEAL_DURATION := 0.140
const PALETTES: Dictionary = {
	"terminal_green": {
		"primary": ThemeColors.UI_TERMINAL_GREEN,
		"secondary": ThemeColors.UI_TERMINAL_GREEN,
		"accent": ThemeColors.UI_WARNING_YELLOW,
		"danger": ThemeColors.UI_DANGER_RED,
		"inverse": ThemeColors.UI_TERMINAL_INVERSE,
		"main_bg": ThemeColors.UI_BLOCK_BACKGROUND,
		"window_bg": Color(0.0, 0.0, 0.0, 0.82),
	},
	"wraith_blue": {
		"primary": ThemeColors.UI_WRAITH_BLUE,
		"secondary": ThemeColors.UI_WRAITH_ICE,
		"accent": ThemeColors.UI_WRAITH_ICE,
		"danger": ThemeColors.UI_WRAITH_DEEP_BLUE,
		"inverse": ThemeColors.UI_WRAITH_INVERSE,
		"main_bg": ThemeColors.UI_WRAITH_BACKGROUND,
		"window_bg": ThemeColors.UI_WRAITH_BACKGROUND,
	},
	"black_star": {
		"primary": Color(0.82, 0.86, 0.88),
		"secondary": Color(0.46, 0.50, 0.53),
		"accent": Color(1.0, 0.58, 0.18),
		"danger": ThemeColors.UI_DANGER_RED,
		"inverse": Color(0.025, 0.03, 0.035),
		"main_bg": Color(0.025, 0.03, 0.035, 0.96),
		"window_bg": Color(0.0, 0.0, 0.0, 0.88),
	},
}
const GLITCH_COLOR_ROLES: Array[String] = [
	"danger", "accent", "primary", "danger", "primary", "danger",
]

var _root: Control
var _motto: TerminalText
var _windows: Array[Dictionary] = []
var _main: Control
var _main_bg: ColorRect
var _main_header_bg: ColorRect
var _main_header: TerminalText
var _name_text: TerminalText
var _role_text: TerminalText
var _callsign_text: TerminalText
var _warning_mark: TerminalText
var _warning_triangle: Polygon2D
var _main_grid: TerminalGridOverlay
var _glitch_bars: Array[ColorRect] = []
var _main_base_position := Vector2.ZERO


func _ready() -> void:
	layer = LAYER
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	visible = false
	get_viewport().size_changed.connect(_layout)


func _build() -> void:
	_root = Control.new()
	_root.name = "BossArrivalBannerRoot"
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_root)

	_motto = _new_text(
		_loc("BOSS_BANNER_MOTTO", "INVADERS MUST DIE"), ThemeColors.UI_TERMINAL_GREEN,
		TerminalText.FontFace.SILKSCREEN, TerminalText.SizeRule.ONE_U_FIXED_15,
		HORIZONTAL_ALIGNMENT_LEFT)
	_root.add_child(_motto)

	for index in range(WINDOW_COUNT):
		_windows.append(_build_warning_window(index))

	_main = Control.new()
	_main.name = "PrimaryIdentityBanner"
	_main.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_main.clip_contents = true
	_root.add_child(_main)

	_main_bg = _new_rect(ThemeColors.UI_BLOCK_BACKGROUND)
	_main.add_child(_main_bg)
	_main_header_bg = _new_rect(ThemeColors.UI_TERMINAL_GREEN)
	_main.add_child(_main_header_bg)

	_main_header = _new_text(
		_loc("BOSS_BANNER_ALERT_HEADER", "UNAUTHORIZED HOSTILE ENTITY"), ThemeColors.UI_TERMINAL_INVERSE,
		TerminalText.FontFace.SILKSCREEN, TerminalText.SizeRule.ONE_U_FIXED_15,
		HORIZONTAL_ALIGNMENT_LEFT)
	_main.add_child(_main_header)

	_name_text = _new_text(
		"MOTHER GOOSE", ThemeColors.UI_TERMINAL_GREEN,
		TerminalText.FontFace.CHAKRA_PETCH_BOLD, TerminalText.SizeRule.VISIBLE_INK_FILL,
		HORIZONTAL_ALIGNMENT_CENTER)
	_name_text.layout_text = "LADON STRIKE GROUP"
	_main.add_child(_name_text)

	_role_text = _new_text(
		"THREAT CLASS // AIRBORNE UAV CARRIER", ThemeColors.UI_TERMINAL_GREEN,
		TerminalText.FontFace.CHAKRA_PETCH_MEDIUM, TerminalText.SizeRule.VISIBLE_INK_FILL,
		HORIZONTAL_ALIGNMENT_CENTER)
	_role_text.layout_text = "THREAT CLASS // AIRBORNE UAV CARRIER"
	_main.add_child(_role_text)

	_callsign_text = _new_text(
		"CALLSIGN // GOOSE", ThemeColors.UI_WARNING_YELLOW,
		TerminalText.FontFace.CHAKRA_PETCH_LIGHT, TerminalText.SizeRule.VISIBLE_INK_FILL,
		HORIZONTAL_ALIGNMENT_CENTER)
	_callsign_text.layout_text = "CALLSIGN // WRAITH"
	_main.add_child(_callsign_text)

	_warning_triangle = Polygon2D.new()
	_warning_triangle.name = "WarningTriangle"
	_warning_triangle.polygon = PackedVector2Array([
		Vector2(0.0, -27.0), Vector2(25.0, 22.0), Vector2(-25.0, 22.0),
	])
	_warning_triangle.color = ThemeColors.UI_WARNING_YELLOW
	_warning_triangle.position = Vector2(70.0, 92.0)
	_main.add_child(_warning_triangle)

	_warning_mark = _new_text(
		"!", ThemeColors.UI_TERMINAL_INVERSE,
		TerminalText.FontFace.CHAKRA_PETCH_BOLD, TerminalText.SizeRule.VISIBLE_INK_FILL,
		HORIZONTAL_ALIGNMENT_CENTER)
	_main.add_child(_warning_mark)

	for bar_data in [
		[ThemeColors.UI_DANGER_RED, Vector2(0.0, 26.0), Vector2(8.0, 118.0)],
		[ThemeColors.UI_WARNING_YELLOW, Vector2(12.0, 42.0), Vector2(4.0, 86.0)],
		[ThemeColors.UI_DANGER_RED, Vector2(0.0, 164.0), Vector2(210.0, 4.0)],
		[ThemeColors.UI_WARNING_YELLOW, Vector2(224.0, 164.0), Vector2(92.0, 4.0)],
		[ThemeColors.UI_TERMINAL_GREEN, Vector2(330.0, 164.0), Vector2(148.0, 4.0)],
		[ThemeColors.UI_DANGER_RED, Vector2(492.0, 164.0), Vector2(54.0, 4.0)],
	]:
		var bar := _new_rect(bar_data[0])
		bar.position = bar_data[1]
		bar.size = bar_data[2]
		_main.add_child(bar)
		_glitch_bars.append(bar)

	_main_grid = TerminalGridOverlayScript.new()
	_main_grid.line_color = ThemeColors.UI_TERMINAL_GREEN
	_main.add_child(_main_grid)
	_layout()


func _build_warning_window(index: int) -> Dictionary:
	var window := Control.new()
	window.name = "SystemWarning%02d" % (index + 1)
	window.mouse_filter = Control.MOUSE_FILTER_IGNORE
	window.clip_contents = true
	_root.add_child(window)

	var bg := _new_rect(Color(0.0, 0.0, 0.0, 0.82))
	window.add_child(bg)
	var title_bg := _new_rect(
		ThemeColors.UI_DANGER_RED if index == WINDOW_COUNT - 1 else ThemeColors.UI_TERMINAL_GREEN)
	window.add_child(title_bg)
	var title := _new_text(
		_loc("BOSS_BANNER_WINDOW_TITLE_FMT", "SYSTEM WARNING // %02d") % (index + 1),
		ThemeColors.UI_TERMINAL_INVERSE,
		TerminalText.FontFace.SILKSCREEN, TerminalText.SizeRule.ONE_U_FIXED_15,
		HORIZONTAL_ALIGNMENT_LEFT)
	window.add_child(title)
	var body := _new_text(
		_loc("BOSS_BANNER_WINDOW_BODY", "FOREIGN PROCESS DETECTED"),
		ThemeColors.UI_WARNING_YELLOW if index >= 3 else ThemeColors.UI_TERMINAL_GREEN,
		TerminalText.FontFace.SILKSCREEN, TerminalText.SizeRule.ONE_U_FIXED_15,
		HORIZONTAL_ALIGNMENT_LEFT)
	window.add_child(body)
	var grid: TerminalGridOverlay = TerminalGridOverlayScript.new()
	grid.line_color = ThemeColors.UI_DANGER_RED if index == WINDOW_COUNT - 1 \
		else ThemeColors.UI_TERMINAL_GREEN
	window.add_child(grid)
	return {
		"root": window,
		"bg": bg,
		"title_bg": title_bg,
		"title": title,
		"body": body,
		"grid": grid,
		"base_position": Vector2.ZERO,
	}


func _new_rect(color: Color) -> ColorRect:
	var rect := ColorRect.new()
	rect.color = color
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rect


func _loc(key: String, fallback: String) -> String:
	var value := tr(key)
	return fallback if value == key or value.is_empty() else value


func _new_text(value: String, color: Color, face: int, rule: int,
		alignment: HorizontalAlignment) -> TerminalText:
	var label: TerminalText = TerminalTextScript.new()
	label.text = value
	label.font_color = color
	label.font_face = face
	label.size_rule = rule
	label.horizontal_alignment = alignment
	return label


func _layout() -> void:
	if _root == null:
		return
	var viewport_size := _root.size
	if viewport_size.x < 1.0 or viewport_size.y < 1.0:
		viewport_size = Vector2(1600.0, 900.0)
	var main_width := maxf(1.0, minf(MAIN_MAX_WIDTH, viewport_size.x - EDGE_MARGIN * 2.0))
	_main.size = Vector2(main_width, MAIN_HEIGHT)
	_main_base_position = Vector2(
		(viewport_size.x - main_width) * 0.5,
		(viewport_size.y - MAIN_HEIGHT) * 0.5,
	)
	_main.position = _main_base_position
	_main.pivot_offset = _main.size * 0.5
	_main_bg.size = _main.size
	_main_header_bg.size = Vector2(main_width, U_HEIGHT)
	_main_header.position = Vector2(10.0, 0.0)
	_main_header.size = Vector2(main_width - 20.0, U_HEIGHT)
	var main_text_width := maxf(1.0, main_width - MAIN_TEXT_X * 2.0)
	_name_text.position = Vector2(MAIN_TEXT_X, MAIN_NAME_Y)
	_name_text.size = Vector2(main_text_width, MAIN_NAME_HEIGHT)
	_role_text.position = Vector2(MAIN_TEXT_X, MAIN_ROLE_Y)
	_role_text.size = Vector2(main_text_width, MAIN_ROLE_HEIGHT)
	_callsign_text.position = Vector2(MAIN_TEXT_X, MAIN_CALLSIGN_Y)
	_callsign_text.size = Vector2(main_text_width, MAIN_CALLSIGN_HEIGHT)
	_warning_mark.position = Vector2(52.0, 67.0)
	_warning_mark.size = Vector2(36.0, 42.0)
	_main_grid.size = _main.size
	_main_grid.regions = [
		Rect2(Vector2.ZERO, _main.size),
		Rect2(Vector2.ZERO, Vector2(main_width, U_HEIGHT)),
		Rect2(Vector2(0.0, 136.0), Vector2(main_width, 32.0)),
	]

	# 长句 motto 需要避开右下方第 5 个级联警告窗；向左借一个 U，
	# 保持左上包装语义并让 Black Star 的完整句子可读。
	_motto.position = Vector2(_main_base_position.x - U_WIDTH,
		_main_base_position.y - 2.0 * U_HEIGHT)
	_motto.size = Vector2(13.0 * U_WIDTH, U_HEIGHT)
	for index in range(_windows.size()):
		var data := _windows[index]
		var width := minf(13.0 * U_WIDTH + index * 2.0 * U_WIDTH, main_width - 3.0 * U_WIDTH)
		var base := _main_base_position + Vector2(
			1.0 * U_WIDTH + index * 1.6 * U_WIDTH,
			-8.0 * U_HEIGHT + index * 1.55 * U_HEIGHT,
		)
		data["base_position"] = base
		var window: Control = data["root"]
		window.position = base
		window.size = Vector2(width, WINDOW_HEIGHT)
		window.pivot_offset = window.size * 0.5
		var bg: ColorRect = data["bg"]
		bg.size = window.size
		var title_bg: ColorRect = data["title_bg"]
		title_bg.size = Vector2(width, U_HEIGHT)
		var title: TerminalText = data["title"]
		title.position = Vector2(8.0, 0.0)
		title.size = Vector2(width - 16.0, U_HEIGHT)
		var body: TerminalText = data["body"]
		body.position = Vector2(10.0, U_HEIGHT)
		body.size = Vector2(width - 20.0, U_HEIGHT)
		var grid: TerminalGridOverlay = data["grid"]
		grid.size = window.size
		grid.regions = [
			Rect2(Vector2.ZERO, window.size),
			Rect2(Vector2(0.0, U_HEIGHT), Vector2(width, U_HEIGHT)),
		]


func show_identity(name_key: String, role_key: String, callsign: String,
		motto_key: String = "BOSS_BANNER_MOTTO",
		palette_id: String = "terminal_green") -> void:
	_apply_palette(palette_id)
	var name_fallback := name_key.trim_prefix("BOSS_BANNER_").trim_suffix("_NAME").replace("_", " ")
	var role_fallback := role_key.trim_prefix("BOSS_BANNER_").trim_suffix("_ROLE").replace("_", " ")
	_name_text.text = _loc(name_key, name_fallback).to_upper()
	_role_text.text = _loc("BOSS_BANNER_ROLE_FMT", "THREAT CLASS // %s") \
		% _loc(role_key, role_fallback).to_upper()
	_callsign_text.text = _loc("BOSS_BANNER_CALLSIGN_FMT", "CALLSIGN // %s") % callsign.to_upper()
	_motto.text = _loc(motto_key, "INVADERS MUST DIE").to_upper()
	_main_header.text = _loc("BOSS_BANNER_ALERT_HEADER", "UNAUTHORIZED HOSTILE ENTITY")
	for index in range(_windows.size()):
		var data := _windows[index]
		(data["title"] as TerminalText).text = \
			_loc("BOSS_BANNER_WINDOW_TITLE_FMT", "SYSTEM WARNING // %02d") % (index + 1)
		(data["body"] as TerminalText).text = \
			_loc("BOSS_BANNER_WINDOW_BODY", "FOREIGN PROCESS DETECTED")
	visible = true
	set_reveal_progress(0.0)


func _apply_palette(palette_id: String) -> void:
	var palette: Dictionary = PALETTES.get(palette_id, PALETTES["terminal_green"])
	var primary: Color = palette["primary"]
	var secondary: Color = palette["secondary"]
	var accent: Color = palette["accent"]
	var danger: Color = palette["danger"]
	var inverse: Color = palette["inverse"]
	_main_bg.color = palette["main_bg"]
	_main_header_bg.color = primary
	_main_header.font_color = inverse
	_name_text.font_color = primary
	_role_text.font_color = secondary
	_callsign_text.font_color = accent
	_motto.font_color = primary
	_warning_triangle.color = accent
	_warning_mark.font_color = inverse
	_main_grid.line_color = primary
	for index in range(_windows.size()):
		var data := _windows[index]
		(data["bg"] as ColorRect).color = palette["window_bg"]
		(data["title_bg"] as ColorRect).color = danger if index == WINDOW_COUNT - 1 else primary
		(data["title"] as TerminalText).font_color = inverse
		(data["body"] as TerminalText).font_color = accent if index >= 3 else secondary
		(data["grid"] as TerminalGridOverlay).line_color = \
			danger if index == WINDOW_COUNT - 1 else primary
	for index in range(_glitch_bars.size()):
		_glitch_bars[index].color = palette[GLITCH_COLOR_ROLES[index]]


static func has_palette(palette_id: String) -> bool:
	return PALETTES.has(palette_id)


func set_reveal_progress(progress: float) -> void:
	visible = true
	var p := clampf(progress, 0.0, 1.0)
	for index in range(_windows.size()):
		var data := _windows[index]
		var local := warning_reveal_progress(index, p)
		var eased := 1.0 - pow(1.0 - local, 3.0)
		var window: Control = data["root"]
		window.modulate.a = eased
		window.scale = Vector2(lerpf(0.78, 1.0, eased), lerpf(0.90, 1.0, eased))
		window.position = data["base_position"] + Vector2(-110.0, -12.0) * (1.0 - eased)

	var main_t := clampf((p - MAIN_REVEAL_START) / MAIN_REVEAL_DURATION, 0.0, 1.0)
	var main_eased := 1.0 - pow(1.0 - main_t, 3.0)
	_main.modulate.a = main_eased
	_main.scale = Vector2(lerpf(0.96, 1.0, main_eased), lerpf(0.72, 1.0, main_eased))
	_main.position = _main_base_position + Vector2(0.0, 24.0 * (1.0 - main_eased))
	var motto_t := clampf((p - MOTTO_REVEAL_START) / MOTTO_REVEAL_DURATION, 0.0, 1.0)
	_motto.modulate.a = 1.0 - pow(1.0 - motto_t, 3.0)
	for index in range(_glitch_bars.size()):
		var pulse := fposmod(p * 17.0 + float(index) * 0.23, 1.0)
		_glitch_bars[index].modulate.a = main_eased * (1.0 if pulse < 0.62 else 0.18)


## 纯函数供无头回归守住“一个完成后再出现下一个”的节拍。
static func warning_reveal_progress(index: int, progress: float) -> float:
	return clampf(
		(progress - float(index) * WINDOW_REVEAL_STAGGER) / WINDOW_REVEAL_DURATION,
		0.0,
		1.0,
	)


func set_dismiss_progress(progress: float) -> void:
	var p := clampf(progress, 0.0, 1.0)
	for index in range(_windows.size()):
		var window: Control = _windows[index]["root"]
		var local := clampf(p * 1.55 - float(WINDOW_COUNT - 1 - index) * 0.08, 0.0, 1.0)
		window.modulate.a = 1.0 - local
		window.scale = Vector2.ONE * lerpf(1.0, 0.96, local)
	var e := p * p * p
	_main.modulate.a = 1.0 - e
	_main.scale = Vector2(lerpf(1.0, 1.04, e), lerpf(1.0, 0.08, e))
	_main.position = _main_base_position
	_motto.modulate.a = 1.0 - clampf(p * 1.7, 0.0, 1.0)
	if p >= 0.999:
		hide_immediately()


func hide_immediately() -> void:
	visible = false
	_main.modulate = Color.WHITE
	_main.scale = Vector2.ONE
	_main.position = _main_base_position
	_motto.modulate = Color.WHITE
	for data in _windows:
		var window: Control = data["root"]
		window.modulate = Color.WHITE
		window.scale = Vector2.ONE
		window.position = data["base_position"]


func is_showing() -> bool:
	return visible
