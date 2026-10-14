extends RefCounted
## 独立GL整场解码；使用与正式AO相同函数，不把无头CPU往返冒充GPU验证。
static func run(parent: Node, source: String, packed: String, output: String) -> int:
	if DisplayServer.get_name()=="headless" or source.is_empty() or packed.is_empty() or output.is_empty():
		return 1
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(packed.path_join("manifest.json")))
	if not raw is Dictionary or preload("res://scripts/experiments/tokyo_height_bits.gd").storage_width(raw)!=1280:
		return 1
	var reference := Image.load_from_file(source.path_join("height_indices.png"))
	var picture := Image.load_from_file(packed.path_join("height_indices5.png"))
	if reference==null or picture==null or reference.get_size()!=Vector2i(2048,2048) or picture.get_size()!=Vector2i(1280,2048):
		return 1
	reference.convert(Image.FORMAT_R8)
	picture.convert(Image.FORMAT_R8)
	var texture := ImageTexture.create_from_image(picture)
	var uploaded := texture.get_image()
	if uploaded.get_data()!=picture.get_data() or uploaded.get_format()!=Image.FORMAT_R8:
		return 1
	var viewport := SubViewport.new()
	viewport.size=Vector2i(2048,2048)
	viewport.disable_3d=true
	viewport.world_2d=World2D.new()
	viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	parent.get_tree().root.add_child(viewport)
	var node := ColorRect.new()
	node.size=Vector2(2048,2048)
	var material := ShaderMaterial.new()
	material.shader=Shader.new()
	material.shader.code="shader_type canvas_item;\nrender_mode unshaded;\nuniform sampler2D baked_height:filter_nearest,repeat_disable;\n"+preload("res://scripts/experiments/tokyo_height_bits.gd").SHADER_CODE+"\nvoid fragment(){COLOR=vec4(vec3(agl_height_index(UV)/255.0),1.0);}\n"
	material.set_shader_parameter("baked_height",texture)
	node.material=material
	viewport.add_child(node)
	for frame in 4:
		await RenderingServer.frame_post_draw
	var result := viewport.get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(output)
	assert(result.save_png(output.path_join("decoded_indices.png"))==OK)
	result.convert(Image.FORMAT_R8)
	var expected := reference.get_data()
	var actual := result.get_data()
	var mismatches := 0
	if expected.size()!=actual.size():
		mismatches=expected.size()
	else:
		for index in expected.size():
			mismatches+=int(expected[index]!=actual[index])
	var record := {"fail":int(mismatches!=0),"headless":false,"pixels":expected.size(),"mismatches":mismatches,"packed_bytes":uploaded.get_data().size(),"gpu_format":uploaded.get_format(),"shader_code_sha256":material.shader.code.sha256_text(),"packed_manifest_sha256":FileAccess.get_sha256(packed.path_join("manifest.json"))}
	# 跨纹素边界直接比较旧normalized nearest与新位解码，包含clamp边缘。
	material=ShaderMaterial.new()
	material.shader=Shader.new()
	material.shader.code="shader_type canvas_item;\nrender_mode unshaded;\nuniform sampler2D baked_height:filter_nearest,repeat_disable;\nuniform sampler2D old_height:filter_nearest,repeat_disable;\nuniform vec2 sample_offset;\n"+preload("res://scripts/experiments/tokyo_height_bits.gd").SHADER_CODE+"\nvoid fragment(){vec2 uv=UV+sample_offset/2048.0; float a=agl_height_index(uv); float b=floor(texture(old_height,uv).r*255.0+0.5); COLOR=vec4(vec3(float(a!=b)),1.0);}\n"
	material.set_shader_parameter("baked_height",texture)
	var reference_texture := ImageTexture.create_from_image(reference)
	material.set_shader_parameter("old_height",reference_texture)
	node.material=material
	assert(reference_texture.get_image().get_data()==expected)
	var boundary_rows: Array = []
	for offset: Vector2 in [Vector2(.49,.49),Vector2(.51,.51),Vector2(-.5,.5)]:
		material.set_shader_parameter("sample_offset",offset)
		for frame in 4:
			await RenderingServer.frame_post_draw
		var difference := viewport.get_texture().get_image()
		assert(difference.save_png(output.path_join("boundary_%d.png"%boundary_rows.size()))==OK)
		difference.convert(Image.FORMAT_R8)
		var count := 0
		for value: int in difference.get_data():
			count += int(value!=0)
		boundary_rows.append({"offset":str(offset),"mismatches":count})
		mismatches+=count
	record["boundary_rows"]=boundary_rows
	record.fail=int(mismatches!=0)
	viewport.queue_free()
	await parent.get_tree().process_frame
	await parent.get_tree().process_frame
	var file := FileAccess.open(output.path_join("decode.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(record,"\t"))
	file.close()
	print("[R105 GPU height] ",record)
	return int(mismatches!=0)
