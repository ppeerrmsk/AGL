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

# ── 坐标 HUD（面板可见时自动开启）──
## 跟随鼠标的世界坐标读数（CanvasLayer 内）
var _coord_label: Label
## 挂在 game_scene 下的世界坐标轴 Node2D（X/Y 轴 + 原点 + 刻度）
var _coord_axes: Node2D
const COORD_AXES_GRID_PX := 1000.0   ## 刻度间距：1000px ≈ 2km
const COORD_AXES_HALF_EXTENT := 8000.0  ## 轴向单边长度（世界 ±7500，多画一点点）

# ── 编队类型枚举（内部）──
enum FormationType { SINGLE, SQUAD, COMMANDER_SQUAD, TU160_FLOCK, AH64_FLOCK, CH47_FLOCK, F47_SQUAD, CSG_BOSS }

const FORMATION_NAMES := {
	FormationType.SINGLE: "单机",
	FormationType.SQUAD: "普通编队",
	FormationType.COMMANDER_SQUAD: "指挥UAV小队",
	FormationType.TU160_FLOCK: "Tu-160 族群波次",
	FormationType.AH64_FLOCK: "AH-64 纵阵波次",
	FormationType.CH47_FLOCK: "CH-47 纵阵波次",
	FormationType.F47_SQUAD: "F-47 王牌小队",
	FormationType.CSG_BOSS: "航母战斗群 BOSS",
}

# ── 敌机类型标签（与 SurvivorSpawner.EnemyType 对应）──
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
	{"label": "AF-03 电磁炮狙击手", "enum_idx": 17},   # EnemyType.AF03
	{"label": "Aegis UAV 激光拦截器", "enum_idx": 18},        # EnemyType.UAV_LASER
]

func _ready() -> void:
	layer = 30
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_build_ui()
	_build_coord_hud()
	visibility_changed.connect(_on_panel_visibility_changed)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_F5:
		visible = not visible
		get_viewport().set_input_as_handled()
		# 防御：某些编辑器快捷键也绑到 F5，避免留下暂停状态
		if visible and game_scene and "is_paused_for_upgrade" in game_scene:
			if get_tree().paused and not game_scene.is_paused_for_upgrade:
				get_tree().paused = false

func _process(_delta: float) -> void:
	if not visible:
		return
	_update_coord_hud()

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
	_formation_option.add_item("航母战斗群 BOSS", FormationType.CSG_BOSS)
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

	# ── 海上单位生成 ──
	var naval_label := Label.new()
	naval_label.text = "[ 海上单位 ]"
	naval_label.add_theme_font_size_override("font_size", 13)
	naval_label.add_theme_color_override("font_color", Color(0.5, 0.75, 0.95))
	naval_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_content.add_child(naval_label)

	var ffg_btn := Button.new()
	ffg_btn.text = "▶ 敌方 FFG 护卫舰"
	ffg_btn.add_theme_font_size_override("font_size", 12)
	_apply_btn_style(ffg_btn, Color(0.3, 0.55, 0.85))
	ffg_btn.pressed.connect(_on_spawn_enemy_ffg)
	_content.add_child(ffg_btn)

	var ddg_btn := Button.new()
	ddg_btn.text = "▶ 敌方 DDG 驱逐舰（VLS 齐射）"
	ddg_btn.add_theme_font_size_override("font_size", 12)
	_apply_btn_style(ddg_btn, Color(0.25, 0.45, 0.9))
	ddg_btn.pressed.connect(_on_spawn_enemy_ddg)
	_content.add_child(ddg_btn)

	var cg_btn := Button.new()
	cg_btn.text = "▶ 敌方 CG 巡洋舰（远距 VLS）"
	cg_btn.add_theme_font_size_override("font_size", 12)
	_apply_btn_style(cg_btn, Color(0.2, 0.35, 0.95))
	cg_btn.pressed.connect(_on_spawn_enemy_cg)
	_content.add_child(cg_btn)

	var cv_btn := Button.new()
	cv_btn.text = "▶ 敌方 CV 航母（BOSS 级，1200 HP）"
	cv_btn.add_theme_font_size_override("font_size", 12)
	_apply_btn_style(cv_btn, Color(0.15, 0.25, 0.85))
	cv_btn.pressed.connect(_on_spawn_enemy_cv)
	_content.add_child(cv_btn)

	var ss_btn := Button.new()
	ss_btn.text = "▶ 敌方 SS 核潜艇（18 枚巡航导弹齐射）"
	ss_btn.add_theme_font_size_override("font_size", 12)
	_apply_btn_style(ss_btn, Color(0.35, 0.2, 0.55))
	ss_btn.pressed.connect(_on_spawn_enemy_ss)
	_content.add_child(ss_btn)

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
	hint.text = "F5 关闭  |  面板不暂停游戏  |  鼠标右下显示世界坐标"
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

	var spawner: SurvivorSpawner = game_scene._spawner
	if not spawner:
		return
	for r in range(repeats):
		match formation:
			FormationType.SINGLE:
				spawner._spawn_single(enum_idx)
			FormationType.SQUAD:
				spawner._spawn_squad(enum_idx, size)
			FormationType.COMMANDER_SQUAD:
				spawner._spawn_commander_squad(size)
			FormationType.TU160_FLOCK:
				# 族群波次：大小由 SurvivorData.TU160_FLOCK_SIZE 定义，size spinbox 忽略
				spawner._spawn_tu160_flock()
			FormationType.AH64_FLOCK:
				spawner._spawn_ah64_flock()
			FormationType.CH47_FLOCK:
				spawner._spawn_ch47_flock()
			FormationType.F47_SQUAD:
				spawner._spawn_f47_squad()
			FormationType.CSG_BOSS:
				var enc := BossRegistry.instantiate("CARRIER_STRIKE_GROUP")
				if enc and game_scene and "player_aircraft" in game_scene and game_scene.player_aircraft:
					var anchor := _find_water_anchor(game_scene.player_aircraft.global_position)
					spawner._spawn_boss(enc, anchor)

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

func _on_spawn_enemy_ffg() -> void:
	if not game_scene or not is_instance_valid(game_scene):
		return
	if game_scene.is_game_over:
		return
	var repeats: int = int(_count_spin.value)
	for r in range(repeats):
		game_scene._spawn_enemy_ffg()
	print("[DebugSpawn] spawned %d × 敌方FFG" % repeats)

func _on_spawn_enemy_ddg() -> void:
	if not game_scene or not is_instance_valid(game_scene):
		return
	if game_scene.is_game_over:
		return
	var repeats: int = int(_count_spin.value)
	for r in range(repeats):
		game_scene._spawn_enemy_ddg()
	print("[DebugSpawn] spawned %d × 敌方DDG" % repeats)

func _on_spawn_enemy_cg() -> void:
	if not game_scene or not is_instance_valid(game_scene):
		return
	if game_scene.is_game_over:
		return
	var repeats: int = int(_count_spin.value)
	for r in range(repeats):
		game_scene._spawn_enemy_cg()
	print("[DebugSpawn] spawned %d × 敌方CG" % repeats)

func _on_spawn_enemy_cv() -> void:
	if not game_scene or not is_instance_valid(game_scene):
		return
	if game_scene.is_game_over:
		return
	var repeats: int = int(_count_spin.value)
	for r in range(repeats):
		game_scene._spawn_enemy_cv()
	print("[DebugSpawn] spawned %d × 敌方CV" % repeats)

func _on_spawn_enemy_ss() -> void:
	if not game_scene or not is_instance_valid(game_scene):
		return
	if game_scene.is_game_over:
		return
	var repeats: int = int(_count_spin.value)
	for r in range(repeats):
		game_scene._spawn_enemy_ss()
	print("[DebugSpawn] spawned %d × 敌方SS" % repeats)

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
		elif child is NavalUnit:
			var nu: NavalUnit = child
			if nu.team != 0 and not nu.is_destroyed:
				# 船没有 take_damage 斩杀路径（船本身不可直接击沉），直接 queue_free + 释放舰名
				if nu.full_name != "":
					NavalShipNames.release(nu.full_name)
				nu.queue_free()
				cleared += 1
	print("[DebugSpawn] cleared %d enemies" % cleared)

func _on_dump_pressed() -> void:
	var path := EventLogger.dump_to_file()
	if path != "":
		print("Combat log saved: %s" % path)

# ══════════════════════════════════════════════
#  坐标 HUD（面板可见时自动开启 / 关闭）
# ══════════════════════════════════════════════
##
## 设计：把 F5 面板从「单一刷怪面板」升级为「Debug 套件入口」——
## 打开面板就同时显示：
##   1. 屏幕上叠加 X/Y 世界坐标轴 + 原点十字 + 1000px 刻度（挂在 game_scene 下，跟相机走）
##   2. 鼠标右下角实时世界坐标（CanvasLayer 内的 Label，跟随光标）
## 关闭面板就一起隐藏，避免占用额外按键。

func _build_coord_hud() -> void:
	# 鼠标坐标读数 Label（CanvasLayer 内，自动跟相机无关）
	_coord_label = Label.new()
	_coord_label.add_theme_font_size_override("font_size", 12)
	_coord_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
	_coord_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_coord_label.add_theme_constant_override("outline_size", 4)
	_coord_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_coord_label.z_index = 100
	add_child(_coord_label)

	# 世界坐标轴 Node2D —— 等 game_scene 注入后再挂
	_coord_axes = Node2D.new()
	_coord_axes.z_index = 50
	_coord_axes.draw.connect(_draw_coord_axes)

func _on_panel_visibility_changed() -> void:
	# 同步坐标轴 Node2D 的 parent + 可见性
	if visible:
		if _coord_axes and not _coord_axes.is_inside_tree() \
				and game_scene and is_instance_valid(game_scene):
			game_scene.add_child(_coord_axes)
		if _coord_axes:
			_coord_axes.visible = true
			_coord_axes.queue_redraw()
	else:
		if _coord_axes:
			_coord_axes.visible = false

func _update_coord_hud() -> void:
	if not _coord_label:
		return
	var screen_pos := get_viewport().get_mouse_position()
	# 用 game_scene 的 canvas_transform 反算世界坐标（兼容相机平移/缩放）
	var world_pos := screen_pos
	if game_scene and is_instance_valid(game_scene) and game_scene is CanvasItem:
		world_pos = (game_scene as CanvasItem).get_canvas_transform().affine_inverse() * screen_pos
	_coord_label.text = "X: %d\nY: %d" % [int(round(world_pos.x)), int(round(world_pos.y))]
	_coord_label.position = screen_pos + Vector2(16, 16)

# 世界坐标轴绘制（callback 自 _coord_axes.draw 信号，运行在世界空间）
func _draw_coord_axes() -> void:
	if not _coord_axes:
		return
	var ext := COORD_AXES_HALF_EXTENT
	var axis_color := Color(1.0, 0.85, 0.4, 0.55)
	var grid_color := Color(1.0, 0.85, 0.4, 0.18)
	# X 轴 / Y 轴
	_coord_axes.draw_line(Vector2(-ext, 0), Vector2(ext, 0), axis_color, 2.0)
	_coord_axes.draw_line(Vector2(0, -ext), Vector2(0, ext), axis_color, 2.0)
	# 原点十字（更显眼）
	_coord_axes.draw_circle(Vector2.ZERO, 30.0, Color(1.0, 0.85, 0.4, 0.35))
	_coord_axes.draw_line(Vector2(-60, 0), Vector2(60, 0), Color(1.0, 0.5, 0.2, 0.9), 3.0)
	_coord_axes.draw_line(Vector2(0, -60), Vector2(0, 60), Color(1.0, 0.5, 0.2, 0.9), 3.0)
	# 刻度 + 数字标签
	var step := COORD_AXES_GRID_PX
	var n := int(ext / step)
	var font := ThemeDB.fallback_font
	var font_size := 18
	for i in range(-n, n + 1):
		if i == 0:
			continue
		var p: float = float(i) * step
		# X 轴刻度 + 标签
		_coord_axes.draw_line(Vector2(p, -10), Vector2(p, 10), axis_color, 1.5)
		_coord_axes.draw_line(Vector2(p, -ext), Vector2(p, ext), grid_color, 1.0)
		_coord_axes.draw_string(font, Vector2(p + 6, -16), str(int(p)),
				HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, axis_color)
		# Y 轴刻度 + 标签
		_coord_axes.draw_line(Vector2(-10, p), Vector2(10, p), axis_color, 1.5)
		_coord_axes.draw_line(Vector2(-ext, p), Vector2(ext, p), grid_color, 1.0)
		_coord_axes.draw_string(font, Vector2(14, p - 4), str(int(p)),
				HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, axis_color)

## CSG BOSS 刷出位置：优先在玩家附近海面找个圆形水域（半径 ≥ 2500px 容得下整支舰队）
## 找不到就退回玩家前方 4500px 固定偏移（测试用，允许刷在陆地上）
func _find_water_anchor(origin: Vector2) -> Vector2:
	var fallback: Vector2 = origin + Vector2(4500, 0)
	# 按距离 / 角度栅格扫描：距离 3000 → 7000 px，每 45° 一个方向
	for dist in [3500.0, 4500.0, 5500.0, 6500.0]:
		for i in range(8):
			var ang: float = float(i) * TAU / 8.0
			var candidate: Vector2 = origin + Vector2(cos(ang), sin(ang)) * dist
			# 舰队尺寸 ~3400×2600，4 角 + 中心均需在水上
			if _is_water_region(candidate, 3000.0):
				return candidate
	return fallback

func _is_water_region(center: Vector2, radius: float) -> bool:
	if not MapGeography.is_on_land(center):
		# 再抽查 4 个方向的边缘点
		for i in range(4):
			var a: float = float(i) * TAU / 4.0
			var pt: Vector2 = center + Vector2(cos(a), sin(a)) * radius
			if MapGeography.is_on_land(pt):
				return false
		return true
	return false
