class_name OfficialMapConverter
extends RefCounted

## 官方地图 → MapDocument 一键转换（map-editor spec §3.4"从官方地图新建"）
##
## 关键事实：官方 gameplay 数据本就是矢量 JSON，转换 = 格式直通搬运（逐顶点无损），
## 不是描图。editor_cells 由多边形栅格化反推；转换后全图层 dirty=false（原始多边形权威），
## 用户动了笔刷才对该层重烘焙（懒烘焙保 1:1）。
##
## 数据来源：
##   MapGeographyData（tokyo_bay.json）→ 陆地 mask / 城区 / 道路 5 级 / 机场多边形 / 海岸线
##   MapGeography.get_land_polygons()  → 手画陆地（Chaikin 平滑后，is_on_land 同款）
##   yokohama_buildings.json districts → 建筑（footprint + 楼高）
##   ZoneData.ZONES                    → 战区（全字段 JSON 化，含地面刷怪多边形）
##   MapBoundary.PLAYER_START_OFFSET_PX → 出生点
##   云/style → MapDocument 默认值（= 官方现值）

const BUILDINGS_JSON_PATH := "res://resources/maps/yokohama_buildings.json"

## 道路等级 → width_class 直通（保留官方 5 级全量）
const ROAD_CLASSES := ["motorway", "trunk", "primary", "secondary", "tertiary"]


static func build() -> MapDocument:
	MapGeographyData.ensure_loaded()
	var doc := MapDocument.new()
	doc.display_name = "Tokyo Bay (Official)"
	doc.world_size_m = MapDocument.WORLD_HALF_PX * 2.0 / GameConstants.PIXELS_PER_METER

	# ── 陆地层：OSM mask + 手画平滑地块（is_on_land 的两路合一，逐顶点直通）──
	# 两路互相重叠 → 语义标 "union"（任一命中即算，与官方 is_on_land 一字不差；spec §3.4）。
	# 不做几何并集：60km 重烘焙数据上逐对 merge_polygons 有浮点精度斑点，直通零损失。
	var land: Array = []
	for poly in MapGeographyData.LAND_MASK_POLYGONS:
		land.append(poly)
	for poly in MapGeography.get_land_polygons():
		land.append(poly)
	doc.layer_polygons["land"] = land
	doc.layer_mode["land"] = "union"

	# ── 城区层（OSM 块间互叠，同 union 语义直通）──
	doc.layer_polygons["urban"] = MapGeographyData.URBAN_POLYGONS.duplicate()
	doc.layer_mode["urban"] = "union"

	# ── 机场（官方为多边形形态，见 MapDocument.airports 注释）──
	for poly in MapGeographyData.AERODROME_POLYGONS:
		doc.airports.append({"polygon": _poly_to_arr(poly)})

	# ── 道路 5 级直通 ──
	var road_sources := {
		"motorway": MapGeographyData.ROADS_MOTORWAY,
		"trunk": MapGeographyData.ROADS_TRUNK,
		"primary": MapGeographyData.ROADS_PRIMARY,
		"secondary": MapGeographyData.ROADS_SECONDARY,
		"tertiary": MapGeographyData.ROADS_TERTIARY,
	}
	for cls in ROAD_CLASSES:
		for line in road_sources[cls]:
			doc.roads.append({"points": _poly_to_arr(line), "width_class": cls})

	# ── 海岸线折线 ──
	for line in MapGeographyData.COASTLINE_LINES:
		doc.coastlines.append(_poly_to_arr(line))

	# ── 建筑（districts 直通：footprint + max_real_h → h_m）──
	var bf := FileAccess.open(BUILDINGS_JSON_PATH, FileAccess.READ)
	if bf != null:
		var braw = JSON.parse_string(bf.get_as_text())
		if braw is Dictionary:
			for d in braw.get("districts", []):
				var fp: Array = d.get("footprint", [])
				if fp.size() >= 3:
					doc.buildings.append({"footprint": fp, "h_m": float(d.get("max_real_h", 30.0))})
	else:
		doc.warnings.append("建筑 JSON 缺失：%s（转换图无建筑）" % BUILDINGS_JSON_PATH)

	# ── 战区全字段 JSON 化（P0"战区布局 JSON 化"落点）──
	for z in ZoneData.ZONES:
		var zj := {
			"id": str(z["id"]),
			"name_key": str(z.get("name_key", "")),
			"label": str(z.get("label", "")),
			"center": [z["center"].x, z["center"].y],
			"radius": float(z["radius"]),
			"mission_type": str(z.get("mission_type", "ground")),
		}
		if z.has("ground_spawn_polygons"):
			var polys_json := []
			for poly in z["ground_spawn_polygons"]:
				var pj := []
				for p in poly:
					pj.append([p.x, p.y])
				polys_json.append(pj)
			zj["ground_spawn_polygons"] = polys_json
		doc.zones.append(zj)

	# ── 出生点 ──
	var start: Vector2 = MapBoundary.get_player_start()
	doc.spawn = {"pos": [start.x, start.y], "heading_deg": 0.0}

	# ── editor_cells 反推（陆地 + 城区两层走笔刷，其余官方图为空层；union 语义）──
	doc.editor_cells["land"] = ContourBaker.rasterize_polygons(
		land, MapDocument.GRID_W, MapDocument.GRID_H,
		MapDocument.CELL_SIZE_PX, MapDocument.grid_origin(), true)
	doc.editor_cells["urban"] = ContourBaker.rasterize_polygons(
		doc.layer_polygons["urban"], MapDocument.GRID_W, MapDocument.GRID_H,
		MapDocument.CELL_SIZE_PX, MapDocument.grid_origin(), true)

	# 全图层保持 dirty=false —— 原始多边形是权威（懒烘焙铁律）
	return doc


static func _poly_to_arr(poly: PackedVector2Array) -> Array:
	var out := []
	for p in poly:
		out.append([p.x, p.y])
	return out
