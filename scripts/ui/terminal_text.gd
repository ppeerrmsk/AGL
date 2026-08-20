class_name TerminalText
extends Control

## 军用终端 UI 的通用字号规范实现。
## 统一负责可见字形测量、最大字符串宽度、固定字号和水平对齐。

enum FontFace {
	THEME,
	SILKSCREEN,
	CHAKRA_PETCH_BOLD,
	CHAKRA_PETCH_MEDIUM,
	CHAKRA_PETCH_LIGHT,
}

enum SizeRule {
	VISIBLE_INK_FILL,
	ONE_U_FIXED_15,
}

const SILKSCREEN_FONT_SOURCE: FontFile = preload("res://resources/fonts/Silkscreen-Regular.ttf")
const CHAKRA_PETCH_BOLD: FontFile = preload("res://resources/fonts/ChakraPetch-Bold.ttf")
const CHAKRA_PETCH_MEDIUM: FontFile = preload("res://resources/fonts/ChakraPetch-Medium.ttf")
const CHAKRA_PETCH_LIGHT: FontFile = preload("res://resources/fonts/ChakraPetch-Light.ttf")
const ONE_U_FONT_SIZE := 15

static var _silkscreen_font: FontFile
const MAX_INK_FONT_SIZE_MULTIPLIER := 8.0

var text: String = "":
	set(value):
		if text == value:
			return
		text = value
		_layout_valid = false
		queue_redraw()

## 用于决定固定字号的最大显示字符串；为空时使用当前 text。
var layout_text: String = "":
	set(value):
		if layout_text == value:
			return
		layout_text = value
		_layout_valid = false
		queue_redraw()

var font_color: Color = ThemeColors.UI_TERMINAL_WHITE:
	set(value):
		if font_color == value:
			return
		font_color = value
		queue_redraw()

## 字体只决定字形；字号始终由所在区域的完整可用高度自动计算。
var font_face: int = FontFace.THEME:
	set(value):
		if font_face == value:
			return
		font_face = value
		_layout_valid = false
		queue_redraw()
var size_rule: int = SizeRule.VISIBLE_INK_FILL:
	set(value):
		if size_rule == value:
			return
		size_rule = value
		_layout_valid = false
		queue_redraw()
var horizontal_alignment: HorizontalAlignment = HORIZONTAL_ALIGNMENT_CENTER:
	set(value):
		if horizontal_alignment == value:
			return
		horizontal_alignment = value
		queue_redraw()
var resolved_font_size: int = 1
var resolved_ink_height: float = 0.0
var _resolved_ink_bounds := Vector2.ZERO
var _layout_valid := false

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED or what == NOTIFICATION_THEME_CHANGED:
		_layout_valid = false
		queue_redraw()

func _draw() -> void:
	var font := _get_text_font()
	if font == null or text.is_empty():
		return
	if size.x <= 0.0 or size.y <= 0.0:
		return

	if not _layout_valid:
		_resolve_layout(font, size)
	var actual_bounds := measure_ink_bounds(font, text, resolved_font_size)
	if not has_visible_ink(actual_bounds):
		actual_bounds = _resolved_ink_bounds
	var actual_height := actual_bounds.y - actual_bounds.x
	var baseline_y := (size.y - actual_height) * 0.5 - actual_bounds.x
	draw_string(
		font,
		Vector2(0.0, baseline_y),
		text,
		horizontal_alignment,
		size.x,
		resolved_font_size,
		font_color
	)

func _get_text_font() -> Font:
	match font_face:
		FontFace.SILKSCREEN:
			if _silkscreen_font == null:
				# 独立副本避免修改导入资源或其他控件的字体栅格化方式。
				_silkscreen_font = SILKSCREEN_FONT_SOURCE.duplicate(true) as FontFile
				_silkscreen_font.antialiasing = TextServer.FONT_ANTIALIASING_NONE
				_silkscreen_font.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
				_silkscreen_font.multichannel_signed_distance_field = false
				_silkscreen_font.generate_mipmaps = false
				_silkscreen_font.allow_system_fallback = true
			return _silkscreen_font
		FontFace.CHAKRA_PETCH_BOLD:
			return CHAKRA_PETCH_BOLD
		FontFace.CHAKRA_PETCH_MEDIUM:
			return CHAKRA_PETCH_MEDIUM
		FontFace.CHAKRA_PETCH_LIGHT:
			return CHAKRA_PETCH_LIGHT
		_:
			return get_theme_default_font()

func _resolve_layout(font: Font, bounds: Vector2) -> void:
	var sizing_text := text if layout_text.is_empty() else layout_text
	if size_rule == SizeRule.ONE_U_FIXED_15:
		_resolve_fixed_font_size(font, sizing_text, ONE_U_FONT_SIZE)
	else:
		_resolve_ink_layout(font, sizing_text, bounds)

func _resolve_fixed_font_size(font: Font, sizing_text: String, font_size: int) -> void:
	resolved_font_size = font_size
	_resolved_ink_bounds = measure_ink_bounds(font, sizing_text, font_size)
	if not has_visible_ink(_resolved_ink_bounds):
		_resolved_ink_bounds = Vector2(
			-font.get_ascent(font_size),
			font.get_descent(font_size)
		)
	resolved_ink_height = _resolved_ink_bounds.y - _resolved_ink_bounds.x
	_layout_valid = true

func _resolve_ink_layout(font: Font, sizing_text: String, bounds: Vector2) -> void:
	var layout := resolve_font_layout(font, sizing_text, bounds)
	resolved_font_size = int(layout.x)
	_resolved_ink_bounds = Vector2(layout.y, layout.z)
	resolved_ink_height = _resolved_ink_bounds.y - _resolved_ink_bounds.x
	_layout_valid = true

static func resolve_font_layout(font: Font, value: String, bounds: Vector2,
		fixed_font_size: int = 0) -> Vector3:
	var candidate := fixed_font_size
	if candidate <= 0:
		var reference_size := maxi(roundi(bounds.y), 1)
		var reference_ink := measure_ink_bounds(font, value, reference_size)
		if has_visible_ink(reference_ink):
			var reference_height := reference_ink.y - reference_ink.x
			candidate = maxi(int(floor(float(reference_size) * bounds.y / reference_height)), 1)
		else:
			candidate = largest_line_font_size_for_height(font, bounds.y)
		candidate = mini(candidate,
			maxi(int(ceil(bounds.y * MAX_INK_FONT_SIZE_MULTIPLIER)), 1))

	var ink := measure_ink_bounds(font, value, candidate)
	if fixed_font_size <= 0:
		while candidate > 1 and not layout_fits(font, value, candidate, ink, bounds):
			candidate -= 1
			ink = measure_ink_bounds(font, value, candidate)
		var maximum := maxi(int(ceil(bounds.y * MAX_INK_FONT_SIZE_MULTIPLIER)), 1)
		while candidate < maximum:
			var next_ink := measure_ink_bounds(font, value, candidate + 1)
			if not layout_fits(font, value, candidate + 1, next_ink, bounds):
				break
			candidate += 1
			ink = next_ink

	if not has_visible_ink(ink):
		ink = Vector2(-font.get_ascent(candidate), font.get_descent(candidate))
	return Vector3(float(candidate), ink.x, ink.y)


## Resolve a visible-ink size from height alone. Width is deliberately ignored so
## callers can preserve a shared font size and expand their board in grid steps.
static func font_size_for_ink_height(font: Font, value: String, height: float) -> int:
	return int(resolve_font_layout(font, value, Vector2(1000000.0, height)).x)


## Keep the requested base width when possible, otherwise add whole grid steps
## until the fixed-size reference string fits. This function never shrinks text.
static func expanded_width_for_fixed_text(font: Font, value: String, font_size: int,
		base_width: float, grid_step: float) -> float:
	if grid_step <= 0.0:
		return base_width
	var required_width := font.get_string_size(
		value, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size).x
	if required_width <= base_width:
		return base_width
	return base_width + ceilf((required_width - base_width) / grid_step) * grid_step


static func layout_fits(font: Font, value: String, font_size: int, ink: Vector2,
		bounds: Vector2) -> bool:
	if not has_visible_ink(ink) or ink.y - ink.x > bounds.y:
		return false
	return font.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size).x \
		<= bounds.x


static func measure_ink_bounds(font: Font, value: String, font_size: int) -> Vector2:
	var text_server := TextServerManager.get_primary_interface()
	var shaped := text_server.create_shaped_text()
	var added := text_server.shaped_text_add_string(
		shaped,
		value,
		font.get_rids(),
		font_size
	)
	if not added:
		text_server.free_rid(shaped)
		return Vector2(INF, -INF)

	var top := INF
	var bottom := -INF
	var glyphs: Array[Dictionary] = text_server.shaped_text_get_glyphs(shaped)
	for glyph in glyphs:
		var glyph_font: RID = glyph.get("font_rid", RID())
		if not glyph_font.is_valid():
			continue
		var glyph_font_size := int(glyph.get("font_size", font_size))
		var glyph_index := int(glyph.get("index", 0))
		var contour_data := text_server.font_get_glyph_contours(
			glyph_font,
			glyph_font_size,
			glyph_index
		)
		var contour_points: PackedVector3Array = contour_data.get(
			"points",
			PackedVector3Array()
		)
		if contour_points.is_empty():
			continue
		var outline_min_y := INF
		var outline_max_y := -INF
		for point in contour_points:
			outline_min_y = minf(outline_min_y, point.y)
			outline_max_y = maxf(outline_max_y, point.y)
		var shaped_offset: Vector2 = glyph.get("offset", Vector2.ZERO)
		# TextServer contour Y coordinates already match canvas baseline space:
		# visible points above the baseline are negative, descenders are positive.
		var glyph_top := shaped_offset.y + outline_min_y
		var glyph_bottom := shaped_offset.y + outline_max_y
		top = minf(top, glyph_top)
		bottom = maxf(bottom, glyph_bottom)

	text_server.free_rid(shaped)
	return Vector2(top, bottom)


static func has_visible_ink(bounds: Vector2) -> bool:
	return is_finite(bounds.x) and is_finite(bounds.y) and bounds.y > bounds.x


static func largest_line_font_size_for_height(font: Font, max_height: float) -> int:
	var start_size := maxi(int(floor(max_height)), 1)
	for candidate in range(start_size, 0, -1):
		if font.get_height(candidate) <= max_height:
			return candidate
	return 1
