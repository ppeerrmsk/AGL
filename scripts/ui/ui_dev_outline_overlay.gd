class_name UiDevOutlineOverlay
extends Control

## UI Dev 场景专用诊断层。
## 编号只由矩形的位置与包含关系产生，不读取面板承载的功能或文字。

const LABEL_FONT_SOURCE: FontFile = preload("res://resources/fonts/Silkscreen-Regular.ttf")
const OUTLINE_COLOR := Color("b94cff")
const OUTLINE_WIDTH := 2.0
const OUTLINE_INSET := 1.0
const LABEL_MAX_FONT_SIZE := 10
const LABEL_MIN_FONT_SIZE := 5
const LABEL_MARGIN := 2.0
const RECT_EPSILON := 0.01

var regions: Array[Rect2] = []:
	set(value):
		regions = value.duplicate()
		_rebuild_entries()

var flatten_descendants := false:
	set(value):
		flatten_descendants = value
		_rebuild_entries()

var entries: Array[Dictionary] = []
var _label_font: FontFile


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus_mode = Control.FOCUS_NONE
	clip_contents = false
	z_index = 1000
	_label_font = LABEL_FONT_SOURCE.duplicate(true) as FontFile
	_label_font.antialiasing = TextServer.FONT_ANTIALIASING_NONE
	_label_font.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
	_rebuild_entries()


func _rebuild_entries() -> void:
	entries = build_entries(regions, flatten_descendants)
	queue_redraw()


func _draw() -> void:
	if _label_font == null:
		return
	for entry in entries:
		var rect: Rect2 = entry["rect"]
		var outline_rect := rect.grow(-OUTLINE_INSET)
		if outline_rect.size.x > 0.0 and outline_rect.size.y > 0.0:
			draw_rect(outline_rect, OUTLINE_COLOR, false, OUTLINE_WIDTH, false)
	_draw_labels_without_overlap()


func _draw_labels_without_overlap() -> void:
	var label_entries := entries.duplicate()
	label_entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a["depth"]) > int(b["depth"])
	)
	var occupied: Array[Rect2] = []
	for entry in label_entries:
		var rect: Rect2 = entry["rect"]
		var code := String(entry["code"])
		var font_size := _fit_label_font_size(code, rect)
		var text_size := _label_font.get_string_size(
			code, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size)
		var label_size := Vector2(
			minf(text_size.x + 4.0, maxf(rect.size.x - LABEL_MARGIN * 2.0, 1.0)),
			minf(_label_font.get_height(font_size) + 1.0,
				maxf(rect.size.y - LABEL_MARGIN * 2.0, 1.0))
		)
		var label_rect := _find_label_rect(rect, label_size, occupied)
		occupied.append(label_rect)
		draw_rect(label_rect, Color(0.0, 0.0, 0.0, 0.9), true)
		var baseline := Vector2(
			label_rect.position.x + 2.0,
			label_rect.position.y + minf(
				_label_font.get_ascent(font_size), label_rect.size.y - 1.0)
		)
		draw_string(_label_font, baseline, code, HORIZONTAL_ALIGNMENT_LEFT,
			maxf(label_rect.size.x - 4.0, 1.0), font_size, OUTLINE_COLOR)


func _fit_label_font_size(code: String, rect: Rect2) -> int:
	var max_width := maxf(rect.size.x - LABEL_MARGIN * 2.0 - 4.0, 1.0)
	var max_height := maxf(rect.size.y - LABEL_MARGIN * 2.0 - 1.0, 1.0)
	var result := LABEL_MAX_FONT_SIZE
	while result > LABEL_MIN_FONT_SIZE:
		var text_size := _label_font.get_string_size(
			code, HORIZONTAL_ALIGNMENT_LEFT, -1.0, result)
		if text_size.x <= max_width and _label_font.get_height(result) <= max_height:
			break
		result -= 1
	return result


func _find_label_rect(container: Rect2, label_size: Vector2,
		occupied: Array[Rect2]) -> Rect2:
	var x := container.end.x - LABEL_MARGIN - label_size.x
	var y := container.position.y + LABEL_MARGIN
	var candidate := Rect2(Vector2(x, y), label_size)
	while _overlaps_any(candidate, occupied):
		y += label_size.y + 1.0
		if y + label_size.y > container.end.y - LABEL_MARGIN:
			y = container.position.y + LABEL_MARGIN
			x -= label_size.x + 1.0
			if x < container.position.x + LABEL_MARGIN:
				x = container.position.x + LABEL_MARGIN
				break
		candidate.position = Vector2(x, y)
	return candidate


static func _overlaps_any(rect: Rect2, others: Array[Rect2]) -> bool:
	for other in others:
		if rect.intersects(other, true):
			return true
	return false


static func build_entries(raw_regions: Array[Rect2], flatten_all_descendants := false) -> Array[Dictionary]:
	var unique_regions := _deduplicate_regions(raw_regions)
	var nodes: Array[Dictionary] = []
	for rect in unique_regions:
		nodes.append({"rect": rect, "parent": -1, "children": []})

	for child_index in range(nodes.size()):
		var child_rect: Rect2 = nodes[child_index]["rect"]
		var parent_index := -1
		var parent_area := INF
		for candidate_index in range(nodes.size()):
			if candidate_index == child_index:
				continue
			var candidate_rect: Rect2 = nodes[candidate_index]["rect"]
			var candidate_area := candidate_rect.get_area()
			if _strictly_contains(candidate_rect, child_rect) and candidate_area < parent_area:
				parent_index = candidate_index
				parent_area = candidate_area
		nodes[child_index]["parent"] = parent_index

	var roots: Array[int] = []
	for index in range(nodes.size()):
		var parent_index: int = nodes[index]["parent"]
		if parent_index < 0:
			roots.append(index)
		else:
			var children: Array = nodes[parent_index]["children"]
			children.append(index)
			nodes[parent_index]["children"] = children
	_sort_indices_by_position(roots, nodes)
	for node in nodes:
		var children: Array = node["children"]
		_sort_untyped_indices_by_position(children, nodes)

	var result: Array[Dictionary] = []
	for root_order in range(roots.size()):
		var root_code := alphabetic_code(root_order)
		if flatten_all_descendants:
			_append_flat_root(nodes, roots[root_order], root_code, result)
		else:
			_append_branch(nodes, roots[root_order], root_code, 0, result)
	return result


static func alphabetic_code(index: int) -> String:
	var value := index + 1
	var result := ""
	while value > 0:
		value -= 1
		result = String.chr(65 + value % 26) + result
		value /= 26
	return result


static func _append_branch(nodes: Array[Dictionary], index: int, code: String,
		depth: int, result: Array[Dictionary]) -> void:
	result.append({
		"code": code,
		"rect": nodes[index]["rect"],
		"depth": depth,
	})
	var children: Array = nodes[index]["children"]
	for child_order in range(children.size()):
		_append_branch(nodes, int(children[child_order]),
			"%s.%d" % [code, child_order + 1], depth + 1, result)


static func _append_flat_root(nodes: Array[Dictionary], root_index: int,
		root_code: String, result: Array[Dictionary]) -> void:
	result.append({
		"code": root_code,
		"rect": nodes[root_index]["rect"],
		"depth": 0,
	})
	var descendants: Array[int] = []
	_collect_descendants(nodes, root_index, descendants)
	_sort_indices_by_position(descendants, nodes)
	for child_order in range(descendants.size()):
		result.append({
			"code": "%s%d" % [root_code, child_order + 1],
			"rect": nodes[descendants[child_order]]["rect"],
			"depth": 1,
		})


static func _collect_descendants(nodes: Array[Dictionary], index: int,
		result: Array[int]) -> void:
	var children: Array = nodes[index]["children"]
	for child in children:
		var child_index := int(child)
		result.append(child_index)
		_collect_descendants(nodes, child_index, result)


static func _deduplicate_regions(raw_regions: Array[Rect2]) -> Array[Rect2]:
	var result: Array[Rect2] = []
	for rect in raw_regions:
		if rect.size.x <= 0.0 or rect.size.y <= 0.0:
			continue
		var duplicate := false
		for existing in result:
			if rect.position.is_equal_approx(existing.position) \
					and rect.size.is_equal_approx(existing.size):
				duplicate = true
				break
		if not duplicate:
			result.append(rect)
	return result


static func _strictly_contains(outer: Rect2, inner: Rect2) -> bool:
	if outer.get_area() <= inner.get_area() + RECT_EPSILON:
		return false
	return outer.position.x <= inner.position.x + RECT_EPSILON \
		and outer.position.y <= inner.position.y + RECT_EPSILON \
		and outer.end.x + RECT_EPSILON >= inner.end.x \
		and outer.end.y + RECT_EPSILON >= inner.end.y


static func _sort_indices_by_position(indices: Array[int], nodes: Array[Dictionary]) -> void:
	for index in range(1, indices.size()):
		var value := indices[index]
		var cursor := index - 1
		while cursor >= 0 and _rect_precedes(
				nodes[value]["rect"], nodes[indices[cursor]]["rect"]):
			indices[cursor + 1] = indices[cursor]
			cursor -= 1
		indices[cursor + 1] = value


static func _sort_untyped_indices_by_position(indices: Array,
		nodes: Array[Dictionary]) -> void:
	for index in range(1, indices.size()):
		var value := int(indices[index])
		var cursor := index - 1
		while cursor >= 0 and _rect_precedes(
				nodes[value]["rect"], nodes[int(indices[cursor])]["rect"]):
			indices[cursor + 1] = indices[cursor]
			cursor -= 1
		indices[cursor + 1] = value


static func _rect_precedes(a: Rect2, b: Rect2) -> bool:
	if not is_equal_approx(a.position.y, b.position.y):
		return a.position.y < b.position.y
	if not is_equal_approx(a.position.x, b.position.x):
		return a.position.x < b.position.x
	if not is_equal_approx(a.size.y, b.size.y):
		return a.size.y > b.size.y
	return a.size.x > b.size.x
