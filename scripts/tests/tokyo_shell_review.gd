extends RefCounted
## R37单块中近景几何试验：同场景替换/恢复，不进入正式归档或运行时LOD。
const Builder := preload("res://scripts/tests/build_tokyo_cells.gd")
const Factory := preload("res://scripts/experiments/tokyo_volume_preview_factory.gd")
const Geometry := preload("res://scripts/experiments/volume_mesh_factory.gd")
const Indexed := preload("res://scripts/experiments/tokyo_indexed_mesh.gd")
const Palette := preload("res://scripts/experiments/tokyo_palette.gd")
const Signature := preload("res://scripts/tests/tokyo_mesh_signature.gd")
const Duplicates := preload("res://scripts/experiments/tokyo_duplicate_outline.gd")
const GroundReview := preload("res://scripts/tests/tokyo_ground_review.gd")
const SCALES := preload("res://scripts/rendering/tokyo_volume_archive.gd").SCALES
var _records: Dictionary = {}
var _suppressed: Dictionary = {}
var _cache: Dictionary = {}
var _fail := 0


func run(owner: Node2D) -> int:
	assert(OS.get_environment("AGL_TOKYO_CELLS_VARIANT") == "yokohama_joined_coastal")
	var root := OS.get_environment("AGL_TOKYO_SHELL_REVIEW")
	var audit: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(root.path_join("audit.json")))
	assert(audit.preview_only and audit.source_sha256 == "5d4d62de65ea87b4dae462aaa82ec1ee36df6734cdc4fb88caece2e090a58bd5")
	assert(FileAccess.get_sha256(root.path_join("city.json")) == audit.prepared_sha256)
	var city: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(root.path_join("city.json")))
	_suppressed = Duplicates.suppressed(city.buildings)
	for raw: Dictionary in city.buildings:
		_records[String(raw.id)] = raw
	var overlay: Node = owner.features._tokyo_volume
	var captures: Array[Dictionary] = []
	for pose: Array in [[0.98, 0.0], [1.5, 0.0], [2.2, 0.0], [5.0, 0.0], [5.0, deg_to_rad(14.0)]]:
		owner.camera.position = Vector2(-6110, -350)
		owner.camera.zoom = Vector2.ONE * float(pose[0])
		owner.camera.rotation = pose[1]
		owner.camera.force_update_scroll()
		await owner.get_tree().create_timer(0.3).timeout
		var deadline := Time.get_ticks_msec() + 15000
		var state: Dictionary = overlay.debug_state()
		while (state.ready_cells != state.desired_cells or state.stream.pending > 0 or not overlay._batches.has(0)) and Time.get_ticks_msec() < deadline:
			await owner.get_tree().process_frame
			state = overlay.debug_state()
		assert(state.ready_cells == state.desired_cells and state.stream.pending == 0 and overlay._batches.has(0))
		assert(state.stream.failures.is_empty() and state.level >= 4)
		# 建筑包就绪不表示底层瓦片已完成淡入；保留首轮冷帧失败，独立等待再对拍。
		await owner.get_tree().create_timer(2.0).timeout
		state = overlay.debug_state()
		var batch: Dictionary = overlay._batches[0]
		var building: Resource = batch.building
		var middle: bool = state.level == 4 and state.mid_relief
		var name_value := "middle" if state.level == 4 else "near"
		assert(float(state.output_scale) <= float(audit.scales[name_value]))
		var key := "%s:%s" % [batch.path, name_value]
		if not _cache.has(key):
			_cache[key] = _build(building, middle, name_value)
		var candidate: Dictionary = _cache[key]
		var node: MeshInstance3D = batch.nodes[0]
		var original := node.mesh
		assert(original == building.meshes[0] and node.visible and candidate.changed > 0)
		var stem := "res://bench/results/tokyo_r37_%03d_%02d" % [roundi(float(pose[0]) * 100), roundi(rad_to_deg(pose[1]))]
		overlay.set_process(false)
		var original_image: Image = await _capture(owner, overlay, stem + "_original.png")
		_fail += await GroundReview.shadowless(overlay, owner.get_viewport(), stem + "_original_unshadowed.png")
		node.mesh = candidate.mesh
		await _capture(owner, overlay, stem + "_candidate.png")
		_fail += await GroundReview.shadowless(overlay, owner.get_viewport(), stem + "_candidate_unshadowed.png")
		node.mesh = original
		var restored_image: Image = await _capture(owner, overlay, stem + "_restored.png")
		var restoration_error := _pixel_error(original_image, restored_image)
		_fail += int(restoration_error > 1)
		assert(node.mesh == original and batch.building == building)
		overlay._viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		overlay.set_process(true)
		var record := candidate.duplicate()
		record.erase("mesh")
		record["state"] = state
		record["zoom"] = pose[0]
		record["rotation"] = pose[1]
		record["file_stem"] = stem.get_file()
		record["restoration_max_channel_error"] = restoration_error
		record["allowed_screen_bounds"] = _screen_bounds(overlay, candidate.sources)
		record["submitted_triangles_candidate"] = int(state.triangles) - int(candidate.faces_saved)
		# 这是同场景对拍的额外驻留，不是流送器已接受的新归档。
		var candidate_bytes := 0
		for cached: Dictionary in _cache.values():
			candidate_bytes += int(cached.bytes)
		record["review_cached_candidate_bytes"] = candidate_bytes
		record["review_resident_total_bytes"] = int(state.stream.bytes) + candidate_bytes
		captures.append(record)
		print("[Tokyo shell review] pose=", pose, " changed=", candidate.changed, " faces_saved=", candidate.faces_saved)
	var file := FileAccess.open("res://bench/results/tokyo_r37_shell_review.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"preview_only": true, "fail": _fail, "audit": audit, "captures": captures}, "\t"))
	file.close()
	_cache.clear()
	print("[Tokyo shell review] captures=", captures.size(), " fail=", _fail)
	return _fail


func _build(source: Resource, middle: bool, name_value: String) -> Dictionary:
	var before := Geometry.new()
	var after := Geometry.new()
	var changed := 0
	var changed_sources: Array[Dictionary] = []
	for identity: String in source.source_ids:
		var raw: Dictionary = _records[identity]
		assert(raw.regional_draw_owner == "yokohama")
		if raw.height_source != "fallback" or raw.get("defer_render", false) or not raw.get("render_outline", true) or _suppressed.has(identity):
			continue
		var detail := Builder.detail_level(raw, 1.0 if middle else SCALES[source.level], true)
		Factory._add_ring_building(before, raw, float(raw.height_m) * 0.5, detail)
		var record := raw
		if raw.get("shell_lod", {}).has(name_value):
			record = raw.duplicate()
			record.rings = raw.shell_lod[name_value].rings
			changed += 1
			changed_sources.append({"id": identity, "height_px": float(raw.height_m) * 0.5,
				"original": raw.rings[0].outer, "candidate": record.rings[0].outer})
		Factory._add_ring_building(after, record, float(raw.height_m) * 0.5, detail)
	var reconstructed := Palette.recolor(before.mesh())
	assert(Signature.of_mesh(reconstructed) == Signature.of_mesh(source.meshes[0]), "rebuild must exactly match native R32 low-building faces before editing")
	var candidate := Palette.recolor(Indexed.pack(after.mesh()))
	var saved_faces := Indexed.triangles(source.meshes[0]) - Indexed.triangles(candidate)
	assert(changed > 0 and saved_faces > 0)
	assert(candidate.get_aabb().position.y == source.meshes[0].get_aabb().position.y and candidate.get_aabb().end.y == source.meshes[0].get_aabb().end.y)
	return {"mesh": candidate, "changed": changed, "faces_saved": saved_faces,
		"original_faces": Indexed.triangles(source.meshes[0]), "candidate_faces": Indexed.triangles(candidate),
		"original_bytes": Builder.mesh_bytes(source.meshes[0]), "bytes": Builder.mesh_bytes(candidate), "sources": changed_sources}


func _capture(owner: Node2D, overlay: Node, path: String) -> Image:
	overlay._viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	for frame in 5:
		await RenderingServer.frame_post_draw
	var image := owner.get_viewport().get_texture().get_image()
	_fail += int(image.save_png(path) != OK)
	return image


static func _pixel_error(before: Image, after: Image) -> int:
	assert(before.get_size() == after.get_size() and before.get_format() == after.get_format())
	var a := before.get_data()
	var b := after.get_data()
	var maximum := 0
	for i in a.size():
		maximum = maxi(maximum, absi(int(a[i]) - int(b[i])))
	return maximum


static func _screen_bounds(overlay: Node, sources: Array) -> Array:
	var result: Array = []
	# 楼栋在_city局部坐标；先把光线转入同一空间，再把投影点转回3D世界。
	var light: Vector3 = overlay._city.global_basis.inverse() * overlay._sun.global_basis.z
	assert(light.y > 0)
	for source: Dictionary in sources:
		var points: Array = source.original + source.candidate
		var rect := Rect2()
		var initialized := false
		for p: Array in points:
			var top := Vector3(p[0], source.height_px, p[1])
			var ground := Vector3(p[0], 0, p[1])
			var shadow := top - light * (top.y / light.y)
			var expected: Vector2 = (overlay._last_canvas * Vector2(p[0], p[1])) / overlay._screen.scale
			var ground_pixel: Vector2 = overlay._camera.unproject_position(overlay._city.to_global(ground))
			assert(ground_pixel.distance_to(expected) <= 0.05, "screen mask ground anchors must match the real 2D composite")
			for world: Vector3 in [ground, top, shadow]:
				var projected: Vector2 = overlay._camera.unproject_position(overlay._city.to_global(world))
				if not initialized:
					rect = Rect2(projected, Vector2.ZERO)
					initialized = true
				rect = rect.expand(projected)
		result.append([rect.position.x, rect.position.y, rect.end.x, rect.end.y])
	return result
