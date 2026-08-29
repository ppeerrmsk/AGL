class_name CanvasTrianglePacket
extends RefCounted

## CanvasItem 三角批次的最小复用层。
##
## 这里只管理 points / indices / colors 三组值数据及一次性提交，不知道弹丸、爆炸或地图
## 的领域语义。调用方仍负责缓存、LOD、生命周期和绘制顺序。


static func create() -> Dictionary:
	return {
		"points": PackedVector2Array(),
		"indices": PackedInt32Array(),
		"colors": PackedColorArray(),
	}


static func layer(layers: Dictionary, name: String) -> Dictionary:
	if not layers.has(name):
		layers[name] = create()
	return layers[name]


static func append_triangle(packet: Dictionary, a: Vector2, b: Vector2, c: Vector2,
		color: Color, minimum_double_area: float = 0.0) -> bool:
	if absf((b - a).cross(c - a)) < minimum_double_area:
		return false
	var points: PackedVector2Array = packet["points"]
	var indices: PackedInt32Array = packet["indices"]
	var colors: PackedColorArray = packet["colors"]
	var base := points.size()
	points.append_array(PackedVector2Array([a, b, c]))
	indices.append_array(PackedInt32Array([base, base + 1, base + 2]))
	colors.append_array(PackedColorArray([color, color, color]))
	return true


static func append_triangle_colors(packet: Dictionary, a: Vector2, b: Vector2, c: Vector2,
		color_a: Color, color_b: Color, color_c: Color,
		minimum_double_area: float = 0.0) -> bool:
	if absf((b - a).cross(c - a)) < minimum_double_area:
		return false
	var points: PackedVector2Array = packet["points"]
	var indices: PackedInt32Array = packet["indices"]
	var colors: PackedColorArray = packet["colors"]
	var base := points.size()
	points.append_array(PackedVector2Array([a, b, c]))
	indices.append_array(PackedInt32Array([base, base + 1, base + 2]))
	colors.append_array(PackedColorArray([color_a, color_b, color_c]))
	return true


static func append_rect(packet: Dictionary, rect: Rect2, color: Color) -> void:
	var a := rect.position
	var b := Vector2(rect.end.x, rect.position.y)
	var c := rect.end
	var d := Vector2(rect.position.x, rect.end.y)
	append_triangle(packet, a, b, c, color)
	append_triangle(packet, a, c, d, color)


static func append_indexed(packet: Dictionary, vertices: PackedVector2Array,
		indices_to_append: PackedInt32Array, color: Color,
		minimum_double_area: float = 0.0) -> int:
	var appended := 0
	for index in range(0, indices_to_append.size(), 3):
		if index + 2 >= indices_to_append.size():
			break
		var ia := indices_to_append[index]
		var ib := indices_to_append[index + 1]
		var ic := indices_to_append[index + 2]
		if ia < 0 or ib < 0 or ic < 0 \
				or ia >= vertices.size() or ib >= vertices.size() or ic >= vertices.size():
			continue
		if append_triangle(packet, vertices[ia], vertices[ib], vertices[ic], color,
				minimum_double_area):
			appended += 1
	return appended


static func sequential_indices(point_count: int) -> PackedInt32Array:
	var indices := PackedInt32Array()
	indices.resize(maxi(point_count, 0))
	for index in indices.size():
		indices[index] = index
	return indices


static func submit_arrays(canvas_item: RID, indices: PackedInt32Array,
		points: PackedVector2Array, colors: PackedColorArray) -> bool:
	if not canvas_item.is_valid() or points.is_empty() or indices.is_empty() \
			or colors.size() != points.size() or indices.size() % 3 != 0:
		return false
	RenderingServer.canvas_item_add_triangle_array(canvas_item, indices, points, colors)
	return true


static func submit(canvas_item: RID, packet: Dictionary) -> bool:
	return submit_arrays(
		canvas_item,
		packet.get("indices", PackedInt32Array()),
		packet.get("points", PackedVector2Array()),
		packet.get("colors", PackedColorArray()))
