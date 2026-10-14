extends RefCounted
## 真实地图入口的连续多倍率流送预览；失败转换与后续冷启动恢复分开记录。
var _fail := 0


func run(owner: Node2D) -> int:
	var overlay: Node = owner.features._tokyo_volume
	assert(overlay.debug_state().candidate == "R41")
	var poses := [["north_city", Vector2(-5600, -2900), 2.2, 0.0],
		["north_close", Vector2(-5600, -2900), 5.0, deg_to_rad(14)],
		["industrial", Vector2(-4300, -2700), 2.2, 0.0],
		["seam", Vector2(-5300, -1700), 2.2, 0.0],
		["seam_rotated", Vector2(-5300, -1700), 2.2, deg_to_rad(14)],
		["yokohama", Vector2(-5300, -700), 2.2, 0.0],
		["housing", Vector2(-6110, -350), 5.0, 0.0],
		["piers", Vector2(-5150, -480), 5.0, 0.0],
		["piers_mid", Vector2(-5150, -480), 2.2, 0.0],
		["piers_rotated", Vector2(-5150, -480), 5.0, deg_to_rad(14)],
		["piers_close", Vector2(-5150, -480), 10.0, 0.0]]
	for zoom_value: float in [0.98, 0.52, 0.26, 0.13, 0.06, 2.2]:
		poses.append(["north_%03d" % roundi(zoom_value * 100), Vector2(-5600, -2900), zoom_value, 0.0])
	var records: Array[Dictionary] = []
	var first_picture: Image
	var restored_error := -1
	var budget_failures: Array[String] = []
	for pose: Array in poses:
		owner.camera.position = pose[1]
		owner.camera.zoom = Vector2.ONE * float(pose[2])
		owner.camera.rotation = pose[3]
		owner.camera.force_update_scroll()
		var started := Time.get_ticks_msec()
		await owner.get_tree().create_timer(0.2).timeout
		var settled := await _wait(owner, overlay)
		var transition: Dictionary = overlay.debug_state()
		var transition_ms := Time.get_ticks_msec() - started
		if not settled:
			_fail += 1
			# 保留失败证据后才单独冷启动，不能把它算成连续转换成功。
			overlay.set_enabled(false)
			overlay.set_enabled(true)
			await owner.get_tree().create_timer(0.2).timeout
			settled = await _wait(owner, overlay)
		await owner.get_tree().create_timer(0.5).timeout
		await RenderingServer.frame_post_draw
		var state: Dictionary = overlay.debug_state()
		var file_name := "tokyo_r41_" + String(pose[0]) + ".png"
		var picture := owner.get_viewport().get_texture().get_image()
		if pose[0] == "north_city":
			first_picture = picture
		elif pose[0] == "north_220":
			restored_error = preload("res://scripts/tests/tokyo_shell_review.gd")._pixel_error(first_picture, picture)
			_fail += int(restored_error > 1)
		if state.triangles > 240000:
			budget_failures.append(String(pose[0]))
			_fail += 1
		_fail += int(picture.save_png("res://bench/results/" + file_name) != OK)
		_fail += int(not settled or state.nodes > 48 or state.materials > 6 or state.active_cells > 16 or state.stream.peak_bytes > 96 * 1024 * 1024)
		records.append({"pose": pose[0], "zoom": pose[2], "rotation": pose[3], "file": file_name,
			"transition_ms": transition_ms, "transition": transition, "captured": state})
		print("[Tokyo hierarchy Visual] pose=", pose[0], " ready=", state.cut_ready, " faces=", state.triangles, " union=", transition.union_bytes, " blocked=", transition.transition_blocked)
	var file := FileAccess.open("res://bench/results/tokyo_r41_review.json", FileAccess.WRITE)
	var peak_failed := int(overlay.debug_state().max_transition_triangles) > 240000
	_fail += int(peak_failed)
	file.store_string(JSON.stringify({"candidate": "R41", "fail": _fail, "records": records, "fps_evidence": false,
		"geometry_budget_failures": budget_failures, "transition_peak_failed": peak_failed, "restored_max_channel_error": restored_error}, "\t"))
	file.close()
	print("[Tokyo hierarchy Visual] captures=", records.size(), " fail=", _fail)
	return _fail


func _wait(owner: Node, overlay: Node) -> bool:
	var deadline := Time.get_ticks_msec() + 10000
	while Time.get_ticks_msec() < deadline:
		var state: Dictionary = overlay.debug_state()
		if not state.transition_blocked.is_empty() or not state.stream.failures.is_empty():
			return false
		if state.cut_ready and state.active_cells > 0 and state.stream.pending == 0:
			return true
		await owner.get_tree().process_frame
	return false
