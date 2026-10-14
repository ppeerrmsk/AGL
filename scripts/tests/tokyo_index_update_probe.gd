extends RefCounted
## 实际渲染器索引更新能力与像素负对照；不证明地图性能。
static func run(parent: Node,input: Dictionary) -> int:
	if DisplayServer.get_name()=="headless" or FileAccess.file_exists(input.output): return 1
	var result := {"version":Engine.get_version_info(),"renderer":RenderingServer.get_current_rendering_method(),
		"index_update_available":RenderingServer.has_method("mesh_surface_update_index_region"),"performance_accepted":false}
	if result.index_update_available:
		var viewport := SubViewport.new();viewport.size=Vector2i(128,64);viewport.own_world_3d=true
		viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS;parent.add_child(viewport)
		var camera := Camera3D.new();viewport.add_child(camera);camera.position.z=4
		camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=4
		var arrays: Array=[];arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX]=PackedVector3Array([Vector3(-1.8,-.7,0),Vector3(-1,.7,0),Vector3(-.2,-.7,0),Vector3(.2,-.7,0),Vector3(1,.7,0),Vector3(1.8,-.7,0)])
		arrays[Mesh.ARRAY_INDEX]=PackedInt32Array([0,1,2])
		var mesh := ArrayMesh.new();mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
		var material := StandardMaterial3D.new();material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
		material.cull_mode=BaseMaterial3D.CULL_DISABLED;material.albedo_color=Color.WHITE
		var node := MeshInstance3D.new();node.mesh=mesh;node.material_override=material;viewport.add_child(node)
		for i in 3: await RenderingServer.frame_post_draw
		var before := viewport.get_texture().get_image();before.convert(Image.FORMAT_RGBA8)
		var stride := RenderingServer.mesh_surface_get_format_index_stride(mesh.surface_get_format(0),6)
		var buffer := PackedByteArray();buffer.resize(3*stride)
		for i in 3:
			if stride==2:buffer.encode_u16(i*2,i+3)
			elif stride==4:buffer.encode_u32(i*4,i+3)
			else:viewport.queue_free();await parent.get_tree().process_frame;return 1
		RenderingServer.call("mesh_surface_update_index_region",mesh.get_rid(),0,0,buffer)
		for i in 3: await RenderingServer.frame_post_draw
		var after := viewport.get_texture().get_image();after.convert(Image.FORMAT_RGBA8)
		node.visible=false
		for i in 3: await RenderingServer.frame_post_draw
		var blank := viewport.get_texture().get_image();blank.convert(Image.FORMAT_RGBA8)
		var changed := 0;var before_left := 0;var before_right := 0;var after_left := 0;var after_right := 0
		for y in 64:
			for x in 128:
				var old_color := before.get_pixel(x,y);var new_color := after.get_pixel(x,y)
				changed+=int(old_color!=new_color)
				if old_color!=blank.get_pixel(x,y):
					if x<64:before_left+=1
					else:before_right+=1
				if new_color!=blank.get_pixel(x,y):
					if x<64:after_left+=1
					else:after_right+=1
		result.merge({"changed_pixels":changed,"before_left":before_left,"before_right":before_right,"after_left":after_left,"after_right":after_right,
			"pixel_update_verified":before_left>0 and before_right==0 and after_left==0 and after_right>0,
			"index_count_after":mesh.surface_get_array_index_len(0),"uploaded_bytes":buffer.size()})
		before.save_png(input.output+".before.png");after.save_png(input.output+".after.png")
		viewport.queue_free();await parent.get_tree().process_frame
	var file := FileAccess.open(input.output,FileAccess.WRITE)
	if file==null:return 1
	file.store_string(JSON.stringify(result,"\t"));file.close()
	return 0 if not result.index_update_available or result.get("pixel_update_verified",false) else 1
