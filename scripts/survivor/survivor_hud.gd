class_name SurvivorHUD
extends CanvasLayer

const PlayerInstrumentPanelScript := preload("res://scripts/survivor/player_instrument_panel.gd")
const WingmanInstrumentPanelScript := preload("res://scripts/survivor/wingman_instrument_panel.gd")
const MilestoneAxisCounterScript := preload("res://scripts/survivor/milestone_axis_counter.gd")
const BottomExperiencePanelScript := preload("res://scripts/survivor/bottom_experience_panel.gd")
const WarzoneTimePanelScript := preload("res://scripts/survivor/warzone_time_panel.gd")
const UiDevOutlineOverlayScript := preload("res://scripts/ui/ui_dev_outline_overlay.gd")
const TerminalGridOverlayScript := preload("res://scripts/ui/terminal_grid_overlay.gd")
const TerminalTextScript := preload("res://scripts/ui/terminal_text.gd")
const HudPreferencesScript := preload("res://scripts/ui/hud_preferences.gd")

## 生存模式 HUD：右下角状态面板 + 顶部时间/击杀 + 底部经验条

var survivor_player: SurvivorPlayer
var game_time: float = 0.0
var kill_count: int = 0
var game_scene: Node2D


## SurvivorPlayer.aircraft 跨帧持有；终局/切控边界可能短暂指向已释放实例。
## 必须先以 Variant 进入统一净化器，不能直接赋给强类型局部变量后再判有效。
func _safe_player_aircraft() -> Aircraft:
	if survivor_player == null:
		return null
	return AircraftRenderer.safe_aircraft_ref(survivor_player.aircraft)


# ── 顶部 ──
var _time_panel: ColorRect
var _time_grid: Control
var _time_label: Control
var _warzone_timer_panel: Control
## 战区阶段倒计时（始终可见，包括升级面板暂停期间）
var _warzone_remaining: float = -1.0   ## -1 = 尚未注入；setter 写入后转正
var _warzone_in_boss_phase: bool = false

# ── 底部经验条 ──
var _bottom_bar_bg: ColorRect
var _bottom_bar_grid: Control
var _bottom_experience_panel: Control
var _milestone_axis_counter: Control

# ── 右下角状态面板 ──
var _status_panel: PanelContainer
var _status_label: RichTextLabel
var _player_instrument: Control
var _wingman_instrument: Control

# ── 右侧战术面板 ──
var _tactical_panel: PanelContainer
var _btn_weapon: Button
var _btn_altitude: Button
var _btn_evasion: Button
var _btn_auto_fire: Button
var _btn_auto_engage: Button
## ── 加力模式（spec afterburner-mode）──
## survivor_mode 注入的小队充能资源 + 充能条控件（每帧 _update_tactical_buttons 刷三态）
var afterburner_charge: AfterburnerCharge
var _ab_bar: ProgressBar
var _ab_bar_fill: StyleBoxFlat
const AB_BAR_CHARGING := Color(0.72, 0.5, 0.15)   ## 充能中：暗橙
const AB_BAR_READY := Color(1.0, 0.78, 0.25)      ## 就绪：亮橙
const AB_BAR_ACTIVE := Color(0.4, 0.9, 1.0)       ## 激活窗口：亮青（倒计时收缩）
var _tooltip_panel: PanelContainer
var _tooltip_label: RichTextLabel
var _tooltip_key: String = ""  # 当前悬停的按钮标识

# ── 小队指挥面板（仅主角有僚机时显示）──
var _squad_panel: PanelContainer
var _squad_status_label: RichTextLabel
var _btn_squad_engage: Button
var _btn_squad_weapon: Button
## 小队交战模式：FREE=独立扫描+协同 / FOLLOW_LEADER=只打长机目标
var _squad_engage_mode: int = 1          # AIController.SquadEngageMode.FOLLOW_LEADER（默认凝聚，spec squad-cohesion）
var _squad_weapon_pref: int = 0          # 0 = 导弹优先, 1 = 机炮优先 (Aircraft.WeaponPreference)

# ── BOSS 小队状态面板（F-47 等 BOSS 在场时显示）──
var _boss_panel: PanelContainer

# ── 雷达小地图 ──
var _radar: Control

# ── 战况栏 / kill feed（左上角，最新 5 条，逐渐淡出）──
var _kill_feed_container: VBoxContainer
var _kill_feed_entries: Array = []   ## 每项 {label: Label, age: float}

# ── 其他 ──
var _game_over_panel: PanelContainer
var _game_over_label: RichTextLabel
var _threat_overlay: Control

var _hud_data_refresh_timer: float = 0.0

# ── 正式生存 HUD 根节点；缩放仅施加于右侧玩家仪表 ──
var _ui_root: Control
var _player_hud_scale := PLAYER_HUD_SCALE_DEFAULT

# ── F7 UI Dev 定位覆盖层 ──
var _ui_dev_overlay: Control
var _ui_dev_manual_flare_button: Button
var _ui_dev_scale_label: Label
var _ui_dev_scale_slider: HSlider
var _ui_dev_visible := false
var _ui_dev_regions: Array[Rect2] = []

# ── 击杀经验表现层（升级表现由 BottomExperiencePanel 负责）──
var _xp_vfx: XpGainVfx

# Debug 性能面板
var _debug_panel: PanelContainer
var _debug_label: Label
var _debug_visible: bool = false
var _debug_update_timer: float = 0.0

const XP_BAR_WIDTH := BottomExperiencePanelScript.CENTER_WIDTH
const XP_BAR_HEIGHT := BottomExperiencePanelScript.U_HEIGHT
const BOTTOM_BAR_HEIGHT := 54.0
const PERSISTENT_HUD_LAYER := 10
const TIME_PANEL_SIZE := Vector2(200.0, 18.0)
const STATUS_PANEL_WIDTH := 220.0
const HUD_DATA_REFRESH_INTERVAL := 0.5
const UI_DEV_TOGGLE_KEY := KEY_F7
const PLAYER_HUD_SCALE_MIN := 0.5
const PLAYER_HUD_SCALE_MAX := 1.0
const PLAYER_HUD_SCALE_STEP := 0.1
const PLAYER_HUD_SCALE_DEFAULT := 0.9
const PLAYER_HUD_BOTTOM_MARGIN := BOTTOM_BAR_HEIGHT

# ── 战况栏参数 ──
const KILL_FEED_MAX := 5      ## 同时显示的最大条数（超出立即移除最旧）
const KILL_FEED_HOLD := 5.0   ## 完全不透明保持秒数
const KILL_FEED_FADE := 1.5   ## 之后淡出秒数

func _ready() -> void:
	layer = PERSISTENT_HUD_LAYER
	_build_ui()

func _build_ui() -> void:
	_ensure_ui_root()
	# ── 战区阶段倒计时（顶部最上方，始终可见，升级面板暂停时也保留）──
	# process_mode=ALWAYS 确保 get_tree().paused=true 时 Label 仍能 process（虽然 Label 本身没 _process，
	# 但保险起见显式设置；setter 调用是同步赋值，process_mode 主要影响子节点 / 信号回调）
	_warzone_timer_panel = WarzoneTimePanelScript.new()
	_warzone_timer_panel.process_mode = Node.PROCESS_MODE_ALWAYS
	_add_ui_child(_warzone_timer_panel)

	# ── 时间（顶部中央）──
	_time_panel = ColorRect.new()
	_time_panel.color = ThemeColors.UI_BLOCK_BACKGROUND
	_time_panel.size = TIME_PANEL_SIZE
	_time_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_add_ui_child(_time_panel)
	_time_grid = TerminalGridOverlayScript.new()
	_time_grid.size = TIME_PANEL_SIZE
	_time_grid.edge_insets = Vector4(0.0, 0.5, 0.0, 0.0)
	var time_regions: Array[Rect2] = [Rect2(Vector2.ZERO, TIME_PANEL_SIZE)]
	_time_grid.regions = time_regions
	_time_panel.add_child(_time_grid)
	_time_label = TerminalTextScript.new()
	_time_label.size = TIME_PANEL_SIZE
	_time_label.font_face = TerminalTextScript.FontFace.CHAKRA_PETCH_BOLD
	_time_label.size_rule = TerminalTextScript.SizeRule.ONE_U_FIXED_15
	_time_label.layout_text = "TIME  99:59"
	_time_label.text = "TIME  00:00"
	_time_panel.add_child(_time_label)

	# ── 全屏底部 3u 常驻框板；三轴计数与经验条作为其内部内容 ──
	_bottom_bar_bg = ColorRect.new()
	_bottom_bar_bg.color = ThemeColors.UI_BLOCK_BACKGROUND
	_bottom_bar_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_add_ui_child(_bottom_bar_bg)
	_bottom_bar_grid = TerminalGridOverlayScript.new()
	_bottom_bar_grid.edge_insets = Vector4(0.5, 0.0, 0.5, 0.5)
	_bottom_bar_bg.add_child(_bottom_bar_grid)

	_bottom_experience_panel = BottomExperiencePanelScript.new()
	_add_ui_child(_bottom_experience_panel)

	# ── 三轴里程碑摘要（经验条正上方，固定占位、无交互）──
	_milestone_axis_counter = MilestoneAxisCounterScript.new()
	_add_ui_child(_milestone_axis_counter)

	# ── 右下角状态面板 ──
	_status_panel = PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = ThemeColors.PANEL_BG
	style.border_color = ThemeColors.PANEL_BORDER
	style.set_border_width_all(1)
	style.set_corner_radius_all(3)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	_status_panel.add_theme_stylebox_override("panel", style)
	_status_panel.custom_minimum_size = Vector2(STATUS_PANEL_WIDTH, 0)
	_add_ui_child(_status_panel)

	_status_label = RichTextLabel.new()
	_status_label.bbcode_enabled = true
	_status_label.fit_content = true
	_status_label.scroll_active = false
	_status_label.custom_minimum_size = Vector2(STATUS_PANEL_WIDTH - 20, 0)
	_status_label.add_theme_font_size_override("normal_font_size", 12)
	_status_label.add_theme_font_size_override("bold_font_size", 12)
	_status_label.add_theme_color_override("default_color", ThemeColors.TEXT_PRIMARY_ALT)
	_status_panel.add_child(_status_label)

	# ── 右侧战术面板 ──
	_tactical_panel = PanelContainer.new()
	var tac_style := StyleBoxFlat.new()
	tac_style.bg_color = ThemeColors.PANEL_BG
	tac_style.border_color = ThemeColors.PANEL_BORDER_ACCENT
	tac_style.set_border_width_all(1)
	tac_style.set_corner_radius_all(3)
	tac_style.content_margin_left = 8
	tac_style.content_margin_right = 8
	tac_style.content_margin_top = 6
	tac_style.content_margin_bottom = 6
	_tactical_panel.add_theme_stylebox_override("panel", tac_style)

	var tac_vbox := VBoxContainer.new()
	tac_vbox.add_theme_constant_override("separation", 4)
	_tactical_panel.add_child(tac_vbox)

	var tac_title := Label.new()
	tac_title.text = tr("TACTIC_HEADER")
	tac_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tac_title.add_theme_font_size_override("font_size", 11)
	tac_title.add_theme_color_override("font_color", ThemeColors.TEXT_ACCENT)
	tac_vbox.add_child(tac_title)

	_btn_weapon = _create_tac_button(tr("TACTIC_MISSILE_PRIORITY"))
	_btn_weapon.pressed.connect(_on_weapon_pressed)
	_btn_weapon.mouse_entered.connect(_on_tac_hover.bind("weapon"))
	_btn_weapon.mouse_exited.connect(_on_tac_hover_exit)
	tac_vbox.add_child(_btn_weapon)

	_btn_altitude = _create_tac_button(tr("TACTIC_CLIMB_PRIORITY"))
	_btn_altitude.pressed.connect(_on_altitude_pressed)
	_btn_altitude.mouse_entered.connect(_on_tac_hover.bind("altitude"))
	_btn_altitude.mouse_exited.connect(_on_tac_hover_exit)
	tac_vbox.add_child(_btn_altitude)

	# ── 加力充能条（spec afterburner-mode）：紧贴加力按钮上方，三态变色显眼提示 ──
	_ab_bar = ProgressBar.new()
	_ab_bar.custom_minimum_size = Vector2(STATUS_PANEL_WIDTH - 16, 12)
	_ab_bar.min_value = 0.0
	_ab_bar.max_value = 1.0
	_ab_bar.value = 1.0
	_ab_bar.show_percentage = false
	_ab_bar.focus_mode = Control.FOCUS_NONE
	_ab_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ab_bg := StyleBoxFlat.new()
	ab_bg.bg_color = Color(0.08, 0.07, 0.05, 0.7)
	ab_bg.border_color = Color(0.62, 0.48, 0.22)
	ab_bg.set_border_width_all(1)
	ab_bg.set_corner_radius_all(2)
	_ab_bar.add_theme_stylebox_override("background", ab_bg)
	_ab_bar_fill = StyleBoxFlat.new()
	_ab_bar_fill.bg_color = AB_BAR_READY
	_ab_bar_fill.set_corner_radius_all(2)
	_ab_bar.add_theme_stylebox_override("fill", _ab_bar_fill)
	tac_vbox.add_child(_ab_bar)

	_btn_evasion = _create_tac_button(tr("TACTIC_EVADE_FMT") % tr("STATE_OFF"))
	_btn_evasion.pressed.connect(_on_evasion_pressed)
	_btn_evasion.mouse_entered.connect(_on_tac_hover.bind("evasion"))
	_btn_evasion.mouse_exited.connect(_on_tac_hover_exit)
	tac_vbox.add_child(_btn_evasion)

	_btn_auto_fire = _create_tac_button(tr("TACTIC_AUTOFIRE_FMT") % tr("STATE_ON"))
	_btn_auto_fire.pressed.connect(_on_auto_fire_pressed)
	_btn_auto_fire.mouse_entered.connect(_on_tac_hover.bind("auto_fire"))
	_btn_auto_fire.mouse_exited.connect(_on_tac_hover_exit)
	tac_vbox.add_child(_btn_auto_fire)

	_btn_auto_engage = _create_tac_button(tr("TACTIC_AUTO_ENGAGE_FMT") % tr("STATE_ON"))
	_btn_auto_engage.pressed.connect(_on_auto_engage_pressed)
	_btn_auto_engage.mouse_entered.connect(_on_tac_hover.bind("auto_engage"))
	_btn_auto_engage.mouse_exited.connect(_on_tac_hover_exit)
	tac_vbox.add_child(_btn_auto_engage)

	_add_ui_child(_tactical_panel)

	# ── 小队指挥面板（仅当主角有僚机时显示）──
	_build_squad_panel()

	# ── BOSS 小队状态面板 ──
	_build_boss_panel()

	# ── 王牌中队交战血条（分段命条，spec ace-squadron-tier §2.8）──
	_build_ace_panel()

	# ── 战术提示面板 ──
	_tooltip_panel = PanelContainer.new()
	_tooltip_panel.visible = false
	var tip_style := StyleBoxFlat.new()
	tip_style.bg_color = ThemeColors.PANEL_BG_TOOLTIP
	tip_style.border_color = ThemeColors.PANEL_BORDER_TOOLTIP
	tip_style.set_border_width_all(1)
	tip_style.set_corner_radius_all(3)
	tip_style.content_margin_left = 10
	tip_style.content_margin_right = 10
	tip_style.content_margin_top = 8
	tip_style.content_margin_bottom = 8
	_tooltip_panel.add_theme_stylebox_override("panel", tip_style)
	_tooltip_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE

	_tooltip_label = RichTextLabel.new()
	_tooltip_label.bbcode_enabled = true
	_tooltip_label.fit_content = true
	_tooltip_label.scroll_active = false
	_tooltip_label.custom_minimum_size = Vector2(220, 0)
	_tooltip_label.add_theme_font_size_override("normal_font_size", 11)
	_tooltip_label.add_theme_color_override("default_color", ThemeColors.TEXT_PRIMARY_ALT)
	_tooltip_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tooltip_panel.add_child(_tooltip_label)
	_add_ui_child(_tooltip_panel)

	# 用户定稿：旧 TACTICS + 玩家信息栏由纯显示玩家仪表替换；保留旧节点仅降低共享工作树
	# 大段删除的冲突风险，但它们不再显示、更新或接收鼠标输入。
	_status_panel.visible = false
	_tactical_panel.visible = false
	_tooltip_panel.visible = false
	_player_instrument = PlayerInstrumentPanelScript.new()
	_player_instrument.scale = Vector2.ONE * _player_hud_scale
	_add_ui_child(_player_instrument)
	_wingman_instrument = WingmanInstrumentPanelScript.new()
	_add_ui_child(_wingman_instrument)

	# ── 雷达小地图（左下角）──
	_radar = RadarDisplay.new()
	_radar.hud = self
	_add_ui_child(_radar)

	# ── Game Over 面板 ──
	_game_over_panel = PanelContainer.new()
	_game_over_panel.visible = false
	_add_ui_child(_game_over_panel)

	var go_style := StyleBoxFlat.new()
	go_style.bg_color = ThemeColors.PANEL_BG_GAMEOVER
	go_style.border_color = ThemeColors.PANEL_BORDER_GAMEOVER
	go_style.set_border_width_all(2)
	go_style.set_corner_radius_all(4)
	go_style.set_content_margin_all(30)
	_game_over_panel.add_theme_stylebox_override("panel", go_style)

	_game_over_label = RichTextLabel.new()
	_game_over_label.bbcode_enabled = true
	_game_over_label.fit_content = true
	_game_over_label.custom_minimum_size = Vector2(300, 200)
	_game_over_label.add_theme_font_size_override("normal_font_size", 14)
	_game_over_label.add_theme_color_override("default_color", ThemeColors.TEXT_PRIMARY)
	_game_over_panel.add_child(_game_over_label)

	# ── 屏幕外威胁方位指示 ──
	_threat_overlay = ThreatOverlay.new()
	_threat_overlay.hud = self
	_add_ui_child(_threat_overlay)

	# ── 击杀经验表现层（叠在经验条之上，仅保留 +N 沉入效果）──
	_xp_vfx = XpGainVfx.new()
	_add_ui_child(_xp_vfx)

	# ── Debug 性能面板（F3）──
	_debug_panel = PanelContainer.new()
	_debug_panel.visible = false
	var dbg_style := StyleBoxFlat.new()
	dbg_style.bg_color = ThemeColors.PANEL_BG_DEBUG
	dbg_style.set_corner_radius_all(3)
	dbg_style.set_content_margin_all(8)
	_debug_panel.add_theme_stylebox_override("panel", dbg_style)
	_add_ui_child(_debug_panel)

	_debug_label = Label.new()
	_debug_label.add_theme_font_size_override("font_size", 11)
	_debug_label.add_theme_color_override("font_color", ThemeColors.TEXT_DEBUG)
	_debug_panel.add_child(_debug_label)

	# ── 战况栏 / kill feed（左上角，订阅 EventLogger 击杀信号）──
	_kill_feed_container = VBoxContainer.new()
	_kill_feed_container.add_theme_constant_override("separation", 2)
	_kill_feed_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_add_ui_child(_kill_feed_container)
	EventLogger.kill_recorded.connect(_on_kill_recorded)


func _ensure_ui_root() -> void:
	if _ui_root != null:
		return
	_ui_root = Control.new()
	_ui_root.name = "UiRoot"
	_ui_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_ui_root)


func _add_ui_child(child: Node) -> void:
	_ensure_ui_root()
	_ui_root.add_child(child)


static func snap_player_hud_scale(value: float) -> float:
	var stepped := roundf(value / PLAYER_HUD_SCALE_STEP) * PLAYER_HUD_SCALE_STEP
	return clampf(stepped, PLAYER_HUD_SCALE_MIN, PLAYER_HUD_SCALE_MAX)


static func right_anchored_player_rect(viewport_size: Vector2,
		panel_size: Vector2, value: float) -> Rect2:
	var safe_scale := snap_player_hud_scale(value)
	var scaled_size := panel_size * safe_scale
	return Rect2(
		Vector2(viewport_size.x - scaled_size.x,
			viewport_size.y - PLAYER_HUD_BOTTOM_MARGIN - scaled_size.y),
		scaled_size)


static func bottom_bar_rect(viewport_size: Vector2) -> Rect2:
	return Rect2(0.0, viewport_size.y - BOTTOM_BAR_HEIGHT,
		viewport_size.x, BOTTOM_BAR_HEIGHT)


static func top_time_rect(viewport_size: Vector2) -> Rect2:
	return Rect2((viewport_size.x - TIME_PANEL_SIZE.x) * 0.5, 0.0,
		TIME_PANEL_SIZE.x, TIME_PANEL_SIZE.y)


static func warzone_time_rect(viewport_size: Vector2) -> Rect2:
	return Rect2((viewport_size.x - WarzoneTimePanelScript.PANEL_SIZE.x) * 0.5,
		TIME_PANEL_SIZE.y,
		WarzoneTimePanelScript.PANEL_SIZE.x, WarzoneTimePanelScript.PANEL_SIZE.y)


static func formatted_elapsed_time(seconds: float) -> String:
	var total_seconds := floori(maxf(seconds, 0.0))
	var minutes := mini(total_seconds / 60, 99)
	return "TIME  %02d:%02d" % [minutes, total_seconds % 60]


static func bottom_progress_rect(viewport_size: Vector2) -> Rect2:
	var bar := bottom_bar_rect(viewport_size)
	return Rect2((viewport_size.x - BottomExperiencePanelScript.TOTAL_SIZE.x) * 0.5,
		bar.position.y,
		BottomExperiencePanelScript.TOTAL_SIZE.x,
		BottomExperiencePanelScript.TOTAL_SIZE.y)


static func bottom_axis_rect(viewport_size: Vector2) -> Rect2:
	var group := bottom_progress_rect(viewport_size)
	return Rect2(group.position.x + BottomExperiencePanelScript.SIDE_WIDTH,
		group.position.y,
		XP_BAR_WIDTH, MilestoneAxisCounterScript.COUNTER_SIZE.y)


static func bottom_xp_rect(viewport_size: Vector2) -> Rect2:
	var group := bottom_progress_rect(viewport_size)
	return Rect2(group.position.x + BottomExperiencePanelScript.SIDE_WIDTH,
		group.position.y + MilestoneAxisCounterScript.COUNTER_SIZE.y,
		XP_BAR_WIDTH, XP_BAR_HEIGHT)


func hud_viewport_size() -> Vector2:
	var viewport := get_viewport()
	if viewport == null:
		return Vector2.ZERO
	return viewport.get_visible_rect().size


func player_hud_scale() -> float:
	return _player_hud_scale


func set_player_hud_scale(value: float) -> void:
	_player_hud_scale = snap_player_hud_scale(value)
	if _player_instrument != null:
		_player_instrument.scale = Vector2.ONE * _player_hud_scale
	if _ui_dev_scale_slider != null \
			and not is_equal_approx(float(_ui_dev_scale_slider.value), _player_hud_scale):
		_ui_dev_scale_slider.set_value_no_signal(_player_hud_scale)
	_update_ui_dev_scale_label()
	if is_inside_tree():
		_layout_ui()
		if _ui_dev_visible:
			_refresh_ui_dev_overlay(true)


func _update_ui_dev_scale_label() -> void:
	if _ui_dev_scale_label != null:
		_ui_dev_scale_label.text = "PLAYER HUD SCALE  %.1fx" % _player_hud_scale


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_F3:
		_debug_visible = not _debug_visible
		_debug_panel.visible = _debug_visible

func _process(delta: float) -> void:
	_layout_ui()
	if _ui_dev_visible:
		_refresh_ui_dev_overlay()
	# 战术按钮（含加力进度）保持逐帧；信息读数层由独立的 2Hz 时钟刷新。
	_update_tactical_buttons()
	_update_hud_data_layer(delta)
	_update_kill_feed(delta)
	if _debug_visible:
		_debug_update_timer -= delta
		if _debug_update_timer <= 0.0:
			_debug_update_timer = 0.25
			_update_debug_panel()

func _update_hud_data_layer(delta: float) -> void:
	_hud_data_refresh_timer -= delta
	if _hud_data_refresh_timer > 0.0:
		return
	_hud_data_refresh_timer = HUD_DATA_REFRESH_INTERVAL
	_update_display()
	_update_squad_panel()
	_update_boss_panel()
	_update_ace_panel()

func toggle_ui_dev_overlay() -> void:
	_ui_dev_visible = not _ui_dev_visible
	_ensure_ui_dev_overlay()
	_ui_dev_overlay.visible = _ui_dev_visible
	_ui_dev_manual_flare_button.visible = _ui_dev_visible
	_ui_dev_scale_label.visible = _ui_dev_visible
	_ui_dev_scale_slider.visible = _ui_dev_visible
	if _ui_dev_visible:
		_refresh_ui_dev_overlay(true)


func is_ui_dev_overlay_visible() -> bool:
	return _ui_dev_visible


func _ensure_ui_dev_overlay() -> void:
	if _ui_dev_overlay != null:
		return
	_ui_dev_overlay = UiDevOutlineOverlayScript.new()
	_ui_dev_overlay.flatten_descendants = true
	_ui_dev_overlay.visible = false
	add_child(_ui_dev_overlay)
	_ui_dev_manual_flare_button = Button.new()
	_ui_dev_manual_flare_button.text = "DEV  + MANUAL FLR [R]"
	_ui_dev_manual_flare_button.position = Vector2(24.0, 24.0)
	_ui_dev_manual_flare_button.size = Vector2(220.0, 34.0)
	_ui_dev_manual_flare_button.visible = false
	_ui_dev_manual_flare_button.z_index = 1001
	_ui_dev_manual_flare_button.pressed.connect(_on_ui_dev_add_manual_flare_pressed)
	add_child(_ui_dev_manual_flare_button)
	_ui_dev_scale_label = Label.new()
	_ui_dev_scale_label.position = Vector2(24.0, 70.0)
	_ui_dev_scale_label.size = Vector2(220.0, 22.0)
	_ui_dev_scale_label.visible = false
	_ui_dev_scale_label.z_index = 1001
	_ui_dev_scale_label.add_theme_font_size_override("font_size", 14)
	_ui_dev_scale_label.add_theme_color_override(
		"font_color", UiDevOutlineOverlayScript.OUTLINE_COLOR)
	_ui_dev_scale_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_ui_dev_scale_label)
	_ui_dev_scale_slider = HSlider.new()
	_ui_dev_scale_slider.position = Vector2(24.0, 94.0)
	_ui_dev_scale_slider.size = Vector2(220.0, 28.0)
	_ui_dev_scale_slider.min_value = PLAYER_HUD_SCALE_MIN
	_ui_dev_scale_slider.max_value = PLAYER_HUD_SCALE_MAX
	_ui_dev_scale_slider.step = PLAYER_HUD_SCALE_STEP
	_ui_dev_scale_slider.value = _player_hud_scale
	_ui_dev_scale_slider.tick_count = 6
	_ui_dev_scale_slider.ticks_on_borders = true
	_ui_dev_scale_slider.allow_lesser = false
	_ui_dev_scale_slider.allow_greater = false
	_ui_dev_scale_slider.scrollable = false
	_ui_dev_scale_slider.visible = false
	_ui_dev_scale_slider.z_index = 1001
	_ui_dev_scale_slider.value_changed.connect(_on_ui_dev_scale_changed)
	add_child(_ui_dev_scale_slider)
	_update_ui_dev_scale_label()


func _on_ui_dev_add_manual_flare_pressed() -> void:
	if _player_instrument == null:
		return
	if _player_instrument.debug_grant_manual_flare_skill():
		_ui_dev_manual_flare_button.text = "DEV  MANUAL FLR ADDED"
		_ui_dev_manual_flare_button.disabled = true
		_refresh_ui_dev_overlay(true)


func _on_ui_dev_scale_changed(value: float) -> void:
	set_player_hud_scale(value)


func _refresh_ui_dev_overlay(force := false) -> void:
	_ensure_ui_dev_overlay()
	var viewport := get_viewport()
	if viewport != null:
		_ui_dev_overlay.size = viewport.get_visible_rect().size
	var next_regions := _collect_ui_dev_regions()
	if not force and next_regions == _ui_dev_regions:
		return
	_ui_dev_regions = next_regions
	_ui_dev_overlay.regions = next_regions


func _collect_ui_dev_regions() -> Array[Rect2]:
	var result: Array[Rect2] = []
	if _time_panel != null:
		result.append(Rect2(_time_panel.position, _time_panel.size))
	if _warzone_timer_panel != null:
		_append_ui_dev_component_regions(result, _warzone_timer_panel.position,
			_warzone_timer_panel.size, WarzoneTimePanelScript.grid_regions(), 1.0)
	if _wingman_instrument != null and _wingman_instrument.visible \
			and _wingman_instrument.size.y > 0.0:
		var wing_count := roundi(
			_wingman_instrument.size.y / WingmanInstrumentPanelScript.ROW_STRIDE)
		var wing_children: Array[Rect2] = []
		for row_index in range(wing_count):
			wing_children.append(Rect2(
				Vector2(0.0, float(row_index) * WingmanInstrumentPanelScript.ROW_STRIDE),
				Vector2(WingmanInstrumentPanelScript.PANEL_WIDTH,
					WingmanInstrumentPanelScript.ROW_BODY_HEIGHT)
			))
		wing_children.append_array(WingmanInstrumentPanelScript.grid_regions(wing_count))
		_append_ui_dev_component_regions(result, _wingman_instrument.position,
			_wingman_instrument.size, wing_children, 1.0)

	if _player_instrument != null:
		var ac := _safe_player_aircraft()
		var maneuver_visible := PlayerInstrumentPanelScript.maneuver_skill_visible(ac)
		_append_ui_dev_component_regions(result, _player_instrument.position,
			_player_instrument.size,
			_player_instrument.grid_regions(maneuver_visible,
				PlayerInstrumentPanelScript.manual_flare_key_visible(ac)),
			_player_hud_scale)

	if _milestone_axis_counter != null:
		_append_ui_dev_component_regions(result, _milestone_axis_counter.position,
			_milestone_axis_counter.size, MilestoneAxisCounterScript.grid_regions(), 1.0)
	if _bottom_experience_panel != null:
		_append_ui_dev_component_regions(result, _bottom_experience_panel.position,
			_bottom_experience_panel.size, BottomExperiencePanelScript.grid_regions(), 1.0)
	if _bottom_bar_bg != null:
		result.append(Rect2(_bottom_bar_bg.position, _bottom_bar_bg.size))
	return result


func _append_ui_dev_component_regions(target: Array[Rect2], origin: Vector2,
		root_size: Vector2, children: Array[Rect2], value: float) -> void:
	if root_size.x <= 0.0 or root_size.y <= 0.0:
		return
	var safe_scale := snap_player_hud_scale(value)
	target.append(Rect2(origin, root_size * safe_scale))
	for child in children:
		target.append(Rect2(
			origin + child.position * safe_scale,
			child.size * safe_scale))

func _layout_ui() -> void:
	var vp := hud_viewport_size()
	if vp == Vector2.ZERO:
		return
	_ui_root.position = Vector2.ZERO
	_ui_root.size = vp
	var time_rect := top_time_rect(vp)
	_time_panel.position = time_rect.position
	_time_panel.size = time_rect.size
	_time_grid.position = Vector2.ZERO
	_time_grid.size = time_rect.size
	_time_label.position = Vector2.ZERO
	_time_label.size = time_rect.size
	var remaining_rect := warzone_time_rect(vp)
	_warzone_timer_panel.position = remaining_rect.position
	_warzone_timer_panel.size = remaining_rect.size

	# 战况栏：左上角（最新在上，向下堆叠）
	if _kill_feed_container:
		_kill_feed_container.position = Vector2(16, 92)

	# BOSS 小队面板：屏幕中上方，击杀标签下方
	if _boss_panel and _boss_panel.visible:
		_boss_panel.position = Vector2(
			vp.x * 0.5 - _boss_panel.size.x * 0.5,
			86
		)
	# 王牌中队血条：与 BOSS 面板同一锚位（两者互斥，BOSS 条优先，tier §2.8）
	if _ace_panel and _ace_panel.visible:
		_ace_panel.position = Vector2(
			vp.x * 0.5 - _ace_panel.size.x * 0.5,
			86
		)

	var bottom_bar := bottom_bar_rect(vp)
	_bottom_bar_bg.position = bottom_bar.position
	_bottom_bar_bg.size = bottom_bar.size
	_bottom_bar_grid.position = Vector2.ZERO
	_bottom_bar_grid.size = _bottom_bar_bg.size
	_bottom_bar_grid.line_color = HudPreferencesScript.hud_color()
	var bottom_bar_regions: Array[Rect2] = [Rect2(Vector2.ZERO, _bottom_bar_bg.size)]
	_bottom_bar_grid.regions = bottom_bar_regions
	var axis_rect := bottom_axis_rect(vp)
	var xp_rect := bottom_xp_rect(vp)
	_bottom_experience_panel.position = bottom_progress_rect(vp).position
	_milestone_axis_counter.position = axis_rect.position
	if _xp_vfx:
		_xp_vfx.bar_rect = xp_rect

	# 状态面板：右下角，经验条上方
	_status_panel.position = Vector2(
		vp.x - _status_panel.size.x - 16,
		vp.y - _status_panel.size.y - XP_BAR_HEIGHT - 36
	)

	# 战术面板：状态面板正上方
	_tactical_panel.position = Vector2(
		vp.x - _tactical_panel.size.x - 16,
		_status_panel.position.y - _tactical_panel.size.y - 8
	)
	# 玩家仪表：严格占用旧 TACTICS + 状态栏的右下区域；其它 HUD 不动。
	if _player_instrument:
		var player_ac := _safe_player_aircraft()
		_player_instrument.update_status(
			player_ac != null and player_ac.cloud_state == 2,
			kill_count)
		_player_instrument.scale = Vector2.ONE * _player_hud_scale
		_player_instrument.position = right_anchored_player_rect(
			vp, _player_instrument.size, _player_hud_scale).position
	# 僚机面板保持独立的 1.0x 布局，不随玩家仪表滑条缩放或位移。
	if _wingman_instrument and _player_instrument:
		_wingman_instrument.scale = Vector2.ONE
		_wingman_instrument.position = Vector2(
			vp.x - _wingman_instrument.size.x,
			vp.y - PLAYER_HUD_BOTTOM_MARGIN - _player_instrument.size.y
				- _wingman_instrument.size.y
		)

	# 旧富文本小队面板仅保留逻辑入口；显示由玩家仪表上方的独立僚机行接管。
	if _squad_panel:
		_squad_panel.visible = false

	# 提示面板：战术面板左侧
	if _tooltip_panel.visible:
		_tooltip_panel.position = Vector2(
			_tactical_panel.position.x - _tooltip_panel.size.x - 8,
			_tactical_panel.position.y
		)

	if _debug_panel.visible:
		_debug_panel.position = Vector2(vp.x - _debug_panel.size.x - 16, 16)

	if _game_over_panel.visible:
		_game_over_panel.position = Vector2(
			(vp.x - _game_over_panel.size.x) * 0.5,
			(vp.y - _game_over_panel.size.y) * 0.5
		)

## survivor_mode 调用：注入战区阶段剩余秒数 + 是否进入 BOSS 阶段
## 升级面板暂停期间（_physics_process 早 return）由 survivor_mode 在打开面板前同步一次
func set_warzone_remaining(seconds: float, in_boss_phase: bool) -> void:
	_warzone_remaining = seconds
	_warzone_in_boss_phase = in_boss_phase
	if _warzone_timer_panel:
		_warzone_timer_panel.update_display(seconds, in_boss_phase)

func _update_display() -> void:
	if not survivor_player:
		return

	# 时间
	_time_label.text = formatted_elapsed_time(game_time)
	var hud_accent: Color = HudPreferencesScript.hud_color()
	_time_label.font_color = hud_accent
	_time_grid.line_color = hud_accent
	_bottom_bar_grid.line_color = hud_accent

	# 经验条
	_bottom_experience_panel.update_display(survivor_player)
	_milestone_axis_counter.update_display(survivor_player)

	_update_player_instrument()

func _update_player_instrument() -> void:
	if _player_instrument == null:
		return
	_player_instrument.update_display(_safe_player_aircraft(), afterburner_charge)

## 收到击杀信号 → 战况栏顶部插入一条（友机击坠=绿 / 友机阵亡=红 / 中立=灰），超上限移除最旧
func _on_kill_recorded(killer: String, victim: String, weapon_kind: String, killer_team: int, victim_team: int, _victim_voiced: bool) -> void:
	if not _kill_feed_container:
		return
	var col: Color
	if victim_team == 0:
		col = ThemeColors.HP_LOW       # 玩家小队被击坠 → 红
	elif killer_team == 0:
		col = ThemeColors.HP_OK        # 玩家小队击坠敌机 → 绿
	elif victim_team == 2 or killer_team == 2:
		col = GameConstants.COL_FRIEND_ALLY   # 第三方参战（击坠/被击坠）→ 海绿（友军色）
	else:
		col = ThemeColors.TEXT_MUTED   # 敌方内讧 / 中立 → 灰
	var wpn := _feed_weapon_label(weapon_kind)
	var line := ""
	if wpn != "":
		line = "%s  →%s→  %s" % [killer, wpn, victim]
	else:
		line = "%s  →  %s" % [killer, victim]
	var lbl := Label.new()
	lbl.text = line
	lbl.add_theme_font_size_override("font_size", 13)
	lbl.add_theme_color_override("font_color", col)
	lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	lbl.add_theme_constant_override("outline_size", 4)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_kill_feed_container.add_child(lbl)
	_kill_feed_container.move_child(lbl, 0)   # 最新置顶
	_kill_feed_entries.push_front({"label": lbl, "age": 0.0})
	while _kill_feed_entries.size() > KILL_FEED_MAX:
		var old: Dictionary = _kill_feed_entries.pop_back()
		var ol = old.get("label")
		if is_instance_valid(ol):
			ol.queue_free()

## 每帧推进战况栏条目年龄：HOLD 秒后开始淡出，完全透明则移除
func _update_kill_feed(delta: float) -> void:
	var i := _kill_feed_entries.size() - 1
	while i >= 0:
		var e: Dictionary = _kill_feed_entries[i]
		var lbl = e.get("label")
		if not is_instance_valid(lbl):
			_kill_feed_entries.remove_at(i)
			i -= 1
			continue
		e["age"] = float(e["age"]) + delta
		var age: float = e["age"]
		if age > KILL_FEED_HOLD + KILL_FEED_FADE:
			lbl.queue_free()
			_kill_feed_entries.remove_at(i)
		elif age > KILL_FEED_HOLD:
			lbl.modulate.a = 1.0 - (age - KILL_FEED_HOLD) / KILL_FEED_FADE
		i -= 1

## 武器种类 → 本地化标签；i18n 未导入时回退中文，保证不崩
func _feed_weapon_label(kind: String) -> String:
	var key := ""
	match kind:
		"gun": key = "WEAPON_GUN"
		"missile": key = "WEAPON_MISSILE"
		"rocket": key = "WEAPON_ROCKET"
		"aoe": key = "WEAPON_AOE"
		"ground_crash": key = "WEAPON_CRASH"
		_: return ""
	var t := tr(key)
	if t != key:
		return t
	match kind:   # 翻译未导入 → 中文回退
		"gun": return "机炮"
		"missile": return "导弹"
		"rocket": return "火箭弹"
		"aoe": return "爆炸"
		"ground_crash": return "坠地"
	return ""

func _update_status_panel() -> void:
	var ac: Aircraft = _safe_player_aircraft()
	if not ac or ac.is_destroyed:
		_status_label.text = ""
		return

	var text := ""

	# ── HP ──
	var current_hp := survivor_player.get_hp()
	var max_hp := survivor_player.get_max_hp()
	var hp_ratio := current_hp / maxf(max_hp, 1.0)
	var hp_color := "66ff66" if hp_ratio > 0.5 else ("ffcc33" if hp_ratio > 0.25 else "ff4444")
	text += "[color=#%s]HP %d / %d[/color]\n" % [hp_color, ceili(current_hp), ceili(max_hp)]

	# ── G 力（实时 / 结构极限）──
	# 分母用瞬时结构 G（猛拉可达的物理上限 max_g_structural），与头顶浮动栏的
	# 当前 g_load 自洽 —— 否则会出现"当前 10.0 / 上限 7.5"这种当前超上限的怪象。
	# 颜色：超持续 max_g（进入掉能量的结构 G 区间）转橙，逼近结构上限转红。
	var g_cur: float = ac.g_load
	var g_sustained: float = ac._effective_max_g()
	var g_struct: float = ac._effective_max_g_instant()
	var g_color := "ff4444" if g_cur >= g_struct * 0.97 else ("ffaa33" if g_cur > g_sustained + 0.05 else "ccddee")
	text += "[color=#%s]G   %.1f / %.1f[/color]\n" % [g_color, g_cur, g_struct]

	# ── 速度 / 加力 ──（双击启动 AB）
	var spd_kmh: int = roundi(ac.speed * 3.6)
	if ac.is_afterburner:
		text += "[color=#ff8833]SPD  %d km/h  ◤AB◢[/color]\n" % spd_kmh
	else:
		text += "[color=#ccddee]SPD  %d km/h[/color]\n" % spd_kmh

	# ── 失速警告 ──（速度低于失速线，机动严重受限）
	# 闪烁式视觉：每秒交替深红/亮红，红字超大字 ! 标志足够刺眼
	if ac.is_stalled:
		var flash := int(Time.get_ticks_msec() / 250) % 2 == 0
		var stall_color := "ff3322" if flash else "ff7733"
		text += "[color=#%s][b]⚠ STALL[/b][/color]\n" % stall_color

	# ── 高度档位 ──（tier 名 + 实际米数；切档目标 ≠ 档位判定线，爬升在翻 HIGH 后仍会继续，
	# 只看 tier 名会显得"爬了很久没变化"，故补数字 + 升降箭头让进度可见）
	# 颜色用 vs 判定（与数据标签同步）：vs > 5 m/s 视为升降中 → 过渡色，否则 tier 静态色
	if ac.flat_altitude:
		var tier_cur: int = ac.get_altitude_tier()
		var tier_name: String = Aircraft.TIER_NAMES[tier_cur]
		var vs_abs: float = absf(ac.vertical_speed)
		var changing: bool = vs_abs > 5.0
		var hex_col := AircraftRenderer.altitude_tier_color_hex(tier_cur, changing)
		var arrow := ""
		if changing:
			arrow = "  ↑" if ac.vertical_speed > 0.0 else "  ↓"
		text += "[color=#%s]ALT  %s  %dm%s[/color]\n" % [hex_col, tier_name, roundi(ac.altitude), arrow]

	# ── 导弹 ──
	var max_msl := ac.params.missile.max_count if ac.params and ac.params.missile else 0
	if max_msl > 0:
		if ac._missile_reload_active:
			var pct := int(ac.missile_reload_progress * 100)
			text += "[color=#5599ff]MSL  RELOAD %d%%[/color]\n" % pct
		else:
			var msl_color := "88bbff" if ac.missiles_remaining > 0 else "666666"
			text += "[color=#%s]MSL  %d / %d[/color]\n" % [msl_color, ac.missiles_remaining, max_msl]

	# ── 副导弹槽（SP，仅装备时显示）──
	# 完全独立于 MSL 的子系统：独立锁定 / 独立 cooldown / 独立装填
	# 详见 docs/changelogs/2026-05-10-secondary-slot-revival.md
	if ac.params and ac.params.secondary_missile:
		var sec: MissileParams = ac.params.secondary_missile
		var max_sp := sec.max_count
		var sp_name := sec.display_name if sec.display_name else "SP"
		if ac._secondary_reload_active:
			text += "[color=#ffaa55]%s  RELOAD[/color]\n" % sp_name
		elif ac._secondary_cooldown > 0.05:
			var cd_ratio_sp: float = 0.0
			if sec.cooldown > 0.0:
				cd_ratio_sp = clampf(ac._secondary_cooldown / sec.cooldown, 0.0, 1.0)
			text += "[color=#aa6633]%s  CD %d%%[/color]\n" % [sp_name, int(cd_ratio_sp * 100)]
		else:
			var sp_color := "ffcc66" if ac.secondary_missiles_remaining > 0 else "666666"
			text += "[color=#%s]%s  %d / %d[/color]\n" % [sp_color, sp_name, ac.secondary_missiles_remaining, max_sp]

	# ── 机炮 ──
	if ac.params and ac.params.gun:
		var max_ammo := ac.params.gun.max_ammo
		if ac.enable_gun_reload and ac._gun_reload_active:
			var pct := int(ac.gun_reload_progress * 100)
			text += "[color=#aa7733]GUN  RELOAD %d%%[/color]\n" % pct
		else:
			var ammo_color := "ccddaa" if ac.ammo > 100 else ("ffaa44" if ac.ammo > 0 else "666666")
			text += "[color=#%s]GUN  %d / %d[/color]\n" % [ammo_color, ac.ammo, max_ammo]

	# ── 火箭弹（RKT）──
	if ac.params and ac.params.rocket:
		var rk: RocketParams = ac.params.rocket
		var cd_ratio_rkt: float = 0.0
		if rk.burst_cooldown > 0.0:
			cd_ratio_rkt = clampf(ac._rocket_burst_cooldown / rk.burst_cooldown, 0.0, 1.0)
		var rkt_color := "ff9944"
		if cd_ratio_rkt > 0.01:
			rkt_color = "884422"
		if rk.infinite_ammo:
			if cd_ratio_rkt > 0.01:
				text += "[color=#%s]RKT  CD %d%%[/color]\n" % [rkt_color, int(cd_ratio_rkt * 100)]
			else:
				text += "[color=#%s]RKT  READY[/color]\n" % rkt_color
		else:
			var max_rkt := rk.max_ammo
			if ac.rockets_remaining <= 0:
				rkt_color = "666666"
			text += "[color=#%s]RKT  %d / %d[/color]\n" % [rkt_color, ac.rockets_remaining, max_rkt]

	# ── 空中鱼雷（TORP，规避模式下自动抛投）──
	if ac.params and ac.params.torpedo:
		var tp: TorpedoParams = ac.params.torpedo
		var cd_ratio_t: float = 0.0
		if tp.cooldown > 0.0:
			cd_ratio_t = clampf(ac._torpedo_cooldown / tp.cooldown, 0.0, 1.0)
		var torp_color := "55ddee"
		if not ac.evasion_mode:
			torp_color = "557788"  # 灰色：规避未激活，不会投放
		elif cd_ratio_t > 0.01:
			torp_color = "338899"
		if cd_ratio_t > 0.01:
			text += "[color=#%s]TORP CD %d%%[/color]\n" % [torp_color, int(cd_ratio_t * 100)]
		else:
			if ac.evasion_mode:
				text += "[color=#%s]TORP READY[/color]\n" % torp_color
			else:
				text += "[color=#%s]TORP (AB)[/color]\n" % torp_color

	# ── 忠诚僚机（WMN，规避模式下自动释放，与 TORP 互斥槽位）──
	if ac.params and ac.params.loyal_wingman:
		var lw: LoyalWingmanParams = ac.params.loyal_wingman
		var alive: int = ac._alive_drones.size()
		var cd_ratio_w: float = 0.0
		if lw.cooldown > 0.0:
			cd_ratio_w = clampf(ac._loyal_wingman_cooldown / lw.cooldown, 0.0, 1.0)
		var wmn_color := "88ddaa"  # 默认绿
		if not ac.evasion_mode:
			wmn_color = "557766"   # 灰：规避未激活
		elif alive >= lw.max_simultaneous:
			wmn_color = "667788"   # 蓝灰：到达 cap
		elif cd_ratio_w > 0.01:
			wmn_color = "447755"   # 暗绿：CD 中
		if alive >= lw.max_simultaneous:
			text += "[color=#%s]WMN  %d/%d  MAX[/color]\n" % [wmn_color, alive, lw.max_simultaneous]
		elif cd_ratio_w > 0.01:
			text += "[color=#%s]WMN  %d/%d  CD %d%%[/color]\n" % [wmn_color, alive, lw.max_simultaneous, int(cd_ratio_w * 100)]
		else:
			if ac.evasion_mode:
				text += "[color=#%s]WMN  %d/%d  READY[/color]\n" % [wmn_color, alive, lw.max_simultaneous]
			else:
				text += "[color=#%s]WMN  %d/%d  (AB)[/color]\n" % [wmn_color, alive, lw.max_simultaneous]

	# ── 热诱弹 ──
	if ac.params and ac.params.flare:
		var max_flr := ac.params.flare.max_flares
		if ac.enable_flare_reload and ac.flares_remaining <= 0 and ac.flare_reload_progress > 0.01:
			var pct := int(ac.flare_reload_progress * 100)
			# 热诱弹耗尽时把装填行做成双色闪烁，避免混在普通武器 CD 里看漏。
			var empty_flash: bool = int(Time.get_ticks_msec() / 180) % 2 == 0
			var reload_color := "ff4433" if empty_flash else "ffbb33"
			text += "[color=#%s][b]FLR  RELOAD %d%%[/b][/color]\n" % [reload_color, pct]
		else:
			var cd_ratio := ac.get_flare_cooldown_ratio()
			var flr_color := "ffdd66"
			if cd_ratio > 0.01:
				flr_color = "aa8833"
			elif ac.flares_remaining <= 0:
				flr_color = "666666"
			var cd_text := "  CD" if cd_ratio > 0.01 else ""
			text += "[color=#%s]FLR  %d / %d%s[/color]\n" % [flr_color, ac.flares_remaining, max_flr, cd_text]

	# ── 规避隐身（仅解锁了 evasion_stealth 时显示）──
	if ac.evasion_stealth_active:
		if ac._in_evasion_stealth:
			text += "[color=#b373d9][b]STLH  ACTIVE[/b][/color]\n"
		elif ac.evasion_mode:
			var rem: float = maxf(Aircraft.EVASION_STEALTH_DELAY - ac._evasion_stealth_timer, 0.0)
			text += "[color=#7755aa]STLH  ARM %.1fs[/color]\n" % rem

	# ── 电磁炮（commit 11+）──
	var rg: RailgunEquipment = ac.params.get_equipment_of_kind("railgun") if ac.params else null
	if rg != null:
		var rg_state: Dictionary = ac.equipment_state.get(RailgunEquipment.STATE_KEY, {})
		var charging: bool = rg_state.get("charging", false)
		var charge_p: float = rg_state.get("charge_progress", 0.0)
		var cd: float = rg_state.get("cooldown", 0.0)
		if charging:
			var chg_pct := int(charge_p * 100)
			text += "[color=#aaccff]RAIL  CHG %d%%[/color]\n" % chg_pct
		elif cd > 0.01:
			var cd_ratio_rg: float = 0.0
			if rg.cooldown > 0.0:
				cd_ratio_rg = clampf(cd / rg.cooldown, 0.0, 1.0)
			text += "[color=#aa8833]RAIL  CD %d%%[/color]\n" % int(cd_ratio_rg * 100)
		else:
			text += "[color=#88ddff]RAIL  READY[/color]\n"

	# ── 激光（commit 11+）──
	var le: LaserEquipment = ac.params.get_equipment_of_kind("laser") if ac.params else null
	if le != null:
		var le_state: Dictionary = ac.equipment_state.get(LaserEquipment.STATE_KEY, {})
		var heat: float = le_state.get("heat", 0.0)
		var overheating: bool = le_state.get("overheating", false)
		var heat_pct := int(heat / le.heat_max * 100)
		if overheating:
			var flash := int(Time.get_ticks_msec() / 250) % 2 == 0
			var oh_color := "ff3322" if flash else "ff7733"
			text += "[color=#%s][b]LSR  ⚠ OVERHEAT[/b][/color]\n" % oh_color
		else:
			var heat_color := "88dd88" if heat_pct < 50 else ("ffcc33" if heat_pct < 80 else "ff6633")
			text += "[color=#%s]LSR  HEAT %d%%[/color]\n" % [heat_color, heat_pct]

	# ── 分隔线 ──
	if game_scene and not game_scene.upgrade_stacks.is_empty():
		text += "[color=#445544]────────────[/color]\n"

		# ── 已激活技能 ──
		var stacks: Dictionary = game_scene.upgrade_stacks
		for u in SurvivorData.UPGRADES:
			var uid: String = u["id"]
			var count: int = stacks.get(uid, 0)
			if count <= 0:
				continue
			var is_evolved: bool = u.get("evolved", false)
			var cat: String = u.get("category", "")
			# 与战术地图 / 升级面板同一套轴色
			var tag_color: String
			match cat:
				"survival":           tag_color = "4db366"
				"mobility":           tag_color = "4d99e6"
				"missile":            tag_color = "e68c40"
				"secondary":          tag_color = "e67373"
				"electronic_warfare": tag_color = "b373d9"
				_:                    tag_color = "aaaaaa"
			var max_s := int(u["max_stacks"])
			var level_dots := ""
			if uid == "executioner" and ac:
				# 侩子手特例：右侧显示当前击杀连击层数（动态）
				# 公式：stacks = clamp(kills-1, 0, 5)；下一层需要 (stacks+2-kills) 杀
				var stk: int = ac.executioner_stacks
				var max_st: int = Aircraft.EXECUTIONER_MAX_STACKS
				var stk_color: String = "ffcc44" if stk > 0 else "666666"
				level_dots = "[color=#%s]%d/%d[/color]" % [stk_color, stk, max_st]
				# 进度提示：距下一层还差几杀（满层时不显示）
				if stk < max_st:
					var need: int = stk + Aircraft.EXECUTIONER_FIRST_STACK_KILLS - ac.executioner_kills
					if need < 1:
						need = 1
					level_dots += "[color=#666] (+%d)[/color]" % need
			elif is_evolved:
				level_dots = "[color=#ffcc44]%s[/color]" % tr("ZONE_REWARD_TAG")
			else:
				for i in range(max_s):
					if i < count:
						level_dots += "[color=#aaddaa]|[/color]"
					else:
						level_dots += "[color=#333]|[/color]"
			text += "[color=#%s]%s[/color] %s\n" % [tag_color, tr(u["name"]), level_dots]

	_status_label.text = text

func _create_tac_button(label_text: String) -> Button:
	var btn := Button.new()
	btn.text = label_text
	btn.custom_minimum_size = Vector2(STATUS_PANEL_WIDTH - 16, 26)
	btn.add_theme_font_size_override("font_size", 11)
	# 禁用焦点，避免 Tab 被 UI 焦点循环消费（否则带僚机的主角按 Tab 无法打开战术地图）
	btn.focus_mode = Control.FOCUS_NONE

	var normal := StyleBoxFlat.new()
	normal.bg_color = ThemeColors.BTN_NORMAL_BG
	normal.border_color = ThemeColors.BTN_NORMAL_BORDER
	normal.set_border_width_all(1)
	normal.set_corner_radius_all(2)
	normal.content_margin_left = 6
	normal.content_margin_right = 6
	normal.content_margin_top = 3
	normal.content_margin_bottom = 3
	btn.add_theme_stylebox_override("normal", normal)

	var hover := StyleBoxFlat.new()
	hover.bg_color = ThemeColors.BTN_HOVER_BG
	hover.border_color = ThemeColors.BTN_HOVER_BORDER
	hover.set_border_width_all(1)
	hover.set_corner_radius_all(2)
	hover.content_margin_left = 6
	hover.content_margin_right = 6
	hover.content_margin_top = 3
	hover.content_margin_bottom = 3
	btn.add_theme_stylebox_override("hover", hover)

	var pressed := StyleBoxFlat.new()
	pressed.bg_color = ThemeColors.BTN_PRESSED_BG
	pressed.border_color = ThemeColors.BTN_PRESSED_BORDER
	pressed.set_border_width_all(1)
	pressed.set_corner_radius_all(2)
	pressed.content_margin_left = 6
	pressed.content_margin_right = 6
	pressed.content_margin_top = 3
	pressed.content_margin_bottom = 3
	btn.add_theme_stylebox_override("pressed", pressed)

	btn.add_theme_color_override("font_color", ThemeColors.BTN_TEXT)
	btn.add_theme_color_override("font_hover_color", ThemeColors.BTN_HOVER_TEXT)
	btn.add_theme_color_override("font_pressed_color", ThemeColors.BTN_PRESSED_TEXT)

	return btn

func _on_weapon_pressed() -> void:
	var ac: Aircraft = _safe_player_aircraft()
	if ac == null:
		return
	if ac.weapon_preference == Aircraft.WeaponPreference.PREFER_MISSILE:
		ac.weapon_preference = Aircraft.WeaponPreference.PREFER_GUN
	else:
		ac.weapon_preference = Aircraft.WeaponPreference.PREFER_MISSILE
	_update_tactical_buttons()
	if _tooltip_panel.visible:
		_update_tooltip()

func _on_altitude_pressed() -> void:
	var ac: Aircraft = _safe_player_aircraft()
	if ac == null:
		return
	if ac.altitude_preference == Aircraft.AltitudePreference.PREFER_CLIMB:
		ac.altitude_preference = Aircraft.AltitudePreference.PREFER_LOW
	else:
		ac.altitude_preference = Aircraft.AltitudePreference.PREFER_CLIMB
	_update_tactical_buttons()
	if _tooltip_panel.visible:
		_update_tooltip()

func _on_evasion_pressed() -> void:
	var ac: Aircraft = _safe_player_aircraft()
	if ac == null:
		return
	# 加力模式：走充能资源（spec afterburner-mode，充能制）；有能量即启动，激活中再点关闭。
	# 无资源注入（防御性兜底）时退回旧开关行为。
	if afterburner_charge:
		afterburner_charge.toggle(ac)
	else:
		ac.set_evasion_mode(not ac.evasion_mode)
	_update_tactical_buttons()
	if _tooltip_panel.visible:
		_update_tooltip()

func _on_auto_fire_pressed() -> void:
	var ac: Aircraft = _safe_player_aircraft()
	if ac == null:
		return
	ac.missile_auto_fire = not ac.missile_auto_fire
	_update_tactical_buttons()
	if _tooltip_panel.visible:
		_update_tooltip()

func _on_auto_engage_pressed() -> void:
	var ac: Aircraft = _safe_player_aircraft()
	if ac == null:
		return
	ac.auto_engage_enabled = not ac.auto_engage_enabled
	_update_tactical_buttons()
	if _tooltip_panel.visible:
		_update_tooltip()

func _on_tac_hover(key: String) -> void:
	_tooltip_key = key
	_update_tooltip()
	_tooltip_panel.visible = true

func _on_tac_hover_exit() -> void:
	_tooltip_key = ""
	_tooltip_panel.visible = false

func _update_tooltip() -> void:
	var ac: Aircraft = _safe_player_aircraft()
	if ac == null:
		return
	var text := ""

	var title_key := ""
	var body_key := ""
	var hint_key := ""
	match _tooltip_key:
		"weapon":
			if ac.weapon_preference == Aircraft.WeaponPreference.PREFER_MISSILE:
				title_key = "TOOLTIP_WEAPON_MISSILE_TITLE"
				body_key = "TOOLTIP_WEAPON_MISSILE_BODY"
				hint_key = "TOOLTIP_WEAPON_MISSILE_HINT"
			else:
				title_key = "TOOLTIP_WEAPON_GUN_TITLE"
				body_key = "TOOLTIP_WEAPON_GUN_BODY"
				hint_key = "TOOLTIP_WEAPON_GUN_HINT"
		"altitude":
			if ac.altitude_preference == Aircraft.AltitudePreference.PREFER_CLIMB:
				title_key = "TOOLTIP_ALT_CLIMB_TITLE"
				body_key = "TOOLTIP_ALT_CLIMB_BODY"
				hint_key = "TOOLTIP_ALT_CLIMB_HINT"
			else:
				title_key = "TOOLTIP_ALT_LOW_TITLE"
				body_key = "TOOLTIP_ALT_LOW_BODY"
				hint_key = "TOOLTIP_ALT_LOW_HINT"
		"evasion":
			# 加力模式：ON 文案 = 加力激活中（或兜底旧 evasion 开关）
			if (afterburner_charge != null and afterburner_charge.is_active()) or ac.evasion_mode:
				title_key = "TOOLTIP_EVADE_ON_TITLE"
				body_key = "TOOLTIP_EVADE_ON_BODY"
				hint_key = "TOOLTIP_EVADE_ON_HINT"
			else:
				title_key = "TOOLTIP_EVADE_OFF_TITLE"
				body_key = "TOOLTIP_EVADE_OFF_BODY"
				hint_key = "TOOLTIP_EVADE_OFF_HINT"
		"auto_fire":
			if ac.missile_auto_fire:
				title_key = "TOOLTIP_AUTOFIRE_ON_TITLE"
				body_key = "TOOLTIP_AUTOFIRE_ON_BODY"
				hint_key = "TOOLTIP_AUTOFIRE_ON_HINT"
			else:
				title_key = "TOOLTIP_AUTOFIRE_OFF_TITLE"
				body_key = "TOOLTIP_AUTOFIRE_OFF_BODY"
				hint_key = "TOOLTIP_AUTOFIRE_OFF_HINT"
		"auto_engage":
			if ac.auto_engage_enabled:
				title_key = "TOOLTIP_AUTO_ENGAGE_ON_TITLE"
				body_key = "TOOLTIP_AUTO_ENGAGE_ON_BODY"
				hint_key = "TOOLTIP_AUTO_ENGAGE_ON_HINT"
			else:
				title_key = "TOOLTIP_AUTO_ENGAGE_OFF_TITLE"
				body_key = "TOOLTIP_AUTO_ENGAGE_OFF_BODY"
				hint_key = "TOOLTIP_AUTO_ENGAGE_OFF_HINT"

	if title_key != "":
		# BODY 含 \n 转义，走 LocaleManager.trm() 还原为真实换行
		text = "[color=#ffcc44][b]%s[/b][/color]\n" % tr(title_key)
		text += "[color=#aabbaa]%s[/color]\n\n" % LocaleManager.trm(body_key)
		text += "[color=#888888]%s[/color]" % LocaleManager.trm(hint_key)

	_tooltip_label.text = text

func _update_tactical_buttons() -> void:
	_update_player_instrument()

## 加力充能条 + 按钮三态（spec afterburner-mode，充能制）：条恒为当前能量 charge/CHARGE_MAX。
## 激活=亮青（放空剩余可烧秒数）/ 满能量=亮橙 READY / 部分能量=暗橙百分比。
## 资源未注入（防御性兜底）时退回旧 ON/OFF 文案。
func _update_afterburner_ui() -> void:
	_update_player_instrument()

# ══════════════════════════════════════════════
#  小队指挥面板（仅主角有僚机时存在）
# ══════════════════════════════════════════════

const SQUAD_PANEL_WIDTH := 240.0

func _build_squad_panel() -> void:
	_squad_panel = PanelContainer.new()
	_squad_panel.visible = false  # 默认隐藏，发现僚机时再显示
	var sp_style := StyleBoxFlat.new()
	sp_style.bg_color = ThemeColors.SQUAD_PANEL_BG
	sp_style.border_color = ThemeColors.SQUAD_PANEL_BORDER
	sp_style.set_border_width_all(1)
	sp_style.set_corner_radius_all(3)
	sp_style.content_margin_left = 10
	sp_style.content_margin_right = 10
	sp_style.content_margin_top = 6
	sp_style.content_margin_bottom = 6
	_squad_panel.add_theme_stylebox_override("panel", sp_style)
	_squad_panel.custom_minimum_size = Vector2(SQUAD_PANEL_WIDTH, 0)

	var sp_vbox := VBoxContainer.new()
	sp_vbox.add_theme_constant_override("separation", 4)
	_squad_panel.add_child(sp_vbox)

	var sp_title := Label.new()
	sp_title.text = tr("SQUAD_HEADER")
	sp_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sp_title.add_theme_font_size_override("font_size", 11)
	sp_title.add_theme_color_override("font_color", ThemeColors.SQUAD_TITLE)
	sp_vbox.add_child(sp_title)

	# 状态区（每帧重新生成 bbcode）
	_squad_status_label = RichTextLabel.new()
	_squad_status_label.bbcode_enabled = true
	_squad_status_label.fit_content = true
	_squad_status_label.scroll_active = false
	_squad_status_label.custom_minimum_size = Vector2(SQUAD_PANEL_WIDTH - 22, 0)
	_squad_status_label.add_theme_font_size_override("normal_font_size", 11)
	_squad_status_label.add_theme_font_size_override("bold_font_size", 11)
	_squad_status_label.add_theme_color_override("default_color", Color(0.82, 0.9, 0.85))
	sp_vbox.add_child(_squad_status_label)

	# 分隔线
	var sep := ColorRect.new()
	sep.color = ThemeColors.SQUAD_SEPARATOR
	sep.custom_minimum_size = Vector2(0, 1)
	sp_vbox.add_child(sep)

	# 指令按钮
	# 阵型按钮已废弃（spec squad-cohesion：战术=阵型，由「交战模式」决定阵型，不再手动切）
	_btn_squad_engage = _create_tac_button(tr("SQUAD_ENGAGE_FMT") % tr("SQUAD_ENGAGE_FREE"))
	_btn_squad_engage.pressed.connect(_on_squad_engage_pressed)
	sp_vbox.add_child(_btn_squad_engage)

	_btn_squad_weapon = _create_tac_button(tr("SQUAD_WEAPON_FMT") % tr("WEAPON_PREF_MISSILE"))
	_btn_squad_weapon.pressed.connect(_on_squad_weapon_pressed)
	sp_vbox.add_child(_btn_squad_weapon)

	_add_ui_child(_squad_panel)

# ══════════════════════════════════════════════
#  BOSS 小队状态面板
# ══════════════════════════════════════════════

var _boss_card_labels: Array[RichTextLabel] = []  ## 每架飞机一个卡片标签
var _boss_title_label: Label

func _build_boss_panel() -> void:
	_boss_panel = PanelContainer.new()
	_boss_panel.visible = false
	var bp_style := StyleBoxFlat.new()
	bp_style.bg_color = ThemeColors.BOSS_PANEL_BG
	bp_style.border_color = ThemeColors.BOSS_PANEL_BORDER
	bp_style.set_border_width_all(1)
	bp_style.set_corner_radius_all(3)
	bp_style.content_margin_left = 8
	bp_style.content_margin_right = 8
	bp_style.content_margin_top = 4
	bp_style.content_margin_bottom = 4
	_boss_panel.add_theme_stylebox_override("panel", bp_style)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 12)
	_boss_panel.add_child(hbox)

	# 标题（由 _update_boss_panel 动态设置为 boss.display_name）
	_boss_title_label = Label.new()
	_boss_title_label.text = "BOSS"
	_boss_title_label.add_theme_font_size_override("font_size", 11)
	_boss_title_label.add_theme_color_override("font_color", ThemeColors.BOSS_TITLE)
	hbox.add_child(_boss_title_label)

	# 5 个卡片槽位（CSG BOSS：CV 旗舰 + 最多 4 架 F-14 Poltergeist）
	_boss_card_labels.clear()
	for i in range(5):
		var card := RichTextLabel.new()
		card.bbcode_enabled = true
		card.fit_content = true
		card.scroll_active = false
		card.custom_minimum_size = Vector2(130, 0)
		card.add_theme_font_size_override("normal_font_size", 10)
		card.add_theme_font_size_override("bold_font_size", 10)
		card.add_theme_color_override("default_color", Color(0.9, 0.82, 0.8))
		hbox.add_child(card)
		_boss_card_labels.append(card)

	_add_ui_child(_boss_panel)

# ══════════════════════════════════════════════
#  王牌中队交战血条（spec ace-squadron-tier §2.8：分段命条）
#  入场不亮（入场信号=无线电三件套）；首次开火/受击后由事件层翻 _battle_joined 才亮。
#  段=编成机数、一段一架（段位绑 squad 槽位，0 号段=长机、带顶边三角色标）；
#  非 BOSS 王牌一发死 → 命条即存活数条。BOSS 条优先：同屏时本条隐藏。
# ══════════════════════════════════════════════

var _ace_panel: PanelContainer
var _ace_title_label: Label
var _ace_emblem: AceEmblemIcon
var _ace_seg_box: HBoxContainer
var _ace_segments: Array[Panel] = []

const ACE_SEG_W := 26.0
const ACE_SEG_H := 9.0
const ACE_SEG_DEAD := Color(0.22, 0.20, 0.22)

func _build_ace_panel() -> void:
	_ace_panel = PanelContainer.new()
	_ace_panel.visible = false
	var style := StyleBoxFlat.new()
	style.bg_color = ThemeColors.BOSS_PANEL_BG
	style.border_color = ThemeColors.BOSS_PANEL_BORDER
	style.set_border_width_all(1)
	style.set_corner_radius_all(3)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 3
	style.content_margin_bottom = 5
	_ace_panel.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 2)
	_ace_panel.add_child(vbox)

	# 代号行（徽章小图 + 代号，颜色随中队主色，_update 时设）
	var title_row := HBoxContainer.new()
	title_row.alignment = BoxContainer.ALIGNMENT_CENTER
	title_row.add_theme_constant_override("separation", 6)
	vbox.add_child(title_row)
	_ace_emblem = AceEmblemIcon.new("", Color.WHITE, 7.0)
	_ace_emblem.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	title_row.add_child(_ace_emblem)
	_ace_title_label = Label.new()
	_ace_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_ace_title_label.add_theme_font_size_override("font_size", 11)
	title_row.add_child(_ace_title_label)

	# 分段条（段数随编成 2~8 变化，_update 时按需重建）
	_ace_seg_box = HBoxContainer.new()
	_ace_seg_box.add_theme_constant_override("separation", 3)
	_ace_seg_box.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(_ace_seg_box)

	_add_ui_child(_ace_panel)

func _update_ace_panel() -> void:
	if _ace_panel == null:
		return
	var info: Dictionary = AceReinforcementEvent.battle_bar_info()
	# BOSS 条优先（同屏窗口极小：BOSS 阶段王牌已撤离）
	if info.is_empty() or (_boss_panel and _boss_panel.visible):
		_ace_panel.visible = false
		return
	_ace_panel.visible = true
	var alive: Array = info.get("alive", [])
	var col: Color = info.get("color", Color(1.0, 0.3, 0.3))
	_ace_title_label.text = String(info.get("codename", ""))
	_ace_title_label.add_theme_color_override("font_color", col.lightened(0.25))
	_ace_emblem.set_emblem(String(info.get("id", "")), col.lightened(0.15))
	# 段数变化（换队/首建）→ 重建
	if _ace_segments.size() != alive.size():
		for seg in _ace_segments:
			seg.queue_free()
		_ace_segments.clear()
		for i in range(alive.size()):
			var seg := Panel.new()
			seg.custom_minimum_size = Vector2(ACE_SEG_W, ACE_SEG_H)
			_ace_seg_box.add_child(seg)
			_ace_segments.append(seg)
	# 段状态：存活=主色 / 阵亡=暗；0 号段（长机）顶边亮色描边作三角位标
	for i in range(_ace_segments.size()):
		var sb := StyleBoxFlat.new()
		sb.bg_color = col if bool(alive[i]) else ACE_SEG_DEAD
		sb.set_corner_radius_all(1)
		if i == 0:
			sb.border_width_top = 2
			sb.border_color = col.lightened(0.55) if bool(alive[i]) else Color(0.45, 0.42, 0.45)
		_ace_segments[i].add_theme_stylebox_override("panel", sb)

func _update_boss_panel() -> void:
	if _boss_panel == null:
		return
	if not game_scene or not game_scene._spawner:
		_boss_panel.visible = false
		return
	var boss: BossEncounter = game_scene._spawner.get_boss()
	if boss == null or not boss.active or not boss.hud_visible:
		_boss_panel.visible = false
		return

	var all_members: Array = boss.get_display_members()
	if all_members.is_empty():
		_boss_panel.visible = false
		return
	_boss_panel.visible = true
	if _boss_title_label:
		_boss_title_label.text = boss.display_name
	var members := all_members
	var prefix: String = boss.callsign_prefix if boss.callsign_prefix != "" else "BOSS"

	for i in range(_boss_card_labels.size()):
		var card: RichTextLabel = _boss_card_labels[i]
		if i >= members.size():
			card.text = ""
			continue
		var raw: Variant = members[i]
		if not is_instance_valid(raw):
			card.text = "[color=#444444][b]%s-%02d[/b] DOWN\n░░░░░░░░[/color]" % [prefix, i + 1]
			continue
		# 舰船（NavalUnit）走独立分支：HP 用 hull_hp / hull_hp_max
		if raw is NavalUnit:
			card.text = _format_boss_ship_card(raw as NavalUnit)
			continue
		# 飞机
		card.text = _format_boss_aircraft_card(raw as Aircraft)

## 舰船（CV 旗舰等）HUD 卡片格式化
func _format_boss_ship_card(ship: NavalUnit) -> String:
	var name: String = ship.full_name if ship.full_name != "" else ship.ship_class_label
	if ship.is_destroyed:
		return "[color=#444444][b]%s[/b] SUNK\n░░░░░░░░[/color]" % name
	var max_hp: float = maxf(ship.hull_hp_max, 1.0)
	var hp_ratio: float = clampf(ship.hull_hp / max_hp, 0.0, 1.0)
	var hp_color: String = "ff4444" if hp_ratio <= 0.3 else ("ffcc44" if hp_ratio <= 0.6 else "44ff44")
	var bar_len := 8
	var filled := int(round(hp_ratio * bar_len))
	var bar := ""
	for c in range(bar_len):
		bar += "█" if c < filled else "░"
	return "[b]%s[/b] [color=#ffaa55]FLAG[/color]\n[color=#%s]%s[/color] [color=#%s]%d/%d[/color]" % [
		name, hp_color, bar, hp_color, int(ship.hull_hp), int(max_hp)]

## 飞机（F-14 Poltergeist / F-47 Wraith）HUD 卡片格式化
func _format_boss_aircraft_card(ac: Aircraft) -> String:
	var max_hp: float = ac.params.max_hp if ac.params else 70.0
	if ac.is_destroyed:
		return "[color=#444444][b]%s[/b] DOWN\n░░░░░░░░ 0/%d[/color]" % [ac.callsign, int(max_hp)]
	var hp_ratio: float = clampf(ac.hp / maxf(max_hp, 0.01), 0.0, 1.0)
	var status_text: String
	var status_color: String
	if ac.is_cloaked:
		status_text = "CLOAK"
		status_color = "aa88ff"
	else:
		var ai := _get_ai(ac)
		status_text = _boss_action_text(ac, ai) if ai else "---"
		status_color = "e8a86a"
	var hp_color: String = "ff4444" if hp_ratio <= 0.3 else ("ffcc44" if hp_ratio <= 0.6 else "44ff44")
	var bar_len := 8
	var filled := int(round(hp_ratio * bar_len))
	var bar := ""
	for c in range(bar_len):
		bar += "█" if c < filled else "░"
	return "[b]%s[/b] [color=#%s]%s[/color]\n[color=#%s]%s[/color] [color=#%s]%d/%d[/color]" % [
		ac.callsign, status_color, status_text,
		hp_color, bar, hp_color, int(ac.hp), int(max_hp)]

## BOSS 成员的动作文本
func _boss_action_text(ac: Aircraft, ai: AIController) -> String:
	var hm: HerbstManeuver = ac.get_herbst()
	if hm and hm.is_active:
		return "J-TURN"
	if hm and hm.counterattack_timer > 0.0:
		return "COUNTER"
	if ai.is_evading():  # Phase 2：EVADE 是 modifier，不在 _state 轴
		return "EVADE"
	match ai._state:
		AIController.AIState.ENGAGE:
			# 王牌角色标签。只显示【行为】而不是角色代号（KNIGHT/SNIPER 是内部设计词汇，
			# 与 Gladiator/Lancer 等 AI 原型同类，不对玩家暴露）
			match AceSquad.role_of(ac):
				AceSquad.AceRole.KNIGHT:
					return "CLOSE"
				AceSquad.AceRole.SNIPER:
					return "STRIKE"
			return "ENGAGE"
		AIController.AIState.PATROL:
			return "RETURN"
		_:
			return "---"

## 返回玩家所在的小队（以玩家为长机的那个 Squad）
func _get_player_squad() -> Squad:
	if not game_scene or not game_scene.player_aircraft:
		return null
	# game_scene 在生存模式下一定是 survivor_mode 且拥有 _spawner 成员（刷怪系统委托）
	if not game_scene._spawner:
		return null
	var squads = game_scene._spawner.get_squads()
	if squads == null:
		return null
	for sq in squads:
		if sq and sq.leader == game_scene.player_aircraft:
			return sq
	return null

## 返回玩家当前活着的僚机列表
func _get_wingmen() -> Array:
	var result: Array = []
	var sq := _get_player_squad()
	if sq == null:
		return result
	for member in sq.members:
		if member != sq.leader and is_instance_valid(member) and not member.is_destroyed:
			result.append(member)
	return result

## 读某架飞机上的 AIController
func _get_ai(ac: Aircraft) -> AIController:
	if not ac:
		return null
	for child in ac.get_children():
		if child is AIController:
			return child
	return null

## 把 AI 当前状态/战术翻译成动作名（已 tr() 翻译）
## 僚机武器状态（导弹 / 机炮 / 热诱弹）—— 含装填进度、冷却剩余秒数。
## 复用玩家 HUD 的色彩 / 标签约定，单行紧凑（squad panel 宽度有限）：
##   MSL 2/2 / MSL ↻80% / MSL 2 (CD 80%)
##   GUN 250 / GUN ↻80%
##   FLR 6 / FLR ↻45% / FLR (cd 比例)
func _wingman_weapon_status(ac: Aircraft) -> String:
	var parts: Array[String] = []

	# ── 导弹 ──
	if ac.params and ac.params.missile:
		var max_msl: int = ac.params.missile.max_count
		if ac._missile_reload_active:
			var pct := int(ac.missile_reload_progress * 100)
			parts.append("[color=#5599ff]MSL ↻%d%%[/color]" % pct)
		elif ac._missile_cooldown > 0.1:
			var max_cd: float = ac.params.missile.cooldown
			var pct_cd: int = int(clampf(ac._missile_cooldown / max_cd, 0.0, 1.0) * 100) if max_cd > 0.0 else 0
			parts.append("[color=#88bbff]MSL %d (CD %d%%)[/color]" % [ac.missiles_remaining, pct_cd])
		else:
			var col := "88bbff" if ac.missiles_remaining > 0 else "666666"
			parts.append("[color=#%s]MSL %d/%d[/color]" % [col, ac.missiles_remaining, max_msl])

	# ── 机炮 ──
	if ac.params and ac.params.gun:
		if ac.enable_gun_reload and ac._gun_reload_active:
			var pct := int(ac.gun_reload_progress * 100)
			parts.append("[color=#aa7733]GUN ↻%d%%[/color]" % pct)
		else:
			var col := "ccddaa" if ac.ammo > 100 else ("ffaa44" if ac.ammo > 0 else "666666")
			parts.append("[color=#%s]GUN %d[/color]" % [col, ac.ammo])

	# ── 热诱弹 ──
	if ac.params and ac.params.flare:
		if ac.enable_flare_reload and ac.flares_remaining <= 0 and ac.flare_reload_progress > 0.01:
			var pct := int(ac.flare_reload_progress * 100)
			parts.append("[color=#aa8833]FLR ↻%d%%[/color]" % pct)
		else:
			var cd_ratio := ac.get_flare_cooldown_ratio()
			var col := "ffdd66"
			if cd_ratio > 0.01:
				col = "aa8833"
			elif ac.flares_remaining <= 0:
				col = "666666"
			parts.append("[color=#%s]FLR %d[/color]" % [col, ac.flares_remaining])

	return "  ".join(parts)

func _wingman_action_text(ac: Aircraft) -> String:
	var ai := _get_ai(ac)
	if ai == null:
		return tr("ACTION_UNKNOWN")
	if ac.evasion_mode:
		return tr("ACTION_EVADING")
	if ai.is_evading():  # Phase 2：EVADE 是 modifier，不在 _state 轴
		return tr("ACTION_MISSILE_EVADE")
	match ai._state:
		AIController.AIState.PATROL:
			return tr("ACTION_PATROL")
		AIController.AIState.ENGAGE:
			if ai.current_tactic_name != "":
				return tr(ai.current_tactic_name)
			return tr("ACTION_ENGAGE")
		AIController.AIState.SQUAD_FOLLOW:
			if ai.current_tactic_name != "":
				return tr(ai.current_tactic_name)
			return tr("ACTION_FORMATION")
	return tr("ACTION_UNKNOWN")

## 每帧刷新玩家仪表上方的僚机信息行；一架存活僚机严格对应一行。
func _update_squad_panel() -> void:
	if _squad_panel == null or _wingman_instrument == null:
		return
	_squad_panel.visible = false
	var wingmen := _get_wingmen()
	if wingmen.is_empty():
		_wingman_instrument.update_display([])
		return
	var sq := _get_player_squad()
	if sq == null:
		_wingman_instrument.update_display([])
		return

	# 继任者标记（spec ace-system §3）：击坠数最高的僚机 = 王牌阵亡时的继任者，标 ★
	var heir: Aircraft = null
	for wm0 in wingmen:
		if heir == null or (wm0 as Aircraft).kill_tally > heir.kill_tally:
			heir = wm0
	if heir and heir.kill_tally <= 0:
		heir = null  # 零杀不标（无有意义的继任排序）

	var rows: Array[Dictionary] = []
	for wm_raw: Variant in wingmen:
		var wm := wm_raw as Aircraft
		if wm == null or not is_instance_valid(wm):
			continue
		var max_hp := ceili(wm.params.max_hp) if wm.params else ceili(wm.hp)
		var has_msl := wm.params != null and wm.params.missile != null
		var has_gun := wm.params != null and wm.params.gun != null
		var has_flr := wm.params != null and wm.params.flare != null
		var msl_busy := has_msl and wm._missile_reload_active
		var gun_busy := has_gun and wm.enable_gun_reload and wm._gun_reload_active
		var flr_busy := has_flr and wm.enable_flare_reload and wm.flares_remaining <= 0 \
			and wm.flare_reload_progress > 0.01
		var msl_text := ""
		if has_msl:
			msl_text = "%d%%" % int(wm.missile_reload_progress * 100.0) if msl_busy \
				else "%d/%d" % [wm.missiles_remaining, wm.params.missile.max_count]
		var gun_text := ""
		if has_gun:
			gun_text = "%d%%" % int(wm.gun_reload_progress * 100.0) if gun_busy else str(wm.ammo)
		var flr_text := ""
		if has_flr:
			flr_text = "%d%%" % int(wm.flare_reload_progress * 100.0) if flr_busy \
				else str(wm.flares_remaining)
		rows.append({
			"slot": wm.squad_slot,
			"callsign": wm.callsign,
			"is_heir": wm == heir,
			"kills": wm.kill_tally,
			"hp": "%d/%d" % [ceili(wm.hp), max_hp],
			"action": _wingman_action_text(wm),
			"has_msl": has_msl,
			"msl": msl_text,
			"msl_busy": msl_busy,
			"has_gun": has_gun,
			"gun": gun_text,
			"gun_busy": gun_busy,
			"has_flr": has_flr,
			"flr": flr_text,
			"flr_busy": flr_busy,
		})
	_wingman_instrument.update_display(rows)
	if _player_instrument:
		var vp := hud_viewport_size()
		_wingman_instrument.position = Vector2(
			vp.x - _wingman_instrument.size.x,
			vp.y - PLAYER_HUD_BOTTOM_MARGIN - _player_instrument.size.y
				- _wingman_instrument.size.y
		)

	# C/V 键盘入口仍沿用既有状态；旧鼠标按钮节点仅保留兼容，不再显示。
	_btn_squad_engage.text = tr("SQUAD_ENGAGE_FMT") % _squad_engage_mode_label()
	_btn_squad_weapon.text = tr("SQUAD_WEAPON_FMT") % (tr("WEAPON_PREF_MISSILE") if _squad_weapon_pref == Aircraft.WeaponPreference.PREFER_MISSILE else tr("WEAPON_PREF_GUN"))

## 交战模式标签（三态：自由交战 / 跟随长机 / 守护后方）
func _squad_engage_mode_label() -> String:
	match _squad_engage_mode:
		AIController.SquadEngageMode.FREE:
			return tr("SQUAD_ENGAGE_FREE")
		AIController.SquadEngageMode.GUARD_REAR:
			return tr("SQUAD_ENGAGE_GUARD")
		_:
			return tr("SQUAD_ENGAGE_FOLLOW")

func _on_squad_engage_pressed() -> void:
	# 三态循环：自由(0) → 跟随长机(1) → 守护后方(2) → 自由
	_squad_engage_mode = (_squad_engage_mode + 1) % 3
	# 战术=阵型：切模式同时把小队阵型设成绑定的那个（自由→展开 / 跟随→指尖四点 / 守后→楔形）
	var sq := _get_player_squad()
	if sq:
		sq.formation = Squad.formation_for_engage_mode(_squad_engage_mode)
	for wm in _get_wingmen():
		var ai := _get_ai(wm)
		if ai == null:
			continue
		ai.squad_engage_mode = _squad_engage_mode
		# 若僚机正在交战，强制脱离并回到编队，保证"切模式=立刻生效"
		# （玩家 UI 强制脱战 → release_target(TS_COMMANDED)，最高优先级必然放行）
		if ai._state == AIController.AIState.ENGAGE:
			if ai.release_target(AIController.TargetSource.TS_COMMANDED, "engage mode switch"):
				# 直接落位完整编队托管（target_position=INF 留给下一帧 squad_coordination 填）
				wm.set_formation_target(game_scene.player_aircraft, Vector2.INF)
				ai.enter_squad_follow_state(true)  # snap：跳过 rejoin 渐变直接落位
				ai._squad_attacking_leader_target = false
				ai._squad_lateral_role = AIController.SquadRole.NONE
				ai._engage_timer = 0.0
				ai._cooldown_timer = 0.0
				ai.current_tactic_name = ""
	var mode_str: String = ["FREE", "FOLLOW_LEADER", "GUARD_REAR"][_squad_engage_mode]
	EventLogger.log_event("SQUAD_CMD", "Player", "engage mode → %s" % mode_str)

## 切换武器偏好（导弹优先 ↔ 机炮优先）
func _on_squad_weapon_pressed() -> void:
	if _squad_weapon_pref == Aircraft.WeaponPreference.PREFER_MISSILE:
		_squad_weapon_pref = Aircraft.WeaponPreference.PREFER_GUN
	else:
		_squad_weapon_pref = Aircraft.WeaponPreference.PREFER_MISSILE
	for wm in _get_wingmen():
		wm.weapon_preference = _squad_weapon_pref
	EventLogger.log_event("SQUAD_CMD", "Player",
		"wingman weapon pref → %s" % ("MISSILE" if _squad_weapon_pref == Aircraft.WeaponPreference.PREFER_MISSILE else "GUN"))

func _update_debug_panel() -> void:
	if not game_scene:
		return
	var fps := Engine.get_frames_per_second()
	var frame_time := 1000.0 / maxf(fps, 1.0)
	var node_count := _count_nodes(get_tree().root)
	var enemy_count := 0
	var aircraft_count := 0
	var missile_count := 0
	for child in game_scene.get_children():
		if child is Aircraft:
			aircraft_count += 1
			if child.team == CombatUnit.TEAM_HOSTILE and not child.is_destroyed:
				enemy_count += 1
	if game_scene.missile_manager:
		missile_count = game_scene.missile_manager.get_child_count()
	var mem := OS.get_static_memory_usage() / 1048576.0

	var text := "FPS: %d (%.1f ms)\n" % [fps, frame_time]
	text += "Enemies: %d\n" % enemy_count
	text += "Aircraft: %d\n" % aircraft_count
	text += "Missiles: %d\n" % missile_count
	text += "Nodes: %d\n" % node_count
	text += "Memory: %.1f MB" % mem
	# Perf 桶（PerfBuckets autoload 喂数据）：units 分类 / AI 拥挤度 / 各热区 µs/帧
	# 用来定位 CSG BOSS 等高压场景的掉帧根因（MountTarget 是否撑大 all_units，
	# 进而拉升 ai.crowd_t、把 AI 全员推到降频路径上去）
	for line in PerfBuckets.format_hud_lines():
		text += "\n" + line
	_debug_label.text = text

func _count_nodes(node: Node) -> int:
	var count := 1
	for child in node.get_children():
		count += _count_nodes(child)
	return count

## ── 经验表现层公开入口（spawner / survivor_mode 调用）──

## 击杀掉落经验：在底部经验条上生成"+N"沉入效果（落点固定在条上，纯表现）。
func spawn_xp_gain(amount: int) -> void:
	if _xp_vfx:
		_xp_vfx.add_gain(amount)

## 升级表现：等级板、经验条、经验数字从左到右各反色一次，不再生成底部弹字。
func show_level_up(_level: int) -> void:
	if _bottom_experience_panel:
		_bottom_experience_panel.update_display(survivor_player)
		_bottom_experience_panel.flash_level_up()

func show_game_over(level: int, time: float, kills: int,
		xp_gained: int = 0, merit_earned: int = 0) -> void:
	var mins := int(time) / 60
	var secs := int(time) % 60
	var text := "[center][color=#ff6655][b]%s[/b][/color]\n\n" % tr("HUD_GAMEOVER_TITLE")
	text += "[color=#aaddaa]%s\n" % (tr("HUD_GAMEOVER_LEVEL_FMT") % level)
	text += "%s\n" % (tr("HUD_GAMEOVER_TIME_FMT") % [mins, secs])
	text += "%s[/color]\n\n" % (tr("HUD_GAMEOVER_KILLS_FMT") % kills)
	text += _format_merit_line(xp_gained, merit_earned)
	text += "[color=#888888]%s[/color][/center]" % tr("HUD_GAMEOVER_HINT")
	_game_over_label.text = text
	_game_over_panel.visible = true

## boss_id 决定副标题里的 BOSS 名（空 / 未注册 id → 通用文案，沙盒与老调用方安全）
func show_victory(level: int, time: float, kills: int,
		xp_gained: int = 0, merit_earned: int = 0, boss_id: String = "") -> void:
	var mins := int(time) / 60
	var secs := int(time) % 60
	var name_key := BossRegistry.name_key_for(boss_id)
	var subtitle := tr("HUD_VICTORY_SUBTITLE_GENERIC") if name_key.is_empty() \
		else tr("HUD_VICTORY_SUBTITLE_FMT") % tr(name_key)
	var text := "[center][color=#55ffaa][b]%s[/b][/color]\n\n" % tr("HUD_VICTORY_TITLE")
	text += "[color=#ddffee]%s[/color]\n\n" % subtitle
	text += "[color=#aaddaa]%s\n" % (tr("HUD_GAMEOVER_LEVEL_FMT") % level)
	text += "%s\n" % (tr("HUD_GAMEOVER_TIME_FMT") % [mins, secs])
	text += "%s[/color]\n\n" % (tr("HUD_GAMEOVER_KILLS_FMT") % kills)
	text += _format_merit_line(xp_gained, merit_earned)
	text += "[color=#888888]%s[/color][/center]" % tr("HUD_GAMEOVER_HINT")
	_game_over_label.text = text
	_game_over_panel.visible = true

## 结算面板里的"功勋 +N"行（XP=0 时返回空串，沙盒/老调用方安全）
func _format_merit_line(xp_gained: int, merit_earned: int) -> String:
	if xp_gained <= 0 and merit_earned <= 0:
		return ""
	var line := "[color=#e8c75c]%s[/color]\n" % (tr("HUD_GAMEOVER_MERIT_FMT") % merit_earned)
	line += "[color=#7a6b3a]%s[/color]\n\n" % (tr("HUD_GAMEOVER_MERIT_DETAIL_FMT") % [xp_gained, MeritLedger.get_total()])
	return line

# ══════════════════════════════════════════════
#  雷达小地图
# ══════════════════════════════════════════════

class RadarDisplay extends Control:
	var hud: SurvivorHUD

	const RADAR_RADIUS := 80.0        ## 雷达圆半径（像素）
	const RADAR_MARGIN := 20.0        ## 距屏幕左下角边距
	const RADAR_RANGE := 5000.0       ## 雷达显示的世界范围（像素）
	const SWEEP_SPEED := 2.5          ## 扫描线旋转速度（rad/s）
	const RING_COUNT := 3             ## 同心圆数量
	const BG_COLOR := ThemeColors.RADAR_BG
	const RING_COLOR := ThemeColors.RADAR_RING
	const SWEEP_COLOR := ThemeColors.RADAR_SWEEP
	const PLAYER_COLOR := ThemeColors.RADAR_PLAYER
	const ENEMY_COLOR := ThemeColors.RADAR_ENEMY
	const LOCKED_COLOR := ThemeColors.RADAR_LOCKED
	const MISSILE_WARNING_COLOR := ThemeColors.RADAR_MISSILE

	var _sweep_angle: float = 0.0
	var _blip_ages: Dictionary = {}  ## { Aircraft instance_id : float } 扫描到的时间

	func _ready() -> void:
		mouse_filter = MOUSE_FILTER_IGNORE

	func _process(delta: float) -> void:
		_sweep_angle += SWEEP_SPEED * delta
		if _sweep_angle > TAU:
			_sweep_angle -= TAU

		# 衰减 blip 亮度
		var keys_to_remove: Array = []
		for key in _blip_ages:
			_blip_ages[key] += delta
			if float(_blip_ages[key]) > 4.0:
				keys_to_remove.append(key)
		for key in keys_to_remove:
			_blip_ages.erase(key)

		queue_redraw()

	func _draw() -> void:
		if not hud or not hud.game_scene or not hud.survivor_player:
			return
		var player_ac: Aircraft = hud._safe_player_aircraft()
		if not player_ac or player_ac.is_destroyed:
			return

		var vp := hud.hud_viewport_size()
		var center := Vector2(RADAR_MARGIN + RADAR_RADIUS, vp.y - RADAR_MARGIN - RADAR_RADIUS - 50)

		# 背景圆
		draw_circle(center, RADAR_RADIUS, BG_COLOR)

		# 同心圆
		for i in range(1, RING_COUNT + 1):
			var r := RADAR_RADIUS * float(i) / float(RING_COUNT)
			draw_arc(center, r, 0, TAU, 64, RING_COLOR, 1.0)

		# 十字线
		draw_line(center - Vector2(RADAR_RADIUS, 0), center + Vector2(RADAR_RADIUS, 0), RING_COLOR, 1.0)
		draw_line(center - Vector2(0, RADAR_RADIUS), center + Vector2(0, RADAR_RADIUS), RING_COLOR, 1.0)

		# 扫描线 + 尾迹
		var sweep_world := _sweep_angle
		var sweep_end := center + Vector2(cos(sweep_world - PI / 2.0), sin(sweep_world - PI / 2.0)) * RADAR_RADIUS
		draw_line(center, sweep_end, SWEEP_COLOR, 1.5)

		# 扫描尾迹
		var trail_steps := 15
		for i in range(trail_steps):
			var t := float(i) / float(trail_steps)
			var a := sweep_world - t * 0.6
			var trail_end := center + Vector2(cos(a - PI / 2.0), sin(a - PI / 2.0)) * RADAR_RADIUS
			var alpha := 0.25 * (1.0 - t)
			draw_line(center, trail_end, Color(0.2, 0.7, 0.2, alpha), 1.0)

		# 更新 blip 并绘制战斗单位（飞机 + 地面）
		var player_pos := player_ac.global_position
		const TGT_COLOR := Color(1.0, 0.85, 0.2, 1.0)  ## TGT 任务目标专用黄色（与战术地图一致）

		for unit in CombatUnit.all_units:
			if not is_instance_valid(unit) or unit == player_ac or unit.is_destroyed:
				continue

			var rel := unit.global_position - player_pos
			var dist := rel.length()
			if dist > RADAR_RANGE:
				continue

			# 旋转到玩家航向为上的坐标系
			var angle := atan2(rel.x, -rel.y)
			var radar_dist := (dist / RADAR_RANGE) * RADAR_RADIUS
			var blip_pos := center + Vector2(sin(angle), -cos(angle)) * radar_dist

			# 检查是否被扫描线扫过（角度接近）
			var blip_angle := fmod(angle + TAU, TAU)
			var sweep_norm := fmod(_sweep_angle + TAU, TAU)
			var angle_diff := fmod(sweep_norm - blip_angle + TAU, TAU)
			if angle_diff < 0.3:
				_blip_ages[unit.get_instance_id()] = 0.0

			# TGT 任务目标：提前标注，不依赖扫描线，永远可见
			var is_tgt: bool = unit.is_mission_target
			var age: float = _blip_ages.get(unit.get_instance_id(), 99.0)
			if not is_tgt and age > 3.5:
				continue  # 非 TGT 且太久没扫到，不显示

			var fade: float = 1.0 if is_tgt else clampf(1.0 - age / 3.5, 0.0, 1.0)

			# 颜色：TGT=黄色（优先级最高），锁定=黄色，友方=蓝色，普通敌=红色
			var blip_color: Color
			if is_tgt and unit.team != 0:
				blip_color = TGT_COLOR
			elif unit.team == 0:
				blip_color = PLAYER_COLOR
			elif unit.team == 2:
				blip_color = GameConstants.COL_FRIEND_ALLY   # 第三方友军（FactionPalette）
			elif unit is Aircraft and player_ac.combat_target == unit:
				blip_color = LOCKED_COLOR
			else:
				blip_color = ENEMY_COLOR

			blip_color.a *= fade

			# TGT 用方括号外框 + 中心小点，一眼和普通点区分开
			if is_tgt and unit.team != 0:
				draw_circle(blip_pos, 2.0, blip_color)
				var bd := 5.0
				var bl := 2.0  ## 括号短边长
				var thick := 1.5
				var tl := blip_pos + Vector2(-bd, -bd)
				var tr_p := blip_pos + Vector2(bd, -bd)
				var bl_p := blip_pos + Vector2(-bd, bd)
				var br_p := blip_pos + Vector2(bd, bd)
				draw_line(tl, tl + Vector2(bl, 0), blip_color, thick)
				draw_line(tl, tl + Vector2(0, bl), blip_color, thick)
				draw_line(tr_p, tr_p + Vector2(-bl, 0), blip_color, thick)
				draw_line(tr_p, tr_p + Vector2(0, bl), blip_color, thick)
				draw_line(bl_p, bl_p + Vector2(bl, 0), blip_color, thick)
				draw_line(bl_p, bl_p + Vector2(0, -bl), blip_color, thick)
				draw_line(br_p, br_p + Vector2(-bl, 0), blip_color, thick)
				draw_line(br_p, br_p + Vector2(0, -bl), blip_color, thick)
			else:
				draw_circle(blip_pos, 2.5, blip_color)
				# 锁定目标加方框
				if unit is Aircraft and player_ac.combat_target == unit:
					var d := 5.0
					draw_rect(Rect2(blip_pos - Vector2(d, d), Vector2(d * 2, d * 2)), Color(blip_color, fade * 0.5), false, 1.0)

		# 玩家标记（中心，始终朝上的小三角）
		var p_size := 4.0
		var p_verts := PackedVector2Array([
			center + Vector2(0, -p_size),
			center + Vector2(p_size * 0.7, p_size * 0.5),
			center + Vector2(-p_size * 0.7, p_size * 0.5),
		])
		draw_colored_polygon(p_verts, PLAYER_COLOR)

		# 来袭导弹警告
		var has_incoming := false
		var warning_pulse: float = lerpf(0.65, 1.0, absf(sin(hud.game_time * TAU * 3.3)))
		var missile_mgr = hud.game_scene.get_node_or_null("MissileManager")
		if missile_mgr:
			for child in missile_mgr.get_children():
				if not child is Missile:
					continue
				var m: Missile = child
				# 与世界警告共用 Missile 的唯一来袭判定；VLS 预末段按目标分配保留警告。
				if not m.is_incoming_warning_for(player_ac):
					continue
				var rel_m := m.global_position - player_pos
				has_incoming = true
				var dist_m := rel_m.length()
				if dist_m > RADAR_RANGE:
					continue
				var angle_m := atan2(rel_m.x, -rel_m.y)
				var radar_dist_m := (dist_m / RADAR_RANGE) * RADAR_RADIUS
				var msl_pos := center + Vector2(sin(angle_m), -cos(angle_m)) * radar_dist_m
				# 标记始终可见、只做亮度脉冲；旧版整段灭掉半周期，混战中容易看漏。
				var marker_color := Color(MISSILE_WARNING_COLOR, warning_pulse)
				draw_circle(msl_pos, 4.5, Color(marker_color, 0.18 * warning_pulse))
				var to_player := center - msl_pos
				var fwd := to_player.normalized() if to_player.length() > 0.1 else Vector2.UP
				var side := Vector2(-fwd.y, fwd.x)
				var bar_len := 10.0
				var bar_w := 1.5
				var tip := msl_pos + fwd * (bar_len * 0.5)
				var tail := msl_pos - fwd * (bar_len * 0.5)
				var bar := PackedVector2Array([
					tail + side * bar_w,
					tail - side * bar_w,
					tip - side * bar_w,
					tip + side * bar_w,
				])
				draw_colored_polygon(bar, marker_color)

		# "MISSILE" 文字警告
		if has_incoming:
			var warn_pos := Vector2(center.x, center.y - RADAR_RADIUS - 13)
			var font := ThemeDB.fallback_font
			var text := tr("HUD_MISSILE_WARNING")
			var font_size := 14
			var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
			var box := Rect2(
				Vector2(center.x - text_size.x * 0.5 - 6.0, warn_pos.y - font_size - 3.0),
				Vector2(text_size.x + 12.0, font_size + 8.0)
			)
			var hot: bool = fmod(hud.game_time * 4.0, 1.0) < 0.5
			var warn_color := Color(1.0, 0.28, 0.18, 1.0) if hot else Color(1.0, 0.85, 0.2, 1.0)
			draw_rect(box, Color(0.18, 0.0, 0.0, 0.82))
			draw_rect(box, Color(warn_color, warning_pulse), false, 2.0)
			draw_string(font, warn_pos - Vector2(text_size.x * 0.5, 0), text,
				HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, warn_color)

		# 外圈边框
		draw_arc(center, RADAR_RADIUS, 0, TAU, 64, ThemeColors.RADAR_BORDER, 1.5)
		if has_incoming:
			draw_arc(center, RADAR_RADIUS + 3.0, 0, TAU, 64,
				Color(MISSILE_WARNING_COLOR, warning_pulse), 3.0, true)

# ══════════════════════════════════════════════
#  屏幕外威胁方位指示器
# ══════════════════════════════════════════════

class ThreatOverlay extends Control:
	var hud: SurvivorHUD

	const ARROW_SIZE := 12.0
	const EDGE_MARGIN := 30.0
	const THREAT_COLOR := ThemeColors.THREAT_ARROW
	const LOCK_COLOR := ThemeColors.LOCK_WARNING

	func _ready() -> void:
		set_anchors_and_offsets_preset(PRESET_FULL_RECT)
		mouse_filter = MOUSE_FILTER_IGNORE

	func _process(_delta: float) -> void:
		queue_redraw()

	func _draw() -> void:
		if not hud or not hud.game_scene or not hud.survivor_player:
			return
		var player_ac: Aircraft = hud._safe_player_aircraft()
		if not player_ac or player_ac.is_destroyed:
			return

		var scene: Node2D = hud.game_scene
		var camera: Camera2D = scene.get_node("Camera2D")
		if not camera:
			return

		var vp_size := hud.hud_viewport_size()
		var cam_pos := camera.global_position
		var zoom := camera.zoom
		var half_vp := vp_size / (2.0 * zoom)

		var screen_left := cam_pos.x - half_vp.x
		var screen_right := cam_pos.x + half_vp.x
		var screen_top := cam_pos.y - half_vp.y
		var screen_bottom := cam_pos.y + half_vp.y

		# 玩家自身离屏时在边缘显示蓝色方向指示（自由视野下定位自己）
		var ppos := player_ac.global_position
		if ppos.x < screen_left or ppos.x > screen_right or ppos.y < screen_top or ppos.y > screen_bottom:
			var pdir := (ppos - cam_pos).normalized()
			var pcenter := vp_size * 0.5
			var parrow_pos := _edge_intersect(pcenter, pdir, vp_size)
			_draw_threat_arrow(parrow_pos, pdir, ThemeColors.RADAR_PLAYER)

			var font := get_theme_default_font()
			var font_size := 12
			var line_h := 14.0
			# 距离：像素 → 米 → 公里（PIXELS_PER_METER = 0.5）
			var dist_km: float = (ppos - cam_pos).length() / (CombatUnit.PIXELS_PER_METER * 1000.0)
			var plane_name := ""
			if player_ac.params:
				plane_name = player_ac.params.display_name
			var lines := [
				player_ac.callsign,
				plane_name,
				"%.1f km" % dist_km,
			]
			# 以箭头朝屏幕内（-pdir）偏移，得到三行文字块的中心锚点
			var block_anchor := parrow_pos + (-pdir) * (ARROW_SIZE + 8.0 + line_h * 1.5)
			# 逐行水平居中绘制
			for i in range(lines.size()):
				var line: String = lines[i]
				var sz := font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
				var x: float = block_anchor.x - sz.x * 0.5
				var y: float = block_anchor.y + (i - 1) * line_h
				x = clamp(x, 6.0, vp_size.x - sz.x - 6.0)
				y = clamp(y, sz.y + 2.0, vp_size.y - 6.0)
				draw_string(font, Vector2(x, y), line, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, ThemeColors.RADAR_PLAYER)

			# 标记正上方系统提示：[ Space ] + 说明文字
			var key_label := "[ Space ]"
			var hint_text := tr("PLAYER_OFFSCREEN_HINT")
			var key_size := font.get_string_size(key_label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
			var hint_size := font.get_string_size(hint_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
			var gap := 8.0
			var total_w: float = key_size.x + gap + hint_size.x
			# 放在三行标签块上方再加一行间距
			var hint_cx: float = clamp(block_anchor.x, total_w * 0.5 + 6.0, vp_size.x - total_w * 0.5 - 6.0)
			var hint_cy: float = clamp(block_anchor.y - line_h * 2.0 - 4.0, key_size.y + 2.0, vp_size.y - 6.0)
			var hx: float = hint_cx - total_w * 0.5
			draw_string(font, Vector2(hx, hint_cy), key_label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, ThemeColors.RADAR_PLAYER)
			draw_string(font, Vector2(hx + key_size.x + gap, hint_cy), hint_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, ThemeColors.TEXT_MUTED)

		for child in scene.get_children():
			if not child is Aircraft:
				continue
			var ac: Aircraft = child
			if ac.team != CombatUnit.TEAM_HOSTILE or ac.is_destroyed:
				continue

			var is_threat := false
			if ac.combat_target == player_ac:
				is_threat = true
			if not is_threat:
				var lock_val: float = ac.radar_targets.get(player_ac, 0.0)
				if lock_val > 0.5:
					is_threat = true
			if not is_threat:
				continue

			var epos := ac.global_position
			if epos.x >= screen_left and epos.x <= screen_right and epos.y >= screen_top and epos.y <= screen_bottom:
				continue

			var dir := (epos - cam_pos).normalized()
			var screen_center := vp_size * 0.5
			var screen_dir := Vector2(dir.x, dir.y).normalized()
			var arrow_pos := _edge_intersect(screen_center, screen_dir, vp_size)

			var lock_progress: float = ac.radar_targets.get(player_ac, 0.0)
			var lock_time_val: float = ac.params.lock_time if ac.params else 3.0
			var color := LOCK_COLOR if lock_progress >= lock_time_val else THREAT_COLOR

			_draw_threat_arrow(arrow_pos, screen_dir, color)

	func _edge_intersect(center: Vector2, dir: Vector2, vp: Vector2) -> Vector2:
		var margin := EDGE_MARGIN
		var half := vp * 0.5 - Vector2(margin, margin)

		var t: float = 99999.0
		if abs(dir.x) > 0.001:
			var tx: float = half.x / abs(dir.x)
			t = minf(t, tx)
		if abs(dir.y) > 0.001:
			var ty: float = half.y / abs(dir.y)
			t = minf(t, ty)

		return center + dir * t

	func _draw_threat_arrow(pos: Vector2, dir: Vector2, color: Color) -> void:
		var s := ARROW_SIZE
		var tip := pos + dir * s
		var perp := Vector2(-dir.y, dir.x)
		var base_l := pos - dir * s * 0.5 + perp * s * 0.6
		var base_r := pos - dir * s * 0.5 - perp * s * 0.6

		var verts := PackedVector2Array([tip, base_l, base_r])
		draw_colored_polygon(verts, color)
		var outline := Color(color.r, color.g, color.b, color.a * 0.5)
		draw_line(tip, base_l, outline, 1.0)
		draw_line(base_l, base_r, outline, 1.0)
		draw_line(base_r, tip, outline, 1.0)
