extends RefCounted
## 相同保存mip的旧/新编码逐像素GL对拍；覆盖块边缘与非整数LOD。
static func run(parent: Node, input: Dictionary) -> int:
	if DisplayServer.get_name()=="headless" or FileAccess.file_exists(input.output):return 1
	var sparse := preload("res://scripts/tests/tokyo_sparse_mip_sampler.gd")
	var materials: Array[ShaderMaterial]=[]
	for binding: Dictionary in [input.reference,input.candidate]:
		var batch: Dictionary=sparse.build(binding)
		if batch.is_empty():return 1
		var material: ShaderMaterial=batch.material
		var pages: Array=[]
		for i in 4:pages.append(material.get_shader_parameter("page%d"%i))
		material.shader.code="shader_type canvas_item;\nrender_mode unshaded, blend_disabled;\nuniform float probe_tile=0.0;\nuniform bool alpha_view=false;\n"+sparse.sampler_code(batch.shared_palette)+"\nvoid fragment(){vec4 c=read_tile(UV,probe_tile);COLOR=vec4(alpha_view?vec3(c.a):c.rgb,1.0);}\n"
		for i in 4:material.set_shader_parameter("page%d"%i,pages[i])
		materials.append(material)
	var viewport := SubViewport.new();viewport.size=Vector2i(193,191)
	viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS;parent.add_child(viewport)
	var rect := ColorRect.new();rect.size=Vector2(viewport.size);viewport.add_child(rect)
	var cases := 0;var failed: Array=[]
	for tile in 4:
		for lod: float in [0.0,0.5,1.0,1.5,2.0,4.25,12.0]:
			for alpha: bool in [false,true]:
				var reference := PackedByteArray()
				for index in 2:
					rect.material=materials[index]
					materials[index].set_shader_parameter("probe_tile",float(tile))
					materials[index].set_shader_parameter("diagnostic_lod",lod)
					materials[index].set_shader_parameter("alpha_view",alpha)
					await RenderingServer.frame_post_draw
					var pixels := viewport.get_texture().get_image().get_data()
					if index==0:reference=pixels
					elif reference!=pixels:failed.append({"tile":tile,"lod":lod,"alpha":alpha})
				cases+=1
	viewport.queue_free();rect=null;viewport=null;materials.clear()
	for frame in 4:await parent.get_tree().process_frame
	var result := {"cases":cases,"failures":failed,"exact":failed.is_empty(),"performance_verified":false,"full_map_verified":false}
	var file := FileAccess.open(input.output,FileAccess.WRITE)
	if file==null:return 1
	file.store_string(JSON.stringify(result,"\t"));file.close()
	print("Tokyo bitpacked mip comparison: ",JSON.stringify(result))
	return 0 if failed.is_empty() else 1
