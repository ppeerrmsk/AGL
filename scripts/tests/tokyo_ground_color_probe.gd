extends RefCounted
## 同位因素隔离；临时克隆正式瓦片材质，结束后恢复原引用，不写用户设置。
const Ground := preload("res://scripts/experiments/tokyo_tile_ground_candidate.gd")
const Review := preload("res://scripts/tests/tokyo_tile_ground_review.gd")
const Session := preload("res://scripts/rendering/tokyo_volume_preload.gd")
const Capture := preload("res://scripts/tests/tokyo_ao_review.gd")
const Pixels := preload("res://scripts/tests/tokyo_shell_review.gd")
const COLOR_INVERSE := """
vec3 canvas_roundtrip_input(vec3 color) {
 vec3 target = pow((clamp(color,vec3(0.0),vec3(1.0))+vec3(0.055))/1.055,vec3(2.4));
 vec3 value = max(color,vec3(0.04));
 for(int i=0;i<5;i++) {
  vec3 error = value*(value*(value*0.305306011+0.682171111)+0.012522878)-target;
  vec3 slope = value*(value*0.915918033+1.364342222)+0.012522878;
  value = max(vec3(0.0),value-error/slope);
 }
 return value;
}
"""


static func run(battle: Node, map: Node, output: String) -> int:
	var tree := battle.get_tree()
	var paused := tree.paused
	var source: RasterBasemapRenderer = battle._map_features._raster_basemap
	var process := source.process_mode
	var msaa: int = map._viewport.msaa_3d
	tree.paused = true
	source.process_mode = Node.PROCESS_MODE_ALWAYS
	battle.camera.position = Vector2(-6000,-3500)
	battle.camera.zoom = Vector2.ONE*.26
	battle.camera.rotation = 0
	battle.camera.force_update_scroll()
	await tree.create_timer(.3).timeout
	var deadline := Time.get_ticks_msec()+15000
	while not Session.state_ready(map.debug_state()) and Time.get_ticks_msec()<deadline:
		await tree.process_frame
	if not Session.state_ready(map.debug_state()) or not await Review._wait_source(source,tree):
		tree.paused = paused
		source.process_mode = process
		return 1
	map.set_process(false)
	var held: Array[Dictionary] = []
	for batch: Dictionary in map._batches.values():
		for node: MeshInstance3D in batch.nodes:
			held.append({"node":node,"visible":node.visible,"mesh":node.mesh})
			node.hide()
	var tiles: Array[Dictionary] = []
	for entry: Dictionary in source.presentation_tiles():
		var sprite: Variant = entry.sprite.get_ref()
		if typeof(sprite)==TYPE_OBJECT and is_instance_valid(sprite):
			tiles.append({"sprite":sprite,"material":sprite.material})
	var rows: Array = []
	var fail := 0
	for mode: String in ["full","edge_off","grain_off","plain","no_msaa","uniform_texel","screen_down","screen_up","raw_uniforms","inverse_curve","ramp","ramp_inverse","corrected","ramp_corrected","shadow_clear"]:
		for tile: Dictionary in tiles:
			var material: ShaderMaterial = tile.material.duplicate()
			if mode in ["edge_off","plain"]:
				material.set_shader_parameter("edge_gain",0.0)
			if mode in ["grain_off","plain"]:
				material.set_shader_parameter("grain_strength",0.0)
			if mode=="uniform_texel":
				var shader := Shader.new()
				shader.code = material.shader.code.replace("shader_type canvas_item;","shader_type canvas_item;\nuniform vec2 explicit_texel;").replace("TEXTURE_PIXEL_SIZE","explicit_texel")
				material.shader = shader
				material.set_shader_parameter("explicit_texel",Vector2.ONE/Vector2(tile.sprite.texture.get_size()))
			if mode.begins_with("ramp"):
				var shader := Shader.new()
				shader.code = material.shader.code.replace("\tCOLOR = vec4(clamp(color.rgb, 0.0, 1.0), color.a) * item_modulate;", "color = vec4(vec3(mod(floor(FRAGCOORD.x),256.0)/255.0),1.0);\n\tCOLOR = vec4(clamp(color.rgb, 0.0, 1.0), color.a) * item_modulate;")
				material.shader = shader
			tile.sprite.material = material
		map._viewport.msaa_3d = Viewport.MSAA_DISABLED if mode=="no_msaa" else msaa
		var stem := output.path_join("r73_color_"+mode)
		map._screen.hide()
		await Capture._capture(battle,map,stem+"_2d")
		map._screen.show()
		var ground := Ground.new()
		if not ground.bind(map,source,mode=="shadow_clear"):
			fail += 1
		else:
			if mode not in ["corrected","ramp_corrected","shadow_clear"]:
				for node: MeshInstance3D in ground._nodes:
					var material: ShaderMaterial = node.material_override
					var shader := Shader.new()
					shader.code = material.shader.code.replace(Ground.ColorTransfer.finish(false),"ALBEDO = clamp(color.rgb, 0.0, 1.0) * item_modulate.rgb;")
					material.shader = shader
			if mode in ["inverse_curve","ramp_inverse"]:
				for node: MeshInstance3D in ground._nodes:
					var material: ShaderMaterial = node.material_override
					var shader := Shader.new()
					shader.code = material.shader.code.replace("void fragment() {",COLOR_INVERSE+"\nvoid fragment() {").replace("ALBEDO = clamp(color.rgb, 0.0, 1.0) * item_modulate.rgb;","ALBEDO = canvas_roundtrip_input(clamp(color.rgb, 0.0, 1.0) * item_modulate.rgb);")
					material.shader = shader
			if mode=="raw_uniforms":
				for node: MeshInstance3D in ground._nodes:
					var material: ShaderMaterial = node.material_override
					var shader := Shader.new()
					shader.code = material.shader.code.replace("uniform vec4 tint : source_color", "uniform vec4 tint").replace("uniform vec4 edge_color : source_color", "uniform vec4 edge_color")
					material.shader = shader
			if mode.begins_with("screen_"):
				var inverse: Transform2D = map._last_canvas.affine_inverse()
				for node: MeshInstance3D in ground._nodes:
					var material: ShaderMaterial = node.material_override
					var tile: Dictionary = {}
					for entry: Dictionary in tiles:
						if entry.sprite.texture==material.get_shader_parameter("map_texture"):
							tile = entry
					if tile.is_empty():
						fail += 1
						continue
					var sprite: Sprite2D = tile.sprite
					var size := Vector2(sprite.texture.get_size())
					var region: Rect2 = sprite.region_rect if sprite.region_enabled else Rect2(Vector2.ZERO,size)
					var code: String = material.shader.code
					var split := code.find("void fragment() {")
					var fragment := code.substr(split).replace("UV","stable_uv")
					var point := "FRAGCOORD.xy" if mode=="screen_down" else "vec2(FRAGCOORD.x,VIEWPORT_SIZE.y-FRAGCOORD.y)"
					fragment = fragment.replace("void fragment() {","void fragment() {\n vec2 pixel = "+point+";\n vec2 stable_uv = stable_origin + pixel.x*stable_dx + pixel.y*stable_dy;")
					var shader := Shader.new()
					shader.code = code.substr(0,split).replace("shader_type spatial;","shader_type spatial;\nuniform vec2 stable_origin;\nuniform vec2 stable_dx;\nuniform vec2 stable_dy;")+fragment
					material.shader = shader
					material.set_shader_parameter("stable_origin",(region.position+(inverse.origin-sprite.position)/sprite.scale)/size)
					material.set_shader_parameter("stable_dx",inverse.x/sprite.scale/size*map._screen.scale.x)
					material.set_shader_parameter("stable_dy",inverse.y/sprite.scale/size*map._screen.scale.y)
			await Capture._capture(battle,map,stem+"_ground_only")
			rows.append({"mode":mode,"stem":stem,"ground":ground.stats.duplicate(true)})
		ground.close()
	for tile: Dictionary in tiles:
		tile.sprite.material = tile.material
	for entry: Dictionary in held:
		entry.node.visible = entry.visible
		fail += int(entry.node.mesh!=entry.mesh)
	map._viewport.msaa_3d = msaa
	map._viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	map.set_process(true)
	source.process_mode = process
	tree.paused = paused
	var file := FileAccess.open(output.path_join("r73_color_probe.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"rows":rows,"fail":fail,"diagnostic_only":true},"\t"))
	file.close()
	print("[R73 color probe] modes=",rows.size()," fail=",fail)
	return fail
