class_name TerminalGridOverlay
extends Control

## 在统一坐标系中绘制终端网格描边。
## 相邻区域共享完全相同的边界坐标，不允许各自在矩形内部偏移 1px。
## Godot 的负宽度轮廓使用不随 Canvas 缩放变粗/变细的 hairline primitive，
## 因而在 F7 HUD 缩放为 0.5x–0.9x 时仍保持一个物理像素，不会落入亚像素后消失。

const SCALE_INVARIANT_LINE_WIDTH := -1.0
## Keep every outer hairline centered inside its owning Control. Internal
## shared seams are untouched because edge_safe_region only applies this inset
## when a region actually coincides with the grid canvas boundary.
const CONTROL_EDGE_INSETS := Vector4(0.5, 0.5, 0.5, 0.5)

var regions: Array[Rect2] = []:
	set(value):
		if regions == value:
			return
		regions = value
		queue_redraw()

var line_color: Color = ThemeColors.UI_TERMINAL_WHITE:
	set(value):
		if line_color.is_equal_approx(value):
			return
		line_color = value
		queue_redraw()

var override_regions: Array[Rect2] = []:
	set(value):
		if override_regions == value:
			return
		override_regions = value
		queue_redraw()

var override_color: Color = ThemeColors.UI_TERMINAL_INVERSE:
	set(value):
		if override_color.is_equal_approx(value):
			return
		override_color = value
		queue_redraw()

## Insets only outline sides that coincide with this grid Control's boundary.
## Vector order: left, top, right, bottom. Half a pixel keeps each hairline's
## center inside clipped controls and physical render-target edges.
var edge_insets := CONTROL_EDGE_INSETS:
	set(value):
		if edge_insets.is_equal_approx(value):
			return
		edge_insets = value
		queue_redraw()

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = false

func _draw() -> void:
	var perf_detail := PerfBuckets.detail_capture_enabled()
	var perf_t0 := Time.get_ticks_usec() if perf_detail else 0
	_draw_impl()
	if perf_detail:
		PerfBuckets.tick("hud_grid_draw", Time.get_ticks_usec() - perf_t0)


func _draw_impl() -> void:
	var normal_segments := outline_segments_for(regions, size, edge_insets)
	if not normal_segments.is_empty():
		draw_multiline(normal_segments, line_color,
			SCALE_INVARIANT_LINE_WIDTH, false)
	var inverted_segments := outline_segments_for(override_regions, size, edge_insets)
	if not inverted_segments.is_empty():
		draw_multiline(inverted_segments, override_color,
			SCALE_INVARIANT_LINE_WIDTH, false)


## 将全部框板边线合成一个 multiline，并去掉父子/相邻矩形的完全重合边。
## 返回值每两个点是一条独立线段，不会把不相邻的边错误连接起来。
static func outline_segments_for(source_regions: Array[Rect2], canvas_size: Vector2,
		insets: Vector4) -> PackedVector2Array:
	var unique_segments: Dictionary = {}
	for source_region in source_regions:
		var region := edge_safe_region(source_region, canvas_size, insets)
		if region.size.x <= 0.0 or region.size.y <= 0.0:
			continue
		var top_left := region.position
		var top_right := Vector2(region.end.x, region.position.y)
		var bottom_left := Vector2(region.position.x, region.end.y)
		var bottom_right := region.end
		_append_unique_segment(unique_segments, top_left, top_right)
		_append_unique_segment(unique_segments, top_right, bottom_right)
		_append_unique_segment(unique_segments, bottom_left, bottom_right)
		_append_unique_segment(unique_segments, top_left, bottom_left)
	var points := PackedVector2Array()
	for segment: PackedVector2Array in unique_segments.values():
		points.append_array(segment)
	return points


static func _append_unique_segment(target: Dictionary, first: Vector2,
		second: Vector2) -> void:
	var start := first
	var finish := second
	if finish.x < start.x or (is_equal_approx(finish.x, start.x) and finish.y < start.y):
		start = second
		finish = first
	var key := Vector4(start.x, start.y, finish.x, finish.y)
	if target.has(key):
		return
	target[key] = PackedVector2Array([start, finish])


static func edge_safe_region(region: Rect2, canvas_size: Vector2,
		insets: Vector4) -> Rect2:
	var start := region.position
	var finish := region.end
	if is_equal_approx(region.position.x, 0.0):
		start.x += maxf(insets.x, 0.0)
	if is_equal_approx(region.position.y, 0.0):
		start.y += maxf(insets.y, 0.0)
	if is_equal_approx(region.end.x, canvas_size.x):
		finish.x -= maxf(insets.z, 0.0)
	if is_equal_approx(region.end.y, canvas_size.y):
		finish.y -= maxf(insets.w, 0.0)
	return Rect2(start, Vector2(
		maxf(finish.x - start.x, 0.0),
		maxf(finish.y - start.y, 0.0)))
