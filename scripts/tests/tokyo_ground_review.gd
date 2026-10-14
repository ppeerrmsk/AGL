extends RefCounted
## 仅显式 Visual 诊断：同一原生深度/几何输出地表色板与无羽化反例，不修改归档。


static func capture(overlay: Node, owner_view: Viewport, stem: String) -> int:
	var failures := 0
	var was_processing: bool = overlay.is_processing()
	overlay.set_process(false)
	var saved: Array[Dictionary] = []
	failures += await shadowless(overlay, owner_view, stem + "_no_cast.png")
	var raw := ShaderMaterial.new()
	raw.shader = Shader.new()
	raw.shader.code = "shader_type spatial; render_mode unshaded; void fragment(){ ALBEDO=COLOR.rgb; }"
	var black := ShaderMaterial.new()
	black.shader = Shader.new()
	black.shader.code = "shader_type spatial; render_mode unshaded; void fragment(){ ALBEDO=vec3(0.0); }"
	for batch: Dictionary in overlay._batches.values():
		for kind in 3:
			var node: MeshInstance3D = batch.nodes[kind]
			saved.append({"node": node, "material": node.material_override})
			node.material_override = raw if kind == 2 else black
	overlay._viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	failures += int(overlay._viewport.get_texture().get_image().save_png(stem + "_ground_ids.png") != OK)
	for entry: Dictionary in saved:
		entry.node.material_override = entry.material
	var original_shader: Shader = overlay._composite.shader
	var hard := Shader.new()
	hard.code = "shader_type canvas_item; void fragment(){ COLOR=texture(TEXTURE,UV); }"
	overlay._composite.shader = hard
	overlay._viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	failures += int(owner_view.get_texture().get_image().save_png(stem + "_no_feather.png") != OK)
	var calibrated := palette_material(overlay._materials[4])
	for batch: Dictionary in overlay._batches.values():
		batch.nodes[2].material_override = calibrated
	overlay._viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	failures += int(owner_view.get_texture().get_image().save_png(stem + "_palette_a.png") != OK)
	var balanced: Dictionary = {}
	for entry: Dictionary in saved:
		var key: int = entry.material.get_instance_id()
		if not balanced.has(key):
			balanced[key] = palette_material(entry.material, true)
		entry.node.material_override = balanced[key]
	overlay._viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	failures += int(owner_view.get_texture().get_image().save_png(stem + "_palette_b.png") != OK)
	for entry: Dictionary in saved:
		entry.node.material_override = entry.material
	overlay._composite.shader = original_shader
	for entry: Dictionary in saved:
		failures += int(entry.node.material_override != entry.material)
	overlay._viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	overlay.set_process(was_processing)
	await RenderingServer.frame_post_draw
	return failures


static func palette_material(original: ShaderMaterial, balanced: bool = false) -> ShaderMaterial:
	# A为同位色板假设，不是发布值；水色和所有楼体原封不动。
	var palette := {"80877e": "a0a69f", "697d65": "9ca396", "64765f": "969f90",
		"95958a": "919790", "757d77": "909992", "636d6b": "8b8d84", "6e7772": "959b91"}
	if balanced:
		# B保持比地面更亮的屋顶、较暗的道路/绿地，不改任何顶点位置和高度。
		palette = preload("res://scripts/experiments/tokyo_palette.gd").PAIRS
	var replacement := "vec3 base = COLOR.rgb;\n"
	var first := true
	for source: String in palette:
		var before := Color(source)
		var after := Color(String(palette[source]))
		replacement += ("if" if first else "else if") + " (distance(base, vec3(%.8f,%.8f,%.8f)) < 0.002) { base=vec3(%.8f,%.8f,%.8f); }\n" % [before.r, before.g, before.b, after.r, after.g, after.b]
		first = false
	var result: ShaderMaterial = original.duplicate()
	result.shader = Shader.new()
	result.shader.code = original.shader.code.replace("vec3 base = COLOR.rgb;", replacement)
	return result


static func shadowless(overlay: Node, owner_view: Viewport, path: String) -> int:
	# 保留光源的shadow_enabled及渲染路径，只停投影者；否则GL整片亮度会改变。
	var was_processing: bool = overlay.is_processing()
	overlay.set_process(false)
	var saved: Array[Dictionary] = []
	for batch: Dictionary in overlay._batches.values():
		for node: MeshInstance3D in batch.nodes:
			saved.append({"node": node, "shadow": node.cast_shadow})
			node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	overlay._viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var failures := int(owner_view.get_texture().get_image().save_png(path) != OK)
	for entry: Dictionary in saved:
		entry.node.cast_shadow = entry.shadow
		failures += int(entry.node.cast_shadow != entry.shadow)
	overlay._viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	overlay.set_process(was_processing)
	await RenderingServer.frame_post_draw
	return failures


static func palette_reference(overlay: Node, owner_view: Viewport, stem: String) -> int:
	# R32同场景反例：相机/太阳不变，换回R30原mesh+R31-B材质，避免把跨次渲染差异归咎于离线颜色。
	var was_processing: bool = overlay.is_processing()
	overlay.set_process(false)
	var saved: Array[Dictionary] = []
	var materials: Dictionary = {}
	for id: int in overlay._batches:
		var batch: Dictionary = overlay._batches[id]
		var fixed: Resource = ResourceLoader.load(String(overlay._archive.cells[id].fixed).replace("r32_cells", "r30_cells"), "", ResourceLoader.CACHE_MODE_IGNORE)
		var building: Resource = ResourceLoader.load(String(batch.path).replace("r32_cells", "r30_cells"), "", ResourceLoader.CACHE_MODE_IGNORE)
		for kind in 3:
			var node: MeshInstance3D = batch.nodes[kind]
			saved.append({"node": node, "mesh": node.mesh, "material": node.material_override})
			var key: int = node.material_override.get_instance_id()
			if not materials.has(key):
				materials[key] = palette_material(node.material_override, true)
			node.material_override = materials[key]
			node.mesh = fixed.meshes[0] if kind == 2 else building.meshes[kind]
			if kind == 0 and batch.precision_guarded:
				node.mesh = building.precision_original
	overlay._viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	for frame in 5:
		await RenderingServer.frame_post_draw
	var failures := int(owner_view.get_texture().get_image().save_png(stem + "_reference.png") != OK)
	for entry: Dictionary in saved:
		entry.node.mesh = entry.mesh
		entry.node.material_override = entry.material
	for frame in 5:
		await RenderingServer.frame_post_draw
	failures += int(owner_view.get_texture().get_image().save_png(stem + "_settled.png") != OK)
	overlay._viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	overlay.set_process(was_processing)
	return failures
