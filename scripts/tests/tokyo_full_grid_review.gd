extends RefCounted
## 整图真实截图入口；暂停审美检查不授予连续巡航或实战帧时通过。
const Grid := preload("res://scripts/rendering/tokyo_full_grid_contract.gd")
const Review := preload("res://scripts/tests/tokyo_canonical_review.gd")


static func poses() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for y in 4:
		for x in 4:
			var center := Grid.BOUNDS.position + Vector2(x * 8000 + 4000, y * 8000 + 4000)
			for zoom: float in [0.08, 0.35, 0.98]:
				result.append({"kind":"root", "root":y * 4 + x, "center":center, "zoom":zoom, "rotation":0.0})
	# 全部24条根共边；每条三机位跨边并含旋转，不挑选已经好看的接缝。
	for axis in 2:
		for seam in range(1, 4):
			for segment in 4:
				var center := Grid.BOUNDS.position + (Vector2(seam * 8000, segment * 8000 + 4000) if axis == 0 else Vector2(segment * 8000 + 4000, seam * 8000))
				for offset: float in [-300.0, 0.0, 300.0]:
					result.append({"kind":"seam", "axis":axis, "seam":seam, "segment":segment,
						"center":center + (Vector2(offset, 0) if axis == 0 else Vector2(0, offset)), "zoom":0.35, "rotation":14.0 if offset == 0 else 0.0})
	result.append({"kind":"overview", "center":Grid.BOUNDS.get_center(), "zoom":0.02, "rotation":0.0})
	return result


static func checks() -> bool:
	var values := poses()
	var roots: Dictionary = {}
	var seams: Dictionary = {}
	for pose: Dictionary in values:
		if not Grid.BOUNDS.has_point(pose.center) or pose.zoom <= 0:
			return false
		if pose.kind == "root":
			roots[pose.root] = int(roots.get(pose.root, 0)) + 1
		elif pose.kind == "seam":
			var key := "%d/%d/%d" % [pose.axis, pose.seam, pose.segment]
			seams[key] = int(seams.get(key, 0)) + 1
	return values.size() == 121 and roots.size() == 16 and seams.size() == 24 and roots.values().count(3) == 16 and seams.values().count(3) == 24


static func run(battle: Node, map: Node, output: String) -> int:
	# 旧局部目录不能借此入口获得整图截图标签；不在头less下伪造画面。
	if DisplayServer.get_name() == "headless" or not checks():
		return 1
	var catalog: Variant = map.get("_canonical")
	if typeof(catalog) != TYPE_OBJECT or not is_instance_valid(catalog):
		return 1
	if catalog.schema_version != 2 or not catalog.valid():
		return 1
	var tree := battle.get_tree()
	var camera: Camera2D = battle.camera
	var source: Node = battle._map_features
	var previous := {"paused":tree.paused, "position":camera.position, "zoom":camera.zoom,
		"rotation":camera.rotation, "ignore":camera.ignore_rotation, "source_mode":source.process_mode}
	var signature := var_to_bytes(BuildingRenderer._cache_entries)
	tree.paused = true
	source.process_mode = Node.PROCESS_MODE_ALWAYS
	camera.ignore_rotation = false
	var rows: Array[Dictionary] = []
	var fail := 0
	for pose: Dictionary in poses():
		camera.position = pose.center
		camera.zoom = Vector2.ONE * pose.zoom
		camera.rotation = deg_to_rad(pose.rotation)
		camera.force_update_scroll()
		var deadline := Time.get_ticks_msec() + 15000
		var stable_since := 0
		var settled := false
		while Time.get_ticks_msec() < deadline:
			await RenderingServer.frame_post_draw
			if Review.ready_at_canvas(map._last_canvas, battle.get_viewport().get_canvas_transform(), map.debug_state()) and Review.source_ready(source):
				if stable_since == 0:
					stable_since = Time.get_ticks_msec()
				if Time.get_ticks_msec() - stable_since >= 200:
					settled = true
					break
			else:
				stable_since = 0
		var state: Dictionary = map.debug_state()
		var unchanged := signature == var_to_bytes(BuildingRenderer._cache_entries)
		var peak := int(state.get("max_transition_triangles", -1))
		fail += int(not settled or not unchanged or peak < 0 or peak > 240000)
		var name_value := "full_%03d_%s" % [rows.size(), pose.kind]
		fail += int(battle.get_viewport().get_texture().get_image().save_png(output.path_join(name_value + ".png")) != OK)
		fail += int(map._viewport.get_texture().get_image().save_png(output.path_join(name_value + "_native.png")) != OK)
		rows.append({"pose":pose, "settled":settled, "collision_unchanged":unchanged, "state":state})
		print("[Tokyo full review] pose=", rows.size(), "/121 settled=", settled, " fail=", fail)
	camera.position = previous.position
	camera.zoom = previous.zoom
	camera.rotation = previous.rotation
	camera.ignore_rotation = previous.ignore
	camera.force_update_scroll()
	source.process_mode = previous.source_mode
	tree.paused = previous.paused
	var file := FileAccess.open(output.path_join("full_grid_review.json"), FileAccess.WRITE)
	if file == null:
		return fail + 1
	file.store_string(JSON.stringify({"rows":rows, "fail":fail, "catalog_sha256":map._canonical_sha,
		"formal_route":true, "fps_evidence":false, "continuous_patrol_pass":false, "aesthetic_approved":false}, "\t"))
	file.close()
	return fail
