extends RefCounted
const Ground := preload("res://scripts/experiments/tokyo_tile_ground_candidate.gd")
const Session := preload("res://scripts/rendering/tokyo_volume_preload.gd")
const Capture := preload("res://scripts/tests/tokyo_ao_review.gd")
const Pixels := preload("res://scripts/tests/tokyo_shell_review.gd")


static func run(battle: Node, map: Node, output: String) -> int:
	var tree := battle.get_tree()
	var paused := tree.paused
	var ignore: bool = battle.camera.ignore_rotation
	tree.paused = true
	battle.camera.ignore_rotation = false
	var source: RasterBasemapRenderer = battle._map_features._raster_basemap
	var source_process := source.process_mode
	# 静态截图暂停战斗，但瓦片owner必须继续完成当前相机对应的真实LOD请求。
	source.process_mode = Node.PROCESS_MODE_ALWAYS
	var collision := var_to_bytes(BuildingRenderer._cache_entries)
	var rows: Array = []
	var fail := 0
	var replace_fixed := OS.get_environment("AGL_TOKYO_TILE_FIXED_REPLACE") == "1"
	for pose: Vector2 in [Vector2(.18,0), Vector2(.26,0), Vector2(.4,0), Vector2(.65,0), Vector2(.98,0), Vector2(.26,14), Vector2(5,0), Vector2(.26,0)]:
		battle.camera.position = Vector2(-6000,-3500)
		battle.camera.zoom = Vector2.ONE * pose.x
		battle.camera.rotation = deg_to_rad(pose.y)
		battle.camera.force_update_scroll()
		await tree.create_timer(.3).timeout
		var deadline := Time.get_ticks_msec() + 15000
		while not Session.state_ready(map.debug_state()) and Time.get_ticks_msec() < deadline:
			await tree.process_frame
		if not Session.state_ready(map.debug_state()) or not await _wait_source(source, tree):
			rows.append({"pose":str(pose), "blocked":"source readiness", "map":map.debug_state(), "basemap":source.debug_state()})
			fail += 1
			continue
		map.set_process(false)
		var stem := output.path_join("r71_ground_%02d" % rows.size())
		var before := await Capture._capture(battle, map, stem + "_original")
		var original_aux: int = map._stream.summary().auxiliary_bytes
		map._screen.hide()
		await Capture._capture(battle, map, stem + "_2d")
		map._screen.show()
		var original_visibility: Dictionary = {}
		var actual_before := 0
		for batch: Dictionary in map._batches.values():
			for node: MeshInstance3D in batch.nodes:
				original_visibility[node.get_instance_id()] = node.visible
				if node.visible:
					actual_before += preload("res://scripts/experiments/tokyo_indexed_mesh.gd").triangles(node.mesh)
		var ground := Ground.new()
		if not ground.bind(map, source, false, replace_fixed):
			rows.append({"pose":str(pose),"blocked":"ground binding", "state":map.debug_state()})
			ground.close()
			fail += 1
			map.set_process(true)
			continue
		var ground_stats := ground.stats.duplicate(true)
		var actual_after := int(ground_stats.extra_faces)
		for batch: Dictionary in map._batches.values():
			for node: MeshInstance3D in batch.nodes:
				if node.visible:
					actual_after += preload("res://scripts/experiments/tokyo_indexed_mesh.gd").triangles(node.mesh)
		ground_stats.merge({"actual_faces_before":actual_before,"actual_faces_after":actual_after})
		var held: Array[Dictionary] = []
		for batch: Dictionary in map._batches.values():
			for layer in batch.nodes.size():
				var node: MeshInstance3D = batch.nodes[layer]
				held.append({"node": node, "visible": node.visible, "mesh": node.mesh, "layer":layer})
				node.hide()
		await Capture._capture(battle, map, stem + "_ground_only")
		for entry: Dictionary in held:
			entry.node.visible = entry.visible
		await Capture._capture(battle, map, stem + "_candidate")
		if OS.get_environment("AGL_TOKYO_GROUND_LAYERS") == "1":
			# 仅暂停的审查机位逐层隔离；不用于实际LOD或性能统计。
			for layer in 3:
				for entry: Dictionary in held:
					entry.node.visible = entry.visible and entry.layer != layer
				await Capture._capture(battle, map, stem + "_without_%d" % layer)
			for entry: Dictionary in held:
				entry.node.visible = entry.visible
			var layer_restore := await Capture._capture(battle, map, stem + "_layers_restored")
			var layer_original := Image.load_from_file(stem + "_candidate_native.png")
			fail += int(Pixels._pixel_error(layer_original, layer_restore) > 1)
			for directional: float in [0.25,0.10]:
				var saved_materials: Array[Dictionary] = []
				var replacements: Dictionary = {}
				for entry: Dictionary in held:
					if entry.layer != 0:
						continue
					var material: ShaderMaterial = entry.node.material_override
					if not replacements.has(material.get_instance_id()):
						var code := preload("res://scripts/experiments/tokyo_low_light_candidate.gd").shader_code(material.shader.code,directional)
						if code.is_empty():
							fail += 1
							continue
						var replacement: ShaderMaterial = material.duplicate()
						var shader := Shader.new()
						shader.code = code
						replacement.shader = shader
						replacements[material.get_instance_id()] = replacement
					saved_materials.append({"node":entry.node,"material":material})
					entry.node.material_override = replacements[material.get_instance_id()]
				await Capture._capture(battle,map,stem+"_light_%02d" % roundi(directional*100))
				for saved: Dictionary in saved_materials:
					saved.node.material_override = saved.material
				var material_restore := await Capture._capture(battle,map,stem+"_light_%02d_restored" % roundi(directional*100))
				fail += int(Pixels._pixel_error(layer_original,material_restore)>1)
		var weak_nodes: Array[WeakRef] = []
		for node: MeshInstance3D in ground._nodes:
			weak_nodes.append(weakref(node))
		ground.close()
		if not ground.bind(map, source, true, replace_fixed):
			fail += 1
		else:
			await Capture._capture(battle, map, stem + "_shadow")
		ground.close()
		ground.close()
		await tree.process_frame
		var restored := await Capture._capture(battle, map, stem + "_restored")
		var exact := true
		for entry: Dictionary in held:
			exact = exact and entry.node.mesh == entry.mesh and entry.node.visible == original_visibility[entry.node.get_instance_id()]
		for node: WeakRef in weak_nodes:
			exact = exact and node.get_ref() == null
		exact = exact and map._stream.summary().auxiliary_bytes == original_aux and var_to_bytes(BuildingRenderer._cache_entries) == collision
		var error := Pixels._pixel_error(before, restored)
		fail += int(not exact or error > 1)
		rows.append({"pose": str(pose), "stem": stem, "ground": ground_stats, "restore_error": error, "state_unchanged": exact, "state": map.debug_state()})
		map._viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		map.set_process(true)
		print("[R71 ground] pose=",pose," planes=",ground_stats.planes," actual_faces=",actual_before,"->",actual_after," retired_fixed=",ground_stats.get("retired_fixed_faces",0)," restore=",error," state=",exact)
	tree.paused = paused
	source.process_mode = source_process
	battle.camera.ignore_rotation = ignore
	var file := FileAccess.open(output.path_join("r71_review.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"rows":rows,"fail":fail,"static_only":true,"bounds":str(Ground.BOUNDS)},"\t"))
	file.close()
	return fail


static func _wait_source(source: RasterBasemapRenderer, tree: SceneTree) -> bool:
	var deadline := Time.get_ticks_msec() + 10000
	while Time.get_ticks_msec() < deadline:
		var state := source.debug_state()
		var stable: bool = state.current_lod == state.target_lod and not state.transitioning and state.pending_count == 0 and state.missing_keys.is_empty()
		for entry: Dictionary in source.presentation_tiles():
			var sprite: Variant = entry.sprite.get_ref()
			if typeof(sprite) == TYPE_OBJECT and is_instance_valid(sprite) and sprite.is_visible_in_tree() and sprite.modulate.a < 0.999999:
				stable = false
		if stable:
			return true
		await tree.process_frame
	return false
