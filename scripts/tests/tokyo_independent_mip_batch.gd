extends RefCounted
## 测试用独立mip图集；不自动接入正式地图。
const Surface := preload("res://scripts/rendering/tokyo_hlod_surface.gd")
const AtlasPlane := preload("res://scripts/rendering/tokyo_fixed_atlas_layer.gd")

static func build(binding: Dictionary, textures: Dictionary) -> Dictionary:
	if FileAccess.get_sha256(binding.path)!=binding.sha256:return {}
	var atlas: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(binding.path))
	if atlas.has("block_count"):
		return preload("res://scripts/tests/tokyo_sparse_mip_sampler.gd").build_map(binding,textures)
	if atlas.pages.size()!=4 or atlas.atlas_hardware_mipmaps:return {}
	var palette_mode := atlas.has("colors") and atlas.has("offsets")
	var code := Surface.textured_code().replace("sample_color.a<0.001","sample_color.a<0.5")
	var extra := """
uniform sampler2D page0 : filter_linear, repeat_disable;
uniform sampler2D page1 : filter_linear, repeat_disable;
uniform sampler2D page2 : filter_linear, repeat_disable;
uniform sampler2D page3 : filter_linear, repeat_disable;
uniform sampler2D mip_table : filter_nearest, repeat_disable;
uniform float diagnostic_lod = -1.0;
vec4 read_level(int tile, int level, vec2 source_uv) {
 vec4 rect=texelFetch(mip_table,ivec2(level*2,tile),0);
 int page=int(texelFetch(mip_table,ivec2(level*2+1,tile),0).x);
 vec2 pixel=rect.xy+clamp(source_uv*rect.zw,vec2(0.5),rect.zw-vec2(0.5));
 if(page==0){return textureLod(page0,pixel/vec2(textureSize(page0,0)),0.0);}
 if(page==1){return textureLod(page1,pixel/vec2(textureSize(page1,0)),0.0);}
 if(page==2){return textureLod(page2,pixel/vec2(textureSize(page2,0)),0.0);}
 return textureLod(page3,pixel/vec2(textureSize(page3,0)),0.0);
}
vec4 read_tile(vec2 source_uv, float tile_number) {
 int tile=int(tile_number+0.5);
 vec4 info=texelFetch(mip_table,ivec2(1,tile),0);
 vec2 dx=dFdx(source_uv)*info.zw;vec2 dy=dFdy(source_uv)*info.zw;
 float lod=clamp(0.5*log2(max(max(dot(dx,dx),dot(dy,dy)),0.000001)),0.0,info.y-1.0);
 if(diagnostic_lod>=0.0){lod=clamp(diagnostic_lod,0.0,info.y-1.0);}
 int lower=int(floor(lod));int upper=min(lower+1,int(info.y)-1);
 return mix(read_level(tile,lower,source_uv),read_level(tile,upper,source_uv),fract(lod));
}
"""
	if palette_mode:
		var begin := extra.find("vec4 read_level(")
		var end := extra.find("vec4 read_tile(")
		extra = extra.substr(0,begin).replace("filter_linear", "filter_nearest") + """
uniform sampler2D palette_colors : filter_nearest, repeat_disable;
uniform sampler2D palette_offsets : filter_nearest, repeat_disable;
uniform vec4 page_channels = vec4(2.0);
vec4 palette_pixel(int page, ivec2 pos, int offset) {
 vec2 pair;
 if(page==0){pair=texelFetch(page0,pos,0).rg;}
 else if(page==1){pair=texelFetch(page1,pos,0).rg;}
 else if(page==2){pair=texelFetch(page2,pos,0).rg;}
 else{pair=texelFetch(page3,pos,0).rg;}
 if(page_channels[page]<1.5){pair.y=0.0;}
 ivec2 bytes=ivec2(round(pair*255.0));
 int index=offset+bytes.x+256*bytes.y;
 int width=textureSize(palette_colors,0).x;
 return texelFetch(palette_colors,ivec2(index%width,index/width),0);
}
vec4 read_level(int tile, int level, vec2 source_uv) {
 vec4 rect=texelFetch(mip_table,ivec2(level*2,tile),0);
 int page=int(texelFetch(mip_table,ivec2(level*2+1,tile),0).x);
 int offset=int(texelFetch(palette_offsets,ivec2(tile,0),0).r+0.5);
 vec2 sample_pos=clamp(source_uv*rect.zw-vec2(0.5),vec2(0.0),rect.zw-vec2(1.0));
 ivec2 p0=ivec2(floor(sample_pos));
 ivec2 p1=min(p0+ivec2(1),ivec2(rect.zw)-ivec2(1));
 ivec2 origin=ivec2(rect.xy);
 vec2 f=fract(sample_pos);
 vec4 a=palette_pixel(page,origin+p0,offset);
 vec4 b=palette_pixel(page,origin+ivec2(p1.x,p0.y),offset);
 vec4 c=palette_pixel(page,origin+ivec2(p0.x,p1.y),offset);
 vec4 d=palette_pixel(page,origin+p1,offset);
 return mix(mix(a,b,f.x),mix(c,d,f.x),f.y);
}
""" + extra.substr(end)
	code=code.replace("void fragment() {",extra+"\nvoid fragment() {").replace("texture(overview,UV)","read_tile(UV,UV2.x)")
	if binding.get("alpha_diagnostic",false):
		code=code.replace("if(sample_color.a<0.5){discard;}","").replace("vec3 base=sample_color.rgb/max(sample_color.a,0.001);","vec3 base=vec3(sample_color.a);")
	var material := ShaderMaterial.new();material.shader=Shader.new();material.shader.code=code
	material.set_shader_parameter("diagnostic_lod",float(binding.get("diagnostic_lod",-1)))
	var texture_bytes := 0
	var page_channels := Vector4(2,2,2,2)
	for i in 4:
		var row: Dictionary=atlas.pages[i]
		if FileAccess.get_sha256(row.path)!=row.sha256:return {}
		var image: Image
		if palette_mode:
			var page_format: String=row.get("format","RG8")
			if page_format not in ["R8","RG8"]:return {}
			page_channels[i]=1.0 if page_format=="R8" else 2.0
			var image_format := Image.FORMAT_R8 if page_format=="R8" else Image.FORMAT_RG8
			image = Image.create_from_data(int(row.width),int(row.height),false,image_format,FileAccess.get_file_as_bytes(row.path))
		else:
			image = Image.load_from_file(row.path)
		if image==null or image.has_mipmaps():return {}
		texture_bytes+=image.get_data_size()*3;material.set_shader_parameter("page%d"%i,ImageTexture.create_from_image(image))
	if palette_mode:material.set_shader_parameter("page_channels",page_channels)
	var meta: Dictionary=atlas.metadata
	if FileAccess.get_sha256(meta.path)!=meta.sha256:return {}
	var table := Image.create_from_data(int(meta.width),int(meta.height),false,Image.FORMAT_RGBAF,FileAccess.get_file_as_bytes(meta.path))
	texture_bytes+=table.get_data_size()*3;material.set_shader_parameter("mip_table",ImageTexture.create_from_image(table))
	if palette_mode:
		for field: String in ["colors","offsets"]:
			var row: Dictionary=atlas[field]
			if FileAccess.get_sha256(row.path)!=row.sha256:return {}
			var format_value := Image.FORMAT_RGBA8 if field=="colors" else Image.FORMAT_RF
			var image := Image.create_from_data(int(row.width),int(row.height),false,format_value,FileAccess.get_file_as_bytes(row.path))
			if image==null or image.get_data_size()*3!=int(row.three_copy_bytes):return {}
			texture_bytes+=image.get_data_size()*3
			material.set_shader_parameter("palette_"+field,ImageTexture.create_from_image(image))
	if texture_bytes!=int(atlas.three_copy_bytes):return {}
	var positions := PackedVector3Array();var normals := PackedVector3Array();var uv := PackedVector2Array();var ids := PackedVector2Array();var indices := PackedInt32Array()
	for i in textures.rows.size():
		var row: Dictionary=textures.rows[i];var g: Array=row.geometry_bounds;var t: Array=row.texture_bounds
		var rect := Rect2(g[0],g[1],g[2]-g[0],g[3]-g[1]);var bounds := Rect2(t[0],t[1],t[2]-t[0],t[3]-t[1])
		var mesh := AtlasPlane.plane(rect,Rect2((rect.position-bounds.position)/bounds.size,rect.size/bounds.size))
		var arrays := mesh.surface_get_arrays(0);var offset := positions.size()
		var texture_index := int(row.get("texture_index",i))
		if texture_index<0 or texture_index>=int(meta.height):return {}
		for p: Vector3 in arrays[Mesh.ARRAY_VERTEX]:positions.append(p+Vector3(0,row.height,0));ids.append(Vector2(texture_index,0))
		normals.append_array(arrays[Mesh.ARRAY_NORMAL]);uv.append_array(arrays[Mesh.ARRAY_TEX_UV])
		for index: int in arrays[Mesh.ARRAY_INDEX]:indices.append(index+offset)
	var arrays: Array=[];arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=positions;arrays[Mesh.ARRAY_NORMAL]=normals;arrays[Mesh.ARRAY_TEX_UV]=uv;arrays[Mesh.ARRAY_TEX_UV2]=ids;arrays[Mesh.ARRAY_INDEX]=indices
	var mesh := ArrayMesh.new();mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	return {"mesh":mesh,"material":material,"texture_three_copy_bytes":texture_bytes}
