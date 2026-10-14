extends RefCounted
## 不透明BC3直接抽取颜色块；不重新量化，不丢alpha，全部mip解码相等才保存。


static func color_blocks(raw: PackedByteArray) -> PackedByteArray:
	if raw.is_empty() or raw.size()%16!=0: return PackedByteArray()
	var result := PackedByteArray()
	result.resize(raw.size()/2)
	for offset in range(0,raw.size(),16):
		var a := raw.decode_u16(offset+8)
		var b := raw.decode_u16(offset+10)
		var codes := raw.decode_u32(offset+12)
		if a<b:
			var swap := a;a=b;b=swap
			codes=codes^0x55555555
		elif a==b: codes=0
		result.encode_u16(offset/2,a)
		result.encode_u16(offset/2+2,b)
		result.encode_u32(offset/2+4,codes)
	return result


static func opaque_image(source: Image) -> Image:
	if source==null or source.get_format()!=Image.FORMAT_DXT5: return null
	var decoded: Image = source.duplicate()
	if decoded.decompress()!=OK: return null
	decoded.convert(Image.FORMAT_RGBA8)
	var pixels := decoded.get_data()
	var width := source.get_width()
	var height := source.get_height()
	var offset := 0
	for level in source.get_mipmap_count()+1:
		var count := width*height*4
		var mip := Image.create_from_data(width,height,false,Image.FORMAT_RGBA8,pixels.slice(offset,offset+count))
		if mip.detect_alpha()!=Image.ALPHA_NONE: return null
		offset+=count
		width=maxi(1,width/2);height=maxi(1,height/2)
	var packed := Image.create_from_data(source.get_width(),source.get_height(),source.has_mipmaps(),Image.FORMAT_DXT1,color_blocks(source.get_data()))
	var restored: Image = packed.duplicate()
	if restored.decompress()!=OK: return null
	restored.convert(Image.FORMAT_RGBA8)
	if restored.get_data()!=decoded.get_data():
		print("[Opaque conversion] decode mismatch size=",source.get_size()," old=",decoded.get_data().slice(0,24)," new=",restored.get_data().slice(0,24))
		return null
	return packed


static func checks() -> bool:
	if not color_blocks(PackedByteArray([0])).is_empty() or opaque_image(null)!=null: return false
	for endpoints in [[65535,0],[0,65535],[1234,1234]]:
		var raw := PackedByteArray();raw.resize(16)
		raw[0]=255;raw[1]=255
		raw.encode_u16(8,endpoints[0]);raw.encode_u16(10,endpoints[1]);raw.encode_u32(12,0xe4e4e4e4)
		var image := Image.create_from_data(4,4,false,Image.FORMAT_DXT5,raw)
		var packed := opaque_image(image)
		if packed==null or packed.get_data_size()!=8:
			print("[Opaque check] rejected endpoints=",endpoints)
			return false
		raw[0]=127;raw[1]=127
		if opaque_image(Image.create_from_data(4,4,false,Image.FORMAT_DXT5,raw))!=null: return false
	return true


static func run(path: String, digest: String, output: String) -> int:
	var contract: GDScript = load("res://scripts/rendering/tokyo_hlod_manifest.gd")
	if not checks() or not contract.sha(digest) or FileAccess.get_sha256(path)!=digest or not output.is_absolute_path() \
		or DirAccess.dir_exists_absolute(output) or DirAccess.make_dir_recursive_absolute(output)!=OK: return 1
	var input: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not input is Array or input.is_empty(): return 1
	var replaced: Dictionary = {}
	var records: Array = []
	var converted := 0
	for binding: Variant in input:
		if not contract.binding(binding) or contract.read(binding.path,binding.sha256).is_empty(): return 1
		var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(binding.path))
		for row: Dictionary in manifest.rows:
			var original: Dictionary = row.native_texture
			if not replaced.has(original.path):
				if FileAccess.get_sha256(original.path)!=original.sha256: return 1
				var source: Image = ResourceLoader.load(original.path,"Image",ResourceLoader.CACHE_MODE_IGNORE)
				if source==null or source.get_data_size()!=int(original.mip_bytes): return 1
				var packed := opaque_image(source)
				var replacement := original.duplicate(true)
				if packed!=null:
					var target := output.path_join(String(original.sha256)+".res")
					if ResourceSaver.save(packed,target,ResourceSaver.FLAG_COMPRESS)!=OK: return 1
					var restored: Image = ResourceLoader.load(target,"Image",ResourceLoader.CACHE_MODE_IGNORE)
					if restored==null or restored.get_format()!=Image.FORMAT_DXT1 or restored.get_data()!=packed.get_data(): return 1
					replacement["path"]=target
					replacement["sha256"]=FileAccess.get_sha256(target)
					replacement["format"]=int(Image.FORMAT_DXT1)
					replacement["mip_bytes"]=packed.get_data_size()
					replacement["three_copy_charge"]=packed.get_data_size()*3+4096
					replacement["opaque_decoded_equal"]=true
					converted+=1
					records.append({"source":original,"replacement":replacement})
				else: records.append({"source":original,"retained":true})
				replaced[original.path]=replacement
			row.native_texture=replaced[original.path]
		var manifest_path := output.path_join("manifest_"+String(binding.sha256)+".json")
		if contract.normalize(manifest).is_empty(): return 1
		var file := FileAccess.open(manifest_path,FileAccess.WRITE)
		if file==null: return 1
		file.store_string(JSON.stringify(manifest));file.close()
		print("[Opaque HLOD] manifest=",manifest_path," unique=",replaced.size()," converted=",converted)
		var mapping := FileAccess.open(output.path_join(String(binding.sha256)+".json"),FileAccess.WRITE)
		if mapping==null: return 1
		mapping.store_string(JSON.stringify({"source":binding,"manifest":{"path":manifest_path,"sha256":FileAccess.get_sha256(manifest_path)}}));mapping.close()
	var report := FileAccess.open(output.path_join("report.json"),FileAccess.WRITE)
	if report==null: return 1
	report.store_string(JSON.stringify({"converted":converted,"textures":records}));report.close()
	return 0
