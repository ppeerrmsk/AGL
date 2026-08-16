class_name NotificationTerminalBar
extends Control

const HudPreferencesScript := preload("res://scripts/ui/hud_preferences.gd")
const TerminalGridOverlayScript := preload("res://scripts/ui/terminal_grid_overlay.gd")
const TerminalTextScript := preload("res://scripts/ui/terminal_text.gd")

const BAR_HEIGHT := 36.0
const ICON_WIDTH := 36.0
const GRAPHIC_PREFIXES := ["⚡", "⚠", "✓", "★", "⚔", "✈", "⚓", "✚"]

var _icon := "!"
var _body := ""
var _accent := ThemeColors.UI_TERMINAL_GREEN
var _follow_hud_color := true
var _icon_text: TerminalText
var _body_text: TerminalText
var _grid: TerminalGridOverlay


func _init() -> void:
	custom_minimum_size.y = BAR_HEIGHT
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = false


func _ready() -> void:
	_ensure_nodes()
	if _follow_hud_color:
		_sync_accent()
	_layout_children()
	set_process(true)


func configure(message: String, fallback_icon: String = "!",
		accent: Color = Color.TRANSPARENT, follow_hud_color: bool = true) -> void:
	_ensure_nodes()
	_follow_hud_color = follow_hud_color
	_accent = HudPreferencesScript.hud_color() if follow_hud_color else accent
	var parts := split_graphic_prefix(message, fallback_icon)
	_icon = parts[0]
	_body = parts[1]
	_sync_content()


func _process(_delta: float) -> void:
	if _follow_hud_color:
		_sync_accent()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_layout_children()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), ThemeColors.UI_BLOCK_BACKGROUND, true)
	if size.x > 0.0 and size.y > 0.0:
		draw_rect(icon_rect(size), _accent, true)


func _ensure_nodes() -> void:
	if _icon_text != null:
		return
	_icon_text = TerminalTextScript.new()
	_icon_text.font_face = TerminalTextScript.FontFace.THEME
	_icon_text.size_rule = TerminalTextScript.SizeRule.VISIBLE_INK_FILL
	_icon_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_icon_text)

	_body_text = TerminalTextScript.new()
	_body_text.font_face = TerminalTextScript.FontFace.THEME
	_body_text.size_rule = TerminalTextScript.SizeRule.ONE_U_FIXED_15
	_body_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_body_text)

	_grid = TerminalGridOverlayScript.new()
	add_child(_grid)
	_sync_content()
	_layout_children()


func _sync_content() -> void:
	if _icon_text == null:
		return
	_icon_text.text = _icon
	_icon_text.layout_text = _icon
	_icon_text.font_color = ThemeColors.UI_BLOCK_BACKGROUND
	_body_text.text = _body
	_body_text.layout_text = _body
	_body_text.font_color = _accent
	_grid.line_color = _accent
	queue_redraw()


func _sync_accent() -> void:
	var next_accent := HudPreferencesScript.hud_color()
	if next_accent == _accent:
		return
	_accent = next_accent
	_sync_content()


func _layout_children() -> void:
	if _icon_text == null:
		return
	var icon_region := icon_rect(size)
	var body_region := body_rect(size)
	_icon_text.position = icon_region.position
	_icon_text.size = icon_region.size
	_body_text.position = body_region.position
	_body_text.size = body_region.size
	_grid.position = Vector2.ZERO
	_grid.size = size
	_grid.regions = [icon_region, body_region]
	queue_redraw()


static func icon_rect(bar_size: Vector2) -> Rect2:
	return Rect2(Vector2.ZERO, Vector2(minf(ICON_WIDTH, bar_size.x), bar_size.y))


static func body_rect(bar_size: Vector2) -> Rect2:
	var left := minf(ICON_WIDTH, bar_size.x)
	return Rect2(Vector2(left, 0.0), Vector2(maxf(bar_size.x - left, 0.0), bar_size.y))


static func split_graphic_prefix(message: String,
		fallback_icon: String = "!") -> PackedStringArray:
	var stripped := message.strip_edges()
	for prefix in GRAPHIC_PREFIXES:
		if stripped.begins_with(prefix):
			return PackedStringArray([prefix, stripped.trim_prefix(prefix).strip_edges()])
	return PackedStringArray([fallback_icon, stripped])
