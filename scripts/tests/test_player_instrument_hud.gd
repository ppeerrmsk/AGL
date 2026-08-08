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
	_check("默认 HUD 色为 #53D13A", HudPreferencesScript.DEFAULT_COLOR.is_equal_approx(Color("53d13a")))


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
	_check("紧凑版玩家仪表收窄到 326×408", PlayerInstrumentPanelScript.PANEL_SIZE == Vector2(326.0, 408.0))
	_check("HP/SPD/加力各自从独立行左上角连续排布",
		PlayerInstrumentPanelScript.HP_RECT.end.y == PlayerInstrumentPanelScript.SPD_RECT.position.y
		and PlayerInstrumentPanelScript.SPD_RECT.end.y == PlayerInstrumentPanelScript.AB_RECT.position.y)
	_check("ENGAGE/FIRE 是两条不共享基线的独立行",
		PlayerInstrumentPanelScript.ENGAGE_RECT.end.y == PlayerInstrumentPanelScript.FIRE_RECT.position.y
		and PlayerInstrumentPanelScript.ENGAGE_RECT.position.x == PlayerInstrumentPanelScript.FIRE_RECT.position.x)
	_check("R 行只占 FLR 右栏且不增加玩家仪表高度",
		PlayerInstrumentPanelScript.FLARE_COMPACT_RECT.end.y == PlayerInstrumentPanelScript.MANEUVER_RECT.position.y
		and PlayerInstrumentPanelScript.MANEUVER_RECT.end.y == PlayerInstrumentPanelScript.CONTROL_RECT.end.y
		and PlayerInstrumentPanelScript.WEAPON_RECT.end.y == PlayerInstrumentPanelScript.PANEL_SIZE.y)
	_check("SPD 左侧固定切出 ALT 状态块、右侧速度区不越界",
		PlayerInstrumentPanelScript.SPD_ALT_RECT.end.x == PlayerInstrumentPanelScript.SPD_SPEED_RECT.position.x
		and PlayerInstrumentPanelScript.SPD_SPEED_RECT.end.x == PlayerInstrumentPanelScript.SPD_RECT.end.x
		and PlayerInstrumentPanelScript.SPD_ALT_RECT == Rect2(28.0, 76.0, 106.0, 78.0))
	_check("Q 与 E/G/F/T 键帽使用同一外侧竖列",
		PlayerInstrumentPanelScript.keycap_rect(PlayerInstrumentPanelScript.Q_KEY_Y).position.x
		== PlayerInstrumentPanelScript.keycap_rect(PlayerInstrumentPanelScript.E_KEY_Y).position.x
		and PlayerInstrumentPanelScript.keycap_rect(PlayerInstrumentPanelScript.E_KEY_Y).position.x
		== PlayerInstrumentPanelScript.keycap_rect(PlayerInstrumentPanelScript.G_KEY_Y).position.x
		and PlayerInstrumentPanelScript.keycap_rect(PlayerInstrumentPanelScript.G_KEY_Y).position.x
		== PlayerInstrumentPanelScript.keycap_rect(PlayerInstrumentPanelScript.F_KEY_Y).position.x
		and PlayerInstrumentPanelScript.keycap_rect(PlayerInstrumentPanelScript.F_KEY_Y).position.x
		== PlayerInstrumentPanelScript.keycap_rect(PlayerInstrumentPanelScript.T_KEY_Y).position.x)
	_check("FLR 当前数量字号大于最大数量",
		PlayerInstrumentPanelScript.FLARE_CURRENT_FONT_SIZE > PlayerInstrumentPanelScript.FLARE_MAX_FONT_SIZE)
	_check("控制区左栏保持约 41% 比例", is_equal_approx(
		PlayerInstrumentPanelScript.CONTROL_LEFT_W / PlayerInstrumentPanelScript.CONTENT_W,
		122.0 / 298.0))
	_check("武器名称列从约 59% 处开始", is_equal_approx(
		(PlayerInstrumentPanelScript.WEAPON_COUNT_W
		+ PlayerInstrumentPanelScript.WEAPON_PRIORITY_W)
		/ PlayerInstrumentPanelScript.CONTENT_W, 176.0 / 298.0))
	_check("7 架僚机与玩家仪表可共同容纳在 900 高逻辑视口",
		WingmanInstrumentPanelScript.total_height_for_count(7)
		+ PlayerInstrumentPanelScript.PANEL_SIZE.y + 6.0 <= 844.0)
	_check("号机数字使用 21px 独立键帽且不抬高行节奏",
		WingmanInstrumentPanelScript.SLOT_FONT_SIZE == 21
		and WingmanInstrumentPanelScript.SLOT_KEY_SIZE == Vector2(28.0, 26.0)
		and WingmanInstrumentPanelScript.ROW_STRIDE == 57.0)


func _test_milestone_axis_counter() -> void:
	var counter = MilestoneAxisCounterScript.new()
	counter._ready()
	_check("三轴计数器与经验条同宽且固定为 400×18",
		counter.size == Vector2(400.0, 18.0)
		and is_equal_approx(MilestoneAxisCounterScript.CELL_WIDTH * 3.0,
			MilestoneAxisCounterScript.COUNTER_SIZE.x))
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
