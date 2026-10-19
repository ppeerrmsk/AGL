extends RefCounted
## 同一真实地图实例逐项还原；只验证覆盖候选，不是战斗帧时间门。
const Ground := preload("res://scripts/experiments/tokyo_tile_ground_candidate.gd")
const Capture := preload("res://scripts/tests/tokyo_ao_review.gd")
const Static := preload("res://scripts/tests/tokyo_tile_ground_review.gd")
const Session := preload("res://scripts/rendering/tokyo_volume_preload.gd")
const Pixels := preload("res://scripts/tests/tokyo_shell_review.gd")


static func run(battle: Node, map: Node, output: String) -> int:
	var tree := battle.get_tree()
	var paused := tree.paused
	var ignore: bool = battle.camera.ignore_rotation
	var source: RasterBasemapRenderer = battle._map_features._raster_basemap
	var mode := source.process_mode
	var collision := var_to_bytes(BuildingRenderer._cache_entries)
	tree.paused = true
	source.process_mode = Node.PROCESS_MODE_ALWAYS
	battle.camera.ignore_rotation = false
	var rows: Array = []
	var fail := 0
	var expanded: Rect2 = map._archive.bounds
	var poses := [Vector4(-5600,-1700,.26,0),Vector4(-5600,-1700,.65,0),Vector4(-5600,-3700,.26,0),Vector4(-5300,-700,.26,0),Vector4(-5600,-1700,.26,14),Vector4(-5600,-1700,1.3,0)]
	for pose: Vector4 in poses:
		battle.camera.position = Vector2(pose.x,pose.y)
		battle.camera.zoom = Vector2.ONE*pose.z
		battle.camera.rotation = deg_to_rad(pose.w)
		battle.camera.force_update_scroll()
		await tree.create_timer(.3).timeout
		var deadline := Time.get_ticks_msec()+15000
		while not Session.state_ready(map.debug_state()) and Time.get_ticks_msec()<deadline:
			await tree.process_frame
		var ready := await Static._wait_source(source,tree)
		if not ready or not Session.state_ready(map.debug_state()):
			rows.append({"pose":str(pose),"blocked":"readiness","map":map.debug_state()})
			fail += 1
			continue
		map.set_process(false)
		source.set_process(false)
		var stem := output.path_join("r96_%02d" % rows.size())
		var runtime := await Capture._capture(battle,map,stem+"_runtime")
		var runtime_stats: Dictionary = map.debug_state().tile_ground
		map._release_tile_ground()
		var original := await Capture._capture(battle,map,stem+"_original")
		var original_aux: int = map._stream.summary().auxiliary_bytes
		var held: Array[Dictionary] = []
		for batch: Dictionary in map._batches.values():
			for node: MeshInstance3D in batch.nodes:
				held.append({"node":node,"mesh":node.mesh,"material":node.material_override,"visible":node.visible})
		var source_image := await preload("res://scripts/tests/tokyo_ground_palette_review.gd").source_only(battle,source,map._viewport.size)
		assert(source_image.save_png(stem+"_source.png")==OK)
		var variants: Array = []
		for bounds: Rect2 in [Ground.BOUNDS,expanded]:
			var ground := Ground.new()
			ground.coverage_bounds = bounds
			var bound := ground.bind(map,source,true,true)
			var label := "local" if variants.is_empty() else "expanded"
			var stats: Dictionary = ground.stats.duplicate(true)
			var picture := await Capture._capture(battle,map,stem+"_"+label)
			var runtime_error := Pixels._pixel_error(runtime,picture) if label=="expanded" and map._full_ground_region else -1
			if runtime_error>=0:
				fail += int(runtime_error>1)
			var visible: Array[bool] = []
			for entry: Dictionary in held:
				visible.append(entry.node.visible)
				entry.node.hide()
			await Capture._capture(battle,map,stem+"_"+label+"_ground")
			for i in held.size():
				held[i].node.visible = visible[i]
			var live: Array[WeakRef] = []
			for node: MeshInstance3D in ground._nodes:
				live.append(weakref(node))
			var tiles: Array = []
			for rect: Rect2 in ground._tiles:
				tiles.append([rect.position.x,rect.position.y,rect.size.x,rect.size.y])
			var joint: int = map._stream.summary().total_bytes
			ground.close()
			ground.close()
			await tree.process_frame
			var restored := await Capture._capture(battle,map,stem+"_"+label+"_restored")
			var unchanged := original_aux==int(map._stream.summary().auxiliary_bytes) and collision==var_to_bytes(BuildingRenderer._cache_entries)
			for entry: Dictionary in held:
				unchanged = unchanged and entry.node.mesh==entry.mesh and entry.node.material_override==entry.material and entry.node.visible==entry.visible
			for ref: WeakRef in live:
				unchanged = unchanged and ref.get_ref()==null
			var error := Pixels._pixel_error(original,restored)
			fail += int(not bound or not unchanged or error>1 or joint>96*1024*1024)
			variants.append({"label":label,"bound":bound,"stats":stats,"tiles":tiles,"joint_bytes":joint,"restore_error":error,"runtime_error":runtime_error,"unchanged":unchanged,"changed":Pixels._pixel_error(original,picture)})
		var corners: Array = []
		for corner: Vector2 in [Ground.BOUNDS.position,Vector2(Ground.BOUNDS.end.x,Ground.BOUNDS.position.y),Ground.BOUNDS.end,Vector2(Ground.BOUNDS.position.x,Ground.BOUNDS.end.y)]:
			var point: Vector2 = map._camera.unproject_position(Vector3(corner.x,0,corner.y))
			corners.append([point.x,point.y])
		rows.append({"pose":str(pose),"stem":stem,"variants":variants,"old_window_screen":corners,"expanded_bounds":str(expanded),"runtime_full_region":map._full_ground_region,"runtime_stats":runtime_stats,"map":map.debug_state()})
		map._viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		map.set_process(true)
		source.set_process(true)
		print("[R96 boundary] pose=",pose," expanded=",expanded," variants=",variants)
	source.process_mode = mode
	battle.camera.ignore_rotation = ignore
	tree.paused = paused
	var file := FileAccess.open(output.path_join("r96_boundary.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"fail":fail,"rows":rows,"fps_evidence":false},"\t"))
	file.close()
	return fail
