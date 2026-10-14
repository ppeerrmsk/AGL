extends "res://scripts/rendering/tokyo_hlod_native.gd"
## 显式候选：新格建筑与原地表联合选择；原正式包不含grid_candidate，不启用此路径。
const Query := preload("res://scripts/experiments/tokyo_grid_query.gd")
const Select := preload("res://scripts/experiments/tokyo_spatial_select.gd")
const GridCoverage := preload("res://scripts/experiments/tokyo_grid_coverage.gd")
var _grid_data: Dictionary={}
var _grid_index: Dictionary={}
var _grid_entries: Dictionary={}
var _grid_ground: Array[Dictionary]=[]
var _grid_native_ground: Array[Dictionary]=[]
var _grid_fine: Dictionary={}
var _grid_variants: Dictionary={}
var _grid_refined_data: Dictionary={}
var _grid_coverage_index := preload("res://scripts/experiments/tokyo_grid_coverage_index.gd").new()
var _grid_subsets: Dictionary={}
var subset_stream: WeakRef
var subset_geometry: Dictionary={}
var _native_ground_only := false
## 仅离线基底可行性审计启用；正式读取合同尚不接受此候选。
var _resident_fine_basis := false


func read(value: Variant) -> bool:
	if not super.read(value): return false
	if not value.get("grid_native_ground_only",false) is bool: return false
	_native_ground_only=value.get("grid_native_ground_only",false)
	_grid_data.clear();_grid_entries.clear();_grid_ground.clear();_grid_index.clear()
	_grid_native_ground.clear()
	_grid_fine.clear();_grid_variants.clear();_grid_refined_data.clear()
	_grid_coverage_index=preload("res://scripts/experiments/tokyo_grid_coverage_index.gd").new()
	_grid_subsets.clear()
	var data: Variant=read_bound(value.get("grid_candidate"))
	if not data is Dictionary or not data.get("source_layers_complete",false) or data.get("configuration")!="lod5_full": return false
	var snapshot: Variant=read_bound(data.snapshot)
	if not snapshot is Dictionary or snapshot.catalog_sha256!=catalog_sha or snapshot.ground!=ground: return false
	if snapshot.configurations.lod5_full.roots!=_partition_roots.get("lod5_full",[]) or data.original_coverage!=coverage.lod5_full: return false
	if not _ground_roots.has("lod5_full"): return false
	var binding: Dictionary=data.joined_audit
	if not Contract.binding(binding) or FileAccess.get_sha256(binding.path)!=binding.sha256: return false
	var audit: Variant=JSON.parse_string(FileAccess.get_file_as_string(binding.path))
	if not audit is Dictionary or not audit.get("all_complete",false): return false
	var seen: Dictionary={}
	var joined_pages: Array=[]
	for record: Dictionary in audit.rows:
		var joined: Variant=read_bound(record.joined)
		if not joined is Dictionary or joined.snapshot!=data.snapshot: return false
		joined_pages.append_array(joined.pages)
		for page: Dictionary in joined.pages:
			var words: PackedStringArray=String(page.key).split(":")
			if words.size()!=3: return false
			var kind := int(words[0])
			if kind<0 or kind>1 or seen.has(page.path): return false
			if data.pages.get(page.path)!={"identity":page.canonical_identity,"sha256":page.sha256,"faces":page.faces,"box":page.box}: return false
			seen[page.path]=true
			var key := "grid/"+words[1]+":"+words[2]
			if not _grid_entries.has(key):
				_grid_entries[key]={"path":key,"boxes":[AABB(),AABB(),AABB()],"triangles":PackedInt32Array([0,0,0]),"bytes":0}
				pages[key]={"views":[null,null],"components":{},"bytes":0}
				_grid_fine[key]=[[],[]]
			if pages[key].views[kind]!=null: return false
			var identity := {"format":"tokyo_grid_view","schema":1,"configuration":"lod5_full","source":binding.sha256,"component":page.canonical_identity.source,"layer":kind}
			var component := {"path":page.path,"sha256":page.sha256,"bytes":page.bytes,"canonical_identity":page.canonical_identity}
			pages[key].views[kind]={"canonical_identity":identity,"components":{page.path:component},"bytes":page.bytes,"faces":page.faces,"box":page.box}
			pages[key].components[page.path]=component
			pages[key].bytes+=int(page.bytes)
			_grid_entries[key].bytes+=int(page.bytes)
			_grid_entries[key].boxes[kind]=page.box
			_grid_entries[key].triangles[kind]=page.faces
			for origin: Dictionary in page.origins:
				var part: Dictionary=origin.component
				var part_identity := {"format":"tokyo_grid_view","schema":1,"configuration":"lod5_full","source":binding.sha256,"component":part.canonical_identity.source,"layer":kind}
				_grid_fine[key][kind].append({"canonical_identity":part_identity,"components":{part.path:part},"bytes":part.bytes,"faces":origin.faces,"box":part.box})
	if seen.size()!=data.pages.size(): return false
	_grid_refined_data=GridCoverage.refinement_data(data,joined_pages)
	if _grid_refined_data.is_empty(): return false
	if value.has("grid_detail"):
		var details: Variant=read_bound(value.grid_detail)
		if not details is Dictionary: return false
		var expanded := preload("res://scripts/rendering/tokyo_grid_detail.gd").expand(_grid_fine,_grid_refined_data,details,value.grid_candidate)
		if expanded.is_empty(): return false
		_grid_fine=expanded.fine;_grid_refined_data=expanded.coverage
	if not _grid_coverage_index.configure(_grid_refined_data): return false
	if not _grid_coverage_index.compile_sources(): return false
	for key: String in _grid_entries:
		var views: Array=pages[key].views
		pages[key]["canonical_identity"]={"format":"tokyo_grid_view","schema":2,"configuration":"lod5_full","source":binding.sha256,
			"layers":[views[0].canonical_identity if views[0]!=null else null,views[1].canonical_identity if views[1]!=null else null]}
		# 固定四种格层组合，描述符只在载入时建立，移动时不累积新身份。
		for bits in range(1,4):
			var children: Array=[[],[]]
			var identities: Array=[[],[]]
			var components: Dictionary={}
			var total := 0
			for kind in 2:
				children[kind]=_grid_fine[key][kind] if bits&(1<<kind) else ([] if views[kind]==null else [views[kind]])
				for child: Dictionary in children[kind]:
					identities[kind].append(child.canonical_identity)
					components.merge(child.components)
					total+=int(child.bytes)
			var variant := key+"/fine%d"%bits
			pages[variant]={"canonical_identity":{"format":"tokyo_grid_view","schema":3,"configuration":"lod5_full","source":binding.sha256,"layers":identities},"views":children,"components":components,"bytes":total}
			_grid_variants[variant]={"base":key,"bits":bits}
	_grid_data=data
	_grid_index=Query.build(_grid_entries.values())
	for root: Dictionary in _ground_roots.lod5_full: _grid_ground.append(ground_only(root))
	for root: Dictionary in _partition_roots.lod5_full: _grid_native_ground.append(ground_only(root))
	if value.has("ground_components"):
		var adapted := preload("res://scripts/rendering/tokyo_ground_catalog.gd").attach(pages,_grid_ground,_grid_native_ground,value.ground_components)
		if adapted.is_empty(): return false
		pages=adapted.pages;_grid_ground=adapted.hybrid;_grid_native_ground=adapted.native
	if value.has("ground_partition"):
		if not value.ground_partition is Dictionary or not preload("res://scripts/rendering/tokyo_ground_partition.gd").attach(self,value.ground_partition): return false
	if value.has("simplified_ground_candidate"):
		if value.has("ground_partition") or not value.simplified_ground_candidate is Dictionary: return false
		if not preload("res://scripts/rendering/tokyo_simplified_ground.gd").attach(self,value.simplified_ground_candidate): return false
	return true


static func read_bound(binding: Variant) -> Variant:
	if not Contract.binding(binding) or FileAccess.get_sha256(binding.path)!=binding.sha256: return null
	var file := FileAccess.open(binding.path,FileAccess.READ)
	if file==null: return null
	return file.get_var(false)


static func ground_only(entry: Dictionary) -> Dictionary:
	var result := entry.duplicate()
	result["triangles"]=PackedInt32Array([0,0,int(entry.triangles[2])])
	if entry.has("children"):
		var children: Array[Dictionary]=[]
		for child: Dictionary in entry.children: children.append(ground_only(child))
		result["children"]=children
	return result


func select(center: Vector2, scale_value: float, rotation_value: float, size: Vector2, configuration_override: String="", byte_budget: int=96*1024*1024, resident: Dictionary={}) -> Dictionary:
	var configuration := "lod%d_full" % Archive.choose_level(-1,scale_value) if configuration_override.is_empty() else configuration_override
	if configuration!="lod5_full":
		var preferred := super.select(center,scale_value,rotation_value,size,configuration_override,byte_budget,resident)
		# 自动档预算失败才尝试已有的细档表示；显式档与驻留裁剪查询保持原合同。
		# 更细档不一定更贵：分格楼栋与地表能避开旧档的大块依赖。
		if configuration_override.is_empty() and resident.is_empty() and (preferred.is_empty() or not preferred.get("within_budget",false)):
			var fallback := select(center,scale_value,rotation_value,size,"lod5_full",byte_budget)
			if fallback.get("within_budget",false) and preload("res://scripts/rendering/tokyo_hlod_handoff.gd").native_qualified(fallback,scale_value):
				return fallback
		return preferred
	# 未证明完整驻留切面时拒绝缓存捷径，不把请求中资源当已提交。
	if not resident.is_empty() or _grid_index.is_empty(): return {}
	# 超过烘焙地表清晰度上限时回到原生地面，不撤销整张近景地图。
	var hybrid := not _native_ground_only and scale_value<=float(ground.limits.lod5_full)
	var ground_roots: Array[Dictionary]=_grid_ground if hybrid else _grid_native_ground
	var canvas := Transform2D(rotation_value,Vector2.ZERO).scaled(Vector2.ONE*scale_value)
	canvas.origin=size*0.5-canvas*center
	var inverse := canvas.affine_inverse()
	var view := Rect2(inverse*Vector2.ZERO,Vector2.ZERO)
	for corner in [Vector2(size.x,0),size,Vector2(0,size.y)]: view=view.expand(inverse*corner)
	var ray := MapProjection.ground_basis(canvas,deg_to_rad(38)).inverse()*MapProjection.camera_basis(canvas,deg_to_rad(38)).z
	var roof := -Vector2(ray.x,ray.z)/ray.y
	var entries: Array=Query.query(_grid_index,view,canvas,size,roof,Vector2.ZERO).entries
	var used_bytes := 0
	var faces := 0
	for entry: Dictionary in entries:
		used_bytes+=int(entry.bytes);faces+=int(entry.faces)
	var available := Contract.native_page_limit()-entries.size()
	var roots := 0
	for root: Dictionary in ground_roots: roots+=int(Select.visible(root,view,canvas,size,roof,Vector2.ZERO).faces>0)
	if available<=0 or roots>available or used_bytes>byte_budget: return {}
	var cut := Cut.choose(ground_roots,view,canvas,size,roof,Vector2.ZERO,available,byte_budget-used_bytes)
	var pieces: Dictionary={}
	if _resident_fine_basis or int(cut.triangles)+faces>240000:
		var refined := refine_entries(entries,view,canvas,size,roof,maxi(0,240000-int(cut.triangles)))
		entries=refined.entries;faces=refined.faces;used_bytes=refined.bytes;pieces=refined.pieces
		var subsets := subset_entries(entries)
		entries=subsets.entries;used_bytes=subsets.bytes;pieces=subsets.pieces
	cut.entries.append_array(entries)
	cut.triangles+=faces;cut.bytes+=used_bytes;cut.active+=entries.size()
	cut["within_budget"]=cut.triangles<=240000 and cut.bytes<=byte_budget
	cut["grid_candidate"]=true
	cut["grid_pieces"]=pieces
	cut["grid_projection"]={"view":view,"canvas":canvas,"size":size,"roof":roof}
	return decorate(cut,configuration,hybrid)


func refine_entries(entries: Array, view: Rect2, canvas: Transform2D, size: Vector2, roof: Vector2, face_budget: int) -> Dictionary:
	var choices: Array=[]
	var visible: Dictionary={}
	var total := 0
	for entry: Dictionary in entries:
		total+=int(entry.faces)
		visible[entry.path]=[PackedInt32Array(),PackedInt32Array()]
		for kind in 2:
			if not entry.mask[kind]: continue
			var fine_faces := 0
			for n in _grid_fine[entry.path][kind].size():
				var child: Dictionary=_grid_fine[entry.path][kind][n]
				var bounds := preload("res://scripts/rendering/tokyo_cells_overlay.gd").projected_layer_bounds(child.box,roof,Vector2.ZERO)
				if not preload("res://scripts/rendering/tokyo_cells_overlay.gd").intersects_view(bounds,view,canvas,size): continue
				visible[entry.path][kind].append(n);fine_faces+=int(child.faces)
			var saved := int(entry.triangles[kind])-fine_faces
			if saved>0 or _resident_fine_basis: choices.append({"key":entry.path,"kind":kind,"saved":saved,"score":float(saved)/maxi(1,visible[entry.path][kind].size()-1)})
	choices.sort_custom(func(a: Dictionary,b: Dictionary) -> bool: return a.score>b.score)
	var selected: Dictionary={}
	for choice: Dictionary in choices:
		if total<=face_budget and not _resident_fine_basis: break
		selected[choice.key]=int(selected.get(choice.key,0))|(1<<int(choice.kind))
		total-=int(choice.saved)
	var result: Array=[]
	var pieces: Dictionary={}
	var bytes := 0
	for original: Dictionary in entries:
		var entry := original.duplicate(true)
		if selected.has(original.path):
			var bits: int=selected[original.path]
			entry.path=original.path+"/fine%d"%bits
			entry.bytes=pages[entry.path].bytes
			entry["piece_indices"]=[PackedInt32Array(),PackedInt32Array()]
			entry.faces=0
			for kind in 2:
				if not entry.mask[kind]: continue
				entry.piece_indices[kind]=visible[original.path][kind] if bits&(1<<kind) else PackedInt32Array([0])
				for n: int in entry.piece_indices[kind]: entry.faces+=int(pages[entry.path].views[kind][n].faces)
			pieces[entry.path]=entry.piece_indices
		result.append(entry);bytes+=int(entry.bytes)
	return {"entries":result,"faces":total,"bytes":bytes,"pieces":pieces}


func subset_entries(entries: Array) -> Dictionary:
	var result: Array=[]
	var pieces: Dictionary={}
	var total := 0
	for original: Dictionary in entries:
		var entry := original.duplicate(true)
		if entry.has("piece_indices"):
			var parent: Dictionary=pages[entry.path]
			var row := {"canonical_identity":parent.canonical_identity.duplicate(true),"views":[[],[]],"components":{},"bytes":0}
			row.canonical_identity.layers=[[],[]]
			for kind in 2:
				for n: int in entry.piece_indices[kind]:
					var child: Dictionary=parent.views[kind][n]
					row.views[kind].append(child);row.canonical_identity.layers[kind].append(child.canonical_identity)
					row.components.merge(child.components);row.bytes+=int(child.bytes)
			var key := "grid-subset/"+JSON.stringify(row.canonical_identity).sha256_text()
			var accepted: bool=not row.components.is_empty() and (pages.has(key) or _grid_subsets.size()<128)
			if accepted and subset_stream!=null:
				var stream: Variant=subset_stream.get_ref()
				accepted=typeof(stream)==TYPE_OBJECT and is_instance_valid(stream) and stream.register_grid_subset(key,row)
			if accepted:
				if not pages.has(key):
					pages[key]=row
					_grid_variants[key]={"base":_grid_variants[entry.path].base,"bits":_grid_variants[entry.path].bits,"source_variant":entry.path,"source_indices":entry.piece_indices.duplicate(true)}
					_grid_subsets[key]=true
				if subset_stream!=null: subset_geometry[key]=pages[key]
				entry.path=key;entry.bytes=row.bytes
				for kind in 2: entry.piece_indices[kind]=PackedInt32Array(range(row.views[kind].size()))
			pieces[entry.path]=entry.piece_indices
		result.append(entry);total+=int(entry.bytes)
	return {"entries":result,"bytes":total,"pieces":pieces}


func retire_subsets(protected: PackedStringArray) -> void:
	if subset_stream==null: return
	var stream: Variant=subset_stream.get_ref()
	if typeof(stream)!=TYPE_OBJECT or not is_instance_valid(stream): return
	for path: String in stream.retire_grid_subsets(protected):
		pages.erase(path);_grid_variants.erase(path);_grid_subsets.erase(path);subset_geometry.erase(path)


func covers_visible_layers(cut: Dictionary, view: Rect2, canvas: Transform2D, logical: Vector2) -> bool:
	if not cut.get("grid_candidate",false): return super.covers_visible_layers(cut,view,canvas,logical)
	if cut.get("configuration")!="lod5_full" or not covers_ground(cut,view,canvas,logical): return false
	var selected: Dictionary={}
	for entry: Dictionary in cut.entries:
		var base: String=_grid_variants.get(entry.path,{}).get("base",entry.path)
		if not _grid_entries.has(base): continue
		if selected.has(base) or entry.boxes!=_grid_entries[base].boxes or entry.triangles!=_grid_entries[base].triangles: return false
		if _grid_variants.has(entry.path):
			if not entry.get("piece_indices") is Array or entry.piece_indices.size()!=2: return false
			for kind in 2:
				var seen: Dictionary={}
				for n: int in entry.piece_indices[kind]:
					if n<0 or n>=pages[entry.path].views[kind].size() or seen.has(n): return false
					seen[n]=true
		selected[base]=entry
	var ray := MapProjection.ground_basis(canvas,deg_to_rad(38)).inverse()*MapProjection.camera_basis(canvas,deg_to_rad(38)).z
	var roof := -Vector2(ray.x,ray.z)/ray.y
	for entry: Dictionary in Query.query(_grid_index,view,canvas,logical,roof,Vector2.ZERO).entries:
		if not selected.has(entry.path): return false
		var actual: Dictionary=selected[entry.path]
		for kind in 2:
			if not entry.mask[kind]: continue
			if not actual.mask[kind]: return false
			if not _grid_variants.has(actual.path): continue
			var variant: Dictionary=_grid_variants[actual.path]
			var source_path: String=variant.get("source_variant",actual.path)
			var actual_indices: Array=[]
			for n: int in actual.piece_indices[kind]: actual_indices.append(variant.source_indices[kind][n] if variant.has("source_indices") else n)
			for n in pages[source_path].views[kind].size():
				var child: Dictionary=pages[source_path].views[kind][n]
				var bounds := preload("res://scripts/rendering/tokyo_cells_overlay.gd").projected_layer_bounds(child.box,roof,Vector2.ZERO)
				if preload("res://scripts/rendering/tokyo_cells_overlay.gd").intersects_view(bounds,view,canvas,logical) and n not in actual_indices: return false
	return true


func covered(cut: Dictionary) -> PackedInt32Array:
	if not cut.get("grid_candidate",false): return super.covered(cut)
	var projection: Dictionary=cut.get("grid_projection",{})
	if projection.is_empty() or not cut.get("within_budget",false): return PackedInt32Array()
	var phase_started := Time.get_ticks_usec() if PerfBuckets.frame_trace_enabled else 0
	if not covers_visible_layers(cut,projection.view,projection.canvas,projection.size): return PackedInt32Array()
	if PerfBuckets.frame_trace_enabled: PerfBuckets.tick("tokyo_map_bind.visible_check",Time.get_ticks_usec()-phase_started)
	phase_started=Time.get_ticks_usec() if PerfBuckets.frame_trace_enabled else 0
	var committed: Dictionary={}
	for entry: Dictionary in cut.entries:
		if not _grid_entries.has(entry.path) and not _grid_variants.has(entry.path): continue
		for kind in 2:
			if not entry.mask[kind]: continue
			var children: Array=[]
			if _grid_variants.has(entry.path):
				for n: int in entry.piece_indices[kind]: children.append(pages[entry.path].views[kind][n])
			elif pages[entry.path].views[kind]!=null: children.append(pages[entry.path].views[kind])
			for child: Dictionary in children:
				for path: String in child.components: committed[path]={"identity":child.components[path].canonical_identity,"layers":1<<kind}
	if PerfBuckets.frame_trace_enabled: PerfBuckets.tick("tokyo_map_bind.committed_build",Time.get_ticks_usec()-phase_started)
	phase_started=Time.get_ticks_usec() if PerfBuckets.frame_trace_enabled else 0
	var result := _grid_coverage_index.covered_sources(committed,projection,cut.configuration,catalog.collision_sha256,catalog_sha)
	if PerfBuckets.frame_trace_enabled: PerfBuckets.tick("tokyo_map_bind.compiled_sources",Time.get_ticks_usec()-phase_started)
	return result
