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

## 装备装载替换面板：每个槽位的 OptionButton 引用，便于 _refresh_loadout 同步选中项
var _loadout_panel: PanelContainer       ## 屏幕左侧独立面板（与中央 F4 面板同步显隐）
var _loadout_section: VBoxContainer
var _loadout_options: Dictionary = {}   ## slot_key -> OptionButton

## §7.5 实时状态面板（active effects / attributes / pity / steering）
## 每 0.25s 由 _process 刷新一次（仅在 visible 时）
var _live_label: RichTextLabel
var _live_refresh_timer: float = 0.0
const LIVE_REFRESH_INTERVAL: float = 0.25

## 即时 tooltip（替代 Godot 默认 0.5s 延迟）
var _hover_tip: PanelContainer
var _hover_tip_label: Label

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
			_refresh_live_state()
			get_tree().paused = true
		else:
			get_tree().paused = false


## §7.5 实时刷新：仅在面板可见且未暂停时跑（暂停时数据不变化，但首次打开会刷一次）
func _process(delta: float) -> void:
	if not visible:
		return
	_live_refresh_timer += delta
	if _live_refresh_timer >= LIVE_REFRESH_INTERVAL:
		_live_refresh_timer = 0.0
		_refresh_live_state()
	# 让 hover tip 跟随鼠标
	if _hover_tip and _hover_tip.visible:
		_position_hover_tip()

func _on_hover_show(text: String) -> void:
	if _hover_tip == null:
		return
	_hover_tip_label.text = text
	_hover_tip.visible = true
	_position_hover_tip()

func _on_hover_hide() -> void:
	if _hover_tip:
		_hover_tip.visible = false

func _position_hover_tip() -> void:
	var mp: Vector2 = get_viewport().get_mouse_position()
	var vp_size: Vector2 = get_viewport().get_visible_rect().size
	var tip_size: Vector2 = _hover_tip.size
	# 默认放在鼠标右下方 16px 偏移；超出右/下边缘则翻转到左/上
	var pos := mp + Vector2(16, 16)
	if pos.x + tip_size.x > vp_size.x:
		pos.x = mp.x - tip_size.x - 8
	if pos.y + tip_size.y > vp_size.y:
		pos.y = mp.y - tip_size.y - 8
	_hover_tip.position = pos

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

	# §7.5 实时状态面板（active effects / attributes / pity / steering）
	var live_title := Label.new()
	live_title.text = "[ 实时状态（每 0.25s 刷新） ]"
	live_title.add_theme_font_size_override("font_size", 12)
	live_title.add_theme_color_override("font_color", ThemeColors.TEXT_MUTED)
	_content.add_child(live_title)

	_live_label = RichTextLabel.new()
	_live_label.bbcode_enabled = true
	_live_label.fit_content = true
	_live_label.scroll_active = false
	_live_label.custom_minimum_size = Vector2(0, 130)
	_live_label.add_theme_font_size_override("normal_font_size", 11)
	_content.add_child(_live_label)

	var sep15 := HSeparator.new()
	sep15.add_theme_color_override("separator", ThemeColors.CARD_SEPARATOR_UNLOCKED)
	_content.add_child(sep15)

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

	# 状态效果测试行（buff / debuff 8 秒）
	var status_sep := HSeparator.new()
	status_sep.add_theme_color_override("separator", ThemeColors.CARD_SEPARATOR_UNLOCKED)
	_content.add_child(status_sep)
	var status_label := Label.new()
	status_label.text = "状态测试（点击施加 8 秒到玩家）"
	status_label.add_theme_font_size_override("font_size", 12)
	status_label.add_theme_color_override("font_color", ThemeColors.TEXT_MUTED)
	_content.add_child(status_label)
	var status_row := HBoxContainer.new()
	status_row.add_theme_constant_override("separation", 4)
	_content.add_child(status_row)
	for sid in StatusEffects.DISPLAY_ORDER:
		var btn := Button.new()
		btn.text = _status_label_for(sid)
		btn.pressed.connect(_on_apply_status.bind(sid))
		_apply_btn_style(btn, StatusEffects.icon_color(sid))
		status_row.add_child(btn)
	var clear_btn := Button.new()
	clear_btn.text = "清"
	clear_btn.pressed.connect(_on_clear_statuses)
	_apply_btn_style(clear_btn, Color(0.5, 0.5, 0.5))
	status_row.add_child(clear_btn)

	# 底部提示
	var hint := Label.new()
	hint.text = "F4 关闭  |  修改即时生效"
	hint.add_theme_font_size_override("font_size", 11)
	hint.add_theme_color_override("font_color", Color(0.4, 0.5, 0.4, 0.5))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_content.add_child(hint)

	# 即时 tooltip（CanvasLayer 顶层，鼠标悬停立即显示）
	_hover_tip = PanelContainer.new()
	var tip_style := StyleBoxFlat.new()
	tip_style.bg_color = Color(0.05, 0.08, 0.05, 0.95)
	tip_style.border_color = ThemeColors.PANEL_BORDER_DEBUG
	tip_style.set_border_width_all(1)
	tip_style.set_corner_radius_all(3)
	tip_style.set_content_margin_all(8)
	_hover_tip.add_theme_stylebox_override("panel", tip_style)
	_hover_tip.visible = false
	_hover_tip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hover_tip.top_level = true
	_hover_tip.z_index = 100
	add_child(_hover_tip)

	_hover_tip_label = Label.new()
	_hover_tip_label.add_theme_font_size_override("font_size", 12)
	_hover_tip_label.add_theme_color_override("font_color", ThemeColors.TEXT_PRIMARY)
	_hover_tip_label.custom_minimum_size = Vector2(280, 0)
	_hover_tip_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hover_tip.add_child(_hover_tip_label)

	# ── 装备装载独立面板（屏幕左侧，与中央面板同步显隐）──
	_build_loadout_panel()


## 屏幕左侧独立面板：装备装载切换（机炮 + 主导弹固定不可换）
func _build_loadout_panel() -> void:
	_loadout_panel = PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = ThemeColors.PANEL_BG_SOLID
	style.border_color = ThemeColors.PANEL_BORDER_DEBUG
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.set_content_margin_all(12)
	_loadout_panel.add_theme_stylebox_override("panel", style)
	# 锚定屏幕左侧居中（垂直）
	# 锚点在屏幕左边 + 上下居中：左 16px 起，宽 380，高 ~340
	_loadout_panel.anchor_left = 0.0
	_loadout_panel.anchor_right = 0.0
	_loadout_panel.anchor_top = 0.5
	_loadout_panel.anchor_bottom = 0.5
	_loadout_panel.offset_left = 16.0
	_loadout_panel.offset_right = 16.0 + 380.0   # 左 16 + 宽 380 = 右 396
	_loadout_panel.offset_top = -180.0
	_loadout_panel.offset_bottom = 180.0
	add_child(_loadout_panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	_loadout_panel.add_child(box)

	var title := Label.new()
	title.text = "[ 装备装载 ]"
	title.add_theme_font_size_override("font_size", 14)
	title.add_theme_color_override("font_color", ThemeColors.TEXT_TITLE_GREEN)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)

	var hint := Label.new()
	hint.text = "机炮 + 主导弹固定，其余可换"
	hint.add_theme_font_size_override("font_size", 10)
	hint.add_theme_color_override("font_color", ThemeColors.TEXT_MUTED)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(hint)

	var sep := HSeparator.new()
	sep.add_theme_color_override("separator", ThemeColors.CARD_SEPARATOR_UNLOCKED)
	box.add_child(sep)

	_loadout_section = VBoxContainer.new()
	_loadout_section.add_theme_constant_override("separation", 4)
	box.add_child(_loadout_section)

	_build_loadout_rows()

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

	# 装备装载 OptionButton 同步当前 params 状态
	_refresh_loadout()

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
	var available: bool = SurvivorData.is_upgrade_available_for(u, pid, p, stacks)

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
	# 鼠标悬停立即显示完整描述（绕开 Godot 默认 0.5s tooltip 延迟）
	var tip_desc: String = tr(u.get("desc", ""))
	var tip_text := "%s\n\n%s" % [tr(u["name"]), tip_desc] if tip_desc != "" else tr(u["name"])
	if is_evolved:
		tip_text = "★ 战区奖励\n" + tip_text
	name_label.mouse_filter = Control.MOUSE_FILTER_STOP
	name_label.mouse_entered.connect(_on_hover_show.bind(tip_text))
	name_label.mouse_exited.connect(_on_hover_hide)
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
			# 与正式获得路径同语义（skills-720 T1）：归属分流 + "+1 轴进度" + 生效子集重建
			game_scene._distribute_upgrade(u)
			game_scene.upgrade_stacks[uid] = game_scene.upgrade_stacks.get(uid, 0) + 1
			game_scene._grant_milestone_plus(u)
			break
	game_scene._refresh_squad_effective_stacks()
	_refresh()

func _on_add_skill() -> void:
	if not survivor_player or not game_scene:
		return
	var idx := _add_option.selected
	if idx < 0:
		return
	var uid: String = _add_option.get_item_metadata(idx)

	# 查找升级定义（与正式获得路径同语义：归属分流 + "+1 轴进度" + 生效子集重建）
	for u in SurvivorData.UPGRADES:
		if u["id"] == uid:
			game_scene._distribute_upgrade(u)
			game_scene.upgrade_stacks[uid] = game_scene.upgrade_stacks.get(uid, 0) + 1
			game_scene._grant_milestone_plus(u)
			break
	game_scene._refresh_squad_effective_stacks()
	_refresh()

func _status_label_for(sid: String) -> String:
	return StatusEffects.short_label(sid)

func _on_apply_status(sid: String) -> void:
	if survivor_player and survivor_player.aircraft:
		survivor_player.aircraft.apply_status(sid, 8.0)

func _on_clear_statuses() -> void:
	if survivor_player and survivor_player.aircraft:
		survivor_player.aircraft.clear_all_statuses()

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
	# 词条联动倍率是从 stacks 重算的，所以移除会立刻生效
	if survivor_player:
		SurvivorData.recompute_category_bonuses(survivor_player.aircraft, stacks)
	# 注意：移除技能不会回退属性（需要重启才能真正还原）
	# 在面板上标注这一点
	_refresh()


# ══════════════════════════════════════════════
# §7.5 实时状态刷新（active effects / attributes / pity / steering）
# ══════════════════════════════════════════════

func _refresh_live_state() -> void:
	if _live_label == null:
		return
	var pref: Aircraft = AircraftRenderer.player_ref
	if pref == null or not is_instance_valid(pref):
		_live_label.text = "[color=#888]玩家飞机不可用[/color]"
		return
	var lines: Array[String] = []

	# ── 状态效果 ──
	if pref.status_effects.is_empty():
		lines.append("[color=#888]状态: 无[/color]")
	else:
		var parts: Array[String] = []
		for sid in pref.status_effects.keys():
			var rem: float = float(pref.status_effects[sid])
			var col: Color = StatusEffects.icon_color(sid)
			var hex: String = "#%02x%02x%02x" % [int(col.r*255), int(col.g*255), int(col.b*255)]
			parts.append("[color=%s]%s[/color] %.1fs" % [hex, StatusEffects.short_label(sid), rem])
		lines.append("状态: " + ", ".join(parts))

	# ── 关键属性 ──
	var hp_max: float = pref.params.max_hp if pref.params else 100.0
	lines.append("HP: [b]%.0f[/b] / %.0f    高度档: %s    evasion: %s" % [
		pref.hp, hp_max, CombatUnit.TIER_NAMES.get(pref.get_altitude_tier(), "?"),
		"[color=#5af]ON[/color]" if pref.evasion_mode else "OFF",
	])

	# ── evasion_modifiers ──
	if "evasion_modifiers" in pref:
		var em: Dictionary = pref.evasion_modifiers
		var em_parts: Array[String] = []
		for k in em.keys():
			em_parts.append("%s=%.2f" % [k, float(em[k])])
		lines.append("[color=#888]evasion_mod:[/color] " + ", ".join(em_parts))

	# ── upgrade_stacks 简表 ──
	var stacks: Dictionary = {}
	if pref.has_meta("upgrade_stacks"):
		stacks = pref.get_meta("upgrade_stacks")
	var skill_count: int = 0
	for v in stacks.values():
		if int(v) > 0:
			skill_count += 1
	lines.append("[color=#888]已选技能数: %d[/color]" % skill_count)

	# ── pity / steering（穿透找 survivor_mode）──
	var sm := game_scene
	if sm and "_pity_counter" in sm:
		var pc: Dictionary = sm._pity_counter
		var pc_parts: Array[String] = []
		for r in pc.keys():
			var rname: String = ["S","A","E","C","N"][int(r)] if int(r) < 5 else "?"
			pc_parts.append("%s:%d" % [rname, int(pc[r])])
		lines.append("[color=#fc5]Pity[/color] " + (", ".join(pc_parts) if pc_parts.size() > 0 else "(空)"))
	if sm and "upgrade_stacks" in sm:
		var lvl: int = sm.survivor_player.level if sm.survivor_player else 1
		var steer: Dictionary = SurvivorData.compute_keyword_steering_weights(sm.upgrade_stacks, lvl)
		if not steer.is_empty():
			var sp: Array[String] = []
			for kw in steer.keys():
				sp.append("%s×%.2f" % [kw, float(steer[kw])])
			lines.append("[color=#a8f]Steering[/color] " + ", ".join(sp))

	_live_label.text = "\n".join(lines)


# ════════════════════════════════════════════════════════════
#  装备装载切换（debug-only loadout swap）
# ════════════════════════════════════════════════════════════
## 槽位定义：每个槽位列出可选装备 .tres 路径 + 类别（field=legacy 字段直存 / equipment=数组装备）
## 第一项一律是"无"（清槽）；GUN 和 MISSILE 不在此列表 = 固定不可换
const _LOADOUT_SLOTS: Array[Dictionary] = [
	{
		"key": "evasion",
		"name": "规避槽（互斥）",
		"kind": "evasion_mutex",   # 特殊：同时管 torpedo + loyal_wingman
		"options": [
			{"label": "无", "path": "", "subkind": ""},
			{"label": "漂浮雷", "path": "res://resources/a10_torpedo.tres", "subkind": "torpedo"},
			{"label": "忠诚僚机", "path": "res://resources/a10_loyal_wingman.tres", "subkind": "loyal_wingman"},
		],
	},
	{
		"key": "rocket",
		"name": "火箭弹",
		"kind": "field",
		"field": "rocket",
		"options": [
			{"label": "无", "path": ""},
			{"label": "FFAR (敌方默认)", "path": "res://resources/rocket_ffar.tres"},
			{"label": "Hydra 70 (A-10)", "path": "res://resources/a10_rocket.tres"},
			{"label": "A-7", "path": "res://resources/a7_rocket.tres"},
			{"label": "Q-5", "path": "res://resources/q5_rocket.tres"},
			{"label": "AH-64", "path": "res://resources/ah64_rocket.tres"},
		],
	},
	{
		"key": "secondary_missile",
		"name": "副武器槽 (SP)",
		"kind": "field",
		"field": "secondary_missile",
		"options": [
			{"label": "无", "path": ""},
			{"label": "QMAAM 格斗弹", "path": "res://resources/qmaam_missile.tres"},
			{"label": "AGM 空地", "path": "res://resources/agm_missile.tres"},
		],
	},
	{
		"key": "flare",
		"name": "热诱弹",
		"kind": "field",
		"field": "flare",
		"options": [
			{"label": "无", "path": ""},
			{"label": "默认", "path": "res://resources/default_flare.tres"},
			{"label": "F-14", "path": "res://resources/f14_flare.tres"},
			{"label": "F-16", "path": "res://resources/playable_f16_flare.tres"},
			{"label": "F-47 (大量)", "path": "res://resources/f47_flare.tres"},
		],
	},
	{
		"key": "railgun",
		"name": "电磁炮",
		"kind": "equipment",
		"equipment_kind": "railgun",
		"options": [
			{"label": "无", "path": ""},
			{"label": "X-02 Railgun", "path": "res://resources/x02_railgun.tres"},
			{"label": "AF-03 (敌方)", "path": "res://resources/enemy_railgun.tres"},
		],
	},
	{
		"key": "laser",
		"name": "激光",
		"kind": "equipment",
		"equipment_kind": "laser",
		"options": [
			{"label": "无", "path": ""},
			{"label": "X-02 Laser", "path": "res://resources/x02_laser.tres"},
			{"label": "Aegis 拦截激光", "path": "res://resources/enemy_laser_interceptor.tres"},
		],
	},
]


func _build_loadout_rows() -> void:
	for slot in _LOADOUT_SLOTS:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		_loadout_section.add_child(row)

		var lbl := Label.new()
		lbl.text = slot["name"]
		lbl.add_theme_font_size_override("font_size", 11)
		lbl.add_theme_color_override("font_color", ThemeColors.TEXT_PRIMARY_ALT)
		lbl.custom_minimum_size = Vector2(170, 0)
		lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
		row.add_child(lbl)

		var opt := OptionButton.new()
		opt.add_theme_font_size_override("font_size", 11)
		opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var options: Array = slot["options"]
		for i in range(options.size()):
			opt.add_item(options[i]["label"], i)
		opt.item_selected.connect(_on_loadout_changed.bind(slot["key"]))
		row.add_child(opt)

		_loadout_options[slot["key"]] = opt


## 同步当前 aircraft.params 状态 → OptionButton 选中项
func _refresh_loadout() -> void:
	if survivor_player == null or survivor_player.aircraft == null or survivor_player.aircraft.params == null:
		return
	var p: AircraftParams = survivor_player.aircraft.params
	for slot in _LOADOUT_SLOTS:
		var opt: OptionButton = _loadout_options.get(slot["key"], null)
		if opt == null:
			continue
		var current_idx := _resolve_current_index(slot, p)
		opt.select(current_idx)


## 找出当前 params 状态对应的 option 下标
func _resolve_current_index(slot: Dictionary, p: AircraftParams) -> int:
	var options: Array = slot["options"]
	var kind: String = slot["kind"]
	if kind == "evasion_mutex":
		# 看 torpedo 还是 loyal_wingman 哪个为非 null
		if p.torpedo != null:
			for i in range(options.size()):
				if options[i].get("subkind", "") == "torpedo":
					return i
		elif p.loyal_wingman != null:
			for i in range(options.size()):
				if options[i].get("subkind", "") == "loyal_wingman":
					return i
		return 0  # "无"
	if kind == "field":
		var f: String = slot["field"]
		var cur: Resource = p.get(f) as Resource
		if cur == null:
			return 0
		# duplicate(true) 清空 resource_path → 优先读 stash 的 meta
		var cur_path: String = cur.get_meta("_loadout_origin_path", "") if cur.has_meta("_loadout_origin_path") else cur.resource_path
		for i in range(options.size()):
			if options[i]["path"] == cur_path:
				return i
		return -1  # 未知（用户可能挂了不在我列表里的 .tres）
	if kind == "equipment":
		var ek: String = slot["equipment_kind"]
		var eq: EquipmentParams = p.get_equipment_of_kind(ek)
		if eq == null:
			return 0
		var eq_path: String = eq.get_meta("_loadout_origin_path", "") if eq.has_meta("_loadout_origin_path") else eq.resource_path
		for i in range(options.size()):
			if options[i]["path"] == eq_path:
				return i
		return -1
	return 0


## OptionButton 选中变化 → 应用到 aircraft.params
func _on_loadout_changed(idx: int, slot_key: String) -> void:
	if survivor_player == null or survivor_player.aircraft == null or survivor_player.aircraft.params == null:
		return
	var slot: Dictionary = {}
	for s in _LOADOUT_SLOTS:
		if s["key"] == slot_key:
			slot = s
			break
	if slot.is_empty():
		return
	var options: Array = slot["options"]
	if idx < 0 or idx >= options.size():
		return
	var chosen: Dictionary = options[idx]
	var path: String = chosen.get("path", "")
	var ac: Aircraft = survivor_player.aircraft
	var p: AircraftParams = ac.params
	var kind: String = slot["kind"]

	if kind == "evasion_mutex":
		# 互斥处理：清空两个槽位，再按选项设置一个
		p.torpedo = null
		p.loyal_wingman = null
		ac._torpedo_cooldown = 0.0
		ac._loyal_wingman_cooldown = 0.0
		# 已活跃的 drone 不强制清场（让他们自然走完寿命）
		if path != "":
			var res: Resource = load(path)
			if res != null:
				var dup: Resource = res.duplicate(true)
				dup.set_meta("_loadout_origin_path", path)
				var subkind: String = chosen.get("subkind", "")
				if subkind == "torpedo":
					p.torpedo = dup
				elif subkind == "loyal_wingman":
					p.loyal_wingman = dup
		EventLogger.log_event("DEBUG_LOADOUT", "F4", "evasion → %s" % chosen["label"])
		return

	if kind == "field":
		var f: String = slot["field"]
		if path == "":
			p.set(f, null)
		else:
			var res: Resource = load(path)
			if res != null:
				var dup: Resource = res.duplicate(true)
				dup.set_meta("_loadout_origin_path", path)
				p.set(f, dup)
		# 重置相关 runtime 状态
		_reset_runtime_state_for_field(ac, f)
		EventLogger.log_event("DEBUG_LOADOUT", "F4", "%s → %s" % [f, chosen["label"]])
		return

	if kind == "equipment":
		var ek: String = slot["equipment_kind"]
		# 移除旧 equipment_kind 的所有条目
		var i := p.equipment.size() - 1
		while i >= 0:
			if p.equipment[i] != null and p.equipment[i].equipment_kind == ek:
				p.equipment.remove_at(i)
			i -= 1
		# 清运行时状态
		ac.equipment_state.erase(ek)
		# 加新装备（duplicate 避免污染 .tres）
		if path != "":
			var res: Resource = load(path)
			if res != null and res is EquipmentParams:
				var dup: EquipmentParams = (res as EquipmentParams).duplicate(true)
				dup.set_meta("_loadout_origin_path", path)
				p.equipment.append(dup)
		# 同步到 legacy 字段（如果是 gun/rocket/missile/flare 等也在 equipment 数组里的）
		if ac.has_method("_publish_equipment_to_legacy"):
			ac._publish_equipment_to_legacy()
		EventLogger.log_event("DEBUG_LOADOUT", "F4", "equipment[%s] → %s" % [ek, chosen["label"]])
		return


## 切换 legacy field 后重置相关计时器 / 弹量 / cd
func _reset_runtime_state_for_field(ac: Aircraft, field: String) -> void:
	match field:
		"rocket":
			ac.rockets_remaining = ac.params.rocket.max_ammo if ac.params.rocket else 0
			ac._rocket_burst_cooldown = 0.0
		"flare":
			if ac.params.flare:
				ac.flares_remaining = ac.params.flare.max_flares
			else:
				ac.flares_remaining = 0
			ac._flare_cooldown = 0.0
		"secondary_missile":
			if ac.params.secondary_missile:
				ac.secondary_missiles_remaining = ac.params.secondary_missile.max_count
			else:
				ac.secondary_missiles_remaining = 0
			# 副槽 runtime 状态重置（独立 cooldown / reload / 锁定累积清空）
			ac._secondary_cooldown = 0.0
			ac._secondary_reload_active = false
			ac._secondary_reload_timer = 0.0
			ac._secondary_radar_tick_acc = 0.0
			ac.secondary_radar_targets.clear()
			ac.secondary_combat_target = null
		# combat 不需要重置 runtime（AI 下一帧自然采用新风格）
