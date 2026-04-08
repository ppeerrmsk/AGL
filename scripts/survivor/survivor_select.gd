extends Node2D

## 生存模式 — 机型选择界面
## 选中飞机后进入 survivor_mode 场景

# 视觉参数（与 main_menu 一致）
const GRID_SPACING := 80.0
const GRID_COLOR := Color(0.15, 0.2, 0.15, 0.3)
const LINE_COLOR := Color(0.3, 0.7, 0.3, 0.5)
const BG_COLOR := Color(0.02, 0.03, 0.02)

var _time := 0.0
var _canvas: CanvasLayer
var _cards_container: HBoxContainer
var _selected_index: int = -1

# ── 可选机型定义 ──
# 每个条目：资源路径、显示名称、特性标签列表
const AIRCRAFT_LIST: Array[Dictionary] = [
	{
		"id": "f16_flare",
		"resource": "res://resources/default_fighter.tres",
		"name": "F-16C Block 50",
		"tags": ["热诱弹", "均衡机动", "SARH 导弹"],
		"desc": "多用途战斗机。携带热诱弹可 100% 规避来袭导弹，攻守兼备的入门之选。",
	},
	# 后续在此追加新机型
]

func _ready() -> void:
	RenderingServer.set_default_clear_color(BG_COLOR)
	_build_ui()

func _process(delta: float) -> void:
	_time += delta
	queue_redraw()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		get_tree().change_scene_to_file("res://scenes/main_menu.tscn")

func _draw() -> void:
	var vp := get_viewport_rect().size
	_draw_grid(vp)
	_draw_corners(vp)

func _draw_grid(vp: Vector2) -> void:
	var cols := int(vp.x / GRID_SPACING) + 1
	var rows := int(vp.y / GRID_SPACING) + 1
	for i in range(cols + 1):
		var x := i * GRID_SPACING
		draw_line(Vector2(x, 0), Vector2(x, vp.y), GRID_COLOR, 1.0)
	for j in range(rows + 1):
		var y := j * GRID_SPACING
		draw_line(Vector2(0, y), Vector2(vp.x, y), GRID_COLOR, 1.0)

func _draw_corners(vp: Vector2) -> void:
	var margin := 40.0
	var corner_len := 20.0
	var c := LINE_COLOR
	# 四角装饰
	draw_line(Vector2(margin, margin), Vector2(margin + corner_len, margin), c, 1.5)
	draw_line(Vector2(margin, margin), Vector2(margin, margin + corner_len), c, 1.5)
	draw_line(Vector2(vp.x - margin, margin), Vector2(vp.x - margin - corner_len, margin), c, 1.5)
	draw_line(Vector2(vp.x - margin, margin), Vector2(vp.x - margin, margin + corner_len), c, 1.5)
	draw_line(Vector2(margin, vp.y - margin), Vector2(margin + corner_len, vp.y - margin), c, 1.5)
	draw_line(Vector2(margin, vp.y - margin), Vector2(margin, vp.y - margin - corner_len), c, 1.5)
	draw_line(Vector2(vp.x - margin, vp.y - margin), Vector2(vp.x - margin - corner_len, vp.y - margin), c, 1.5)
	draw_line(Vector2(vp.x - margin, vp.y - margin), Vector2(vp.x - margin, vp.y - margin - corner_len), c, 1.5)

# ══════════════════════════════════════════════
#  UI 构建
# ══════════════════════════════════════════════

func _build_ui() -> void:
	_canvas = CanvasLayer.new()
	_canvas.layer = 10
	add_child(_canvas)

	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.alignment = BoxContainer.ALIGNMENT_CENTER
	root.add_theme_constant_override("separation", 0)
	_canvas.add_child(root)

	# 上部空白
	var spacer_top := Control.new()
	spacer_top.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer_top.size_flags_stretch_ratio = 0.25
	root.add_child(spacer_top)

	# 标题
	var title := Label.new()
	title.text = "[ 选择机型 ]"
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", Color(0.4, 1.0, 0.4))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(title)

	# 副标题
	var subtitle := Label.new()
	subtitle.text = "生存模式  //  SURVIVAL MODE"
	subtitle.add_theme_font_size_override("font_size", 13)
	subtitle.add_theme_color_override("font_color", Color(0.3, 0.6, 0.3, 0.6))
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(subtitle)

	var sep := Control.new()
	sep.custom_minimum_size = Vector2(0, 30)
	root.add_child(sep)

	# 机型卡片容器
	_cards_container = HBoxContainer.new()
	_cards_container.alignment = BoxContainer.ALIGNMENT_CENTER
	_cards_container.add_theme_constant_override("separation", 24)
	_cards_container.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	root.add_child(_cards_container)

	for i in range(AIRCRAFT_LIST.size()):
		_build_aircraft_card(i)

	# 下方提示
	var sep2 := Control.new()
	sep2.custom_minimum_size = Vector2(0, 24)
	root.add_child(sep2)

	var hint := Label.new()
	hint.text = "ESC 返回主菜单"
	hint.add_theme_font_size_override("font_size", 12)
	hint.add_theme_color_override("font_color", Color(0.4, 0.5, 0.4, 0.4))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(hint)

	# 下部空白
	var spacer_bottom := Control.new()
	spacer_bottom.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer_bottom.size_flags_stretch_ratio = 0.4
	root.add_child(spacer_bottom)

func _build_aircraft_card(index: int) -> void:
	var data: Dictionary = AIRCRAFT_LIST[index]

	var card := VBoxContainer.new()
	card.custom_minimum_size = Vector2(300, 320)
	card.add_theme_constant_override("separation", 8)

	# 卡片面板背景
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.04, 0.07, 0.04, 0.8)
	style.border_color = Color(0.3, 0.6, 0.3, 0.4)
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.set_content_margin_all(20)
	panel.add_theme_stylebox_override("panel", style)
	panel.custom_minimum_size = Vector2(300, 320)

	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 10)
	panel.add_child(inner)

	# 机型名称
	var name_label := Label.new()
	name_label.text = data["name"]
	name_label.add_theme_font_size_override("font_size", 22)
	name_label.add_theme_color_override("font_color", Color(0.85, 0.95, 0.85))
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	inner.add_child(name_label)

	# 分隔线
	var sep_line := ColorRect.new()
	sep_line.color = Color(0.3, 0.6, 0.3, 0.3)
	sep_line.custom_minimum_size = Vector2(0, 1)
	inner.add_child(sep_line)

	# 特性标签
	var tags_box := HBoxContainer.new()
	tags_box.alignment = BoxContainer.ALIGNMENT_CENTER
	tags_box.add_theme_constant_override("separation", 8)
	inner.add_child(tags_box)

	var tags: Array = data["tags"]
	for tag_text in tags:
		var tag := Label.new()
		tag.text = "[ %s ]" % tag_text
		tag.add_theme_font_size_override("font_size", 11)
		tag.add_theme_color_override("font_color", Color(0.5, 0.9, 0.5, 0.7))
		tags_box.add_child(tag)

	# 描述
	var desc_label := Label.new()
	desc_label.text = data["desc"]
	desc_label.add_theme_font_size_override("font_size", 13)
	desc_label.add_theme_color_override("font_color", Color(0.6, 0.7, 0.6, 0.8))
	desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_label.custom_minimum_size = Vector2(260, 0)
	inner.add_child(desc_label)

	# 弹性空间
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	inner.add_child(spacer)

	# 简要参数
	var params_res: AircraftParams = load(data["resource"])
	if params_res:
		var stats := Label.new()
		stats.text = "HP %d  |  速度 %d km/h  |  G极限 %.0f  |  导弹 %d" % [
			int(params_res.max_hp),
			int(params_res.max_speed),
			params_res.max_g,
			params_res.missile.max_count if params_res.missile else 0,
		]
		stats.add_theme_font_size_override("font_size", 11)
		stats.add_theme_color_override("font_color", Color(0.5, 0.65, 0.5, 0.6))
		stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		inner.add_child(stats)

	# 出击按钮
	var btn := Button.new()
	btn.text = "出  击"
	btn.custom_minimum_size = Vector2(260, 44)
	btn.add_theme_font_size_override("font_size", 18)

	var btn_style := StyleBoxFlat.new()
	btn_style.bg_color = Color(0.08, 0.15, 0.08, 0.9)
	btn_style.border_color = Color(0.4, 0.8, 0.4, 0.5)
	btn_style.set_border_width_all(1)
	btn_style.set_corner_radius_all(3)
	btn_style.set_content_margin_all(6)
	btn.add_theme_stylebox_override("normal", btn_style)

	var btn_hover := StyleBoxFlat.new()
	btn_hover.bg_color = Color(0.12, 0.25, 0.12, 0.95)
	btn_hover.border_color = Color(0.5, 1.0, 0.5, 0.8)
	btn_hover.set_border_width_all(2)
	btn_hover.set_corner_radius_all(3)
	btn_hover.set_content_margin_all(6)
	btn.add_theme_stylebox_override("hover", btn_hover)

	var btn_pressed := StyleBoxFlat.new()
	btn_pressed.bg_color = Color(0.18, 0.35, 0.18, 1.0)
	btn_pressed.border_color = Color(0.6, 1.0, 0.6, 1.0)
	btn_pressed.set_border_width_all(2)
	btn_pressed.set_corner_radius_all(3)
	btn_pressed.set_content_margin_all(6)
	btn.add_theme_stylebox_override("pressed", btn_pressed)

	var idx := index
	btn.pressed.connect(func(): _on_aircraft_selected(idx))
	inner.add_child(btn)

	_cards_container.add_child(panel)

# ══════════════════════════════════════════════
#  选择 & 进入游戏
# ══════════════════════════════════════════════

func _on_aircraft_selected(index: int) -> void:
	var data: Dictionary = AIRCRAFT_LIST[index]
	# 通过 scene tree meta 传递选择的机型资源路径
	get_tree().set_meta("survivor_aircraft_resource", data["resource"])
	get_tree().change_scene_to_file("res://scenes/survivor_mode.tscn")
