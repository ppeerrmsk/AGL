extends RefCounted
## 仅从已经驻留的同风格页求完整切面；缺资源的节点仍保留几何范围，禁止当空白裁掉。
const Contract := preload("res://scripts/rendering/tokyo_hlod_manifest.gd")
const Select := preload("res://scripts/experiments/tokyo_spatial_select.gd")
const MapProjection := preload("res://scripts/experiments/volume_projection.gd")


static func candidate_catalogs(catalogs: Array[Dictionary], preferred: int, previous: int, scale: float) -> PackedInt32Array:
	var result := PackedInt32Array()
	if not is_finite(scale) or scale<=0.0: return result
	for index: int in [preferred,previous]:
		if index>=0 and index<catalogs.size() and scale<=float(catalogs[index].max_scale) and index not in result:
			result.append(index)
	var nearest := -1
	for index in catalogs.size():
		if index in result or scale>float(catalogs[index].max_scale): continue
		if nearest<0 or float(catalogs[index].max_scale)<float(catalogs[nearest].max_scale): nearest=index
	# 每次最多三档；没有完整合格缓存就报告失败，不能无界搜索拖住游戏帧。
	if nearest>=0: result.append(nearest)
	return result


static func select(catalog: Dictionary, center: Vector2, scale: float, angle: float, size: Vector2,
		geometry: Dictionary, meshes: Dictionary, textures: Dictionary) -> Dictionary:
	if not is_finite(scale) or scale<=0.0 or scale>float(catalog.max_scale) or not is_finite(angle) \
		or not center.is_finite() or not size.is_finite() or size.x<=0.0 or size.y<=0.0: return {}
	var canvas := Transform2D(angle,Vector2.ZERO).scaled(Vector2.ONE*scale)
	canvas.origin=size*0.5-canvas*center
	var inverse := canvas.affine_inverse()
	var view := Rect2(inverse*Vector2.ZERO,Vector2.ZERO)
	for point: Vector2 in [Vector2(size.x,0),size,Vector2(0,size.y)]: view=view.expand(inverse*point)
	var ground := MapProjection.ground_basis(canvas,deg_to_rad(38))
	var ray := ground.inverse()*MapProjection.camera_basis(canvas,deg_to_rad(38)).z
	var context := {"view":view,"canvas":canvas,"size":size,"roof":-Vector2(ray.x,ray.z)/ray.y,
		"geometry":geometry,"meshes":meshes,"textures":textures}
	var roots: Array[Dictionary]=[]
	for entry: Dictionary in Contract.qualified_roots(catalog,scale): roots.append(_resident_tree(entry,context))
	var resident := catalog.duplicate()
	resident["roots"]=roots
	resident["min_scale"]=minf(float(catalog.min_scale),scale)
	resident.erase("identity")
	var result := Contract.select(resident,center,scale,angle,size,false,preload("res://scripts/rendering/tokyo_hlod_cache_policy.gd").display_limit())
	return result if not result.is_empty() and result.within_budget and not result.keys.is_empty() else {}


static func _resident_tree(entry: Dictionary, context: Dictionary) -> Dictionary:
	if Select.visible(entry,context.view,context.canvas,context.size,context.roof,Vector2.ZERO).faces==0: return entry
	var result := entry.duplicate()
	var ready: bool=context.textures.has(entry.texture_path)
	for part: String in context.geometry.get(entry.path,{}).get("components",{entry.path:{}}):
		ready=ready and context.meshes.has(part)
	if not ready: result["bytes"]=192*1024*1024+1
	if entry.has("children"):
		var children: Array[Dictionary]=[]
		for child: Dictionary in entry.children: children.append(_resident_tree(child,context))
		result["children"]=children
	return result


static func native_tree(entry: Dictionary, context: Dictionary) -> Dictionary:
	var visible := Select.visible(entry,context.view,context.canvas,context.size,context.roof,Vector2.ZERO)
	if visible.faces==0: return entry
	var result := entry.duplicate()
	var ready: bool=context.geometry.has(entry.path)
	for part: String in context.geometry.get(entry.path,{}).get("components",{entry.path:{}}):
		ready=ready and context.meshes.has(part)
	if visible.mask[2]:
		for surface: Dictionary in preload("res://scripts/rendering/tokyo_native_ground.gd").surfaces(entry):
			ready=ready and context.textures.has(surface.texture)
			if surface.has("height_texture"):
				ready=ready and context.textures.has(surface.height_texture)
	# 保留几何和孩子，只让尚未驻留的候选不可能通过费用门；不能把缺资源当不可见。
	if not ready: result["bytes"]=192*1024*1024+1
	if entry.has("children"):
		var children: Array[Dictionary]=[]
		for child: Dictionary in entry.children: children.append(native_tree(child,context))
		result["children"]=children
	return result
