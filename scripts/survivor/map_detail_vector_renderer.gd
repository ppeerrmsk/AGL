class_name MapDetailVectorRenderer
extends Node2D

## 4 km 城市细节瓦片的直接矢量烘焙源。
## 所有三角形在 setup 时按层合并提交；加载后零 _process / queue_redraw。

const DATA_PATH := "res://resources/maps/yokohama_gold_slice_preview.json"

const LAYER_COLORS := {
	"forest": Color8(113, 127, 117, 70),
	"farmland": Color8(138, 141, 123, 38),
	"orchard": Color8(123, 135, 116, 46),
	"grass": Color8(142, 145, 133, 46),
	"meadow": Color8(146, 147, 134, 42),
	"industrial": Color8(121, 126, 121, 56),
	"residential": Color8(128, 133, 127, 34),
	"parking": Color8(142, 142, 132, 58),
	"civic": Color8(138, 140, 130, 54),
	"park": Color8(126, 138, 122, 60),
	"water": Color8(101, 115, 117, 205),
}
const POLYGON_ORDER := [
	"forest", "farmland", "orchard", "grass", "meadow", "industrial", "residential",
	"parking", "civic", "park", "water",
]
const BUILDING_ORDER := ["building_small", "building_medium", "building_large"]
const PACKED_TRIANGLE_ORDER := [
	"forest", "farmland", "orchard", "grass", "meadow", "industrial", "residential",
	"parking", "civic", "park", "water", "building_small", "building_medium", "building_large",
]
const PACKED_LINE_ORDER := [
	"building_small_outline", "building_medium_outline", "building_large_outline",
	"rail", "waterway", "port",
]
const PACKED_MAX_UNCOMPRESSED_BYTES := 64 * 1024 * 1024
const LANDMARK_WALL_MAX_UNCOMPRESSED_BYTES := 8 * 1024 * 1024
const BUILDING_SMALL_FILL := Color8(135, 140, 135, 198)
const BUILDING_MEDIUM_FILL := Color8(146, 147, 139, 214)
const BUILDING_LARGE_FILL := Color8(160, 157, 145, 226)
const BUILDING_LARGE_WALL := Color8(77, 85, 84, 125)
const BUILDING_OUTLINE_SHADOW := Color8(80, 92, 91, 96)
const BUILDING_OUTLINE_HIGHLIGHT := Color8(178, 180, 169, 88)
const BUILDING_OUTLINE_CORE := Color8(113, 123, 120, 124)
const RAIL_CASING := Color8(96, 105, 103, 150)
const RAIL_CORE := Color8(145, 146, 132, 180)
const WATERWAY := Color8(83, 105, 112, 162)
const PORT := Color8(142, 147, 138, 145)

static var _definitions_by_path: Dictionary = {}
static var _metrics_by_path: Dictionary = {}
static var _data_errors: Dictionary = {}

var _data_path := DATA_PATH


class StaticPacket extends Node2D:
	var packet_points := PackedVector2Array()
	var packet_indices := PackedInt32Array()
	var packet_colors := PackedColorArray()

	func configure(definition: Dictionary) -> void:
		packet_points = definition.get("points", PackedVector2Array())
		packet_indices = definition.get("indices", PackedInt32Array())
		packet_colors = definition.get("colors", PackedColorArray())

	func _draw() -> void:
		if packet_points.is_empty():
			return
		RenderingServer.canvas_item_add_triangle_array(
			get_canvas_item(), packet_indices, packet_points, packet_colors)


class BinaryCursor extends RefCounted:
	var data := PackedByteArray()
	var offset := 0

	func _init(bytes: PackedByteArray, start_offset: int = 0) -> void:
		data = bytes
		offset = start_offset

	func read_u16() -> int:
		var value := data.decode_u16(offset)
		offset += 2
		return value

	func read_u32() -> int:
		var value := data.decode_u32(offset)
		offset += 4
		return value

	func read_s32() -> int:
		var value := data.decode_u32(offset)
		offset += 4
		return value - 4294967296 if value > 2147483647 else value

	func read_f32() -> float:
		var value := data.decode_float(offset)
		offset += 4
		return value

	func read_flat_points(origin: Vector2, quantization: float) -> Array:
		var point_count := read_u32()
		var values: Array = []
		values.resize(point_count * 2)
		for index in range(point_count):
			values[index * 2] = origin.x + float(read_s32()) / quantization
			values[index * 2 + 1] = origin.y + float(read_s32()) / quantization
		return values


func setup(data_path: String = DATA_PATH) -> Dictionary:
	_data_path = data_path
	var result := prewarm(_data_path)
	if not bool(result.get("ok", false)):
		return result
	z_index = 2
	var definitions: Array = _definitions_by_path.get(_data_path, [])
	for index in range(definitions.size()):
		var definition: Dictionary = definitions[index]
		var packet := StaticPacket.new()
		packet.name = "DetailPacket_%02d_%s" % [index, String(definition.get("name", "layer"))]
		packet.configure(definition)
		add_child(packet)
	return result


static func prewarm(data_path: String = DATA_PATH) -> Dictionary:
	if _definitions_by_path.has(data_path):
		var cached: Dictionary = (_metrics_by_path.get(data_path, {}) as Dictionary).duplicate(true)
		cached["cache_hit"] = true
		return cached
	if _data_errors.has(data_path):
		return {"ok": false, "error": String(_data_errors[data_path])}
	var t0 := Time.get_ticks_msec()
	var parsed = _load_data(data_path)
	if typeof(parsed) != TYPE_DICTIONARY:
		var parse_error := "detail tile parse failed: %s" % data_path
		_data_errors[data_path] = parse_error
		return {"ok": false, "error": parse_error}

	var data: Dictionary = parsed
	var definitions: Array = []
	var triangles: Dictionary = data.get("triangles", {})
	var lines: Dictionary = data.get("lines", {})
	for layer_any in POLYGON_ORDER:
		var layer := String(layer_any)
		_append_flat_triangle_packet(definitions, layer, triangles.get(layer, []), LAYER_COLORS[layer])

	# 全图共享的静态地标 relief：只让大建筑产生冷暗侧墙偏移，避免为每栋小楼创建
	# 运行时节点。墙体先画、屋顶后画，形成与横滨金样一致的俯视伪立体层次。
	var large_building_outlines: Array = lines.get("building_large_outline", [])
	_append_line_packet(definitions, "building_large_wall", large_building_outlines, 6.5,
		BUILDING_LARGE_WALL, Vector2(2.4, 3.2))
	var landmark_wall_triangles := _merge_landmark_wall_packet(definitions, data_path)
	_append_flat_triangle_packet(definitions, "building_small",
		triangles.get("building_small", []), BUILDING_SMALL_FILL)
	_append_flat_triangle_packet(definitions, "building_medium",
		triangles.get("building_medium", []), BUILDING_MEDIUM_FILL)
	_append_flat_triangle_packet(definitions, "building_large",
		triangles.get("building_large", []), BUILDING_LARGE_FILL)

	# 小建筑用体块 + 单层细线概括城区，不逐栋做完整浮雕。中大型建筑才保留
	# 阴影/高光层次：这是 detail 烘焙的固定性能降级档，也是远景去噪策略。
	var small_building_outlines: Array = lines.get("building_small_outline", [])
	var emphasized_building_outlines: Array = []
	emphasized_building_outlines.append_array(lines.get("building_medium_outline", []))
	emphasized_building_outlines.append_array(large_building_outlines)
	_append_line_packet(definitions, "building_outline_shadow", emphasized_building_outlines, 3.2,
		BUILDING_OUTLINE_SHADOW, Vector2(0.9, 1.1))
	_append_line_packet(definitions, "building_outline_highlight", emphasized_building_outlines, 2.1,
		BUILDING_OUTLINE_HIGHLIGHT, Vector2(-0.6, -0.7))
	_append_line_packet(definitions, "building_outline_core", emphasized_building_outlines, 1.55,
		BUILDING_OUTLINE_CORE)
	_append_line_packet(definitions, "building_small_outline_core", small_building_outlines, 1.0,
		BUILDING_OUTLINE_CORE)
	_append_line_packet(definitions, "rail_casing", lines.get("rail", []), 2.7, RAIL_CASING)
	_append_line_packet(definitions, "rail_core", lines.get("rail", []), 0.85, RAIL_CORE)
	_append_line_packet(definitions, "waterway", lines.get("waterway", []), 1.15, WATERWAY)
	_append_line_packet(definitions, "port", lines.get("port", []), 1.25, PORT)

	var vertex_count := 0
	var triangle_count := 0
	for definition_any in definitions:
		var definition: Dictionary = definition_any
		vertex_count += (definition["points"] as PackedVector2Array).size()
		triangle_count += (definition["indices"] as PackedInt32Array).size() / 3
	var metrics := {
		"ok": not definitions.is_empty(),
		"cache_hit": false,
		"data_path": data_path,
		"tile_id": String(data.get("tile_id", "detail")),
		"build_ms": Time.get_ticks_msec() - t0,
		"draw_calls": definitions.size(),
		"vertices": vertex_count,
		"triangles": triangle_count,
		"source_counts": data.get("counts", {}),
		"landmark_wall_triangles": landmark_wall_triangles,
		"landmark_wall_path": landmark_wall_path_for(data_path),
	}
	_definitions_by_path[data_path] = definitions
	_metrics_by_path[data_path] = metrics
	print("[MapDetailVectorRenderer] %s" % metrics)
	return metrics.duplicate(true)

static func release_prewarm(data_path: String) -> void:
	# loading viewport 已读回纹理后，运行时不再需要源三角数组。逐瓦片释放，
	# 避免把 2,000+ 万字节 JSON 解包后的 PackedArray 常驻到战斗场景。
	_definitions_by_path.erase(data_path)
	_metrics_by_path.erase(data_path)


static func landmark_wall_path_for(data_path: String) -> String:
	if not data_path.ends_with(".agdt.gz"):
		return ""
	return "res://resources/maps/detail_landmark_walls/%s.aglw.gz" % data_path.get_file().trim_suffix(".agdt.gz")


static func _merge_landmark_wall_packet(definitions: Array, data_path: String) -> int:
	var wall_path := landmark_wall_path_for(data_path)
	if wall_path.is_empty() or not FileAccess.file_exists(wall_path):
		return 0
	var compressed := FileAccess.get_file_as_bytes(wall_path)
	if compressed.is_empty():
		return 0
	var bytes := compressed.decompress_dynamic(
		LANDMARK_WALL_MAX_UNCOMPRESSED_BYTES, FileAccess.COMPRESSION_GZIP)
	if bytes.size() < 24 or bytes.slice(0, 4).get_string_from_ascii() != "AGLW":
		return 0
	if bytes.decode_u16(4) != 1:
		return 0
	var origin := Vector2(bytes.decode_float(8), bytes.decode_float(12))
	var quantization := bytes.decode_float(16)
	var point_count := int(bytes.decode_u32(20))
	if quantization <= 0.0 or point_count % 3 != 0 or bytes.size() != 24 + point_count * 12:
		return 0
	var target: Dictionary = {}
	for definition_any in definitions:
		var definition: Dictionary = definition_any
		if String(definition.get("name", "")) == "building_large_wall":
			target = definition
			break
	if target.is_empty():
		target = {
			"name": "building_large_wall",
			"points": PackedVector2Array(),
			"indices": PackedInt32Array(),
			"colors": PackedColorArray(),
		}
		definitions.append(target)
	var points: PackedVector2Array = target.points
	var indices: PackedInt32Array = target.indices
	var colors: PackedColorArray = target.colors
	var base := points.size()
	points.resize(base + point_count)
	indices.resize(base + point_count)
	colors.resize(base + point_count)
	for index in range(point_count):
		var offset := 24 + index * 12
		var x := bytes.decode_u32(offset)
		var y := bytes.decode_u32(offset + 4)
		var sx := x - 4294967296 if x > 2147483647 else x
		var sy := y - 4294967296 if y > 2147483647 else y
		points[base + index] = origin + Vector2(float(sx), float(sy)) / quantization
		indices[base + index] = base + index
		colors[base + index] = Color8(
			bytes[offset + 8], bytes[offset + 9], bytes[offset + 10], bytes[offset + 11])
	return point_count / 3


static func _load_data(data_path: String) -> Variant:
	if data_path.ends_with(".agdt.gz"):
		return _load_packed_data(data_path)
	var file := FileAccess.open(data_path, FileAccess.READ)
	if file == null:
		return null
	var parsed = JSON.parse_string(file.get_as_text())
	file.close()
	return parsed

static func _load_packed_data(data_path: String) -> Variant:
	var compressed := FileAccess.get_file_as_bytes(data_path)
	if compressed.is_empty():
		return null
	var bytes := compressed.decompress_dynamic(
		PACKED_MAX_UNCOMPRESSED_BYTES, FileAccess.COMPRESSION_GZIP)
	if bytes.size() < 28 or bytes.slice(0, 4).get_string_from_ascii() != "AGDT":
		return null
	var cursor := BinaryCursor.new(bytes, 4)
	var version := cursor.read_u16()
	cursor.read_u16() # reserved
	if version != 1:
		return null
	var origin := Vector2(cursor.read_f32(), cursor.read_f32())
	cursor.read_f32() # width
	cursor.read_f32() # height
	var quantization := cursor.read_f32()
	if quantization <= 0.0:
		return null
	var triangles: Dictionary = {}
	for layer_any in PACKED_TRIANGLE_ORDER:
		var layer := String(layer_any)
		var values := cursor.read_flat_points(origin, quantization)
		if not values.is_empty():
			triangles[layer] = values
	var lines: Dictionary = {}
	for layer_any in PACKED_LINE_ORDER:
		var layer := String(layer_any)
		var path_count := cursor.read_u32()
		var paths: Array = []
		paths.resize(path_count)
		for path_index in range(path_count):
			paths[path_index] = cursor.read_flat_points(origin, quantization)
		if not paths.is_empty():
			lines[layer] = paths
	return {
		"tile_id": data_path.get_file().trim_suffix(".agdt.gz"),
		"triangles": triangles,
		"lines": lines,
		"counts": {},
	}


static func _append_flat_triangle_packet(
		definitions: Array, name: String, values_any: Variant, color: Color,
		offset: Vector2 = Vector2.ZERO) -> void:
	var values: Array = values_any if values_any is Array else []
	if values.size() < 6:
		return
	var points := PackedVector2Array()
	var indices := PackedInt32Array()
	var colors := PackedColorArray()
	points.resize(values.size() / 2)
	indices.resize(points.size())
	colors.resize(points.size())
	for index in range(points.size()):
		points[index] = Vector2(float(values[index * 2]), float(values[index * 2 + 1])) + offset
		indices[index] = index
		colors[index] = color
	definitions.append({"name": name, "points": points, "indices": indices, "colors": colors})


static func _append_line_packet(
		definitions: Array, name: String, paths_any: Variant, width: float, color: Color,
		offset: Vector2 = Vector2.ZERO) -> void:
	var paths: Array = paths_any if paths_any is Array else []
	var points := PackedVector2Array()
	var indices := PackedInt32Array()
	var colors := PackedColorArray()
	var half_width := width * 0.5
	for path_any in paths:
		var values: Array = path_any if path_any is Array else []
		for value_index in range(0, values.size() - 2, 2):
			var a := Vector2(float(values[value_index]), float(values[value_index + 1])) + offset
			var b := Vector2(float(values[value_index + 2]), float(values[value_index + 3])) + offset
			var direction := b - a
			if direction.length_squared() < 0.01:
				continue
			var normal := Vector2(-direction.y, direction.x).normalized() * half_width
			var base := points.size()
			points.append_array(PackedVector2Array([
				a - normal, a + normal, b + normal,
				a - normal, b + normal, b - normal,
			]))
			indices.append_array(PackedInt32Array([
				base, base + 1, base + 2, base + 3, base + 4, base + 5,
			]))
			for _vertex in range(6):
				colors.append(color)
	if not points.is_empty():
		definitions.append({"name": name, "points": points, "indices": indices, "colors": colors})
