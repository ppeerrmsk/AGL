extends RefCounted
## 原几何上的联合配色候选；黑白双绘几何遮罩保留其他层的真实遮挡。
const Palette := preload("res://scripts/experiments/tokyo_ground_palette_candidate.gd")
const Tone := preload("res://scripts/experiments/tokyo_low_tone_candidate.gd")
const Source := preload("res://scripts/tests/tokyo_ground_palette_review.gd")
const Static := preload("res://scripts/tests/tokyo_tile_ground_review.gd")
const Session := preload("res://scripts/rendering/tokyo_volume_preload.gd")
const Capture := preload("res://scripts/tests/tokyo_ao_review.gd")
const Pixels := preload("res://scripts/tests/tokyo_shell_review.gd")


static func low_mask_code(original: String) -> String:
	var light: String = preload("res://scripts/experiments/tokyo_low_light_candidate.gd").LIGHT
	if original.count(light)!=1 or original.count("ROUGHNESS = 1.0;")!=1 or original.count("void vertex() {")!=1 or original.contains("finish_mask_local"):
		return ""
	return original.replace("void vertex() {","uniform float finish_mask_value=0.0;\nvarying vec3 finish_mask_local;\nvoid vertex() {\nfinish_mask_local=VERTEX;").replace("ROUGHNESS = 1.0;","ALBEDO=vec3(0.0); EMISSION=vec3(finish_mask_value*float(finish_mask_local.x>=-6300.0 && finish_mask_local.x<=-2300.0 && finish_mask_local.z>=-3700.0 && finish_mask_local.z<=-1700.0)); ROUGHNESS = 1.0;").replace(light,"")


static func replacement(original: ShaderMaterial, code: String) -> ShaderMaterial:
	if code.is_empty():
		return null
	var result: ShaderMaterial = original.duplicate()
	result.shader = Shader.new()
	result.shader.code = code
	return result


static func restore(held: Array[Dictionary]) -> void:
	for entry: Dictionary in held:
		entry.node.material_override = entry.material


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
	var sample: Dictionary = {}
	var colors: Array[Color] = Palette.COLORS.duplicate()
	var capacity_recorded := false
	var poses: Array[Vector4] = [Vector4(-6000,-3500,.65,0),Vector4(-5600,-2900,.26,0),Vector4(-5600,-2900,.4,0),Vector4(-5600,-2900,.65,0),Vector4(-5600,-2900,.98,0),Vector4(-5600,-2900,.26,14),Vector4(-6300,-2900,.26,0)]
	var static_order := OS.get_environment("AGL_TOKYO_FINISH_STATIC_ORDER")=="1"
	if OS.get_environment("AGL_TOKYO_FINISH_WIDE_REVIEW")=="1":
		# 原七机位顺序不变，追加实际受阻宽视角及返回；不能用AO片区中心替代。
		poses.append_array([Vector4(-5600,-2900,1.95,0),Vector4(-5600,-2900,.26,14)])
	if OS.get_environment("AGL_TOKYO_FINISH_MID_REVIEW")=="1":
		poses.append_array([Vector4(-5600,-2900,1.2,0),Vector4(-5600,-2900,1.85,0),Vector4(-5600,-2900,5,0),Vector4(-5600,-2900,1.2,0)])
	if static_order:
		# 独立补齐静态机位，不替代默认顺序中已复现的近景返回过渡失败。
		var near_pose := poses[4]
		poses.remove_at(4)
		poses.append(near_pose)
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
			fail += 1
			rows.append({"pose":str(pose),"blocked":true,"map":map.debug_state(),"source":source.debug_state()})
			print("[R104 blocked] pose=",pose," map=",map.debug_state()," source=",source.debug_state())
			if not capacity_recorded and OS.get_environment("AGL_TOKYO_FINISH_CAPACITY_PROBE")=="1":
				preload("res://scripts/tests/tokyo_cut_capacity_probe.gd").run(map,output)
				capacity_recorded = true
			continue
		map.set_process(false)
		source.set_process(false)
		var state: Dictionary = map.debug_state()
		var stem := output.path_join("r104_%02d"%rows.size())
		var held: Array[Dictionary] = []
		var cache: Dictionary = {}
		for batch: Dictionary in map._batches.values():
			for kind in 3:
				var node: MeshInstance3D = batch.nodes[kind]
				var original: ShaderMaterial = node.material_override
				var entry := {"node":node,"kind":kind,"mesh":node.mesh,"material":original,"visible":node.visible}
				if kind!=1:
					var key := str(kind)+":"+str(original.get_instance_id())
					if not cache.has(key):
						cache[key] = {"candidate":replacement(original,Tone.shader_code(original.shader.code,.9) if kind==0 else Palette.shader_code(original.shader.code)),"mask":replacement(original,low_mask_code(original.shader.code) if kind==0 else Palette.shader_code(original.shader.code))}
					entry.merge(cache[key])
					fail += int(entry.candidate==null or entry.mask==null)
				held.append(entry)
		var original_image := await Capture._capture(battle,map,stem+"_original")
		var reference := await Source.source_only(battle,source,original_image.get_size())
		assert(reference.save_png(stem+"_source.png")==OK)
		# 双绘只改变被审查类别的发光黑/白；其他楼体/道路保持原来的深度遮挡。
		for kind in [0,2]:
			for value in [0,1]:
				for entry: Dictionary in held:
					if entry.kind!=kind or entry.mask==null:
						continue
					entry.node.material_override = entry.mask
					entry.mask.set_shader_parameter("finish_mask_value" if kind==0 else "ground_palette_mask",float(value) if kind==0 else (9 if value==1 else 99))
				var mask_image := await Capture._capture(battle,map,stem+"_mask%d_%d"%[kind,value])
				if rows.is_empty() and kind==2 and value==1:
					sample = Source.sample_color(reference,mask_image,2)
					if sample.count>=64:
						colors[9] = Color(sample.rgb[0]/255.0,sample.rgb[1]/255.0,sample.rgb[2]/255.0)
					else:
						fail += 1
				restore(held)
		var changes: Array[int] = []
		for label: String in ["a_low","b_low_land"]:
			for entry: Dictionary in held:
				if entry.kind==1 or entry.candidate==null or (entry.kind==2 and label=="a_low"):
					continue
				entry.node.material_override = entry.candidate
				if entry.kind==0:
					entry.candidate.set_shader_parameter("low_tone_weight",Tone.weight(state.output_scale))
				else:
					entry.candidate.set_shader_parameter("ground_palette_base_only",true)
					entry.candidate.set_shader_parameter("ground_palette",Palette.vectors(colors))
			var picture := await Capture._capture(battle,map,stem+"_"+label)
			changes.append(Pixels._pixel_error(original_image,picture))
			if label=="a_low" and Tone.weight(state.output_scale)==0.0:
				fail += int(changes.back()>1)
			restore(held)
		var restored := await Capture._capture(battle,map,stem+"_restored")
		var error := Pixels._pixel_error(original_image,restored)
		var unchanged := collision==var_to_bytes(BuildingRenderer._cache_entries)
		for entry: Dictionary in held:
			unchanged = unchanged and entry.node.mesh==entry.mesh and entry.node.material_override==entry.material and entry.node.visible==entry.visible
		fail += int(error>1 or not unchanged)
		rows.append({"pose":str(pose),"stem":stem,"map":state,"weight":Tone.weight(state.output_scale),"changes":changes,"restore_error":error,"unchanged":unchanged})
		map._viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		map.set_process(true)
		source.set_process(true)
		print("[R104 finish] pose=",pose," sample=",sample," changes=",changes," restore=",error," fail=",fail)
	source.process_mode = mode
	battle.camera.ignore_rotation = ignore
	tree.paused = paused
	var file := FileAccess.open(output.path_join("r104_finish.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"rows":rows,"sample":sample,"fail":fail,"static_order":static_order,"fps_evidence":false},"\t"))
	file.close()
	return fail
