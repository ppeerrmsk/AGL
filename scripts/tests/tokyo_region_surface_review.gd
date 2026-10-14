extends RefCounted
## 使用现有AO shader的独立原生材质对拍；不放宽规范bind_ao/预热身份门。
const AO := preload("res://scripts/experiments/tokyo_baked_ao.gd")


func run(view: Node) -> int:
	var directory := OS.get_environment("AGL_TOKYO_REGION_SURFACE_AO")
	var manifest: Variant = JSON.parse_string(FileAccess.get_file_as_string(directory.path_join("manifest.json")))
	if not manifest is Dictionary or manifest.get("source_kind","")!="independent_cells_lod5" or manifest.get("index_sha256","")!=FileAccess.get_sha256(OS.get_environment("AGL_TOKYO_REGION_SAMPLE_INDEX")):
		return 1
	var row: Dictionary = AO.choose_row(manifest.rows,5.0)
	if row.is_empty() or int(row.size)!=2048 or AO.row_bytes(manifest,row)<=0:
		return 1
	var textures: Array[ImageTexture] = []
	for field: String in ["ao","height"]:
		if String(row[field])!=String(row[field]).get_file() or FileAccess.get_sha256(directory.path_join(row[field]))!=row[field+"_sha256"]:
			return 1
		var picture := Image.load_from_file(directory.path_join(row[field]))
		if picture==null or picture.get_size()!=Vector2i(2048,2048):
			return 1
		if field=="ao":
			picture.convert(Image.FORMAT_R8)
			if picture.generate_mipmaps()!=OK:
				return 1
		textures.append(ImageTexture.create_from_image(picture))
	var shader := Shader.new()
	shader.code=AO.make_shader(preload("res://resources/shaders/tokyo_volume_surface.gdshader").code)
	if shader.code.is_empty():
		return 1
	var original: Array[Shader] = []
	var bounds: Array = manifest.bounds
	for material: ShaderMaterial in view._shared:
		original.append(material.shader)
		material.shader=shader
		material.set_shader_parameter("facade_detail",original.size()==2)
		material.set_shader_parameter("baked_ao",textures[0])
		material.set_shader_parameter("baked_height",textures[1])
		material.set_shader_parameter("ao_bounds",Vector4(bounds[0],bounds[1],bounds[2]-bounds[0],bounds[3]-bounds[1]))
		material.set_shader_parameter("ao_strength",0.0)
	var captures: Array[Dictionary] = []
	var failed := false
	var poses: Array = []
	for zoom_value: float in [0.13,0.26,0.65,0.98,1.95,5.0]:
		poses.append(["center_%03d" % roundi(zoom_value*100),view.preview_center,zoom_value])
	poses.append(["ao_edge",Vector2(bounds[0],(bounds[1]+bounds[3])*0.5),5.0])
	poses.append(["north",Vector2(view.preview_center.x,view._index.bounds.position.y+120.0),1.95])
	poses.append(["south",Vector2(view.preview_center.x,view._index.bounds.end.y-120.0),1.95])
	for pose: Array in poses:
		view._set_view(pose[1],pose[2])
		failed=await view._settle() or failed
		for strength: float in [0.0,0.3,0.6,0.0]:
			for material: ShaderMaterial in view._shared:
				material.set_shader_parameter("ao_strength",strength)
			var suffix := "restore" if captures.size()%5==3 else "ao_%02d" % roundi(strength*100)
			failed=await view._capture(pose[0]+"_"+suffix,pose[1],pose[2],false,captures) or failed
			captures[-1]["strength"]=strength
			captures[-1]["selection"]=view._selection.duplicate(true)
			failed=failed or int(view._selection.resident_bytes)+int(row.conservative_bytes)>96*1024*1024 or int(view._selection.shadow_casters)!=0 or not view._selection.light_shadow_path
		view._geometry_root.hide()
		failed=await view._capture(pose[0]+"_tiles",pose[1],pose[2],false,captures) or failed
		view._geometry_root.show()
	for i in view._shared.size():
		view._shared[i].shader=original[i]
		view._shared[i].set_shader_parameter("facade_detail",i==1)
	failed=await view._capture("shader_restored",poses[-1][1],poses[-1][2],false,captures) or failed
	var file := FileAccess.open(view.output_prefix+"manifest.json",FileAccess.WRITE)
	if file==null:
		return 1
	file.store_string(JSON.stringify({"failed":failed,"captures":captures,"ao_manifest_sha256":FileAccess.get_sha256(directory.path_join("manifest.json")),"bounds":bounds,
		"texture_conservative_bytes":row.conservative_bytes,"source_kind":"independent_cells_lod5","shader":"tokyo_volume_surface + tokyo_baked_ao.make_shader","production_compositor":false,"streaming_verified":false}))
	file.close()
	print("[Tokyo region surface Visual] captures=",captures.size()," fail=",failed)
	return 1 if failed else 0
