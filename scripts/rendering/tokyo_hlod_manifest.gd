extends RefCounted
const PREFETCH_RATIO := 0.50
const FRAME_SOLUTIONS := 16

static func resolve_native_page_limit(bench: bool, candidate: String) -> int:
	# 仅隔离测试可扩大原生切面；环境变量不能改变F5正式合同。
	return 32 if bench and candidate=="32" else 16

static func native_page_limit(work: Variant = null) -> int:
	if background_selection(work):
		var limit: Variant=work.get("native_page_limit",16)
		return int(limit) if typeof(limit)==TYPE_INT and limit in [16,32] else 0
	var bench := false
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--bench="): bench=true
	return resolve_native_page_limit(bench,OS.get_environment("AGL_TOKYO_NATIVE_PAGE_LIMIT"))


static func background_selection(work: Variant) -> bool:
	return work is Dictionary and work.get("background",false)==true


static func display_limit(work: Variant = null) -> int:
	# 后台使用加载期确定的预算，不读取环境或触碰进程级容量缓存。
	if background_selection(work):
		var limit: Variant=work.get("display_limit",-1)
		return int(limit) if typeof(limit)==TYPE_INT and limit>0 and limit<=192*1024*1024 else -1
	return preload("res://scripts/rendering/tokyo_hlod_cache_policy.gd").display_limit()


static func selection_context_valid(work: Dictionary) -> bool:
	return background_selection(work) and typeof(work.get("epoch"))==TYPE_INT and int(work.epoch)>=0 \
		and display_limit(work)>0 and native_page_limit(work)>0

## HLOD的新身份/预算适配；只读纯值，不借规范目录coverage，不同步载入全部贴图。
const ORIGIN := Vector2(-16300,-15700)
const SOURCE_COUNT := 189
const Boundary := preload("res://scripts/rendering/tokyo_boundary_extent.gd")
const Cut := preload("res://scripts/experiments/tokyo_spatial_cut.gd")
const MapProjection := preload("res://scripts/experiments/volume_projection.gd")
const PreparedCatalog := preload("res://scripts/rendering/tokyo_prepared_catalog.gd")


static func integer(value: Variant, low: int = 0, high: int = 1099511627776) -> bool:
	return typeof(value) in [TYPE_INT,TYPE_FLOAT] and is_finite(float(value)) and value==int(value) and value>=low and value<=high


static func sha(value: Variant) -> bool:
	if not value is String or value.length()!=64: return false
	for character in value:
		if character not in "0123456789abcdef": return false
	return true


static func numbers(value: Variant, count: int) -> bool:
	if not value is Array or value.size()!=count: return false
	for number in value:
		if typeof(number) not in [TYPE_INT,TYPE_FLOAT] or not is_finite(float(number)): return false
	return true


static func binding(value: Variant) -> bool:
	return value is Dictionary and value.get("path") is String \
		and (value.path.begins_with("res://") or value.path.is_absolute_path()) and sha(value.get("sha256"))


static func same_numbers(actual: Array, expected: Array) -> bool:
	if not numbers(actual,expected.size()): return false
	for index in expected.size():
		if float(actual[index])!=float(expected[index]): return false
	return true


static func texture_valid(row: Dictionary) -> bool:
	var texture: Variant = row.get("texture")
	var native: Variant = row.get("native_texture")
	if not texture is Dictionary or not binding(native) or not binding(texture.get("file")) \
		or native.get("roundtrip")!=true or (native.get("format")!=Image.FORMAT_DXT1 and native.get("format")!=Image.FORMAT_DXT5) \
		or not texture.get("levels") is Array or texture.levels.is_empty() or not numbers(texture.get("bounds"),4): return false
	var first: Variant = texture.levels[0]
	if not first is Dictionary or not integer(first.get("width"),1,16384) or not integer(first.get("height"),1,16384): return false
	var width := int(first.width)
	var height := int(first.height)
	var rgba_bytes := 0
	var compressed_bytes := 0
	var ended := false
	for level: Variant in texture.levels:
		if ended or not level is Dictionary or level.get("width")!=width or level.get("height")!=height \
			or level.get("offset")!=rgba_bytes or level.get("bytes")!=width*height*4: return false
		rgba_bytes+=width*height*4
		compressed_bytes+=ceili(width/4.0)*ceili(height/4.0)*(8 if native.format==Image.FORMAT_DXT1 else 16)
		ended=width==1 and height==1
		width=maxi(1,width/2);height=maxi(1,height/2)
	return ended and texture.get("bytes")==rgba_bytes and native.get("mip_bytes")==compressed_bytes \
		and native.get("three_copy_charge")==compressed_bytes*3+4096 \
		and texture.bounds[0]<=row.bounds[0] and texture.bounds[1]<=row.bounds[1] \
		and texture.bounds[2]>=row.bounds[2] and texture.bounds[3]>=row.bounds[3]


static func row_valid(row: Variant, boundary_sha: String = "") -> bool:
	if not row is Dictionary or not integer(row.get("depth"),0,2) or not integer(row.get("id"),0,255) \
		or not numbers(row.get("bounds"),4) or not row.get("children") is Array \
		or not integer(row.get("faces"),2) or not integer(row.get("ordinary_faces")) \
		or not integer(row.get("top_faces"),0,int(row.ordinary_faces)) \
		or not row.get("formal") is Array or not row.get("formal_source_ids") is Array: return false
	var depth := int(row.depth)
	var count := 4<<depth
	var id_value := int(row.id)
	if id_value>=count*count: return false
	var x := id_value%count
	var y := id_value/count
	var expected := Boundary.page_bounds(depth,id_value,boundary_sha)
	if expected.is_empty() or not same_numbers(row.bounds,expected): return false
	if row.get("parent")!=(-1 if depth==0 else (y/2)*(count/2)+x/2): return false
	var children: Array = []
	if depth<2:
		for dy in 2:
			for dx in 2: children.append((y*2+dy)*(count*2)+x*2+dx)
	if not same_numbers(row.children,children): return false
	var geometry: Variant = row.get("native_geometry")
	if not binding(geometry) or not integer(geometry.get("bytes")) or not geometry.get("canonical_identity") is Dictionary: return false
	var identity: Dictionary = geometry.canonical_identity
	if identity.get("format")!="tokyo_mesh_component" or identity.get("schema")!=1 or identity.get("slots")!=2 or not sha(identity.get("source")): return false
	var end := int(row.ordinary_faces)
	var ids: Array = []
	for formal: Variant in row.formal:
		if not formal is Dictionary or not integer(formal.get("source_id"),0,SOURCE_COUNT-1) \
			or formal.source_id in ids or formal.get("first_face")!=end or not integer(formal.get("faces"),1) \
			or typeof(formal.get("height")) not in [TYPE_INT,TYPE_FLOAT] or not is_finite(float(formal.height)) or formal.height<0: return false
		ids.append(formal.source_id)
		end+=int(formal.faces)
	if not same_numbers(ids,row.formal_source_ids) or end+2!=row.faces: return false
	var box_values: Variant = row.get("geometry_bounds")
	if end==0:
		if box_values!=[]: return false
	else:
		if not numbers(box_values,6): return false
		for axis in 3:
			if box_values[axis]>box_values[axis+3]: return false
	return texture_valid(row)


static func normalize(data: Variant) -> Dictionary:
	if not data is Dictionary or data.get("schema")!=1 or data.get("roots")!=16 or data.get("nodes")!=336 \
		or data.get("native_saved_roundtrip")!=true or not sha(data.get("input_sha256")) \
		or not data.get("rows") is Array or data.rows.size()!=336 \
		or typeof(data.get("min_scale")) not in [TYPE_INT,TYPE_FLOAT] or typeof(data.get("max_scale")) not in [TYPE_INT,TYPE_FLOAT] \
		or not is_finite(float(data.min_scale)) or not is_finite(float(data.max_scale)) or data.min_scale<0 or data.max_scale<=data.min_scale: return {}
	if data.has("middle_massing_recipe") and (not binding(data.middle_massing_recipe) or not is_equal_approx(float(data.max_scale),0.625)): return {}
	var rows: Dictionary = {}
	var mixed_scales := false
	var geometry: Dictionary = {}
	var textures: Dictionary = {}
	var formal_definitions: Dictionary = {}
	var owners := [{},{},{}]
	var boundary_sha: Variant = data.get("boundary_source_sha256","")
	if not boundary_sha is String or not Boundary.bounds(boundary_sha).has_area(): return {}
	for row: Variant in data.rows:
		if row is Dictionary and row.has("max_scale"):
			if typeof(row.max_scale) not in [TYPE_INT,TYPE_FLOAT] or not is_finite(float(row.max_scale)) or row.max_scale<=0 or row.max_scale>data.max_scale: return {}
			mixed_scales=mixed_scales or row.max_scale<data.max_scale
		if not row_valid(row,boundary_sha): return {}
		var key := "%d:%d" % [int(row.depth),int(row.id)]
		if rows.has(key): return {}
		rows[key]=row.duplicate(true)
		for formal: Dictionary in row.formal:
			var definition := [formal.height,formal.faces]
			if formal_definitions.has(int(formal.source_id)) and formal_definitions[int(formal.source_id)]!=definition: return {}
			formal_definitions[int(formal.source_id)]=definition
		for id_value in row.formal_source_ids:
			if owners[int(row.depth)].has(int(id_value)): return {}
			owners[int(row.depth)][int(id_value)]=key
		var mesh_path: String = row.native_geometry.path
		var native_identity: Dictionary = row.native_geometry.canonical_identity
		var mesh_descriptor := {"bytes":int(row.native_geometry.bytes),"canonical_identity":{"format":"tokyo_mesh_component","schema":1,"slots":2,"source":String(native_identity.source)},"sha256":row.native_geometry.sha256}
		if geometry.has(mesh_path) and geometry[mesh_path]!=mesh_descriptor: return {}
		geometry[mesh_path]=mesh_descriptor
		var image_path: String = row.native_texture.path
		var texture_descriptor := {"sha256":row.native_texture.sha256,"mip_bytes":int(row.native_texture.mip_bytes),
			"charge":int(row.native_texture.three_copy_charge),"width":int(row.texture.levels[0].width),"height":int(row.texture.levels[0].height),"format":int(row.native_texture.format)}
		if textures.has(image_path) and textures[image_path]!=texture_descriptor: return {}
		textures[image_path]=texture_descriptor
	for level in owners:
		if level.size()!=SOURCE_COUNT: return {}
	for row: Dictionary in rows.values():
		if int(row.depth)==2: continue
		var child_sources: Array = []
		for child in row.children:
			var child_key := "%d:%d" % [int(row.depth)+1,int(child)]
			if not rows.has(child_key): return {}
			child_sources.append_array(rows[child_key].formal_source_ids)
		var parent_sources: Array = row.formal_source_ids.duplicate()
		parent_sources.sort();child_sources.sort()
		if not same_numbers(parent_sources,child_sources): return {}
	var roots: Array[Dictionary] = []
	for root in 16: roots.append(tree(rows,0,root))
	var result := {"rows":rows,"roots":roots,"geometry":geometry,"textures":textures,"min_scale":float(data.min_scale),"max_scale":float(data.max_scale),"mixed_scales":mixed_scales,
		"input_sha256":data.input_sha256,"source_count":SOURCE_COUNT,"bounds":Boundary.bounds(boundary_sha),"formal_runtime_coverage_verified":false,"runtime_integrated":false}
	if data.has("middle_massing_recipe"): result["middle_massing_recipe"]=data.middle_massing_recipe.duplicate(true)
	return result


static func tree(rows: Dictionary, depth: int, id_value: int) -> Dictionary:
	var key := "%d:%d" % [depth,id_value]
	var row: Dictionary = rows[key]
	var bounds: Array = row.bounds
	var box_value := AABB(Vector3(bounds[0],0,bounds[1]),Vector3(bounds[2]-bounds[0],0,bounds[3]-bounds[1]))
	if not row.geometry_bounds.is_empty():
		var b: Array = row.geometry_bounds
		box_value=box_value.merge(AABB(Vector3(b[0],b[1],b[2]),Vector3(b[3]-b[0],b[4]-b[1],b[5]-b[2])))
	var result := {"key":key,"path":row.native_geometry.path,"texture_path":row.native_texture.path,
		"max_scale":float(row.get("max_scale",INF)),
		"triangles":[int(row.faces),0,0],"boxes":[box_value,AABB(),AABB()],
		"bytes":int(row.native_geometry.bytes)+int(row.native_texture.three_copy_charge)+288}
	if not row.children.is_empty():
		var children: Array[Dictionary] = []
		for child in row.children:
			var branch := tree(rows,depth+1,int(child))
			children.append(branch)
			box_value=box_value.merge(branch.coverage_box)
		result["children"]=children
	# 覆盖检查的父包络包含所有子档楼高；不能用简化父网格剔除更高的可见子楼。
	# 选择/绘制仍消费原boxes，资源、细节和费用完全不变。
	result["coverage_box"]=box_value
	return result


static func charges(catalog: Dictionary, keys: PackedStringArray, work: Variant = null) -> Dictionary:
	if keys.size()>16 or not catalog.get("rows") is Dictionary: return {}
	var meshes: Dictionary = {}
	var images: Dictionary = {}
	var used: Dictionary = {}
	var faces := 0
	for key in keys:
		if used.has(key) or not catalog.rows.has(key): return {}
		used[key]=true
		var row: Dictionary = catalog.rows[key]
		var parent := int(row.parent)
		var depth := int(row.depth)-1
		while depth>=0:
			if ("%d:%d" % [depth,parent]) in keys: return {}
			parent=int(catalog.rows["%d:%d" % [depth,parent]].parent)
			depth-=1
		meshes[row.native_geometry.path]=int(row.native_geometry.bytes)
		images[row.native_texture.path]=int(row.native_texture.three_copy_charge)
		faces+=int(row.faces)
	var mesh_bytes := 0
	var texture_bytes := 0
	for amount in meshes.values(): mesh_bytes+=int(amount)
	for amount in images.values(): texture_bytes+=int(amount)
	var ground_bytes := keys.size()*288
	return {"geometry_bytes":mesh_bytes,"texture_charge":texture_bytes,"ground_bytes":ground_bytes,
		"total_bytes":mesh_bytes+texture_bytes+ground_bytes,"faces":faces,"pages":keys.size(),
		"within_budget":faces<=240000 and mesh_bytes+texture_bytes+ground_bytes<=display_limit(work),"coverage_verified":false}


static func select(catalog: Dictionary, center: Vector2, scale: float, rotation: float, size: Vector2 = Vector2(1600,900), allow_finer: bool = false, byte_budget: int = 96*1024*1024, work: Variant = null, small_uploads: bool = false) -> Dictionary:
	if not catalog.get("roots") is Array or not is_finite(scale) or not is_finite(rotation) \
		or not center.is_finite() or not size.is_finite() or size.x<=0 or size.y<=0 \
		or byte_budget<0 or byte_budget>display_limit(work) or scale<=0 or (not allow_finer and scale<float(catalog.get("min_scale",INF))) or scale>float(catalog.get("max_scale",-INF)): return {}
	var background := background_selection(work)
	var canvas := Transform2D(rotation,Vector2.ZERO).scaled(Vector2.ONE*scale)
	canvas.origin=size*0.5-canvas*center
	var inverse := canvas.affine_inverse()
	var view := Rect2(inverse*Vector2.ZERO,Vector2.ZERO)
	for point in [Vector2(size.x,0),size,Vector2(0,size.y)]: view=view.expand(inverse*point)
	var ground := MapProjection.ground_basis(canvas,deg_to_rad(38))
	var ray := ground.inverse()*MapProjection.camera_basis(canvas,deg_to_rad(38)).z
	var roof := -Vector2(ray.x,ray.z)/ray.y
	# 预算只影响最终筛选；缓存由overlay持有，身份/视野/帧完全相同才复用。
	var identity: Dictionary = catalog.get("identity",{})
	var cacheable := work is Dictionary and not identity.is_empty()
	var key: Array = [identity.get("path",""),identity.get("sha256",""),center,scale,rotation,size,allow_finer]
	# 半池失败后会穿插多个保护带，再回到同一个全池查询；单槽缓存会重复求树。
	# 只保留本帧最多16份纯值候选，预算仍逐次pick，绝不跨帧复用可见性。
	var epoch := int(work.get("epoch",-1)) if background else Engine.get_process_frames()
	if cacheable and work.get("frame",-1)!=epoch:
		work["solutions"]={}
		work["frame"]=epoch
	var solutions: Dictionary=work.get("solutions",{}) if cacheable else {}
	var reused: bool = cacheable and solutions.has(key)
	var solved: Dictionary
	if reused:
		solved=solutions[key]
		work["reuses"]=int(work.get("reuses",0))+1
	else:
		var roots: Array[Dictionary] = []
		roots.assign(catalog.roots)
		if catalog.get("mixed_scales",false):
			var qualification_scale := minf(scale/PREFETCH_RATIO,float(catalog.max_scale)) if allow_finer else scale
			roots=qualified_roots(catalog,qualification_scale,work)
		solved=Cut.solve(roots,view,canvas,size,roof,Vector2.ZERO,16,not background)
		if not background and PerfBuckets.frame_trace_enabled: PerfBuckets.tick("tokyo_solver.hlod",int(solved.solver_usec))
		if cacheable:
			if solutions.size()>=FRAME_SOLUTIONS: solutions.erase(solutions.keys()[0])
			solutions[key]=solved
			work["solutions"]=solutions
			work["builds"]=int(work.get("builds",0))+1
	var result := Cut.pick(solved,byte_budget)
	if reused: result.solver_usec=0
	if small_uploads and result.within_budget:
		result=split_large_uploads(result,catalog,view,canvas,size,roof,byte_budget)
	var keys := PackedStringArray()
	for entry: Dictionary in result.entries: keys.append(entry.key)
	var charged := charges(catalog,keys,work)
	if charged.is_empty() or charged.faces!=result.triangles or charged.total_bytes>result.bytes: return {}
	result["charges"]=charged
	result["keys"]=keys
	return result




static func select_handoff(catalog: Dictionary, center: Vector2, scale: float, rotation: float, size: Vector2, budget: int, costs: Dictionary, work: Variant = null, allow_finer: bool = false, qualification_scale: float = 0.0, prepared_roots: Array[Dictionary] = []) -> Dictionary:
	# 求解的是旧页继续显示期间的新增物理费用；清晰度、16页和24万面仍照常。
	if costs.is_empty() or budget<0 or budget>display_limit(work) \
		or (not allow_finer and scale<float(catalog.min_scale)) or scale>float(catalog.max_scale): return {}
	var canvas := Transform2D(rotation,Vector2.ZERO).scaled(Vector2.ONE*scale)
	canvas.origin=size*0.5-canvas*center
	var inverse := canvas.affine_inverse()
	var view := Rect2(inverse*Vector2.ZERO,Vector2.ZERO)
	for point: Vector2 in [Vector2(size.x,0),size,Vector2(0,size.y)]: view=view.expand(inverse*point)
	var ray := MapProjection.ground_basis(canvas,deg_to_rad(38)).inverse()*MapProjection.camera_basis(canvas,deg_to_rad(38)).z
	var roof := -Vector2(ray.x,ray.z)/ray.y
	var roots := prepared_roots if not prepared_roots.is_empty() else handoff_roots(catalog,maxf(scale,qualification_scale),costs,work)
	var background := background_selection(work)
	var result := Cut.pick(Cut.solve(roots,view,canvas,size,roof,Vector2.ZERO,16,not background),budget)
	if not background and PerfBuckets.frame_trace_enabled: PerfBuckets.tick("tokyo_solver.handoff",int(result.solver_usec))
	if not result.within_budget: return {}
	var keys := PackedStringArray()
	for entry: Dictionary in result.entries:
		keys.append(entry.key)
		var row: Dictionary=catalog.rows[entry.key]
		# 显示/流送下游仍看到完整费用，折扣只用于此次交接求解。
		entry.bytes=int(row.native_geometry.bytes)+int(row.native_texture.three_copy_charge)+288
	var charged := charges(catalog,keys,work)
	if charged.is_empty() or not charged.within_budget or charged.faces!=result.triangles: return {}
	result["handoff_incremental_bytes"]=result.bytes
	result["bytes"]=charged.total_bytes
	result["charges"]=charged
	result["keys"]=keys
	return result


static func handoff_roots(catalog: Dictionary, scale: float, costs: Dictionary, work: Variant = null) -> Array[Dictionary]:
	# 同一次交接查询的四档保护带共享只读费用树；跨查询不缓存资源驻留状态。
	var roots: Array[Dictionary]=[]
	var source: Array=qualified_roots(catalog,scale,work) if catalog.get("mixed_scales",false) else catalog.roots
	for entry: Dictionary in source: roots.append(incremental_tree(entry,costs))
	return roots


static func incremental_tree(entry: Dictionary, costs: Dictionary) -> Dictionary:
	var result := entry.duplicate()
	# qualified_tree的失格哨兵不能因资源已在内存中而获得资格。
	if int(entry.bytes)<=192*1024*1024: result.bytes=int(costs.get(entry.key,entry.bytes))
	if entry.has("children"):
		var children: Array[Dictionary]=[]
		for child: Dictionary in entry.children: children.append(incremental_tree(child,costs))
		result.children=children
	return result


static func visible_subset(catalog: Dictionary, cut: Dictionary, center: Vector2, scale: float, rotation: float, size: Vector2, work: Variant = null, lead: Vector2 = Vector2.ZERO) -> Dictionary:
	# 只从原切面的最多16页中裁掉当前/前进视野联合区之外的页，不展开子页。
	if not lead.is_finite() or not cut.get("entries") is Array or cut.entries.is_empty(): return {}
	var subset := catalog.duplicate()
	var roots: Array[Dictionary]=[]
	for entry: Dictionary in cut.entries:
		var leaf := entry.duplicate()
		leaf.erase("children")
		roots.append(leaf)
	subset["roots"]=roots
	subset["min_scale"]=minf(float(catalog.min_scale),scale)
	# 旧切面子集不是原目录的完整树，不能命中同身份的完整树缓存。
	subset.erase("identity")
	var query_center := center+lead*0.5
	var query_size := size+(Transform2D(rotation,Vector2.ZERO).basis_xform(lead)*scale).abs()
	var result := select(subset,query_center,scale,rotation,query_size,false,display_limit(work),work)
	# 子集求解仅证明所留页的费用；调用方仍须向完整目录核验联合区覆盖。
	if not result.is_empty(): result["trim_lead_world"]=lead
	return result


static func split_large_uploads(original: Dictionary, catalog: Dictionary, view: Rect2, canvas: Transform2D, size: Vector2, roof: Vector2, byte_budget: int) -> Dictionary:
	# 完整父子替换，不增加预算、不改资产；失格子页沿qualified_tree的超预算哨兵被拒绝。
	var started := Time.get_ticks_usec()
	var result := original.duplicate()
	var entries: Array = original.entries.duplicate()
	var cursor := 0
	while cursor<entries.size():
		var entry: Dictionary = entries[cursor]
		var row: Dictionary = catalog.rows[entry.key]
		if int(row.native_texture.mip_bytes)<=4*1024*1024 or not entry.has("children") or entry.children.is_empty():
			cursor+=1;continue
		var children: Array[Dictionary] = []
		var faces := int(result.triangles)-int(entry.faces)
		var bytes := int(result.bytes)-int(entry.bytes)
		for child: Dictionary in entry.children:
			var visible := preload("res://scripts/experiments/tokyo_spatial_select.gd").visible(child,view,canvas,size,roof,Vector2.ZERO)
			if visible.faces<=0: continue
			children.append(visible)
			faces+=int(visible.faces);bytes+=int(visible.bytes)
		if children.is_empty() or entries.size()-1+children.size()>16 or faces>240000 or bytes>byte_budget:
			cursor+=1;continue
		entries.remove_at(cursor)
		for n in children.size(): entries.insert(cursor+n,children[n])
		result["triangles"]=faces;result["bytes"]=bytes
		# 下一轮只会进入更深一层，最多两级；保留全部投影可见子块。
	result["entries"]=entries;result["active"]=entries.size()
	result["solver_usec"]=int(result.solver_usec)+Time.get_ticks_usec()-started
	return result


static func qualified_roots(catalog: Dictionary, scale: float, work: Variant = null) -> Array[Dictionary]:
	# 静态资格与视野无关；相邻目录/当前及提前尺度交错时保留有限的精确资格区间。
	# 每个可见切面仍逐帧投影求解，绝不把旧相机的选页结果当作当前覆盖证明。
	var identity: Dictionary=catalog.get("identity",{})
	if work is Dictionary and work.get("prepared_catalogs") is Dictionary \
		and work.prepared_catalogs.has(identity.get("path","")):
		var prepared: Variant=work.prepared_catalogs[identity.get("path","")]
		var ready: Array[Dictionary]=[]
		if prepared is Dictionary: ready=PreparedCatalog.roots_at(prepared,scale)
		work["prepared_reuses"]=int(work.get("prepared_reuses",0))+1
		# Loading已逐来源校验；后台命中却无有效根时报告无解，不在游戏期间补做树构建。
		if not ready.is_empty() or background_selection(work): return ready
	var cacheable := work is Dictionary and not identity.is_empty()
	var key: Array=[identity.get("path",""),identity.get("sha256","")]
	var cache: Array=work.get("qualifications",[]) if cacheable else []
	for cached: Dictionary in cache:
		# qualified_tree使用严格大于；阈值等号必须留在左侧区间。
		if cached.key==key and scale>float(cached.lower) and scale<=float(cached.upper):
			work["qualification_reuses"]=int(work.get("qualification_reuses",0))+1
			return cached.roots
	var roots: Array[Dictionary]=[]
	for entry: Dictionary in catalog.roots: roots.append(qualified_tree(entry,scale))
	if cacheable:
		var lower := 0.0
		var upper := INF
		for row: Dictionary in catalog.rows.values():
			var limit := float(row.max_scale)
			if scale>limit: lower=maxf(lower,limit)
			else: upper=minf(upper,limit)
		if cache.size()>=FRAME_SOLUTIONS: cache.pop_front()
		cache.append({"key":key,"lower":lower,"upper":upper,"roots":roots})
		work["qualifications"]=cache
		work["qualification_builds"]=int(work.get("qualification_builds",0))+1
	return roots


static func qualified_tree(entry: Dictionary, scale: float) -> Dictionary:
	# 不合格父页不能成为可提交候选；子页仍可构成完整清晰切面，不扩大预算。
	var result := entry.duplicate()
	if scale>float(entry.max_scale): result.bytes=192*1024*1024+1+int(entry.bytes)
	if entry.has("children"):
		var children: Array[Dictionary] = []
		for child: Dictionary in entry.children: children.append(qualified_tree(child,scale))
		result.children=children
	return result


static func read(path: String, expected_sha: String) -> Dictionary:
	if not sha(expected_sha) or not FileAccess.file_exists(path) or FileAccess.get_sha256(path)!=expected_sha: return {}
	var result := normalize(JSON.parse_string(FileAccess.get_file_as_string(path)))
	if not result.is_empty(): result["identity"]={"path":path,"sha256":expected_sha,"input_sha256":result.input_sha256}
	return result


static func retained(catalog: Dictionary, cut: Dictionary, required: Dictionary, scale: float, allow_finer: bool = false, work: Variant = null) -> bool:
	if not is_finite(scale) or scale<=0 or (not allow_finer and scale<float(catalog.get("min_scale",INF))) \
		or scale>float(catalog.get("max_scale",-INF)) or not cut.get("keys") is PackedStringArray \
		or not required.get("keys") is PackedStringArray or cut.keys.is_empty() or required.keys.is_empty(): return false
	var charged := charges(catalog,cut.keys,work)
	if charged.is_empty() or not charged.within_budget or charges(catalog,required.keys,work).is_empty(): return false
	# 与select提前细化使用同一尺度，禁止空间覆盖优化撤销清晰度预取。
	var qualification_scale := minf(scale/PREFETCH_RATIO,float(catalog.max_scale)) if allow_finer else scale
	for key in cut.keys:
		if qualification_scale>float(catalog.rows[key].get("max_scale",INF)): return false
	# required是原求解器已证明完整的切面；这里只证明空间父子覆盖，不再逐叶计算可见性。
	for key in required.keys:
		var ancestor: String = key
		var found := false
		while not ancestor.is_empty():
			if ancestor in cut.keys: found=true;break
			var row: Dictionary = catalog.rows[ancestor]
			ancestor="%d:%d" % [int(row.depth)-1,int(row.parent)] if int(row.depth)>0 else ""
		if not found and not covered_key(catalog.rows,cut.keys,key): return false
	return true


static func covered_key(rows: Dictionary, selected: PackedStringArray, key: String) -> bool:
	if key in selected: return true
	var row: Dictionary = rows[key]
	if row.children.is_empty(): return false
	for child in row.children:
		if not covered_key(rows,selected,"%d:%d" % [int(row.depth)+1,int(child)]): return false
	return true
