class_name SurvivorUpgradeUI
extends CanvasLayer

## 升级选择面板：暂停时显示3个升级选项

signal upgrade_selected(upgrade: Dictionary)

var _title: Label
var _btn_container: HBoxContainer
var _buttons: Array[Button] = []
## §5 稀有度徽章：每张卡片右上角悬浮的"STABLE / ADV / EXP / CLA / NEXT"标签
var _rarity_badges: Array[Label] = []
## 三轴归属徽章：每张卡片左上角的轴色 chip（"斗士 +1"，spec evolution-attribute-gates §3.1）
var _axis_badges: Array[Label] = []
## 归属角标：每张卡片左下角（skills-720 §1.2：通用◈全队 / 品类限定 / 王牌 / 队级单件 + "+1 轴进度"）
var _scope_badges: Array[Label] = []
var _choices: Array[Dictionary] = []

func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_build_ui()

func _build_ui() -> void:
	# 遮罩已收归表演导演的全局压暗层（CanvasLayer 16，spec ui-transition §2.1）——
	# 面板不再自持 ColorRect，避免两套遮罩打架、也让无线电条不被一起压暗

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

		# 三轴归属徽章：左上角轴色 chip——大一号字 + 轴色左粗边 + 轴色文字，
		# "属于哪个轴"一眼可辨（2026-07-19 用户令；颜色 = SurvivorData.AXIS_COLORS）
		var axis_badge := Label.new()
		axis_badge.text = ""
		axis_badge.add_theme_font_size_override("font_size", 15)
		var axis_bg := StyleBoxFlat.new()
		axis_bg.bg_color = Color(0.0, 0.0, 0.0, 0.6)
		axis_bg.set_corner_radius_all(3)
		axis_bg.set_content_margin_all(4)
		axis_bg.content_margin_left = 8.0
		axis_badge.add_theme_stylebox_override("normal", axis_bg)
		axis_badge.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
		axis_badge.position = Vector2(6, 6)
		axis_badge.size = Vector2(108, 22)
		axis_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		btn.add_child(axis_badge)
		_axis_badges.append(axis_badge)

		# 归属角标：左下角小标签——"这条强化谁吃得到"选卡时可见（skills-720 §1.2）
		var scope_badge := Label.new()
		scope_badge.text = ""
		scope_badge.add_theme_font_size_override("font_size", 11)
		var scope_bg := StyleBoxFlat.new()
		scope_bg.bg_color = Color(0.0, 0.0, 0.0, 0.55)
		scope_bg.set_corner_radius_all(3)
		scope_bg.set_content_margin_all(4)
		scope_badge.add_theme_stylebox_override("normal", scope_bg)
		scope_badge.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
		scope_badge.position = Vector2(6, -26)
		scope_badge.size = Vector2(200, 18)
		scope_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		btn.add_child(scope_badge)
		_scope_badges.append(scope_badge)

	# 下部空白
	var spacer_bottom := Control.new()
	spacer_bottom.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(spacer_bottom)

## 错开出入场的元素顺序（表演导演协议，spec ui-transition §4.3）。
## 遮罩不在此列——它归导演的全局压暗通道统一管
func get_transition_elements() -> Array[Control]:
	var out: Array[Control] = [_title]
	for b in _buttons:
		if b.visible:
			out.append(b)
	return out

## 只填内容、【不负责显示】——显示与入场动画由 Presentation.present() 驱动。
## 旧的 show_choices() 保留为兼容入口（内部 populate + 直接 visible），
## 供无导演场景（bench / 单测）使用
func show_choices(choices: Array[Dictionary]) -> void:
	populate(choices)
	# 重置导演退场时留下的 alpha/scale —— 否则上一轮 dismiss 把元素压到 alpha 0 后，
	# 这条无导演路径会显示一个"空面板"
	_reset_transition_state()
	visible = true

## 把出入场动画改过的属性恢复原状（无导演路径 / 异常兜底用）
func _reset_transition_state() -> void:
	for c in get_transition_elements():
		c.modulate.a = 1.0
		c.scale = Vector2.ONE

func populate(choices: Array[Dictionary]) -> void:
	_choices = choices
	for i in range(3):
		if i < choices.size():
			_buttons[i].visible = true
			var cat: String = choices[i].get("category", "")
			var cat_prefix := _axis_prefix(cat)
			# 轴归属交给左上角轴色徽章（大字+轴色），正文不再重复轴名——首行留白给徽章行
			var axis: StringName = SurvivorData.axis_of_upgrade(choices[i])
			var axis_color: Color = SurvivorData.AXIS_COLORS.get(axis, Color.WHITE)
			_buttons[i].text = "\n%s%s\n\n%s" % [cat_prefix, tr(choices[i]["name"]), tr(choices[i]["desc"])]
			if i < _axis_badges.size():
				var ab := _axis_badges[i]
				ab.text = "%s +1" % tr(str(SurvivorData.AXIS_I18N_KEY.get(axis, "")))
				ab.add_theme_color_override("font_color", axis_color)
				var ab_bg: StyleBoxFlat = ab.get_theme_stylebox("normal")
				if ab_bg is StyleBoxFlat:
					ab_bg.border_color = axis_color
					ab_bg.border_width_left = 4
					ab_bg.bg_color = Color(axis_color.r, axis_color.g, axis_color.b, 0.14)
				ab.visible = true

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

			# 归属角标（skills-720 §1.2）：通用◈全队 / 品类=系名+轴色 / 王牌金色 / 队级单件
			# + "+1 轴进度"提示（milestone_plus）
			if i < _scope_badges.size():
				var sb := _scope_badges[i]
				var parts: Array = []
				var sb_color := Color(0.72, 0.76, 0.8)
				var scope: String = SurvivorData.upgrade_scope(choices[i])
				var cls: Array = SurvivorData.upgrade_classes(choices[i])
				if scope == "ace":
					sb_color = Color(1.0, 0.84, 0.3)
					parts.append(tr("UPGRADE_SCOPE_ACE"))
				elif scope == "squad_once":
					sb_color = Color(0.5, 0.85, 0.95)
					parts.append(tr("UPGRADE_SCOPE_SQUAD_ONCE"))
				if not cls.is_empty():
					var cls_names: Array = []
					for c in cls:
						cls_names.append(tr(str(SurvivorData.AXIS_I18N_KEY.get(StringName(str(c)), ""))))
					if scope != "ace":
						sb_color = SurvivorData.AXIS_COLORS.get(StringName(str(cls[0])), sb_color)
					parts.append(tr("UPGRADE_CLASS_LIMITED_FMT") % "/".join(PackedStringArray(cls_names)))
				if parts.is_empty():
					parts.append(tr("UPGRADE_SCOPE_SQUAD"))
				var mp: StringName = SurvivorData.milestone_plus_of(choices[i])
				if mp != &"":
					parts.append(tr("UPGRADE_MILESTONE_PLUS_FMT") % tr(str(SurvivorData.AXIS_I18N_KEY.get(mp, ""))))
				sb.text = " · ".join(PackedStringArray(parts))
				sb.add_theme_color_override("font_color", sb_color)
				sb.visible = true
		else:
			_buttons[i].visible = false
			if i < _rarity_badges.size():
				_rarity_badges[i].visible = false
			if i < _axis_badges.size():
				_axis_badges[i].visible = false
			if i < _scope_badges.size():
				_scope_badges[i].visible = false

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

## 只发信号，【不自己隐藏】——退场由 survivor_mode 走 Presentation.dismiss() 驱动。
## 若无导演（bench / 单测），survivor_mode 的兜底分支会直接置 visible = false
func _on_choice_pressed(index: int) -> void:
	if index < _choices.size():
		upgrade_selected.emit(_choices[index])
