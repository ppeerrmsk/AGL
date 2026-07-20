extends SceneTree

## UgcLoader 运行时注入冒烟测试（无头）：
##   godot --headless --path . --script res://scripts/tests/test_ugc_loader.gd
## 覆盖（map-editor spec §4 loader + §3.2 云注入的可无头部分）：
##   ① 地理注入等价：apply_geography（转换图）后 is_on_land（偶奇路径）在全部
##      150×150 格心 == 转换时记录的官方真值 editor_cells
##   ② 注入量核对：道路/城区/海岸线条数 == doc
##   ③ 建筑注入：分帧预热跑完 → entries 数 == doc.buildings；全局最高楼 > 0
##   ④ 云注入：mask 空=基线不变；全 0=处处无云；全 255=不弱于基线；风向 90°=正东
##   ⑤ clear() 还原：官方 JSON 重载后陆判再次逐点 == editor_cells（对官方图两路等价）

var fails: Array[String] = []

func _check(cond: bool, msg: String) -> void:
	if not cond:
		fails.append(msg)

func _land_mismatch_vs_cells(cells: PackedByteArray) -> int:
	var mismatch := 0
	for cy in range(MapDocument.GRID_H):
		for cx in range(MapDocument.GRID_W):
			var p := MapDocument.grid_origin() + Vector2(cx + 0.5, cy + 0.5) * MapDocument.CELL_SIZE_PX
			if (cells[cy * MapDocument.GRID_W + cx] != 0) != MapGeography.is_on_land(p):
				mismatch += 1
	return mismatch

func _initialize() -> void:
	# 转换（editor_cells 即官方陆判真值，由 test_official_map_converter 保证）
	var doc := OfficialMapConverter.build()
	var cells: PackedByteArray = doc.editor_cells["land"]

	# ① 地理注入 → 偶奇路径等价
	UgcLoader.apply_geography(doc)
	_check(MapGeography.ugc_mode, "ugc_mode 未置位")
	var mis := _land_mismatch_vs_cells(cells)
	_check(mis == 0, "注入后陆判：%d 个格心与官方真值不一致" % mis)

	# ② 注入量核对
	var road_total := MapGeographyData.ROADS_MOTORWAY.size() + MapGeographyData.ROADS_TRUNK.size() \
		+ MapGeographyData.ROADS_PRIMARY.size() + MapGeographyData.ROADS_SECONDARY.size() \
		+ MapGeographyData.ROADS_TERTIARY.size()
	_check(road_total == doc.roads.size(), "注入道路 %d ≠ doc %d" % [road_total, doc.roads.size()])
	_check(MapGeographyData.URBAN_POLYGONS.size() == (doc.layer_polygons["urban"] as Array).size(), "注入城区数不等")
	_check(MapGeographyData.COASTLINE_LINES.size() == doc.coastlines.size(), "注入海岸线数不等")
	_check(MapGeographyData.AERODROME_POLYGONS.size() == doc.airports.size(), "注入机场数不等")

	# ③ 建筑注入 + 分帧预热跑完
	# 基准 = 官方管线产出（官方 JSON 也会丢三角剖分失败的退化街区），注入路径须零差异
	BuildingRenderer.cache_reset()
	var guard := 0
	while not BuildingRenderer.cache_step(100) and guard < 1000:
		guard += 1
	var official_count := BuildingRenderer._cache_entries.size()
	UgcLoader.apply_buildings(doc)
	guard = 0
	while not BuildingRenderer.cache_step(100) and guard < 1000:
		guard += 1
	_check(BuildingRenderer.cache_is_ready(), "建筑预热未完成")
	_check(BuildingRenderer._cache_entries.size() == official_count,
		"建筑 entries %d ≠ 官方管线 %d（注入路径零差异铁律）" % [BuildingRenderer._cache_entries.size(), official_count])
	_check(BuildingRenderer._cache_max_h_global > 0.0, "全局最高楼未计算")

	# ④ 云注入
	var w := WeatherSystem.new()
	var base_cfg := {"seed": 12345, "coverage": 0.35, "frequency": 0.00055,
		"wind_dir_deg": 90.0, "wind_speed_ms": 20.0, "mask": PackedByteArray()}
	w.apply_ugc_config(base_cfg)
	_check(w.wind_direction.distance_to(Vector2(1, 0)) < 0.001, "风向 90° 应为正东 (1,0)，得 %s" % str(w.wind_direction))
	var sample_pts: Array[Vector2] = []
	for i in range(40):
		sample_pts.append(Vector2(-7000 + i * 350.0, fmod(i * 1234.5, 14000.0) - 7000.0))
	var baseline: Array[float] = []
	for p in sample_pts:
		baseline.append(w.sample_density(p))
	var has_cloud := false
	for d in baseline:
		if d > 0.0:
			has_cloud = true
	_check(has_cloud, "基线采样全无云（seed/coverage 异常）")
	# mask 全 1.0（128）≈ 基线
	var mask_one := PackedByteArray()
	mask_one.resize(64 * 64)
	mask_one.fill(128)
	w.ugc_mask = mask_one
	for i in range(sample_pts.size()):
		if absf(w.sample_density(sample_pts[i]) - baseline[i]) > 0.02:
			fails.append("mask=1.0 采样点 %d 偏离基线" % i)
			break
	# mask 全 0 → 处处无云
	var mask_zero := PackedByteArray()
	mask_zero.resize(64 * 64)
	w.ugc_mask = mask_zero
	for p in sample_pts:
		if w.sample_density(p) != 0.0:
			fails.append("mask=0 仍有云")
			break
	# mask 全 255（×2）→ 不弱于基线
	var mask_two := PackedByteArray()
	mask_two.resize(64 * 64)
	mask_two.fill(255)
	w.ugc_mask = mask_two
	for i in range(sample_pts.size()):
		if w.sample_density(sample_pts[i]) < baseline[i] - 0.001:
			fails.append("mask=2 弱于基线")
			break
	w.free()

	# ⑤ clear() 还原官方
	UgcLoader.clear()
	_check(not MapGeography.ugc_mode, "clear 后 ugc_mode 未复位")
	var mis2 := _land_mismatch_vs_cells(cells)
	_check(mis2 == 0, "clear 后官方陆判：%d 个格心与真值不一致" % mis2)
	_check(not BuildingRenderer.cache_is_ready(), "clear 后建筑缓存未重置")

	if fails.is_empty():
		print("PASS: UgcLoader 5 组测试全过（地理注入等价/注入量/建筑预热/云mask/clear还原）")
		quit(0)
	else:
		for m in fails:
			print("FAIL: " + m)
		quit(1)
