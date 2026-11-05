extends RefCounted
## 离线比较等价分区的联合前沿，所有来源仍保留三层完整几何。
var variants: Array=[]
var branching := 2
var diagnostic_cap := 16
var split_balance := "median"
var split_aspect := 1.0
var current_roots := false
var eligible_leaf: Callable
var probes: Array=[]

func select(native: RefCounted, center: Vector2, scale: float, angle: float, size: Vector2, configuration: String, depth: int) -> Dictionary:
	if probes.is_empty():
		for variant: Dictionary in variants:
			var probe := preload("res://scripts/tests/tokyo_native_refinement_probe.gd").new()
			probe.branching=2;probe.current_roots=true;probe.eligible_leaf=eligible_leaf
			probe.split_balance=String(variant.get("balance","median"));probe.split_aspect=float(variant.get("aspect",1.0))
			probes.append(probe)
	var replacements := {}
	for index in probes.size():
		var probe: RefCounted=probes[index]
		var cut: Dictionary=probe.select(native,center,scale,angle,size,configuration,depth)
		if cut.is_empty() or probe.failed: return {}
		for entry: Dictionary in probe._cache.values():
			if not replacements.has(entry.path): replacements[entry.path]=[]
			var children: Array=[]
			for child: Dictionary in entry.children: children.append(_rename(child,index))
			replacements[entry.path].append(children)
	var roots: Array[Dictionary]=[]
	for root: Dictionary in native.catalog.configurations[configuration]: roots.append(_replace(root,replacements))
	var canvas := Transform2D(angle,Vector2.ZERO).scaled(Vector2.ONE*scale)
	canvas.origin=size*0.5-canvas*center
	var inverse := canvas.affine_inverse()
	var view := Rect2(inverse*Vector2.ZERO,Vector2.ZERO)
	for corner: Vector2 in [Vector2(size.x,0),size,Vector2(0,size.y)]: view=view.expand(inverse*corner)
	var projection := preload("res://scripts/experiments/volume_projection.gd")
	var ray := projection.ground_basis(canvas,deg_to_rad(38)).inverse()*projection.camera_basis(canvas,deg_to_rad(38)).z
	var cut := preload("res://scripts/experiments/tokyo_spatial_cut.gd").choose(roots,view,canvas,size,-Vector2(ray.x,ray.z)/ray.y,Vector2.ZERO,16,96*1024*1024)
	cut=preload("res://scripts/rendering/tokyo_hlod_native.gd").decorate(cut,configuration,false)
	cut["refinement"]={"variants":variants,"depth":depth,"leaves":replacements.size(),"runtime_integrated":false}
	return cut

static func _rename(entry: Dictionary, variant: int) -> Dictionary:
	var result := entry.duplicate()
	result.path="alternative%d:"%variant+String(entry.path)
	result.children=[]
	for child: Dictionary in entry.children: result.children.append(_rename(child,variant))
	return result

static func _replace(entry: Dictionary, replacements: Dictionary) -> Dictionary:
	var result := entry.duplicate()
	result.children=[]
	if replacements.has(entry.path):
		result.children=replacements[entry.path][0]
		result["alternative_children"]=replacements[entry.path].slice(1)
	else:
		for child: Dictionary in entry.children: result.children.append(_replace(child,replacements))
	return result
