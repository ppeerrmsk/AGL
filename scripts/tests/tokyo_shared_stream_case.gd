extends RefCounted
## 原生共享存储/释放证据；AO仅预留已验证保守额，此fixture不绘制地图或实际AO。
const Stream := preload("res://scripts/rendering/tokyo_cell_stream.gd")
const Builder := preload("res://scripts/tests/build_tokyo_cells.gd")
const AO_RESERVATION := 29361664


static func run(parent: Node, directory: String, output: String) -> int:
	if output.is_empty() or FileAccess.file_exists(output):
		return 1
	var file := FileAccess.open(directory.path_join("manifest.bin"), FileAccess.READ)
	if file == null:
		return 1
	var manifest: Dictionary = file.get_var(false)
	file.close()
	if manifest.rows.size() != 208:
		return 1
	var roots := PackedStringArray()
	var rest := PackedStringArray()
	var descriptors: Dictionary = {}
	var old_root_bytes := 0
	for row: Dictionary in manifest.rows:
		if FileAccess.get_sha256(row.path) != row.sha256:
			return 1
		descriptors[row.path] = {"bytes": row.bytes, "canonical_identity": row.canonical_identity}
		if row.cell == -1:
			roots.append(row.path)
			old_root_bytes += int(row.old_bytes)
		else:
			rest.append(row.path)
	if roots.size() != 16:
		return 1
	var owner := Node.new()
	parent.add_child(owner)
	var stream := Stream.new()
	parent.add_child(stream)
	stream.configure(owner, descriptors)
	var stream_ref: WeakRef = weakref(stream)
	var token := RefCounted.new()
	var key := token.get_instance_id()
	var fail := int(not stream.reserve_auxiliary(key, AO_RESERVATION))
	var weak_meshes: Array[WeakRef] = []
	var weak_pages: Array[WeakRef] = []
	var groups: Array = [roots]
	for start in range(0, rest.size(), 16):
		groups.append(rest.slice(start, mini(start + 16, rest.size())))
	var validated := 0
	var root_state: Dictionary = {}
	var current := PackedStringArray()
	for wanted: PackedStringArray in groups:
		# 加载fixture不提交旧节点：旧组先退役，不能冒称旧新切面交接已接通。
		stream.request(wanted, PackedStringArray())
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
			fail += 1
			break
		for path: String in wanted:
			fail += _inspect(stream.resource(path), weak_meshes, weak_pages)
			validated += 1
		if root_state.is_empty():
			root_state = stream.summary()
		current = wanted
	var summary := stream.summary()
	# roots[0]不在末组；先发出真实在途请求，再通过owner退出关闭。
	stream.request(PackedStringArray([roots[0]]), current)
	stream._process_stream()
	var pending := not stream._pending.is_empty()
	owner.queue_free()
	await parent.get_tree().process_frame
	await parent.get_tree().process_frame
	var awaiting_aux := is_instance_valid(stream_ref.get_ref()) and stream._closed
	stream.release_auxiliary(key)
	var deadline := Time.get_ticks_msec() + 15000
	while is_instance_valid(stream_ref.get_ref()) and Time.get_ticks_msec() < deadline:
		await parent.get_tree().process_frame
	var retained := 0
	for reference: WeakRef in weak_meshes + weak_pages:
		retained += int(is_instance_valid(reference.get_ref()))
	fail += int(not pending or not awaiting_aux or retained > 0 or is_instance_valid(stream_ref.get_ref()) or not Stream._busy.is_empty())
	fail += int(validated != 208 or summary.peak_total_bytes > Stream.BUDGET or summary.max_completed_per_frame != 1)
	var report := {"fail": fail, "validated": validated, "old_root_pair_bytes": old_root_bytes,
		"root_state": root_state, "summary": summary, "pending_exit": pending, "awaiting_aux_release": awaiting_aux,
		"retained_weak_resources": retained, "ao_allowance_only": true, "map_visual_verified": false}
	file = FileAccess.open(output, FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print("[R68 shared stream] ", report)
	return fail


static func _inspect(page: Resource, weak_meshes: Array[WeakRef], weak_pages: Array[WeakRef]) -> int:
	var fail := 0
	var total := 0
	weak_pages.append(weakref(page))
	for mesh: ArrayMesh in page.meshes:
		total += Builder.mesh_bytes(mesh)
		weak_meshes.append(weakref(mesh))
		fail += int(RenderingServer.mesh_get_surface_count(mesh.get_rid()) != mesh.get_surface_count())
	var full: Array[ArrayMesh] = page.variant_meshes("lod2_full")
	var guarded: Array[ArrayMesh] = page.variant_meshes("lod2_guarded")
	# 该批次逐源证实两层完全相同；实际指针/RID也必须只有一份。
	for kind in [1, 2]:
		fail += int(full[kind] != guarded[kind] or full[kind].get_rid() != guarded[kind].get_rid())
	return fail + int(total != page.geometry_bytes)
