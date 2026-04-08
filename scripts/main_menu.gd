extends Node2D

## 主菜单：游戏入口，选择游戏模式

# --- 视觉参数 ---
const GRID_SPACING := 80.0
const GRID_COLOR := Color(0.15, 0.2, 0.15, 0.3)
const LINE_COLOR := Color(0.3, 0.7, 0.3, 0.5)
const TITLE_COLOR := Color(0.4, 1.0, 0.4)
const SUBTITLE_COLOR := Color(0.3, 0.6, 0.3, 0.7)
const BG_COLOR := Color(0.02, 0.03, 0.02)

# --- 动画 ---
var _time := 0.0
var _sweep_angle := 0.0  ## 雷达扫描角度

# --- UI ---
var _canvas: CanvasLayer
var _mode_container: VBoxContainer

func _ready() -> void:
	RenderingServer.set_default_clear_color(BG_COLOR)
	_build_ui()

func _process(delta: float) -> void:
	_time += delta
	_sweep_angle += delta * 1.2  # 雷达扫描速度
	if _sweep_angle > TAU:
		_sweep_angle -= TAU
	queue_redraw()

func _draw() -> void:
	var vp := get_viewport_rect().size
	_draw_grid(vp)
	_draw_radar_sweep(vp)
	_draw_decorative_lines(vp)

func _draw_grid(vp: Vector2) -> void:
	var cols := int(vp.x / GRID_SPACING) + 1
	var rows := int(vp.y / GRID_SPACING) + 1
	for i in range(cols + 1):
		var x := i * GRID_SPACING
		draw_line(Vector2(x, 0), Vector2(x, vp.y), GRID_COLOR, 1.0)
	for j in range(rows + 1):
		var y := j * GRID_SPACING
		draw_line(Vector2(0, y), Vector2(vp.x, y), GRID_COLOR, 1.0)

func _draw_radar_sweep(vp: Vector2) -> void:
	# 右下角雷达装饰
	var center := Vector2(vp.x - 140, vp.y - 140)
	var radius := 100.0
	var rings := 3

	# 同心圆
	for i in range(1, rings + 1):
		var r := radius * i / rings
		draw_arc(center, r, 0, TAU, 64, Color(0.2, 0.5, 0.2, 0.3), 1.0)

	# 十字线
	draw_line(center - Vector2(radius, 0), center + Vector2(radius, 0), Color(0.2, 0.5, 0.2, 0.2), 1.0)
	draw_line(center - Vector2(0, radius), center + Vector2(0, radius), Color(0.2, 0.5, 0.2, 0.2), 1.0)

	# 扫描线
	var sweep_end := center + Vector2(cos(_sweep_angle), sin(_sweep_angle)) * radius
	draw_line(center, sweep_end, Color(0.3, 1.0, 0.3, 0.6), 1.5)

	# 扫描尾迹
	var trail_steps := 20
	for i in range(trail_steps):
		var t := float(i) / trail_steps
		var a := _sweep_angle - t * 0.8
		var end := center + Vector2(cos(a), sin(a)) * radius
		var alpha := 0.3 * (1.0 - t)
		draw_line(center, end, Color(0.3, 1.0, 0.3, alpha), 1.0)

	# 随机点
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	for i in range(8):
		var angle := rng.randf() * TAU
		var dist := rng.randf_range(10, radius - 5)
		var dot_pos := center + Vector2(cos(angle), sin(angle)) * dist
		# 被扫描线扫过时闪亮
		var dot_angle := fmod(angle + TAU, TAU)
		var sweep_norm := fmod(_sweep_angle + TAU, TAU)
		var diff := fmod(sweep_norm - dot_angle + TAU, TAU)
		var brightness := exp(-diff * 2.0) * 0.8
		if brightness > 0.05:
			draw_circle(dot_pos, 2.0, Color(0.4, 1.0, 0.4, brightness))

func _draw_decorative_lines(vp: Vector2) -> void:
	# 左上角装饰框
	var margin := 60.0
	var corner_len := 30.0
	var c := LINE_COLOR

	# 左上
	draw_line(Vector2(margin, margin), Vector2(margin + corner_len, margin), c, 1.5)
	draw_line(Vector2(margin, margin), Vector2(margin, margin + corner_len), c, 1.5)
	# 右上
	draw_line(Vector2(vp.x - margin, margin), Vector2(vp.x - margin - corner_len, margin), c, 1.5)
	draw_line(Vector2(vp.x - margin, margin), Vector2(vp.x - margin, margin + corner_len), c, 1.5)
	# 左下
	draw_line(Vector2(margin, vp.y - margin), Vector2(margin + corner_len, vp.y - margin), c, 1.5)
	draw_line(Vector2(margin, vp.y - margin), Vector2(margin, vp.y - margin - corner_len), c, 1.5)
	# 右下
	draw_line(Vector2(vp.x - margin, vp.y - margin), Vector2(vp.x - margin - corner_len, vp.y - margin), c, 1.5)
	draw_line(Vector2(vp.x - margin, vp.y - margin), Vector2(vp.x - margin, vp.y - margin - corner_len), c, 1.5)

	# 底部扫描线动画
	var scan_x := fmod(_time * 200.0, vp.x + 200) - 100
	draw_line(Vector2(scan_x, vp.y - 40), Vector2(scan_x, vp.y - 55), Color(0.3, 1.0, 0.3, 0.2), 1.0)

func _build_ui() -> void:
	_canvas = CanvasLayer.new()
	_canvas.layer = 10
	add_child(_canvas)

	# --- 主容器 ---
	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.alignment = BoxContainer.ALIGNMENT_CENTER
	root.add_theme_constant_override("separation", 0)
	_canvas.add_child(root)

	# 上部空白
	var spacer_top := Control.new()
	spacer_top.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer_top.size_flags_stretch_ratio = 0.3
	root.add_child(spacer_top)

	# --- 标题区域 ---
	var title_box := VBoxContainer.new()
	title_box.alignment = BoxContainer.ALIGNMENT_CENTER
	title_box.add_theme_constant_override("separation", 8)
	root.add_child(title_box)

	# 标题
	var title := Label.new()
	title.text = "A G L"
	title.add_theme_font_size_override("font_size", 72)
	title.add_theme_color_override("font_color", TITLE_COLOR)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_box.add_child(title)

	# 副标题
	var subtitle := Label.new()
	subtitle.text = "AIR  GROUND  LINK  //  俯视战斗机模拟"
	subtitle.add_theme_font_size_override("font_size", 16)
	subtitle.add_theme_color_override("font_color", SUBTITLE_COLOR)
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_box.add_child(subtitle)

	# 分隔
	var sep_spacer := Control.new()
	sep_spacer.custom_minimum_size = Vector2(0, 40)
	root.add_child(sep_spacer)

	# --- 模式选择区域 ---
	_mode_container = VBoxContainer.new()
	_mode_container.alignment = BoxContainer.ALIGNMENT_CENTER
	_mode_container.add_theme_constant_override("separation", 12)
	_mode_container.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	root.add_child(_mode_container)

	# 模式标签
	var mode_label := Label.new()
	mode_label.text = "[ 选择模式 ]"
	mode_label.add_theme_font_size_override("font_size", 14)
	mode_label.add_theme_color_override("font_color", Color(0.5, 0.7, 0.5, 0.6))
	mode_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_mode_container.add_child(mode_label)

	# 沙盒模式按钮
	_add_mode_button("沙盒测试", "自由飞行 / 武器测试 / AI 对战", _on_sandbox_pressed)

	# 生存模式
	_add_mode_button("生存模式", "击落敌机 / 升级武器 / 存活越久越好", _on_survivor_pressed)

	# 未来模式占位（灰色不可用）
	_add_mode_button("任务模式", "即将推出", Callable(), true)

	# 下部空白
	var spacer_bottom := Control.new()
	spacer_bottom.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer_bottom.size_flags_stretch_ratio = 0.5
	root.add_child(spacer_bottom)

	# --- 底部版本信息 ---
	var version_label := Label.new()
	version_label.text = "v0.1.0-dev  //  Godot 4.6  //  GL Compatibility"
	version_label.add_theme_font_size_override("font_size", 11)
	version_label.add_theme_color_override("font_color", Color(0.3, 0.4, 0.3, 0.4))
	version_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(version_label)

	var bottom_margin := Control.new()
	bottom_margin.custom_minimum_size = Vector2(0, 20)
	root.add_child(bottom_margin)

func _add_mode_button(title: String, desc: String, callback: Callable, disabled := false) -> void:
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(360, 56)
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT

	if disabled:
		btn.text = "  %s  —  %s" % [title, desc]
		btn.disabled = true
		btn.add_theme_color_override("font_disabled_color", Color(0.3, 0.4, 0.3, 0.4))
	else:
		btn.text = "  %s  —  %s" % [title, desc]

	btn.add_theme_font_size_override("font_size", 16)

	# 按钮样式
	var style_normal := StyleBoxFlat.new()
	style_normal.bg_color = Color(0.08, 0.12, 0.08, 0.6)
	style_normal.border_color = Color(0.3, 0.6, 0.3, 0.4)
	style_normal.set_border_width_all(1)
	style_normal.set_corner_radius_all(2)
	style_normal.set_content_margin_all(8)
	btn.add_theme_stylebox_override("normal", style_normal)

	var style_hover := StyleBoxFlat.new()
	style_hover.bg_color = Color(0.12, 0.2, 0.12, 0.8)
	style_hover.border_color = Color(0.4, 1.0, 0.4, 0.7)
	style_hover.set_border_width_all(1)
	style_hover.set_corner_radius_all(2)
	style_hover.set_content_margin_all(8)
	btn.add_theme_stylebox_override("hover", style_hover)

	var style_pressed := StyleBoxFlat.new()
	style_pressed.bg_color = Color(0.15, 0.25, 0.15, 0.9)
	style_pressed.border_color = Color(0.5, 1.0, 0.5, 0.9)
	style_pressed.set_border_width_all(2)
	style_pressed.set_corner_radius_all(2)
	style_pressed.set_content_margin_all(8)
	btn.add_theme_stylebox_override("pressed", style_pressed)

	if disabled:
		var style_disabled := StyleBoxFlat.new()
		style_disabled.bg_color = Color(0.05, 0.06, 0.05, 0.3)
		style_disabled.border_color = Color(0.2, 0.25, 0.2, 0.2)
		style_disabled.set_border_width_all(1)
		style_disabled.set_corner_radius_all(2)
		style_disabled.set_content_margin_all(8)
		btn.add_theme_stylebox_override("disabled", style_disabled)

	if not disabled and callback.is_valid():
		btn.pressed.connect(callback)

	_mode_container.add_child(btn)

func _on_sandbox_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/main.tscn")

func _on_survivor_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/survivor_select.tscn")
