extends RefCounted
## 显式隔离目录：2288包通过生产Stream，不冒称已经提交到地图画面。
const Stream := preload("res://scripts/rendering/tokyo_cell_stream.gd")
const Spatial := preload("res://scripts/tests/build_tokyo_spatial_pages.gd")


static func run(parent: Node, catalog_path: String) -> int:
	var catalog: Resource = ResourceLoader.load(catalog_path, "", ResourceLoader.CACHE_MODE_IGNORE)
	if catalog == null or not catalog.valid():
		return 1
	var owner := Node.new()
	parent.add_child(owner)
	var stream := Stream.new()
	parent.add_child(stream)
	stream.configure(owner, catalog.descriptors)
	var stream_ref: WeakRef = weakref(stream)
	var paths := PackedStringArray(catalog.descriptors.keys())
	var offset := 0
	var validated := 0
	var groups := 0
	var failures := 0
	var current := PackedStringArray()
	var last_summary: Dictionary = {}
	while offset < paths.size():
		var wanted := PackedStringArray()
		var bytes := 0
		while offset < paths.size() and wanted.size() < 16:
			var amount := int(catalog.descriptors[paths[offset]].bytes)
			if bytes + amount > Stream.BUDGET / 3:
				break
			bytes += amount
			wanted.append(paths[offset])
			offset += 1
		if wanted.is_empty():
			failures += 1
			break
		stream.request(wanted, current)
		var deadline := Time.get_ticks_msec() + 15000
		var ready := false
		while Time.get_ticks_msec() < deadline:
			ready = true
			for path: String in wanted:
				ready = ready and stream.resource(path) != null
			if ready or not stream.summary().failures.is_empty():
				break
			await parent.get_tree().process_frame
		if not ready:
			print("[Tokyo canonical stream] not ready at ", offset, " ", stream.summary())
			failures += 1
			break
		for path: String in wanted:
			var page: Resource = stream.resource(path)
			var geometry := Spatial.descriptor(page.meshes)
			failures += int(geometry.bytes != int(catalog.descriptors[path].bytes))
			for mesh: ArrayMesh in page.meshes:
				failures += int(RenderingServer.mesh_get_surface_count(mesh.get_rid()) != mesh.get_surface_count())
			validated += 1
		current = wanted
		stream.request(current, current)
		last_summary = stream.summary()
		failures += int(last_summary.bytes != bytes or last_summary.reserved_bytes != 0 or last_summary.pending != 0)
		groups += 1
		if groups % 20 == 0:
			print("[Tokyo canonical stream] groups=", groups, " validated=", validated)
	# 真正owner退出时留一个在途请求，必须清理当前/预留/全局槽。
	stream.request(PackedStringArray([paths[0]]), current)
	stream._process_stream()
	var pending := not stream._pending.is_empty()
	var terminal: Dictionary = {}
	stream.tree_exiting.connect(func() -> void: terminal.merge(stream.summary()))
	owner.queue_free()
	var deadline := Time.get_ticks_msec() + 15000
	while is_instance_valid(stream_ref.get_ref()) and Time.get_ticks_msec() < deadline:
		await parent.get_tree().process_frame
	failures += int(not pending or is_instance_valid(stream_ref.get_ref()) or not Stream._busy.is_empty())
	failures += int(not terminal.get("closed", false) or terminal.get("pending", -1) != 0 \
		or terminal.get("reserved_bytes", -1) != 0 or terminal.get("bytes", -1) != 0)
	failures += int(validated != 2288 or last_summary.get("peak_bytes", Stream.BUDGET + 1) > Stream.BUDGET \
		or last_summary.get("peak_pending", 3) > 2 or last_summary.get("max_completed_per_frame", 0) != 1)
	print("[Tokyo canonical stream] COMPLETE validated=", validated, " groups=", groups, " backend=", last_summary.get("loader_backend"),
		" peak_bytes=", last_summary.get("peak_bytes"), " pending_exit=", pending, " fail=", failures)
	if failures:
		push_error("[Bench] Canonical native stream failed")
	return failures
