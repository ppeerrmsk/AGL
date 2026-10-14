extends RefCounted
const Select := preload("res://scripts/experiments/tokyo_spatial_select.gd")
const Pixels := preload("res://scripts/tests/tokyo_shell_review.gd")
var _fail := 0


func run(owner: Node2D) -> int:
	var overlay: Node = owner.features._tokyo_volume
	assert(overlay.debug_state().candidate == "R42")
	var poses := [["north_mid", Vector2(-5600, -2900), 0.98, 0.0],
		["north_full", Vector2(-5600, -2900), 1.3, 0.0],
		["north_full_rotated", Vector2(-5600, -2900), 1.65, deg_to_rad(14)],
		["industrial_mid", Vector2(-4300, -2700), 0.98, 0.0],
		["industrial_full", Vector2(-4300, -2700), 1.3, 0.0],
		["yokohama_mid", Vector2(-5300, -700), 0.98, 0.0],
		["yokohama_full", Vector2(-5300, -700), 1.3, 0.0],
		["seam_mid_rotated", Vector2(-5300, -1700), 0.98, deg_to_rad(14)],
		["seam_full_rotated", Vector2(-5300, -1700), 1.3, deg_to_rad(-14)],
		["piers_full", Vector2(-5150, -480), 1.3, 0.0],
		["north_close", Vector2(-5600, -2900), 2.2, 0.0],
		["piers_close", Vector2(-5150, -480), 5.0, 0.0],
		["north_far", Vector2(-5600, -2900), 0.26, 0.0],
		["north_distant", Vector2(-5600, -2900), 0.06, 0.0],
		["north_return", Vector2(-5600, -2900), 0.98, 0.0]]
	var records: Array[Dictionary] = []
	if OS.get_environment("AGL_TOKYO_LOD_SPATIAL_PROBE") == "1":
		poses = [["piers_full", Vector2(-5150, -480), 1.3, 0.0]]
	for pose: Array in poses:
		owner.camera.position = pose[1]
		owner.camera.zoom = Vector2.ONE * float(pose[2])
		owner.camera.rotation = pose[3]
		owner.camera.force_update_scroll()
		await owner.get_tree().create_timer(0.2).timeout
		var deadline := Time.get_ticks_msec() + 10000
		var state: Dictionary = overlay.debug_state()
		while (not state.cut_ready or state.active_cells == 0 or state.stream.pending > 0) and Time.get_ticks_msec() < deadline and state.transition_blocked.is_empty():
			await owner.get_tree().process_frame
			state = overlay.debug_state()
		if not state.cut_ready or not state.stream.failures.is_empty():
			_fail += 1
			push_warning("R42 incomplete cut: " + str(state))
			continue
		var stem := "res://bench/results/tokyo_r42_" + String(pose[0])
		_fail += int(not await _wait_basemap(owner))
		await owner.get_tree().create_timer(0.5).timeout
		overlay.set_process(false)
		if OS.get_environment("AGL_TOKYO_NO_SHADOW_REVIEW") == "1":
			for nodes: Array in overlay._slots:
				for node: MeshInstance3D in nodes:
					node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var candidate: Image = await _capture(owner, overlay, stem + "_candidate.png")
		if OS.get_environment("AGL_TOKYO_LOD_SPATIAL_PROBE") == "1":
			preload("res://scripts/tests/tokyo_lod_spatial_probe.gd").capture(overlay, "candidate")
		var record := {"pose": pose[0], "zoom": pose[2], "state": state, "pixel_error": -1, "restore_error": -1,
			"reference_faces": 0, "reference_extra_bytes": 0, "file": stem + "_candidate.png"}
		if int(state.level) == 4:
			var reference := await _reference(owner, overlay, stem, candidate)
			record.merge(reference, true)
		_fail += int(state.triangles > 240000 or state.nodes > 48 or state.materials > 6 or state.stream.peak_bytes > 96 * 1024 * 1024)
		overlay._viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		overlay.set_process(true)
		records.append(record)
		print("[Tokyo LOD spatial Visual] pose=", pose[0], " level=", state.level, " faces=", state.triangles,
			" original=", record.reference_faces, " pixels=", record.pixel_error, " restored=", record.restore_error)
	var peak_failed := int(overlay.debug_state().max_transition_triangles) > 240000
	_fail += int(peak_failed)
	var file := FileAccess.open("res://bench/results/tokyo_r42_review.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"candidate": "R42", "fail": _fail, "transition_peak_failed": peak_failed, "records": records, "fps_evidence": false}, "\t"))
	file.close()
	print("[Tokyo LOD spatial Visual] captures=", records.size(), " fail=", _fail)
	return _fail


func _reference(owner: Node2D, overlay: Node, stem: String, candidate: Image) -> Dictionary:
	var catalog: Resource = overlay._lod_catalogs["mid" if overlay._relief_active else "full"]
	var inverse: Basis = overlay._city.basis.inverse()
	var camera_ray: Vector3 = inverse * overlay._camera.basis.z
	var light_ray: Vector3 = inverse * overlay._sun.basis.z
	var logical: Vector2 = Vector2(overlay._viewport.size) * overlay._screen.scale
	var parents: Array[Dictionary] = []
	var extra_paths := PackedStringArray()
	var extra_bytes := 0
	var faces := 0
	for parent: Dictionary in catalog.parents:
		var entry := Select.visible(parent, overlay._cull_view, overlay._last_canvas, logical,
			-Vector2(camera_ray.x, camera_ray.z) / camera_ray.y, -Vector2(light_ray.x, light_ray.z) / light_ray.y)
		if entry.faces == 0:
			continue
		parents.append(entry)
		faces += int(entry.faces)
		for path: String in [entry.building, entry.fixed]:
			if overlay._stream.resource(path) == null and path not in extra_paths:
				extra_paths.append(path)
				extra_bytes += int(overlay._descriptors[path].bytes)
	var resident := int(overlay._stream.summary().bytes) + int(overlay._stream.summary().reserved_bytes) + extra_bytes
	if resident > 96 * 1024 * 1024:
		_fail += 1
		return {"reference_faces": faces, "reference_extra_bytes": extra_bytes, "reference_blocked": true}
	var resources: Dictionary = {}
	for path: String in extra_paths:
		resources[path] = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
	var saved: Array[Dictionary] = []
	for nodes: Array in overlay._slots:
		for node: MeshInstance3D in nodes:
			saved.append({"node": node, "mesh": node.mesh, "visible": node.visible, "cast": node.cast_shadow})
			node.hide()
	for n in parents.size():
		var entry: Dictionary = parents[n]
		var building: Resource = resources.get(entry.building, overlay._stream.resource(entry.building))
		var fixed: Resource = resources.get(entry.fixed, overlay._stream.resource(entry.fixed))
		for kind in 3:
			var node: MeshInstance3D = overlay._slots[n][kind]
			node.mesh = fixed.meshes[0] if kind == 2 else building.meshes[kind]
			node.visible = entry.mask[kind]
			node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if kind < 2 else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			if OS.get_environment("AGL_TOKYO_NO_SHADOW_REVIEW") == "1":
				node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var original: Image = await _capture(owner, overlay, stem + "_original.png")
	if OS.get_environment("AGL_TOKYO_LOD_SPATIAL_PROBE") == "1":
		preload("res://scripts/tests/tokyo_lod_spatial_probe.gd").capture(overlay, "original")
	for entry: Dictionary in saved:
		entry.node.mesh = entry.mesh
		entry.node.visible = entry.visible
		entry.node.cast_shadow = entry.cast
	var restored: Image = await _capture(owner, overlay, stem + "_restored.png")
	var error := Pixels._pixel_error(original, candidate)
	var restore_error := Pixels._pixel_error(restored, candidate)
	_fail += int(error > 1 or restore_error > 1)
	return {"pixel_error": error, "restore_error": restore_error, "reference_faces": faces, "reference_extra_bytes": extra_bytes, "reference_resident_bytes": resident}


func _capture(owner: Node2D, overlay: Node, path: String) -> Image:
	overlay._viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	for frame in 5:
		await RenderingServer.frame_post_draw
	var picture := owner.get_viewport().get_texture().get_image()
	_fail += int(picture.save_png(path) != OK)
	return picture


func _wait_basemap(owner: Node2D) -> bool:
	var renderer: Variant = owner.features._raster_basemap
	if typeof(renderer) != TYPE_OBJECT or not is_instance_valid(renderer):
		return false
	var deadline := Time.get_ticks_msec() + 10000
	while Time.get_ticks_msec() < deadline:
		var state: Dictionary = renderer.debug_state()
		var stable: bool = state.current_lod == state.target_lod and not state.transitioning and state.pending_count == 0 and state.missing_keys.is_empty()
		for tile: Dictionary in renderer.presentation_tiles():
			var sprite: Variant = tile.sprite.get_ref()
			if typeof(sprite) == TYPE_OBJECT and is_instance_valid(sprite) and sprite.is_visible_in_tree() and sprite.modulate.a < 0.999999:
				stable = false
		if stable:
			return true
		await owner.get_tree().process_frame
	return false
