extends RefCounted

const UiDevOutlineOverlayScript := preload("res://scripts/ui/ui_dev_outline_overlay.gd")
const SurvivorHUDScript := preload("res://scripts/survivor/survivor_hud.gd")
const SurvivorDebugZoneScript := preload("res://scripts/survivor/survivor_debug_zone.gd")
const ZoneHintScript := preload("res://scripts/survivor/zone_hint.gd")
const NotificationTerminalBarScript := preload(
	"res://scripts/survivor/notification_terminal_bar.gd")
const WarzoneTimePanelScript := preload("res://scripts/survivor/warzone_time_panel.gd")
const BottomExperiencePanelScript := preload("res://scripts/survivor/bottom_experience_panel.gd")
const TerminalTextScript := preload("res://scripts/ui/terminal_text.gd")

var _pass := 0
var _fail := 0


func run() -> void:
	print("\n════════ UI Dev 面板定位覆盖层验收 ════════")
	_test_geometry_only_hierarchy()
	_test_stable_top_level_letters()
	_test_visual_contract()
	_test_scale_contract()
	_test_edge_bar_contract()
	_test_hotkey_contract()
	print("──────── 结果：%d 通过 / %d 失败 ────────\n" % [_pass, _fail])


func _test_geometry_only_hierarchy() -> void:
	var root := Rect2(0.0, 0.0, 80.0, 36.0)
	var child := Rect2(0.0, 0.0, 40.0, 18.0)
	var grandchild := Rect2(0.0, 0.0, 18.0, 18.0)
	var independent := Rect2(100.0, 0.0, 18.0, 18.0)
	var entries: Array[Dictionary] = UiDevOutlineOverlayScript.build_entries([
		independent, grandchild, root, child, root,
	])
	_check("重复矩形只生成一个定位框", entries.size() == 4)
	_check("顶层从 A 开始且只按位置排序",
		_code_for_rect(entries, root) == "A"
		and _code_for_rect(entries, independent) == "B")
	_check("包含关系自动生成纯几何层级",
		_code_for_rect(entries, child) == "A.1"
		and _code_for_rect(entries, grandchild) == "A.1.1")
	var flat_entries: Array[Dictionary] = UiDevOutlineOverlayScript.build_entries([
		independent, grandchild, root, child,
	], true)
	_check("Dev 场景将全部可编辑子框压成两级定位",
		_code_for_rect(flat_entries, child) == "A1"
		and _code_for_rect(flat_entries, grandchild) == "A2")


func _test_stable_top_level_letters() -> void:
	var regions: Array[Rect2] = []
	for index in range(27):
		regions.append(Rect2(float(index) * 20.0, 0.0, 18.0, 18.0))
	var entries: Array[Dictionary] = UiDevOutlineOverlayScript.build_entries(regions)
	_check("前 26 个顶层使用 A-Z",
		String(entries[0]["code"]) == "A"
		and String(entries[25]["code"]) == "Z")
	_check("超过 Z 后稳定延伸为 AA", String(entries[26]["code"]) == "AA")


func _test_visual_contract() -> void:
	_check("定位框固定使用 2px 紫色描边",
		is_equal_approx(UiDevOutlineOverlayScript.OUTLINE_WIDTH, 2.0)
		and UiDevOutlineOverlayScript.OUTLINE_COLOR == Color("b94cff"))
	_check("描边向内缩进避免改变面板占地",
		is_equal_approx(UiDevOutlineOverlayScript.OUTLINE_INSET, 1.0))


func _test_scale_contract() -> void:
	_check("玩家 HUD 缩放固定为 0.5x 到 1.0x、步进 0.1x，默认 0.9x",
		is_equal_approx(SurvivorHUDScript.PLAYER_HUD_SCALE_MIN, 0.5)
		and is_equal_approx(SurvivorHUDScript.PLAYER_HUD_SCALE_MAX, 1.0)
		and is_equal_approx(SurvivorHUDScript.PLAYER_HUD_SCALE_STEP, 0.1)
		and is_equal_approx(SurvivorHUDScript.PLAYER_HUD_SCALE_DEFAULT, 0.9))
	_check("任意输入只能吸附到六个合法缩放档",
		is_equal_approx(SurvivorHUDScript.snap_player_hud_scale(1.2), 1.0)
		and is_equal_approx(SurvivorHUDScript.snap_player_hud_scale(0.86), 0.9)
		and is_equal_approx(SurvivorHUDScript.snap_player_hud_scale(0.74), 0.7)
		and is_equal_approx(SurvivorHUDScript.snap_player_hud_scale(0.1), 0.5))
	var physical_viewport := Vector2(1920.0, 1080.0)
	var physical_right_rect := SurvivorHUDScript.right_anchored_player_rect(
		physical_viewport, Vector2(298.0, 432.0), 0.5)
	_check("玩家 HUD 单独缩放后仍贴物理屏幕右边且保持固定底边距",
		is_equal_approx(physical_right_rect.end.x, physical_viewport.x)
		and is_equal_approx(physical_right_rect.end.y,
			physical_viewport.y - SurvivorHUDScript.PLAYER_HUD_BOTTOM_MARGIN)
		and physical_right_rect.size == Vector2(149.0, 216.0))


func _test_edge_bar_contract() -> void:
	var viewport_size := Vector2(1920.0, 1080.0)
	var bar := SurvivorHUDScript.bottom_bar_rect(viewport_size)
	var group := SurvivorHUDScript.bottom_progress_rect(viewport_size)
	var axis := SurvivorHUDScript.bottom_axis_rect(viewport_size)
	var xp := SurvivorHUDScript.bottom_xp_rect(viewport_size)
	var warzone_panel = WarzoneTimePanelScript.new()
	warzone_panel._ready()
	_check("底部常驻框板横跨全屏并固定为 3u",
		bar == Rect2(0.0, 1026.0, 1920.0, 54.0)
		and SurvivorHUDScript.PLAYER_HUD_BOTTOM_MARGIN == bar.size.y)
	_check("顶部时间使用居中的 1u 常驻框板与固定终端格式",
		SurvivorHUDScript.top_time_rect(viewport_size)
			== Rect2(860.0, 0.0, 200.0, 18.0)
		and SurvivorHUDScript.formatted_elapsed_time(65.9) == "TIME  01:05"
		and SurvivorHUDScript.formatted_elapsed_time(-1.0) == "TIME  00:00")
	_check("战区剩余时间使用四个 2u 数字格、冒号和对齐的 1u 说明框",
		SurvivorHUDScript.warzone_time_rect(viewport_size)
			== Rect2(871.0, 18.0, 178.0, 54.0)
		and WarzoneTimePanelScript.digit_rect(0) == Rect2(0.0, 0.0, 40.0, 36.0)
		and WarzoneTimePanelScript.separator_rect() == Rect2(80.0, 0.0, 18.0, 36.0)
		and WarzoneTimePanelScript.label_rect() == Rect2(0.0, 36.0, 178.0, 18.0)
		and WarzoneTimePanelScript.formatted_remaining_time(125.9) == "02:05"
		and warzone_panel._grid_overlay.edge_insets == Vector4(0.5, 0.5, 0.5, 0.5))
	var mode_source := FileAccess.get_file_as_string(
		"res://scripts/survivor/survivor_mode.gd")
	var physics_start := mode_source.find("func _physics_process(delta: float) -> void:")
	var capture_start := mode_source.find("func _bench_capture_weather_frame() -> void:")
	var elapsed_sync := mode_source.find("hud.game_time = game_time", physics_start)
	var remaining_sync := mode_source.find("hud.set_warzone_remaining(", physics_start)
	_check("正式物理主循环持续注入当前与战区时间，截图 Bench 不得吞掉 HUD 同步块",
		physics_start >= 0 and capture_start > physics_start
		and elapsed_sync > physics_start and elapsed_sync < capture_start
		and remaining_sync > elapsed_sync and remaining_sync < capture_start)
	var timer_hud = SurvivorHUDScript.new()
	timer_hud._build_ui()
	timer_hud.set_warzone_remaining(372.9, false, 27.9)
	var first_visible_seconds: float = timer_hud._warzone_timer_panel._seconds
	timer_hud.set_warzone_remaining(372.1, false)
	var same_visible_second: float = timer_hud._warzone_timer_panel._seconds
	timer_hud.set_warzone_remaining(371.9, false)
	var next_visible_second: float = timer_hud._warzone_timer_panel._seconds
	timer_hud.set_warzone_remaining(371.8, true, 28.1)
	_check("战区时间只在可见整数秒或 BOSS 状态变化时请求重绘",
		is_equal_approx(first_visible_seconds, 372.9)
		and is_equal_approx(same_visible_second, 372.9)
		and is_equal_approx(next_visible_second, 371.9)
		and timer_hud._warzone_timer_panel._boss_phase
		and timer_hud._time_label.text == "TIME  00:28")
	timer_hud.free()
	_check("3u 常驻栏由等宽侧板、2u 三方向和 1u 经验条完整填满",
		group == Rect2(618.0, 1026.0, 684.0, 54.0)
		and axis == Rect2(756.0, 1026.0, 408.0, 36.0)
		and xp == Rect2(756.0, 1062.0, 408.0, 18.0)
		and group.position.y == bar.position.y
		and xp.end.y == bar.end.y
		and BottomExperiencePanelScript.left_panel_rect().size
			== BottomExperiencePanelScript.right_panel_rect().size)
	var hint = ZoneHintScript.new()
	hint._build()
	var hud_source := FileAccess.get_file_as_string(
		"res://scripts/survivor/survivor_hud.gd")
	var encounter_layout_start := hud_source.find("# BOSS / 王牌条固定在顶部通知通道下方")
	var encounter_layout_end := hud_source.find("# 状态面板：右下角", encounter_layout_start)
	var encounter_layout := ""
	if encounter_layout_start >= 0 and encounter_layout_end > encounter_layout_start:
		encounter_layout = hud_source.substr(
			encounter_layout_start, encounter_layout_end - encounter_layout_start)
	_check("顶部通知与 BOSS / 王牌共用锚位按固定通道依次堆叠",
		ZoneHintScript.NOTICE_HEIGHT == 36.0
		and ZoneHintScript.NOTICE_ANCHOR_LEFT == 0.2
		and ZoneHintScript.NOTICE_ANCHOR_RIGHT == 0.8
		and ZoneHintScript.BOTTOM_RESERVED_HEIGHT == SurvivorHUDScript.BOTTOM_BAR_HEIGHT
		and ZoneHintScript.TOP_RESERVED_HEIGHT
			== SurvivorHUDScript.TIME_PANEL_SIZE.y + WarzoneTimePanelScript.PANEL_SIZE.y
		and SurvivorHUDScript.TOP_ENCOUNTER_Y
			== ZoneHintScript.TOP_RESERVED_HEIGHT + ZoneHintScript.NOTICE_HEIGHT
				+ SurvivorHUDScript.TOP_ENCOUNTER_GAP
		and SurvivorHUDScript.TOP_ENCOUNTER_Y == 114.0
		and encounter_layout_start >= 0 and encounter_layout_end > encounter_layout_start
		and encounter_layout.count("TOP_ENCOUNTER_Y") == 2
		and ZoneHintScript.NOTIFICATION_LAYER
			== SurvivorHUDScript.PERSISTENT_HUD_LAYER - 1
		and ZoneHintScript.SLIDE_DURATION == 0.25
		and hint._bg != hint._temp_bg
		and not hint._bg.visible and not hint._temp_bg.visible
		and hint._bg.offset_top == -ZoneHintScript.NOTICE_HEIGHT
		and hint._bg.offset_bottom == 0.0
		and hint._temp_bg.anchor_top == 1.0
		and hint._temp_bg.offset_top == 0.0
		and hint._temp_bg.offset_bottom == ZoneHintScript.NOTICE_HEIGHT
		and hint._bg.get_script() == NotificationTerminalBarScript
		and NotificationTerminalBarScript.icon_rect(Vector2(960.0, 36.0))
			== Rect2(0.0, 0.0, 36.0, 36.0)
		and NotificationTerminalBarScript.body_rect(Vector2(960.0, 36.0))
			== Rect2(36.0, 0.0, 924.0, 36.0)
		and NotificationTerminalBarScript.split_graphic_prefix(
			"⚡ NEW ZONE", "!") == PackedStringArray(["⚡", "NEW ZONE"]))
	hint.free()
	warzone_panel.free()


func _test_hotkey_contract() -> void:
	_check("F6 继续专用于战区 Debug，F7 专用于 UI Dev",
		SurvivorDebugZoneScript.TOGGLE_KEY == KEY_F6
		and SurvivorHUDScript.UI_DEV_TOGGLE_KEY == KEY_F7)
	var hud: SurvivorHUD = SurvivorHUDScript.new()
	hud._build_ui()
	hud.toggle_ui_dev_overlay()
	_check("当前时间保持 1u 并切换为 Chakra Petch 粗体",
		hud._time_label.font_face == TerminalTextScript.FontFace.CHAKRA_PETCH_BOLD
		and hud._time_label.size == SurvivorHUDScript.TIME_PANEL_SIZE)
	_check("F7 入口第一次调用显示实际 HUD 定位层",
		hud.is_ui_dev_overlay_visible()
		and hud._ui_dev_overlay != null
		and hud._ui_dev_overlay.visible)
	_check("F7 同时提供手动添加 FLR 控制键的测试按钮",
		hud._ui_dev_manual_flare_button != null
		and hud._ui_dev_manual_flare_button.visible
		and hud._ui_dev_manual_flare_button.text.contains("MANUAL FLR"))
	_check("F7 玩家 HUD 缩放滑条默认 0.9x 且只允许六档",
		hud._ui_dev_scale_slider != null
		and hud._ui_dev_scale_slider.visible
		and is_equal_approx(float(hud._ui_dev_scale_slider.value), 0.9)
		and is_equal_approx(float(hud._ui_dev_scale_slider.min_value), 0.5)
		and is_equal_approx(float(hud._ui_dev_scale_slider.max_value), 1.0)
		and is_equal_approx(float(hud._ui_dev_scale_slider.step), 0.1)
		and hud._ui_dev_scale_slider.tick_count == 6
		and hud._ui_dev_scale_label.text.contains("PLAYER HUD"))
	hud.set_player_hud_scale(0.83)
	_check("滑条变值只缩放玩家仪表，其余 HUD 根节点与面板保持 1.0x",
		is_equal_approx(hud.player_hud_scale(), 0.8)
		and hud._player_instrument.scale.is_equal_approx(Vector2(0.8, 0.8))
		and hud._ui_root.scale.is_equal_approx(Vector2.ONE)
		and hud._wingman_instrument.scale.is_equal_approx(Vector2.ONE)
		and hud._milestone_axis_counter.scale.is_equal_approx(Vector2.ONE)
		and hud._bottom_experience_panel.scale.is_equal_approx(Vector2.ONE)
		and hud._ui_dev_scale_label.text.contains("0.8x"))
	hud.toggle_ui_dev_overlay()
	_check("F7 入口第二次调用关闭定位层",
		not hud.is_ui_dev_overlay_visible()
		and not hud._ui_dev_overlay.visible
		and not hud._ui_dev_manual_flare_button.visible
		and not hud._ui_dev_scale_label.visible
		and not hud._ui_dev_scale_slider.visible)
	_check("关闭 F7 不会重置当前战局缩放",
		is_equal_approx(hud.player_hud_scale(), 0.8))
	hud.free()
	var fresh_hud = SurvivorHUDScript.new()
	_check("新战局玩家 HUD 使用默认 0.9x",
		is_equal_approx(fresh_hud.player_hud_scale(), 0.9))
	fresh_hud.free()


func _code_for_rect(entries: Array[Dictionary], target: Rect2) -> String:
	for entry in entries:
		var rect: Rect2 = entry["rect"]
		if rect == target:
			return String(entry["code"])
	return ""


func _check(label: String, condition: bool) -> void:
	if condition:
		_pass += 1
		print("  ✓ %s" % label)
	else:
		_fail += 1
		print("  ✗ %s" % label)
