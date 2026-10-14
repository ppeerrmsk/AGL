extends RefCounted
## 新HLOD表示原生打包；不借用旧逐角守恒/正式楼coverage身份。
const NativeReview := preload("res://scripts/tests/tokyo_overview_hlod_review.gd")
const ComponentWriter := preload("res://scripts/tests/build_tokyo_mesh_components.gd")
const MeshPacking := preload("res://scripts/experiments/tokyo_packed_mesh_reindex.gd")
const MeshCount := preload("res://scripts/experiments/tokyo_indexed_mesh.gd")
const FlatBC3 := preload("res://scripts/tests/build_tokyo_fixed_atlas_bc3.gd")


static func valid_input(data: Variant) -> bool:
	if not data is Dictionary or data.get("schema")!=1 or data.get("roots")!=16 or data.get("nodes")!=336 \
		or not data.get("rows") is Array or data.rows.size()!=336 or data.get("mesh_format")!="little_endian_float32_triangle_XYZ" \
		or data.get("textures")!="premultiplied_rgba8_mips":
		return false
	var keys: Dictionary = {}
	if data.has("reuse_parent_textures") and typeof(data.reuse_parent_textures)!=TYPE_BOOL: return false
	for row: Variant in data.rows:
		if not row is Dictionary or not typeof(row.get("depth")) in [TYPE_INT,TYPE_FLOAT] \
			or not typeof(row.get("id")) in [TYPE_INT,TYPE_FLOAT] or row.depth!=int(row.depth) or row.id!=int(row.id):
			return false
		var depth := int(row.depth)
		if depth<0 or depth>2 or row.id<0 or row.id>=16*(1<<(depth*2)):
			return false
		var key := "%d:%d" % [depth,int(row.id)]
		if keys.has(key): return false
		keys[key]=true
	return true


static func build_mesh(raw: PackedByteArray, first: int, count: int, bounds: Rect2, formal: bool) -> ArrayMesh:
	if count==0: return ArrayMesh.new()
	var result := NativeReview.triangle_mesh(raw,first,count,bounds)
	if formal:
		var arrays := result.surface_get_arrays(0)
		var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		for n in colors.size():
			colors[n]=Color.html("b0b1a9") if normals[n].y>0.99 else Color.html("b0b1a9").darkened(0.08)
		arrays[Mesh.ARRAY_COLOR]=colors
		result=ArrayMesh.new()
		result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	var packed := MeshPacking.repack(result)
	if packed==null or MeshPacking.corner_digest(packed)!=MeshPacking.corner_digest(result): return null
	return packed


static func reuse_texture(row: Dictionary, reference: Variant) -> Dictionary:
	if not reference is Dictionary or not row.get("texture") is Dictionary or not reference.get("texture") is Dictionary: return {}
	var texture: Dictionary = row.texture.duplicate(true)
	var previous: Dictionary = reference.texture.duplicate(true)
	if not NativeReview.binding(texture.get("file")) or not NativeReview.binding(previous.get("file")) \
		or texture.file.sha256!=previous.file.sha256: return {}
	texture.erase("file");previous.erase("file")
	if texture!=previous or not NativeReview.binding(reference.get("native_texture")) \
		or not NativeReview.binding(reference.get("decoded_texture")): return {}
	var loaded: Resource = ResourceLoader.load(reference.native_texture.path,"",ResourceLoader.CACHE_MODE_IGNORE)
	if not loaded is Image or loaded.get_format()!=Image.FORMAT_DXT5 or not loaded.has_mipmaps() \
		or loaded.get_width()!=int(texture.levels[0].width) or loaded.get_height()!=int(texture.levels[0].height) \
		or loaded.get_data().size()!=int(reference.native_texture.mip_bytes) \
		or int(reference.native_texture.three_copy_charge)!=loaded.get_data().size()*3+4096: return {}
	var decoded: Image = loaded.duplicate()
	if decoded.decompress()!=OK or decoded.get_data()!=FileAccess.get_file_as_bytes(reference.decoded_texture.path): return {}
	return {"native_texture":reference.native_texture.duplicate(true),"decoded_texture":reference.decoded_texture.duplicate(true)}


static func checks() -> bool:
	return not valid_input(null) and not valid_input({}) and not valid_input({"schema":1,"roots":16,"nodes":336,"rows":[]}) \
		and build_mesh(PackedByteArray(),0,0,Rect2(0,0,1,1),false).get_surface_count()==0 \
		and reuse_texture({},null).is_empty() and reuse_texture({"texture":{}},{"texture":{}}).is_empty() \
		and reuse_geometry({},null).is_empty() and reuse_geometry({},{"depth":0}).is_empty()


static func reuse_geometry(row: Dictionary, reference: Variant) -> Dictionary:
	if not reference is Dictionary: return {}
	if not row.get("texture") is Dictionary or not reference.get("texture") is Dictionary: return {}
	for key in ["depth","id","bounds","geometry_bounds","geometry","faces","ordinary_faces","formal","formal_source_ids"]:
		if not row.has(key) or row[key]!=reference.get(key): return {}
	if row.texture.bounds!=reference.texture.bounds or not NativeReview.binding(reference.get("native_geometry")): return {}
	var loaded: Resource = ResourceLoader.load(reference.native_geometry.path,"",ResourceLoader.CACHE_MODE_IGNORE)
	if loaded==null or not loaded.has_method("valid") or not loaded.valid() or loaded.meshes.size()!=2: return {}
	var identity: Variant = reference.native_geometry.get("canonical_identity")
	if not identity is Dictionary or identity.get("format")!="tokyo_mesh_component" \
		or int(identity.get("schema",-1))!=loaded.schema_version or int(identity.get("slots",-1))!=loaded.meshes.size() \
		or identity.get("source")!=loaded.source_hash or int(reference.native_geometry.get("bytes",-1))!=loaded.geometry_bytes: return {}
	if MeshCount.triangles(loaded.meshes[0])+MeshCount.triangles(loaded.meshes[1])+2!=int(row.faces): return {}
	return reference.native_geometry.duplicate(true)


static func run(path: String, expected_sha: String, output: String) -> int:
	if not NativeReview.binding({"path":path,"sha256":expected_sha}) or not output.is_absolute_path() or DirAccess.dir_exists_absolute(output): return 1
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not valid_input(data) or not NativeReview.binding(data.get("source")) or not NativeReview.binding(data.get("height_source")): return 1
	var reuse_path := OS.get_environment("AGL_TOKYO_HLOD_TEXTURE_REUSE")
	var reuse_sha := OS.get_environment("AGL_TOKYO_HLOD_TEXTURE_REUSE_SHA")
	var geometry_only := OS.get_environment("AGL_TOKYO_HLOD_GEOMETRY_REUSE")=="1"
	var reuse_rows: Dictionary = {}
	if not reuse_path.is_empty():
		if not NativeReview.binding({"path":reuse_path,"sha256":reuse_sha}): return 1
		var reference: Variant = JSON.parse_string(FileAccess.get_file_as_string(reuse_path))
		if not reference is Dictionary or reference.get("native_saved_roundtrip")!=true \
			or not reference.get("rows") is Array or reference.rows.size()!=336: return 1
		for previous: Dictionary in reference.rows:
			var key := "%s:%s" % [previous.get("depth"),previous.get("id")]
			if reuse_rows.has(key): return 1
			reuse_rows[key]=previous
	var retained_rows: Dictionary = {}
	if data.has("retained_catalog"):
		var contract := preload("res://scripts/rendering/tokyo_hlod_manifest.gd")
		if not NativeReview.binding(data.retained_catalog) or data.get("boundary_source_sha256")!=preload("res://scripts/rendering/tokyo_boundary_extent.gd").SOURCE_SHA: return 1
		var retained := contract.read(data.retained_catalog.path,data.retained_catalog.sha256)
		if retained.is_empty(): return 1
		retained_rows=retained.rows
	if DirAccess.make_dir_recursive_absolute(output)!=OK: return 1
	if data.get("reuse_parent_textures",false) and not geometry_only: return 1
	var rows: Array[Dictionary] = []
	var retained_count := 0
	for row: Dictionary in data.rows:
		if row.get("retained_native",false):
			var unchanged:=row.duplicate(true)
			unchanged.erase("retained_native")
			var key := "%d:%d" % [int(row.depth),int(row.id)]
			if unchanged!=retained_rows.get(key,{}): return 1
			for field: String in ["native_geometry","native_texture"]:
				if not NativeReview.binding(unchanged[field]): return 1
			rows.append(unchanged)
			retained_count+=1
			continue
		if not NativeReview.binding(row.get("geometry")) or not row.get("texture") is Dictionary \
			or not NativeReview.binding(row.texture.get("file")): return 1
		var raw := FileAccess.get_file_as_bytes(row.geometry.path)
		if raw.size()!=(int(row.faces)-2)*36: return 1
		var bounds_values: Array = row.texture.bounds
		var uv_bounds := Rect2(float(bounds_values[0]),float(bounds_values[1]),float(bounds_values[2])-float(bounds_values[0]),float(bounds_values[3])-float(bounds_values[1]))
		var name_value := "d%d-%03d" % [int(row.depth),int(row.id)]
		var geometry: Dictionary = {}
		if geometry_only:
			geometry=reuse_geometry(row,reuse_rows.get("%s:%s" % [row.depth,row.id]))
		else:
			var ordinary := build_mesh(raw,0,int(row.ordinary_faces),uv_bounds,false)
			var formal := build_mesh(raw,int(row.ordinary_faces),int(row.faces)-2-int(row.ordinary_faces),uv_bounds,true)
			if ordinary==null or formal==null or MeshCount.triangles(ordinary)+MeshCount.triangles(formal)+2!=int(row.faces): return 1
			geometry=ComponentWriter._save([ordinary,formal],expected_sha+":"+name_value,output.path_join(name_value+".res"))
		if geometry.is_empty(): return 1
		if (not reuse_path.is_empty() and not geometry_only) or (data.get("reuse_parent_textures",false) and int(row.depth)<2):
			var reused := reuse_texture(row,reuse_rows.get("%s:%s" % [row.depth,row.id]))
			if reused.is_empty(): return 1
			var reused_row := row.duplicate(true)
			reused_row["native_geometry"]=geometry
			reused_row.merge(reused)
			rows.append(reused_row)
			if rows.size()%16==0: print("[HLOD native pages] saved=",rows.size(),"/336 reused exact texture")
			continue
		var levels: Array = row.texture.levels
		var payload := FileAccess.get_file_as_bytes(row.texture.file.path)
		var image := Image.create_from_data(int(levels[0].width),int(levels[0].height),true,Image.FORMAT_RGBA8,payload)
		if image==null or image.get_data()!=payload: return 1
		var packed_image: Image = image.duplicate()
		if packed_image.compress_from_channels(Image.COMPRESS_S3TC,Image.USED_CHANNELS_RGBA)!=OK or packed_image.get_format()!=Image.FORMAT_DXT5: return 1
		var refinement := FlatBC3.patch_flat_blocks(image,packed_image)
		if refinement.is_empty(): return 1
		packed_image=Image.create_from_data(image.get_width(),image.get_height(),true,Image.FORMAT_DXT5,refinement.bytes)
		var texture_path := output.path_join(name_value+".image.res")
		if ResourceSaver.save(packed_image,texture_path,ResourceSaver.FLAG_COMPRESS)!=OK: return 1
		var restored: Resource = ResourceLoader.load(texture_path,"",ResourceLoader.CACHE_MODE_IGNORE)
		if not restored is Image or restored.get_data()!=packed_image.get_data() or restored.get_format()!=Image.FORMAT_DXT5: return 1
		var image_bytes: int = restored.get_data().size()
		var decoded: Image = restored.duplicate()
		if decoded.decompress()!=OK or decoded.get_data().size()!=payload.size(): return 1
		var decoded_path := output.path_join(name_value+".decoded.rgba8")
		var file := FileAccess.open(decoded_path,FileAccess.WRITE)
		if file==null: return 1
		file.store_buffer(decoded.get_data());file.close()
		var saved_row := row.duplicate(true)
		saved_row["native_geometry"]=geometry
		saved_row["native_texture"]={"path":texture_path,"sha256":FileAccess.get_sha256(texture_path),"format":int(Image.FORMAT_DXT5),
			"mip_bytes":image_bytes,"three_copy_charge":image_bytes*3+4096,"roundtrip":true,"patched_flat_blocks":refinement.patched_blocks}
		saved_row["decoded_texture"]={"path":decoded_path,"sha256":FileAccess.get_sha256(decoded_path)}
		rows.append(saved_row)
		if rows.size()%16==0: print("[HLOD native pages] saved=",rows.size(),"/336")
	var result := {"schema":1,"input_path":path,"input_sha256":expected_sha,"rows":rows,"roots":16,"nodes":336,
		"texture_reuse_path":reuse_path,"texture_reuse_sha256":reuse_sha,
		"min_scale":data.min_scale,"max_scale":data.max_scale,"native_saved_roundtrip":true,
		"texture_error_accepted":false,"native_visual_accepted":false,"runtime_integrated":false,"formal_runtime_coverage_verified":false}
	if data.has("boundary_source_sha256"):
		if retained_count!=283: return 1
		result["boundary_source_sha256"]=data.boundary_source_sha256
		if preload("res://scripts/rendering/tokyo_hlod_manifest.gd").normalize(result).is_empty(): return 1
	var destination := output.path_join("manifest.bin")
	var file := FileAccess.open(destination,FileAccess.WRITE)
	if file==null: return 1
	file.store_var(result,false);file.close()
	file=FileAccess.open(destination,FileAccess.READ)
	if file==null: return 1
	var saved: Variant = file.get_var(false);file.close()
	if saved!=result: return 1
	file=FileAccess.open(output.path_join("manifest.json"),FileAccess.WRITE)
	if file==null: return 1
	file.store_string(JSON.stringify(result,"",true,true));file.close()
	print("[HLOD native pages] complete=336 source=",expected_sha," separate new representation; NOT installed")
	return 0
