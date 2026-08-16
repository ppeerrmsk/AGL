extends RefCounted

## 玩家仪表确定性验收：单位换算、纯显示交互、武器优先跳过缺失项、
## 十枚热诱弹视觉波与星号/装填进度同步。

const SurvivorModeScript := preload("res://scripts/survivor/survivor_mode.gd")
const HudPreferencesScript := preload("res://scripts/ui/hud_preferences.gd")
const PlayerInstrumentPanelScript := preload("res://scripts/survivor/player_instrument_panel.gd")
const WingmanInstrumentPanelScript := preload("res://scripts/survivor/wingman_instrument_panel.gd")
const MilestoneAxisCounterScript := preload("res://scripts/survivor/milestone_axis_counter.gd")
const BottomExperiencePanelScript := preload("res://scripts/survivor/bottom_experience_panel.gd")
const HudColorSettingsPanelScript := preload("res://scripts/ui/hud_color_settings_panel.gd")
const HudFirstRevealSequencerScript := preload("res://scripts/ui/hud_first_reveal_sequencer.gd")
const HudBoardVisibilityScript := preload("res://scripts/ui/hud_board_visibility.gd")
const TerminalTextScript := preload("res://scripts/ui/terminal_text.gd")

var _pass := 0
var _fail := 0


func run() -> void:
	print("\n════════ 玩家仪表 HUD 验收 ════════")
	_test_speed_units()
	_test_display_is_mouse_transparent()
	_test_wingman_rows_follow_live_count()
	_test_layout_contract()
	_test_milestone_axis_counter()
	_test_progress_color_contract()
	_test_altitude_preference_display()
	_test_special_weapon_status()
	_test_first_reveal_sequence()
	_test_color_panel_builds()
	_test_weapon_priority_cycle()
	_test_flare_visual_progress()
	_test_unique_r_maneuver_cooldown()
	print("──────── 结果：%d 通过 / %d 失败 ────────\n" % [_pass, _fail])


func _test_speed_units() -> void:
	_check("1852 km/h = 1000 kt", HudPreferencesScript.speed_value_for(
		1852.0, HudPreferencesScript.SPEED_KT) == 1000)
	_check("km/h 保持整数显示", HudPreferencesScript.speed_value_for(
		945.0, HudPreferencesScript.SPEED_KMH) == 945)
	_check("默认 HUD 使用通用终端绿且面板背景精确为 70%",
		HudPreferencesScript.DEFAULT_COLOR.is_equal_approx(ThemeColors.UI_TERMINAL_GREEN)
		and is_equal_approx(ThemeColors.UI_BLOCK_BACKGROUND.a, 0.70))


func _test_display_is_mouse_transparent() -> void:
	var panel = PlayerInstrumentPanelScript.new()
	panel._ready()
	_check("仪表鼠标穿透", panel.mouse_filter == Control.MOUSE_FILTER_IGNORE)
	_check("仪表不可获焦", panel.focus_mode == Control.FOCUS_NONE)
	_check("中文本地化明确使用当前主题默认字体",
		PlayerInstrumentPanelScript.uses_theme_font_for_locale("zh_CN")
		and not PlayerInstrumentPanelScript.uses_theme_font_for_locale("en")
		and panel._localized_font == panel.get_theme_default_font())
	panel.free()


func _test_wingman_rows_follow_live_count() -> void:
	var panel = WingmanInstrumentPanelScript.new()
	panel._ready()
	var row := {
		"slot": 2,
		"callsign": "VIPER",
		"hp": "84/100",
		"action": "FORMATION",
		"has_msl": true,
		"msl": "2/4",
	}
	panel.update_display([row])
	_check("1 架僚机生成 1 条独立信息行",
		panel.visible and is_equal_approx(panel.size.y,
			WingmanInstrumentPanelScript.total_height_for_count(1)))
	_check("僚机首次显现按每架信息行拆成独立框板",
		panel.reveal_panel_regions().size() == 1
		and panel.reveal_panel_regions()[0].get("id", &"") == &"wingman_2")
	panel.update_display([row, row.merged({"slot": 3, "callsign": "MOBIUS"}, true)])
	_check("2 架僚机按数量扩成 2 行",
		is_equal_approx(panel.size.y, WingmanInstrumentPanelScript.total_height_for_count(2)))
	_check("两架僚机不会被首次显现合成一个整体",
		panel.reveal_panel_regions().size() == 2)
	_check("僚机仪表鼠标穿透且不可获焦",
		panel.mouse_filter == Control.MOUSE_FILTER_IGNORE
		and panel.focus_mode == Control.FOCUS_NONE)
	panel.update_display([])
	_check("无僚机时信息行完全隐藏", not panel.visible and panel.size.y == 0.0)
	panel.free()


func _test_color_panel_builds() -> void:
	var color_panel = HudColorSettingsPanelScript.new()
	color_panel._ready()
	color_panel.open()
	_check("主菜单 HUD 色盘可构建", color_panel.visible and color_panel.get_child_count() == 2)
	color_panel.free()


func _test_layout_contract() -> void:
	var panel = PlayerInstrumentPanelScript.new()
	panel._ready()
	var reveal_regions: Array[Dictionary] = panel.reveal_panel_regions(false, false)
	var reveal_ids: Array[StringName] = []
	for descriptor in reveal_regions:
		reveal_ids.append(StringName(descriptor.get("id", &"")))
	_check("玩家仪表首次显现拆成逐功能框而非整组目标",
		reveal_regions.size() >= 20
		and reveal_ids.has(&"player_hp") and reveal_ids.has(&"player_g")
		and reveal_ids.has(&"player_alt") and reveal_ids.has(&"player_spd")
		and reveal_ids.has(&"player_engage") and reveal_ids.has(&"player_flare")
		and reveal_ids.has(&"player_fire") and reveal_ids.has(&"player_weapon_msl")
		and reveal_ids.has(&"player_weapon_gun"))
	_check("maximum layout references remain explicit",
		PlayerInstrumentPanelScript.HP_VALUE_LAYOUT_TEXT == "999"
		and PlayerInstrumentPanelScript.G_VALUE_LAYOUT_TEXT == "11.5"
		and PlayerInstrumentPanelScript.G_INTEGER_LAYOUT_TEXT == "11"
		and PlayerInstrumentPanelScript.G_FRACTION_LAYOUT_TEXT == "9"
		and PlayerInstrumentPanelScript.SPD_VALUE_LAYOUT_TEXT == "99999"
		and PlayerInstrumentPanelScript.ALT_VALUE_LAYOUT_TEXT == "99999"
		and PlayerInstrumentPanelScript.FLARE_VALUE_LAYOUT_TEXT == "99"
		and PlayerInstrumentPanelScript.PROGRESS_PERCENT_LAYOUT_TEXT == "100%"
		and PlayerInstrumentPanelScript.PROGRESS_SECONDS_LAYOUT_TEXT == "100s")
	_check("IN CLOUD 与击杀数在 HP 上方平分一条 1u 粗体状态行",
		panel.status_rect.size == Vector2(panel.aligned_content_width, 18.0)
		and panel.cloud_status_rect.size == panel.kill_status_rect.size
		and panel.cloud_status_rect.end.x == panel.kill_status_rect.position.x
		and panel.hp_rect.position.y == panel.status_rect.end.y
		and panel.grid_regions(false).has(panel.cloud_status_rect)
		and panel.grid_regions(false).has(panel.kill_status_rect))
	panel.update_status(false, 3)
	panel.update_status(true, 4)
	panel._kill_flash_started_ms = 1000
	_check("云层状态常亮而击杀 +1 只反色闪烁两次",
		panel._in_cloud and panel._status_kill_count == 4
		and PlayerInstrumentPanelScript.cloud_status_text_color(
			true, Color.WHITE).is_equal_approx(ThemeColors.UI_TERMINAL_INVERSE)
		and PlayerInstrumentPanelScript.cloud_status_text_color(
			false, Color.WHITE).is_equal_approx(ThemeColors.UI_INACTIVE_DIGIT)
		and panel.kill_flash_on(1000)
		and not panel.kill_flash_on(1180)
		and panel.kill_flash_on(1360)
		and not panel.kill_flash_on(1540)
		and panel.kill_flash_active(1719)
		and not panel.kill_flash_on(1720)
		and not panel.kill_flash_active(1720))
	var display_font: Font = panel._display_font
	_check("ALT HP and FLR preserve 3u digits while SPD is tighter than compact G",
		panel.primary_value_font_size > 1
		and panel.spd_digit_font_size > 1
		and panel.g_integer_font_size > 1
		and panel.primary_value_font_size > panel.spd_digit_font_size
		and panel.hp_current_rect.size.y == PlayerInstrumentPanelScript.PRIMARY_VALUE_HEIGHT
		and panel.alt_value_rect.size.y == PlayerInstrumentPanelScript.PRIMARY_VALUE_HEIGHT
		and panel.g_integer_rect.size.y == PlayerInstrumentPanelScript.COMPACT_VALUE_HEIGHT
		and panel.spd_current_rect.size.y == PlayerInstrumentPanelScript.COMPACT_VALUE_HEIGHT
		and panel.spd_digit_rect(0).size.y == PlayerInstrumentPanelScript.COMPACT_VALUE_HEIGHT
		and panel.g_fraction_rect.size.y == PlayerInstrumentPanelScript.U_SIZE.y
		and panel.g_decimal_font_size == panel.primary_value_font_size)
	_check("SPD digit size preserves the complete widest zero inside every fixed cell",
		display_font.get_string_size("0", HORIZONTAL_ALIGNMENT_LEFT, -1.0,
			panel.spd_digit_font_size).x <= PlayerInstrumentPanelScript.SPD_DIGIT_WIDTH)
	_check("HP and ALT use fixed former-SPD cells without shrinking their 3u digit size",
		display_font.get_string_size("0", HORIZONTAL_ALIGNMENT_LEFT, -1.0,
			panel.primary_value_font_size).x <= PlayerInstrumentPanelScript.THREE_U_DIGIT_WIDTH
		and panel.hp_current_rect.size.x
			== PlayerInstrumentPanelScript.THREE_U_DIGIT_WIDTH * 3.0
		and panel.hp_digit_rect(0).position == panel.hp_current_rect.position
		and panel.hp_digit_rect(2).end == panel.hp_current_rect.end
		and panel.alt_digit_rect(0).position == panel.alt_value_rect.position
		and panel.alt_digit_rect(4).end == panel.alt_value_rect.end)
	_check("G keeps the 2u digit rule while SPD uses tighter two-q spacing",
		PlayerInstrumentPanelScript.SPD_DIGIT_COUNT == 5
		and PlayerInstrumentPanelScript.TWO_U_DIGIT_WIDTH
			== PlayerInstrumentPanelScript.U_SIZE.x
		and PlayerInstrumentPanelScript.SPD_DIGIT_WIDTH
			== PlayerInstrumentPanelScript.Q_SIZE.x * 2.0
		and PlayerInstrumentPanelScript.THREE_U_DIGIT_WIDTH
			== PlayerInstrumentPanelScript.U_SIZE.x
			+ PlayerInstrumentPanelScript.DECORATIVE_HALF_Q_WIDTH
		and panel.spd_current_rect.size.x
			== PlayerInstrumentPanelScript.SPD_DIGIT_WIDTH * 5.0
		and panel.spd_digit_rect(0).position == panel.spd_current_rect.position
		and panel.spd_digit_rect(4).end == panel.spd_current_rect.end)
	_check("SPD left and G right fill one 3u row without cutting the title row",
		panel.spd_rect.size.y == PlayerInstrumentPanelScript.U_SIZE.y * 3.0
		and panel.spd_speed_rect.position == panel.spd_rect.position
		and panel.spd_speed_rect.end.x == panel.g_rect.position.x
		and panel.g_rect.end == panel.spd_rect.end
		and panel.spd_title_rect.position == panel.spd_speed_rect.position
		and panel.spd_title_rect.size
			== Vector2(panel.spd_speed_rect.size.x, PlayerInstrumentPanelScript.U_SIZE.y)
		and panel.spd_blank_rect.position.x == panel.spd_current_rect.end.x
		and panel.spd_blank_rect.position.y == panel.spd_title_rect.end.y
		and panel.spd_blank_rect.size
			== Vector2(PlayerInstrumentPanelScript.Q_SIZE.x
				+ (PlayerInstrumentPanelScript.TWO_U_DIGIT_WIDTH
					- PlayerInstrumentPanelScript.SPD_DIGIT_WIDTH) * 5.0,
				PlayerInstrumentPanelScript.COMPACT_VALUE_HEIGHT)
		and panel.spd_unit_kt_rect.position.y == panel.spd_title_rect.end.y
		and panel.spd_unit_kmh_rect.end.y == panel.spd_rect.end.y)
	_check("SPD zero padding and five-digit overflow states are deterministic",
		PlayerInstrumentPanelScript.formatted_speed_digits(500) == "00500"
		and PlayerInstrumentPanelScript.speed_digit_is_padding("00500", 0)
		and PlayerInstrumentPanelScript.speed_digit_is_padding("00500", 1)
		and not PlayerInstrumentPanelScript.speed_digit_is_padding("00500", 2)
		and not PlayerInstrumentPanelScript.speed_digit_is_padding("00500", 3)
		and PlayerInstrumentPanelScript.formatted_speed_digits(100000) == "99999"
		and PlayerInstrumentPanelScript.speed_value_overflows(100000))
	var overflow_red := PlayerInstrumentPanelScript.speed_digit_color(
		"99999", 0, true, true, Color.GREEN)
	var overflow_off := PlayerInstrumentPanelScript.speed_digit_color(
		"99999", 0, true, false, Color.GREEN)
	_check("SPD padding is 75 percent black and overflow blinks red",
		PlayerInstrumentPanelScript.speed_digit_color(
			"00500", 0, false, true, Color.GREEN).is_equal_approx(
				PlayerInstrumentPanelScript.SPD_PADDING_ZERO_COLOR)
		and overflow_red.is_equal_approx(PlayerInstrumentPanelScript.DANGER_RED)
		and is_zero_approx(overflow_off.a))
	_check("G uses two compact 2u integer cells and unchanged bottom decimal division",
		panel.g_rect.size.y == PlayerInstrumentPanelScript.U_SIZE.y * 3.0
		and panel.g_integer_rect.size.y == PlayerInstrumentPanelScript.U_SIZE.y * 2.0
		and panel.g_integer_rect.size.x == PlayerInstrumentPanelScript.TWO_U_DIGIT_WIDTH * 2.0
		and panel.g_integer_digit_rect(0).size
			== Vector2(PlayerInstrumentPanelScript.TWO_U_DIGIT_WIDTH,
				PlayerInstrumentPanelScript.COMPACT_VALUE_HEIGHT)
		and panel.g_integer_digit_rect(1).end == panel.g_integer_rect.end
		and panel.g_decimal_rect.size == PlayerInstrumentPanelScript.Q_SIZE
		and panel.g_decimal_font_size == panel.primary_value_font_size
		and PlayerInstrumentPanelScript.G_INTEGER_ALIGNMENT == HORIZONTAL_ALIGNMENT_CENTER
		and panel.g_decimal_rect.end.y == panel.g_rect.end.y
		and panel.g_fraction_rect.size.y == PlayerInstrumentPanelScript.U_SIZE.y
		and panel.g_fraction_rect.end.y == panel.g_rect.end.y
		and panel.g_integer_rect.end.x == panel.g_decimal_rect.position.x
		and panel.g_decimal_rect.end.x == panel.g_fraction_rect.position.x)
	_check("secondary maximum value expands by q steps and fills 2u height",
		panel.hp_max_rect.size.y == PlayerInstrumentPanelScript.SECONDARY_VALUE_HEIGHT
		and panel.hp_max_rect.size.x > PlayerInstrumentPanelScript.U_SIZE.x
		and is_equal_approx(fmod(
			panel.hp_max_rect.size.x - PlayerInstrumentPanelScript.U_SIZE.x,
			PlayerInstrumentPanelScript.Q_SIZE.x), 0.0)
		and display_font.get_string_size("999", HORIZONTAL_ALIGNMENT_LEFT, -1.0,
			panel.secondary_value_font_size).x <= panel.hp_max_rect.size.x)
	_check("HP current value is three framed digits and its right reserve is frameless",
		PlayerInstrumentPanelScript.formatted_three_digit_value(7) == "007"
		and PlayerInstrumentPanelScript.formatted_three_digit_value(1200) == "999"
		and panel.hp_title_rect.position == panel.hp_rect.position
		and panel.hp_title_rect.size
			== Vector2(panel.hp_rect.size.x, PlayerInstrumentPanelScript.U_SIZE.y)
		and panel.hp_empty_rect.position.x == panel.hp_value_rect.end.x
		and panel.hp_empty_rect.position.y == panel.hp_title_rect.end.y
		and panel.hp_empty_rect.end.x == panel.hp_rect.end.x
		and panel.hp_empty_rect.end.y == panel.hp_rect.end.y
		and panel.grid_regions(false).has(panel.hp_digit_rect(0))
		and panel.grid_regions(false).has(panel.hp_digit_rect(2))
		and not panel.grid_regions(false).has(panel.hp_empty_rect))
	_check("ALT returns to nominal width with a compact gauge and 1u mode cells",
		panel.alt_rect.size.y == PlayerInstrumentPanelScript.U_SIZE.y * 4.0
		and panel.alt_gauge_rect.size
			== Vector2(PlayerInstrumentPanelScript.U_SIZE.x * 2.0
				+ PlayerInstrumentPanelScript.Q_SIZE.x,
				PlayerInstrumentPanelScript.PRIMARY_VALUE_HEIGHT)
		and panel.alt_gauge_rect.end.x == panel.alt_value_rect.position.x
		and panel.alt_value_rect.size
			== Vector2(PlayerInstrumentPanelScript.THREE_U_DIGIT_WIDTH * 5.0,
				PlayerInstrumentPanelScript.PRIMARY_VALUE_HEIGHT)
		and panel.alt_value_rect.end.x == panel.alt_mode_high_rect.position.x
		and panel.alt_mode_high_rect.size
			== PlayerInstrumentPanelScript.U_SIZE
		and panel.alt_mode_low_rect.position.y == panel.alt_mode_high_rect.end.y
		and panel.alt_mode_low_rect.size == panel.alt_mode_high_rect.size
		and panel.alt_mode_empty_rect.position.y == panel.alt_mode_low_rect.end.y
		and panel.alt_mode_empty_rect.end == panel.alt_rect.end)
	_check("HP and compact SPD G share nominal-width half-u decorative rows",
		panel.hp_decorative_rect.position
			== Vector2(panel.spd_rect.position.x, panel.hp_rect.end.y)
		and panel.hp_decorative_rect.size
			== Vector2(panel.spd_rect.size.x,
				PlayerInstrumentPanelScript.DECORATIVE_HALF_U_HEIGHT)
		and panel.spd_rect.position.y == panel.hp_decorative_rect.end.y
		and panel.spd_decorative_rect.position
			== Vector2(panel.spd_rect.position.x, panel.spd_rect.end.y)
		and panel.spd_decorative_rect.size == panel.hp_decorative_rect.size
		and panel.alt_rect.position.y == panel.spd_decorative_rect.end.y
		and panel.alt_rect.end.x == panel.spd_decorative_rect.end.x
		and panel.alt_rect.size.x == panel.spd_decorative_rect.size.x
		and panel.ab_rect.position.y == panel.alt_rect.end.y)
	_check("afterburner is 2u with a 1u title and a fixed 2u by 2u percent board",
		panel.ab_rect.size.y == PlayerInstrumentPanelScript.PROGRESS_PANEL_HEIGHT
		and panel.ab_title_rect.size.y == PlayerInstrumentPanelScript.PROGRESS_INFO_HEIGHT
		and panel.ab_percent_rect.size == PlayerInstrumentPanelScript.PROGRESS_PERCENT_SIZE
		and panel.ab_progress_rect.size.y == PlayerInstrumentPanelScript.U_SIZE.y
		and panel.ab_progress_rect.position.y == panel.ab_title_rect.end.y
		and panel.ab_progress_rect.end.x == panel.ab_percent_rect.position.x
		and panel.ab_percent_rect.end.x == panel.ab_rect.end.x)
	_check("roll maneuver uses the same title percent and bottom-bar layout",
		panel.maneuver_title_rect(panel.maneuver_base_rect).size.y
			== PlayerInstrumentPanelScript.PROGRESS_INFO_HEIGHT
		and panel.maneuver_percent_rect(panel.maneuver_base_rect).size
			== PlayerInstrumentPanelScript.PROGRESS_PERCENT_SIZE
		and panel.maneuver_percent_rect(panel.maneuver_base_rect).end.x
			== panel.maneuver_base_rect.end.x
		and panel.maneuver_progress_rect(panel.maneuver_base_rect).size.y
			== PlayerInstrumentPanelScript.U_SIZE.y
		and panel.maneuver_base_rect.size.x == panel.aligned_content_width)
	_check("compact SPD G and revised ALT both use the 383px nominal width",
		PlayerInstrumentPanelScript.DECORATIVE_HALF_Q_WIDTH
			== PlayerInstrumentPanelScript.Q_SIZE.x * 0.5
		and PlayerInstrumentPanelScript.DECORATIVE_HALF_U_HEIGHT
			== PlayerInstrumentPanelScript.U_SIZE.y * 0.5
		and panel.aligned_content_width == 383.0
		and panel.spd_rect.size.x == panel.aligned_content_width
		and panel.spd_rect.position.x == panel.ab_rect.position.x
		and panel.g_fraction_rect.size.x == 27.0
		and panel.spd_blank_rect.size.x == 38.0
		and panel.alt_rect.size.x == panel.aligned_content_width
		and panel.alt_rect.position.x == panel.spd_rect.position.x
		and panel.hp_rect.position.x == panel.ab_rect.position.x
		and panel.autopilot_rect.position.x == panel.ab_rect.position.x
		and panel.maneuver_base_rect.position.x == panel.ab_rect.position.x
		and panel.weapon_rect.position.x == panel.ab_rect.position.x)
	_check("ENGAGE and FIRE are children of one aligned AUTOPILOT parent panel",
		panel.autopilot_rect.size.x == PlayerInstrumentPanelScript.AUTOPILOT_WIDTH
		and panel.autopilot_rect.size.x == PlayerInstrumentPanelScript.U_SIZE.x * 3.0
		and panel.engage_rect.position == panel.autopilot_rect.position
		and panel.engage_rect.size.x == panel.autopilot_rect.size.x
		and panel.fire_rect.position.y == panel.engage_rect.end.y
		and panel.fire_rect.size.x == panel.autopilot_rect.size.x
		and panel.fire_rect.end == panel.autopilot_rect.end)
	_check("structural empty panel bridges AUTOPILOT to FLR and can surrender one q",
		panel.control_empty_rect.position.x == panel.autopilot_rect.end.x
		and panel.control_empty_rect.end.x == panel.flare_base_rect.position.x
		and panel.control_empty_rect.size.x >= PlayerInstrumentPanelScript.Q_SIZE.x
		and panel.active_control_empty_rect(true).size.x
			== panel.control_empty_rect.size.x - PlayerInstrumentPanelScript.Q_SIZE.x)
	_check("Q rejoins the nominal E G F T key column",
		PlayerInstrumentPanelScript.keycap_left_of(panel.alt_rect).position.x
			== panel.alt_rect.position.x - PlayerInstrumentPanelScript.Q_SIZE.x
		and PlayerInstrumentPanelScript.keycap_left_of(panel.alt_rect).position.x
			== PlayerInstrumentPanelScript.keycap_left_of(panel.ab_rect).position.x
		and PlayerInstrumentPanelScript.keycap_left_of(panel.ab_rect).position.x
			== PlayerInstrumentPanelScript.keycap_left_of(panel.engage_rect).position.x
		and PlayerInstrumentPanelScript.keycap_left_of(panel.engage_rect).position.x
			== PlayerInstrumentPanelScript.keycap_left_of(panel.maneuver_base_rect).position.x
		and PlayerInstrumentPanelScript.keycap_left_of(panel.maneuver_base_rect).position.x
			== PlayerInstrumentPanelScript.keycap_left_of(panel.weapon_title_rect).position.x)
	var inset_track := PlayerInstrumentPanelScript.progress_inner_track(panel.ab_progress_rect)
	_check("progress fill uses a visible four-pixel inward inset",
		PlayerInstrumentPanelScript.PROGRESS_INNER_INSET == 4.0
		and inset_track.position == panel.ab_progress_rect.position + Vector2(4.0, 4.0)
		and inset_track.size == panel.ab_progress_rect.size - Vector2(8.0, 8.0))
	_check("all operation keys are independent 1q cells at their row top",
		PlayerInstrumentPanelScript.keycap_left_of(panel.ab_rect).size
			== PlayerInstrumentPanelScript.Q_SIZE
		and panel.maneuver_key_rect().size == PlayerInstrumentPanelScript.Q_SIZE
		and panel.maneuver_key_rect().position.y == panel.maneuver_base_rect.position.y
		and panel.manual_flare_key_rect().position.y == panel.flare_base_rect.position.y)
	_check("internal R insertion consumes the empty panel without moving AUTOPILOT or FLR",
		panel.active_flare_rect(true) == panel.flare_base_rect
		and panel.active_autopilot_rect(true) == panel.autopilot_rect
		and panel.active_engage_rect(true) == panel.engage_rect
		and panel.active_fire_rect(true) == panel.fire_rect
		and panel.active_fire_rect(true).end == panel.active_autopilot_rect(true).end
		and panel.active_control_empty_rect(true).position
			== panel.control_empty_rect.position
		and panel.active_control_empty_rect(true).size.x
			== panel.control_empty_rect.size.x - PlayerInstrumentPanelScript.Q_SIZE.x
		and panel.active_control_empty_rect(true).end.x
			== panel.manual_flare_key_rect().position.x
		and panel.active_maneuver_rect(true, true) == panel.maneuver_base_rect
		and panel.manual_flare_key_rect().end.x == panel.flare_base_rect.position.x)
	_check("all expandable rows preserve the shared screen-side right edge",
		panel.hp_rect.end.x == panel.size.x
		and panel.spd_rect.end.x == panel.size.x
		and panel.alt_rect.end.x == panel.size.x
		and panel.ab_rect.end.x == panel.size.x
		and panel.flare_base_rect.end.x == panel.size.x
		and panel.maneuver_base_rect.end.x == panel.size.x
		and panel.weapon_rect.end.x == panel.size.x)
	_check("SPD and ALT five digit cells are individually included in the shared grid",
		panel.grid_regions(false).has(panel.spd_digit_rect(0))
		and panel.grid_regions(false).has(panel.spd_digit_rect(4))
		and panel.grid_regions(false).has(panel.alt_digit_rect(0))
		and panel.grid_regions(false).has(panel.alt_digit_rect(4)))
	var ac := _make_aircraft()
	ac.displacement_roll_active = true
	panel.aircraft = ac
	_check("F7 manual flare grant switches the R skill and starts its key",
		panel.debug_grant_manual_flare_skill()
		and ac.manual_dodge_active
		and not ac.displacement_roll_active
		and PlayerInstrumentPanelScript.manual_flare_key_visible(ac))
	panel._manual_flare_key_flash_started_ms = 1000
	_check("new manual flare key alternates inverse state for exactly five seconds",
		panel.manual_flare_key_flash_on(1000)
		and not panel.manual_flare_key_flash_on(1500)
		and panel.manual_flare_key_flash_on(2000)
		and not panel.manual_flare_key_flash_on(6000))
	var player_regions: Array[Rect2] = panel.grid_regions(true, true)
	var active_flare := panel.active_flare_rect(true)
	_check("grid frames active cells while HP reserve and supplemental boards stay borderless",
		player_regions.has(panel.hp_rect)
		and player_regions.has(panel.ab_title_rect)
		and player_regions.has(panel.ab_percent_rect)
		and player_regions.has(panel.ab_progress_rect)
		and player_regions.has(panel.active_autopilot_rect(true))
		and player_regions.has(panel.active_control_empty_rect(true))
		and player_regions.has(panel.weapon_title_rect)
		and player_regions.has(panel.hp_decorative_rect)
		and player_regions.has(panel.spd_decorative_rect)
		and player_regions.has(panel.manual_flare_key_rect())
		and player_regions.has(panel.g_integer_digit_rect(0))
		and player_regions.has(panel.g_integer_digit_rect(1))
		and player_regions.has(panel.g_decimal_rect)
		and player_regions.has(panel.hp_digit_rect(0))
		and not player_regions.has(panel.hp_empty_rect)
		and player_regions.has(panel.spd_blank_rect)
		and player_regions.has(panel.alt_gauge_rect)
		and player_regions.has(panel.alt_mode_high_rect)
		and player_regions.has(panel.alt_mode_low_rect)
		and player_regions.has(PlayerInstrumentPanelScript.flare_current_digit_rect(
			active_flare, 0))
		and player_regions.has(PlayerInstrumentPanelScript.flare_current_digit_rect(
			active_flare, 1))
		and player_regions.has(PlayerInstrumentPanelScript.flare_title_rect(active_flare))
		and not player_regions.has(panel.hp_current_rect)
		and not player_regions.has(panel.g_fraction_rect)
		and not player_regions.has(panel.hp_separator_rect)
		and not player_regions.has(panel.hp_max_rect)
		and not player_regions.has(PlayerInstrumentPanelScript.flare_current_rect(active_flare)))
	_check("weapon group begins after a framed half-u spacer and a standalone 1u title",
		panel.weapon_spacer_rect.position.y == panel.maneuver_base_rect.end.y
		and panel.weapon_spacer_rect.size.y
			== PlayerInstrumentPanelScript.DECORATIVE_HALF_U_HEIGHT
		and player_regions.has(panel.weapon_spacer_rect)
		and panel.weapon_title_rect.position.y == panel.weapon_spacer_rect.end.y
		and panel.weapon_title_rect.size.y == PlayerInstrumentPanelScript.U_SIZE.y
		and panel.weapon_rect.position.y == panel.weapon_title_rect.end.y
		and PlayerInstrumentPanelScript.keycap_left_of(panel.weapon_title_rect).position.y
			== panel.weapon_title_rect.position.y
		and PlayerInstrumentPanelScript.keycap_left_of(panel.weapon_title_rect).end.y
			== panel.weapon_title_rect.end.y)
	_check("two 3u weapon slots are separated by one framed half-u board",
		panel.weapon_row_rect(0).size.y == PlayerInstrumentPanelScript.U_SIZE.y * 3.0
		and panel.weapon_row_rect(1).size.y == PlayerInstrumentPanelScript.U_SIZE.y * 3.0
		and panel.weapon_row_rect(0).end.y == panel.weapon_middle_spacer_rect.position.y
		and panel.weapon_middle_spacer_rect.size.y
			== PlayerInstrumentPanelScript.DECORATIVE_HALF_U_HEIGHT
		and panel.weapon_middle_spacer_rect.end.y == panel.weapon_row_rect(1).position.y
		and player_regions.has(panel.weapon_middle_spacer_rect)
		and panel.size == Vector2(401.0, PlayerInstrumentPanelScript.U_SIZE.y * 31.0)
		and panel.weapon_rect.end.y == panel.size.y)
	_check("only the selected weapon value boards invert and reload at 2 Hz",
		PlayerInstrumentPanelScript.weapon_value_inverted(true, false, false)
		and PlayerInstrumentPanelScript.weapon_value_inverted(true, true, true)
		and not PlayerInstrumentPanelScript.weapon_value_inverted(true, true, false)
		and not PlayerInstrumentPanelScript.weapon_value_inverted(false, true, true))
	_check("3u weapon slots use count, a 2u dual-readout plus bottom bar, and right name",
		panel.weapon_count_rect(0).position == panel.weapon_row_rect(0).position
		and panel.weapon_count_rect(0).size.y
			== PlayerInstrumentPanelScript.WEAPON_SLOT_HEIGHT
		and panel.weapon_count_rect(0).size.x == panel.weapon_count_width
		and panel.weapon_name_rect(0).size
			== Vector2(PlayerInstrumentPanelScript.U_SIZE.x * 2.0,
				PlayerInstrumentPanelScript.U_SIZE.y * 3.0)
		and panel.weapon_name_rect(0).end == panel.weapon_row_rect(0).end
		and panel.weapon_empty_rect(0).position.x == panel.weapon_count_rect(0).end.x
		and panel.weapon_empty_rect(0).end.x == panel.weapon_name_rect(0).position.x
		and panel.weapon_reload_percent_rect(0).position
			== panel.weapon_empty_rect(0).position
		and panel.weapon_reload_percent_rect(0).size
			== PlayerInstrumentPanelScript.WEAPON_RELOAD_VALUE_SIZE
		and panel.weapon_reload_remaining_rect(0).size
			== panel.weapon_reload_percent_rect(0).size
		and panel.weapon_reload_remaining_rect(0).end.x
			== panel.weapon_empty_rect(0).end.x
		and panel.weapon_reload_percent_rect(0).end.x
			<= panel.weapon_reload_remaining_rect(0).position.x
		and panel.weapon_reload_progress_rect(0).size
			== Vector2(panel.weapon_empty_rect(0).size.x,
				PlayerInstrumentPanelScript.U_SIZE.y)
		and panel.weapon_reload_progress_rect(0).position.y
			== panel.weapon_empty_rect(0).end.y - PlayerInstrumentPanelScript.U_SIZE.y
		and panel.weapon_reload_progress_rect(0).end
			== panel.weapon_empty_rect(0).end
		and player_regions.has(panel.weapon_reload_percent_rect(0))
		and player_regions.has(panel.weapon_reload_remaining_rect(0))
		and player_regions.has(panel.weapon_reload_progress_rect(0)))
	_check("weapon reload readouts share formatting and account for actual reload rate",
		PlayerInstrumentPanelScript.weapon_reload_percent_text(0.62) == "62%"
		and PlayerInstrumentPanelScript.weapon_reload_seconds_text(7.6) == "8s"
		and is_equal_approx(PlayerInstrumentPanelScript.weapon_reload_remaining_seconds(
			0.62, 20.0, 1.0), 7.6)
		and is_equal_approx(PlayerInstrumentPanelScript.weapon_reload_remaining_seconds(
			0.5, 20.0, 2.0), 5.0)
		and PlayerInstrumentPanelScript.weapon_reload_seconds_text(0.0) == "0s")
	_check("G and FLR two-digit formatting stays zero-padded and bounded",
		PlayerInstrumentPanelScript.formatted_two_digit_value(1) == "01"
		and PlayerInstrumentPanelScript.formatted_two_digit_value(11) == "11"
		and PlayerInstrumentPanelScript.formatted_two_digit_value(120) == "99")
	_check("wingman slot keys remain independent 1q cells",
		WingmanInstrumentPanelScript.SLOT_FONT_SIZE == 15
		and WingmanInstrumentPanelScript.SLOT_KEY_SIZE == Vector2(18.0, 18.0)
		and WingmanInstrumentPanelScript.ROW_STRIDE == 54.0)
	var wing_regions: Array[Rect2] = WingmanInstrumentPanelScript.grid_regions(2)
	_check("相邻僚机行复用同一条水平边界",
		wing_regions[0].end.y == wing_regions[3].position.y)
	ac.free()
	panel.free()


func _test_milestone_axis_counter() -> void:
	var counter = MilestoneAxisCounterScript.new()
	counter._ready()
	_check("三方向以等宽 2u 面板、固定名框和八个 0.5q 技能格排列",
		counter.size == Vector2(408.0, 36.0)
		and MilestoneAxisCounterScript.cell_rect(0) == Rect2(0.0, 0.0, 136.0, 36.0)
		and MilestoneAxisCounterScript.cell_rect(1) == Rect2(136.0, 0.0, 136.0, 36.0)
		and MilestoneAxisCounterScript.cell_rect(2) == Rect2(272.0, 0.0, 136.0, 36.0)
		and MilestoneAxisCounterScript.name_rect(0).size == Vector2(64.0, 36.0)
		and MilestoneAxisCounterScript.point_rect(0, 0).size == Vector2(9.0, 36.0)
		and MilestoneAxisCounterScript.point_rect(0, 7).end.x
			== MilestoneAxisCounterScript.cell_rect(0).end.x)
	_check("英文最长三方向名使用固定缩写",
		MilestoneAxisCounterScript.english_axis_label(SurvivorData.AXIS_GLADIATOR) == "GLAD."
		and MilestoneAxisCounterScript.english_axis_label(SurvivorData.AXIS_KNIGHT) == "KNIGHT"
		and MilestoneAxisCounterScript.english_axis_label(SurvivorData.AXIS_SCHEMER) == "SCHEM.")
	_check("三轴计数器鼠标穿透且不自带逐帧处理",
		counter.mouse_filter == Control.MOUSE_FILTER_IGNORE
		and counter.focus_mode == Control.FOCUS_NONE
		and not counter.is_processing())

	var player := SurvivorPlayer.new()
	player.axis_points[SurvivorData.AXIS_GLADIATOR] = 2
	player.axis_points[SurvivorData.AXIS_KNIGHT] = 1
	player.axis_points[SurvivorData.AXIS_SCHEMER] = 4
	player.milestone_bonus[SurvivorData.AXIS_GLADIATOR] = 1
	player.milestone_bonus[SurvivorData.AXIS_KNIGHT] = 1
	var snapshot := MilestoneAxisCounterScript.snapshot_for(player)
	_check("三方向技能格只读取玩家实际点击数量，不混入里程碑加成",
		snapshot == [2, 1, 4])
	counter.update_display(player)
	var revision: int = counter._redraw_revision
	counter.update_display(player)
	_check("三轴读数不变时不重复请求重绘", counter._redraw_revision == revision)
	player.axis_points[SurvivorData.AXIS_SCHEMER] = 24
	counter.update_display(player)
	_check("超过八点只钳制亮格、不扩张三方向计数器",
		counter._values == [2, 1, 24]
		and counter.size == MilestoneAxisCounterScript.COUNTER_SIZE)
	var bottom = BottomExperiencePanelScript.new()
	bottom._ready()
	player.level = 12
	player.xp = 84
	player.xp_to_next = 160
	bottom.update_display(player)
	bottom._accent = Color.TRANSPARENT
	bottom.update_display(player)
	_check("底栏中央为 2u 三方向加 1u 经验条，两侧为等宽 3u 面板",
		bottom.size == Vector2(684.0, 54.0)
		and bottom._grid_overlay.edge_insets == Vector4(0.5, 0.5, 0.5, 0.5)
		and bottom._accent.is_equal_approx(HudPreferencesScript.hud_color())
		and BottomExperiencePanelScript.left_panel_rect().size
			== BottomExperiencePanelScript.right_panel_rect().size
		and BottomExperiencePanelScript.LEVEL_DIGIT_WIDTH
			== PlayerInstrumentPanelScript.THREE_U_DIGIT_WIDTH
		and BottomExperiencePanelScript.xp_rect() == Rect2(138.0, 36.0, 408.0, 18.0)
		and BottomExperiencePanelScript.current_xp_rect() == Rect2(546.0, 0.0, 138.0, 36.0)
		and BottomExperiencePanelScript.max_xp_rect() == Rect2(546.0, 36.0, 138.0, 18.0))
	var level_accent := Color.WHITE
	_check("LV 两位数字复用框版前导零灰色规则且不与经验区重叠",
		BottomExperiencePanelScript.formatted_level_digits(0) == "00"
		and BottomExperiencePanelScript.formatted_level_digits(7) == "07"
		and BottomExperiencePanelScript.level_digit_color(
			"00", 0, level_accent, false).is_equal_approx(
				ThemeColors.UI_INACTIVE_DIGIT)
		and BottomExperiencePanelScript.level_digit_color(
			"00", 1, level_accent, false).is_equal_approx(level_accent)
		and BottomExperiencePanelScript.level_digit_color(
			"10", 1, level_accent, false).is_equal_approx(level_accent)
		and bottom._display_font.get_string_size("0", HORIZONTAL_ALIGNMENT_LEFT,
			-1.0, int(TerminalTextScript.resolve_font_layout(
				bottom._display_font, "0",
				BottomExperiencePanelScript.level_digit_rect(0).size).x)).x
			<= BottomExperiencePanelScript.LEVEL_DIGIT_WIDTH
		and BottomExperiencePanelScript.level_digit_rect(1).end.x
			== BottomExperiencePanelScript.xp_rect().position.x
		and not BottomExperiencePanelScript.level_digit_rect(1).intersects(
			BottomExperiencePanelScript.xp_rect()))
	_check("升级反色按等级、经验条、经验数字从左到右依次闪过一次",
		BottomExperiencePanelScript.flash_index_at(0.0) == 0
		and BottomExperiencePanelScript.flash_index_at(0.15) == 1
		and BottomExperiencePanelScript.flash_index_at(0.29) == 2
		and BottomExperiencePanelScript.flash_index_at(1.0) == -1)
	bottom.free()
	player.free()
	counter.free()


func _test_progress_color_contract() -> void:
	var accent := Color("53d13a")
	_check("进度超过一半使用 HUD 强调色",
		PlayerInstrumentPanelScript.progress_color(0.51, accent).is_equal_approx(accent))
	_check("进度一半及以下使用警戒黄",
		PlayerInstrumentPanelScript.progress_color(0.50, accent).is_equal_approx(
			PlayerInstrumentPanelScript.WARNING_YELLOW))
	_check("进度两成及以下使用危险红",
		PlayerInstrumentPanelScript.progress_color(0.20, accent).is_equal_approx(
			PlayerInstrumentPanelScript.DANGER_RED))
	_check("冷却条按接近 READY 的完成度增长",
		is_equal_approx(PlayerInstrumentPanelScript.cooldown_ready_ratio(12.0, 15.0), 0.20)
		and is_equal_approx(PlayerInstrumentPanelScript.cooldown_ready_ratio(0.0, 15.0), 1.0))


func _test_altitude_preference_display() -> void:
	var ac := _make_aircraft()
	ac.altitude = 2000.0
	_check("ALT 明确显示当前低空档",
		PlayerInstrumentPanelScript.altitude_tier_name_key(ac) == "HUD_ALT_TIER_LOW")
	ac.altitude = 5500.0
	_check("ALT 明确显示当前中空档",
		PlayerInstrumentPanelScript.altitude_tier_name_key(ac) == "HUD_ALT_TIER_MID")
	ac.altitude = 10000.0
	_check("ALT 明确显示当前高空档",
		PlayerInstrumentPanelScript.altitude_tier_name_key(ac) == "HUD_ALT_TIER_HIGH")
	ac.altitude_preference = Aircraft.AltitudePreference.PREFER_CLIMB
	_check("Q 爬升优先显示固定正式字体 HIGH",
		PlayerInstrumentPanelScript.altitude_preference_name_key(ac) == "TOOLTIP_ALT_CLIMB_TITLE"
		and PlayerInstrumentPanelScript.altitude_mode_text(ac) == "HIGH")
	SurvivorModeScript._cycle_player_altitude_preference(ac)
	_check("Q 保留爬升优先到低空优先的真实切换",
		ac.altitude_preference == Aircraft.AltitudePreference.PREFER_LOW)
	_check("Q 低空优先显示固定正式字体 LOW",
		PlayerInstrumentPanelScript.altitude_preference_name_key(ac) == "TOOLTIP_ALT_LOW_TITLE"
		and PlayerInstrumentPanelScript.altitude_mode_text(ac) == "LOW")
	SurvivorModeScript._cycle_player_altitude_preference(ac)
	_check("Q 再按返回爬升优先",
		ac.altitude_preference == Aircraft.AltitudePreference.PREFER_CLIMB)
	_check("高度指针严格使用 20 到 160 度并让 LOW HIGH 分居左右",
		is_equal_approx(PlayerInstrumentPanelScript.altimeter_target_degrees(0.0, true), 20.0)
		and is_equal_approx(PlayerInstrumentPanelScript.altimeter_target_degrees(20000.0, true), 85.0)
		and is_equal_approx(PlayerInstrumentPanelScript.altimeter_target_degrees(0.0, false), 95.0)
		and is_equal_approx(PlayerInstrumentPanelScript.altimeter_target_degrees(
			20000.0, false), 160.0)
		and is_equal_approx(PlayerInstrumentPanelScript.altimeter_target_degrees(
			10000.0, true), 52.5)
		and is_equal_approx(PlayerInstrumentPanelScript.altimeter_target_degrees(
			10000.0, false), 127.5))
	var panel = PlayerInstrumentPanelScript.new()
	panel._ready()
	panel.aircraft = ac
	ac.altitude = 20000.0
	panel._altimeter_needle_initialized = true
	panel._altimeter_needle_degrees = 20.0
	panel._process(0.1)
	_check("高度指针按角速度追随而不是瞬间跳到目标",
		panel._altimeter_needle_degrees > 20.0
		and panel._altimeter_needle_degrees < 160.0)
	panel.free()
	ac.free()


func _test_special_weapon_status() -> void:
	_check("自动驾驶和开火关闭态使用明确动作文字",
		PlayerInstrumentPanelScript.engage_state_key(true) == "HUD_ENGAGE"
		and PlayerInstrumentPanelScript.engage_state_key(false) == "HUD_PASSIVE"
		and PlayerInstrumentPanelScript.fire_state_key(true) == "HUD_AUTO_FIRE"
		and PlayerInstrumentPanelScript.fire_state_key(false) == "HUD_MANUAL_FIRE")
	var ac := _make_aircraft()
	ac.params.secondary_missile = MissileParams.new()
	ac.params.secondary_missile.max_count = 4
	ac.params.secondary_missile.cooldown = 3.0
	ac.secondary_missiles_remaining = 2
	ac._secondary_cooldown = 1.5
	ac.params.rocket = RocketParams.new()
	ac.params.rocket.max_ammo = 24
	ac.params.rocket.burst_cooldown = 4.0
	ac.rockets_remaining = 12
	ac._rocket_burst_cooldown = 1.0
	var rows := PlayerInstrumentPanelScript.special_weapon_rows(ac)
	_check("战区 SP 导弹在主武器下生成真实冷却状态",
		rows.size() == 2
		and rows[0].get("kind") == "secondary_missile"
		and rows[0].get("state") == "cooldown"
		and is_equal_approx(float(rows[0].get("remaining_s")), 1.5)
		and is_equal_approx(float(rows[0].get("ready_ratio")), 0.5))
	var panel = PlayerInstrumentPanelScript.new()
	panel._ready()
	panel.update_display(ac, null)
	var special_row := panel.special_weapon_row_rect(0)
	var special_status := panel.special_weapon_status_rect(0)
	var special_progress := panel.special_weapon_progress_rect(0)
	var special_name := panel.special_weapon_name_rect(0)
	var second_special := panel.special_weapon_row_rect(1)
	_check("SP 区按 0.5u 分隔标题和 2u 网格行向下扩展",
		panel.special_weapon_spacer_rect.position.y == panel.weapon_rect.end.y
		and panel.special_weapon_spacer_rect.size.y
			== PlayerInstrumentPanelScript.DECORATIVE_HALF_U_HEIGHT
		and panel.special_weapon_title_rect.position.y == panel.special_weapon_spacer_rect.end.y
		and special_row.position.y == panel.special_weapon_title_rect.end.y
		and special_row.size.y
			== PlayerInstrumentPanelScript.SPECIAL_WEAPON_SLOT_HEIGHT
		and special_row.size.y == PlayerInstrumentPanelScript.U_SIZE.y * 2.0
		and special_name.end == special_row.end
		and panel.size.y == PlayerInstrumentPanelScript.PANEL_SIZE.y
			+ PlayerInstrumentPanelScript.DECORATIVE_HALF_U_HEIGHT
			+ PlayerInstrumentPanelScript.SPECIAL_WEAPON_TITLE_HEIGHT
			+ PlayerInstrumentPanelScript.SPECIAL_WEAPON_SLOT_HEIGHT)
	_check("SP 每格严格占 PRIORITY WEAPON 内容宽度的一半且一行容纳两件",
		special_row.size.x == panel.weapon_title_rect.size.x * 0.5
		and second_special.size == special_row.size
		and second_special.position == Vector2(special_row.end.x, special_row.position.y)
		and second_special.end.x == panel.special_weapon_rect.end.x)
	_check("SP 状态和横向进度各占 1u",
		special_status.position == special_row.position
		and special_status.size.y == PlayerInstrumentPanelScript.U_SIZE.y
		and special_progress.position.y == special_status.end.y
		and special_progress.size == special_status.size
		and special_progress.size.x > special_progress.size.y
		and special_progress.end.x == special_name.position.x
		and special_name.size == PlayerInstrumentPanelScript.U_SIZE * Vector2(2.0, 2.0))
	_check("SP 名称以最长五字母 QMAAM 作为次要信息排版基准",
		PlayerInstrumentPanelScript.SPECIAL_WEAPON_NAME_LAYOUT_TEXT == "QMAAM"
		and PlayerInstrumentPanelScript.SPECIAL_WEAPON_NAME_LAYOUT_TEXT.length() <= 5)
	var abbreviations_valid := true
	for locale in ["zh", "en", "ja"]:
		var translation := load("res://i18n/interface.%s.translation" % locale) as Translation
		for key in ["HUD_SP_MISSILE", "HUD_SP_ROCKET", "HUD_SP_RAILGUN",
				"HUD_SP_LASER", "HUD_SP_TAIL_MINE", "HUD_SP_DRONE", "HUD_SP_ESM"]:
			var abbreviation := str(translation.get_message(key)) if translation != null else ""
			abbreviations_valid = abbreviations_valid and not abbreviation.is_empty() \
				and abbreviation.length() <= 5 and abbreviation == abbreviation.to_upper()
	_check("全部 SP 武器在中英日资源中使用不超过五字母的英文简称", abbreviations_valid)
	ac._missile_reload_active = true
	ac.missile_reload_duration = 20.0
	ac._missile_reload_timer = 12.5
	_check("主导弹装填剩余秒数读取真实有效装填计时器",
		is_equal_approx(PlayerInstrumentPanelScript.missile_reload_remaining_s(ac), 7.5))
	panel.free()
	ac.free()


func _test_first_reveal_sequence() -> void:
	var sequencer = HudFirstRevealSequencerScript.new()
	var top_left := Control.new()
	var top_right := Control.new()
	var bottom_left := Control.new()
	sequencer.register_panel(&"bottom_left", [bottom_left], Vector2(0.0, 100.0))
	sequencer.register_panel(&"top_right", [top_right], Vector2(100.0, 0.0))
	sequencer.register_panel(&"top_left", [top_left], Vector2.ZERO)
	sequencer.update(0.0)
	sequencer.update(HudFirstRevealSequencerScript.PANEL_STAGGER)
	var overlaps_previous := sequencer.active_panel_ids().has(&"top_left") \
		and sequencer.active_panel_ids().has(&"top_right")
	sequencer.update(HudFirstRevealSequencerScript.PANEL_STAGGER)
	_check("HUD 首显按屏幕坐标从上到下且同一行从左到右启动",
		sequencer.start_history() == [&"top_left", &"top_right", &"bottom_left"])
	_check("下一框板快速错峰启动且不等待前一框板完成",
		overlaps_previous and not sequencer.panel_completed(&"top_left"))

	var blink_sequencer = HudFirstRevealSequencerScript.new()
	var blink_panel := Control.new()
	blink_sequencer.register_panel(&"blink", [blink_panel], Vector2.ZERO)
	blink_sequencer.update(0.0)
	blink_sequencer.update(HudFirstRevealSequencerScript.BLINK_HALF_PERIOD)
	var first_off := is_zero_approx(blink_panel.modulate.a)
	blink_sequencer.update(HudFirstRevealSequencerScript.BLINK_HALF_PERIOD)
	var first_on := is_equal_approx(blink_panel.modulate.a, 1.0)
	blink_sequencer.update(HudFirstRevealSequencerScript.BLINK_HALF_PERIOD)
	var second_off := is_zero_approx(blink_panel.modulate.a)
	blink_sequencer.update(HudFirstRevealSequencerScript.BLINK_HALF_PERIOD)
	_check("单框板在 0.50 秒内完成两闪后常亮",
		is_equal_approx(HudFirstRevealSequencerScript.BLINK_TOTAL_DURATION, 0.50)
		and first_off and first_on and second_off
		and blink_sequencer.panel_completed(&"blink")
		and is_equal_approx(blink_panel.modulate.a, 1.0))

	var board_source := Control.new()
	var board_child := Control.new()
	board_source.add_child(board_child)
	var board_visibility = HudBoardVisibilityScript.new(board_source)
	board_visibility.sync_regions([{
		"id": &"board",
		"rect": Rect2(0.0, 0.0, 40.0, 18.0),
	}])
	var source_starts_hidden := board_source.material is ShaderMaterial \
		and board_child.material is ShaderMaterial and board_source.get_child_count() == 1
	var hidden_rects: PackedVector4Array = (board_source.material as ShaderMaterial).get_shader_parameter(
		"board_rects")
	var border_bleed_hidden := hidden_rects[0] == Vector4(-1.0, -1.0, 41.0, 19.0)
	board_visibility.set_reveal_alpha(1.0, &"board")
	_check("复合仪表首帧默认关闭源框板且不创建黑底遮罩",
		source_starts_hidden and border_bleed_hidden
		and board_source.material == null and board_child.material == null)

	var callback_sequencer = HudFirstRevealSequencerScript.new()
	callback_sequencer.register_callback_panel(
		&"board",
		board_visibility.set_reveal_alpha.bind(&"board"),
		board_visibility.board_is_visible.bind(&"board"),
		Vector2.ZERO)
	callback_sequencer.update(0.0)
	callback_sequencer.update(HudFirstRevealSequencerScript.BLINK_TOTAL_DURATION)
	_check("首次显现调度器可直接驱动框板源可见性",
		callback_sequencer.panel_completed(&"board") and board_source.material == null)

	var dynamic_sequencer = HudFirstRevealSequencerScript.new()
	var dynamic_panel := Control.new()
	dynamic_panel.visible = false
	dynamic_sequencer.register_panel(&"dynamic", [dynamic_panel], Vector2.ZERO, false)
	dynamic_sequencer.update(0.0)
	_check("动态 HUD 空内容时不提前消费首次机会",
		dynamic_sequencer.active_panel_id().is_empty()
		and dynamic_sequencer.panel_start_count(&"dynamic") == 0)
	dynamic_panel.visible = true
	dynamic_sequencer.set_panel_available(&"dynamic", true)
	dynamic_sequencer.update(0.0)
	dynamic_panel.visible = false
	dynamic_sequencer.update(0.0)
	var canceled_restored := is_equal_approx(dynamic_panel.modulate.a, 1.0) \
		and not dynamic_sequencer.panel_completed(&"dynamic")
	dynamic_panel.visible = true
	dynamic_sequencer.update(0.0)
	dynamic_sequencer.update(HudFirstRevealSequencerScript.BLINK_TOTAL_DURATION)
	dynamic_panel.visible = false
	dynamic_sequencer.update(0.0)
	dynamic_panel.visible = true
	dynamic_sequencer.update(0.0)
	_check("动态 HUD 中途隐藏会重试且完成后不重播",
		canceled_restored
		and dynamic_sequencer.panel_completed(&"dynamic")
		and dynamic_sequencer.panel_start_count(&"dynamic") == 2
		and dynamic_sequencer.active_panel_id().is_empty()
		and is_equal_approx(dynamic_panel.modulate.a, 1.0))

	top_left.free()
	top_right.free()
	bottom_left.free()
	blink_panel.free()
	board_source.free()
	dynamic_panel.free()


func _test_weapon_priority_cycle() -> void:
	var ac := _make_aircraft()
	ac.params.missile = MissileParams.new()
	ac.params.gun = GunParams.new()
	ac.weapon_preference = Aircraft.WeaponPreference.PREFER_MISSILE
	SurvivorModeScript._cycle_player_weapon_preference(ac)
	_check("T 双武器 MSL→GUN", ac.weapon_preference == Aircraft.WeaponPreference.PREFER_GUN)
	SurvivorModeScript._cycle_player_weapon_preference(ac)
	_check("T 双武器 GUN→MSL", ac.weapon_preference == Aircraft.WeaponPreference.PREFER_MISSILE)

	ac.params.gun = null
	ac.weapon_preference = Aircraft.WeaponPreference.PREFER_GUN
	SurvivorModeScript._cycle_player_weapon_preference(ac)
	_check("T 跳过不存在的 GUN", ac.weapon_preference == Aircraft.WeaponPreference.PREFER_MISSILE)
	_check("单武器显示有效优先", PlayerInstrumentPanelScript.effective_weapon_preference(ac) \
		== Aircraft.WeaponPreference.PREFER_MISSILE)

	ac.params.missile = null
	var before := ac.weapon_preference
	SurvivorModeScript._cycle_player_weapon_preference(ac)
	_check("无基础武器 T 无操作", ac.weapon_preference == before)
	_check("无基础武器没有可见优先", PlayerInstrumentPanelScript.effective_weapon_preference(ac) == -1)
	ac.free()


func _test_flare_visual_progress() -> void:
	var counts := AircraftFlares.FLARE_VISUAL_WAVE_COUNTS
	var total := 0
	for count in counts:
		total += int(count)
	_check("视觉热诱弹保持六波", counts.size() == 6)
	_check("六波视觉热诱弹合计十枚", total == 10)

	var ac := _make_aircraft()
	ac.params.flare = FlareParams.new()
	ac.params.flare.max_flares = 3
	ac.flares_remaining = 2
	ac._flare_cooldown = 2.0
	AircraftFlares._queue_visual_burst(ac)
	_check("投放排入六个视觉波", ac._flare_spawn_queue.size() == 6)
	AircraftFlares._update_particles(ac, 0.0)
	_check("首波实际生成两枚并同帧熄灭两星",
		ac.flare_visual_burst_emitted == 2
		and PlayerInstrumentPanelScript.flare_lit_star_count(ac) == 8)
	for _i in range(5):
		AircraftFlares._update_particles(ac, 0.12)
	_check("最后一波后严格生成十枚", ac.flare_visual_burst_emitted == 10
		and ac._flare_particles.size() == 10)
	_check("短冷却期间十星保持全灭", PlayerInstrumentPanelScript.flare_lit_star_count(ac) == 0)
	ac._flare_cooldown = 0.0
	_check("短冷却结束十星一次全亮", PlayerInstrumentPanelScript.flare_lit_star_count(ac) == 10)

	ac.enable_flare_reload = true
	ac.flares_remaining = 0
	ac._flare_cooldown = 10.0
	ac.flare_reload_progress = 0.49
	_check("长装填按进度逐星点亮", PlayerInstrumentPanelScript.flare_lit_star_count(ac) == 5)
	ac.flare_reload_progress = 0.91
	_check("装填末段十星先填满且数字仍为零",
		PlayerInstrumentPanelScript.flare_lit_star_count(ac) == 10 and ac.flares_remaining == 0)
	ac.free()


func _test_unique_r_maneuver_cooldown() -> void:
	var cases := [
		[&"cobra_skill", Aircraft.COBRA_SKILL_COOLDOWN],
		[&"evasion_herbst", HerbstManeuver.COOLDOWN],
		[&"manual_dodge", Aircraft.MANUAL_DODGE_CD],
		[&"displacement_roll", Aircraft.DISPLACEMENT_ROLL_COOLDOWN],
		[&"vertical_break", Aircraft.VERTICAL_BREAK_COOLDOWN],
	]
	for entry in cases:
		var ac := _make_aircraft()
		_set_r_maneuver_flag(ac, entry[0])
		ac._active_special_local_cooldown_s = float(entry[1])
		_check("唯一 R 技能 %s 返回自身标识" % entry[0],
			ac.equipped_r_maneuver_id() == entry[0])
		_check("唯一 R 技能 %s 返回自身总冷却" % entry[0],
			is_equal_approx(ac.r_maneuver_cooldown_total(), float(entry[1])))
		_check("唯一 R 技能 %s 取得后常驻" % entry[0],
			PlayerInstrumentPanelScript.maneuver_skill_visible(ac))
		_check("唯一 R 技能 %s 发动后从 0%% 充能" % entry[0],
			is_equal_approx(PlayerInstrumentPanelScript.maneuver_charge_ratio(ac), 0.0))
		ac._active_special_local_cooldown_s = float(entry[1]) * 0.40
		_check("唯一 R 技能 %s 冷却只换算充能百分比" % entry[0],
			is_equal_approx(PlayerInstrumentPanelScript.maneuver_charge_ratio(ac), 0.60))
		ac._active_special_local_cooldown_s = 0.0
		_check("唯一 R 技能 %s READY 后保持 100%% 常驻" % entry[0],
			PlayerInstrumentPanelScript.maneuver_skill_visible(ac)
			and is_equal_approx(PlayerInstrumentPanelScript.maneuver_charge_ratio(ac), 1.0))
		ac.free()


func _set_r_maneuver_flag(ac: Aircraft, maneuver_id: StringName) -> void:
	match maneuver_id:
		&"cobra_skill":
			ac.cobra_skill_active = true
		&"evasion_herbst":
			ac.evasion_herbst_active = true
		&"manual_dodge":
			ac.manual_dodge_active = true
		&"displacement_roll":
			ac.displacement_roll_active = true
		&"vertical_break":
			ac.vertical_break_active = true


func _make_aircraft() -> Aircraft:
	var ac := Aircraft.new()
	ac.params = AircraftParams.new()
	return ac


func _check(label: String, condition: bool) -> void:
	if condition:
		_pass += 1
		print("  ✓ %s" % label)
	else:
		_fail += 1
		print("  ✗ %s" % label)
