class_name EvolutionUI
extends CanvasLayer

## 战区结算进化面板（垂直切片，spec ace-system §2.3/§2.4）
## ACE 强制手动三选：列出当前节点全部出口（等级不足灰显门槛），或"暂不进化"。
## 僚机跟随在 survivor_mode 侧执行；本面板只负责选择。
## 选择结果经 choice_made 信号回传（&"" = 暂不）。

signal choice_made(node_id: StringName)

var _panel: PanelContainer
var _vbox: VBoxContainer

func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS  # 暂停期间可交互（同 survivor_upgrade_ui 模式）
	visible = false
	_panel = PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = ThemeColors.PANEL_BG_SOLID
	style.border_color = ThemeColors.PANEL_BORDER_ACCENT
	style.set_border_width_all(2)
	style.set_corner_radius_all(4)
	style.set_content_margin_all(16)
	_panel.add_theme_stylebox_override("panel", style)
	_panel.custom_minimum_size = Vector2(420, 0)
	add_child(_panel)
	_vbox = VBoxContainer.new()
	_vbox.add_theme_constant_override("separation", 8)
	_panel.add_child(_vbox)

## 打开面板。current = 当前节点 Dictionary；exits = 出口节点数组；team_level = 团队等级（门槛判定）
func show_offer(current: Dictionary, exits: Array, team_level: int) -> void:
	for c in _vbox.get_children():
		c.queue_free()
	var title := Label.new()
	title.text = tr("EVOLUTION_TITLE")
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", ThemeColors.TEXT_ACCENT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_vbox.add_child(title)
	var sub := Label.new()
	sub.text = tr("EVOLUTION_SUBTITLE_FMT") % tr(String(current.get("name_key", "")))
	sub.add_theme_font_size_override("font_size", 13)
	sub.add_theme_color_override("font_color", ThemeColors.TEXT_MUTED)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_vbox.add_child(sub)
	for nd in exits:
		var need: int = EvolutionSystem.min_level_of(nd)
		var btn := Button.new()
		var label := "%s ｜ %s · T%d" % [
			tr(String(nd.get("name_key", ""))),
			tr(EvolutionSystem.category_key_of(nd)),
			int(nd.get("tier", 0))]
		if team_level < need:
			btn.text = label + "   " + tr("EVOLUTION_LOCKED_FMT") % need
			btn.disabled = true
		else:
			btn.text = label
			var nid := StringName(nd.get("id", ""))
			btn.pressed.connect(func() -> void: _choose(nid))
		btn.add_theme_font_size_override("font_size", 14)
		_vbox.add_child(btn)
	var skip := Button.new()
	skip.text = tr("EVOLUTION_SKIP")
	skip.add_theme_font_size_override("font_size", 13)
	skip.pressed.connect(func() -> void: _choose(&""))
	_vbox.add_child(skip)
	visible = true
	_center.call_deferred()

func _center() -> void:
	var vp := _panel.get_viewport_rect().size
	_panel.position = (vp - _panel.size) * 0.5

func _choose(node_id: StringName) -> void:
	visible = false
	choice_made.emit(node_id)
