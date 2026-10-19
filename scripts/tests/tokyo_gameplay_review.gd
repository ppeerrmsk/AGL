extends RefCounted
## 实际Survivor静态区域对拍；绑定候选时保留全部碰撞缓存，结束后恢复旧视觉。
const Factory := preload("res://scripts/experiments/tokyo_gameplay_volume.gd")
const Depth := preload("res://scripts/rendering/tokyo_shadow_depth.gd")
const Shared := preload("res://scripts/tests/tokyo_shared_roof_review.gd")
const REGION := Rect2(-6150, -1700, 700, 1350)
var _fail := 0


func run(battle: Node, map: Node) -> int:
	var tree := battle.get_tree()
	var original_pause := tree.paused
	var original_ignore: bool = battle.camera.ignore_rotation
	battle.camera.ignore_rotation = false
	tree.paused = true
	map.set_process(false)
	var legacy: BuildingRenderer = battle._building_renderer
	legacy.set_process(false)
	var source: Array = legacy._districts
	var source_signature := var_to_bytes(BuildingRenderer._cache_entries).hex_encode().sha256_text()
	var selected: Array = []
	var remaining: Array = []
	var ids: Array[int] = []
	for n in source.size():
		var entry: Dictionary = source[n]
		if REGION.encloses(entry.bbox) and map._archive.bounds.encloses(entry.bbox):
			selected.append(entry)
			ids.append(n)
		else:
			remaining.append(entry)
	if selected.is_empty():
		push_error("Tokyo gameplay review: no accepted district in target region")
		tree.paused = original_pause
		return 1
	var addition := Factory.build_many(selected)
	var added_bytes := Factory.geometry_bytes(addition)
	var added_faces := Factory.triangles(addition)
	var native_ref: WeakRef = weakref(addition)
	var native_refs: Array[WeakRef] = [native_ref]
	var difference_enabled := OS.get_environment("AGL_TOKYO_ROOF_DIFFERENCE") == "1"
	var shared_directory := OS.get_environment("AGL_TOKYO_SHARED_REVIEW")
	var shared_enabled := not shared_directory.is_empty()
	var prefix := "r50" if shared_enabled else "r49"
	var rows: Array[Dictionary] = []
	var poses := [Vector3(0.35,0,0), Vector3(0.65,0,0), Vector3(0.98,0,0), Vector3(1.3,0,0), Vector3(1.95,0,0), Vector3(0.98,-0.244,0), Vector3(0.98,0.209,0)]
	for i in poses.size():
		battle.camera.position = REGION.get_center()
		battle.camera.zoom = Vector2.ONE * poses[i].x
		battle.camera.rotation = poses[i].y
		battle._camera_ctrl.target_zoom = poses[i].x
		battle.camera.force_update_scroll()
		legacy._districts = source
		legacy.queue_redraw()
		var deadline := Time.get_ticks_msec() + 15000
		while Time.get_ticks_msec() < deadline:
			map._process(0.1)
			var state: Dictionary = map.debug_state()
			if state.cut_ready and state.stream.pending == 0 and state.active_cells > 0:
				break
			await tree.process_frame
		await _capture(tree, map, prefix + "_%02d_legacy" % i)
		var state: Dictionary = map.debug_state()
		if not state.cut_ready or state.stream.pending != 0:
			_fail += 1
			continue
		var roof_info: Dictionary = {}
		if OS.get_environment("AGL_TOKYO_GAMEPLAY_EXPORT") == "1":
			var exporter: Script = load("res://scripts/tests/export_tokyo_gameplay_roofs.gd")
			if exporter == null or not exporter.can_instantiate():
				_fail += 1
			else:
				exporter.run(map, selected, ids, i, "res://bench/results/tokyo_r50_pose_%02d.json" % i)
		if difference_enabled or i == 4:
			roof_info = _coplanar_roofs(map, selected)
			if difference_enabled:
				addition = Factory.build_many(selected, roof_info.native_roofs)
				added_faces = Factory.triangles(addition)
				added_bytes = Factory.geometry_bytes(addition)
				native_refs.append(weakref(addition))
				if i == 4:
					_export_roofs(addition, selected, roof_info.native_roofs)
			roof_info.erase("native_roofs")
		var shared: Dictionary = {}
		if shared_enabled:
			addition = null
			shared = Shared.bind(map, shared_directory + "/r50_shared_v2_pose_%02d.res" % i, source_signature)
			if shared.is_empty():
				push_error("Tokyo shared review: saved bundle source mismatch")
				_fail += 1
				continue
			addition = shared.addition
			added_bytes = int(shared.bytes)
			native_refs.append(weakref(addition))
			native_refs.append_array(Shared.references(shared))
		# 复用一个已绑定标高批次，静态审查期间停用自动剔除；不新增Mesh节点。
		var batch: Dictionary = map._batches.values()[0]
		var node: MeshInstance3D = batch.nodes[1]
		var original: ArrayMesh = node.mesh
		var combined := Factory.joined(original, addition)
		if shared_enabled:
			native_refs.append(weakref(combined))
		var union_bytes := int(state.stream.bytes) + added_bytes + Factory.geometry_bytes(combined)
		var row := {"pose": i, "zoom": poses[i].x, "rotation": poses[i].y, "sources": ids,
			"source_count": ids.size(), "added_faces": Factory.triangles(addition), "union_bytes": union_bytes,
			"nodes": state.nodes, "materials": state.materials, "baseline": state, "fps_evidence": false}
		row["rotation_error"] = absf(wrapf(float(state.canvas_rotation) + poses[i].y, -PI, PI))
		_fail += int(row.rotation_error > 0.0001)
		row["roof_difference"] = difference_enabled
		row["shared_roof_bundle"] = shared_enabled
		row["coplanar_roofs"] = roof_info
		if union_bytes > 96 * 1024 * 1024:
			row["budget_rejected"] = true
			_fail += 1
			rows.append(row)
			Shared.restore(shared)
			continue
		var prior_visible := node.visible
		var prior_shadow := node.cast_shadow
		node.mesh = combined
		node.show()
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		legacy._districts = remaining
		legacy.queue_redraw()
		# 街区最高点纳入实际相机深度；不沿用仅考虑原地图可见楼的局部深度。
		var prior_clip := Vector2(map._camera.near, map._camera.far)
		var prior_light: float = map._sun.directional_shadow_max_distance
		var clip := Depth.fit(map._camera.size, maxf(map._depth_max_height, addition.get_aabb().end.y), map._camera.basis, map._sun.basis)
		map._camera.near = clip.x
		map._camera.far = clip.y
		map._sun.directional_shadow_max_distance = clip.y
		var projection := _projection_errors(map, selected)
		row["ground_error_px"] = projection.x
		row["height_error_px"] = projection.y
		_fail += int(projection.x > 0.1 or projection.y > 0.1)
		map._viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
		await _capture(tree, map, prefix + "_%02d_native" % i)
		row["submitted_faces"] = Shared.submitted_faces(map)
		row["triangle_budget_pass"] = row.submitted_faces <= 240000
		_fail += int(not row.triangle_budget_pass)
		row["collision_unchanged"] = source_signature == var_to_bytes(BuildingRenderer._cache_entries).hex_encode().sha256_text()
		_fail += int(not row.collision_unchanged)
		rows.append(row)
		node.mesh = original
		node.visible = prior_visible
		node.cast_shadow = prior_shadow
		map._camera.near = prior_clip.x
		map._camera.far = prior_clip.y
		map._sun.directional_shadow_max_distance = prior_light
		combined = null
		original = null
		Shared.restore(shared)
	legacy._districts = source
	legacy.queue_redraw()
	legacy.set_process(true)
	map.set_process(true)
	battle.camera.ignore_rotation = original_ignore
	tree.paused = original_pause
	addition = null
	await tree.process_frame
	var released := true
	var unreleased: Array[String] = []
	for reference: WeakRef in native_refs:
		released = released and reference.get_ref() == null
		if reference.get_ref() != null:
			unreleased.append(str(reference.get_ref().resource_path))
	_fail += int(not released)
	var file := FileAccess.open("res://bench/results/tokyo_" + prefix + "_review.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"rows": rows, "fail": _fail, "native_released": released,
		"unreleased": unreleased,
		"collision_signature": source_signature, "production_enabled": false, "continuous_lod_evidence": false}, "\t"))
	file.close()
	print("[Tokyo gameplay review] poses=", rows.size(), " districts=", ids.size(), " extra_faces=", added_faces, " fail=", _fail)
	return _fail


func _projection_errors(map: Node, entries: Array) -> Vector2:
	var error := Vector2.ZERO
	var pixel_scale := float(map._viewport.size.y) / float(map._camera.size)
	for entry: Dictionary in entries:
		var height := float(entry.max_real_h) * CombatUnit.PIXELS_PER_METER
		for point: Vector2 in entry.footprint:
			var floor_pos: Vector2 = map._camera.unproject_position(map._city.to_global(Vector3(point.x, 0, point.y)))
			var roof_pos: Vector2 = map._camera.unproject_position(map._city.to_global(Vector3(point.x, height, point.y)))
			var expected: Vector2 = (map._last_canvas * point) / map._screen.scale
			error.x = maxf(error.x, expected.distance_to(floor_pos))
			error.y = maxf(error.y, (roof_pos - floor_pos).distance_to(Vector2(0, -height * sin(map.TILT) * pixel_scale)))
	return error


func _coplanar_roofs(map: Node, entries: Array) -> Dictionary:
	# 只读近景原生三角，确认屋顶斑块是否存在真实共面覆盖；不靠截图猜测删除面。
	var by_height: Dictionary = {}
	for id in entries.size():
		var key := roundi(float(entries[id].max_real_h) * CombatUnit.PIXELS_PER_METER * 1000.0)
		if not by_height.has(key):
			by_height[key] = []
		by_height[key].append(id)
	var overlaps: Dictionary = {}
	var native_roofs: Dictionary = {}
	var faces := 0
	var area := 0.0
	for batch: Dictionary in map._batches.values():
		for kind in 2:
			var node: MeshInstance3D = batch.nodes[kind]
			if not node.visible:
				continue
			for surface in node.mesh.get_surface_count():
				var arrays := node.mesh.surface_get_arrays(surface)
				var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
				var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
				var count := indices.size() if not indices.is_empty() else vertices.size()
				for n in range(0, count, 3):
					var a := vertices[indices[n] if not indices.is_empty() else n]
					var b := vertices[indices[n + 1] if not indices.is_empty() else n + 1]
					var c := vertices[indices[n + 2] if not indices.is_empty() else n + 2]
					if a.y != b.y or a.y != c.y or not by_height.has(roundi(a.y * 1000.0)):
						continue
					var polygon := PackedVector2Array([Vector2(a.x,a.z), Vector2(b.x,b.z), Vector2(c.x,c.z)])
					var roof_key := roundi(a.y * 1000.0)
					if not native_roofs.has(roof_key):
						native_roofs[roof_key] = []
					native_roofs[roof_key].append(polygon)
					for id: int in by_height[roundi(a.y * 1000.0)]:
						var intersect := Geometry2D.intersect_polygons(polygon, entries[id].footprint)
						var local_area := 0.0
						for part: PackedVector2Array in intersect:
							var signed_area := 0.0
							for edge in part.size():
								signed_area += (part[edge] - part[0]).cross(part[(edge + 1) % part.size()] - part[0])
							local_area += absf(signed_area) * 0.5
						if local_area > 0.01:
							faces += 1
							area += local_area
							overlaps[id] = int(overlaps.get(id,0)) + 1
	return {"source_districts": overlaps.size(), "source_triangle_overlaps": faces, "overlap_area_px2": area, "by_selected_id": overlaps, "native_roofs": native_roofs}


func _capture(tree: SceneTree, map: Node, name_value: String) -> void:
	for frame in 3:
		await RenderingServer.frame_post_draw
	var screen := tree.root.get_texture().get_image()
	_fail += int(screen.save_png("res://bench/results/" + name_value + ".png") != OK)
	var native: Image = map._viewport.get_texture().get_image()
	_fail += int(native.save_png("res://bench/results/" + name_value + "_map.png") != OK)


func _export_roofs(addition: ArrayMesh, entries: Array, reference: Dictionary) -> void:
	var expected: Array = []
	var native: Array = []
	var candidate: Array = []
	for entry: Dictionary in entries:
		expected.append({"height": roundi(float(entry.max_real_h) * CombatUnit.PIXELS_PER_METER * 1000), "points": _points(entry.footprint)})
	for key: int in reference:
		for polygon: PackedVector2Array in reference[key]:
			native.append({"height": key, "points": _points(polygon)})
	var arrays := addition.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	for n in range(0, vertices.size(), 3):
		if normals[n].y < 0.99:
			continue
		candidate.append({"height": roundi(vertices[n].y * 1000), "points": [[vertices[n].x,vertices[n].z], [vertices[n+1].x,vertices[n+1].z], [vertices[n+2].x,vertices[n+2].z]]})
	var file := FileAccess.open("res://bench/results/tokyo_r49_roof_audit.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"expected": expected, "native": native, "candidate": candidate}))
	file.close()


func _points(polygon: PackedVector2Array) -> Array:
	var result: Array = []
	for p: Vector2 in polygon:
		result.append([p.x,p.y])
	return result
