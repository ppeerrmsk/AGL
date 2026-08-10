class_name HudBoardVisibility
extends RefCounted

## 对单个复合绘制 Control 内的逻辑框板直接做源渲染开关。
## 全部框板常亮时卸下材质，避免把临时首显成本留到常态 HUD。

const VISIBILITY_SHADER := preload("res://resources/shaders/hud_board_visibility.gdshader")
const MAX_BOARDS := 32
const BORDER_BLEED_PX := 1.0

var source: Control
var _material: ShaderMaterial
var _rects: Dictionary = {}
var _alphas: Dictionary = {}
var _draw_items: Array[CanvasItem] = []


func _init(target: Control) -> void:
	source = target
	_material = ShaderMaterial.new()
	_material.shader = VISIBILITY_SHADER
	_collect_draw_items(source)


func sync_regions(regions: Array[Dictionary]) -> void:
	var active_ids: Dictionary = {}
	var changed := false
	for descriptor in regions:
		var id := StringName(descriptor.get("id", &""))
		var rect: Rect2 = descriptor.get("rect", Rect2())
		if id.is_empty() or rect.size.x <= 0.0 or rect.size.y <= 0.0:
			continue
		active_ids[id] = true
		changed = changed or not _rects.has(id) or _rects[id] != rect
		_rects[id] = rect
		if not _alphas.has(id):
			# 新框板先关闭，避免进入树到首个 process 之间露出总体 1px 描边。
			_alphas[id] = 0.0
	for raw_id: Variant in _rects.keys():
		var id := StringName(raw_id)
		if active_ids.has(id):
			continue
		_rects.erase(id)
		# 保留已完成框板的 alpha；动态消失后重现不能被重新压暗。
		changed = true
	if changed:
		_apply()


func set_reveal_alpha(alpha: float, id: StringName) -> void:
	if not _rects.has(id):
		return
	_alphas[id] = clampf(alpha, 0.0, 1.0)
	_apply()


func has_board(id: StringName) -> bool:
	return _rects.has(id)


func board_is_visible(id: StringName) -> bool:
	if source == null or not is_instance_valid(source) or not _rects.has(id):
		return false
	if source.is_inside_tree():
		return source.is_visible_in_tree()
	return source.visible


func board_screen_position(id: StringName) -> Vector2:
	if source == null or not is_instance_valid(source) or not _rects.has(id):
		return Vector2.ZERO
	var rect: Rect2 = _rects[id]
	return source.position + rect.position


func _apply() -> void:
	if source == null or not is_instance_valid(source):
		return
	var ids: Array = _rects.keys()
	ids.sort_custom(func(a: Variant, b: Variant) -> bool:
		return String(a) < String(b))
	var rect_values := PackedVector4Array()
	var alpha_values := PackedFloat32Array()
	rect_values.resize(MAX_BOARDS)
	alpha_values.resize(MAX_BOARDS)
	var needs_visibility_material := false
	var count := mini(ids.size(), MAX_BOARDS)
	for index in range(MAX_BOARDS):
		rect_values[index] = Vector4.ZERO
		alpha_values[index] = 1.0
	for index in range(count):
		var id := StringName(ids[index])
		# draw_rect(..., false, 1px) 以边界为中心向外覆盖半像素；可见性区域
		# 向外扩 1px，才能把复合网格的外侧采样也一并关闭。
		var logical_rect: Rect2 = _rects[id]
		var rect := logical_rect.grow(BORDER_BLEED_PX)
		var alpha := clampf(float(_alphas.get(id, 1.0)), 0.0, 1.0)
		rect_values[index] = Vector4(
			rect.position.x, rect.position.y, rect.end.x, rect.end.y)
		alpha_values[index] = alpha
		needs_visibility_material = needs_visibility_material or alpha < 0.999
	_material.set_shader_parameter("board_count", count)
	_material.set_shader_parameter("board_rects", rect_values)
	_material.set_shader_parameter("board_alphas", alpha_values)
	for item in _draw_items:
		if item == null or not is_instance_valid(item):
			continue
		item.material = _material if needs_visibility_material else null
		item.queue_redraw()


func _collect_draw_items(parent: Node) -> void:
	if parent is CanvasItem:
		var item := parent as CanvasItem
		item.use_parent_material = false
		_draw_items.append(item)
	for child in parent.get_children():
		_collect_draw_items(child)
