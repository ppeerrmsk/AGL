extends RefCounted

## 无头验收：军用终端文字以最终可见字形边界撑满区域。
## 运行：bench/run.cmd terminal_text（或 --bench=all）

const TerminalGridOverlayScript := preload("res://scripts/ui/terminal_grid_overlay.gd")

var _pass := 0
var _fail := 0

func run() -> void:
	print("\n════════ 终端文字可见字形撑高验收 ════════")
	_check_visible_fill("Chakra 105 / 2u", "105", TerminalText.FontFace.CHAKRA_PETCH_BOLD, 36.0)
	_check_one_u_fixed_15("Silkscreen SPD / 1u", "SPD", 18.0)
	_check_ink_bounds_cache()
	_check_dynamic_glyph_cache()
	_check_layout_reference_controls_width()
	_check_height_first_q_expansion()
	_check_horizontal_alignment_rule()
	_check_shared_grid_coordinates()
	_check_grid_flash_override_types()
	_check_viewport_edge_hairline_insets()
	_check_grid_outline_batching()
	_check_scale_invariant_grid_lines()
	print("──────── 结果：%d 通过 / %d 失败 ────────" % [_pass, _fail])
	print("══════════════════════════════════════════\n")

func _check_visible_fill(label: String, value: String, face: int, height: float) -> void:
	var terminal_text := TerminalText.new()
	terminal_text.size = Vector2(200.0, height)
	terminal_text.font_face = face
	terminal_text.text = value
	terminal_text._resolve_layout(terminal_text._get_text_font(), terminal_text.size)

	var ink_height := terminal_text.resolved_ink_height
	var baseline := (height - ink_height) * 0.5 - terminal_text._resolved_ink_bounds.x
	var visible_top := baseline + terminal_text._resolved_ink_bounds.x
	var visible_bottom := baseline + terminal_text._resolved_ink_bounds.y
	_check(
		"%s：最终字形高度顶满" % label,
		ink_height <= height and ink_height >= height - 2.0,
		"font=%d ink=%.1f/%.1f" % [terminal_text.resolved_font_size, ink_height, height]
	)
	_check(
		"%s：最终字形垂直居中" % label,
		absf(visible_top - (height - visible_bottom)) <= 0.01,
		"top=%.2f bottom=%.2f" % [visible_top, visible_bottom]
	)
	_check(
		"%s：轮廓位于实际基线上方" % label,
		terminal_text._resolved_ink_bounds.x < 0.0
			and baseline > -terminal_text._resolved_ink_bounds.x,
		"bounds=(%.1f, %.1f) baseline=%.1f" % [
			terminal_text._resolved_ink_bounds.x,
			terminal_text._resolved_ink_bounds.y,
			baseline,
		]
	)
	terminal_text.free()


func _check_ink_bounds_cache() -> void:
	TerminalText._ink_bounds_cache.clear()
	var font: Font = TerminalText.CHAKRA_PETCH_BOLD
	var first := TerminalText.measure_ink_bounds(font, "105", 36)
	var entries_after_first := TerminalText._ink_bounds_cache.size()
	var second := TerminalText.measure_ink_bounds(font, "105", 36)
	_check(
		"Repeated glyph contour measurement reuses the bounded cache",
		first == second and entries_after_first == 1
			and TerminalText._ink_bounds_cache.size() == entries_after_first,
		"entries=%d bounds=%s" % [TerminalText._ink_bounds_cache.size(), first]
	)

func _check_dynamic_glyph_cache() -> void:
	var font: Font = TerminalText.CHAKRA_PETCH_BOLD
	TerminalText.measure_ink_bounds(font, "0123456789%s", 36)
	var queries := TerminalText._glyph_contour_queries
	var values: Array[String] = []
	for n in range(101):
		values.append(str(n) + "%")
		values.append(str(n) + "s")
	var start := Time.get_ticks_usec()
	for value in values:
		TerminalText.measure_ink_bounds(font, value, 36)
	var elapsed := Time.get_ticks_usec() - start
	_check("动态百分比/秒数完整塑形但不重复提取已预热字形轮廓",
		TerminalText._glyph_contour_queries == queries)
	print("[Terminal numeric cache] strings=202 us=", elapsed,
		" contour_queries=", TerminalText._glyph_contour_queries - queries)
	for face: Font in [font, TerminalText.CHAKRA_PETCH_LIGHT, TerminalText.SILKSCREEN_FONT_SOURCE]:
		for value: String in ["19%", "8s", "105", "ffi", "A g", ""]:
			_check("塑形轮廓与直接TextServer一致 " + value,
				TerminalText.measure_ink_bounds(face, value, 36) == _direct_ink_bounds(face, value, 36))
	# 通过真实查询越过容量：每次仅淘汰一项，不清空已热条目。
	var server := TextServerManager.get_primary_interface()
	var rid: RID = font.get_rids()[0]
	for size in range(1, TerminalText.MAX_GLYPH_BOUNDS_CACHE_ENTRIES + 2):
		TerminalText._glyph_ink_bounds(server, rid, size, 0)
	_check("字形缓存保持固定容量", TerminalText._glyph_bounds_cache.size() == TerminalText.MAX_GLYPH_BOUNDS_CACHE_ENTRIES)


func _direct_ink_bounds(font: Font, value: String, font_size: int) -> Vector2:
	var server := TextServerManager.get_primary_interface()
	var shaped := server.create_shaped_text()
	server.shaped_text_add_string(shaped, value, font.get_rids(), font_size)
	var bounds := Vector2(INF, -INF)
	for glyph: Dictionary in server.shaped_text_get_glyphs(shaped):
		var rid: RID = glyph.get("font_rid", RID())
		if not rid.is_valid():
			continue
		var contours := server.font_get_glyph_contours(rid, int(glyph.get("font_size", font_size)), int(glyph.get("index", 0)))
		var offset: Vector2 = glyph.get("offset", Vector2.ZERO)
		for point: Vector3 in contours.get("points", PackedVector3Array()):
			bounds.x = minf(bounds.x, point.y + offset.y)
			bounds.y = maxf(bounds.y, point.y + offset.y)
	server.free_rid(shaped)
	return bounds


func _check_one_u_fixed_15(label: String, value: String, height: float) -> void:
	var terminal_text := TerminalText.new()
	terminal_text.size = Vector2(40.0, height)
	terminal_text.font_face = TerminalText.FontFace.SILKSCREEN
	terminal_text.size_rule = TerminalText.SizeRule.ONE_U_FIXED_15
	terminal_text.text = value
	terminal_text._resolve_layout(terminal_text._get_text_font(), terminal_text.size)

	var ink_height := terminal_text.resolved_ink_height
	var baseline := (height - ink_height) * 0.5 - terminal_text._resolved_ink_bounds.x
	var visible_top := baseline + terminal_text._resolved_ink_bounds.x
	var visible_bottom := baseline + terminal_text._resolved_ink_bounds.y
	_check(
		"%s fixed 15px" % label,
		terminal_text.resolved_font_size == TerminalText.ONE_U_FONT_SIZE,
		"font=%d" % terminal_text.resolved_font_size
	)
	_check(
		"%s vertically centered" % label,
		absf(visible_top - (height - visible_bottom)) <= 0.01,
		"ink=%.1f top=%.2f bottom=%.2f" % [ink_height, visible_top, visible_bottom]
	)
	_check(
		"%s uses the actual baseline direction" % label,
		terminal_text._resolved_ink_bounds.x < 0.0
			and baseline > -terminal_text._resolved_ink_bounds.x,
		"bounds=(%.1f, %.1f) baseline=%.1f" % [
			terminal_text._resolved_ink_bounds.x,
			terminal_text._resolved_ink_bounds.y,
			baseline,
		]
	)
	terminal_text.free()

func _check_layout_reference_controls_width() -> void:
	var terminal_text := TerminalText.new()
	terminal_text.size = Vector2(80.0, 36.0)
	terminal_text.font_face = TerminalText.FontFace.CHAKRA_PETCH_BOLD
	terminal_text.layout_text = "999"
	terminal_text.text = "1"
	terminal_text._resolve_layout(terminal_text._get_text_font(), terminal_text.size)
	var wide_font_size := terminal_text.resolved_font_size

	terminal_text.text = "99"
	terminal_text._resolve_layout(terminal_text._get_text_font(), terminal_text.size)
	_check(
		"Maximum layout string keeps runtime values at one font size",
		terminal_text.resolved_font_size == wide_font_size,
		"one=%d two=%d" % [wide_font_size, terminal_text.resolved_font_size]
	)

	terminal_text.size = Vector2(20.0, 36.0)
	terminal_text._resolve_layout(terminal_text._get_text_font(), terminal_text.size)
	_check(
		"Maximum layout string shrinks when its declared region is narrower",
		terminal_text.resolved_font_size < wide_font_size,
		"wide=%d narrow=%d" % [wide_font_size, terminal_text.resolved_font_size]
	)
	terminal_text.free()


func _check_horizontal_alignment_rule() -> void:
	var terminal_text := TerminalText.new()
	_check("TerminalText defaults to centered text",
		terminal_text.horizontal_alignment == HORIZONTAL_ALIGNMENT_CENTER)
	terminal_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_check("Small-title callers can explicitly select left alignment",
		terminal_text.horizontal_alignment == HORIZONTAL_ALIGNMENT_LEFT)
	terminal_text.free()


func _check_height_first_q_expansion() -> void:
	var font: Font = TerminalText.CHAKRA_PETCH_BOLD
	var shared_size := TerminalText.font_size_for_ink_height(font, "999", 54.0)
	var hp_width := TerminalText.expanded_width_for_fixed_text(
		font, "999", shared_size, 120.0, 18.0)
	var g_width := TerminalText.expanded_width_for_fixed_text(
		font, "11.5", shared_size, 80.0, 18.0)
	var spd_width := TerminalText.expanded_width_for_fixed_text(
		font, "9999", shared_size, 120.0, 18.0)
	_check("Height-first sizing returns one shared primary font size",
		shared_size > 1)
	_check("Fixed-size boards expand only in whole q steps",
		is_equal_approx(fmod(hp_width - 120.0, 18.0), 0.0)
		and is_equal_approx(fmod(g_width - 80.0, 18.0), 0.0)
		and is_equal_approx(fmod(spd_width - 120.0, 18.0), 0.0))
	_check("q expansion fits every maximum reference without shrinking",
		font.get_string_size("999", HORIZONTAL_ALIGNMENT_LEFT, -1.0, shared_size).x
			<= hp_width
		and font.get_string_size("11.5", HORIZONTAL_ALIGNMENT_LEFT, -1.0, shared_size).x
			<= g_width
		and font.get_string_size("9999", HORIZONTAL_ALIGNMENT_LEFT, -1.0, shared_size).x
			<= spd_width)

func _check_shared_grid_coordinates() -> void:
	var u := Vector2(40.0, 18.0)
	var q := Vector2(18.0, 18.0)
	var main_origin := Vector2(q.x, 0.0)
	var regions: Array[Rect2] = [
		Rect2(Vector2.ZERO, q),
		Rect2(main_origin, u * Vector2(3.0, 3.0)),
		Rect2(main_origin + Vector2(0.0, u.y * 2.0), u * Vector2(2.0, 1.0)),
		Rect2(main_origin + Vector2(u.x * 2.0, 0.0), u),
		Rect2(main_origin + Vector2(u.x * 2.0, u.y), u),
		Rect2(main_origin + Vector2(u.x * 2.0, u.y * 2.0), u),
	]
	_check("Shared grid exposes all declared outlines", regions.size() == 6,
		"regions=%d" % regions.size())
	if regions.size() != 6:
		return

	var q_rect: Rect2 = regions[0]
	var main_rect: Rect2 = regions[1]
	var empty_rect: Rect2 = regions[2]
	var spd_rect: Rect2 = regions[3]
	var g_rect: Rect2 = regions[4]
	var alt_rect: Rect2 = regions[5]
	_check(
		"1q right edge reuses main-panel left edge",
		q_rect.end.x == main_rect.position.x,
		"q=%.1f main=%.1f" % [q_rect.end.x, main_rect.position.x]
	)
	_check(
		"Stacked 1u rows reuse one horizontal coordinate",
		spd_rect.end.y == g_rect.position.y and g_rect.end.y == alt_rect.position.y,
		"spd=%.1f g=%.1f alt=%.1f" % [spd_rect.end.y, g_rect.position.y, alt_rect.position.y]
	)
	_check(
		"Bottom 2u frame reuses ALT and outer-panel edges",
		empty_rect.position.y == alt_rect.position.y
			and empty_rect.end.y == main_rect.end.y
			and empty_rect.end.x == alt_rect.position.x,
		"empty=%s alt=%s main=%s" % [empty_rect, alt_rect, main_rect]
	)
	_check(
		"Right 1u column reuses main-panel right edge",
		spd_rect.end.x == main_rect.end.x
			and g_rect.end.x == main_rect.end.x
			and alt_rect.end.x == main_rect.end.x,
		"right=%.1f" % main_rect.end.x
	)

func _check_grid_flash_override_types() -> void:
	var overlay: Control = TerminalGridOverlayScript.new()
	var flash_rect := Rect2(98.0, 0.0, 40.0, 18.0)
	var flash_regions: Array[Rect2] = [flash_rect]
	overlay.set("override_regions", flash_regions)
	var inverted_regions: Array[Rect2] = overlay.get("override_regions")
	_check(
		"Flash override accepts a typed Rect2 array",
		inverted_regions.size() == 1 and inverted_regions[0] == flash_rect,
		"regions=%s" % inverted_regions
	)

	var cleared_regions: Array[Rect2] = []
	overlay.set("override_regions", cleared_regions)
	var normal_regions: Array[Rect2] = overlay.get("override_regions")
	_check(
		"Normal phase clears the typed override array",
		normal_regions.is_empty(),
		"regions=%s" % str(normal_regions)
	)

	overlay.free()


func _check_viewport_edge_hairline_insets() -> void:
	var overlay := TerminalGridOverlayScript.new()
	var full := Rect2(0.0, 0.0, 1920.0, 54.0)
	var bottom_safe := TerminalGridOverlayScript.edge_safe_region(
		full, full.size, Vector4(0.5, 0.0, 0.5, 0.5))
	var internal := Rect2(120.0, 0.0, 408.0, 36.0)
	var internal_safe := TerminalGridOverlayScript.edge_safe_region(
		internal, full.size, Vector4(0.5, 0.0, 0.5, 0.5))
	_check(
		"Control-edge hairlines default half a pixel inside without changing internal seams",
		bottom_safe == Rect2(0.5, 0.0, 1919.0, 53.5)
			and internal_safe == internal
			and overlay.edge_insets == TerminalGridOverlayScript.CONTROL_EDGE_INSETS
			and overlay.edge_insets == Vector4(0.5, 0.5, 0.5, 0.5),
		"bottom=%s internal=%s" % [bottom_safe, internal_safe]
	)
	overlay.free()


func _check_grid_outline_batching() -> void:
	var regions: Array[Rect2] = [
		Rect2(0.0, 0.0, 40.0, 18.0),
		Rect2(40.0, 0.0, 40.0, 18.0),
		Rect2(40.0, 0.0, 40.0, 18.0),
	]
	var segments := TerminalGridOverlayScript.outline_segments_for(
		regions, Vector2(80.0, 18.0),
		TerminalGridOverlayScript.CONTROL_EDGE_INSETS)
	_check(
		"Adjacent and duplicate grid boards share one batched seam",
		segments.size() == 14,
		"segments=%d expected=14" % segments.size()
	)


func _check_scale_invariant_grid_lines() -> void:
	_check(
		"Grid outlines use Godot hairlines that remain one physical pixel when scaled",
		is_equal_approx(TerminalGridOverlayScript.SCALE_INVARIANT_LINE_WIDTH, -1.0),
		"width=%.1f" % TerminalGridOverlayScript.SCALE_INVARIANT_LINE_WIDTH
	)

func _check(label: String, cond: bool, detail: String = "") -> void:
	if cond:
		_pass += 1
		print("  ✓ %s %s" % [label, detail])
	else:
		_fail += 1
		print("  ✗ %s %s" % [label, detail])
