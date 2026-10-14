extends RefCounted
## 独立动态体采样样板；CPU只更新时间，三维形变/点阵均由GPU完成。

static func build_gallery(noise_texture: Texture3D) -> Node3D:
	if OS.get_environment("AGL_WEATHER_DUST") == "1":
		return build_storm(noise_texture)
	var root := Node3D.new()
	var sizes: Array[Vector3] = [Vector3(1850,520,900),Vector3(1450,620,750),Vector3(1100,380,600),Vector3(630,250,340)]
	var positions: Array[Vector3] = [Vector3(-1900,660,-1050),Vector3(2000,740,-650),Vector3(-200,520,1500),Vector3(2300,390,1700)]
	for i in range(4):
		var node := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3.ONE*2.0
		node.mesh = box
		node.scale = sizes[i]
		node.position = positions[i]
		node.rotation.y = [0.13,-0.27,0.21,-0.1][i]
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.extra_cull_margin=1200.0
		var material := ShaderMaterial.new()
		material.shader = preload("res://resources/shaders/weather_density_preview.gdshader")
		material.set_shader_parameter("cloud_noise",noise_texture)
		material.set_shader_parameter("cloud_seed",float(i)*0.217)
		material.set_shader_parameter("loop_period",[28.0,35.0,43.0,52.0][i])
		material.set_shader_parameter("drift_velocity",Vector2(0.005+float(i)*0.0012,0.0015))
		node.material_override = material
		root.add_child(node)
	return root

static func set_time(gallery: Node3D, seconds: float) -> void:
	# 四个固定实例，仅验收协程调用，不引入正式场景tick。
	for node: GeometryInstance3D in gallery.get_children():
		node.material_override.set_shader_parameter("weather_time",seconds)

static func capture(host: Node, path: String) -> Image:
	await RenderingServer.frame_post_draw
	var image := host.get_viewport().get_texture().get_image()
	if image.save_png(path) != OK:
		push_error("Density capture failed: "+path)
	return image

static func measure(host: Node, gallery: Node3D, map_name: String) -> void:
	var viewport := gallery.get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(viewport,true)
	var rows: Array[Dictionary] = []
	for steps in [0,24,16,0]:
		var enabled: bool = steps > 0
		gallery.visible = enabled
		if enabled:
			for node: GeometryInstance3D in gallery.get_children():
				if node is MeshInstance3D:
					node.material_override.set_shader_parameter("march_steps",steps)
		for i in range(30):
			await host.get_tree().process_frame
		var gpu := 0.0
		var cpu := 0.0
		var worst := 0.0
		var below := 0
		var wall_sum := 0.0
		var previous := Time.get_ticks_usec()
		for i in range(120):
			set_time(gallery,float(i)/60.0)
			await RenderingServer.frame_post_draw
			var now := Time.get_ticks_usec()
			var wall := float(now-previous)/1000.0
			previous=now
			wall_sum += wall
			worst=maxf(worst,wall)
			if wall > 1000.0/60.0:
				below+=1
			gpu+=RenderingServer.viewport_get_measured_render_time_gpu(viewport)
			cpu+=RenderingServer.viewport_get_measured_render_time_cpu(viewport)
		var row := {"on":enabled,"steps":steps,"gpu_ms":gpu/120.0,"cpu_render_ms":cpu/120.0,"avg_fps":120000.0/wall_sum,"worst_frame_ms":worst,"frames_below_60":below}
		rows.append(row)
		print("Density sample ",map_name," ",row)
	RenderingServer.viewport_set_measure_render_time(viewport,false)
	gallery.show()
	for node: GeometryInstance3D in gallery.get_children():
		if node is MeshInstance3D:
			node.material_override.set_shader_parameter("march_steps",24)
	var kind := "dust" if OS.get_environment("AGL_WEATHER_DUST") == "1" else "animated_cloud"
	var file := FileAccess.open("res://bench/results/weather_%s_%s_timing.json" % [kind,map_name],FileAccess.WRITE)
	file.store_string(JSON.stringify(rows,"\t"))

static func run(host: Node, mode: Node, owner: Node3D, map_name: String) -> void:
	var tree := host.get_tree()
	var kind := "dust" if OS.get_environment("AGL_WEATHER_DUST") == "1" else "animated_cloud"
	var texture := NoiseTexture3D.new()
	texture.width=64
	texture.height=64
	texture.depth=64
	texture.seamless=true
	var noise := FastNoiseLite.new()
	noise.seed=270927
	noise.frequency=0.075
	noise.fractal_octaves=4
	texture.noise=noise
	await texture.changed
	owner.set_enabled(false)
	mode._weather.set_meta(&"weather_volume_owner",weakref(owner))
	mode._weather.queue_redraw()
	mode._camera_ctrl.follow_enabled=false
	mode._camera_ctrl.set_process(false)
	mode.camera.rotation=0.0
	mode.camera.position=Vector2.ZERO
	mode._camera_ctrl.target_zoom=0.18
	mode._camera_ctrl._base_zoom=0.18
	mode.camera.zoom=Vector2.ONE*0.18
	mode.camera.force_update_scroll()
	var gallery := build_gallery(texture)
	gallery.basis=owner.basis
	owner.get_parent().add_child(gallery)
	# 只在样板内修正当前视口合成；退出恢复原材质，不修改正式合成器。
	var screen: TextureRect
	for candidate in tree.root.find_children("*","TextureRect",true,false):
		if candidate.texture == gallery.get_viewport().get_texture():
			screen=candidate
			break
	var original_material: Material
	if screen != null:
		original_material=screen.material
		var composite := ShaderMaterial.new()
		composite.shader=preload("res://resources/shaders/weather_density_composite_preview.gdshader")
		screen.material=composite
		print("Density premult composite: ",screen.get_path())
	elif not gallery.get_viewport().transparent_bg:
		print("Density direct opaque viewport: ",gallery.get_viewport().get_path())
	else:
		push_error("Density preview composite not found")
		tree.quit(1)
		return
	await tree.create_timer(1.0).timeout
	await measure(host,gallery,map_name)
	# 动画录制冻结游戏时间，只推进云的指定时间，保证相机/战局可比较。
	tree.paused=true
	for frame in range(96 if map_name == "desert_railway" else 1):
		set_time(gallery,float(frame)*0.125)
		await tree.process_frame
		await capture(host,"res://bench/results/weather_%s_%s_%03d.png" % [kind,map_name,frame])
	set_time(gallery,0.0)
	await tree.process_frame
	var first := await capture(host,"res://bench/results/weather_%s_%s_still.png" % [kind,map_name])
	await tree.create_timer(0.25,true,false,true).timeout
	await RenderingServer.frame_post_draw
	var second := host.get_viewport().get_texture().get_image()
	# 原HUD可能有独立动画，仅检查没有UI/飞机的云区。
	var a := first.get_region(Rect2i(250,130,450,220)).get_data()
	var b := second.get_region(Rect2i(250,130,450,220)).get_data()
	if a != b:
		push_error("Density frozen clock changed cloud region")
	else:
		print("Density frozen clock: PASS")
	for node: GeometryInstance3D in gallery.get_children():
		if node is MeshInstance3D:
			node.material_override.set_shader_parameter("march_steps",16)
	await tree.process_frame
	await capture(host,"res://bench/results/weather_%s_%s_steps16.png" % [kind,map_name])
	if kind == "animated_cloud" and map_name == "desert_railway":
		await check_loop(host,gallery)
	if screen != null:
		screen.material=original_material
	tree.paused=false
	gallery.queue_free()
	await tree.process_frame

static func build_storm(noise_texture: Texture3D) -> Node3D:
	var root := Node3D.new()
	var wall := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size=Vector3.ONE*2.0
	wall.mesh=box
	wall.scale=Vector3(1250,600,3400)
	wall.position=Vector3(-350,580,0)
	wall.extra_cull_margin=1200.0
	wall.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := ShaderMaterial.new()
	material.shader=preload("res://resources/shaders/weather_density_preview.gdshader")
	material.set_shader_parameter("cloud_noise",noise_texture)
	material.set_shader_parameter("dust_mode",true)
	material.set_shader_parameter("scan_enabled",false)
	material.set_shader_parameter("loop_period",18.0)
	material.set_shader_parameter("drift_velocity",Vector2(25.0/1250.0,0.0))
	wall.material_override=material
	root.add_child(wall)
	var grit := MultiMeshInstance3D.new()
	var mm := MultiMesh.new()
	mm.transform_format=MultiMesh.TRANSFORM_3D
	mm.use_custom_data=true
	var mesh := ArrayMesh.new()
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=PackedVector3Array([Vector3.ZERO,Vector3(65,0,0),Vector3(0,0,5)])
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	mm.mesh=mesh
	mm.instance_count=128
	mm.custom_aabb=AABB(Vector3(-1700,0,-2600),Vector3(4400,250,5200))
	var rng := RandomNumberGenerator.new()
	rng.seed=927
	for i in range(128):
		mm.set_instance_transform(i,Transform3D.IDENTITY)
		mm.set_instance_custom_data(i,Color(rng.randf(),rng.randf(),rng.randf(),rng.randf()))
	grit.multimesh=mm
	grit.position=Vector3(-350,0,0)
	grit.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var grit_material := ShaderMaterial.new()
	grit_material.shader=preload("res://resources/shaders/weather_dust_streak_preview.gdshader")
	grit.material_override=grit_material
	root.add_child(grit)
	return root

static func check_loop(host: Node, gallery: Node3D) -> void:
	var nodes := gallery.get_children()
	for i in range(nodes.size()):
		nodes[i].visible=i==0
	var material: ShaderMaterial=nodes[0].material_override
	material.set_shader_parameter("drift_enabled",false)
	material.set_shader_parameter("weather_time",0.0)
	await host.get_tree().process_frame
	await RenderingServer.frame_post_draw
	var a := host.get_viewport().get_texture().get_image().get_region(Rect2i(240,100,560,280)).get_data()
	material.set_shader_parameter("weather_time",28.0)
	await host.get_tree().process_frame
	await RenderingServer.frame_post_draw
	var b := host.get_viewport().get_texture().get_image().get_region(Rect2i(240,100,560,280)).get_data()
	var error_sum := 0.0
	for i in range(a.size()):
		error_sum+=absf(float(a[i])-float(b[i]))
	var mean_error := error_sum/float(a.size())
	print("Cloud loop seam mean byte error=",mean_error)
	if mean_error > 0.02:
		push_error("Cloud cycle has visible seam")
		host.get_tree().quit(1)
