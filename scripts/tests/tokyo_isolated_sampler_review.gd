extends RefCounted
## 单纹理采样隔离：无深度重叠、无光照、无alpha discard。
const Batch := preload("res://scripts/tests/tokyo_independent_mip_batch.gd")
const Difference := preload("res://scripts/tests/tokyo_layered_roof_review.gd")

static func run(parent: Node,input: Dictionary) -> int:
	if DisplayServer.get_name()=="headless":return 1
	if FileAccess.get_sha256(input.textures.path)!=input.textures.sha256:return 1
	var textures: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(input.textures.path))
	var sparse := bool(input.get("sparse_mips",false))
	var batch := preload("res://scripts/tests/tokyo_sparse_mip_sampler.gd").build(input.atlas) if sparse else Batch.build(input.atlas,textures)
	if batch.is_empty():return 1
	var material: ShaderMaterial=batch.material
	var original_code: String=material.shader.code
	var start := original_code.find("uniform sampler2D page0")
	var end := original_code.find("\nvoid fragment()",start)
	if start<0 or end<start:return 1
	material.shader=Shader.new()
	material.shader.code="""shader_type canvas_item;
render_mode unshaded, blend_disabled;
uniform sampler2D overview : filter_linear_mipmap, repeat_disable;
uniform bool use_atlas = false;
uniform bool alpha_view = false;
uniform float probe_tile_id = 0.0;
"""+original_code.substr(start,end-start)+"""
void fragment(){
 vec4 sample_color;
 if(use_atlas){sample_color=read_tile(UV,probe_tile_id);}
 else{sample_color=textureLod(overview,UV,diagnostic_lod);}
 COLOR=vec4(alpha_view ? vec3(sample_color.a) : sample_color.rgb,1.0);
}
"""
	# 更换shader后参数显式重绑，避免测试依赖引擎参数缓存行为。
	var rebound := preload("res://scripts/tests/tokyo_sparse_mip_sampler.gd").build(input.atlas) if sparse else Batch.build(input.atlas,textures)
	var donor: ShaderMaterial=rebound.material
	for name: String in ["page0","page1","page2","page3"]:material.set_shader_parameter(name,donor.get_shader_parameter(name))
	if not sparse:material.set_shader_parameter("mip_table",donor.get_shader_parameter("mip_table"))
	if original_code.contains("uniform sampler2D palette_colors"):
		for name: String in ["palette_colors","palette_offsets","page_channels"]:
			material.set_shader_parameter(name,donor.get_shader_parameter(name))
	var output: String=input.output
	if DirAccess.dir_exists_absolute(output) or DirAccess.make_dir_recursive_absolute(output)!=OK:return 1
	var viewport := SubViewport.new();viewport.size=Vector2i(192,192);viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	parent.add_child(viewport)
	var rect := ColorRect.new();rect.size=Vector2(192,192);rect.material=material;viewport.add_child(rect)
	var results: Array=[]
	for tile_value: Variant in input.get("probe_tiles",[249,499]):
		var tile_id := int(tile_value)
		if tile_id<0 or tile_id>=textures.rows.size():return 1
		var row: Dictionary=textures.rows[tile_id]
		if FileAccess.get_sha256(row.path)!=row.sha256:return 1
		var image := Image.load_from_file(row.path)
		if image==null or image.generate_mipmaps()!=OK:return 1
		material.set_shader_parameter("overview",ImageTexture.create_from_image(image));material.set_shader_parameter("probe_tile_id",float(tile_id))
		for lod: float in input.get("probe_lods",[0.0,0.5,1.0,1.5,2.0]):
			material.set_shader_parameter("diagnostic_lod",lod)
			for alpha_view: bool in [false,true]:
				material.set_shader_parameter("alpha_view",alpha_view)
				var pictures: Array[Image]=[]
				for atlas: bool in [false,true]:
					material.set_shader_parameter("use_atlas",atlas)
					for frame in 3:await RenderingServer.frame_post_draw
					var picture := viewport.get_texture().get_image();pictures.append(picture)
					if picture.save_png(output.path_join("%d_%.1f_%s_%s.png"%[tile_id,lod,str(alpha_view),str(atlas)]))!=OK:return 1
				var varied := false;var first := pictures[0].get_pixel(0,0)
				for y in 192:
					for x in 192:
						if pictures[0].get_pixel(x,y)!=first:varied=true;break
					if varied:break
				if not varied:return 1
				results.append({"tile":tile_id,"lod":lod,"alpha":alpha_view,"reference_nonuniform":varied,"difference":Difference.difference(pictures[0],pictures[1])})
	viewport.queue_free();await parent.get_tree().process_frame
	var file := FileAccess.open(output.path_join("report.json"),FileAccess.WRITE)
	if file==null:return 1
	file.store_string(JSON.stringify({"results":results,"full_map_accepted":false,"performance_accepted":false},"\t"));file.close()
	return 0
