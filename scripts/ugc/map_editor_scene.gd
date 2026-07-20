class_name MapEditorScene
extends Node2D

## 地图编辑器主场景（map-editor spec §4 三区布局 + §2.4 文件生命周期 + 阶段 2 笔刷）
##
## 布局：左上=素材库（图层选择）/ 中间=画布（MapEditorCanvas 静态层 + 本节点画光标）/
##       顶部=工具栏（笔刷/橡皮/尺寸/撤销/存读/试飞）
## 重绘纪律：静态层（canvas 子节点）只在数据变化时重绘；光标/笔画格子由本节点
## 自己的 _draw 承担（轻量，随鼠标重绘不拖静态层）。
## 相机：复用 CameraController（WASD/中键平移/钳制），缩放范围编辑器自管
## （看全 30km 图需要比战斗更低的 zoom 下限）。

const EDITOR_ZOOM_MAX := 3.0
## 缩放下限运行时按"看全图再留 15% 余量"计算（60km 图 ≈ 0.03；随 map-expansion 主开关）
var _zoom_min := 0.03
const AUTOSAVE_INTERVAL_S := 120.0
const MAPS_DIR := "user://ugc/maps"
const TESTFLIGHT_PATH := "user://ugc/maps/_testflight.json"

const CURSOR_COLOR := Color(1.0, 1.0, 1.0, 0.55)
const STROKE_CELL_ALPHA := 0.45

var doc: MapDocument
var current_path := ""            ## 当前存档路径（"" = 未命名）
var doc_dirty := false            ## 有未保存改动（标题栏 *）

## 工具状态
var active_layer := "land"
var tool_eraser := false
var brush_cells := 3              ## 笔刷直径（格），§2.1：1/3/5/9
var _painting := false
var _last_paint_cell := Vector2i(-1, -1)
var _hover_cell := Vector2i(-1, -1)

var _camera: Camera2D
var _cam_ctrl: CameraController
var _canvas: MapEditorCanvas
var _autosave_timer: Timer

## UI 引用
var _title_label: Label
var _layer_buttons: Dictionary = {}
var _tool_brush_btn: Button
var _tool_eraser_btn: Button
var _size_buttons: Dictionary = {}
var _hint_label: Label
var _saveas_dialog: ConfirmationDialog
var _saveas_edit: LineEdit
var _open_dialog: FileDialog
var _exit_dialog: ConfirmationDialog
var _recover_dialog: ConfirmationDialog
var _pending_recover_path := ""

const CELL_LAYER_KEYS := {
	"land": "EDITOR_LAYER_LAND",
	"mountain": "EDITOR_LAYER_MOUNTAIN",
	"forest": "EDITOR_LAYER_FOREST",
	"farmland": "EDITOR_LAYER_FARMLAND",
	"beach": "EDITOR_LAYER_BEACH",
	"urban": "EDITOR_LAYER_URBAN",
}


func _ready() -> void:
	doc = MapDocument.new()

	_camera = Camera2D.new()
	_camera.make_current()
	add_child(_camera)
	_cam_ctrl = CameraController.new()
	add_child(_cam_ctrl)
	_cam_ctrl.setup(_camera)
	var half := MapDocument.WORLD_HALF_PX
	_cam_ctrl.set_world_bounds(Rect2(-half * 1.4, -half * 1.4, half * 2.8, half * 2.8))
	# 开局看全图（编辑器缩放范围自管，绕过 CameraController 的战斗用下限；随世界尺寸自适应）
	var fit := get_viewport_rect().size.y / (half * 2.0 * 1.15)
	_zoom_min = fit * 0.85
	_cam_ctrl.target_zoom = fit
	_camera.zoom = Vector2(fit, fit)

	_canvas = MapEditorCanvas.new()
	_canvas.doc = doc
	add_child(_canvas)
	move_child(_canvas, 0)

	_build_ui()
	_refresh_title()

	_autosave_timer = Timer.new()
	_autosave_timer.wait_time = AUTOSAVE_INTERVAL_S
	_autosave_timer.timeout.connect(_do_autosave)
	add_child(_autosave_timer)
	_autosave_timer.start()


func _process(delta: float) -> void:
	_cam_ctrl.update(delta)


# ══════════════════════════════════════════════
#  输入：笔刷 / 相机
# ══════════════════════════════════════════════

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_zoom(1.15)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_zoom(1.0 / 1.15)
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_begin_stroke(false)
			else:
				_end_stroke()
		elif mb.button_index == MOUSE_BUTTON_RIGHT:
			# 右键 = 临时橡皮（快捷擦除，不切工具）
			if mb.pressed:
				_begin_stroke(true)
			else:
				_end_stroke()
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if Input.is_mouse_button_pressed(MOUSE_BUTTON_MIDDLE):
			_cam_ctrl.handle_drag(mm.relative)
		var cell := _mouse_cell()
		if cell != _hover_cell:
			_hover_cell = cell
			queue_redraw()
		if _painting and cell.x >= 0:
			_paint_line(_last_paint_cell, cell)
			_last_paint_cell = cell
	elif event is InputEventKey and event.pressed and not event.echo:
		var key := event as InputEventKey
		if key.keycode == KEY_S and key.ctrl_pressed:
			_save()
		elif key.keycode == KEY_Z and key.ctrl_pressed:
			_undo()
		elif key.keycode == KEY_ESCAPE:
			_request_exit()


var _stroke_erase := false

func _begin_stroke(erase: bool) -> void:
	var cell := _mouse_cell()
	if cell.x < 0 or _painting:
		return
	_painting = true
	_stroke_erase = erase or tool_eraser
	doc.push_undo(active_layer)
	_last_paint_cell = cell
	_stamp(cell)
	queue_redraw()


func _end_stroke() -> void:
	if not _painting:
		return
	_painting = false
	doc.mark_dirty_and_rebake(active_layer)
	doc_dirty = true
	_refresh_title()
	_canvas.notify_changed()
	queue_redraw()


## 沿格子连线补点（快速拖动不断线）
func _paint_line(from: Vector2i, to: Vector2i) -> void:
	var steps := maxi(absi(to.x - from.x), absi(to.y - from.y))
	for i in range(steps + 1):
		var t := float(i) / maxf(float(steps), 1.0)
		_stamp(Vector2i(Vector2(from).lerp(Vector2(to), t).round()))
	queue_redraw()


## 圆形笔刷落印
func _stamp(center: Vector2i) -> void:
	var cells: PackedByteArray = doc.editor_cells[active_layer]
	var r := brush_cells * 0.5
	var ri := int(ceilf(r))
	var value := 0 if _stroke_erase else 1
	for dy in range(-ri, ri + 1):
		for dx in range(-ri, ri + 1):
			if Vector2(dx, dy).length() > r:
				continue
			var cx := center.x + dx
			var cy := center.y + dy
			if cx < 0 or cy < 0 or cx >= MapDocument.GRID_W or cy >= MapDocument.GRID_H:
				continue
			cells[cy * MapDocument.GRID_W + cx] = value


func _mouse_cell() -> Vector2i:
	var world := _cam_ctrl.screen_to_world(get_viewport().get_mouse_position())
	var f := (world - MapDocument.grid_origin()) / MapDocument.CELL_SIZE_PX
	var cell := Vector2i(int(floorf(f.x)), int(floorf(f.y)))
	if cell.x < 0 or cell.y < 0 or cell.x >= MapDocument.GRID_W or cell.y >= MapDocument.GRID_H:
		return Vector2i(-1, -1)
	return cell


func _zoom(factor: float) -> void:
	_cam_ctrl.target_zoom = clampf(_cam_ctrl.target_zoom * factor, _zoom_min, EDITOR_ZOOM_MAX)


func _undo() -> void:
	var layer := doc.undo()
	if layer != "":
		doc_dirty = true
		_refresh_title()
		_canvas.notify_changed()
		queue_redraw()


# ══════════════════════════════════════════════
#  光标 + 笔画格子绘制（轻量层，随鼠标重绘）
# ══════════════════════════════════════════════

func _draw() -> void:
	# 笔画进行中：当前层原始格子半透明叠加（整行连续段合并 rect）
	if _painting:
		var cells: PackedByteArray = doc.editor_cells[active_layer]
		var cs := MapDocument.CELL_SIZE_PX
		var origin := MapDocument.grid_origin()
		var col: Color = _canvas.layer_color(active_layer)
		col.a = STROKE_CELL_ALPHA
		for cy in range(MapDocument.GRID_H):
			var run_start := -1
			for cx in range(MapDocument.GRID_W + 1):
				var filled: bool = cx < MapDocument.GRID_W and cells[cy * MapDocument.GRID_W + cx] != 0
				if filled and run_start < 0:
					run_start = cx
				elif not filled and run_start >= 0:
					draw_rect(Rect2(origin + Vector2(run_start, cy) * cs,
						Vector2((cx - run_start) * cs, cs)), col, true)
					run_start = -1
	# 笔刷光标
	if _hover_cell.x >= 0:
		var cs2 := MapDocument.CELL_SIZE_PX
		var origin2 := MapDocument.grid_origin()
		var rect := Rect2(origin2 + Vector2(_hover_cell) * cs2, Vector2(cs2, cs2))
		draw_rect(rect, CURSOR_COLOR, false, 2.0)
		draw_arc(rect.get_center(), brush_cells * 0.5 * cs2, 0, TAU, 32, CURSOR_COLOR, 1.5, true)


# ══════════════════════════════════════════════
#  UI 构建
# ══════════════════════════════════════════════

func _build_ui() -> void:
	var ui := CanvasLayer.new()
	add_child(ui)

	# ── 顶部工具栏 ──
	var top := PanelContainer.new()
	top.add_theme_stylebox_override("panel", _panel_style())
	top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	ui.add_child(top)
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 8)
	top.add_child(bar)

	_title_label = Label.new()
	_title_label.add_theme_font_size_override("font_size", 15)
	bar.add_child(_title_label)
	bar.add_child(_vsep())

	_tool_brush_btn = _bar_button(tr("EDITOR_TOOL_BRUSH"), func(): _set_tool(false))
	bar.add_child(_tool_brush_btn)
	_tool_eraser_btn = _bar_button(tr("EDITOR_TOOL_ERASER"), func(): _set_tool(true))
	bar.add_child(_tool_eraser_btn)
	bar.add_child(_vsep())

	for size in [1, 3, 5, 9]:
		var b := _bar_button(str(size), func(): _set_brush(size))
		_size_buttons[size] = b
		bar.add_child(b)
	bar.add_child(_vsep())

	bar.add_child(_bar_button(tr("EDITOR_UNDO"), _undo))
	bar.add_child(_vsep())
	bar.add_child(_bar_button(tr("EDITOR_NEW_BLANK"), _new_blank))
	bar.add_child(_bar_button(tr("EDITOR_NEW_FROM_OFFICIAL"), _new_from_official))
	bar.add_child(_bar_button(tr("EDITOR_OPEN"), _open))
	bar.add_child(_bar_button(tr("EDITOR_SAVE"), _save))
	bar.add_child(_bar_button(tr("EDITOR_SAVE_AS"), _save_as))
	bar.add_child(_vsep())
	bar.add_child(_bar_button(tr("EDITOR_TEST_FLY"), _test_fly))

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(spacer)
	bar.add_child(_bar_button(tr("EDITOR_BACK"), _request_exit))

	# ── 左上素材库 ──
	var palette := PanelContainer.new()
	palette.add_theme_stylebox_override("panel", _panel_style())
	palette.set_anchors_preset(Control.PRESET_TOP_LEFT)
	palette.position = Vector2(8, 52)
	ui.add_child(palette)
	var pv := VBoxContainer.new()
	pv.add_theme_constant_override("separation", 4)
	palette.add_child(pv)
	var ptitle := Label.new()
	ptitle.text = tr("EDITOR_PALETTE_TITLE")
	ptitle.add_theme_font_size_override("font_size", 14)
	ptitle.add_theme_color_override("font_color", Color(0.5, 0.7, 0.5, 0.9))
	pv.add_child(ptitle)
	for layer in CELL_LAYER_KEYS:
		var b := _bar_button(tr(CELL_LAYER_KEYS[layer]), func(): _set_layer(layer))
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		_layer_buttons[layer] = b
		pv.add_child(b)

	# ── 底部提示 ──
	var hint := PanelContainer.new()
	hint.add_theme_stylebox_override("panel", _panel_style())
	hint.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	hint.position.y -= 34
	ui.add_child(hint)
	_hint_label = Label.new()
	_hint_label.text = tr("EDITOR_HINT")
	_hint_label.add_theme_font_size_override("font_size", 12)
	_hint_label.add_theme_color_override("font_color", Color(0.7, 0.8, 0.7, 0.7))
	hint.add_child(_hint_label)

	# ── 对话框 ──
	_saveas_dialog = ConfirmationDialog.new()
	_saveas_dialog.title = tr("EDITOR_NAME_PROMPT")
	_saveas_edit = LineEdit.new()
	_saveas_edit.placeholder_text = tr("EDITOR_NAME_PROMPT")
	_saveas_dialog.add_child(_saveas_edit)
	_saveas_dialog.register_text_enter(_saveas_edit)
	_saveas_dialog.confirmed.connect(_do_save_as)
	ui.add_child(_saveas_dialog)

	_open_dialog = FileDialog.new()
	_open_dialog.access = FileDialog.ACCESS_USERDATA
	_open_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_open_dialog.filters = ["*.json ; UGC Map"]
	_open_dialog.file_selected.connect(_do_open)
	ui.add_child(_open_dialog)

	_exit_dialog = ConfirmationDialog.new()
	_exit_dialog.title = tr("EDITOR_UNSAVED_TITLE")
	_exit_dialog.dialog_text = tr("EDITOR_UNSAVED_MSG")
	_exit_dialog.ok_button_text = tr("EDITOR_BTN_SAVE_EXIT")
	_exit_dialog.add_button(tr("EDITOR_BTN_DISCARD"), true, "discard")
	_exit_dialog.confirmed.connect(func():
		if _save():
			_go_menu())
	_exit_dialog.custom_action.connect(func(_a): _go_menu())
	ui.add_child(_exit_dialog)

	_recover_dialog = ConfirmationDialog.new()
	_recover_dialog.title = tr("EDITOR_RECOVER_TITLE")
	_recover_dialog.dialog_text = tr("EDITOR_RECOVER_MSG")
	_recover_dialog.confirmed.connect(_do_recover)
	ui.add_child(_recover_dialog)

	_set_tool(false)
	_set_brush(3)
	_set_layer("land")


func _panel_style() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.06, 0.09, 0.08, 0.92)
	s.border_color = Color(0.3, 0.5, 0.4, 0.6)
	s.set_border_width_all(1)
	s.set_content_margin_all(6)
	return s


func _bar_button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", 13)
	b.pressed.connect(cb)
	return b


func _vsep() -> VSeparator:
	return VSeparator.new()


func _set_tool(eraser: bool) -> void:
	tool_eraser = eraser
	_tool_brush_btn.disabled = not eraser
	_tool_eraser_btn.disabled = eraser


func _set_brush(size: int) -> void:
	brush_cells = size
	for s in _size_buttons:
		(_size_buttons[s] as Button).disabled = s == size
	queue_redraw()


func _set_layer(layer: String) -> void:
	active_layer = layer
	for l in _layer_buttons:
		(_layer_buttons[l] as Button).disabled = l == layer


func _refresh_title() -> void:
	var name := doc.display_name if doc.display_name != "" else "untitled"
	_title_label.text = "%s%s" % [name, "*" if doc_dirty else ""]


# ══════════════════════════════════════════════
#  文件生命周期（§2.4）
# ══════════════════════════════════════════════

func _new_blank() -> void:
	doc = MapDocument.new()
	current_path = ""
	doc_dirty = false
	_after_doc_replaced()


func _new_from_official() -> void:
	doc = OfficialMapConverter.build()
	current_path = ""
	doc_dirty = true
	_after_doc_replaced()


func _after_doc_replaced() -> void:
	_canvas.doc = doc
	_canvas.notify_changed()
	_refresh_title()
	queue_redraw()


func _open() -> void:
	_open_dialog.current_dir = MAPS_DIR
	_open_dialog.popup_centered_ratio(0.6)


func _do_open(path: String) -> void:
	if path.ends_with(".autosave.json"):
		return
	var loaded := MapDocument.load_from(path)
	if loaded == null:
		return
	doc = loaded
	current_path = path
	doc_dirty = false
	_after_doc_replaced()
	# 自动保存恢复检查：autosave 比主存档新 → 弹恢复确认
	var auto_path := _autosave_path()
	if FileAccess.file_exists(auto_path) \
			and FileAccess.get_modified_time(auto_path) > FileAccess.get_modified_time(path):
		_pending_recover_path = auto_path
		_recover_dialog.popup_centered()


func _do_recover() -> void:
	var recovered := MapDocument.load_from(_pending_recover_path)
	if recovered != null:
		doc = recovered
		doc_dirty = true
		_after_doc_replaced()


## 保存；未命名时转另存为。返回是否已落盘
func _save() -> bool:
	if current_path == "":
		_save_as()
		return false
	if doc.save_to(current_path):
		doc_dirty = false
		_refresh_title()
		return true
	return false


func _save_as() -> void:
	_saveas_edit.text = doc.display_name if doc.display_name != "untitled" else ""
	_saveas_dialog.popup_centered()
	_saveas_edit.grab_focus()


func _do_save_as() -> void:
	var name := _saveas_edit.text.strip_edges()
	if name == "":
		return
	doc.display_name = name
	current_path = "%s/%s.json" % [MAPS_DIR, name.validate_filename()]
	if doc.save_to(current_path):
		doc_dirty = false
	_refresh_title()


func _autosave_path() -> String:
	if current_path == "":
		return "%s/_unsaved.autosave.json" % MAPS_DIR
	return current_path.get_basename() + ".autosave.json"


func _do_autosave() -> void:
	if doc_dirty:
		doc.save_to(_autosave_path())


func _test_fly() -> void:
	_do_autosave()  # §2.4：试飞前自动保存
	if not doc.save_to(TESTFLIGHT_PATH):
		return
	get_tree().set_meta("ugc_map_path", TESTFLIGHT_PATH)
	get_tree().change_scene_to_file("res://scenes/survivor_mode.tscn")


func _request_exit() -> void:
	if doc_dirty:
		_exit_dialog.popup_centered()
	else:
		_go_menu()


func _go_menu() -> void:
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
