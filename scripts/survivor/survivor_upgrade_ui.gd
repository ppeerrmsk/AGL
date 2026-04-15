class_name SurvivorUpgradeUI
extends CanvasLayer

## 升级选择面板：暂停时显示3个升级选项

signal upgrade_selected(upgrade: Dictionary)

var _overlay: ColorRect
var _title: Label
var _btn_container: HBoxContainer
var _buttons: Array[Button] = []
var _choices: Array[Dictionary] = []

func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_build_ui()

func _build_ui() -> void:
	# 半透明遮罩
	_overlay = ColorRect.new()
	_overlay.color = Color(0.0, 0.0, 0.0, 0.6)
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_overlay)

	# 主容器
	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.alignment = BoxContainer.ALIGNMENT_CENTER
	root.add_theme_constant_override("separation", 20)
	add_child(root)

	# 上部空白
	var spacer_top := Control.new()
	spacer_top.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(spacer_top)

	# 标题
	_title = Label.new()
	_title.text = tr("UPGRADE_HEADER")
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_font_size_override("font_size", 24)
	_title.add_theme_color_override("font_color", Color(1.0, 0.8, 0.3))
	root.add_child(_title)

	# 按钮容器
	_btn_container = HBoxContainer.new()
	_btn_container.alignment = BoxContainer.ALIGNMENT_CENTER
	_btn_container.add_theme_constant_override("separation", 20)
	_btn_container.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	root.add_child(_btn_container)

	# 3个按钮
	for i in range(3):
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(220, 120)
		btn.add_theme_font_size_override("font_size", 14)

		var style_normal := StyleBoxFlat.new()
		style_normal.bg_color = Color(0.06, 0.1, 0.06, 0.85)
		style_normal.border_color = Color(0.3, 0.6, 0.3, 0.5)
		style_normal.set_border_width_all(1)
		style_normal.set_corner_radius_all(4)
		style_normal.set_content_margin_all(12)
		btn.add_theme_stylebox_override("normal", style_normal)

		var style_hover := StyleBoxFlat.new()
		style_hover.bg_color = Color(0.1, 0.18, 0.1, 0.9)
		style_hover.border_color = Color(1.0, 0.8, 0.3, 0.8)
		style_hover.set_border_width_all(2)
		style_hover.set_corner_radius_all(4)
		style_hover.set_content_margin_all(12)
		btn.add_theme_stylebox_override("hover", style_hover)

		var style_pressed := StyleBoxFlat.new()
		style_pressed.bg_color = Color(0.15, 0.25, 0.15, 0.95)
		style_pressed.border_color = Color(1.0, 0.9, 0.4, 1.0)
		style_pressed.set_border_width_all(2)
		style_pressed.set_corner_radius_all(4)
		style_pressed.set_content_margin_all(12)
		btn.add_theme_stylebox_override("pressed", style_pressed)

		var idx := i
		btn.pressed.connect(func(): _on_choice_pressed(idx))
		_btn_container.add_child(btn)
		_buttons.append(btn)

	# 下部空白
	var spacer_bottom := Control.new()
	spacer_bottom.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(spacer_bottom)

func show_choices(choices: Array[Dictionary]) -> void:
	_choices = choices
	for i in range(3):
		if i < choices.size():
			_buttons[i].visible = true
			var cat: String = choices[i].get("category", "")
			var cat_prefix := ""
			if cat == "combat":
				cat_prefix = tr("UPGRADE_CATEGORY_COMBAT_PREFIX")
			elif cat == "survival":
				cat_prefix = tr("UPGRADE_CATEGORY_SURVIVAL_PREFIX")
			_buttons[i].text = "%s%s\n\n%s" % [cat_prefix, tr(choices[i]["name"]), tr(choices[i]["desc"])]
			# 根据类别调整边框颜色
			var style_normal: StyleBoxFlat = _buttons[i].get_theme_stylebox("normal").duplicate()
			var style_hover: StyleBoxFlat = _buttons[i].get_theme_stylebox("hover").duplicate()
			if cat == "combat":
				style_normal.border_color = Color(0.8, 0.4, 0.3, 0.5)
				style_hover.border_color = Color(1.0, 0.5, 0.3, 0.8)
			else:
				style_normal.border_color = Color(0.3, 0.6, 0.3, 0.5)
				style_hover.border_color = Color(0.3, 1.0, 0.5, 0.8)
			_buttons[i].add_theme_stylebox_override("normal", style_normal)
			_buttons[i].add_theme_stylebox_override("hover", style_hover)
		else:
			_buttons[i].visible = false
	visible = true

func _on_choice_pressed(index: int) -> void:
	if index < _choices.size():
		upgrade_selected.emit(_choices[index])
	visible = false
