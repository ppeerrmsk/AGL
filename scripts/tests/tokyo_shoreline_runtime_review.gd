extends RefCounted
const Session := preload("res://scripts/rendering/tokyo_volume_preload.gd")
const Static := preload("res://scripts/tests/tokyo_tile_ground_review.gd")
const Capture := preload("res://scripts/tests/tokyo_ao_review.gd")
const Pixels := preload("res://scripts/tests/tokyo_shell_review.gd")


static func cancelled_loading(parent: Node) -> int:
	var directory := OS.get_environment("AGL_TOKYO_SHORELINE")
	OS.set_environment("AGL_TOKYO_SHORELINE",directory.path_join("intentional_missing"))
	var owner := Node2D.new()
	parent.add_child(owner)
	var ref: WeakRef = Session.start(owner,Vector2(-5300,-1100),.65)
	var deadline := Time.get_ticks_msec()+5000
	for frame in 2:
		await parent.get_tree().process_frame
	while ref!=null and ref.get_ref()!=null and Time.get_ticks_msec()<deadline:
		await parent.get_tree().process_frame
	var rejected := ref!=null and ref.get_ref()==null
	owner.queue_free()
	await parent.get_tree().process_frame
	OS.set_environment("AGL_TOKYO_SHORELINE",directory)
	print("[R99 missing shore] rejected_and_released=",rejected)
	return int(not rejected)


static func run(battle: Node, map: Node, output: String) -> int:
	if map._shoreline==null or map._shoreline.warm_mask!=7:
		return 1
	var layer: RefCounted = map._shoreline
	var ids: PackedInt64Array = layer.stats.mesh_ids.duplicate()
	var tree := battle.get_tree()
	var paused := tree.paused
	var source: RasterBasemapRenderer = battle._map_features._raster_basemap
	var mode := source.process_mode
	var ignore: bool = battle.camera.ignore_rotation
	tree.paused = true
	source.process_mode = Node.PROCESS_MODE_ALWAYS
	battle.camera.ignore_rotation = false
	var collision := var_to_bytes(BuildingRenderer._cache_entries)
	var rows: Array = []
	var fail := 0
	var poses := [Vector4(-5300,-1100,.26,0),Vector4(-5300,-1100,.65,0),Vector4(-5300,-1100,.98,14),Vector4(-5300,-1100,1.2,0),Vector4(-4700,-1700,1.3,0),Vector4(-5350,-1080,2.4,-14),Vector4(-5350,-1080,5.0,0),Vector4(-5300,-1100,.26,0)]
	for pose: Vector4 in poses:
		battle.camera.position = Vector2(pose.x,pose.y)
		battle.camera.zoom = Vector2.ONE*pose.z
		battle.camera.rotation = deg_to_rad(pose.w)
		battle.camera.force_update_scroll()
		await tree.create_timer(.3).timeout
		var deadline := Time.get_ticks_msec()+15000
		while not Session.state_ready(map.debug_state()) and Time.get_ticks_msec()<deadline:
			await tree.process_frame
		if not await Static._wait_source(source,tree) or not Session.state_ready(map.debug_state()):
			rows.append({"pose":str(pose),"blocked":"readiness","map":map.debug_state()})
			fail += 1
			continue
		map.set_process(false)
		source.set_process(false)
		var state: Dictionary = map.debug_state()
		var held: Array[Dictionary] = []
		for batch: Dictionary in map._batches.values():
			for node: MeshInstance3D in batch.nodes:
				held.append({"node":node,"mesh":node.mesh,"material":node.material_override,"visible":node.visible})
		var tiles: Array[Rect2] = []
		if map._tile_ground!=null:
			tiles.assign(map._tile_ground._tiles)
		var stem := output.path_join("r99_%02d"%rows.size())
		var actual := await Capture._capture(battle,map,stem+"_runtime")
		var projected: Array = []
		for node_index in layer._nodes.size():
			var node: MeshInstance3D = layer._nodes[node_index]
			if not node.visible:
				continue
			var arrays := node.mesh.surface_get_arrays(0)
			var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			for index in points.size():
				var point := points[index]
				if layer._morph:
					var offset: Vector2 = arrays[Mesh.ARRAY_TEX_UV][index]
					var factor: float = node.material_override.get_shader_parameter("shoreline_morph_t")
					point += Vector3(offset.x,0,offset.y)*factor
				var screen: Vector2 = map._camera.unproject_position(map._city.to_global(point))
				projected.append([screen.x,screen.y])
		var cover: Array = []
		for rect: Rect2 in tiles:
			var polygon: Array = []
			for point: Vector2 in [rect.position,Vector2(rect.end.x,rect.position.y),rect.end,Vector2(rect.position.x,rect.end.y)]:
				var screen: Vector2 = map._camera.unproject_position(map._city.to_global(Vector3(point.x,.03,point.y)))
				polygon.append([screen.x,screen.y])
			cover.append(polygon)
		layer.hide()
		var without := await Capture._capture(battle,map,stem+"_without")
		layer.update(.5,tiles,true)
		await Capture._capture(battle,map,stem+"_wide")
		layer.update(state.output_scale,tiles,map._active)
		var restored := await Capture._capture(battle,map,stem+"_restored")
		var unchanged: bool = collision==var_to_bytes(BuildingRenderer._cache_entries) and ids==layer.stats.mesh_ids
		for entry: Dictionary in held:
			unchanged = unchanged and entry.node.mesh==entry.mesh and entry.node.material_override==entry.material and entry.node.visible==entry.visible
		var error := Pixels._pixel_error(actual,restored)
		fail += int(not unchanged or error>1 or int(state.stream.total_bytes)>96*1024*1024 or int(state.max_transition_triangles)<int(state.tile_peak_faces))
		rows.append({"pose":str(pose),"map":state,"projected_triangles":projected,"covered_polygons":cover,"unchanged":unchanged,"restore_error":error,"changed":Pixels._pixel_error(actual,without)})
		map._viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		map.set_process(true)
		source.set_process(true)
		print("[R99 shore runtime] pose=",pose," levels=",state.shoreline.levels," faces=",state.shoreline.faces," restore=",error," fail=",fail)
	source.process_mode = mode
	battle.camera.ignore_rotation = ignore
	tree.paused = paused
	var file := FileAccess.open(output.path_join("r99_shoreline.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"fail":fail,"rows":rows,"fps_evidence":false},"\t"))
	file.close()
	return fail
