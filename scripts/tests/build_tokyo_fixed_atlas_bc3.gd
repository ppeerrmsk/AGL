extends RefCounted
## 仅离线制作；显式原生来源与实际BC3字节，不用PNG文件大小当GPU预算。
const RESIDENTIAL_CATALOG := "c0311651371c29025b8db0a8618adb57a2faeb39ab59c4751ee743b3d9c346ca"
const RESIDENTIAL_MANIFESTS := {11:"445a25e52a81f5e85fc597ff4215549e61e7e030718707ee7252ad46f6359455",12:"25ae9e49472285cbf2adc2a9f8692184dda237bd82a7ef8b4b77695a42556ec4"}


static func region_contract(parent: Variant, catalog: String = "") -> Dictionary:
	var region := preload("res://scripts/rendering/tokyo_fixed_atlas_layer.gd").region_contract(parent)
	if catalog==RESIDENTIAL_CATALOG:
		if region.is_empty() or int(parent) not in [11,12]:
			return {}
		region.faces=28145 if int(parent)==11 else 9705
	return region


static func manifest_valid(raw: Variant) -> bool:
	if not raw is Dictionary or raw.get("schema")!=1:
		return false
	if raw.get("catalog_sha256")!=RESIDENTIAL_CATALOG and raw.get("catalog_sha256") not in preload("res://scripts/rendering/tokyo_canonical_catalog.gd").UNCHANGED_FIXED_LOD12_CATALOGS:
		return false
	var region := region_contract(raw.get("parent"),str(raw.get("catalog_sha256")))
	if region.is_empty() or not raw.get("source") is Dictionary or raw.get("original_fixed_faces")!=region.faces:
		return false
	if raw.source.get("parent")!=raw.parent or raw.source.get("triangles")!=region.faces or not raw.source.get("source") is String or not raw.source.get("source_sha256") is String or raw.source.source_sha256.length()!=64:
		return false
	if not raw.get("rows") is Array or raw.rows.size()!=2:
		return false
	for index in 2:
		var row: Variant = raw.rows[index]
		if not row is Dictionary or row.get("world_step")!=[2,1][index] or row.get("native_bounds")!=region.bounds or row.get("max_scale")!=0.3888 or row.get("rectangular_coverage")!=true or row.get("premultiplied_alpha")!=true:
			return false
		if not row.get("bounds") is Array or row.bounds.size()!=4 or not row.get("height_range") is Array or row.height_range.size()!=2:
			return false
		for number: Variant in row.bounds+row.height_range+[row.get("width"),row.get("height")]:
			if not typeof(number) in [TYPE_INT,TYPE_FLOAT] or not is_finite(float(number)):
				return false
		if row.width<=0 or row.height<=0 or row.width!=int(row.width) or row.height!=int(row.height) or int(row.width)%4!=0 or int(row.height)%4!=0 or row.width>4096 or row.height>4096:
			return false
		if row.bounds[2]-row.bounds[0]!=row.width*row.world_step or row.bounds[3]-row.bounds[1]!=row.height*row.world_step or row.height_range[0]<-1 or row.height_range[1]>1 or row.height_range[0]>row.height_range[1]:
			return false
		if row.bounds[0]>region.bounds[0] or row.bounds[1]>region.bounds[1] or row.bounds[2]<region.bounds[2] or row.bounds[3]<region.bounds[3]:
			return false
		if not row.get("file") is String or row.file.is_empty() or row.file.get_file()!=row.file or not row.get("sha256") is String or row.sha256.length()!=64:
			return false
	return true


static func flat_rgb_block(rgb: PackedByteArray) -> PackedByteArray:
	var result := PackedByteArray()
	if rgb.size()!=3:
		return result
	result.resize(8)
	var endpoint0 := 0
	var endpoint1 := 0
	for channel in 3:
		var bits := 6 if channel==1 else 5
		var best := 2147483647
		var pair := Vector2i.ZERO
		for a in 1<<bits:
			var va: int = (a<<2)|(a>>4) if bits==6 else (a<<3)|(a>>2)
			for b in 1<<bits:
				var vb: int = (b<<2)|(b>>4) if bits==6 else (b<<3)|(b>>2)
				var value := (2.0*va+vb)/3.0
				var worst := maxi(absi(floori(value)-int(rgb[channel])),absi(ceili(value)-int(rgb[channel])))
				var cost := worst*100000+absi(floori(value)-int(rgb[channel]))*10000+absi(va-int(rgb[channel]))+absi(vb-int(rgb[channel]))
				if cost<best:
					best=cost
					pair=Vector2i(a,b)
		var shift: int = [11,5,0][channel]
		endpoint0|=pair.x<<shift
		endpoint1|=pair.y<<shift
	result.encode_u16(0,endpoint0)
	result.encode_u16(2,endpoint1)
	result.encode_u32(4,0xaaaaaaaa)
	return result


static func patch_flat_blocks(original: Image, packed: Image) -> Dictionary:
	if original==null or packed==null or original.get_format()!=Image.FORMAT_RGBA8 or packed.get_format()!=Image.FORMAT_DXT5 or original.get_size()!=packed.get_size() or original.get_mipmap_count()!=packed.get_mipmap_count():
		return {}
	var rgba := original.get_data()
	var bytes := packed.get_data()
	var width := original.get_width()
	var height := original.get_height()
	var colors: Dictionary = {}
	var patched := 0
	for level in original.get_mipmap_count()+1:
		var source_offset := original.get_mipmap_offset(level)
		var target_offset := packed.get_mipmap_offset(level)
		var blocks_w := ceili(width/4.0)
		for by in height/4:
			for bx in width/4:
				var start := source_offset+(by*4*width+bx*4)*4
				var color := rgba.decode_u32(start)
				if rgba[start+3]!=255:
					continue
				var constant := true
				for y in 4:
					for x in 4:
						if rgba.decode_u32(start+(y*width+x)*4)!=color:
							constant=false
							break
					if not constant:
						break
				if not constant:
					continue
				if not colors.has(color):
					colors[color]=flat_rgb_block(rgba.slice(start,start+3))
				var offset := target_offset+(by*blocks_w+bx)*16+8
				for n in 8:
					bytes[offset+n]=colors[color][n]
				patched+=1
		width=maxi(1,width/2)
		height=maxi(1,height/2)
	return {"bytes":bytes,"patched_blocks":patched,"flat_colors":colors.size()}


static func run(source: String, output: String) -> int:
	if DirAccess.dir_exists_absolute(output):
		return 1
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(source.path_join("manifest.json")))
	if not manifest_valid(raw):
		return 1
	if raw.catalog_sha256==RESIDENTIAL_CATALOG and FileAccess.get_sha256(source.path_join("manifest.json"))!=RESIDENTIAL_MANIFESTS[int(raw.parent)]:
		return 1
	if FileAccess.get_sha256(raw.source.source)!=raw.source.source_sha256:
		return 1
	DirAccess.make_dir_recursive_absolute(output)
	var manifest: Dictionary = raw.duplicate(true)
	var reports: Array[Dictionary] = []
	for row: Dictionary in manifest.rows:
		var path := source.path_join(str(row.file))
		if FileAccess.get_sha256(path)!=row.sha256:
			return 1
		var original := Image.load_from_file(path)
		if original==null or original.get_size()!=Vector2i(int(row.width),int(row.height)):
			return 1
		original.convert(Image.FORMAT_RGBA8)
		if original.generate_mipmaps()!=OK:
			return 1
		var packed: Image = original.duplicate()
		if packed.compress_from_channels(Image.COMPRESS_S3TC,Image.USED_CHANNELS_RGBA)!=OK or packed.get_format()!=Image.FORMAT_DXT5 or not packed.has_mipmaps() or packed.get_data().size()!=int(row.bc3_mip_bytes_estimate):
			return 1
		if OS.get_environment("AGL_TOKYO_FIXED_FLAT_BC3")=="1":
			var refinement := patch_flat_blocks(original,packed)
			if refinement.is_empty() or refinement.bytes.size()!=packed.get_data().size():
				return 1
			packed=Image.create_from_data(original.get_width(),original.get_height(),true,Image.FORMAT_DXT5,refinement.bytes)
			row["flat_bc3"]={"patched_blocks":refinement.patched_blocks,"flat_colors":refinement.flat_colors,"only_constant_opaque_blocks":true}
		var name_value := "fixed_%d.bc3" % int(row.world_step)
		var file := FileAccess.open(output.path_join(name_value),FileAccess.WRITE)
		file.store_buffer(packed.get_data())
		file.close()
		var restored := Image.create_from_data(original.get_width(),original.get_height(),true,Image.FORMAT_DXT5,FileAccess.get_file_as_bytes(output.path_join(name_value)))
		if restored==null or restored.get_data()!=packed.get_data() or restored.decompress()!=OK:
			return 1
		restored.convert(Image.FORMAT_RGBA8)
		var a := original.get_data()
		var b := restored.get_data()
		if a.size()!=b.size():
			return 1
		var maximum := 0
		var total := 0
		var alpha_max := 0
		for n in a.size():
			var delta := absi(int(a[n])-int(b[n]))
			maximum=maxi(maximum,delta)
			total+=delta
			if n%4==3:
				alpha_max=maxi(alpha_max,delta)
		row["original_file"]=path
		row["original_sha256"]=row.sha256
		row.file=name_value
		row.sha256=FileAccess.get_sha256(output.path_join(name_value))
		row["actual_bc3_bytes"]=packed.get_data().size()
		row["conservative_bytes"]=packed.get_data().size()*3+4096
		row["format"]=int(Image.FORMAT_DXT5)
		reports.append({"step":row.world_step,"bytes":packed.get_data().size(),"max_error":maximum,"mean_error":float(total)/a.size(),"alpha_max":alpha_max})
	manifest["encoding"]="bc3_rgba_mips"
	manifest["compression_roundtrip_verified"]=true
	manifest["compression_report"]=reports
	var file := FileAccess.open(output.path_join("manifest.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(manifest,"\t"))
	file.close()
	print("[fixed BC3] parent=",raw.parent," ",JSON.stringify(reports))
	return 0
