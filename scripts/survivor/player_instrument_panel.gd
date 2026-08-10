class_name PlayerInstrumentPanel
extends Control

const HudPreferencesScript := preload("res://scripts/ui/hud_preferences.gd")
const TerminalGridOverlayScript := preload("res://scripts/ui/terminal_grid_overlay.gd")
const TerminalTextScript := preload("res://scripts/ui/terminal_text.gd")
const INFO_FONT_SOURCE := preload("res://resources/fonts/Silkscreen-Regular.ttf")
const DISPLAY_FONT_SOURCE := preload("res://resources/fonts/ChakraPetch-Bold.ttf")

## 生存模式右侧玩家仪表。纯显示、鼠标穿透；每条信息行只使用自身左上角局部坐标。
const U_SIZE := Vector2(40.0, 18.0)
const Q_SIZE := Vector2(18.0, 18.0)
const DECORATIVE_HALF_U_HEIGHT := U_SIZE.y * 0.5
const DECORATIVE_HALF_Q_WIDTH := Q_SIZE.x * 0.5
const CONTENT_X := Q_SIZE.x
const SECONDARY_W := U_SIZE.x * 2.0
const BASE_CONTENT_W := U_SIZE.x * 6.0 + Q_SIZE.x
const PANEL_SIZE := Vector2(CONTENT_X + BASE_CONTENT_W,
	U_SIZE.y * 24.0)
const PRIMARY_VALUE_HEIGHT := U_SIZE.y * 3.0
const SECONDARY_VALUE_HEIGHT := U_SIZE.y * 2.0
const PROGRESS_PANEL_HEIGHT := U_SIZE.y * 2.0
const PROGRESS_INFO_HEIGHT := U_SIZE.y
const PROGRESS_PERCENT_SIZE := Vector2(U_SIZE.x * 2.0, U_SIZE.y * 2.0)
const PROGRESS_INNER_INSET := 4.0
const HP_VALUE_LAYOUT_TEXT := "999"
const G_VALUE_LAYOUT_TEXT := "11.5"
const G_INTEGER_LAYOUT_TEXT := "11"
const G_FRACTION_LAYOUT_TEXT := "9"
const G_INTEGER_ALIGNMENT := HORIZONTAL_ALIGNMENT_CENTER
const ALT_VALUE_LAYOUT_TEXT := "99999"
const SPD_VALUE_LAYOUT_TEXT := "99999"
const SPD_DIGIT_COUNT := 5
const SPD_DIGIT_WIDTH := U_SIZE.x + DECORATIVE_HALF_Q_WIDTH
const SPD_PADDING_ZERO_COLOR := ThemeColors.UI_INACTIVE_DIGIT
const G_INTEGER_DIGIT_COUNT := 2
const FLARE_CURRENT_DIGIT_COUNT := 2
const FLARE_CURRENT_WIDTH := SPD_DIGIT_WIDTH * FLARE_CURRENT_DIGIT_COUNT
const AUTOPILOT_WIDTH := U_SIZE.x * 3.0
const WEAPON_COUNT_MIN_W := U_SIZE.x * 2.0
const WEAPON_COUNT_LAYOUT_TEXT := "9999"
const WEAPON_NAME_W := U_SIZE.x * 2.0
const WEAPON_TITLE_HEIGHT := U_SIZE.y
const WEAPON_SLOT_HEIGHT := U_SIZE.y * 2.0
const WEAPON_AUX_EMPTY_WIDTH := DECORATIVE_HALF_Q_WIDTH
const BLINK_STEP_MS := 500
const RELOAD_BLINK_STEP_MS := 250
const NEW_KEY_FLASH_MS := 5000
const REDRAW_INTERVAL_MS := 50
const FLARE_STAR_COUNT := 10
const FLARE_VALUE_LAYOUT_TEXT := "99"
const PROGRESS_PERCENT_LAYOUT_TEXT := "100%"
const WARNING_YELLOW := Color("f2d34f")
const DANGER_RED := Color("ff493d")
const MANEUVER_NAME_KEYS := {
	&"cobra_skill": "UPGRADE_COBRA_SKILL_NAME",
	&"evasion_herbst": "UPGRADE_EVASION_HERBST_NAME",
	&"manual_dodge": "UPGRADE_MANUAL_DODGE_NAME",
	&"displacement_roll": "UPGRADE_DISPLACEMENT_ROLL_NAME",
	&"vertical_break": "UPGRADE_VERTICAL_BREAK_NAME",
}

var aircraft: Aircraft
var afterburner_charge: AfterburnerCharge
var _last_redraw_ms: int = -REDRAW_INTERVAL_MS
var _info_font: Font
var _display_font: Font
var _localized_font: Font
var _grid_overlay
var primary_value_font_size := 1
var secondary_value_font_size := 1
var spd_digit_font_size := 1
var hp_rect := Rect2()
var hp_value_rect := Rect2()
var hp_title_rect := Rect2()
var hp_current_rect := Rect2()
var hp_separator_rect := Rect2()
var hp_max_rect := Rect2()
var hp_g_rect := Rect2()
var g_title_rect := Rect2()
var g_value_rect := Rect2()
var g_integer_rect := Rect2()
var g_decimal_rect := Rect2()
var g_fraction_rect := Rect2()
var g_decimal_font_size := 1
var spd_rect := Rect2()
var spd_alt_rect := Rect2()
var alt_title_rect := Rect2()
var alt_value_rect := Rect2()
var alt_mode_rect := Rect2()
var spd_speed_rect := Rect2()
var spd_title_rect := Rect2()
var spd_current_rect := Rect2()
var spd_unit_kt_rect := Rect2()
var spd_unit_kmh_rect := Rect2()
var spd_unit_empty_rect := Rect2()
var ab_rect := Rect2()
var ab_title_rect := Rect2()
var ab_percent_rect := Rect2()
var ab_progress_rect := Rect2()
var control_rect := Rect2()
var autopilot_rect := Rect2()
var control_empty_rect := Rect2()
var engage_rect := Rect2()
var fire_rect := Rect2()
var flare_base_rect := Rect2()
var maneuver_base_rect := Rect2()
var weapon_spacer_rect := Rect2()
var weapon_title_rect := Rect2()
var weapon_rect := Rect2()
var weapon_middle_spacer_rect := Rect2()
var weapon_count_width := WEAPON_COUNT_MIN_W
var _flare_max_width := U_SIZE.x
var aligned_content_width := BASE_CONTENT_W
var _manual_flare_key_known := false
var _manual_flare_key_visible := false
var _manual_flare_key_flash_started_ms := -NEW_KEY_FLASH_MS
var weapon_animation_time_override_ms := -1


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
	_configure_layout()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus_mode = Control.FOCUS_NONE
	set_process(false)
	_grid_overlay = TerminalGridOverlayScript.new()
	_grid_overlay.size = size
	add_child(_grid_overlay)


func update_display(ac: Aircraft, charge: AfterburnerCharge) -> void:
	var next_manual_flare_key := manual_flare_key_visible(ac)
	if aircraft != ac:
		_manual_flare_key_known = true
		_manual_flare_key_visible = next_manual_flare_key
	elif _manual_flare_key_known and next_manual_flare_key and not _manual_flare_key_visible:
		_begin_manual_flare_key_flash()
	_manual_flare_key_known = true
	_manual_flare_key_visible = next_manual_flare_key
	aircraft = ac
	afterburner_charge = charge
	var now := Time.get_ticks_msec()
	if now - _last_redraw_ms < REDRAW_INTERVAL_MS:
		return
	_last_redraw_ms = now
	queue_redraw()


func _configure_layout() -> void:
	primary_value_font_size = TerminalTextScript.font_size_for_ink_height(
		_display_font, HP_VALUE_LAYOUT_TEXT, PRIMARY_VALUE_HEIGHT)
	# SPD, G integer digits, and the FLR current value deliberately share this
	# one fixed font size and one fixed digit-cell geometry.
	spd_digit_font_size = int(TerminalTextScript.resolve_font_layout(
		_display_font, "0", Vector2(SPD_DIGIT_WIDTH, PRIMARY_VALUE_HEIGHT)).x)
	g_decimal_font_size = spd_digit_font_size
	secondary_value_font_size = TerminalTextScript.font_size_for_ink_height(
		_display_font, HP_VALUE_LAYOUT_TEXT, SECONDARY_VALUE_HEIGHT)
	weapon_count_width = _expanded_value_width(
		WEAPON_COUNT_LAYOUT_TEXT, secondary_value_font_size, WEAPON_COUNT_MIN_W)

	var hp_current_width := _expanded_value_width(
		HP_VALUE_LAYOUT_TEXT, primary_value_font_size, U_SIZE.x * 3.0)
	var hp_max_width := _expanded_value_width(
		HP_VALUE_LAYOUT_TEXT, secondary_value_font_size, U_SIZE.x)
	var g_integer_width := SPD_DIGIT_WIDTH * float(G_INTEGER_DIGIT_COUNT)
	var g_fraction_width := _expanded_value_width(
		G_FRACTION_LAYOUT_TEXT, secondary_value_font_size, U_SIZE.x)
	var g_width := g_integer_width + Q_SIZE.x + g_fraction_width
	var spd_current_width := SPD_DIGIT_WIDTH * float(SPD_DIGIT_COUNT)
	_flare_max_width = _expanded_value_width(
		FLARE_VALUE_LAYOUT_TEXT, secondary_value_font_size, U_SIZE.x)

	var hp_value_width := hp_current_width + Q_SIZE.x + hp_max_width
	var hp_total_width := hp_value_width + g_width
	var spd_speed_width := spd_current_width + Q_SIZE.x + U_SIZE.x
	var spd_total_width := SECONDARY_W + spd_speed_width
	# The five functional SPD digit boards establish the new alignment baseline.
	# Decorative half-q columns are only applied to later structural fill.
	aligned_content_width = maxf(BASE_CONTENT_W, spd_total_width)
	var flare_width := maxf(
		BASE_CONTENT_W - AUTOPILOT_WIDTH,
		FLARE_CURRENT_WIDTH + Q_SIZE.x + _flare_max_width)
	# AUTOPILOT is a fixed 3u panel. Keep at least one q of structural empty
	# panel between it and FLR so a runtime R key can replace that space.
	aligned_content_width = decorative_aligned_width(aligned_content_width,
		AUTOPILOT_WIDTH + Q_SIZE.x + flare_width)
	var configured_width := maxf(hp_total_width, spd_total_width + Q_SIZE.x)
	configured_width = maxf(configured_width, aligned_content_width + Q_SIZE.x)
	var right_edge := configured_width

	# Every row is laid out from the shared right edge toward the left. Any q-step
	# expansion therefore preserves the screen-side edge of the instrument stack.
	hp_g_rect = Rect2(right_edge - g_width, 0.0, g_width, U_SIZE.y * 4.0)
	g_title_rect = Rect2(hp_g_rect.position, Vector2(hp_g_rect.size.x, U_SIZE.y))
	g_value_rect = Rect2(hp_g_rect.position + Vector2(0.0, U_SIZE.y),
		Vector2(hp_g_rect.size.x, PRIMARY_VALUE_HEIGHT))
	g_integer_rect = Rect2(g_value_rect.position,
		Vector2(g_integer_width, PRIMARY_VALUE_HEIGHT))
	g_decimal_rect = Rect2(
		Vector2(g_integer_rect.end.x, hp_g_rect.end.y - U_SIZE.y), Q_SIZE)
	g_fraction_rect = Rect2(
		Vector2(g_decimal_rect.end.x, hp_g_rect.end.y - SECONDARY_VALUE_HEIGHT),
		Vector2(g_fraction_width, SECONDARY_VALUE_HEIGHT))
	hp_value_rect = Rect2(hp_g_rect.position.x - hp_value_width, 0.0,
		hp_value_width, U_SIZE.y * 4.0)
	hp_title_rect = Rect2(hp_value_rect.position, Vector2(hp_value_rect.size.x, U_SIZE.y))
	hp_max_rect = Rect2(hp_value_rect.end.x - hp_max_width, U_SIZE.y,
		hp_max_width, SECONDARY_VALUE_HEIGHT)
	hp_separator_rect = Rect2(hp_max_rect.position.x - Q_SIZE.x,
		U_SIZE.y, Q_SIZE.x, Q_SIZE.y)
	hp_current_rect = Rect2(hp_separator_rect.position.x - hp_current_width,
		U_SIZE.y, hp_current_width, PRIMARY_VALUE_HEIGHT)
	hp_rect = Rect2(hp_value_rect.position,
		Vector2(hp_g_rect.end.x - hp_value_rect.position.x, U_SIZE.y * 4.0))

	var unit_x := right_edge - U_SIZE.x
	spd_unit_kt_rect = Rect2(unit_x, U_SIZE.y * 5.0, U_SIZE.x, U_SIZE.y)
	spd_unit_kmh_rect = Rect2(unit_x, U_SIZE.y * 6.0, U_SIZE.x, U_SIZE.y)
	spd_unit_empty_rect = Rect2(unit_x, U_SIZE.y * 7.0, U_SIZE.x, U_SIZE.y)
	spd_speed_rect = Rect2(right_edge - spd_speed_width, U_SIZE.y * 4.0,
		spd_speed_width, U_SIZE.y * 4.0)
	spd_title_rect = Rect2(spd_speed_rect.position, Vector2(spd_speed_rect.size.x, U_SIZE.y))
	spd_current_rect = Rect2(unit_x - Q_SIZE.x - spd_current_width,
		U_SIZE.y * 5.0, spd_current_width, PRIMARY_VALUE_HEIGHT)
	spd_alt_rect = Rect2(spd_speed_rect.position.x - SECONDARY_W,
		U_SIZE.y * 4.0, SECONDARY_W, U_SIZE.y * 4.0)
	alt_title_rect = Rect2(spd_alt_rect.position, Vector2(spd_alt_rect.size.x, U_SIZE.y))
	alt_value_rect = Rect2(spd_alt_rect.position + Vector2(0.0, U_SIZE.y),
		Vector2(spd_alt_rect.size.x, SECONDARY_VALUE_HEIGHT))
	alt_mode_rect = Rect2(spd_alt_rect.position + Vector2(0.0, U_SIZE.y * 3.0),
		Vector2(spd_alt_rect.size.x, U_SIZE.y))
	spd_rect = Rect2(spd_alt_rect.position,
		Vector2(right_edge - spd_alt_rect.position.x, U_SIZE.y * 4.0))

	ab_rect = Rect2(right_edge - aligned_content_width, U_SIZE.y * 8.0,
		aligned_content_width, PROGRESS_PANEL_HEIGHT)
	ab_percent_rect = Rect2(ab_rect.end.x - PROGRESS_PERCENT_SIZE.x, ab_rect.position.y,
		PROGRESS_PERCENT_SIZE.x, PROGRESS_PERCENT_SIZE.y)
	ab_title_rect = Rect2(ab_rect.position,
		Vector2(ab_percent_rect.position.x - ab_rect.position.x, PROGRESS_INFO_HEIGHT))
	ab_progress_rect = Rect2(ab_rect.position + Vector2(0.0, PROGRESS_INFO_HEIGHT),
		Vector2(ab_percent_rect.position.x - ab_rect.position.x, U_SIZE.y))

	flare_base_rect = Rect2(right_edge - flare_width, U_SIZE.y * 10.0,
		flare_width, U_SIZE.y * 6.0)
	autopilot_rect = Rect2(right_edge - aligned_content_width,
		flare_base_rect.position.y,
		AUTOPILOT_WIDTH, U_SIZE.y * 6.0)
	control_empty_rect = Rect2(autopilot_rect.end.x, flare_base_rect.position.y,
		flare_base_rect.position.x - autopilot_rect.end.x, U_SIZE.y * 6.0)
	engage_rect = Rect2(autopilot_rect.position,
		Vector2(autopilot_rect.size.x, U_SIZE.y * 3.0))
	fire_rect = Rect2(autopilot_rect.position + Vector2(0.0, U_SIZE.y * 3.0),
		Vector2(autopilot_rect.size.x, U_SIZE.y * 3.0))
	control_rect = Rect2(autopilot_rect.position,
		Vector2(aligned_content_width, U_SIZE.y * 6.0))
	maneuver_base_rect = Rect2(right_edge - aligned_content_width, U_SIZE.y * 16.0,
		aligned_content_width, PROGRESS_PANEL_HEIGHT)
	weapon_spacer_rect = Rect2(right_edge - aligned_content_width, U_SIZE.y * 18.0,
		aligned_content_width, DECORATIVE_HALF_U_HEIGHT)
	weapon_title_rect = Rect2(
		Vector2(right_edge - aligned_content_width, weapon_spacer_rect.end.y),
		Vector2(aligned_content_width, WEAPON_TITLE_HEIGHT))
	weapon_rect = Rect2(
		Vector2(right_edge - aligned_content_width, weapon_title_rect.end.y),
		Vector2(aligned_content_width,
			WEAPON_SLOT_HEIGHT * 2.0 + DECORATIVE_HALF_U_HEIGHT))
	weapon_middle_spacer_rect = Rect2(
		weapon_rect.position + Vector2(0.0, WEAPON_SLOT_HEIGHT),
		Vector2(aligned_content_width, DECORATIVE_HALF_U_HEIGHT))

	var configured_size := Vector2(configured_width, PANEL_SIZE.y)
	custom_minimum_size = configured_size
	size = configured_size


func _expanded_value_width(reference_text: String, font_size: int,
		base_width: float) -> float:
	# Numeric fit is deliberately quantized to a whole q. Decorative alignment
	# uses decorative_aligned_width() and must not weaken this rule.
	return TerminalTextScript.expanded_width_for_fixed_text(
		_display_font, reference_text, font_size, base_width, Q_SIZE.x)


static func decorative_aligned_width(base_width: float, target_width: float) -> float:
	if target_width <= base_width:
		return base_width
	var columns := ceili((target_width - base_width) / DECORATIVE_HALF_Q_WIDTH)
	return base_width + float(columns) * DECORATIVE_HALF_Q_WIDTH


func _draw() -> void:
	var accent: Color = HudPreferencesScript.hud_color()
	var animation_now := _weapon_animation_now_ms()
	var blink_on := int(animation_now / BLINK_STEP_MS) % 2 == 0
	var reload_blink_on := int(animation_now / RELOAD_BLINK_STEP_MS) % 2 == 0
	var has_aircraft := aircraft != null and is_instance_valid(aircraft) and not aircraft.is_destroyed
	var maneuver_visible := maneuver_skill_visible(aircraft) if has_aircraft else false
	var manual_flare_visible := manual_flare_key_visible(aircraft) if has_aircraft else false
	var flare_rect := active_flare_rect(manual_flare_visible)
	var maneuver_rect := active_maneuver_rect(maneuver_visible, manual_flare_visible)
	var engage_row_rect := active_engage_rect(manual_flare_visible)
	var fire_row_rect := active_fire_rect(manual_flare_visible)
	_grid_overlay.line_color = accent
	_grid_overlay.regions = grid_regions(maneuver_visible, manual_flare_visible)

	_draw_module(hp_rect, accent)
	_draw_module(spd_rect, accent)
	_draw_module(ab_rect, accent)
	_draw_module(active_autopilot_rect(manual_flare_visible), accent)
	_draw_module(active_control_empty_rect(manual_flare_visible), accent)
	_draw_module(flare_rect, accent)
	_draw_module(maneuver_rect, accent)
	_draw_module(weapon_spacer_rect, accent)
	_draw_module(weapon_title_rect, accent)
	_draw_module(weapon_row_rect(0), accent)
	_draw_module(weapon_middle_spacer_rect, accent)
	_draw_module(weapon_row_rect(1), accent)
	_draw_keycap_at("Q", keycap_left_of(spd_rect), accent)
	_draw_keycap_at("E", keycap_left_of(ab_rect), accent)
	_draw_keycap_at("G", keycap_left_of(engage_row_rect), accent)
	_draw_keycap_at("F", keycap_left_of(fire_row_rect), accent)
	_draw_keycap_at("T", keycap_left_of(weapon_title_rect), accent)
	if maneuver_visible:
		var r_rect := manual_flare_key_rect() if manual_flare_visible else maneuver_key_rect()
		_draw_keycap_at("R", r_rect, accent,
			manual_flare_visible and manual_flare_key_flash_on())
	if not has_aircraft:
		return

	_draw_flight_data(accent, blink_on)
	_draw_afterburner(accent)
	_draw_toggle_row(engage_row_rect, tr("HUD_ENGAGE"), aircraft.auto_engage_enabled, accent)
	_draw_toggle_row(fire_row_rect, tr("HUD_FIRE"), aircraft.missile_auto_fire, accent)
	_draw_flares(flare_rect, accent)
	if maneuver_visible:
		_draw_maneuver_charge(maneuver_rect, accent)
	var weapon_title := tr("HUD_PRIORITY_WEAPON")
	if weapon_title == "HUD_PRIORITY_WEAPON":
		weapon_title = "PRIORITY WEAPON"
	_draw_localized_text_in_rect(weapon_title, weapon_title_rect, 15,
		accent, false, HORIZONTAL_ALIGNMENT_LEFT)
	_draw_weapons(accent, reload_blink_on)


func _draw_module(rect: Rect2, accent: Color) -> void:
	draw_rect(rect, ThemeColors.UI_BLOCK_BACKGROUND, true)


func _draw_keycap_at(text: String, rect: Rect2, accent: Color,
		inverted: bool = false) -> void:
	draw_rect(rect, accent if inverted else ThemeColors.UI_BLOCK_BACKGROUND, true)
	_draw_text_in_rect(text, rect, 15, Color.BLACK if inverted else accent)


static func keycap_left_of(rect: Rect2) -> Rect2:
	return Rect2(rect.position.x - Q_SIZE.x, rect.position.y, Q_SIZE.x, Q_SIZE.y)


static func toggle_state_rect(rect: Rect2) -> Rect2:
	return Rect2(rect.position + Vector2(0.0, U_SIZE.y),
		Vector2(rect.size.x, U_SIZE.y * 2.0))


func speed_unit_rect(index: int) -> Rect2:
	return spd_unit_kt_rect if index == 0 else spd_unit_kmh_rect


func spd_digit_rect(index: int) -> Rect2:
	return Rect2(
		spd_current_rect.position + Vector2(float(index) * SPD_DIGIT_WIDTH, 0.0),
		Vector2(SPD_DIGIT_WIDTH, spd_current_rect.size.y))


func g_integer_digit_rect(index: int) -> Rect2:
	return Rect2(
		g_integer_rect.position + Vector2(float(index) * SPD_DIGIT_WIDTH, 0.0),
		Vector2(SPD_DIGIT_WIDTH, g_integer_rect.size.y))


func active_flare_rect(_manual_flare_visible: bool) -> Rect2:
	return flare_base_rect


func active_maneuver_rect(_maneuver_visible: bool,
		_manual_flare_visible: bool) -> Rect2:
	return maneuver_base_rect


func active_engage_rect(manual_flare_visible: bool) -> Rect2:
	var parent := active_autopilot_rect(manual_flare_visible)
	return Rect2(parent.position, Vector2(parent.size.x, U_SIZE.y * 3.0))


func active_fire_rect(manual_flare_visible: bool) -> Rect2:
	var parent := active_autopilot_rect(manual_flare_visible)
	return Rect2(parent.position + Vector2(0.0, U_SIZE.y * 3.0),
		Vector2(parent.size.x, U_SIZE.y * 3.0))


func active_autopilot_rect(manual_flare_visible: bool) -> Rect2:
	# The two AUTOPILOT rows are one fixed 3u-wide parent. Runtime insertion
	# consumes the structural empty panel instead of moving this parent.
	return autopilot_rect


func active_control_empty_rect(manual_flare_visible: bool) -> Rect2:
	var width := control_empty_rect.size.x
	if manual_flare_visible:
		width = maxf(0.0, width - Q_SIZE.x)
	return Rect2(control_empty_rect.position,
		Vector2(width, control_empty_rect.size.y))


func manual_flare_key_rect() -> Rect2:
	return Rect2(flare_base_rect.position - Vector2(Q_SIZE.x, 0.0), Q_SIZE)


func maneuver_key_rect() -> Rect2:
	return keycap_left_of(maneuver_base_rect)


static func manual_flare_key_visible(ac: Aircraft) -> bool:
	return ac != null and is_instance_valid(ac) and not ac.is_destroyed \
		and ac.manual_dodge_active


func manual_flare_key_flash_on(now_ms: int = -1) -> bool:
	if now_ms < 0:
		now_ms = Time.get_ticks_msec()
	var elapsed := now_ms - _manual_flare_key_flash_started_ms
	return elapsed >= 0 and elapsed < NEW_KEY_FLASH_MS \
		and int(elapsed / BLINK_STEP_MS) % 2 == 0


func _begin_manual_flare_key_flash() -> void:
	_manual_flare_key_flash_started_ms = Time.get_ticks_msec()
	queue_redraw()


func debug_grant_manual_flare_skill() -> bool:
	if aircraft == null or not is_instance_valid(aircraft) or aircraft.is_destroyed:
		return false
	aircraft.vertical_break_active = false
	aircraft.displacement_roll_active = false
	aircraft.cobra_skill_active = false
	aircraft.evasion_herbst_active = false
	aircraft.manual_dodge_active = true
	_manual_flare_key_known = true
	_manual_flare_key_visible = true
	_begin_manual_flare_key_flash()
	return true


static func flare_title_rect(rect: Rect2) -> Rect2:
	return Rect2(rect.position, Vector2(rect.size.x, U_SIZE.y))


static func flare_current_rect(rect: Rect2) -> Rect2:
	return Rect2(rect.position + Vector2(0.0, U_SIZE.y),
		Vector2(FLARE_CURRENT_WIDTH, U_SIZE.y * 3.0))


static func flare_current_digit_rect(rect: Rect2, index: int) -> Rect2:
	var current := flare_current_rect(rect)
	return Rect2(
		current.position + Vector2(float(index) * SPD_DIGIT_WIDTH, 0.0),
		Vector2(SPD_DIGIT_WIDTH, current.size.y))


static func flare_separator_rect(rect: Rect2) -> Rect2:
	return Rect2(flare_current_rect(rect).end.x, rect.position.y + U_SIZE.y,
		Q_SIZE.x, Q_SIZE.y)


static func flare_max_rect(rect: Rect2, max_width: float = U_SIZE.x) -> Rect2:
	return Rect2(flare_separator_rect(rect).end.x, rect.position.y + U_SIZE.y,
		max_width, U_SIZE.y * 2.0)


static func flare_stars_rect(rect: Rect2) -> Rect2:
	return Rect2(rect.position + Vector2(0.0, U_SIZE.y * 4.0),
		Vector2(rect.size.x, maxf(0.0, rect.size.y - U_SIZE.y * 4.0)))


func maneuver_title_rect(rect: Rect2) -> Rect2:
	return Rect2(rect.position,
		Vector2(rect.size.x - PROGRESS_PERCENT_SIZE.x, PROGRESS_INFO_HEIGHT))


func maneuver_percent_rect(rect: Rect2) -> Rect2:
	return Rect2(rect.end.x - PROGRESS_PERCENT_SIZE.x, rect.position.y,
		PROGRESS_PERCENT_SIZE.x, PROGRESS_PERCENT_SIZE.y)


static func maneuver_progress_rect(rect: Rect2) -> Rect2:
	return Rect2(rect.position + Vector2(0.0, PROGRESS_INFO_HEIGHT),
		Vector2(rect.size.x - PROGRESS_PERCENT_SIZE.x, U_SIZE.y))


func small_title_regions(flare_rect: Rect2) -> Array[Rect2]:
	return [
		hp_title_rect,
		g_title_rect,
		alt_title_rect,
		spd_title_rect,
		flare_title_rect(flare_rect),
		weapon_title_rect,
	]


func grid_regions(maneuver_visible: bool,
		manual_flare_visible: bool = false) -> Array[Rect2]:
	var flare_rect := active_flare_rect(manual_flare_visible)
	var maneuver_rect := active_maneuver_rect(maneuver_visible, manual_flare_visible)
	var engage_row_rect := active_engage_rect(manual_flare_visible)
	var fire_row_rect := active_fire_rect(manual_flare_visible)
	var result: Array[Rect2] = [
		hp_rect,
		hp_value_rect,
		hp_g_rect,
		spd_rect,
		spd_alt_rect,
		alt_mode_rect,
		spd_speed_rect,
		g_decimal_rect,
		speed_unit_rect(0),
		speed_unit_rect(1),
		spd_unit_empty_rect,
		ab_rect,
		ab_title_rect,
		ab_percent_rect,
		ab_progress_rect,
		active_autopilot_rect(manual_flare_visible),
		active_control_empty_rect(manual_flare_visible),
		engage_row_rect,
		toggle_state_rect(engage_row_rect),
		fire_row_rect,
		toggle_state_rect(fire_row_rect),
		flare_rect,
		flare_stars_rect(flare_rect),
		maneuver_rect,
		maneuver_title_rect(maneuver_rect),
		maneuver_percent_rect(maneuver_rect),
		maneuver_progress_rect(maneuver_rect),
		weapon_spacer_rect,
		weapon_row_rect(0),
		weapon_middle_spacer_rect,
		weapon_row_rect(1),
		keycap_left_of(spd_rect),
		keycap_left_of(ab_rect),
		keycap_left_of(engage_row_rect),
		keycap_left_of(fire_row_rect),
		keycap_left_of(weapon_title_rect),
	]
	if maneuver_visible:
		result.append(manual_flare_key_rect() if manual_flare_visible else maneuver_key_rect())
	result.append_array(small_title_regions(flare_rect))
	for digit_index in range(SPD_DIGIT_COUNT):
		result.append(spd_digit_rect(digit_index))
	for digit_index in range(G_INTEGER_DIGIT_COUNT):
		result.append(g_integer_digit_rect(digit_index))
	for digit_index in range(FLARE_CURRENT_DIGIT_COUNT):
		result.append(flare_current_digit_rect(flare_rect, digit_index))
	for row in range(2):
		result.append(weapon_count_rect(row))
		result.append(weapon_empty_rect(row))
		result.append(weapon_aux_empty_rect(row))
		result.append(weapon_reload_progress_rect(row))
		result.append(weapon_name_rect(row))
	return result


func _draw_flight_data(accent: Color, blink_on: bool) -> void:
	var current_hp := ceili(aircraft.hp)
	var max_hp := ceili(aircraft.params.max_hp) if aircraft.params else current_hp
	_draw_text_in_rect("HP", hp_title_rect, 15, accent, false,
		HORIZONTAL_ALIGNMENT_LEFT)
	_draw_text_in_rect(str(current_hp), hp_current_rect, primary_value_font_size, accent, true,
		HORIZONTAL_ALIGNMENT_CENTER, HP_VALUE_LAYOUT_TEXT)
	_draw_text_in_rect("/", hp_separator_rect, 0, accent, true)
	_draw_text_in_rect(str(max_hp), hp_max_rect, secondary_value_font_size, accent, true,
		HORIZONTAL_ALIGNMENT_CENTER, HP_VALUE_LAYOUT_TEXT)
	_draw_text_in_rect("G", g_title_rect, 15, accent, false,
		HORIZONTAL_ALIGNMENT_LEFT)
	var g_digits := formatted_two_digit_value(floori(absf(aircraft.g_load)))
	for digit_index in range(G_INTEGER_DIGIT_COUNT):
		var digit_color := shared_digit_color(g_digits, digit_index, accent)
		_draw_text_in_rect(g_digits.substr(digit_index, 1),
			g_integer_digit_rect(digit_index), spd_digit_font_size, digit_color, true,
			HORIZONTAL_ALIGNMENT_CENTER, "9")
	var g_fraction := str(absi(roundi(aircraft.g_load * 10.0)) % 10)
	_draw_text_in_rect(".", g_decimal_rect, g_decimal_font_size, accent, true)
	_draw_text_in_rect(g_fraction, g_fraction_rect, secondary_value_font_size, accent, true,
		HORIZONTAL_ALIGNMENT_CENTER, G_FRACTION_LAYOUT_TEXT)

	_draw_altitude_preference(accent)
	var speed_title := "STALL" if aircraft.is_stalled and blink_on else "SPD"
	var speed_title_color := DANGER_RED if speed_title == "STALL" else accent
	_draw_text_in_rect(speed_title, spd_title_rect, 15, speed_title_color, false,
		HORIZONTAL_ALIGNMENT_LEFT)
	var speed_kmh := aircraft.speed * 3.6
	var speed_value := HudPreferencesScript.speed_value(speed_kmh)
	var speed_digits := formatted_speed_digits(speed_value)
	var speed_overflow := speed_value_overflows(speed_value)
	for digit_index in range(SPD_DIGIT_COUNT):
		var digit_color := speed_digit_color(
			speed_digits, digit_index, speed_overflow, blink_on, accent)
		_draw_text_in_rect(speed_digits.substr(digit_index, 1),
			spd_digit_rect(digit_index), spd_digit_font_size, digit_color, true,
			HORIZONTAL_ALIGNMENT_CENTER, "9")
	_draw_unit_cell(speed_unit_rect(0), "KT",
		HudPreferencesScript.uses_knots(), accent)
	_draw_unit_cell(speed_unit_rect(1), "KM/H",
		not HudPreferencesScript.uses_knots(), accent)


func _draw_altitude_preference(accent: Color) -> void:
	_draw_text_in_rect("ALT", alt_title_rect, 15, accent, false,
		HORIZONTAL_ALIGNMENT_LEFT)
	_draw_text_in_rect(str(roundi(aircraft.altitude)), alt_value_rect, 0, accent, true,
		HORIZONTAL_ALIGNMENT_CENTER, ALT_VALUE_LAYOUT_TEXT)
	_draw_localized_text_in_rect(tr(altitude_preference_name_key(aircraft)),
		alt_mode_rect, 12, accent)


func _draw_unit_cell(rect: Rect2, text: String, selected: bool, accent: Color) -> void:
	if selected:
		draw_rect(rect, accent, true)
	_draw_text_in_rect(text, rect, 15, Color.BLACK if selected else accent)


func _draw_afterburner(accent: Color) -> void:
	var ratio := 1.0
	if afterburner_charge != null:
		ratio = clampf(afterburner_charge.ratio(), 0.0, 1.0)
	var text_color := progress_color(ratio, accent)
	_draw_localized_text_in_rect(tr("HUD_AFTERBURNER"), ab_title_rect, 15,
		text_color, true, HORIZONTAL_ALIGNMENT_LEFT)
	_draw_text_in_rect("%d%%" % roundi(ratio * 100.0), ab_percent_rect,
		0, text_color, true, HORIZONTAL_ALIGNMENT_RIGHT,
		PROGRESS_PERCENT_LAYOUT_TEXT)
	_draw_progress_bar(ab_progress_rect, ratio, accent)


func _draw_toggle_row(rect: Rect2, text: String, enabled: bool, accent: Color) -> void:
	var origin := rect.position
	_draw_text("AUTOPILOT", Vector2(origin.x, origin.y + 14.0), 15, accent,
		HORIZONTAL_ALIGNMENT_CENTER, rect.size.x)
	var state_rect := toggle_state_rect(rect)
	if enabled:
		draw_rect(state_rect, accent, true)
	_draw_localized_text(text, Vector2(state_rect.position.x, state_rect.position.y + 24.0), 18,
		Color.BLACK if enabled else accent, HORIZONTAL_ALIGNMENT_CENTER, state_rect.size.x, true)


func _draw_flares(rect: Rect2, accent: Color) -> void:
	var has_flare := aircraft.params != null and aircraft.params.flare != null
	var color := accent if has_flare else Color(accent, 0.0)
	_draw_text_in_rect("FLR", flare_title_rect(rect), 15, color, false,
		HORIZONTAL_ALIGNMENT_LEFT)
	if has_flare:
		var flare_digits := formatted_two_digit_value(aircraft.flares_remaining)
		for digit_index in range(FLARE_CURRENT_DIGIT_COUNT):
			var digit_color := shared_digit_color(flare_digits, digit_index, color)
			_draw_text_in_rect(flare_digits.substr(digit_index, 1),
				flare_current_digit_rect(rect, digit_index), spd_digit_font_size,
				digit_color, true, HORIZONTAL_ALIGNMENT_CENTER, "9")
		_draw_text_in_rect("/", flare_separator_rect(rect), 0, color, true)
		_draw_text_in_rect(str(aircraft.params.flare.max_flares),
			flare_max_rect(rect, _flare_max_width), secondary_value_font_size, color, true,
			HORIZONTAL_ALIGNMENT_CENTER, FLARE_VALUE_LAYOUT_TEXT)
	if rect.size.y > U_SIZE.y * 3.0:
		_draw_flare_stars(flare_stars_rect(rect), flare_lit_star_count(aircraft), color)


func _draw_flare_stars(rect: Rect2, lit_count: int, accent: Color) -> void:
	var cell_w := rect.size.x / 5.0
	var cell_h := rect.size.y / 2.0
	for i in range(FLARE_STAR_COUNT):
		var row := i / 5
		var col := i % 5
		var color := accent if i < lit_count else Color(accent, 0.16)
		_draw_text_in_rect("*", Rect2(
			rect.position + Vector2(float(col) * cell_w, float(row) * cell_h),
			Vector2(cell_w, cell_h)), 15, color)


func _draw_maneuver_charge(rect: Rect2, accent: Color) -> void:
	var maneuver_id := aircraft.equipped_r_maneuver_id()
	if maneuver_id == &"":
		return
	var name_key: String = MANEUVER_NAME_KEYS.get(maneuver_id, "")
	_draw_localized_text_in_rect(tr(name_key), maneuver_title_rect(rect), 15,
		accent, true, HORIZONTAL_ALIGNMENT_LEFT)
	var ready_ratio := maneuver_charge_ratio(aircraft)
	_draw_text_in_rect("%d%%" % roundi(ready_ratio * 100.0), maneuver_percent_rect(rect),
		0, progress_color(ready_ratio, accent), true,
		HORIZONTAL_ALIGNMENT_RIGHT, PROGRESS_PERCENT_LAYOUT_TEXT)
	_draw_progress_bar(maneuver_progress_rect(rect), ready_ratio, accent)


func _draw_weapons(accent: Color, reload_blink_on: bool) -> void:
	var effective_pref := effective_weapon_preference(aircraft)
	_draw_weapon_row(weapon_row_rect(0), "MSL",
		aircraft.params != null and aircraft.params.missile != null,
		aircraft.missiles_remaining,
		effective_pref == Aircraft.WeaponPreference.PREFER_MISSILE,
		aircraft._missile_reload_active, aircraft.missile_reload_progress,
		accent, reload_blink_on)
	_draw_weapon_row(weapon_row_rect(1), "GUN",
		aircraft.params != null and aircraft.params.gun != null,
		aircraft.ammo,
		effective_pref == Aircraft.WeaponPreference.PREFER_GUN,
		aircraft._gun_reload_active, aircraft.gun_reload_progress,
		accent, reload_blink_on)


func _draw_weapon_row(rect: Rect2, name_text: String, exists: bool, ammo: int, selected: bool,
		reloading: bool, reload_progress: float, accent: Color,
		reload_blink_on: bool) -> void:
	var row_index := 0 if rect.position.y == weapon_rect.position.y else 1
	var count_rect := weapon_count_rect(row_index)
	var name_rect := weapon_name_rect(row_index)
	var content_color := accent if exists else Color(accent, 0.0)
	var selected_inverse := exists and weapon_value_inverted(
		selected, reloading, reload_blink_on)
	var value_text_color := content_color
	if selected_inverse:
		draw_rect(count_rect, accent, true)
		draw_rect(name_rect, accent, true)
		value_text_color = Color.BLACK
	_draw_text_in_rect(str(ammo), count_rect, secondary_value_font_size, value_text_color, true,
		HORIZONTAL_ALIGNMENT_LEFT, WEAPON_COUNT_LAYOUT_TEXT)
	# The name stays in the secondary information tier, but its fixed 2u board
	# is authoritative; resolve the largest whole font size that preserves the
	# complete MSL/GUN abbreviation inside that board.
	_draw_text_in_rect(name_text, name_rect, 0,
		value_text_color, true, HORIZONTAL_ALIGNMENT_CENTER, name_text)
	_draw_progress_bar(weapon_reload_progress_rect(row_index), reload_progress,
		accent, true, reloading and reload_blink_on, false)


func _draw_progress_bar(rect: Rect2, ratio: float, accent: Color,
		vertical: bool = false, visible_fill: bool = true,
		use_progress_color: bool = true) -> void:
	if not visible_fill:
		return
	var clamped := clampf(ratio, 0.0, 1.0)
	var track := progress_inner_track(rect)
	var color := progress_color(clamped, accent) if use_progress_color else accent
	if clamped <= 0.0:
		return
	var fill := track
	if vertical:
		fill.size.y *= clamped
		fill.position.y = track.end.y - fill.size.y
	else:
		fill.size.x *= clamped
	draw_rect(fill, color, true)


static func progress_inner_track(rect: Rect2) -> Rect2:
	return rect.grow(-PROGRESS_INNER_INSET)


func weapon_row_rect(index: int) -> Rect2:
	var row_h := WEAPON_SLOT_HEIGHT
	var row_y := weapon_rect.position.y
	if index > 0:
		row_y += row_h + DECORATIVE_HALF_U_HEIGHT
	return Rect2(Vector2(weapon_rect.position.x, row_y),
		Vector2(weapon_rect.size.x, row_h))


func weapon_count_rect(index: int) -> Rect2:
	var row := weapon_row_rect(index)
	return Rect2(row.position, Vector2(weapon_count_width, row.size.y))


func weapon_name_rect(index: int) -> Rect2:
	var row := weapon_row_rect(index)
	return Rect2(Vector2(row.end.x - WEAPON_NAME_W, row.position.y),
		Vector2(WEAPON_NAME_W, row.size.y))


func weapon_reload_progress_rect(index: int) -> Rect2:
	var name := weapon_name_rect(index)
	return Rect2(Vector2(name.position.x - Q_SIZE.x, name.position.y),
		Vector2(Q_SIZE.x, name.size.y))


func weapon_aux_empty_rect(index: int) -> Rect2:
	var progress := weapon_reload_progress_rect(index)
	return Rect2(Vector2(progress.position.x - WEAPON_AUX_EMPTY_WIDTH, progress.position.y),
		Vector2(WEAPON_AUX_EMPTY_WIDTH, progress.size.y))


func weapon_empty_rect(index: int) -> Rect2:
	var row := weapon_row_rect(index)
	var aux_empty := weapon_aux_empty_rect(index)
	return Rect2(Vector2(row.position.x + weapon_count_width, row.position.y),
		Vector2(maxf(0.0, aux_empty.position.x - row.position.x - weapon_count_width), row.size.y))


static func speed_value_overflows(speed_value: int) -> bool:
	return speed_value > 99999


static func formatted_speed_digits(speed_value: int) -> String:
	if speed_value_overflows(speed_value):
		return "99999"
	return "%05d" % maxi(speed_value, 0)


static func formatted_two_digit_value(value: int) -> String:
	return "%02d" % clampi(value, 0, 99)


static func speed_digit_is_padding(digits: String, index: int) -> bool:
	var first_significant := -1
	for digit_index in range(digits.length()):
		if digits.substr(digit_index, 1) != "0":
			first_significant = digit_index
			break
	if first_significant < 0:
		first_significant = digits.length() - 1
	return index < first_significant


static func speed_digit_color(digits: String, index: int, overflow: bool,
		blink_on: bool, accent: Color) -> Color:
	if overflow:
		return DANGER_RED if blink_on else Color(DANGER_RED, 0.0)
	if speed_digit_is_padding(digits, index):
		return SPD_PADDING_ZERO_COLOR
	return accent


static func shared_digit_color(digits: String, index: int, accent: Color) -> Color:
	return SPD_PADDING_ZERO_COLOR if speed_digit_is_padding(digits, index) else accent


static func weapon_value_inverted(selected: bool, reloading: bool, blink_on: bool) -> bool:
	return selected and (not reloading or blink_on)


func _weapon_animation_now_ms() -> int:
	return weapon_animation_time_override_ms if weapon_animation_time_override_ms >= 0 \
		else Time.get_ticks_msec()


static func progress_color(ratio: float, accent: Color) -> Color:
	var clamped := clampf(ratio, 0.0, 1.0)
	if clamped <= 0.20:
		return DANGER_RED
	if clamped <= 0.50:
		return WARNING_YELLOW
	return accent


static func cooldown_ready_ratio(remaining: float, total: float) -> float:
	if total <= 0.0:
		return 0.0
	return clampf(1.0 - remaining / total, 0.0, 1.0)


static func maneuver_skill_visible(ac: Aircraft) -> bool:
	return ac != null and is_instance_valid(ac) and not ac.is_destroyed \
		and ac.equipped_r_maneuver_id() != &""


static func maneuver_charge_ratio(ac: Aircraft) -> float:
	if not maneuver_skill_visible(ac):
		return 0.0
	return cooldown_ready_ratio(ac.r_maneuver_cooldown_remaining(),
		ac.r_maneuver_cooldown_total())


static func altitude_preference_name_key(ac: Aircraft) -> String:
	if ac != null and is_instance_valid(ac) \
		and ac.altitude_preference == Aircraft.AltitudePreference.PREFER_LOW:
		return "TOOLTIP_ALT_LOW_TITLE"
	return "TOOLTIP_ALT_CLIMB_TITLE"


static func effective_weapon_preference(ac: Aircraft) -> int:
	if ac == null or not is_instance_valid(ac) or ac.params == null:
		return -1
	var has_missile := ac.params.missile != null
	var has_gun := ac.params.gun != null
	if has_missile and not has_gun:
		return Aircraft.WeaponPreference.PREFER_MISSILE
	if has_gun and not has_missile:
		return Aircraft.WeaponPreference.PREFER_GUN
	if not has_missile and not has_gun:
		return -1
	return ac.weapon_preference


static func flare_lit_star_count(ac: Aircraft) -> int:
	if ac == null or not is_instance_valid(ac) or ac.params == null or ac.params.flare == null:
		return 0
	if ac.enable_flare_reload and ac.flares_remaining <= 0 and ac.flare_reload_progress > 0.0:
		return clampi(ceili(ac.flare_reload_progress * float(FLARE_STAR_COUNT)), 0, FLARE_STAR_COUNT)
	if ac._flare_cooldown > 0.0:
		return clampi(FLARE_STAR_COUNT - ac.flare_visual_burst_emitted, 0, FLARE_STAR_COUNT)
	return FLARE_STAR_COUNT


func _draw_text_in_rect(text: String, rect: Rect2, fixed_font_size: int, color: Color,
		use_display_font: bool = false,
		alignment: HorizontalAlignment = HORIZONTAL_ALIGNMENT_CENTER,
		layout_text: String = "") -> void:
	var font := _display_font if use_display_font else _info_font
	_draw_font_text_in_rect(font, text, rect, fixed_font_size, color, alignment,
		text if layout_text.is_empty() else layout_text)


func _draw_localized_text_in_rect(text: String, rect: Rect2, fixed_font_size: int,
		color: Color, use_display_font: bool = false,
		alignment: HorizontalAlignment = HORIZONTAL_ALIGNMENT_CENTER) -> void:
	_draw_font_text_in_rect(_localized_font_for(use_display_font), text, rect,
		fixed_font_size, color, alignment, text)


func _draw_font_text_in_rect(font: Font, text: String, rect: Rect2, fixed_font_size: int,
		color: Color, alignment: HorizontalAlignment, layout_text: String) -> void:
	if text.is_empty() or rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return
	var layout := TerminalTextScript.resolve_font_layout(
		font, layout_text, rect.size, fixed_font_size)
	var font_size := int(layout.x)
	var actual_ink := TerminalTextScript.measure_ink_bounds(font, text, font_size)
	var ink_top := actual_ink.x if TerminalTextScript.has_visible_ink(actual_ink) else layout.y
	var ink_bottom := actual_ink.y if TerminalTextScript.has_visible_ink(actual_ink) else layout.z
	var baseline_y := rect.position.y + (rect.size.y - (ink_bottom - ink_top)) * 0.5 - ink_top
	draw_string(font, Vector2(rect.position.x, baseline_y), text,
		alignment, rect.size.x, font_size, color)

func _draw_text(text: String, baseline: Vector2, font_size: int, color: Color,
		alignment: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT, width: float = -1.0,
		use_display_font: bool = false) -> void:
	var font := _display_font if use_display_font else _info_font
	draw_string(font, baseline, text, alignment, width, font_size, color)


func _draw_localized_text(text: String, baseline: Vector2, font_size: int, color: Color,
		alignment: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT, width: float = -1.0,
		use_display_font: bool = false) -> void:
	var font := _localized_font_for(use_display_font)
	draw_string(font, baseline, text, alignment, width, font_size, color)


func _draw_text_top(text: String, top_left: Vector2, font_size: int, color: Color,
		use_display_font: bool = false) -> void:
	_draw_text(text, Vector2(top_left.x, top_left.y + _font_ascent(font_size, use_display_font)),
		font_size, color, HORIZONTAL_ALIGNMENT_LEFT, -1.0, use_display_font)


func _draw_localized_text_top(text: String, top_left: Vector2, font_size: int,
		color: Color, use_display_font: bool = false) -> void:
	var font := _localized_font_for(use_display_font)
	_draw_localized_text(text, Vector2(top_left.x, top_left.y + font.get_ascent(font_size)),
		font_size, color, HORIZONTAL_ALIGNMENT_LEFT, -1.0, use_display_font)


func _draw_text_right(text: String, right_x: float, baseline_y: float, font_size: int,
		color: Color, use_display_font: bool = false) -> void:
	_draw_text(text, Vector2(right_x - _text_width(text, font_size, use_display_font), baseline_y),
		font_size, color, HORIZONTAL_ALIGNMENT_LEFT, -1.0, use_display_font)


func _draw_text_outline(text: String, baseline: Vector2, font_size: int, color: Color,
		outline_color: Color, alignment: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT,
		width: float = -1.0) -> void:
	draw_string_outline(_display_font, baseline, text, alignment, width, font_size,
		2, outline_color)
	draw_string(_display_font, baseline, text, alignment, width, font_size, color)


func _draw_localized_text_outline(text: String, baseline: Vector2, font_size: int, color: Color,
		outline_color: Color, alignment: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT,
		width: float = -1.0) -> void:
	var font := _localized_font_for(true)
	draw_string_outline(font, baseline, text, alignment, width, font_size, 2, outline_color)
	draw_string(font, baseline, text, alignment, width, font_size, color)


func _text_width(text: String, font_size: int, use_display_font: bool = false) -> float:
	var font := _display_font if use_display_font else _info_font
	return font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size).x


func _font_ascent(font_size: int, use_display_font: bool = false) -> float:
	var font := _display_font if use_display_font else _info_font
	return font.get_ascent(font_size)


func _localized_font_for(use_display_font: bool = false) -> Font:
	if uses_theme_font_for_locale(TranslationServer.get_locale()):
		return _localized_font
	return _display_font if use_display_font else _info_font


static func uses_theme_font_for_locale(locale: String) -> bool:
	var normalized := locale.to_lower()
	return normalized.begins_with("zh") or normalized.begins_with("ja") \
		or normalized.begins_with("ko")
