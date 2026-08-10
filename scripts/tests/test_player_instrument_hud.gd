extends RefCounted

## 玩家仪表确定性验收：单位换算、纯显示交互、武器优先跳过缺失项、
## 十枚热诱弹视觉波与星号/装填进度同步。

const SurvivorModeScript := preload("res://scripts/survivor/survivor_mode.gd")
const HudPreferencesScript := preload("res://scripts/ui/hud_preferences.gd")
const PlayerInstrumentPanelScript := preload("res://scripts/survivor/player_instrument_panel.gd")
const WingmanInstrumentPanelScript := preload("res://scripts/survivor/wingman_instrument_panel.gd")
const MilestoneAxisCounterScript := preload("res://scripts/survivor/milestone_axis_counter.gd")
const HudColorSettingsPanelScript := preload("res://scripts/ui/hud_color_settings_panel.gd")

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
	panel.update_display([row, row.merged({"slot": 3, "callsign": "MOBIUS"}, true)])
	_check("2 架僚机按数量扩成 2 行",
		is_equal_approx(panel.size.y, WingmanInstrumentPanelScript.total_height_for_count(2)))
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
	_check("maximum layout references remain explicit",
		PlayerInstrumentPanelScript.HP_VALUE_LAYOUT_TEXT == "999"
		and PlayerInstrumentPanelScript.G_VALUE_LAYOUT_TEXT == "11.5"
		and PlayerInstrumentPanelScript.G_INTEGER_LAYOUT_TEXT == "11"
		and PlayerInstrumentPanelScript.G_FRACTION_LAYOUT_TEXT == "9"
		and PlayerInstrumentPanelScript.SPD_VALUE_LAYOUT_TEXT == "9999"
		and PlayerInstrumentPanelScript.ALT_VALUE_LAYOUT_TEXT == "99999"
		and PlayerInstrumentPanelScript.FLARE_VALUE_LAYOUT_TEXT == "99")
	_check("HP G and SPD share one height-first primary font size",
		panel.primary_value_font_size > 1
		and panel.hp_current_rect.size.y == PlayerInstrumentPanelScript.PRIMARY_VALUE_HEIGHT
		and panel.g_integer_rect.size.y == PlayerInstrumentPanelScript.PRIMARY_VALUE_HEIGHT
		and panel.spd_current_rect.size.y == PlayerInstrumentPanelScript.PRIMARY_VALUE_HEIGHT)
	var display_font: Font = panel._display_font
	_check("primary boards expand by whole q steps instead of shrinking text",
		display_font.get_string_size("999", HORIZONTAL_ALIGNMENT_LEFT, -1.0,
			panel.primary_value_font_size).x <= panel.hp_current_rect.size.x
		and display_font.get_string_size("11", HORIZONTAL_ALIGNMENT_LEFT, -1.0,
			panel.primary_value_font_size).x <= panel.g_integer_rect.size.x
		and display_font.get_string_size("9999", HORIZONTAL_ALIGNMENT_LEFT, -1.0,
			panel.primary_value_font_size).x <= panel.spd_current_rect.size.x
		and is_equal_approx(fmod(panel.hp_current_rect.size.x - 120.0, 18.0), 0.0)
		and is_equal_approx(fmod(panel.g_integer_rect.size.x - 80.0, 18.0), 0.0)
		and is_equal_approx(fmod(panel.spd_current_rect.size.x - 120.0, 18.0), 0.0))
	_check("G uses framed 3u integer and bottom decimal cells with a borderless 2u fraction",
		panel.g_integer_rect.size.y == PlayerInstrumentPanelScript.U_SIZE.y * 3.0
		and panel.g_decimal_rect.size == PlayerInstrumentPanelScript.Q_SIZE
		and panel.g_decimal_rect.end.y == panel.hp_g_rect.end.y
		and panel.g_fraction_rect.size.y == PlayerInstrumentPanelScript.U_SIZE.y * 2.0
		and panel.g_fraction_rect.end.y == panel.hp_g_rect.end.y
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
	_check("decorative half-q columns align lower rows to ALT SPD without changing numeric q steps",
		PlayerInstrumentPanelScript.DECORATIVE_HALF_Q_WIDTH
			== PlayerInstrumentPanelScript.Q_SIZE.x * 0.5
		and PlayerInstrumentPanelScript.DECORATIVE_HALF_U_HEIGHT
			== PlayerInstrumentPanelScript.U_SIZE.y * 0.5
		and is_equal_approx(fmod(
			panel.aligned_content_width - PlayerInstrumentPanelScript.BASE_CONTENT_W,
			PlayerInstrumentPanelScript.DECORATIVE_HALF_Q_WIDTH), 0.0)
		and panel.ab_rect.position.x == panel.spd_rect.position.x
		and panel.engage_rect.position.x == panel.spd_rect.position.x
		and panel.maneuver_base_rect.position.x == panel.spd_rect.position.x
		and panel.weapon_rect.position.x == panel.spd_rect.position.x)
	_check("aligned operation keycaps form one vertical display column",
		PlayerInstrumentPanelScript.keycap_left_of(panel.spd_rect).position.x
			== PlayerInstrumentPanelScript.keycap_left_of(panel.ab_rect).position.x
		and PlayerInstrumentPanelScript.keycap_left_of(panel.ab_rect).position.x
			== PlayerInstrumentPanelScript.keycap_left_of(panel.engage_rect).position.x
		and PlayerInstrumentPanelScript.keycap_left_of(panel.engage_rect).position.x
			== PlayerInstrumentPanelScript.keycap_left_of(panel.maneuver_base_rect).position.x
		and PlayerInstrumentPanelScript.keycap_left_of(panel.maneuver_base_rect).position.x
			== PlayerInstrumentPanelScript.keycap_left_of(panel.weapon_rect).position.x)
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
	_check("internal R insertion grows left while the flare right edge remains fixed",
		panel.active_flare_rect(true) == panel.flare_base_rect
		and panel.active_engage_rect(true).position.x
			== panel.engage_rect.position.x - PlayerInstrumentPanelScript.Q_SIZE.x
		and panel.active_fire_rect(true).position.x
			== panel.fire_rect.position.x - PlayerInstrumentPanelScript.Q_SIZE.x
		and panel.active_maneuver_rect(true, true) == panel.maneuver_base_rect
		and panel.manual_flare_key_rect().end.x == panel.flare_base_rect.position.x)
	_check("all expandable rows preserve the shared screen-side right edge",
		panel.hp_rect.end.x == panel.size.x
		and panel.spd_rect.end.x == panel.size.x
		and panel.ab_rect.end.x == panel.size.x
		and panel.flare_base_rect.end.x == panel.size.x
		and panel.maneuver_base_rect.end.x == panel.size.x
		and panel.weapon_rect.end.x == panel.size.x)
	_check("SPD primary value explicitly uses left alignment",
		PlayerInstrumentPanelScript.SPD_VALUE_ALIGNMENT == HORIZONTAL_ALIGNMENT_LEFT)
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
	_check("grid frames boards and key cells while numeric word boards stay borderless",
		player_regions.has(panel.hp_rect)
		and player_regions.has(panel.ab_title_rect)
		and player_regions.has(panel.ab_percent_rect)
		and player_regions.has(panel.ab_progress_rect)
		and player_regions.has(panel.manual_flare_key_rect())
		and player_regions.has(panel.g_integer_rect)
		and player_regions.has(panel.g_decimal_rect)
		and player_regions.has(PlayerInstrumentPanelScript.flare_title_rect(active_flare))
		and not player_regions.has(panel.hp_current_rect)
		and not player_regions.has(panel.g_fraction_rect)
		and not player_regions.has(panel.hp_separator_rect)
		and not player_regions.has(panel.hp_max_rect)
		and not player_regions.has(PlayerInstrumentPanelScript.flare_current_rect(active_flare)))
	_check("removing the empty row and using 2u progress panels yields 24u total height",
		panel.size.y == PlayerInstrumentPanelScript.U_SIZE.y * 24.0
		and panel.weapon_rect.end.y == panel.size.y)
	_check("weapon name column still begins after four u of numeric information",
		is_equal_approx(PlayerInstrumentPanelScript.WEAPON_COUNT_W
			+ PlayerInstrumentPanelScript.WEAPON_PRIORITY_W,
			PlayerInstrumentPanelScript.U_SIZE.x * 4.0))
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
	_check("三轴计数器使用 3u+3u+4u 且与经验条同宽",
		counter.size == Vector2(400.0, 18.0)
		and MilestoneAxisCounterScript.cell_rect(0) == Rect2(0.0, 0.0, 120.0, 18.0)
		and MilestoneAxisCounterScript.cell_rect(1) == Rect2(120.0, 0.0, 120.0, 18.0)
		and MilestoneAxisCounterScript.cell_rect(2) == Rect2(240.0, 0.0, 160.0, 18.0))
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
	_check("三轴计数按斗士/骑士/策士顺序读取里程碑进度",
		snapshot == [3, 2, 4])
	counter.update_display(player)
	var revision: int = counter._redraw_revision
	counter.update_display(player)
	_check("三轴读数不变时不重复请求重绘", counter._redraw_revision == revision)
	player.axis_points[SurvivorData.AXIS_SCHEMER] = 24
	counter.update_display(player)
	_check("更大读数只改文字、不扩张计数器",
		counter._values == [3, 2, 24]
		and counter.size == MilestoneAxisCounterScript.COUNTER_SIZE)
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
	ac.altitude_preference = Aircraft.AltitudePreference.PREFER_CLIMB
	_check("Q 爬升优先使用既有本地化状态",
		PlayerInstrumentPanelScript.altitude_preference_name_key(ac) == "TOOLTIP_ALT_CLIMB_TITLE")
	SurvivorModeScript._cycle_player_altitude_preference(ac)
	_check("Q 保留爬升优先到低空优先的真实切换",
		ac.altitude_preference == Aircraft.AltitudePreference.PREFER_LOW)
	_check("Q 低空优先使用既有本地化状态",
		PlayerInstrumentPanelScript.altitude_preference_name_key(ac) == "TOOLTIP_ALT_LOW_TITLE")
	SurvivorModeScript._cycle_player_altitude_preference(ac)
	_check("Q 再按返回爬升优先",
		ac.altitude_preference == Aircraft.AltitudePreference.PREFER_CLIMB)
	ac.free()


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
