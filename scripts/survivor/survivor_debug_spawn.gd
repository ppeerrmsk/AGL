class_name SurvivorDebugSpawn
extends CanvasLayer

## F5 Debug 刷怪面板：在生存模式里按需生成敌机/编队
## 与 F4 技能面板的区别：此面板打开时**不暂停**游戏，便于即时测试

var game_scene: Node  ## survivor_mode 实例

# ── UI 节点 ──
var _panel: PanelContainer
var _content: VBoxContainer
var _type_option: OptionButton
var _formation_option: OptionButton
var _squad_size_spin: SpinBox
var _squad_size_row: HBoxContainer
var _count_spin: SpinBox

# ── 编队类型枚举（内部）──
enum FormationType { SINGLE, SQUAD, COMMANDER_SQUAD, TU160_FLOCK, AH64_FLOCK, CH47_FLOCK, F47_SQUAD }

const FORMATION_NAMES := {
	FormationType.SINGLE: "单机",
	FormationType.SQUAD: "普通编队",
	FormationType.COMMANDER_SQUAD: "指挥UAV小队",
	FormationType.TU160_FLOCK: "Tu-160 族群波次",
	FormationType.AH64_FLOCK: "AH-64 纵阵波次",
	FormationType.CH47_FLOCK: "CH-47 纵阵波次",
	FormationType.F47_SQUAD: "F-47 王牌小队",
}

# ── 敌机类型标签（与 survivor_mode.EnemyType 对应）──
# ⚠ 新增敌人类型时必须在这里同步追加，否则 Debug 面板刷不出来
const ENEMY_TYPE_LABELS := [
	{"label": "MiG-29", "enum_idx": 2},               # EnemyType.MIG
	{"label": "MiG-31 截击机", "enum_idx": 6},          # EnemyType.MIG31
	{"label": "MiG-23", "enum_idx": 7},               # EnemyType.MIG23
	{"label": "J-7 截击机", "enum_idx": 3},             # EnemyType.INTERCEPTOR
	{"label": "F-100", "enum_idx": 8},                # EnemyType.F100
	{"label": "F-86", "enum_idx": 5},                 # EnemyType.F86
	{"label": "Su-27", "enum_idx": 9},                # EnemyType.SU27
	{"label": "A-7 攻击机", "enum_idx": 10},             # EnemyType.A7
	{"label": "Q-5 攻击机", "enum_idx": 11},             # EnemyType.Q5
	{"label": "UAV 机炮无人机", "enum_idx": 0},           # EnemyType.UAV
	{"label": "UCAV 导弹无人机", "enum_idx": 1},          # EnemyType.UCAV
	{"label": "Sentinel 指挥 UAV", "enum_idx": 4},      # EnemyType.UAV_COMMANDER
	{"label": "Tu-160 白天鹅（Adds）", "enum_idx": 12}, # EnemyType.TU160
	{"label": "AH-64 Apache（Adds 直升机）", "enum_idx": 13}, # EnemyType.AH64
	{"label": "CH-47 Chinook（Adds 直升机）", "enum_idx": 14}, # EnemyType.CH47
	{"label": "F-47 王牌小队（BOSS）", "enum_idx": 15},      # EnemyType.F47
]

func _ready() -> void:
	layer = 30
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_build_ui()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_F5:
		visible = not visible
		get_viewport().set_input_as_handled()
		# 防御：某些编辑器快捷键也绑到 F5，避免留下暂停状态
		if visible and game_scene and "is_paused_for_upgrade" in game_scene:
			if get_tree().paused and not game_scene.is_paused_for_upgrade:
				get_tree().paused = false

# ══════════════════════════════════════════════
#  UI 构建
# ══════════════════════════════════════════════

func _build_ui() -> void:
	_panel = PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.04, 0.02, 0.04, 0.95)
	style.border_color = Color(0.9, 0.6, 0.2, 0.6)
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.set_content_margin_all(16)
	_panel.add_theme_stylebox_override("panel", style)
	_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_panel.position = Vector2(-440, 20)  # 右上角内嵌
	_panel.custom_minimum_size = Vector2(420, 0)
	add_child(_panel)

	_content = VBoxContainer.new()
	_content.add_theme_constant_override("separation", 8)
	_panel.add_child(_content)

	# 标题
	var title := Label.new()
	title.text = "[ DEBUG — 刷怪面板 ]"
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", Color(1.0, 0.75, 0.3))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_content.add_child(title)

	_content.add_child(_make_sep())

	# 敌机类型选择
	var type_row := HBoxContainer.new()
	type_row.add_theme_constant_override("separation", 10)
	_content.add_child(type_row)
	type_row.add_child(_make_label("敌机:", 13))

	_type_option = OptionButton.new()
	_type_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_type_option.add_theme_font_size_override("font_size", 12)
	for i in range(ENEMY_TYPE_LABELS.size()):
		_type_option.add_item(ENEMY_TYPE_LABELS[i]["label"], i)
	_type_option.selected = 0
	_type_option.item_selected.connect(_on_type_changed)
	type_row.add_child(_type_option)

	# 编队模式选择
	var formation_row := HBoxContainer.new()
	formation_row.add_theme_constant_override("separation", 10)
	_content.add_child(formation_row)
	formation_row.add_child(_make_label("编队:", 13))

	_formation_option = OptionButton.new()
	_formation_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_formation_option.add_theme_font_size_override("font_size", 12)
	_formation_option.add_item("单机", FormationType.SINGLE)
	_formation_option.add_item("普通编队", FormationType.SQUAD)
	_formation_option.add_item("指挥UAV小队", FormationType.COMMANDER_SQUAD)
	_formation_option.add_item("Tu-160 族群波次", FormationType.TU160_FLOCK)
	_formation_option.add_item("AH-64 纵阵波次", FormationType.AH64_FLOCK)
	_formation_option.add_item("CH-47 纵阵波次", FormationType.CH47_FLOCK)
	_formation_option.add_item("F-47 王牌小队", FormationType.F47_SQUAD)
	_formation_option.selected = 0
	_formation_option.item_selected.connect(_on_formation_changed)
	formation_row.add_child(_formation_option)

	# 编队规模行
	_squad_size_row = HBoxContainer.new()
	_squad_size_row.add_theme_constant_override("separation", 10)
	_content.add_child(_squad_size_row)
	_squad_size_row.add_child(_make_label("僚机/规模:", 13))

	_squad_size_spin = SpinBox.new()
	_squad_size_spin.min_value = 1
	_squad_size_spin.max_value = 8
	_squad_size_spin.value = 3
	_squad_size_spin.custom_minimum_size = Vector2(80, 0)
	_squad_size_row.add_child(_squad_size_spin)

	var size_hint := Label.new()
	size_hint.text = "  (编队=总数, 指挥小队=僚机数)"
	size_hint.add_theme_font_size_override("font_size", 10)
	size_hint.add_theme_color_override("font_color", Color(0.6, 0.6, 0.5, 0.7))
	_squad_size_row.add_child(size_hint)

	_squad_size_row.visible = false  # 默认单机模式下隐藏

	# 刷怪次数
	var count_row := HBoxContainer.new()
	count_row.add_theme_constant_override("separation", 10)
	_content.add_child(count_row)
	count_row.add_child(_make_label("刷怪次数:", 13))

	_count_spin = SpinBox.new()
	_count_spin.min_value = 1
	_count_spin.max_value = 20
	_count_spin.value = 1
	_count_spin.custom_minimum_size = Vector2(80, 0)
	count_row.add_child(_count_spin)

	var count_hint := Label.new()
	count_hint.text = "  (重复刷 N 次)"
	count_hint.add_theme_font_size_override("font_size", 10)
	count_hint.add_theme_color_override("font_color", Color(0.6, 0.6, 0.5, 0.7))
	count_row.add_child(count_hint)

	_content.add_child(_make_sep())

	# 刷怪按钮
	var spawn_btn := Button.new()
	spawn_btn.text = "▶ 刷新敌人"
	spawn_btn.add_theme_font_size_override("font_size", 14)
	_apply_btn_style(spawn_btn, Color(0.9, 0.5, 0.2))
	spawn_btn.pressed.connect(_on_spawn_pressed)
	_content.add_child(spawn_btn)

	_content.add_child(_make_sep())

	# ── 地面单位生成 ──
	var ground_label := Label.new()
	ground_label.text = "[ 地面单位 ]"
	ground_label.add_theme_font_size_override("font_size", 13)
	ground_label.add_theme_color_override("font_color", Color(0.85, 0.65, 0.3))
	ground_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_content.add_child(ground_label)

	var sam_btn := Button.new()
	sam_btn.text = "▶ 敌方 SAM（防空导弹）"
	sam_btn.add_theme_font_size_override("font_size", 12)
	_apply_btn_style(sam_btn, Color(0.8, 0.4, 0.2))
	sam_btn.pressed.connect(_on_spawn_enemy_sam)
	_content.add_child(sam_btn)

	var aa_btn := Button.new()
	aa_btn.text = "▶ 敌方 AA 炮（高射炮）"
	aa_btn.add_theme_font_size_override("font_size", 12)
	_apply_btn_style(aa_btn, Color(0.8, 0.4, 0.2))
	aa_btn.pressed.connect(_on_spawn_enemy_aa)
	_content.add_child(aa_btn)

	_content.add_child(_make_sep())

	# 清空敌人按钮
	var clear_btn := Button.new()
	clear_btn.text = "✖ 清空所有敌人"
	clear_btn.add_theme_font_size_override("font_size", 12)
	_apply_btn_style(clear_btn, Color(0.7, 0.2, 0.2))
	clear_btn.pressed.connect(_on_clear_pressed)
	_content.add_child(clear_btn)

	# 导出日志按钮（替代 F9，避免编辑器拦截）
	var dump_btn := Button.new()
	dump_btn.text = "💾 导出战斗日志（替代 F9）"
	dump_btn.add_theme_font_size_override("font_size", 12)
	_apply_btn_style(dump_btn, Color(0.2, 0.6, 0.8))
	dump_btn.pressed.connect(_on_dump_pressed)
	_content.add_child(dump_btn)

	# 底部提示
	var hint := Label.new()
	hint.text = "F5 关闭  |  面板不暂停游戏  |  绕过敌机上限"
	hint.add_theme_font_size_override("font_size", 10)
	hint.add_theme_color_override("font_color", Color(0.5, 0.5, 0.4, 0.6))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_content.add_child(hint)

# ══════════════════════════════════════════════
#  UI 辅助
# ══════════════════════════════════════════════

func _make_label(text: String, size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", Color(0.85, 0.85, 0.78))
	return l

func _make_sep() -> HSeparator:
	var sep := HSeparator.new()
	sep.add_theme_color_override("separator", Color(0.5, 0.3, 0.1, 0.3))
	return sep

func _apply_btn_style(btn: Button, accent: Color) -> void:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(accent.r * 0.3, accent.g * 0.3, accent.b * 0.3, 0.85)
	s.border_color = Color(accent, 0.6)
	s.set_border_width_all(1)
	s.set_corner_radius_all(3)
	s.set_content_margin_all(8)
	btn.add_theme_stylebox_override("normal", s)
	var h := s.duplicate()
	h.bg_color = Color(accent.r * 0.45, accent.g * 0.45, accent.b * 0.45, 0.95)
	h.border_color = Color(accent, 0.9)
	btn.add_theme_stylebox_override("hover", h)

# ══════════════════════════════════════════════
#  交互回调
# ══════════════════════════════════════════════

func _on_type_changed(idx: int) -> void:
	# 指挥 UAV 类型需要强制切到"指挥UAV小队"模式
	var enum_idx: int = ENEMY_TYPE_LABELS[idx]["enum_idx"]
	if enum_idx == 4:  # EnemyType.UAV_COMMANDER
		_formation_option.selected = FormationType.COMMANDER_SQUAD
		_on_formation_changed(FormationType.COMMANDER_SQUAD)
	elif enum_idx == 12:  # EnemyType.TU160
		# Tu-160 只能走族群波次（Adds）
		_formation_option.selected = FormationType.TU160_FLOCK
		_on_formation_changed(FormationType.TU160_FLOCK)
	elif enum_idx == 13:  # EnemyType.AH64
		_formation_option.selected = FormationType.AH64_FLOCK
		_on_formation_changed(FormationType.AH64_FLOCK)
	elif enum_idx == 14:  # EnemyType.CH47
		_formation_option.selected = FormationType.CH47_FLOCK
		_on_formation_changed(FormationType.CH47_FLOCK)
	elif enum_idx == 15:  # EnemyType.F47
		_formation_option.selected = FormationType.F47_SQUAD
		_on_formation_changed(FormationType.F47_SQUAD)

func _on_formation_changed(idx: int) -> void:
	# 单机 / Adds 族群波次（大小由 SurvivorData 定义，固定）不需要 size spinbox
	_squad_size_row.visible = (idx != FormationType.SINGLE \
			and idx != FormationType.TU160_FLOCK \
			and idx != FormationType.AH64_FLOCK \
			and idx != FormationType.CH47_FLOCK \
			and idx != FormationType.F47_SQUAD)

func _on_spawn_pressed() -> void:
	if not game_scene or not is_instance_valid(game_scene):
		return
	if not ("player_aircraft" in game_scene) or game_scene.player_aircraft == null:
		return
	if game_scene.is_game_over:
		return

	var enum_idx: int = ENEMY_TYPE_LABELS[_type_option.selected]["enum_idx"]
	var formation: int = _formation_option.selected
	var size: int = int(_squad_size_spin.value)
	var repeats: int = int(_count_spin.value)

	for r in range(repeats):
		match formation:
			FormationType.SINGLE:
				game_scene._spawn_single(enum_idx)
			FormationType.SQUAD:
				game_scene._spawn_squad(enum_idx, size)
			FormationType.COMMANDER_SQUAD:
				game_scene._spawn_commander_squad(size)
			FormationType.TU160_FLOCK:
				# 族群波次：大小由 SurvivorData.TU160_FLOCK_SIZE 定义，size spinbox 忽略
				game_scene._spawn_tu160_flock()
			FormationType.AH64_FLOCK:
				game_scene._spawn_ah64_flock()
			FormationType.CH47_FLOCK:
				game_scene._spawn_ch47_flock()
			FormationType.F47_SQUAD:
				game_scene._spawn_f47_squad()

	print("[DebugSpawn] spawned %d × %s [%s]" % [
		repeats,
		FORMATION_NAMES.get(formation, "?"),
		ENEMY_TYPE_LABELS[_type_option.selected]["label"],
	])

func _on_spawn_enemy_sam() -> void:
	if not game_scene or not is_instance_valid(game_scene):
		return
	if game_scene.is_game_over:
		return
	var repeats: int = int(_count_spin.value)
	for r in range(repeats):
		game_scene._spawn_enemy_sam()
	print("[DebugSpawn] spawned %d × 敌方SAM" % repeats)

func _on_spawn_enemy_aa() -> void:
	if not game_scene or not is_instance_valid(game_scene):
		return
	if game_scene.is_game_over:
		return
	var repeats: int = int(_count_spin.value)
	for r in range(repeats):
		game_scene._spawn_enemy_aa()
	print("[DebugSpawn] spawned %d × 敌方AA炮" % repeats)

func _on_clear_pressed() -> void:
	if not game_scene or not is_instance_valid(game_scene):
		return
	var cleared := 0
	for child in game_scene.get_children():
		if child is Aircraft:
			var ac: Aircraft = child
			if ac.team != 0 and not ac.is_destroyed:
				ac._start_destroy()
				cleared += 1
		elif child is GroundUnit:
			var gu: GroundUnit = child
			if gu.team != 0 and not gu.is_destroyed:
				gu.take_damage(9999.0)
				cleared += 1
	print("[DebugSpawn] cleared %d enemies" % cleared)

func _on_dump_pressed() -> void:
	var path := EventLogger.dump_to_file()
	if path != "":
		print("Combat log saved: %s" % path)
