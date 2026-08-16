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
		regions = value
		queue_redraw()

var line_color: Color = ThemeColors.UI_TERMINAL_GREEN:
	set(value):
		line_color = value
		queue_redraw()

var override_regions: Array[Rect2] = []:
	set(value):
		override_regions = value
		queue_redraw()

var override_color: Color = ThemeColors.UI_TERMINAL_INVERSE:
	set(value):
		override_color = value
		queue_redraw()

## Insets only outline sides that coincide with this grid Control's boundary.
## Vector order: left, top, right, bottom. Half a pixel keeps each hairline's
## center inside clipped controls and physical render-target edges.
var edge_insets := CONTROL_EDGE_INSETS:
	set(value):
		edge_insets = value
		queue_redraw()

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = false

func _draw() -> void:
	for region in regions:
		draw_rect(edge_safe_region(region, size, edge_insets), line_color,
			false, SCALE_INVARIANT_LINE_WIDTH, false)
	for region in override_regions:
		draw_rect(edge_safe_region(region, size, edge_insets), override_color,
			false, SCALE_INVARIANT_LINE_WIDTH, false)


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
