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


static func prefetch_changed(previous: Dictionary, next: Dictionary, catalog: int) -> bool:
	# 未设置的空列表与压缩字符串列表必须先归一化，不能直接跨类型比较。
	return PackedStringArray(previous.get("prefetch_keys",[]))!=PackedStringArray(next.get("prefetch_keys",[])) \
		or PackedStringArray(previous.get("guard_prefetch_keys",[]))!=PackedStringArray(next.get("guard_prefetch_keys",[])) \
		or int(previous.get("prefetch_catalog",catalog))!=int(next.get("prefetch_catalog",catalog)) \
		or Array(previous.get("prefetch_extra",[]))!=Array(next.get("prefetch_extra",[]))


static func prefetch_requests(catalogs: Array[Dictionary], cut: Dictionary, catalog: int) -> Array[Dictionary]:
	var requests: Array[Dictionary]=[]
	# 当前边缘与预测LOD是两份不同身份的清单；预测更新不得覆盖当前保护带。
	# 真实目标由调用者先排队；随后准备预测切面，最后才加载可能超显示预算的扩大保护带。
	for pair: Array in [[cut.get("prefetch_catalog",catalog),cut.get("prefetch_keys",[])],[catalog,cut.get("guard_prefetch_keys",[])]]:
		var index: int=pair[0]
		for key: String in pair[1]:
			requests.append({"mesh":key if index==-2 else catalogs[index].rows[key].native_geometry.path,
				"image":"" if index==-2 else catalogs[index].rows[key].native_texture.path})
	requests.append_array(cut.get("prefetch_extra",[]))
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
