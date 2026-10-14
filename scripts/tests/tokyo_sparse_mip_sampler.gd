extends RefCounted
## 显式测试采样器：保留原mip像素，先解码再双线性/三线性过滤。

static func build_map(binding: Dictionary, textures: Dictionary) -> Dictionary:
	var result := build(binding)
	if result.is_empty():return {}
	var manifest: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(binding.path))
	var material: ShaderMaterial=result.material
	var bound: Array=[]
	for i in 4:bound.append(material.get_shader_parameter("page%d"%i))
	var code := preload("res://scripts/rendering/tokyo_hlod_surface.gd").textured_code().replace("sample_color.a<0.001","sample_color.a<0.5")
	code=code.replace("void fragment() {",sampler_code(result.shared_palette)+"\nvoid fragment() {").replace("texture(overview,UV)","read_tile(UV,UV2.x)")
	material.shader.code=code
	for i in 4:material.set_shader_parameter("page%d"%i,bound[i])
	var positions := PackedVector3Array();var normals := PackedVector3Array();var uv := PackedVector2Array();var ids := PackedVector2Array();var indices := PackedInt32Array()
	for row: Dictionary in textures.rows:
		var tile := int(row.texture_index)
		if tile<0 or tile>=int(manifest.tile_count):return {}
		var g: Array=row.geometry_bounds;var t: Array=row.texture_bounds
		var rect := Rect2(g[0],g[1],g[2]-g[0],g[3]-g[1]);var bounds := Rect2(t[0],t[1],t[2]-t[0],t[3]-t[1])
		var mesh := preload("res://scripts/rendering/tokyo_fixed_atlas_layer.gd").plane(rect,Rect2((rect.position-bounds.position)/bounds.size,rect.size/bounds.size))
		var a := mesh.surface_get_arrays(0);var offset := positions.size()
		for p: Vector3 in a[Mesh.ARRAY_VERTEX]:positions.append(p+Vector3(0,row.height,0));ids.append(Vector2(tile,0))
		normals.append_array(a[Mesh.ARRAY_NORMAL]);uv.append_array(a[Mesh.ARRAY_TEX_UV])
		for index: int in a[Mesh.ARRAY_INDEX]:indices.append(index+offset)
	var arrays: Array=[];arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=positions;arrays[Mesh.ARRAY_NORMAL]=normals;arrays[Mesh.ARRAY_TEX_UV]=uv;arrays[Mesh.ARRAY_TEX_UV2]=ids;arrays[Mesh.ARRAY_INDEX]=indices
	var mesh := ArrayMesh.new();mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	result["mesh"]=mesh
	return result

static func build(binding: Dictionary) -> Dictionary:
	if FileAccess.get_sha256(binding.path)!=binding.sha256:return {}
	var manifest: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(binding.path))
	if int(manifest.block_size)!=32 or not manifest.all_saved_mip_pixels_exact:return {}
	var shared_palette: bool=manifest.get("format","")=="shared_palette_inline_modes_plus_16_v1"
	var material := ShaderMaterial.new();material.shader=Shader.new()
	material.shader.code="shader_type canvas_item;\n"+sampler_code(shared_palette)+"\nvoid fragment(){COLOR=read_tile(UV,0.0);}\n"
	var total := 0
	var names := ["payload","blocks","mips","tiles"]
	for i in 4:
		var row: Dictionary=manifest.files[names[i]]
		if FileAccess.get_sha256(row.path)!=row.sha256:return {}
		var format_value := Image.FORMAT_RGBA8 if i==0 else (Image.FORMAT_RGF if i==3 else Image.FORMAT_RGBAF)
		var image := Image.create_from_data(int(row.width),int(row.height),false,format_value,FileAccess.get_file_as_bytes(row.path))
		if image==null or image.get_data_size()!=int(row.bytes):return {}
		total+=image.get_data_size()*3
		material.set_shader_parameter("page%d"%i,ImageTexture.create_from_image(image))
	if total!=int(manifest.three_copy_bytes):return {}
	return {"material":material,"texture_three_copy_bytes":total,"shared_palette":shared_palette}


static func sampler_code(shared_palette: bool=false) -> String:
	return "const bool shared_palette_enabled="+("true" if shared_palette else "false")+";\n"+"""
uniform sampler2D page0 : filter_nearest, repeat_disable;
uniform sampler2D page1 : filter_nearest, repeat_disable;
uniform sampler2D page2 : filter_nearest, repeat_disable;
uniform sampler2D page3 : filter_nearest, repeat_disable;
uniform float diagnostic_lod = -1.0;
ivec2 address(int word){return ivec2(word%4096,word/4096);}
int sparse_byte(int offset){
 ivec4 v=ivec4(round(texelFetch(page0,address(offset/4),0)*255.0));
 return v[offset%4];
}
int sparse_u16(int offset){return sparse_byte(offset)+256*sparse_byte(offset+1);}
vec4 sparse_rgba(int offset){return vec4(float(sparse_byte(offset)),float(sparse_byte(offset+1)),float(sparse_byte(offset+2)),float(sparse_byte(offset+3)))/255.0;}
vec4 sparse_pixel(vec4 mip, ivec2 pixel){
 ivec2 block=pixel/32;
 int entry=int(mip.z)+block.y*int(mip.w)+block.x;
 ivec4 desc=ivec4(round(texelFetch(page1,address(entry),0)));
 ivec2 local=pixel-block*32;
 int index=local.y*desc.w+local.x;
 if(desc.x<0){return vec4(1.0,0.0,1.0,1.0);}
 if(desc.x>=16){
  if(!shared_palette_enabled){return vec4(1.0,0.0,1.0,1.0);}
  int mode=desc.x-16;int base=desc.y*4;
  if(mode!=1 && mode!=2 && mode!=5 && mode!=6 && mode!=8 && mode!=10){return vec4(1.0,0.0,1.0,1.0);}
  int pointer=base;int records=base+4;int color=-1;
  if(mode==10){
   int height=min(32,int(mip.y)-block.y*32);pointer=base+2*(height+1);records=pointer+4;
   int low=sparse_u16(base+local.y*2);int high=sparse_u16(base+(local.y+1)*2);int end=high;
   for(int step=0;step<6;step++){
    if(low<high){int middle=(low+high)/2;if(sparse_byte(records+middle*2)>local.x){high=middle;}else{low=middle+1;}}
   }
   if(low<end){color=sparse_byte(records+low*2+1);}
  }else if(mode==1){color=sparse_byte(records+index);}
  else if(mode==2){color=sparse_u16(records+index*2);}
  else{int bits=mode-4;int bit_index=index*bits;color=(sparse_byte(records+bit_index/8)>>(bit_index%8))&((1<<bits)-1);}
  int palette=sparse_u16(pointer)+65536*sparse_u16(pointer+2);
  return color>=0 && color<desc.z?texelFetch(page0,address(palette+color),0):vec4(1.0,0.0,1.0,1.0);
 }
 if(desc.x==9 || desc.x==10){
  int height=min(32,int(mip.y)-block.y*32);
  int base=desc.y*4;
  int low=sparse_u16(base+local.y*2);
  int high=sparse_u16(base+(local.y+1)*2);
  int end=high;
  int palette=base+2*(height+1);
  int stride=desc.x==9?5:2;
  int records=palette+(desc.x==10?desc.z*4:0);
  for(int step=0;step<6;step++){
   if(low<high){int middle=(low+high)/2;if(sparse_byte(records+middle*stride)>local.x){high=middle;}else{low=middle+1;}}
  }
  if(low>=end){return vec4(1.0,0.0,1.0,1.0);}
  if(desc.x==9){return sparse_rgba(records+low*5+1);}
  int color=sparse_byte(records+low*2+1);
  return color<desc.z?sparse_rgba(palette+color*4):vec4(1.0,0.0,1.0,1.0);
 }
 if(desc.x==0){return texelFetch(page0,address(desc.y),0);}
 if(desc.x==3){return texelFetch(page0,address(desc.y+index),0);}
 if(desc.x==5 || desc.x==6 || desc.x==8){
  int bits=desc.x-4;
  int bit_index=index*bits;
  int byte_offset=bit_index/8;
  ivec4 packed=ivec4(round(texelFetch(page0,address(desc.y+desc.z+byte_offset/4),0)*255.0));
  int color=(packed[byte_offset%4]>>(bit_index%8))&((1<<bits)-1);
  return texelFetch(page0,address(desc.y+color),0);
 }
 int stride=desc.x;
 int byte_index=index*stride;
 ivec4 bytes=ivec4(round(texelFetch(page0,address(desc.y+desc.z+byte_index/4),0)*255.0));
 int channel=byte_index%4;
 int color=bytes[channel];
 if(stride==2){color+=256*bytes[channel+1];}
 return texelFetch(page0,address(desc.y+color),0);
}
vec4 read_level(int first,int level,vec2 uv){
 vec4 mip=texelFetch(page2,address(first+level),0);
 vec2 position=clamp(uv*mip.xy-vec2(0.5),vec2(0.0),mip.xy-vec2(1.0));
 ivec2 p0=ivec2(floor(position));ivec2 p1=min(p0+ivec2(1),ivec2(mip.xy)-ivec2(1));
 vec2 f=fract(position);
 return mix(mix(sparse_pixel(mip,p0),sparse_pixel(mip,ivec2(p1.x,p0.y)),f.x),
            mix(sparse_pixel(mip,ivec2(p0.x,p1.y)),sparse_pixel(mip,p1),f.x),f.y);
}
vec4 read_tile(vec2 uv,float tile_number){
 int tile_index=int(tile_number+0.5);
 ivec2 tile_extent=textureSize(page3,0);
 if(tile_number<0.0 || tile_index>=tile_extent.x*tile_extent.y){return vec4(1.0,0.0,1.0,1.0);}
 vec2 tile=texelFetch(page3,address(tile_index),0).rg;
 ivec2 mip_extent=textureSize(page2,0);
 if(tile.x<0.0 || tile.y<1.0 || tile.x+tile.y>float(mip_extent.x*mip_extent.y)){return vec4(1.0,0.0,1.0,1.0);}
 vec2 size=texelFetch(page2,address(int(tile.x)),0).xy;
 vec2 dx=dFdx(uv)*size;vec2 dy=dFdy(uv)*size;
 float lod=clamp(0.5*log2(max(max(dot(dx,dx),dot(dy,dy)),0.000001)),0.0,tile.y-1.0);
 if(diagnostic_lod>=0.0){lod=clamp(diagnostic_lod,0.0,tile.y-1.0);}
 int lower=int(floor(lod));int upper=min(lower+1,int(tile.y)-1);
 return mix(read_level(int(tile.x),lower,uv),read_level(int(tile.x),upper,uv),fract(lod));
}
"""
