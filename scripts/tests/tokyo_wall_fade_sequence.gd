extends RefCounted
## 固定低墙分层的连续相机采样；每姿态有同位原形参考，不用于帧时统计。


static func run(root: String, output: String, viewport: SubViewport, camera: Camera3D, low: MeshInstance3D, full: ArrayMesh, reduced: ArrayMesh, material: ShaderMaterial) -> int:
	var path := root.path_join("r183-wall-transition-a/walls.bin")
	if FileAccess.get_sha256(path)!="2c25c0d0aaa8a5cfc9bc9c89c2fcfeb08edff82344f233c8ea4bf9ff5ee7db71":
		return 1
	var mesh := preload("res://scripts/tests/tokyo_residential_patch.gd").decode(FileAccess.get_file_as_bytes(path))
	if mesh==null:
		return 1
	var wall := MeshInstance3D.new()
	wall.mesh=mesh
	var fade_material: ShaderMaterial = material.duplicate()
	fade_material.set_shader_parameter("outgoing",true)
	wall.material_override=fade_material
	viewport.add_child(wall)
	viewport.size=Vector2i(512,512)
	var rows: Array = []
	var fail := 0
	for step in 81:
		var t := float(step)/80.0
		var scale := .18+.47*sin(PI*t)
		var angle := 90.0*sin(PI*t)
		var center := Vector3(-6675+40*sin(TAU*t),0,-2325+30*sin(TAU*t))
		var offset := Vector3(0,cos(deg_to_rad(38)),sin(deg_to_rad(38)))*15000
		camera.size=512.0/scale
		camera.position=center+offset.rotated(Vector3.UP,deg_to_rad(angle))
		camera.look_at(center,Vector3.UP)
		var fade := 1.0-smoothstep(.32,.48,scale)
		var row := {"step":step,"scale":scale,"rotation":angle,"center":[center.x,center.z],"fade":fade}
		for variant: String in ["reference","candidate"]:
			low.mesh=full if variant=="reference" else reduced
			wall.visible=variant=="candidate" and fade<1.0
			fade_material.set_shader_parameter("lod_mix",fade)
			for frame in 3:
				await RenderingServer.frame_post_draw
			fail+=int(viewport.get_texture().get_image().save_png(output.path_join("%03d_%s.png"%[step,variant]))!=OK)
			row[variant+"_primitives"]=RenderingServer.viewport_get_render_info(viewport.get_viewport_rid(),RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE,RenderingServer.VIEWPORT_RENDER_INFO_PRIMITIVES_IN_FRAME)
			row[variant+"_draw_calls"]=RenderingServer.viewport_get_render_info(viewport.get_viewport_rid(),RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE,RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME)
		rows.append(row)
		if step%20==0:
			print("[R184 wall fade] step=",step," fade=",fade)
	wall.queue_free()
	var file := FileAccess.open(output.path_join("sequence.json"),FileAccess.WRITE)
	if file==null:
		return 1
	file.store_string(JSON.stringify({"rows":rows,"fail":fail,"fade_start_scale":.32,"full_wall_scale":.48,"same_pose_references":true,"runtime_integrated":false,"gameplay_performance_evidence":false,"ao_validated":false},"  "))
	file.close()
	return fail
