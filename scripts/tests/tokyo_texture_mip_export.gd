extends RefCounted
## 导出引擎实际mip像素，避免离线缩放算法与正式采样输入不同。
static func run(_parent: Node,input: Dictionary) -> int:
	var binding: Dictionary=input.texture_mip_export
	if FileAccess.get_sha256(binding.path)!=binding.sha256:return 1
	var source: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(binding.path))
	var output: String=input.output
	if DirAccess.dir_exists_absolute(output) or DirAccess.make_dir_recursive_absolute(output)!=OK:return 1
	var rows: Array=[]
	for i in source.rows.size():
		var row: Dictionary=source.rows[i]
		if FileAccess.get_sha256(row.path)!=row.sha256:return 1
		var image := Image.load_from_file(row.path)
		if image==null or image.get_format()!=Image.FORMAT_RGBA8 or image.generate_mipmaps()!=OK:return 1
		var bytes := image.get_data()
		if bytes.size()*3!=int(row.three_copy_bytes):return 1
		var path := output.path_join("%04d.rgba"%i)
		var file := FileAccess.open(path,FileAccess.WRITE)
		if file==null:return 1
		file.store_buffer(bytes);file.close()
		var levels: Array=[];var w := image.get_width();var h := image.get_height()
		for level in image.get_mipmap_count()+1:
			levels.append({"level":level,"width":w,"height":h,"offset":image.get_mipmap_offset(level)})
			w=maxi(1,w/2);h=maxi(1,h/2)
		rows.append({"tile":i,"path":path,"sha256":FileAccess.get_sha256(path),"levels":levels})
	var file := FileAccess.open(output.path_join("manifest.json"),FileAccess.WRITE)
	if file==null:return 1
	file.store_string(JSON.stringify({"source_sha256":binding.sha256,"rows":rows,"gpu_sampling_verified":false},"\t"));file.close()
	print("Tokyo texture mip export: ",rows.size())
	return 0
