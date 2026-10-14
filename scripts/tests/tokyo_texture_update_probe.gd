extends RefCounted
## 显式诊断本机公开接口与同对象更新，不授整包峰值或帧率资格。
static func run(parent: Node, input: Dictionary) -> int:
	if input.has("layer_cases"):return await run_layered(parent,input)
	var methods: Dictionary={}
	for type_name: String in ["ImageTexture","RenderingServer"]:
		var selected: Array=[]
		for method: Dictionary in ClassDB.class_get_method_list(type_name):
			var method_name := String(method.name)
			if "update" in method_name and (type_name=="ImageTexture" or "texture" in method_name):
				selected.append(method)
		methods[type_name]=selected
	var cases: Array=[]
	var passed := true
	for format_value: int in [Image.FORMAT_RGBA8,Image.FORMAT_RGF,Image.FORMAT_RGBAF]:
		var image := Image.create(16,4,false,format_value)
		image.fill(Color(0,0,0,1))
		var texture := ImageTexture.create_from_image(image)
		var original_rid := texture.get_rid()
		image.set_pixel(7,2,Color(0.25,0.5,0.75,1))
		var expected := image.get_data()
		texture.update(image)
		await parent.get_tree().process_frame
		await RenderingServer.frame_post_draw
		var actual := texture.get_image()
		var exact := actual.get_data()==expected
		var same_rid := texture.get_rid()==original_rid
		passed=passed and exact and same_rid
		cases.append({"format":format_value,"pixel_exact":exact,"same_rid":same_rid})
		actual=null
		image=null
		texture=null
	await parent.get_tree().process_frame
	var output := FileAccess.open(String(input.output),FileAccess.WRITE)
	if output==null:return 1
	output.store_string(JSON.stringify({"engine":Engine.get_version_info(),"methods":methods,"cases":cases,"passed":passed,"whole_package_verified":false,"performance_verified":false},"\t"))
	output.close()
	return 0 if passed else 1

static func run_layered(parent: Node, input: Dictionary) -> int:
	var results: Array=[]
	var passed := true
	for row: Dictionary in input.layer_cases:
		var source := FileAccess.open(row.source,FileAccess.READ)
		var patch := FileAccess.open(row.patch,FileAccess.READ)
		if source==null or patch==null:return 1
		source.seek(int(row.source_offset));patch.seek(int(row.patch_offset))
		var before := source.get_buffer(int(row.bytes));before.resize(int(row.bytes))
		var after := patch.get_buffer(int(row.bytes))
		source.close();patch.close()
		var digest := HashingContext.new();digest.start(HashingContext.HASH_SHA256);digest.update(after)
		if digest.finish().hex_encode()!=row.sha256:return 1
		var initial := Image.create_from_data(4096,1,false,int(row.format),before)
		var replacement := Image.create_from_data(4096,1,false,int(row.format),after)
		var texture := Texture2DArray.new()
		var images: Array[Image]=[initial,initial]
		if texture.create_from_images(images)!=OK:return 1
		var rid := texture.get_rid()
		texture.update_layer(replacement,0)
		await parent.get_tree().process_frame
		await RenderingServer.frame_post_draw
		var updated := texture.get_layer_data(0)
		var untouched := texture.get_layer_data(1)
		var exact := updated.get_data()==after and untouched.get_data()==before
		var shader_result: Dictionary={}
		if input.get("shader_readback",false):
			shader_result=await sample_layered(parent,texture,before,after,int(row.format))
			exact=shader_result.exact
		var actual_bytes := updated.get_data()
		var difference := -1
		for i in mini(actual_bytes.size(),after.size()):
			if actual_bytes[i]!=after[i]:difference=i;break
		passed=passed and exact and texture.get_rid()==rid
		results.append({"name":row.name,"bytes":row.bytes,"pixel_exact":exact,"same_rid":texture.get_rid()==rid,"source_changed":before!=after,"actual_format":updated.get_format(),"expected_format":int(row.format),"actual_bytes":actual_bytes.size(),"untouched_exact":untouched.get_data()==before,"first_different_byte":difference,"expected_float":after.decode_float(difference-difference%4) if difference>=0 and int(row.format)!=5 else 0,"actual_float":actual_bytes.decode_float(difference-difference%4) if difference>=0 and int(row.format)!=5 else 0})
		results.back()["shader_readback"]=shader_result
		updated=null;untouched=null;images.clear();initial=null;replacement=null;texture=null
	for frame in 4:await parent.get_tree().process_frame
	var output := FileAccess.open(String(input.output),FileAccess.WRITE)
	if output==null:return 1
	output.store_string(JSON.stringify({"passed":passed,"cases":results,"actual_patch_rows":true,"all_layers_capacity_verified":false,"map_continuity_verified":false,"performance_verified":false},"\t"));output.close()
	return 0 if passed else 1

static func sample_layered(parent: Node, texture: Texture2DArray, before: PackedByteArray, after: PackedByteArray, format_value: int) -> Dictionary:
	var channels := 2 if format_value==Image.FORMAT_RGF else 4
	var viewport := SubViewport.new();viewport.size=Vector2i(4096,channels*2)
	viewport.transparent_bg=true;viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	var material := ShaderMaterial.new();material.shader=Shader.new()
	material.shader.code="""shader_type canvas_item;
render_mode unshaded, blend_disabled;
uniform sampler2DArray source_array : filter_nearest, repeat_disable;
uniform int components;
void fragment(){
 ivec2 p=ivec2(FRAGCOORD.xy);
 vec4 v=texelFetch(source_array,ivec3(p.x,0,p.y/components),0);
 uint n=uint(round(v[p.y%components])+1.0);
 COLOR=vec4(float(n&255u),float((n>>8u)&255u),float((n>>16u)&255u),float((n>>24u)&255u))/255.0;
}"""
	material.set_shader_parameter("source_array",texture);material.set_shader_parameter("components",channels)
	var rect := ColorRect.new();rect.size=Vector2(viewport.size);rect.material=material
	parent.add_child(viewport);viewport.add_child(rect)
	await RenderingServer.frame_post_draw
	var actual := viewport.get_texture().get_image();actual.convert(Image.FORMAT_RGBA8)
	var bytes := actual.get_data();var expected := PackedByteArray();expected.resize(bytes.size())
	for layer in 2:
		var data := after if layer==0 else before
		for component in channels:
			for x in 4096:
				expected.encode_u32(((layer*channels+component)*4096+x)*4,int(round(data.decode_float((x*channels+component)*4)))+1)
	var mismatch := -1
	for i in bytes.size():
		if bytes[i]!=expected[i]:mismatch=i;break
	var result := {"exact":bytes==expected,"values":4096*channels*2,"first_mismatch":mismatch}
	viewport.queue_free();rect=null;viewport=null;material=null;actual=null
	await parent.get_tree().process_frame
	return result
