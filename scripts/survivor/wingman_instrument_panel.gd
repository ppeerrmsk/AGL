class_name WingmanInstrumentPanel
extends Control

const HudPreferencesScript := preload("res://scripts/ui/hud_preferences.gd")
const INFO_FONT_SOURCE := preload("res://resources/fonts/AcuminPro-Regular.otf")
const DISPLAY_FONT_SOURCE := preload("res://resources/fonts/AcuminProExtraCond-Semibold.otf")

## 玩家仪表上方的僚机信息行。纯显示、鼠标穿透；每架存活僚机对应一个独立线框模块。
const PANEL_WIDTH := 326.0
const CONTENT_X := 28.0
const CONTENT_W := 298.0
const ROW_BODY_TOP := 8.0
const ROW_BODY_HEIGHT := 44.0
const ROW_GAP := 5.0
const ROW_STRIDE := ROW_BODY_TOP + ROW_BODY_HEIGHT + ROW_GAP
const TAB_X := CONTENT_X + 12.0
const TAB_WIDTH := 112.0
const TAB_HEIGHT := 20.0
const SLOT_KEY_SIZE := Vector2(28.0, 26.0)
const SLOT_FONT_SIZE := 21
const REDRAW_INTERVAL_MS := 50
const BLINK_STEP_MS := 500

var _rows: Array[Dictionary] = []
var _last_redraw_ms: int = -REDRAW_INTERVAL_MS
var _info_font: Font
var _display_font: Font
var _localized_font: Font


func _ready() -> void:
	_info_font = INFO_FONT_SOURCE.duplicate() as Font
	_display_font = DISPLAY_FONT_SOURCE.duplicate() as Font
	_info_font.fallbacks.append(ThemeDB.fallback_font)
	_display_font.fallbacks.append(ThemeDB.fallback_font)
	_localized_font = get_theme_default_font()
	if _localized_font == null:
		_localized_font = ThemeDB.fallback_font
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus_mode = Control.FOCUS_NONE
	set_process(false)
	_apply_row_count(0)


func update_display(rows: Array) -> void:
	_rows.clear()
	for raw: Variant in rows:
		if raw is Dictionary:
			_rows.append((raw as Dictionary).duplicate())
	_rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("slot", 0)) < int(b.get("slot", 0)))
	_apply_row_count(_rows.size())
	var now := Time.get_ticks_msec()
	if now - _last_redraw_ms < REDRAW_INTERVAL_MS:
		return
	_last_redraw_ms = now
	queue_redraw()


static func total_height_for_count(count: int) -> float:
	if count <= 0:
		return 0.0
	return ROW_BODY_TOP + ROW_BODY_HEIGHT + float(count - 1) * ROW_STRIDE


func _apply_row_count(count: int) -> void:
	var target_size := Vector2(PANEL_WIDTH, total_height_for_count(count))
	custom_minimum_size = target_size
	size = target_size
	visible = count > 0


func _draw() -> void:
	var accent: Color = HudPreferencesScript.hud_color()
	var blink_on := int(Time.get_ticks_msec() / BLINK_STEP_MS) % 2 == 0
	for index in range(_rows.size()):
		_draw_row(_rows[index], float(index) * ROW_STRIDE, accent, blink_on)


func _draw_row(row: Dictionary, row_y: float, accent: Color, blink_on: bool) -> void:
	var body := Rect2(CONTENT_X, row_y + ROW_BODY_TOP, CONTENT_W, ROW_BODY_HEIGHT)
	draw_rect(body, Color(0.0, 0.0, 0.0, 0.78), true)
	draw_rect(body, accent, false, 2.0)

	var tab := Rect2(TAB_X, row_y, TAB_WIDTH, TAB_HEIGHT)
	draw_rect(tab, accent, true)
	var key_rect := Rect2(tab.position, SLOT_KEY_SIZE)
	draw_rect(key_rect, Color(0.0, 0.0, 0.0, 0.92), true)
	draw_rect(key_rect, accent, false, 2.0)
	_draw_text(str(int(row.get("slot", 0))),
		Vector2(key_rect.position.x, key_rect.position.y + 20.0), SLOT_FONT_SIZE,
		accent, HORIZONTAL_ALIGNMENT_CENTER, key_rect.size.x, true)
	var callsign_text := "%s%s" % [
		"★ " if bool(row.get("is_heir", false)) else "",
		String(row.get("callsign", "---")),
	]
	var callsign_rect := Rect2(
		Vector2(key_rect.end.x + 3.0, tab.position.y),
		Vector2(tab.end.x - key_rect.end.x - 6.0, tab.size.y),
	)
	var callsign_size := _fit_font_size(callsign_text, 15, callsign_rect.size.x, true)
	_draw_text(callsign_text,
		Vector2(callsign_rect.position.x, callsign_rect.position.y + 15.0), callsign_size,
		Color.BLACK, HORIZONTAL_ALIGNMENT_CENTER, callsign_rect.size.x, true)

	var action := String(row.get("action", "---"))
	var action_rect := Rect2(body.position + Vector2(126.0, 2.0), Vector2(112.0, 18.0))
	var action_font := _localized_font_for(true)
	var action_size := _fit_font_size_with_font(action, 16, action_rect.size.x, action_font)
	draw_string(action_font, Vector2(action_rect.position.x, action_rect.position.y + 15.0),
		action, HORIZONTAL_ALIGNMENT_RIGHT, action_rect.size.x, action_size, accent)
	var kills := int(row.get("kills", 0))
	if kills > 0:
		_draw_text("K", body.position + Vector2(244.0, 17.0), 10, Color(accent, 0.72))
		_draw_text(str(kills), body.position + Vector2(257.0, 18.0), 15, accent,
			HORIZONTAL_ALIGNMENT_LEFT, -1.0, true)

	_draw_stat(body.position.x + 8.0, body.position.y + 38.0, 72.0, "HP",
		String(row.get("hp", "--/--")), true, false, accent, blink_on)
	_draw_stat(body.position.x + 82.0, body.position.y + 38.0, 62.0, "MSL",
		String(row.get("msl", "")), bool(row.get("has_msl", false)),
		bool(row.get("msl_busy", false)), accent, blink_on)
	_draw_stat(body.position.x + 148.0, body.position.y + 38.0, 68.0, "GUN",
		String(row.get("gun", "")), bool(row.get("has_gun", false)),
		bool(row.get("gun_busy", false)), accent, blink_on)
	_draw_stat(body.position.x + 220.0, body.position.y + 38.0, 70.0, "FLR",
		String(row.get("flr", "")), bool(row.get("has_flr", false)),
		bool(row.get("flr_busy", false)), accent, blink_on)


func _draw_stat(x: float, baseline_y: float, width: float, label_text: String,
		value_text: String, exists: bool, busy: bool, accent: Color, blink_on: bool) -> void:
	var alpha := 1.0 if exists else 0.0
	if exists and busy and not blink_on:
		alpha = 0.38
	var color := Color(accent, alpha)
	_draw_text(label_text, Vector2(x, baseline_y), 10, color)
	var label_width := _text_width(label_text, 10, false)
	var value_width := maxf(width - label_width - 4.0, 0.0)
	var value_size := _fit_font_size(value_text, 16, value_width, true)
	_draw_text(value_text, Vector2(x + label_width + 4.0, baseline_y + 1.0), value_size,
		color, HORIZONTAL_ALIGNMENT_LEFT, value_width, true)


func _fit_font_size(text: String, preferred_size: int, width: float,
		use_display_font: bool) -> int:
	var font := _display_font if use_display_font else _info_font
	return _fit_font_size_with_font(text, preferred_size, width, font)


func _fit_font_size_with_font(text: String, preferred_size: int, width: float,
		font: Font) -> int:
	var result := preferred_size
	while result > 9 and font.get_string_size(
			text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, result).x > width:
		result -= 1
	return result


func _draw_text(text: String, baseline: Vector2, font_size: int, color: Color,
		alignment: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT, width: float = -1.0,
		use_display_font: bool = false) -> void:
	var font := _display_font if use_display_font else _info_font
	draw_string(font, baseline, text, alignment, width, font_size, color)


func _text_width(text: String, font_size: int, use_display_font: bool) -> float:
	var font := _display_font if use_display_font else _info_font
	return font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size).x


func _localized_font_for(use_display_font: bool = false) -> Font:
	if PlayerInstrumentPanel.uses_theme_font_for_locale(TranslationServer.get_locale()):
		return _localized_font
	return _display_font if use_display_font else _info_font
