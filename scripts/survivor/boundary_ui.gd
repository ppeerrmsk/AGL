class_name BoundaryUI
extends CanvasLayer

## 生存模式：边界警告条 + 撤退菜单
##
## 由 MapBoundary 的信号驱动：
##   approach_warning(active, distance_m)  → 顶部闪烁红条
##   boundary_crossed                       → 弹出模态菜单
##
## 撤退菜单回发信号：
##   retreat_confirmed    → 结束战局（由 survivor_mode 处理）
##   supply_confirmed     → 补给（回血 + 加 1 分钟 Token）
##   cancelled            → 关闭菜单，玩家继续作战

signal retreat_confirmed
signal supply_confirmed
signal cancelled

const WARN_COLOR := Color(0.95, 0.2, 0.2, 1.0)
const WARN_BG := Color(0.15, 0.03, 0.03, 0.75)
const PANEL_BG := Color(0.04, 0.05, 0.06, 0.92)
const PANEL_BORDER := Color(0.85, 0.25, 0.25, 0.9)
const TEXT_TITLE := Color(0.95, 0.45, 0.45, 1.0)
const TEXT_BODY := Color(0.75, 0.8, 0.8, 1.0)
const BTN_BG := Color(0.08, 0.1, 0.11, 1.0)
const BTN_BORDER := Color(0.35, 0.5, 0.5, 0.8)
const BTN_HOVER_BG := Color(0.15, 0.2, 0.22, 1.0)

var _warn_label: Label
var _warn_bg: ColorRect
var _menu_root: Control
var _menu_visible: bool = false

func _ready() -> void:
	layer = 20  # 在一般 HUD 之上
	_build_warning_bar()
	_build_menu()
	_warn_bg.visible = false
	_menu_root.visible = false

func _process(delta: float) -> void:
	# 警告条脉冲闪烁
	if _warn_bg.visible:
		var t := (sin(Time.get_ticks_msec() / 150.0) * 0.5 + 0.5)
		_warn_bg.color = WARN_BG.lerp(Color(WARN_BG.r * 2.0, 0.06, 0.06, 0.85), t)

# ══════════════════════════════════════════════
#  信号入口（由 survivor_mode 接线到 MapBoundary）
# ══════════════════════════════════════════════

func on_approach(active: bool, distance_m: float) -> void:
	if active:
		_warn_bg.visible = true
		_warn_label.text = tr("BOUNDARY_APPROACH_WARN") % (distance_m / 1000.0)
	else:
		_warn_bg.visible = false

func on_crossed() -> void:
	_open_menu()

# ══════════════════════════════════════════════
#  UI 构建
# ══════════════════════════════════════════════

func _build_warning_bar() -> void:
	_warn_bg = ColorRect.new()
	_warn_bg.anchor_left = 0.25
	_warn_bg.anchor_right = 0.75
	_warn_bg.anchor_top = 0.0
	_warn_bg.anchor_bottom = 0.0
	_warn_bg.offset_top = 20
	_warn_bg.offset_bottom = 60
	_warn_bg.color = WARN_BG
	_warn_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_warn_bg)

	_warn_label = Label.new()
	_warn_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_warn_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_warn_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_warn_label.add_theme_font_size_override("font_size", 16)
	_warn_label.add_theme_color_override("font_color", WARN_COLOR)
	_warn_bg.add_child(_warn_label)

func _build_menu() -> void:
	_menu_root = Control.new()
	_menu_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_menu_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_menu_root.process_mode = Node.PROCESS_MODE_ALWAYS  # 暂停时也响应输入
	add_child(_menu_root)

	var dim := ColorRect.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0, 0, 0, 0.55)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_menu_root.add_child(dim)

	var panel := PanelContainer.new()
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -230
	panel.offset_right = 230
	panel.offset_top = -170
	panel.offset_bottom = 170
	var style := StyleBoxFlat.new()
	style.bg_color = PANEL_BG
	style.border_color = PANEL_BORDER
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(24)
	panel.add_theme_stylebox_override("panel", style)
	_menu_root.add_child(panel)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	panel.add_child(vb)

	var title := Label.new()
	title.text = tr("BOUNDARY_MENU_TITLE")
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", TEXT_TITLE)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(title)

	var body := Label.new()
	body.text = tr("BOUNDARY_MENU_BODY")
	body.add_theme_font_size_override("font_size", 12)
	body.add_theme_color_override("font_color", TEXT_BODY)
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(body)

	var sp := Control.new()
	sp.custom_minimum_size = Vector2(0, 8)
	vb.add_child(sp)

	var btn_retreat := _make_button(tr("BOUNDARY_BTN_RETREAT"))
	btn_retreat.pressed.connect(_on_retreat_pressed)
	vb.add_child(btn_retreat)

	var btn_supply := _make_button(tr("BOUNDARY_BTN_SUPPLY"))
	btn_supply.pressed.connect(_on_supply_pressed)
	vb.add_child(btn_supply)

	var btn_cancel := _make_button(tr("BOUNDARY_BTN_CANCEL"))
	btn_cancel.pressed.connect(_on_cancel_pressed)
	vb.add_child(btn_cancel)

func _make_button(label: String) -> Button:
	var btn := Button.new()
	btn.text = label
	btn.custom_minimum_size = Vector2(360, 40)
	btn.add_theme_font_size_override("font_size", 14)
	btn.add_theme_color_override("font_color", TEXT_BODY)
	var s := StyleBoxFlat.new()
	s.bg_color = BTN_BG
	s.border_color = BTN_BORDER
	s.set_border_width_all(1)
	s.set_corner_radius_all(3)
	s.set_content_margin_all(8)
	btn.add_theme_stylebox_override("normal", s)
	var sh := s.duplicate() as StyleBoxFlat
	sh.bg_color = BTN_HOVER_BG
	sh.border_color = PANEL_BORDER
	btn.add_theme_stylebox_override("hover", sh)
	return btn

# ══════════════════════════════════════════════
#  菜单交互
# ══════════════════════════════════════════════

func _open_menu() -> void:
	_menu_visible = true
	_menu_root.visible = true
	_warn_bg.visible = false
	get_tree().paused = true

func _close_menu() -> void:
	_menu_visible = false
	_menu_root.visible = false
	get_tree().paused = false

func _on_retreat_pressed() -> void:
	_close_menu()
	retreat_confirmed.emit()

func _on_supply_pressed() -> void:
	_close_menu()
	supply_confirmed.emit()

func _on_cancel_pressed() -> void:
	_close_menu()
	cancelled.emit()
