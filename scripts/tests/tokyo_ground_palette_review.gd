extends RefCounted
const Palette := preload("res://scripts/experiments/tokyo_ground_palette_candidate.gd")
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
	var collision := var_to_bytes(BuildingRenderer._cache_entries)
	tree.paused = true
	source.process_mode = Node.PROCESS_MODE_ALWAYS
	battle.camera.ignore_rotation = false
	var colors: Array[Color] = Palette.COLORS.duplicate()
	var samples: Array = []
	var flat_sample: Dictionary = {}
	var flat_colors: Array[Color] = Palette.COLORS.duplicate()
	var rows: Array = []
	var fail := 0
	for pose: Vector2 in [Vector2(.65,0),Vector2(.4,0),Vector2(.98,0),Vector2(.65,14)]:
		battle.camera.position = Vector2(-6000,-3500)
		battle.camera.zoom = Vector2.ONE*pose.x
		battle.camera.rotation = deg_to_rad(pose.y)
		battle.camera.force_update_scroll()
		await tree.create_timer(.3).timeout
		var deadline := Time.get_ticks_msec()+15000
		while not Session.state_ready(map.debug_state()) and Time.get_ticks_msec()<deadline:
			await tree.process_frame
		if not Session.state_ready(map.debug_state()) or not await Static._wait_source(source,tree):
			fail += 1
			continue
		map.set_process(false)
		map._release_tile_ground()
		var stem := output.path_join("r80_%02d" % rows.size())
		var before := await Capture._capture(battle,map,stem+"_original")
		var reference := await source_only(battle,source,before.get_size())
		fail += int(reference.get_size()!=before.get_size())
		fail += int(reference.save_png(stem+"_source.png")!=OK)
		var held: Array[Dictionary] = []
		var replacements: Dictionary = {}
		for batch: Dictionary in map._batches.values():
			for layer in batch.nodes.size():
				var node: MeshInstance3D = batch.nodes[layer]
				var material: ShaderMaterial = node.material_override
				held.append({"node":node,"visible":node.visible,"mesh":node.mesh,"material":material,"layer":layer})
				if layer!=2:
					continue
				if not replacements.has(material.get_instance_id()):
					var code := Palette.shader_code(material.shader.code)
					if code.is_empty():
						fail += 1
						continue
					var replacement: ShaderMaterial = material.duplicate()
					var shader := Shader.new()
					shader.code = code
					replacement.shader = shader
					replacements[material.get_instance_id()] = replacement
				node.material_override = replacements[material.get_instance_id()]
		if rows.is_empty():
			for entry: Dictionary in held:
				entry.node.visible = entry.visible and entry.layer==2
			for category in Palette.COLORS.size():
				for material: ShaderMaterial in replacements.values():
					material.set_shader_parameter("ground_palette_mask",category)
				var mask := await Capture._capture(battle,map,stem+"_mask_%02d" % category)
				var sample := sample_color(reference,mask)
				if category==9:
					flat_sample = sample_color(reference,mask,2)
					if flat_sample.count>=64:
						flat_colors[9] = Color(flat_sample.rgb[0]/255.0,flat_sample.rgb[1]/255.0,flat_sample.rgb[2]/255.0)
					print("[R83 flat sample] ",flat_sample)
				if sample.count>=64:
					colors[category] = Color(sample.rgb[0]/255.0,sample.rgb[1]/255.0,sample.rgb[2]/255.0)
				sample["category"] = category
				sample["original_rgb"] = [roundi(Palette.COLORS[category].r*255),roundi(Palette.COLORS[category].g*255),roundi(Palette.COLORS[category].b*255)]
				samples.append(sample)
				print("[R80 palette sample] ",sample)
			var calibrated := 0
			for sample: Dictionary in samples:
				calibrated += int(sample.count>=64)
			fail += int(calibrated==0)
			fail += int(int(flat_sample.get("count",0))<64)
		for entry: Dictionary in held:
			entry.node.visible = entry.visible
		for material: ShaderMaterial in replacements.values():
			material.set_shader_parameter("ground_palette_mask",-1)
			material.set_shader_parameter("ground_palette",Palette.vectors(colors))
		await Capture._capture(battle,map,stem+"_candidate")
		for material: ShaderMaterial in replacements.values():
			material.set_shader_parameter("ground_palette_base_only",true)
		await Capture._capture(battle,map,stem+"_base_only")
		if int(flat_sample.get("count",0))>=64:
			for material: ShaderMaterial in replacements.values():
				material.set_shader_parameter("ground_palette",Palette.vectors(flat_colors))
			await Capture._capture(battle,map,stem+"_flat_base")
			for material: ShaderMaterial in replacements.values():
				material.set_shader_parameter("ground_palette_base_only",false)
				material.set_shader_parameter("ground_palette",Palette.vectors(Palette.semantic_colors(flat_colors[9])))
			await Capture._capture(battle,map,stem+"_semantic")
		var unchanged := var_to_bytes(BuildingRenderer._cache_entries)==collision
		for entry: Dictionary in held:
			unchanged = unchanged and entry.node.mesh==entry.mesh and entry.node.visible==entry.visible
			entry.node.material_override = entry.material
		var restored := await Capture._capture(battle,map,stem+"_restored")
		var error := Pixels._pixel_error(before,restored)
		fail += int(not unchanged or error>1)
		var roi: Array = []
		for point: Vector2 in [Vector2(-6300,-3700),Vector2(-2300,-3700),Vector2(-2300,-1700),Vector2(-6300,-1700)]:
			var pixel: Vector2 = map._camera.unproject_position(map._city.to_global(Vector3(point.x,0,point.y)))
			roi.append([pixel.x,pixel.y])
		rows.append({"pose":str(pose),"stem":stem,"state_unchanged":unchanged,"restore_error":error,"roi":roi,"map":map.debug_state()})
		print("[R80 palette] pose=",pose," restore=",error," state=",unchanged)
		map._viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		map.set_process(true)
	tree.paused = paused
	source.process_mode = mode
	battle.camera.ignore_rotation = ignore
	var file := FileAccess.open(output.path_join("r80_review.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"rows":rows,"samples":samples,"flat_sample":flat_sample,"semantic_colors":Palette.vectors(Palette.semantic_colors(flat_colors[9])),"fail":fail,"static_only":true,"calibration_pose":"0.65, 0"},"\t"))
	file.close()
	return fail


static func source_only(battle: Node, source: RasterBasemapRenderer, output_size: Vector2i) -> Image:
	# 仅诊断：共享已就绪纹理与shader参数，独立2D世界排除HUD/实体；不用作帧时间证据。
	var viewport := SubViewport.new()
	var logical_size: Vector2 = battle.get_viewport().get_visible_rect().size
	var rendered_size := Vector2(output_size)
	viewport.size = rendered_size
	viewport.disable_3d = true
	viewport.transparent_bg = true
	viewport.world_2d = World2D.new()
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	battle.get_tree().root.add_child(viewport)
	for entry: Dictionary in source.presentation_tiles():
		var sprite: Variant = entry.sprite.get_ref()
		if typeof(sprite)!=TYPE_OBJECT or not is_instance_valid(sprite) or not sprite.is_visible_in_tree():
			continue
		var copy: Variant = MeshInstance2D.new() if entry.get("projected",false) else Sprite2D.new()
		copy.texture = sprite.texture
		copy.material = sprite.material
		if entry.get("projected",false):
			copy.mesh = sprite.mesh
		else:
			copy.centered = sprite.centered
			copy.offset = sprite.offset
			copy.region_enabled = sprite.region_enabled
			copy.region_rect = sprite.region_rect
			copy.region_filter_clip_enabled = sprite.region_filter_clip_enabled
		copy.texture_filter = sprite.texture_filter
		copy.modulate = sprite.modulate
		copy.self_modulate = sprite.self_modulate
		copy.transform = Transform2D.IDENTITY.scaled(rendered_size/logical_size)*sprite.get_global_transform_with_canvas()
		viewport.add_child(copy)
	for frame in 4:
		await RenderingServer.frame_post_draw
	var picture := viewport.get_texture().get_image()
	viewport.queue_free()
	await battle.get_tree().process_frame
	await battle.get_tree().process_frame
	return picture


static func sample_color(reference: Image, mask: Image, flat_limit: int = -1) -> Dictionary:
	var channels: Array[PackedInt32Array] = []
	for channel in 3:
		var bins := PackedInt32Array()
		bins.resize(256)
		channels.append(bins)
	var count := 0
	if reference.get_size()!=mask.get_size():
		return {"count":0,"rgb":[]}
	for y in range(2,mask.get_height()-2,2):
		for x in range(2,mask.get_width()-2,2):
			if not mask_inside(mask.get_pixel(x,y)) or not mask_inside(mask.get_pixel(x-2,y)) or not mask_inside(mask.get_pixel(x+2,y)) or not mask_inside(mask.get_pixel(x,y-2)) or not mask_inside(mask.get_pixel(x,y+2)):
				continue
			var color := reference.get_pixel(x,y)
			if color.a<.999:
				continue
			if flat_limit>=0 and not source_flat(reference,x,y,flat_limit):
				continue
			count += 1
			for channel in 3:
				channels[channel][roundi(color[channel]*255)] += 1
	var rgb: Array[int] = []
	for bins in channels:
		var cumulative := 0
		for value in 256:
			cumulative += bins[value]
			if cumulative>count/2:
				rgb.append(value)
				break
	return {"count":count,"rgb":rgb}


static func source_flat(reference: Image, x: int, y: int, limit: int) -> bool:
	var center := reference.get_pixel(x,y)
	for offset: Vector2i in [Vector2i(-2,0),Vector2i(2,0),Vector2i(0,-2),Vector2i(0,2)]:
		var color := reference.get_pixel(x+offset.x,y+offset.y)
		if color.a<.999:
			return false
		for channel in 3:
			if absi(roundi(color[channel]*255)-roundi(center[channel]*255))>limit:
				return false
	return true


static func mask_inside(color: Color) -> bool:
	return color.a>=.999 and color.r>=.999 and color.g>=.999 and color.b>=.999
