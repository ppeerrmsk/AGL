extends RefCounted
## 暂停实际R42控制器做原生候选对拍；恢复后才移动相机，不冒充连续LOD实装。
const Cut := preload("res://scripts/experiments/tokyo_spatial_cut.gd")
const Pixels := preload("res://scripts/tests/tokyo_shell_review.gd")
const Indexed := preload("res://scripts/experiments/tokyo_indexed_mesh.gd")
const Builder := preload("res://scripts/tests/build_tokyo_cells.gd")
const Review := preload("res://scripts/tests/tokyo_lod_spatial_review.gd")
var _fail := 0
var _catalogs: Dictionary = {}


func run(owner: Node2D) -> int:
	var overlay: Node = owner.features._tokyo_volume
	assert(overlay.debug_state().candidate == "R42")
	for variant: String in ["full", "mid"]:
		var catalog: Resource = load("res://resources/maps/tokyo_volume_preview/r44_lod_pages/" + variant + "/index.res")
		assert(catalog.valid())
		_catalogs[variant] = catalog
	var records: Array[Dictionary] = []
	var utility := Review.new()
	for pose: Array in [["mid", 0.98, 0.0], ["full", 1.3, 0.0], ["rotated", 1.65, deg_to_rad(14.0)],
			["counter_rotated", 1.65, deg_to_rad(-14.0)], ["near_original", 2.2, 0.0], ["close_original", 5.0, 0.0], ["return", 0.98, 0.0]]:
		owner.camera.position = Vector2(-5600, -2900)
		owner.camera.zoom = Vector2.ONE * float(pose[1])
		owner.camera.rotation = pose[2]
		owner.camera.force_update_scroll()
		await owner.get_tree().create_timer(0.3).timeout
		var deadline := Time.get_ticks_msec() + 12000
		var state: Dictionary = overlay.debug_state()
		while (not state.cut_ready or state.active_cells == 0 or state.stream.pending > 0) and Time.get_ticks_msec() < deadline:
			await owner.get_tree().process_frame
			state = overlay.debug_state()
		assert(state.cut_ready and state.stream.failures.is_empty())
		_fail += int(not await utility._wait_basemap(owner))
		await owner.get_tree().create_timer(0.5).timeout
		overlay.set_process(false)
		var stem := "res://bench/results/tokyo_r44_" + String(pose[0])
		var original := await _capture(owner, overlay, stem + "_original.png")
		var record := {"pose": pose[0], "zoom": pose[1], "rotation": pose[2], "original_state": state, "file_stem": stem.get_file(),
			"native_candidate": false, "continuous_lod": false, "candidate_faces": state.triangles}
		if state.level == 4:
			assert(float(state.output_scale) <= 1.5552)
			record.merge(await _compare(owner, overlay, original, stem), true)
		else:
			assert(state.level == 5)
			_fail += int(original.save_png(stem + "_candidate.png") != OK)
			record["near_original"] = true
		overlay._viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		overlay.set_process(true)
		records.append(record)
		print("[Tokyo cluster Visual] pose=", pose[0], " original=", state.triangles, " candidate=", record.candidate_faces,
			" restored=", record.get("restoration_max_channel_error", -1), " budget_failed=", record.get("face_budget_failed", false))
	var file := FileAccess.open("res://bench/results/tokyo_r44_review.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"candidate": "R44", "fail": _fail, "records": records, "fps_evidence": false, "continuous_lod": false}, "\t"))
	file.close()
	print("[Tokyo cluster Visual] captures=", records.size(), " fail=", _fail)
	return _fail


func _compare(owner: Node2D, overlay: Node, original: Image, stem: String) -> Dictionary:
	var catalog: Resource = _catalogs["mid" if overlay._relief_active else "full"]
	var inverse: Basis = overlay._city.basis.inverse()
	var camera_ray: Vector3 = inverse * overlay._camera.basis.z
	var light_ray: Vector3 = inverse * overlay._sun.basis.z
	var chosen := Cut.choose(catalog.parents, overlay._cull_view, overlay._last_canvas, Vector2(overlay._viewport.size) * overlay._screen.scale,
		-Vector2(camera_ray.x, camera_ray.z) / camera_ray.y, -Vector2(light_ray.x, light_ray.z) / light_ray.y)
	var entries: Array[Dictionary] = []
	entries.assign(chosen.entries)
	var paths: Dictionary = {}
	for entry: Dictionary in entries:
		if entry.has("path"):
			paths[entry.path] = int(entry.bytes)
		else:
			var fixed_bytes := int(overlay._descriptors[entry.fixed].bytes)
			paths[entry.fixed] = fixed_bytes
			paths[entry.building] = int(entry.bytes) - fixed_bytes
	var extra := 0
	for path: String in paths:
		if overlay._stream.resource(path) == null:
			extra += int(paths[path])
	var state: Dictionary = overlay.debug_state()
	var resident := int(state.stream.bytes) + int(state.stream.reserved_bytes) + extra
	if resident > 96 * 1024 * 1024:
		_fail += 1
		return {"native_candidate": false, "memory_blocked": true, "reference_resident_bytes": resident}
	var resources: Dictionary = {}
	for path: String in paths:
		resources[path] = overlay._stream.resource(path)
		if resources[path] == null:
			resources[path] = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
		assert(resources[path] != null and resources[path].valid())
	var saved: Array[Dictionary] = []
	for nodes: Array in overlay._slots:
		for node: MeshInstance3D in nodes:
			saved.append({"node": node, "mesh": node.mesh, "visible": node.visible, "cast": node.cast_shadow})
			node.hide()
	var actual := 0
	for n in entries.size():
		var entry: Dictionary = entries[n]
		var building: Resource = resources[entry.path if entry.has("path") else entry.building]
		var fixed: Resource = building if entry.has("path") else resources[entry.fixed]
		for kind in 3:
			var node: MeshInstance3D = overlay._slots[n][kind]
			node.mesh = fixed.meshes[2 if entry.has("path") else 0] if kind == 2 else building.meshes[kind]
			node.visible = entry.mask[kind]
			node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if kind < 2 else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			if node.visible:
				actual += Indexed.triangles(node.mesh)
	assert(entries.size() <= 16 and actual == int(chosen.triangles))
	await _capture(owner, overlay, stem + "_candidate.png")
	var sources: Array[Dictionary] = []
	for parent: Dictionary in catalog.parents:
		for group: Dictionary in parent.get("cluster_groups", []):
			sources.append({"original": group.outer, "candidate": group.outer, "height_px": float(group.height_m) * 0.5})
	var masks := Pixels._screen_bounds(overlay, sources)
	for entry: Dictionary in saved:
		entry.node.mesh = entry.mesh
		entry.node.visible = entry.visible
		entry.node.cast_shadow = entry.cast
	var restored := await _capture(owner, overlay, stem + "_restored.png")
	var error := Pixels._pixel_error(original, restored)
	_fail += int(error > 1)
	_fail += int(actual > 240000)
	return {"native_candidate": true, "candidate_faces": actual, "face_budget_failed": actual > 240000,
		"restoration_max_channel_error": error, "allowed_screen_bounds": masks, "mask_padding_px": 4,
		"candidate_cells": entries.size(), "candidate_extra_bytes": extra, "reference_resident_bytes": resident}


func _capture(owner: Node2D, overlay: Node, path: String) -> Image:
	overlay._viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	for frame in 5:
		await RenderingServer.frame_post_draw
	var picture := owner.get_viewport().get_texture().get_image()
	_fail += int(picture.save_png(path) != OK)
	return picture
