extends RefCounted
const Ground := preload("res://scripts/experiments/tokyo_tile_ground_candidate.gd")
const Capture := preload("res://scripts/tests/tokyo_ao_review.gd")
const Pixels := preload("res://scripts/tests/tokyo_shell_review.gd")
const Static := preload("res://scripts/tests/tokyo_tile_ground_review.gd")
const Session := preload("res://scripts/rendering/tokyo_volume_preload.gd")


static func run(battle: Node, map: Node, output: String) -> int:
	var tree := battle.get_tree()
	var paused := tree.paused
	var source: RasterBasemapRenderer = battle._map_features._raster_basemap
	var mode := source.process_mode
	var ignore: bool = battle.camera.ignore_rotation
	var collision := var_to_bytes(BuildingRenderer._cache_entries)
	tree.paused = true
	source.process_mode = Node.PROCESS_MODE_ALWAYS
	battle.camera.ignore_rotation = false
	var rows: Array = []
	var residential := OS.get_environment("AGL_TOKYO_RESIDENTIAL_REVIEW")=="1"
	var destination := Vector2(-6130,-2195) if residential else Vector2(-6000,-3500)
	var geometry: RefCounted = null
	if residential:
		geometry=preload("res://scripts/tests/tokyo_draw_geometry_probe.gd").new()
		assert(geometry.setup(map))
	var atlas_observed := {"fine_draws":0,"fine_max_scale":0.0,"native_beyond_fine_draws":0,"double_draws":0,"borrowed_overlap_draws":0}
	var fail := 0
	var errors: Array[String] = []
	var frames := 0
	var borrowed_frames := 0
	var transition_frames := 0
	var previous_bind := -1
	var previous_nodes := PackedInt64Array()
	# 不只采样镜头插值：瓦片可能在后续等待阶段才开始淡入，观察每个实际绘制帧。
	var observed := {"draw_frames":0,"transition_draws":0,"invalid_borrow":0,"overscale_low":0,"overscale_records":[],"configurations":{},"candidate_draws":0,"candidate_lod3_draws":0,"candidate_lod4_draws":0,"candidate_lod5_draws":0}
	var candidate_directory := OS.get_environment("AGL_TOKYO_CANONICAL_CATALOG").get_base_dir()+"/"
	var observe := func() -> void:
		observed.draw_frames += 1
		observed.transition_draws += int(source._transitioning)
		var scale_value: float = float(map._viewport.size.y)/map._camera.size
		if map._tile_ground!=null and (source._transitioning or not Ground.texture_resolved(map._tile_ground.source_step,scale_value)):
			observed.invalid_borrow += 1
		var candidate_seen := false
		var candidate_lod3_seen := false
		var candidate_lod4_seen := false
		var candidate_lod5_seen := false
		var native_beyond_fine := false
		# 手动参考图会临时恢复原层；只把正式更新中的绘制计入切档断言。
		if map._fixed_atlas!=null and map.is_processing():
			for layer: RefCounted in map._fixed_atlas.members():
				if not is_instance_valid(layer._node) or not layer._node.visible:
					continue
				if layer._fine:
					atlas_observed.fine_draws+=1
					atlas_observed.fine_max_scale=maxf(atlas_observed.fine_max_scale,scale_value)
				if map._tile_ground!=null and layer.borrowed_overlap(layer._parent,map._tile_ground._tiles):
					atlas_observed.borrowed_overlap_draws+=1
				for saved: Dictionary in layer._held:
					var node: Variant = saved.node.get_ref()
					if typeof(node)==TYPE_OBJECT and is_instance_valid(node) and node.visible:
						atlas_observed.double_draws+=1
		for batch: Dictionary in map._batches.values():
			if not batch.nodes[0].visible:
				continue
			var identity: Dictionary = map._descriptors[batch.path].canonical_identity
			var configuration: String = identity.configuration
			if map.is_processing() and int(identity.get("parent",-1))==11 and batch.nodes[2].visible and scale_value>0.55:
				native_beyond_fine=true
			observed.configurations[configuration] = int(observed.configurations.get(configuration,0))+1
			var candidate_path := str(batch.path).replace("\\","/").begins_with(candidate_directory.replace("\\","/"))
			candidate_seen = candidate_seen or candidate_path
			candidate_lod3_seen = candidate_lod3_seen or (candidate_path and configuration=="lod3_full")
			candidate_lod4_seen = candidate_lod4_seen or (candidate_path and configuration=="lod4_full")
			candidate_lod5_seen = candidate_lod5_seen or (candidate_path and configuration=="lod5_full")
			if configuration in ["lod1_full","lod2_full","lod3_full","lod4_full"] and scale_value>float(preload("res://scripts/rendering/tokyo_volume_archive.gd").CUTS[int(identity.level)])*1.08+0.000001:
				observed.overscale_low += 1
				if observed.overscale_records.size()<24:
					observed.overscale_records.append({"frame":Engine.get_process_frames(),"scale":scale_value,"configuration":configuration,"path":batch.path,"level":map._level,"clock":map._lod_clock,"current_cluster":map._is_cluster(map._current_cut),"phase":map._phase,"target":map.paths_for(map._target_cut)})
		observed.candidate_draws += int(candidate_seen)
		atlas_observed.native_beyond_fine_draws+=int(native_beyond_fine)
		observed.candidate_lod3_draws += int(candidate_lod3_seen)
		observed.candidate_lod4_draws += int(candidate_lod4_seen)
		observed.candidate_lod5_draws += int(candidate_lod5_seen)
	RenderingServer.frame_post_draw.connect(observe)
	for pose: Vector2 in [Vector2(.18,0),Vector2(.26,0),Vector2(.4,0),Vector2(.65,0),Vector2(.98,0),Vector2(.26,14),Vector2(5,0),Vector2(.26,0)]:
		var start_position: Vector2 = battle.camera.position
		var start_zoom: float = battle.camera.zoom.x
		var start_rotation: float = battle.camera.rotation
		for step in 60:
			var t := (step+1)/60.0
			battle.camera.position = start_position.lerp(destination,t)
			battle.camera.zoom = Vector2.ONE*lerpf(start_zoom,pose.x,t)
			battle.camera.rotation = lerpf(start_rotation,deg_to_rad(pose.y),t)
			battle.camera.force_update_scroll()
			await tree.create_timer(.02).timeout
			frames += 1
			transition_frames += int(source._transitioning)
			if map._tile_ground != null:
				borrowed_frames += 1
				var ground: RefCounted = map._tile_ground
				if source._transitioning or not Ground.texture_resolved(ground.source_step,float(map._viewport.size.y)/map._camera.size):
					fail += 1
					errors.append("borrow invalid frame %d transition=%s step=%s scale=%s" % [frames,source._transitioning,ground.source_step,float(map._viewport.size.y)/map._camera.size])
				var nodes := PackedInt64Array()
				for node: MeshInstance3D in ground._nodes:
					nodes.append(node.get_instance_id())
				if map._tile_binds == previous_bind:
					if nodes != previous_nodes:
						fail += 1
						errors.append("plane identity changed without bind frame %d" % frames)
				previous_bind = map._tile_binds
				previous_nodes = nodes
		var ready := await Static._wait_source(source,tree)
		var source_after_wait := source.debug_state()
		var alpha_after_wait: Array = []
		for entry: Dictionary in source.presentation_tiles():
			var sprite: Variant = entry.sprite.get_ref()
			if typeof(sprite)==TYPE_OBJECT and is_instance_valid(sprite) and sprite.is_visible_in_tree():
				alpha_after_wait.append({"name":sprite.name,"alpha":sprite.modulate.a,"process":sprite.process_mode})
		var deadline := Time.get_ticks_msec()+15000
		while not Session.state_ready(map.debug_state()) and Time.get_ticks_msec()<deadline:
			await tree.process_frame
		await tree.create_timer(.2).timeout
		var state: Dictionary = map.debug_state()
		fail += int(not ready or not Session.state_ready(state))
		if not ready or not Session.state_ready(state):
			errors.append("readiness pose %s source=%s map=%s" % [pose,ready,Session.state_ready(state)])
		var expected := pose.x < .4
		fail += int((map._tile_ground != null) != expected)
		if (map._tile_ground != null) != expected:
			errors.append("coverage pose %s expected=%s" % [pose,expected])
		var stem := output.path_join("r77_%02d" % rows.size())
		map.set_process(false)
		source.set_process(false)
		var continuous := await Capture._capture(battle,map,stem+"_continuous")
		var projected: Dictionary = {}
		if not source.source_projection.is_empty():
			projected = await projected_check(battle,map,source,stem)
			fail += int(not projected.missing.is_empty() or projected.color_error>1 or not state.projected_source_reserved)
		map._release_tile_ground()
		await Capture._capture(battle,map,stem+"_original")
		var reference := Ground.new()
		if map._full_ground_region:
			reference.coverage_bounds=map._archive.bounds
		var bound := reference.bind(map,source,true,true)
		var image := await Capture._capture(battle,map,stem+"_reference")
		var error := Pixels._pixel_error(continuous,image)
		fail += int(not bound or error>1)
		if not bound or error>1:
			errors.append("pixel pose %s bound=%s error=%d" % [pose,bound,error])
		reference.close()
		map.set_process(true)
		source.set_process(true)
		rows.append({"pose":str(pose),"state":state,"reference_error":error,"bound":bound,"source_ready":ready,"source":source.debug_state(),"source_after_wait":source_after_wait,"alpha_after_wait":alpha_after_wait,"projected":projected})
		print("[R77 stream] pose=",pose," faces=",state.triangles," binds=",state.tile_binds," pixel=",error)
	RenderingServer.frame_post_draw.disconnect(observe)
	var geometry_report := {}
	if geometry!=null:
		geometry.close()
		geometry_report=geometry.summary()
		if geometry_report.runtime_samples==0 or geometry_report.reference_samples==0 or geometry_report.runtime_peak>240000 or geometry_report.runtime_underreported>0:
			fail+=1
			errors.append("runtime geometry gate: %s" % geometry_report.runtime_peak)
	var invalid := frames!=480 or borrowed_frames==0 or int(observed.transition_draws)==0 or int(observed.invalid_borrow)>0 or int(observed.overscale_low)>0 or collision!=var_to_bytes(BuildingRenderer._cache_entries)
	if OS.get_environment("AGL_TOKYO_BLOCK_DRAW_AUDIT")=="1":
		invalid = invalid or int(observed.candidate_draws)==0
	if OS.get_environment("AGL_TOKYO_BLOCK_LOD3")=="1":
		invalid = invalid or int(observed.candidate_lod3_draws)==0
	if OS.get_environment("AGL_TOKYO_BLOCK_LOD5")=="1":
		invalid = invalid or int(observed.candidate_lod5_draws)==0
	if OS.get_environment("AGL_TOKYO_BLOCK_MID6")=="1":
		invalid = invalid or int(observed.candidate_lod4_draws)==0
	if residential:
		invalid = invalid or atlas_observed.fine_draws==0 or atlas_observed.native_beyond_fine_draws==0 or atlas_observed.fine_max_scale>0.550001
	invalid = invalid or atlas_observed.double_draws>0 or atlas_observed.borrowed_overlap_draws>0
	fail += int(invalid)
	if invalid:
		errors.append("coverage or collision incomplete")
	map._release_tile_ground()
	source.process_mode = mode
	battle.camera.ignore_rotation = ignore
	tree.paused = paused
	var file := FileAccess.open(output.path_join("r77_stream.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"fail":fail,"errors":errors,"frames":frames,"borrowed_frames":borrowed_frames,"transition_frames":transition_frames,"observed":observed,"atlas_observed":atlas_observed,"runtime_geometry":geometry_report,"destination":str(destination),"rows":rows},"\t"))
	file.close()
	print("[R77 stream] fail=",fail," frames=",frames," borrowed=",borrowed_frames," transitions=",transition_frames)
	print("[R77 stream] errors=",errors)
	print("[R79 stream draw audit] ",observed)
	return fail


static func projected_check(battle: Node,map: Node,source: RasterBasemapRenderer,stem: String) -> Dictionary:
	var missing: Array[String] = []
	if source._current_lod!=RasterBasemapRenderer.LOD_STRATEGIC:
		var size: Vector2 = source.get_viewport_rect().size
		var inverse := source.get_global_transform_with_canvas().affine_inverse()
		var view := PackedVector2Array([inverse*Vector2.ZERO,inverse*Vector2(size.x,0),inverse*size,inverse*Vector2(0,size.y)])
		var level: Dictionary = source._manifest.levels[source._current_lod]
		var level_size := Vector2(level.size[0],level.size[1])
		var geo := preload("res://scripts/experiments/tokyo_raster_projection.gd")
		for key: String in source._records[source._current_lod]:
			var record: Dictionary = source._records[source._current_lod][key]
			var raw: Array = record.content_rect
			var top_left := source._world_rect.position+Vector2(raw[0],raw[1])/level_size*source._world_rect.size
			var bottom_right := top_left+Vector2(raw[2],raw[3])/level_size*source._world_rect.size
			top_left.y = geo.world_y(top_left.y,source.source_projection)
			bottom_right.y = geo.world_y(bottom_right.y,source.source_projection)
			var polygon := PackedVector2Array([top_left,Vector2(bottom_right.x,top_left.y),bottom_right,Vector2(top_left.x,bottom_right.y)])
			# 独立多边形相交，对照生产SAT；遍历完整源层，不复用其候选列表。
			if not Geometry2D.intersect_polygons(view,polygon).is_empty() and not source._sprites[source._current_lod].has(key):
				missing.append(key)
	var picture := await preload("res://scripts/tests/tokyo_ground_palette_review.gd").source_only(battle,source,map._viewport.size)
	assert(picture.save_png(stem+"_projected_source.png")==OK)
	var color_error := 0
	var pixels := 0
	if map._tile_ground!=null and not map._tile_ground._nodes.is_empty():
		var held: Array[Dictionary] = []
		for batch: Dictionary in map._batches.values():
			for node: MeshInstance3D in batch.nodes:
				held.append({"node":node,"visible":node.visible})
				node.hide()
		# 独立源色检查只保留借用瓦片；岸线是另一个受审层，不能混入地表像素真值。
		var shore_visible: Array[bool] = []
		if map._shoreline!=null:
			for node: MeshInstance3D in map._shoreline._nodes:
				shore_visible.append(node.visible)
				node.hide()
		if map._fixed_atlas!=null:
			for layer: RefCounted in map._fixed_atlas.members():
				if is_instance_valid(layer._node):
					held.append({"node":layer._node,"visible":layer._node.visible})
					layer._node.hide()
		var ground := await Capture._capture(battle,map,stem+"_projected_ground_only")
		if map._shoreline!=null:
			for index in shore_visible.size():
				map._shoreline._nodes[index].visible=shore_visible[index]
		for entry: Dictionary in held:
			entry.node.visible = entry.visible
		var a := picture.get_data()
		var b := ground.get_data()
		for i in range(0,b.size(),4):
			if b[i+3]!=255:
				continue
			pixels += 1
			for channel in 3:
				color_error = maxi(color_error,absi(int(a[i+channel])-int(b[i+channel])))
		if pixels==0:
			color_error = 255
	print("[R82 source check] missing=",missing," color=",color_error," pixels=",pixels," geometry=",source.projected_geometry_bytes())
	return {"missing":missing,"color_error":color_error,"compared_pixels":pixels,"geometry_bytes":source.projected_geometry_bytes()}
