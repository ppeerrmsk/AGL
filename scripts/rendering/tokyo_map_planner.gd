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
var _lod_pair_work: Dictionary={}
var _flags: Dictionary={}
var _small_uploads := false
var display_budget := Stream.BUDGET
var _bounds := Rect2()
var _logical := Vector2.ZERO
var _last_size := Vector2.ZERO
var _last_canvas := Transform2D()
var _pan_velocity := Vector2.ZERO
var _zoom_rate := 0.0
var _prediction_floor := 0.0
var _committed := PackedStringArray()
var _committed_catalog := -1
var _committed_cut: Dictionary={}
var _target_catalog := -1
var _target: Dictionary={}
var _stream: Dictionary={}
var _force_replan := false
var _camera_demand_pending := false
var _ground_candidate_state: Dictionary={}
var _native_screen_bridge_state: Dictionary={}
var _speculative_cache: Dictionary={}
var _prediction_planner: RefCounted
var _prediction_request: Dictionary={}
var pending_selection_reuses := 0
var native_screen_rejections := 0
var retained_cuts := 0
var _cached_cut_attempts := 0
var foundation_prefetch_skips := 0
var speculative_plan_reuses := 0
var motion_actual_cuts := 0
var selection_usec := 0


func retirement_data() -> Array:
	var values: Array=[_catalogs,_geometry,_textures,_foundation,_selection_work,_lod_pair_work,
		_speculative_cache,_ground_candidate_state,_native_screen_bridge_state]
	if _native!=null: values.append_array(_native.retirement_data())
	if _prediction_planner!=null: values.append_array(_prediction_planner.retirement_data())
	return values


func configure(source: Dictionary, native_source: RefCounted = null) -> bool:
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
	_prediction_planner=null;_prediction_request={}
	_selection_work=source.context.duplicate(true)
	_lod_pair_work=source.context.duplicate(true)
	_selection_work["persistent_summary"]=_flags.get("guard_prefetch",false)
	_selection_work["stable_hlod_leaves"]=_flags.get("guard_prefetch",false)
	_selection_work["stable_hlod_tiles"]=_flags.get("return_cache",false)
	_selection_work["prepared_catalogs"]=source.get("prepared_catalogs",{})
	display_budget=int(_selection_work.display_limit)
	if not source.get("native",{}).is_empty():
		if native_source!=null:
			_native=native_source.fork_selection(source.context)
			if _native==null: return false
		else:
			_native=Native.new()
			if not _native.configure_selection_snapshot(source.native,source.context): return false
			if _flags.get("return_cache",false): _native.prepare_resident_index()
	if _flags.get("guard_prefetch",false) and not _flags.get("prediction_only",false):
		var prediction_source := source.duplicate()
		prediction_source.flags=_flags.duplicate()
		prediction_source.flags["prediction_only"]=true
		_prediction_planner=get_script().new()
		if not _prediction_planner.configure(prediction_source,_native if _flags.get("share_selection_source",false) else null): return false
	return true


func _trim_waiting_display(request: Dictionary) -> Dictionary:
	if not request.get("camera_demand",false) or _committed_catalog<0 \
		or not request.has("display_canvas") or not request.has("display_size") or not request.has("display_scale"): return {}
	var canvas: Transform2D=request.display_canvas
	var size: Vector2=request.display_size
	var scale_value: float=request.display_scale
	if not canvas.is_finite() or not size.is_finite() or minf(size.x,size.y)<=0.0 \
		or not is_finite(scale_value) or scale_value<=0.0: return {}
	var center := canvas.affine_inverse()*(_logical*0.5)
	var catalog: Dictionary=_catalogs[_committed_catalog]
	if not Handoff.qualified(catalog,_committed_cut,scale_value) \
		or not Handoff.covers_motion_view(catalog,_committed_cut,center,scale_value,canvas.get_rotation(),size): return {}
	var trimmed := Contract.visible_subset(catalog,_committed_cut,center,scale_value,canvas.get_rotation(),size,_selection_work)
	if not trimmed.is_empty() and trimmed.within_budget and trimmed.keys.size()<_committed.size() \
		and Handoff.covers_motion_view(catalog,trimmed,center,scale_value,canvas.get_rotation(),size):
		trimmed["selection_stage"]="trim_displayed"
		return trimmed
	if not _flags.get("display_compaction",false): return {}
	var compact_catalog := catalog
	if catalog.get("transition_only",false):
		compact_catalog=catalog.duplicate()
		var roots: Array[Dictionary]=[]
		for key: String in _committed: roots.append(catalog.transition_spatial_trees[key])
		compact_catalog["roots"]=roots
		compact_catalog.erase("identity");compact_catalog.erase("transition_intervals")
	# 已经显示的父页仍与屏幕相交，不等于整张父页都必须常驻。只在原实际姿态
	# 完整替换为同档子页；待显示的新尺度不能否决这次释放交接空间的事务。
	var compact := Contract.select(compact_catalog,center,scale_value,canvas.get_rotation(),size,
		not catalog.get("transition_only",false),Stream.BUDGET/2,_selection_work)
	if compact.is_empty() or not compact.within_budget or int(compact.bytes)>=int(_committed_cut.get("bytes",0)) \
		or not Handoff.qualified(catalog,compact,scale_value) \
		or not Handoff.covers_motion_view(catalog,compact,center,scale_value,canvas.get_rotation(),size): return {}
	var combined := _handoff_bytes(compact,_committed_catalog)
	if combined<0 or combined>int(_stream.residency_limit)-int(_stream.residency_bytes): return {}
	compact["selection_stage"]="compact_displayed"
	return compact


func plan(request: Dictionary) -> Dictionary:
	var prepared_cuts: Array=[]
	_prediction_request=request
	_last_canvas=request.canvas;_last_size=request.size;_logical=request.logical
	_pan_velocity=request.pan_velocity;_zoom_rate=request.zoom_rate
	_committed_catalog=request.committed_catalog;_committed_cut=request.committed
	_committed=PackedStringArray(_committed_cut.get("keys",[]))
	_target_catalog=request.target_catalog;_target=request.target
	_stream=request.stream.duplicate()
	# 紧凑输入只传身份；就绪与请求中集合仍分开，不能把在途资源判为可显示。
	for field: String in ["_cache","_textures","planned_meshes","planned_images"]:
		if _stream.get(field) is PackedStringArray:
			var keys := {}
			for path: String in _stream[field]: keys[path]=true
			_stream[field]=keys
	_selection_work["epoch"]=int(request.sequence)
	_lod_pair_work["epoch"]=int(request.sequence)
	if _native!=null: _native.selection_context["epoch"]=int(request.sequence)
	_force_replan=false
	_camera_demand_pending=bool(request.get("camera_demand",false))
	var scale_value: float=request.scale
	if _flags.get("lod_transition",false) and (not _flags.get("prediction_only",false) or request.get("actual_display_prediction",false)) \
		and not Handoff.display_target_allowed(_catalogs,scale_value,_committed_catalog,_target_catalog):
		# 过期的预取目标不能占住显示规划；只重置本次工作副本，不撤掉已提交画面。
		_target={};_target_catalog=-1
	# 高速输入主动使用完整常驻概括，不等细资源缺失才接管。
	# 后台也暂停细树换档；慢下来仍由原选择器恢复，不改变相机轨迹。
	var moving_summary := _motion_summary_plan(request)
	if not moving_summary.is_empty(): return moving_summary
	# 普通滚轮的可达下限来自实际 Camera2D；演出/诊断未声明时保持原预测。
	var requested_floor := float(request.get("prediction_floor",0.0))
	_prediction_floor=minf(requested_floor,scale_value) if _flags.get("display_compaction",false) \
		and is_finite(requested_floor) and requested_floor>0.0 and requested_floor<=scale_value+0.000001 else 0.0
	var zooming_out: bool=request.zooming_out
	var current_covered := _committed_catalog!=-1 and _cut_covers_current_view(_committed_cut,_committed_catalog)
	var lod_pair := _lod_pair_plan(request)
	if not lod_pair.is_empty(): return lod_pair
	var handoff_budget: int=_stream.residency_limit-_stream.residency_bytes
	var advancing_actual: bool=_flags.get("display_compaction",false) and _zoom_rate<=0.02 \
		and (request.get("camera_demand",false) or not _pan_velocity.is_zero_approx())
	var selected := Handoff.catalog_index(_catalogs,scale_value,not zooming_out and not advancing_actual)
	if _flags.get("lod_transition",false) and (not _flags.get("prediction_only",false) or request.get("actual_display_prediction",false)):
		selected=Handoff.display_catalog_index(_catalogs,scale_value,_committed_catalog)
	var foundation_catalog := preload("res://scripts/rendering/tokyo_hlod_foundation.gd").catalog_at(_foundation,scale_value,selected)
	# 新中景本身是完整合格显示表示；相邻细档另由预测I/O准备，不提前替换画面。
	if foundation_catalog<0:
		var actual_foundation := preload("res://scripts/rendering/tokyo_hlod_foundation.gd").catalog_at(_foundation,scale_value)
		if actual_foundation>=0 and (_catalogs[actual_foundation].has("middle_massing_recipe") or _catalogs[actual_foundation].has("far_summary_recipe")): foundation_catalog=actual_foundation
	if foundation_catalog>=0: selected=foundation_catalog
	var next: Dictionary = {}
	if selected<0 and _native!=null and scale_value>0.1944: selected=-2
	if _pending_display_compaction(request) or _pending_motion_path(request):
		# 腾池事务服务于实际显示姿态；输入终点继续变化不能让它反复取消。
		next=_target;selected=_target_catalog
		pending_selection_reuses+=1;_force_replan=true
	elif selected>=0 or selected==-2:
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
		var native_preferred := true
		if _flags.get("lod_transition",false) and selected>=0 and _committed_catalog>=0 \
			and is_equal_approx(float(_catalogs[selected].max_scale),1.25):
			# 中景交接完成后，在相同倍率平移不能被旧的原生偏好反复抢回。
			# 真正放大到共同过渡区才恢复偏好；中景无解时的完整原生回退仍保留。
			native_preferred=_zoom_rate>0.02 and scale_value>=1.18
		if not finishing_hlod and native_preferred and selected>=0 and _native!=null and not _native.ground.is_empty():
			var ground_configuration: String=_native.ground_configuration(scale_value)
			if not ground_configuration.is_empty():
				var hybrid: Dictionary=_select_native(center,scale_value,_last_canvas.get_rotation(),_last_size,ground_configuration,display_budget)
				var hybrid_union := 0 if _committed.is_empty() else _handoff_bytes(hybrid,-2)
				_ground_candidate_state={"deferred":false,"configuration":ground_configuration,"faces":hybrid.get("triangles",0),"bytes":hybrid.get("bytes",0),"images":hybrid.get("ground_images",[]).size(),"guard":hybrid.get("spatial_guard_px",0),"within_budget":hybrid.get("within_budget",false),"handoff_bytes":hybrid_union,"handoff_budget":handoff_budget}
				if not hybrid.get("ground_images",PackedStringArray()).is_empty() and Handoff.native_preference_qualified(hybrid,scale_value,_zoom_rate) and Handoff.native_preference(hybrid,hybrid_union,handoff_budget) and float(hybrid.get("spatial_guard_px",0))>0:
					next=hybrid;selected=-2
		if not finishing_hlod and selected>=0 and _native!=null and scale_value>0.1944 and (next.is_empty() or not next.within_budget or (native_preferred and not zooming_out and scale_value>float(_catalogs[selected].get("prefer_native_above",INF)))):
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
			# 缩远已进入较粗档时，先准备该档；旧细档的零增量候选会一直胜出并吃满扩区预算。
			if zooming_out and actual_catalog>=0 and actual_catalog!=_committed_catalog: bridge_catalogs.append(actual_catalog)
			if _committed_catalog>=0 and not _catalogs[_committed_catalog].get("transition_only",false): bridge_catalogs.append(_committed_catalog)
			if actual_catalog>=0 and actual_catalog not in bridge_catalogs: bridge_catalogs.append(actual_catalog)
			for bridge_catalog: int in bridge_catalogs:
				var handoff_cut := _select_handoff_hlod(bridge_catalog,center,scale_value,_last_canvas.get_rotation(),_last_size,handoff_budget,display_budget)
				if not handoff_cut.is_empty():
					next=handoff_cut;selected=bridge_catalog
					break
		# 镜头守卫尚未放行时，请求姿态可能在旧覆盖之外；裁旧页必须按仍在显示的姿态。
		# 先释放屏外旧页，再继续原需求。不能用尚未显示的视野阻止这一步，造成预算互等。
		if not next.is_empty() and not _committed.is_empty() and _handoff_bytes(next,selected)>handoff_budget:
			var displayed_trim := _trim_waiting_display(request)
			if not displayed_trim.is_empty():
				next=displayed_trim;selected=_committed_catalog
				_force_replan=true
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
			if _handoff_bytes(next,selected)>handoff_budget and _committed_catalog>=0 and _committed_qualified(scale_value) \
				and not _catalogs[_committed_catalog].get("transition_only",false):
				var bridge := _select_hlod(_catalogs[_committed_catalog],center,scale_value,_last_canvas.get_rotation(),_last_size,true,Stream.BUDGET/2)
				if not bridge.is_empty() and bridge.within_budget and int(bridge.charges.total_bytes)<current_bytes:
					var bridge_bytes := _handoff_bytes(bridge,_committed_catalog)
					if bridge_bytes>=0 and bridge_bytes<=handoff_budget:
							bridge["selection_stage"]="compact_bridge"
							next=bridge;selected=_committed_catalog
		# 已显示细档占满池时逐块交给当前实际档；只改变表示，镜头仍按原输入推进。
		# 刚够放下的粗档裸视野也需要腾池；不能把“联合费用已满足”误当成
		# “能撑过下一次装载窗口”，直接换掉仍带保护的旧画面。
		var short_coarse_handoff: bool=_flags.get("display_compaction",false) and not request.get("camera_demand",false) \
			and zooming_out and selected>=0 and selected!=_committed_catalog \
			and float(next.get("spatial_guard_px",0.0))<96.0
		var needs_room: bool=next.is_empty() or _handoff_bytes(next,selected)>handoff_budget \
			or (selected==_committed_catalog and next.get("keys")==_committed) or short_coarse_handoff
		var display_transition := _compact_displayed_scale(request) if needs_room else {}
		if not display_transition.is_empty():
			next=display_transition.cut;selected=int(display_transition.catalog);_force_replan=true
		# 提前档超预算不等于当前尺度无解；先退回实际尺度合格的完整切面，不能直接清屏。
		if next.is_empty() or not next.within_budget:
			for n in _catalogs.size():
				var catalog: Dictionary=_catalogs[n]
				if catalog.get("transition_only",false): continue
				if scale_value<float(catalog.min_scale) or scale_value>float(catalog.max_scale): continue
				var current_cut := _select_hlod(catalog,center,scale_value,_last_canvas.get_rotation(),_last_size,false,Stream.BUDGET/2)
				if not current_cut.is_empty() and not current_cut.within_budget:
					current_cut=_select_hlod(catalog,center,scale_value,_last_canvas.get_rotation(),_last_size)
				if not current_cut.is_empty() and current_cut.within_budget:
					next=current_cut;selected=n
					break
		if not next.is_empty() and next.within_budget:
			var predicted := {} if _flags.get("prediction_only",false) else _predict_path_prefetch(center,scale_value,_last_canvas.get_rotation(),_last_size)
			if not predicted.is_empty():
				prepared_cuts=predicted.get("prepared_cuts",[])
				# next可能与在途目标共享Dictionary；先复制，才能正确检测预取身份变化。
				next=next.duplicate()
				next["prefetch_catalog"]=predicted.catalog
				next["prefetch_keys"]=predicted.keys
				next["prefetch_extra"]=predicted.extra
				next["path_prefetch_first"]=_flags.get("return_cache",false)
			# 显式对照：旧页已缺边时，优先用缓存内完整合格切面接住；原目标继续预取。
			if _flags.get("cached_cut",false) and (not current_covered or not _committed_qualified(scale_value)) and not _committed.is_empty() and not _resources_ready(next,selected):
				_cached_cut_attempts+=1
				var cached := preload("res://scripts/rendering/tokyo_hlod_cached_cut.gd")
				var native_bridge: Dictionary={}
				if selected==-2 and _flags.get("native_screen_bridge",false):
					native_bridge=_native_screen_bridge(next,center,scale_value,_last_canvas.get_rotation(),_last_size,handoff_budget)
				if not native_bridge.is_empty(): next=native_bridge
				for cached_index: int in cached.candidate_catalogs(_catalogs,selected,_committed_catalog,scale_value) if native_bridge.is_empty() else PackedInt32Array():
					if _flags.get("lod_transition",false) and not Handoff.display_target_allowed(_catalogs,scale_value,_committed_catalog,cached_index): continue
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
	var result := {"status":"candidate" if next.get("within_budget",false) else "no_solution",
		"prepared_cuts":prepared_cuts,
		"catalog":selected,"cut":compact_cut(next),"force_replan":_force_replan,
		"ground_candidate":_ground_candidate_state.duplicate(true),"native_screen_bridge":_native_screen_bridge_state.duplicate(true),
		"stats":{"selection_usec":selection_usec,"retained_cuts":retained_cuts,"pending_reuses":pending_selection_reuses,
			"native_screen_rejections":native_screen_rejections,"cached_cut_attempts":_cached_cut_attempts,
			"foundation_prefetch_skips":foundation_prefetch_skips,"speculative_plan_reuses":speculative_plan_reuses,"motion_actual_cuts":motion_actual_cuts,
			"hlod_builds":_selection_work.get("builds",0),"hlod_reuses":_selection_work.get("reuses",0),
			"qualification_builds":_selection_work.get("qualification_builds",0),"prepared_reuses":_selection_work.get("prepared_reuses",0),
			"native_builds":_native.solver_builds if _native!=null else 0,"native_reuses":_native.solver_reuses if _native!=null else 0}}
	# 远距返回可能无法让完整新旧视野同时常驻。沿原输入路径找可交接的最大中间步，
	# 而不是反复求同一个超池终点；镜头仍由原控制器按正常速度及完整覆盖独立提交。
	if _flags.get("display_compaction",false) and request.get("camera_demand",false) \
		and request.has("display_canvas") and not request.get("motion_substep",false) \
		and (result.status!="candidate" or _handoff_bytes(next,selected)>handoff_budget):
		var from_canvas: Transform2D=request.display_canvas
		var from_center := from_canvas.affine_inverse()*(_logical*0.5)
		var to_center: Vector2=request.canvas.affine_inverse()*(_logical*0.5)
		for fraction: float in CameraController.MAP_MOTION_FRACTIONS:
			var subrequest := request.duplicate()
			var subscale := lerpf(float(request.display_scale),float(request.scale),fraction)
			var subcanvas := Transform2D(lerp_angle(from_canvas.get_rotation(),request.canvas.get_rotation(),fraction),Vector2.ZERO)
			subcanvas=subcanvas.scaled(Vector2.ONE*subscale*float(_logical.x)/float(request.size.x))
			subcanvas.origin=_logical*0.5-subcanvas*from_center.lerp(to_center,fraction)
			subrequest.canvas=subcanvas;subrequest.scale=subscale;subrequest["motion_substep"]=true
			var subcatalog := Handoff.catalog_index(_catalogs,subscale,false)
			var progress: Dictionary
			if subcatalog>=0:
				# 完整终点已尝试裁页和逐页压缩；中间步只求新增资源费用，不再为四个
				# 小步各跑一遍全预算、原生回退、预测与压缩链，避免失败查询占住后台槽。
				_last_canvas=subcanvas
				var checkpoint := _select_handoff_hlod(subcatalog,from_center.lerp(to_center,fraction),
					subscale,subcanvas.get_rotation(),request.size,handoff_budget,display_budget)
				progress=result.duplicate()
				progress.catalog=subcatalog;progress.cut=compact_cut(checkpoint)
				progress.status="candidate" if checkpoint.get("within_budget",false) else "no_solution"
			else:
				progress=plan(subrequest)
			var combined := _handoff_bytes(progress.cut,int(progress.catalog))
			if progress.status=="candidate" and combined>=0 and combined<=handoff_budget:
				progress.cut["motion_checkpoint"]=true
				progress.force_replan=true
				result=progress
				break
		_last_canvas=request.canvas;_last_size=request.size;_zoom_rate=request.zoom_rate;_pan_velocity=request.pan_velocity
	# 完整输入切面也可能在 I/O 期间变成路径上的中间步；保留该资格标记，
	# 由最新路径再次核验，不能仅因最新终点稍远就取消已准备的有效资源。
	if _flags.get("display_compaction",false) and request.get("camera_demand",false) \
		and result.status=="candidate" and int(result.catalog)>=0 \
		and _cut_covers_current_view(result.cut,int(result.catalog)):
		result.cut["motion_checkpoint"]=true
		result.force_replan=true
	return result


func _lod_pair_plan(request: Dictionary) -> Dictionary:
	if not _flags.get("lod_transition",false) or _native==null: return {}
	var predicting: bool=_flags.get("prediction_only",false)
	var scale: float=request.scale
	# 高速平移沿用完整的方向保护与路径预取；过渡的小范围联合查询不能替代移动规划。
	if _pan_velocity.length()*scale>600.0: return {}
	if scale<0.8 or scale>2.0 or (not predicting and _committed_catalog==-2 and scale<1.15): return {}
	var index := Handoff.catalog_index(_catalogs,1.2,false)
	if index<0 or not is_equal_approx(float(_catalogs[index].max_scale),1.25) \
		or (not predicting and _committed_catalog not in [-2,index]): return {}
	# 已缩远的共同档保持到真实放大；旧prefer_native_above不能在交接后立刻抢回显示。
	if not predicting and _committed_catalog==index and _zoom_rate<=0.02 \
		and Handoff.qualified(_catalogs[index],_committed_cut,scale) and _cut_covers_current_view(_committed_cut,index):
		return {"status":"candidate","catalog":index,"cut":compact_cut(_committed_cut),"prepared_cuts":[],
			"force_replan":false,"ground_candidate":{},"native_screen_bridge":{},"stats":{}}
	var center := _last_canvas.affine_inverse()*(_logical*0.5)
	# 两档在同一扩大视野求解；远侧倍率为共同交接底端，平移只使用原预测方向。
	var lead := Handoff.pan_lead(_pan_velocity,1.15,0.09,_last_size)
	var size := _last_size+(Transform2D(_last_canvas.get_rotation(),Vector2.ZERO).basis_xform(lead)*1.15).abs()
	center+=lead*0.5
	# 过渡应联合选父/子页；普通移动的固定细叶策略会耗尽页余量，不能用于这里。
	var coarse := Contract.select(_catalogs[index],center,1.15,_last_canvas.get_rotation(),size,false,display_budget,_lod_pair_work)
	if coarse.is_empty() or not coarse.within_budget: return {}
	# 同时准备最高细档，避免1.6边界才再请求下一档；只选同预算前沿，不扩大显示面数。
	var configuration := "lod5_full"
	var fine: Dictionary=_native.select_limited(center,1.15,_last_canvas.get_rotation(),size,configuration,
		16-coarse.keys.size(),240000-int(coarse.triangles),display_budget-int(coarse.bytes))
	if fine.is_empty() or not fine.within_budget: return {}
	fine["lod_blend_floor"]=1.15
	var fine_next := compact_cut(fine)
	var coarse_next := compact_cut(coarse)
	coarse["lod_successor"]={"catalog":-2,"cut":fine_next,"direction":1,"scale":1.18,"reverse_scale":1.245}
	fine["lod_successor"]={"catalog":index,"cut":coarse_next,"direction":-1,"scale":1.245,"reverse_scale":1.18}
	var selected := -2 if predicting else _committed_catalog
	var next: Dictionary=fine if selected==-2 else coarse
	if not predicting and selected==index and scale<1.15:
		# 放大前先准备两档；较窄的交接切面尚未覆盖此刻视野，不能提前显示。
		next=_committed_cut.duplicate()
		next["lod_successor"]={"catalog":index,"cut":compact_cut(coarse),"direction":1,"scale":1.15}
	# 先收紧当前同档，待提交后再换档；缩放、覆盖与实际资源就绪仍由显示门独立检查。
	var prepared: bool=_committed==next.keys and _committed_cut.get("configuration","")==next.get("configuration","")
	if not predicting and scale>=1.15 and prepared and ((selected==-2 and _zoom_rate< -0.02 and scale<=1.245) or (selected==index and _zoom_rate>0.02 and scale>=1.18)):
		selected=index if selected==-2 else -2
		next=coarse if selected==index else fine
		next["lod_blend_target"]=true
	var extras: Array[Dictionary]=[]
	for key: String in coarse.keys:
		var row: Dictionary=_catalogs[index].rows[key]
		extras.append({"mesh":row.native_geometry.path,"image":row.native_texture.path})
	for key: String in fine.keys: extras.append({"mesh":key,"image":""})
	next["prefetch_extra"]=extras
	next["selection_stage"]="lod_pair_prepare"
	return {"status":"candidate","catalog":selected,"cut":compact_cut(next),"prepared_cuts":[],
		"force_replan":true,"ground_candidate":{},"native_screen_bridge":{},"stats":{}}


func _motion_summary_plan(request: Dictionary) -> Dictionary:
	var foundation := preload("res://scripts/rendering/tokyo_hlod_foundation.gd")
	if not _flags.get("guard_prefetch",false) or _flags.get("prediction_only",false) \
		or not foundation.motion_active(_pan_velocity,_zoom_rate,request.scale,_logical,_last_size,request.get("return_hint",{})): return {}
	var selected := foundation.catalog_at(_foundation,request.scale,-1,true)
	if selected<0 or not _catalogs[selected].has("resident_motion_summary"): return {}
	var center := _last_canvas.affine_inverse()*(_logical*0.5)
	var next := foundation.select(_catalogs[selected],_foundation.layers[selected].entries,center,request.scale,
		_last_canvas.get_rotation(),_last_size,display_budget,_selection_work)
	if next.is_empty() or not _resources_ready(next,selected) or not _cut_covers_current_view(next,selected): return {}
	var combined := _handoff_bytes(next,selected)
	if combined<0 or combined>_stream.residency_limit-_stream.residency_bytes: return {}
	next["motion_summary"]=true
	return {"status":"candidate","catalog":selected,"cut":compact_cut(next),"prepared_cuts":[],
		"force_replan":true,"ground_candidate":{},"native_screen_bridge":{},"stats":{}}


static func compact_cut(cut: Dictionary) -> Dictionary:
	var result := cut.duplicate()
	if cut.has("prefetch_extra"):
		# 多个预测姿态常引用同一物理资源；保留首次优先级，不复制后面的重复请求。
		var extras: Array[Dictionary]=[]
		var seen := {}
		for pair: Dictionary in cut.prefetch_extra:
			if seen.get(pair.mesh,{}).has(pair.image): continue
			if not seen.has(pair.mesh): seen[pair.mesh]={}
			seen[pair.mesh][pair.image]=true
			extras.append(pair)
		result["prefetch_extra"]=extras
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
	# 缩远跨出当前档后，不再扩装同一细档；它会耗尽本该交给粗档的空间。
	# 真正跨档的在途桥接仍可先完成，避免取消必经的中间档。
	if zooming_out and _target_catalog>=0 and (_target_catalog==_committed_catalog or _flags.get("display_compaction",false)) \
		and scale_value<float(_catalogs[_target_catalog].get("range",[0.0,INF])[0]): return false
	# 普通保护带事务也可能即将到期；沿用桥接的0.25秒资格，不能占住下一细档的加载窗口。
	# 候选在途页只要仍覆盖最新完整视野就先完成；96px 额外保护不足不等于已缺图。
	# 否则连续缩远会在资源完成前反复换目标。实际镜头提交仍逐帧验完整覆盖。
	var margin := 96.0 if zooming_out and not _flags.get("display_compaction",false) else 0.0
	var current_valid := _target_catalog>=0 and not _target_committed() and not _target.has("anticipated_scale") \
		and Handoff.qualified(_catalogs[_target_catalog],_target,scale_value) \
		and _handoff_bridge_qualified(_target_catalog,_target,scale_value) \
		and _target_covers_current_view(margin)
	if not current_valid: return false
	if not _flags.get("display_compaction",false) or _camera_demand_pending or _pan_velocity.is_zero_approx(): return true
	# 自由移动不会等待此事务；不能保留装好后即将缺边的旧目标，须提前继续规划前沿。
	# 守卫等待仍保留原中间步，不改相机速度，也不延长任何旧切面的显示资格。
	var center := _last_canvas.affine_inverse()*(_logical*0.5)
	var motion := Handoff.native_motion_query(center,scale_value,_last_canvas.get_rotation(),_last_size,
		Handoff.pan_lead(_pan_velocity,scale_value,0.25,_last_size),0.25,_zoom_rate)
	return not motion.is_empty() and Handoff.covers_motion_view(_catalogs[_target_catalog],_target,
		motion.center,scale_value,_last_canvas.get_rotation(),motion.size)


func _select_hlod(catalog: Dictionary, center: Vector2, scale: float, angle: float, size: Vector2, finer: bool = false, budget: int = -1, include_zoom_footprint: bool = true) -> Dictionary:
	if _flags.get("return_cache",false) and not _selection_work.get("stable_hlod_tiles_only",false) \
		and not catalog.get("mixed_scales",false) and float(catalog.min_scale)>=0.17 and float(catalog.max_scale)<=0.25:
		# 先沿同一固定网格尝试各档保护带，再回退自适应树；否则大保护带的混合解会反复打断固定身份。
		for refine: bool in [false,true]:
			_selection_work["stable_hlod_tiles_only"]=true
			_selection_work["stable_hlod_refine"]=refine
			var tiled := _select_hlod(catalog,center,scale,angle,size,finer,budget,include_zoom_footprint)
			_selection_work["stable_hlod_tiles_only"]=false
			_selection_work["stable_hlod_refine"]=false
			if not tiled.is_empty() and tiled.within_budget: return tiled
	if budget==-1:
		# 扩大硬上限不能把原48/96MiB首选一起抬高；原切面可用时保持原资源身份。
		if display_budget>Stream.BUDGET:
			var original := _select_hlod(catalog,center,scale,angle,size,finer,Stream.BUDGET,include_zoom_footprint)
			if not original.is_empty() and original.within_budget: return original
		budget=display_budget
	# 快速缩放和等待中的镜头先留半池；连续平移保留完整保护带，不能仅因
	# 速度超过前探阈值就删掉即将入屏的边缘页。实际守卫事务仍可按原半池交接。
	# 候选缓存能同时容纳两份完整显示切面时，允许原全预算重试保护带；
	# 后面的真实联合账本仍须通过，显示面数、页数和96MiB上限均不改变。
	var reserve_transition: bool=_flags.get("display_compaction",false) \
		and (_camera_demand_pending or absf(_zoom_rate)>1.0) \
		and not (_flags.get("wide_motion_guard",false) and _stream.residency_limit-_stream.residency_bytes>=2*display_budget)
	for index: int in _foundation.get("layers",{}):
		if _catalogs[index]!=catalog: continue
		var fixed := preload("res://scripts/rendering/tokyo_hlod_foundation.gd").select(catalog,_foundation.layers[index].entries,center,scale,angle,size,budget,_selection_work)
		if not fixed.is_empty():
			return fixed
	# 空间提前量与缩放提前量独立；保持真实像素尺度，不能用降低scale冒充扩区。
	var lead := Handoff.pan_lead(_pan_velocity,scale,0.35,size)
	var padding := (Transform2D(angle,Vector2.ZERO).basis_xform(lead)*scale).abs()+Vector2(384,384)
	if include_zoom_footprint: padding+=_hlod_zoom_padding(catalog,scale,size)
	var expanded := Contract.select(catalog,center+lead*0.5,scale,angle,size+padding,finer,budget,_selection_work,_small_uploads)
	var expanded_retry := false
	if (expanded.is_empty() or not expanded.within_budget) and budget<display_budget and not reserve_transition:
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
		expanded=_prefer_resident_hlod(catalog,expanded,center+lead*0.5,scale,angle,size+padding,finer,display_budget if expanded_retry else budget)
		expanded["spatial_guard_px"]=192
		expanded["selection_stage"]="hlod_guard_retry" if expanded_retry else "hlod_guard"
		return expanded
	# 每档保护带都先验首选预算，再验显示上限与同一真实联合预算，最后才收窄。
	for ratio: float in [0.5,0.25]:
		var reduced := Contract.select(catalog,center+lead*0.5*ratio,scale,angle,size+padding*ratio,finer,budget,_selection_work,_small_uploads)
		var reduced_retry := false
		if (reduced.is_empty() or not reduced.within_budget) and budget<display_budget and not reserve_transition:
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
			reduced=_prefer_resident_hlod(catalog,reduced,center+lead*0.5*ratio,scale,angle,size+padding*ratio,finer,display_budget if reduced_retry else budget)
			reduced["spatial_guard_px"]=192*ratio
			reduced["selection_stage"]="hlod_guard_retry" if reduced_retry else "hlod_guard"
			return reduced
	var actual := Contract.select(catalog,center,scale,angle,size,finer,budget,_selection_work,_small_uploads)
	if actual.is_empty(): return {}
	if actual.within_budget: actual=_prefer_resident_hlod(catalog,actual,center,scale,angle,size,finer,budget)
	actual["spatial_guard_px"]=0
	actual["selection_stage"]="hlod_actual"
	actual["guard_rejection"]={"faces":expanded.get("triangles",0),"bytes":expanded.get("bytes",0),"budget":budget,"kind":"hlod"}
	# 超显示面数/字节的扩区只能作为未绑定预取集，绝不作为合格显示切面提交。
	actual["guard_prefetch_keys"]=expanded.get("keys",PackedStringArray())
	return actual


func _prefer_resident_hlod(catalog: Dictionary, selected: Dictionary, center: Vector2, scale: float, angle: float, size: Vector2, finer: bool, budget: int) -> Dictionary:
	if not _flags.get("return_cache",false) or _selection_work.get("stable_hlod_tiles_only",false): return selected
	var index := _catalogs.find(catalog)
	if index<0 or _resources_ready(selected,index): return selected
	var meshes: Dictionary=_stream.get("_cache",{}).duplicate()
	var images: Dictionary=_stream.get("_textures",{}).duplicate()
	# 复用同一查询包络，绝不以较窄保护带换缓存命中；提前细化仍使用原资格尺度。
	var qualified_scale := minf(scale/Contract.PREFETCH_RATIO,float(catalog.max_scale)) if finer else scale
	for requested: bool in [false,true]:
		if requested:
			meshes.merge(_stream.get("planned_meshes",{}));images.merge(_stream.get("planned_images",{}))
		if meshes.is_empty(): continue
		var resident := preload("res://scripts/rendering/tokyo_hlod_cached_cut.gd").select(catalog,center,qualified_scale,angle,
			size*(qualified_scale/scale),_geometry,meshes,images,_selection_work)
		if resident.is_empty() or int(resident.bytes)>budget: continue
		# 完整就绪的切面优先于在途身份；后者只能延续请求，不能取得显示资格。
		resident["cache_reuse"]=_resources_ready(resident,index)
		resident["request_reuse"]=not resident.cache_reuse
		return resident
	return selected


func _handoff_bridge_qualified(index: int, cut: Dictionary, scale: float) -> bool:
	# 与既有预测I/O共用0.25秒视窗；快速放大时不能靠低档桥接拖延即将到期的换档。
	var future_scale := scale*exp(clampf(_zoom_rate*0.25,0.0,0.7))
	return Handoff.qualified(_catalogs[index],cut,future_scale)


func _motion_guarded_actual(selected: int, next: Dictionary, center: Vector2, scale: float, angle: float, size: Vector2, handoff_budget: int) -> Dictionary:
	# 提前细档受16页/面数/预算所限常只剩裸视野；运动中这类切面一两帧即失去覆盖。
	# 实际档须在换档前探窗内合格、保护带更宽且可同池交接；细档仍由预测预取准备。
	var guard := float(next.get("spatial_guard_px",0.0))
	var need := Handoff.motion_guard_need(_pan_velocity,scale,size)
	# 冷进入还没有速度历史；裸视野若先吃满显示池，第一次跟随就没有交接空间。
	# 仅复用既有实际档资格/保护带规则，细档继续预取，资产与清晰度阈值不变。
	var cold_full := _committed.is_empty() and int(next.get("bytes",0))>Stream.BUDGET/2 and guard<48.0
	if (guard>=need and not cold_full) or _foundation.get("layers",{}).has(selected): return {}
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
	if include_zoom_footprint: padding+=_hlod_zoom_padding(_catalogs[index],scale,size)
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


func _hlod_zoom_padding(catalog: Dictionary, scale: float, size: Vector2) -> Vector2:
	var rate := _zoom_rate
	if _flags.get("display_compaction",false) and rate<0.0 and scale>0.0:
		# 本档只前探到下一粗档边界；跨档区域由原预测预取准备，不能继续扩装旧细档。
		# 平移前探和固定保护带独立保留，显示资格、覆盖和联合预算仍由提交门核验。
		var lower := float(catalog.get("range",[0.0,INF])[0])
		if _flags.get("lod_transition",false): lower*=0.92
		var boundary := maxf(lower,_prediction_floor)
		if boundary>0.0: rate=maxf(rate,log(minf(1.0,boundary/scale))/0.25)
	return Handoff.zoom_out_padding(rate,size)


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


func _predict_path_prefetch(center: Vector2, scale_value: float, angle: float, size: Vector2) -> Dictionary:
	if not _flags.get("guard_prefetch",false): return _predict_prefetch(center,scale_value,angle,size)
	var stationary := _pan_velocity.length()*scale_value<1.0 and absf(_zoom_rate)<0.02
	# 树的父页与子页不共享物理身份。只缓存远端视野会漏掉途中需要的另一套切面。
	# 近期先排队；仍由主线程按同池账本逐资源接纳，不将预测当成显示证明。
	var result: Dictionary={}
	var prepared: Array=[]
	var preceding: Dictionary={}
	var hint: Dictionary=_prediction_request.get("return_hint",{})
	var horizons: Array=[0.25] if stationary else [0.02,0.06,0.12,0.25]
	# 连续WASD的20ms样本在后台规划/图片上传完成前已经过期。
	# 当前切面照常优先，预取提前到0.1–0.5秒；SPACE起步仍保留密集采样。
	if _flags.get("return_cache",false) and not stationary and hint.get("screen_pan",false) and not hint.get("following",true):
		# 缩远时后缘也会露出；只查较远前方会漏掉近时刻的扩张视野。
		horizons=[0.1,0.2,0.35,0.5] if absf(_zoom_rate)<0.02 else [0.02,0.06,0.12,0.25,0.5]
	if _flags.get("return_cache",false) and hint.get("following",false) \
		and center.distance_to(hint.position)*scale_value>80.0 and absf(_zoom_rate)<0.02:
		horizons=Handoff.return_horizons(center.distance_to(hint.position)*scale_value,size,float(hint.rate),float(hint.get("step_seconds",0.0)))
		horizons.sort()
	for horizon: float in horizons:
		var predicted := _predict_prefetch(center,scale_value,angle,size,horizon,preceding)
		if predicted.is_empty(): continue
		preceding=predicted
		if predicted.has("prepared_cut"):
			prepared.append({"catalog":predicted.catalog,"cut":predicted.prepared_cut})
		if result.is_empty():
			result=predicted.duplicate(true)
		else:
			var cut := {"prefetch_catalog":predicted.catalog,"prefetch_keys":predicted.keys,"prefetch_extra":predicted.extra}
			result.extra.append_array(Handoff.prefetch_requests(_catalogs,cut,int(predicted.catalog)))
	# 自由镜头随时可能按空格反向。提前准备返回路径起步，费用仍由同池账本逐项接纳。
	if not hint.is_empty() and not hint.get("following",true) and (absf(_zoom_rate)<0.02 or hint.get("direct_return",false)) \
		and center.distance_to(hint.position)*scale_value>80.0:
		var saved_request := _prediction_request
		var saved_velocity := _pan_velocity
		_prediction_request=_prediction_request.duplicate()
		_prediction_request.return_hint=hint.duplicate()
		_prediction_request.return_hint.following=true
		_prediction_request.return_hint["direct_destination"]=hint.get("direct_return",false)
		_pan_velocity=(Vector2(hint.position)-center)*float(hint.rate)
		_prediction_request.pan_velocity=_pan_velocity
		preceding={}
		# 返回目的地与沿途是不同资源；先保留目的地请求，再按近到远准备起步。
		# 仍走同一清晰度选择器与共享池；不将预测当成显示/驻留保证。
		# 高刷新率下首步早于20ms；远距回中20ms切面可能已越过首步视野的后缘。
		var return_steps: Array=Handoff.return_horizons(center.distance_to(hint.position)*scale_value,size,float(hint.rate),float(hint.get("step_seconds",0.0))) \
			if _flags.get("return_cache",false) else [0.02,0.06,0.12,0.25]
		# 立即回中只需现在的落点和短时移动/缩放后的落点，不再预取整条高速扫图路径。
		if hint.get("direct_return",false): return_steps=[0.0,0.25]
		for horizon: float in return_steps:
			var predicted := _predict_prefetch(center,scale_value,angle,size,horizon,preceding)
			if predicted.is_empty(): continue
			preceding=predicted
			if predicted.has("prepared_cut"): prepared.append({"catalog":predicted.catalog,"cut":predicted.prepared_cut})
			if result.is_empty(): result=predicted.duplicate(true)
			else:
				var cut := {"prefetch_catalog":predicted.catalog,"prefetch_keys":predicted.keys,"prefetch_extra":predicted.extra}
				var requests := Handoff.prefetch_requests(_catalogs,cut,int(predicted.catalog))
				if (horizon==1.0 or hint.get("direct_return",false)) \
					and (not _flags.get("lod_transition",false) or saved_velocity.length()*scale_value<600.0):
					requests.append_array(result.extra);result.extra=requests
				else: result.extra.append_array(requests)
		_prediction_request=saved_request;_pan_velocity=saved_velocity
	# 前方当前档与相邻精度是两份任务；预热细档不能取代WASD真正会露出的当前档。
	if _flags.get("lod_transition",false) \
		and Handoff.preload_entry_scale(_catalogs,scale_value,_zoom_rate)>0.0:
		var adjacent := _predict_prefetch(center,scale_value,angle,size,0.25,{},true)
		if not adjacent.is_empty():
			if adjacent.has("prepared_cut"): prepared.append({"catalog":adjacent.catalog,"cut":adjacent.prepared_cut})
			if result.is_empty(): result=adjacent.duplicate(true)
			else:
				var adjacent_requests := Handoff.prefetch_requests(_catalogs,{"prefetch_catalog":adjacent.catalog,"prefetch_keys":adjacent.keys,"prefetch_extra":adjacent.extra},int(adjacent.catalog))
				if _zoom_rate>0.02:
					adjacent_requests.append_array(result.extra);result.extra=adjacent_requests
				else: result.extra.append_array(adjacent_requests)
	if not result.is_empty(): result["prepared_cuts"]=prepared
	return result


func _forecast_zoom(scale_value: float, horizon: float, output_ratio: float, hint: Dictionary, stop_scale: float = 0.0) -> Dictionary:
	var value := scale_value/output_ratio
	var target := float(hint.zoom_target)
	var step := maxf(clampf(float(hint.get("step_seconds",1.0/120.0)),1.0/240.0,0.1),horizon/64.0)
	var elapsed := 0.0
	for index in 64:
		var delta := minf(step,horizon-elapsed)
		if delta<=0.000001: break
		var next := CameraController.next_zoom(value,target,delta)
		if stop_scale>0.0 and not is_equal_approx(value,next) and (stop_scale/output_ratio-value)*(stop_scale/output_ratio-next)<=0.0:
			return {"scale":stop_scale,"seconds":elapsed+delta*(stop_scale/output_ratio-value)/(next-value)}
		value=next;elapsed+=delta
	return {"scale":value*output_ratio,"seconds":elapsed}


func _predict_screen_pan(center: Vector2, scale_value: float, future_scale: float, horizon: float, hint: Dictionary) -> Dictionary:
	# 有界纯值预测，复用正式 WASD 参数；覆盖起步、松键和变向时的速度曲线。
	# 只准备未来资源，不回写相机或 Input。
	var velocity: Vector2=hint.pan_velocity
	var direction: Vector2=hint.pan_direction
	var held := float(hint.pan_hold)
	var zoom := maxf(float(hint.pan_zoom),0.001)
	var start_zoom := zoom
	var rate := log(future_scale/scale_value)/maxf(horizon,0.001)
	var step := maxf(clampf(float(hint.get("step_seconds",1.0/120.0)),1.0/240.0,0.1),horizon/64.0)
	var elapsed := 0.0
	for index in 64:
		var delta := minf(step,horizon-elapsed)
		if delta<=0.000001: break
		elapsed+=delta
		var desired := Vector2.ZERO
		if direction!=Vector2.ZERO:
			held=minf(held+delta,CameraController.WASD_RAMP_TIME)
			var curve := 1.0-pow(1.0-held/CameraController.WASD_RAMP_TIME,3)
			desired=direction*lerpf(CameraController.WASD_SPEED_MIN,CameraController.WASD_SPEED_MAX,curve)
		else: held=0.0
		velocity=velocity.lerp(desired,clampf(delta*CameraController.WASD_ACCEL,0.0,1.0))
		zoom=CameraController.next_zoom(zoom,float(hint.zoom_target),delta) if hint.has("zoom_target") else start_zoom*exp(rate*elapsed)
		center+=velocity*delta/zoom
	return {"center":center,"velocity":velocity/zoom}


func _predict_prefetch(center: Vector2, scale_value: float, angle: float, size: Vector2, prediction_horizon: float = 0.25, preceding: Dictionary = {}, prime_adjacent: bool = false) -> Dictionary:
	# 预取下一实际视野的切面，而不是大视野父页：父页与随后细分的子页是不同物理资源。
	var fixed_now := preload("res://scripts/rendering/tokyo_hlod_foundation.gd").catalog_at(_foundation,scale_value)
	var prime_summary: bool=_flags.get("guard_prefetch",false) and fixed_now>=0 \
		and _catalogs[fixed_now].has("far_summary_recipe") and _zoom_rate>=-0.02
	var adjacent_entry := Handoff.preload_entry_scale(_catalogs,scale_value,_zoom_rate) if prime_adjacent and _flags.get("lod_transition",false) else 0.0
	var prime_exit := prime_summary or adjacent_entry>0.0
	if _pan_velocity.length()*scale_value<1.0 and absf(_zoom_rate)<0.02 and not prime_exit: return {}
	var horizon := prediction_horizon
	if _zoom_rate < -0.02 and not _flags.get("lod_transition",false):
		var current_catalog := Handoff.catalog_index(_catalogs,scale_value,false)
		if current_catalog>=0:
			var boundary := float(_catalogs[current_catalog].range[0])
			var crossing := log(boundary/scale_value)/_zoom_rate
			# 快速缩远也必须先准备相邻档，不能预测到更远目录而跳过必经资源。
			if crossing>=0.0 and crossing<horizon: horizon=minf(horizon,crossing+0.04)
	# 输出尺度含实际像素倍率；4K 的近景不能错误钳回 1080p 的 5.0 上限。
	var prediction_ceiling := maxf(5.0,5.0*size.x/_logical.x) if _flags.get("guard_prefetch",false) else 5.0
	# 半秒预取不能继续沿用旧250ms预测的倍率截断，否则位置预测会按错误的
	# 缩放速度积分，资源准备在真实WASD路线前方而非实际越界处。
	var zoom_span := 4.0 if _prediction_request.get("return_hint",{}).get("direct_return",false) else 0.7
	var future_scale := clampf(scale_value*exp(clampf(_zoom_rate*horizon,-zoom_span,zoom_span)),maxf(0.0973,_prediction_floor),prediction_ceiling)
	var zoom_hint: Dictionary=_prediction_request.get("return_hint",{})
	var exact_zoom: bool=_flags.get("guard_prefetch",false) and zoom_hint.has("zoom_target") and not prime_exit
	var output_ratio := size.x/_logical.x
	if exact_zoom:
		future_scale=float(_forecast_zoom(scale_value,horizon,output_ratio,zoom_hint).scale)
	# 缩向已常驻远档时，不能因终点资源齐备而漏掉必经的细档边缘。
	var ready_destination := Handoff.catalog_index(_catalogs,future_scale,false)
	if _flags.get("guard_prefetch",false):
		var fixed_destination := preload("res://scripts/rendering/tokyo_hlod_foundation.gd").catalog_at(_foundation,future_scale)
		if fixed_destination>=0: ready_destination=fixed_destination
	var needs_exit: bool=Handoff.catalog_index(_catalogs,scale_value,false)<0 or (_flags.get("guard_prefetch",false) and fixed_now<0)
	if not _flags.get("lod_transition",false) and _zoom_rate < -0.02 and needs_exit and ready_destination>=0 \
		and (_flags.get("guard_prefetch",false) or _foundation.get("layers",{}).has(ready_destination)):
		var checkpoint := Handoff.native_exit_checkpoint(scale_value,future_scale,float(_catalogs[ready_destination].range[1]))
		if checkpoint>future_scale:
			future_scale=checkpoint
			horizon=float(_forecast_zoom(scale_value,horizon,output_ratio,zoom_hint,future_scale).seconds) if exact_zoom else clampf(log(future_scale/scale_value)/_zoom_rate,0.0,horizon)
	if _flags.get("lod_transition",false):
		# 第一个预测点守住换档入口，后续点从已预测的入口继续前探。
		# 不能把所有时间点都截在同一边界，漏掉紧随其后的平移/缩远切面。
		var checkpoint_scale := float(preceding.get("forecast_scale",scale_value))
		var checkpoint_catalog := int(preceding.get("catalog",_committed_catalog))
		var checkpoint := Handoff.prediction_checkpoint(_catalogs,checkpoint_scale,future_scale,_zoom_rate,checkpoint_catalog)
		if not is_equal_approx(checkpoint,future_scale):
			future_scale=checkpoint
			horizon=float(_forecast_zoom(scale_value,horizon,output_ratio,zoom_hint,future_scale).seconds) if exact_zoom else clampf(log(future_scale/scale_value)/_zoom_rate,0.0,horizon)
	# 冷进入后第一次滚轮只需约70ms就越过0.4；此时才排细档纹理已经太晚。
	# 概括远景常驻时用同池空余提前准备出口，不等待滚轮发生才开始；不提前绑定细档。
	if prime_exit:
		# 普通分级也预热相邻档；查询它开始显示时的视野，不拿当前更大的视野压垮预算。
		var exit_scale := float(_foundation.layers[fixed_now].upper)*1.001 if prime_summary else adjacent_entry
		if not prime_summary:
			future_scale=exit_scale
			# 尚未滚轮时按正式相机最快可达时刻预热，不能把250ms后的远端位置当成交接入口。
			horizon=log(exit_scale/scale_value)/maxf(_zoom_rate,CameraController.ZOOM_LOG_SPEED)
		elif future_scale<exit_scale:
			future_scale=exit_scale
			# 出口尺度发生在未来越界时；位置也必须取同一时刻。否则高速平移时
			# 先加载的是镜头身后的页，即使纹理已就绪仍会在0.4边界等待网格。
			var exit_rate := maxf(_zoom_rate,2.0)
			horizon=maxf(horizon,log(exit_scale/scale_value)/exit_rate)
	# 只移动未来查询的中心，不扩大它的视口。SPACE回中一帧可经过数屏，
	# 把中心也截为一屏会使所有预测样本重合，并永远落在真实输入之后。
	var future_center := center+(_pan_velocity*horizon if _flags.get("guard_prefetch",false) \
		else Handoff.pan_lead(_pan_velocity,future_scale,horizon,size))
	var follow_hint: Dictionary=_prediction_request.get("return_hint",{})
	if prime_exit and follow_hint.has("zoom_target"):
		follow_hint=follow_hint.duplicate();follow_hint.erase("zoom_target")
	var future_velocity := _pan_velocity
	if _flags.get("guard_prefetch",false) and follow_hint.get("direct_destination",false):
		future_velocity=follow_hint.get("target_velocity",Vector2.ZERO)
		future_center=Vector2(follow_hint.position)+future_velocity*horizon
	elif _flags.get("guard_prefetch",false) and follow_hint.get("following",false):
		# 正式跟随逐帧使用rate*delta的线性权重，且玩家仍在飞行。连续指数近似
		# 会落后于真实回程；近景数屏跳转时这点偏差足以跨到未准备的父子页。
		var rate := float(follow_hint.rate)
		var step := float(follow_hint.get("step_seconds",0.0))
		var retention := maxf(0.0001,1.0-rate*step)
		var effective_rate := -log(retention)/step if step>0.0 else rate
		var target_velocity: Vector2=follow_hint.get("target_velocity",Vector2.ZERO)
		var lag := target_velocity*retention/rate
		var transient := (center-Vector2(follow_hint.position)+lag)*exp(-effective_rate*horizon)
		future_center=Vector2(follow_hint.position)+target_velocity*horizon-lag+transient
		future_velocity=target_velocity-transient*effective_rate
	elif _flags.get("guard_prefetch",false) and follow_hint.get("screen_pan",false):
		# WASD速度以屏幕像素定义。缩放时世界速度随1/zoom变化，线性外推
		# 会在放大时越过实际出口，且把过大的旧速度带进未来切面保护带。
		var pose_rate := log(future_scale/scale_value)/maxf(horizon,0.001)
		var distance_time := (1.0-exp(-pose_rate*horizon))/pose_rate if absf(pose_rate)>0.001 else horizon
		future_center=center+_pan_velocity*distance_time
		future_velocity=_pan_velocity*(scale_value/future_scale)
		if follow_hint.has("pan_direction"):
			var motion := _predict_screen_pan(center,scale_value,future_scale,horizon,follow_hint)
			future_center=motion.center;future_velocity=motion.velocity
	if prime_adjacent:
		# 邻档预热围绕当前视野，选择器自身仍加入方向保护带；沿路预测另行负责前方。
		# 把两份前探叠在一起会提前离开当前纹理范围，入口尚未到达就淘汰所需页。
		future_center=center
		future_velocity=_pan_velocity*(scale_value/future_scale)
	var index := Handoff.catalog_index(_catalogs,future_scale,_zoom_rate>=0.0 or prime_exit)
	var future_foundation := preload("res://scripts/rendering/tokyo_hlod_foundation.gd").catalog_at(_foundation,future_scale)
	# 概括远景的未来视野仍由常驻页完整覆盖时，不因纯平移提前加载两倍尺度细档。
	if future_foundation>=0 and _catalogs[future_foundation].has("far_summary_recipe"): index=future_foundation
	if index<0 or (_zoom_rate>=0.0 and future_scale>float(_catalogs[index].get("prefer_native_above",INF))): index=-2
	if _foundation.get("layers",{}).has(index):
		var fixed := preload("res://scripts/rendering/tokyo_hlod_foundation.gd").select(_catalogs[index],_foundation.layers[index].entries,future_center,future_scale,angle,size,display_budget,_selection_work)
		# 全部固定资源本来就在请求/保护集；完整未来切面有解时无需再次求整树预取。
		if not fixed.is_empty():
			foundation_prefetch_skips+=1
			return {}
	var cut: Dictionary
	var cacheable: bool=fixed_now>=0 and _catalogs[fixed_now].has("middle_massing_recipe") and index>=0
	if cacheable and prediction_horizon==0.25 and preload("res://scripts/rendering/tokyo_hlod_prefetch_cache.gd").reusable(_speculative_cache,_catalogs[index],index,future_center,future_scale,angle,size,_zoom_rate<0.0,Time.get_ticks_usec()):
		speculative_plan_reuses+=1
		return _speculative_cache.result
	if _prediction_planner!=null and not _prediction_request.is_empty():
		# 与实际显示共用完整选择规则：提前档无解可能退到实际档，父子页身份也会改变。
		# 独立纯值规划器不再递归预测；复用同一不可变来源，不创建资源或额外工作线程。
		var forecast := _prediction_request.duplicate()
		var canvas := Transform2D(angle,Vector2.ZERO).scaled(Vector2.ONE*future_scale*_logical.x/size.x)
		canvas.origin=_logical*0.5-canvas*future_center
		forecast.canvas=canvas;forecast.scale=future_scale;forecast.size=size
		forecast.pan_velocity=future_velocity
		forecast.camera_demand=false;forecast.zooming_out=_zoom_rate< -0.02
		forecast["actual_display_prediction"]=true
		forecast.zoom_rate=maxf(_zoom_rate,2.0) if prime_exit else _zoom_rate
		var preceding_catalog := int(preceding.get("catalog",-1))
		if _flags.get("return_cache",false) and preceding.has("prepared_cut") \
			and (preceding_catalog>=0 or (_flags.get("lod_transition",false) and preceding_catalog==-2)):
			# 相邻预测沿用同一待加载身份，仍经原在途切面的资格、未来覆盖与预算门。
			# 原生也须连续选页，避免每个前探点从当前显示重新选出不同父子网格。
			# 不伪造committed或ready；不满足下一机位则由完整选择器重算。
			forecast.target_catalog=preceding.catalog;forecast.target=preceding.prepared_cut
		var planned: Dictionary=_prediction_planner.plan(forecast)
		if planned.status!="candidate": return {}
		cut=planned.cut;index=int(planned.catalog)
	elif index==-2:
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
	var far_scale := clampf(scale_value*exp(clampf(_zoom_rate*0.25,-0.7,0.7)),maxf(0.0973,_prediction_floor),prediction_ceiling)
	var far_index := Handoff.catalog_index(_catalogs,far_scale,false)
	if prediction_horizon==0.25 and _zoom_rate < -0.02 and far_index>=0 and far_index!=index:
		var far_center := center+(_pan_velocity*0.25 if _flags.get("guard_prefetch",false) \
			else Handoff.pan_lead(_pan_velocity,far_scale,0.25,size))
		var far_cut := _select_hlod(_catalogs[far_index],far_center,far_scale,angle,size,true,Stream.BUDGET/2,false)
		if not far_cut.is_empty() and not far_cut.within_budget:
			far_cut=_select_hlod(_catalogs[far_index],far_center,far_scale,angle,size,true,-1,false)
		if not far_cut.is_empty() and far_cut.within_budget:
			for key: String in far_cut.keys:
				var row: Dictionary=_catalogs[far_index].rows[key]
				extra.append({"mesh":row.native_geometry.path,"image":row.native_texture.path})
	var result := {"catalog":index,"keys":cut.keys,"extra":extra}
	if _flags.get("lod_transition",false): result["forecast_scale"]=future_scale
	if _flags.get("lod_transition",false) and index!=_committed_catalog:
		# 准备完成不等于可以抢先显示。近中景联合后继有独立的1.18交接门。
		cut=cut.duplicate()
		var entry_scale := float(_catalogs[index].range[0]) if index>=0 else (1.25 if _committed_catalog>=0 else 0.0)
		cut["anticipated_scale"]=maxf(float(cut.get("anticipated_scale",0.0)),entry_scale)
	if _flags.get("guard_prefetch",false): result["prepared_cut"]=compact_cut(cut)
	if cacheable and prediction_horizon==0.25 and cut.get("within_budget",false):
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




func _compact_displayed_scale(request: Dictionary) -> Dictionary:
	if not _flags.get("display_compaction",false) or _committed_catalog<0 \
		or int(_committed_cut.get("bytes",0))<=Stream.BUDGET/2: return {}
	var canvas: Transform2D=request.get("display_canvas",request.canvas)
	var size: Vector2=request.get("display_size",request.size)
	var scale_value: float=request.get("display_scale",request.scale)
	var center := canvas.affine_inverse()*(_logical*0.5)
	var destination := Handoff.catalog_index(_catalogs,scale_value,false)
	if destination<0 \
		or not Handoff.qualified(_catalogs[_committed_catalog],_committed_cut,scale_value) \
		or not Handoff.covers_motion_view(_catalogs[_committed_catalog],_committed_cut,center,scale_value,canvas.get_rotation(),size): return {}
	var moving_coarser: bool=not request.get("camera_demand",false)
	if moving_coarser:
		# 连续缩远跨档时也要提前腾池，但停镜和同档不得反复压缩。
		if not request.get("zooming_out",false) or float(request.get("zoom_rate",0.0))>=-0.02 \
			or destination==_committed_catalog: return {}
		var motion := Handoff.native_motion_query(center,scale_value,canvas.get_rotation(),size,
			Handoff.pan_lead(request.pan_velocity,scale_value,0.25,size),0.25,request.zoom_rate)
		if motion.is_empty(): return {}
		# 自由推进的镜头必须覆盖下一装载窗口及96px余量，不能只交换裸视野。
		center=motion.center;size=motion.size+Vector2.ONE*192.0
	var transition := preload("res://scripts/rendering/tokyo_hlod_transition.gd")
	var index := transition.index_for(_catalogs,_committed_catalog,destination)
	if index<0: return {}
	var current_bytes := _handoff_bytes({"keys":PackedStringArray()},index)
	var budget: int=int(_stream.residency_limit)-int(_stream.residency_bytes)
	if current_bytes<0 or current_bytes>=budget: return {}
	var result := transition.compact_display(_catalogs,_committed_catalog,_committed_cut,destination,
		center,scale_value,canvas.get_rotation(),size,budget-current_bytes,_handoff_incremental_costs(index),_selection_work)
	if result.is_empty(): return {}
	if moving_coarser: result.cut["spatial_guard_px"]=96.0
	var combined := _handoff_bytes(result.cut,int(result.catalog))
	return result if combined>=0 and combined<=budget else {}


func _pending_display_compaction(request: Dictionary) -> bool:
	if not _flags.get("display_compaction",false) or not request.get("camera_demand",false) \
		or _target_catalog<0 or _committed_catalog<0 or _target_committed() \
		or not _target.get("within_budget",false) or int(_target.get("bytes",0))>=int(_committed_cut.get("bytes",0)) \
		or _target.get("selection_stage","") not in ["compact_displayed","compact_displayed_scale","trim_displayed"]: return false
	if not request.has("display_canvas") or not request.has("display_scale") or not request.has("display_size"): return false
	var canvas: Transform2D=request.display_canvas
	var size: Vector2=request.display_size
	var scale_value: float=request.display_scale
	if not canvas.is_finite() or not size.is_finite() or minf(size.x,size.y)<=0.0 \
		or not is_finite(scale_value) or scale_value<=0.0: return false
	var center := canvas.affine_inverse()*(_logical*0.5)
	for pair: Array in [[_committed_catalog,_committed_cut],[_target_catalog,_target]]:
		var catalog: Dictionary=_catalogs[int(pair[0])]
		if not Handoff.qualified(catalog,pair[1],scale_value) \
			or not Handoff.covers_motion_view(catalog,pair[1],center,scale_value,canvas.get_rotation(),size): return false
	var combined := _handoff_bytes(_target,_target_catalog)
	return combined>=0 and combined<=int(_stream.residency_limit)-int(_stream.residency_bytes)


func _pending_motion_path(request: Dictionary) -> bool:
	if not _flags.get("display_compaction",false) or not request.get("camera_demand",false) \
		or _target_catalog<0 or _committed_catalog<0 or _target_committed() \
		or not _target.get("within_budget",false) or not _target.get("motion_checkpoint",false): return false
	if not request.has("display_canvas") or not request.has("display_scale") or not request.has("display_size"): return false
	var from_canvas: Transform2D=request.display_canvas
	var display_size: Vector2=request.display_size
	var display_scale: float=request.display_scale
	if not from_canvas.is_finite() or not display_size.is_finite() or minf(display_size.x,display_size.y)<=0.0 \
		or not is_finite(display_scale) or display_scale<=0.0: return false
	var from_center := from_canvas.affine_inverse()*(_logical*0.5)
	var old: Dictionary=_catalogs[_committed_catalog]
	if not Handoff.qualified(old,_committed_cut,display_scale) \
		or not Handoff.covers_motion_view(old,_committed_cut,from_center,display_scale,from_canvas.get_rotation(),display_size): return false
	var combined := _handoff_bytes(_target,_target_catalog)
	if combined<0 or combined>int(_stream.residency_limit)-int(_stream.residency_bytes): return false
	var to_center: Vector2=request.canvas.affine_inverse()*(_logical*0.5)
	var catalog: Dictionary=_catalogs[_target_catalog]
	for fraction: float in [1.0]+CameraController.MAP_MOTION_FRACTIONS:
		var scale_value := lerpf(display_scale,float(request.scale),fraction)
		if not Handoff.qualified(catalog,_target,scale_value) or not _handoff_bridge_qualified(_target_catalog,_target,scale_value): continue
		if Handoff.covers_motion_view(catalog,_target,from_center.lerp(to_center,fraction),scale_value,
			lerp_angle(from_canvas.get_rotation(),request.canvas.get_rotation(),fraction),request.size): return true
	return false
