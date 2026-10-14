extends RefCounted
## 候选分层采样器：一原始行一物理层，逻辑纹理身份保持不变。
const Sparse := preload("res://scripts/tests/tokyo_sparse_mip_sampler.gd")
const Hash := preload("res://scripts/tests/tokyo_nine_domain_preview.gd")

static func sampler_code() -> String:
	return Sparse.sampler_code(true).replace("sampler2D page","sampler2DArray page").replace("ivec2 address(int word){return ivec2(word%4096,word/4096);}","ivec3 address(int word){return ivec3(word%4096,0,word/4096);}").replace("textureSize(page3,0);","textureSize(page3,0).xz;").replace("textureSize(page2,0);","textureSize(page2,0).xz;")

static func build(binding: Dictionary) -> Dictionary:
	if FileAccess.get_sha256(binding.path)!=binding.sha256:return {}
	var manifest: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(binding.path))
	var material := ShaderMaterial.new();material.shader=Shader.new()
	material.shader.code="shader_type canvas_item;\n"+sampler_code()+"\nvoid fragment(){COLOR=read_tile(UV,0.0);}\n"
	var total := 0
	var names := ["payload","blocks","mips","tiles"]
	for i in 4:
		var row: Dictionary=manifest.files[names[i]]
		if FileAccess.get_sha256(row.path)!=row.sha256:return {}
		var file := FileAccess.open(row.path,FileAccess.READ)
		if file==null:return {}
		var format_value := Image.FORMAT_RGBA8 if i==0 else (Image.FORMAT_RGF if i==3 else Image.FORMAT_RGBAF)
		var stride := 4 if i==0 else (8 if i==3 else 16)
		var images: Array[Image]=[]
		for layer in int(row.target_height):
			var bytes := file.get_buffer(4096*stride);bytes.resize(4096*stride)
			images.append(Image.create_from_data(4096,1,false,format_value,bytes))
		file.close()
		var texture := Texture2DArray.new()
		if texture.create_from_images(images)!=OK:return {}
		images.clear();total+=int(row.target_height)*4096*stride*3
		material.set_shader_parameter("page%d"%i,texture)
	return {"material":material,"shared_palette":true,"texture_three_copy_bytes":total}

static func apply_updates(parent: Node, materials: Array[ShaderMaterial], viewport: SubViewport, binding: Dictionary, move_camera: Callable=Callable()) -> Dictionary:
	if FileAccess.get_sha256(binding.path)!=binding.sha256:return {"passed":false}
	var report: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(binding.path))
	await RenderingServer.frame_post_draw
	var baseline := Hash.digest(viewport.get_texture().get_image().get_data())
	var frames := 0;var changed := 0;var largest := 0
	var started := Time.get_ticks_usec()
	for row: Dictionary in report.rows:
		if FileAccess.get_sha256(row.patch_path)!=row.patch_sha256 or FileAccess.get_sha256(row.directory_path)!=row.directory_sha256:return {"passed":false}
		var patch := FileAccess.open(row.patch_path,FileAccess.READ)
		var directory := FileAccess.open(row.directory_path,FileAccess.READ)
		if patch==null or directory==null:return {"passed":false}
		var index := ["payload","blocks","mips","tiles"].find(row.name)
		var texture: Texture2DArray=materials[int(row.bank)].get_shader_parameter("page%d"%index)
		var format_value := Image.FORMAT_RGBA8 if index==0 else (Image.FORMAT_RGF if index==3 else Image.FORMAT_RGBAF)
		for entry in int(row.changed_rows):
			if move_camera.is_valid():
				move_camera.call(Vector2(1408.0-64.0*float(frames)/573.0,-15232),0.5)
				await RenderingServer.frame_post_draw
				baseline=Hash.digest(viewport.get_texture().get_image().get_data())
			var layer := directory.get_32();var offset := directory.get_32();var count := directory.get_32()
			if layer>=texture.get_layers() or count!=int(row.max_row_bytes):return {"passed":false}
			patch.seek(offset);var bytes := patch.get_buffer(count)
			if bytes.size()!=count:return {"passed":false}
			var image := Image.create_from_data(4096,1,false,format_value,bytes)
			texture.update_layer(image,layer);image=null;bytes=PackedByteArray();largest=maxi(largest,count)
			await RenderingServer.frame_post_draw
			frames+=1
			if Hash.digest(viewport.get_texture().get_image().get_data())!=baseline:changed+=1
		patch.close();directory.close()
	return {"passed":changed==0 and frames==574,"updated_layers":frames,"changed_current_frames":changed,"max_input_bytes":largest,"camera_static":not move_camera.is_valid(),"request_to_ready_us":Time.get_ticks_usec()-started,"pace_tied_to_updates":move_camera.is_valid(),"moving_coverage_verified":false,"performance_verified":false}
