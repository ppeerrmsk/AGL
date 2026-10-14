extends RefCounted
const Layer := preload("res://scripts/experiments/tokyo_static_shadow.gd")
const Utility := preload("res://scripts/tests/tokyo_lod_spatial_review.gd")
const Pixels := preload("res://scripts/tests/tokyo_shell_review.gd")
var _fail := 0


func run(owner: Node2D, directory: String, output: String) -> int:
	if output.is_empty() or DirAccess.dir_exists_absolute(output):
		return 1
	DirAccess.make_dir_recursive_absolute(output)
	var overlay: Node = owner.features._tokyo_volume
	var utility := Utility.new()
	var records: Array[Dictionary] = []
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(directory.path_join("manifest.json")))
	var bounds: Array = manifest.bounds
	var center := Vector2((bounds[0]+bounds[2])*0.5, (bounds[1]+bounds[3])*0.5)
	var poses: Array = [[0.4, 0.0], [0.98, 0.0], [2.4, 0.0], [5.0, 0.0], [0.98, 14.0], [2.4, 14.0]]
	if OS.get_environment("AGL_TOKYO_STATIC_SHADOW_EXTENDED") == "1":
		poses.append_array([[0.98, -14.0], [2.4, -14.0], [0.98, 90.0], [2.4, 90.0]])
	for pose: Array in poses:
		owner.camera.position = center
		owner.camera.zoom = Vector2.ONE * float(pose[0])
		owner.camera.rotation = deg_to_rad(pose[1])
		owner.camera.force_update_scroll()
		await owner.get_tree().create_timer(0.3).timeout
		var state: Dictionary = overlay.debug_state()
		var deadline := Time.get_ticks_msec() + 15000
		while (state.ready_cells != state.desired_cells or state.ready_cells == 0 or state.stream.pending > 0) and Time.get_ticks_msec() < deadline:
			await owner.get_tree().process_frame
			state = overlay.debug_state()
		if state.ready_cells != state.desired_cells or state.ready_cells == 0 or not state.stream.failures.is_empty():
			return 1
		_fail += int(not await utility._wait_basemap(owner))
		overlay.set_process(false)
		var stem := output.path_join("z%03d_r%02d" % [roundi(pose[0]*100), roundi(pose[1])])
		var original: Image = await utility._capture(owner, overlay, stem + "_original.png")
		var materials: Array = overlay._materials.duplicate()
		var geometry := _geometry_state(overlay)
		var layer := Layer.new()
		if not layer.bind(overlay, directory, state.output_scale):
			return 1
		var direction: Array = layer.stats.direction
		var light: Vector3 = overlay._city.global_basis.inverse() * overlay._sun.global_basis.z
		var direction_error := Vector2(direction[0], direction[1]).distance_to(Vector2(-light.x/light.y, -light.z/light.y))
		if is_zero_approx(pose[1]):
			_fail += int(direction_error > 0.00001)
		for strength: float in [0.5, 0.7]:
			layer.set_strength(strength)
			await utility._capture(owner, overlay, stem + "_static_%02d.png" % roundi(strength*100))
		var b: Array = layer.stats.bounds
		var corners: Array = [[b[0],b[1]], [b[2],b[1]], [b[2],b[3]], [b[0],b[3]]]
		var masks := Pixels._screen_bounds(overlay, [{"original": corners, "candidate": [], "height_px": overlay._source_max_height}])
		var stats := layer.stats.duplicate(true)
		var geometry_unchanged := _geometry_state(overlay) == geometry
		_fail += int(not geometry_unchanged)
		layer.close()
		layer.close()
		_fail += int(overlay._materials != materials)
		_fail += int(_geometry_state(overlay) != geometry)
		var restored: Image = await utility._capture(owner, overlay, stem + "_restored.png")
		var error := Pixels._pixel_error(original, restored)
		_fail += int(error > 1)
		records.append({"stem": stem, "zoom": pose[0], "rotation": pose[1], "state": state,
			"shadow": stats, "restore_max": error, "allowed_screen_bounds": masks, "direction_error": direction_error,
			"geometry_unchanged": geometry_unchanged, "center": [center.x, center.y]})
		overlay._viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		overlay.set_process(true)
		print("[R59 static shadow Visual] zoom=", pose[0], " rotation=", pose[1], " texture=", stats["size"], " restored=", error)
	_fail += utility._fail
	# 真正跨帧释放owner后读取弱缓存，清理必须执行到底且可重入。
	var dead_owner := Node.new()
	owner.get_tree().root.add_child(dead_owner)
	var stale := Layer.new()
	stale._owner = weakref(dead_owner)
	dead_owner.queue_free()
	await owner.get_tree().process_frame
	stale.close()
	stale.close()
	_fail += int(stale._owner != null or stale._texture != null)
	var file := FileAccess.open(output.path_join("review.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"records": records, "fail": _fail, "dynamic_pass_removed": false, "fps_evidence": false}, "\t"))
	file.close()
	return _fail


func _geometry_state(overlay: Node) -> Array[Dictionary]:
	# 固定机位诊断，不进入帧时间采样；逐原生数组摘要验证而不只看贴图。
	var rows: Array[Dictionary] = []
	for batch: Dictionary in overlay._batches.values():
		for node: MeshInstance3D in batch.nodes:
			var surfaces: Array[int] = []
			for index in node.mesh.get_surface_count():
				surfaces.append(hash(node.mesh.surface_get_arrays(index)))
			rows.append({"node": node.get_instance_id(), "mesh": node.mesh.get_instance_id(),
				"arrays": surfaces, "transform": node.global_transform, "visible": node.visible})
	return rows
