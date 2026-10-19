extends RefCounted
## 同一网格展示与实机验收；固定时相，不向正式天气注入演示轮廓。

static func contour(layer: int, seed_value: float) -> PackedVector3Array:
	var points := PackedVector3Array()
	var scale_value := [1.0, 0.84, 0.60][layer] as float
	for i in range(96):
		var a := TAU * float(i) / 96.0
		var radius := 1.0 + 0.17*sin(3.0*a+seed_value) + 0.09*cos(5.0*a-0.6) + 0.035*sin(9.0*a+seed_value)
		points.append(Vector3(cos(a)*1650.0*radius*scale_value + layer*100.0, 240.0+layer*210.0, sin(a)*690.0*radius*scale_value))
	return points

static func mesh_node(vertices: PackedVector3Array, colors: PackedColorArray, primitive: int, material: Material) -> MeshInstance3D:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_COLOR] = colors
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(primitive, arrays)
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return node

static func build_gallery() -> Node3D:
	var root := Node3D.new()
	var lines := PackedVector3Array()
	var colors := PackedColorArray()
	var fill := PackedVector3Array()
	var fill_colors := PackedColorArray()
	for cloud in range(3):
		var center: Vector3 = [Vector3(-1900,0,-1100), Vector3(2050,0,-800), Vector3(0,0,1500)][cloud]
		var turn := Basis(Vector3.UP, [0.12,-0.30,0.23][cloud])
		for layer in range(3):
			var ring := contour(layer, float(cloud)*1.7)
			var tint := Color(0.52,0.64,0.58).lerp(Color(0.79,0.86,0.78),float(layer)/2.0)
			for i in range(96):
				lines.append(center + turn*ring[i])
				lines.append(center + turn*ring[(i+1)%96])
				colors.append(tint)
				colors.append(tint)
			if layer == 0:
				var polygon := PackedVector2Array()
				for p in ring:
					polygon.append(Vector2(p.x,p.z))
				var indices := Geometry2D.triangulate_polygon(polygon)
				for index in indices:
					fill.append(center + turn*ring[index])
					fill_colors.append(Color(0.55,0.68,0.60,0.24))
			# 少数高度连接线，避免密集线框像山体。
			if layer < 2:
				var upper := contour(layer+1, float(cloud)*1.7)
				for i in [6,38,70]:
					lines.append(center+turn*ring[i])
					lines.append(center+turn*upper[i])
					colors.append(Color(0.40,0.51,0.46))
					colors.append(Color(0.40,0.51,0.46))
	var line_material := StandardMaterial3D.new()
	line_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	line_material.vertex_color_use_as_albedo = true
	var fill_material := ShaderMaterial.new()
	fill_material.shader = preload("res://resources/shaders/weather_holo_preview.gdshader")
	root.add_child(mesh_node(lines,colors,Mesh.PRIMITIVE_LINES,line_material))
	root.add_child(mesh_node(fill,fill_colors,Mesh.PRIMITIVE_TRIANGLES,fill_material))
	print("Holo geometry: lines=",lines.size()/2," triangles=",fill.size()/3," surfaces=2")
	return root

static func render_display(host: Node, gallery: Node3D) -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1600,900)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	host.add_child(viewport)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.035,0.048,0.044)
	viewport.add_child(env)
	var copy := gallery.duplicate() as Node3D
	copy.basis = Basis.IDENTITY
	viewport.add_child(copy)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 7800.0
	camera.far = 30000.0
	viewport.add_child(camera)
	camera.position = Vector3(0,7200,7000)
	camera.look_at(Vector3(0,200,0))
	for i in range(4):
		await host.get_tree().process_frame
	await RenderingServer.frame_post_draw
	var error := viewport.get_texture().get_image().save_png("res://bench/results/weather_holo_display.png")
	if error != OK:
		push_error("Holo display capture failed")
	viewport.queue_free()
	await host.get_tree().process_frame

static func run(host: Node, mode: Node, owner: Node3D, map_name: String) -> void:
	var tree := host.get_tree()
	mode._camera_ctrl.follow_enabled = false
	mode._camera_ctrl.set_process(false)
	owner.set_enabled(false)
	mode._weather.set_meta(&"weather_volume_owner",weakref(owner))
	mode._weather.queue_redraw()
	var gallery := build_gallery()
	gallery.basis = owner.basis
	owner.get_parent().add_child(gallery)
	if map_name == "desert_railway":
		await render_display(host,gallery)
	for view in ["field","close"]:
		mode.camera.position = Vector2.ZERO if view == "field" else Vector2(-1900,-1100)
		mode.camera.rotation = 0.0
		var zoom := 0.18 if view == "field" else 0.32
		mode._camera_ctrl.target_zoom = zoom
		mode._camera_ctrl._base_zoom = zoom
		mode.camera.zoom = Vector2.ONE*zoom
		mode.player_aircraft.global_position = mode.camera.position + Vector2(0,1100)
		mode.player_aircraft.clear_trail()
		mode.camera.force_update_scroll()
		await tree.create_timer(1.0).timeout
		await RenderingServer.frame_post_draw
		var path := "res://bench/results/weather_holo_%s_%s.png" % [map_name,view]
		if host.get_viewport().get_texture().get_image().save_png(path) != OK:
			push_error("Holo field capture failed: "+path)
		print("Holo capture: ",path)
	gallery.queue_free()
	await tree.process_frame
