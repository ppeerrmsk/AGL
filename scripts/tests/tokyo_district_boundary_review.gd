extends RefCounted
## 固定机位逐层隔离；临时隐藏不作为减负或美术通过证据。
const Session := preload("res://scripts/rendering/tokyo_volume_preload.gd")
const Capture := preload("res://scripts/tests/tokyo_ao_review.gd")
const Static := preload("res://scripts/tests/tokyo_tile_ground_review.gd")
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
	for pose: Vector4 in [Vector4(-5600,-2900,.26,0),Vector4(-5600,-2900,.4,0),Vector4(-5600,-2900,.65,0),Vector4(-5600,-2900,.26,14),Vector4(-6300,-2900,.26,0)]:
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
			rows.append({"pose":str(pose),"blocked":true,"map":map.debug_state()})
			continue
		map.set_process(false)
		source.set_process(false)
		var state: Dictionary = map.debug_state()
		var stem := output.path_join("r101_%02d"%rows.size())
		var held: Array[Dictionary] = []
		for batch: Dictionary in map._batches.values():
			for kind in 3:
				var node: MeshInstance3D = batch.nodes[kind]
				held.append({"node":node,"kind":kind,"mesh":node.mesh,"material":node.material_override,"visible":node.visible})
		var runtime := await Capture._capture(battle,map,stem+"_runtime")
		var reference := await preload("res://scripts/tests/tokyo_ground_palette_review.gd").source_only(battle,source,map._viewport.size)
		fail += int(reference.save_png(stem+"_source.png")!=OK)
		var variants: Array = []
		for label: String in ["no_low","no_tagged","no_buildings","tile_only"]:
			for entry: Dictionary in held:
				var hidden: bool = label=="tile_only" or (label=="no_low" and entry.kind==0) or (label=="no_tagged" and entry.kind==1) or (label=="no_buildings" and entry.kind<2)
				entry.node.visible = entry.visible and not hidden
			var shore_visible: Array[bool] = []
			if map._shoreline!=null:
				for index in map._shoreline._nodes.size():
					shore_visible.append(map._shoreline._nodes[index].visible)
					if label=="tile_only":
						map._shoreline._nodes[index].hide()
			var picture := await Capture._capture(battle,map,stem+"_"+label)
			variants.append({"label":label,"max_change":Pixels._pixel_error(runtime,picture)})
			for entry: Dictionary in held:
				entry.node.visible = entry.visible
			if map._shoreline!=null:
				for index in shore_visible.size():
					map._shoreline._nodes[index].visible = shore_visible[index]
		var strengths: Dictionary = {}
		for entry: Dictionary in held:
			var material: ShaderMaterial = entry.material
			if material.shader.code.contains("uniform float ao_strength") and not strengths.has(material.get_instance_id()):
				strengths[material.get_instance_id()] = {"material":material,"value":material.get_shader_parameter("ao_strength")}
				material.set_shader_parameter("ao_strength",0.0)
		await Capture._capture(battle,map,stem+"_no_ao")
		for entry: Dictionary in strengths.values():
			entry.material.set_shader_parameter("ao_strength",entry.value)
		var tone_script := preload("res://scripts/experiments/tokyo_low_tone_candidate.gd")
		var tones: Array = []
		for factor: float in [.90,.80]:
			var replacements: Dictionary = {}
			for entry: Dictionary in held:
				if entry.kind!=0:
					continue
				var original: ShaderMaterial = entry.material
				if not replacements.has(original.get_instance_id()):
					var code := tone_script.shader_code(original.shader.code,factor)
					if code.is_empty():
						fail += 1
						continue
					var material: ShaderMaterial = original.duplicate()
					var shader := Shader.new()
					shader.code = code
					material.shader = shader
					material.set_shader_parameter("low_tone_weight",tone_script.weight(state.output_scale))
					replacements[original.get_instance_id()] = material
				entry.node.material_override = replacements[original.get_instance_id()]
			var toned := await Capture._capture(battle,map,stem+"_tone%02d"%roundi(factor*100))
			tones.append({"factor":factor,"weight":tone_script.weight(state.output_scale),"max_change":Pixels._pixel_error(runtime,toned)})
			if tone_script.weight(state.output_scale)==0.0:
				fail += int(Pixels._pixel_error(runtime,toned)>1)
			for entry: Dictionary in held:
				entry.node.material_override = entry.material
		var restored := await Capture._capture(battle,map,stem+"_restored")
		var unchanged: bool = collision==var_to_bytes(BuildingRenderer._cache_entries)
		for entry: Dictionary in held:
			unchanged = unchanged and entry.node.mesh==entry.mesh and entry.node.material_override==entry.material and entry.node.visible==entry.visible
		var error := Pixels._pixel_error(runtime,restored)
		fail += int(not unchanged or error>1)
		rows.append({"pose":str(pose),"map":state,"variants":variants,"tones":tones,"restore_error":error,"unchanged":unchanged,"ao_materials":strengths.size()})
		map._viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		map.set_process(true)
		source.set_process(true)
		print("[R101 district] pose=",pose," restore=",error," fail=",fail)
	source.process_mode = mode
	battle.camera.ignore_rotation = ignore
	tree.paused = paused
	var file := FileAccess.open(output.path_join("r101_district.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"rows":rows,"fail":fail,"diagnostic_only":true,"fps_evidence":false},"\t"))
	file.close()
	return fail
