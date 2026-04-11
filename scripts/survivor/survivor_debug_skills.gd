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
	style.bg_color = Color(0.02, 0.04, 0.02, 0.95)
	style.border_color = Color(0.3, 0.8, 0.3, 0.6)
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.set_content_margin_all(16)
	_panel.add_theme_stylebox_override("panel", style)
	_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_panel.custom_minimum_size = Vector2(420, 500)
	add_child(_panel)

	_content = VBoxContainer.new()
	_content.add_theme_constant_override("separation", 8)
	_panel.add_child(_content)

	# 标题
	var title := Label.new()
	title.text = "[ DEBUG — 技能管理 ]"
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", Color(0.4, 1.0, 0.4))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_content.add_child(title)

	# 等级控制
	var level_row := HBoxContainer.new()
	level_row.add_theme_constant_override("separation", 10)
	_content.add_child(level_row)

	_level_label = Label.new()
	_level_label.text = "等级:"
	_level_label.add_theme_font_size_override("font_size", 14)
	_level_label.add_theme_color_override("font_color", Color(0.8, 0.9, 0.8))
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
	sep.add_theme_color_override("separator", Color(0.3, 0.5, 0.3, 0.3))
	_content.add_child(sep)

	# 已有技能标题
	var skills_title := Label.new()
	skills_title.text = "已激活技能"
	skills_title.add_theme_font_size_override("font_size", 13)
	skills_title.add_theme_color_override("font_color", Color(0.6, 0.8, 0.6, 0.7))
	_content.add_child(skills_title)

	# 技能列表（可滚动）
	_scroll = ScrollContainer.new()
	_scroll.custom_minimum_size = Vector2(0, 240)
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_content.add_child(_scroll)

	_skill_list = VBoxContainer.new()
	_skill_list.add_theme_constant_override("separation", 4)
	_skill_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_skill_list)

	# 分隔
	var sep2 := HSeparator.new()
	sep2.add_theme_color_override("separator", Color(0.3, 0.5, 0.3, 0.3))
	_content.add_child(sep2)

	# 添加技能行
	var add_row := HBoxContainer.new()
	add_row.add_theme_constant_override("separation", 8)
	_content.add_child(add_row)

	var add_label := Label.new()
	add_label.text = "添加:"
	add_label.add_theme_font_size_override("font_size", 13)
	add_label.add_theme_color_override("font_color", Color(0.8, 0.9, 0.8))
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

func _refresh() -> void:
	if not survivor_player or not game_scene:
		return

	_level_input.value = survivor_player.level

	# 清空技能列表
	for child in _skill_list.get_children():
		child.queue_free()

	# 填充已有技能
	var stacks: Dictionary = game_scene.upgrade_stacks
	for u in SurvivorData.UPGRADES:
		var uid: String = u["id"]
		var count: int = stacks.get(uid, 0)
		if count <= 0:
			continue

		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		_skill_list.add_child(row)

		var cat: String = u.get("category", "")
		var is_evolved: bool = u.get("evolved", false)
		var is_exclusive: bool = (u.get("exclusive_to", null) != null) and (u["exclusive_to"].size() > 0)
		var cat_color: Color
		var tag_text: String
		if is_evolved:
			cat_color = Color(1.0, 0.8, 0.2)
			tag_text = "[★]"
		elif is_exclusive:
			cat_color = Color(0.4, 0.8, 1.0)
			tag_text = "[专]"
		elif cat == "combat":
			cat_color = Color(0.8, 0.4, 0.3)
			tag_text = "[战]"
		else:
			cat_color = Color(0.3, 0.7, 0.4)
			tag_text = "[存]"

		var tag := Label.new()
		tag.text = tag_text
		tag.add_theme_font_size_override("font_size", 11)
		tag.add_theme_color_override("font_color", cat_color)
		row.add_child(tag)

		var name_label := Label.new()
		name_label.text = "%s  x%d / %d" % [u["name"], count, int(u["max_stacks"])]
		name_label.add_theme_font_size_override("font_size", 13)
		name_label.add_theme_color_override("font_color", Color(0.85, 0.9, 0.85))
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name_label)

		# +1 层按钮（未满时可用）
		var add_btn := Button.new()
		add_btn.text = " + "
		add_btn.custom_minimum_size = Vector2(30, 0)
		_apply_btn_style(add_btn, Color(0.2, 0.7, 0.3))
		var uid_add := uid
		if count >= int(u["max_stacks"]):
			add_btn.disabled = true
		else:
			add_btn.pressed.connect(func(): _on_add_skill_by_id(uid_add))
		row.add_child(add_btn)

		var remove_btn := Button.new()
		remove_btn.text = " - "
		remove_btn.custom_minimum_size = Vector2(30, 0)
		_apply_btn_style(remove_btn, Color(0.8, 0.2, 0.2))
		var uid_capture := uid
		remove_btn.pressed.connect(func(): _on_remove_skill(uid_capture))
		row.add_child(remove_btn)

	# 填充可添加的技能下拉（仅显示当前主角实际可获取的）
	_add_option.clear()
	var pid: StringName = game_scene._player_profile_id if game_scene else &""
	var p: AircraftParams = survivor_player.aircraft.params if survivor_player and survivor_player.aircraft else null
	for u in SurvivorData.UPGRADES:
		var uid: String = u["id"]
		var count: int = stacks.get(uid, 0)
		if count >= int(u["max_stacks"]):
			continue
		# 应用与正式升级池相同的硬件 / 专属筛选
		if not SurvivorData.is_upgrade_available_for(u, pid, p):
			continue
		_add_option.add_item("%s (%s)" % [u["name"], u["desc"]], _add_option.item_count)
		_add_option.set_item_metadata(_add_option.item_count - 1, uid)

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
