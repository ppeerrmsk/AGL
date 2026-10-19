extends RefCounted
## 只用于造型验收：同镜头读取离线融合网格，不接管正式天气判定。

static func build_mesh(data: Dictionary) -> ArrayMesh:
	var vertices := PackedVector3Array()
	var colors := PackedColorArray()
	var points: Array = data.vertices
	var normals: Array = data.normals
	var light := Vector3(-0.4,0.8,-0.3).normalized()
	for i in range(0,points.size(),9):
		var face: Array[Vector3] = []
		for j in range(3):
			var k := i+j*3
			face.append(Vector3(points[k],points[k+1],points[k+2]))
		var flat := (face[2]-face[0]).cross(face[1]-face[0]).normalized()
		for j in range(3):
			var k := i+j*3
			var normal := Vector3(normals[k],normals[k+1],normals[k+2])
			var shade := 0.73+0.25*maxf(0,normal.dot(light))+0.02*maxf(0,flat.dot(light))
			var opacity := 0.94*smoothstep(-0.25,0.45,normal.y)
			vertices.append(Vector3(face[j].x*600,350+face[j].y*250,face[j].z*600))
			colors.append(Color(0.97*shade,0.985*shade,shade,opacity))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_COLOR] = colors
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	return mesh


static func run(host: Node, mode: Node, owner: Node3D, map_name: String) -> void:
	var tree := host.get_tree()
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://resources/weather_cloud_shapes/compare.json"))
	mode._camera_ctrl.follow_enabled = false
	mode._camera_ctrl.set_process(false)
	mode.camera.position = Vector2.ZERO
	mode.camera.rotation = 0.0
	mode.camera.zoom = Vector2.ONE*0.18
	mode.camera.force_update_scroll()
	await tree.process_frame
	await tree.process_frame
	var gallery := Node3D.new()
	gallery.basis = owner.basis
	owner.get_parent().add_child(gallery)
	owner.set_enabled(false)
	# owner仍活着，保持旧2D天气停画；样板退场由原owner负责清理元数据。
	mode._weather.set_meta(&"weather_volume_owner",weakref(owner))
	mode._weather.queue_redraw()
	var material := ShaderMaterial.new()
	material.shader = preload("res://resources/shaders/weather_shape_preview.gdshader")
	for style in ["a","b","c"]:
		var nodes: Array[MeshInstance3D] = []
		var total := 0
		for i in range(3):
			var node := MeshInstance3D.new()
			node.mesh = build_mesh(data[style][i])
			node.material_override = material
			node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			node.position = [Vector3(-2100,0,-1100),Vector3(1900,0,-800),Vector3(-100,0,1300)][i]
			node.rotation.y = [0.0,0.25,-0.2][i]
			gallery.add_child(node)
			nodes.append(node)
			total += int(data[style][i].triangles)
		for view in ["field","close"]:
			mode.camera.position = Vector2.ZERO if view == "field" else Vector2(-2100,-1100)
			var zoom := 0.18 if view == "field" else 0.32
			mode._camera_ctrl.target_zoom = zoom
			mode._camera_ctrl._base_zoom = zoom
			mode.camera.zoom = Vector2.ONE*zoom
			mode.player_aircraft.global_position = mode.camera.position + Vector2(0,1100)
			mode.player_aircraft.clear_trail()
			mode.camera.force_update_scroll()
			await tree.create_timer(1.0).timeout
			await RenderingServer.frame_post_draw
			var path := "res://bench/results/weather_shapes_%s_%s_%s.png" % [map_name,style,view]
			var error := host.get_viewport().get_texture().get_image().save_png(path)
			if error != OK:
				push_error("Weather shape capture failed: " + path)
				tree.quit(1)
				return
			print("Weather shape ",style," triangles=",total," capture=",path)
		for node in nodes:
			node.queue_free()
		await tree.process_frame
	gallery.queue_free()
	await tree.process_frame
