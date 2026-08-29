class_name SurvivorUpgradeUI
extends CanvasLayer

## 升级选择面板：基础三轴三选一；机体战术适配可稀有追加一张普通第四卡。
## 机体专属技能仍只在机场停靠二选一中取得。

signal upgrade_selected(upgrade: Dictionary)

const CARD_SIZE := Vector2(240, 300)
const CARD_GAP := 18
const NOTE_POPUP_SIZE := Vector2(244, 84)
const NOTE_POPUP_GAP := 28.0
## 弹窗刚出现时吞掉玩家上一拍仍在进行的点击，避免误选。
const INPUT_UNLOCK_DELAY_S := 0.80
## 确认后直接垂直压入底部槽位：无连线、无透明拖尾，只做快速形变。
const CONFIRM_INSERT_DURATION_S := 0.055
const CONFIRM_INSERT_SCALE := Vector2(0.86, 0.055)
const MEDIA_GLOW_SHADER: Shader = preload("res://resources/shaders/upgrade_media_glow.gdshader")
const UPGRADE_MEDIA_SURFACE_SCRIPT: Script = preload("res://scripts/survivor/upgrade_media_surface.gd")
const SURVIVOR_HUD_SCRIPT: Script = preload("res://scripts/survivor/survivor_hud.gd")
const INFO_FONT_SOURCE: FontFile = preload("res://resources/fonts/Silkscreen-Regular.ttf")
const DISPLAY_FONT_SOURCE: FontFile = preload("res://resources/fonts/ChakraPetch-Bold.ttf")

var _title: Label
var _btn_container: HBoxContainer
var _cards: Array[VBoxContainer] = []
var _buttons: Array[Button] = []
var _media_roots: Array[Control] = []
var _glow_panels: Array[ColorRect] = []
var _media_surfaces: Array = []
var _name_labels: Array[Label] = []
var _description_labels: Array[RichTextLabel] = []
var _note_popup_layer: Control
var _note_panels: Array[Panel] = []
var _scan_lines: Array[ColorRect] = []
## §5 稀有度徽章：每张卡片右上角悬浮的"STABLE / ADV / EXP / CLA / NEXT"标签
var _rarity_badges: Array[Label] = []
## 三轴归属徽章：每张卡片左上角的轴色 chip（"斗士 +1"，spec evolution-attribute-gates §3.1）
var _axis_badges: Array[Label] = []
## 机体战术适配第四卡的来源标识；不改写该卡自身稀有度视觉。
var _source_badges: Array[Label] = []
## 归属角标：每张卡片左下角（skills-720 §1.2：通用◈全队 / 品类限定 / 王牌 / 队级单件 + "+1 轴进度"）
var _scope_badges: Array[Label] = []
## 状态词条旁注：hover / focus 后在整组卡牌一侧浮现，解释 buff/debuff 本身干什么
## （0729；内容由 SurvivorData.status_notes_of + StatusEffects.NOTE_I18N_KEY 决定）
var _status_notes: Array[Label] = []
## CLASSIFIED 卡一次性入场闪边覆盖层。
var _flash_frames: Array[Panel] = []
var _choices: Array[Dictionary] = []
var _populate_generation: int = 0
var _hovered: Array[bool] = [false, false, false, false]
var _focused: Array[bool] = [false, false, false, false]
var _note_tweens: Array = [null, null, null, null]
var _selection_locked: bool = false
var _input_locked: bool = true

## 词条浮层文字色：比正文暗一档，不跟卡框/轴色抢视觉
const NOTE_COLOR := Color(0.62, 0.68, 0.74)
const FLASH_FIRST_CARD_DELAY_S := 0.42  ## upgrade_in: at .16 + title stagger .06 + elem .20
const FLASH_CARD_STAGGER_S := 0.06

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
	root.add_theme_constant_override("separation", 24)
	add_child(root)
	# 词条解释独立放到全屏旁注层，避免再覆盖介质标签正文。
	_note_popup_layer = Control.new()
	_note_popup_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_note_popup_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_note_popup_layer)

	# 上部空白
	var spacer_top := Control.new()
	spacer_top.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(spacer_top)

	# 标题
	_title = Label.new()
	_title.text = tr("UPGRADE_HEADER")
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_font_override("font", DISPLAY_FONT_SOURCE)
	_title.add_theme_font_size_override("font_size", 28)
	_title.add_theme_color_override("font_color", ThemeColors.TEXT_PRIMARY)
	root.add_child(_title)

	# 按钮容器
	_btn_container = HBoxContainer.new()
	_btn_container.alignment = BoxContainer.ALIGNMENT_CENTER
	_btn_container.add_theme_constant_override("separation", CARD_GAP)
	_btn_container.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	root.add_child(_btn_container)

	# 预建 4 个同尺寸介质按钮；普通轮次隐藏第四槽，机体适配命中时才显现。
	# 状态词条以固定覆盖层浮现，不参与 HBox 尺寸计算。
	for i in range(4):
		var card := VBoxContainer.new()
		card.custom_minimum_size = CARD_SIZE
		card.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		_btn_container.add_child(card)
		_cards.append(card)

		var btn := Button.new()
		btn.custom_minimum_size = CARD_SIZE
		btn.focus_mode = Control.FOCUS_ALL
		btn.clip_contents = false
		btn.text = ""
		for state in ["normal", "hover", "pressed", "focus", "disabled"]:
			var transparent_style := StyleBoxFlat.new()
			transparent_style.bg_color = Color.TRANSPARENT
			transparent_style.border_color = Color.TRANSPARENT
			transparent_style.set_content_margin_all(0)
			btn.add_theme_stylebox_override(state, transparent_style)

		var idx := i
		btn.pressed.connect(func(): _on_choice_pressed(idx))
		btn.mouse_entered.connect(func(): _set_card_hovered(idx, true))
		btn.mouse_exited.connect(func(): _set_card_hovered(idx, false))
		btn.focus_entered.connect(func(): _set_card_focused(idx, true))
		btn.focus_exited.connect(func(): _set_card_focused(idx, false))
		card.add_child(btn)
		_buttons.append(btn)

		var media_root := Control.new()
		media_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		media_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
		media_root.pivot_offset = CARD_SIZE * 0.5
		btn.add_child(media_root)
		_media_roots.append(media_root)

		# GPU halo 只覆盖 288×348 的三个小区域；用 TIME 驱动，不加 _process / queue_redraw。
		var glow := ColorRect.new()
		glow.position = Vector2(-24, -24)
		glow.size = CARD_SIZE + Vector2(48, 48)
		glow.color = Color.WHITE
		glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var glow_material := ShaderMaterial.new()
		glow_material.shader = MEDIA_GLOW_SHADER
		glow.material = glow_material
		media_root.add_child(glow)
		_glow_panels.append(glow)

		var surface: Variant = UPGRADE_MEDIA_SURFACE_SCRIPT.new()
		surface.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		surface.mouse_filter = Control.MOUSE_FILTER_IGNORE
		media_root.add_child(surface)
		_media_surfaces.append(surface)

		# 只画边框的覆盖层：Tween 动 alpha，不改按钮本体样式，hover 时也能看见闪光。
		var flash_frame := Panel.new()
		flash_frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		flash_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
		flash_frame.modulate.a = 0.0
		flash_frame.visible = false
		var flash_style := StyleBoxFlat.new()
		flash_style.bg_color = Color.TRANSPARENT
		flash_style.border_color = Color.WHITE
		flash_style.set_border_width_all(4)
		flash_frame.add_theme_stylebox_override("panel", flash_style)
		media_root.add_child(flash_frame)
		_flash_frames.append(flash_frame)

		# 入场时横扫介质的读写线，模拟机器突然识别到新软盘/光盘。
		var scan_line := ColorRect.new()
		scan_line.position = Vector2(10, 18)
		scan_line.size = Vector2(CARD_SIZE.x - 20, 3)
		scan_line.color = Color.WHITE
		scan_line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		scan_line.visible = false
		media_root.add_child(scan_line)
		_scan_lines.append(scan_line)

		# 稀有度与三轴归属印在介质标签第一行。
		var badge := Label.new()
		badge.text = ""
		badge.add_theme_font_override("font", INFO_FONT_SOURCE)
		badge.add_theme_font_size_override("font_size", 11)
		badge.add_theme_color_override("font_color", Color.WHITE)
		var badge_bg := StyleBoxFlat.new()
		badge_bg.bg_color = Color(0.0, 0.0, 0.0, 0.30)
		badge_bg.set_content_margin_all(2)
		badge.add_theme_stylebox_override("normal", badge_bg)
		badge.position = Vector2(137, 91)
		badge.size = Vector2(82, 18)
		badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		media_root.add_child(badge)
		_rarity_badges.append(badge)

		var axis_badge := Label.new()
		axis_badge.text = ""
		axis_badge.add_theme_font_override("font", INFO_FONT_SOURCE)
		axis_badge.add_theme_font_size_override("font_size", 11)
		var axis_bg := StyleBoxFlat.new()
		axis_bg.bg_color = Color(0.0, 0.0, 0.0, 0.22)
		axis_bg.set_content_margin_all(2)
		axis_bg.content_margin_left = 7.0
		axis_badge.add_theme_stylebox_override("normal", axis_bg)
		axis_badge.position = Vector2(22, 91)
		axis_badge.size = Vector2(110, 18)
		axis_badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		axis_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		media_root.add_child(axis_badge)
		_axis_badges.append(axis_badge)

		var source_badge := Label.new()
		source_badge.text = tr("AIRFRAME_AFFINITY_CARD_BADGE")
		source_badge.add_theme_font_override("font", INFO_FONT_SOURCE)
		source_badge.add_theme_font_size_override("font_size", 11)
		var source_bg := StyleBoxFlat.new()
		source_bg.bg_color = Color(0.01, 0.02, 0.025, 0.94)
		source_bg.set_border_width_all(1)
		source_bg.set_content_margin_all(2)
		source_badge.add_theme_stylebox_override("normal", source_bg)
		source_badge.position = Vector2(25, 64)
		source_badge.size = Vector2(190, 20)
		source_badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		source_badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		source_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		source_badge.visible = false
		media_root.add_child(source_badge)
		_source_badges.append(source_badge)

		var skill_name := Label.new()
		skill_name.position = Vector2(25, 116)
		skill_name.size = Vector2(190, 29)
		skill_name.add_theme_font_override("font", DISPLAY_FONT_SOURCE)
		skill_name.add_theme_font_size_override("font_size", 18)
		skill_name.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		skill_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		skill_name.mouse_filter = Control.MOUSE_FILTER_IGNORE
		media_root.add_child(skill_name)
		_name_labels.append(skill_name)

		var desc := RichTextLabel.new()
		desc.position = Vector2(25, 148)
		desc.size = Vector2(190, 68)
		desc.bbcode_enabled = true
		desc.fit_content = false
		desc.scroll_active = false
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc.add_theme_font_override("normal_font", DISPLAY_FONT_SOURCE)
		desc.add_theme_font_size_override("normal_font_size", 12)
		desc.mouse_filter = Control.MOUSE_FILTER_IGNORE
		media_root.add_child(desc)
		_description_labels.append(desc)

		# 限定信息固定印在标签底边。
		var scope_badge := Label.new()
		scope_badge.text = ""
		scope_badge.add_theme_font_override("font", INFO_FONT_SOURCE)
		scope_badge.add_theme_font_size_override("font_size", 10)
		scope_badge.position = Vector2(25, 219)
		scope_badge.size = Vector2(190, 18)
		scope_badge.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		scope_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		media_root.add_child(scope_badge)
		_scope_badges.append(scope_badge)

		# 状态词条解释默认隐藏；hover / focus 时在整组卡牌一侧横向滑出。
		var note_panel := Panel.new()
		note_panel.position = Vector2.ZERO
		note_panel.size = NOTE_POPUP_SIZE
		note_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		note_panel.modulate.a = 0.0
		note_panel.visible = false
		var note_style := StyleBoxFlat.new()
		note_style.bg_color = Color(0.01, 0.015, 0.025, 0.96)
		note_style.border_color = Color(NOTE_COLOR, 0.75)
		note_style.set_border_width_all(1)
		note_style.set_content_margin_all(8)
		note_panel.add_theme_stylebox_override("panel", note_style)
		_note_popup_layer.add_child(note_panel)
		_note_panels.append(note_panel)

		var note := Label.new()
		note.text = ""
		note.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		note.offset_left = 8
		note.offset_top = 7
		note.offset_right = -8
		note.offset_bottom = -7
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		note.add_theme_font_override("font", DISPLAY_FONT_SOURCE)
		note.add_theme_font_size_override("font_size", 11)
		note.add_theme_color_override("font_color", NOTE_COLOR)
		note.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		note.mouse_filter = Control.MOUSE_FILTER_IGNORE
		note_panel.add_child(note)
		_status_notes.append(note)

	# 下部空白
	var spacer_bottom := Control.new()
	spacer_bottom.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(spacer_bottom)

## 错开出入场的元素顺序（表演导演协议，spec ui-transition §4.3）。
## 遮罩不在此列——它归导演的全局压暗通道统一管
func get_transition_elements() -> Array[Control]:
	var out: Array[Control] = [_title]
	for i in range(_cards.size()):
		if not _buttons[i].visible:
			continue
		# 整列作为一个动画元素，按钮/背景/脚注同步入场；元素数为标题+当前可见卡。
		out.append(_cards[i])
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

## points_capped：三轴点数已封顶（spec evolution-attribute-gates §2.2 v9）——
## 选卡仍得技能但不再加点，徽章去掉"+1"避免撒谎
func populate(choices: Array[Dictionary], points_capped: bool = false) -> void:
	_populate_generation += 1
	_choices.clear()
	for choice in choices:
		if _choices.size() >= _buttons.size():
			push_error("SurvivorUpgradeUI 最多接受四张普通轴卡；多余候选已拒绝显示")
			break
		_choices.append(choice)
	_selection_locked = false
	_input_locked = true
	for i in range(_buttons.size()):
		_hovered[i] = false
		_focused[i] = false
		if i < _choices.size():
			var choice := _choices[i]
			var btn := _buttons[i]
			btn.visible = true
			btn.disabled = true
			btn.mouse_filter = Control.MOUSE_FILTER_STOP
			btn.custom_minimum_size = CARD_SIZE
			_media_roots[i].position = Vector2.ZERO
			_media_roots[i].scale = Vector2.ONE
			_media_roots[i].rotation = 0.0
			_media_roots[i].modulate = Color.WHITE
			var axis: StringName = SurvivorData.axis_of_upgrade(choice)
			var axis_color: Color = SurvivorData.AXIS_COLORS.get(axis, Color.WHITE)

			var rarity: int = SurvivorData.get_rarity(choice)
			var rarity_color: Color = SurvivorData.RARITY_COLORS[rarity] \
				if rarity < SurvivorData.RARITY_COLORS.size() else Color.WHITE
			var frame_color: Color = rarity_color
			_media_surfaces[i].configure(rarity, frame_color, false)
			_media_surfaces[i].set_selected(false)

			# 稀有度越高，介质后的 shader 辉光越强；低档软盘保持近乎实体材质。
			var glow_levels := [0.0, 0.07, 0.20, 0.58, 0.92]
			var glow_intensity: float = float(glow_levels[clampi(rarity, 0, glow_levels.size() - 1)])
			var glow_material := _glow_panels[i].material as ShaderMaterial
			glow_material.set_shader_parameter("glow_color", frame_color)
			glow_material.set_shader_parameter("intensity", glow_intensity)
			glow_material.set_shader_parameter("optical_mix", 1.0 if _media_surfaces[i].optical else 0.0)

			var light_label: bool = not bool(_media_surfaces[i].label_is_dark)
			var primary_text := Color(0.055, 0.06, 0.075) if light_label else Color(0.94, 0.96, 1.0)
			var secondary_text := Color(0.11, 0.12, 0.15, 0.96) if light_label else Color(0.73, 0.79, 0.88)
			_name_labels[i].text = tr(str(choice.get("name", "")))
			_name_labels[i].add_theme_color_override("font_color", primary_text)
			_description_labels[i].text = _description_bbcode(choice, secondary_text)
			if i < _axis_badges.size():
				var ab := _axis_badges[i]
				var axis_name := tr(str(SurvivorData.AXIS_I18N_KEY.get(axis, "")))
				ab.text = axis_name if points_capped else "%s +1" % axis_name
				var axis_display := axis_color
				if light_label:
					axis_display = axis_display.darkened(0.38)
				ab.add_theme_color_override("font_color", axis_display)
				var ab_bg: StyleBoxFlat = ab.get_theme_stylebox("normal")
				if ab_bg is StyleBoxFlat:
					var badge_color := axis_color
					ab_bg.border_color = badge_color
					ab_bg.border_width_left = 4
					ab_bg.bg_color = Color(badge_color.r, badge_color.g, badge_color.b, 0.12)
				ab.visible = true
			if i < _source_badges.size():
				var source_badge := _source_badges[i]
				var is_airframe_bonus := bool(choice.get("airframe_bonus_offer", false))
				source_badge.text = "◆ %s" % tr("AIRFRAME_AFFINITY_CARD_BADGE")
				source_badge.add_theme_color_override("font_color", axis_color.lightened(0.18))
				var source_style := source_badge.get_theme_stylebox("normal") as StyleBoxFlat
				source_style.border_color = Color(axis_color, 0.88)
				source_style.bg_color = Color(0.01, 0.02, 0.025, 0.94)
				source_badge.visible = is_airframe_bonus

			var rarity_label: String = ""
			if rarity < SurvivorData.RARITY_LABEL_KEYS.size():
				rarity_label = tr(SurvivorData.RARITY_LABEL_KEYS[rarity])
			if i < _rarity_badges.size():
				var badge := _rarity_badges[i]
				badge.text = rarity_label
				var badge_style := badge.get_theme_stylebox("normal") as StyleBoxFlat
				if light_label:
					# 浅色纸标签上使用实体深色铭牌，避免灰字叠灰底呈现为 disabled。
					badge_style.bg_color = Color(0.075, 0.085, 0.10, 0.94)
					badge_style.border_color = Color(rarity_color, 0.82)
					badge_style.set_border_width_all(1)
					badge.add_theme_color_override("font_color", rarity_color.lightened(0.62))
				else:
					badge_style.bg_color = Color(0.0, 0.0, 0.0, 0.42)
					badge_style.border_color = Color(rarity_color, 0.52)
					badge_style.set_border_width_all(1)
					badge.add_theme_color_override("font_color", rarity_color.lightened(0.10))
				badge.visible = rarity_label != ""

			# 归属角标（skills-720 §1.2）：通用◈全队 / 品类=系名+轴色 / 王牌金色 / 队级单件
			# + "+1 轴进度"提示（milestone_plus）
			if i < _scope_badges.size():
				var sb := _scope_badges[i]
				var parts: Array = []
				var sb_color := Color(0.72, 0.76, 0.8)
				var scope: String = SurvivorData.upgrade_scope(choice)
				var cls: Array = SurvivorData.upgrade_classes(choice)
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
				var mp: StringName = SurvivorData.milestone_plus_of(choice)
				if mp != &"":
					parts.append(tr("UPGRADE_MILESTONE_PLUS_FMT") % tr(str(SurvivorData.AXIS_I18N_KEY.get(mp, ""))))
				sb.text = " · ".join(PackedStringArray(parts))
				sb.add_theme_color_override("font_color", sb_color.darkened(0.42) if light_label else sb_color)
				sb.visible = true

			# 状态词条解释：先填内容，默认隐藏；hover / focus 再浮现。
			if i < _status_notes.size():
				var nb := _status_notes[i]
				var note_lines: Array = []
				for sid in SurvivorData.status_notes_of(choice):
					var nk: String = StatusEffects.note_i18n_key(sid)
					if nk != "":
						note_lines.append(tr(nk))
				nb.text = "\n".join(PackedStringArray(note_lines))
				_note_panels[i].visible = false
				_note_panels[i].modulate.a = 0.0
				_note_panels[i].position = Vector2.ZERO
				var note_style := _note_panels[i].get_theme_stylebox("panel") as StyleBoxFlat
				note_style.border_color = Color(frame_color, 0.86)

			if i < _flash_frames.size():
				_flash_frames[i].visible = false
				_flash_frames[i].modulate.a = 0.0
			if i < _scan_lines.size():
				_scan_lines[i].visible = false
				_scan_lines[i].modulate.a = 0.0
		else:
			_buttons[i].visible = false
			_buttons[i].disabled = true
			_buttons[i].mouse_filter = Control.MOUSE_FILTER_IGNORE
			if i < _status_notes.size():
				_status_notes[i].text = ""
				_note_panels[i].visible = false
			if i < _rarity_badges.size():
				_rarity_badges[i].visible = false
			if i < _axis_badges.size():
				_axis_badges[i].visible = false
			if i < _scope_badges.size():
				_scope_badges[i].visible = false
			if i < _source_badges.size():
				_source_badges[i].visible = false
		if i < _cards.size():
			_cards[i].visible = i < choices.size()
	_schedule_input_unlock()


## pause-process timer 让保护时间在游戏硬暂停期间仍正常流逝；generation 防旧弹窗回调串场。
func _schedule_input_unlock() -> void:
	if not is_inside_tree():
		return
	var generation := _populate_generation
	_begin_input_unlock_delay.call_deferred(generation)


func _begin_input_unlock_delay(generation: int) -> void:
	await get_tree().process_frame
	if generation != _populate_generation:
		return
	await get_tree().create_timer(INPUT_UNLOCK_DELAY_S, true, false, true).timeout
	if generation == _populate_generation and visible:
		_unlock_choice_input(generation)


func _unlock_choice_input(generation: int) -> void:
	if generation != _populate_generation or _selection_locked:
		return
	_input_locked = false
	for i in range(_buttons.size()):
		var enabled := i < _choices.size() and _buttons[i].visible
		_buttons[i].disabled = not enabled
		_buttons[i].mouse_filter = Control.MOUSE_FILTER_STOP if enabled else Control.MOUSE_FILTER_IGNORE
		if enabled:
			_refresh_card_active(i)



## 把明确标注的代价句单独染成 UI 规范危险红；普通效果仍按介质标签的明暗配色。
## warning_sentence_count 是纯展示元数据，不用文本关键词猜测，避免把“不可被命中”误判为警告。
func _description_bbcode(choice: Dictionary, normal_color: Color) -> String:
	var raw := tr(str(choice.get("desc", "")))
	var warning_count := maxi(0, int(choice.get("warning_sentence_count", 0)))
	var escaped := _escape_bbcode(raw)
	if warning_count == 0 or raw == "":
		return "[color=#%s]%s[/color]" % [normal_color.to_html(false), escaped]
	var split_at := _warning_prefix_length(raw, warning_count)
	var warning_text := _escape_bbcode(raw.substr(0, split_at))
	var normal_text := _escape_bbcode(raw.substr(split_at))
	return "[color=#%s]%s[/color][color=#%s]%s[/color]" % [
		ThemeColors.UI_DANGER_RED.to_html(false), warning_text,
		normal_color.to_html(false), normal_text,
	]


func _warning_prefix_length(text: String, sentence_count: int) -> int:
	var cursor := 0
	for _sentence in range(sentence_count):
		var full_stop := text.find("。", cursor)
		var period := text.find(". ", cursor)
		var boundary := -1
		var advance := 1
		if full_stop >= 0:
			boundary = full_stop
		if period >= 0 and (boundary < 0 or period < boundary):
			boundary = period
			advance = 2
		if boundary < 0:
			return text.length()
		cursor = boundary + advance
	return cursor


func _escape_bbcode(text: String) -> String:
	return text.replace("[", "[lb]")


func _set_card_hovered(index: int, value: bool) -> void:
	if index < 0 or index >= _hovered.size():
		return
	_hovered[index] = value
	_refresh_card_active(index)


func _set_card_focused(index: int, value: bool) -> void:
	if index < 0 or index >= _focused.size():
		return
	_focused[index] = value
	_refresh_card_active(index)


func _refresh_card_active(index: int) -> void:
	if index < 0 or index >= _buttons.size() or not _buttons[index].visible:
		return
	var active := (_hovered[index] or _focused[index]) and not _selection_locked and not _input_locked
	_media_surfaces[index].set_selected(active)
	_media_roots[index].scale = Vector2(1.018, 1.018) if active else Vector2.ONE
	_set_note_revealed(index, active)


func _set_note_revealed(index: int, revealed: bool) -> void:
	if index < 0 or index >= _status_notes.size():
		return
	var panel := _note_panels[index]
	var old_tween: Variant = _note_tweens[index]
	if old_tween is Tween:
		(old_tween as Tween).kill()
	_note_tweens[index] = null
	if _status_notes[index].text == "":
		panel.visible = false
		return
	if not is_inside_tree():
		panel.visible = revealed
		panel.modulate.a = 1.0 if revealed else 0.0
		return
	var target_position := _note_popup_position(index)
	var hidden_position := _note_popup_hidden_position(target_position)
	var tween := create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_note_tweens[index] = tween
	if revealed:
		# 键盘 focus 与鼠标 hover 可能短暂指向不同卡；旁注层始终只显示最新一张。
		for other_index in range(_note_panels.size()):
			if other_index == index:
				continue
			var other_tween: Variant = _note_tweens[other_index]
			if other_tween is Tween:
				(other_tween as Tween).kill()
				_note_tweens[other_index] = null
			_note_panels[other_index].visible = false
		if not panel.visible:
			panel.position = hidden_position
		panel.visible = true
		tween.set_parallel(true)
		tween.tween_property(panel, "modulate:a", 1.0, 0.14).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tween.tween_property(panel, "position", target_position, 0.14).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	else:
		tween.set_parallel(true)
		tween.tween_property(panel, "modulate:a", 0.0, 0.10).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tween.tween_property(panel, "position", hidden_position, 0.10).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tween.chain().tween_callback(func() -> void:
			if is_instance_valid(panel) and panel.modulate.a <= 0.01:
				panel.visible = false
			_note_tweens[index] = null)


func _note_popup_position(index: int) -> Vector2:
	var viewport_size := get_viewport().get_visible_rect().size
	var row_rect := _btn_container.get_global_rect()
	var card_rect := _buttons[index].get_global_rect()
	var right_x := row_rect.end.x + NOTE_POPUP_GAP
	var left_x := row_rect.position.x - NOTE_POPUP_SIZE.x - NOTE_POPUP_GAP
	var x := right_x
	if right_x + NOTE_POPUP_SIZE.x > viewport_size.x - 16.0 and left_x >= 16.0:
		x = left_x
	elif right_x + NOTE_POPUP_SIZE.x > viewport_size.x - 16.0:
		x = clampf(card_rect.end.x + NOTE_POPUP_GAP, 16.0,
			viewport_size.x - NOTE_POPUP_SIZE.x - 16.0)
	var y := clampf(card_rect.position.y + 112.0, 16.0,
		viewport_size.y - NOTE_POPUP_SIZE.y - 16.0)
	return Vector2(x, y)


func _note_popup_hidden_position(target_position: Vector2) -> Vector2:
	var row_center_x := _btn_container.get_global_rect().get_center().x
	var toward_cards := -12.0 if target_position.x > row_center_x else 12.0
	return target_position + Vector2(toward_cards, 0)


func _play_media_boot(index: int) -> void:
	if index < 0 or index >= _scan_lines.size() or not _buttons[index].visible:
		return
	var line := _scan_lines[index]
	var choice := _choices[index]
	line.color = entry_flash_color(choice)
	line.position = Vector2(10, 18)
	line.modulate.a = 0.0
	line.visible = true
	var tween := create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.set_parallel(true)
	tween.tween_property(line, "position:y", CARD_SIZE.y - 24.0, 0.26).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tween.tween_property(line, "modulate:a", 0.92, 0.06).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.chain().tween_property(line, "modulate:a", 0.0, 0.16)
	tween.chain().tween_callback(func() -> void:
		if is_instance_valid(line):
			line.visible = false)

## upgrade_in 的每张卡完成错开入场后，CLASSIFIED 卡闪边一次。
## SceneTreeTimer 与 Tween 都设为 pause-process，硬暂停期间照常播放；generation 防旧弹窗回调串场。
func schedule_entry_flashes() -> void:
	if not is_inside_tree():
		return
	var generation := _populate_generation
	_schedule_entry_flashes_deferred.call_deferred(generation)

func _schedule_entry_flashes_deferred(generation: int) -> void:
	await get_tree().process_frame
	if generation != _populate_generation:
		return
	for i in range(_choices.size()):
		var idx := i
		var timer := get_tree().create_timer(
			FLASH_FIRST_CARD_DELAY_S + FLASH_CARD_STAGGER_S * float(i), true, false, true)
		timer.timeout.connect(func() -> void:
			if generation == _populate_generation and visible:
				_play_media_boot(idx)
				if idx < _choices.size() and should_flash_entry(_choices[idx]):
					_play_border_flash(idx))

func _play_border_flash(index: int) -> void:
	if index < 0 or index >= _choices.size() or index >= _flash_frames.size():
		return
	var choice: Dictionary = _choices[index]
	var rarity := SurvivorData.get_rarity(choice)
	var color := entry_flash_color(choice)
	var normal_w: int = 1 + clampi(rarity, 0, 4) / 2 \
		+ (1 if rarity >= SurvivorData.Rarity.CLASSIFIED else 0)
	var frame := _flash_frames[index]
	var style := frame.get_theme_stylebox("panel") as StyleBoxFlat
	style.border_color = color
	style.set_border_width_all(normal_w + 2)
	frame.modulate.a = 0.0
	frame.visible = true
	var tween := create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_property(frame, "modulate:a", 1.0, 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_interval(0.10)
	tween.tween_property(frame, "modulate:a", 0.0, 0.33).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	tween.finished.connect(func() -> void:
		if is_instance_valid(frame):
			frame.visible = false)

static func should_flash_entry(choice: Dictionary) -> bool:
	return SurvivorData.get_rarity(choice) == SurvivorData.Rarity.CLASSIFIED

static func entry_flash_color(choice: Dictionary) -> Color:
	var rarity := SurvivorData.get_rarity(choice)
	return SurvivorData.RARITY_COLORS[rarity] if rarity < SurvivorData.RARITY_COLORS.size() \
		else Color.WHITE

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
	if index < 0 or index >= _choices.size() or _selection_locked or _input_locked:
		return
	_selection_locked = true
	_populate_generation += 1  # 取消尚未开始的入场闪边 timer
	var selected_choice := _choices[index]
	for btn in _buttons:
		btn.disabled = true
		btn.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_media_surfaces[index].set_selected(true)
	_set_note_revealed(index, false)
	if not is_inside_tree():
		upgrade_selected.emit(selected_choice)
		return
	# 不建立连线、不淡出：卡带保持实体，垂直压入底部成长槽并压成薄片。
	var media := _media_roots[index]
	var start_position := media.position
	var card_center := media.get_global_rect().get_center()
	var viewport_size := get_viewport().get_visible_rect().size
	var slot_center_y: float = float(
		SURVIVOR_HUD_SCRIPT.bottom_axis_rect(viewport_size).get_center().y)
	var target_position := start_position + Vector2(0, slot_center_y - card_center.y)
	media.modulate.a = 1.0
	var insert_tween := create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	insert_tween.set_parallel(true)
	insert_tween.tween_property(media, "position", target_position,
		CONFIRM_INSERT_DURATION_S).set_trans(Tween.TRANS_LINEAR)
	insert_tween.tween_property(media, "scale", CONFIRM_INSERT_SCALE,
		CONFIRM_INSERT_DURATION_S).set_trans(Tween.TRANS_LINEAR)
	insert_tween.finished.connect(func() -> void:
		upgrade_selected.emit(selected_choice))
