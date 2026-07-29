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

## 警告条颜色 —— 从刺眼红改为温和的琥珀/暖金，边界其实是"补给友好区"，不是危险区
const WARN_COLOR := Color(0.98, 0.78, 0.35, 1.0)
const WARN_BG := Color(0.18, 0.13, 0.04, 0.75)
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
## 可选：指向 ZoneData —— BOSS 阶段下警告条改文案，告诉玩家无法补给
var zones: ZoneData

func _ready() -> void:
	layer = 20  # 在一般 HUD 之上
	_build_warning_bar()
	_build_menu()
	_warn_bg.visible = false
	_menu_root.visible = false

func _process(_delta: float) -> void:
	# 警告条温和呼吸（不是刺眼闪烁）—— 边界是补给友好区，不是危险区
	if _warn_bg.visible:
		var t := (sin(Time.get_ticks_msec() / 400.0) * 0.5 + 0.5)
		_warn_bg.color = WARN_BG.lerp(Color(0.32, 0.22, 0.06, 0.85), t)

# ══════════════════════════════════════════════
#  信号入口（由 survivor_mode 接线到 MapBoundary）
# ══════════════════════════════════════════════

func on_approach(active: bool, distance_m: float) -> void:
	if active:
		_warn_bg.visible = true
		# 与补给禁用闸同源（spec survivor-loop §3.1）：BOSS **解锁**就换"无法补给"文案，
		# 不等玩家在战术地图选中 BOSS 圈——否则 PRE_STAGE 段文案会承诺一个已经被拒的补给
		var boss_phase: bool = zones != null and (zones.is_boss_phase() or zones.boss_unlocked)
		var key := "BOUNDARY_APPROACH_WARN_BOSS" if boss_phase else "BOUNDARY_APPROACH_WARN"
		_warn_label.text = tr(key) % (distance_m / 1000.0)
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

	# 顺序：补给（最常用） → 继续作战 → 撤退（最下，避免误点结算战局）
	var btn_supply := _make_button(tr("BOUNDARY_BTN_SUPPLY"))
	btn_supply.pressed.connect(_on_supply_pressed)
	vb.add_child(btn_supply)

	var btn_cancel := _make_button(tr("BOUNDARY_BTN_CANCEL"))
	btn_cancel.pressed.connect(_on_cancel_pressed)
	vb.add_child(btn_cancel)

	var btn_retreat := _make_button(tr("BOUNDARY_BTN_RETREAT"))
	btn_retreat.pressed.connect(_on_retreat_pressed)
	vb.add_child(btn_retreat)

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
	Presentation.present(self, "panel_in")

func _close_menu() -> void:
	_menu_visible = false
	# 只隐藏 _menu_root 而非整个 CanvasLayer —— 后者还要继续画越界警告
	Presentation.dismiss(self, "panel_out", _menu_root)

func get_transition_elements() -> Array[Control]:
	var out: Array[Control] = []
	if _menu_root:
		out.append(_menu_root)
	return out

func _on_retreat_pressed() -> void:
	_close_menu()
	retreat_confirmed.emit()

func _on_supply_pressed() -> void:
	_close_menu()
	supply_confirmed.emit()

func _on_cancel_pressed() -> void:
	_close_menu()
	cancelled.emit()
