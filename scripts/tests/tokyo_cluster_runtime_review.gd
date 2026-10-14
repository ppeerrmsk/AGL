extends RefCounted
## 真实连续R45加载器；急拉近截图冻结流送，证明原形无需新领取。
const Basemap := preload("res://scripts/tests/tokyo_lod_spatial_review.gd")
var _fail := 0


func run(owner: Node2D, expected: String = "R45") -> int:
	var overlay: Node = owner.features._tokyo_volume
	assert(overlay.debug_state().candidate == expected)
	var utility := Basemap.new()
	var records: Array[Dictionary] = []
	for pose: Array in [["mid", 0.98, 0.0], ["full", 1.3, 0.0], ["rotated", 1.65, deg_to_rad(14.0)],
			["counter_rotated", 1.65, deg_to_rad(-14.0)], ["instant", 5.0, 0.0],
			["near", 2.2, 0.0], ["close", 5.0, 0.0], ["return", 0.98, 0.0]]:
		var before: Dictionary = overlay.debug_state()
		owner.camera.position = Vector2(-5600, -2900)
		owner.camera.zoom = Vector2.ONE * float(pose[1])
		owner.camera.rotation = pose[2]
		owner.camera.force_update_scroll()
		var immediate: bool = pose[0] == "instant"
		if immediate:
			overlay._lod_clock = 10.0
			overlay._process(0.0)
			overlay._stream.set_process(false)
			var after: Dictionary = overlay.debug_state()
			_fail += int(after.cluster_active or after.instant_restores != int(before.instant_restores) + 1 or after.stream.started != before.stream.started)
			for batch: Dictionary in overlay._batches.values():
				_fail += int(batch.level != 5 or batch.nodes[0].mesh != batch.building.meshes[0] or batch.nodes[1].mesh != batch.building.meshes[1])
		else:
			_fail += int(not await _wait(owner, overlay))
			_fail += int(not await utility._wait_basemap(owner))
			await owner.get_tree().create_timer(0.3).timeout
		overlay._viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		for frame in 5:
			await RenderingServer.frame_post_draw
		var picture := owner.get_viewport().get_texture().get_image()
		var name_value := "tokyo_" + expected.to_lower() + "_" + String(pose[0]) + ".png"
		_fail += int(picture.save_png("res://bench/results/" + name_value) != OK)
		var state: Dictionary = overlay.debug_state()
		_fail += int(state.nodes > 48 or state.materials > 6 or state.active_cells > 16 or state.stream.peak_bytes > 96 * 1024 * 1024)
		_fail += int(state.triangles > 240000)
		records.append({"pose": pose[0], "zoom": pose[1], "rotation": pose[2], "image": name_value,
			"state": state, "load_frozen": immediate, "before": before if immediate else {}})
		print("[Tokyo cluster runtime Visual] pose=", pose[0], " triangles=", state.triangles,
			" pair=", state.cluster_active, " ready=", state.cut_ready, " bytes=", state.stream.bytes, " blocked=", state.transition_blocked)
		overlay._viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		if immediate:
			overlay._stream.set_process(true)
	var transition_failed: bool = overlay.peak_triangles > 240000
	_fail += int(transition_failed)
	var file := FileAccess.open("res://bench/results/tokyo_" + expected.to_lower() + "_review.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"candidate": expected, "continuous_lod": true, "fps_evidence": false, "fail": _fail,
		"transition_face_budget_failed": transition_failed, "records": records}, "\t"))
	file.close()
	print("[Tokyo cluster runtime Visual] captures=", records.size(), " fail=", _fail)
	return _fail


func _wait(owner: Node, overlay: Node) -> bool:
	await owner.get_tree().create_timer(0.2).timeout
	var deadline := Time.get_ticks_msec() + 15000
	while Time.get_ticks_msec() < deadline:
		var state: Dictionary = overlay.debug_state()
		if not state.transition_blocked.is_empty() or not state.stream.failures.is_empty():
			push_error("cluster runtime selection: " + str(state))
			return false
		if state.cut_ready and state.active_cells > 0 and state.stream.pending == 0:
			return true
		await owner.get_tree().process_frame
	push_error("cluster runtime timeout: " + str(overlay.debug_state()))
	return false
