class_name SurvivorUpgradeUI
extends CanvasLayer

## 升级选择面板：暂停时显示3个升级选项

signal upgrade_selected(upgrade: Dictionary)

var _overlay: ColorRect
var _title: Label
var _btn_container: HBoxContainer
var _buttons: Array[Button] = []
## §5 稀有度徽章：每张卡片右上角悬浮的"STABLE / ADV / EXP / CLA / NEXT"标签
var _rarity_badges: Array[Label] = []
var _choices: Array[Dictionary] = []

func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_build_ui()

func _build_ui() -> void:
	# 半透明遮罩
	_overlay = ColorRect.new()
	_overlay.color = ThemeColors.PANEL_BG_OVERLAY
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
	_title.add_theme_color_override("font_color", ThemeColors.TEXT_ACCENT)
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
		style_normal.bg_color = Color(ThemeColors.BTN_NORMAL_BG, 0.85)
		style_normal.border_color = ThemeColors.BTN_NORMAL_BORDER
		style_normal.set_border_width_all(1)
		style_normal.set_corner_radius_all(4)
		style_normal.set_content_margin_all(12)
		btn.add_theme_stylebox_override("normal", style_normal)

		var style_hover := StyleBoxFlat.new()
		style_hover.bg_color = Color(ThemeColors.BTN_HOVER_BG, 0.9)
		style_hover.border_color = Color(ThemeColors.TEXT_ACCENT, 0.8)
		style_hover.set_border_width_all(2)
		style_hover.set_corner_radius_all(4)
		style_hover.set_content_margin_all(12)
		btn.add_theme_stylebox_override("hover", style_hover)

		var style_pressed := StyleBoxFlat.new()
		style_pressed.bg_color = Color(ThemeColors.BTN_PRESSED_BG, 0.95)
		style_pressed.border_color = Color(ThemeColors.BTN_PRESSED_BORDER, 1.0)
		style_pressed.set_border_width_all(2)
		style_pressed.set_corner_radius_all(4)
		style_pressed.set_content_margin_all(12)
		btn.add_theme_stylebox_override("pressed", style_pressed)

		var idx := i
		btn.pressed.connect(func(): _on_choice_pressed(idx))
		_btn_container.add_child(btn)
		_buttons.append(btn)

		# §5 稀有度徽章：右上角小标签（pos 由 _layout_rarity_badge 在 show_choices 设置）
		var badge := Label.new()
		badge.text = ""
		badge.add_theme_font_size_override("font_size", 11)
		badge.add_theme_color_override("font_color", Color.WHITE)
		# 半透明黑底 + 圆角，让浅色字在任何背景上都可读
		var badge_bg := StyleBoxFlat.new()
		badge_bg.bg_color = Color(0.0, 0.0, 0.0, 0.55)
		badge_bg.set_corner_radius_all(3)
		badge_bg.set_content_margin_all(4)
		badge.add_theme_stylebox_override("normal", badge_bg)
		# 不参与父容器布局：通过 anchor 钉到按钮右上
		badge.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
		badge.position = Vector2(-90, 6)
		badge.size = Vector2(82, 18)
		badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		btn.add_child(badge)
		_rarity_badges.append(badge)

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
			var cat_prefix := _axis_prefix(cat)
			# 三轴标签（spec evolution-attribute-gates §2.2）：选卡=该轴 +1 点，卡面第一行直接可见
			var axis: StringName = SurvivorData.axis_of_upgrade(choices[i])
			var axis_tag := "【%s +1】" % tr(str(SurvivorData.AXIS_I18N_KEY.get(axis, "")))
			_buttons[i].text = "%s %s%s\n\n%s" % [axis_tag, cat_prefix, tr(choices[i]["name"]), tr(choices[i]["desc"])]

			# §5 稀有度边框 + 徽章（覆盖原 5 轴边框颜色，让稀有度成为主视觉）
			var rarity: int = SurvivorData.get_rarity(choices[i])
			var rarity_color: Color = SurvivorData.RARITY_COLORS[rarity] if rarity < SurvivorData.RARITY_COLORS.size() else Color.WHITE
			var rarity_label: String = ""
			if rarity < SurvivorData.RARITY_LABEL_KEYS.size():
				rarity_label = tr(SurvivorData.RARITY_LABEL_KEYS[rarity])
			# 高稀有度更粗边框，更醒目
			var border_w: int = 1 + clampi(rarity, 0, 4) / 2 + (1 if rarity >= SurvivorData.Rarity.CLASSIFIED else 0)

			var style_normal: StyleBoxFlat = _buttons[i].get_theme_stylebox("normal").duplicate()
			var style_hover: StyleBoxFlat = _buttons[i].get_theme_stylebox("hover").duplicate()
			# normal 用 70% 不透明的稀有度色，hover 满色 + 更粗
			style_normal.border_color = Color(rarity_color, 0.7)
			style_hover.border_color = rarity_color
			style_normal.set_border_width_all(border_w)
			style_hover.set_border_width_all(border_w + 1)
			# Next-Gen 给一点微微的发光底色（让"顶级"卡视觉就能区分）
			if rarity == SurvivorData.Rarity.NEXT_GEN:
				style_normal.bg_color = Color(rarity_color, 0.10).blend(style_normal.bg_color)
			_buttons[i].add_theme_stylebox_override("normal", style_normal)
			_buttons[i].add_theme_stylebox_override("hover", style_hover)

			# 徽章文本 + 边框颜色
			if i < _rarity_badges.size():
				var badge := _rarity_badges[i]
				badge.text = rarity_label
				badge.add_theme_color_override("font_color", rarity_color)
				badge.visible = rarity_label != ""
		else:
			_buttons[i].visible = false
			if i < _rarity_badges.size():
				_rarity_badges[i].visible = false
	visible = true

## 5 轴前缀（i18n key）
func _axis_prefix(axis: String) -> String:
	match axis:
		"survival": return tr("UPGRADE_AXIS_SURVIVAL_PREFIX")
		"mobility": return tr("UPGRADE_AXIS_MOBILITY_PREFIX")
		"missile": return tr("UPGRADE_AXIS_MISSILE_PREFIX")
		"secondary": return tr("UPGRADE_AXIS_SECONDARY_PREFIX")
		"electronic_warfare": return tr("UPGRADE_AXIS_EW_PREFIX")
		_: return ""

## 5 轴边框颜色 [normal, hover]
static func _axis_colors(axis: String) -> Array:
	match axis:
		"survival": return [Color(0.3, 0.6, 0.3, 0.5), Color(0.3, 1.0, 0.5, 0.8)]
		"mobility": return [Color(0.3, 0.5, 0.8, 0.5), Color(0.4, 0.7, 1.0, 0.8)]
		"missile": return [Color(0.8, 0.45, 0.2, 0.5), Color(1.0, 0.6, 0.3, 0.8)]
		"secondary": return [Color(0.8, 0.35, 0.35, 0.5), Color(1.0, 0.5, 0.4, 0.8)]
		"electronic_warfare": return [Color(0.6, 0.35, 0.7, 0.5), Color(0.8, 0.5, 1.0, 0.8)]
		_: return [Color(0.5, 0.5, 0.5, 0.5), Color(0.7, 0.7, 0.7, 0.8)]

func _on_choice_pressed(index: int) -> void:
	if index < _choices.size():
		upgrade_selected.emit(_choices[index])
	visible = false
