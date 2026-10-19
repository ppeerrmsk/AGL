extends "res://scripts/tests/tokyo_volume_visual_runner.gd"
## 走真实 MapFeatureRenderer/Camera2D/原生合成的 R7 异步检查，不使用静态观察场同步加载。


func _ready() -> void:
	camera.ignore_rotation = false
	var previous := OS.get_environment("AGL_TOKYO_VOLUME")
	OS.set_environment("AGL_TOKYO_VOLUME", "cells")
	super._ready()
	OS.set_environment("AGL_TOKYO_VOLUME", previous)


func _capture_sequence() -> void:
	if OS.get_environment("AGL_TOKYO_STATIC_SHADOW") != "":
		var script: Script = load("res://scripts/tests/tokyo_static_shadow_review.gd")
		if script == null or not script.can_instantiate():
			get_tree().quit(1)
			return
		_fail += await script.new().run(self, OS.get_environment("AGL_TOKYO_STATIC_SHADOW"), OS.get_environment("AGL_TOKYO_STATIC_SHADOW_OUT"))
		get_tree().quit(1 if _fail else 0)
		return
	if OS.get_environment("AGL_TOKYO_FAR_CLUSTER_REVIEW") != "":
		var script: Script = load("res://scripts/tests/tokyo_far_cluster_review.gd")
		if script == null or not script.can_instantiate():
			get_tree().quit(1)
			return
		_fail += await script.new().run(self, OS.get_environment("AGL_TOKYO_FAR_CLUSTER_REVIEW"), OS.get_environment("AGL_TOKYO_FAR_CLUSTER_REVIEW_OUT"))
		get_tree().quit(1 if _fail else 0)
		return
	if OS.get_environment("AGL_TOKYO_GROUND_MERGE_REVIEW") != "":
		var ground: Script = load("res://scripts/tests/tokyo_ground_merge_review.gd")
		if ground == null or not ground.can_instantiate():
			get_tree().quit(1)
			return
		_fail += await ground.new().run(self, OS.get_environment("AGL_TOKYO_GROUND_MERGE_REVIEW"))
		get_tree().quit(1 if _fail else 0)
		return
	if OS.get_environment("AGL_TOKYO_CELLS_VARIANT") in ["yokohama_cluster_hierarchy", "yokohama_cluster_stable"]:
		var runtime_script: Script = load("res://scripts/tests/tokyo_cluster_runtime_review.gd")
		if runtime_script == null or not runtime_script.can_instantiate():
			get_tree().quit(1)
			return
		var expected := "R46" if OS.get_environment("AGL_TOKYO_CELLS_VARIANT") == "yokohama_cluster_stable" else "R45"
		_fail += await runtime_script.new().run(self, expected)
		get_tree().quit(1 if _fail else 0)
		return
	if OS.get_environment("AGL_TOKYO_CLUSTER_REVIEW") == "1":
		var cluster_script: Script = load("res://scripts/tests/tokyo_cluster_review.gd")
		if cluster_script == null or not cluster_script.can_instantiate():
			get_tree().quit(1)
			return
		_fail += await cluster_script.new().run(self)
		get_tree().quit(1 if _fail else 0)
		return
	if OS.get_environment("AGL_TOKYO_CELLS_VARIANT") == "yokohama_joined_lod_hierarchy":
		var lod_script: Script = load("res://scripts/tests/tokyo_lod_spatial_review.gd")
		if lod_script == null or not lod_script.can_instantiate():
			get_tree().quit(1)
			return
		_fail += await lod_script.new().run(self)
		get_tree().quit(1 if _fail else 0)
		return
	if OS.get_environment("AGL_TOKYO_CELLS_VARIANT") == "yokohama_joined_hierarchy":
		var hierarchy_script: Script = load("res://scripts/tests/tokyo_hierarchical_review.gd")
		if hierarchy_script == null or not hierarchy_script.can_instantiate():
			get_tree().quit(1)
			return
		_fail += await hierarchy_script.new().run(self)
		get_tree().quit(1 if _fail else 0)
		return
	if OS.get_environment("AGL_TOKYO_SPATIAL_REVIEW") == "1":
		var review_script: Script = load("res://scripts/tests/tokyo_spatial_review.gd")
		if review_script == null or not review_script.can_instantiate():
			get_tree().quit(1)
			return
		var review: RefCounted = review_script.new()
		_fail += await review.run(self)
		get_tree().quit(1 if _fail else 0)
		return
	if not OS.get_environment("AGL_TOKYO_SHELL_REVIEW").is_empty():
		var review: RefCounted = load("res://scripts/tests/tokyo_shell_review.gd").new()
		_fail += await review.run(self)
		get_tree().quit(1 if _fail else 0)
		return
	var prefix := "tokyo_r8_" if OS.get_environment("AGL_TOKYO_CELLS_VARIANT") == "relief" else "tokyo_r7_"
	var records: Array[Dictionary] = []
	var places: Array = []
	for zoom_value: float in [0.06, 0.13, 0.26, 0.52, 0.98, 2.2, 5.0]:
		places.append(["shimbashi_%03d" % roundi(zoom_value * 100), Vector2(-30, -12550), zoom_value, 0.0])
	places.append_array([["station", Vector2(330, -13420), 2.2, 0.0], ["waterfront", Vector2(300, -12200), 2.2, 0.0],
		["seam_rotated", Vector2(95, -12730), 2.2, deg_to_rad(14.0)]])
	var yokohama := OS.get_environment("AGL_TOKYO_CELLS_VARIANT").begins_with("yokohama") or OS.get_environment("AGL_TOKYO_CELLS_VARIANT").begins_with("kawasaki")
	if yokohama:
		prefix = "tokyo_r9_"
		if OS.get_environment("AGL_TOKYO_CELLS_VARIANT") == "yokohama_color":
			prefix = "tokyo_r9c_"
		if OS.get_environment("AGL_TOKYO_CELLS_VARIANT") == "yokohama_roofs":
			prefix = "tokyo_r10_"
		if OS.get_environment("AGL_TOKYO_CELLS_VARIANT") == "yokohama_cull":
			prefix = "tokyo_r11_"
		if OS.get_environment("AGL_TOKYO_CELLS_VARIANT") == "yokohama_mid":
			prefix = "tokyo_r11b_"
		if OS.get_environment("AGL_TOKYO_CELLS_VARIANT") == "yokohama_directional":
			prefix = "tokyo_r12_"
		if OS.get_environment("AGL_TOKYO_CELLS_VARIANT") == "yokohama_adaptive":
			prefix = "tokyo_r13_"
		if OS.get_environment("AGL_TOKYO_CELLS_VARIANT") == "yokohama_frustum":
			prefix = "tokyo_r14_"
		if OS.get_environment("AGL_TOKYO_CELLS_VARIANT") == "yokohama_coverage":
			prefix = "tokyo_r15_"
		if OS.get_environment("AGL_TOKYO_CELLS_VARIANT") == "yokohama_coverage_b":
			prefix = "tokyo_r15b_"
		if OS.get_environment("AGL_TOKYO_CELLS_VARIANT") == "yokohama_coverage_c":
			prefix = "tokyo_r15c_"
		if OS.get_environment("AGL_TOKYO_CELLS_VARIANT") == "yokohama_domes":
			prefix = "tokyo_r17_"
		if OS.get_environment("AGL_TOKYO_CELLS_VARIANT") == "yokohama_domes_b":
			prefix = "tokyo_r17b_"
		if OS.get_environment("AGL_TOKYO_CELLS_VARIANT") == "yokohama_shadow_depth":
			prefix = "tokyo_r18_"
		if OS.get_environment("AGL_TOKYO_CELLS_VARIANT") == "yokohama_dedup":
			prefix = "tokyo_r19_"
		places.clear()
		for zoom_value: float in [0.06, 0.13, 0.26, 0.52, 0.98, 2.2, 5.0]:
			places.append(["yokohama_%03d" % roundi(zoom_value * 100), Vector2(-5300, -700), zoom_value, 0.0])
		places.append_array([["port", Vector2(-5000, -650), 2.2, 0.0],
			["seam_rotated", Vector2(-5300, -700), 2.2, deg_to_rad(14.0)]])
		if OS.get_environment("AGL_TOKYO_CELLS_VARIANT") in ["yokohama_roofs", "yokohama_cull", "yokohama_mid", "yokohama_directional", "yokohama_adaptive", "yokohama_frustum", "yokohama_coverage", "yokohama_coverage_b", "yokohama_coverage_c"]:
			places.append(["warehouse_close", Vector2(-5290, -715), 8.0, 0.0])
		if OS.get_environment("AGL_TOKYO_CELLS_VARIANT") in ["yokohama_roofs", "yokohama_mid", "yokohama_directional", "yokohama_adaptive", "yokohama_frustum", "yokohama_coverage", "yokohama_coverage_b", "yokohama_coverage_c"]:
			places.append_array([["mid_before", Vector2(-5300, -700), 1.15, 0.0],
				["mid_after", Vector2(-5300, -700), 1.25, 0.0],
				["mid_return", Vector2(-5300, -700), 1.15, 0.0],
				["low_close", Vector2(-6050, -350), 5.0, 0.0]])
		if OS.get_environment("AGL_TOKYO_CELLS_VARIANT").begins_with("yokohama_domes") or OS.get_environment("AGL_TOKYO_CELLS_VARIANT") in ["yokohama_shadow_depth", "yokohama_dedup"]:
			places.append_array([["warehouse_close", Vector2(-5290, -715), 8.0, 0.0],
				["mid_before", Vector2(-5300, -700), 1.15, 0.0], ["mid_after", Vector2(-5300, -700), 1.25, 0.0],
				["mid_return", Vector2(-5300, -700), 1.15, 0.0], ["low_close", Vector2(-6050, -350), 5.0, 0.0]])
		if OS.get_environment("AGL_TOKYO_CELLS_VARIANT").begins_with("yokohama_domes") or OS.get_environment("AGL_TOKYO_CELLS_VARIANT") in ["yokohama_shadow_depth", "yokohama_dedup"] or OS.get_environment("AGL_TOKYO_DOME_REVIEW") == "1":
			if OS.get_environment("AGL_TOKYO_DOME_REVIEW") == "1":
				places.clear()
			places.append_array([["queen_dome", Vector2(-5316, -520), 16.0, 0.0],
				["museum_dome", Vector2(-5581, -512), 12.0, deg_to_rad(14.0)],
				["unresolved_dome", Vector2(-5950, -879), 6.0, 0.0]])
	if OS.get_environment("AGL_TOKYO_CELLS_VARIANT").begins_with("kawasaki"):
		prefix = "tokyo_r21_" if OS.get_environment("AGL_TOKYO_CELLS_VARIANT") == "kawasaki_strokes" else "tokyo_r20_"
		if OS.get_environment("AGL_TOKYO_CELLS_VARIANT") == "kawasaki_lod":
			prefix = "tokyo_r22_"
		places.clear()
		for zoom_value: float in [0.06, 0.13, 0.26, 0.52, 0.98, 2.2, 5.0]:
			places.append(["north_%03d" % roundi(zoom_value * 100), Vector2(-4300, -2700), zoom_value, 0.0])
		places.append_array([["boundary", Vector2(-5300, -1700), 0.98, 0.0],
			["rotated", Vector2(-4300, -2700), 2.2, deg_to_rad(14)],
			["west_city", Vector2(-5600, -2900), 2.2, 0.0],
			["east_port", Vector2(-2800, -2800), 2.2, 0.0]])
	if OS.get_environment("AGL_TOKYO_SHADOW_REVIEW") == "1":
		prefix += "shadow_"
		places = [["warehouse", Vector2(-5290, -715), 8.0, 0.0], ["queen", Vector2(-5316, -520), 16.0, 0.0],
			["museum", Vector2(-5581, -512), 12.0, deg_to_rad(14.0)], ["low", Vector2(-6050, -350), 5.0, 0.0],
			["rotated", Vector2(-5300, -700), 2.2, deg_to_rad(14.0)], ["far", Vector2(-5300, -700), 0.06, 0.0]]
	if OS.get_environment("AGL_TOKYO_DUPLICATE_REVIEW") == "1":
		prefix += "duplicate_"
		places = [["close", Vector2(-5380, -560), 10.0, deg_to_rad(14)],
			["mid", Vector2(-5380, -560), 2.2, 0.0], ["far", Vector2(-5380, -560), 0.26, 0.0]]
	if OS.get_environment("AGL_TOKYO_CELLS_VARIANT") in ["kawasaki_strokes", "kawasaki_lod"]:
		places.append_array([["guard_far", Vector2(-4300, -2700), 0.06, 0.0],
			["guard_jump", Vector2(-4300, -2700), 5.0, 0.0]])
	if OS.get_environment("AGL_TOKYO_CELLS_VARIANT") in ["yokohama_joined", "yokohama_joined_depth", "yokohama_joined_indexed", "yokohama_joined_spatial", "yokohama_joined_area", "yokohama_joined_palette", "yokohama_joined_coastal"]:
		prefix = "tokyo_r27_" if OS.get_environment("AGL_TOKYO_CELLS_VARIANT") == "yokohama_joined_depth" else "tokyo_r26_"
		if OS.get_environment("AGL_TOKYO_CELLS_VARIANT") == "yokohama_joined_indexed":
			prefix = "tokyo_r28_"
		if OS.get_environment("AGL_TOKYO_CELLS_VARIANT") == "yokohama_joined_spatial":
			prefix = "tokyo_r29_"
		if OS.get_environment("AGL_TOKYO_CELLS_VARIANT") == "yokohama_joined_area":
			prefix = "tokyo_r30_"
		if OS.get_environment("AGL_TOKYO_CELLS_VARIANT") == "yokohama_joined_palette":
			prefix = "tokyo_r32_"
		if OS.get_environment("AGL_TOKYO_CELLS_VARIANT") == "yokohama_joined_coastal":
			prefix = "tokyo_r34_"
		places.clear()
		for zoom_value: float in [0.06, 0.13, 0.26, 0.52, 0.98, 2.2, 5.0]:
			places.append(["joint_%03d" % roundi(zoom_value * 100), Vector2(-5300, -1700), zoom_value, 0.0])
		places.append_array([["north_city", Vector2(-5600, -2900), 2.2, 0.0],
			["yokohama_port", Vector2(-5300, -700), 2.2, 0.0], ["seam_rotated", Vector2(-5300, -1700), 2.2, deg_to_rad(14)],
			["unmade_corner", Vector2(-3000, -650), 2.2, 0.0]])
	if OS.get_environment("AGL_TOKYO_COASTAL_REVIEW") == "1":
		prefix = "tokyo_r34_" if OS.get_environment("AGL_TOKYO_CELLS_VARIANT") == "yokohama_joined_coastal" else "tokyo_r34_control_"
		for location: Array in [["piers", Vector2(-5150, -480)], ["breakwater", Vector2(-4600, -1200)], ["north_piers", Vector2(-4160, -2160)]]:
			for scale_value: float in [0.26, 0.98, 2.2, 5.0]:
				places.append(["%s_%03d" % [location[0], roundi(scale_value * 100)], location[1], scale_value, 0.0])
		places.append(["piers_rotated", Vector2(-5150, -480), 5.0, deg_to_rad(14)])
	if OS.get_environment("AGL_TOKYO_GROUND_REVIEW") == "1":
		prefix = "tokyo_r31_probe_"
	for place: Array in places:
		if place[0] == "guard_jump":
			# 上一张瓦片基线关闭地图时会释放原生包，先在原远景机位重新真实加载，不能冻结空场。
			await get_tree().create_timer(0.2).timeout
			var guard_deadline := Time.get_ticks_msec() + 15000
			var guard_state: Dictionary = features._tokyo_volume.debug_state()
			while (guard_state.desired_cells == 0 or guard_state.ready_cells != guard_state.desired_cells \
					or guard_state.stream.pending > 0) and Time.get_ticks_msec() < guard_deadline:
				await get_tree().process_frame
				guard_state = features._tokyo_volume.debug_state()
			_fail += int(guard_state.level != 0 or guard_state.desired_cells == 0 or guard_state.ready_cells != guard_state.desired_cells)
			features._tokyo_volume._lod_clock = 1000.0
		camera.position = place[1]
		camera.zoom = Vector2.ONE * float(place[2])
		camera.rotation = place[3]
		camera.force_update_scroll()
		await get_tree().create_timer(1.0).timeout
		var deadline := Time.get_ticks_msec() + 15000
		var state: Dictionary = features._tokyo_volume.debug_state()
		var expects_empty: bool = place[0] == "unmade_corner"
		while (state.ready_cells != state.desired_cells or (state.desired_cells == 0 and not expects_empty) or state.stream.pending > 0) and Time.get_ticks_msec() < deadline:
			await get_tree().process_frame
			state = features._tokyo_volume.debug_state()
		if (not expects_empty and (not state.active or state.desired_cells == 0)) or state.ready_cells != state.desired_cells \
				or state.stream.pending > 0 or not state.stream.failures.is_empty():
			_fail += 1
		if expects_empty:
			_fail += int(state.ready_cells != 0 or state.triangles != 0)
		await get_tree().create_timer(1.0).timeout
		await RenderingServer.frame_post_draw
		var image := get_viewport().get_texture().get_image()
		var file_name := prefix + String(place[0]) + ".png"
		_fail += int(image.save_png("res://bench/results/" + file_name) != OK)
		state = features._tokyo_volume.debug_state()
		if place[0] == "guard_jump" and OS.get_environment("AGL_TOKYO_CELLS_VARIANT") == "kawasaki_lod":
			_fail += int(state.level != 0 or state.precision_guarded == 0)
		state["file"] = file_name
		state["zoom"] = place[2]
		state["rotation"] = place[3]
		records.append(state)
		if OS.get_environment("AGL_TOKYO_SHADOW_REVIEW") == "1":
			_fail += await preload("res://scripts/tests/tokyo_ground_review.gd").shadowless(
				features._tokyo_volume, get_viewport(), "res://bench/results/" + file_name.replace(".png", "_unshadowed.png"))
		if OS.get_environment("AGL_TOKYO_GROUND_REVIEW") == "1":
			_fail += await preload("res://scripts/tests/tokyo_ground_review.gd").capture(
				features._tokyo_volume, get_viewport(), "res://bench/results/" + prefix + String(place[0]))
		if OS.get_environment("AGL_TOKYO_CELLS_VARIANT") == "yokohama_joined_palette":
			_fail += await preload("res://scripts/tests/tokyo_ground_review.gd").palette_reference(
				features._tokyo_volume, get_viewport(), "res://bench/results/" + prefix + String(place[0]))
		if yokohama:
			features._tokyo_volume.set_enabled(false)
			await get_tree().create_timer(0.5).timeout
			await RenderingServer.frame_post_draw
			var baseline := get_viewport().get_texture().get_image()
			if expects_empty:
				_fail += int(image.get_region(Rect2i(300, 200, 1000, 500)).get_data() != baseline.get_region(Rect2i(300, 200, 1000, 500)).get_data())
			_fail += int(baseline.save_png("res://bench/results/" + prefix + String(place[0]) + "_baseline.png") != OK)
			features._tokyo_volume.set_enabled(true)
	var file := FileAccess.open("res://bench/results/" + prefix + "runtime_manifest.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"candidate": true, "fail": _fail, "records": records}, "\t"))
	file.close()
	print("[Tokyo cells runtime Visual] output=", prefix, " captures=", records.size(), " fail=", _fail)
	get_tree().quit(1 if _fail else 0)
