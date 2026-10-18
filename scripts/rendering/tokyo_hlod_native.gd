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


func read(value: Variant) -> bool:
	selection_context={};_selection_configurations={}
	_partition_roots.clear()
	_partition_pages.clear()
	_selection_frame=-1
	_selection_solutions.clear()
	solver_peak.clear()
	ground.clear();_ground_roots.clear()
	if not value is Dictionary or not Contract.binding(value.get("catalog")) or not Contract.binding(value.get("components")) or not value.get("coverage") is Dictionary: return false
	catalog=load(value.catalog.path)
	if not catalog is Catalog or catalog.schema_version!=2 or not catalog.valid(): return false
	catalog_sha=value.catalog.sha256
	var component_data := Components.read(value.components.path,catalog,catalog_sha)
	if component_data.is_empty(): return false
	pages=component_data.pages
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
	if value.has("partition_override"):
		var adapted := preload("res://scripts/rendering/tokyo_partition_override.gd").read(value.partition_override,catalog,catalog_sha,pages,coverage)
		if adapted.is_empty(): return false
		_partition_roots=adapted.roots
		_partition_pages=adapted.pages
		pages.merge(_partition_pages)
	if value.has("ground_override"):
		ground=preload("res://scripts/rendering/tokyo_native_ground.gd").read(value.ground_override,pages)
		if ground.is_empty(): return false
		for configuration: String in ground.limits:
			var roots: Array[Dictionary]=[]
			for entry: Dictionary in _partition_roots.get(configuration,catalog.configurations[configuration]):
				var adapted := preload("res://scripts/rendering/tokyo_native_ground.gd").tree(entry,ground.rows)
				if adapted.is_empty(): return false
				roots.append(adapted)
			_ground_roots[configuration]=roots
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
	return true


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
	for child: Dictionary in entry.children:
		if not _layer_complete(child,selected,view,canvas,logical,roof,kind): return false
	return true


func covered(cut: Dictionary) -> PackedInt32Array:
	var committed: Dictionary = {}
	for entry: Dictionary in cut.entries:
		# 接合器逐旧页核验无游戏建筑；这些页不为任何旧楼提供隐藏凭据。
		if _partition_pages.has(entry.path): continue
		var layers := 0
		for kind in 3:
			if entry.mask[kind]: layers|=1<<kind
		committed[entry.path]={"identity":pages[entry.path].canonical_identity,"layers":layers}
	return Coverage.covered_sources(coverage[cut.configuration],committed,cut.configuration,catalog.collision_sha256,catalog_sha)
