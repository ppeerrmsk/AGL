extends RefCounted
## 舰船水域硬闸：船体外接圆 + 岸线线段距离，避免点采样漏掉窄堤/小岛。
## 空间桶只含几何值，不持有场景 Object；更换地图数组或 UGC 语义后自动重建。
## 东京用与正式画面同源的离线地表净空。UGC仅使用当前地图注入的多边形。
const TOKYO_PATH := "res://resources/maps/tokyo_naval_clearance.bin"
const TOKYO_ORIGIN := Vector2(-16300, -15700)
const TOKYO_STEP := 8.0
const TOKYO_WIDTH := 4000
const CELL := 512.0
static var _tokyo_clearance := PackedByteArray()
static var _tokyo_attempted := false
static var _source: Array = []
static var _ugc := false
static var _even_odd := false
static var _built := false
static var _edges: Dictionary = {}
static var revision := 0

static func prepare() -> void:
	MapGeography.ensure_ready()
	if _built and is_same(_source, MapGeographyData.LAND_MASK_POLYGONS) \
			and _ugc == MapGeography.ugc_mode and _even_odd == MapGeography.ugc_land_even_odd:
		return
	_source = MapGeographyData.LAND_MASK_POLYGONS
	_ugc = MapGeography.ugc_mode
	_even_odd = MapGeography.ugc_land_even_odd
	_built = true
	revision += 1
	_edges.clear()
	if not _ugc:
		if not _tokyo_attempted:
			_tokyo_attempted = true
			if FileAccess.file_exists(TOKYO_PATH):
				_tokyo_clearance = FileAccess.get_file_as_bytes(TOKYO_PATH).decompress(
					TOKYO_WIDTH * TOKYO_WIDTH, FileAccess.COMPRESSION_DEFLATE)
			if _tokyo_clearance.size() != TOKYO_WIDTH * TOKYO_WIDTH:
				push_error("Naval water: invalid Tokyo coastal clearance map")
		return
	for poly: PackedVector2Array in _source:
		for i in poly.size():
			var a := poly[i]
			var b := poly[(i + 1) % poly.size()]
			# 长段先分割，避免对角岸线的巨大包围盒占满全图桶。
			var parts := maxi(1, ceili(a.distance_to(b) / CELL))
			for j in parts:
				var start := a.lerp(b, float(j) / parts)
				var finish := a.lerp(b, float(j + 1) / parts)
				var low := Vector2i((start.min(finish) / CELL).floor())
				var high := Vector2i((start.max(finish) / CELL).floor())
				for y in range(low.y, high.y + 1):
					for x in range(low.x, high.x + 1):
						var key := Vector2i(x, y)
						if not _edges.has(key):
							_edges[key] = []
						_edges[key].append([start, finish])

static func disk_clear(center: Vector2, radius: float) -> bool:
	if not center.is_finite() or not is_finite(radius) or radius < 0.0:
		return false
	prepare()
	if not _ugc:
		var cell := Vector2i(((center - TOKYO_ORIGIN) / TOKYO_STEP).floor())
		if cell.x < 0 or cell.y < 0 or cell.x >= TOKYO_WIDTH or cell.y >= TOKYO_WIDTH \
				or _tokyo_clearance.size() != TOKYO_WIDTH * TOKYO_WIDTH:
			return false
		# 棋盘距离给出欧氏净空下界，再扣两格覆盖光栅化取整及格内位置误差。
		return (_tokyo_clearance[cell.y * TOKYO_WIDTH + cell.x] - 2) * TOKYO_STEP > radius
	if MapGeography.is_on_land(center):
		return false
	var low := Vector2i(((center - Vector2.ONE * radius) / CELL).floor())
	var high := Vector2i(((center + Vector2.ONE * radius) / CELL).floor())
	var radius_squared := radius * radius
	for y in range(low.y, high.y + 1):
		for x in range(low.x, high.x + 1):
			for edge: Array in _edges.get(Vector2i(x, y), []):
				if Geometry2D.get_closest_point_to_segment(center, edge[0], edge[1]).distance_squared_to(center) <= radius_squared:
					return false
	return true
