class_name TerminalGridOverlay
extends Control

## 在统一坐标系中绘制终端网格描边。
## 相邻区域共享完全相同的边界坐标，不允许各自在矩形内部偏移 1px。

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

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = false

func _draw() -> void:
	for region in regions:
		draw_rect(region, line_color, false, 1.0, false)
	for region in override_regions:
		draw_rect(region, override_color, false, 1.0, false)
