class_name PauseMenu
extends CanvasLayer

## 生存模式：暂停菜单（spec pause-menu）
##
## ESC 不再无确认地直接销毁战局回主菜单，而是：冻结全场 → 弹确认页 →
## 玩家自己选"继续作战"还是"返回主菜单"。
##
## 时间控制完全交给表演导演（panel_in 第 0 帧 hard_pause(true)，
## panel_out 第 0 帧 hard_pause(false)），本模块不直写 get_tree().paused。
##
## 信号：
##   resumed      → 继续作战（survivor_mode 无需做任何事，仅供日志/扩展）
##   quit_to_menu → 确认退出（由 survivor_mode 执行 clear_all + 切场景）
##
## ⚠ process_mode = ALWAYS：硬暂停期间 survivor_mode 收不到输入，
##   所以"ESC 关闭"必须由本模块自己处理（与 tactical_map 同一分工）。

signal resumed
signal quit_to_menu

const PANEL_BG := Color(0.04, 0.05, 0.06, 0.92)
const PANEL_BORDER := Color(0.35, 0.75, 1.0, 0.9)
const TEXT_TITLE := Color(0.6, 0.9, 1.0, 1.0)
const TEXT_BODY := Color(0.75, 0.8, 0.8, 1.0)
const TEXT_WARN := Color(0.95, 0.65, 0.35, 1.0)
const BTN_BG := Color(0.08, 0.1, 0.11, 1.0)
const BTN_BORDER := Color(0.35, 0.5, 0.5, 0.8)
const BTN_HOVER_BG := Color(0.15, 0.2, 0.22, 1.0)

var _root: Control
var _is_open: bool = false

func _ready() -> void:
	layer = 21  # 高于越界菜单(20)/战术地图(15)；压暗层由导演自动落到其下
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	_root.visible = false

func _unhandled_input(event: InputEvent) -> void:
	if not _is_open:
		return
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		_on_resume_pressed()

func is_open() -> bool:
	return _is_open

# ══════════════════════════════════════════════
#  开关
# ══════════════════════════════════════════════

func open() -> void:
	if _is_open:
		return
	_is_open = true
	_root.visible = true
	AudioManager.set_music_muffled(true)
	# 暂停与淡入统一交给表演导演（时间的唯一入口，spec ui-transition §2.2）
	Presentation.present(self, "panel_in")

func close() -> void:
	if not _is_open:
		return
	_is_open = false
	AudioManager.set_music_muffled(false)
	# 解暂停在 panel_out 第 0 帧，dismiss 之后只剩视觉尾巴
	Presentation.dismiss(self, "panel_out")

## 表演导演的错开出入场元素（spec ui-transition §4.3）
func get_transition_elements() -> Array[Control]:
	var out: Array[Control] = []
	if _root:
		out.append(_root)
	return out

# ══════════════════════════════════════════════
#  UI 构建
# ══════════════════════════════════════════════

func _build_ui() -> void:
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.process_mode = Node.PROCESS_MODE_ALWAYS  # 暂停时也响应点击
	add_child(_root)

	var dim := ColorRect.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0, 0, 0, 0.55)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(dim)

	var panel := PanelContainer.new()
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -230
	panel.offset_right = 230
	panel.offset_top = -150
	panel.offset_bottom = 150
	var style := StyleBoxFlat.new()
	style.bg_color = PANEL_BG
	style.border_color = PANEL_BORDER
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(24)
	panel.add_theme_stylebox_override("panel", style)
	_root.add_child(panel)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	panel.add_child(vb)

	var title := Label.new()
	title.text = tr("PAUSE_MENU_TITLE")
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", TEXT_TITLE)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(title)

	var body := Label.new()
	body.text = tr("PAUSE_MENU_BODY")
	body.add_theme_font_size_override("font_size", 12)
	body.add_theme_color_override("font_color", TEXT_BODY)
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(body)

	var warn := Label.new()
	warn.text = tr("PAUSE_MENU_WARN")
	warn.add_theme_font_size_override("font_size", 11)
	warn.add_theme_color_override("font_color", TEXT_WARN)
	warn.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	warn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(warn)

	var sp := Control.new()
	sp.custom_minimum_size = Vector2(0, 8)
	vb.add_child(sp)

	# 顺序：继续（安全项）在上，退出（破坏性）在下，避免误点丢整局
	var btn_resume := _make_button(tr("PAUSE_BTN_RESUME"))
	btn_resume.pressed.connect(_on_resume_pressed)
	vb.add_child(btn_resume)

	var btn_quit := _make_button(tr("PAUSE_BTN_QUIT"))
	btn_quit.pressed.connect(_on_quit_pressed)
	vb.add_child(btn_quit)

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
#  交互
# ══════════════════════════════════════════════

func _on_resume_pressed() -> void:
	close()
	resumed.emit()

func _on_quit_pressed() -> void:
	# 退出不走 dismiss：场景马上销毁，视觉尾巴无意义，
	# 且解暂停由 survivor_mode 的 Presentation.clear_all() 负责
	_is_open = false
	_root.visible = false
	AudioManager.set_music_muffled(false)
	quit_to_menu.emit()
