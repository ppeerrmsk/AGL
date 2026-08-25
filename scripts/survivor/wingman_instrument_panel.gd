class_name WingmanInstrumentPanel
extends Control

const HudPreferencesScript := preload("res://scripts/ui/hud_preferences.gd")
const PlayerInstrumentPanelScript := preload("res://scripts/survivor/player_instrument_panel.gd")
const TerminalGridOverlayScript := preload("res://scripts/ui/terminal_grid_overlay.gd")
const INFO_FONT_SOURCE := preload("res://resources/fonts/Silkscreen-Regular.ttf")
const DISPLAY_FONT_SOURCE := preload("res://resources/fonts/ChakraPetch-Bold.ttf")

## 玩家 HUD 上方的僚机 HUD 信息行。纯显示、鼠标穿透；不属于飞机旁的状态栏。
const U_SIZE := Vector2(40.0, 18.0)
const Q_SIZE := Vector2(18.0, 18.0)
const PANEL_WIDTH := Q_SIZE.x + U_SIZE.x * 7.0
const CONTENT_X := Q_SIZE.x
const CONTENT_W := U_SIZE.x * 7.0
const ROW_BODY_TOP := 0.0
const ROW_BODY_HEIGHT := U_SIZE.y * 3.0
const ROW_GAP := 0.0
const ROW_STRIDE := ROW_BODY_TOP + ROW_BODY_HEIGHT + ROW_GAP
const TAB_X := CONTENT_X
const TAB_WIDTH := U_SIZE.x * 3.0
const TAB_HEIGHT := U_SIZE.y
const SLOT_KEY_SIZE := Q_SIZE
const SLOT_FONT_SIZE := 15
const REDRAW_INTERVAL_MS := 50
const BLINK_STEP_MS := 500

var _rows: Array[Dictionary] = []
var _last_redraw_ms: int = -REDRAW_INTERVAL_MS
var _info_font: Font
var _display_font: Font
var _localized_font: Font
var _grid_overlay
var _last_damage_token_by_slot: Dictionary = {}
var _damage_flash_until_by_slot: Dictionary = {}
var _last_damage_draw_phase := -2
var damage_animation_time_override_ms := -1


func _ready() -> void:
	_info_font = INFO_FONT_SOURCE.duplicate() as Font
	_display_font = DISPLAY_FONT_SOURCE.duplicate() as Font
	if _info_font is FontFile:
		(_info_font as FontFile).antialiasing = TextServer.FONT_ANTIALIASING_NONE
		(_info_font as FontFile).subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
	_info_font.fallbacks.append(ThemeDB.fallback_font)
	_display_font.fallbacks.append(ThemeDB.fallback_font)
	_localized_font = get_theme_default_font()
	if _localized_font == null:
		_localized_font = ThemeDB.fallback_font
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus_mode = Control.FOCUS_NONE
	set_process(false)
	_grid_overlay = TerminalGridOverlayScript.new()
	add_child(_grid_overlay)
	_apply_row_count(0)


func update_display(rows: Array) -> void:
	_rows.clear()
	for raw: Variant in rows:
		if raw is Dictionary:
			_rows.append((raw as Dictionary).duplicate())
	_rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("slot", 0)) < int(b.get("slot", 0)))
	_sync_damage_rows(_rows, _damage_animation_now_ms())
	_apply_row_count(_rows.size())
	var now := Time.get_ticks_msec()
	if now - _last_redraw_ms < REDRAW_INTERVAL_MS:
		return
	_last_redraw_ms = now
	queue_redraw()


func _process(_delta: float) -> void:
	var now_ms := _damage_animation_now_ms()
	var phase := damage_shared_phase(now_ms) if any_damage_flash_active(now_ms) else -1
	if phase != _last_damage_draw_phase:
		_last_damage_draw_phase = phase
		queue_redraw()
	if phase < 0:
		set_process(false)


func _sync_damage_rows(rows: Array[Dictionary], now_ms: int) -> void:
	var live_slots: Dictionary = {}
	for row in rows:
		var slot := int(row.get("slot", 0))
		live_slots[slot] = true
		var token := float(row.get("damage_token", -INF))
		var seen := _last_damage_token_by_slot.has(slot)
		var previous := float(_last_damage_token_by_slot.get(slot, -INF))
		_last_damage_token_by_slot[slot] = token
		var is_new_damage := is_finite(token) and (
			(token > previous and seen) or (not seen and bool(row.get("damage_recent", false))))
		if is_new_damage:
			_damage_flash_until_by_slot[slot] = now_ms \
				+ PlayerInstrumentPanelScript.DAMAGE_FLASH_DURATION_MS
			_last_damage_draw_phase = -2
			set_process(true)
	for slot: Variant in _last_damage_token_by_slot.keys():
		if not live_slots.has(slot):
			_last_damage_token_by_slot.erase(slot)
			_damage_flash_until_by_slot.erase(slot)


func any_damage_flash_active(now_ms: int) -> bool:
	for row in _rows:
		if damage_flash_active_for_slot(int(row.get("slot", 0)), now_ms):
			return true
	return false


func damage_flash_active_for_slot(slot: int, now_ms: int) -> bool:
	return now_ms < int(_damage_flash_until_by_slot.get(slot, -1))


func _damage_animation_now_ms() -> int:
	return damage_animation_time_override_ms \
		if damage_animation_time_override_ms >= 0 else Time.get_ticks_msec()


static func damage_shared_phase(now_ms: int) -> int:
	return int(now_ms / PlayerInstrumentPanelScript.DAMAGE_FLASH_STEP_MS) % 2


static func total_height_for_count(count: int) -> float:
	if count <= 0:
		return 0.0
	return ROW_BODY_TOP + ROW_BODY_HEIGHT + float(count - 1) * ROW_STRIDE


func _apply_row_count(count: int) -> void:
	var target_size := Vector2(PANEL_WIDTH, total_height_for_count(count))
	custom_minimum_size = target_size
	size = target_size
	if _grid_overlay != null:
		_grid_overlay.size = target_size
	visible = count > 0


func _draw() -> void:
	var accent: Color = HudPreferencesScript.hud_color()
	var now_ms := _damage_animation_now_ms()
	var blink_on := int(Time.get_ticks_msec() / BLINK_STEP_MS) % 2 == 0
	_grid_overlay.line_color = accent
	_grid_overlay.regions = grid_regions(_rows.size())
	var no_damage_regions: Array[Rect2] = []
	_grid_overlay.override_regions = no_damage_regions
	for index in range(_rows.size()):
		_draw_row(_rows[index], float(index) * ROW_STRIDE, accent, blink_on, now_ms)


func _draw_row(row: Dictionary, row_y: float, base_accent: Color, blink_on: bool,
		now_ms: int) -> void:
	var damage_active := damage_flash_active_for_slot(int(row.get("slot", 0)), now_ms)
	var damage_blue_on := damage_shared_phase(now_ms) == 0
	var hp_value_color := PlayerInstrumentPanelScript.damage_hp_color(
		base_accent, damage_active, damage_blue_on)
	var body := Rect2(CONTENT_X, row_y + ROW_BODY_TOP, CONTENT_W, ROW_BODY_HEIGHT)
	draw_rect(body, ThemeColors.UI_BLOCK_BACKGROUND, true)

	var tab := Rect2(TAB_X, row_y, TAB_WIDTH, TAB_HEIGHT)
	draw_rect(tab, base_accent, true)
	var key_rect := Rect2(Vector2(0.0, row_y), SLOT_KEY_SIZE)
	draw_rect(key_rect, ThemeColors.UI_BLOCK_BACKGROUND, true)
	_draw_text(str(int(row.get("slot", 0))),
		Vector2(key_rect.position.x, key_rect.position.y + 14.0), SLOT_FONT_SIZE,
		base_accent, HORIZONTAL_ALIGNMENT_CENTER, key_rect.size.x, true)
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
		action, HORIZONTAL_ALIGNMENT_RIGHT, action_rect.size.x, action_size, base_accent)
	var kills := int(row.get("kills", 0))
	if kills > 0:
		_draw_text("K", body.position + Vector2(244.0, 17.0), 10, Color(base_accent, 0.72))
		_draw_text(str(kills), body.position + Vector2(257.0, 18.0), 15, base_accent,
			HORIZONTAL_ALIGNMENT_LEFT, -1.0, true)

	_draw_stat(body.position.x + 6.0, body.position.y + 46.0, 70.0, "HP",
		String(row.get("hp", "--/--")), true, false, hp_value_color, blink_on, hp_value_color)
	_draw_stat(body.position.x + 78.0, body.position.y + 46.0, 58.0, "MSL",
		String(row.get("msl", "")), bool(row.get("has_msl", false)),
		bool(row.get("msl_busy", false)), base_accent, blink_on, base_accent)
	_draw_stat(body.position.x + 138.0, body.position.y + 46.0, 62.0, "GUN",
		String(row.get("gun", "")), bool(row.get("has_gun", false)),
		bool(row.get("gun_busy", false)), base_accent, blink_on, base_accent)
	_draw_stat(body.position.x + 202.0, body.position.y + 46.0, 72.0, "FLR",
		String(row.get("flr", "")), bool(row.get("has_flr", false)),
		bool(row.get("flr_busy", false)), base_accent, blink_on, base_accent)


static func grid_regions(count: int) -> Array[Rect2]:
	var result: Array[Rect2] = []
	for index in range(count):
		var row_y := float(index) * ROW_STRIDE
		result.append(Rect2(CONTENT_X, row_y, CONTENT_W, ROW_BODY_HEIGHT))
		result.append(Rect2(TAB_X, row_y, TAB_WIDTH, TAB_HEIGHT))
		result.append(Rect2(Vector2(0.0, row_y), SLOT_KEY_SIZE))
	return result


static func grid_regions_for_row(index: int) -> Array[Rect2]:
	var row_y := float(index) * ROW_STRIDE
	return [
		Rect2(CONTENT_X, row_y, CONTENT_W, ROW_BODY_HEIGHT),
		Rect2(TAB_X, row_y, TAB_WIDTH, TAB_HEIGHT),
		Rect2(Vector2(0.0, row_y), SLOT_KEY_SIZE),
	]


## 每架僚机行都是独立框板；使用固定 slot 作 id，避免阵亡后的行索引变化导致重播。
func reveal_panel_regions() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for index in range(_rows.size()):
		var slot := int(_rows[index].get("slot", index + 1))
		result.append({
			"id": StringName("wingman_%d" % slot),
			"rect": Rect2(
				Vector2(0.0, float(index) * ROW_STRIDE),
				Vector2(PANEL_WIDTH, ROW_BODY_HEIGHT)),
		})
	return result


func _draw_stat(x: float, baseline_y: float, width: float, label_text: String,
		value_text: String, exists: bool, busy: bool, accent: Color, blink_on: bool,
		value_base_color: Color) -> void:
	var alpha := 1.0 if exists else 0.0
	if exists and busy and not blink_on:
		alpha = 0.38
	var label_color := Color(accent, alpha)
	var value_color := Color(value_base_color, alpha)
	_draw_text(label_text, Vector2(x, baseline_y), 10, label_color)
	var label_width := _text_width(label_text, 10, false)
	var value_width := maxf(width - label_width - 4.0, 0.0)
	var value_size := _fit_font_size(value_text, 16, value_width, true)
	_draw_text(value_text, Vector2(x + label_width + 4.0, baseline_y + 1.0), value_size,
		value_color, HORIZONTAL_ALIGNMENT_LEFT, value_width, true)


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
	if PlayerInstrumentPanelScript.uses_theme_font_for_locale(TranslationServer.get_locale()):
		return _localized_font
	return _display_font if use_display_font else _info_font
