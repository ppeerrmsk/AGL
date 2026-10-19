extends RefCounted
## Single-owner pure-value policy. No SceneTree, resources, global frame state or synchronous I/O.
const Contract := preload("res://scripts/rendering/tokyo_hlod_manifest.gd")
const Handoff := preload("res://scripts/rendering/tokyo_hlod_handoff.gd")
const Native := preload("res://scripts/rendering/tokyo_hlod_native.gd")
class Stream:
	const BUDGET := 96*1024*1024
var _catalogs: Array[Dictionary]=[]
var _geometry: Dictionary={}
var _textures: Dictionary={}
var _foundation: Dictionary={}
var _native: RefCounted
var _selection_work: Dictionary={}
var _flags: Dictionary={}
var _small_uploads := false
var display_budget := Stream.BUDGET
var _bounds := Rect2()
var _logical := Vector2.ZERO
var _last_size := Vector2.ZERO
var _last_canvas := Transform2D()
var _pan_velocity := Vector2.ZERO
var _zoom_rate := 0.0
var _committed := PackedStringArray()
var _committed_catalog := -1
var _committed_cut: Dictionary={}
var _target_catalog := -1
var _target: Dictionary={}
var _stream: Dictionary={}
var _force_replan := false
var _ground_candidate_state: Dictionary={}
var _native_screen_bridge_state: Dictionary={}
var _speculative_cache: Dictionary={}
var pending_selection_reuses := 0
var native_screen_rejections := 0
var retained_cuts := 0
var _cached_cut_attempts := 0
var foundation_prefetch_skips := 0
var speculative_plan_reuses := 0
var motion_actual_cuts := 0
var selection_usec := 0


func configure(source: Dictionary) -> bool:
	if not source.get("catalogs") is Array or source.catalogs.is_empty(): return false
	if not Contract.selection_context_valid(source.get("context",{})): return false
	_native=null
	_speculative_cache={}
	_ground_candidate_state={};_native_screen_bridge_state={}
	pending_selection_reuses=0;native_screen_rejections=0;retained_cuts=0
	_cached_cut_attempts=0;foundation_prefetch_skips=0;speculative_plan_reuses=0;motion_actual_cuts=0;selection_usec=0
	_catalogs.assign(source.catalogs)
	_geometry=source.geometry;_textures=source.textures
	_foundation=source.get("foundation",{});_bounds=source.bounds
	_flags=source.get("flags",{});_small_uploads=_flags.get("small_uploads",false)
	_selection_work=source.context.duplicate(true)
	_selection_work["prepared_catalogs"]=source.get("prepared_catalogs",{})
	display_budget=int(_selection_work.display_limit)
	if not source.get("native",{}).is_empty():
		_native=Native.new()
		if not _native.configure_selection_snapshot(source.native,source.context): return false
	return true


func plan(request: Dictionary) -> Dictionary:
	_last_canvas=request.canvas;_last_size=request.size;_logical=request.logical
	_pan_velocity=request.pan_velocity;_zoom_rate=request.zoom_rate
	_committed_catalog=request.committed_catalog;_committed_cut=request.committed
	_committed=PackedStringArray(_committed_cut.get("keys",[]))
	_target_catalog=request.target_catalog;_target=request.target
	_stream=request.stream
	_selection_work["epoch"]=int(request.sequence)
	if _native!=null: _native.selection_context["epoch"]=int(request.sequence)
	_force_replan=false
	var scale_value: float=request.scale
	var zooming_out: bool=request.zooming_out
	var current_covered := _committed_catalog!=-1 and _cut_covers_current_view(_committed_cut,_committed_catalog)
	var handoff_budget: int=_stream.residency_limit-_stream.residency_bytes
	var selected := Handoff.catalog_index(_catalogs,scale_value,not zooming_out)
	var foundation_catalog := preload("res://scripts/rendering/tokyo_hlod_foundation.gd").catalog_at(_foundation,scale_value,selected)
	# 新中景本身是完整合格显示表示；相邻细档另由预测I/O准备，不提前替换画面。
	if foundation_catalog<0:
		var actual_foundation := preload("res://scripts/rendering/tokyo_hlod_foundation.gd").catalog_at(_foundation,scale_value)
		if actual_foundation>=0 and _catalogs[actual_foundation].has("middle_massing_recipe"): foundation_catalog=actual_foundation
	if foundation_catalog>=0: selected=foundation_catalog
	var next: Dictionary = {}
	if selected<0 and _native!=null and scale_value>0.1944: selected=-2
	if selected>=0 or selected==-2:
		var selection_start := Time.get_ticks_usec()
		var center := _last_canvas.affine_inverse()*(_logical*0.5)
		# 双向缩放均先完成仍完整合格的在途桥接档，缩远还须保留96px余量。
		# 在求树前判断：原先先重算半池/全池再无条件覆盖结果，等待I/O时每帧白算。
		if _pending_hlod_covers(scale_value,zooming_out):
			selected=_target_catalog
			next=_target
			pending_selection_reuses+=1
		else:
			# 常驻页不必为重新加载同一资源预留半池；仍守原96MiB显示门。
			if foundation_catalog>=0:
				next=preload("res://scripts/rendering/tokyo_hlod_foundation.gd").select(_catalogs[selected],_foundation.layers[selected].entries,center,scale_value,_last_canvas.get_rotation(),_last_size,display_budget,_selection_work)
			if next.is_empty():
				next=_select_native(center,scale_value,_last_canvas.get_rotation(),_last_size,"",Stream.BUDGET/2) if selected==-2 else _select_hlod(_catalogs[selected],center,scale_value,_last_canvas.get_rotation(),_last_size,true,Stream.BUDGET/2)
			# 稳态优先留出一份交接空间；完整清晰切面确实放不下才使用全预算。
			if selected>=0 and not next.is_empty() and not next.within_budget:
				next=_select_hlod(_catalogs[selected],center,scale_value,_last_canvas.get_rotation(),_last_size,true)
			elif selected==-2 and (next.is_empty() or not next.within_budget):
				next=_select_native(center,scale_value,_last_canvas.get_rotation(),_last_size)
		# 运动中提前细档只剩撑不过0.25秒平移的保护带时，显示改用实际档的带保护完整切面。
		if selected>=0 and not next.is_empty() and next.within_budget:
			var guarded := _motion_guarded_actual(selected,next,center,scale_value,_last_canvas.get_rotation(),_last_size,handoff_budget)
			if not guarded.is_empty(): next=guarded;selected=Handoff.catalog_index(_catalogs,scale_value,false);motion_actual_cuts+=1
		# 原生是细节偏好，不得取消仍完整合格的HLOD在途事务；提交后再升级。
		var finishing_hlod := selected>=0 and selected==_target_catalog and not _target_committed() \
			and not next.is_empty() and Contract.retained(_catalogs[selected],_target,next,scale_value,true,_selection_work)
		if _native!=null and not _native.ground.is_empty(): _ground_candidate_state={"deferred":finishing_hlod}
		if not finishing_hlod and (next.is_empty() or not next.within_budget):
			var current_foundation := preload("res://scripts/rendering/tokyo_hlod_foundation.gd").catalog_at(_foundation,scale_value)
			if current_foundation>=0:
				var fixed := preload("res://scripts/rendering/tokyo_hlod_foundation.gd").select(_catalogs[current_foundation],_foundation.layers[current_foundation].entries,center,scale_value,_last_canvas.get_rotation(),_last_size,display_budget,_selection_work)
				# 提前细档无解时仍有完整常驻切面，不能转求昂贵原生树；预测预取另走原路径。
				if not fixed.is_empty(): next=fixed;selected=current_foundation
		if _flags.get("actual_before_native",false) and not finishing_hlod:
			var actual_index := Handoff.actual_fallback(_catalogs,selected,scale_value,not next.is_empty() and next.within_budget)
			if actual_index>=0:
				var actual_cut := _select_hlod(_catalogs[actual_index],center,scale_value,_last_canvas.get_rotation(),_last_size,false,Stream.BUDGET/2)
				if not actual_cut.is_empty() and not actual_cut.within_budget:
					actual_cut=_select_hlod(_catalogs[actual_index],center,scale_value,_last_canvas.get_rotation(),_last_size,false)
				if not actual_cut.is_empty() and actual_cut.within_budget:
					next=actual_cut;selected=actual_index
		# 近景预算允许时保留原生高楼细节；超限密集区才使用已合格HLOD，绝不强降原生档。
		# 原生偏好是显示选择，不是预取资格；乘提前比例会在合格HLOD仍足够时过早切回重地表。
		if not finishing_hlod and selected>=0 and _native!=null and not _native.ground.is_empty():
			var ground_configuration: String=_native.ground_configuration(scale_value)
			if not ground_configuration.is_empty():
				var hybrid: Dictionary=_select_native(center,scale_value,_last_canvas.get_rotation(),_last_size,ground_configuration,display_budget)
				var hybrid_union := 0 if _committed.is_empty() else _handoff_bytes(hybrid,-2)
				_ground_candidate_state={"deferred":false,"configuration":ground_configuration,"faces":hybrid.get("triangles",0),"bytes":hybrid.get("bytes",0),"images":hybrid.get("ground_images",[]).size(),"guard":hybrid.get("spatial_guard_px",0),"within_budget":hybrid.get("within_budget",false),"handoff_bytes":hybrid_union,"handoff_budget":handoff_budget}
				if not hybrid.get("ground_images",PackedStringArray()).is_empty() and Handoff.native_preference_qualified(hybrid,scale_value,_zoom_rate) and Handoff.native_preference(hybrid,hybrid_union,handoff_budget) and float(hybrid.get("spatial_guard_px",0))>0:
					next=hybrid;selected=-2
		if not finishing_hlod and selected>=0 and _native!=null and scale_value>0.1944 and (next.is_empty() or not next.within_budget or (not zooming_out and scale_value>float(_catalogs[selected].get("prefer_native_above",INF)))):
			var native_cut := _select_native_fallback(center,scale_value,_last_canvas.get_rotation(),_last_size,next.is_empty() or not next.within_budget)
			var native_union := -1 if native_cut.is_empty() else (0 if _committed.is_empty() else _handoff_bytes(native_cut,-2))
			if Handoff.native_preference_qualified(native_cut,scale_value,_zoom_rate) and Handoff.native_preference(native_cut,native_union,handoff_budget) and (next.is_empty() or not next.within_budget or float(native_cut.get("spatial_guard_px",0))>0.0):
				# 原生档若足以接替整段HLOD资格，也属于提前交接；不只标记原生内部升档。
				native_cut["prefetched_native"]=Handoff.native_qualified(native_cut,float(_catalogs[selected].max_scale))
				selected=-2
				next=native_cut
		if not finishing_hlod and _native!=null and (next.is_empty() or not next.within_budget):
			var current_ground := _select_current_ground(center,scale_value,_last_canvas.get_rotation(),_last_size,display_budget)
			if not current_ground.is_empty(): next=current_ground;selected=-2
		if selected==-2 and not next.is_empty() and next.get("ground_images",PackedStringArray()).is_empty():
			var archive := preload("res://scripts/rendering/tokyo_volume_archive.gd")
			var early_configuration := "lod%d_full" % archive.choose_level(-1,scale_value*0.90/Contract.PREFETCH_RATIO)
			if _target_catalog==-2 and not _target_committed():
				early_configuration=Handoff.loading_configuration(_target,scale_value,early_configuration)
			if early_configuration!=next.configuration:
				var early: Dictionary=_select_native(center,scale_value,_last_canvas.get_rotation(),_last_size,early_configuration,Stream.BUDGET/2)
				if early.is_empty() or not early.within_budget: early=_select_native(center,scale_value,_last_canvas.get_rotation(),_last_size,early_configuration)
				var early_bytes := -1 if early.is_empty() else (0 if _committed.is_empty() else _handoff_bytes(early,-2))
				if not early.is_empty() and early.within_budget and early_bytes>=0 and early_bytes<=handoff_budget:
					early["prefetched_native"]=true
					next=early
		if selected>=0 and selected==_target_catalog and not next.is_empty() and (not _target_committed() or int(_target.get("bytes",display_budget))<=maxi(Stream.BUDGET/2,int(next.bytes))) and Contract.retained(_catalogs[selected],_target,next,scale_value,true,_selection_work):
			next=_target
			retained_cuts+=1
		# 提前细档的联合费用过高时，先尝试当前清晰度的完整桥接。
		# 半池只是首选；同池重叠允许超过半池的切面，保护带也必须逐档验联合费用。
		if selected>=0 and not _committed.is_empty() and _committed_qualified(scale_value) \
			and (next.is_empty() or not next.within_budget or _handoff_bytes(next,selected)>handoff_budget):
			var actual_catalog := Handoff.catalog_index(_catalogs,scale_value,false)
			var bridge_catalogs: Array[int]=[]
			if _committed_catalog>=0: bridge_catalogs.append(_committed_catalog)
			if actual_catalog>=0 and actual_catalog!=_committed_catalog: bridge_catalogs.append(actual_catalog)
			for bridge_catalog: int in bridge_catalogs:
				var handoff_cut := _select_handoff_hlod(bridge_catalog,center,scale_value,_last_canvas.get_rotation(),_last_size,handoff_budget,display_budget)
				if not handoff_cut.is_empty():
					next=handoff_cut;selected=bridge_catalog
					break
		# 只裁掉当前和短期前探都不需要的旧页；运动包络仍由完整目录证明。
		if selected>=0 and not next.is_empty() and _committed_catalog>=0 and _committed_qualified(scale_value) \
			and _handoff_bytes(next,selected)>handoff_budget \
			and current_covered:
			var trim_lead := Handoff.pan_lead(_pan_velocity,scale_value,0.25,_last_size)
			var visible_old := Contract.visible_subset(_catalogs[_committed_catalog],_committed_cut,center,scale_value,_last_canvas.get_rotation(),_last_size,_selection_work,trim_lead)
			if not visible_old.is_empty() and visible_old.within_budget and visible_old.keys.size()<_committed.size() \
				and Handoff.covers_motion_view(_catalogs[_committed_catalog],visible_old,center,scale_value,_last_canvas.get_rotation(),_last_size,trim_lead):
				visible_old["selection_stage"]="trim"
				next=visible_old;selected=_committed_catalog
				# 裁页不需I/O；下一帧继续原换档事务，即使相机已停止也不能搁置。
				_force_replan=true
		# 不只按稳态最低面数选页：交接需给仍在显示的旧切面留足物理内存。
		if selected>=0 and not next.is_empty() and not _committed.is_empty() and _handoff_bytes(next,selected)>handoff_budget:
			var current_bytes := _handoff_bytes({"keys":PackedStringArray()},selected)
			var remaining := clampi(handoff_budget-current_bytes,0,display_budget) if current_bytes>=0 else 0
			var compact := _select_hlod(_catalogs[selected],center,scale_value,_last_canvas.get_rotation(),_last_size,true,remaining)
			if not compact.is_empty() and compact.within_budget:
				var compact_bytes := _handoff_bytes(compact,selected)
				if compact_bytes>=0 and compact_bytes<=handoff_budget:
					compact["selection_stage"]="compact"
					next=compact
			# 先预取新档的到期尺度切面，避免旧档再分块的I/O吃掉新档加载窗口；提交另验真实覆盖。
			if _handoff_bytes(next,selected)>handoff_budget and _committed_catalog>=0 and _committed_qualified(scale_value):
				var future_scale := Handoff.scale_limit(_catalogs[_committed_catalog],_committed_cut) if current_covered else 0.0
				if future_scale>scale_value:
					var anticipated := _select_hlod(_catalogs[selected],center,future_scale,_last_canvas.get_rotation(),_last_size,true,Stream.BUDGET/2)
					if not anticipated.is_empty() and not anticipated.within_budget:
						anticipated=_select_hlod(_catalogs[selected],center,future_scale,_last_canvas.get_rotation(),_last_size,true)
					if not anticipated.is_empty() and anticipated.within_budget:
						var anticipated_bytes := _handoff_bytes(anticipated,selected)
						if anticipated_bytes>=0 and anticipated_bytes<=handoff_budget:
							anticipated["anticipated_scale"]=future_scale
							anticipated["selection_stage"]="anticipated"
							next=anticipated
			# 新档提前切面仍放不下，才缩减旧档桥接；空间前提和联合预算均不放宽。
			if _handoff_bytes(next,selected)>handoff_budget and _committed_catalog>=0 and _committed_qualified(scale_value):
				var bridge := _select_hlod(_catalogs[_committed_catalog],center,scale_value,_last_canvas.get_rotation(),_last_size,true,Stream.BUDGET/2)
				if not bridge.is_empty() and bridge.within_budget and int(bridge.charges.total_bytes)<current_bytes:
					var bridge_bytes := _handoff_bytes(bridge,_committed_catalog)
					if bridge_bytes>=0 and bridge_bytes<=handoff_budget:
							bridge["selection_stage"]="compact_bridge"
							next=bridge;selected=_committed_catalog
		# 提前档超预算不等于当前尺度无解；先退回实际尺度合格的完整切面，不能直接清屏。
		if next.is_empty() or not next.within_budget:
			for n in _catalogs.size():
				var catalog: Dictionary=_catalogs[n]
				if scale_value<float(catalog.min_scale) or scale_value>float(catalog.max_scale): continue
				var current_cut := _select_hlod(catalog,center,scale_value,_last_canvas.get_rotation(),_last_size,false,Stream.BUDGET/2)
				if not current_cut.is_empty() and not current_cut.within_budget:
					current_cut=_select_hlod(catalog,center,scale_value,_last_canvas.get_rotation(),_last_size)
				if not current_cut.is_empty() and current_cut.within_budget:
					next=current_cut;selected=n
					break
		if not next.is_empty() and next.within_budget:
			var predicted := _predict_prefetch(center,scale_value,_last_canvas.get_rotation(),_last_size)
			if not predicted.is_empty():
				# next可能与在途目标共享Dictionary；先复制，才能正确检测预取身份变化。
				next=next.duplicate()
				next["prefetch_catalog"]=predicted.catalog
				next["prefetch_keys"]=predicted.keys
				next["prefetch_extra"]=predicted.extra
			# 显式对照：旧页已缺边时，优先用缓存内完整合格切面接住；原目标继续预取。
			if _flags.get("cached_cut",false) and (not current_covered or not _committed_qualified(scale_value)) and not _committed.is_empty() and not _resources_ready(next,selected):
				_cached_cut_attempts+=1
				var cached := preload("res://scripts/rendering/tokyo_hlod_cached_cut.gd")
				var native_bridge: Dictionary={}
				if selected==-2 and _flags.get("native_screen_bridge",false):
					native_bridge=_native_screen_bridge(next,center,scale_value,_last_canvas.get_rotation(),_last_size,handoff_budget)
				if not native_bridge.is_empty(): next=native_bridge
				for cached_index: int in cached.candidate_catalogs(_catalogs,selected,_committed_catalog,scale_value) if native_bridge.is_empty() else PackedInt32Array():
					var ready_cut: Dictionary={}
					if _foundation.get("layers",{}).has(cached_index):
						ready_cut=preload("res://scripts/rendering/tokyo_hlod_foundation.gd").select(_catalogs[cached_index],_foundation.layers[cached_index].entries,center,scale_value,_last_canvas.get_rotation(),_last_size,display_budget,_selection_work)
						if not _resources_ready(ready_cut,cached_index): ready_cut={}
					if ready_cut.is_empty():
						ready_cut=cached.select(_catalogs[cached_index],center,scale_value,_last_canvas.get_rotation(),_last_size,_geometry,_stream._cache,_stream._textures,_selection_work)
					var ready_union := -1 if ready_cut.is_empty() else _handoff_bytes(ready_cut,cached_index)
					if ready_cut.is_empty() or (cached_index==selected and ready_cut.keys==next.keys) or ready_union<0 or ready_union>handoff_budget: continue
					var extras := Handoff.prefetch_requests(_catalogs,next,selected)
					for key: String in next.keys:
						extras.append({"mesh":key if selected==-2 else _catalogs[selected].rows[key].native_geometry.path,
							"image":"" if selected==-2 else _catalogs[selected].rows[key].native_texture.path})
					ready_cut["prefetch_extra"]=extras
					ready_cut["cache_bridge"]=true
					next=ready_cut;selected=cached_index
					break
		selection_usec+=Time.get_ticks_usec()-selection_start
	return {"status":"candidate" if next.get("within_budget",false) else "no_solution",
		"catalog":selected,"cut":compact_cut(next),"force_replan":_force_replan,
		"ground_candidate":_ground_candidate_state.duplicate(true),"native_screen_bridge":_native_screen_bridge_state.duplicate(true),
		"stats":{"selection_usec":selection_usec,"retained_cuts":retained_cuts,"pending_reuses":pending_selection_reuses,
			"native_screen_rejections":native_screen_rejections,"cached_cut_attempts":_cached_cut_attempts,
			"foundation_prefetch_skips":foundation_prefetch_skips,"speculative_plan_reuses":speculative_plan_reuses,"motion_actual_cuts":motion_actual_cuts,
			"hlod_builds":_selection_work.get("builds",0),"hlod_reuses":_selection_work.get("reuses",0),
			"qualification_builds":_selection_work.get("qualification_builds",0),"prepared_reuses":_selection_work.get("prepared_reuses",0),
			"native_builds":_native.solver_builds if _native!=null else 0,"native_reuses":_native.solver_reuses if _native!=null else 0}}


static func compact_cut(cut: Dictionary) -> Dictionary:
	var result := cut.duplicate()
	if cut.has("entries"):
		var entries: Array[Dictionary]=[]
		for entry: Dictionary in cut.entries:
			var item := entry.duplicate()
			item.erase("children")
			entries.append(item)
		result["entries"]=entries
	return result.duplicate(true)


func _cut_covers_current_view(cut: Dictionary, catalog: int, margin_px: float = 0.0) -> bool:
	var margin := Vector2.ONE*margin_px*_logical/_last_size
	var canvas := _last_canvas
	canvas.origin+=margin
	var size := _logical+2.0*margin
	var inverse := canvas.affine_inverse()
	var view := Rect2(inverse*Vector2.ZERO,Vector2.ZERO)
	for point: Vector2 in [Vector2(size.x,0),size,Vector2(0,size.y)]: view=view.expand(inverse*point)
	view=view.intersection(_bounds)
	if catalog>=0: return Handoff.covers_projection(_catalogs[catalog],cut,view,canvas,size)
	return _native!=null and _native.covers_visible_layers(cut,view,canvas,size)


func _resources_ready(cut: Dictionary, catalog: int) -> bool:
	if cut.get("keys",PackedStringArray()).is_empty(): return false
	for path: String in cut.get("ground_images",[]):
		if not _stream._textures.has(path): return false
	for key: String in cut.keys:
		var path := key
		if catalog>=0:
			var row: Dictionary=_catalogs[catalog].rows[key]
			path=row.native_geometry.path
			if not _stream._textures.has(row.native_texture.path): return false
		if not _geometry.has(path): return false
		for part: String in _geometry[path].get("components",{path:{}}):
			if not _stream._cache.has(part): return false
	return true


func _handoff_bytes(next: Dictionary, selected: int) -> int:
	var meshes := PackedStringArray()
	var images := PackedStringArray()
	var ground := 0
	for pair: Array in [[_committed_catalog,_committed_cut],[selected,next]]:
		var index: int=pair[0]
		var cut: Dictionary=pair[1]
		ground+=int(cut.get("charges",{}).get("ground_bytes",0))
		images.append_array(PackedStringArray(cut.get("ground_images",[])))
		for key: String in cut.get("keys",[]):
			if index==-2: meshes.append(key)
			else:
				var row: Dictionary=_catalogs[index].rows[key]
				meshes.append(row.native_geometry.path);images.append(row.native_texture.path)
	var fixed := {"bytes":0,"meshes":{},"images":{}}
	if not Handoff.append_streaming_bundle(fixed,_geometry,_textures,_stream.residency_meshes,_stream.residency_images,9223372036854775807): return -1
	if int(fixed.bytes)!=int(_stream.residency_bytes): return -1
	var delta := {"bytes":ground,"meshes":{},"images":{}}
	return int(delta.bytes) if Handoff.append_streaming_bundle(delta,_geometry,_textures,meshes,images,9223372036854775807,fixed) else -1


func _pending_hlod_covers(scale_value: float, zooming_out: bool) -> bool:
	# 普通保护带事务也可能即将到期；沿用桥接的0.25秒资格，不能占住下一细档的加载窗口。
	return _target_catalog>=0 and not _target_committed() and not _target.has("anticipated_scale") \
		and Handoff.qualified(_catalogs[_target_catalog],_target,scale_value) \
		and _handoff_bridge_qualified(_target_catalog,_target,scale_value) \
		and _target_covers_current_view(96.0 if zooming_out else 0.0)


func _select_hlod(catalog: Dictionary, center: Vector2, scale: float, angle: float, size: Vector2, finer: bool = false, budget: int = -1, include_zoom_footprint: bool = true) -> Dictionary:
	if budget==-1:
		# 扩大硬上限不能把原48/96MiB首选一起抬高；原切面可用时保持原资源身份。
		if display_budget>Stream.BUDGET:
			var original := _select_hlod(catalog,center,scale,angle,size,finer,Stream.BUDGET,include_zoom_footprint)
			if not original.is_empty() and original.within_budget: return original
		budget=display_budget
	for index: int in _foundation.get("layers",{}):
		if _catalogs[index]!=catalog: continue
		var fixed := preload("res://scripts/rendering/tokyo_hlod_foundation.gd").select(catalog,_foundation.layers[index].entries,center,scale,angle,size,budget,_selection_work)
		if not fixed.is_empty():
			return fixed
	# 空间提前量与缩放提前量独立；保持真实像素尺度，不能用降低scale冒充扩区。
	var lead := Handoff.pan_lead(_pan_velocity,scale,0.35,size)
	var padding := (Transform2D(angle,Vector2.ZERO).basis_xform(lead)*scale).abs()+Vector2(384,384)
	if include_zoom_footprint: padding+=Handoff.zoom_out_padding(_zoom_rate,size)
	var expanded := Contract.select(catalog,center+lead*0.5,scale,angle,size+padding,finer,budget,_selection_work,_small_uploads)
	var expanded_retry := false
	if (expanded.is_empty() or not expanded.within_budget) and budget<display_budget:
		var full := Contract.select(catalog,center+lead*0.5,scale,angle,size+padding,finer,display_budget,_selection_work,_small_uploads)
		var index := _catalogs.find(catalog)
		if not full.is_empty() and full.within_budget:
			var combined := 0 if _committed.is_empty() else (_handoff_bytes(full,index) if index>=0 else -1)
			if combined>=0 and (_committed.is_empty() or combined<=_stream.residency_limit-_stream.residency_bytes):
				expanded=full;expanded_retry=true
			elif index>=0 and combined>_stream.residency_limit-_stream.residency_bytes:
				# 同档完整切面因旧页占池失败时，先求共享资源前沿，不能直接丢掉保护带。
				var shared := _select_handoff_hlod(index,center,scale,angle,size,
					_stream.residency_limit-_stream.residency_bytes,display_budget,192.0,include_zoom_footprint)
				if not shared.is_empty():
					shared["selection_stage"]="hlod_guard_shared"
					return shared
	if not expanded.is_empty() and expanded.within_budget:
		expanded["spatial_guard_px"]=192
		expanded["selection_stage"]="hlod_guard_retry" if expanded_retry else "hlod_guard"
		return expanded
	# 每档保护带都先验首选预算，再验显示上限与同一真实联合预算，最后才收窄。
	for ratio: float in [0.5,0.25]:
		var reduced := Contract.select(catalog,center+lead*0.5*ratio,scale,angle,size+padding*ratio,finer,budget,_selection_work,_small_uploads)
		var reduced_retry := false
		if (reduced.is_empty() or not reduced.within_budget) and budget<display_budget:
			var full := Contract.select(catalog,center+lead*0.5*ratio,scale,angle,size+padding*ratio,finer,display_budget,_selection_work,_small_uploads)
			var index := _catalogs.find(catalog)
			if not full.is_empty() and full.within_budget:
				var combined := 0 if _committed.is_empty() else (_handoff_bytes(full,index) if index>=0 else -1)
				if combined>=0 and (_committed.is_empty() or combined<=_stream.residency_limit-_stream.residency_bytes):
					reduced=full;reduced_retry=true
				elif index>=0 and combined>_stream.residency_limit-_stream.residency_bytes:
					var shared := _select_handoff_hlod(index,center,scale,angle,size,
						_stream.residency_limit-_stream.residency_bytes,display_budget,192.0*ratio,include_zoom_footprint)
					if not shared.is_empty():
						shared["selection_stage"]="hlod_guard_shared"
						return shared
		if not reduced.is_empty() and reduced.within_budget:
			reduced["spatial_guard_px"]=192*ratio
			reduced["selection_stage"]="hlod_guard_retry" if reduced_retry else "hlod_guard"
			return reduced
	var actual := Contract.select(catalog,center,scale,angle,size,finer,budget,_selection_work,_small_uploads)
	if actual.is_empty(): return {}
	actual["spatial_guard_px"]=0
	actual["selection_stage"]="hlod_actual"
	actual["guard_rejection"]={"faces":expanded.get("triangles",0),"bytes":expanded.get("bytes",0),"budget":budget,"kind":"hlod"}
	# 超显示面数/字节的扩区只能作为未绑定预取集，绝不作为合格显示切面提交。
	actual["guard_prefetch_keys"]=expanded.get("keys",PackedStringArray())
	return actual


func _handoff_bridge_qualified(index: int, cut: Dictionary, scale: float) -> bool:
	# 与既有预测I/O共用0.25秒视窗；快速放大时不能靠低档桥接拖延即将到期的换档。
	var future_scale := scale*exp(clampf(_zoom_rate*0.25,0.0,0.7))
	return Handoff.qualified(_catalogs[index],cut,future_scale)


func _motion_guarded_actual(selected: int, next: Dictionary, center: Vector2, scale: float, angle: float, size: Vector2, handoff_budget: int) -> Dictionary:
	# 提前细档受16页/面数/预算所限常只剩裸视野；运动中这类切面一两帧即失去覆盖。
	# 实际档须在换档前探窗内合格、保护带更宽且可同池交接；细档仍由预测预取准备。
	var guard := float(next.get("spatial_guard_px",0.0))
	var need := Handoff.motion_guard_need(_pan_velocity,scale,size)
	if guard>=need or _foundation.get("layers",{}).has(selected): return {}
	var actual := Handoff.catalog_index(_catalogs,scale,false)
	if actual<0 or actual==selected: return {}
	var cut := _select_hlod(_catalogs[actual],center,scale,angle,size,false,Stream.BUDGET/2)
	if not cut.is_empty() and not cut.within_budget: cut=_select_hlod(_catalogs[actual],center,scale,angle,size)
	if cut.is_empty() or not cut.within_budget or float(cut.get("spatial_guard_px",0.0))<=guard \
		or not Handoff.motion_actual_qualified(_catalogs[actual],cut,scale,_zoom_rate): return {}
	if not _committed.is_empty():
		var union := _handoff_bytes(cut,actual)
		if union<0 or union>handoff_budget: return {}
	cut["motion_guard_need_px"]=need
	return cut


func _select_handoff_hlod(index: int, center: Vector2, scale: float, angle: float, size: Vector2, budget: int, max_display_bytes: int = -1, min_guard_px: float = 0.0, include_zoom_footprint: bool = true) -> Dictionary:
	if not is_finite(min_guard_px) or min_guard_px<0.0: return {}
	var future_scale := scale*exp(clampf(_zoom_rate*0.25,0.0,0.7))
	if future_scale>float(_catalogs[index].max_scale): return {}
	var lead := Handoff.pan_lead(_pan_velocity,scale,0.35,size)
	var padding := (Transform2D(angle,Vector2.ZERO).basis_xform(lead)*scale).abs()+Vector2(384,384)
	if include_zoom_footprint: padding+=Handoff.zoom_out_padding(_zoom_rate,size)
	var current_bytes := _handoff_bytes({"keys":PackedStringArray()},index)
	if current_bytes<0 or current_bytes>=budget: return {}
	var costs := _handoff_incremental_costs(index)
	var roots := Contract.handoff_roots(_catalogs[index],maxf(scale,future_scale),costs,_selection_work)
	for ratio: float in [1.0,0.5,0.25,0.0]:
		if 192.0*ratio<min_guard_px: continue
		var candidate := Contract.select_handoff(_catalogs[index],center+lead*0.5*ratio,scale,angle,size+padding*ratio,budget-current_bytes,costs,_selection_work,index==_committed_catalog,future_scale,roots)
		if candidate.is_empty() or not candidate.within_budget or not _handoff_bridge_qualified(index,candidate,scale): continue
		# 少量新增前方页可维持覆盖；显示上限和真实联合费用共同约束，不强制逐次缩费。
		if int(candidate.bytes)>mini(display_budget,max_display_bytes if max_display_bytes>=0 else display_budget): continue
		var combined := _handoff_bytes(candidate,index)
		if combined<0 or combined>budget: continue
		if not _cut_covers_current_view(candidate,index): continue
		candidate["spatial_guard_px"]=192*ratio
		candidate["handoff_bridge"]=true
		candidate["selection_stage"]="handoff"
		return candidate
	return {}


func _handoff_incremental_costs(index: int) -> Dictionary:
	var meshes := PackedStringArray()
	var images := PackedStringArray(_committed_cut.get("ground_images",[]))
	for key: String in _committed:
		if _committed_catalog==-2: meshes.append(key)
		else:
			var old: Dictionary=_catalogs[_committed_catalog].rows[key]
			meshes.append(old.native_geometry.path);images.append(old.native_texture.path)
	if not _stream.is_empty():
		meshes.append_array(_stream.residency_meshes);images.append_array(_stream.residency_images)
	var ledger := {"bytes":0,"meshes":{},"images":{}}
	if not Handoff.append_streaming_bundle(ledger,_geometry,_textures,meshes,images,display_budget+Stream.BUDGET): return {}
	var costs := {}
	for key: String in _catalogs[index].rows:
		var row: Dictionary=_catalogs[index].rows[key]
		var path: String=row.native_geometry.path
		var parts: Dictionary=_geometry[path].get("components",{path:_geometry[path]})
		var amount := 288
		for physical: String in parts:
			if not ledger.meshes.has(physical): amount+=int(parts[physical].bytes)
		if not ledger.images.has(row.native_texture.path): amount+=int(row.native_texture.three_copy_charge)
		costs[key]=amount
	return costs


func _select_current_ground(center: Vector2, scale: float, angle: float, size: Vector2, budget: int) -> Dictionary:
	if _native==null: return {}
	var configuration: String=_native.ground_configuration(scale)
	if configuration.is_empty(): return {}
	# 默认档无解时先求当前清晰度合格的完整地面；不以提前换档偏好否决当前可玩切面。
	# 只求精确视野，避免在失败路径重复展开多个保护带；后续加载和交接预算仍照常核验。
	var cut: Dictionary=_native.select(center,scale,angle,size,configuration,budget)
	if cut.is_empty() or not cut.get("within_budget",false) or cut.get("ground_images",PackedStringArray()).is_empty() or not Handoff.native_qualified(cut,scale): return {}
	cut["spatial_guard_px"]=0
	return cut


func _select_native_fallback(center: Vector2, scale: float, angle: float, size: Vector2, check_screen: bool) -> Dictionary:
	if check_screen and _target_catalog!=-2:
		# 失败回退先验最小视野的全预算下界。连裸视野都无解，包含它的三个
		# 保护带更不可能有解；正常近景/原生细节偏好仍走原顺序，不增加成功路径查询。
		# 已有原生目标可能属于另一合法配置，必须先沿原路径保留，不能用默认档否决它。
		var screen: Dictionary=_native.select(center,scale,angle,size,"",display_budget)
		if screen.is_empty() or not screen.within_budget:
			native_screen_rejections+=1
			return screen
	var cut := _select_native(center,scale,angle,size,"",Stream.BUDGET/2)
	if cut.is_empty() or not cut.within_budget: cut=_select_native(center,scale,angle,size)
	return cut


func _select_native(center: Vector2, scale: float, angle: float, size: Vector2, configuration: String = "", budget: int = -1, retain_current: bool = true, include_zoom_footprint: bool = true) -> Dictionary:
	# 原生与HLOD共用已批准显示档；默认96MiB不变，不能把192MiB候选重试锁回旧档。
	if budget==-1: budget=display_budget
	# 96/48px保护带不能用固定192px复用门，否则缓慢巡检也每次重求树。
	# 高速移动仍按预测距离保留原192px门，零保护带不允许无余量复用。
	var margin := clampf(maxf(float(_target.get("spatial_guard_px",192))*0.5,_pan_velocity.length()*scale*0.25),24.0,192.0)
	# 完整在途切面尚能覆盖当前视野时先完成它，避免持续平移反复换树形切面。
	# 已提交切面用内圈触发下一次预取；清晰度与配置资格不放宽。
	if retain_current and _target_catalog==-2 and not _target.is_empty() and Handoff.native_qualified(_target,scale) \
		and int(_target.bytes)<=budget and (configuration.is_empty() or configuration==_target.configuration) \
		and _target_covers_current_view(margin if _target_committed() else 0.0):
		return _target
	var lead := Handoff.pan_lead(_pan_velocity,scale,0.35,size)
	var padding := (Transform2D(angle,Vector2.ZERO).basis_xform(lead)*scale).abs()+Vector2(384,384)
	var expanded: Dictionary = _native.select(center+lead*0.5,scale,angle,size+padding,configuration,budget)
	var expanded_retry := false
	if (expanded.is_empty() or not expanded.within_budget) and budget<display_budget:
		var full: Dictionary = _native.select(center+lead*0.5,scale,angle,size+padding,configuration,display_budget)
		if not full.is_empty() and full.within_budget:
			var combined := 0 if _committed.is_empty() else _handoff_bytes(full,-2)
			if combined>=0 and (_committed.is_empty() or combined<=_stream.residency_limit-_stream.residency_bytes):
				expanded=full;expanded_retry=true
	if not expanded.is_empty() and expanded.within_budget:
		expanded["spatial_guard_px"]=192
		expanded["selection_stage"]="native_guard_retry" if expanded_retry else "native_guard"
		return expanded
	for ratio: float in [0.5,0.25]:
		var reduced: Dictionary=_native.select(center+lead*0.5*ratio,scale,angle,size+padding*ratio,configuration,budget)
		var reduced_retry := false
		if (reduced.is_empty() or not reduced.within_budget) and budget<display_budget:
			var full: Dictionary=_native.select(center+lead*0.5*ratio,scale,angle,size+padding*ratio,configuration,display_budget)
			if not full.is_empty() and full.within_budget:
				var combined := 0 if _committed.is_empty() else _handoff_bytes(full,-2)
				if combined>=0 and (_committed.is_empty() or combined<=_stream.residency_limit-_stream.residency_bytes):
					reduced=full;reduced_retry=true
		if not reduced.is_empty() and reduced.within_budget:
			reduced["spatial_guard_px"]=192*ratio
			reduced["selection_stage"]="native_guard_retry" if reduced_retry else "native_guard"
			return reduced
	# 对称保护带可能只因侧后方可见面数超限；在退回裸视野前保留同档的方向性前探。
	# 逐级缩短现有预测距离，不改变清晰度、页数、面数或物理联合预算。
	for ratio: float in [1.0,0.5,0.25]:
		var motion_lead := lead*ratio
		if motion_lead.length()*scale<1.0: continue
		var motion_query := Handoff.native_motion_query(center,scale,angle,size,motion_lead,0.35*ratio,_zoom_rate if include_zoom_footprint else 0.0)
		if motion_query.is_empty(): continue
		var motion: Dictionary=_native.select(motion_query.center,scale,angle,motion_query.size,configuration,budget)
		if (motion.is_empty() or not motion.within_budget) and budget<display_budget:
			var full: Dictionary=_native.select(motion_query.center,scale,angle,motion_query.size,configuration,display_budget)
			if not full.is_empty() and full.within_budget:
				var combined := 0 if _committed.is_empty() else _handoff_bytes(full,-2)
				if combined>=0 and (_committed.is_empty() or combined<=_stream.residency_limit-_stream.residency_bytes): motion=full
		if not motion.is_empty() and motion.within_budget:
			motion["spatial_guard_px"]=0
			motion["selection_stage"]="native_motion_guard"
			motion["motion_lead_world"]=motion_lead
			motion["motion_horizon"]=0.35*ratio
			return motion
	# 所有保护候选都失败时，不主动裁掉仍完整合格的已提交保护层。
	# 只复用现有绑定；未来预取的retain_current=false仍必须求自己的视野。
	if retain_current and _target_catalog==-2 and _target_committed() \
		and (configuration.is_empty() or configuration==_target.get("configuration","")) \
		and Handoff.retain_display(_target,Handoff.native_qualified(_target,scale),_target_covers_current_view(),budget,Contract.native_page_limit(_selection_work)):
		var retained: Dictionary=_target.duplicate()
		retained["selection_stage"]="native_retained";retained["spatial_guard_px"]=0
		return retained
	var actual: Dictionary = _native.select(center,scale,angle,size,configuration,budget)
	if actual.is_empty(): return {}
	actual["spatial_guard_px"]=0
	actual["selection_stage"]="native_actual"
	actual["guard_prefetch_keys"]=expanded.get("keys",PackedStringArray())
	actual["guard_rejection"]={"faces":expanded.get("triangles",0),"bytes":expanded.get("bytes",0),"budget":budget,"kind":"native"}
	actual["prefetch_keys"]=expanded.get("keys",PackedStringArray())
	return actual


func _predict_prefetch(center: Vector2, scale_value: float, angle: float, size: Vector2) -> Dictionary:
	# 预取下一实际视野的切面，而不是大视野父页：父页与随后细分的子页是不同物理资源。
	if _pan_velocity.length()*scale_value<1.0 and absf(_zoom_rate)<0.02: return {}
	var horizon := 0.25
	if _zoom_rate < -0.02:
		var current_catalog := Handoff.catalog_index(_catalogs,scale_value,false)
		if current_catalog>=0:
			var boundary := float(_catalogs[current_catalog].range[0])
			var crossing := log(boundary/scale_value)/_zoom_rate
			# 快速缩远也必须先准备相邻档，不能预测到更远目录而跳过必经资源。
			if crossing>=0.0 and crossing<horizon: horizon=minf(horizon,crossing+0.04)
	var future_scale := clampf(scale_value*exp(clampf(_zoom_rate*horizon,-0.7,0.7)),0.0973,5.0)
	# 从原生缩向已常驻远档时，不能因终点资源齐备而漏掉必经的原生地表交接。
	var ready_destination := Handoff.catalog_index(_catalogs,future_scale,false)
	if _zoom_rate < -0.02 and Handoff.catalog_index(_catalogs,scale_value,false)<0 \
		and _foundation.get("layers",{}).has(ready_destination):
		var checkpoint := Handoff.native_exit_checkpoint(scale_value,future_scale,float(_catalogs[ready_destination].range[1]))
		if checkpoint>future_scale:
			future_scale=checkpoint
			horizon=clampf(log(future_scale/scale_value)/_zoom_rate,0.0,horizon)
	var future_center := center+Handoff.pan_lead(_pan_velocity,future_scale,horizon,size)
	var index := Handoff.catalog_index(_catalogs,future_scale,_zoom_rate>=0.0)
	if index<0 or (_zoom_rate>=0.0 and future_scale>float(_catalogs[index].get("prefer_native_above",INF))): index=-2
	if _foundation.get("layers",{}).has(index):
		var fixed := preload("res://scripts/rendering/tokyo_hlod_foundation.gd").select(_catalogs[index],_foundation.layers[index].entries,future_center,future_scale,angle,size,display_budget,_selection_work)
		# 全部固定资源本来就在请求/保护集；完整未来切面有解时无需再次求整树预取。
		if not fixed.is_empty():
			foundation_prefetch_skips+=1
			return {}
	var cut: Dictionary
	var fixed_now := preload("res://scripts/rendering/tokyo_hlod_foundation.gd").catalog_at(_foundation,scale_value)
	var cacheable: bool=fixed_now>=0 and _catalogs[fixed_now].has("middle_massing_recipe") and index>=0
	if cacheable and preload("res://scripts/rendering/tokyo_hlod_prefetch_cache.gd").reusable(_speculative_cache,_catalogs[index],index,future_center,future_scale,angle,size,_zoom_rate<0.0,Time.get_ticks_usec()):
		speculative_plan_reuses+=1
		return _speculative_cache.result
	if index==-2:
		if _native==null: return {}
		var archive := preload("res://scripts/rendering/tokyo_volume_archive.gd")
		var configuration := "lod%d_full"%archive.choose_level(-1,future_scale*0.90/Contract.PREFETCH_RATIO)
		# 缩远的实际地表会换到较低档；提前细档的物理网格不能替代该档资源。
		var ground_configuration: String=_native.ground_configuration(future_scale) if _zoom_rate < -0.02 else ""
		if not ground_configuration.is_empty(): configuration=ground_configuration
		# 预测也用实际保护带，但不能把此刻视野的在途复用结果冒充未来视野。
		cut={}
		# future_scale已计入缩放，保护带只保留原纯平移包络，不再外推一次倍率。
		cut=_select_native(future_center,future_scale,angle,size,configuration,Stream.BUDGET/2,false,false)
		if cut.is_empty() or not cut.within_budget: cut=_select_native(future_center,future_scale,angle,size,configuration,display_budget,false,false)
	else:
		# 必须与实际选页使用同样的保护带；仅预测裸视野会选出另一套父子页。
		# future_scale已包含缩远，不得再外推一次视口增长。
		cut=_select_hlod(_catalogs[index],future_center,future_scale,angle,size,true,Stream.BUDGET/2,false)
		if not cut.is_empty() and not cut.within_budget:
			cut=_select_hlod(_catalogs[index],future_center,future_scale,angle,size,true,-1,false)
	if cut.is_empty(): return {}
	var extra: Array[Dictionary]=[]
	if index==-2:
		for entry: Dictionary in cut.get("entries",[]):
			if entry.mask[2]:
				for surface: Dictionary in preload("res://scripts/rendering/tokyo_native_ground.gd").surfaces(entry):
					extra.append({"mesh":entry.path,"image":surface.texture})
					if surface.has("height_texture"): extra.append({"mesh":entry.path,"image":surface.height_texture})
	# 相邻档优先，连续缩远时另备后续档；只占缓存，不增加显示切面。
	var far_scale := clampf(scale_value*exp(clampf(_zoom_rate*0.25,-0.7,0.7)),0.0973,5.0)
	var far_index := Handoff.catalog_index(_catalogs,far_scale,false)
	if _zoom_rate < -0.02 and far_index>=0 and far_index!=index:
		var far_center := center+Handoff.pan_lead(_pan_velocity,far_scale,0.25,size)
		var far_cut := _select_hlod(_catalogs[far_index],far_center,far_scale,angle,size,true,Stream.BUDGET/2,false)
		if not far_cut.is_empty() and not far_cut.within_budget:
			far_cut=_select_hlod(_catalogs[far_index],far_center,far_scale,angle,size,true,-1,false)
		if not far_cut.is_empty() and far_cut.within_budget:
			for key: String in far_cut.keys:
				var row: Dictionary=_catalogs[far_index].rows[key]
				extra.append({"mesh":row.native_geometry.path,"image":row.native_texture.path})
	var result := {"catalog":index,"keys":cut.keys,"extra":extra}
	if cacheable and cut.get("within_budget",false):
		_speculative_cache={"index":index,"identity":_catalogs[index].get("identity",{}).duplicate(true),
			"zooming_out":_zoom_rate<0.0,"created":Time.get_ticks_usec(),"cut":{"keys":cut.keys.duplicate()},"result":result.duplicate(true)}
	return result


func _async_full_prefetch_allowed(cut: Dictionary) -> bool:
	if _committed.is_empty(): return true
	var bytes := _handoff_bytes(cut,-2)
	return bytes>=0 and bytes<=_stream.residency_limit-_stream.residency_bytes


func _native_screen_bridge(pending: Dictionary, center: Vector2, scale_value: float, angle: float, size: Vector2, handoff_budget: int) -> Dictionary:
	if _native==null or _stream.is_empty() or pending.get("configuration","").is_empty(): return {}
	_native_screen_bridge_state={"reason":"selection","attempts":int(_native_screen_bridge_state.get("attempts",0))+1}
	# 完整三层选择器重新求屏内切面，不从旧目标删除未就绪页；同档清晰度与原预算不变。
	var cut: Dictionary=_native.select(center,scale_value,angle,size,pending.configuration,display_budget,{"meshes":_stream._cache,"textures":_stream._textures})
	_native_screen_bridge_state["faces"]=cut.get("triangles",0)
	_native_screen_bridge_state["bytes"]=cut.get("bytes",0)
	_native_screen_bridge_state["pages"]=cut.get("active",0)
	if not Handoff.retain_display(cut,Handoff.native_qualified(cut,scale_value),true,display_budget,Contract.native_page_limit(_selection_work)): return {}
	_native_screen_bridge_state["reason"]="coverage"
	if not _cut_covers_current_view(cut,-2): return {}
	_native_screen_bridge_state["reason"]="resources"
	if not _resources_ready(cut,-2): return {}
	_native_screen_bridge_state["reason"]="union_budget"
	var combined := _handoff_bytes(cut,-2)
	if combined<0 or combined>handoff_budget: return {}
	# 屏内先完整提交；原目标及预测仍走同池预算预取，不能丢失原生地表/高度图片。
	var extras := Handoff.prefetch_requests(_catalogs,pending,-2)
	for key: String in pending.keys: extras.append({"mesh":key,"image":""})
	for path: String in pending.get("ground_images",[]): extras.append({"mesh":pending.keys[0],"image":path})
	cut["prefetch_extra"]=extras
	cut["cache_bridge"]=true
	cut["native_screen_bridge"]=true
	_native_screen_bridge_state["reason"]="ready"
	return cut


func _target_covers_current_view(margin_px: float = 0.0) -> bool:
	return _cut_covers_current_view(_target,_target_catalog,margin_px)


func _target_committed() -> bool:
	return not _committed.is_empty() and _committed_catalog==_target_catalog and _committed==_target.get("keys") \
		and (_target_catalog!=-2 or _committed_cut.get("masks")==_target.get("masks")) \
		and PackedStringArray(_committed_cut.get("ground_images",[]))==PackedStringArray(_target.get("ground_images",[]))


func _committed_qualified(scale_value: float) -> bool:
	return Handoff.native_qualified(_committed_cut,scale_value) if _committed_catalog==-2 \
		else _committed_catalog>=0 and Handoff.qualified(_catalogs[_committed_catalog],_committed_cut,scale_value)


