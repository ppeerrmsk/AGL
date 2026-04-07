class_name SurvivorHUD
extends CanvasLayer

## 生存模式 HUD：血量、经验条、时间、击杀数

var survivor_player: SurvivorPlayer
var game_time: float = 0.0
var kill_count: int = 0

# ── UI 元素 ──
var _hp_bar_bg: ColorRect
var _hp_bar_fill: ColorRect
var _hp_label: Label
var _xp_bar_bg: ColorRect
var _xp_bar_fill: ColorRect
var _xp_label: Label
var _time_label: Label
var _kill_label: Label
var _game_over_panel: PanelContainer
var _game_over_label: RichTextLabel

const HP_BAR_WIDTH := 200.0
const HP_BAR_HEIGHT := 16.0
const XP_BAR_WIDTH := 400.0
const XP_BAR_HEIGHT := 20.0

func _ready() -> void:
	layer = 10
	_build_ui()

func _build_ui() -> void:
	# ── HP 条（左上角）──
	_hp_bar_bg = ColorRect.new()
	_hp_bar_bg.color = Color(0.1, 0.1, 0.1, 0.7)
	_hp_bar_bg.size = Vector2(HP_BAR_WIDTH, HP_BAR_HEIGHT)
	_hp_bar_bg.position = Vector2(20, 20)
	add_child(_hp_bar_bg)

	_hp_bar_fill = ColorRect.new()
	_hp_bar_fill.color = Color(0.3, 1.0, 0.3)
	_hp_bar_fill.size = Vector2(HP_BAR_WIDTH, HP_BAR_HEIGHT)
	_hp_bar_fill.position = Vector2(20, 20)
	add_child(_hp_bar_fill)

	_hp_label = Label.new()
	_hp_label.position = Vector2(20, 20)
	_hp_label.size = Vector2(HP_BAR_WIDTH, HP_BAR_HEIGHT)
	_hp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hp_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_hp_label.add_theme_font_size_override("font_size", 11)
	_hp_label.add_theme_color_override("font_color", Color(1, 1, 1))
	add_child(_hp_label)

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

	# ── Game Over 面板（隐藏）──
	_game_over_panel = PanelContainer.new()
	_game_over_panel.visible = false
	add_child(_game_over_panel)

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.02, 0.03, 0.02, 0.92)
	style.border_color = Color(1.0, 0.3, 0.3, 0.6)
	style.set_border_width_all(2)
	style.set_corner_radius_all(4)
	style.set_content_margin_all(30)
	_game_over_panel.add_theme_stylebox_override("panel", style)

	_game_over_label = RichTextLabel.new()
	_game_over_label.bbcode_enabled = true
	_game_over_label.fit_content = true
	_game_over_label.custom_minimum_size = Vector2(300, 200)
	_game_over_label.add_theme_font_size_override("normal_font_size", 14)
	_game_over_label.add_theme_color_override("default_color", Color(0.85, 0.9, 0.85))
	_game_over_panel.add_child(_game_over_label)

func _process(_delta: float) -> void:
	_layout_ui()
	_update_display()

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

	if _game_over_panel.visible:
		_game_over_panel.position = Vector2(
			(vp.x - _game_over_panel.size.x) * 0.5,
			(vp.y - _game_over_panel.size.y) * 0.5
		)

func _update_display() -> void:
	if not survivor_player:
		return

	# HP
	var current_hp := survivor_player.get_hp()
	var max_hp := survivor_player.get_max_hp()
	var hp_ratio := current_hp / maxf(max_hp, 1.0)
	_hp_bar_fill.size.x = HP_BAR_WIDTH * hp_ratio
	if hp_ratio > 0.5:
		_hp_bar_fill.color = Color(0.3, 1.0, 0.3)
	elif hp_ratio > 0.25:
		_hp_bar_fill.color = Color(1.0, 0.8, 0.2)
	else:
		_hp_bar_fill.color = Color(1.0, 0.3, 0.3)
	_hp_label.text = "HP  %d / %d" % [ceili(current_hp), ceili(max_hp)]

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
