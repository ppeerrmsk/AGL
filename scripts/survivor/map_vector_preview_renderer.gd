class_name MapVectorPreviewRenderer
extends Node2D

## 东京湾 V43 全图纯矢量候选渲染器。
##
## 所有几何只在首次进入某个 LOD 时构建一次；每个有序图层合并为一个
## RenderingServer triangle-array canvas command。相机移动/缩放不重绘地图，
## 跨 LOD 只切换已缓存根节点的 visible。

const DATA_PATH := "res://resources/maps/tokyo_bay_vector_preview.json"
const DENSITY_PATH := "res://resources/maps/tokyo_bay_operational_density.agod.gz"
const DENSITY_MAX_UNCOMPRESSED_BYTES := 2 * 1024 * 1024
const OPERATIONAL_BUILDINGS_PATH := "res://resources/maps/tokyo_bay_operational_buildings.agob.gz"
const OPERATIONAL_BUILDINGS_MAX_UNCOMPRESSED_BYTES := 32 * 1024 * 1024
const OPERATIONAL_ROADS_PATH := "res://resources/maps/tokyo_bay_operational_roads.agor.gz"
const OPERATIONAL_ROADS_MAX_UNCOMPRESSED_BYTES := 4 * 1024 * 1024
const OPERATIONAL_LANDMARKS_PATH := "res://resources/maps/tokyo_bay_operational_landmarks.aglw.gz"
const OPERATIONAL_LANDMARKS_MAX_UNCOMPRESSED_BYTES := 4 * 1024 * 1024

const LOD_STRATEGIC := 0
const LOD_OPERATIONAL := 1
const LOD_DETAIL := 2
const LOD_TAB := 3

const STRATEGIC_REFERENCE_ZOOM := 0.20
const OPERATIONAL_REFERENCE_ZOOM := 0.35
const DETAIL_REFERENCE_ZOOM := 1.00
const OP_MASS_FADE_START_ZOOM := 0.18
const OP_MASS_FADE_END_ZOOM := 0.58
const OP_MASS_MIN_OPACITY := 0.28
const OP_ROOF_FADE_START_ZOOM := 0.24
const OP_ROOF_FADE_END_ZOOM := 0.58
const OP_ROOF_MAX_OPACITY := 0.56
const OP_DEPTH_FADE_START_ZOOM := 0.34
const OP_DEPTH_FADE_END_ZOOM := 0.74
const OP_DEPTH_MAX_OPACITY := 0.72

const SEA_STRATEGIC := Color8(127, 138, 136)
const SEA_OPERATIONAL := Color8(124, 136, 135)
const SEA_DETAIL := Color8(122, 134, 134)
const SEA_SHALLOW_1 := Color8(130, 140, 136)
const SEA_SHALLOW_2 := Color8(134, 142, 136)
# PNG 靠街区密度帮助识别陆地；静态预览尚未具备同等密度时，底色必须先保证可读。
const LAND_STRATEGIC := Color8(146, 144, 136)
const LAND_OPERATIONAL := Color8(148, 146, 137)
const LAND_DETAIL := Color8(150, 148, 139)
const LAND_HI := Color8(160, 155, 143, 14)
const URBAN_STRATEGIC := Color8(128, 127, 120, 40)
const URBAN_OPERATIONAL := Color8(120, 120, 116, 14)
const URBAN_DETAIL := Color8(126, 125, 118, 44)
const URBAN_EDGE := Color8(78, 81, 79, 64)
const AIRPORT := Color8(151, 150, 134)
const AIRPORT_EDGE := Color8(174, 174, 153, 128)
const ROAD_SHADOW := Color8(78, 90, 89, 44)
const ROAD_CASING := Color8(91, 101, 99, 116)
const ROAD_MAJOR := Color8(157, 151, 123, 225)
const ROAD_TRUNK := Color8(153, 151, 130, 214)
const ROAD_PRIMARY := Color8(149, 153, 136, 190)
const ROAD_SECONDARY := Color8(146, 153, 144, 184)
const ROAD_TERTIARY := Color8(150, 158, 151, 170)
const ROAD_LOCAL := Color8(170, 175, 166, 135)
const ROAD_NEIGHBORHOOD := Color8(114, 114, 110, 170)
const ROAD_SERVICE := Color8(160, 168, 160, 90)
const ROAD_HIGHLIGHT := Color8(213, 198, 145, 72)
const INDUSTRIAL := Color8(132, 124, 109, 64)
## 数据通道仍分开，但显示统一落入暖灰纸板色族；主要靠明度而非蓝/绿/橙色相区分。
const DENSITY_URBAN := Color8(113, 112, 106)
const DENSITY_VEGETATION := Color8(119, 116, 108)
const DENSITY_INDUSTRIAL := Color8(126, 120, 108)
const OP_BUILDING_LARGE := Color8(154, 153, 143, 185)
const OP_BUILDING_MEDIUM := Color8(142, 144, 136, 175)
const OP_BUILDING_SMALL := Color8(132, 138, 132, 150)
const OP_BUILDING_CASING := Color8(80, 92, 91, 88)
const OP_BUILDING_CASING_EXPAND_PX := 1.6
const OP_BUILDING_WALL := Color8(74, 85, 84, 86)
const OP_BUILDING_WALL_OFFSET := Vector2(2.2, 3.0)
const APRON := Color8(147, 140, 123, 54)
const RUNWAY_CASING := Color8(94, 107, 105, 24)
const RUNWAY_CORE := Color8(169, 164, 140, 118)
const TAXIWAY := Color8(157, 160, 148, 38)
const PORT := Color8(145, 141, 125, 62)
const CONTEXT_SHADOW := Color8(76, 76, 72, 38)
const CONTEXT_GRAY := Color8(124, 121, 113, 50)
const CONTEXT_GRAY_INSET := Color8(143, 139, 128, 28)
const CONTEXT_GREEN := Color8(119, 117, 110, 48)
const CONTEXT_GREEN_INSET := Color8(139, 135, 126, 27)
const CONTEXT_TAUPE := Color8(130, 123, 110, 50)
const CONTEXT_TAUPE_INSET := Color8(147, 139, 125, 29)
const CONTEXT_WARM_GRAY := Color8(126, 122, 113, 46)
const CONTEXT_WARM_GRAY_INSET := Color8(144, 139, 129, 26)
const CONTEXT_MIN_AREA_PX2 := 75000.0
const CONTEXT_MAX_BLOCKS := 120
const CONTEXT_SHADOW_OFFSET := Vector2(6.0, 8.0)
const CONTEXT_INSET_PX := 8.0
const MASK_INDEX_CELL_PX := 1200.0
const RELIEF_GREEN_BASE := Color8(118, 116, 109, 42)
const RELIEF_GREEN_MIDDLE := Color8(134, 130, 121, 30)
const RELIEF_GREEN_INNER := Color8(149, 143, 131, 18)
const RELIEF_GRAY_BASE := Color8(123, 121, 113, 38)
const RELIEF_GRAY_MIDDLE := Color8(138, 134, 124, 28)
const RELIEF_GRAY_INNER := Color8(151, 146, 134, 16)
const RELIEF_TAUPE_BASE := Color8(130, 123, 110, 42)
const RELIEF_TAUPE_MIDDLE := Color8(143, 135, 120, 30)
const RELIEF_TAUPE_INNER := Color8(154, 145, 130, 18)
const RELIEF_EDGE := Color8(76, 77, 74, 32)
const COAST_DARK := Color8(71, 84, 84, 78)
const COAST_GLOW := Color8(151, 162, 156, 26)
const COAST_CORE := Color8(65, 79, 80, 150)

const WATER_AREA_GATES := {
	LOD_STRATEGIC: {"water": 95.0, "land_inlay": 140.0},
	LOD_OPERATIONAL: {"water": 24.0, "land_inlay": 48.0},
	LOD_DETAIL: {"water": 6.0, "land_inlay": 14.0},
	LOD_TAB: {"water": 95.0, "land_inlay": 140.0},
}

static var _data_cache: Dictionary = {}
static var _data_error := ""
static var _packet_cache: Dictionary = {}
static var _density_cache: Dictionary = {}
static var _operational_buildings_cache: Dictionary = {}
static var _operational_roads_cache: Array = []
static var _operational_landmarks_cache: Dictionary = {}

var _camera: Camera2D = null
var _world_rect := Rect2()
var _forced_lod := -1
var _active_lod := -1
var _lod_roots: Dictionary = {}
var _operational_mass_packets: Array[CanvasItem] = []
var _operational_roof_packets: Array[CanvasItem] = []
var _operational_depth_packets: Array[CanvasItem] = []


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


func setup(camera: Camera2D, world_rect: Rect2, forced_lod: int = -1) -> bool:
	_camera = camera
	_world_rect = world_rect
	_forced_lod = forced_lod
	if not preview_available():
		push_warning("MapVectorPreviewRenderer unavailable: %s" % _data_error)
		return false
	z_index = 0
	update_lod()
	return _active_lod >= 0


func update_lod(_delta: float = 0.0) -> void:
	# v7 止损态：主地图固定 Operational。整图 LOD alpha 淡入会重复合成半透明图层，
	# 导致滚轮时整体明暗漂移；新架构完成前不再按 zoom 切换整张底图。
	var next_lod := _forced_lod if _forced_lod >= 0 else LOD_OPERATIONAL
	if next_lod == _active_lod:
		_update_operational_feature_opacity()
		return
	if not _lod_roots.has(next_lod):
		_build_lod_root(next_lod)
	if not _lod_roots.has(next_lod):
		return
	for key in _lod_roots:
		var root := _lod_roots[key] as Node2D
		root.visible = int(key) == next_lod
		root.modulate = Color.WHITE
		root.z_index = 0
	_active_lod = next_lod
	_update_operational_feature_opacity()


func _update_operational_feature_opacity() -> void:
	if _camera == null:
		return
	# V40 只重排已有静态 packet：大质量块先退、浅屋顶再进、低浮雕边缘最后进。
	# 海陆、海岸和道路不参与整根 cross-fade，因此滚轮不会让全图忽明忽暗。
	var zoom_value := _camera.zoom.x
	var mass_t := smoothstep(OP_MASS_FADE_START_ZOOM, OP_MASS_FADE_END_ZOOM, zoom_value)
	var mass_opacity := lerpf(1.0, OP_MASS_MIN_OPACITY, mass_t)
	var roof_opacity := OP_ROOF_MAX_OPACITY * smoothstep(
		OP_ROOF_FADE_START_ZOOM, OP_ROOF_FADE_END_ZOOM, zoom_value)
	var depth_opacity := OP_DEPTH_MAX_OPACITY * smoothstep(
		OP_DEPTH_FADE_START_ZOOM, OP_DEPTH_FADE_END_ZOOM, zoom_value)
	for packet in _operational_mass_packets:
		if is_instance_valid(packet):
			packet.modulate.a = mass_opacity
	for packet in _operational_roof_packets:
		if is_instance_valid(packet):
			packet.modulate.a = roof_opacity
	for packet in _operational_depth_packets:
		if is_instance_valid(packet):
			packet.modulate.a = depth_opacity


func current_lod() -> int:
	return _active_lod


static func preview_available() -> bool:
	return not _load_data().is_empty()


static func validate_preview_data() -> Dictionary:
	var data := _load_data()
	if data.is_empty():
		return {"ok": false, "error": _data_error}
	var expected_min := {
		"water_rings": 100,
		"roads_tertiary": 10000,
		"roads_residential": 1900,
		"roads_service": 500,
		"runways": 8,
		"taxiways": 700,
		"aprons": 10,
		"port_lines": 30,
		"industrial": 20,
	}
	for key in expected_min:
		var values: Array = data.get(key, [])
		if values.size() < int(expected_min[key]):
			return {"ok": false, "error": "%s count %d" % [key, values.size()]}
	var operational_roads := _load_operational_roads()
	if operational_roads.size() < 9000:
		return {"ok": false, "error": "operational road skeleton count %d" % operational_roads.size()}
	return {"ok": true, "counts": _data_counts(data)}


static func prewarm_lod(lod: int, world_rect: Rect2) -> Dictionary:
	if not preview_available():
		return {"ok": false, "error": _data_error}
	var cache_key := _packet_cache_key(lod, world_rect)
	var cache_hit := _packet_cache.has(cache_key)
	var t0 := Time.get_ticks_msec()
	if not cache_hit:
		MapGeography.ensure_ready()
		var definitions := _build_packet_definitions(lod, world_rect)
		if definitions.is_empty():
			return {"ok": false, "error": "LOD%d produced no packets" % lod}
		_packet_cache[cache_key] = definitions
	var packets: Array = _packet_cache[cache_key]
	var triangles := 0
	for definition_any in packets:
		var definition: Dictionary = definition_any
		triangles += (definition.get("indices", PackedInt32Array()) as PackedInt32Array).size() / 3
	return {
		"ok": true,
		"cache_hit": cache_hit,
		"draw_calls": packets.size(),
		"triangles": triangles,
		"build_ms": Time.get_ticks_msec() - t0,
	}


static func inspect_lod(lod: int, world_rect: Rect2) -> Dictionary:
	if not preview_available():
		return {"ok": false, "error": _data_error}
	MapGeography.ensure_ready()
	var t0 := Time.get_ticks_msec()
	var prewarm := prewarm_lod(lod, world_rect)
	if not bool(prewarm.get("ok", false)):
		return prewarm
	var packets: Array = _packet_cache[_packet_cache_key(lod, world_rect)]
	var vertices := 0
	var triangles := 0
	var layer_triangles := {}
	var terrain_context_water_hits := 0
	var terrain_context_water_hits_by_source := {}
	var failed_water_rings: Array = []
	var visual_masks := _visual_masks_for_lod(lod)
	for definition_any in packets:
		var definition: Dictionary = definition_any
		vertices += (definition.get("points", PackedVector2Array()) as PackedVector2Array).size()
		var packet_triangles := (definition.get("indices", PackedInt32Array()) as PackedInt32Array).size() / 3
		triangles += packet_triangles
		var layer_name := String(definition.get("name", "?"))
		layer_triangles[layer_name] = packet_triangles
		if layer_name == "terrain_context":
			var water_masks: Array = visual_masks.get("water", [])
			var land_inlay_masks: Array = visual_masks.get("land_inlay", [])
			var relief_end := int(definition.get("relief_index_end", 0))
			var districts_end := int(definition.get("district_index_end", relief_end))
			var final_end := (definition.get("indices", PackedInt32Array()) as PackedInt32Array).size()
			var relief_hits := _count_context_water_hits(
				definition, water_masks, land_inlay_masks, 0, relief_end)
			var district_hits := _count_context_water_hits(
				definition, water_masks, land_inlay_masks, relief_end, districts_end)
			var facility_hits := _count_context_water_hits(
				definition, water_masks, land_inlay_masks, districts_end, final_end)
			terrain_context_water_hits = relief_hits + district_hits + facility_hits
			terrain_context_water_hits_by_source = {
				"relief": relief_hits,
				"district": district_hits,
				"facility": facility_hits,
			}
	var gates: Dictionary = WATER_AREA_GATES.get(lod, WATER_AREA_GATES[LOD_OPERATIONAL])
	for entry_any in _load_data().get("water_rings", []):
		var entry: Dictionary = entry_any
		if String(entry.get("role", "water")) != "water" \
				or float(entry.get("area_px2", 0.0)) < float(gates.get("water", INF)):
			continue
		var water_poly := _unpack_flat(entry.get("points", []), true)
		if water_poly.size() >= 3 and (_triangulate_polygon(water_poly).indices as PackedInt32Array).is_empty():
			failed_water_rings.append({
				"area_px2": float(entry.get("area_px2", 0.0)),
				"points": water_poly.size(),
			})
	return {
		"ok": not packets.is_empty(),
		"draw_calls": packets.size(),
		"vertices": vertices,
		"triangles": triangles,
		"layer_triangles": layer_triangles,
		"terrain_context_water_hits": terrain_context_water_hits,
		"terrain_context_water_hits_by_source": terrain_context_water_hits_by_source,
		"failed_water_rings": failed_water_rings,
		"build_ms": Time.get_ticks_msec() - t0,
	}


static func smoke_submit_triangle_array() -> bool:
	# headless 也可验证 Godot 4.7 RenderingServer 调用签名；RID 当场释放。
	var item := RenderingServer.canvas_item_create()
	if not item.is_valid():
		return false
	RenderingServer.canvas_item_add_triangle_array(
		item,
		PackedInt32Array([0, 1, 2]),
		PackedVector2Array([Vector2.ZERO, Vector2.RIGHT, Vector2.DOWN]),
		PackedColorArray([Color.WHITE, Color.WHITE, Color.WHITE]))
	RenderingServer.free_rid(item)
	return true


func _build_lod_root(lod: int) -> void:
	var t0 := Time.get_ticks_msec()
	var prewarm := prewarm_lod(lod, _world_rect)
	if not bool(prewarm.get("ok", false)):
		return
	var definitions: Array = _packet_cache[_packet_cache_key(lod, _world_rect)]
	if definitions.is_empty():
		return
	var root := Node2D.new()
	root.name = "VectorMapLOD%d" % lod
	root.visible = false
	add_child(root)
	var vertices := 0
	var triangles := 0
	for i in range(definitions.size()):
		var definition: Dictionary = definitions[i]
		var layer_name := String(definition.get("name", "layer"))
		var packet := StaticPacket.new()
		packet.name = "Packet_%02d_%s" % [i, layer_name]
		packet.configure(definition)
		root.add_child(packet)
		if lod == LOD_OPERATIONAL:
			if layer_name == "urban":
				_operational_mass_packets.append(packet)
			elif layer_name == "industrial":
				_operational_roof_packets.append(packet)
			elif layer_name in ["building_wall", "building_casing"]:
				_operational_depth_packets.append(packet)
		vertices += packet.packet_points.size()
		triangles += packet.packet_indices.size() / 3
	_lod_roots[lod] = root
	print("[MapVectorPreviewRenderer] LOD%d ready: packets=%d vertices=%d triangles=%d (%dms)" % [
		lod, definitions.size(), vertices, triangles, Time.get_ticks_msec() - t0,
	])


static func _packet_cache_key(lod: int, world_rect: Rect2) -> String:
	return "%d|%.2f|%.2f|%.2f|%.2f" % [
		lod, world_rect.position.x, world_rect.position.y, world_rect.size.x, world_rect.size.y,
	]


static func _load_data() -> Dictionary:
	if not _data_cache.is_empty():
		return _data_cache
	if _data_error != "":
		return {}
	var file := FileAccess.open(DATA_PATH, FileAccess.READ)
	if file == null:
		_data_error = "cannot open %s" % DATA_PATH
		return {}
	var parsed = JSON.parse_string(file.get_as_text())
	file.close()
	if parsed == null or typeof(parsed) != TYPE_DICTIONARY:
		_data_error = "JSON parse failed"
		return {}
	if int(parsed.get("schema_version", 0)) != 1:
		_data_error = "unsupported schema_version"
		return {}
	_data_cache = parsed
	return _data_cache


static func _data_counts(data: Dictionary) -> Dictionary:
	var out := {}
	for key in data:
		if data[key] is Array:
			out[key] = (data[key] as Array).size()
	return out


static func _build_packet_definitions(lod: int, world_rect: Rect2) -> Array:
	var data := _load_data()
	if data.is_empty():
		return []
	var layers := {}
	# 与 PNG 一样在战区框外落回场景暗底；海色只延伸到三层暗角的最外圈。
	var sea_color := _sea_color(lod)
	var land_color := _land_color(lod)
	_add_rect(layers, "sea", world_rect.grow(2000.0), sea_color)
	var trace: Array = data.get("trace_rect", [])
	if trace.size() != 4:
		return []
	var trace_rect := Rect2(
		Vector2(float(trace[0]), float(trace[1])),
		Vector2(float(trace[2]) - float(trace[0]), float(trace[3]) - float(trace[1])))
	_add_rect(layers, "land", trace_rect, land_color)
	_add_operational_density(layers, lod)

	var gates: Dictionary = WATER_AREA_GATES.get(lod, WATER_AREA_GATES[LOD_OPERATIONAL])
	var coast_lines: Array = []
	var water_masks: Array = []
	var land_inlay_masks: Array = []
	for entry_any in data.get("water_rings", []):
		var entry: Dictionary = entry_any
		var role := String(entry.get("role", "water"))
		if float(entry.get("area_px2", 0.0)) < float(gates.get(role, INF)):
			continue
		var poly := _unpack_flat(entry.get("points", []), true)
		if poly.size() < 3:
			continue
		if lod != LOD_DETAIL:
			# 早期 water ring 来自像素轮廓；单轮柔化在 0.20 倍中景仍会露出阶梯。
			# 两轮 Chaikin 保持闭合拓扑，同时把港湾转角变成与批准金样一致的软边。
			var softened := _soften_closed_polygon(poly, 2)
			if not (_triangulate_polygon(softened).indices as PackedInt32Array).is_empty():
				poly = softened
		_add_polygon(layers, "water" if role == "water" else "land_inlay", poly,
			sea_color if role == "water" else land_color)
		var mask_entry := _make_mask_entry(poly)
		if role == "water":
			water_masks.append(mask_entry)
		else:
			land_inlay_masks.append(mask_entry)
		var closed := poly.duplicate()
		closed.append(poly[0])
		coast_lines.append(closed)

	# land inlay 是否需要恢复只与视觉水环有关，整批预计算，避免每块重复遍历水体。
	for i in range(land_inlay_masks.size()):
		var inlay_entry: Dictionary = land_inlay_masks[i]
		inlay_entry["restore"] = _point_in_mask_entries(
			_polygon_center(inlay_entry.poly), water_masks)
		land_inlay_masks[i] = inlay_entry

	if lod == LOD_OPERATIONAL or lod == LOD_DETAIL:
		_add_scene_context_blocks(layers, data, water_masks, land_inlay_masks)
	_add_polygons(layers, "urban", MapGeography.URBAN_DISTRICTS, _urban_color(lod))
	if lod == LOD_OPERATIONAL or lod == LOD_DETAIL:
		# 顶点色允许 fill 与 edge 共用同一 packet，保持 draw-call 上限不变。
		_add_polygon_outlines(layers, "urban", MapGeography.URBAN_DISTRICTS,
			_width_for_lod(lod, 0.0, 0.55, 0.45, 0.0), URBAN_EDGE)
	if lod != LOD_STRATEGIC and lod != LOD_TAB:
		_add_operational_buildings(layers, lod)
	else:
		_add_operational_buildings(layers, lod)
	if lod == LOD_OPERATIONAL:
		# 真实高层是常驻地标，不跟普通 large 屋顶/低浮雕的 zoom opacity 一起消失。
		_add_operational_landmarks(layers)
	_add_polygons(layers, "airport", MapGeography.OSM_AERODROMES, AIRPORT)
	_add_polygon_outlines(layers, "airport_edge", MapGeography.OSM_AERODROMES,
		_width_for_lod(lod, 1.0, 1.0, 1.0, 1.0), AIRPORT_EDGE)

	var road_specs := _road_specs(lod, data)
	for spec_any in road_specs:
		var spec: Dictionary = spec_any
		if bool(spec.get("major", true)):
			_add_lines(layers, "road_shadow", spec.lines,
				float(spec.width) + _width_for_lod(lod, 1.2, 1.2, 1.2, 1.0), ROAD_SHADOW,
				Vector2(_width_for_lod(lod, 0.65, 0.65, 0.65, 0.7), _width_for_lod(lod, 0.9, 0.9, 0.9, 0.9)))
		if bool(spec.get("major", true)) or bool(spec.get("casing", false)):
			_add_lines(layers, "road_casing", spec.lines,
				float(spec.width) + _width_for_lod(lod, 0.45, 0.45, 0.45, 0.8), ROAD_CASING)
		_add_lines(layers, "road_core", spec.lines, float(spec.core), spec.color)
		if String(spec.key) in ["motorway", "trunk"]:
			_add_lines(layers, "road_highlight", spec.lines,
				maxf(float(spec.core) * 0.28, _width_for_lod(lod, 1.0, 1.0, 1.0, 0.8)), ROAD_HIGHLIGHT)

	var runways := _unpack_flat_lines(data.get("runways", []))
	var runway_width := _width_for_lod(lod, 1.8, 4.5, 7.5, 2.1)
	_add_lines(layers, "runway_casing", runways,
		runway_width + _width_for_lod(lod, 2.0, 2.0, 2.0, 1.2), RUNWAY_CASING)
	_add_lines(layers, "runway_core", runways, runway_width, RUNWAY_CORE)
	if lod != LOD_STRATEGIC and lod != LOD_TAB:
		_add_lines(layers, "taxiways", _unpack_flat_lines(data.get("taxiways", [])),
			_width_for_lod(lod, 1.0, 1.0, 1.4, 1.0), TAXIWAY)
		_add_lines(layers, "port", _unpack_flat_lines(data.get("port_lines", [])),
			_width_for_lod(lod, 1.0, 1.0, 1.2, 1.0), PORT)

	# 三重海岸层与陆海拓扑同源，避免“蓝线脱离陆块漂在海上”。
	_add_lines(layers, "coast_glow", coast_lines,
		_width_for_lod(lod, 4.6, 3.5, 1.7, 3.5), COAST_GLOW)
	_add_lines(layers, "coast_dark", coast_lines,
		_width_for_lod(lod, 2.5, 2.0, 1.1, 2.0), COAST_DARK)
	_add_lines(layers, "coast_core", coast_lines,
		_width_for_lod(lod, 1.15, 1.0, 0.65, 1.1), COAST_CORE)
	# 旧 terrain wash 没有真实陆地 mask，柔化海岸后会从水边漏出规则亮带。
	# V12 由已陆地遮罩的 OSM density field 承担中远景纸面层次。
	_add_vignette(layers, world_rect)

	var order := [
		"sea", "land", "water", "land_inlay", "terrain_context", "urban", "building_wall", "building_casing", "industrial", "aprons",
		"airport", "airport_edge", "road_shadow", "road_casing", "road_core", "road_highlight",
		"runway_casing", "runway_core", "taxiways", "port", "landmark", "coast_glow", "coast_dark", "coast_core",
		"vignette_0", "vignette_1", "vignette_2",
	]
	var out: Array = []
	for name in order:
		if not layers.has(name):
			continue
		var packet: Dictionary = layers[name]
		if (packet.points as PackedVector2Array).is_empty():
			continue
		packet["name"] = name
		out.append(packet)
	return out


static func _add_operational_density(layers: Dictionary, lod: int) -> void:
	var source := _load_density_data()
	if source.is_empty():
		return
	var cols := int(source.get("cols", 0))
	var rows := int(source.get("rows", 0))
	var channels: PackedByteArray = source.get("channels", PackedByteArray())
	if cols < 2 or rows < 2 or channels.size() != cols * rows * 3:
		return
	var origin: Vector2 = source.get("origin", Vector2.ZERO)
	var step := float(source.get("step", 0.0))
	if step <= 0.0:
		return
	# 远景不画住宅细线，用连续城市 mass 承担信息密度；比 Operational 略强，
	# 防止全图缩放时陆地退成空白，同时不会制造规则格或黑色噪点。
	var alpha_scale := 0.60 if lod == LOD_STRATEGIC else 0.68 if lod == LOD_TAB \
		else 0.62 if lod == LOD_DETAIL else 0.76
	var points := PackedVector2Array()
	var colors := PackedColorArray()
	points.resize(cols * rows)
	colors.resize(cols * rows)
	for y in range(rows):
		for x in range(cols):
			var index := y * cols + x
			points[index] = origin + Vector2(x * step, y * step)
			var urban := float(channels[index * 3]) / 255.0
			var vegetation := float(channels[index * 3 + 1]) / 255.0
			var industrial := float(channels[index * 3 + 2]) / 255.0
			var urban_weight := urban * 0.23
			var vegetation_weight := vegetation * 0.115
			var industrial_weight := industrial * 0.15
			var total := urban_weight + vegetation_weight + industrial_weight
			if total <= 0.0001:
				# 透明顶点也必须保留暗色 RGB。透明白与相邻密度顶点插值时会在
				# 海岸 mask 边缘产生大块发亮条带（GL Compatibility 下尤其明显）。
				colors[index] = Color(DENSITY_URBAN.r, DENSITY_URBAN.g, DENSITY_URBAN.b, 0.0)
				continue
			var rgb := (Vector3(DENSITY_URBAN.r, DENSITY_URBAN.g, DENSITY_URBAN.b) * urban_weight
				+ Vector3(DENSITY_VEGETATION.r, DENSITY_VEGETATION.g, DENSITY_VEGETATION.b) * vegetation_weight
				+ Vector3(DENSITY_INDUSTRIAL.r, DENSITY_INDUSTRIAL.g, DENSITY_INDUSTRIAL.b) * industrial_weight) / total
			colors[index] = Color(rgb.x, rgb.y, rgb.z, minf(total, 0.34) * alpha_scale)
	var indices := PackedInt32Array()
	indices.resize((cols - 1) * (rows - 1) * 6)
	var write_index := 0
	for y in range(rows - 1):
		for x in range(cols - 1):
			var top_left := y * cols + x
			indices[write_index] = top_left
			indices[write_index + 1] = top_left + 1
			indices[write_index + 2] = top_left + cols + 1
			indices[write_index + 3] = top_left
			indices[write_index + 4] = top_left + cols + 1
			indices[write_index + 5] = top_left + cols
			write_index += 6
	# 与既有城区轮廓共用一个 packet；仍保持密度顶点先提交、精确城区随后覆盖。
	layers["urban"] = {"points": points, "indices": indices, "colors": colors}


## 纸模式低频场景层：只复用既有多边形，在一个静态 packet 内提交
## 贴地阴影、底面与内缩浅面。所有部分先按视觉水体做差集，再恢复岛屿/填海 inlay，
## 因而暖灰 landuse 不会越过陆地底盘漂到海上。
static func _add_scene_context_blocks(layers: Dictionary, data: Dictionary,
		water_masks: Array, land_inlay_masks: Array) -> void:
	_add_baked_relief(layers, data)
	var context_packet := _packet(layers, "terrain_context")
	# relief 已在离线烘焙时按同源柔化水环留出 90px 安全带；运行时不重复逐三角扫水体。
	context_packet["relief_index_end"] = (context_packet.indices as PackedInt32Array).size()
	var selected := 0
	for index in range(MapGeography.URBAN_DISTRICTS.size()):
		var poly: PackedVector2Array = MapGeography.URBAN_DISTRICTS[index]
		if _polygon_area_abs(poly) < CONTEXT_MIN_AREA_PX2:
			continue
		var center := _polygon_center(poly)
		var stable_hash := absi(int(round(center.x * 0.01)) * 31
			+ int(round(center.y * 0.01)) * 17 + index * 13)
		# 留出连续底色呼吸区，禁止把 717 个城市面全部填成拼花。
		if stable_hash % 3 == 0:
			continue
		var palette := _context_palette(center, stable_hash)
		_add_context_plate(layers, poly, palette.base, palette.inset,
			water_masks, land_inlay_masks)
		selected += 1
		if selected >= CONTEXT_MAX_BLOCKS:
			break
	_filter_context_range_to_visual_land(context_packet, water_masks, land_inlay_masks,
		int(context_packet.get("relief_index_end", 0)))
	context_packet["district_index_end"] = (context_packet.indices as PackedInt32Array).size()

	# 工业与停机坪使用同一贴地语法，不再直接把原始面盖在 water packet 之后。
	for flat_any in data.get("industrial", []):
		_add_context_plate(layers, _unpack_flat(flat_any, true), INDUSTRIAL,
			CONTEXT_TAUPE_INSET, water_masks, land_inlay_masks)
	for flat_any in data.get("aprons", []):
		_add_context_plate(layers, _unpack_flat(flat_any, true), APRON,
			CONTEXT_WARM_GRAY_INSET, water_masks, land_inlay_masks)
	_filter_context_range_to_visual_land(context_packet, water_masks, land_inlay_masks,
		int(context_packet.get("district_index_end", 0)))


## 离线烘焙的大形纸模台地已经按同源视觉水体留出安全带。运行时只三角化简单九边形，
## 不再对 2,795 点陆地并集做昂贵布尔运算，也不增加规则格、道路或普通小楼。
static func _add_baked_relief(layers: Dictionary, data: Dictionary) -> void:
	_add_baked_relief_group(layers, data, "green",
		RELIEF_GREEN_BASE, RELIEF_GREEN_MIDDLE, RELIEF_GREEN_INNER)
	_add_baked_relief_group(layers, data, "gray",
		RELIEF_GRAY_BASE, RELIEF_GRAY_MIDDLE, RELIEF_GRAY_INNER)
	_add_baked_relief_group(layers, data, "taupe",
		RELIEF_TAUPE_BASE, RELIEF_TAUPE_MIDDLE, RELIEF_TAUPE_INNER)


static func _add_baked_relief_group(layers: Dictionary, data: Dictionary, prefix: String,
		base_color: Color, middle_color: Color, inner_color: Color) -> void:
	var tiers := [
		["base", base_color],
		["middle", middle_color],
		["inner", inner_color],
	]
	for tier_any in tiers:
		var tier: Array = tier_any
		var polygons: Array = []
		for flat_any in data.get("relief_%s_%s" % [prefix, String(tier[0])], []):
			var poly := _unpack_flat(flat_any, true)
			if poly.size() < 3:
				continue
			polygons.append(poly)
			_add_polygon(layers, "terrain_context", poly, tier[1] as Color)
		if String(tier[0]) == "base":
			_add_polygon_outlines(layers, "terrain_context", polygons, 2.2, RELIEF_EDGE)


static func _add_context_plate(layers: Dictionary, poly: PackedVector2Array,
		base_color: Color, inset_color: Color, water_masks: Array,
		land_inlay_masks: Array) -> void:
	if poly.size() < 3:
		return
	var shadow := PackedVector2Array()
	shadow.resize(poly.size())
	for i in range(poly.size()):
		shadow[i] = poly[i] + CONTEXT_SHADOW_OFFSET
	_add_context_parts(layers, _clip_polygon_to_visual_land(
		shadow, water_masks, land_inlay_masks), CONTEXT_SHADOW)
	var base_parts := _clip_polygon_to_visual_land(poly, water_masks, land_inlay_masks)
	_add_context_parts(layers, base_parts, base_color)
	# 内缩面基于已裁切的底面生成，天然留在视觉陆地内，不再重复执行水体差集。
	for part_any in base_parts:
		var part: PackedVector2Array = part_any
		for inset in Geometry2D.offset_polygon(part, -CONTEXT_INSET_PX, Geometry2D.JOIN_ROUND):
			if inset.size() >= 3:
				_add_polygon(layers, "terrain_context", inset, inset_color)


static func _add_context_parts(layers: Dictionary, parts: Array, color: Color) -> void:
	for part_any in parts:
		var part: PackedVector2Array = part_any
		if part.size() >= 3:
			_add_polygon(layers, "terrain_context", part, color)


static func _clip_polygon_to_visual_land(subject: PackedVector2Array,
		water_masks: Array, land_inlay_masks: Array) -> Array:
	if subject.size() < 3:
		return []
	var subject_rect := _polygon_rect(subject)
	var parts: Array = [subject]
	for entry_any in water_masks:
		var entry: Dictionary = entry_any
		var water_rect: Rect2 = entry.rect
		if not subject_rect.intersects(water_rect):
			continue
		var water_poly: PackedVector2Array = entry.poly
		var clipped_parts: Array = []
		for part_any in parts:
			var part: PackedVector2Array = part_any
			if not _polygon_rect(part).intersects(water_rect):
				clipped_parts.append(part)
				continue
			for clipped in Geometry2D.clip_polygons(part, water_poly):
				if clipped.size() >= 3:
					clipped_parts.append(clipped)
		parts = clipped_parts
		if parts.is_empty():
			break

	# land_inlay 是 water 环内重新盖回的陆地；只恢复确实位于水环内的部分。
	for entry_any in land_inlay_masks:
		var entry: Dictionary = entry_any
		var inlay_rect: Rect2 = entry.rect
		if not subject_rect.intersects(inlay_rect):
			continue
		var inlay: PackedVector2Array = entry.poly
		if not bool(entry.get("restore", false)):
			continue
		for restored in Geometry2D.intersect_polygons(subject, inlay):
			if restored.size() >= 3:
				parts.append(restored)
	return parts


static func _context_palette(point: Vector2, stable_hash: int) -> Dictionary:
	var sample := _density_sample(point)
	if sample.z >= sample.x * 0.62 and sample.z >= sample.y * 0.82:
		return {"base": CONTEXT_TAUPE, "inset": CONTEXT_TAUPE_INSET}
	if sample.y >= sample.x * 0.72:
		return {"base": CONTEXT_GREEN, "inset": CONTEXT_GREEN_INSET}
	if stable_hash % 5 == 0:
		return {"base": CONTEXT_WARM_GRAY, "inset": CONTEXT_WARM_GRAY_INSET}
	return {"base": CONTEXT_GRAY, "inset": CONTEXT_GRAY_INSET}


static func _density_sample(point: Vector2) -> Vector3:
	var source := _load_density_data()
	if source.is_empty():
		return Vector3.ZERO
	var cols := int(source.get("cols", 0))
	var rows := int(source.get("rows", 0))
	var step := float(source.get("step", 0.0))
	var channels: PackedByteArray = source.get("channels", PackedByteArray())
	if cols <= 0 or rows <= 0 or step <= 0.0 or channels.size() != cols * rows * 3:
		return Vector3.ZERO
	var origin: Vector2 = source.get("origin", Vector2.ZERO)
	var x := clampi(int(round((point.x - origin.x) / step)), 0, cols - 1)
	var y := clampi(int(round((point.y - origin.y) / step)), 0, rows - 1)
	var index := (y * cols + x) * 3
	return Vector3(float(channels[index]), float(channels[index + 1]),
		float(channels[index + 2])) / 255.0


static func _polygon_area_abs(poly: PackedVector2Array) -> float:
	var twice_area := 0.0
	for i in range(poly.size()):
		var a := poly[i]
		var b := poly[(i + 1) % poly.size()]
		twice_area += a.x * b.y - b.x * a.y
	return absf(twice_area) * 0.5


static func _polygon_center(poly: PackedVector2Array) -> Vector2:
	if poly.is_empty():
		return Vector2.ZERO
	var total := Vector2.ZERO
	for point in poly:
		total += point
	return total / float(poly.size())


static func _polygon_rect(poly: PackedVector2Array) -> Rect2:
	if poly.is_empty():
		return Rect2()
	var min_point := poly[0]
	var max_point := poly[0]
	for point in poly:
		min_point = min_point.min(point)
		max_point = max_point.max(point)
	return Rect2(min_point, max_point - min_point)


static func _point_in_mask_entries(point: Vector2, entries: Array) -> bool:
	for entry_any in entries:
		var entry: Dictionary = entry_any
		var bounds: Rect2 = entry.rect
		if bounds.has_point(point) and _point_in_mask_entry(point, entry):
			return true
	return false


static func _make_mask_entry(poly: PackedVector2Array) -> Dictionary:
	var scan_rows := {}
	for index in range(poly.size()):
		var a := poly[index]
		var b := poly[(index + 1) % poly.size()]
		if is_equal_approx(a.y, b.y):
			continue
		var first_row := floori(minf(a.y, b.y) / MASK_INDEX_CELL_PX)
		var last_row := floori((maxf(a.y, b.y) - 0.0001) / MASK_INDEX_CELL_PX)
		var edge := Vector4(a.x, a.y, b.x, b.y)
		for row in range(first_row, last_row + 1):
			if not scan_rows.has(row):
				scan_rows[row] = []
			(scan_rows[row] as Array).append(edge)
	return {"poly": poly, "rect": _polygon_rect(poly), "scan_rows": scan_rows}


static func _point_in_mask_entry(point: Vector2, entry: Dictionary) -> bool:
	var scan_rows: Dictionary = entry.get("scan_rows", {})
	var row := floori(point.y / MASK_INDEX_CELL_PX)
	var inside := false
	for edge_any in scan_rows.get(row, []):
		var edge: Vector4 = edge_any
		if (edge.y > point.y) == (edge.w > point.y):
			continue
		var crossing_x := edge.x + (point.y - edge.y) * (edge.z - edge.x) / (edge.w - edge.y)
		if point.x < crossing_x:
			inside = not inside
	return inside


static func _build_mask_index(entries: Array) -> Dictionary:
	var index := {}
	for entry_any in entries:
		var entry: Dictionary = entry_any
		var bounds: Rect2 = entry.rect
		var min_cell := Vector2i(
			floori(bounds.position.x / MASK_INDEX_CELL_PX),
			floori(bounds.position.y / MASK_INDEX_CELL_PX))
		var max_cell := Vector2i(
			floori(bounds.end.x / MASK_INDEX_CELL_PX),
			floori(bounds.end.y / MASK_INDEX_CELL_PX))
		for cell_y in range(min_cell.y, max_cell.y + 1):
			for cell_x in range(min_cell.x, max_cell.x + 1):
				var key := Vector2i(cell_x, cell_y)
				if not index.has(key):
					index[key] = []
				(index[key] as Array).append(entry)
	return index


static func _point_in_mask_index(point: Vector2, index: Dictionary) -> bool:
	var key := Vector2i(
		floori(point.x / MASK_INDEX_CELL_PX),
		floori(point.y / MASK_INDEX_CELL_PX))
	for entry_any in index.get(key, []):
		var entry: Dictionary = entry_any
		var bounds: Rect2 = entry.rect
		if bounds.has_point(point) and _point_in_mask_entry(point, entry):
			return true
	return false


static func _count_context_water_hits(packet: Dictionary, water_masks: Array,
		land_inlay_masks: Array, start_index: int = 0, end_index: int = -1) -> int:
	var points: PackedVector2Array = packet.get("points", PackedVector2Array())
	var indices: PackedInt32Array = packet.get("indices", PackedInt32Array())
	var water_index := _build_mask_index(water_masks)
	var land_inlay_index := _build_mask_index(land_inlay_masks)
	var hits := 0
	var safe_start := maxi(0, start_index - posmod(start_index, 3))
	var safe_end := indices.size() if end_index < 0 else mini(end_index, indices.size())
	for offset in range(safe_start, safe_end, 3):
		if offset + 2 >= safe_end:
			break
		var center := (points[indices[offset]] + points[indices[offset + 1]]
			+ points[indices[offset + 2]]) / 3.0
		if _point_in_mask_index(center, water_index) \
				and not _point_in_mask_index(center, land_inlay_index):
			hits += 1
	return hits


static func _filter_context_range_to_visual_land(packet: Dictionary, water_masks: Array,
		land_inlay_masks: Array, start_index: int) -> void:
	var points: PackedVector2Array = packet.get("points", PackedVector2Array())
	var indices: PackedInt32Array = packet.get("indices", PackedInt32Array())
	var water_index := _build_mask_index(water_masks)
	var land_inlay_index := _build_mask_index(land_inlay_masks)
	var safe_start := maxi(0, start_index - posmod(start_index, 3))
	var filtered := PackedInt32Array()
	filtered.resize(safe_start)
	for index in range(safe_start):
		filtered[index] = indices[index]
	for offset in range(safe_start, indices.size(), 3):
		if offset + 2 >= indices.size():
			break
		var center := (points[indices[offset]] + points[indices[offset + 1]]
			+ points[indices[offset + 2]]) / 3.0
		if _point_in_mask_index(center, water_index) \
				and not _point_in_mask_index(center, land_inlay_index):
			continue
		filtered.append(indices[offset])
		filtered.append(indices[offset + 1])
		filtered.append(indices[offset + 2])
	packet["indices"] = filtered


static func _visual_masks_for_lod(lod: int) -> Dictionary:
	var water_masks: Array = []
	var land_inlay_masks: Array = []
	var gates: Dictionary = WATER_AREA_GATES.get(lod, WATER_AREA_GATES[LOD_OPERATIONAL])
	for entry_any in _load_data().get("water_rings", []):
		var entry: Dictionary = entry_any
		var role := String(entry.get("role", "water"))
		if float(entry.get("area_px2", 0.0)) < float(gates.get(role, INF)):
			continue
		var poly := _unpack_flat(entry.get("points", []), true)
		if poly.size() < 3:
			continue
		if lod != LOD_DETAIL:
			var softened := _soften_closed_polygon(poly, 2)
			if not (_triangulate_polygon(softened).indices as PackedInt32Array).is_empty():
				poly = softened
		var mask_entry := _make_mask_entry(poly)
		if role == "water":
			water_masks.append(mask_entry)
		else:
			land_inlay_masks.append(mask_entry)
	return {"water": water_masks, "land_inlay": land_inlay_masks}


static func _load_density_data() -> Dictionary:
	if not _density_cache.is_empty():
		return _density_cache
	var compressed := FileAccess.get_file_as_bytes(DENSITY_PATH)
	if compressed.is_empty():
		return {}
	var bytes := compressed.decompress_dynamic(DENSITY_MAX_UNCOMPRESSED_BYTES, FileAccess.COMPRESSION_GZIP)
	if bytes.size() < 24 or bytes.slice(0, 4).get_string_from_ascii() != "AGOD":
		return {}
	var version := bytes.decode_u16(4)
	if version != 1:
		return {}
	var origin := Vector2(bytes.decode_float(8), bytes.decode_float(12))
	var step := bytes.decode_float(16)
	var cols := bytes.decode_u16(20)
	var rows := bytes.decode_u16(22)
	var expected_size := 24 + cols * rows * 3
	if cols < 2 or rows < 2 or bytes.size() != expected_size:
		return {}
	_density_cache = {
		"origin": origin,
		"step": step,
		"cols": cols,
		"rows": rows,
		"channels": bytes.slice(24),
	}
	return _density_cache


static func _add_operational_buildings(layers: Dictionary, lod: int) -> void:
	var source := _load_operational_buildings()
	var points: PackedVector2Array = source.get("points", PackedVector2Array())
	if points.is_empty():
		return
	var large_count := int(source.get("large_count", points.size()))
	var medium_count := int(source.get("medium_count", 0))
	var point_limit := points.size()
	if lod == LOD_STRATEGIC or lod == LOD_TAB:
		# 51k 个所谓 large 体块在 Tab 只会退化为盐点；远景由 density mass 表达城市。
		point_limit = 0
	if lod == LOD_OPERATIONAL:
		# Operational 只保留大型建筑轮廓。中小建筑由城市质量块概括，近景交给
		# AGDT 瓦片，避免在稳定根层与局部细节层重复提交约 70 万三角。
		point_limit = large_count
		_add_operational_building_walls(layers, points, large_count)
		_add_operational_building_casings(layers, points, large_count)
	var alpha_scale := 0.82 if lod == LOD_DETAIL else 1.0
	var packet := _packet(layers, "industrial")
	var packet_points: PackedVector2Array = packet.points
	var packet_indices: PackedInt32Array = packet.indices
	var packet_colors: PackedColorArray = packet.colors
	var base := packet_points.size()
	for index in range(point_limit):
		packet_points.append(points[index])
	packet_colors.resize(packet_points.size())
	for local_index in range(point_limit):
		var packet_index := base + local_index
		packet_indices.append(packet_index)
		var color := OP_BUILDING_LARGE
		if local_index >= large_count + medium_count:
			color = OP_BUILDING_SMALL
		elif local_index >= large_count:
			color = OP_BUILDING_MEDIUM
		color.a *= alpha_scale
		packet_colors[packet_index] = color


static func _add_operational_building_casings(layers: Dictionary,
		points: PackedVector2Array, point_limit: int) -> void:
	var packet := _packet(layers, "building_casing")
	var packet_points: PackedVector2Array = packet.points
	var packet_indices: PackedInt32Array = packet.indices
	var packet_colors: PackedColorArray = packet.colors
	# AGOB 每个方向体块固定为 c0,c1,c2,c0,c2,c3 六顶点；只给中大型加一次静态外缘。
	for offset in range(0, mini(point_limit, points.size()), 6):
		if offset + 5 >= points.size():
			break
		var corners := PackedVector2Array([
			points[offset], points[offset + 1], points[offset + 2], points[offset + 5],
		])
		var center := (corners[0] + corners[1] + corners[2] + corners[3]) * 0.25
		for corner_index in range(4):
			var radial := corners[corner_index] - center
			if radial.length_squared() > 0.0001:
				corners[corner_index] += radial.normalized() * OP_BUILDING_CASING_EXPAND_PX
		for corner_index in [0, 1, 2, 0, 2, 3]:
			packet_points.append(corners[corner_index])
			packet_indices.append(packet_points.size() - 1)
			packet_colors.append(OP_BUILDING_CASING)


static func _add_operational_building_walls(layers: Dictionary,
		points: PackedVector2Array, point_limit: int) -> void:
	var packet := _packet(layers, "building_wall")
	var packet_points: PackedVector2Array = packet.points
	var packet_indices: PackedInt32Array = packet.indices
	var packet_colors: PackedColorArray = packet.colors
	# AGOB 已是每楼六顶点三角形；整体东南偏移后先画一次，原位 casing +
	# 浅屋顶随后覆盖，仅留下低成本的侧墙轮廓。全图仍是一个静态 packet。
	for index in range(mini(point_limit, points.size())):
		packet_points.append(points[index] + OP_BUILDING_WALL_OFFSET)
		packet_indices.append(packet_points.size() - 1)
		packet_colors.append(OP_BUILDING_WALL)


static func _load_operational_buildings() -> Dictionary:
	if not _operational_buildings_cache.is_empty():
		return _operational_buildings_cache
	var compressed := FileAccess.get_file_as_bytes(OPERATIONAL_BUILDINGS_PATH)
	if compressed.is_empty():
		return {}
	var bytes := compressed.decompress_dynamic(
		OPERATIONAL_BUILDINGS_MAX_UNCOMPRESSED_BYTES, FileAccess.COMPRESSION_GZIP)
	if bytes.size() < 24 or bytes.slice(0, 4).get_string_from_ascii() != "AGOB":
		return {}
	var version := bytes.decode_u16(4)
	if version != 1 and version != 2:
		return {}
	var origin := Vector2(bytes.decode_float(8), bytes.decode_float(12))
	var quantization := bytes.decode_float(16)
	var large_count := int(bytes.decode_u32(20))
	var medium_count := int(bytes.decode_u32(24)) if version == 2 else 0
	var small_count := int(bytes.decode_u32(28)) if version == 2 else 0
	var header_size := 32 if version == 2 else 24
	var point_count := large_count + medium_count + small_count
	if quantization <= 0.0 or bytes.size() != header_size + point_count * 8:
		return {}
	var points := PackedVector2Array()
	points.resize(point_count)
	for index in range(point_count):
		var offset := header_size + index * 8
		var x := bytes.decode_u32(offset)
		var y := bytes.decode_u32(offset + 4)
		var sx := x - 4294967296 if x > 2147483647 else x
		var sy := y - 4294967296 if y > 2147483647 else y
		points[index] = origin + Vector2(float(sx), float(sy)) / quantization
	_operational_buildings_cache = {
		"points": points,
		"large_count": large_count,
		"medium_count": medium_count,
		"small_count": small_count,
	}
	return _operational_buildings_cache


static func _add_operational_landmarks(layers: Dictionary) -> void:
	var source := _load_operational_landmarks()
	var points: PackedVector2Array = source.get("points", PackedVector2Array())
	var colors: PackedColorArray = source.get("colors", PackedColorArray())
	if points.is_empty() or colors.size() != points.size():
		return
	var packet := _packet(layers, "landmark")
	var packet_points: PackedVector2Array = packet.points
	var packet_indices: PackedInt32Array = packet.indices
	var packet_colors: PackedColorArray = packet.colors
	var base := packet_points.size()
	packet_points.append_array(points)
	packet_colors.append_array(colors)
	for index in range(points.size()):
		packet_indices.append(base + index)


static func _load_operational_landmarks() -> Dictionary:
	if not _operational_landmarks_cache.is_empty():
		return _operational_landmarks_cache
	var compressed := FileAccess.get_file_as_bytes(OPERATIONAL_LANDMARKS_PATH)
	if compressed.is_empty():
		return {}
	var bytes := compressed.decompress_dynamic(
		OPERATIONAL_LANDMARKS_MAX_UNCOMPRESSED_BYTES, FileAccess.COMPRESSION_GZIP)
	if bytes.size() < 24 or bytes.slice(0, 4).get_string_from_ascii() != "AGLW":
		return {}
	if bytes.decode_u16(4) != 1:
		return {}
	var origin := Vector2(bytes.decode_float(8), bytes.decode_float(12))
	var quantization := bytes.decode_float(16)
	var point_count := int(bytes.decode_u32(20))
	if quantization <= 0.0 or point_count <= 0 or point_count % 3 != 0 \
			or bytes.size() != 24 + point_count * 12:
		return {}
	var points := PackedVector2Array()
	var colors := PackedColorArray()
	points.resize(point_count)
	colors.resize(point_count)
	for index in range(point_count):
		var offset := 24 + index * 12
		var x := bytes.decode_u32(offset)
		var y := bytes.decode_u32(offset + 4)
		var sx := x - 4294967296 if x > 2147483647 else x
		var sy := y - 4294967296 if y > 2147483647 else y
		points[index] = origin + Vector2(float(sx), float(sy)) / quantization
		colors[index] = Color8(
			bytes[offset + 8], bytes[offset + 9], bytes[offset + 10], bytes[offset + 11])
	_operational_landmarks_cache = {
		"points": points,
		"colors": colors,
		"triangles": point_count / 3,
	}
	return _operational_landmarks_cache


static func _load_operational_roads() -> Array:
	if not _operational_roads_cache.is_empty():
		return _operational_roads_cache
	var compressed := FileAccess.get_file_as_bytes(OPERATIONAL_ROADS_PATH)
	if compressed.is_empty():
		return []
	var bytes := compressed.decompress_dynamic(
		OPERATIONAL_ROADS_MAX_UNCOMPRESSED_BYTES, FileAccess.COMPRESSION_GZIP)
	if bytes.size() < 24 or bytes.slice(0, 4).get_string_from_ascii() != "AGOR":
		return []
	if bytes.decode_u16(4) != 1:
		return []
	var origin := Vector2(bytes.decode_float(8), bytes.decode_float(12))
	var quantization := bytes.decode_float(16)
	var line_count := bytes.decode_u32(20)
	if quantization <= 0.0 or line_count > 20000:
		return []
	var offset := 24
	var decoded: Array = []
	for _line_index in range(line_count):
		if offset + 2 > bytes.size():
			return []
		var point_count := bytes.decode_u16(offset)
		offset += 2
		if point_count < 2 or offset + point_count * 8 > bytes.size():
			return []
		var line := PackedVector2Array()
		line.resize(point_count)
		for point_index in range(point_count):
			var point_offset := offset + point_index * 8
			var x := bytes.decode_u32(point_offset)
			var y := bytes.decode_u32(point_offset + 4)
			var sx := x - 4294967296 if x > 2147483647 else x
			var sy := y - 4294967296 if y > 2147483647 else y
			line[point_index] = origin + Vector2(float(sx), float(sy)) / quantization
		offset += point_count * 8
		decoded.append(line)
	if offset != bytes.size():
		return []
	_operational_roads_cache = decoded
	return _operational_roads_cache


static func _soften_closed_polygon(poly: PackedVector2Array, iterations: int = 1) -> PackedVector2Array:
	if poly.size() < 3:
		return poly
	var current_poly := poly
	for _pass in range(maxi(iterations, 0)):
		var softened := PackedVector2Array()
		softened.resize(current_poly.size() * 2)
		for index in range(current_poly.size()):
			var current := current_poly[index]
			var following := current_poly[(index + 1) % current_poly.size()]
			softened[index * 2] = current.lerp(following, 0.22)
			softened[index * 2 + 1] = current.lerp(following, 0.78)
		current_poly = softened
	return current_poly


static func _road_specs(lod: int, data: Dictionary) -> Array:
	var specs: Array = []
	var base := {
		"motorway": MapGeographyData.ROADS_MOTORWAY,
		"trunk": MapGeographyData.ROADS_TRUNK,
		"primary": MapGeographyData.ROADS_PRIMARY,
		"secondary": MapGeographyData.ROADS_SECONDARY,
		"tertiary": _unpack_flat_lines(data.get("roads_tertiary", [])),
		"local": _unpack_flat_lines(data.get("roads_residential", [])),
		"neighborhood": _load_operational_roads(),
		"service": _unpack_flat_lines(data.get("roads_service", [])),
	}
	var style: Array
	if lod == LOD_TAB:
		style = [
			["motorway", 3.2, 1.45, ROAD_MAJOR, true],
			["trunk", 2.4, 1.05, ROAD_TRUNK, true],
		]
	elif lod == LOD_STRATEGIC:
		style = [
			["motorway", 3.2, 1.45, ROAD_MAJOR, true],
			["trunk", 2.4, 1.05, ROAD_TRUNK, true],
			["primary", 1.8, 0.85, ROAD_PRIMARY, true],
			["secondary", 1.2, 0.62, ROAD_SECONDARY, true],
		]
	elif lod == LOD_OPERATIONAL:
		style = [
			["motorway", 11.0, 7.2, ROAD_MAJOR, true],
			["trunk", 8.5, 5.4, ROAD_TRUNK, true],
			["primary", 5.8, 3.2, ROAD_PRIMARY, true],
			["secondary", 3.4, 1.75, ROAD_SECONDARY, true],
			["tertiary", 1.4, 0.78, ROAD_TERTIARY, true],
			["neighborhood", 1.15, 1.15, ROAD_NEIGHBORHOOD, false],
		]
	else:
		style = [
			["motorway", 13.0, 8.8, ROAD_MAJOR, true],
			["trunk", 10.0, 6.4, ROAD_TRUNK, true],
			["primary", 7.0, 4.0, ROAD_PRIMARY, true],
			["secondary", 3.4, 1.6, ROAD_SECONDARY, true],
			["tertiary", 1.8, 1.0, ROAD_TERTIARY, true],
			["local", 1.0, 1.0, ROAD_LOCAL, false],
			["service", 1.0, 1.0, ROAD_SERVICE, false],
		]
	for row_any in style:
		var row: Array = row_any
		var key := String(row[0])
		specs.append({
			"key": key,
			"lines": base[key],
			"width": _width_for_lod(lod, float(row[1]), float(row[1]), float(row[1]), float(row[1])),
			"core": _width_for_lod(lod, float(row[2]), float(row[2]), float(row[2]), float(row[2])),
			"color": row[3],
			"major": row[4],
			"casing": row[5] if row.size() > 5 else false,
		})
	return specs


static func _sea_color(lod: int) -> Color:
	match lod:
		LOD_DETAIL:
			return SEA_DETAIL
		LOD_OPERATIONAL:
			return SEA_OPERATIONAL
		_:
			return SEA_STRATEGIC


static func _land_color(lod: int) -> Color:
	match lod:
		LOD_DETAIL:
			return LAND_DETAIL
		LOD_OPERATIONAL:
			return LAND_OPERATIONAL
		_:
			return LAND_STRATEGIC


static func _urban_color(lod: int) -> Color:
	match lod:
		LOD_DETAIL:
			return URBAN_DETAIL
		LOD_OPERATIONAL:
			return URBAN_OPERATIONAL
		_:
			return URBAN_STRATEGIC


## 把设计稿的屏幕像素宽度换成该 LOD 的世界宽度；相机只变换静态几何。
static func _width_for_lod(lod: int, strategic_px: float, operational_px: float,
		detail_px: float, tab_px: float) -> float:
	match lod:
		LOD_STRATEGIC:
			return strategic_px / STRATEGIC_REFERENCE_ZOOM
		LOD_DETAIL:
			return detail_px / DETAIL_REFERENCE_ZOOM
		LOD_TAB:
			return tab_px / 0.034
		_:
			return operational_px / OPERATIONAL_REFERENCE_ZOOM


static func _packet(layers: Dictionary, name: String) -> Dictionary:
	if not layers.has(name):
		layers[name] = {
			"points": PackedVector2Array(),
			"indices": PackedInt32Array(),
			"colors": PackedColorArray(),
		}
	return layers[name]


static func _add_triangle(layers: Dictionary, name: String, a: Vector2, b: Vector2,
		c: Vector2, color: Color) -> void:
	var p := _packet(layers, name)
	var points: PackedVector2Array = p.points
	var indices: PackedInt32Array = p.indices
	var colors: PackedColorArray = p.colors
	var base := points.size()
	points.append_array(PackedVector2Array([a, b, c]))
	indices.append_array(PackedInt32Array([base, base + 1, base + 2]))
	colors.append_array(PackedColorArray([color, color, color]))


static func _add_rect(layers: Dictionary, name: String, rect: Rect2, color: Color) -> void:
	var a := rect.position
	var b := Vector2(rect.end.x, rect.position.y)
	var c := rect.end
	var d := Vector2(rect.position.x, rect.end.y)
	_add_triangle(layers, name, a, b, c, color)
	_add_triangle(layers, name, a, c, d, color)


static func _add_polygon(layers: Dictionary, name: String, poly: PackedVector2Array,
		color: Color) -> void:
	if poly.size() < 3:
		return
	var triangulation := _triangulate_polygon(poly)
	var vertices: PackedVector2Array = triangulation.vertices
	var triangles: PackedInt32Array = triangulation.indices
	for i in range(0, triangles.size(), 3):
		if i + 2 < triangles.size():
			_add_triangle(layers, name, vertices[triangles[i]], vertices[triangles[i + 1]],
				vertices[triangles[i + 2]], color)


static func _triangulate_polygon(poly: PackedVector2Array) -> Dictionary:
	var triangles := Geometry2D.triangulate_polygon(poly)
	if not triangles.is_empty():
		return {"vertices": poly, "indices": triangles}
	# Raster contour 的超长主水环含像素级折返/自交，Godot ear clipping 会整环失败。
	# offset_polygon 走 Clipper 整理拓扑，并可能
	# 拆成多个合法闭环；这里把各闭环预三角化后重新合进同一静态 packet。
	for delta in [0.01, 0.1, 1.0]:
		var cleaned_parts: Array[PackedVector2Array] = Geometry2D.offset_polygon(
			poly, delta, Geometry2D.JOIN_SQUARE)
		var combined_vertices := PackedVector2Array()
		var combined_indices := PackedInt32Array()
		for part in cleaned_parts:
			if part.size() < 3:
				continue
			var part_triangles := Geometry2D.triangulate_polygon(part)
			if part_triangles.is_empty():
				continue
			var base := combined_vertices.size()
			combined_vertices.append_array(part)
			for index in part_triangles:
				combined_indices.append(base + index)
		if not combined_indices.is_empty():
			return {"vertices": combined_vertices, "indices": combined_indices}
	return {"vertices": poly, "indices": PackedInt32Array()}


static func _add_polygons(layers: Dictionary, name: String, polygons: Array, color: Color) -> void:
	for poly_any in polygons:
		_add_polygon(layers, name, poly_any as PackedVector2Array, color)


static func _add_flat_polygons(layers: Dictionary, name: String, polygons: Array,
		color: Color) -> void:
	for flat_any in polygons:
		_add_polygon(layers, name, _unpack_flat(flat_any, true), color)


static func _add_polygon_outlines(layers: Dictionary, name: String, polygons: Array,
		width: float, color: Color) -> void:
	var lines: Array = []
	for poly_any in polygons:
		var poly := (poly_any as PackedVector2Array).duplicate()
		if poly.size() >= 3:
			poly.append(poly[0])
			lines.append(poly)
	_add_lines(layers, name, lines, width, color)


static func _add_lines(layers: Dictionary, name: String, lines: Array, width: float,
		color: Color, offset := Vector2.ZERO) -> void:
	if width <= 0.0:
		return
	var half := width * 0.5
	for line_any in lines:
		var line: PackedVector2Array = line_any
		if line.size() < 2:
			continue
		for i in range(line.size() - 1):
			var a := line[i] + offset
			var b := line[i + 1] + offset
			var delta := b - a
			if delta.length_squared() < 0.0001:
				continue
			var normal := Vector2(-delta.y, delta.x).normalized() * half
			_add_triangle(layers, name, a + normal, b + normal, b - normal, color)
			_add_triangle(layers, name, a + normal, b - normal, a - normal, color)


static func _unpack_flat_lines(source: Array) -> Array:
	var out: Array = []
	for flat_any in source:
		var line := _unpack_flat(flat_any, false)
		if line.size() >= 2:
			out.append(line)
	return out


static func _unpack_flat(flat_any, polygon: bool) -> PackedVector2Array:
	var flat: Array = flat_any
	var out := PackedVector2Array()
	var i := 0
	while i + 1 < flat.size():
		var point := Vector2(float(flat[i]), float(flat[i + 1]))
		if out.is_empty() or out[out.size() - 1].distance_squared_to(point) > 0.01:
			out.append(point)
		i += 2
	if polygon and out.size() >= 2 and out[0].distance_squared_to(out[out.size() - 1]) <= 0.01:
		out.remove_at(out.size() - 1)
	return out


static func _add_terrain_wash(layers: Dictionary, lod: int, world_rect: Rect2) -> void:
	# 大尺度、低 alpha 的确定性世界空间纸面层；没有黑色散点，也不随相机游动。
	var spacing := 2200.0 if lod in [LOD_STRATEGIC, LOD_TAB] else (1300.0 if lod == LOD_OPERATIONAL else 780.0)
	var min_cell := Vector2i(floori(world_rect.position.x / spacing), floori(world_rect.position.y / spacing))
	var max_cell := Vector2i(ceili(world_rect.end.x / spacing), ceili(world_rect.end.y / spacing))
	var colors := [LAND_HI, Color8(105, 127, 116, 14), Color8(153, 145, 128, 12)]
	for gx in range(min_cell.x, max_cell.x + 1):
		for gy in range(min_cell.y, max_cell.y + 1):
			var hash := absi(gx * 73856093 ^ gy * 19349663 ^ 0xA61)
			if hash % 5 < 2:
				continue
			var center := Vector2((gx + 0.5) * spacing, (gy + 0.5) * spacing)
			var radius := spacing * (0.44 + float(hash % 17) * 0.012)
			_add_soft_disc(layers, "terrain_wash", center, radius, colors[hash % colors.size()])


static func _add_soft_disc(layers: Dictionary, name: String, center: Vector2, radius: float,
		color: Color) -> void:
	const SEGMENTS := 12
	var edge := Color(color.r, color.g, color.b, 0.0)
	for i in range(SEGMENTS):
		var a := center + Vector2.from_angle(TAU * float(i) / SEGMENTS) * radius
		var b := center + Vector2.from_angle(TAU * float(i + 1) / SEGMENTS) * radius
		var packet := _packet(layers, name)
		var points: PackedVector2Array = packet.points
		var indices: PackedInt32Array = packet.indices
		var colors: PackedColorArray = packet.colors
		var base := points.size()
		points.append_array(PackedVector2Array([center, a, b]))
		indices.append_array(PackedInt32Array([base, base + 1, base + 2]))
		colors.append_array(PackedColorArray([color, edge, edge]))


static func _add_vignette(layers: Dictionary, world_rect: Rect2) -> void:
	var rings := [
		[0.0, 280.0, Color(0.04, 0.05, 0.07, 0.24)],
		[280.0, 700.0, Color(0.04, 0.05, 0.07, 0.42)],
		[700.0, 2000.0, Color(0.03, 0.04, 0.06, 0.72)],
	]
	for i in range(rings.size()):
		var ring: Array = rings[i]
		var inner := world_rect.grow(float(ring[0]))
		var outer := world_rect.grow(float(ring[1]))
		var color: Color = ring[2]
		var name := "vignette_%d" % i
		_add_rect(layers, name, Rect2(outer.position, Vector2(outer.size.x, inner.position.y - outer.position.y)), color)
		_add_rect(layers, name, Rect2(Vector2(outer.position.x, inner.end.y), Vector2(outer.size.x, outer.end.y - inner.end.y)), color)
		_add_rect(layers, name, Rect2(Vector2(outer.position.x, inner.position.y), Vector2(inner.position.x - outer.position.x, inner.size.y)), color)
		_add_rect(layers, name, Rect2(Vector2(inner.end.x, inner.position.y), Vector2(outer.end.x - inner.end.x, inner.size.y)), color)
