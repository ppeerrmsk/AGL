extends RefCounted
## 仅静态原图/候选/恢复对照；不代替连续 LOD 或战斗性能验收。
const Capture := preload("res://scripts/tests/tokyo_lod_spatial_review.gd")
const Pixels := preload("res://scripts/tests/tokyo_shell_review.gd")
const Indexed := preload("res://scripts/experiments/tokyo_indexed_mesh.gd")
const Bake := preload("res://scripts/tests/bake_tokyo_ground_merge.gd")
const Order := preload("res://scripts/tests/tokyo_ground_order_probe.gd")
var _fail := 0


func run(owner: Node2D, directory: String) -> int:
	var output := OS.get_environment("AGL_TOKYO_GROUND_REVIEW_OUT")
	if output.is_empty() or DirAccess.dir_exists_absolute(output):
		return 1
	DirAccess.make_dir_recursive_absolute(output)
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(directory.path_join("manifest.json")))
	var overlay: Node = owner.features._tokyo_volume
	# 同位消融只判断阴影采样是否参与误差，不作为美术或性能通过证据。
	if OS.get_environment("AGL_TOKYO_GROUND_NO_SHADOW") == "1":
		overlay._sun.shadow_enabled = false
	var capture := Capture.new()
	var records: Array[Dictionary] = []
	for place: Array in [["north", Vector2(-5600, -2900)], ["seam", Vector2(-5300, -1700)], ["port", Vector2(-5150, -480)]]:
		for zoom: float in [0.13, 0.26, 0.98, 2.2, 5.0]:
			owner.camera.position = place[1]
			owner.camera.zoom = Vector2.ONE * zoom
			owner.camera.rotation = deg_to_rad(14) if place[0] == "seam" else 0.0
			owner.camera.force_update_scroll()
			await owner.get_tree().create_timer(0.3).timeout
			var deadline := Time.get_ticks_msec() + 15000
			var state: Dictionary = overlay.debug_state()
			while (state.ready_cells != state.desired_cells or state.ready_cells == 0 or state.stream.pending > 0) and Time.get_ticks_msec() < deadline:
				await owner.get_tree().process_frame
				state = overlay.debug_state()
			if state.ready_cells == 0 or state.ready_cells != state.desired_cells or not state.stream.failures.is_empty():
				_fail += 1
				records.append({"place": place[0], "zoom": zoom, "blocked": "incomplete source cut", "state": state})
				continue
			_fail += int(not await capture._wait_basemap(owner))
			overlay.set_process(false)
			var stem := output.path_join("%s_%03d" % [place[0], roundi(zoom * 100)])
			var record := await _compare(owner, overlay, capture, manifest, stem)
			record.merge({"place": place[0], "zoom": zoom, "state": state})
			records.append(record)
			overlay._viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
			overlay.set_process(true)
			print("[R55 ground Visual] ", place[0], " zoom=", zoom, " result=", record)
	_fail += capture._fail
	var file := FileAccess.open(output.path_join("review.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"fail": _fail, "records": records, "fps_evidence": false, "production_enabled": false}, "\t"))
	file.close()
	print("[R55 ground Visual] COMPLETE poses=", records.size(), " fail=", _fail)
	return _fail


func _compare(owner: Node2D, overlay: Node, capture: RefCounted, manifest: Dictionary, stem: String) -> Dictionary:
	var control := OS.get_environment("AGL_TOKYO_GROUND_COMPACT_CONTROL") == "1"
	var order_path := OS.get_environment("AGL_TOKYO_GROUND_ORDER_PLAN")
	var order_only := not order_path.is_empty()
	var extra := 0
	for id: int in overlay._batches:
		extra += int(manifest.rows[id].old_bytes if control or order_only else manifest.rows[id].bytes)
	var stream: Dictionary = overlay._stream.summary()
	var resident := int(stream.bytes) + int(stream.reserved_bytes) + extra
	if resident > 96 * 1024 * 1024:
		_fail += 1
		return {"blocked": "old plus candidate memory budget", "resident_bytes": resident}
	var resources: Dictionary = {}
	for id: int in overlay._batches:
		var row: Dictionary = manifest.rows[id]
		if FileAccess.get_sha256(row.path) != row.sha256 or FileAccess.get_sha256(row.source) != row.source_sha256:
			_fail += 1
			return {"blocked": "source or candidate identity"}
		# 对照直接复用已驻留源，避免另持一份源网格漏算内存。
		var resource: Resource = overlay._batches[id].fixed if control or order_only else ResourceLoader.load(row.path, "", ResourceLoader.CACHE_MODE_IGNORE)
		if resource == null or not resource.valid() or resource.cell_id != id or overlay._archive.cells[id].fixed != row.source:
			_fail += 1
			return {"blocked": "native identity"}
		resources[id] = Bake.compact(resource.meshes[0]) if control else resource.meshes[0]
		if order_only:
			var plan: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(order_path.path_join("cell_%02d.json" % id)))
			if plan.source_sha256 != row.source_sha256 or int(plan.cell_id) != id:
				_fail += 1
				return {"blocked": "order plan identity"}
			resources[id] = Order.move_to_end(resource.meshes[0], plan.removed)
			if resources[id] == null or not Bake.Join.conserved(resource.meshes[0], [resources[id]]):
				_fail += 1
				return {"blocked": "order control changed original faces"}
	var original_transform: Transform3D = overlay._camera.transform
	var original_near: float = overlay._camera.near
	var original_far: float = overlay._camera.far
	var original_shadow: float = overlay._sun.directional_shadow_max_distance
	var distance_shift := 0.0
	if OS.get_environment("AGL_TOKYO_GROUND_NEAR_CAMERA") == "1":
		# 正交投影沿光轴平移，并等量缩短近远面；不移动地图或立面世界坐标。
		distance_shift = minf(45000.0, original_near - 1.0)
		overlay._camera.position -= overlay._camera.basis.z * distance_shift
		overlay._camera.near = original_near - distance_shift
		overlay._camera.far = original_far - distance_shift
		overlay._sun.directional_shadow_max_distance = original_shadow - distance_shift
	var before: Image = await capture._capture(owner, overlay, stem + "_original.png")
	var saved: Dictionary = {}
	var faces := 0
	for id: int in overlay._batches:
		var batch: Dictionary = overlay._batches[id]
		saved[id] = batch.nodes[2].mesh
		batch.nodes[2].mesh = resources[id]
		for node: MeshInstance3D in batch.nodes:
			if node.visible:
				faces += Indexed.triangles(node.mesh)
	var candidate: Image = await capture._capture(owner, overlay, stem + "_candidate.png")
	for id: int in saved:
		overlay._batches[id].nodes[2].mesh = saved[id]
	var restored: Image = await capture._capture(owner, overlay, stem + "_restored.png")
	overlay._camera.transform = original_transform
	overlay._camera.near = original_near
	overlay._camera.far = original_far
	overlay._sun.directional_shadow_max_distance = original_shadow
	var error := Pixels._pixel_error(before, candidate)
	var restore_error := Pixels._pixel_error(before, restored)
	_fail += int(error > 1 or restore_error > 1)
	return {"distance_shift": distance_shift, "shadows": overlay._sun.shadow_enabled, "order_only": order_only, "compact_only": control, "pixel_error": error, "restore_error": restore_error, "faces": faces, "face_budget_pass": faces <= 240000, "resident_bytes": resident}
