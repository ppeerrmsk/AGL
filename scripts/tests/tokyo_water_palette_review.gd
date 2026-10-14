extends RefCounted
const Palette := preload("res://scripts/experiments/tokyo_ground_palette_candidate.gd")
const Source := preload("res://scripts/tests/tokyo_ground_palette_review.gd")
const Static := preload("res://scripts/tests/tokyo_tile_ground_review.gd")
const Session := preload("res://scripts/rendering/tokyo_volume_preload.gd")
const Capture := preload("res://scripts/tests/tokyo_ao_review.gd")
const Pixels := preload("res://scripts/tests/tokyo_shell_review.gd")


static func run(battle: Node, map: Node, output: String) -> int:
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
	var source_sample: Dictionary = {}
	var native_sample: Dictionary = {}
	var target := Color.WHITE
	var halfway := Color.WHITE
	for pose: Vector4 in [Vector4(-5300,-1100,.65,0),Vector4(-5300,-1100,.98,0),Vector4(-5300,-1100,.65,14),Vector4(-4700,-1500,1.3,0)]:
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
		map._release_tile_ground()
		var stem := output.path_join("r97_%02d" % rows.size())
		var original := await Capture._capture(battle,map,stem+"_original")
		var reference := await Source.source_only(battle,source,original.get_size())
		assert(reference.save_png(stem+"_source.png")==OK)
		var held: Array[Dictionary] = []
		var replacements: Dictionary = {}
		for batch: Dictionary in map._batches.values():
			for layer in 3:
				var node: MeshInstance3D = batch.nodes[layer]
				held.append({"node":node,"mesh":node.mesh,"material":node.material_override,"visible":node.visible,"layer":layer})
				if layer!=2:
					continue
				var material: ShaderMaterial = node.material_override
				if not replacements.has(material.get_instance_id()):
					var code := Palette.shader_code(material.shader.code,map._archive.bounds)
					if code.is_empty():
						fail += 1
						continue
					var replacement: ShaderMaterial = material.duplicate()
					replacement.shader = Shader.new()
					replacement.shader.code = code
					replacements[material.get_instance_id()] = replacement
				node.material_override = replacements[material.get_instance_id()]
		for material: ShaderMaterial in replacements.values():
			material.set_shader_parameter("ground_palette_mask",10)
			material.set_shader_parameter("ground_palette_only_class",10)
		# 保留楼体和道路遮挡，使水mask不会包含被它们覆盖的非水屏幕像素。
		var mask := await Capture._capture(battle,map,stem+"_mask")
		if rows.is_empty():
			source_sample = Source.sample_color(reference,mask,2)
			native_sample = Source.sample_color(original,mask,2)
			if source_sample.count<64 or native_sample.count<64:
				fail += 1
			else:
				target = Color(source_sample.rgb[0]/255.0,source_sample.rgb[1]/255.0,source_sample.rgb[2]/255.0)
				var native := Color(native_sample.rgb[0]/255.0,native_sample.rgb[1]/255.0,native_sample.rgb[2]/255.0)
				halfway = native.lerp(target,.5)
		for label: String in ["source_water","half_water"]:
			var colors: Array[Color] = Palette.COLORS.duplicate()
			colors[10] = target if label=="source_water" else halfway
			for material: ShaderMaterial in replacements.values():
				material.set_shader_parameter("ground_palette_mask",-1)
				material.set_shader_parameter("ground_palette",Palette.vectors(colors))
			await Capture._capture(battle,map,stem+"_"+label)
		var unchanged := collision==var_to_bytes(BuildingRenderer._cache_entries)
		for entry: Dictionary in held:
			unchanged = unchanged and entry.node.mesh==entry.mesh and entry.node.visible==entry.visible
			entry.node.material_override = entry.material
		var restored := await Capture._capture(battle,map,stem+"_restored")
		var error := Pixels._pixel_error(original,restored)
		fail += int(not unchanged or error>1)
		rows.append({"pose":str(pose),"stem":stem,"unchanged":unchanged,"restore_error":error,"map":map.debug_state()})
		map._viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		map.set_process(true)
		source.set_process(true)
		print("[R97 water] pose=",pose," source=",source_sample," native=",native_sample," restored=",error)
	source.process_mode = mode
	battle.camera.ignore_rotation = ignore
	tree.paused = paused
	var file := FileAccess.open(output.path_join("r97_water.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"fail":fail,"rows":rows,"source_sample":source_sample,"native_sample":native_sample,"target":str(target),"halfway":str(halfway),"fps_evidence":false},"\t"))
	file.close()
	return fail
