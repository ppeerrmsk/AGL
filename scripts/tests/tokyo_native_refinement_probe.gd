extends RefCounted
## 离线反例重放：原生叶再分桶，只核可见成本，不写目录或授予运行时显示资格。
const Cut := preload("res://scripts/experiments/tokyo_spatial_cut.gd")
const Select := preload("res://scripts/experiments/tokyo_spatial_select.gd")
const Split := preload("res://scripts/experiments/tokyo_spatial_split.gd")
const Join := preload("res://scripts/experiments/tokyo_packed_mesh_join.gd")
const Read := preload("res://scripts/experiments/tokyo_packed_mesh_reindex.gd")
const Count := preload("res://scripts/experiments/tokyo_indexed_mesh.gd")
const Boundary := preload("res://scripts/tests/build_tokyo_boundary_tree.gd")
const MapProjection := preload("res://scripts/experiments/volume_projection.gd")
const Archive := preload("res://scripts/rendering/tokyo_volume_archive.gd")
var _cache: Dictionary = {}
var failed := false
var refined_leaves := 0
var conserved_splits := 0
var branching := 4
var diagnostic_cap := 16
var page_sink: Callable
var current_roots := false
var eligible_leaf: Callable
var refine_branches := false
var recorded_plans: Dictionary={}
var _active_cuts: Dictionary={}
var split_plan: Dictionary = {}
var leaf_split_plans: Dictionary = {}
var split_balance := "median"
var split_aspect := 1.0


static func planned_cut(plan: Dictionary, path: String) -> Dictionary:
	var hint: Variant=plan.get(path)
	var contract := preload("res://scripts/rendering/tokyo_hlod_manifest.gd")
	if not hint is Dictionary or not contract.integer(hint.get("axis")) \
		or int(hint.axis) not in [0,1] or typeof(hint.get("threshold")) not in [TYPE_INT,TYPE_FLOAT] \
		or not is_finite(float(hint.threshold)): return {}
	if hint.get("metric","centroid") not in ["centroid","extent"]: return {}
	if hint.get("metric","")=="extent" and (int(hint.axis)!=0 or float(hint.threshold)<=0): return {}
	return hint


static func partition_owners(mesh: ArrayMesh, hint: Dictionary) -> PackedInt32Array:
	var owners := PackedInt32Array()
	if hint.get("metric","centroid")=="centroid":
		for point: Vector2 in Split.centers(mesh): owners.append(int(point[int(hint.axis)]>=float(hint.threshold)))
		return owners
	if mesh.get_surface_count()==0: return owners
	var arrays := mesh.surface_get_arrays(0)
	var positions: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array=arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX]!=null else PackedInt32Array()
	var count := positions.size() if indices.is_empty() else indices.size()
	for offset in range(0,count,3):
		var first: Vector3=positions[offset if indices.is_empty() else indices[offset]]
		var box := AABB(first,Vector3.ZERO)
		for corner in range(1,3): box=box.expand(positions[offset+corner if indices.is_empty() else indices[offset+corner]])
		owners.append(int(maxf(box.size.x,box.size.z)>=float(hint.threshold)))
	return owners


static func export_cut(native: RefCounted, cut: Dictionary, directory: String) -> Dictionary:
	if not directory.is_absolute_path() or DirAccess.dir_exists_absolute(directory): return {}
	if DirAccess.make_dir_recursive_absolute(directory)!=OK: return {}
	var layers: Array = [[],[],[]]
	for entry: Dictionary in cut.entries:
		var row: Dictionary=native.pages[entry.path]
		var meshes:=Boundary.meshes(row,row.components)
		if meshes.size()!=3: return {}
		for kind in 3:
			if entry.mask[kind]: layers[kind].append(meshes[kind])
	var result: Dictionary={"layers":[],"runtime_integrated":false}
	for kind in 3:
		var inputs: Array[ArrayMesh]=[]
		inputs.assign(layers[kind])
		var joined:=Join.join(inputs)
		if joined==null or not Join.conserved(joined,inputs): return {}
		var path:=directory.path_join("layer_%d.attributes"%kind)
		if preload("res://scripts/tests/tokyo_residential_preview.gd").export_attributes(joined,path)!=0: return {}
		result.layers.append({"path":path,"sha256":FileAccess.get_sha256(path),"faces":Count.triangles(joined)})
	return result


func select(native: RefCounted, center: Vector2, scale_value: float, rotation_value: float,
		size: Vector2, configuration: String, depth: int) -> Dictionary:
	if depth<1 or depth>(8 if refine_branches else 4) or branching not in [2,4] or diagnostic_cap not in [16,24] or split_balance not in ["median","area","sah"] or failed: return {}
	if not is_finite(split_aspect) or split_aspect<0.25 or split_aspect>4.0: return {}
	if configuration.is_empty(): configuration="lod%d_full" % Archive.choose_level(-1,scale_value)
	var canvas := Transform2D(rotation_value,Vector2.ZERO).scaled(Vector2.ONE*scale_value)
	canvas.origin=size*0.5-canvas*center
	var inverse := canvas.affine_inverse()
	var view := Rect2(inverse*Vector2.ZERO,Vector2.ZERO)
	for corner in [Vector2(size.x,0),size,Vector2(0,size.y)]: view=view.expand(inverse*corner)
	var ray := MapProjection.ground_basis(canvas,deg_to_rad(38)).inverse()*MapProjection.camera_basis(canvas,deg_to_rad(38)).z
	var roof := -Vector2(ray.x,ray.z)/ray.y
	var roots: Array[Dictionary] = []
	var source_roots: Array=native._partition_roots.get(configuration,native.catalog.configurations[configuration]) if current_roots else native.catalog.configurations[configuration]
	for entry: Dictionary in source_roots:
		roots.append(_refine(entry,native,view,canvas,size,roof,depth))
	if failed: return {}
	# 超16只用于离线成本对照；不修改正式求解器的16页上限。
	var started := Time.get_ticks_usec()
	var context := {"view":view,"canvas":canvas,"logical":size,"roof":roof,"shadow":Vector2.ZERO,"cap":diagnostic_cap,"visited":0}
	var frontier: Array[Dictionary] = [{"entries":[],"active":0,"faces":0,"bytes":0}]
	for entry: Dictionary in roots: frontier=Cut._combine(frontier,Cut._frontier(entry,context),diagnostic_cap)
	var result := Cut.pick({"frontier":frontier,"visited":context.visited,"solver_usec":Time.get_ticks_usec()-started},96*1024*1024)
	result.keys=PackedStringArray()
	for entry: Dictionary in result.entries: result.keys.append(entry.path)
	result.configuration=configuration
	result.charges={"ground_bytes":0}
	result.refinement={"depth":depth,"branching":branching,"diagnostic_cap":diagnostic_cap,"formal_page_gate":result.active<=16,"leaves":refined_leaves,"conserved_splits":conserved_splits,
		"runtime_integrated":false,"coverage_certified":false}
	return result


func _refine(entry: Dictionary, native: RefCounted, view: Rect2, canvas: Transform2D,
		size: Vector2, roof: Vector2, depth: int) -> Dictionary:
	if failed or int(Select.visible(entry,view,canvas,size,roof,Vector2.ZERO).faces)==0: return entry
	if not entry.children.is_empty() and not (refine_branches and eligible_leaf.is_valid() and eligible_leaf.call(entry)):
		var parent := entry.duplicate()
		parent.children=[]
		for child: Dictionary in entry.children: parent.children.append(_refine(child,native,view,canvas,size,roof,depth))
		return parent
	# 增量制作先排除正式楼/已有替换；成本求解必须保留原页，不能先假设可拆再写出失败。
	if eligible_leaf.is_valid() and not eligible_leaf.call(entry): return entry
	# 每个完整来源只细分到各自绑定计划需要的深度，避免为少数热点放大全图资源。
	var requested_depth: Variant=leaf_split_plans.get(entry.path,{}).get("split_depth",depth)
	if not preload("res://scripts/rendering/tokyo_hlod_manifest.gd").integer(requested_depth) or int(requested_depth)<1 or int(requested_depth)>depth:
		failed=true
		return entry
	depth=int(requested_depth)
	var key := str(entry.path)+":"+str(depth)+":"+str(branching)
	if _cache.has(key): return _cache[key]
	var row: Dictionary = native.pages[entry.path]
	var meshes := Boundary.meshes(row,row.components)
	if meshes.size()!=3:
		failed=true
		return entry
	for kind in 3:
		if Count.triangles(meshes[kind])!=int(entry.triangles[kind]) or meshes[kind].get_aabb()!=entry.boxes[kind]:
			failed=true
			return entry
	var previous_plan := split_plan
	split_plan=leaf_split_plans.get(entry.path,{}).get("cuts",previous_plan)
	_active_cuts={}
	var result := _split(entry,meshes,depth)
	split_plan=previous_plan
	if failed: return entry
	if branching==2: recorded_plans[entry.path]={"tree_sha256":var_to_bytes(entry).hex_encode().sha256_text(),"split_depth":depth,"cuts":_active_cuts.duplicate(true)}
	refined_leaves+=1
	_cache[key]=result
	return result


func _split(entry: Dictionary, meshes: Array[ArrayMesh], depth: int) -> Dictionary:
	if page_sink.is_valid() and not page_sink.call(entry,meshes):
		failed=true
		return entry
	if depth==0: return entry
	var cuts := Split.cuts(meshes)
	var axis := 0
	var threshold := float(cuts[0])
	var metric := "centroid"
	if branching==2 and not split_plan.is_empty():
		var hint := planned_cut(split_plan,str(entry.path))
		if hint.is_empty():
			failed=true
			return entry
		axis=int(hint.axis);threshold=float(hint.threshold);metric=String(hint.get("metric","centroid"))
	elif branching==2:
		var centers := PackedVector2Array()
		for mesh: ArrayMesh in meshes: centers.append_array(Split.centers(mesh))
		if centers.is_empty(): return entry
		var bounds := Rect2(centers[0],Vector2.ZERO)
		for point: Vector2 in centers: bounds=bounds.expand(point)
		axis=0 if bounds.size.x/split_aspect>=bounds.size.y else 1
		var coordinates := PackedFloat32Array()
		for point: Vector2 in centers: coordinates.append(point[axis])
		coordinates.sort()
		threshold=coordinates[coordinates.size()/2]
		if split_balance=="area": threshold=bounds.position[axis]+bounds.size[axis]*0.5
		elif split_balance=="sah":
			var hint := preload("res://scripts/tests/tokyo_partition_sah.gd").choose(meshes)
			if not hint.is_empty(): axis=int(hint.axis);threshold=float(hint.threshold)
	if branching==2:
		_active_cuts[entry.path]={"axis":axis,"threshold":threshold}
		if metric!="centroid": _active_cuts[entry.path]["metric"]=metric
	var layers: Array = []
	for kind in meshes.size():
		var mesh: ArrayMesh=meshes[kind]
		var pieces: Array[ArrayMesh]
		if branching==2:
			var owners := partition_owners(mesh,{"axis":axis,"threshold":threshold,"metric":metric})
			pieces=Split.partition(mesh,owners,2)
		else: pieces=Split.split(mesh,cuts)
		if pieces.size()!=branching or not Join.conserved(mesh,pieces):
			failed=true
			return entry
		layers.append(pieces)
		conserved_splits+=1
	var parent := entry.duplicate()
	parent.children=[]
	for n in branching:
		var child := {"path":str(entry.path)+"/probe_"+str(n),"boxes":[],"triangles":[],"bytes":0,"children":[]}
		var child_meshes: Array[ArrayMesh] = []
		for kind in 3:
			var mesh: ArrayMesh = layers[kind][n]
			child_meshes.append(mesh)
			child.boxes.append(mesh.get_aabb())
			child.triangles.append(Count.triangles(mesh))
			child.bytes+=Read.decoded_bytes(mesh)
		parent.children.append(_split(child,child_meshes,depth-1))
	return parent
