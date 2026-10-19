extends RefCounted
## 编辑器离线压缩；游戏只读取已生成的数据，不调用压缩接口。


static func run(source: String, output: String) -> int:
	if source.is_empty() or output.is_empty() or DirAccess.dir_exists_absolute(output):
		return 1
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(source.path_join("manifest.json")))
	if not raw is Dictionary or raw.get("height_encoding")!="global_palette_r8" or raw.get("height_size")!=2048:
		return 1
	var manifest: Dictionary = raw.duplicate(true)
	DirAccess.make_dir_recursive_absolute(output)
	var reports: Array[Dictionary] = []
	for row: Dictionary in manifest.rows:
		var ao_path := source.path_join(str(row.ao))
		if FileAccess.get_sha256(ao_path)!=row.ao_sha256:
			return 1
		var original := Image.load_from_file(ao_path)
		if original==null or original.get_size()!=Vector2i(int(row.size),int(row.size)):
			return 1
		original.convert(Image.FORMAT_R8)
		if original.generate_mipmaps()!=OK:
			return 1
		var packed: Image = original.duplicate()
		var error := packed.compress_from_channels(Image.COMPRESS_S3TC,Image.USED_CHANNELS_R)
		print("[R91 compression] size=",row.size," error=",error," format=",packed.get_format()," bytes=",packed.get_data().size())
		if error!=OK or packed.get_format()!=Image.FORMAT_RGTC_R or not packed.has_mipmaps():
			return 1
		var name_value := "ao_%d.bc4" % int(row.size)
		var file := FileAccess.open(output.path_join(name_value),FileAccess.WRITE)
		file.store_buffer(packed.get_data())
		file.close()
		var restored := Image.create_from_data(int(row.size),int(row.size),true,Image.FORMAT_RGTC_R,FileAccess.get_file_as_bytes(output.path_join(name_value)))
		if restored==null or restored.get_data()!=packed.get_data() or restored.decompress()!=OK:
			return 1
		restored.convert(Image.FORMAT_R8)
		var a := original.get_data()
		var b := restored.get_data()
		if a.size()!=b.size():
			return 1
		var maximum := 0
		var total := 0
		for n in a.size():
			var delta := absi(int(a[n])-int(b[n]))
			maximum=maxi(maximum,delta)
			total+=delta
		var byte_count := packed.get_data().size()
		reports.append({"size":row.size,"original_bytes":a.size(),"packed_bytes":byte_count,"max_error":maximum,"mean_error":float(total)/a.size()})
		row["original_ao_sha256"]=row.ao_sha256
		row.ao=name_value
		row.ao_sha256=FileAccess.get_sha256(output.path_join(name_value))
		row["ao_data_bytes"]=byte_count
		row.conservative_bytes=byte_count*3+2048*2048*3+1536
	for field: String in ["height_indices.png",str(manifest.palette)]:
		if DirAccess.copy_absolute(source.path_join(field),output.path_join(field))!=OK:
			return 1
	for row: Dictionary in manifest.rows:
		if FileAccess.get_sha256(output.path_join(str(row.height)))!=row.height_sha256:
			return 1
	if FileAccess.get_sha256(output.path_join(str(manifest.palette)))!=manifest.palette_sha256:
		return 1
	manifest["ao_encoding"]="bc4_unorm_mips"
	manifest["source_manifest_sha256"]=FileAccess.get_sha256(source.path_join("manifest.json"))
	var file := FileAccess.open(output.path_join("manifest.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(manifest,"\t"))
	file.close()
	file=FileAccess.open(output.path_join("compression-report.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"rows":reports,"fail":0,"height_unchanged":true,"spatial_resolution_unchanged":true,"runtime_enabled":false},"\t"))
	file.close()
	print("[R91 build] ",JSON.stringify(reports))
	return 0
