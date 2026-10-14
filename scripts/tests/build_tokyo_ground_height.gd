extends RefCounted
## 显式候选制作：高度索引无有损压缩、无mip，颜色资源保持原身份。
static func run(input: Dictionary) -> int:
	var contract := preload("res://scripts/rendering/tokyo_hlod_manifest.gd")
	var source: Variant=input.get("ground_height_pack")
	var color: Variant=input.get("color_pack")
	var output: String=input.get("output","")
	if not contract.binding(source) or not contract.binding(color): return 1
	if FileAccess.get_sha256(source.path)!=source.sha256 or FileAccess.get_sha256(color.path)!=color.sha256: return 1
	if not output.is_absolute_path() or DirAccess.dir_exists_absolute(output): return 1
	var heights: Variant=JSON.parse_string(FileAccess.get_file_as_string(source.path))
	var colors: Variant=JSON.parse_string(FileAccess.get_file_as_string(color.path))
	if not heights is Dictionary or not colors is Dictionary or not heights.get("rows") is Dictionary or not colors.get("stream_resource_format",false): return 1
	if heights.rows.size()!=colors.get("rows",{}).size(): return 1
	if DirAccess.make_dir_recursive_absolute(output)!=OK: return 1
	var count := 0
	for key: String in colors.rows:
		var row: Dictionary=colors.rows[key]
		if not heights.rows.has(key): return 1
		var height: Dictionary=heights.rows[key]
		if height.get("source")!=row.source or height.get("height_packing")!="two_nibbles_per_byte" or not contract.numbers(height.get("height_levels"),16): return 1
		if not contract.binding(height.get("height_texture")) or FileAccess.get_sha256(height.height_texture.path)!=height.height_texture.sha256: return 1
		var image := Image.load_from_file(height.height_texture.path)
		if image==null or image.has_mipmaps(): return 1
		image.convert(Image.FORMAT_RGBA8)
		var path := output.path_join("height_%03d.image.res"%count)
		if ResourceSaver.save(image,path,ResourceSaver.FLAG_COMPRESS)!=OK: return 1
		var restored: Resource=ResourceLoader.load(path,"",ResourceLoader.CACHE_MODE_IGNORE)
		if not restored is Image or restored.has_mipmaps() or restored.get_format()!=Image.FORMAT_RGBA8 or restored.get_data()!=image.get_data(): return 1
		var descriptor := {"path":path,"sha256":FileAccess.get_sha256(path),"kind":"ground_height_4bit","mipmaps":false,
			"width":image.get_width(),"height":image.get_height(),"format":Image.FORMAT_RGBA8,"mip_bytes":image.get_data_size(),"charge":image.get_data_size()*3+4096}
		if preload("res://scripts/rendering/tokyo_ground_height.gd").descriptor(descriptor,Vector2i(int(row.native_texture.width),int(row.native_texture.height))).is_empty(): return 1
		row["native_height"]=descriptor;row["height_levels"]=height.height_levels
		count+=1
	colors["height_source"]=source
	var file := FileAccess.open(output.path_join("manifest.json"),FileAccess.WRITE)
	if file==null: return 1
	file.store_string(JSON.stringify(colors,"\t"));file.close()
	print("[Ground height pack] lossless_pages=",count)
	return 0
