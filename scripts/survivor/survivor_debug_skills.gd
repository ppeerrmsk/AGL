class_name SurvivorDebugSkills
extends CanvasLayer

## F4 Debug 面板：查看/添加/移除技能，修改等级

var game_scene: Node2D  ## survivor_mode
var survivor_player: SurvivorPlayer

var _panel: PanelContainer
var _content: VBoxContainer
var _level_label: Label
var _level_input: SpinBox
var _skill_list: VBoxContainer
var _add_option: OptionButton
var _scroll: ScrollContainer

func _ready() -> void:
	layer = 30
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_build_ui()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_F4:
		visible = not visible
		if visible:
			_refresh()
			get_tree().paused = true
		else:
			get_tree().paused = false

func _build_ui() -> void:
	_panel = PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = ThemeColors.PANEL_BG_SOLID
	style.border_color = ThemeColors.PANEL_BORDER_DEBUG
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.set_content_margin_all(16)
	_panel.add_theme_stylebox_override("panel", style)
	_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_panel.custom_minimum_size = Vector2(460, 680)
	add_child(_panel)

	_content = VBoxContainer.new()
	_content.add_theme_constant_override("separation", 8)
	_panel.add_child(_content)

	# 标题
	var title := Label.new()
	title.text = "[ DEBUG — 技能管理 ]"
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", ThemeColors.TEXT_TITLE_GREEN)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_content.add_child(title)

	# 等级控制
	var level_row := HBoxContainer.new()
	level_row.add_theme_constant_override("separation", 10)
	_content.add_child(level_row)

	_level_label = Label.new()
	_level_label.text = "等级:"
	_level_label.add_theme_font_size_override("font_size", 14)
	_level_label.add_theme_color_override("font_color", ThemeColors.TEXT_PRIMARY_ALT)
	level_row.add_child(_level_label)

	_level_input = SpinBox.new()
	_level_input.min_value = 1
	_level_input.max_value = 100
	_level_input.value = 1
	_level_input.custom_minimum_size = Vector2(80, 0)
	level_row.add_child(_level_input)

	var level_btn := Button.new()
	level_btn.text = "设置等级"
	level_btn.pressed.connect(_on_set_level)
	_apply_btn_style(level_btn, Color(0.2, 0.5, 0.8))
	level_row.add_child(level_btn)

	var xp_label := Label.new()
	xp_label.text = "  "
	level_row.add_child(xp_label)

	var levelup_btn := Button.new()
	levelup_btn.text = "+1 升级"
	levelup_btn.pressed.connect(_on_levelup)
	_apply_btn_style(levelup_btn, Color(0.6, 0.5, 0.2))
	level_row.add_child(levelup_btn)

	# 分隔
	var sep := HSeparator.new()
	sep.add_theme_color_override("separator", ThemeColors.CARD_SEPARATOR_UNLOCKED)
	_content.add_child(sep)

	# 技能列表标题
	var skills_title := Label.new()
	skills_title.text = "所有技能（按轴分类）"
	skills_title.add_theme_font_size_override("font_size", 13)
	skills_title.add_theme_color_override("font_color", ThemeColors.TEXT_MUTED)
	_content.add_child(skills_title)

	# 技能列表（可滚动）
	_scroll = ScrollContainer.new()
	_scroll.custom_minimum_size = Vector2(0, 480)
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_content.add_child(_scroll)

	_skill_list = VBoxContainer.new()
	_skill_list.add_theme_constant_override("separation", 4)
	_skill_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_skill_list)

	# 分隔
	var sep2 := HSeparator.new()
	sep2.add_theme_color_override("separator", ThemeColors.CARD_SEPARATOR_UNLOCKED)
	_content.add_child(sep2)

	# 添加技能行
	var add_row := HBoxContainer.new()
	add_row.add_theme_constant_override("separation", 8)
	_content.add_child(add_row)

	var add_label := Label.new()
	add_label.text = "添加:"
	add_label.add_theme_font_size_override("font_size", 13)
	add_label.add_theme_color_override("font_color", ThemeColors.TEXT_PRIMARY_ALT)
	add_row.add_child(add_label)

	_add_option = OptionButton.new()
	_add_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_add_option.add_theme_font_size_override("font_size", 12)
	add_row.add_child(_add_option)

	var add_btn := Button.new()
	add_btn.text = "添加"
	add_btn.pressed.connect(_on_add_skill)
	_apply_btn_style(add_btn, Color(0.2, 0.7, 0.3))
	add_row.add_child(add_btn)

	# 底部提示
	var hint := Label.new()
	hint.text = "F4 关闭  |  修改即时生效"
	hint.add_theme_font_size_override("font_size", 11)
	hint.add_theme_color_override("font_color", Color(0.4, 0.5, 0.4, 0.5))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_content.add_child(hint)

func _apply_btn_style(btn: Button, accent: Color) -> void:
	btn.add_theme_font_size_override("font_size", 12)
	var s := StyleBoxFlat.new()
	s.bg_color = Color(accent.r * 0.3, accent.g * 0.3, accent.b * 0.3, 0.8)
	s.border_color = Color(accent, 0.5)
	s.set_border_width_all(1)
	s.set_corner_radius_all(3)
	s.set_content_margin_all(6)
	btn.add_theme_stylebox_override("normal", s)
	var h := s.duplicate()
	h.bg_color = Color(accent.r * 0.4, accent.g * 0.4, accent.b * 0.4, 0.9)
	h.border_color = Color(accent, 0.8)
	btn.add_theme_stylebox_override("hover", h)

## 5 轴显示顺序与中文标题
const _AXIS_ORDER: Array[String] = ["survival", "mobility", "missile", "secondary", "electronic_warfare"]
const _AXIS_TITLES := {
	"survival": "▸ 生存",
	"mobility": "▸ 机动",
	"missile": "▸ 导弹",
	"secondary": "▸ 副武器",
	"electronic_warfare": "▸ 电子战",
}
const _AXIS_COLORS := {
	"survival": Color(0.3, 0.7, 0.4),
	"mobility": Color(0.3, 0.6, 0.9),
	"missile": Color(0.9, 0.55, 0.25),
	"secondary": Color(0.9, 0.45, 0.45),
	"electronic_warfare": Color(0.7, 0.45, 0.85),
}

func _refresh() -> void:
	if not survivor_player or not game_scene:
		return

	_level_input.value = survivor_player.level

	# 清空技能列表
	for child in _skill_list.get_children():
		child.queue_free()

	var stacks: Dictionary = game_scene.upgrade_stacks
	var pid: StringName = game_scene._player_profile_id if game_scene else &""
	var p: AircraftParams = survivor_player.aircraft.params if survivor_player and survivor_player.aircraft else null

	# 按轴分桶（evolved 即战区奖励，也按轴归类但单独排在每个轴末尾）
	var buckets: Dictionary = {}
	for axis in _AXIS_ORDER:
		buckets[axis] = {"regular": [], "evolved": []}
	for u in SurvivorData.UPGRADES:
		var cat: String = u.get("category", "survival")
		if not buckets.has(cat):
			buckets[cat] = {"regular": [], "evolved": []}
		if u.get("evolved", false):
			buckets[cat]["evolved"].append(u)
		else:
			buckets[cat]["regular"].append(u)

	# 按轴顺序渲染
	for axis in _AXIS_ORDER:
		var bucket: Dictionary = buckets.get(axis, {"regular": [], "evolved": []})
		if bucket["regular"].is_empty() and bucket["evolved"].is_empty():
			continue

		# 轴标题
		var title := Label.new()
		title.text = _AXIS_TITLES.get(axis, axis)
		title.add_theme_font_size_override("font_size", 13)
		title.add_theme_color_override("font_color", _AXIS_COLORS.get(axis, Color.WHITE))
		_skill_list.add_child(title)

		# 常规技能
		for u in bucket["regular"]:
			_build_skill_row(u, stacks, pid, p, axis, false)
		# 战区奖励（细分隔）
		if not bucket["evolved"].is_empty():
			for u in bucket["evolved"]:
				_build_skill_row(u, stacks, pid, p, axis, true)

		# 轴间空隙
		var sp := Control.new()
		sp.custom_minimum_size = Vector2(0, 4)
		_skill_list.add_child(sp)

	# 隐藏旧的"添加"下拉（分轴列表已涵盖全部技能）
	_add_option.clear()
	_add_option.add_item("(已合并至上方列表)")
	_add_option.disabled = true

func _build_skill_row(u: Dictionary, stacks: Dictionary, pid: StringName, p: AircraftParams, axis: String, is_evolved: bool) -> void:
	var uid: String = u["id"]
	var count: int = stacks.get(uid, 0)
	var available: bool = SurvivorData.is_upgrade_available_for(u, pid, p)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	_skill_list.add_child(row)

	# 标签前缀（战区奖励 = ★，否则轴标签）
	var tag := Label.new()
	if is_evolved:
		tag.text = "  ★"
		tag.add_theme_color_override("font_color", Color(1.0, 0.8, 0.2))
	else:
		tag.text = "  •"
		tag.add_theme_color_override("font_color", _AXIS_COLORS.get(axis, Color.WHITE))
	tag.add_theme_font_size_override("font_size", 11)
	row.add_child(tag)

	# 名字 + 层数
	var name_label := Label.new()
	var text := "%s  %d/%d" % [tr(u["name"]), count, int(u["max_stacks"])]
	if not available:
		text += "  (不适配)"
	name_label.text = text
	name_label.add_theme_font_size_override("font_size", 12)
	if count > 0:
		name_label.add_theme_color_override("font_color", ThemeColors.TEXT_PRIMARY)
	elif available:
		name_label.add_theme_color_override("font_color", ThemeColors.TEXT_MUTED)
	else:
		name_label.add_theme_color_override("font_color", Color(0.5, 0.3, 0.3))
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_label)

	# +1 按钮
	var add_btn := Button.new()
	add_btn.text = " + "
	add_btn.custom_minimum_size = Vector2(30, 0)
	_apply_btn_style(add_btn, Color(0.2, 0.7, 0.3))
	if count >= int(u["max_stacks"]) or not available:
		add_btn.disabled = true
	else:
		var uid_add := uid
		add_btn.pressed.connect(func(): _on_add_skill_by_id(uid_add))
	row.add_child(add_btn)

	# -1 按钮（仅已有层数时）
	var remove_btn := Button.new()
	remove_btn.text = " - "
	remove_btn.custom_minimum_size = Vector2(30, 0)
	_apply_btn_style(remove_btn, Color(0.8, 0.2, 0.2))
	if count <= 0:
		remove_btn.disabled = true
	else:
		var uid_capture := uid
		remove_btn.pressed.connect(func(): _on_remove_skill(uid_capture))
	row.add_child(remove_btn)

func _on_set_level() -> void:
	if not survivor_player:
		return
	var target_level := int(_level_input.value)
	survivor_player.level = target_level
	survivor_player.xp = 0
	survivor_player.xp_to_next = SurvivorData.xp_for_level(target_level + 1)
	_refresh()

func _on_levelup() -> void:
	if not survivor_player:
		return
	survivor_player.level += 1
	survivor_player.xp = 0
	survivor_player.xp_to_next = SurvivorData.xp_for_level(survivor_player.level + 1)
	# 触发升级事件（弹出升级选择）
	survivor_player.leveled_up.emit(survivor_player.level)
	_refresh()

func _on_add_skill_by_id(uid: String) -> void:
	if not survivor_player or not game_scene:
		return
	for u in SurvivorData.UPGRADES:
		if u["id"] == uid:
			survivor_player.apply_upgrade(u)
			game_scene.upgrade_stacks[uid] = game_scene.upgrade_stacks.get(uid, 0) + 1
			break
	_refresh()

func _on_add_skill() -> void:
	if not survivor_player or not game_scene:
		return
	var idx := _add_option.selected
	if idx < 0:
		return
	var uid: String = _add_option.get_item_metadata(idx)

	# 查找升级定义
	for u in SurvivorData.UPGRADES:
		if u["id"] == uid:
			survivor_player.apply_upgrade(u)
			game_scene.upgrade_stacks[uid] = game_scene.upgrade_stacks.get(uid, 0) + 1
			break
	_refresh()

func _on_remove_skill(uid: String) -> void:
	if not game_scene:
		return
	var stacks: Dictionary = game_scene.upgrade_stacks
	var count: int = stacks.get(uid, 0)
	if count <= 0:
		return
	stacks[uid] = count - 1
	if stacks[uid] <= 0:
		stacks.erase(uid)
	# 注意：移除技能不会回退属性（需要重启才能真正还原）
	# 在面板上标注这一点
	_refresh()
