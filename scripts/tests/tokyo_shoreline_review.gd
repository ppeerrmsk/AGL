extends RefCounted
const Shore := preload("res://scripts/experiments/tokyo_shoreline_candidate.gd")
const Source := preload("res://scripts/tests/tokyo_ground_palette_review.gd")
const Static := preload("res://scripts/tests/tokyo_tile_ground_review.gd")
const Session := preload("res://scripts/rendering/tokyo_volume_preload.gd")
const Capture := preload("res://scripts/tests/tokyo_ao_review.gd")
const Pixels := preload("res://scripts/tests/tokyo_shell_review.gd")


static func run(battle: Node, map: Node, output: String) -> int:
	var path := OS.get_environment("AGL_TOKYO_SHORELINE_DATA")
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not data is Dictionary or data.get("schema",0)!=1 or data.get("candidates",[]).size()!=2:
		return 1
	var mesh_paths := PackedStringArray()
	for i in 2:
		var mesh := Shore.build(data.candidates[i])
		if mesh==null:
			return 1
		var saved := output.path_join("r98_shore_%d.res" % i)
		if ResourceSaver.save(mesh,saved)!=OK:
			return 1
		var reloaded: ArrayMesh = ResourceLoader.load(saved,"",ResourceLoader.CACHE_MODE_IGNORE)
		if reloaded==null:
			return 1
		var before := mesh.surface_get_arrays(0)
		var after := reloaded.surface_get_arrays(0)
		for slot in Mesh.ARRAY_MAX:
			if var_to_bytes(before[slot])!=var_to_bytes(after[slot]):
				print("[R98 reload] slot=",slot," before_type=",typeof(before[slot])," after_type=",typeof(after[slot])," before=",str(before[slot]).left(300)," after=",str(after[slot]).left(300))
		if var_to_bytes(before)!=var_to_bytes(after):
			return 1
		mesh_paths.append(saved)
		mesh = null
		reloaded = null
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
	var poses := [Vector4(-5300,-1100,.26,0),Vector4(-5300,-1100,.65,0),Vector4(-5300,-1100,.98,0),Vector4(-5300,-1100,.65,14),Vector4(-4700,-1700,1.3,0),Vector4(-3100,-2500,.65,-14),Vector4(-5350,-1080,5.0,0)]
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
		var stem := output.path_join("r98_%02d" % rows.size())
		await Capture._capture(battle,map,stem+"_runtime")
		var runtime_ground: Dictionary = map.debug_state().tile_ground
		map._release_tile_ground()
		var original := await Capture._capture(battle,map,stem+"_original")
		var reference := await Source.source_only(battle,source,original.get_size())
		assert(reference.save_png(stem+"_source.png")==OK)
		var held: Array[Dictionary] = []
		var material: ShaderMaterial
		for batch: Dictionary in map._batches.values():
			for layer in 3:
				var node: MeshInstance3D = batch.nodes[layer]
				held.append({"node":node,"mesh":node.mesh,"material":node.material_override,"visible":node.visible})
				if layer==2 and material==null:
					material = node.material_override.duplicate()
		var variants: Array = []
		for i in 2:
			var node := MeshInstance3D.new()
			node.mesh = ResourceLoader.load(mesh_paths[i],"",ResourceLoader.CACHE_MODE_IGNORE)
			var mesh_ref: WeakRef = weakref(node.mesh)
			node.material_override = material
			node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			map._city.add_child(node)
			var label := "width%d" % (i+1)
			var picture := await Capture._capture(battle,map,stem+"_"+label)
			var native: Array = node.mesh.surface_get_arrays(0)
			var projected: Array = []
			for point: Vector3 in native[Mesh.ARRAY_VERTEX]:
				var screen: Vector2 = map._camera.unproject_position(map._city.to_global(point))
				projected.append([screen.x,screen.y])
			var mask_material := StandardMaterial3D.new()
			mask_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			mask_material.albedo_color = Color.WHITE
			node.material_override = mask_material
			for entry: Dictionary in held:
				entry.node.hide()
			await Capture._capture(battle,map,stem+"_"+label+"_mask")
			for entry: Dictionary in held:
				entry.node.visible = entry.visible
			var ref: WeakRef = weakref(node)
			node.queue_free()
			await tree.process_frame
			var restored := await Capture._capture(battle,map,stem+"_"+label+"_restored")
			var unchanged := collision==var_to_bytes(BuildingRenderer._cache_entries) and ref.get_ref()==null and mesh_ref.get_ref()==null
			for entry: Dictionary in held:
				unchanged = unchanged and entry.node.mesh==entry.mesh and entry.node.material_override==entry.material and entry.node.visible==entry.visible
			var error := Pixels._pixel_error(original,restored)
			fail += int(not unchanged or error>1)
			variants.append({"label":label,"stats":data.candidates[i].stats,"projected_triangles":projected,"unchanged":unchanged,"restore_error":error,"changed":Pixels._pixel_error(original,picture)})
		rows.append({"pose":str(pose),"stem":stem,"variants":variants,"map":map.debug_state(),"runtime_ground":runtime_ground})
		map._viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		map.set_process(true)
		source.set_process(true)
		print("[R98 shore] pose=",pose," fail=",fail)
	source.process_mode = mode
	battle.camera.ignore_rotation = ignore
	tree.paused = paused
	var file := FileAccess.open(output.path_join("r98_shoreline.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"fail":fail,"rows":rows,"source_sha":FileAccess.get_sha256(path),"fps_evidence":false},"\t"))
	file.close()
	return fail
