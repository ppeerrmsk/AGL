extends RefCounted
## 使用生产Stream在RID churn期间换四批真实包，验证后端、原数组及终态。
const Stream := preload("res://scripts/rendering/tokyo_cell_stream.gd")


static func run(parent: Node) -> int:
	var catalog: Resource = load("res://resources/maps/tokyo_volume_preview/r34_cells/index.res")
	var paths := PackedStringArray()
	var descriptors: Dictionary = {}
	var fingerprints: Dictionary = {}
	for cell: Dictionary in catalog.cells:
		for path: String in [cell.levels[0].path, cell.fixed]:
			var original: Resource = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
			paths.append(path)
			descriptors[path] = {"id": original.cell_id, "level": original.level, "bytes": original.geometry_bytes, "height_hash": original.height_hash}
			fingerprints[path] = _fingerprint(original)
	var owner := Node.new()
	parent.add_child(owner)
	var stream := Stream.new()
	parent.add_child(stream)
	stream.configure(owner, descriptors)
	var reference: WeakRef = weakref(stream)
	var failures := 0
	var validated := 0
	var main_backend := DisplayServer.get_name() == "headless"
	failures += int(stream._main_thread_meshes != main_backend)
	for round_index in 4:
		var wanted := PackedStringArray()
		for n in 16:
			wanted.append(paths[(round_index % 2) * 16 + n])
		var seen: Dictionary = {}
		var frame := Engine.get_process_frames()
		stream.request(wanted, PackedStringArray())
		var deadline := Time.get_ticks_msec() + 10000
		while seen.size() < wanted.size() and Time.get_ticks_msec() < deadline:
			for path: String in wanted:
				var resource: Resource = stream.resource(path)
				if resource == null or seen.has(path):
					continue
				for mesh: ArrayMesh in resource.meshes:
					failures += int(RenderingServer.mesh_get_surface_count(mesh.get_rid()) != mesh.get_surface_count())
				failures += int(_fingerprint(resource) != fingerprints[path])
				seen[path] = true
				validated += 1
			for n in 2000:
				var mesh := ArrayMesh.new()
				mesh.get_rid()
			await parent.get_tree().process_frame
		failures += int(seen.size() != wanted.size() or Engine.get_process_frames() <= frame + 2)
	var summary := stream.summary()
	failures += int(not summary.failures.is_empty() or summary.peak_bytes > Stream.BUDGET or summary.peak_pending > 2 or summary.max_completed_per_frame != 1)
	# 真实tree_exiting关闭：先留一个下一帧才领取的请求，再释放owner。
	stream.request(PackedStringArray([paths[0]]), PackedStringArray())
	stream._process_stream()
	var had_pending := not stream._pending.is_empty()
	var discarded := stream.discarded
	var closed_state: Dictionary = {}
	stream.tree_exiting.connect(func() -> void:
		closed_state.merge(stream.summary())
		closed_state["main_queued"] = stream._main_queued.size()
	)
	owner.queue_free()
	await parent.get_tree().process_frame
	await parent.get_tree().process_frame
	var deadline := Time.get_ticks_msec() + 10000
	while is_instance_valid(reference.get_ref()) and Time.get_ticks_msec() < deadline:
		await parent.get_tree().process_frame
	failures += int(not had_pending or is_instance_valid(reference.get_ref()) or not Stream._busy.is_empty())
	failures += int(not closed_state.get("closed", false) or int(closed_state.get("bytes", -1)) != 0
		or int(closed_state.get("reserved_bytes", -1)) != 0 or int(closed_state.get("pending", -1)) != 0
		or int(closed_state.get("main_queued", -1)) != 0 or int(closed_state.get("discarded", -1)) != discarded + 1)
	print("[Tokyo RID stream] validated=", validated, " backend=", summary.loader_backend, " per_frame=", summary.max_completed_per_frame,
		" peak_bytes=", summary.peak_bytes, " fail=", failures, " closed_pending=", had_pending, " prior_discarded=", discarded)
	if failures:
		push_error("[Bench] Tokyo RID stream contract failed")
	return failures


static func _fingerprint(resource: Resource) -> String:
	var arrays: Array = []
	for mesh: ArrayMesh in resource.meshes:
		for surface in mesh.get_surface_count():
			arrays.append(mesh.surface_get_arrays(surface))
	var precision: Variant = resource.get("precision_original")
	if precision is ArrayMesh:
		arrays.append(precision.surface_get_arrays(0))
	return var_to_bytes(arrays).hex_encode().sha256_text()
