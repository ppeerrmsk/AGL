extends RefCounted
## 独立候选的真实同池加载/保留/释放，不把资源ready当作画面覆盖或战斗性能。
const Contract := preload("res://scripts/rendering/tokyo_hlod_manifest.gd")
const Cut := preload("res://scripts/experiments/tokyo_spatial_cut.gd")
const MapProjection := preload("res://scripts/experiments/volume_projection.gd")
const Stream := preload("res://scripts/rendering/tokyo_hlod_stream.gd")


static func read_partition(binding: Variant) -> Dictionary:
	if not Contract.binding(binding) or FileAccess.get_sha256(binding.path)!=binding.sha256: return {}
	var file := FileAccess.open(binding.path,FileAccess.READ)
	if file==null: return {}
	var data: Variant=file.get_var(false)
	file.close()
	if not data is Dictionary or data.get("schema") not in [2,3] or not data.get("pages") is Dictionary or not data.get("tree") is Dictionary: return {}
	return data


static func run(parent: Node, path: String, expected: String) -> int:
	if not Contract.sha(expected) or FileAccess.get_sha256(path)!=expected: return 1
	var input: Variant=JSON.parse_string(FileAccess.get_file_as_string(path))
	if input is Dictionary and input.has("vector_roof_compare"):
		return await preload("res://scripts/tests/tokyo_vector_roof_compare.gd").run(parent,input)
	if input is Dictionary and input.has("texture_update_probe"):
		return await preload("res://scripts/tests/tokyo_texture_update_probe.gd").run(parent,input)
	if input is Dictionary and input.has("boundary_commit_preview"):
		return await preload("res://scripts/tests/tokyo_boundary_commit_preview.gd").run(parent,input)
	if input is Dictionary and input.get("segmented_delta_frames",false):
		return await preload("res://scripts/tests/tokyo_index_recipe_probe.gd").run_segmented_frames(parent,input)
	if input is Dictionary and input.has("index_recipe_probe"):
		return preload("res://scripts/tests/tokyo_index_recipe_probe.gd").run(input)
	if input is Dictionary and input.has("nine_domain_preview"):
		return await preload("res://scripts/tests/tokyo_nine_domain_preview.gd").run(parent,input)
	if input is Dictionary and input.has("staged_resource_probe"):
		return await preload("res://scripts/tests/tokyo_staged_resource_probe.gd").run(parent,input)
	if input is Dictionary and input.has("selectable_geometry_save"):
		return preload("res://scripts/tests/tokyo_selectable_geometry_save.gd").run(input)
	if input is Dictionary and input.has("bitpacked_mip_compare"):
		return await preload("res://scripts/tests/tokyo_bitpacked_mip_compare.gd").run(parent,input)
	if input is Dictionary and input.has("bitpacked_pixel_probe"):
		return await preload("res://scripts/tests/tokyo_bitpacked_pixel_probe.gd").run(parent,input)
	if input is Dictionary and input.has("residential_saved_load"):
		return await preload("res://scripts/tests/tokyo_residential_saved_load.gd").run(parent,input)
	if input is Dictionary and input.has("residential_packet_audit"):
		return preload("res://scripts/tests/tokyo_residential_packet_audit.gd").run(input)
	if input is Dictionary and input.has("residential_native_costs"):
		return preload("res://scripts/tests/tokyo_residential_native_costs.gd").run(input)
	if input is Dictionary and input.has("audio_exit_probe"):
		return await preload("res://scripts/tests/tokyo_audio_exit_probe.gd").run(parent,input)
	if input is Dictionary and input.has("cell_index_contract"):
		return preload("res://scripts/tests/test_tokyo_cell_index_selector.gd").run(input)
	if input is Dictionary and input.has("export_joined_layers"):
		return preload("res://scripts/tests/tokyo_export_joined_layers.gd").run(input)
	if input is Dictionary and input.has("joined_layers_catalog"):
		return preload("res://scripts/tests/tokyo_joined_layers_catalog.gd").run(input)
	if input is Dictionary and input.has("rebind_grid"):
		return preload("res://scripts/tests/tokyo_rebind_grid_batches.gd").run(input)
	if input is Dictionary and input.has("grid_reuse_inventory"):
		return preload("res://scripts/tests/tokyo_grid_reuse_inventory.gd").run(input)
	if input is Dictionary and input.has("source_inventory"):
		return preload("res://scripts/tests/export_tokyo_current_sources.gd").run(input)
	if input is Dictionary and input.has("shared_index_audit"):
		return preload("res://scripts/tests/tokyo_shared_index_audit.gd").run(input)
	if input is Dictionary and input.has("isolated_sampler_review"):
		return await preload("res://scripts/tests/tokyo_isolated_sampler_review.gd").run(parent,input)
	if input is Dictionary and input.has("texture_mip_export"):
		return preload("res://scripts/tests/tokyo_texture_mip_export.gd").run(parent,input)
	if input is Dictionary and input.has("envelope_visual_review"):
		return await preload("res://scripts/tests/tokyo_envelope_visual_review.gd").run(parent,input)
	if input is Dictionary and input.has("envelope_resource_audit"):
		return preload("res://scripts/tests/tokyo_envelope_resource_audit.gd").run(parent,input)
	if input is Dictionary and input.has("index_hybrid_review"):
		return await preload("res://scripts/tests/tokyo_index_hybrid_review.gd").run(parent,input)
	if input is Dictionary and input.has("index_update_probe"):
		return await preload("res://scripts/tests/tokyo_index_update_probe.gd").run(parent,input)
	if input is Dictionary and input.has("selective_native_cost"):
		return preload("res://scripts/tests/tokyo_selective_native_cost.gd").run(input)
	if input is Dictionary and input.has("layered_roof_review"):
		return await preload("res://scripts/tests/tokyo_layered_roof_review.gd").run(parent,input)
	if input is Dictionary and input.has("materialize_ground"):
		return preload("res://scripts/tests/build_tokyo_simplified_ground.gd").run(input)
	if input is Dictionary and input.has("path_replay"):
		return preload("res://scripts/tests/build_tokyo_path_replay.gd").run(input)
	if input is Dictionary and input.has("ground_stream"):
		return await preload("res://scripts/tests/tokyo_ground_stream_case.gd").run(parent,input)
	if input is Dictionary and input.has("build_ground_components"):
		return preload("res://scripts/tests/build_tokyo_ground_components.gd").run(input)
	if input is Dictionary and input.has("build_grid_detail"):
		return preload("res://scripts/tests/build_tokyo_grid_detail.gd").run(input)
	if input is Dictionary and input.has("grid_native"):
		return await preload("res://scripts/tests/tokyo_grid_native_case.gd").run(parent,input)
	if input is Dictionary and input.has("grid_selection"):
		return preload("res://scripts/tests/tokyo_grid_selection_case.gd").run(input)
	if input is Dictionary and input.has("grid_stream"):
		return await preload("res://scripts/tests/tokyo_grid_stream_case.gd").run(parent,input)
	if input is Dictionary and input.has("grid_coverage_checks"):
		var data: Variant=preload("res://scripts/tests/build_tokyo_grid_dependencies.gd").read(input.grid_coverage_checks)
		if not data is Dictionary: return 1
		return preload("res://scripts/tests/test_tokyo_grid_coverage.gd").checks(data)
	if input is Dictionary and input.has("grid_dependencies"):
		return preload("res://scripts/tests/build_tokyo_grid_dependencies.gd").run(input)
	if input is Dictionary and input.has("joined_grid_series"):
		return preload("res://scripts/tests/build_tokyo_joined_grid.gd").run_series(input)
	if input is Dictionary and input.has("joined_grid"):
		return preload("res://scripts/tests/build_tokyo_joined_grid.gd").run(input)
	if input is Dictionary and input.has("current_grid_series"):
		return preload("res://scripts/tests/build_tokyo_current_grid_batch.gd").run_series(input)
	if input is Dictionary and input.has("current_grid_batch"):
		return preload("res://scripts/tests/build_tokyo_current_grid_batch.gd").run(input)
	if input is Dictionary and input.has("current_sources"):
		return preload("res://scripts/tests/export_tokyo_current_sources.gd").run(input)
	if input is Dictionary and input.has("grid_resources"):
		return preload("res://scripts/tests/build_tokyo_grid_resources.gd").run(input)
	if input is Dictionary and input.has("handoff_selection_probe"):
		return preload("res://scripts/tests/tokyo_handoff_selection_probe.gd").run(input)
	if input is Dictionary and input.has("source_massing_package"):
		return preload("res://scripts/tests/build_tokyo_source_massing.gd").run(input,expected)
	if input is Dictionary and input.has("native_source_export"):
		return preload("res://scripts/tests/export_tokyo_native_source.gd").run(input,expected)
	if input is Dictionary and input.has("ground_height_pack"):
		return preload("res://scripts/tests/build_tokyo_ground_height.gd").run(input)
	if input is Dictionary and input.has("static_leaf_probe"):
		return await preload("res://scripts/tests/tokyo_static_leaf_probe.gd").run(parent,input)
	if input is Dictionary and input.has("ground_pack"):
		return preload("res://scripts/tests/build_tokyo_native_ground_pack.gd").run(input)
	if input is Dictionary and input.has("ground_review"):
		return await preload("res://scripts/tests/tokyo_native_ground_review.gd").run(parent,input)
	if input is Dictionary and input.has("native_massing_cost"):
		return preload("res://scripts/tests/tokyo_native_massing_cost.gd").run(input)
	if input is Dictionary and input.has("incremental_package"):
		return preload("res://scripts/tests/stage_tokyo_incremental_package.gd").run(input,expected)
	if input is Dictionary and input.has("verify_incremental_package"):
		return preload("res://scripts/tests/verify_tokyo_incremental_package.gd").run(input)
	if input is Dictionary and input.has("lossless_leaf_package"):
		return preload("res://scripts/tests/build_tokyo_lossless_leaf_partitions.gd").run(input,expected)
	if input is Dictionary and input.has("repack_partition"):
		return preload("res://scripts/tests/repack_tokyo_partition.gd").run(input,expected)
	if input is Dictionary and input.has("attach_native"):
		return preload("res://scripts/tests/tokyo_partition_attach_probe.gd").run(input,expected)
	if not input is Dictionary or not Contract.binding(input.get("partition")) or FileAccess.get_sha256(input.partition.path)!=input.partition.sha256: return 1
	var output: String=input.get("output","")
	if not output.is_absolute_path() or FileAccess.file_exists(output) or not input.get("poses") is Array or input.poses.is_empty(): return 1
	var data := read_partition(input.partition)
	if data.is_empty(): return 1
	var partitions: Array[Dictionary]=[data]
	if input.has("alternate_partition"):
		var alternate := read_partition(input.alternate_partition)
		if alternate.is_empty(): return 1
		partitions.append(alternate)
	var logical_pages := bool(input.get("logical_pages",false))
	for partition: Dictionary in partitions:
		if partition.schema==3 and not logical_pages: return 1
	if input.get("render_compare",false) and not logical_pages: return 1
	var logical_trees: Array[Dictionary]=[]
	var geometry: Dictionary={}
	for index in partitions.size():
		var partition: Dictionary=partitions[index]
		var binding: Dictionary=input.partition if index==0 else input.alternate_partition
		if logical_pages and binding.get("configuration") not in ["lod4_full","lod5_full"]: return 1
		if logical_pages:
			var normalized := preload("res://scripts/rendering/tokyo_partition_catalog.gd").normalize(partition,binding)
			if normalized.is_empty(): return 1
			logical_trees.append(normalized.tree)
			for key: String in normalized.pages:
				if geometry.has(key): return 1
				geometry[key]=normalized.pages[key]
			continue
		for page_path: String in partition.pages:
			var row: Dictionary=partition.pages[page_path]
			if row.get("layers",[]).size()!=3: return 1
			for layer: Dictionary in row.layers:
				if not Contract.binding(layer) or not layer.get("canonical_identity") is Dictionary: return 1
				if geometry.has(layer.path) and geometry[layer.path]!=layer: return 1
				geometry[layer.path]=layer
	var stream: Variant=Stream.new()
	parent.add_child(stream)
	var exit_state: Dictionary={}
	var stream_ref: WeakRef=weakref(stream)
	stream.tree_exiting.connect(func() -> void:
		var live: Variant=stream_ref.get_ref()
		if typeof(live)==TYPE_OBJECT and is_instance_valid(live): exit_state.merge(live.summary()),CONNECT_ONE_SHOT)
	if not stream.configure_hlod(parent,geometry,{}):
		stream.queue_free()
		await parent.get_tree().process_frame
		return 1
	var previous := PackedStringArray()
	var rows: Array=[]
	var failure := ""
	var deadline := Time.get_ticks_msec()+30000
	for pose: Dictionary in input.poses:
		var choice := int(pose.get("partition",0))
		if choice<0 or choice>=partitions.size():
			failure="invalid partition choice"
			break
		var selected: Dictionary=partitions[choice]
		var roots: Array[Dictionary]=[logical_trees[choice] if logical_pages else selected.tree]
		var size := Vector2(1600,900)
		var canvas := Transform2D(float(pose.rotation),Vector2.ZERO).scaled(Vector2.ONE*float(pose.scale))
		canvas.origin=size*.5-canvas*Vector2(pose.center[0],pose.center[1])
		var inverse := canvas.affine_inverse()
		var view := Rect2(inverse*Vector2.ZERO,Vector2.ZERO)
		for corner in [Vector2(size.x,0),size,Vector2(0,size.y)]: view=view.expand(inverse*corner)
		var ray := MapProjection.ground_basis(canvas,deg_to_rad(38)).inverse()*MapProjection.camera_basis(canvas,deg_to_rad(38)).z
		var cut := Cut.choose(roots,view,canvas,size,-Vector2(ray.x,ray.z)/ray.y,Vector2.ZERO,16)
		if not cut.within_budget:
			failure="cut budget"
			break
		var wanted := PackedStringArray()
		for entry: Dictionary in cut.entries:
			if logical_pages:
				wanted.append(entry.path)
				continue
			for kind in 3:
				if entry.mask[kind]: wanted.append(selected.pages[entry.path].layers[kind].path)
		stream.request(wanted,previous)
		var started := Time.get_ticks_msec()
		var ready := false
		while Time.get_ticks_msec()<deadline:
			await parent.get_tree().process_frame
			ready=true
			for resource_path: String in previous:
				if stream.resource(resource_path)==null: failure="outgoing retired before incoming ready"
			for resource_path: String in wanted:
				ready=ready and stream.resource(resource_path)!=null
			if ready or not failure.is_empty(): break
		if not ready and failure.is_empty(): failure="incoming timeout"
		var snapshot: Dictionary=stream.summary()
		if not snapshot.failures.is_empty() or not snapshot.texture_failures.is_empty(): failure="stream resource rejected"
		if snapshot.total_bytes>Stream.BUDGET: failure="stream budget"
		var record := {"pose":pose,"ready":ready,"wait_ms":Time.get_ticks_msec()-started,"components":wanted.size(),"snapshot":snapshot}
		if input.get("render_compare",false) and failure.is_empty():
			record["render"]=await preload("res://scripts/tests/tokyo_partition_render_probe.gd").compare(parent,stream,cut,selected,pose,output+"_pose_%d"%rows.size())
			if record.render.is_empty() or record.render.different_pixels!=0 or record.render.blank_control_pixels==0:
				failure="render comparison failed"
		rows.append(record)
		if not failure.is_empty(): break
		# 新资源全部ready才解除旧pins；这是资源交接，不是正式画面提交。
		stream.request(wanted,PackedStringArray())
		previous=wanted
	stream.close()
	var cleanup_deadline := Time.get_ticks_msec()+5000
	var drained := false
	var terminal: Dictionary=stream.summary()
	while Time.get_ticks_msec()<cleanup_deadline:
		drained=not terminal.is_empty() and terminal.pending==0 and terminal.mesh_checks_pending==0 and terminal.cached==0 and terminal.total_bytes==0
		if drained: break
		await parent.get_tree().process_frame
		if typeof(stream)==TYPE_OBJECT and is_instance_valid(stream):
			terminal=stream.summary()
		else:
			terminal=exit_state
			if terminal.is_empty(): break
	if not drained: failure="close not drained"
	if typeof(stream)==TYPE_OBJECT and is_instance_valid(stream): stream.queue_free()
	await parent.get_tree().process_frame
	var released := not is_instance_valid(stream)
	if not released: failure="stream node not released"
	var file := FileAccess.open(output,FileAccess.WRITE)
	if file==null: return 1
	file.store_string(JSON.stringify({"input_sha256":expected,"rows":rows,"failure":failure,"drained":drained,"released":released,
		"vsync":DisplayServer.window_get_vsync_mode(),"logical_pages":logical_pages,"runtime_integrated":false,"rendered_coverage_verified":false,"performance_accepted":false},"\t"))
	file.close()
	print("[partition real stream] poses=",rows.size()," drained=",drained," failure=",failure)
	return int(not failure.is_empty())
