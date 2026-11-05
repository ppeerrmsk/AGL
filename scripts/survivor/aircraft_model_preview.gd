class_name AircraftModelPreview
extends Control

## 选机页、进化树和浮窗共用的静态机体图。PNG 与选机页保持同源；
## 无 PNG 的机型从已有逐机模型取顶视图，不创建 Aircraft / SubViewport / 常驻 tick。
const Silhouettes := preload("res://scripts/aircraft_silhouette_catalog.gd")
const Models := preload("res://scripts/experiments/volume_aircraft_catalog.gd")
static var _projections: Dictionary = {}

var _texture: Texture2D
var _projection: Dictionary = {}
var model_key: String = ""


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	resized.connect(queue_redraw)


func show_profile(profile: PlayableAircraft) -> void:
	_texture = null
	_projection = {}
	model_key = ""
	if profile != null and profile.base_params != null:
		var airframe := profile.base_params.display_name
		model_key = Silhouettes.canonical_model_key_for_display_name(airframe)
		_texture = Silhouettes.texture_for_display_name(airframe)
		if _texture == null and not model_key.is_empty():
			_projection = _projection_for(model_key)
	queue_redraw()


func has_model() -> bool:
	return _texture != null or not _projection.is_empty()


func _draw() -> void:
	if not has_model() or size.x <= 0.0 or size.y <= 0.0:
		return
	if _texture != null:
		var texture_size := _texture.get_size()
		var factor := minf(size.x / texture_size.x, size.y / texture_size.y)
		var display_size := texture_size * factor
		draw_texture_rect(_texture, Rect2((size - display_size) * 0.5, display_size), false)
		return
	var bounds: Rect2 = _projection["bounds"]
	var factor := minf(size.x / bounds.size.x, size.y / bounds.size.y)
	draw_set_transform(size * 0.5 - bounds.get_center() * factor, 0.0, Vector2.ONE * factor)
	RenderingServer.canvas_item_add_triangle_array(get_canvas_item(),
		_projection["indices"], _projection["points"], _projection["colors"])


## 每种机型只投影一次；按高度从下往上提交，保留座舱与进气口等识别细节。
static func _projection_for(key: String) -> Dictionary:
	if _projections.has(key):
		return _projections[key]
	var mesh := Models.build(key)
	if mesh == null:
		_projections[key] = {}
		return {}
	var triangles: Array[Dictionary] = []
	for surface in range(mesh.get_surface_count()):
		var arrays := mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		var count := vertices.size() if indices.is_empty() else indices.size()
		for start in range(0, count, 3):
			var points := PackedVector2Array()
			var shades := PackedColorArray()
			var height := 0.0
			for offset in range(3):
				var index := start + offset if indices.is_empty() else indices[start + offset]
				var vertex := vertices[index]
				points.append(Vector2(vertex.x, vertex.z))
				height += vertex.y
				var shade := colors[index] if not colors.is_empty() else Color.WHITE
				shade.a = 1.0 # 模型 alpha 是机翼掩码，不是界面透明度。
				shades.append(shade)
			if absf((points[1] - points[0]).cross(points[2] - points[0])) > 0.00001:
				triangles.append({"height": height, "points": points, "colors": shades})
	triangles.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["height"] < b["height"])
	var points := PackedVector2Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	for triangle in triangles:
		points.append_array(triangle["points"])
		colors.append_array(triangle["colors"])
	if points.is_empty():
		_projections[key] = {}
		return {}
	var bounds := Rect2(points[0], Vector2.ZERO)
	for index in range(points.size()):
		indices.append(index)
		bounds = bounds.expand(points[index])
	var result := {"points": points, "colors": colors, "indices": indices, "bounds": bounds}
	_projections[key] = result
	return result
