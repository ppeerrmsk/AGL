class_name SurvivorHUD
extends CanvasLayer

## 生存模式 HUD：右下角状态面板 + 顶部时间/击杀 + 底部经验条

var survivor_player: SurvivorPlayer
var game_time: float = 0.0
var kill_count: int = 0
var game_scene: Node2D

# ── 顶部 ──
var _time_label: Label
var _kill_label: Label

# ── 底部经验条 ──
var _xp_bar_bg: ColorRect
var _xp_bar_fill: ColorRect
var _xp_label: Label

# ── 右下角状态面板 ──
var _status_panel: PanelContainer
var _status_label: RichTextLabel

# ── 右侧战术面板 ──
var _tactical_panel: PanelContainer
var _btn_weapon: Button
var _btn_altitude: Button
var _btn_evasion: Button
var _btn_auto_fire: Button
var _tooltip_panel: PanelContainer
var _tooltip_label: RichTextLabel
var _tooltip_key: String = ""  # 当前悬停的按钮标识

# ── 小队指挥面板（仅主角有僚机时显示）──
var _squad_panel: PanelContainer
var _squad_status_label: RichTextLabel
var _btn_squad_formation: Button
var _btn_squad_engage: Button
var _btn_squad_weapon: Button
## 小队交战模式：FREE=独立扫描+协同 / FOLLOW_LEADER=只打长机目标
var _squad_engage_mode: int = 0          # AIController.SquadEngageMode.FREE
var _squad_weapon_pref: int = 0          # 0 = 导弹优先, 1 = 机炮优先 (Aircraft.WeaponPreference)

# ── 雷达小地图 ──
var _radar: Control

# ── 其他 ──
var _game_over_panel: PanelContainer
var _game_over_label: RichTextLabel
var _threat_overlay: Control

# Debug 性能面板
var _debug_panel: PanelContainer
var _debug_label: Label
var _debug_visible: bool = false
var _debug_update_timer: float = 0.0

const XP_BAR_WIDTH := 400.0
const XP_BAR_HEIGHT := 20.0
const STATUS_PANEL_WIDTH := 220.0

func _ready() -> void:
	layer = 10
	_build_ui()

func _build_ui() -> void:
	# ── 时间（顶部中央）──
	_time_label = Label.new()
	_time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_time_label.add_theme_font_size_override("font_size", 18)
	_time_label.add_theme_color_override("font_color", Color(0.8, 0.9, 0.8))
	add_child(_time_label)

	# ── 击杀数（时间下方）──
	_kill_label = Label.new()
	_kill_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_kill_label.add_theme_font_size_override("font_size", 13)
	_kill_label.add_theme_color_override("font_color", Color(0.6, 0.7, 0.6, 0.7))
	add_child(_kill_label)

	# ── 经验条（底部中央）──
	_xp_bar_bg = ColorRect.new()
	_xp_bar_bg.color = Color(0.1, 0.1, 0.1, 0.7)
	_xp_bar_bg.size = Vector2(XP_BAR_WIDTH, XP_BAR_HEIGHT)
	add_child(_xp_bar_bg)

	_xp_bar_fill = ColorRect.new()
	_xp_bar_fill.color = Color(1.0, 0.8, 0.3)
	_xp_bar_fill.size = Vector2(0, XP_BAR_HEIGHT)
	add_child(_xp_bar_fill)

	_xp_label = Label.new()
	_xp_label.size = Vector2(XP_BAR_WIDTH, XP_BAR_HEIGHT)
	_xp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_xp_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_xp_label.add_theme_font_size_override("font_size", 12)
	_xp_label.add_theme_color_override("font_color", Color(1, 1, 1))
	add_child(_xp_label)

	# ── 右下角状态面板 ──
	_status_panel = PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.02, 0.04, 0.02, 0.75)
	style.border_color = Color(0.25, 0.5, 0.25, 0.35)
	style.set_border_width_all(1)
	style.set_corner_radius_all(3)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	_status_panel.add_theme_stylebox_override("panel", style)
	_status_panel.custom_minimum_size = Vector2(STATUS_PANEL_WIDTH, 0)
	add_child(_status_panel)

	_status_label = RichTextLabel.new()
	_status_label.bbcode_enabled = true
	_status_label.fit_content = true
	_status_label.scroll_active = false
	_status_label.custom_minimum_size = Vector2(STATUS_PANEL_WIDTH - 20, 0)
	_status_label.add_theme_font_size_override("normal_font_size", 12)
	_status_label.add_theme_font_size_override("bold_font_size", 12)
	_status_label.add_theme_color_override("default_color", Color(0.8, 0.9, 0.8))
	_status_panel.add_child(_status_label)

	# ── 右侧战术面板 ──
	_tactical_panel = PanelContainer.new()
	var tac_style := StyleBoxFlat.new()
	tac_style.bg_color = Color(0.02, 0.04, 0.02, 0.75)
	tac_style.border_color = Color(0.3, 0.6, 0.3, 0.4)
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
	tac_title.text = "[ 战术 ]"
	tac_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tac_title.add_theme_font_size_override("font_size", 11)
	tac_title.add_theme_color_override("font_color", Color(0.8, 0.7, 0.3))
	tac_vbox.add_child(tac_title)

	_btn_weapon = _create_tac_button("1 导弹优先")
	_btn_weapon.pressed.connect(_on_weapon_pressed)
	_btn_weapon.mouse_entered.connect(_on_tac_hover.bind("weapon"))
	_btn_weapon.mouse_exited.connect(_on_tac_hover_exit)
	tac_vbox.add_child(_btn_weapon)

	_btn_altitude = _create_tac_button("3 爬升优先")
	_btn_altitude.pressed.connect(_on_altitude_pressed)
	_btn_altitude.mouse_entered.connect(_on_tac_hover.bind("altitude"))
	_btn_altitude.mouse_exited.connect(_on_tac_hover_exit)
	tac_vbox.add_child(_btn_altitude)

	_btn_evasion = _create_tac_button("E 规避: 关")
	_btn_evasion.pressed.connect(_on_evasion_pressed)
	_btn_evasion.mouse_entered.connect(_on_tac_hover.bind("evasion"))
	_btn_evasion.mouse_exited.connect(_on_tac_hover_exit)
	tac_vbox.add_child(_btn_evasion)

	_btn_auto_fire = _create_tac_button("F 自动发射: 开")
	_btn_auto_fire.pressed.connect(_on_auto_fire_pressed)
	_btn_auto_fire.mouse_entered.connect(_on_tac_hover.bind("auto_fire"))
	_btn_auto_fire.mouse_exited.connect(_on_tac_hover_exit)
	tac_vbox.add_child(_btn_auto_fire)

	add_child(_tactical_panel)

	# ── 小队指挥面板（仅当主角有僚机时显示）──
	_build_squad_panel()

	# ── 战术提示面板 ──
	_tooltip_panel = PanelContainer.new()
	_tooltip_panel.visible = false
	var tip_style := StyleBoxFlat.new()
	tip_style.bg_color = Color(0.03, 0.05, 0.03, 0.9)
	tip_style.border_color = Color(0.4, 0.6, 0.3, 0.5)
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
	_tooltip_label.add_theme_color_override("default_color", Color(0.75, 0.85, 0.75))
	_tooltip_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tooltip_panel.add_child(_tooltip_label)
	add_child(_tooltip_panel)

	# ── 雷达小地图（左下角）──
	_radar = RadarDisplay.new()
	_radar.hud = self
	add_child(_radar)

	# ── Game Over 面板 ──
	_game_over_panel = PanelContainer.new()
	_game_over_panel.visible = false
	add_child(_game_over_panel)

	var go_style := StyleBoxFlat.new()
	go_style.bg_color = Color(0.02, 0.03, 0.02, 0.92)
	go_style.border_color = Color(1.0, 0.3, 0.3, 0.6)
	go_style.set_border_width_all(2)
	go_style.set_corner_radius_all(4)
	go_style.set_content_margin_all(30)
	_game_over_panel.add_theme_stylebox_override("panel", go_style)

	_game_over_label = RichTextLabel.new()
	_game_over_label.bbcode_enabled = true
	_game_over_label.fit_content = true
	_game_over_label.custom_minimum_size = Vector2(300, 200)
	_game_over_label.add_theme_font_size_override("normal_font_size", 14)
	_game_over_label.add_theme_color_override("default_color", Color(0.85, 0.9, 0.85))
	_game_over_panel.add_child(_game_over_label)

	# ── 屏幕外威胁方位指示 ──
	_threat_overlay = ThreatOverlay.new()
	_threat_overlay.hud = self
	add_child(_threat_overlay)

	# ── Debug 性能面板（F3）──
	_debug_panel = PanelContainer.new()
	_debug_panel.visible = false
	var dbg_style := StyleBoxFlat.new()
	dbg_style.bg_color = Color(0.0, 0.0, 0.0, 0.7)
	dbg_style.set_corner_radius_all(3)
	dbg_style.set_content_margin_all(8)
	_debug_panel.add_theme_stylebox_override("panel", dbg_style)
	add_child(_debug_panel)

	_debug_label = Label.new()
	_debug_label.add_theme_font_size_override("font_size", 11)
	_debug_label.add_theme_color_override("font_color", Color(0.0, 1.0, 0.4))
	_debug_panel.add_child(_debug_label)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_F3:
		_debug_visible = not _debug_visible
		_debug_panel.visible = _debug_visible

func _process(delta: float) -> void:
	_layout_ui()
	_update_display()
	_update_tactical_buttons()
	_update_squad_panel()
	if _debug_visible:
		_debug_update_timer -= delta
		if _debug_update_timer <= 0.0:
			_debug_update_timer = 0.25
			_update_debug_panel()

func _layout_ui() -> void:
	var vp := get_viewport().get_visible_rect().size

	_time_label.position = Vector2(vp.x * 0.5 - 60, 16)
	_time_label.size = Vector2(120, 30)

	_kill_label.position = Vector2(vp.x * 0.5 - 60, 42)
	_kill_label.size = Vector2(120, 20)

	var xp_x := (vp.x - XP_BAR_WIDTH) * 0.5
	var xp_y := vp.y - XP_BAR_HEIGHT - 20
	_xp_bar_bg.position = Vector2(xp_x, xp_y)
	_xp_bar_fill.position = Vector2(xp_x, xp_y)
	_xp_label.position = Vector2(xp_x, xp_y)
	_xp_label.size = Vector2(XP_BAR_WIDTH, XP_BAR_HEIGHT)

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

	# 小队指挥面板：战术面板正上方（只在有僚机时可见）
	if _squad_panel and _squad_panel.visible:
		_squad_panel.position = Vector2(
			vp.x - _squad_panel.size.x - 16,
			_tactical_panel.position.y - _squad_panel.size.y - 8
		)

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

func _update_display() -> void:
	if not survivor_player:
		return

	# 时间
	var mins := int(game_time) / 60
	var secs := int(game_time) % 60
	_time_label.text = "%02d:%02d" % [mins, secs]

	# 击杀
	_kill_label.text = "击杀: %d" % kill_count

	# 经验条
	var xp_ratio := float(survivor_player.xp) / float(maxi(survivor_player.xp_to_next, 1))
	_xp_bar_fill.size.x = XP_BAR_WIDTH * clampf(xp_ratio, 0.0, 1.0)
	_xp_label.text = "LV %d    %d / %d" % [survivor_player.level, survivor_player.xp, survivor_player.xp_to_next]

	# 右下角状态面板
	_update_status_panel()

func _update_status_panel() -> void:
	var ac := survivor_player.aircraft
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

	# ── G 力 / 结构极限 ──
	var g_cur: float = ac.g_load
	var g_max: float = ac._effective_max_g()
	var g_color := "ffaa33" if g_cur > g_max * 0.85 else "ccddee"
	text += "[color=#%s]G   %.1f / %.1f[/color]\n" % [g_color, g_cur, g_max]

	# ── 高度档位 ──
	if ac.flat_altitude:
		var tier_name: String = Aircraft.TIER_NAMES[ac.get_altitude_tier()]
		var target_tier_name: String = Aircraft.TIER_NAMES[ac.target_altitude_tier]
		var transitioning := ac.get_altitude_tier() != ac.target_altitude_tier
		if transitioning:
			text += "[color=#ffcc44]ALT  %s → %s[/color]\n" % [tier_name, target_tier_name]
		else:
			text += "[color=#aaccff]ALT  %s[/color]\n" % tier_name

	# ── 导弹 ──
	var max_msl := ac.params.missile.max_count if ac.params and ac.params.missile else 0
	if max_msl > 0:
		if ac._missile_reload_active:
			var pct := int(ac.missile_reload_progress * 100)
			text += "[color=#5599ff]MSL  RELOAD %d%%[/color]\n" % pct
		else:
			var msl_color := "88bbff" if ac.missiles_remaining > 0 else "666666"
			text += "[color=#%s]MSL  %d / %d[/color]\n" % [msl_color, ac.missiles_remaining, max_msl]

	# ── 机炮 ──
	if ac.params and ac.params.gun:
		var max_ammo := ac.params.gun.max_ammo
		if ac.enable_gun_reload and ac._gun_reload_active:
			var pct := int(ac.gun_reload_progress * 100)
			text += "[color=#aa7733]GUN  RELOAD %d%%[/color]\n" % pct
		else:
			var ammo_color := "ccddaa" if ac.ammo > 100 else ("ffaa44" if ac.ammo > 0 else "666666")
			text += "[color=#%s]GUN  %d / %d[/color]\n" % [ammo_color, ac.ammo, max_ammo]

	# ── 热诱弹 ──
	if ac.params and ac.params.flare:
		var max_flr := ac.params.flare.max_flares
		if ac.enable_flare_reload and ac.flares_remaining <= 0 and ac.flare_reload_progress > 0.01:
			var pct := int(ac.flare_reload_progress * 100)
			text += "[color=#aa8833]FLR  RELOAD %d%%[/color]\n" % pct
		else:
			var cd_ratio := ac.get_flare_cooldown_ratio()
			var flr_color := "ffdd66"
			if cd_ratio > 0.01:
				flr_color = "aa8833"
			elif ac.flares_remaining <= 0:
				flr_color = "666666"
			var cd_text := "  CD" if cd_ratio > 0.01 else ""
			text += "[color=#%s]FLR  %d / %d%s[/color]\n" % [flr_color, ac.flares_remaining, max_flr, cd_text]

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
			var tag_color: String
			if is_evolved:
				tag_color = "ffcc44"  # 金色：进化技能
			elif cat == "combat":
				tag_color = "cc6655"
			else:
				tag_color = "55aa66"
			var max_s := int(u["max_stacks"])
			var level_dots := ""
			if is_evolved:
				level_dots = "[color=#ffcc44]★[/color]"
			else:
				for i in range(max_s):
					if i < count:
						level_dots += "[color=#aaddaa]|[/color]"
					else:
						level_dots += "[color=#333]|[/color]"
			text += "[color=#%s]%s[/color] %s\n" % [tag_color, u["name"], level_dots]

	_status_label.text = text

func _create_tac_button(label_text: String) -> Button:
	var btn := Button.new()
	btn.text = label_text
	btn.custom_minimum_size = Vector2(STATUS_PANEL_WIDTH - 16, 26)
	btn.add_theme_font_size_override("font_size", 11)

	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.06, 0.1, 0.06)
	normal.border_color = Color(0.3, 0.6, 0.3, 0.5)
	normal.set_border_width_all(1)
	normal.set_corner_radius_all(2)
	normal.content_margin_left = 6
	normal.content_margin_right = 6
	normal.content_margin_top = 3
	normal.content_margin_bottom = 3
	btn.add_theme_stylebox_override("normal", normal)

	var hover := StyleBoxFlat.new()
	hover.bg_color = Color(0.1, 0.18, 0.1)
	hover.border_color = Color(1.0, 0.8, 0.3, 0.6)
	hover.set_border_width_all(1)
	hover.set_corner_radius_all(2)
	hover.content_margin_left = 6
	hover.content_margin_right = 6
	hover.content_margin_top = 3
	hover.content_margin_bottom = 3
	btn.add_theme_stylebox_override("hover", hover)

	var pressed := StyleBoxFlat.new()
	pressed.bg_color = Color(0.15, 0.25, 0.15)
	pressed.border_color = Color(1.0, 0.9, 0.4, 0.7)
	pressed.set_border_width_all(1)
	pressed.set_corner_radius_all(2)
	pressed.content_margin_left = 6
	pressed.content_margin_right = 6
	pressed.content_margin_top = 3
	pressed.content_margin_bottom = 3
	btn.add_theme_stylebox_override("pressed", pressed)

	btn.add_theme_color_override("font_color", Color(0.7, 0.9, 0.7))
	btn.add_theme_color_override("font_hover_color", Color(1.0, 0.9, 0.5))
	btn.add_theme_color_override("font_pressed_color", Color(1.0, 1.0, 0.6))

	return btn

func _on_weapon_pressed() -> void:
	if not survivor_player or not survivor_player.aircraft:
		return
	var ac := survivor_player.aircraft
	if ac.weapon_preference == Aircraft.WeaponPreference.PREFER_MISSILE:
		ac.weapon_preference = Aircraft.WeaponPreference.PREFER_GUN
	else:
		ac.weapon_preference = Aircraft.WeaponPreference.PREFER_MISSILE
	_update_tactical_buttons()
	if _tooltip_panel.visible:
		_update_tooltip()

func _on_altitude_pressed() -> void:
	if not survivor_player or not survivor_player.aircraft:
		return
	var ac := survivor_player.aircraft
	if ac.altitude_preference == Aircraft.AltitudePreference.PREFER_CLIMB:
		ac.altitude_preference = Aircraft.AltitudePreference.PREFER_LOW
	else:
		ac.altitude_preference = Aircraft.AltitudePreference.PREFER_CLIMB
	_update_tactical_buttons()
	if _tooltip_panel.visible:
		_update_tooltip()

func _on_evasion_pressed() -> void:
	if not survivor_player or not survivor_player.aircraft:
		return
	var ac := survivor_player.aircraft
	ac.set_evasion_mode(not ac.evasion_mode)
	_update_tactical_buttons()
	if _tooltip_panel.visible:
		_update_tooltip()

func _on_auto_fire_pressed() -> void:
	if not survivor_player or not survivor_player.aircraft:
		return
	var ac := survivor_player.aircraft
	ac.missile_auto_fire = not ac.missile_auto_fire
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
	if not survivor_player or not survivor_player.aircraft:
		return
	var ac := survivor_player.aircraft
	var text := ""

	match _tooltip_key:
		"weapon":
			if ac.weapon_preference == Aircraft.WeaponPreference.PREFER_MISSILE:
				text = "[color=#ffcc44][b]导弹优先[/b][/color]\n"
				text += "[color=#aabbaa]点击敌机后自动锁定并发射导弹\n"
				text += "导弹耗尽时自动切换机炮\n"
				text += "装填完毕后恢复导弹模式[/color]\n\n"
				text += "[color=#888888]按 [color=#ffdd66]2[/color] 切换到机炮优先[/color]"
			else:
				text = "[color=#ffcc44][b]机炮优先[/b][/color]\n"
				text += "[color=#aabbaa]始终使用机炮进行攻击\n"
				text += "不会自动发射导弹[/color]\n\n"
				text += "[color=#888888]按 [color=#ffdd66]1[/color] 切换到导弹优先[/color]"
		"altitude":
			if ac.altitude_preference == Aircraft.AltitudePreference.PREFER_CLIMB:
				text = "[color=#ffcc44][b]爬升优先[/b][/color]\n"
				text += "[color=#aabbaa]巡航时自动爬升至高空\n"
				text += "高空有利于积蓄能量\n"
				text += "[color=#66ccff]导弹射程更远[/color]\n"
				text += "交战时仍会自动匹配目标高度[/color]\n\n"
				text += "[color=#888888]按 [color=#ffdd66]4[/color] 切换到低空优先[/color]"
			else:
				text = "[color=#ffcc44][b]低空优先[/b][/color]\n"
				text += "[color=#aabbaa]巡航时自动降至低空\n"
				text += "[color=#66ff66]更难被雷达锁定（锁定时间+43%）[/color]\n"
				text += "[color=#66ff66]敌方导弹追踪能力下降[/color]\n"
				text += "[color=#66ff66]AI攻击意愿降低[/color]\n"
				text += "交战时仍会自动匹配目标高度[/color]\n\n"
				text += "[color=#888888]按 [color=#ffdd66]3[/color] 切换到爬升优先[/color]"
		"evasion":
			if ac.evasion_mode:
				text = "[color=#ffcc44][b]规避模式: 开[/b][/color]\n"
				text += "[color=#aabbaa]检测到来袭导弹时自动规避\n"
				text += "垂直于导弹轨迹急转+变换高度\n"
				text += "无导弹威胁时做S型机动\n"
				text += "点击地面可临时覆盖规避路径[/color]\n\n"
				text += "[color=#888888]按 [color=#ffdd66]E[/color] 关闭规避[/color]"
			else:
				text = "[color=#ffcc44][b]规避模式: 关[/b][/color]\n"
				text += "[color=#aabbaa]飞机不会主动进行规避机动\n"
				text += "完全听从玩家的移动指令[/color]\n\n"
				text += "[color=#888888]按 [color=#ffdd66]E[/color] 开启规避[/color]"
		"auto_fire":
			if ac.missile_auto_fire:
				text = "[color=#ffcc44][b]自动发射: 开[/b][/color]\n"
				text += "[color=#aabbaa]飞机自动选择最佳角度发射导弹\n"
				text += "锁定任意敌机即自动开火\n"
				text += "[color=#66ccff]多目标追踪升级下一次发多枚[/color]\n"
				text += "无需玩家手动点击目标[/color]\n\n"
				text += "[color=#888888]按 [color=#ffdd66]F[/color] 关闭自动发射[/color]"
			else:
				text = "[color=#ffcc44][b]自动发射: 关[/b][/color]\n"
				text += "[color=#aabbaa]只在玩家点击敌机指定攻击时开火\n"
				text += "节省弹药 / 精准打击[/color]\n\n"
				text += "[color=#888888]按 [color=#ffdd66]F[/color] 开启自动发射[/color]"

	_tooltip_label.text = text

func _update_tactical_buttons() -> void:
	if not survivor_player or not survivor_player.aircraft:
		return
	var ac := survivor_player.aircraft
	if ac.weapon_preference == Aircraft.WeaponPreference.PREFER_MISSILE:
		_btn_weapon.text = "1 导弹优先"
	else:
		_btn_weapon.text = "2 机炮优先"
	if ac.altitude_preference == Aircraft.AltitudePreference.PREFER_CLIMB:
		_btn_altitude.text = "3 爬升优先"
	else:
		_btn_altitude.text = "4 低空优先"
	_btn_evasion.text = "E 规避: %s" % ("开" if ac.evasion_mode else "关")
	_btn_auto_fire.text = "F 自动发射: %s" % ("开" if ac.missile_auto_fire else "关")

# ══════════════════════════════════════════════
#  小队指挥面板（仅主角有僚机时存在）
# ══════════════════════════════════════════════

const SQUAD_PANEL_WIDTH := 240.0

func _build_squad_panel() -> void:
	_squad_panel = PanelContainer.new()
	_squad_panel.visible = false  # 默认隐藏，发现僚机时再显示
	var sp_style := StyleBoxFlat.new()
	sp_style.bg_color = Color(0.02, 0.04, 0.02, 0.78)
	sp_style.border_color = Color(0.35, 0.55, 0.75, 0.45)
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
	sp_title.text = "[ 小队指挥 ]"
	sp_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sp_title.add_theme_font_size_override("font_size", 11)
	sp_title.add_theme_color_override("font_color", Color(0.5, 0.75, 1.0))
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
	sep.color = Color(0.3, 0.5, 0.7, 0.35)
	sep.custom_minimum_size = Vector2(0, 1)
	sp_vbox.add_child(sep)

	# 指令按钮
	_btn_squad_formation = _create_tac_button("5 阵型: 指尖四点")
	_btn_squad_formation.pressed.connect(_on_squad_formation_pressed)
	sp_vbox.add_child(_btn_squad_formation)

	_btn_squad_engage = _create_tac_button("6 交战: 自由交战")
	_btn_squad_engage.pressed.connect(_on_squad_engage_pressed)
	sp_vbox.add_child(_btn_squad_engage)

	_btn_squad_weapon = _create_tac_button("7 武器: 导弹优先")
	_btn_squad_weapon.pressed.connect(_on_squad_weapon_pressed)
	sp_vbox.add_child(_btn_squad_weapon)

	add_child(_squad_panel)

## 返回玩家所在的小队（以玩家为长机的那个 Squad）
func _get_player_squad() -> Squad:
	if not game_scene or not game_scene.player_aircraft:
		return null
	# game_scene 在生存模式下一定是 survivor_mode 且拥有 _squads 成员
	var squads = game_scene._squads
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

## 把 AI 当前状态/战术翻译成中文动作名
func _wingman_action_text(ac: Aircraft) -> String:
	var ai := _get_ai(ac)
	if ai == null:
		return "?"
	if ac.evasion_mode:
		return "规避机动"
	match ai._state:
		AIController.AIState.PATROL:
			return "巡逻"
		AIController.AIState.ENGAGE:
			if ai.current_tactic_name != "":
				return ai.current_tactic_name
			return "交战"
		AIController.AIState.EVADE_MISSILE:
			return "导弹规避"
		AIController.AIState.SQUAD_FOLLOW:
			if ai.current_tactic_name != "":
				return ai.current_tactic_name
			return "编队跟随"
	return "?"

## 每帧刷新小队面板内容（状态行 + 按钮文本 + 可见性）
func _update_squad_panel() -> void:
	if _squad_panel == null:
		return
	var wingmen := _get_wingmen()
	if wingmen.is_empty():
		_squad_panel.visible = false
		return
	_squad_panel.visible = true

	var bbcode := ""
	for i in range(wingmen.size()):
		var wm: Aircraft = wingmen[i]
		var max_hp: float = wm.params.max_hp if wm.params else 100.0
		var hp_ratio: float = clampf(wm.hp / maxf(max_hp, 0.01), 0.0, 1.0)
		var hp_color: String = "66ff66" if hp_ratio > 0.6 else ("ffcc44" if hp_ratio > 0.3 else "ff5555")
		var bar_cells := 10
		var filled := int(round(hp_ratio * bar_cells))
		var bar_str := ""
		for c in range(bar_cells):
			bar_str += "█" if c < filled else "░"

		bbcode += "[b]%s[/b]  [color=#%s]HP %3d%%[/color]\n" % [wm.callsign, hp_color, int(hp_ratio * 100)]
		bbcode += "  [color=#%s]%s[/color]\n" % [hp_color, bar_str]
		var msl_n: int = wm.missiles_remaining if wm.params and wm.params.missile else 0
		var amm_n: int = wm.ammo if wm.params and wm.params.gun else 0
		var flr_n: int = wm.flares_remaining if wm.params and wm.params.flare else 0
		bbcode += "  [color=#aabbaa]MSL %d  AMM %d  FLR %d[/color]\n" % [msl_n, amm_n, flr_n]
		bbcode += "  [color=#6ab4e8]• %s[/color]" % _wingman_action_text(wm)
		if i < wingmen.size() - 1:
			bbcode += "\n\n"
	_squad_status_label.text = bbcode

	# 按钮文本
	var sq := _get_player_squad()
	if sq:
		_btn_squad_formation.text = "5 阵型: %s" % sq.get_formation_name()
	var mode_str := "自由交战" if _squad_engage_mode == AIController.SquadEngageMode.FREE else "跟随长机"
	_btn_squad_engage.text = "6 交战: %s" % mode_str
	_btn_squad_weapon.text = "7 武器: %s" % ("导弹优先" if _squad_weapon_pref == Aircraft.WeaponPreference.PREFER_MISSILE else "机炮优先")

## 切换阵型（命令所有僚机按新槽位归队）
func _on_squad_formation_pressed() -> void:
	var sq := _get_player_squad()
	if sq == null:
		return
	sq.cycle_formation()
	EventLogger.log_event("SQUAD_CMD", "Player", "formation → %s" % sq.get_formation_name())

## 切换交战模式（自由交战 ↔ 跟随长机）
## 切换时强制所有僚机立即脱离当前 ENGAGE 并回到 SQUAD_FOLLOW，
## 这样模式切换能马上生效，不会有"模式改了但僚机还在打老目标"的感觉。
func _on_squad_engage_pressed() -> void:
	if _squad_engage_mode == AIController.SquadEngageMode.FREE:
		_squad_engage_mode = AIController.SquadEngageMode.FOLLOW_LEADER
	else:
		_squad_engage_mode = AIController.SquadEngageMode.FREE
	for wm in _get_wingmen():
		var ai := _get_ai(wm)
		if ai == null:
			continue
		ai.squad_engage_mode = _squad_engage_mode
		# 若僚机正在交战，强制脱离并回到编队，保证"切模式=立刻生效"
		if ai._state == AIController.AIState.ENGAGE:
			wm.clear_combat_target()
			wm.ai_override_pursuit = false
			wm.keep_target_on_arrival = true
			wm.formation_mode = true
			wm._formation_leader = game_scene.player_aircraft
			wm._formation_blend = 1.0  # 直接落位完整编队托管，不走慢吞吞的 rejoin
			wm.lod_level = 1
			ai._state = AIController.AIState.SQUAD_FOLLOW
			ai._formation_blend = 1.0
			ai._rejoining = false
			ai._current_target = null
			ai._squad_attacking_leader_target = false
			ai._engage_timer = 0.0
			ai._cooldown_timer = 0.0
			ai.current_tactic_name = ""
	var mode_str := "FREE" if _squad_engage_mode == AIController.SquadEngageMode.FREE else "FOLLOW_LEADER"
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
			if child.team != 0 and not child.is_destroyed:
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
	_debug_label.text = text

func _count_nodes(node: Node) -> int:
	var count := 1
	for child in node.get_children():
		count += _count_nodes(child)
	return count

func show_game_over(level: int, time: float, kills: int) -> void:
	var mins := int(time) / 60
	var secs := int(time) % 60
	var text := "[center][color=#ff6655][b][ GAME OVER ][/b][/color]\n\n"
	text += "[color=#aaddaa]等级: %d\n" % level
	text += "存活时间: %02d:%02d\n" % [mins, secs]
	text += "击杀数: %d[/color]\n\n" % kills
	text += "[color=#888888]按 ESC 返回主菜单[/color][/center]"
	_game_over_label.text = text
	_game_over_panel.visible = true

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
	const BG_COLOR := Color(0.02, 0.06, 0.02, 0.8)
	const RING_COLOR := Color(0.15, 0.35, 0.15, 0.5)
	const SWEEP_COLOR := Color(0.2, 0.8, 0.2, 0.5)
	const PLAYER_COLOR := Color(0.3, 0.7, 1.0, 0.9)
	const ENEMY_COLOR := Color(1.0, 0.3, 0.2, 0.85)
	const LOCKED_COLOR := Color(1.0, 0.8, 0.2, 0.95)
	const MISSILE_WARNING_COLOR := Color(1.0, 0.15, 0.1, 0.95)

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
		var player_ac: Aircraft = hud.survivor_player.aircraft
		if not player_ac or player_ac.is_destroyed:
			return

		var vp := get_viewport_rect().size
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

		# 更新 blip 并绘制敌机
		var scene: Node2D = hud.game_scene
		var player_pos := player_ac.global_position

		for child in scene.get_children():
			if not child is Aircraft:
				continue
			var ac: Aircraft = child
			if ac == player_ac:
				continue
			if ac.is_destroyed:
				continue

			var rel := ac.global_position - player_pos
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
				_blip_ages[ac.get_instance_id()] = 0.0

			# 绘制 blip
			var age: float = _blip_ages.get(ac.get_instance_id(), 99.0)
			if age > 3.5:
				continue  # 太久没扫描到，不显示

			var fade := clampf(1.0 - age / 3.5, 0.0, 1.0)

			# 颜色：锁定目标=黄色，普通敌机=红色，友方=蓝色
			var blip_color: Color
			if ac.team == 0:
				blip_color = PLAYER_COLOR
			elif player_ac.combat_target == ac:
				blip_color = LOCKED_COLOR
			else:
				blip_color = ENEMY_COLOR

			blip_color.a *= fade
			draw_circle(blip_pos, 2.5, blip_color)

			# 锁定目标加方框
			if player_ac.combat_target == ac:
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
		var missile_mgr = hud.game_scene.get_node_or_null("MissileManager")
		if missile_mgr:
			var blink := fmod(hud.game_time * 3.33, 1.0) > 0.5
			for child in missile_mgr.get_children():
				if not child is Missile:
					continue
				var m: Missile = child
				if not m.is_active or m.target != player_ac:
					continue
				has_incoming = true
				var rel_m := m.global_position - player_pos
				var dist_m := rel_m.length()
				if dist_m > RADAR_RANGE:
					continue
				var angle_m := atan2(rel_m.x, -rel_m.y)
				var radar_dist_m := (dist_m / RADAR_RANGE) * RADAR_RADIUS
				var msl_pos := center + Vector2(sin(angle_m), -cos(angle_m)) * radar_dist_m
				if blink:
					# 小菱形标记
					var s := 4.0
					var diamond := PackedVector2Array([
						msl_pos + Vector2(0, -s),
						msl_pos + Vector2(s, 0),
						msl_pos + Vector2(0, s),
						msl_pos + Vector2(-s, 0),
					])
					draw_colored_polygon(diamond, MISSILE_WARNING_COLOR)

		# "MISSILE" 文字警告
		if has_incoming:
			var blink_txt := fmod(hud.game_time * 2.5, 1.0) > 0.3
			if blink_txt:
				var warn_pos := Vector2(center.x, center.y - RADAR_RADIUS - 12)
				var font := ThemeDB.fallback_font
				var text := "MISSILE"
				var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, 11)
				draw_string(font, warn_pos - Vector2(text_size.x * 0.5, 0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, MISSILE_WARNING_COLOR)

		# 外圈边框
		draw_arc(center, RADAR_RADIUS, 0, TAU, 64, Color(0.2, 0.5, 0.2, 0.6), 1.5)

# ══════════════════════════════════════════════
#  屏幕外威胁方位指示器
# ══════════════════════════════════════════════

class ThreatOverlay extends Control:
	var hud: SurvivorHUD

	const ARROW_SIZE := 12.0
	const EDGE_MARGIN := 30.0
	const THREAT_COLOR := Color(1.0, 0.3, 0.2, 0.8)
	const LOCK_COLOR := Color(1.0, 0.15, 0.1, 0.95)

	func _ready() -> void:
		set_anchors_and_offsets_preset(PRESET_FULL_RECT)
		mouse_filter = MOUSE_FILTER_IGNORE

	func _process(_delta: float) -> void:
		queue_redraw()

	func _draw() -> void:
		if not hud or not hud.game_scene or not hud.survivor_player:
			return
		var player_ac: Aircraft = hud.survivor_player.aircraft
		if not player_ac or player_ac.is_destroyed:
			return

		var scene: Node2D = hud.game_scene
		var camera: Camera2D = scene.get_node("Camera2D")
		if not camera:
			return

		var vp_size := get_viewport_rect().size
		var cam_pos := camera.global_position
		var zoom := camera.zoom
		var half_vp := vp_size / (2.0 * zoom)

		var screen_left := cam_pos.x - half_vp.x
		var screen_right := cam_pos.x + half_vp.x
		var screen_top := cam_pos.y - half_vp.y
		var screen_bottom := cam_pos.y + half_vp.y

		for child in scene.get_children():
			if not child is Aircraft:
				continue
			var ac: Aircraft = child
			if ac.team == 0 or ac.is_destroyed:
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
