extends RefCounted
## 独立交集 oracle，避免用被测函数自己的包围盒证明旋转覆盖。
var _pass := 0
var _fail := 0


func run() -> bool:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1920, 1080)
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	(Engine.get_main_loop() as SceneTree).root.get_node("BenchRunner").add_child(viewport)
	var camera := Camera2D.new()
	camera.ignore_rotation = false
	viewport.add_child(camera)
	var source := RasterBasemapRenderer.new()
	viewport.add_child(source)
	source.set_process(false)
	source._camera = camera
	source._world_rect = Rect2(-16384, -16384, 32768, 32768)
	source._manifest = {"levels": {"detail": {"size": [8192, 8192], "rows": 8, "columns": 8}}}
	var missing := 0
	var extraneous := 0
	var cases := 0
	var peak_visible := 0
	for size in [Vector2i(1920, 1080), Vector2i(1080, 1920)]:
		viewport.size = size
		for angle in [0.0, 0.244346, -0.209440, PI / 4.0]:
			for zoom in [0.20, 0.26, 0.65]:
				for center in [Vector2.ZERO, Vector2(2700, -3700), Vector2(6000, 6000)]:
					camera.position = center
					camera.zoom = Vector2.ONE * zoom
					camera.rotation = angle
					camera.offset = Vector2(73, -41)
					camera.force_update_scroll()
					var inverse := viewport.canvas_transform.affine_inverse()
					var view := PackedVector2Array([inverse * Vector2.ZERO, inverse * Vector2(size.x, 0),
						inverse * Vector2(size), inverse * Vector2(0, size.y)])
					var visible := source._visible_keys(&"detail")
					var required := source._required_keys(&"detail")
					var expected: Array[String] = []
					peak_visible = maxi(peak_visible, visible.size())
					for row in 8:
						for column in 8:
							var corner := Vector2(-16384, -16384) + Vector2(column, row) * 4096.0
							var polygon := PackedVector2Array([corner, corner + Vector2(4096, 0),
								corner + Vector2(4096, 4096), corner + Vector2(0, 4096)])
							if not Geometry2D.intersect_polygons(view, polygon).is_empty():
								var key := "r%02d_c%02d" % [row, column]
								expected.append(key)
								missing += int(key not in visible)
								missing += int(key not in required)
					for key: String in visible:
						extraneous += int(key not in expected)
					cases += 1
	_check(missing == 0, "rotated and offset viewport intersections are all visible and requested")
	_check(extraneous == 0, "offscreen bounding-box corners do not consume visible tile slots")
	_check(peak_visible <= source.MAX_REQUIRED_TILES_PER_LOD, "tested views fit unchanged required tile budget")
	viewport.size = Vector2i(1920, 1080)
	camera.position = Vector2.ZERO
	camera.rotation = 0.0
	camera.offset = Vector2.ZERO
	camera.zoom = Vector2.ONE * 0.26
	camera.force_update_scroll()
	var aligned := source._visible_keys(&"detail")
	aligned.sort()
	_check(aligned == ["r03_c03", "r03_c04", "r04_c03", "r04_c04"], "axis-aligned center retains original four tiles")
	camera.position = Vector2(100000, 100000)
	camera.zoom = Vector2.ONE
	camera.force_update_scroll()
	_check(source._visible_keys(&"detail").is_empty(), "viewport wholly outside map does not request clamped edge tiles")
	camera.enabled = false
	camera.ignore_rotation = true
	camera.position = Vector2(6000, 6000)
	camera.offset = Vector2.ZERO
	camera.zoom = Vector2.ONE * 0.65
	viewport.canvas_transform = Transform2D.IDENTITY
	_check(source._visible_keys(&"detail") == ["r05_c05"], "inactive logical camera does not borrow unrelated screen Canvas")
	print("[Volume tile visibility] cases=%d missing=%d extraneous=%d peak_visible=%d pass=%d fail=%d" % [cases, missing, extraneous, peak_visible, _pass, _fail])
	viewport.free()
	return _fail == 0


func _check(ok: bool, label: String) -> void:
	if ok:
		_pass += 1
	else:
		_fail += 1
		push_error("Volume tile visibility: " + label)
