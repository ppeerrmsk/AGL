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
	CombatUnit.reset_id_allocator()
	CallsignDB.reset()
	_build_ui()


## ── Debug 快捷键（开发用） ──
## Ctrl + M           → +1000 功勋
## Ctrl + Shift + M   → -1000 功勋（夹底 0）
## Ctrl + Alt + M     → 功勋归零
## 注：仅在主菜单生效；不入正式发布的 build 时可去掉本函数
func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	if event.keycode != KEY_M or not event.ctrl_pressed:
		return
	var delta: int = 1000
	var msg: String = ""
	if event.alt_pressed:
		MeritLedger.debug_reset()
		msg = "[debug] merit reset → 0"
	elif event.shift_pressed:
		var cur: int = MeritLedger.get_total()
		var sub: int = mini(delta, cur)
		MeritLedger.debug_add(-sub)
		msg = "[debug] merit -%d → %d" % [sub, MeritLedger.get_total()]
	else:
		MeritLedger.debug_add(delta)
		msg = "[debug] merit +%d → %d" % [delta, MeritLedger.get_total()]
	_show_toast(msg)
	get_viewport().set_input_as_handled()

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
	title.text = tr("MENU_TITLE")
	title.add_theme_font_size_override("font_size", 72)
	title.add_theme_color_override("font_color", TITLE_COLOR)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_box.add_child(title)

	# 副标题
	var subtitle := Label.new()
	subtitle.text = tr("MENU_SUBTITLE")
	subtitle.add_theme_font_size_override("font_size", 16)
	subtitle.add_theme_color_override("font_color", SUBTITLE_COLOR)
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_box.add_child(subtitle)

	# 功勋显示（标题下方居中，硬币 + 数字）
	_build_merit_display(title_box)

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
	mode_label.text = tr("MENU_MODE_LABEL")
	mode_label.add_theme_font_size_override("font_size", 14)
	mode_label.add_theme_color_override("font_color", Color(0.5, 0.7, 0.5, 0.6))
	mode_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_mode_container.add_child(mode_label)

	# 测试版：生存模式为主显示
	_add_mode_button(tr("MENU_MODE_SURVIVOR_NAME"), tr("MENU_MODE_SURVIVOR_DESC"), _on_survivor_pressed)

	# 未来模式占位（灰色不可用）
	_add_mode_button(tr("MENU_MODE_MISSION_NAME"), tr("MENU_MODE_MISSION_DESC"), Callable(), true)

	# 测试版：沙盒入口缩成右下角小按钮
	_build_sandbox_corner_button()

	# 下部空白
	var spacer_bottom := Control.new()
	spacer_bottom.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer_bottom.size_flags_stretch_ratio = 0.5
	root.add_child(spacer_bottom)

	# --- 语言切换 ---
	_build_language_switcher(root)

	# --- 音频设置按钮 ---
	_build_audio_button(root)

	# --- 底部版本信息 ---
	var version_label := Label.new()
	version_label.text = tr("MENU_VERSION")
	version_label.add_theme_font_size_override("font_size", 11)
	version_label.add_theme_color_override("font_color", Color(0.3, 0.4, 0.3, 0.4))
	version_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(version_label)

	var bottom_margin := Control.new()
	bottom_margin.custom_minimum_size = Vector2(0, 20)
	root.add_child(bottom_margin)

## 底部语言切换：中 / EN / 日（按钮文字不翻译，保持识别性）
func _build_language_switcher(root: VBoxContainer) -> void:
	var lang_row := HBoxContainer.new()
	lang_row.alignment = BoxContainer.ALIGNMENT_CENTER
	lang_row.add_theme_constant_override("separation", 8)
	root.add_child(lang_row)

	var current_locale: String = LocaleManager.get_current_locale()
	var options := [
		{"code": "zh", "label": "中"},
		{"code": "en", "label": "EN"},
		{"code": "ja", "label": "日"},
	]
	for opt in options:
		var btn := Button.new()
		btn.text = opt["label"]
		btn.custom_minimum_size = Vector2(44, 26)
		btn.add_theme_font_size_override("font_size", 13)
		var is_active: bool = (opt["code"] == current_locale)

		var style_normal := StyleBoxFlat.new()
		if is_active:
			style_normal.bg_color = Color(0.12, 0.22, 0.12, 0.85)
			style_normal.border_color = Color(0.45, 1.0, 0.45, 0.75)
			btn.add_theme_color_override("font_color", Color(0.6, 1.0, 0.6))
		else:
			style_normal.bg_color = Color(0.05, 0.08, 0.05, 0.45)
			style_normal.border_color = Color(0.25, 0.45, 0.25, 0.35)
			btn.add_theme_color_override("font_color", Color(0.5, 0.7, 0.5, 0.75))
		style_normal.set_border_width_all(1)
		style_normal.set_corner_radius_all(2)
		style_normal.set_content_margin_all(4)
		btn.add_theme_stylebox_override("normal", style_normal)

		var style_hover := StyleBoxFlat.new()
		style_hover.bg_color = Color(0.12, 0.2, 0.12, 0.8)
		style_hover.border_color = Color(0.5, 1.0, 0.5, 0.7)
		style_hover.set_border_width_all(1)
		style_hover.set_corner_radius_all(2)
		style_hover.set_content_margin_all(4)
		btn.add_theme_stylebox_override("hover", style_hover)
		btn.add_theme_color_override("font_hover_color", Color(0.9, 1.0, 0.6))

		var code_capture: String = opt["code"]
		btn.pressed.connect(func(): LocaleManager.set_locale_persistent(code_capture))
		lang_row.add_child(btn)

	var pad := Control.new()
	pad.custom_minimum_size = Vector2(0, 8)
	root.add_child(pad)

## 小号「音频设置」按钮，打开叠加面板
func _build_audio_button(root: VBoxContainer) -> void:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	root.add_child(row)

	var btn := Button.new()
	btn.text = tr("MENU_AUDIO_BUTTON")
	btn.custom_minimum_size = Vector2(140, 28)
	btn.add_theme_font_size_override("font_size", 13)

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.08, 0.05, 0.45)
	style.border_color = Color(0.25, 0.45, 0.25, 0.35)
	style.set_border_width_all(1)
	style.set_corner_radius_all(2)
	style.set_content_margin_all(4)
	btn.add_theme_stylebox_override("normal", style)
	btn.add_theme_color_override("font_color", Color(0.5, 0.7, 0.5, 0.85))

	var style_hover := StyleBoxFlat.new()
	style_hover.bg_color = Color(0.12, 0.2, 0.12, 0.8)
	style_hover.border_color = Color(0.5, 1.0, 0.5, 0.7)
	style_hover.set_border_width_all(1)
	style_hover.set_corner_radius_all(2)
	style_hover.set_content_margin_all(4)
	btn.add_theme_stylebox_override("hover", style_hover)
	btn.add_theme_color_override("font_hover_color", Color(0.9, 1.0, 0.6))

	btn.pressed.connect(_on_audio_settings_pressed)
	row.add_child(btn)

	# 删除存档按钮（测试用）：重置首次引导 / 进度标志
	var reset_btn := Button.new()
	reset_btn.text = tr("MENU_RESET_SAVE_BUTTON")
	reset_btn.custom_minimum_size = Vector2(140, 28)
	reset_btn.add_theme_font_size_override("font_size", 13)
	var rs_normal := StyleBoxFlat.new()
	rs_normal.bg_color = Color(0.10, 0.05, 0.05, 0.45)
	rs_normal.border_color = Color(0.55, 0.25, 0.22, 0.4)
	rs_normal.set_border_width_all(1)
	rs_normal.set_corner_radius_all(2)
	rs_normal.set_content_margin_all(4)
	reset_btn.add_theme_stylebox_override("normal", rs_normal)
	reset_btn.add_theme_color_override("font_color", Color(0.75, 0.5, 0.45, 0.85))
	var rs_hover := StyleBoxFlat.new()
	rs_hover.bg_color = Color(0.2, 0.08, 0.08, 0.8)
	rs_hover.border_color = Color(1.0, 0.45, 0.4, 0.7)
	rs_hover.set_border_width_all(1)
	rs_hover.set_corner_radius_all(2)
	rs_hover.set_content_margin_all(4)
	reset_btn.add_theme_stylebox_override("hover", rs_hover)
	reset_btn.add_theme_color_override("font_hover_color", Color(1.0, 0.75, 0.55))
	reset_btn.pressed.connect(_on_reset_save_pressed)
	row.add_child(reset_btn)

	var bottom_pad := Control.new()
	bottom_pad.custom_minimum_size = Vector2(0, 6)
	root.add_child(bottom_pad)

## 要在重置时删除的存档文件列表（保留 locale.cfg / audio.cfg 用户偏好）
## tutorial.cfg 走文件删除；merit/loadout 走 ledger.debug_reset()（同时清内存 + 重写 cfg）
const RESET_SAVE_FILES := [
	"user://tutorial.cfg",
]

func _on_reset_save_pressed() -> void:
	var dlg := ConfirmationDialog.new()
	dlg.dialog_text = tr("MENU_RESET_SAVE_CONFIRM")
	dlg.ok_button_text = tr("MENU_RESET_SAVE_CONFIRM_BTN")
	dlg.cancel_button_text = tr("MENU_RESET_SAVE_CANCEL")
	dlg.title = tr("MENU_RESET_SAVE_BUTTON")
	_canvas.add_child(dlg)
	dlg.confirmed.connect(func():
		var removed := 0
		for path in RESET_SAVE_FILES:
			if FileAccess.file_exists(path):
				DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
				removed += 1
		# AutoLoad 已在内存里持有这些 ledger 状态，单删 cfg 不够，必须调 debug_reset
		MeritLedger.debug_reset()
		removed += 1
		LoadoutLedger.debug_reset()
		removed += 1
		_show_toast(tr("MENU_RESET_SAVE_OK") % removed)
		dlg.queue_free())
	dlg.canceled.connect(func(): dlg.queue_free())
	dlg.popup_centered()

func _show_toast(text: String) -> void:
	var wrap := PanelContainer.new()
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.05, 0.1, 0.05, 0.92)
	bg.border_color = Color(0.4, 0.9, 0.4, 0.6)
	bg.set_border_width_all(1)
	bg.set_corner_radius_all(3)
	bg.set_content_margin_all(10)
	wrap.add_theme_stylebox_override("panel", bg)
	wrap.set_anchors_preset(Control.PRESET_CENTER_TOP)
	wrap.position = Vector2(-140, 80)
	wrap.custom_minimum_size = Vector2(280, 0)
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 14)
	lbl.add_theme_color_override("font_color", Color(0.8, 1.0, 0.6))
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	wrap.add_child(lbl)
	_canvas.add_child(wrap)
	var tw := create_tween()
	tw.tween_interval(1.8)
	tw.tween_property(wrap, "modulate:a", 0.0, 0.5)
	tw.tween_callback(wrap.queue_free)

func _on_audio_settings_pressed() -> void:
	var panel = preload("res://scripts/audio/audio_settings_panel.gd").new()
	add_child(panel)
	panel.closed.connect(panel.queue_free)
	panel.open()

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

## 测试版：把沙盒入口做成右下角小按钮（不走主菜单 VBox）
func _build_sandbox_corner_button() -> void:
	var btn := Button.new()
	btn.text = tr("MENU_MODE_SANDBOX_NAME")
	btn.custom_minimum_size = Vector2(110, 24)
	btn.add_theme_font_size_override("font_size", 11)
	btn.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	btn.position = Vector2(-130, -40)

	var style_normal := StyleBoxFlat.new()
	style_normal.bg_color = Color(0.05, 0.08, 0.05, 0.45)
	style_normal.border_color = Color(0.25, 0.45, 0.25, 0.35)
	style_normal.set_border_width_all(1)
	style_normal.set_corner_radius_all(2)
	style_normal.set_content_margin_all(4)
	btn.add_theme_stylebox_override("normal", style_normal)
	btn.add_theme_color_override("font_color", Color(0.4, 0.6, 0.4, 0.7))

	var style_hover := StyleBoxFlat.new()
	style_hover.bg_color = Color(0.1, 0.16, 0.1, 0.75)
	style_hover.border_color = Color(0.4, 0.8, 0.4, 0.6)
	style_hover.set_border_width_all(1)
	style_hover.set_corner_radius_all(2)
	style_hover.set_content_margin_all(4)
	btn.add_theme_stylebox_override("hover", style_hover)
	btn.add_theme_color_override("font_hover_color", Color(0.8, 1.0, 0.6))

	btn.pressed.connect(_on_sandbox_pressed)
	_canvas.add_child(btn)

func _on_survivor_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/survivor_map_select.tscn")

## 标题下方的功勋徽章 + 数字（局外货币）
func _build_merit_display(parent: VBoxContainer) -> void:
	var pad := Control.new()
	pad.custom_minimum_size = Vector2(0, 10)
	parent.add_child(pad)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 8)
	parent.add_child(row)

	var coin := preload("res://scripts/meta/merit_coin_icon.gd").new()
	coin.radius = 11.0
	row.add_child(coin)

	var label := Label.new()
	label.text = "%s  %d" % [tr("MENU_MERIT_LABEL"), MeritLedger.get_total()]
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_color_override("font_color", Color(0.85, 0.75, 0.35))
	row.add_child(label)

	# 余额变化时实时刷新（如果以后加调试按钮 / 改装界面跳回主菜单）
	MeritLedger.merit_changed.connect(func(total: int, _delta: int):
		if is_instance_valid(label):
			label.text = "%s  %d" % [tr("MENU_MERIT_LABEL"), total])
