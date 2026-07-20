class_name UgcLoader
extends RefCounted

## UGC 地图运行时注入器（map-editor spec §4；ugc-editor P0 交付物的地图部分）
##
## 职责：MapDocument → 既有运行时系统。全部走加法式注入口，官方路径零改动：
##   地理    → MapGeographyData.inject_ugc + MapGeography.ugc_mode（偶奇陆判）
##   建筑    → BuildingRenderer.inject_ugc_districts（复用分帧预热流水线）
##   云      → WeatherSystem.apply_ugc_config（sample_density 唯一注入点）
##   战区/出生点/style 调色板 → 尚未接线（TODO 阶段 2/4：战区注入待 ZoneData 读取口
##   数据化；style 待渲染层颜色数据驱动化）
##
## 调用顺序契约：apply_geography 必须在生存模式场景 _ready 链之前（或紧随其后调
## MapGeography.rebuild_from_data 已内置）；apply_to_weather 在 WeatherSystem.setup 之后。
## 退出 UGC 局回官方图：必须调 clear()，否则静态注入残留污染下一局。

## 加载 + 校验一张 UGC 地图；失败/拒载返回 null（warnings 已打印）
static func load_map(path: String) -> MapDocument:
	return MapDocument.load_from(path)


## 注入地理三件套（陆地/城区/道路/机场/海岸线）并重建派生缓存
static func apply_geography(doc: MapDocument) -> void:
	var roads_by_class := {}
	for cls in ["motorway", "trunk", "primary", "secondary", "tertiary"]:
		roads_by_class[cls] = []
	for r in doc.roads:
		var cls := str(r.get("width_class", "primary"))
		if not roads_by_class.has(cls):
			cls = "primary"
		var pts := PackedVector2Array()
		for p in r.get("points", []):
			pts.append(Vector2(float(p[0]), float(p[1])))
		if pts.size() >= 2:
			roads_by_class[cls].append(pts)
	var aero: Array = []
	for a in doc.airports:
		if a is Dictionary and a.has("polygon"):
			var poly := PackedVector2Array()
			for p in a["polygon"]:
				poly.append(Vector2(float(p[0]), float(p[1])))
			if poly.size() >= 3:
				aero.append(poly)
	var coast: Array = []
	for line in doc.coastlines:
		var pts := PackedVector2Array()
		for p in line:
			pts.append(Vector2(float(p[0]), float(p[1])))
		if pts.size() >= 2:
			coast.append(pts)
	# 陆地层进 LAND_MASK 槽位；判定语义随 doc.layer_mode（union=官方直通 / even_odd=烘焙环组）
	MapGeographyData.inject_ugc(
		doc.layer_polygons.get("land", []),
		doc.layer_polygons.get("urban", []),
		aero, roads_by_class, coast)
	MapGeography.ugc_mode = true
	MapGeography.ugc_land_even_odd = str(doc.layer_mode.get("land", "even_odd")) == "even_odd"
	MapGeography.rebuild_from_data()


## 注入建筑（doc.buildings {footprint, h_m} → 官方 districts 结构）
static func apply_buildings(doc: MapDocument) -> void:
	var districts: Array = []
	for b in doc.buildings:
		if b is Dictionary and b.has("footprint"):
			districts.append({"footprint": b["footprint"], "max_real_h": float(b.get("h_m", 30.0))})
	BuildingRenderer.inject_ugc_districts(districts)


## 注入云配置（weather 需已 setup）
static func apply_to_weather(weather: WeatherSystem, doc: MapDocument) -> void:
	weather.apply_ugc_config(doc.cloud)


## 清除全部 UGC 静态注入，恢复官方数据路径（回主菜单/换图时必调）
static func clear() -> void:
	MapGeography.ugc_mode = false
	MapGeography.ugc_land_even_odd = true
	MapGeographyData.reset_to_official()
	MapGeography.rebuild_from_data()
	BuildingRenderer.cache_reset()
