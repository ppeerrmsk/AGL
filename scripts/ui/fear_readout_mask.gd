class_name FearReadoutMask
extends RefCounted

## 只绘制信息噪声，不移动布局或改变输入；正常读数由调用者停止提交。
static func draw(canvas: CanvasItem, rect: Rect2, title: String, remaining: float = 0.0) -> void:
	canvas.draw_rect(rect, Color(0.07, 0.015, 0.11, 1.0))
	canvas.draw_rect(rect, FearResponse.COLOR, false, 1.0)
	var font := ThemeDB.fallback_font
	if rect.size.y < 42.0:
		var compact := "%s // FEAR %.1fs // AB" % [title, remaining] if remaining > 0.0 else title
		canvas.draw_string(font, rect.position + Vector2(8, minf(16.0, rect.size.y - 2.0)), compact, HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 16.0, 14, FearResponse.COLOR)
		return
	canvas.draw_string(font, rect.position + Vector2(8, 17), title, HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 16.0, 14, FearResponse.COLOR)
	if title != "???" or remaining > 0.0:
		var text := "FEAR %.1fs // AB" % remaining if remaining > 0.0 else "???"
		canvas.draw_string(font, rect.position + Vector2(8, minf(38.0, rect.size.y - 4.0)), text, HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 16.0, 14, FearResponse.COLOR)
