extends RefCounted
## 独立GL同位对拍，不替代全游戏流送、AO或帧时验收。
const Patch := preload("res://scripts/tests/tokyo_residential_patch.gd")
const Join := preload("res://scripts/experiments/tokyo_packed_mesh_join.gd")


static func run(parent: Node, root: String, output: String) -> int:
	var base_path := root.path_join("r179-joint-patch-b/shared-complete.bin")
	var proxy_path := root.path_join("r182-roof-proxy-a/shared-roofs.bin")
	var outside_path := root.path_join("r179-joint-patch-b/lod3_full-outside.bin")
	var page_path := root.path_join("r150-native-a/lod3_full/parent_11.res")
	if DisplayServer.get_name()=="headless" or DirAccess.dir_exists_absolute(output):
		return 1
	if FileAccess.get_sha256(base_path)!="159183c9bff5d28c5c99a67c1abca4a611ca1c05d90b8a5da1bb7c6b2007533c" or FileAccess.get_sha256(proxy_path)!="26af7663d53837adc5f4697ffe6a53f7beb260dce1e448a6c5db56b253861d13":
		return 1
	if FileAccess.get_sha256(outside_path)!="2efe0084cc557cfc64ba5de745d3c9d9bc033ba9fc0fe555d887fe11b8ac59d8" or FileAccess.get_sha256(page_path)!="57e1db2f7d21a6d03bc7664717e2f1575f3aae66bd2f29e2031ebf4e234d9f54":
		return 1
	var outside := Patch.decode(FileAccess.get_file_as_bytes(outside_path))
	var base := Patch.decode(FileAccess.get_file_as_bytes(base_path))
	var proxy := Patch.decode(FileAccess.get_file_as_bytes(proxy_path))
	var page: Resource = load(page_path)
	if outside==null or base==null or proxy==null or page==null or not page.valid():
		return 1
	var full := Join.join([outside,base])
	var reduced := Join.join([outside,proxy])
	var viewport := SubViewport.new()
	viewport.size=Vector2i(1200,900)
	viewport.own_world_3d=true
	viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	parent.add_child(viewport)
	var camera := Camera3D.new()
	viewport.add_child(camera)
	camera.projection=Camera3D.PROJECTION_ORTHOGONAL
	camera.far=30000
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees=Vector3(-50,-35,0)
	sun.light_energy=.8
	sun.shadow_enabled=false
	viewport.add_child(sun)
	var material := ShaderMaterial.new()
	material.shader=preload("res://resources/shaders/tokyo_volume_surface.gdshader")
	var nodes: Array[MeshInstance3D] = []
	for mesh: ArrayMesh in page.meshes:
		var node := MeshInstance3D.new()
		node.mesh=mesh
		node.material_override=material
		viewport.add_child(node)
		nodes.append(node)
	DirAccess.make_dir_recursive_absolute(output)
	if OS.get_environment("AGL_TOKYO_WALL_FADE_SEQUENCE")=="1":
		var sequence_fail: int = await preload("res://scripts/tests/tokyo_wall_fade_sequence.gd").run(root,output,viewport,camera,nodes[0],full,reduced,material)
		viewport.queue_free()
		await parent.get_tree().process_frame
		return sequence_fail
	var rows: Array = []
	var fail := 0
	var center := Vector3(-6675,0,-2325)
	var slot := 0
	for scale: float in [.1,.18,.30666663,.65]:
		camera.size=900.0/scale
		for rotation: float in [0.,14.,90.]:
			var offset := Vector3(0,cos(deg_to_rad(38)),sin(deg_to_rad(38)))*15000
			camera.position=center+offset.rotated(Vector3.UP,deg_to_rad(rotation))
			camera.look_at(center,Vector3.UP)
			for variant: String in ["full","proxy","restore"]:
				nodes[0].mesh=reduced if variant=="proxy" else full
				for frame in 3:
					await RenderingServer.frame_post_draw
				var filename := "%02d_%s.png"%[slot,variant]
				fail+=int(viewport.get_texture().get_image().save_png(output.path_join(filename))!=OK)
			rows.append({"slot":slot,"scale":scale,"rotation":rotation,"camera_size":camera.size,"tilt":38})
			slot+=1
	viewport.queue_free()
	await parent.get_tree().process_frame
	var file := FileAccess.open(output.path_join("report.json"),FileAccess.WRITE)
	if file==null:
		return 1
	file.store_string(JSON.stringify({"rows":rows,"fail":fail,"removed_faces":2689,"runtime_integrated":false,"ao_validated":false,"continuous_camera_evidence":false},"  "))
	file.close()
	print("[R183 roof proxy] pairs=",rows.size()," fail=",fail)
	return fail
