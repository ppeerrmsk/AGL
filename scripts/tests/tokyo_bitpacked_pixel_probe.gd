extends RefCounted
## 位编码隔离GL像素门。对象释放证据不等同驱动暂存峰值。
static func run(parent: Node, input: Dictionary) -> int:
	if DisplayServer.get_name()=="headless" or FileAccess.file_exists(input.output):return 1
	for binding: Dictionary in [input.payload,input.shader,input.cases]:
		if FileAccess.get_sha256(binding.path)!=binding.sha256:return 1
	var cases: Array=JSON.parse_string(FileAccess.get_file_as_string(input.cases.path))
	var material := ShaderMaterial.new();var shader := Shader.new()
	shader.code=FileAccess.get_file_as_string(input.shader.path);material.shader=shader
	var bytes := FileAccess.get_file_as_bytes(input.payload.path)
	var image := Image.create_from_data(4096,bytes.size()/16384,false,Image.FORMAT_RGBA8,bytes)
	var texture := ImageTexture.create_from_image(image)
	var image_probe: WeakRef=weakref(image);var texture_probe: WeakRef=weakref(texture)
	material.set_shader_parameter("payload",texture)
	bytes=PackedByteArray();image=null
	RenderingServer.force_sync()
	var cpu_image_released := image_probe.get_ref()==null
	var viewport := SubViewport.new();viewport.transparent_bg=true
	viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS;parent.add_child(viewport)
	var rect := ColorRect.new();rect.material=material;viewport.add_child(rect)
	var failures: Array=[];var tested := 0
	for row: Dictionary in cases:
		var d: Array=row.descriptor
		# SubViewport每轴至少2；一像素尾mip重复采样后只回读真实尺寸。
		viewport.size=Vector2i(maxi(2,int(d[3])),maxi(2,int(d[4])));rect.size=Vector2(viewport.size)
		material.set_shader_parameter("descriptor",Vector4i(int(d[0]),int(d[1]),int(d[2]),int(d[3])))
		material.set_shader_parameter("block_height",int(d[4]))
		await RenderingServer.frame_post_draw
		var actual := viewport.get_texture().get_image().get_region(Rect2i(0,0,int(d[3]),int(d[4])));actual.convert(Image.FORMAT_RGBA8)
		var hash := HashingContext.new();hash.start(HashingContext.HASH_SHA256);hash.update(actual.get_data())
		if hash.finish().hex_encode()!=row.sha256:
			failures.append({"case":tested,"mode":d[0]})
			break
		tested+=1
	viewport.queue_free();rect=null;viewport=null;material=null;shader=null;texture=null
	for frame in 4:await parent.get_tree().process_frame
	RenderingServer.force_sync()
	var texture_released := texture_probe.get_ref()==null
	var result := {"cases_tested":tested,"case_count":cases.size(),"failures":failures,
		"cpu_image_released_before_sampling":cpu_image_released,"texture_released":texture_released,
		"saved_gl_pixels_exact":failures.is_empty() and tested==cases.size(),
		"gpu_transient_release_measured":false,"performance_verified":false,"runtime_integrated":false}
	var file := FileAccess.open(input.output,FileAccess.WRITE)
	if file==null:return 1
	file.store_string(JSON.stringify(result,"\t"));file.close()
	print("Tokyo bitpacked pixel probe: ",JSON.stringify(result))
	return 0 if result.saved_gl_pixels_exact and cpu_image_released and texture_released else 1
