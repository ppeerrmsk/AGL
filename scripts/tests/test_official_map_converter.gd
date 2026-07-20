extends SceneTree

## 官方地图转换器冒烟测试（无头）：
##   godot --headless --path . --script res://scripts/tests/test_official_map_converter.gd
## 覆盖（map-editor spec §3.4 转换闭环的可无头部分）：
##   ① 陆判等价铁律：转换图陆判（union 直通语义）== MapGeography.is_on_land，全部格心逐点一致
##   ② editor_cells 反推与陆判一致（涂格 == is_on_land）
##   ③ 直通保真：陆地首多边形逐顶点 == 官方 mask；道路总数 == 官方 5 级之和且首条逐顶点相等；
##      建筑数 == districts 数；战区数/字段 == ZoneData.ZONES；海岸线/机场条数一致
##   ④ 存读闭环：save → load 无警告不拒载，陆地层多边形逐顶点相等 + layer_mode 保留
##   ⑤ 围栏静默：转换结果天然在围栏内（无截断警告）

var fails: Array[String] = []

func _check(cond: bool, msg: String) -> void:
	if not cond:
		fails.append(msg)

## 按图层语义判定（union=任一命中 / even_odd=偶奇计数）
func _covered(p: Vector2, polys: Array, mode: String) -> bool:
	var hits := 0
	for poly in polys:
		if Geometry2D.is_point_in_polygon(p, poly):
			if mode == "union":
				return true
			hits += 1
	return hits % 2 == 1 if mode != "union" else false

func _initialize() -> void:
	var t0 := Time.get_ticks_msec()
	var doc := OfficialMapConverter.build()
	print("转换耗时 %d ms" % (Time.get_ticks_msec() - t0))
	_check(doc.warnings.is_empty(), "转换产生警告: %s" % str(doc.warnings))

	# ① 陆判等价：全格心逐点对拍（按 layer_mode 语义）
	var land: Array = doc.layer_polygons["land"]
	var land_mode := str(doc.layer_mode.get("land", "even_odd"))
	print("陆地层多边形数: %d（语义 %s，直通）" % [land.size(), land_mode])
	_check(land_mode == "union", "转换图陆地层语义应为 union，得 %s" % land_mode)
	var mismatch := 0
	for cy in range(MapDocument.GRID_H):
		for cx in range(MapDocument.GRID_W):
			var p := MapDocument.grid_origin() + Vector2(cx + 0.5, cy + 0.5) * MapDocument.CELL_SIZE_PX
			if _covered(p, land, land_mode) != MapGeography.is_on_land(p):
				mismatch += 1
	_check(mismatch == 0, "陆判等价：%d 个格心不一致" % mismatch)
	# 直通铁律：首个陆地多边形与官方 mask 逐顶点相等
	if not land.is_empty() and not MapGeographyData.LAND_MASK_POLYGONS.is_empty():
		_check(land[0] == MapGeographyData.LAND_MASK_POLYGONS[0], "陆地首多边形与官方 mask 不等（直通铁律）")

	# ② editor_cells 与陆判一致
	var cells: PackedByteArray = doc.editor_cells["land"]
	var cell_mismatch := 0
	for cy in range(MapDocument.GRID_H):
		for cx in range(MapDocument.GRID_W):
			var p := MapDocument.grid_origin() + Vector2(cx + 0.5, cy + 0.5) * MapDocument.CELL_SIZE_PX
			if (cells[cy * MapDocument.GRID_W + cx] != 0) != MapGeography.is_on_land(p):
				cell_mismatch += 1
	_check(cell_mismatch == 0, "editor_cells 反推：%d 个格与陆判不一致" % cell_mismatch)
	var painted := 0
	for i in range(cells.size()):
		if cells[i] != 0:
			painted += 1
	_check(painted > 500, "涂格数异常少：%d" % painted)

	# ③ 直通保真
	var road_total := MapGeographyData.ROADS_MOTORWAY.size() + MapGeographyData.ROADS_TRUNK.size() \
		+ MapGeographyData.ROADS_PRIMARY.size() + MapGeographyData.ROADS_SECONDARY.size() \
		+ MapGeographyData.ROADS_TERTIARY.size()
	_check(doc.roads.size() == road_total, "道路数 %d ≠ 官方 %d" % [doc.roads.size(), road_total])
	if not doc.roads.is_empty() and not MapGeographyData.ROADS_MOTORWAY.is_empty():
		var r0: Array = doc.roads[0]["points"]
		var o0: PackedVector2Array = MapGeographyData.ROADS_MOTORWAY[0]
		_check(r0.size() == o0.size(), "首条道路顶点数不等")
		if r0.size() == o0.size():
			for i in range(o0.size()):
				if Vector2(r0[i][0], r0[i][1]) != o0[i]:
					fails.append("首条道路顶点 %d 不等（直通铁律）" % i)
					break
	var bjson = JSON.parse_string(FileAccess.open(OfficialMapConverter.BUILDINGS_JSON_PATH, FileAccess.READ).get_as_text())
	var district_count: int = (bjson.get("districts", []) as Array).size()
	_check(doc.buildings.size() == district_count, "建筑数 %d ≠ districts %d" % [doc.buildings.size(), district_count])
	_check(doc.buildings.size() <= MapDocument.MAX_BUILDINGS, "建筑数超围栏（围栏须容纳官方量）")
	_check(doc.zones.size() == ZoneData.ZONES.size(), "战区数 %d ≠ %d" % [doc.zones.size(), ZoneData.ZONES.size()])
	if not doc.zones.is_empty():
		var z0: Dictionary = doc.zones[0]
		var o_z0: Dictionary = ZoneData.ZONES[0]
		_check(z0["id"] == str(o_z0["id"]), "战区 id 不等")
		_check(Vector2(z0["center"][0], z0["center"][1]) == o_z0["center"], "战区 center 不等")
		_check(z0.has("ground_spawn_polygons") == o_z0.has("ground_spawn_polygons"), "战区刷怪多边形丢失")
	_check(doc.coastlines.size() == MapGeographyData.COASTLINE_LINES.size(), "海岸线条数不等")
	_check(doc.airports.size() == MapGeographyData.AERODROME_POLYGONS.size(), "机场数不等")
	_check(not doc.spawn.is_empty(), "出生点缺失")

	# ④ 存读闭环
	var path := "user://test_official_convert.json"
	_check(doc.save_to(path), "保存失败")
	var back := MapDocument.load_from(path)
	_check(back != null, "读回失败")
	if back != null:
		_check(back.warnings.is_empty(), "读回产生警告（围栏静默铁律）: %s" % str(back.warnings))
		var l0: Array = doc.layer_polygons["land"]
		var l1: Array = back.layer_polygons["land"]
		_check(l1.size() == l0.size(), "读回陆地多边形组数不等")
		if l1.size() == l0.size():
			for i in range(l0.size()):
				if l0[i] != l1[i]:
					fails.append("读回陆地多边形 %d 顶点不等" % i)
					break
		_check(back.buildings.size() == doc.buildings.size(), "读回建筑数不等")
		_check(str(back.layer_mode.get("land", "")) == "union", "读回 layer_mode 丢失")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

	if fails.is_empty():
		print("PASS: 官方图转换 5 组测试全过（陆判等价/涂格反推/直通保真/存读闭环/围栏静默）")
		quit(0)
	else:
		for m in fails:
			print("FAIL: " + m)
		quit(1)
