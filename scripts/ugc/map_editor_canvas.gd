class_name MapEditorCanvas
extends Node2D

## 地图编辑器静态画布（世界空间，map-editor spec §4）
## 绘制：海底色 → 涂格图层多边形（调色板取色 + 描边）→ 机场/道路/海岸线/建筑/战区 → 边界框
## 重绘纪律：只在数据变化时由场景调 notify_changed() 重绘；
## 相机平移缩放走 canvas transform 不触发重绘（性能守则第 1 条）。
## 光标/笔画中格子叠加由 MapEditorScene 自己的轻量 _draw 承担，不在本层。

var doc: MapDocument = null

## 涂格图层 → 调色板 key
const LAYER_PALETTE_KEY := {
	"land": "land",
	"mountain": "terrain_mountain",
	"forest": "terrain_forest",
	"farmland": "terrain_farmland",
	"beach": "terrain_beach",
	"urban": "urban",
}

const BOUNDARY_COLOR := Color(0.55, 0.75, 0.82, 0.5)


func notify_changed() -> void:
	queue_redraw()


## 图层对应的调色板颜色（场景画笔画叠加也用它取色）
func layer_color(layer: String) -> Color:
	return _pal(LAYER_PALETTE_KEY.get(layer, "land"))


func _draw() -> void:
	if doc == null:
		return
	var half := MapDocument.WORLD_HALF_PX
	# 海底色（世界范围 + 一圈余量）
	draw_rect(Rect2(-half * 1.2, -half * 1.2, half * 2.4, half * 2.4), _pal("sea"), true)

	# 涂格图层多边形（land 最底，其余覆盖其上；与 §2.2 图层顺序一致）
	var outline: Color = _style_color(doc.style.get("post", {}).get("land_outline", [0.1, 0.12, 0.1, 0.6]))
	for layer in ["land", "mountain", "forest", "farmland", "beach", "urban"]:
		var col := layer_color(layer)
		for poly in doc.layer_polygons.get(layer, []):
			if poly.size() >= 3:
				draw_colored_polygon(poly, col)
				draw_polyline(_closed(poly), outline, 1.5, true)

	# 机场（官方转换图为多边形形态）
	for a in doc.airports:
		if a is Dictionary and a.has("polygon"):
			var poly := _to_packed(a["polygon"])
			if poly.size() >= 3:
				draw_colored_polygon(poly, _pal("road").darkened(0.3))

	# 道路（折线，按等级取宽度）
	for r in doc.roads:
		var pts := _to_packed(r.get("points", []))
		if pts.size() >= 2:
			var cls := str(r.get("width_class", "primary"))
			var w := 14.0 if cls == "motorway" else (10.0 if cls == "trunk" else 6.0)
			draw_polyline(pts, _pal("road"), w, false)

	# 海岸线
	for line in doc.coastlines:
		var pts := _to_packed(line)
		if pts.size() >= 2:
			draw_polyline(pts, _pal("tacview_cross"), 2.0, true)

	# 建筑 footprint（编辑器内平面示意；伪 3D 是游戏内 BuildingRenderer 的事）
	for b in doc.buildings:
		if b is Dictionary and b.has("footprint"):
			var fp := _to_packed(b["footprint"])
			if fp.size() >= 3:
				draw_colored_polygon(fp, _pal("building_roof"))

	# 战区圆
	for z in doc.zones:
		if z is Dictionary and z.has("center"):
			var c := Vector2(float(z["center"][0]), float(z["center"][1]))
			draw_arc(c, float(z.get("radius", 1000.0)), 0, TAU, 64, BOUNDARY_COLOR, 3.0, true)

	# 世界边界
	draw_rect(Rect2(-half, -half, half * 2.0, half * 2.0), BOUNDARY_COLOR, false, 4.0)


# ── 取色工具 ──

func _pal(key: String) -> Color:
	return _style_color(doc.style.get("palette", {}).get(key, [0.5, 0.5, 0.5, 1.0]))


static func _style_color(arr) -> Color:
	if arr is Array and arr.size() >= 3:
		var a := 1.0
		if arr.size() >= 4:
			a = float(arr[3])
		return Color(float(arr[0]), float(arr[1]), float(arr[2]), a)
	return Color.GRAY


static func _to_packed(raw) -> PackedVector2Array:
	var out := PackedVector2Array()
	if raw is Array:
		for p in raw:
			if p is Array and p.size() >= 2:
				out.append(Vector2(float(p[0]), float(p[1])))
	return out


static func _closed(poly: PackedVector2Array) -> PackedVector2Array:
	var out := poly.duplicate()
	if poly.size() > 0:
		out.append(poly[0])
	return out
