extends RefCounted
## 将地面样片转成正式流送器接受的Image资源；仅制作，不授予地图覆盖资格。


static func run(input: Dictionary) -> int:
	var contract := preload("res://scripts/rendering/tokyo_hlod_manifest.gd")
	var binding: Dictionary=input.get("ground_pack",{})
	var output: String=input.get("output","")
	if not contract.binding(binding) or FileAccess.get_sha256(binding.path)!=binding.sha256: return 1
	if not output.is_absolute_path() or DirAccess.dir_exists_absolute(output): return 1
	var source: Variant=JSON.parse_string(FileAccess.get_file_as_string(binding.path))
	if not source is Dictionary or not source.get("preview_only",false) or source.get("roof_geometry_baked",true) or not source.get("rows") is Dictionary: return 1
	if DirAccess.make_dir_recursive_absolute(output)!=OK: return 1
	var rows: Dictionary={}
	for key: String in source.rows:
		var row: Dictionary=source.rows[key]
		if not contract.binding(row.get("texture")) or FileAccess.get_sha256(row.texture.path)!=row.texture.sha256: return 1
		var image := Image.load_from_file(row.texture.path)
		if image==null or image.get_format()!=Image.FORMAT_RGBA8 or image.generate_mipmaps()!=OK: return 1
		if image.get_width()!=int(row.raster.width) or image.get_height()!=int(row.raster.height): return 1
		var packed: Image=image.duplicate()
		if packed.compress_from_channels(Image.COMPRESS_S3TC,Image.USED_CHANNELS_RGBA)!=OK or packed.get_format()!=Image.FORMAT_DXT5: return 1
		var patched := preload("res://scripts/tests/build_tokyo_fixed_atlas_bc3.gd").patch_flat_blocks(image,packed)
		if patched.is_empty(): return 1
		packed=Image.create_from_data(image.get_width(),image.get_height(),true,Image.FORMAT_DXT5,patched.bytes)
		var path := output.path_join("ground_%03d.image.res" % rows.size())
		if ResourceSaver.save(packed,path,ResourceSaver.FLAG_COMPRESS)!=OK: return 1
		var restored: Resource=ResourceLoader.load(path,"",ResourceLoader.CACHE_MODE_IGNORE)
		if not restored is Image or restored.get_format()!=Image.FORMAT_DXT5 or restored.get_data()!=packed.get_data(): return 1
		var decoded: Image=restored.duplicate()
		if decoded.decompress()!=OK: return 1
		var original_bytes := image.get_data()
		var decoded_bytes := decoded.get_data()
		if original_bytes.size()!=decoded_bytes.size(): return 1
		var max_error := 0
		var opaque_loss := 0
		var empty_fill := 0
		for offset in range(0,image.get_width()*image.get_height()*4,4):
			opaque_loss+=int(original_bytes[offset+3]==255 and decoded_bytes[offset+3]!=255)
			empty_fill+=int(original_bytes[offset+3]==0 and decoded_bytes[offset+3]!=0)
			for channel in 3: max_error=maxi(max_error,absi(int(original_bytes[offset+channel])-int(decoded_bytes[offset+channel])))
		if opaque_loss!=0 or empty_fill!=0: return 1
		var count := packed.get_data().size()
		var saved := row.duplicate(true)
		saved["native_texture"]={"path":path,"sha256":FileAccess.get_sha256(path),"width":image.get_width(),"height":image.get_height(),
			"format":int(Image.FORMAT_DXT5),"mip_bytes":count,"charge":count*3+4096}
		saved["compression_audit"]={"roundtrip":true,"opaque_pixels_lost":opaque_loss,"empty_pixels_filled":empty_fill,"max_base_rgb_error":max_error,"patched_flat_blocks":patched.patched_blocks}
		rows[key]=saved
		print("[Native ground pack] pages=",rows.size(),"/",source.rows.size()," max_rgb_error=",max_error)
	var result: Dictionary=source.duplicate(true)
	result["uncompressed_source"]=binding
	result["rows"]=rows
	result["stream_resource_format"]=true
	var file := FileAccess.open(output.path_join("manifest.json"),FileAccess.WRITE)
	if file==null: return 1
	file.store_string(JSON.stringify(result,"\t"));file.close()
	return 0
