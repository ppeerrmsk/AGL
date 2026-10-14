extends RefCounted
## 显式混合候选的纯值适配；原生楼栋及其coverage身份不变，地面单独计费。
const Contract := preload("res://scripts/rendering/tokyo_hlod_manifest.gd")
const PLANE_BYTES := 288


static func surfaces(entry: Dictionary) -> Array:
	# 多来源只由后续已校验的资源适配器注入；旧目录保持单面合同。
	if entry.has("ground_surfaces"): return entry.ground_surfaces
	return [entry.ground_replacement] if entry.has("ground_replacement") else []


static func read(binding: Variant, pages: Dictionary) -> Dictionary:
	if not Contract.binding(binding) or FileAccess.get_sha256(binding.path)!=binding.sha256: return {}
	var data: Variant=JSON.parse_string(FileAccess.get_file_as_string(binding.path))
	if not data is Dictionary or not data.get("stream_resource_format",false) or data.get("roof_geometry_baked",true) or not data.get("rows") is Dictionary or data.rows.is_empty(): return {}
	var rows: Dictionary={}
	var textures: Dictionary={}
	var limits: Dictionary={}
	for key: String in data.rows:
		var row: Dictionary=data.rows[key]
		if not pages.has(key) or not row.get("source") is Dictionary or not row.source.get("components") is Dictionary: return {}
		var original: Dictionary=pages[key].components
		if original.size()!=row.source.components.size(): return {}
		for path: String in original:
			if not row.source.components.has(path) or row.source.components[path].get("sha256")!=original[path].sha256 or row.source.components[path].get("bytes")!=original[path].bytes: return {}
		var texture: Variant=row.get("native_texture")
		var raster: Variant=row.get("raster")
		if not Contract.binding(texture) or not raster is Dictionary or not Contract.numbers(raster.get("bounds"),4) or not Contract.numbers(row.source.get("bounds"),4): return {}
		if not Contract.integer(texture.get("width"),1,16384) or not Contract.integer(texture.get("height"),1,16384) or not Contract.integer(texture.get("mip_bytes"),1) or texture.get("format")!=Image.FORMAT_DXT5 or texture.get("charge")!=int(texture.mip_bytes)*3+4096: return {}
		if not Contract.numbers([raster.get("max_scale"),raster.get("world_step")],2) or raster.max_scale<=0 or raster.world_step<=0 or raster.max_scale*raster.world_step>1.25: return {}
		if raster.get("premultiplied_alpha")!=true or row.get("compression_audit",{}).get("opaque_pixels_lost",-1)!=0 or row.get("compression_audit",{}).get("empty_pixels_filled",-1)!=0: return {}
		if not Contract.numbers([raster.get("flattened_plane_y")],1) or not Contract.numbers(raster.get("height_range"),2): return {}
		if float(raster.flattened_plane_y)!=float(raster.height_range[0]): return {}
		var b: Array=raster.bounds
		var native_bounds: Array=row.source.bounds
		var bounds := Rect2(b[0],b[1],b[2]-b[0],b[3]-b[1])
		var footprint := Rect2(native_bounds[0],native_bounds[1],native_bounds[2]-native_bounds[0],native_bounds[3]-native_bounds[1])
		if not bounds.has_area() or not footprint.has_area() or not bounds.encloses(footprint): return {}
		if absf(bounds.size.x-float(texture.width)*float(raster.world_step))>0.001 or absf(bounds.size.y-float(texture.height)*float(raster.world_step))>0.001: return {}
		var configuration: String=row.source.get("configuration","")
		if configuration not in ["lod3_full","lod4_full","lod5_full"]: return {}
		rows[key]={"texture":texture.path,"bounds":bounds,"footprint":footprint,"source_faces":int(row.source.triangles),"max_scale":float(raster.max_scale),"charge":int(texture.charge),"configuration":configuration,"plane_y":float(raster.flattened_plane_y)}
		# JSON数字为float；预算账本要求已校验的整数，不能把读入容器直接交给流送。
		var normalized: Dictionary=texture.duplicate()
		for field: String in ["width","height","format","mip_bytes","charge"]: normalized[field]=int(texture[field])
		textures[texture.path]=normalized
		if row.has("native_height"):
			var height := preload("res://scripts/rendering/tokyo_ground_height.gd").descriptor(row.native_height,Vector2i(int(texture.width),int(texture.height)))
			if height.is_empty() or not Contract.numbers(row.get("height_levels"),16): return {}
			for level: float in row.height_levels:
				if level < -1.0 or level > 1.0: return {}
			if textures.has(height.path) and textures[height.path]!=height: return {}
			textures[height.path]=height
			rows[key]["height_texture"]=height.path
			rows[key]["height_levels"]=PackedFloat32Array(row.height_levels)
			rows[key]["height_size"]=Vector2(texture.width,texture.height)
			rows[key].charge+=int(height.charge)
		limits[configuration]=minf(float(limits.get(configuration,INF)),float(raster.max_scale))
	return {"rows":rows,"textures":textures,"limits":limits}


static func tree(entry: Dictionary, rows: Dictionary) -> Dictionary:
	var result := entry.duplicate()
	if entry.has("children"):
		var children: Array[Dictionary]=[]
		for child: Dictionary in entry.children:
			var adapted := tree(child,rows)
			if adapted.is_empty(): return {}
			children.append(adapted)
		result["children"]=children
	if rows.has(entry.path):
		var row: Dictionary=rows[entry.path]
		# 来源包络与面数必须完全一致；未知地面保留原生，不以矩形填掉空洞。
		var box: AABB=entry.boxes[2]
		if int(entry.triangles[2])!=row.source_faces or Rect2(box.position.x,box.position.z,box.size.x,box.size.z)!=row.footprint: return {}
		if not row.has("plane_y") or not is_equal_approx(float(row.plane_y),box.position.y): return {}
		var triangles: Variant=entry.triangles.duplicate()
		triangles[2]=2
		result["triangles"]=triangles
		result["bytes"]=int(entry.bytes)+int(row.charge)+PLANE_BYTES
		result["ground_replacement"]=row
	return result
