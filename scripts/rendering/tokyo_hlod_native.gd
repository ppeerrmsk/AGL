extends RefCounted
## 近景只适配已验证组件，不新增加载池、几何副本或放宽切面预算。
const Contract := preload("res://scripts/rendering/tokyo_hlod_manifest.gd")
const Catalog := preload("res://scripts/rendering/tokyo_canonical_catalog.gd")
const Components := preload("res://scripts/rendering/tokyo_component_manifest.gd")
const Coverage := preload("res://scripts/experiments/tokyo_source_coverage.gd")
const Cut := preload("res://scripts/experiments/tokyo_spatial_cut.gd")
const MapProjection := preload("res://scripts/experiments/volume_projection.gd")
const Archive := preload("res://scripts/rendering/tokyo_volume_archive.gd")
var catalog: Resource
var catalog_sha := ""
var pages: Dictionary = {}
var coverage: Dictionary = {}
var _partition_roots: Dictionary={}
var _partition_pages: Dictionary={}
var _selection_frame := -1
var _selection_solutions: Dictionary = {}
var solver_builds := 0
var solver_reuses := 0
var solver_peak: Dictionary={}
var ground: Dictionary={}
var _ground_roots: Dictionary={}
var selection_context: Dictionary={}
var _selection_configurations: Dictionary={}
var _prefetch_ancestors: Dictionary={}
var _resident_component_ancestors: Dictionary={}
var _resident_empty_ancestors: Dictionary={}
var _resident_index_ready := false
var read_stages_usec: Dictionary={}


func retirement_data() -> Array:
	var values: Array=[pages,coverage,_partition_roots,_partition_pages,ground,_ground_roots,
		_selection_configurations,_prefetch_ancestors,_resident_component_ancestors,_resident_empty_ancestors,
		selection_context,_selection_solutions]
	if catalog!=null:
		values.append_array([catalog.configurations,catalog.descriptors,catalog.regional_extension,catalog.full_grid])
	return values


func read(value: Variant) -> bool:
	read_stages_usec={}
	var started := Time.get_ticks_usec()
	_resident_index_ready=false;_resident_component_ancestors={};_resident_empty_ancestors={}
	selection_context={};_selection_configurations={}
	_partition_roots={}
	_partition_pages.clear()
	_selection_frame=-1
	_selection_solutions.clear()
	solver_peak.clear()
	ground={};_ground_roots={}
	if not value is Dictionary or not Contract.binding(value.get("catalog")) or not Contract.binding(value.get("components")) or not value.get("coverage") is Dictionary: return false
	catalog=load(value.catalog.path)
	read_stages_usec["catalog_load"]=Time.get_ticks_usec()-started
	started=Time.get_ticks_usec()
	if not catalog is Catalog or catalog.schema_version!=2 or not catalog.valid(): return false
	read_stages_usec["catalog_validate"]=Time.get_ticks_usec()-started
	started=Time.get_ticks_usec()
	catalog_sha=value.catalog.sha256
	var component_data := Components.read(value.components.path,catalog,catalog_sha)
	if component_data.is_empty(): return false
	pages=component_data.pages
	read_stages_usec["components"]=Time.get_ticks_usec()-started
	started=Time.get_ticks_usec()
	for configuration: String in Catalog.CONFIGURATIONS:
		var binding: Variant = value.coverage.get(configuration)
		if not Contract.binding(binding): return false
		var file := FileAccess.open(binding.path,FileAccess.READ)
		if file==null: return false
		var data: Variant = file.get_var(false)
		file.close()
		if not data is Dictionary or data.get("schema")!=1 or not data.get("verified",false) or data.get("configuration")!=configuration \
			or data.get("catalog_sha256")!=catalog_sha or data.get("collision_sha256")!=catalog.collision_sha256 or data.get("owners_sha256")!=catalog.owners_sha256 \
			or not data.get("pages") is Dictionary or data.pages.size()!=catalog.pages_per_configuration() \
			or not data.get("sources") is Dictionary or data.sources.size()!=catalog.gameplay_source_count(): return false
		for path: String in data.pages:
			if data.pages[path].get("identity")!=catalog.descriptors.get(path,{}).get("canonical_identity"): return false
		coverage[configuration]=data
	read_stages_usec["coverage"]=Time.get_ticks_usec()-started
	started=Time.get_ticks_usec()
	if value.has("partition_override"):
		var adapted := preload("res://scripts/rendering/tokyo_partition_override.gd").read(value.partition_override,catalog,catalog_sha,pages,coverage)
		if adapted.is_empty(): return false
		_partition_roots=adapted.roots
		_partition_pages=adapted.pages
		pages.merge(_partition_pages)
		for configuration: String in adapted.get("coverage",{}): coverage[configuration]=adapted.coverage[configuration]
	read_stages_usec["partitions"]=Time.get_ticks_usec()-started
	started=Time.get_ticks_usec()
	if value.has("ground_override"):
		# 等价完整三层分区暂不接受另外替换地表的混合协议。
		if value.get("partition_override",{}).get("allow_lossless_alternatives",false): return false
		ground=preload("res://scripts/rendering/tokyo_native_ground.gd").read(value.ground_override,pages)
		if ground.is_empty(): return false
		for configuration: String in ground.limits:
			var roots: Array[Dictionary]=[]
			for entry: Dictionary in _partition_roots.get(configuration,catalog.configurations[configuration]):
				var adapted := preload("res://scripts/rendering/tokyo_native_ground.gd").tree(entry,ground.rows)
				if adapted.is_empty(): return false
				roots.append(adapted)
			_ground_roots[configuration]=roots
	read_stages_usec["ground"]=Time.get_ticks_usec()-started
	started=Time.get_ticks_usec()
	_prepare_prefetch_ancestors()
	if preload("res://scripts/rendering/tokyo_installed_map.gd").runtime_option("AGL_TOKYO_RETURN_CACHE")=="1": prepare_resident_index()
	read_stages_usec["indices"]=Time.get_ticks_usec()-started
	return true


func selection_snapshot() -> Dictionary:
	# 只在加载/换源时复制；不把目录Resource、覆盖认证或完整组件元数据带进任务。
	var configurations := _configurations()
	if configurations.is_empty(): return {}
	var selection_pages := {}
	for path: String in pages:
		var row: Dictionary=pages[path]
		var parts := {}
		for physical: String in row.get("components",{path:row}):
			parts[physical]=true
		selection_pages[path]={"components":parts}
	var snapshot := {"schema":1,"catalog_sha":catalog_sha,"configurations":configurations,
		"partition_roots":_partition_roots,"ground_roots":_ground_roots,
		"ground_limits":ground.get("limits",{}),"pages":selection_pages}
	return snapshot.duplicate(true) if _selection_value_is_pure(snapshot) else {}


func configure_selection_snapshot(snapshot: Dictionary, context: Dictionary) -> bool:
	_resident_index_ready=false;_resident_component_ancestors={};_resident_empty_ancestors={}
	# 此实例只属于单个后台规划器；原实例与调用方的来源容器之后都不能改变它。
	if snapshot.get("schema")!=1 or not Contract.selection_context_valid(context) \
		or not _selection_value_is_pure(snapshot) or not _selection_value_is_pure(context): return false
	for field: String in ["configurations","partition_roots","ground_roots","ground_limits","pages"]:
		if not snapshot.get(field) is Dictionary: return false
	if snapshot.configurations.is_empty(): return false
	for field: String in ["configurations","partition_roots","ground_roots"]:
		for key: Variant in snapshot[field]:
			if not key is String or not snapshot[field][key] is Array or snapshot[field][key].is_empty(): return false
	for configuration: String in snapshot.ground_roots:
		if not snapshot.configurations.has(configuration) or not snapshot.ground_limits.has(configuration): return false
		var limit: Variant=snapshot.ground_limits[configuration]
		if typeof(limit) not in [TYPE_FLOAT,TYPE_INT] or not is_finite(float(limit)) or float(limit)<=0.0: return false
	var source := snapshot.duplicate(true)
	catalog=null
	catalog_sha=String(source.get("catalog_sha",""))
	_selection_configurations=source.configurations
	_partition_roots=source.partition_roots
	_ground_roots=source.ground_roots
	ground={"limits":source.ground_limits} if not source.ground_limits.is_empty() else {}
	pages=source.pages
	coverage={};_partition_pages={}
	selection_context=context.duplicate(true)
	_selection_frame=-1;_selection_solutions={}
	solver_builds=0;solver_reuses=0;solver_peak={}
	_prepare_prefetch_ancestors()
	return true


func fork_selection(context: Dictionary) -> RefCounted:
	# 同一个工作器串行执行当前/预测查询，只共享已经独占复制的只读地图表。
	# 查询上下文、求解缓存与计数各自独立；不共享主线程的目录 Resource。
	if catalog!=null or _selection_configurations.is_empty() or not Contract.selection_context_valid(context): return null
	var fork: RefCounted=get_script().new()
	fork.catalog_sha=catalog_sha
	fork._selection_configurations=_selection_configurations
	fork._partition_roots=_partition_roots
	fork._ground_roots=_ground_roots
	fork.ground=ground
	fork.pages=pages
	fork._prefetch_ancestors=_prefetch_ancestors
	fork._resident_component_ancestors=_resident_component_ancestors
	fork._resident_empty_ancestors=_resident_empty_ancestors
	fork._resident_index_ready=_resident_index_ready
	fork.selection_context=context.duplicate(true)
	return fork


func _prepare_prefetch_ancestors() -> void:
	# 无损分区的父子是不同资源；缩远重新合页时也要提前准备父页。
	# 只在加载/工作器初始化建立纯值索引，不在每次预测扫描整棵地图树。
	_prefetch_ancestors={}
	for roots: Array in _partition_roots.values():
		var stack: Array=[]
		for entry: Dictionary in roots: stack.append([entry,[]])
		while not stack.is_empty():
			var item: Array=stack.pop_back()
			var entry: Dictionary=item[0]
			var ancestors: Array=item[1]
			if not ancestors.is_empty(): _prefetch_ancestors[entry.path]=ancestors
			var next := ancestors.duplicate()
			# 大父页会挤掉必要细页；小父页只补充同池中的可选合并表示。
			if int(entry.bytes)<=1048576: next.append({"path":entry.path,"bytes":entry.bytes})
			for child: Dictionary in entry.get("children",[]): stack.append([child,next])
			for alternative: Array in entry.get("alternative_children",[]):
				for child: Dictionary in alternative: stack.append([child,next])


func prepare_resident_index() -> void:
	# Loading 建立物理组件→可能包含已驻留候选的祖先。共享组件、所有LOD、
	# 地表替代树和无损替代分支都取并集；宁可多查，不能把缺块当不可见。
	_resident_component_ancestors={};_resident_empty_ancestors={}
	var forests: Array=[]
	forests.append_array(_configurations().values())
	forests.append_array(_partition_roots.values());forests.append_array(_ground_roots.values())
	for roots: Array in forests:
		var stack: Array=[]
		for entry: Dictionary in roots: stack.append([entry,PackedStringArray()])
		while not stack.is_empty():
			var item: Array=stack.pop_back()
			var entry: Dictionary=item[0]
			var ancestors: PackedStringArray=item[1].duplicate()
			ancestors.append(entry.path)
			if pages.has(entry.path):
				var parts: Dictionary=pages[entry.path].get("components",{entry.path:{}})
				if parts.is_empty():
					for path: String in ancestors: _resident_empty_ancestors[path]=true
				for part: String in parts:
					var known: Dictionary=_resident_component_ancestors.get(part,{})
					for path: String in ancestors: known[path]=true
					_resident_component_ancestors[part]=known
			for child: Dictionary in entry.get("children",[]): stack.append([child,ancestors])
			for alternative: Array in entry.get("alternative_children",[]):
				for child: Dictionary in alternative: stack.append([child,ancestors])
	_resident_index_ready=true


func resident_possible_nodes(meshes: Dictionary) -> Dictionary:
	# 只遍历实际缓存；这不是ready证明，完整组件/贴图/资格仍由原函数核验。
	var possible := _resident_empty_ancestors.duplicate()
	for part: String in meshes:
		for path: String in _resident_component_ancestors.get(part,{}): possible[path]=true
	return possible


func prefetch_ancestor_requests(cut: Dictionary, budget: int) -> Array[Dictionary]:
	var result: Array[Dictionary]=[]
	if budget<=0 or not cut.get("ground_images",PackedStringArray()).is_empty(): return result
	var candidates := {}
	for key: String in cut.get("keys",[]):
		for ancestor: Dictionary in _prefetch_ancestors.get(key,[]):
			if ancestor.path not in cut.keys: candidates[ancestor.path]=int(ancestor.bytes)
	var paths := candidates.keys()
	paths.sort_custom(func(a: String,b: String) -> bool: return candidates[a]>candidates[b] if candidates[a]!=candidates[b] else a<b)
	for path: String in paths:
		if int(candidates[path])>budget: continue
		budget-=int(candidates[path]);result.append({"mesh":path,"image":""})
	return result


func _configurations() -> Dictionary:
	if not _selection_configurations.is_empty(): return _selection_configurations
	return catalog.configurations if catalog!=null else {}


static func _selection_value_is_pure(value: Variant, depth: int = 0) -> bool:
	if depth>32 or typeof(value) in [TYPE_OBJECT,TYPE_CALLABLE,TYPE_SIGNAL,TYPE_RID]: return false
	if value is Dictionary:
		for key: Variant in value:
			if not _selection_value_is_pure(key,depth+1) or not _selection_value_is_pure(value[key],depth+1): return false
	elif value is Array:
		for item: Variant in value:
			if not _selection_value_is_pure(item,depth+1): return false
	return true


func ground_configuration(scale_value: float) -> String:
	# 远景已有合格表示；不要为看不清的近景地面反复求树、上传纹理。
	if not is_finite(scale_value) or scale_value<=float(Archive.SCALES[2]): return ""
	for level in [3,4,5]:
		var configuration := "lod%d_full" % level
		if _ground_roots.has(configuration) and scale_value<=float(ground.limits[configuration]) and scale_value<=float(Archive.SCALES[level]): return configuration
	return ""


func select(center: Vector2, scale_value: float, rotation_value: float, size: Vector2, configuration_override: String = "", byte_budget: int = 96*1024*1024, resident: Dictionary = {}) -> Dictionary:
	var configuration := "lod%d_full" % Archive.choose_level(-1,scale_value) if configuration_override.is_empty() else configuration_override
	var configurations := _configurations()
	if not configurations.has(configuration): return {}
	var canvas := Transform2D(rotation_value,Vector2.ZERO).scaled(Vector2.ONE*scale_value)
	canvas.origin=size*0.5-canvas*center
	var inverse := canvas.affine_inverse()
	var view := Rect2(inverse*Vector2.ZERO,Vector2.ZERO)
	for corner in [Vector2(size.x,0),size,Vector2(0,size.y)]: view=view.expand(inverse*corner)
	var ground := MapProjection.ground_basis(canvas,deg_to_rad(38))
	var ray := ground.inverse()*MapProjection.camera_basis(canvas,deg_to_rad(38)).z
	var roots: Array[Dictionary] = []
	roots.assign(_partition_roots.get(configuration,configurations[configuration]))
	var hybrid := _ground_roots.has(configuration) and scale_value<=float(self.ground.limits[configuration])
	if hybrid: roots.assign(_ground_roots[configuration])
	if not resident.is_empty():
		var context := {"view":view,"canvas":canvas,"size":size,"roof":-Vector2(ray.x,ray.z)/ray.y,
			"geometry":pages,"meshes":resident.meshes,"textures":resident.textures}
		if _resident_index_ready: context["possible"]=resident_possible_nodes(resident.meshes)
		for index in roots.size(): roots[index]=preload("res://scripts/rendering/tokyo_hlod_cached_cut.gd").native_tree(roots[index],context)
	# 半池/全池只改变最终筛选；同帧同视野不重复求整棵候选树。
	# 同帧允许保护带查询穿插；不缓存画面或Resource，跨帧整批失效。
	var background := Contract.background_selection(selection_context)
	var page_limit := Contract.native_page_limit(selection_context)
	if page_limit<=0: return {}
	var key: Array = [configuration,center,scale_value,rotation_value,size,hybrid,page_limit]
	var frame := int(selection_context.get("epoch",-1)) if background else Engine.get_process_frames()
	if frame!=_selection_frame:
		_selection_solutions.clear()
		_selection_frame=frame
	# 驻留集合可能同帧变化，不与普通选择或先前缓存状态共用候选缓存。
	var reused := resident.is_empty() and _selection_solutions.has(key)
	var solution: Dictionary={}
	if not reused:
		solution=Cut.solve(roots,view,canvas,size,-Vector2(ray.x,ray.z)/ray.y,Vector2.ZERO,page_limit,not background)
		if resident.is_empty():
			if _selection_solutions.size()>=Contract.FRAME_SOLUTIONS: _selection_solutions.erase(_selection_solutions.keys()[0])
			_selection_solutions[key]=solution
		if not background and PerfBuckets.frame_trace_enabled:
			var solved: Dictionary=solution
			PerfBuckets.tick("tokyo_solver.native",int(solved.solver_usec))
			PerfBuckets.mark_frame_event("tokyo_native_solve")
			if int(solved.solver_usec)>int(solver_peak.get("usec",0)):
				solver_peak={"usec":solved.solver_usec,"configuration":configuration,"center":center,"scale":scale_value,"rotation":rotation_value,"size":size,"hybrid":hybrid,"visited":solved.visited,"frontier_states":solved.frontier.size()}
		solver_builds+=1
	else:
		solver_reuses+=1
		solution=_selection_solutions[key]
	var cut := Cut.pick(solution,byte_budget)
	if reused: cut.solver_usec=0
	return decorate(cut,configuration,hybrid)


func select_limited(center: Vector2, scale_value: float, angle: float, size: Vector2, configuration: String,
		page_limit: int, face_limit: int, byte_limit: int) -> Dictionary:
	# 只缩小既有选择上限；复用同次求解的完整前沿，不读取网格、不改来源与覆盖。
	if page_limit<1 or page_limit>16 or face_limit<1 or face_limit>240000 or byte_limit<1 or byte_limit>96*1024*1024: return {}
	var original := select(center,scale_value,angle,size,configuration,byte_limit)
	if original.is_empty(): return {}
	var hybrid := _ground_roots.has(configuration) and scale_value<=float(ground.limits[configuration])
	var key: Array=[configuration,center,scale_value,angle,size,hybrid,Contract.native_page_limit(selection_context)]
	if not _selection_solutions.has(key): return {}
	var solved: Dictionary=_selection_solutions[key].duplicate()
	var frontier: Array[Dictionary]=[]
	for state: Dictionary in solved.frontier:
		if state.active<=page_limit and state.faces<=face_limit and state.bytes<=byte_limit: frontier.append(state)
	if frontier.is_empty(): return {}
	solved.frontier=frontier
	return decorate(Cut.pick(solved,byte_limit),configuration,hybrid)


static func decorate(cut: Dictionary, configuration: String, hybrid: bool) -> Dictionary:
	cut["keys"]=PackedStringArray()
	cut["configuration"]=configuration
	cut["charges"]={"ground_bytes":0}
	cut["masks"]=[]
	cut["ground_images"]=PackedStringArray()
	cut["ground_max_scale"]=INF
	cut["ground_tree"]=hybrid
	for entry: Dictionary in cut.entries:
		cut.keys.append(entry.path)
		cut.masks.append(entry.mask)
		if entry.mask[2]:
			for surface: Dictionary in preload("res://scripts/rendering/tokyo_native_ground.gd").surfaces(entry):
				cut.ground_images.append(surface.texture)
				if surface.has("height_texture"): cut.ground_images.append(surface.height_texture)
				cut.ground_max_scale=minf(cut.ground_max_scale,surface.max_scale)
				cut.charges.ground_bytes+=preload("res://scripts/rendering/tokyo_native_ground.gd").PLANE_BYTES
	return cut


func covers_ground(cut: Dictionary, view: Rect2, canvas: Transform2D, logical: Vector2) -> bool:
	return _covers_layers(cut,view,canvas,logical,4)


func covers_visible_layers(cut: Dictionary, view: Rect2, canvas: Transform2D, logical: Vector2) -> bool:
	return _covers_layers(cut,view,canvas,logical,7)


func _covers_layers(cut: Dictionary, view: Rect2, canvas: Transform2D, logical: Vector2, required: int) -> bool:
	if not view.has_area(): return true
	var configuration: String=cut.get("configuration","")
	var configurations := _configurations()
	var roots: Array=[]
	if cut.get("ground_tree",false) and _ground_roots.has(configuration): roots=_ground_roots[configuration]
	elif _partition_roots.has(configuration): roots=_partition_roots[configuration]
	elif configurations.has(configuration): roots=configurations[configuration]
	if roots.is_empty(): return false
	var selected: Dictionary={}
	for entry: Dictionary in cut.get("entries",[]):
		var layers := 0
		for kind in 3:
			if entry.mask[kind]: layers|=1<<kind
		selected[entry.path]=int(selected.get(entry.path,0))|layers
	var ray := MapProjection.ground_basis(canvas,deg_to_rad(38)).inverse()*MapProjection.camera_basis(canvas,deg_to_rad(38)).z
	var roof := -Vector2(ray.x,ray.z)/ray.y
	for root: Dictionary in roots:
		for kind in 3:
			if required&(1<<kind) and not _layer_complete(root,selected,view,canvas,logical,roof,kind): return false
	return true


static func _layer_complete(entry: Dictionary, selected: Dictionary, view: Rect2, canvas: Transform2D, logical: Vector2, roof: Vector2, kind: int) -> bool:
	if int(entry.triangles[kind])==0: return true
	# 完整选中的同层祖先已覆盖后代，无需再投影；未选中层仍逐视野递归证明。
	if int(selected.get(entry.path,0))&(1<<kind): return true
	var projection := preload("res://scripts/rendering/tokyo_cells_overlay.gd")
	var bounds := projection.projected_layer_bounds(entry.boxes[kind],roof,Vector2.ZERO)
	if not projection.intersects_view(bounds,view,canvas,logical): return true
	# AABB只能用于拒绝不可见节点，不能证明节点内部地面已填满。
	# 原生分区三角守恒：选中祖先，或完整包含全部可见后代，才可安全暂留。
	if entry.get("children",[]).is_empty(): return false
	var choices: Array=[entry.children]
	choices.append_array(entry.get("alternative_children",[]))
	for children: Array in choices:
		var complete := not children.is_empty()
		for child: Dictionary in children:
			if not _layer_complete(child,selected,view,canvas,logical,roof,kind):
				complete=false;break
		if complete: return true
	return false


func covered(cut: Dictionary) -> PackedInt32Array:
	var committed: Dictionary = {}
	for entry: Dictionary in cut.entries:
		# 普通概括页没有正式楼凭据；只有逐面无损重认证的新页可参与隐藏判定。
		if _partition_pages.has(entry.path) and not coverage[cut.configuration].pages.has(entry.path): continue
		var layers := 0
		for kind in 3:
			if entry.mask[kind]: layers|=1<<kind
		committed[entry.path]={"identity":pages[entry.path].canonical_identity,"layers":layers}
	return Coverage.covered_sources(coverage[cut.configuration],committed,cut.configuration,catalog.collision_sha256,catalog_sha)
