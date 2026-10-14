extends RefCounted
## 加载期冻结来源依赖；提交期只投影包围树的可见分支。旧纯函数保留作差分真值。
const CellProjection := preload("res://scripts/rendering/tokyo_cells_overlay.gd")
var _data: Dictionary={}
var _reverse: Dictionary={}
var _masks: Dictionary={}
var _unboxed: Array[String]=[]
var _tree: Dictionary={}
var _ready := false
var _source_index := preload("res://scripts/experiments/tokyo_source_mask_index.gd").new()


func configure(data: Dictionary) -> bool:
	_ready=false;_reverse.clear();_masks.clear();_unboxed.clear();_tree.clear()
	_source_index=preload("res://scripts/experiments/tokyo_source_mask_index.gd").new()
	_data=data.duplicate(true)
	if _data.get("schema")!=1 or not _data.get("source_layers_complete",false): return false
	if not _data.get("pages") is Dictionary or not _data.get("dependencies") is Dictionary: return false
	if not _data.get("original_coverage") is Dictionary or not _data.original_coverage.get("pages") is Dictionary: return false
	if not _data.get("coarse_to_fine",{}) is Dictionary: return false
	for group: Variant in _data.get("coarse_to_fine",{}).values():
		if not group is Dictionary or not group.get("identity") is Dictionary or not group.get("children") is Array: return false
		for child: Variant in group.children:
			if not child is Dictionary or child.get("layer",-1) not in [0,1]: return false
			if not _data.pages.has(child.get("path")) or child.get("identity")!=_data.pages[child.path].get("identity"): return false
	for source: String in _data.dependencies:
		if not _data.original_coverage.pages.has(source): continue
		if not _data.dependencies[source] is Dictionary: return false
		_masks[source]=0
		for kind: Variant in _data.dependencies[source]:
			if not kind is int or kind<0 or kind>1: return false
			var required: Variant=_data.dependencies[source][kind]
			if not required is Array or required.is_empty(): return false
			_masks[source]|=1<<kind
			for dependency: Variant in required:
				if not dependency is Dictionary: return false
				var path: String=dependency.get("path","")
				var page: Variant=_data.pages.get(path)
				if not page is Dictionary or dependency.get("identity")!=page.get("identity"): return false
				if not _reverse.has(path): _reverse[path]=[]
				_reverse[path].append({"source":source,"bit":1<<kind})
	var boxed: Array=[]
	for path: String in _reverse:
		if _data.pages[path].get("box") is AABB: boxed.append(path)
		else: _unboxed.append(path)
	if not boxed.is_empty(): _tree=_build(boxed)
	_ready=true
	return true


func _build(paths: Array) -> Dictionary:
	var bounds: AABB=_data.pages[paths[0]].box
	for path: String in paths: bounds=bounds.merge(_data.pages[path].box)
	if paths.size()<=8: return {"box":bounds,"paths":paths}
	var axis := 0 if bounds.size.x>=bounds.size.z else 2
	paths.sort_custom(func(a: String,b: String) -> bool: return _data.pages[a].box.get_center()[axis]<_data.pages[b].box.get_center()[axis])
	var middle: int=paths.size()>>1
	return {"box":bounds,"left":_build(paths.slice(0,middle)),"right":_build(paths.slice(middle))}


func _visible(node: Dictionary, projection: Dictionary, paths: Array) -> void:
	if node.is_empty(): return
	var bounds := CellProjection.projected_layer_bounds(node.box,projection.roof,Vector2.ZERO)
	if not CellProjection.intersects_view(bounds,projection.view,projection.canvas,projection.size): return
	if node.has("paths"):
		for path: String in node.paths:
			bounds=CellProjection.projected_layer_bounds(_data.pages[path].box,projection.roof,Vector2.ZERO)
			if CellProjection.intersects_view(bounds,projection.view,projection.canvas,projection.size): paths.append(path)
	else:
		_visible(node.left,projection,paths);_visible(node.right,projection,paths)


func refined_layers(committed: Dictionary, projection: Dictionary={}) -> Dictionary:
	var masks := _refined_masks(committed,projection)
	var result: Dictionary={}
	for source: String in masks:
		if masks[source]: result[source]={"identity":_data.original_coverage.pages[source].identity.duplicate(true),"layers":masks[source]}
	return result


func compile_sources() -> bool:
	return _ready and _source_index.configure(_data.original_coverage,_masks)


func covered_sources(committed: Dictionary, projection: Dictionary, configuration: String, collision: String, catalog_sha: String) -> PackedInt32Array:
	return _source_index.covered(_refined_masks(committed,projection),configuration,collision,catalog_sha)


func _refined_masks(committed: Dictionary, projection: Dictionary) -> Dictionary:
	if not _ready: return {}
	var pieces: Dictionary={}
	for path: String in committed:
		var actual: Variant=committed[path]
		if not actual is Dictionary or not actual.get("layers") is int or actual.layers<0 or actual.layers>3: return {}
		if _data.get("coarse_to_fine",{}).has(path):
			var group: Dictionary=_data.coarse_to_fine[path]
			if actual.get("identity")!=group.identity: return {}
			for child: Dictionary in group.children:
				if (actual.layers&(1<<int(child.layer)))==0: continue
				if pieces.has(child.path): return {}
				pieces[child.path]={"identity":child.identity,"layers":1<<int(child.layer)}
		else:
			if pieces.has(path): return {}
			pieces[path]=actual
	for path: String in pieces:
		var page: Variant=_data.pages.get(path)
		if not page is Dictionary or not page.get("identity") is Dictionary or page.identity.is_empty() or pieces[path].get("identity")!=page.identity: return {}
	var required: Array=[]
	if projection.is_empty(): required=_reverse.keys()
	else:
		if not projection.get("view") is Rect2 or not projection.get("canvas") is Transform2D or not projection.get("size") is Vector2 or not projection.get("roof") is Vector2: return {}
		if not projection.view.has_area() or not projection.size.is_finite() or projection.size.x<=0 or projection.size.y<=0 or not projection.roof.is_finite(): return {}
		required.append_array(_unboxed)
		_visible(_tree,projection,required)
	var remaining := _masks.duplicate()
	for path: String in required:
		var present := int(pieces.get(path,{}).get("layers",0))
		for dependency: Dictionary in _reverse[path]:
			if (present&int(dependency.bit))==0: remaining[dependency.source]&=~int(dependency.bit)
	return remaining
