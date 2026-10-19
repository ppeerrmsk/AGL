extends RefCounted
## 只读源清单的固定分区成本审计；不加载网格/纹理，不授予Visual或生产资格。
const Contract := preload("res://scripts/rendering/tokyo_hlod_manifest.gd")
const Spatial := preload("res://scripts/experiments/tokyo_spatial_select.gd")
const MapProjection := preload("res://scripts/experiments/volume_projection.gd")
const Handoff := preload("res://scripts/rendering/tokyo_hlod_handoff.gd")


static func leaves(entry: Dictionary, depth: int) -> Array[Dictionary]:
	var result: Array[Dictionary]=[]
	if depth==0 or not entry.has("children") or entry.children.is_empty():
		var leaf := entry.duplicate()
		leaf.erase("children")
		result.append(leaf)
	else:
		for child: Dictionary in entry.children: result.append_array(leaves(child,depth-1))
	return result


static func sample(entries: Array[Dictionary], catalog: Dictionary, center: Vector2, scale: float, angle: float, size: Vector2, conservative: bool = false, display_budget: int = 96*1024*1024) -> Dictionary:
	var canvas := Transform2D(angle,Vector2.ZERO).scaled(Vector2.ONE*scale)
	canvas.origin=size*0.5-canvas*center
	var inverse := canvas.affine_inverse()
	var view := Rect2(inverse*Vector2.ZERO,Vector2.ZERO)
	for point: Vector2 in [Vector2(size.x,0),size,Vector2(0,size.y)]: view=view.expand(inverse*point)
	var ground := MapProjection.ground_basis(canvas,deg_to_rad(38))
	var ray := ground.inverse()*MapProjection.camera_basis(canvas,deg_to_rad(38)).z
	var keys := PackedStringArray()
	var faces := 0
	var meshes := {}
	var textures := {}
	var qualified := true
	for entry: Dictionary in entries:
		var visible := Spatial.visible(entry,view,canvas,size,-Vector2(ray.x,ray.z)/ray.y,Vector2.ZERO)
		# 固定基础页也覆盖旋转视野外接矩形；额外地表面仍计入显示预算。
		var bounds: Array=catalog.rows[entry.key].bounds
		var page := Rect2(bounds[0],bounds[1],bounds[2]-bounds[0],bounds[3]-bounds[1])
		if conservative and page.intersects(view) and visible.faces<=0:
			# HLOD树把整页几何记在slot0；地表另绑定，不能沿用原生slot2语义。
			visible.mask[0]=true
			visible.faces=int(entry.triangles[0])
		if visible.faces<=0: continue
		keys.append(entry.key)
		faces+=int(visible.faces)
		qualified=qualified and scale<=float(entry.max_scale)
		var row: Dictionary=catalog.rows[entry.key]
		meshes[row.native_geometry.path]=int(row.native_geometry.bytes)
		textures[row.native_texture.path]=int(row.native_texture.three_copy_charge)
	var bytes := keys.size()*288
	for value: int in meshes.values(): bytes+=value
	for value: int in textures.values(): bytes+=value
	var clipped := view.intersection(catalog.bounds)
	var covered := keys.size()<=16 and Handoff.covers_view(catalog,{"keys":keys},clipped)
	return {"center":[center.x,center.y],"scale":scale,"angle":angle,"size":[size.x,size.y],
		"pages":keys.size(),"faces":faces,"bytes":bytes,"qualified":qualified,"covered":covered,"conservative":conservative,
		"display_budget":display_budget,"pass":qualified and covered and keys.size()<=16 and faces<=240000 and bytes<=display_budget}


static func run(output: String) -> int:
	if not output.begins_with("res://tmp/"): return 1
	var package_path := "res://resources/maps/tokyo_playable/m20/package.json"
	var extended := OS.get_environment("AGL_TOKYO_FOUNDATION_EXTENDED")=="1"
	var active_budget := preload("res://scripts/rendering/tokyo_hlod_cache_policy.gd").display_limit()
	if extended and active_budget!=192*1024*1024:
		push_error("Extended foundation audit requires the actual qualified 192MiB display policy")
		return 1
	if not OS.get_environment("AGL_TOKYO_HLOD_PACKAGE").is_empty():
		package_path=OS.get_environment("AGL_TOKYO_HLOD_PACKAGE")
		var expected := OS.get_environment("AGL_TOKYO_HLOD_PACKAGE_SHA")
		if not Contract.sha(expected) or FileAccess.get_sha256(package_path)!=expected: return 1
	var package: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(package_path))
	var report := {"schema":3,"diagnostic_only":true,"extended":extended,"active_display_budget":active_budget,"package_path":package_path,"package_sha":FileAccess.get_sha256(package_path),"partitions":[],"foundation_samples":[],"native":{},"unions":{}}
	var sets := {}
	for index in package.catalogs.size():
		var binding: Dictionary=package.catalogs[index]
		var catalog := Contract.read(binding.path,binding.sha256)
		if catalog.is_empty(): return 1
		for depth in 3:
			var entries: Array[Dictionary]=[]
			for root: Dictionary in catalog.roots: entries.append_array(leaves(root,depth))
			var resources := {}
			for entry: Dictionary in entries:
				var row: Dictionary=catalog.rows[entry.key]
				resources[row.native_geometry.path]=int(row.native_geometry.bytes)
				resources[row.native_texture.path]=int(row.native_texture.three_copy_charge)
			sets["%d:%d"%[index,depth]]=resources
			var bytes := 0
			for amount: int in resources.values(): bytes+=amount
			var result := {"catalog":index,"depth":depth,"resident_bytes":bytes,"samples":0,"fail":0,"max_faces":0,"max_bytes":0,"max_pages":0,"failures":[]}
			for scale: float in [maxf(float(binding.range[0])+0.000001,0.1666667),float(catalog.max_scale)]:
				if scale>float(catalog.max_scale): continue
				for x in range(-16000,16001,4000):
					for y in range(-16000,16001,4000):
						for angle: float in [0.0,deg_to_rad(-14),deg_to_rad(12)]:
							var item := sample(entries,catalog,Vector2(x,y),scale,angle,Vector2(1600,900))
							result.samples+=1
							result.fail+=int(not item.pass)
							result.max_faces=maxi(result.max_faces,item.faces)
							result.max_bytes=maxi(result.max_bytes,item.bytes)
							result.max_pages=maxi(result.max_pages,item.pages)
							if not item.pass and result.failures.size()<8: result.failures.append(item)
			report.partitions.append(result)
			print("[Foundation audit] catalog=%d depth=%d resident=%.2fMiB samples=%d fail=%d"%[index,depth,float(bytes)/(1024*1024),result.samples,result.fail])
			if [index,depth] not in [[3,0],[6,1],[5,1]] and not (extended and index==4 and depth in [1,2]): continue
			var lower: float={3:preload("res://scripts/rendering/tokyo_hlod_foundation.gd").LOWER,6:0.1944001,5:0.2500001,4:0.6250001}[index]
			var upper: float={3:0.1944,6:0.25,5:0.625,4:1.25}[index]
			for size: Vector2 in [Vector2(1600,900),Vector2(2100,900)]:
				var fixed := {"catalog":index,"depth":depth,"size":[size.x,size.y],"samples":0,"fail":0,"production_fail":0,"production_tested":extended or index in [3,6],"max_faces":0,"max_bytes":0,"max_pages":0,"failures":[]}
				for scale: float in [lower,(lower+upper)*0.5,upper]:
					for x in range(-16000,16001,2000):
						for y in range(-16000,16001,2000):
							for angle: float in [0.0,deg_to_rad(-14),deg_to_rad(12)]:
								var item := sample(entries,catalog,Vector2(x,y),scale,angle,size,true,192*1024*1024 if extended else 96*1024*1024)
								if extended or index in [3,6]:
									var actual := preload("res://scripts/rendering/tokyo_hlod_foundation.gd").select(catalog,entries,Vector2(x,y),scale,angle,size,192*1024*1024)
									fixed.production_fail+=int(actual.is_empty() or actual.get("bytes",-1)!=item.bytes or actual.get("triangles",-1)!=item.faces)
								fixed.samples+=1;fixed.fail+=int(not item.pass)
								fixed.max_faces=maxi(fixed.max_faces,item.faces)
								fixed.max_bytes=maxi(fixed.max_bytes,item.bytes)
								fixed.max_pages=maxi(fixed.max_pages,item.pages)
								if not item.pass and fixed.failures.size()<8: fixed.failures.append(item)
				report.foundation_samples.append(fixed)
				print("[Foundation audit] conservative catalog=%d width=%d samples=%d fail=%d"%[index,int(size.x),fixed.samples,fixed.fail])
	var native := preload("res://scripts/rendering/tokyo_hlod_native.gd").new()
	if not native.read(package.native): return 1
	if extended:
		var stack: Array=native._partition_roots.get("lod5_full",native.catalog.configurations.lod5_full).duplicate()
		var physical := {}
		while not stack.is_empty():
			var entry: Dictionary=stack.pop_back()
			if not entry.get("children",[]).is_empty(): stack.append_array(entry.children);continue
			for path: String in native.pages[entry.path].components: physical[path]=int(native.pages[entry.path].components[path].bytes)
		sets["native:leaf5"]=physical
	# 常见组合按物理路径去重，只记录成本，不凭成本证明可显示。
	var combinations: Array=[["3:0","6:1"],["3:0","6:1","5:1"],["3:0","6:1","5:1","4:2"],["3:2","6:2","5:2"]]
	if extended:
		combinations.append_array([["3:0","6:1","5:1","4:1"],["native:leaf5","3:0","6:1","5:1"],["native:leaf5","3:0","6:1","5:1","4:1"]])
	for names: Array in combinations:
		var physical := {}
		for name_value: String in names:
			for path: String in sets[name_value]:
				if physical.has(path) and physical[path]!=sets[name_value][path]: return 1
				physical[path]=sets[name_value][path]
		var bytes := 0
		for amount: int in physical.values(): bytes+=amount
		report.unions[str(names)]={"bytes":bytes,"resources":physical.size()}
	for configuration: String in native.catalog.configurations:
		var physical := {}
		var by_slot: Array=[{},{},{}]
		for root: Dictionary in native.catalog.configurations[configuration]:
			for path: String in native.pages[root.path].components: physical[path]=native.pages[root.path].components[path].bytes
			for slot in 3:
				var path: String=native.pages[root.path].mapping[slot][0]
				by_slot[slot][path]=native.pages[root.path].components[path].bytes
		var bytes := 0
		var slots: Array=[]
		for amount: int in physical.values(): bytes+=amount
		for slot: Dictionary in by_slot:
			var amount := 0
			for value: int in slot.values(): amount+=value
			slots.append({"bytes":amount,"resources":slot.size()})
		report.native[configuration]={"bytes":bytes,"resources":physical.size(),"slots":slots}
	DirAccess.make_dir_recursive_absolute(output.get_base_dir())
	var file := FileAccess.open(output,FileAccess.WRITE)
	if file==null: return 1
	file.store_string(JSON.stringify(report,"\t"));file.close()
	return 0
