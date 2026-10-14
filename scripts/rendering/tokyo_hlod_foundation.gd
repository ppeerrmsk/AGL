extends RefCounted
## 同风格远景固定分区：不降清晰度、不改资源、不借旧底图填空。
const Contract := preload("res://scripts/rendering/tokyo_hlod_manifest.gd")
const Spatial := preload("res://scripts/experiments/tokyo_spatial_select.gd")
const MapProjection := preload("res://scripts/experiments/volume_projection.gd")
const Handoff := preload("res://scripts/rendering/tokyo_hlod_handoff.gd")
const LOWER := 1.0/6.0-0.0000001
const UPPER := 0.1944


static func plan(catalogs: Array[Dictionary], display_budget: int = 96*1024*1024, complete: bool = false) -> Dictionary:
	var layers := {}
	var meshes := PackedStringArray()
	var images := PackedStringArray()
	for index in catalogs.size():
		var catalog: Dictionary=catalogs[index]
		var middle: bool=Contract.binding(catalog.get("middle_massing_recipe")) and is_equal_approx(float(catalog.max_scale),0.625)
		var fine: bool=complete and is_equal_approx(float(catalog.max_scale),1.25)
		var depth := 2 if fine else (0 if is_equal_approx(float(catalog.max_scale),UPPER) else 1)
		if depth>0 and (display_budget!=192*1024*1024 or (not fine and not middle and not is_equal_approx(float(catalog.max_scale),0.25))): continue
		var entries: Array[Dictionary]=[]
		for root: Dictionary in catalog.roots:
			var sources: Array[Dictionary]=[root]
			for level in depth:
				var next: Array[Dictionary]=[]
				for source: Dictionary in sources:
					if source.get("children",[]).is_empty(): return {}
					next.append_array(source.children)
				sources=next
			for source: Dictionary in sources:
				if float(source.max_scale)<float(catalog.max_scale): return {}
				var entry := source.duplicate()
				entry.erase("children")
				entries.append(entry)
				if source.path not in meshes: meshes.append(source.path)
				if source.texture_path not in images: images.append(source.texture_path)
		if entries.is_empty(): return {}
		layers[index]={"entries":entries,"lower":0.625 if fine else (0.25 if middle else (LOWER if depth==0 else UPPER)),"upper":float(catalog.max_scale)}
	if complete:
		for upper: float in [UPPER,0.25,0.625,1.25]:
			var found := false
			for layer: Dictionary in layers.values(): found=found or is_equal_approx(float(layer.upper),upper)
			if not found: return {}
	return {"layers":layers,"meshes":meshes,"images":images} if not layers.is_empty() else {}


static func catalog_at(plan_value: Dictionary, scale: float, requested: int = -1) -> int:
	if not is_finite(scale): return -1
	# 常驻层外的更细档仍须提前开始真实交接，不能等基础清晰度到期才请求。
	if requested>=0 and not plan_value.get("layers",{}).has(requested): return -1
	for index: int in plan_value.get("layers",{}):
		var layer: Dictionary=plan_value.layers[index]
		if scale>=float(layer.lower) and scale<=float(layer.upper): return index
	return -1


static func select(catalog: Dictionary, entries: Array[Dictionary], center: Vector2, scale: float, angle: float, size: Vector2, budget: int) -> Dictionary:
	if not is_finite(scale) or scale<LOWER or scale>float(catalog.max_scale) or not is_finite(angle) \
		or not center.is_finite() or not size.is_finite() or size.x<=0 or size.y<=0 or budget<=0: return {}
	var started := Time.get_ticks_usec()
	var canvas := Transform2D(angle,Vector2.ZERO).scaled(Vector2.ONE*scale)
	canvas.origin=size*0.5-canvas*center
	var inverse := canvas.affine_inverse()
	var view := Rect2(inverse*Vector2.ZERO,Vector2.ZERO)
	for point: Vector2 in [Vector2(size.x,0),size,Vector2(0,size.y)]: view=view.expand(inverse*point)
	var ground := MapProjection.ground_basis(canvas,deg_to_rad(38))
	var ray := ground.inverse()*MapProjection.camera_basis(canvas,deg_to_rad(38)).z
	var selected: Array[Dictionary]=[]
	var keys := PackedStringArray()
	var selected_faces := 0
	for entry: Dictionary in entries:
		var visible := Spatial.visible(entry,view,canvas,size,-Vector2(ray.x,ray.z)/ray.y,Vector2.ZERO)
		var bounds: Array=catalog.rows[entry.key].bounds
		var page := Rect2(bounds[0],bounds[1],bounds[2]-bounds[0],bounds[3]-bounds[1])
		# 包含外接矩形的地表页，避免旋转后旧空间证明误判为不完整。
		if visible.faces<=0 and not page.intersects(view): continue
		if float(entry.max_scale)<scale: return {}
		visible.faces=int(entry.triangles[0]);visible.mask[0]=true
		selected.append(visible);keys.append(entry.key)
		selected_faces+=int(catalog.rows[entry.key].faces)
		# 后续只能增加页数/面数；已必然超原门时无需扫描其余固定页。
		if keys.size()>16 or selected_faces>240000: return {}
	var charged := Contract.charges(catalog,keys)
	if keys.is_empty() or charged.is_empty() or not charged.within_budget or charged.total_bytes>budget \
		or not Handoff.covers_view(catalog,{"keys":keys},view.intersection(catalog.bounds)): return {}
	return {"entries":selected,"keys":keys,"charges":charged,"triangles":charged.faces,
		"bytes":charged.total_bytes,"active":keys.size(),"within_budget":true,"spatial_guard_px":0,
		"solver_usec":Time.get_ticks_usec()-started,"foundation":true}
