extends SceneTree

## 地图编辑器阶段 1 核心冒烟测试（无头）：
##   godot --headless --path . --script res://scripts/tests/test_map_editor_core.gd
## 覆盖（map-editor spec §5 的可无头部分）：
##   ① Chaikin 对拍：ContourBaker == MapGeography._chaikin_closed（同参数铁律）
##   ② bake_layer 几何：实心块 → 闭合多边形；深内部格心在内、远处格心在外
##   ③ 孔洞：环形涂格 → 2 个环，孔心偶奇判定为"非陆地"
##   ④ rasterize→bake 往返：一致率 ≥ 90%（角切损耗只在边界）
##   ⑤ MapDocument 存读闭环：多边形/涂格/dirty/style 逐项相等
##   ⑥ 围栏：zones 超上限截断 + 警告；schema 过新拒载
##   ⑦ 撤销：push_undo → 改 → undo 恢复

var fails: Array[String] = []

func _check(cond: bool, msg: String) -> void:
	if not cond:
		fails.append(msg)

func _initialize() -> void:
	_test_chaikin_parity()
	_test_bake_blob()
	_test_bake_ring_hole()
	_test_rasterize_roundtrip()
	_test_document_roundtrip()
	_test_fences()
	_test_undo()
	if fails.is_empty():
		print("PASS: map-editor 阶段1 核心 7 组测试全过（Chaikin对拍/烘焙/孔洞/往返/存读/围栏/撤销）")
		quit(0)
	else:
		for m in fails:
			print("FAIL: " + m)
		quit(1)


## ① Chaikin 与手画地块实现逐点相等
func _test_chaikin_parity() -> void:
	var poly := PackedVector2Array([
		Vector2(0, 0), Vector2(400, -120), Vector2(700, 300),
		Vector2(500, 800), Vector2(-100, 600), Vector2(-300, 200),
	])
	var a := ContourBaker.chaikin_closed(poly, 2)
	var b := MapGeography._chaikin_closed(poly, 2)
	_check(a.size() == b.size(), "Chaikin 对拍：顶点数 %d ≠ %d" % [a.size(), b.size()])
	if a.size() == b.size():
		for i in range(a.size()):
			if a[i] != b[i]:
				fails.append("Chaikin 对拍：顶点 %d 不等 %s ≠ %s" % [i, a[i], b[i]])
				break


## 小网格工具：20×20，格 100px，原点 (-1000,-1000)
const GW := 20
const GH := 20
const CS := 100.0
const ORI := Vector2(-1000, -1000)

func _paint(pred: Callable) -> PackedByteArray:
	var cells := PackedByteArray()
	cells.resize(GW * GH)
	for cy in range(GH):
		for cx in range(GW):
			if pred.call(cx, cy):
				cells[cy * GW + cx] = 1
	return cells

func _cell_center(cx: int, cy: int) -> Vector2:
	return ORI + Vector2(cx + 0.5, cy + 0.5) * CS

func _inside_even_odd(p: Vector2, polys: Array) -> bool:
	var hits := 0
	for poly in polys:
		if Geometry2D.is_point_in_polygon(p, poly):
			hits += 1
	return hits % 2 == 1


## ② 实心圆块烘焙
func _test_bake_blob() -> void:
	var c := Vector2(10, 10)
	var cells := _paint(func(cx, cy): return Vector2(cx, cy).distance_to(c) <= 6.0)
	var polys := ContourBaker.bake_layer(cells, GW, GH, CS, ORI)
	_check(polys.size() == 1, "实心块：期望 1 个多边形，得 %d" % polys.size())
	if polys.is_empty():
		return
	_check(polys[0].size() >= 8, "实心块：平滑后顶点过少 %d" % polys[0].size())
	# 深内部（离边界 ≥2 格）必在内
	var deep_ok := true
	var far_ok := true
	for cy in range(GH):
		for cx in range(GW):
			var d := Vector2(cx, cy).distance_to(c)
			var p := _cell_center(cx, cy)
			if d <= 4.0 and not _inside_even_odd(p, polys):
				deep_ok = false
			if d >= 8.0 and _inside_even_odd(p, polys):
				far_ok = false
	_check(deep_ok, "实心块：深内部格心有落在多边形外的")
	_check(far_ok, "实心块：远处空格心有落在多边形内的")


## ③ 环形（甜甜圈）→ 外环 + 孔洞两个环
func _test_bake_ring_hole() -> void:
	var c := Vector2(10, 10)
	var cells := _paint(func(cx, cy):
		var d := Vector2(cx, cy).distance_to(c)
		return d >= 3.5 and d <= 8.0)
	var polys := ContourBaker.bake_layer(cells, GW, GH, CS, ORI)
	_check(polys.size() == 2, "环形：期望 2 个环（外+孔），得 %d" % polys.size())
	# 孔心：偶奇判定应为"外"
	_check(not _inside_even_odd(_cell_center(10, 10), polys), "环形：孔心被偶奇判定为陆地")
	# 环带中部：应为"内"
	_check(_inside_even_odd(_cell_center(10, 10 + 6), polys), "环形：环带格心未判定为陆地")


## ④ 涂格 → 烘焙 → 反栅格化 一致率
func _test_rasterize_roundtrip() -> void:
	var c := Vector2(9, 11)
	var cells := _paint(func(cx, cy): return Vector2(cx, cy).distance_to(c) <= 6.5)
	var polys := ContourBaker.bake_layer(cells, GW, GH, CS, ORI)
	var back := ContourBaker.rasterize_polygons(polys, GW, GH, CS, ORI)
	var agree := 0
	for i in range(GW * GH):
		if (cells[i] != 0) == (back[i] != 0):
			agree += 1
	var ratio := float(agree) / float(GW * GH)
	_check(ratio >= 0.90, "往返一致率 %.3f < 0.90" % ratio)


## ⑤ MapDocument 存读闭环
func _test_document_roundtrip() -> void:
	var doc := MapDocument.new()
	doc.display_name = "测试图"
	# 在 land 层涂一块并烘焙
	for cy in range(60, 90):
		for cx in range(40, 100):
			doc.editor_cells["land"][cy * MapDocument.GRID_W + cx] = 1
	doc.mark_dirty_and_rebake("land")
	doc.zones = [{"center": [0, 0], "radius": 1500.0, "type": "standard"}]
	doc.railways = [{"id": "boss_main", "points": [[-1000, -500], [1000, 500]]}]
	doc.spawn = {"pos": [0.0, 5000.0], "heading_deg": 0.0}
	var path := "user://test_map_editor_core.json"
	_check(doc.save_to(path), "保存失败")
	var back := MapDocument.load_from(path)
	_check(back != null, "读回失败")
	if back == null:
		return
	_check(back.display_name == "测试图", "display_name 丢失")
	_check(back.layer_dirty["land"] == true, "layer_dirty 丢失")
	_check(back.editor_cells["land"] == doc.editor_cells["land"], "涂格原稿不等（editor_cells 无损铁律）")
	var p0: Array = doc.layer_polygons["land"]
	var p1: Array = back.layer_polygons["land"]
	_check(p1.size() == p0.size(), "多边形组数 %d ≠ %d" % [p1.size(), p0.size()])
	if p1.size() == p0.size():
		for i in range(p0.size()):
			if p0[i].size() != p1[i].size():
				fails.append("多边形 %d 顶点数不等" % i)
				break
	_check(back.zones.size() == 1, "zones 丢失")
	_check(back.railways == doc.railways, "railways 路线 SSOT 丢失")
	_check(back.style["palette"]["sea"][0] == 0.16, "style 默认调色板丢失")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


## ⑥ 数值围栏
func _test_fences() -> void:
	var zones := []
	for i in range(20):
		zones.append({"center": [i * 100, 0], "radius": 800.0, "type": "standard"})
	var doc := MapDocument.from_json_dict({"schema_version": 1, "zones": zones})
	_check(doc.zones.size() == MapDocument.MAX_ZONES, "zones 未截断到 %d（得 %d）" % [MapDocument.MAX_ZONES, doc.zones.size()])
	_check(not doc.warnings.is_empty(), "zones 截断未产生警告")
	var newer := MapDocument.from_json_dict({"schema_version": 99})
	_check(newer.rejected, "过新 schema 未被拒载")
	var bad_cloud := MapDocument.from_json_dict({"schema_version": 1,
		"cloud": {"coverage": 5.0, "wind_speed_ms": -10.0}})
	_check(float(bad_cloud.cloud["coverage"]) == 1.0, "coverage 未钳制到 1.0")
	_check(float(bad_cloud.cloud["wind_speed_ms"]) == 0.0, "wind_speed 未钳制到 0")


## ⑦ 撤销
func _test_undo() -> void:
	var doc := MapDocument.new()
	doc.editor_cells["land"][0] = 1
	var before: PackedByteArray = doc.editor_cells["land"].duplicate()
	doc.push_undo("land")
	doc.editor_cells["land"][1] = 1
	doc.editor_cells["land"][2] = 1
	var restored := doc.undo()
	_check(restored == "land", "undo 未返回图层名")
	_check(doc.editor_cells["land"] == before, "undo 未恢复涂格")
