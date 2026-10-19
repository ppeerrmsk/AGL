extends RefCounted
## 有限样件：八字节代理顶点 + 街区参数表；逐顶点寻址开销不能当免费。
const Surface := preload("res://scripts/rendering/tokyo_hlod_surface.gd")

static func build(input: Dictionary, bounds: AABB) -> Dictionary:
	for key: String in ["local_vertices","group_table"]:
		if FileAccess.get_sha256(input[key].path)!=input[key].sha256:return {}
	var raw := FileAccess.get_file_as_bytes(input.local_vertices.path).to_float32_array()
	var points := PackedVector2Array()
	for i in range(0,raw.size(),2):points.append(Vector2(raw[i],raw[i+1]))
	var arrays: Array=[];arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=points
	var index_binding: Dictionary=input.get("encoded_indices",input.indices)
	if FileAccess.get_sha256(index_binding.path)!=index_binding.sha256:return {}
	arrays[Mesh.ARRAY_INDEX]=FileAccess.get_file_as_bytes(index_binding.path).to_int32_array()
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays,[],{},Mesh.ARRAY_FLAG_USE_2D_VERTICES)
	mesh.custom_aabb=bounds
	var data := FileAccess.get_file_as_bytes(input.group_table.path)
	if data.size()!=int(input.group_count)*32:return {}
	var texture := ImageTexture.create_from_image(Image.create_from_data(2,int(input.group_count),false,Image.FORMAT_RGBAF,data))
	var material := ShaderMaterial.new();material.shader=Shader.new()
	var code := Surface.native_code().replace("shader_type spatial;","shader_type spatial;\nuniform sampler2D roof_groups : filter_nearest, repeat_disable;\nuniform int roof_group_count;")
	code=code.replace("void vertex() {", """void vertex() {
	int lo=0; int hi=roof_group_count-1;
	for(int search=0;search<16;search++) {
		if(lo>=hi){break;}
		int mid=(lo+hi)/2;
		vec4 row=texelFetch(roof_groups,ivec2(0,mid),0);
		if(float(VERTEX_ID)>=row.y){lo=mid+1;}else{hi=mid;}
	}
	vec4 row=texelFetch(roof_groups,ivec2(0,lo),0);
	vec4 shape=texelFetch(roof_groups,ivec2(1,lo),0);
	vec2 local=VERTEX.xy;
	VERTEX=vec3(local.x*shape.x+row.z,shape.y,local.y*shape.x+row.w);
	NORMAL=vec3(0.0,1.0,0.0);
	COLOR=vec4(176.0/255.0,177.0/255.0,169.0/255.0,1.0);
""")
	material.shader.code=code;material.set_shader_parameter("roof_groups",texture);material.set_shader_parameter("roof_group_count",int(input.group_count))
	var surface: Dictionary=mesh.get("_surfaces")[0]
	var costs: Dictionary={};var total := data.size()
	for key: String in ["vertex_data","attribute_data","skin_data","index_data"]:
		var bytes: PackedByteArray=surface.get(key,PackedByteArray());costs[key]=bytes.size();total+=bytes.size()
	return {"mesh":mesh,"material":material,"texture":texture,"costs":costs,"table_bytes":data.size(),"three_payload_copies":3*total,"metadata_upload_peak_verified":false}
