extends RefCounted
## 只证明同池暂存预算，不授予旧切面完整目标覆盖。
const Contract := preload("res://scripts/rendering/tokyo_hlod_manifest.gd")

static func retain_display(cut: Dictionary, qualified: bool, covered: bool, budget: int, page_limit: int = 16) -> bool:
	# 新求解失败不撤销已有合格显示；绝不借此保留缺边、过期或超预算的旧切面。
	var keys: Variant=cut.get("keys")
	return page_limit in [16,32] and qualified and covered and keys is PackedStringArray and not keys.is_empty() and keys.size()<=page_limit \
		and cut.get("within_budget",false) and int(cut.get("triangles",240001))<=240000 \
		and int(cut.get("bytes",budget+1))<=budget

static func zoom_direction(previous: float, current: float) -> int:
	if previous<=0.0 or not is_finite(previous) or not is_finite(current): return 0
	var change := current/previous-1.0
	return 0 if absf(change)<=0.0001 else (1 if change>0.0 else -1)

static func prediction_zoom_rate(previous: float, ratio: float, delta: float) -> float:
	if not is_finite(previous) or not is_finite(ratio) or not is_finite(delta) or delta<=0.0: return 0.0
	var measured := log(ratio)/delta if ratio>0.67 and ratio<1.5 else 0.0
	# 真实反向不能被旧方向的指数平滑拖住，否则会预取相反LOD；浮点微抖仍忽略。
	if zoom_direction(1.0,ratio)!=0 and previous*measured<0.0: return measured
	return lerpf(previous,measured,0.4)


static func native_exit_checkpoint(current: float, proposed: float, boundary: float) -> float:
	# 常驻远档已就绪时，仍先备齐跨过去之前最后一个原生视野；不改变实际相机或清晰度。
	if not is_finite(current) or not is_finite(proposed) or not is_finite(boundary) or boundary<=0.0: return proposed
	if current<=boundary or proposed>boundary or proposed<=0.0: return proposed
	return minf(current,boundary*1.001)


static func catalog_index(catalogs: Array[Dictionary], scale: float, prefetch_finer: bool = true) -> int:
	if not is_finite(scale) or scale<=0: return -1
	var selected := -1
	for n in catalogs.size():
		if catalogs[n].get("transition_only",false): continue
		var interval: Array=catalogs[n].range
		if scale>float(interval[0]) and scale<=float(interval[1]): selected=n;break
	if selected<0: return selected
	if not prefetch_finer: return selected
	var boundary := float(catalogs[selected].range[1])
	# 目录、选页和复用共用提前比例，避免其中一层抵消预取。
	if scale>=boundary*Contract.PREFETCH_RATIO:
		for n in catalogs.size():
			if is_equal_approx(float(catalogs[n].range[0]),boundary): return n
	return selected

static func display_catalog_index(catalogs: Array[Dictionary], scale: float, current: int) -> int:
	# 预取只准备资源；显示沿真实范围选档，缩远保留8%滞回，避免阈值两边反复跳档。
	var actual := catalog_index(catalogs,scale,false)
	if actual<0 or current<0 or current>=catalogs.size() or catalogs[current].get("transition_only",false): return actual
	var lower := float(catalogs[current].range[0])
	var upper := float(catalogs[current].range[1])
	return current if scale>=lower*0.92 and scale<=upper else actual


static func display_target_allowed(catalogs: Array[Dictionary], scale: float, current: int, next: int) -> bool:
	# 预测与缓存可以提前准备，但不能绕过实际显示阈值；混合桥接仍由覆盖和预算门裁决。
	if next==-2: return true
	if next<0 or next>=catalogs.size(): return false
	return catalogs[next].get("transition_only",false) or next==display_catalog_index(catalogs,scale,current)


static func blend_allowed(old: Dictionary, next: Dictionary, combined_bytes: int, budget: int) -> bool:
	return old.get("within_budget",false) and next.get("within_budget",false) \
		and old.get("keys") is PackedStringArray and next.get("keys") is PackedStringArray \
		and not old.keys.is_empty() and not next.keys.is_empty() and old.keys.size()+next.keys.size()<=16 \
		and Contract.integer(old.get("triangles"),0,240000) and Contract.integer(next.get("triangles"),0,240000) \
		and int(old.get("triangles",240001))+int(next.get("triangles",240001))<=240000 \
		and combined_bytes>=0 and combined_bytes<=budget


static func preload_entry_scale(catalogs: Array[Dictionary], scale: float, rate: float) -> float:
	var index := catalog_index(catalogs,scale,false)
	if index<0 or not is_finite(rate) or rate< -0.02: return 0.0
	var boundary := float(catalogs[index].range[1])
	return boundary*1.001 if scale>=boundary*Contract.PREFETCH_RATIO else 0.0


static func prediction_checkpoint(catalogs: Array[Dictionary], scale: float, future: float, rate: float, current: int = -1) -> float:
	# 先准备必经的相邻档入口，不能让固定时间预测越过它、只加载更远的终点。
	if not is_finite(rate) or absf(rate)<0.02: return future
	var index := display_catalog_index(catalogs,scale,current)
	var boundary := 0.0
	if index>=0: boundary=float(catalogs[index].range[1]) if rate>0.0 else float(catalogs[index].range[0])*0.92
	elif rate<0.0:
		for catalog: Dictionary in catalogs:
			if not catalog.get("transition_only",false): boundary=maxf(boundary,float(catalog.range[1]))
		if scale<=boundary: return future
		# 缩远先覆盖边界前最后一个原生视野，再准备边界后的HLOD。
		# 后续预测已经到过此点时必须继续，不能把全部前探点钉在同一倍率。
		var native_edge := boundary*1.001
		if scale>native_edge and not is_equal_approx(scale,native_edge): return maxf(future,native_edge)
	var checkpoint := boundary*(1.001 if rate>0.0 else 0.999)
	if boundary<=0.0: return future
	return minf(future,checkpoint) if rate>0.0 else maxf(future,checkpoint)


static func blend_progress(age: float, start_scale: float, scale: float, boundary: float) -> float:
	var progress := clampf(age/0.09,0.0,1.0)
	if start_scale>0.0 and scale>0.0 and boundary>0.0 and not is_equal_approx(start_scale,boundary):
		progress=maxf(progress,clampf(log(scale/start_scale)/log(boundary/start_scale),0.0,1.0))
	return smoothstep(0.0,1.0,progress)


static func native_qualified(cut: Dictionary, scale: float) -> bool:
	if not is_finite(scale) or scale<=0 or not cut.get("keys") is PackedStringArray or cut.keys.is_empty(): return false
	if scale>float(cut.get("ground_max_scale",INF)): return false
	var archive := preload("res://scripts/rendering/tokyo_volume_archive.gd")
	for level in archive.SCALES.size():
		if cut.get("configuration")=="lod%d_full" % level:
			return level==archive.SCALES.size()-1 or scale<=float(archive.SCALES[level])
	return false


static func native_preference_qualified(cut: Dictionary, scale: float, zoom_rate: float) -> bool:
	if not native_qualified(cut,scale) or not is_finite(zoom_rate): return false
	if cut.get("ground_images",PackedStringArray()).is_empty() or zoom_rate<=0.0: return true
	# 烘焙地面可早于原生几何到期；偏好不能把即将到期的旧档反复选回来。
	# 仅提前让位给合格接替，不延长任何旧页资格；与现有预测I/O同用0.25秒视窗。
	return native_qualified(cut,scale*exp(clampf(zoom_rate*0.25,0.0,0.7)))


static func pan_lead(velocity: Vector2, scale: float, horizon: float, size: Vector2) -> Vector2:
	if not velocity.is_finite() or not is_finite(scale) or scale<=0.0 or not is_finite(horizon) or horizon<0.0 \
		or not size.is_finite() or minf(size.x,size.y)<=0.0: return Vector2.ZERO
	# 相机转场的瞬时速度不能被外推成数屏全图求解；只限制投机前探，不改真实相机。
	# 正常2400px/s移动的0.35s前探840px仍完整保留在1600x900视口内。
	return (velocity*horizon).limit_length(minf(size.x,size.y)/scale)


static func motion_guard_need(velocity: Vector2, scale: float, size: Vector2) -> float:
	# 显示切面应能撑过0.25秒平移（与裁页同一前探视窗）；静止为0，上限为最宽192px保护带。
	return minf(192.0,pan_lead(velocity,scale,0.25,size).length()*scale)


static func return_horizons(distance_px: float, size: Vector2, rate: float, step: float) -> Array[float]:
	# 回中是指数路径：固定时间点在远距离下会跳过整片视野。按屏幕距离均分路径，
	# 再换回正式跟随曲线的时刻；只用于预取，不改变实际镜头或清晰度。
	if not is_finite(distance_px) or distance_px<0.0 or not size.is_finite() or minf(size.x,size.y)<=0.0 \
		or not is_finite(rate) or rate<=0.0 or not is_finite(step) or step<0.0: return []
	var effective := -log(maxf(0.0001,1.0-rate*step))/step if step>0.0 else rate
	var segments := clampi(ceili(distance_px/(minf(size.x,size.y)*0.4)),2,10)
	var result: Array[float]=[1.0,0.005]
	for index in range(1,segments):
		var horizon := -log(1.0-float(index)/segments)/effective
		if horizon>0.005 and horizon<1.0: result.append(horizon)
	return result


## 运动中改用实际档时，实际档到期前须留出换回细档的裁页与装载时间。
const MOTION_ACTUAL_HORIZON := 0.6

static func motion_actual_qualified(catalog: Dictionary, cut: Dictionary, scale: float, zoom_rate: float) -> bool:
	# 只按放大方向外推；缩远不会使实际档提前失格。
	return is_finite(zoom_rate) and qualified(catalog,cut,scale*exp(clampf(zoom_rate*MOTION_ACTUAL_HORIZON,0.0,0.7)))


static func zoom_out_padding(zoom_rate: float, size: Vector2, horizon: float = 0.25) -> Vector2:
	if not is_finite(zoom_rate) or not size.is_finite() or minf(size.x,size.y)<=0.0 \
		or not is_finite(horizon) or horizon<0.0: return Vector2.ZERO
	# 只扩张空间查询，LOD仍使用此刻真实scale；放大不扩大视野，缩远最多前探同一0.7对数范围。
	return size*(exp(clampf(-zoom_rate*horizon,0.0,0.7))-1.0)


static func native_motion_query(center: Vector2, scale: float, rotation: float, size: Vector2,
		lead: Vector2, horizon: float, zoom_rate: float = 0.0) -> Dictionary:
	if not center.is_finite() or not lead.is_finite() or not size.is_finite() or minf(size.x,size.y)<=0.0 \
		or not is_finite(scale) or scale<=0.0 or not is_finite(rotation) or not is_finite(horizon) or horizon<0.0 \
		or not is_finite(zoom_rate): return {}
	var basis := Transform2D(rotation,Vector2.ZERO)
	var offset := basis.basis_xform(lead)*scale
	# 零缩放率保留原纯平移查询；已在未来scale上的预取显式走这一路，避免重复外推。
	if zoom_rate==0.0: return {"center":center+lead*0.5,"size":size+offset.abs()}
	# 与预测预取共用指数和尺度范围，但仅改变空间包络；目录资格仍使用当前scale。
	var future_scale := clampf(scale*exp(clampf(zoom_rate*horizon,-0.7,0.7)),0.0973,5.0)
	var future_size := size*(scale/future_scale)
	var swept := Rect2(-size*0.5,size).merge(Rect2(offset-future_size*0.5,future_size))
	return {"center":center+basis.basis_xform_inv(swept.get_center()/scale),"size":swept.size}


static func actual_fallback(catalogs: Array[Dictionary], selected: int, scale: float, within_budget: bool) -> int:
	# 提前细档失败，不代表当前距离无合格HLOD；不要先求昂贵的原生近景切面。
	if within_budget or selected<0: return -1
	var actual := catalog_index(catalogs,scale,false)
	return actual if actual>=0 and actual!=selected else -1


static func loading_configuration(cut: Dictionary, scale: float, desired: String) -> String:
	# 在途档仍满足真实清晰度时先完成它，不能被更远期细节预取反复取消。
	return String(cut.configuration) if cut.get("prefetched_native",false) and native_qualified(cut,scale) else desired


static func native_preference(cut: Dictionary, combined: int, pool_limit: int = 96*1024*1024) -> bool:
	# 原生单独放得下不等于能交接；不能取消有解的HLOD后钉住超联合预算的原生偏好。
	return cut.get("within_budget",false) and pool_limit>=96*1024*1024 and pool_limit<=1536*1024*1024 \
		and combined>=0 and combined<=pool_limit


static func scale_limit(catalog: Dictionary, cut: Dictionary) -> float:
	var limit := float(catalog.get("max_scale",0.0))
	for key in cut.get("keys",PackedStringArray()):
		limit=minf(limit,float(catalog.rows[key].get("max_scale",limit)))
	return limit


static func anticipation_scale(catalog: Dictionary, cut: Dictionary, view: Rect2) -> float:
	# 提前窄视野只能依靠仍覆盖当前视野的旧页等待；离屏旧页不能作预取桥梁。
	return scale_limit(catalog,cut) if covers_view(catalog,cut,view) else 0.0


static func display_grace(catalog: Dictionary, cut: Dictionary, scale: float, elapsed_ms: int, view: Rect2) -> bool:
	# 仅保留已显示的同风格3D页，不授予新候选超尺度提交资格；空间、时间、倍率均有硬界。
	var limit := scale_limit(catalog,cut)
	return not cut.get("keys",PackedStringArray()).is_empty() and is_finite(scale) and limit>0.0 \
		and scale>limit and scale<=limit*1.10 and elapsed_ms>=0 and elapsed_ms<=100 and covers_view(catalog,cut,view)


static func covers_view(catalog: Dictionary, cut: Dictionary, view: Rect2) -> bool:
	return uncovered_view(catalog,cut,view).is_empty()


static func covers_motion_view(catalog: Dictionary, cut: Dictionary, center: Vector2, scale: float, rotation: float, size: Vector2, lead: Vector2 = Vector2.ZERO) -> bool:
	# 当前和前探视口的屏幕矩形包络；必须对完整目录证明，旧切面子集自身不能证明完整性。
	if not center.is_finite() or not lead.is_finite() or not size.is_finite() or minf(size.x,size.y)<=0.0 \
		or not is_finite(scale) or scale<=0.0 or not is_finite(rotation): return false
	var expanded := size+(Transform2D(rotation,Vector2.ZERO).basis_xform(lead)*scale).abs()
	var canvas := Transform2D(rotation,Vector2.ZERO).scaled(Vector2.ONE*scale)
	canvas.origin=expanded*0.5-canvas*(center+lead*0.5)
	var inverse := canvas.affine_inverse()
	var view := Rect2(inverse*Vector2.ZERO,Vector2.ZERO)
	for point: Vector2 in [Vector2(expanded.x,0),expanded,Vector2(0,expanded.y)]: view=view.expand(inverse*point)
	if typeof(catalog.get("bounds"))==TYPE_RECT2: view=view.intersection(catalog.bounds)
	return covers_projection(catalog,cut,view,canvas,expanded)


static func covers_projection(catalog: Dictionary, cut: Dictionary, view: Rect2, canvas: Transform2D, logical: Vector2) -> bool:
	# 与选页共用真实屏幕和楼体高度投影。旋转视野的AABB角落并不在屏幕内，
	# 不能因此拒绝已完整就绪的切面；屏外地面上的楼顶若投影入屏仍必须覆盖。
	if not catalog.get("roots") is Array or catalog.roots.is_empty() or not cut.get("keys") is PackedStringArray or cut.keys.is_empty(): return false
	var selected := {}
	for key: String in cut.keys: selected[key]=true
	var projection := preload("res://scripts/experiments/volume_projection.gd")
	var ray := projection.ground_basis(canvas,deg_to_rad(38)).inverse()*projection.camera_basis(canvas,deg_to_rad(38)).z
	var roof := -Vector2(ray.x,ray.z)/ray.y
	for root: Dictionary in catalog.roots:
		if not _covers_projected_entry(root,selected,view,canvas,logical,roof): return false
	return true


static func _covers_projected_entry(entry: Dictionary, selected: Dictionary, view: Rect2, canvas: Transform2D, logical: Vector2, roof: Vector2) -> bool:
	if selected.has(entry.key): return true
	var projection := preload("res://scripts/rendering/tokyo_cells_overlay.gd")
	# 正式树在加载期合并了各档包络；旧夹具没有该证明时只能递归，不能猜父界。
	if entry.has("coverage_box") or entry.get("children",[]).is_empty():
		var bounds := projection.projected_layer_bounds(entry.get("coverage_box",entry.boxes[0]),roof,Vector2.ZERO)
		if not projection.intersects_view(bounds,view,canvas,logical): return true
	if entry.get("children",[]).is_empty(): return false
	for child: Dictionary in entry.children:
		if not _covers_projected_entry(child,selected,view,canvas,logical,roof): return false
	return true


static func uncovered_view(catalog: Dictionary, cut: Dictionary, view: Rect2) -> Array[Rect2]:
	# 预算等待和未来窄视野预取共用空间证明；尺度合格不代表仍盖满视野。
	if not view.has_area(): return []
	var uncovered: Array[Rect2]=[view]
	for key in cut.get("keys",PackedStringArray()):
		var bounds: Array=catalog.rows[key].bounds
		var page := Rect2(Vector2(bounds[0],bounds[1]),Vector2(bounds[2]-bounds[0],bounds[3]-bounds[1]))
		var remaining: Array[Rect2]=[]
		for part in uncovered:
			var overlap := part.intersection(page)
			if not overlap.has_area():
				remaining.append(part)
				continue
			for piece: Rect2 in [Rect2(part.position,Vector2(part.size.x,overlap.position.y-part.position.y)),
				Rect2(Vector2(part.position.x,overlap.end.y),Vector2(part.size.x,part.end.y-overlap.end.y)),
				Rect2(Vector2(part.position.x,overlap.position.y),Vector2(overlap.position.x-part.position.x,overlap.size.y)),
				Rect2(Vector2(overlap.end.x,overlap.position.y),Vector2(part.end.x-overlap.end.x,overlap.size.y))]:
				# Rect2为float32，矩形差集在共边处会留下约0.00006世界单位的伪细条。
				# 0.001世界单位在最高5倍下也仅0.005像素；真实像素缺口仍须拒绝。
				if piece.size.x>0.001 and piece.size.y>0.001: remaining.append(piece)
		uncovered=remaining
		if uncovered.is_empty(): return uncovered
	return uncovered


static func shared_texture_meshes(catalogs: Array[Dictionary]) -> Dictionary:
	# 同一图像和同一地理范围的相邻细档只补网格，不重复上传纹理。只生成纯请求，不授予显示资格。
	var result := {}
	for index in catalogs.size():
		var source: Dictionary=catalogs[index]
		if source.get("mixed_scales",false): continue
		var finer := -1
		for candidate in catalogs.size():
			if catalogs[candidate].get("mixed_scales",false) or float(catalogs[candidate].max_scale)<=float(source.max_scale): continue
			if finer<0 or float(catalogs[candidate].max_scale)<float(catalogs[finer].max_scale): finer=candidate
		if finer<0: continue
		var images := {}
		for row: Dictionary in catalogs[finer].rows.values():
			var image: String=row.native_texture.path
			if not images.has(image): images[image]=[]
			images[image].append(row)
		var aliases := {}
		for row: Dictionary in source.rows.values():
			for other: Dictionary in images.get(row.native_texture.path,[]):
				if row.bounds!=other.bounds or row.native_geometry.path==other.native_geometry.path: continue
				aliases[row.native_geometry.path]={"mesh":other.native_geometry.path,"image":row.native_texture.path}
				break
		if not aliases.is_empty(): result[index]=aliases
	return result


static func prefetch_changed(previous: Dictionary, next: Dictionary, catalog: int) -> bool:
	# 未设置的空列表与压缩字符串列表必须先归一化，不能直接跨类型比较。
	return PackedStringArray(previous.get("prefetch_keys",[]))!=PackedStringArray(next.get("prefetch_keys",[])) \
		or PackedStringArray(previous.get("guard_prefetch_keys",[]))!=PackedStringArray(next.get("guard_prefetch_keys",[])) \
		or int(previous.get("prefetch_catalog",catalog))!=int(next.get("prefetch_catalog",catalog)) \
		or bool(previous.get("path_prefetch_first",false))!=bool(next.get("path_prefetch_first",false)) \
		or Array(previous.get("prefetch_extra",[]))!=Array(next.get("prefetch_extra",[]))


static func prefetch_requests(catalogs: Array[Dictionary], cut: Dictionary, catalog: int) -> Array[Dictionary]:
	var requests: Array[Dictionary]=[]
	# 当前边缘与预测LOD是两份不同身份的清单；预测更新不得覆盖当前保护带。
	# 真实目标由调用者先排队；随后准备预测切面，最后才加载可能超显示预算的扩大保护带。
	var group := 0
	for pair: Array in [[cut.get("prefetch_catalog",catalog),cut.get("prefetch_keys",[])],[catalog,cut.get("guard_prefetch_keys",[])]]:
		if group==1 and cut.get("path_prefetch_first",false):
			requests.append_array(cut.get("prefetch_extra",[]))
		group+=1
		var index: int=pair[0]
		for key: String in pair[1]:
			requests.append({"mesh":key if index==-2 else catalogs[index].rows[key].native_geometry.path,
				"image":"" if index==-2 else catalogs[index].rows[key].native_texture.path})
	if not cut.get("path_prefetch_first",false): requests.append_array(cut.get("prefetch_extra",[]))
	return requests


static func native_covers_view(cut: Dictionary, view: Rect2) -> bool:
	var rows := {}
	for entry: Dictionary in cut.get("entries",[]):
		# 包顺序固定为低楼、高楼、地表；楼栋包络不证明地表覆盖。
		if not entry.mask[2]: continue
		var box: AABB=entry.boxes[2]
		rows[entry.path]={"bounds":[box.position.x,box.position.z,box.end.x,box.end.z]}
	return covers_view({"rows":rows},{"keys":PackedStringArray(rows.keys())},view)


static func streaming_bytes(geometry: Dictionary, textures: Dictionary, meshes: PackedStringArray, images: PackedStringArray, ground: int) -> int:
	if ground<0: return -1
	var physical: Dictionary={}
	for key: String in meshes:
		if not geometry.has(key): return -1
		var parts: Dictionary=geometry[key].get("components",{key:geometry[key]})
		for path: String in parts:
			if physical.has(path) and physical[path]!=parts[path]: return -1
			if not parts[path].get("bytes") is int or parts[path].bytes<0: return -1
			physical[path]=parts[path]
	for part: Dictionary in physical.values(): ground+=int(part.bytes)
	var seen: Dictionary={}
	for path: String in images:
		if seen.has(path): continue
		if not textures.has(path) or not textures[path].get("charge") is int or textures[path].charge<0: return -1
		seen[path]=true;ground+=int(textures[path].charge)
	return ground


static func append_streaming_bundle(ledger: Dictionary, geometry: Dictionary, textures: Dictionary, meshes: PackedStringArray, images: PackedStringArray, limit: int, fixed: Dictionary = {}) -> bool:
	# 单次请求计划的物理账本；先局部验证，整组可容纳才提交，拒绝不能留下半份记录。
	if not ledger.get("bytes") is int or ledger.bytes<0 or not ledger.get("meshes") is Dictionary or not ledger.get("images") is Dictionary: return false
	# 可选固定基底只读；增量账本无需复制数百个常驻键，仍逐身份核验本次请求。
	if not fixed.get("meshes",{}) is Dictionary or not fixed.get("images",{}) is Dictionary: return false
	var fixed_meshes: Dictionary=fixed.get("meshes",{})
	var fixed_images: Dictionary=fixed.get("images",{})
	var added_meshes := {}
	var added_images := {}
	var amount: int=ledger.bytes
	for path: String in meshes:
		if not geometry.has(path): return false
		var parts: Dictionary=geometry[path].get("components",{path:geometry[path]})
		for physical: String in parts:
			var row: Dictionary=parts[physical]
			if not row.get("bytes") is int or row.bytes<0: return false
			if fixed_meshes.has(physical):
				if fixed_meshes[physical]!=row: return false
			elif ledger.meshes.has(physical):
				if ledger.meshes[physical]!=row: return false
			elif added_meshes.has(physical):
				if added_meshes[physical]!=row: return false
			else:
				added_meshes[physical]=row;amount+=int(row.bytes)
	for path: String in images:
		if not textures.has(path) or not textures[path].get("charge") is int or textures[path].charge<0: return false
		if fixed_images.has(path):
			if fixed_images[path]!=int(textures[path].charge): return false
			continue
		if not ledger.images.has(path) and not added_images.has(path):
			added_images[path]=int(textures[path].charge);amount+=int(textures[path].charge)
	if amount>limit: return false
	ledger.meshes.merge(added_meshes);ledger.images.merge(added_images);ledger.bytes=amount
	return true


static func combined_bytes(left: Dictionary, left_cut: Dictionary, right: Dictionary, right_cut: Dictionary) -> int:
	var meshes: Dictionary = {}
	var textures: Dictionary = {}
	var ground := 0
	for pair: Array in [[left,left_cut],[right,right_cut]]:
		var catalog: Dictionary = pair[0]
		var cut: Dictionary = pair[1]
		if not cut.get("keys") is PackedStringArray: return -1
		var charge := Contract.charges(catalog,cut.keys)
		if charge.is_empty() or not charge.within_budget: return -1
		ground+=int(charge.ground_bytes)
		for key: String in cut.keys:
			var row: Dictionary = catalog.rows[key]
			for mapping: Array in [[meshes,row.native_geometry],[textures,row.native_texture]]:
				var seen: Dictionary = mapping[0]
				var binding: Dictionary = mapping[1]
				if seen.has(binding.path) and seen[binding.path]!=binding: return -1
				seen[binding.path]=binding
	for binding: Dictionary in meshes.values(): ground+=int(binding.bytes)
	for binding: Dictionary in textures.values(): ground+=int(binding.three_copy_charge)
	return ground


static func qualified(catalog: Dictionary, cut: Dictionary, scale: float) -> bool:
	if not is_finite(scale) or scale<=0 or scale>float(catalog.get("max_scale",-INF)): return false
	if not cut.get("keys") is PackedStringArray or cut.keys.is_empty(): return false
	for key: String in cut.keys:
		if not catalog.rows.has(key) or scale>float(catalog.rows[key].get("max_scale",INF)): return false
	return true
