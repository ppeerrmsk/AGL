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
	U_SIZE.y * 31.0)
const STATUS_ROW_HEIGHT := U_SIZE.y
const KILL_FLASH_STEP_MS := 180
const KILL_FLASH_COUNT := 2
const KILL_FLASH_DURATION_MS := KILL_FLASH_STEP_MS * KILL_FLASH_COUNT * 2
const PRIMARY_VALUE_HEIGHT := U_SIZE.y * 3.0
const SECONDARY_VALUE_HEIGHT := U_SIZE.y * 2.0
const COMPACT_VALUE_HEIGHT := U_SIZE.y * 2.0
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
const THREE_U_DIGIT_WIDTH := U_SIZE.x + DECORATIVE_HALF_Q_WIDTH
const TWO_U_DIGIT_WIDTH := U_SIZE.x
const SPD_DIGIT_WIDTH := Q_SIZE.x * 2.0
const SPD_PADDING_ZERO_COLOR := ThemeColors.UI_INACTIVE_DIGIT
const HP_DIGIT_COUNT := 3
const ALT_DIGIT_COUNT := 5
const G_INTEGER_DIGIT_COUNT := 2
const FLARE_CURRENT_DIGIT_COUNT := 2
const FLARE_CURRENT_WIDTH := THREE_U_DIGIT_WIDTH * FLARE_CURRENT_DIGIT_COUNT
const AUTOPILOT_WIDTH := U_SIZE.x * 3.0
const WEAPON_COUNT_MIN_W := U_SIZE.x * 2.0
const WEAPON_COUNT_LAYOUT_TEXT := "9999"
const WEAPON_NAME_W := U_SIZE.x * 2.0
const WEAPON_TITLE_HEIGHT := U_SIZE.y
const WEAPON_SLOT_HEIGHT := U_SIZE.y * 3.0
const WEAPON_AUX_EMPTY_WIDTH := DECORATIVE_HALF_Q_WIDTH
const SPECIAL_WEAPON_TITLE_HEIGHT := U_SIZE.y
const SPECIAL_WEAPON_SLOT_HEIGHT := U_SIZE.y * 2.0
const SPECIAL_WEAPON_COLUMNS := 2
const SPECIAL_WEAPON_NAME_WIDTH := U_SIZE.x * 2.0
const SPECIAL_WEAPON_NAME_LAYOUT_TEXT := "QMAAM"
const WEAPON_RELOAD_INFO_HEIGHT := U_SIZE.y * 2.0
const WEAPON_RELOAD_VALUE_SIZE := Vector2(U_SIZE.x * 2.0, U_SIZE.y * 2.0)
const BLINK_STEP_MS := 500
const RELOAD_BLINK_STEP_MS := 250
const NEW_KEY_FLASH_MS := 5000
const REDRAW_INTERVAL_MS := 50
const FLARE_STAR_COUNT := 10
const FLARE_VALUE_LAYOUT_TEXT := "99"
const PROGRESS_PERCENT_LAYOUT_TEXT := "100%"
const PROGRESS_SECONDS_LAYOUT_TEXT := "100s"
const ALT_STATUS_WIDTH := U_SIZE.x
const ALT_GAUGE_WIDTH := U_SIZE.x * 2.0 + Q_SIZE.x
const ALT_GAUGE_MIN_DEGREES := 20.0
const ALT_GAUGE_LOW_MAX_DEGREES := 85.0
const ALT_GAUGE_HIGH_MIN_DEGREES := 95.0
const ALT_GAUGE_MAX_DEGREES := 160.0
const ALT_GAUGE_REFERENCE_ALTITUDE := 20000.0
const ALT_GAUGE_NEEDLE_SPEED := 120.0
const ALT_GAUGE_ARC_WIDTH := 3.0
const ALT_GAUGE_NEEDLE_WIDTH := 6.0
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
var g_integer_font_size := 1
var g_fraction_font_size := 1
var hp_rect := Rect2()
var status_rect := Rect2()
var cloud_status_rect := Rect2()
var kill_status_rect := Rect2()
var hp_value_rect := Rect2()
var hp_title_rect := Rect2()
var hp_current_rect := Rect2()
var hp_separator_rect := Rect2()
var hp_max_rect := Rect2()
var hp_empty_rect := Rect2()
var hp_decorative_rect := Rect2()
var g_rect := Rect2()
var g_title_rect := Rect2()
var g_value_rect := Rect2()
var g_integer_rect := Rect2()
var g_decimal_rect := Rect2()
var g_fraction_rect := Rect2()
var g_decimal_font_size := 1
var spd_rect := Rect2()
var spd_speed_rect := Rect2()
var spd_title_rect := Rect2()
var spd_current_rect := Rect2()
var spd_blank_rect := Rect2()
var spd_unit_kt_rect := Rect2()
var spd_unit_kmh_rect := Rect2()
var spd_decorative_rect := Rect2()
var alt_rect := Rect2()
var alt_title_rect := Rect2()
var alt_gauge_rect := Rect2()
var alt_value_rect := Rect2()
var alt_mode_high_rect := Rect2()
var alt_mode_low_rect := Rect2()
var alt_mode_empty_rect := Rect2()
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
var special_weapon_spacer_rect := Rect2()
var special_weapon_title_rect := Rect2()
var special_weapon_rect := Rect2()
var weapon_count_width := WEAPON_COUNT_MIN_W
var weapon_name_font_size := 1
var _flare_max_width := U_SIZE.x
var aligned_content_width := BASE_CONTENT_W
var _manual_flare_key_known := false
var _manual_flare_key_visible := false
var _manual_flare_key_flash_started_ms := -NEW_KEY_FLASH_MS
var weapon_animation_time_override_ms := -1
var _special_weapon_rows: Array[Dictionary] = []
var _altimeter_needle_degrees := ALT_GAUGE_MIN_DEGREES
var _altimeter_needle_initialized := false
var _status_initialized := false
var _in_cloud := false
var _status_kill_count := 0
var _kill_flash_started_ms := -KILL_FLASH_DURATION_MS


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
	set_process(true)
	_grid_overlay = TerminalGridOverlayScript.new()
	_grid_overlay.size = size
	add_child(_grid_overlay)


func update_display(ac: Aircraft, charge: AfterburnerCharge) -> void:
	var next_special_weapon_rows := special_weapon_rows(ac)
	var special_weapon_count_changed := (
		next_special_weapon_rows.size() != _special_weapon_rows.size())
	_special_weapon_rows = next_special_weapon_rows
	if special_weapon_count_changed:
		_configure_layout()
	var next_manual_flare_key := manual_flare_key_visible(ac)
	if aircraft != ac:
		_manual_flare_key_known = true
		_manual_flare_key_visible = next_manual_flare_key
		_altimeter_needle_initialized = false
	elif _manual_flare_key_known and next_manual_flare_key and not _manual_flare_key_visible:
		_begin_manual_flare_key_flash()
	_manual_flare_key_known = true
	_manual_flare_key_visible = next_manual_flare_key
	aircraft = ac
	afterburner_charge = charge
	if aircraft != null and is_instance_valid(aircraft) and not aircraft.is_destroyed \
			and not _altimeter_needle_initialized:
		_altimeter_needle_degrees = altimeter_target_degrees(
			aircraft.altitude,
			aircraft.altitude_preference == Aircraft.AltitudePreference.PREFER_LOW)
		_altimeter_needle_initialized = true
	var now := Time.get_ticks_msec()
	if now - _last_redraw_ms < REDRAW_INTERVAL_MS:
		return
	_last_redraw_ms = now
	queue_redraw()


func update_status(in_cloud: bool, kills: int) -> void:
	var safe_kills := maxi(kills, 0)
	if _status_initialized and safe_kills > _status_kill_count:
		_kill_flash_started_ms = Time.get_ticks_msec()
	_status_initialized = true
	if _in_cloud == in_cloud and _status_kill_count == safe_kills:
		return
	_in_cloud = in_cloud
	_status_kill_count = safe_kills
	queue_redraw()


func _process(delta: float) -> void:
	if kill_flash_active():
		queue_redraw()
	elif _kill_flash_started_ms >= 0:
		# Redraw the first frame after the second pulse so the inverse board cannot stick.
		_kill_flash_started_ms = -1
		queue_redraw()
	if aircraft == null or not is_instance_valid(aircraft) or aircraft.is_destroyed:
		return
	var target := altimeter_target_degrees(
		aircraft.altitude, aircraft.altitude_preference == Aircraft.AltitudePreference.PREFER_LOW)
	if not _altimeter_needle_initialized:
		_altimeter_needle_degrees = target
		_altimeter_needle_initialized = true
		queue_redraw()
		return
	var next_angle := move_toward(
		_altimeter_needle_degrees, target, ALT_GAUGE_NEEDLE_SPEED * delta)
	if not is_equal_approx(next_angle, _altimeter_needle_degrees):
		_altimeter_needle_degrees = next_angle
		queue_redraw()


func _configure_layout() -> void:
	var previous_size := size
	var preserve_screen_side_anchor := is_inside_tree() and previous_size.x > 0.0 \
		and previous_size.y > 0.0
	# HP, ALT, and FLR use the 49 × 54 px three-u digit template. G keeps the
	# general 40 × 36 px two-u template while SPD uses tighter 36 px cells.
	primary_value_font_size = int(TerminalTextScript.resolve_font_layout(
		_display_font, "0", Vector2(THREE_U_DIGIT_WIDTH, PRIMARY_VALUE_HEIGHT)).x)
	spd_digit_font_size = int(TerminalTextScript.resolve_font_layout(
		_display_font, "0", Vector2(SPD_DIGIT_WIDTH, COMPACT_VALUE_HEIGHT)).x)
	g_integer_font_size = int(TerminalTextScript.resolve_font_layout(
		_display_font, "0", Vector2(TWO_U_DIGIT_WIDTH, COMPACT_VALUE_HEIGHT)).x)
	g_decimal_font_size = primary_value_font_size
	g_fraction_font_size = TerminalTextScript.font_size_for_ink_height(
		_display_font, G_FRACTION_LAYOUT_TEXT, U_SIZE.y)
	secondary_value_font_size = TerminalTextScript.font_size_for_ink_height(
		_display_font, HP_VALUE_LAYOUT_TEXT, SECONDARY_VALUE_HEIGHT)
	weapon_count_width = _expanded_value_width(
		WEAPON_COUNT_LAYOUT_TEXT, secondary_value_font_size, WEAPON_COUNT_MIN_W)
	weapon_name_font_size = mini(
		int(TerminalTextScript.resolve_font_layout(_display_font, "MSL",
			Vector2(WEAPON_NAME_W, U_SIZE.y * 2.0)).x),
		int(TerminalTextScript.resolve_font_layout(_display_font, "GUN",
			Vector2(WEAPON_NAME_W, U_SIZE.y * 2.0)).x))

	var hp_current_width := THREE_U_DIGIT_WIDTH * float(HP_DIGIT_COUNT)
	var hp_max_width := _expanded_value_width(
		HP_VALUE_LAYOUT_TEXT, secondary_value_font_size, U_SIZE.x)
	var g_integer_width := TWO_U_DIGIT_WIDTH * float(G_INTEGER_DIGIT_COUNT)
	# The borderless one-u fraction absorbs the remaining 27 px so the compact
	# SPD+G row returns exactly to the nominal 383 px content width.
	var g_fraction_width := Q_SIZE.x + DECORATIVE_HALF_Q_WIDTH
	var g_width := g_integer_width + Q_SIZE.x + g_fraction_width
	var spd_current_width := SPD_DIGIT_WIDTH * float(SPD_DIGIT_COUNT)
	_flare_max_width = _expanded_value_width(
		FLARE_VALUE_LAYOUT_TEXT, secondary_value_font_size, U_SIZE.x)

	var hp_value_width := hp_current_width + Q_SIZE.x + hp_max_width
	# Preserve the previous 383 px nominal content width. The two revised flight
	# rows do not expand the root Control or lower modules.
	var nominal_content_width := SECONDARY_W \
		+ THREE_U_DIGIT_WIDTH * float(SPD_DIGIT_COUNT) + Q_SIZE.x + U_SIZE.x
	# SPD keeps its former group width: all width released by the tighter digit
	# cells is transferred to the structural blank between the digits and units.
	var spd_speed_width := nominal_content_width - g_width
	var spd_blank_width := spd_speed_width - spd_current_width - U_SIZE.x
	var spd_total_width := spd_speed_width + g_width
	aligned_content_width = maxf(BASE_CONTENT_W, nominal_content_width)
	var flare_width := maxf(
		BASE_CONTENT_W - AUTOPILOT_WIDTH,
		FLARE_CURRENT_WIDTH + Q_SIZE.x + _flare_max_width)
	# AUTOPILOT is a fixed 3u panel. Keep at least one q of structural empty
	# panel between it and FLR so a runtime R key can replace that space.
	aligned_content_width = decorative_aligned_width(aligned_content_width,
		AUTOPILOT_WIDTH + Q_SIZE.x + flare_width)
	var configured_width := aligned_content_width + Q_SIZE.x
	var right_edge := configured_width
	var content_left := right_edge - aligned_content_width
	var flight_left := right_edge - spd_total_width
	var alt_total_width := ALT_GAUGE_WIDTH \
		+ THREE_U_DIGIT_WIDTH * float(ALT_DIGIT_COUNT) + ALT_STATUS_WIDTH
	var alt_left := right_edge - alt_total_width

	# Every row is laid out from the shared right edge toward the left. Any q-step
	# expansion therefore preserves the screen-side edge of the instrument stack.
	status_rect = Rect2(content_left, 0.0, aligned_content_width, STATUS_ROW_HEIGHT)
	cloud_status_rect = Rect2(status_rect.position,
		Vector2(status_rect.size.x * 0.5, status_rect.size.y))
	kill_status_rect = Rect2(Vector2(cloud_status_rect.end.x, status_rect.position.y),
		Vector2(status_rect.size.x * 0.5, status_rect.size.y))
	hp_rect = Rect2(content_left, STATUS_ROW_HEIGHT,
		aligned_content_width, U_SIZE.y * 4.0)
	hp_value_rect = Rect2(content_left, STATUS_ROW_HEIGHT, hp_value_width, hp_rect.size.y)
	hp_title_rect = Rect2(hp_rect.position, Vector2(hp_rect.size.x, U_SIZE.y))
	hp_max_rect = Rect2(hp_value_rect.end.x - hp_max_width, hp_rect.position.y + U_SIZE.y,
		hp_max_width, SECONDARY_VALUE_HEIGHT)
	hp_separator_rect = Rect2(hp_max_rect.position.x - Q_SIZE.x,
		hp_rect.position.y + U_SIZE.y, Q_SIZE.x, Q_SIZE.y)
	hp_current_rect = Rect2(hp_separator_rect.position.x - hp_current_width,
		hp_rect.position.y + U_SIZE.y, hp_current_width, PRIMARY_VALUE_HEIGHT)
	hp_empty_rect = Rect2(hp_value_rect.end.x, hp_rect.position.y + U_SIZE.y,
		right_edge - hp_value_rect.end.x, hp_rect.size.y - U_SIZE.y)

	var spd_y := hp_rect.end.y + DECORATIVE_HALF_U_HEIGHT
	spd_rect = Rect2(flight_left, spd_y, spd_total_width, U_SIZE.y * 3.0)
	spd_speed_rect = Rect2(flight_left, spd_y, spd_speed_width, spd_rect.size.y)
	spd_title_rect = Rect2(spd_speed_rect.position,
		Vector2(spd_speed_rect.size.x, U_SIZE.y))
	spd_current_rect = Rect2(spd_speed_rect.position + Vector2(0.0, U_SIZE.y),
		Vector2(spd_current_width, COMPACT_VALUE_HEIGHT))
	spd_blank_rect = Rect2(Vector2(spd_current_rect.end.x, spd_y + U_SIZE.y),
		Vector2(spd_blank_width, COMPACT_VALUE_HEIGHT))
	var unit_x := spd_blank_rect.end.x
	spd_unit_kt_rect = Rect2(unit_x, spd_y + U_SIZE.y, U_SIZE.x, U_SIZE.y)
	spd_unit_kmh_rect = Rect2(unit_x, spd_y + U_SIZE.y * 2.0, U_SIZE.x, U_SIZE.y)

	g_rect = Rect2(spd_speed_rect.end.x, spd_y, g_width, spd_rect.size.y)
	g_title_rect = Rect2(g_rect.position, Vector2(g_rect.size.x, U_SIZE.y))
	g_value_rect = Rect2(g_rect.position + Vector2(0.0, U_SIZE.y),
		Vector2(g_rect.size.x, COMPACT_VALUE_HEIGHT))
	g_integer_rect = Rect2(g_value_rect.position,
		Vector2(g_integer_width, COMPACT_VALUE_HEIGHT))
	g_decimal_rect = Rect2(Vector2(g_integer_rect.end.x, g_rect.end.y - U_SIZE.y), Q_SIZE)
	g_fraction_rect = Rect2(Vector2(g_decimal_rect.end.x, g_rect.end.y - U_SIZE.y),
		Vector2(g_fraction_width, U_SIZE.y))

	hp_decorative_rect = Rect2(
		Vector2(spd_rect.position.x, hp_rect.end.y),
		Vector2(spd_rect.size.x, DECORATIVE_HALF_U_HEIGHT))
	spd_decorative_rect = Rect2(
		Vector2(spd_rect.position.x, spd_rect.end.y),
		Vector2(spd_rect.size.x, DECORATIVE_HALF_U_HEIGHT))

	alt_rect = Rect2(alt_left, spd_decorative_rect.end.y,
		alt_total_width, U_SIZE.y * 4.0)
	alt_title_rect = Rect2(alt_rect.position, Vector2(alt_rect.size.x, U_SIZE.y))
	var altitude_content_y := alt_rect.position.y + U_SIZE.y
	alt_gauge_rect = Rect2(Vector2(alt_left, altitude_content_y),
		Vector2(ALT_GAUGE_WIDTH, PRIMARY_VALUE_HEIGHT))
	alt_value_rect = Rect2(Vector2(alt_gauge_rect.end.x, altitude_content_y),
		Vector2(THREE_U_DIGIT_WIDTH * float(ALT_DIGIT_COUNT), PRIMARY_VALUE_HEIGHT))
	alt_mode_high_rect = Rect2(Vector2(alt_value_rect.end.x, altitude_content_y),
		Vector2(ALT_STATUS_WIDTH, U_SIZE.y))
	alt_mode_low_rect = Rect2(Vector2(alt_value_rect.end.x, alt_mode_high_rect.end.y),
		Vector2(ALT_STATUS_WIDTH, U_SIZE.y))
	alt_mode_empty_rect = Rect2(Vector2(alt_value_rect.end.x, alt_mode_low_rect.end.y),
		Vector2(ALT_STATUS_WIDTH, U_SIZE.y))

	ab_rect = Rect2(right_edge - aligned_content_width, alt_rect.end.y,
		aligned_content_width, PROGRESS_PANEL_HEIGHT)
	ab_percent_rect = Rect2(ab_rect.end.x - PROGRESS_PERCENT_SIZE.x, ab_rect.position.y,
		PROGRESS_PERCENT_SIZE.x, PROGRESS_PERCENT_SIZE.y)
	ab_title_rect = Rect2(ab_rect.position,
		Vector2(ab_percent_rect.position.x - ab_rect.position.x, PROGRESS_INFO_HEIGHT))
	ab_progress_rect = Rect2(ab_rect.position + Vector2(0.0, PROGRESS_INFO_HEIGHT),
		Vector2(ab_percent_rect.position.x - ab_rect.position.x, U_SIZE.y))

	flare_base_rect = Rect2(right_edge - flare_width, ab_rect.end.y,
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
	maneuver_base_rect = Rect2(right_edge - aligned_content_width, flare_base_rect.end.y,
		aligned_content_width, PROGRESS_PANEL_HEIGHT)
	weapon_spacer_rect = Rect2(right_edge - aligned_content_width, maneuver_base_rect.end.y,
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
	var configured_height := PANEL_SIZE.y
	if not _special_weapon_rows.is_empty():
		special_weapon_spacer_rect = Rect2(
			Vector2(right_edge - aligned_content_width, weapon_rect.end.y),
			Vector2(aligned_content_width, DECORATIVE_HALF_U_HEIGHT))
		special_weapon_title_rect = Rect2(
			Vector2(right_edge - aligned_content_width, special_weapon_spacer_rect.end.y),
			Vector2(aligned_content_width, SPECIAL_WEAPON_TITLE_HEIGHT))
		special_weapon_rect = Rect2(
			Vector2(right_edge - aligned_content_width, special_weapon_title_rect.end.y),
			Vector2(aligned_content_width,
				SPECIAL_WEAPON_SLOT_HEIGHT * float(ceili(
					float(_special_weapon_rows.size()) / float(SPECIAL_WEAPON_COLUMNS)))))
		configured_height = special_weapon_rect.end.y
	else:
		special_weapon_spacer_rect = Rect2()
		special_weapon_title_rect = Rect2()
		special_weapon_rect = Rect2()

	var configured_size := Vector2(configured_width, configured_height)
	custom_minimum_size = configured_size
	size = configured_size
	if preserve_screen_side_anchor:
		position += previous_size - configured_size
	if _grid_overlay != null:
		_grid_overlay.size = size


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

	_draw_module(status_rect, accent)
	_draw_module(hp_rect, accent)
	_draw_module(hp_decorative_rect, accent)
	_draw_module(spd_rect, accent)
	_draw_module(spd_decorative_rect, accent)
	_draw_module(alt_rect, accent)
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
	if not _special_weapon_rows.is_empty():
		_draw_module(special_weapon_spacer_rect, accent)
		_draw_module(special_weapon_title_rect, accent)
		for row_index in range(_special_weapon_rows.size()):
			_draw_module(special_weapon_row_rect(row_index), accent)
	_draw_keycap_at("Q", keycap_left_of(alt_rect), accent)
	_draw_keycap_at("E", keycap_left_of(ab_rect), accent)
	_draw_keycap_at("G", keycap_left_of(engage_row_rect), accent)
	_draw_keycap_at("F", keycap_left_of(fire_row_rect), accent)
	_draw_keycap_at("T", keycap_left_of(weapon_title_rect), accent)
	if maneuver_visible:
		var r_rect := manual_flare_key_rect() if manual_flare_visible else maneuver_key_rect()
		_draw_keycap_at("R", r_rect, accent,
			manual_flare_visible and manual_flare_key_flash_on())
	_draw_player_status(accent)
	if not has_aircraft:
		return

	_draw_flight_data(accent, blink_on)
	_draw_afterburner(accent)
	_draw_toggle_row(engage_row_rect, tr(engage_state_key(aircraft.auto_engage_enabled)),
		aircraft.auto_engage_enabled, accent)
	_draw_toggle_row(fire_row_rect, tr(fire_state_key(aircraft.missile_auto_fire)),
		aircraft.missile_auto_fire, accent)
	_draw_flares(flare_rect, accent)
	if maneuver_visible:
		_draw_maneuver_charge(maneuver_rect, accent)
	var weapon_title := tr("HUD_PRIORITY_WEAPON")
	if weapon_title == "HUD_PRIORITY_WEAPON":
		weapon_title = "PRIORITY WEAPON"
	_draw_localized_text_in_rect(weapon_title, weapon_title_rect, 15,
		accent, false, HORIZONTAL_ALIGNMENT_LEFT)
	_draw_weapons(accent, reload_blink_on)
	if not _special_weapon_rows.is_empty():
		_draw_localized_text_in_rect(tr("HUD_SPECIAL_WEAPON"), special_weapon_title_rect,
			15, accent, false, HORIZONTAL_ALIGNMENT_LEFT)
		for row_index in range(_special_weapon_rows.size()):
			_draw_special_weapon_row(row_index, _special_weapon_rows[row_index], accent)


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


func hp_digit_rect(index: int) -> Rect2:
	return Rect2(
		hp_current_rect.position + Vector2(float(index) * THREE_U_DIGIT_WIDTH, 0.0),
		Vector2(THREE_U_DIGIT_WIDTH, hp_current_rect.size.y))


func alt_digit_rect(index: int) -> Rect2:
	return Rect2(
		alt_value_rect.position + Vector2(float(index) * THREE_U_DIGIT_WIDTH, 0.0),
		Vector2(THREE_U_DIGIT_WIDTH, alt_value_rect.size.y))


func g_integer_digit_rect(index: int) -> Rect2:
	return Rect2(
		g_integer_rect.position + Vector2(float(index) * TWO_U_DIGIT_WIDTH, 0.0),
		Vector2(TWO_U_DIGIT_WIDTH, g_integer_rect.size.y))


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
		current.position + Vector2(float(index) * THREE_U_DIGIT_WIDTH, 0.0),
		Vector2(THREE_U_DIGIT_WIDTH, current.size.y))


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
	var result: Array[Rect2] = [
		hp_title_rect,
		g_title_rect,
		alt_title_rect,
		spd_title_rect,
		flare_title_rect(flare_rect),
		weapon_title_rect,
	]
	if not _special_weapon_rows.is_empty():
		result.append(special_weapon_title_rect)
	return result


func grid_regions(maneuver_visible: bool,
		manual_flare_visible: bool = false) -> Array[Rect2]:
	var flare_rect := active_flare_rect(manual_flare_visible)
	var maneuver_rect := active_maneuver_rect(maneuver_visible, manual_flare_visible)
	var engage_row_rect := active_engage_rect(manual_flare_visible)
	var fire_row_rect := active_fire_rect(manual_flare_visible)
	var result: Array[Rect2] = [
		status_rect,
		cloud_status_rect,
		kill_status_rect,
		hp_rect,
		hp_decorative_rect,
		spd_rect,
		spd_speed_rect,
		spd_blank_rect,
		g_rect,
		g_decimal_rect,
		speed_unit_rect(0),
		speed_unit_rect(1),
		spd_decorative_rect,
		alt_rect,
		alt_gauge_rect,
		alt_mode_high_rect,
		alt_mode_low_rect,
		alt_mode_empty_rect,
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
		keycap_left_of(alt_rect),
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
	for digit_index in range(HP_DIGIT_COUNT):
		result.append(hp_digit_rect(digit_index))
	for digit_index in range(ALT_DIGIT_COUNT):
		result.append(alt_digit_rect(digit_index))
	for digit_index in range(G_INTEGER_DIGIT_COUNT):
		result.append(g_integer_digit_rect(digit_index))
	for digit_index in range(FLARE_CURRENT_DIGIT_COUNT):
		result.append(flare_current_digit_rect(flare_rect, digit_index))
	for row in range(2):
		result.append(weapon_count_rect(row))
		result.append(weapon_empty_rect(row))
		result.append(weapon_reload_percent_rect(row))
		result.append(weapon_reload_remaining_rect(row))
		result.append(weapon_reload_progress_rect(row))
		result.append(weapon_name_rect(row))
	if not _special_weapon_rows.is_empty():
		result.append(special_weapon_spacer_rect)
		for row in range(_special_weapon_rows.size()):
			result.append(special_weapon_row_rect(row))
			result.append(special_weapon_status_rect(row))
			result.append(special_weapon_progress_rect(row))
			result.append(special_weapon_name_rect(row))
	return result


## 首次显现只按互不重叠的实际框板分组；不要把内部数字格或父框重复登记，
## 否则一个视觉区域会被多层遮罩重复播放。
func reveal_panel_regions(maneuver_visible: bool,
		manual_flare_visible: bool = false) -> Array[Dictionary]:
	var engage_row_rect := active_engage_rect(manual_flare_visible)
	var fire_row_rect := active_fire_rect(manual_flare_visible)
	var result: Array[Dictionary] = [
		{"id": &"player_hp", "rect": hp_value_rect},
		{"id": &"player_g", "rect": g_rect},
		{"id": &"player_alt", "rect": alt_rect},
		{"id": &"player_spd", "rect": spd_speed_rect},
		{"id": &"player_afterburner", "rect": ab_rect},
		{"id": &"player_engage", "rect": engage_row_rect},
		{"id": &"player_control_empty", "rect": active_control_empty_rect(
			manual_flare_visible)},
		{"id": &"player_flare", "rect": active_flare_rect(manual_flare_visible)},
		{"id": &"player_fire", "rect": fire_row_rect},
		{"id": &"player_maneuver", "rect": active_maneuver_rect(
			maneuver_visible, manual_flare_visible)},
		{"id": &"player_weapon_spacer", "rect": weapon_spacer_rect},
		{"id": &"player_weapon_title", "rect": weapon_title_rect},
		{"id": &"player_weapon_msl", "rect": weapon_row_rect(0)},
		{"id": &"player_weapon_middle", "rect": weapon_middle_spacer_rect},
		{"id": &"player_weapon_gun", "rect": weapon_row_rect(1)},
		{"id": &"player_key_q", "rect": keycap_left_of(alt_rect)},
		{"id": &"player_key_e", "rect": keycap_left_of(ab_rect)},
		{"id": &"player_key_g", "rect": keycap_left_of(engage_row_rect)},
		{"id": &"player_key_f", "rect": keycap_left_of(fire_row_rect)},
		{"id": &"player_key_t", "rect": keycap_left_of(weapon_title_rect)},
	]
	if maneuver_visible:
		result.append({
			"id": &"player_key_r",
			"rect": manual_flare_key_rect() if manual_flare_visible else maneuver_key_rect(),
		})
	if not _special_weapon_rows.is_empty():
		result.append({"id": &"player_special_spacer", "rect": special_weapon_spacer_rect})
		result.append({"id": &"player_special_title", "rect": special_weapon_title_rect})
		for row_index in range(_special_weapon_rows.size()):
			result.append({
				"id": StringName("player_special_%d" % row_index),
				"rect": special_weapon_row_rect(row_index),
			})
	return result


func _draw_player_status(accent: Color) -> void:
	if _in_cloud:
		draw_rect(cloud_status_rect, accent, true)
	_draw_text_in_rect("IN CLOUD", cloud_status_rect, 15,
		cloud_status_text_color(_in_cloud, accent), true,
		HORIZONTAL_ALIGNMENT_CENTER, "IN CLOUD")
	var kill_inverted := kill_flash_on()
	if kill_inverted:
		draw_rect(kill_status_rect, accent, true)
	_draw_text_in_rect("KILLS %d" % _status_kill_count,
		kill_status_rect, 15,
		ThemeColors.UI_TERMINAL_INVERSE if kill_inverted else accent,
		true, HORIZONTAL_ALIGNMENT_CENTER, "KILLS 9999")


func kill_flash_on(now_ms: int = -1) -> bool:
	if now_ms < 0:
		now_ms = Time.get_ticks_msec()
	var elapsed := now_ms - _kill_flash_started_ms
	return elapsed >= 0 and elapsed < KILL_FLASH_DURATION_MS \
		and int(elapsed / KILL_FLASH_STEP_MS) % 2 == 0


func kill_flash_active(now_ms: int = -1) -> bool:
	if now_ms < 0:
		now_ms = Time.get_ticks_msec()
	var elapsed := now_ms - _kill_flash_started_ms
	return elapsed >= 0 and elapsed < KILL_FLASH_DURATION_MS


static func cloud_status_text_color(in_cloud: bool, accent: Color) -> Color:
	return ThemeColors.UI_TERMINAL_INVERSE if in_cloud \
		else ThemeColors.UI_INACTIVE_DIGIT


func _draw_flight_data(accent: Color, blink_on: bool) -> void:
	var current_hp := ceili(aircraft.hp)
	var max_hp := ceili(aircraft.params.max_hp) if aircraft.params else current_hp
	_draw_text_in_rect("HP", hp_title_rect, 15, accent, false,
		HORIZONTAL_ALIGNMENT_LEFT)
	var hp_digits := formatted_three_digit_value(current_hp)
	for digit_index in range(HP_DIGIT_COUNT):
		var digit_color := shared_digit_color(hp_digits, digit_index, accent)
		_draw_text_in_rect(hp_digits.substr(digit_index, 1), hp_digit_rect(digit_index),
			primary_value_font_size, digit_color, true, HORIZONTAL_ALIGNMENT_CENTER, "9")
	_draw_text_in_rect("/", hp_separator_rect, 0, accent, true)
	_draw_text_in_rect(str(max_hp), hp_max_rect, secondary_value_font_size, accent, true,
		HORIZONTAL_ALIGNMENT_CENTER, HP_VALUE_LAYOUT_TEXT)
	_draw_text_in_rect("G", g_title_rect, 15, accent, false,
		HORIZONTAL_ALIGNMENT_LEFT)
	var g_digits := formatted_two_digit_value(floori(absf(aircraft.g_load)))
	for digit_index in range(G_INTEGER_DIGIT_COUNT):
		var digit_color := shared_digit_color(g_digits, digit_index, accent)
		_draw_text_in_rect(g_digits.substr(digit_index, 1),
			g_integer_digit_rect(digit_index), g_integer_font_size, digit_color, true,
			HORIZONTAL_ALIGNMENT_CENTER, "9")
	var g_fraction := str(absi(roundi(aircraft.g_load * 10.0)) % 10)
	_draw_text_in_rect(".", g_decimal_rect, g_decimal_font_size, accent, true)
	_draw_text_in_rect(g_fraction, g_fraction_rect, g_fraction_font_size, accent, true,
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
	var altitude_digits := formatted_altitude_digits(roundi(aircraft.altitude))
	for digit_index in range(ALT_DIGIT_COUNT):
		var digit_color := shared_digit_color(altitude_digits, digit_index, accent)
		_draw_text_in_rect(altitude_digits.substr(digit_index, 1), alt_digit_rect(digit_index),
			primary_value_font_size, digit_color, true, HORIZONTAL_ALIGNMENT_CENTER, "9")
	var prefer_low := aircraft.altitude_preference == Aircraft.AltitudePreference.PREFER_LOW
	_draw_unit_cell(alt_mode_high_rect, "HIGH", not prefer_low, accent)
	_draw_unit_cell(alt_mode_low_rect, "LOW", prefer_low, accent)
	_draw_altimeter_gauge(accent)


func _draw_altimeter_gauge(accent: Color) -> void:
	var pivot := Vector2(alt_gauge_rect.get_center().x, alt_gauge_rect.end.y - 5.0)
	var radius := minf((alt_gauge_rect.size.x - 12.0) * 0.5,
		alt_gauge_rect.size.y - 10.0)
	draw_arc(pivot, radius, PI, TAU, 48, accent, ALT_GAUGE_ARC_WIDTH, false)
	var degrees := clampf(_altimeter_needle_degrees,
		ALT_GAUGE_MIN_DEGREES, ALT_GAUGE_MAX_DEGREES)
	var angle := PI + deg_to_rad(degrees)
	var needle_end := pivot + Vector2(cos(angle), sin(angle)) * (radius - 4.0)
	draw_line(pivot, needle_end, accent, ALT_GAUGE_NEEDLE_WIDTH, false)


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
				flare_current_digit_rect(rect, digit_index), primary_value_font_size,
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
	var reload_rate := aircraft.esm_reload_rate_multiplier()
	var missile_reload_seconds := weapon_reload_remaining_seconds(
		aircraft.missile_reload_progress,
		aircraft.missile_reload_duration * aircraft._executioner_reload_mult(),
		reload_rate)
	var gun_reload_seconds := weapon_reload_remaining_seconds(
		aircraft.gun_reload_progress, aircraft.gun_reload_duration, reload_rate)
	_draw_weapon_row(weapon_row_rect(0), "MSL",
		aircraft.params != null and aircraft.params.missile != null,
		aircraft.missiles_remaining,
		effective_pref == Aircraft.WeaponPreference.PREFER_MISSILE,
		aircraft._missile_reload_active, aircraft.missile_reload_progress,
		missile_reload_seconds, accent, reload_blink_on)
	_draw_weapon_row(weapon_row_rect(1), "GUN",
		aircraft.params != null and aircraft.params.gun != null,
		aircraft.ammo,
		effective_pref == Aircraft.WeaponPreference.PREFER_GUN,
		aircraft._gun_reload_active, aircraft.gun_reload_progress,
		gun_reload_seconds, accent, reload_blink_on)


func _draw_weapon_row(rect: Rect2, name_text: String, exists: bool, ammo: int, selected: bool,
		reloading: bool, reload_progress: float, reload_remaining_seconds: float, accent: Color,
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
	# Keep the MSL/GUN type at its former 2u-board size even though the slot is 3u high.
	_draw_text_in_rect(name_text, name_rect, weapon_name_font_size,
		value_text_color, true, HORIZONTAL_ALIGNMENT_CENTER, name_text)
	if exists and reloading:
		var reload_color := progress_color(reload_progress, accent)
		_draw_text_in_rect(weapon_reload_percent_text(reload_progress),
			weapon_reload_percent_rect(row_index), 0, reload_color, true,
			HORIZONTAL_ALIGNMENT_LEFT, PROGRESS_PERCENT_LAYOUT_TEXT)
		_draw_text_in_rect(weapon_reload_seconds_text(reload_remaining_seconds),
			weapon_reload_remaining_rect(row_index), 0, reload_color, true,
			HORIZONTAL_ALIGNMENT_RIGHT, PROGRESS_PERCENT_LAYOUT_TEXT)
	_draw_progress_bar(weapon_reload_progress_rect(row_index), reload_progress,
		accent, false, exists and reloading and reload_blink_on, true)


func _draw_special_weapon_row(index: int, row: Dictionary, accent: Color) -> void:
	var state: String = String(row.get("state", "ready"))
	var ready_ratio: float = clampf(float(row.get("ready_ratio", 1.0)), 0.0, 1.0)
	var state_color := progress_color(ready_ratio, accent)
	if state == "empty" or state == "overheat":
		state_color = DANGER_RED
	elif state == "standby" or state == "max":
		state_color = WARNING_YELLOW
	elif state == "ready" or state == "active":
		state_color = accent
	var detail: String = String(row.get("detail", ""))
	var state_text := special_weapon_state_text(row)
	var status_text := state_text if detail.is_empty() else "%s  %s" % [detail, state_text]
	_draw_text_in_rect(status_text, special_weapon_status_rect(index), 0,
		state_color, true, HORIZONTAL_ALIGNMENT_LEFT, status_text)
	_draw_progress_bar(special_weapon_progress_rect(index), ready_ratio,
		accent, false, true, true)
	_draw_text_in_rect(tr(String(row.get("name_key", "HUD_SPECIAL_WEAPON"))),
		special_weapon_name_rect(index), 0, state_color, true,
		HORIZONTAL_ALIGNMENT_CENTER, SPECIAL_WEAPON_NAME_LAYOUT_TEXT)


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
	var info := weapon_empty_rect(index)
	return Rect2(
		Vector2(info.position.x, info.end.y - U_SIZE.y),
		Vector2(info.size.x, U_SIZE.y))


func weapon_reload_percent_rect(index: int) -> Rect2:
	var info := weapon_empty_rect(index)
	return Rect2(info.position, WEAPON_RELOAD_VALUE_SIZE)


func weapon_reload_remaining_rect(index: int) -> Rect2:
	var info := weapon_empty_rect(index)
	return Rect2(
		Vector2(info.end.x - WEAPON_RELOAD_VALUE_SIZE.x, info.position.y),
		WEAPON_RELOAD_VALUE_SIZE)


func weapon_empty_rect(index: int) -> Rect2:
	var row := weapon_row_rect(index)
	var name := weapon_name_rect(index)
	return Rect2(Vector2(row.position.x + weapon_count_width, row.position.y),
		Vector2(maxf(0.0, name.position.x - row.position.x - weapon_count_width), row.size.y))


func special_weapon_row_rect(index: int) -> Rect2:
	var slot_width := special_weapon_rect.size.x / float(SPECIAL_WEAPON_COLUMNS)
	var column := index % SPECIAL_WEAPON_COLUMNS
	var grid_row := floori(float(index) / float(SPECIAL_WEAPON_COLUMNS))
	return Rect2(
		special_weapon_rect.position + Vector2(slot_width * float(column),
			SPECIAL_WEAPON_SLOT_HEIGHT * float(grid_row)),
		Vector2(slot_width, SPECIAL_WEAPON_SLOT_HEIGHT))


func special_weapon_name_rect(index: int) -> Rect2:
	var row := special_weapon_row_rect(index)
	return Rect2(Vector2(row.end.x - SPECIAL_WEAPON_NAME_WIDTH, row.position.y),
		Vector2(SPECIAL_WEAPON_NAME_WIDTH, row.size.y))


func special_weapon_progress_rect(index: int) -> Rect2:
	var row := special_weapon_row_rect(index)
	var name := special_weapon_name_rect(index)
	return Rect2(Vector2(row.position.x, row.position.y + U_SIZE.y),
		Vector2(maxf(name.position.x - row.position.x, 0.0), U_SIZE.y))


func special_weapon_status_rect(index: int) -> Rect2:
	var row := special_weapon_row_rect(index)
	return Rect2(row.position,
		Vector2(maxf(row.size.x - SPECIAL_WEAPON_NAME_WIDTH, 0.0), U_SIZE.y))


static func speed_value_overflows(speed_value: int) -> bool:
	return speed_value > 99999


static func formatted_speed_digits(speed_value: int) -> String:
	if speed_value_overflows(speed_value):
		return "99999"
	return "%05d" % maxi(speed_value, 0)


static func formatted_two_digit_value(value: int) -> String:
	return "%02d" % clampi(value, 0, 99)


static func formatted_three_digit_value(value: int) -> String:
	return "%03d" % clampi(value, 0, 999)


static func formatted_altitude_digits(value: int) -> String:
	return "%05d" % clampi(value, 0, 99999)


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


static func missile_reload_remaining_s(ac: Aircraft) -> float:
	if ac == null or not is_instance_valid(ac) or not ac._missile_reload_active:
		return 0.0
	var total := ac.missile_reload_duration * ac._executioner_reload_mult()
	var rate := maxf(ac.esm_reload_rate_multiplier(), 0.001)
	return maxf(total - ac._missile_reload_timer, 0.0) / rate


static func engage_state_key(enabled: bool) -> String:
	return "HUD_ENGAGE" if enabled else "HUD_PASSIVE"


static func fire_state_key(enabled: bool) -> String:
	return "HUD_AUTO_FIRE" if enabled else "HUD_MANUAL_FIRE"


static func special_weapon_rows(ac: Aircraft) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	if ac == null or not is_instance_valid(ac) or ac.is_destroyed or ac.params == null:
		return rows
	var reload_rate := maxf(ac.esm_reload_rate_multiplier(), 0.001)

	if ac.params.secondary_missile != null:
		var secondary: MissileParams = ac.params.secondary_missile
		var secondary_total := secondary.cooldown * float(maxi(secondary.max_count, 1))
		var secondary_state := "ready"
		var secondary_ratio := 1.0
		var secondary_remaining := 0.0
		if ac._secondary_reload_active:
			secondary_state = "reload"
			secondary_ratio = clampf(ac._secondary_reload_timer / maxf(secondary_total, 0.001),
				0.0, 1.0)
			secondary_remaining = maxf(secondary_total - ac._secondary_reload_timer, 0.0) \
				/ reload_rate
		elif ac._secondary_cooldown > 0.0:
			secondary_state = "cooldown"
			secondary_remaining = ac._secondary_cooldown
			secondary_ratio = cooldown_ready_ratio(secondary_remaining,
				secondary.cooldown * ac.weapon_master_cd_mult)
		elif ac.secondary_missiles_remaining <= 0:
			secondary_state = "empty"
			secondary_ratio = 0.0
		rows.append({
			"kind": "secondary_missile",
			"name_key": "HUD_SP_MISSILE",
			"detail": "%d/%d" % [ac.secondary_missiles_remaining, secondary.max_count],
			"state": secondary_state,
			"ready_ratio": secondary_ratio,
			"remaining_s": secondary_remaining,
			"progress_pct": roundi(secondary_ratio * 100.0),
		})

	if ac.params.rocket != null:
		var rocket: RocketParams = ac.params.rocket
		var rocket_state := "ready"
		var rocket_ratio := 1.0
		var rocket_remaining := 0.0
		if not rocket.infinite_ammo and ac.rockets_remaining <= 0:
			rocket_state = "empty"
			rocket_ratio = 0.0
		elif ac._rocket_burst_cooldown > 0.0:
			rocket_state = "cooldown"
			rocket_remaining = ac._rocket_burst_cooldown
			rocket_ratio = cooldown_ready_ratio(rocket_remaining,
				rocket.burst_cooldown * ac.weapon_master_cd_mult)
		rows.append({
			"kind": "rocket",
			"name_key": "HUD_SP_ROCKET",
			"detail": "" if rocket.infinite_ammo else "%d/%d" % [
				ac.rockets_remaining, rocket.max_ammo],
			"state": rocket_state,
			"ready_ratio": rocket_ratio,
			"remaining_s": rocket_remaining,
		})

	var railgun := ac.params.get_equipment_of_kind("railgun") as RailgunEquipment
	if railgun != null:
		var railgun_state: Dictionary = ac.equipment_state.get(RailgunEquipment.STATE_KEY, {})
		var railgun_cooldown := float(railgun_state.get("cooldown", 0.0))
		var railgun_charging := bool(railgun_state.get("charging", false))
		var railgun_charge := clampf(float(railgun_state.get("charge_progress", 0.0)), 0.0, 1.0)
		rows.append({
			"kind": "railgun",
			"name_key": "HUD_SP_RAILGUN",
			"detail": "",
			"state": "charge" if railgun_charging else (
				"cooldown" if railgun_cooldown > 0.0 else "ready"),
			"ready_ratio": railgun_charge if railgun_charging else cooldown_ready_ratio(
				railgun_cooldown, railgun.cooldown) if railgun_cooldown > 0.0 else 1.0,
			"remaining_s": railgun_cooldown,
			"progress_pct": roundi(railgun_charge * 100.0),
		})

	var laser := ac.params.get_equipment_of_kind("laser") as LaserEquipment
	if laser != null:
		var laser_state: Dictionary = ac.equipment_state.get(LaserEquipment.STATE_KEY, {})
		var heat := clampf(float(laser_state.get("heat", 0.0)), 0.0, laser.heat_max)
		var overheating := bool(laser_state.get("overheating", false))
		var heat_ratio := heat / maxf(laser.heat_max, 0.001)
		var overheat_threshold := laser.heat_max * laser.overheat_exit_threshold
		var overheat_remaining := maxf(heat - overheat_threshold, 0.0) \
			/ maxf(laser.heat_cooldown_per_second, 0.001) if overheating else 0.0
		rows.append({
			"kind": "laser",
			"name_key": "HUD_SP_LASER",
			"detail": "",
			"state": "overheat" if overheating else ("heat" if heat > 0.01 else "ready"),
			"ready_ratio": 1.0 - heat_ratio,
			"remaining_s": overheat_remaining,
			"progress_pct": roundi(heat_ratio * 100.0),
		})

	if ac.params.torpedo != null:
		var torpedo: TorpedoParams = ac.params.torpedo
		var torpedo_remaining := maxf(ac._torpedo_cooldown, 0.0)
		rows.append({
			"kind": "torpedo",
			"name_key": "HUD_SP_TAIL_MINE",
			"detail": "",
			"state": "cooldown" if torpedo_remaining > 0.0 else (
				"ready" if ac.evasion_mode else "standby"),
			"ready_ratio": cooldown_ready_ratio(torpedo_remaining, torpedo.cooldown)
				if torpedo_remaining > 0.0 else 1.0,
			"remaining_s": torpedo_remaining,
		})

	if ac.params.loyal_wingman != null:
		var wingman: LoyalWingmanParams = ac.params.loyal_wingman
		var wingman_remaining := maxf(ac._loyal_wingman_cooldown, 0.0)
		var alive_drones := ac._alive_drones.size()
		var wingman_state := "ready" if ac.evasion_mode else "standby"
		if alive_drones >= wingman.max_simultaneous:
			wingman_state = "max"
		elif wingman_remaining > 0.0:
			wingman_state = "cooldown"
		rows.append({
			"kind": "loyal_wingman",
			"name_key": "HUD_SP_DRONE",
			"detail": "%d/%d" % [alive_drones, wingman.max_simultaneous],
			"state": wingman_state,
			"ready_ratio": cooldown_ready_ratio(wingman_remaining, wingman.cooldown)
				if wingman_remaining > 0.0 else 1.0,
			"remaining_s": wingman_remaining,
		})

	if ac.params.get_equipment_of_kind("esm_pod") != null:
		rows.append({
			"kind": "esm_pod",
			"name_key": "HUD_SP_ESM",
			"detail": "",
			"state": "active",
			"ready_ratio": 1.0,
			"remaining_s": 0.0,
		})
	return rows


func special_weapon_state_text(row: Dictionary) -> String:
	var state: String = String(row.get("state", "ready"))
	match state:
		"cooldown":
			return tr("HUD_WEAPON_COOLDOWN_FMT") % float(row.get("remaining_s", 0.0))
		"reload":
			return tr("HUD_WEAPON_RELOAD_FMT") % [
				int(row.get("progress_pct", 0)), float(row.get("remaining_s", 0.0))]
		"charge":
			return tr("HUD_WEAPON_CHARGE_FMT") % int(row.get("progress_pct", 0))
		"heat":
			return tr("HUD_WEAPON_HEAT_FMT") % int(row.get("progress_pct", 0))
		"overheat":
			return tr("HUD_WEAPON_OVERHEAT_FMT") % float(row.get("remaining_s", 0.0))
		"empty":
			return tr("HUD_WEAPON_EMPTY")
		"standby":
			return tr("HUD_WEAPON_STANDBY")
		"max":
			return tr("HUD_WEAPON_MAX")
		"active":
			return tr("HUD_WEAPON_ACTIVE")
		_:
			return tr("HUD_WEAPON_READY")


static func weapon_reload_remaining_seconds(progress: float, duration: float,
		reload_rate: float = 1.0) -> float:
	if duration <= 0.0:
		return 0.0
	return maxf(0.0,
		(1.0 - clampf(progress, 0.0, 1.0)) * duration / maxf(reload_rate, 0.001))


static func weapon_reload_percent_text(progress: float) -> String:
	return "%d%%" % roundi(clampf(progress, 0.0, 1.0) * 100.0)


static func weapon_reload_seconds_text(remaining_seconds: float) -> String:
	return "%ds" % ceili(maxf(remaining_seconds, 0.0))


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


static func altitude_tier_name_key(ac: Aircraft) -> String:
	if ac == null or not is_instance_valid(ac):
		return "HUD_ALT_TIER_MID"
	match ac.get_altitude_tier():
		Aircraft.AltitudeTier.HIGH:
			return "HUD_ALT_TIER_HIGH"
		Aircraft.AltitudeTier.MID:
			return "HUD_ALT_TIER_MID"
		_:
			return "HUD_ALT_TIER_LOW"


static func altitude_mode_text(ac: Aircraft) -> String:
	if ac != null and is_instance_valid(ac) \
			and ac.altitude_preference == Aircraft.AltitudePreference.PREFER_LOW:
		return "LOW"
	return "HIGH"


static func altimeter_target_degrees(altitude: float, prefer_low: bool) -> float:
	var ratio := clampf(altitude / ALT_GAUGE_REFERENCE_ALTITUDE, 0.0, 1.0)
	if prefer_low:
		return lerpf(ALT_GAUGE_MIN_DEGREES, ALT_GAUGE_LOW_MAX_DEGREES, ratio)
	return lerpf(ALT_GAUGE_HIGH_MIN_DEGREES, ALT_GAUGE_MAX_DEGREES, ratio)


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
