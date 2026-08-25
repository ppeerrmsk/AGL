extends RefCounted

## 三图外缘空域 + 严格相机裁切回归（map-expansion §2.6）。

var _pass := 0
var _fail := 0


func run() -> void:
	print("\n════════ 三图外缘空域 / 边界倒计时 ════════")
	_test_geometry_and_camera_crop()
	_test_three_map_raster_coverage()
	_test_ai_extension_discipline()
	_test_boundary_ui_countdown()
	_test_countdown_cancel_latch_and_rearm()
	_test_freed_player_reference()
	print("──────── 结果：%d 通过 / %d 失败 ────────" % [_pass, _fail])


func _test_geometry_and_camera_crop() -> void:
	_check("真边界为 64km / ±16000px",
		is_equal_approx(MapBoundary.WORLD_SIZE_M, 64000.0)
			and is_equal_approx(MapBoundary.WORLD_HALF_PX, 16000.0),
		"half=%.0f" % MapBoundary.WORLD_HALF_PX)
	_check("旧 60km 边界成为 1000px 外缘入口",
		is_equal_approx(MapBoundary.CORE_HALF_PX, 15000.0)
			and is_equal_approx(MapBoundary.EXTENSION_WIDTH_PX, 1000.0),
		"core=%.0f width=%.0f" % [MapBoundary.CORE_HALF_PX, MapBoundary.EXTENSION_WIDTH_PX])
	_check("核心内不算外缘、入口线开始算外缘",
		not MapBoundary.is_in_extension_zone(Vector2(14999.0, 0.0))
			and MapBoundary.is_in_extension_zone(Vector2(15000.0, 0.0)),
		"entry distance %.0f/%.0f" % [
			MapBoundary.distance_to_extension_entry(Vector2(14999.0, 0.0)),
			MapBoundary.distance_to_extension_entry(Vector2(15000.0, 0.0))])
	var boundary := MapBoundary.new()
	var crop := boundary.get_camera_bounds()
	_check("相机裁切矩形严格内收 32px",
		is_equal_approx(crop.position.x, -15968.0)
			and is_equal_approx(crop.end.x, 15968.0)
			and crop.encloses(Rect2(-15000.0, -15000.0, 30000.0, 30000.0)),
		str(crop))
	boundary.free()


func _test_three_map_raster_coverage() -> void:
	var required_half := MapBoundary.WORLD_HALF_PX + MapBoundary.CAMERA_CONTENT_INSET_PX
	for entry in [
		["东京湾", "res://resources/maps/tokyo_bay_bg.json"],
		["沙漠铁路", "res://resources/maps/desert_railway_bg.json"],
		["海洋群岛", "res://resources/maps/ocean_islands_bg.json"],
	]:
		var file := FileAccess.open(entry[1], FileAccess.READ)
		var meta = JSON.parse_string(file.get_as_text()) if file != null else null
		if file != null:
			file.close()
		var covered := false
		var extents := Vector4.ZERO
		if meta is Dictionary:
			var bbox: Dictionary = meta.get("bbox_ll", {})
			var center: Array = meta.get("game_world_center_latlon", [])
			if center.size() >= 2:
				var ppm := float(meta.get("game_world_px_per_meter", 0.5))
				var m_lat := float(meta.get("game_world_meters_per_degree_lat", 111000.0))
				var m_lon := float(meta.get("game_world_meters_per_degree_lon_at_center", 111000.0))
				var x0 := (float(bbox.get("lon_min", 0.0)) - float(center[1])) * m_lon * ppm
				var x1 := (float(bbox.get("lon_max", 0.0)) - float(center[1])) * m_lon * ppm
				var y0 := -(float(bbox.get("lat_max", 0.0)) - float(center[0])) * m_lat * ppm
				var y1 := -(float(bbox.get("lat_min", 0.0)) - float(center[0])) * m_lat * ppm
				extents = Vector4(x0, y0, x1, y1)
				covered = x0 <= -required_half and y0 <= -required_half \
					and x1 >= required_half and y1 >= required_half
		_check("%s 栅格覆盖 64km 安全裁切" % entry[0], covered, str(extents.round()))
	for preview_path in [
		"res://resources/maps/desert_railway_preview.aglmap",
		"res://resources/maps/ocean_islands_preview.aglmap",
	]:
		var preview_file := FileAccess.open(preview_path, FileAccess.READ)
		var doc = JSON.parse_string(preview_file.get_as_text()) if preview_file != null else null
		if preview_file != null:
			preview_file.close()
		_check("内置 preview 文档登记 64km", doc is Dictionary
			and is_equal_approx(float(doc.get("world_size_m", 0.0)), 64000.0), preview_path)


func _test_ai_extension_discipline() -> void:
	var mode := Node2D.new()
	var player := Aircraft.new()
	player.team = CombatUnit.TEAM_PLAYER
	player.global_position = Vector2.ZERO
	mode.add_child(player)
	var enemy := Aircraft.new()
	enemy.team = CombatUnit.TEAM_HOSTILE
	mode.add_child(enemy)
	var ai := AIController.new()
	ai.aircraft = enemy
	enemy.add_child(ai)
	enemy._ai_ref = ai
	var spawner := SurvivorSpawner.new()
	spawner.mode = mode
	spawner.player_aircraft = player

	# AI 可以严谨进入扩充带：越过旧核心线后仍不应被旧边界逻辑赶走。
	enemy.global_position = Vector2(MapBoundary.CORE_HALF_PX + 500.0, 0.0)
	spawner._update_boundary_discipline(0.016)
	_check("普通 AI 可进入外缘扩充区", ai.waypoints.is_empty(),
		"edge=%.0fpx" % MapBoundary.distance_to_edge(enemy.global_position))

	# 只有抵达真实边界前 300px 才转向，目标必须指向地图内侧。
	enemy.global_position = Vector2(
		MapBoundary.WORLD_HALF_PX - MapBoundary.AI_EDGE_TURN_MARGIN_PX + 10.0, 0.0)
	spawner._update_boundary_discipline(0.016)
	_check("普通 AI 在真实边界转弯带内收", not ai.waypoints.is_empty()
			and ai.waypoints[0].x < enemy.global_position.x,
		"edge=%.0fpx" % MapBoundary.distance_to_edge(enemy.global_position))

	enemy.global_position = Vector2(MapBoundary.WORLD_HALF_PX + 10.0, 0.0)
	spawner._update_boundary_discipline(0.016)
	_check("普通 AI 越线当帧硬钳回图内",
		is_equal_approx(MapBoundary.distance_to_edge(enemy.global_position),
			SurvivorSpawner.BOUNDARY_HARD_CLAMP_MARGIN_PX),
		"edge=%.0fpx" % MapBoundary.distance_to_edge(enemy.global_position))

	mode.free()
	spawner.free()


func _test_boundary_ui_countdown() -> void:
	var ui := BoundaryUI.new()
	ui._ready()
	ui.on_countdown(true, 2.1)
	_check("倒计时三语资源可格式化", ui._warn_bg.visible
			and ui._warn_label.text.contains("3")
			and not ui._warn_label.text.contains("BOUNDARY_EXIT_COUNTDOWN"),
		ui._warn_label.text)
	ui.on_countdown(false, MapBoundary.EXIT_COUNTDOWN_S)
	_check("倒计时取消后提示条收起", not ui._warn_bg.visible,
		"return to core cleanup")
	ui.free()


func _test_countdown_cancel_latch_and_rearm() -> void:
	var boundary := MapBoundary.new()
	var probe := Node2D.new()
	var fired := [0]
	var countdown_updates: Array = []
	boundary.player = probe
	boundary.boundary_crossed.connect(func() -> void: fired[0] += 1)
	boundary.boundary_countdown.connect(func(active: bool, remaining: float) -> void:
		countdown_updates.append([active, remaining]))

	probe.position = Vector2(MapBoundary.CORE_HALF_PX + 10.0, 0.0)
	boundary._process(1.0)
	_check("进入外缘 1s 不立即触发", fired[0] == 0
			and is_equal_approx(boundary._countdown_remaining, 1.5),
		"remaining=%.2f" % boundary._countdown_remaining)

	probe.position = Vector2(MapBoundary.CORE_HALF_PX - 100.0, 0.0)
	boundary._process(0.1)
	_check("返回核心立即取消并重置",
		not boundary._in_extension
			and is_equal_approx(boundary._countdown_remaining, MapBoundary.EXIT_COUNTDOWN_S)
			and not countdown_updates.is_empty() and not bool(countdown_updates.back()[0]),
		"remaining=%.2f" % boundary._countdown_remaining)

	probe.position = Vector2(MapBoundary.CORE_HALF_PX + 10.0, 0.0)
	boundary._process(MapBoundary.EXIT_COUNTDOWN_S - 0.1)
	_check("倒计时耗尽前仍不触发", fired[0] == 0,
		"remaining=%.2f" % boundary._countdown_remaining)
	boundary._process(0.11)
	boundary._process(5.0)
	_check("耗尽后只触发一次并锁存", fired[0] == 1 and boundary._decision_latched,
		"events=%d" % fired[0])

	probe.position = Vector2(MapBoundary.CORE_HALF_PX - MapBoundary.RETURN_RESET_MARGIN_PX - 1.0, 0.0)
	boundary._process(0.1)
	probe.position = Vector2(MapBoundary.CORE_HALF_PX + 10.0, 0.0)
	boundary._process(MapBoundary.EXIT_COUNTDOWN_S)
	_check("回到核心后可重新武装下一次进入", fired[0] == 2,
		"events=%d" % fired[0])

	probe.free()
	boundary.free()


func _test_freed_player_reference() -> void:
	var boundary := MapBoundary.new()
	var probe := Node2D.new()
	var cancelled := [false]
	boundary.player = probe
	boundary.boundary_countdown.connect(func(active: bool, _remaining: float) -> void:
		if not active:
			cancelled[0] = true)
	probe.position = Vector2(MapBoundary.CORE_HALF_PX + 10.0, 0.0)
	boundary._process(0.1)
	probe.free()
	boundary._process(0.1)
	_check("玩家引用释放后取消倒计时并安全返回",
		cancelled[0] and not boundary._in_extension,
		"Variant 生命周期边界 + UI 清理")
	boundary.free()


func _check(label: String, condition: bool, detail: String) -> void:
	if condition:
		_pass += 1
		print("  ✓ %s — %s" % [label, detail])
	else:
		_fail += 1
		print("  ✗ %s — %s" % [label, detail])
