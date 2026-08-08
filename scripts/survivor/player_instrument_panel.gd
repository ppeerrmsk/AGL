class_name PlayerInstrumentPanel
extends Control

const HudPreferencesScript := preload("res://scripts/ui/hud_preferences.gd")
const INFO_FONT_SOURCE := preload("res://resources/fonts/AcuminPro-Regular.otf")
const DISPLAY_FONT_SOURCE := preload("res://resources/fonts/AcuminProExtraCond-Semibold.otf")

## 生存模式右侧玩家仪表。纯显示、鼠标穿透；每条信息行只使用自身左上角局部坐标。
const PANEL_SIZE := Vector2(326.0, 408.0)
const CONTENT_X := 28.0
const CONTENT_W := 298.0
const HP_RECT := Rect2(CONTENT_X, 0.0, CONTENT_W, 76.0)
const SPD_RECT := Rect2(CONTENT_X, 76.0, CONTENT_W, 78.0)
const SPD_ALT_RECT := Rect2(CONTENT_X, 76.0, 106.0, 78.0)
const SPD_SPEED_RECT := Rect2(CONTENT_X + 106.0, 76.0, CONTENT_W - 106.0, 78.0)
const AB_RECT := Rect2(CONTENT_X, 154.0, CONTENT_W, 28.0)
const CONTROL_RECT := Rect2(CONTENT_X, 184.0, CONTENT_W, 116.0)
const CONTROL_LEFT_W := 122.0
const ENGAGE_RECT := Rect2(CONTENT_X, 184.0, CONTROL_LEFT_W, 58.0)
const FIRE_RECT := Rect2(CONTENT_X, 242.0, CONTROL_LEFT_W, 58.0)
const FLARE_FULL_RECT := Rect2(CONTENT_X + CONTROL_LEFT_W, 184.0,
	CONTENT_W - CONTROL_LEFT_W, 116.0)
const FLARE_COMPACT_RECT := Rect2(CONTENT_X + CONTROL_LEFT_W, 184.0,
	CONTENT_W - CONTROL_LEFT_W, 66.0)
const MANEUVER_RECT := Rect2(CONTENT_X + CONTROL_LEFT_W, 250.0,
	CONTENT_W - CONTROL_LEFT_W, 50.0)
const WEAPON_RECT := Rect2(CONTENT_X, 304.0, CONTENT_W, 104.0)
const WEAPON_COUNT_W := 70.0
const WEAPON_PRIORITY_W := 106.0
const KEYCAP_X := 2.0
const KEYCAP_SIZE := 21.0
const Q_KEY_Y := 80.0
const E_KEY_Y := 157.0
const G_KEY_Y := 188.0
const F_KEY_Y := 246.0
const T_KEY_Y := 312.0
const BLINK_STEP_MS := 500
const REDRAW_INTERVAL_MS := 50
const FLARE_STAR_COUNT := 10
const PROGRESS_HEIGHT := 5.0
const FLARE_CURRENT_FONT_SIZE := 36
const FLARE_MAX_FONT_SIZE := 18
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


func _ready() -> void:
	_info_font = INFO_FONT_SOURCE.duplicate() as Font
	_display_font = DISPLAY_FONT_SOURCE.duplicate() as Font
	_info_font.fallbacks.append(ThemeDB.fallback_font)
	_display_font.fallbacks.append(ThemeDB.fallback_font)
	_localized_font = get_theme_default_font()
	if _localized_font == null:
		_localized_font = ThemeDB.fallback_font
	custom_minimum_size = PANEL_SIZE
	size = PANEL_SIZE
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus_mode = Control.FOCUS_NONE
	set_process(false)


func update_display(ac: Aircraft, charge: AfterburnerCharge) -> void:
	aircraft = ac
	afterburner_charge = charge
	var now := Time.get_ticks_msec()
	if now - _last_redraw_ms < REDRAW_INTERVAL_MS:
		return
	_last_redraw_ms = now
	queue_redraw()


func _draw() -> void:
	var accent: Color = HudPreferencesScript.hud_color()
	var blink_on := int(Time.get_ticks_msec() / BLINK_STEP_MS) % 2 == 0
	var has_aircraft := aircraft != null and is_instance_valid(aircraft) and not aircraft.is_destroyed
	var maneuver_visible := maneuver_skill_visible(aircraft) if has_aircraft else false
	var flare_rect := FLARE_COMPACT_RECT if maneuver_visible else FLARE_FULL_RECT

	_draw_module(HP_RECT, accent)
	_draw_module(SPD_RECT, accent)
	_draw_module(AB_RECT, accent)
	_draw_module(ENGAGE_RECT, accent)
	_draw_module(FIRE_RECT, accent)
	_draw_module(flare_rect, accent)
	if maneuver_visible:
		_draw_module(MANEUVER_RECT, accent)
	_draw_module(weapon_row_rect(0), accent)
	_draw_module(weapon_row_rect(1), accent)
	_draw_keycap("Q", Q_KEY_Y, accent)
	_draw_keycap("E", E_KEY_Y, accent)
	_draw_keycap("G", G_KEY_Y, accent)
	_draw_keycap("F", F_KEY_Y, accent)
	_draw_keycap("T", T_KEY_Y, accent)
	if not has_aircraft:
		return

	_draw_flight_data(accent, blink_on)
	_draw_afterburner(accent, blink_on)
	_draw_toggle_row(ENGAGE_RECT, tr("HUD_ENGAGE"), aircraft.auto_engage_enabled, accent)
	_draw_toggle_row(FIRE_RECT, tr("HUD_FIRE"), aircraft.missile_auto_fire, accent)
	_draw_flares(flare_rect, accent)
	if maneuver_visible:
		_draw_maneuver_charge(accent)
	_draw_weapons(accent, blink_on)


func _draw_module(rect: Rect2, accent: Color) -> void:
	draw_rect(rect, Color(0.0, 0.0, 0.0, 0.78), true)
	draw_rect(rect, accent, false, 2.0)


func _draw_keycap(text: String, y: float, accent: Color) -> void:
	var rect := keycap_rect(y)
	draw_rect(rect, Color(0.0, 0.0, 0.0, 0.82), true)
	draw_rect(rect, accent, false, 2.0)
	_draw_text(text, Vector2(rect.position.x, rect.position.y + 16.0), 13, accent,
		HORIZONTAL_ALIGNMENT_CENTER, rect.size.x)


static func keycap_rect(y: float) -> Rect2:
	return Rect2(KEYCAP_X, y, KEYCAP_SIZE, KEYCAP_SIZE)


func _draw_flight_data(accent: Color, blink_on: bool) -> void:
	var hp_origin := HP_RECT.position
	var current_hp := ceili(aircraft.hp)
	var max_hp := ceili(aircraft.params.max_hp) if aircraft.params else current_hp
	_draw_text_top("HP", hp_origin + Vector2(10.0, 9.0), 17, accent)
	_draw_text_top(str(current_hp), hp_origin + Vector2(45.0, 5.0), 44, accent, true)
	_draw_text_top("/%d" % max_hp, hp_origin + Vector2(139.0, 13.0), 22, accent, true)
	_draw_text_top("G", hp_origin + Vector2(202.0, 8.0), 14, accent)
	_draw_text_right("%.1f" % aircraft.g_load, hp_origin.x + HP_RECT.size.x - 9.0,
		hp_origin.y + 50.0, 35, accent, true)
	var hp_ratio := float(current_hp) / maxf(float(max_hp), 1.0)
	_draw_progress_bar(HP_RECT, hp_ratio, accent)

	_draw_altitude_preference(accent)
	var speed_origin := SPD_SPEED_RECT.position
	_draw_text_top("SPD", speed_origin + Vector2(10.0, 11.0), 17, accent)
	var speed_kmh := aircraft.speed * 3.6
	_draw_text_top(str(HudPreferencesScript.speed_value(speed_kmh)),
		speed_origin + Vector2(45.0, 5.0), 48, accent, true)
	_draw_unit_cell(Rect2(speed_origin + Vector2(133.0, 7.0), Vector2(50.0, 24.0)), "KT",
		HudPreferencesScript.uses_knots(), accent)
	_draw_unit_cell(Rect2(speed_origin + Vector2(125.0, 41.0), Vector2(58.0, 24.0)), "KM/H",
		not HudPreferencesScript.uses_knots(), accent)
	if aircraft.is_stalled and blink_on:
		_draw_text_top("STALL", speed_origin + Vector2(92.0, 48.0), 15, DANGER_RED, true)


func _draw_altitude_preference(accent: Color) -> void:
	var origin := SPD_ALT_RECT.position
	draw_line(Vector2(SPD_ALT_RECT.end.x, origin.y), SPD_ALT_RECT.end, accent, 2.0)
	_draw_text_top("ALT", origin + Vector2(8.0, 6.0), 13, accent)
	_draw_text_top(str(roundi(aircraft.altitude)), origin + Vector2(8.0, 22.0), 22, accent, true)
	_draw_localized_text_top(tr(altitude_preference_name_key(aircraft)),
		origin + Vector2(8.0, 51.0), 12, accent)


func _draw_unit_cell(rect: Rect2, text: String, selected: bool, accent: Color) -> void:
	if selected:
		draw_rect(rect, accent, true)
	_draw_text(text, Vector2(rect.position.x, rect.position.y + 19.0), 16,
		Color.BLACK if selected else accent, HORIZONTAL_ALIGNMENT_CENTER, rect.size.x)


func _draw_afterburner(accent: Color, blink_on: bool) -> void:
	var ratio := 1.0
	var active := false
	if afterburner_charge != null:
		ratio = clampf(afterburner_charge.ratio(), 0.0, 1.0)
		active = afterburner_charge.is_active()
	var charging := not active and ratio < 0.999
	var fill_color := progress_color(ratio, accent)
	if active or charging:
		var fill := AB_RECT.grow(-3.0)
		fill.size.x *= ratio
		draw_rect(fill, fill_color, true)
	var show_text := not charging or blink_on
	if not show_text:
		return
	var text_color := accent
	if charging and ratio <= 0.20:
		text_color = DANGER_RED
	if (active or charging) and ratio >= 0.48:
		_draw_localized_text_outline(tr("HUD_AFTERBURNER"),
			Vector2(AB_RECT.position.x, AB_RECT.position.y + 21.0), 18, Color.BLACK,
			fill_color, HORIZONTAL_ALIGNMENT_CENTER, AB_RECT.size.x)
	else:
		_draw_localized_text(tr("HUD_AFTERBURNER"), Vector2(AB_RECT.position.x, AB_RECT.position.y + 21.0),
			18, text_color, HORIZONTAL_ALIGNMENT_CENTER, AB_RECT.size.x, true)


func _draw_toggle_row(rect: Rect2, text: String, enabled: bool, accent: Color) -> void:
	var origin := rect.position
	_draw_text_top("AUTOPILOT", origin + Vector2(7.0, 5.0), 10, accent)
	var state_rect := Rect2(origin + Vector2(7.0, 21.0), Vector2(rect.size.x - 14.0, 31.0))
	if enabled:
		draw_rect(state_rect, accent, true)
	_draw_localized_text(text, Vector2(state_rect.position.x, state_rect.position.y + 23.0), 16,
		Color.BLACK if enabled else accent, HORIZONTAL_ALIGNMENT_CENTER, state_rect.size.x, true)


func _draw_flares(rect: Rect2, accent: Color) -> void:
	var has_flare := aircraft.params != null and aircraft.params.flare != null
	var color := accent if has_flare else Color(accent, 0.0)
	var origin := rect.position
	_draw_text_top("FLR", origin + Vector2(8.0, 5.0), 15, color, true)
	if has_flare:
		_draw_text_top(str(aircraft.flares_remaining), origin + Vector2(8.0, 21.0),
			FLARE_CURRENT_FONT_SIZE, color, true)
		_draw_text_top("/%d" % aircraft.params.flare.max_flares,
			origin + Vector2(57.0, 29.0), FLARE_MAX_FONT_SIZE, color, true)
	_draw_flare_stars(Rect2(origin + Vector2(88.0, 18.0), Vector2(80.0, 39.0)),
		flare_lit_star_count(aircraft), color)


func _draw_flare_stars(rect: Rect2, lit_count: int, accent: Color) -> void:
	for i in range(FLARE_STAR_COUNT):
		var row := i / 5
		var col := i % 5
		var color := accent if i < lit_count else Color(accent, 0.16)
		_draw_text("*", rect.position + Vector2(float(col) * 16.0,
			15.0 + float(row) * 16.0), 17, color)


func _draw_maneuver_charge(accent: Color) -> void:
	var maneuver_id := aircraft.equipped_r_maneuver_id()
	if maneuver_id == &"":
		return
	var origin := MANEUVER_RECT.position
	var name_key: String = MANEUVER_NAME_KEYS.get(maneuver_id, "")
	_draw_text_top("R", origin + Vector2(7.0, 4.0), 12, accent)
	_draw_localized_text_top(tr(name_key), origin + Vector2(25.0, 4.0), 10, accent)
	var ready_ratio := maneuver_charge_ratio(aircraft)
	_draw_text_top("%d%%" % roundi(ready_ratio * 100.0), origin + Vector2(7.0, 17.0),
		23, progress_color(ready_ratio, accent), true)
	_draw_progress_bar(MANEUVER_RECT, ready_ratio, accent)


func _draw_weapons(accent: Color, blink_on: bool) -> void:
	var effective_pref := effective_weapon_preference(aircraft)
	_draw_weapon_row(weapon_row_rect(0), "MSL",
		aircraft.params != null and aircraft.params.missile != null,
		aircraft.missiles_remaining,
		effective_pref == Aircraft.WeaponPreference.PREFER_MISSILE,
		aircraft._missile_reload_active, aircraft.missile_reload_progress, accent, blink_on)
	_draw_weapon_row(weapon_row_rect(1), "GUN",
		aircraft.params != null and aircraft.params.gun != null,
		aircraft.ammo,
		effective_pref == Aircraft.WeaponPreference.PREFER_GUN,
		aircraft._gun_reload_active, aircraft.gun_reload_progress, accent, blink_on)


func _draw_weapon_row(rect: Rect2, name_text: String, exists: bool, ammo: int, selected: bool,
		reloading: bool, reload_progress: float, accent: Color, blink_on: bool) -> void:
	var origin := rect.position
	var name_x := origin.x + WEAPON_COUNT_W + WEAPON_PRIORITY_W
	draw_multiline(PackedVector2Array([
		Vector2(origin.x + WEAPON_COUNT_W, origin.y),
		Vector2(origin.x + WEAPON_COUNT_W, rect.end.y),
		Vector2(name_x, origin.y), Vector2(name_x, rect.end.y),
	]), accent, 2.0)
	var name_rect := Rect2(Vector2(name_x, origin.y), Vector2(rect.end.x - name_x, rect.size.y))
	var content_color := accent if exists else Color(accent, 0.0)
	var name_text_color := content_color
	var reload_inverted := false
	if exists and reloading:
		var ratio := clampf(reload_progress, 0.0, 1.0)
		var fill := name_rect.grow(-3.0)
		fill.size.x *= ratio
		var fill_color := progress_color(ratio, accent)
		if blink_on:
			draw_rect(fill, fill_color, true)
			reload_inverted = ratio >= 0.48
			if reload_inverted:
				name_text_color = Color.BLACK
	elif exists and selected:
		draw_rect(name_rect.grow(-2.0), accent, true)
		name_text_color = Color.BLACK
	_draw_text_top(str(ammo), origin + Vector2(8.0, 10.0), 27, content_color, true)
	if selected and exists:
		_draw_localized_text_top(tr("HUD_PRIORITY"), origin + Vector2(WEAPON_COUNT_W + 8.0, 17.0),
			12, content_color)
	var name_baseline := Vector2(name_rect.position.x, origin.y + 40.0)
	if reload_inverted:
		_draw_text_outline(name_text, name_baseline, 33, name_text_color,
			progress_color(clampf(reload_progress, 0.0, 1.0), accent),
			HORIZONTAL_ALIGNMENT_CENTER, name_rect.size.x)
	else:
		_draw_text(name_text, name_baseline, 33, name_text_color,
			HORIZONTAL_ALIGNMENT_CENTER, name_rect.size.x, true)


func _draw_progress_bar(rect: Rect2, ratio: float, accent: Color) -> void:
	var clamped := clampf(ratio, 0.0, 1.0)
	var track := Rect2(rect.position + Vector2(3.0, rect.size.y - PROGRESS_HEIGHT - 3.0),
		Vector2(rect.size.x - 6.0, PROGRESS_HEIGHT))
	var color := progress_color(clamped, accent)
	draw_rect(track, Color(color, 0.16), true)
	if clamped <= 0.0:
		return
	var fill := track
	fill.size.x *= clamped
	draw_rect(fill, color, true)


static func weapon_row_rect(index: int) -> Rect2:
	var row_h := WEAPON_RECT.size.y * 0.5
	return Rect2(WEAPON_RECT.position + Vector2(0.0, float(index) * row_h),
		Vector2(WEAPON_RECT.size.x, row_h))


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
