extends RefCounted
const Layer := preload("res://scripts/rendering/tokyo_shoreline_layer.gd")


static func checks() -> Array[bool]:
	var shader: String = preload("res://resources/shaders/tokyo_volume_surface.gdshader").code
	var morph := {"schema":2,"widths":[2.0,1.0,.35],"plan_sha":"a".repeat(64),"source_sha":"b".repeat(64),"reserved_bytes":4260672,"meshes":[{"file":"morph.res","faces":414},{"file":"fallback_0.res","faces":2278},{"file":"fallback_1.res","faces":2351},{"file":"fallback_2.res","faces":2354}]}
	var absent_source := morph.duplicate(true)
	absent_source.erase("source_sha")
	var undercharged := morph.duplicate(true)
	undercharged.reserved_bytes-=1
	var missing := morph.duplicate(true)
	missing.meshes.pop_back()
	var readiness := Layer.new()
	var no_warm: bool = not readiness.material_warm_ready()
	readiness.stats["material_warmup"] = {"state":"ready", "rendered":true, "submitted_frames":1, "reserved_bytes":0}
	var incomplete: bool = not readiness.material_warm_ready()
	readiness.stats.material_warmup.submitted_frames = 2
	readiness.stats.material_warmup.reserved_bytes = 524288
	var held: bool = not readiness.material_warm_ready()
	readiness.stats.material_warmup.reserved_bytes = 0
	var complete: bool = readiness.material_warm_ready()
	return [Layer.levels(.85)==Vector3(0,0,0),Layer.levels(1.15)==Vector3(1,1,0),Layer.levels(1.7)==Vector3(1,1,0),Layer.levels(2.3)==Vector3(2,2,0),
		no_warm, incomplete, held, complete,
		Layer.manifest_bytes(JSON.parse_string(JSON.stringify(morph)))==4260672,
		Layer.manifest_bytes(absent_source)==-1,
		Layer.manifest_bytes(morph)==4260672,Layer.manifest_bytes(undercharged)==-1,Layer.manifest_bytes(missing)==-1,
		Layer.levels(1.0).is_equal_approx(Vector3(0,1,.5)),Layer.levels(2.0).is_equal_approx(Vector3(1,2,.5)),Layer.levels(NAN).x<0,Layer.levels(0).x<0,
		Layer.shader_code(shader).contains("shoreline_count"),Layer.shader_code(Layer.shader_code(shader)).is_empty(),Layer.shader_code("drift").is_empty(),
		load("res://scripts/tests/build_tokyo_shoreline_lod.gd").can_instantiate(),
		load("res://scripts/tests/tokyo_shoreline_runtime_review.gd").can_instantiate(),
		not preload("res://scripts/rendering/tokyo_volume_preload.gd").state_ready({"shoreline_required":true,"level":0,"blend":1.0}),
		not preload("res://scripts/rendering/tokyo_volume_preload.gd").state_ready({"shoreline_required":true,"shoreline_error":"missing","shoreline":{"ready":true},"level":0,"blend":1.0})]


static func lifecycle(parent: Node) -> int:
	var map := preload("res://scripts/rendering/tokyo_tile_ground_overlay.gd").new()
	parent.add_child(map)
	map.set_process(false)
	map._city = Node3D.new()
	map.add_child(map._city)
	var material := ShaderMaterial.new()
	material.shader = preload("res://resources/shaders/tokyo_volume_surface.gdshader")
	for i in 5:
		map._materials.append(material)
	map._stream = preload("res://scripts/rendering/tokyo_cell_stream.gd").new()
	parent.add_child(map._stream)
	map._stream.configure(map,{})
	var warm_fail := await _material_warm_lifecycle(parent, map._stream)
	var layer := Layer.new()
	var fail := warm_fail + int(layer.bind(map,"res://missing_shoreline"))
	map.peak_triangles = 239000
	map._tile_peak_faces = 240001
	fail += int(map.debug_state().max_transition_triangles!=240001)
	map.peak_triangles = 250000
	fail += int(map.debug_state().max_transition_triangles!=240001 or map.debug_state().max_preparation_triangles!=250000)
	fail += int(preload("res://scripts/tests/tokyo_volume_combat_runner.gd").cell_peak_within_budget(map.debug_state()))
	map.peak_triangles = 0
	map._tile_peak_faces = 0
	var path := OS.get_environment("AGL_TOKYO_SHORELINE_TEST")
	if not path.is_empty():
		var key := parent.get_instance_id()
		fail += int(not map._stream.reserve_auxiliary(key,95*1024*1024))
		fail += int(layer.bind(map,path))
		map._stream.release_auxiliary(key)
		fail += int(not layer.bind(map,path))
		if not layer._nodes.is_empty():
			var refs: Array[WeakRef] = []
			for mesh: ArrayMesh in layer._meshes:
				refs.append(weakref(mesh))
			for node: MeshInstance3D in layer._nodes:
				refs.append(weakref(node))
			layer.update(1.0,[],true)
			var morph := bool(layer._morph)
			var expected_faces := layer._faces[0]+layer._faces[1]+(layer._faces[2] if morph else 0)
			fail += int(layer.stats.visible_nodes!=(3 if morph else 2) or layer.stats.faces!=expected_faces)
			if morph:
				fail += int(not is_equal_approx(float(layer._materials[2].get_shader_parameter("shoreline_morph_t")),Layer.morph_factor(1.0)))
			var stationary := layer.update(1.0,[],true)
			print("[R99 stationary] changed=",stationary," signature=",layer._signature)
			fail += int(stationary)
			var bounds: AABB = layer._bounds
			var tiles: Array[Rect2] = [Rect2(Vector2(bounds.position.x,bounds.position.z)-Vector2.ONE,Vector2(bounds.size.x,bounds.size.z)+Vector2.ONE*2)]
			layer.update(1.0,tiles,true)
			fail += int(layer.stats.visible_nodes!=0)
			layer.begin_warm()
			for i in 3:
				if morph:
					fail += int(not layer._nodes[2].visible or not is_equal_approx(float(layer._materials[2].get_shader_parameter("shoreline_morph_t")),[0.0,1.0/1.65,1.0][i]))
				layer.warm_draw()
			fail += int(layer.warm_mask!=7)
			if morph:
				fail += int(layer.stats.shared_warm_mask!=7)
			layer.close()
			layer.close()
			await parent.get_tree().process_frame
			for ref: WeakRef in refs:
				if ref.get_ref()!=null:
					print("[R99 release] retained=",ref.get_ref())
				fail += int(ref.get_ref()!=null)
			fail += int(map._stream.summary().auxiliary_bytes!=0)
	layer.close()
	map._stream.close()
	map._stream.queue_free()
	map.queue_free()
	await parent.get_tree().process_frame
	print("[R99 shore lifecycle] fail=",fail)
	return fail


static func _material_warm_lifecycle(parent: Node, stream: Node) -> int:
	var warm_script := preload("res://scripts/rendering/tokyo_shoreline_warmup.gd")
	var material := ShaderMaterial.new()
	material.shader = Shader.new()
	material.shader.code = Layer.morph_shader_code(preload("res://resources/shaders/tokyo_volume_surface.gdshader").code)
	var fail := 0
	var warm := warm_script.new()
	var key := parent.get_instance_id()
	fail += int(not stream.reserve_auxiliary(key, 96*1024*1024 - warm_script.RESERVE_BYTES + 1))
	fail += int(warm.configure(stream, material))
	fail += int(warm.result.state != "budget_rejected")
	stream.release_auxiliary(key)
	fail += int(not warm.configure(stream, material))
	var state: Dictionary = warm.result
	var refs: Array[WeakRef] = [weakref(warm)]
	for i in 3:
		var sample: MeshInstance3D = warm.get_child(i)
		fail += int(sample.material_override.shader != material.shader)
		refs.append(weakref(sample.material_override))
	# 未入树、没有提交：全局回调不能把空视口记为完成。
	warm._after_draw()
	fail += int(state.submitted_frames != 0 or state.state != "pending")
	parent.add_child(warm)
	var pixel_seen := false
	if DisplayServer.get_name() != "headless":
		for i in 10:
			await RenderingServer.frame_post_draw
			if not is_instance_valid(warm):
				break
			var picture: Image = warm.get_texture().get_image()
			for y in picture.get_height():
				for x in picture.get_width():
					pixel_seen = pixel_seen or picture.get_pixel(x,y).a > .1
			if state.rendered:
				break
		fail += int(not state.rendered or state.submitted_frames < 2 or not pixel_seen)
	else:
		fail += int(state.state != "headless_skipped" or state.rendered)
	await parent.get_tree().process_frame
	await parent.get_tree().process_frame
	for reference: WeakRef in refs:
		fail += int(reference.get_ref() != null)
	fail += int(state.reserved_bytes != 0 or stream.summary().auxiliary_bytes != 0)
	var cancelled := warm_script.new()
	fail += int(not cancelled.configure(stream, material))
	var cancelled_state: Dictionary = cancelled.result
	var cancelled_ref: WeakRef = weakref(cancelled)
	parent.add_child(cancelled)
	cancelled.close()
	cancelled.close()
	fail += int(RenderingServer.frame_post_draw.is_connected(cancelled._after_draw))
	await parent.get_tree().process_frame
	await parent.get_tree().process_frame
	fail += int(cancelled_ref.get_ref() != null or cancelled_state.reserved_bytes != 0 or stream.summary().auxiliary_bytes != 0)
	var retired_stream := preload("res://scripts/rendering/tokyo_cell_stream.gd").new()
	parent.add_child(retired_stream)
	retired_stream.configure(parent, {})
	var orphan := warm_script.new()
	fail += int(not orphan.configure(retired_stream, material))
	var orphan_state: Dictionary = orphan.result
	var orphan_ref: WeakRef = weakref(orphan)
	parent.add_child(orphan)
	retired_stream.free()
	orphan.close()
	await parent.get_tree().process_frame
	await parent.get_tree().process_frame
	fail += int(orphan_ref.get_ref() != null or orphan_state.reserved_bytes != 0)
	print("[R137 shore warm lifecycle] fail=", fail, " warm=", state, " pixels=", pixel_seen)
	return fail
