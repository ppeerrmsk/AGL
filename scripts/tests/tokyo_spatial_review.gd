extends RefCounted
## 同SceneTree检验无损空间布局；复用最多16组三层节点，不把同步试装冒充正式流送。
const Select := preload("res://scripts/experiments/tokyo_spatial_select.gd")
const Indexed := preload("res://scripts/experiments/tokyo_indexed_mesh.gd")
const ShellReview := preload("res://scripts/tests/tokyo_shell_review.gd")
const SurfaceOwner := preload("res://scripts/experiments/tokyo_surface_owner.gd")
const Builder := preload("res://scripts/tests/build_tokyo_cells.gd")
const Cut := preload("res://scripts/experiments/tokyo_spatial_cut.gd")
var _fail := 0


func run(owner: Node2D) -> int:
	var control := OS.get_environment("AGL_TOKYO_SPATIAL_CONTROL")
	var hierarchical := control in ["hierarchy_native", "hierarchy_greedy"]
	var owned_native := control == "owned_native" or hierarchical
	var catalog_path := "res://resources/maps/tokyo_volume_preview/r39_pages/index.res" if owned_native else "res://resources/maps/tokyo_volume_preview/r38_pages/index.res"
	if hierarchical:
		catalog_path = "res://resources/maps/tokyo_volume_preview/r40_pages/index.res"
	var catalog: Resource = load(catalog_path)
	assert(catalog.valid() and OS.get_environment("AGL_TOKYO_CELLS_VARIANT") == "yokohama_joined_coastal")
	var overlay: Node = owner.features._tokyo_volume
	assert(catalog.source_hash == overlay._archive.source_hash)
	var poses := [["yokohama", Vector2(-5300, -700), 2.2, 0.0], ["housing", Vector2(-6110, -350), 5.0, 0.0],
		["north_city", Vector2(-5600, -2900), 2.2, 0.0], ["industrial", Vector2(-4300, -2700), 2.2, 0.0],
		["seam", Vector2(-5300, -1700), 2.2, 0.0], ["seam_rotated", Vector2(-5300, -1700), 2.2, deg_to_rad(14)],
		["piers", Vector2(-5150, -480), 5.0, 0.0], ["north_close", Vector2(-5600, -2900), 5.0, deg_to_rad(14)]]
	if control in ["all_children", "known_roots", "low_roots", "fixed_roots", "no_shadows", "surface_probe"] or control.begins_with("known_surface_owner"):
		poses = [["piers", Vector2(-5150, -480), 5.0, 0.0]]
	if control in ["covered_multi", "owned_native"] or hierarchical:
		poses.append_array([["piers_mid", Vector2(-5150, -480), 2.2, 0.0],
			["piers_rotated", Vector2(-5150, -480), 5.0, deg_to_rad(14)],
			["piers_close", Vector2(-5150, -480), 10.0, 0.0]])
	var reports: Array[Dictionary] = []
	for pose: Array in poses:
		owner.camera.position = pose[1]
		owner.camera.zoom = Vector2.ONE * float(pose[2])
		owner.camera.rotation = pose[3]
		owner.camera.force_update_scroll()
		await owner.get_tree().create_timer(0.3).timeout
		var deadline := Time.get_ticks_msec() + 15000
		var state: Dictionary = overlay.debug_state()
		while (state.level != 5 or state.ready_cells != state.desired_cells or state.stream.pending > 0) and Time.get_ticks_msec() < deadline:
			await owner.get_tree().process_frame
			state = overlay.debug_state()
		assert(state.level == 5 and state.ready_cells == state.desired_cells and state.stream.pending == 0 and state.stream.failures.is_empty())
		await owner.get_tree().create_timer(2.0).timeout
		state = overlay.debug_state()
		var inverse: Basis = overlay._city.basis.inverse()
		var camera_ray: Vector3 = inverse * overlay._camera.basis.z
		var light_ray: Vector3 = inverse * overlay._sun.basis.z
		var roof := -Vector2(camera_ray.x, camera_ray.z) / camera_ray.y
		var shadow := -Vector2(light_ray.x, light_ray.z) / light_ray.y
		var logical: Vector2 = Vector2(overlay._viewport.size) * overlay._screen.scale
		var query := Select.choose(catalog.parents, overlay._cull_view, overlay._last_canvas, logical, roof, shadow)
		if control == "hierarchy_native":
			query = Cut.choose(catalog.parents, overlay._cull_view, overlay._last_canvas, logical, roof, shadow)
		if control in ["known_roots", "low_roots", "fixed_roots"]:
			# 逐层定位对照：指定层恢复原父批次，其余层继续分桶，不改变原网格。
			var retained_kind: int = {"known_roots": 1, "low_roots": 0, "fixed_roots": 2}[control]
			for entry: Dictionary in query.entries:
				if entry.mask[retained_kind]:
					query.triangles -= int(entry.triangles[retained_kind])
				entry.mask[retained_kind] = false
			for parent: Dictionary in catalog.parents:
				var entry := Select.visible(parent, overlay._cull_view, overlay._last_canvas, logical, roof, shadow)
				if not entry.mask[retained_kind]:
					continue
				for kind in 3:
					entry.mask[kind] = kind == retained_kind
				query.entries.append(entry)
				query.triangles += int(entry.triangles[retained_kind])
				query.bytes += int(entry.bytes)
			query.active = query.entries.size()
			query.within_budget = query.active <= 16 and query.bytes <= 96 * 1024 * 1024 and query.triangles <= 240000
		if control == "all_children":
			# 负对照：父包原来可见的层全部按四子包提交，不用子包包络剔除。
			query = {"entries": [], "triangles": 0, "bytes": 0, "active": 0, "within_budget": false}
			for parent: Dictionary in catalog.parents:
				var original_visible := Select.visible(parent, overlay._cull_view, overlay._last_canvas, logical, roof, shadow)
				if original_visible.faces == 0:
					continue
				for child: Dictionary in parent.children:
					var entry := child.duplicate()
					entry["mask"] = original_visible.mask
					query.entries.append(entry)
					query.bytes += int(entry.bytes)
					for kind in 3:
						query.triangles += int(entry.triangles[kind]) if entry.mask[kind] else 0
			query.active = query.entries.size()
			query.within_budget = query.active <= 16 and query.bytes <= 96 * 1024 * 1024 and query.triangles <= 240000
		var coarse_faces := 0
		for parent: Dictionary in catalog.parents:
			var original := parent.duplicate()
			if owned_native:
				original.boxes = parent.original_boxes
				original.triangles = parent.original_triangles
			coarse_faces += int(Select.visible(original, overlay._cull_view, overlay._last_canvas, logical, roof, shadow).faces)
		assert(coarse_faces == int(state.triangles), "metadata visibility must reproduce actual old submissions")
		var resources: Array[Resource] = []
		var mesh_sets: Array = []
		var extra_bytes := 0
		for entry: Dictionary in query.entries:
			if int(entry.cell_id) < 0:
				assert(overlay._batches.has(int(entry.parent_id)))
				var batch: Dictionary = overlay._batches[int(entry.parent_id)]
				if owned_native:
					var root: Resource = ResourceLoader.load(entry.building, "", ResourceLoader.CACHE_MODE_IGNORE)
					assert(root.valid() and root.height_hash == batch.building.height_hash)
					resources.append(root)
					extra_bytes += root.geometry_bytes
					mesh_sets.append([root.meshes[0], root.meshes[1], batch.fixed.meshes[0]])
				else:
					mesh_sets.append([batch.building.meshes[0], batch.building.meshes[1], batch.fixed.meshes[0]])
			else:
				var page: Resource = ResourceLoader.load(entry.path, "", ResourceLoader.CACHE_MODE_IGNORE)
				assert(page.valid() and page.source_hash == entry.source_hash and page.height_hash == entry.height_hash and page.geometry_bytes == entry.bytes)
				resources.append(page)
				mesh_sets.append(page.meshes)
				extra_bytes += page.geometry_bytes
		assert(query.active <= 16 and int(state.stream.bytes) + extra_bytes <= 96 * 1024 * 1024)
		var slots: Array = []
		var saved: Array[Dictionary] = []
		for batch: Dictionary in overlay._batches.values():
			slots.append(batch.nodes)
			for node: MeshInstance3D in batch.nodes:
				saved.append({"node": node, "mesh": node.mesh, "visible": node.visible, "cast": node.cast_shadow})
		var extras: Array[Node] = []
		while slots.size() < int(query.active):
			var nodes: Array[MeshInstance3D] = []
			for kind in 3:
				var node: MeshInstance3D = overlay._add_mesh(null, overlay._materials[4 if kind == 2 else kind], kind < 2)
				node.hide()
				nodes.append(node)
				extras.append(node)
			slots.append(nodes)
		assert(slots.size() * 3 <= 48)
		overlay.set_process(false)
		var canonical_removed := 0
		var canonical_extra_bytes := 0
		if control.begins_with("known_surface_owner") or control == "covered_multi" or owned_native:
			for batch: Dictionary in overlay._batches.values():
				var resolved := SurfaceOwner.resolve(batch.building.meshes[0], batch.building.meshes[1], control in ["known_surface_owner_covered", "covered_multi"] or owned_native)
				if resolved.changed:
					canonical_extra_bytes += Builder.mesh_bytes(resolved.mesh)
					canonical_removed += resolved.removed.size() if batch.nodes[0].visible else 0
					for entry: Dictionary in saved:
						if entry.node == batch.nodes[0]:
							entry["original_mesh"] = entry.mesh
							entry.mesh = resolved.mesh
							entry.node.mesh = resolved.mesh
			for n in mesh_sets.size():
				var resolved := SurfaceOwner.resolve(mesh_sets[n][0], mesh_sets[n][1], control in ["known_surface_owner_covered", "covered_multi"] or owned_native)
				assert(not owned_native or not resolved.changed, "saved canonical meshes require no runtime ownership patch")
				if resolved.changed:
					canonical_extra_bytes += Builder.mesh_bytes(resolved.mesh)
					mesh_sets[n] = mesh_sets[n].duplicate()
					mesh_sets[n][0] = resolved.mesh
					if query.entries[n].mask[0]:
						query.triangles -= resolved.removed.size()
			assert(int(state.stream.bytes) + extra_bytes + canonical_extra_bytes <= 96 * 1024 * 1024)
		var shadow_enabled: bool = overlay._sun.shadow_enabled
		if control in ["no_shadows", "known_surface_owner_no_shadows"]:
			overlay._sun.shadow_enabled = false
		var stem := "res://bench/results/tokyo_r38_" + String(pose[0])
		var original: Image = await _capture(owner, overlay, stem + "_original.png")
		if control == "surface_probe":
			_probe_surfaces(overlay, catalog)
		if control == "known_surface_owner_probe":
			for sample: Vector2 in [Vector2(388.5, 729.5), Vector2(385.5, 734.5), Vector2(365.5, 736.5), Vector2(383.5, 737.5)]:
				_probe_surfaces(overlay, catalog, sample, true)
		for nodes: Array in slots:
			for node: MeshInstance3D in nodes:
				node.hide()
		var actual_faces := 0
		for n in query.entries.size():
			var entry: Dictionary = query.entries[n]
			for kind in 3:
				var node: MeshInstance3D = slots[n][kind]
				node.mesh = mesh_sets[n][kind]
				node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if kind < 2 else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				node.visible = entry.mask[kind]
				actual_faces += Indexed.triangles(node.mesh) if node.visible else 0
		assert(actual_faces == int(query.triangles))
		var candidate: Image = await _capture(owner, overlay, stem + "_candidate.png")
		for entry: Dictionary in saved:
			entry.node.mesh = entry.mesh
			entry.node.visible = entry.visible
			entry.node.cast_shadow = entry.cast
		for node: Node in extras:
			node.hide()
			node.mesh = null
			node.queue_free()
		var restored: Image = await _capture(owner, overlay, stem + "_restored.png")
		var restore_error := ShellReview._pixel_error(original, restored)
		var pixel_error := ShellReview._pixel_error(original, candidate)
		for entry: Dictionary in saved:
			if entry.has("original_mesh"):
				entry.node.mesh = entry.original_mesh
		overlay._sun.shadow_enabled = shadow_enabled
		_fail += int(restore_error > 1 or pixel_error > 1)
		overlay._viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		overlay.set_process(true)
		var keys: Array[String] = []
		for entry: Dictionary in query.entries:
			keys.append(entry.key)
		reports.append({"pose": pose[0], "zoom": pose[2], "rotation": pose[3], "coarse_state": state,
			"active": query.active, "nodes": slots.size() * 3, "keys": keys, "coarse_faces": coarse_faces, "candidate_faces": actual_faces,
			"selected_bytes": query.bytes, "review_resident_bytes": int(state.stream.bytes) + extra_bytes + canonical_extra_bytes,
			"canonical_removed": canonical_removed, "canonical_extra_bytes": canonical_extra_bytes,
			"solver_usec": query.get("solver_usec", 0), "visited": query.get("visited", 0), "frontier_states": query.get("frontier_states", 0),
			"within_budget": query.within_budget, "restore_error": restore_error, "pixel_error": pixel_error})
		print("[Tokyo spatial review] pose=", pose[0], " faces=", coarse_faces, "->", actual_faces, " active=", query.active, " pixel_error=", pixel_error)
		mesh_sets.clear()
		resources.clear()
	var file := FileAccess.open("res://bench/results/tokyo_r38_review.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"preview_only": true, "control": control, "fail": _fail, "records": reports}, "\t"))
	file.close()
	print("[Tokyo spatial review] captures=", reports.size(), " fail=", _fail)
	return _fail


func _capture(owner: Node2D, overlay: Node, path: String) -> Image:
	overlay._viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	for frame in 5:
		await RenderingServer.frame_post_draw
	var image := owner.get_viewport().get_texture().get_image()
	_fail += int(image.save_png(path) != OK)
	return image


func _probe_surfaces(overlay: Node, catalog: Resource, sample: Vector2 = Vector2(360.5, 730.5), canonical: bool = false) -> void:
	# 只读诊断：在差异像素的真实相机投影下列出原生覆盖三角，禁止推测后直接删面。
	var hits: Array[Dictionary] = []
	var camera_inverse: Transform3D = overlay._camera.global_transform.affine_inverse()
	for parent_id: int in overlay._batches:
		var batch: Dictionary = overlay._batches[parent_id]
		for kind in 2:
			var mesh: ArrayMesh = batch.nodes[kind].mesh if canonical else batch.building.meshes[kind]
			if mesh.get_surface_count() == 0:
				continue
			var arrays := mesh.surface_get_arrays(0)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var indices := PackedInt32Array()
			if arrays[Mesh.ARRAY_INDEX] != null:
				indices = arrays[Mesh.ARRAY_INDEX]
			var projected := PackedVector2Array()
			for point: Vector3 in vertices:
				projected.append(overlay._camera.unproject_position(overlay._city.to_global(point)))
			var count := indices.size() if not indices.is_empty() else vertices.size()
			for offset in range(0, count, 3):
				var ids := PackedInt32Array()
				for n in 3:
					ids.append(indices[offset + n] if not indices.is_empty() else offset + n)
				if not Geometry2D.point_is_inside_triangle(sample, projected[ids[0]], projected[ids[1]], projected[ids[2]]):
					continue
				var points: Array = []
				var normals: Array = []
				var colors: Array = []
				var pixels: Array = []
				var depth: Array = []
				var center := Vector3.ZERO
				for id in ids:
					var p: Vector3 = vertices[id]
					var normal: Vector3 = arrays[Mesh.ARRAY_NORMAL][id]
					var color: Color = arrays[Mesh.ARRAY_COLOR][id]
					points.append([p.x, p.y, p.z])
					normals.append([normal.x, normal.y, normal.z])
					colors.append([color.r, color.g, color.b, color.a])
					pixels.append([projected[id].x, projected[id].y])
					depth.append(-(camera_inverse * overlay._city.to_global(p)).z)
					center += p / 3.0
				var split: GDScript = load("res://scripts/experiments/tokyo_spatial_split.gd")
				hits.append({"parent": parent_id, "layer": kind, "face": offset / 3,
					"page": parent_id * 4 + split.bucket(Vector2(center.x, center.z), catalog.parents[parent_id].cuts),
					"vertices": points, "normals": normals, "colors": colors, "pixels": pixels, "depth": depth})
	var name_value := "tokyo_r39_probe_%d_%d.json" % [int(sample.x), int(sample.y)] if canonical else "tokyo_r38_surface_probe.json"
	var file := FileAccess.open("res://bench/results/" + name_value, FileAccess.WRITE)
	file.store_string(JSON.stringify({"sample": [sample.x, sample.y], "hits": hits}, "\t"))
	file.close()
	print("[Tokyo spatial probe] covering_triangles=", hits.size())
