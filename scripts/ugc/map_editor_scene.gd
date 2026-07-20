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
enum Tool { BRUSH, ERASER, RECT, ELLIPSE, TRI }
var active_layer := "land"
var cur_tool: Tool = Tool.BRUSH
var brush_cells := 3              ## 笔刷直径（格），§2.1：1/3/5/9
var _painting := false
var _last_paint_cell := Vector2i(-1, -1)
var _hover_cell := Vector2i(-1, -1)
## 图形拖拽状态（RECT/ELLIPSE/TRI）
var _shape_dragging := false
var _shape_erase := false
var _shape_anchor := Vector2.ZERO   ## 世界坐标
var _shape_cur := Vector2.ZERO
## PNG 垫图
var _underlay: Sprite2D = null
var _underlay_image: Image = null

var _camera: Camera2D
var _cam_ctrl: CameraController
var _canvas: MapEditorCanvas
var _autosave_timer: Timer

## UI 引用
var _title_label: Label
var _layer_buttons: Dictionary = {}
var _tool_buttons: Dictionary = {}   ## Tool → Button
var _size_buttons: Dictionary = {}
var _image_dialog: FileDialog
var _extract_dialog: ConfirmationDialog
var _extract_slider: HSlider
var _extract_dark: CheckButton
var _underlay_btn: Button
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
				if cur_tool >= Tool.RECT:
					_begin_shape(false)
				else:
					_begin_stroke(cur_tool == Tool.ERASER)
			else:
				_end_stroke()
				_commit_shape()
		elif mb.button_index == MOUSE_BUTTON_RIGHT:
			# 右键 = 快捷擦除（笔刷模式下临时橡皮；图形模式下擦除图形）
			if mb.pressed:
				if cur_tool >= Tool.RECT:
					_begin_shape(true)
				else:
					_begin_stroke(true)
			else:
				_end_stroke()
				_commit_shape()
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
		if _shape_dragging:
			_shape_cur = _mouse_world()
			queue_redraw()
	elif event is InputEventKey and event.pressed and not event.echo:
		var key := event as InputEventKey
		if key.keycode == KEY_S and key.ctrl_pressed:
			_save()
		elif key.keycode == KEY_Z and key.ctrl_pressed:
			_undo()
		elif key.keycode == KEY_ESCAPE:
			if _shape_dragging:
				_shape_dragging = false  # 先取消进行中的图形，不弹退出
				queue_redraw()
			else:
				_request_exit()


var _stroke_erase := false

func _begin_stroke(erase: bool) -> void:
	var cell := _mouse_cell()
	if cell.x < 0 or _painting:
		return
	_painting = true
	_stroke_erase = erase
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


func _mouse_world() -> Vector2:
	return _cam_ctrl.screen_to_world(get_viewport().get_mouse_position())


func _mouse_cell() -> Vector2i:
	var f := (_mouse_world() - MapDocument.grid_origin()) / MapDocument.CELL_SIZE_PX
	var cell := Vector2i(int(floorf(f.x)), int(floorf(f.y)))
	if cell.x < 0 or cell.y < 0 or cell.x >= MapDocument.GRID_W or cell.y >= MapDocument.GRID_H:
		return Vector2i(-1, -1)
	return cell


# ══════════════════════════════════════════════
#  图形工具（矩形/圆形/三角形 → 精确谓词写格 → 同一平滑管线）
# ══════════════════════════════════════════════

func _begin_shape(erase: bool) -> void:
	if _shape_dragging or _painting:
		return
	_shape_dragging = true
	_shape_erase = erase
	_shape_anchor = _mouse_world()
	_shape_cur = _shape_anchor


func _commit_shape() -> void:
	if not _shape_dragging:
		return
	_shape_dragging = false
	var rect := Rect2(_shape_anchor, _shape_cur - _shape_anchor).abs()
	if rect.size.x < MapDocument.CELL_SIZE_PX * 0.5 and rect.size.y < MapDocument.CELL_SIZE_PX * 0.5:
		queue_redraw()
		return
	doc.push_undo(active_layer)
	var cells: PackedByteArray = doc.editor_cells[active_layer]
	var value := 0 if _shape_erase else 1
	var origin := MapDocument.grid_origin()
	var cs := MapDocument.CELL_SIZE_PX
	var c0 := Vector2i(((rect.position - origin) / cs).floor())
	var c1 := Vector2i(((rect.end - origin) / cs).ceil())
	for cy in range(maxi(c0.y, 0), mini(c1.y, MapDocument.GRID_H)):
		for cx in range(maxi(c0.x, 0), mini(c1.x, MapDocument.GRID_W)):
			var p := origin + Vector2(cx + 0.5, cy + 0.5) * cs
			if _shape_contains(rect, p):
				cells[cy * MapDocument.GRID_W + cx] = value
	doc.mark_dirty_and_rebake(active_layer)
	doc_dirty = true
	_refresh_title()
	_canvas.notify_changed()
	queue_redraw()


## 当前图形工具在 rect 框内的形状判定
func _shape_contains(rect: Rect2, p: Vector2) -> bool:
	match cur_tool:
		Tool.RECT:
			return rect.has_point(p)
		Tool.ELLIPSE:
			var c := rect.get_center()
			var rx := maxf(rect.size.x * 0.5, 0.001)
			var ry := maxf(rect.size.y * 0.5, 0.001)
			var dx := (p.x - c.x) / rx
			var dy := (p.y - c.y) / ry
			return dx * dx + dy * dy <= 1.0
		Tool.TRI:
			# 等腰三角形：顶点=框上边中点，底边=框下边
			var apex := Vector2(rect.get_center().x, rect.position.y)
			var bl := Vector2(rect.position.x, rect.end.y)
			var br := rect.end
			return Geometry2D.point_is_inside_triangle(p, apex, bl, br)
	return false


## 图形预览轮廓点集（拖拽中 _draw 用）
func _shape_preview_points(rect: Rect2) -> PackedVector2Array:
	var pts := PackedVector2Array()
	match cur_tool:
		Tool.RECT:
			pts.append_array([rect.position, Vector2(rect.end.x, rect.position.y),
				rect.end, Vector2(rect.position.x, rect.end.y), rect.position])
		Tool.ELLIPSE:
			var c := rect.get_center()
			for i in range(33):
				var a := TAU * i / 32.0
				pts.append(c + Vector2(cos(a) * rect.size.x * 0.5, sin(a) * rect.size.y * 0.5))
		Tool.TRI:
			var apex := Vector2(rect.get_center().x, rect.position.y)
			pts.append_array([apex, rect.end, Vector2(rect.position.x, rect.end.y), apex])
	return pts


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
	# 图形拖拽预览
	if _shape_dragging:
		var srect := Rect2(_shape_anchor, _shape_cur - _shape_anchor).abs()
		var pts := _shape_preview_points(srect)
		if pts.size() >= 2:
			var pcol := Color(1.0, 0.5, 0.4, 0.8) if _shape_erase else CURSOR_COLOR
			draw_polyline(pts, pcol, 2.0, true)
	# 笔刷光标（仅笔刷/橡皮模式）：所见即所得——按落印同一几何谓词
	# 半透明填出将被涂到的每个格子（橡皮=红色调），外加范围圈
	if _hover_cell.x >= 0 and cur_tool < Tool.RECT:
		var cs2 := MapDocument.CELL_SIZE_PX
		var origin2 := MapDocument.grid_origin()
		var fill_col: Color
		if cur_tool == Tool.ERASER:
			fill_col = Color(1.0, 0.45, 0.35, 0.35)
		else:
			fill_col = _canvas.layer_color(active_layer)
			fill_col.a = 0.4
		var r := brush_cells * 0.5
		var ri := int(ceilf(r))
		for dy in range(-ri, ri + 1):
			for dx in range(-ri, ri + 1):
				if Vector2(dx, dy).length() > r:
					continue
				var cx := _hover_cell.x + dx
				var cy := _hover_cell.y + dy
				if cx < 0 or cy < 0 or cx >= MapDocument.GRID_W or cy >= MapDocument.GRID_H:
					continue
				draw_rect(Rect2(origin2 + Vector2(cx, cy) * cs2, Vector2(cs2, cs2)), fill_col, true)
		var center := origin2 + (Vector2(_hover_cell) + Vector2(0.5, 0.5)) * cs2
		draw_arc(center, r * cs2, 0, TAU, 32, CURSOR_COLOR, 1.5, true)


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

	var tool_defs := {
		Tool.BRUSH: "EDITOR_TOOL_BRUSH", Tool.ERASER: "EDITOR_TOOL_ERASER",
		Tool.RECT: "EDITOR_TOOL_RECT", Tool.ELLIPSE: "EDITOR_TOOL_ELLIPSE",
		Tool.TRI: "EDITOR_TOOL_TRI",
	}
	for t in tool_defs:
		var tb := _bar_button(tr(tool_defs[t]), func(): _set_tool(t))
		_tool_buttons[t] = tb
		bar.add_child(tb)
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
	bar.add_child(_bar_button(tr("EDITOR_IMPORT_IMAGE"), _import_image))
	_underlay_btn = _bar_button(tr("EDITOR_UNDERLAY_TOGGLE"), _toggle_underlay)
	_underlay_btn.visible = false
	bar.add_child(_underlay_btn)
	var extract_btn := _bar_button(tr("EDITOR_EXTRACT"), _open_extract)
	bar.add_child(extract_btn)
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

	# PNG 垫图导入（系统文件对话框；参考图仅编辑态，不写入成品，spec §2.5）
	_image_dialog = FileDialog.new()
	_image_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_image_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_image_dialog.filters = ["*.png, *.jpg, *.jpeg, *.webp, *.bmp ; Image"]
	_image_dialog.file_selected.connect(_do_import_image)
	ui.add_child(_image_dialog)

	# 按亮度阈值把垫图提取到当前图层
	_extract_dialog = ConfirmationDialog.new()
	_extract_dialog.title = tr("EDITOR_EXTRACT")
	var ev := VBoxContainer.new()
	var thr_label := Label.new()
	thr_label.text = tr("EDITOR_THRESHOLD")
	ev.add_child(thr_label)
	_extract_slider = HSlider.new()
	_extract_slider.min_value = 0.05
	_extract_slider.max_value = 0.95
	_extract_slider.step = 0.05
	_extract_slider.value = 0.5
	_extract_slider.custom_minimum_size = Vector2(240, 0)
	ev.add_child(_extract_slider)
	_extract_dark = CheckButton.new()
	_extract_dark.text = tr("EDITOR_EXTRACT_DARK")
	_extract_dark.button_pressed = true
	ev.add_child(_extract_dark)
	_extract_dialog.add_child(ev)
	_extract_dialog.confirmed.connect(_do_extract)
	ui.add_child(_extract_dialog)

	_set_tool(Tool.BRUSH)
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


func _set_tool(t: Tool) -> void:
	cur_tool = t
	for k in _tool_buttons:
		(_tool_buttons[k] as Button).disabled = k == t
	queue_redraw()


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


# ══════════════════════════════════════════════
#  PNG 垫图 + 阈值提取（spec §2.5 参考图仅编辑态 / v6 提取到图层）
# ══════════════════════════════════════════════

func _import_image() -> void:
	_image_dialog.popup_centered_ratio(0.6)


func _do_import_image(path: String) -> void:
	var img := Image.load_from_file(path)
	if img == null:
		return
	_underlay_image = img
	if _underlay != null:
		_underlay.queue_free()
	_underlay = Sprite2D.new()
	_underlay.texture = ImageTexture.create_from_image(img)
	_underlay.centered = false
	_underlay.position = MapDocument.grid_origin()
	var world := MapDocument.WORLD_HALF_PX * 2.0
	_underlay.scale = Vector2(world / img.get_width(), world / img.get_height())
	_underlay.self_modulate = Color(1, 1, 1, 0.4)
	add_child(_underlay)
	move_child(_underlay, 1)  # 画布(0)之上、光标绘制之下
	_underlay_btn.visible = true


func _toggle_underlay() -> void:
	if _underlay != null:
		_underlay.visible = not _underlay.visible


func _open_extract() -> void:
	if _underlay_image == null:
		_import_image()  # 还没垫图 → 先走导入
		return
	_extract_dialog.popup_centered()


## 逐格心采样垫图亮度 → 命中格并入当前图层（叠加不清除）→ 重烘焙平滑
func _do_extract() -> void:
	if _underlay_image == null:
		return
	doc.push_undo(active_layer)
	var cells: PackedByteArray = doc.editor_cells[active_layer]
	var thr := float(_extract_slider.value)
	var want_dark := _extract_dark.button_pressed
	var world := MapDocument.WORLD_HALF_PX * 2.0
	var iw := _underlay_image.get_width()
	var ih := _underlay_image.get_height()
	for cy in range(MapDocument.GRID_H):
		for cx in range(MapDocument.GRID_W):
			var u := (cx + 0.5) * MapDocument.CELL_SIZE_PX / world
			var v := (cy + 0.5) * MapDocument.CELL_SIZE_PX / world
			var px := clampi(int(u * iw), 0, iw - 1)
			var py := clampi(int(v * ih), 0, ih - 1)
			var c := _underlay_image.get_pixel(px, py)
			if c.a < 0.5:
				continue  # 透明像素不参与
			var lum := c.get_luminance()
			if (lum < thr) if want_dark else (lum > thr):
				cells[cy * MapDocument.GRID_W + cx] = 1
	doc.mark_dirty_and_rebake(active_layer)
	doc_dirty = true
	_refresh_title()
	_canvas.notify_changed()
	queue_redraw()


func _request_exit() -> void:
	if doc_dirty:
		_exit_dialog.popup_centered()
	else:
		_go_menu()


func _go_menu() -> void:
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
