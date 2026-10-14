extends "res://scripts/rendering/tokyo_volume_overlay.gd"
## 显式整图验收候选；沿原视口/相机/合成，只替换几何资源所有者。
const Contract := preload("res://scripts/rendering/tokyo_hlod_manifest.gd")
const Coverage := preload("res://scripts/rendering/tokyo_hlod_coverage.gd")
const Stream := preload("res://scripts/rendering/tokyo_hlod_stream.gd")
const Ground := preload("res://scripts/rendering/tokyo_fixed_atlas_layer.gd")
const Native := preload("res://scripts/rendering/tokyo_hlod_native.gd")
const Handoff := preload("res://scripts/rendering/tokyo_hlod_handoff.gd")
const GridPage := preload("res://scripts/rendering/tokyo_grid_page.gd")
const GridNative := preload("res://scripts/rendering/tokyo_grid_native.gd")
var _native: RefCounted
var _native_hidden := PackedInt32Array()
var _catalogs: Array[Dictionary] = []
var _geometry: Dictionary = {}
var _textures: Dictionary = {}
var _stream: Node
var _target: Dictionary = {}
var _target_catalog := -1
var _committed_catalog := -1
var _committed := PackedStringArray()
var _committed_cut: Dictionary = {}
var _nodes: Array[MeshInstance3D] = []
var _page_materials: Array[ShaderMaterial] = []
var _ground_token := RefCounted.new()
var _ground_charged := false
var _legacy: WeakRef
var _hidden_sources := PackedInt32Array()
var _surface: Shader
var _height_surface: Shader
var _formal_surface: Shader
var _native_surface: Shader
var _warm_deadline := 0
var _fallback := "loading"
var _last_selected_canvas := Transform2D(0,Vector2(INF,INF))
var _last_selected_size := Vector2.ZERO
var preload_max_scale := 0.1944
var retained_cuts := 0
var selection_usec := 0
var binding_usec := 0
var output_scale := 0.0
var staged_switches := 0
var _handoff_reason := "initial"
var _prefetch_pages := 0
var _cached_cut_attempts := 0
var _cached_cut_commits := 0
var _native_screen_bridge_commits := 0
var _native_screen_bridge_state: Dictionary={}
var _zoom_rate := 0.0
var zoom_prediction_reversals := 0
var _zooming_in := false
var _last_zoom_direction := 0
var _display_grace := false
var _grace_started := -1
var _grace_age_ms := 0
var lod_grace_frames := 0
var max_lod_grace_ms := 0
var max_lod_grace_ratio := 1.0
var _selection_work: Dictionary = {}
var _small_uploads := OS.get_environment("AGL_TOKYO_SMALL_UPLOADS")=="1"
var _motion_center := Vector2(INF,INF)
var _pan_velocity := Vector2.ZERO
var display_budget := preload("res://scripts/rendering/tokyo_hlod_cache_policy.gd").display_limit()
var cache_pool_limit := preload("res://scripts/rendering/tokyo_hlod_cache_policy.gd").candidate_limit()
var loading_neighborhood := false
var loading_neighborhood_bytes := 0
var resident_foundation := OS.get_environment("AGL_TOKYO_RESIDENT_FOUNDATION")=="1"
var _foundation: Dictionary = {}
var foundation_prefetch_skips := 0
var _speculative_cache: Dictionary = {}
var speculative_plan_reuses := 0
var _future_predictor: RefCounted
var _ground_candidate_state: Dictionary={}
var _loading_residency_base: Dictionary={}
var loading_neighborhood_on_setup := false

class Layout extends Resource:
	var bounds := Rect2(-16300,-15700,32000,32000)
	var catalogs: Array[Dictionary] = []
	func valid() -> bool:
		return not catalogs.is_empty()


func _load_archive() -> Resource:
	var path := preload("res://scripts/rendering/tokyo_installed_map.gd").package_path()
	var digest := preload("res://scripts/rendering/tokyo_installed_map.gd").package_sha()
	if not Contract.sha(digest) or not FileAccess.file_exists(path) or FileAccess.get_sha256(path)!=digest: return null
	var package: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not package is Dictionary or package.get("schema")!=1 or not package.get("catalogs") is Array \
		or not Contract.binding(package.get("coverage")): return null
	for binding: Variant in package.catalogs:
		if not Contract.binding(binding): return null
		var catalog := Contract.read(binding.path,binding.sha256)
		if catalog.is_empty() or not Contract.numbers(binding.get("range"),2) \
			or binding.range[0]<catalog.min_scale or binding.range[1]>catalog.max_scale or binding.range[0]>=binding.range[1]: return null
		if not _catalogs.is_empty() and catalog.bounds!=_catalogs[0].bounds: return null
		var covered := Coverage.read(package.coverage.path,package.coverage.sha256,catalog)
		if covered.is_empty(): return null
		catalog["range"]=binding.range
		if binding.has("prefer_native_above"):
			if not Contract.numbers([binding.prefer_native_above],1) or binding.prefer_native_above<binding.range[0] or binding.prefer_native_above>binding.range[1]: return null
			catalog["prefer_native_above"]=binding.prefer_native_above
		for physical: String in covered:
			if _geometry.has(physical) and _geometry[physical]!=covered[physical]: return null
			_geometry[physical]=covered[physical]
		for physical: String in catalog.textures:
			if _textures.has(physical) and _textures[physical]!=catalog.textures[physical]: return null
			_textures[physical]=catalog.textures[physical]
		_catalogs.append(catalog)
	if package.has("native"):
		_native=preload("res://scripts/rendering/tokyo_grid_native.gd").new() if package.native.has("grid_candidate") else Native.new()
		if not _native.read(package.native): return null
		for texture_path: String in _native.ground.get("textures",{}):
			if _textures.has(texture_path): return null
			_textures[texture_path]=_native.ground.textures[texture_path]
		if _catalogs.is_empty() or _native.catalog.full_grid.bounds!=_catalogs[0].bounds: return null
		for physical: String in _native.pages:
			if _geometry.has(physical): return null
			_geometry[physical]=_native.pages[physical]
		preload_max_scale=5.0
		if OS.get_environment("AGL_TOKYO_ASYNC_PREFETCH")=="1" and not package.native.has("grid_candidate"):
			_future_predictor=preload("res://scripts/rendering/tokyo_native_predictor.gd").new()
			if not _future_predictor.prepare(_native):
				_future_predictor.close()
				return null
	var layout := Layout.new()
	if _catalogs.is_empty(): return null
	layout.bounds=_catalogs[0].bounds
	layout.catalogs=_catalogs
	return layout


func _setup_geometry() -> void:
	_composite.set_shader_parameter("edge_feather",0.0)
	_sun.shadow_enabled=false
	_surface=Shader.new()
	_surface.code=preload("res://scripts/rendering/tokyo_hlod_surface.gd").textured_code()
	_height_surface=Shader.new()
	_height_surface.code=preload("res://scripts/rendering/tokyo_ground_height.gd").shader_code()
	_formal_surface=Shader.new()
	_formal_surface.code=preload("res://scripts/rendering/tokyo_hlod_surface.gd").shader_code()
	_native_surface=Shader.new()
	_native_surface.code=preload("res://scripts/rendering/tokyo_hlod_surface.gd").native_code()
	_stream=Stream.new()
	if _native is GridNative:
		_native.subset_stream=weakref(_stream)
		_native.subset_geometry=_geometry
	# 退出后仍须领取在途资源，不能作为随overlay立即删除的子节点。
	get_tree().root.add_child(_stream)
	if not _stream.configure_hlod(self,_geometry,_textures):
		_fallback="invalid stream"
		_enabled=false
	elif resident_foundation:
		_foundation=preload("res://scripts/rendering/tokyo_hlod_foundation.gd").plan(_catalogs,display_budget,OS.get_environment("AGL_TOKYO_COMPLETE_FOUNDATION")=="1")
		if _foundation.is_empty() or not _stream.configure_residency(_foundation.meshes,_foundation.images,cache_pool_limit):
			_fallback="invalid foundation residency"
			_enabled=false
	elif OS.get_environment("AGL_TOKYO_RESIDENT_MIDDLE")=="1":
		var meshes := PackedStringArray()
		var images := PackedStringArray()
		for catalog: Dictionary in _catalogs:
			if catalog.range!=[0.0972,0.183]: continue
			for row: Dictionary in catalog.rows.values():
				if int(row.depth)!=2: continue
				meshes.append(row.native_geometry.path);images.append(row.native_texture.path)
		if not _stream.configure_residency(meshes,images):
			_fallback="invalid residency plan"
			_enabled=false
	elif OS.get_environment("AGL_TOKYO_RESIDENCY_POOL_ONLY")=="1":
		# 对照：同384MiB池但不预载整图，不把扩池收益误归因于载入阶段。
		_stream.residency_limit=384*1024*1024
	elif cache_pool_limit>Stream.BUDGET:
		_stream.residency_limit=cache_pool_limit
	# base.setup紧接着会同步_process(0)并发出首批I/O；邻区必须在那之前完成组合。
	if loading_neighborhood_on_setup and _enabled and cache_pool_limit>Stream.BUDGET:
		var source: Variant=_source_ref.get_ref()
		var camera: Variant=_camera_ref.get_ref()
		if typeof(source)==TYPE_OBJECT and is_instance_valid(source) and typeof(camera)==TYPE_OBJECT and is_instance_valid(camera):
			prepare_loading_neighborhood(camera.position,clampf(camera.zoom.x,0.0973,preload_max_scale),source.get_viewport().get_visible_rect().size)


func prepare_loading_neighborhood(center: Vector2, scale_value: float, output: Vector2) -> void:
	if cache_pool_limit<=Stream.BUDGET or loading_neighborhood: return
	var policy := preload("res://scripts/rendering/tokyo_hlod_cache_policy.gd")
	var base := {"meshes":_stream.residency_meshes.duplicate(),"images":_stream.residency_images.duplicate(),"bytes":_stream.residency_bytes}
	var plan: Dictionary=base.duplicate(true)
	var scales: Array[float]=[scale_value,scale_value*0.65,scale_value*1.5]
	var entry_catalog := Handoff.catalog_index(_catalogs,scale_value,false)
	# 大幅度合并的常驻档可能包含全部三个倍率；还须实际跨入相邻细档，不能空预载。
	if entry_catalog>=0: scales.append(float(_catalogs[entry_catalog].range[1])*1.01)
	# 载入阶段计算候选，不增加实际显示预算；整组装入，不能拿半份cut当预热完成。
	for proposed_scale: float in scales:
		var scale_now := clampf(proposed_scale,0.0244,5.0)
		var index := Handoff.catalog_index(_catalogs,scale_now,false)
		for offset: Vector2 in [Vector2.ZERO,Vector2.LEFT,Vector2.RIGHT,Vector2.UP,Vector2.DOWN]:
			var location := center+offset*output/scale_now*0.5
			var selected: Dictionary=_select_hlod(_catalogs[index],location,scale_now,0.0,output,false) if index>=0 else _select_native(location,scale_now,0.0,output,"",Stream.BUDGET,false)
			var choices: Array[Dictionary]=[{"catalog":index,"cut":selected}]
			if index>=0 and _native!=null:
				var configuration: String=_native.ground_configuration(scale_now)
				if not configuration.is_empty(): choices.append({"catalog":-2,"cut":_select_native(location,scale_now,0.0,output,configuration,display_budget,false)})
			for choice: Dictionary in choices:
				var cut: Dictionary=choice.cut
				if cut.is_empty() or not cut.get("within_budget",false): continue
				var meshes := PackedStringArray()
				var images := PackedStringArray()
				for key: String in cut.keys:
					if int(choice.catalog)<0: meshes.append(key)
					else:
						meshes.append(_catalogs[choice.catalog].rows[key].native_geometry.path)
						images.append(_catalogs[choice.catalog].rows[key].native_texture.path)
				if int(choice.catalog)<0: images.append_array(cut.get("ground_images",PackedStringArray()))
				policy.append_bundle(plan,meshes,images,_geometry,_textures,cache_pool_limit-2*Stream.BUDGET)
	if int(plan.bytes)>int(base.bytes):
		loading_neighborhood=_stream.configure_residency(plan.meshes,plan.images,cache_pool_limit,int(base.bytes)>0)
		if loading_neighborhood:
			_loading_residency_base=base
			loading_neighborhood_bytes=int(plan.bytes)-int(base.bytes)


func release_loading_neighborhood() -> void:
	if not loading_neighborhood: return
	# 只撤销临时邻区保护；原整图常驻层继续受保护，不清资源、不另建加载池。
	_stream.residency_meshes=_loading_residency_base.meshes
	_stream.residency_images=_loading_residency_base.images
	_stream.residency_bytes=_loading_residency_base.bytes
	_loading_residency_base.clear()
	loading_neighborhood=false
	_last_selected_size=Vector2.ZERO


func _step_geometry(view_bounds: Rect2, scale_value: float, _delta: float) -> bool:
	if not is_instance_valid(_stream): return false
	if _native!=null and _native.has_method("retire_subsets"):
		var protected := _committed.duplicate()
		protected.append_array(PackedStringArray(_target.get("keys",[])))
		protected.append_array(_stream.residency_meshes)
		_native.retire_subsets(protected)
	var handoff_budget: int=_stream.residency_limit-_stream.residency_bytes
	if output_scale>0.0 and _delta>0.0:
		var ratio := scale_value/output_scale
		var next_rate := Handoff.prediction_zoom_rate(_zoom_rate,ratio,_delta)
		zoom_prediction_reversals+=int(_zoom_rate*next_rate<0.0)
		_zoom_rate=next_rate
	output_scale=scale_value
	var motion_source: Node = _source_ref.get_ref()
	var motion_center := _last_canvas.affine_inverse()*(motion_source.get_viewport().get_visible_rect().size*0.5)
	if _motion_center.is_finite() and _delta>0.0:
		var displacement := motion_center-_motion_center
		# 瞬切另走冷进入，不把瞬移距离作为无限预取带。
		var velocity := displacement/_delta if displacement.length()*scale_value<160.0 else Vector2.ZERO
		# 候选预取按时间平滑：物理60Hz/呈现120Hz的零位移交替不能放大为预测摆动。
		_pan_velocity=_future_predictor.smooth_pan(_pan_velocity,velocity,_delta) if _future_predictor!=null else _pan_velocity.lerp(velocity,0.4)
	_motion_center=motion_center
	var previous_scale := _last_selected_canvas.x.length()
	var direction := Handoff.zoom_direction(previous_scale,_last_canvas.x.length())
	var zooming_out := direction<0
	var reversing_in := direction>0 and _last_zoom_direction<0
	if direction!=0: _last_zoom_direction=direction
	_zooming_in=direction>0
	# 已就绪的合格中间档先交接；方向反转后不提交更快过期的降档事务。
	var changed := _commit_ready_target(scale_value)
	_update_display_grace(view_bounds.intersection(_archive.bounds),scale_value)
	var rapid_zoom := previous_scale>0.0 and absf(_last_canvas.x.length()/previous_scale-1.0)>0.025
	var visible_ground := view_bounds.intersection(_archive.bounds)
	var current_covered := _cut_covers_current_view(_committed_cut,-2) if _committed_catalog==-2 else \
		(_committed_catalog>=0 and Handoff.covers_view(_catalogs[_committed_catalog],_committed_cut,visible_ground))
	if _selection_due(current_covered,scale_value,reversing_in,rapid_zoom) and (_last_selected_canvas!=_last_canvas or _last_selected_size!=_last_size):
		_lod_clock=0.05
		_last_selected_canvas=_last_canvas
		_last_selected_size=_last_size
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
			var source: Variant = _source_ref.get_ref()
			var logical: Vector2 = source.get_viewport().get_visible_rect().size
			var center := _last_canvas.affine_inverse()*(logical*0.5)
			# 常驻页不必为重新加载同一资源预留半池；仍守原96MiB显示门。
			if foundation_catalog>=0:
				next=preload("res://scripts/rendering/tokyo_hlod_foundation.gd").select(_catalogs[selected],_foundation.layers[selected].entries,center,scale_value,_last_canvas.get_rotation(),_last_size,display_budget)
			if next.is_empty():
				next=_select_native(center,scale_value,_last_canvas.get_rotation(),_last_size,"",Stream.BUDGET/2) if selected==-2 else _select_hlod(_catalogs[selected],center,scale_value,_last_canvas.get_rotation(),_last_size,true,Stream.BUDGET/2)
			# 稳态优先留出一份交接空间；只有完整清晰切面确实放不下时才使用全预算。
			if selected>=0 and not next.is_empty() and not next.within_budget:
				next=_select_hlod(_catalogs[selected],center,scale_value,_last_canvas.get_rotation(),_last_size,true)
			elif selected==-2 and (next.is_empty() or not next.within_budget):
				next=_select_native(center,scale_value,_last_canvas.get_rotation(),_last_size)
			# 双向缩放均先完成仍完整合格的在途桥接档，缩远还须保留96px余量。
			# 不能让下一目录的提前偏好取消它，导致旧档已过期而两批新页都未完成。
			if _target_catalog>=0 and not _target_committed() and not _target.has("anticipated_scale") \
				and Handoff.qualified(_catalogs[_target_catalog],_target,scale_value) and _target_covers_current_view(96.0 if zooming_out else 0.0):
				# 同目录平移也要先完成完整在途页；不能只保护跨LOD交接。
				selected=_target_catalog
				next=_target
			# 原生是细节偏好，不得取消仍完整合格的HLOD在途事务；提交后再升级。
			var finishing_hlod := selected>=0 and selected==_target_catalog and not _target_committed() \
				and not next.is_empty() and Contract.retained(_catalogs[selected],_target,next,scale_value,true)
			if _native!=null and not _native.ground.is_empty(): _ground_candidate_state={"deferred":finishing_hlod}
			if not finishing_hlod and (next.is_empty() or not next.within_budget):
				var current_foundation := preload("res://scripts/rendering/tokyo_hlod_foundation.gd").catalog_at(_foundation,scale_value)
				if current_foundation>=0:
					var fixed := preload("res://scripts/rendering/tokyo_hlod_foundation.gd").select(_catalogs[current_foundation],_foundation.layers[current_foundation].entries,center,scale_value,_last_canvas.get_rotation(),_last_size,display_budget)
					# 提前细档无解时仍有完整常驻切面，不能转求昂贵原生树；预测预取另走原路径。
					if not fixed.is_empty(): next=fixed;selected=current_foundation
			if OS.get_environment("AGL_TOKYO_ACTUAL_BEFORE_NATIVE")=="1" and not finishing_hlod:
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
				var native_cut: Dictionary = _select_native(center,scale_value,_last_canvas.get_rotation(),_last_size,"",Stream.BUDGET/2)
				if native_cut.is_empty() or not native_cut.within_budget: native_cut=_select_native(center,scale_value,_last_canvas.get_rotation(),_last_size)
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
			if selected>=0 and selected==_target_catalog and not next.is_empty() and (not _target_committed() or int(_target.get("bytes",display_budget))<=maxi(Stream.BUDGET/2,int(next.bytes))) and Contract.retained(_catalogs[selected],_target,next,scale_value,true):
				next=_target
				retained_cuts+=1
			# 先原样裁掉已离屏的旧页；不加载替代桥接页，给新档让出真实预算。
			if selected>=0 and not next.is_empty() and _committed_catalog>=0 and _committed_qualified(scale_value) \
				and _handoff_bytes(next,selected)>handoff_budget \
				and Handoff.covers_view(_catalogs[_committed_catalog],_committed_cut,view_bounds.intersection(_archive.bounds)):
				var visible_old := Contract.visible_subset(_catalogs[_committed_catalog],_committed_cut,center,scale_value,_last_canvas.get_rotation(),_last_size)
				if not visible_old.is_empty() and visible_old.within_budget and visible_old.keys.size()<_committed.size():
					next=visible_old;selected=_committed_catalog
					# 裁页不需I/O；下一帧继续原换档事务，即使相机已停止也不能搁置。
					_lod_clock=0.0
					_last_selected_size=Vector2.ZERO
			# 不只按稳态最低面数选页：交接需给仍在显示的旧切面留足物理内存。
			if selected>=0 and not next.is_empty() and not _committed.is_empty() and _handoff_bytes(next,selected)>handoff_budget:
				var current_bytes := _handoff_bytes({"keys":PackedStringArray()},selected)
				var remaining := clampi(handoff_budget-current_bytes,0,display_budget) if current_bytes>=0 else 0
				var compact := _select_hlod(_catalogs[selected],center,scale_value,_last_canvas.get_rotation(),_last_size,true,remaining)
				if not compact.is_empty() and compact.within_budget:
					var compact_bytes := _handoff_bytes(compact,selected)
					if compact_bytes>=0 and compact_bytes<=handoff_budget: next=compact
				# 先预取新档的到期尺度切面，避免旧档再分块的I/O吃掉新档加载窗口；提交另验真实覆盖。
				if _handoff_bytes(next,selected)>handoff_budget and _committed_catalog>=0 and _committed_qualified(scale_value):
					var future_scale := Handoff.anticipation_scale(_catalogs[_committed_catalog],_committed_cut,view_bounds.intersection(_archive.bounds))
					if future_scale>scale_value:
						var anticipated := _select_hlod(_catalogs[selected],center,future_scale,_last_canvas.get_rotation(),_last_size,true,Stream.BUDGET/2)
						if not anticipated.is_empty() and not anticipated.within_budget:
							anticipated=_select_hlod(_catalogs[selected],center,future_scale,_last_canvas.get_rotation(),_last_size,true)
						if not anticipated.is_empty() and anticipated.within_budget:
							var anticipated_bytes := _handoff_bytes(anticipated,selected)
							if anticipated_bytes>=0 and anticipated_bytes<=handoff_budget:
								anticipated["anticipated_scale"]=future_scale
								next=anticipated
				# 新档提前切面仍放不下，才缩减旧档桥接；空间前提和联合预算均不放宽。
				if _handoff_bytes(next,selected)>handoff_budget and _committed_catalog>=0 and _committed_qualified(scale_value):
					var bridge := _select_hlod(_catalogs[_committed_catalog],center,scale_value,_last_canvas.get_rotation(),_last_size,true,Stream.BUDGET/2)
					if not bridge.is_empty() and bridge.within_budget and int(bridge.charges.total_bytes)<current_bytes:
						var bridge_bytes := _handoff_bytes(bridge,_committed_catalog)
						if bridge_bytes>=0 and bridge_bytes<=handoff_budget:
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
				var predict_started := Time.get_ticks_usec() if PerfBuckets.frame_trace_enabled else 0
				var predicted := _predict_prefetch(center,scale_value,_last_canvas.get_rotation(),_last_size)
				if PerfBuckets.frame_trace_enabled: PerfBuckets.tick("tokyo_map_predict_plan",Time.get_ticks_usec()-predict_started)
				if not predicted.is_empty():
					# next可能与在途目标共享Dictionary；先复制，才能正确检测预取身份变化。
					next=next.duplicate()
					next["prefetch_catalog"]=predicted.catalog
					next["prefetch_keys"]=predicted.keys
					next["prefetch_extra"]=predicted.extra
				# 显式对照：旧页已缺边时，优先用缓存内完整合格切面接住；原目标继续预取。
				if OS.get_environment("AGL_TOKYO_CACHED_CUT")=="1" and (not current_covered or not _committed_qualified(scale_value)) and not _committed.is_empty() and not _resources_ready(next,selected):
					var bridge_started := Time.get_ticks_usec()
					_cached_cut_attempts+=1
					var cached := preload("res://scripts/rendering/tokyo_hlod_cached_cut.gd")
					var native_bridge: Dictionary={}
					if selected==-2 and OS.get_environment("AGL_TOKYO_NATIVE_SCREEN_BRIDGE")=="1":
						native_bridge=_native_screen_bridge(next,center,scale_value,_last_canvas.get_rotation(),_last_size,handoff_budget)
					if not native_bridge.is_empty(): next=native_bridge
					for cached_index: int in cached.candidate_catalogs(_catalogs,selected,_committed_catalog,scale_value) if native_bridge.is_empty() else PackedInt32Array():
						var ready_cut: Dictionary={}
						if _foundation.get("layers",{}).has(cached_index):
							ready_cut=preload("res://scripts/rendering/tokyo_hlod_foundation.gd").select(_catalogs[cached_index],_foundation.layers[cached_index].entries,center,scale_value,_last_canvas.get_rotation(),_last_size,display_budget)
							if not _resources_ready(ready_cut,cached_index): ready_cut={}
						if ready_cut.is_empty():
							ready_cut=cached.select(_catalogs[cached_index],center,scale_value,_last_canvas.get_rotation(),_last_size,_geometry,_stream._cache,_stream._textures)
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
					if PerfBuckets.frame_trace_enabled: PerfBuckets.tick("tokyo_map_cache_bridge",Time.get_ticks_usec()-bridge_started)
			selection_usec+=Time.get_ticks_usec()-selection_start
		# 候选无解与当前显示失效是两件事；仍合格且覆盖完整时沿用已绑定切面。
		if (next.is_empty() or not next.within_budget) and Handoff.retain_display(_committed_cut,_committed_qualified(scale_value),current_covered,display_budget,Contract.native_page_limit() if _committed_catalog==-2 else 16):
			next=_committed_cut;selected=_committed_catalog
		if next.is_empty() or not next.within_budget:
			_clear_current()
			_target={};_target_catalog=-1
			_stream.request_residency_only()
			_fallback="unsupported scale" if selected==-1 else "cut budget"
		elif selected!=_target_catalog or _target.get("keys")!=next.keys or _target.get("anticipated_scale",0.0)!=next.get("anticipated_scale",0.0) or (selected==-2 and (_target.get("masks")!=next.masks or _target.get("grid_pieces",{})!=next.get("grid_pieces",{}) or _target.get("ground_images",PackedStringArray())!=next.get("ground_images",PackedStringArray()))) or Handoff.prefetch_changed(_target,next,selected):
			var staging := false
			_handoff_reason="native_or_initial"
			if not _committed.is_empty() and (_committed_qualified(scale_value) or _display_grace):
				var combined := _handoff_bytes(next,selected)
				staging=combined>=0 and combined<=handoff_budget
				_handoff_reason="retained" if staging else "union_budget"
			elif not _committed.is_empty():
				_handoff_reason="old_scale"
			# 提前预取超联合预算时，旧页仍合格就等视野收窄；不能主动闪回后再加载。
			if not staging and not _committed.is_empty() and (_committed_qualified(scale_value) or _display_grace):
				if _committed_catalog>=0 and not Handoff.covers_view(_catalogs[_committed_catalog],_committed_cut,view_bounds.intersection(_archive.bounds)):
					_handoff_reason="old_view"
					_clear_current()
				else:
					_handoff_reason="wait_union_budget"
					_fallback="waiting prefetch budget"
					_record_display_grace(scale_value)
					return changed
			if not staging: _clear_current()
			else: staged_switches+=1
			_target=next;_target_catalog=selected
			_request_target(staging)
			_fallback="staging cut" if staging else "loading cut"
			changed=true
	# 相机继续放大时旧切面可能失去清晰度资格，不能为避免回退继续显示。
	if not _target.is_empty() and not _target_committed() \
		and (_committed.is_empty() or not _committed_qualified(scale_value) or not current_covered):
		_stream.collect_ready_meshes()
	if not _target.is_empty() and not _target_committed() and not _committed.is_empty() \
		and not _committed_qualified(scale_value) and not _display_grace:
		_handoff_reason="old_scale"
		_clear_current()
		_request_target(false)
		_fallback="loading cut"
	changed=_commit_ready_target(scale_value) or changed
	_record_display_grace(scale_value)
	_screen.visible=_active and not _committed.is_empty()
	_sync_legacy()
	return changed


func _selection_due(current_covered: bool, scale_value: float, reversing_in: bool, rapid_zoom: bool) -> bool:
	# 覆盖完整不代表清晰度仍合格；跨地表上限时必须当帧换目标，不能先清屏再等20Hz选页。
	return _lod_clock<=0.0 or reversing_in or not current_covered or not _committed_qualified(scale_value) \
		or (rapid_zoom and _lod_clock<=0.05-1.0/60.0)


func _update_display_grace(view: Rect2, scale_value: float) -> void:
	_display_grace=false
	_grace_age_ms=0
	if _committed_catalog<0 or _committed.is_empty() or _committed_qualified(scale_value):
		_grace_started=-1
		return
	var now := Time.get_ticks_msec()
	if _grace_started<0: _grace_started=now
	_grace_age_ms=now-_grace_started
	_display_grace=Handoff.display_grace(_catalogs[_committed_catalog],_committed_cut,scale_value,_grace_age_ms,view)


func _record_display_grace(scale_value: float) -> void:
	if not _display_grace or _committed_catalog<0: return
	lod_grace_frames+=1
	max_lod_grace_ms=maxi(max_lod_grace_ms,_grace_age_ms)
	max_lod_grace_ratio=maxf(max_lod_grace_ratio,scale_value/Handoff.scale_limit(_catalogs[_committed_catalog],_committed_cut))


func _select_hlod(catalog: Dictionary, center: Vector2, scale: float, angle: float, size: Vector2, finer: bool = false, budget: int = -1) -> Dictionary:
	if budget==-1:
		# 扩大硬上限不能把原48/96MiB首选一起抬高；原切面可用时保持原资源身份。
		if display_budget>Stream.BUDGET:
			var original := _select_hlod(catalog,center,scale,angle,size,finer,Stream.BUDGET)
			if not original.is_empty() and original.within_budget: return original
		budget=display_budget
	var foundation_probe_started := Time.get_ticks_usec() if PerfBuckets.frame_trace_enabled else 0
	for index: int in _foundation.get("layers",{}):
		if _catalogs[index]!=catalog: continue
		var fixed := preload("res://scripts/rendering/tokyo_hlod_foundation.gd").select(catalog,_foundation.layers[index].entries,center,scale,angle,size,budget)
		if not fixed.is_empty():
			if PerfBuckets.frame_trace_enabled: PerfBuckets.tick("tokyo_map_hlod_foundation_probe",Time.get_ticks_usec()-foundation_probe_started)
			return fixed
	if PerfBuckets.frame_trace_enabled: PerfBuckets.tick("tokyo_map_hlod_foundation_probe",Time.get_ticks_usec()-foundation_probe_started)
	# 空间提前量与缩放提前量独立；保持真实像素尺度，不能用降低scale冒充扩区。
	var lead := Handoff.pan_lead(_pan_velocity,scale,0.35,size)
	var padding := (Transform2D(angle,Vector2.ZERO).basis_xform(lead)*scale).abs()+Vector2(384,384)
	var expanded := Contract.select(catalog,center+lead*0.5,scale,angle,size+padding,finer,budget,_selection_work,_small_uploads)
	if not expanded.is_empty() and not expanded.within_budget and budget==Stream.BUDGET/2:
		var full := Contract.select(catalog,center+lead*0.5,scale,angle,size+padding,finer,Stream.BUDGET,_selection_work,_small_uploads)
		var lookup_started := Time.get_ticks_usec() if PerfBuckets.frame_trace_enabled else 0
		var index := _catalogs.find(catalog)
		if PerfBuckets.frame_trace_enabled: PerfBuckets.tick("tokyo_map_hlod_catalog_lookup",Time.get_ticks_usec()-lookup_started)
		if not full.is_empty() and full.within_budget and ( _committed.is_empty() or (index>=0 and _handoff_bytes(full,index)<=_stream.residency_limit-_stream.residency_bytes)):
			expanded=full
	if not expanded.is_empty() and expanded.within_budget:
		expanded["spatial_guard_px"]=192
		return expanded
	# 大保护带放不下时逐级收窄，不能一步退到零余量。
	for ratio: float in [0.5,0.25]:
		var reduced := Contract.select(catalog,center+lead*0.5*ratio,scale,angle,size+padding*ratio,finer,budget,_selection_work,_small_uploads)
		if not reduced.is_empty() and reduced.within_budget:
			reduced["spatial_guard_px"]=192*ratio
			return reduced
	var actual := Contract.select(catalog,center,scale,angle,size,finer,budget,_selection_work,_small_uploads)
	if actual.is_empty(): return {}
	actual["spatial_guard_px"]=0
	actual["guard_rejection"]={"faces":expanded.get("triangles",0),"bytes":expanded.get("bytes",0),"budget":budget,"kind":"hlod"}
	# 超显示面数/字节的扩区只能作为未绑定预取集，绝不作为合格显示切面提交。
	actual["guard_prefetch_keys"]=expanded.get("keys",PackedStringArray())
	return actual


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


func _select_native(center: Vector2, scale: float, angle: float, size: Vector2, configuration: String = "", budget: int = -1, retain_current: bool = true) -> Dictionary:
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
	var query_started := Time.get_ticks_usec() if PerfBuckets.frame_trace_enabled else 0
	var expanded: Dictionary = _native.select(center+lead*0.5,scale,angle,size+padding,configuration,budget)
	if PerfBuckets.frame_trace_enabled: PerfBuckets.tick("tokyo_native_query.expanded",Time.get_ticks_usec()-query_started)
	if (expanded.is_empty() or not expanded.within_budget) and budget==Stream.BUDGET/2:
		var full: Dictionary = _native.select(center+lead*0.5,scale,angle,size+padding,configuration,display_budget)
		if not full.is_empty() and full.within_budget and (_committed.is_empty() or _handoff_bytes(full,-2)<=_stream.residency_limit-_stream.residency_bytes): expanded=full
	if not expanded.is_empty() and expanded.within_budget:
		expanded["spatial_guard_px"]=192
		return expanded
	for ratio: float in [0.5,0.25]:
		query_started=Time.get_ticks_usec() if PerfBuckets.frame_trace_enabled else 0
		var reduced: Dictionary=_native.select(center+lead*0.5*ratio,scale,angle,size+padding*ratio,configuration,budget)
		if PerfBuckets.frame_trace_enabled: PerfBuckets.tick("tokyo_native_query.half" if ratio==0.5 else "tokyo_native_query.quarter",Time.get_ticks_usec()-query_started)
		if not reduced.is_empty() and reduced.within_budget:
			reduced["spatial_guard_px"]=192*ratio
			return reduced
	query_started=Time.get_ticks_usec() if PerfBuckets.frame_trace_enabled else 0
	var actual: Dictionary = _native.select(center,scale,angle,size,configuration,budget)
	if PerfBuckets.frame_trace_enabled: PerfBuckets.tick("tokyo_native_query.bare",Time.get_ticks_usec()-query_started)
	if actual.is_empty(): return {}
	actual["spatial_guard_px"]=0
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
		var fixed := preload("res://scripts/rendering/tokyo_hlod_foundation.gd").select(_catalogs[index],_foundation.layers[index].entries,future_center,future_scale,angle,size,display_budget)
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
		if _future_predictor!=null:
			cut=_future_predictor.request(future_center,future_scale,angle,size,configuration,_pan_velocity,1 if _zoom_rate>0.02 else (-1 if _zoom_rate< -0.02 else 0),display_budget,_async_full_prefetch_allowed,_zoom_rate)
		if cut.is_empty():
			cut=_select_native(future_center,future_scale,angle,size,configuration,Stream.BUDGET/2,false)
			if cut.is_empty() or not cut.within_budget: cut=_select_native(future_center,future_scale,angle,size,configuration,display_budget,false)
		if _future_predictor!=null: _future_predictor.dispatch()
	else:
		# 必须与实际选页使用同样的保护带；仅预测裸视野会选出另一套父子页。
		cut=_select_hlod(_catalogs[index],future_center,future_scale,angle,size,true,Stream.BUDGET/2)
		if not cut.is_empty() and not cut.within_budget:
			cut=_select_hlod(_catalogs[index],future_center,future_scale,angle,size,true)
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
		var far_cut := _select_hlod(_catalogs[far_index],far_center,far_scale,angle,size,true,Stream.BUDGET/2)
		if not far_cut.is_empty() and not far_cut.within_budget:
			far_cut=_select_hlod(_catalogs[far_index],far_center,far_scale,angle,size,true)
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
	if _native==null or not is_instance_valid(_stream) or pending.get("configuration","").is_empty(): return {}
	_native_screen_bridge_state={"reason":"selection","attempts":int(_native_screen_bridge_state.get("attempts",0))+1}
	# 完整三层选择器重新求屏内切面，不从旧目标删除未就绪页；同档清晰度与原预算不变。
	var cut: Dictionary=_native.select(center,scale_value,angle,size,pending.configuration,display_budget,{"meshes":_stream._cache,"textures":_stream._textures})
	_native_screen_bridge_state["faces"]=cut.get("triangles",0)
	_native_screen_bridge_state["bytes"]=cut.get("bytes",0)
	_native_screen_bridge_state["pages"]=cut.get("active",0)
	if not Handoff.retain_display(cut,Handoff.native_qualified(cut,scale_value),true,display_budget,Contract.native_page_limit()): return {}
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


func _cut_covers_current_view(cut: Dictionary, catalog: int, margin_px: float = 0.0) -> bool:
	var coverage_started := Time.get_ticks_usec() if PerfBuckets.frame_trace_enabled else 0
	var source: Variant = _source_ref.get_ref() if _source_ref!=null else null
	if typeof(source)!=TYPE_OBJECT or not is_instance_valid(source): return false
	var logical: Vector2 = source.get_viewport().get_visible_rect().size
	var inverse := _last_canvas.affine_inverse()
	var view := Rect2(inverse*Vector2.ZERO,Vector2.ZERO)
	for point: Vector2 in [Vector2(logical.x,0),logical,Vector2(0,logical.y)]: view=view.expand(inverse*point)
	view=view.grow(margin_px/maxf(output_scale,0.001)).intersection(_archive.bounds)
	if catalog>=0:
		var covered_hlod := Handoff.covers_view(_catalogs[catalog],cut,view)
		if PerfBuckets.frame_trace_enabled: PerfBuckets.tick("tokyo_map_coverage",Time.get_ticks_usec()-coverage_started)
		return covered_hlod
	if _native==null: return false
	var margin_logical := Vector2.ONE*margin_px*logical/_last_size
	var expanded_canvas := _last_canvas
	expanded_canvas.origin+=margin_logical
	var covered_native: bool=_native.covers_visible_layers(cut,view,expanded_canvas,logical+2.0*margin_logical)
	if PerfBuckets.frame_trace_enabled: PerfBuckets.tick("tokyo_map_coverage",Time.get_ticks_usec()-coverage_started)
	return covered_native


func _commit_ready_target(scale_value: float) -> bool:
	if _target.is_empty() or _target_committed(): return false
	# 所有目标都必须重新证明此刻覆盖；异步期间相机可能已离开请求时的视野。
	if not _target_covers_current_view(): return false
	if _zooming_in and _target_catalog>=0 and _committed_catalog>=0 and _committed_qualified(scale_value) \
		and _cut_covers_current_view(_committed_cut,_committed_catalog) \
		and Handoff.scale_limit(_catalogs[_target_catalog],_target)<Handoff.scale_limit(_catalogs[_committed_catalog],_committed_cut):
		return false
	if _target.has("anticipated_scale"):
		if scale_value<float(_target.anticipated_scale): return false
		var source: Variant=_source_ref.get_ref() if _source_ref!=null else null
		if typeof(source)!=TYPE_OBJECT or not is_instance_valid(source): return false
		var logical: Vector2=source.get_viewport().get_visible_rect().size
		var center := _last_canvas.affine_inverse()*(logical*0.5)
		var required := _select_hlod(_catalogs[_target_catalog],center,scale_value,_last_canvas.get_rotation(),_last_size,true)
		if required.is_empty() or not required.within_budget or not Contract.retained(_catalogs[_target_catalog],_target,required,scale_value,true): return false
	if _target_catalog==-2:
		if not Handoff.native_qualified(_target,scale_value): return false
	elif _target_catalog<0 or not Handoff.qualified(_catalogs[_target_catalog],_target,scale_value): return false
	if not _resources_ready(_target,_target_catalog): return false
	# 新地表租约先到手才释放旧画面；预约失败必须保持旧节点、可见性和旧租约。
	var next_ground: RefCounted
	if _target_catalog!=-2 or int(_target.get("charges",{}).get("ground_bytes",0))>0:
		next_ground=RefCounted.new()
		if not _stream.reserve_auxiliary(next_ground.get_instance_id(),int(_target.charges.ground_bytes)):
			_fallback="waiting ground budget"
			_handoff_reason="ground_budget"
			return false
	_clear_current()
	if next_ground!=null: _ground_token=next_ground
	_cached_cut_commits+=int(_target.get("cache_bridge",false))
	_native_screen_bridge_commits+=int(_target.get("native_screen_bridge",false))
	_ground_charged=next_ground!=null
	_bind_target()
	_request_target(false)
	# 已在途的HLOD完成后，补一次曾推迟的候选选择；静止镜头也不能永久停在桥接档。
	if _target_catalog>=0 and _ground_candidate_state.get("deferred",false):
		_ground_candidate_state["deferred"]=false
		_last_selected_size=Vector2.ZERO
	_screen.visible=_active
	_sync_legacy()
	return true


func _resources_ready(cut: Dictionary, catalog: int) -> bool:
	if not is_instance_valid(_stream) or cut.get("keys",PackedStringArray()).is_empty(): return false
	if catalog!=-2 and (catalog<0 or catalog>=_catalogs.size()): return false
	for path: String in cut.get("ground_images",[]):
		if _stream.texture(path)==null: return false
	for key: String in cut.keys:
		if catalog==-2:
			if _stream.resource(key)==null: return false
		else:
			if not _catalogs[catalog].rows.has(key): return false
			var row: Dictionary=_catalogs[catalog].rows[key]
			if _stream.resource(row.native_geometry.path)==null or _stream.texture(row.native_texture.path)==null: return false
	return true


func _target_committed() -> bool:
	return not _committed.is_empty() and _committed_catalog==_target_catalog and _committed==_target.get("keys") \
		and (_target_catalog!=-2 or _committed_cut.get("masks")==_target.get("masks")) \
		and PackedStringArray(_committed_cut.get("ground_images",[]))==PackedStringArray(_target.get("ground_images",[]))

func _committed_qualified(scale_value: float) -> bool:
	return Handoff.native_qualified(_committed_cut,scale_value) if _committed_catalog==-2 \
		else _committed_catalog>=0 and Handoff.qualified(_catalogs[_committed_catalog],_committed_cut,scale_value)

func _handoff_bytes(next: Dictionary, selected: int) -> int:
	var budget_started := Time.get_ticks_usec() if PerfBuckets.frame_trace_enabled else 0
	var meshes := PackedStringArray()
	var textures := PackedStringArray()
	var ground := 0
	for pair: Array in [[_committed_catalog,_committed_cut],[selected,next]]:
		var index: int=pair[0]
		var cut: Dictionary=pair[1]
		ground+=int(cut.get("charges",{}).get("ground_bytes",0))
		textures.append_array(PackedStringArray(cut.get("ground_images",[])))
		for key: String in cut.keys:
			if index==-2: meshes.append(key)
			else:
				var row: Dictionary=_catalogs[index].rows[key]
				meshes.append(row.native_geometry.path);textures.append(row.native_texture.path)
	var amount := -1
	if is_instance_valid(_stream) and _stream.residency_bytes>0:
		# 调用方比较的是扣除固定集后的余额；只计算物理联合相对固定集的增量。
		# 不以池上限截断，让原调用方仍能区分超预算与无效描述符。
		amount=_stream.handoff_increment(_geometry,_textures,meshes,textures,ground)
	else:
		amount=Handoff.streaming_bytes(_geometry,_textures,meshes,textures,ground)
	if PerfBuckets.frame_trace_enabled: PerfBuckets.tick("tokyo_map_handoff_budget",Time.get_ticks_usec()-budget_started)
	return amount


func _request_target(keep_current: bool) -> void:
	var request_started := Time.get_ticks_usec()
	var meshes := PackedStringArray()
	var textures := PackedStringArray()
	var mesh_pins := PackedStringArray()
	var texture_pins := PackedStringArray()
	textures.append_array(PackedStringArray(_target.get("ground_images",[])))
	for key: String in _target.keys:
		if _target_catalog==-2:
			meshes.append(key)
		else:
			var row: Dictionary = _catalogs[_target_catalog].rows[key]
			meshes.append(row.native_geometry.path)
			textures.append(row.native_texture.path)
	# 在附加预测之前保存真实目标，跨网格/图片的共享槽不能只按各自列表排序。
	var charged_meshes := meshes.duplicate()
	var charged_images := textures.duplicate()
	var priority_meshes := meshes.duplicate()
	var prefetch_meshes := PackedStringArray()
	_stream.touch_display_resources(meshes,textures)
	if _stream.visible_io_first or _stream.fair_image_slot or _stream.visible_finalize_first:
		_stream.visible_meshes=_stream._paths(meshes)
		_stream.visible_images=textures.duplicate()
	# 载入与战场始终同一池/同一固定集，不能进入游戏后立即淘汰预载资源。
	var seen_meshes: Dictionary = {}
	var seen_textures: Dictionary = {}
	for path: String in meshes: seen_meshes[path]=true
	for path: String in textures: seen_textures[path]=true
	for path: String in _stream.residency_meshes:
		if not seen_meshes.has(path):
			meshes.append(path);seen_meshes[path]=true
	for path: String in _stream.residency_images:
		if not seen_textures.has(path):
			textures.append(path);seen_textures[path]=true
	# 分组请求在Stream内合并固定保护；这里只传当前显示的附加pins。
	texture_pins=_stream.residency_images.duplicate()
	if keep_current and _committed_catalog==-2:
		mesh_pins.append_array(_committed)
		texture_pins.append_array(PackedStringArray(_committed_cut.get("ground_images",[])))
		charged_meshes.append_array(_committed)
		charged_images.append_array(PackedStringArray(_committed_cut.get("ground_images",[])))
	elif keep_current and _committed_catalog>=0:
		for key: String in _committed:
			var row: Dictionary = _catalogs[_committed_catalog].rows[key]
			mesh_pins.append(row.native_geometry.path)
			texture_pins.append(row.native_texture.path)
			charged_meshes.append(row.native_geometry.path)
			charged_images.append(row.native_texture.path)
	_prefetch_pages=0
	var ground := int(_target.get("charges",{}).get("ground_bytes",0))+int(_committed_cut.get("charges",{}).get("ground_bytes",0))
	var requests := Handoff.prefetch_requests(_catalogs,_target,_target_catalog)
	var ledger: Dictionary=_stream.residency_request_ledger(ground)
	var valid_ledger := not ledger.is_empty() and Handoff.append_streaming_bundle(ledger,_geometry,_textures,charged_meshes,charged_images,_stream.residency_limit)
	for request: Dictionary in requests:
		var mesh_path: String=request.mesh
		var image_path: String=request.image
		if seen_meshes.has(mesh_path) and (image_path.is_empty() or seen_textures.has(image_path)): continue
		var bundle_images := PackedStringArray() if image_path.is_empty() else PackedStringArray([image_path])
		if not valid_ledger or not Handoff.append_streaming_bundle(ledger,_geometry,_textures,PackedStringArray([mesh_path]),bundle_images,_stream.residency_limit): continue
		if not seen_meshes.has(mesh_path): prefetch_meshes.append(mesh_path);seen_meshes[mesh_path]=true
		if not image_path.is_empty() and not seen_textures.has(image_path): textures.append(image_path);seen_textures[image_path]=true
		_prefetch_pages+=1
	if PerfBuckets.frame_trace_enabled: PerfBuckets.tick("tokyo_map_request_plan",Time.get_ticks_usec()-request_started)
	var dispatch_started := Time.get_ticks_usec()
	_stream.request_partitioned(priority_meshes,_stream.residency_meshes,prefetch_meshes,mesh_pins)
	var textures_started := Time.get_ticks_usec()
	_stream.request_textures(textures,texture_pins)
	if PerfBuckets.frame_trace_enabled: PerfBuckets.tick("tokyo_map_dispatch_textures",Time.get_ticks_usec()-textures_started)
	if PerfBuckets.frame_trace_enabled: PerfBuckets.tick("tokyo_map_request_dispatch",Time.get_ticks_usec()-dispatch_started)


func _bind_target() -> void:
	var binding_start := Time.get_ticks_usec()
	var formal := ShaderMaterial.new()
	formal.shader=_native_surface if _target_catalog==-2 else _formal_surface
	_page_materials.append(formal)
	# 楼层线只给独立高楼；住宅街坊和地表保持连续大面。
	var high := ShaderMaterial.new()
	high.shader=formal.shader
	high.set_shader_parameter("facade_detail",true)
	_page_materials.append(high)
	for key in _target.keys:
		if _target_catalog==-2:
			var page: Resource = _stream.resource(key)
			for entry: Dictionary in _target.entries:
				if entry.path!=key: continue
				_bind_native_entry(page,entry,formal,high)
			continue
		var row: Dictionary = _catalogs[_target_catalog].rows[key]
		var component: Resource = _stream.resource(row.native_geometry.path)
		var shading := ShaderMaterial.new()
		shading.shader=_surface
		shading.set_shader_parameter("overview",_stream.texture(row.native_texture.path))
		shading.set_shader_parameter("wall_solid_color",OS.get_environment("AGL_TOKYO_HLOD_WALL_SOLID_COLOR")=="1")
		_page_materials.append(shading)
		var bounds := Rect2(row.bounds[0],row.bounds[1],row.bounds[2]-row.bounds[0],row.bounds[3]-row.bounds[1])
		var values: Array = row.texture.bounds
		var texture_bounds := Rect2(values[0],values[1],values[2]-values[0],values[3]-values[1])
		var uv := Rect2((bounds.position-texture_bounds.position)/texture_bounds.size,bounds.size/texture_bounds.size)
		_nodes.append(_add_mesh(Ground.plane(bounds,uv),shading,false))
		var building_shading := shading
		if OS.get_environment("AGL_TOKYO_HLOD_WALL_SOLID_COLOR")=="1" or OS.get_environment("AGL_TOKYO_HLOD_WALL_REVIEW")=="1":
			building_shading=shading.duplicate() as ShaderMaterial
			building_shading.set_shader_parameter("ordinary_building",true)
			_page_materials.append(building_shading)
		_nodes.append(_add_mesh(component.meshes[0],building_shading,false))
		_nodes.append(_add_mesh(component.meshes[1],high,false))
	_committed=_target.keys.duplicate()
	_committed_catalog=_target_catalog
	_committed_cut=_target
	max_transition_triangles=maxi(max_transition_triangles,int(_committed_cut.triangles))
	if _target_catalog==-2:
		var coverage_started := Time.get_ticks_usec() if PerfBuckets.frame_trace_enabled else 0
		_native_hidden=_native.covered(_target)
		if PerfBuckets.frame_trace_enabled: PerfBuckets.tick("tokyo_map_bind.source_coverage",Time.get_ticks_usec()-coverage_started)
	_fallback=""
	lod_switches+=1
	binding_usec+=Time.get_ticks_usec()-binding_start
	if PerfBuckets.frame_trace_enabled: PerfBuckets.tick("tokyo_map_bind",Time.get_ticks_usec()-binding_start)


func _bind_native_entry(page: Resource, entry: Dictionary, formal: ShaderMaterial, high: ShaderMaterial) -> void:
	for kind in 3:
		if not entry.mask[kind]: continue
		if kind==2 and (entry.has("ground_replacement") or entry.has("ground_surfaces")):
			for replacement: Dictionary in preload("res://scripts/rendering/tokyo_native_ground.gd").surfaces(entry):
				_bind_ground_surface(replacement)
		elif page is GridPage.SegmentedView:
			var indices: Variant=entry.piece_indices[kind] if entry.has("piece_indices") else range(page.layer_meshes[kind].size())
			for n: int in indices:
				_nodes.append(_add_mesh(page.layer_meshes[kind][n],high if kind==1 else formal,false))
		else: _nodes.append(_add_mesh(page.meshes[kind],high if kind==1 else formal,false))


func _bind_ground_surface(replacement: Dictionary) -> void:
	var shading := ShaderMaterial.new()
	shading.shader=_surface
	shading.set_shader_parameter("overview",_stream.texture(replacement.texture))
	if replacement.has("height_texture"):
		shading.shader=_height_surface
		shading.set_shader_parameter("overview",_stream.texture(replacement.texture))
		shading.set_shader_parameter("height_source",_stream.texture(replacement.height_texture))
		shading.set_shader_parameter("height_levels",replacement.height_levels)
		shading.set_shader_parameter("height_size",replacement.height_size)
		shading.set_shader_parameter("plane_y",replacement.plane_y)
	_page_materials.append(shading)
	var footprint: Rect2=replacement.footprint
	var texture_bounds: Rect2=replacement.bounds
	var uv := Rect2((footprint.position-texture_bounds.position)/texture_bounds.size,footprint.size/texture_bounds.size)
	var ground_node := _add_mesh(Ground.plane(footprint,uv),shading,false)
	ground_node.position.y=replacement.plane_y
	_nodes.append(ground_node)


func _clear_current() -> void:
	var clear_started := Time.get_ticks_usec() if PerfBuckets.frame_trace_enabled else 0
	_display_grace=false;_grace_started=-1;_grace_age_ms=0
	for node in _nodes:
		if is_instance_valid(node): node.free()
	_nodes.clear();_page_materials.clear();_committed.clear()
	_committed_catalog=-1
	_committed_cut={}
	_native_hidden.clear()
	if _ground_charged and is_instance_valid(_stream):
		_stream.release_auxiliary(_ground_token.get_instance_id())
	_ground_charged=false
	if is_instance_valid(_screen): _screen.hide()
	_sync_legacy()
	if PerfBuckets.frame_trace_enabled: PerfBuckets.tick("tokyo_map_clear",Time.get_ticks_usec()-clear_started)


func bind_legacy(renderer: BuildingRenderer) -> bool:
	if var_to_bytes(renderer._districts).hex_encode().sha256_text()!=Coverage.Full.COLLISION_SHA: return false
	_legacy=weakref(renderer)
	_sync_legacy()
	return true


func _sync_legacy() -> void:
	var renderer: Variant = _legacy.get_ref() if _legacy!=null else null
	if typeof(renderer)!=TYPE_OBJECT or not is_instance_valid(renderer): return
	var sources := PackedInt32Array()
	if _active and is_instance_valid(_screen) and _screen.visible and _committed_catalog==-2:
		sources=_native_hidden
	if _active and is_instance_valid(_screen) and _screen.visible and _committed_catalog>=0:
		for key in _committed:
			for id_value in _catalogs[_committed_catalog].rows[key].formal_source_ids: sources.append(int(id_value))
	sources.sort()
	if sources!=_hidden_sources and renderer.set_volume_coverage(self,sources): _hidden_sources=sources


func _deactivate() -> void:
	super._deactivate()
	_sync_legacy()


func _exit_tree() -> void:
	if _future_predictor!=null: _future_predictor.close()
	_clear_current()
	if is_instance_valid(_stream): _stream.close()


func debug_state() -> Dictionary:
	var ready := _committed.size()
	return {"active":_active,"enabled":_enabled,"hlod":true,"fallback":_fallback,"cut_ready":_target_committed(),
		"staged_switches":staged_switches,"max_transition_triangles":max_transition_triangles,
		"handoff_reason":_handoff_reason,"native_page_limit":Contract.native_page_limit(),
		"prefetch_pages":_prefetch_pages,
		"loading_neighborhood_bytes":loading_neighborhood_bytes,"loading_neighborhood_pinned":loading_neighborhood,
		"resident_foundation":resident_foundation,"foundation_cut":_committed_cut.get("foundation",false),
		"foundation_prefetch_skips":foundation_prefetch_skips,
		"speculative_plan_reuses":speculative_plan_reuses,
		"async_prefetch":{} if _future_predictor==null else {"submitted":_future_predictor.submitted,"applied":_future_predictor.applied,"fallback":_future_predictor.fallback,"prepare_usec":_future_predictor.prepare_usec,"discarded":_future_predictor.worker.discarded,"rejections":_future_predictor.rejections,"center_samples":_future_predictor.center_samples},
		"cached_cut_attempts":_cached_cut_attempts,"cached_cut_commits":_cached_cut_commits,
		"native_screen_bridge_commits":_native_screen_bridge_commits,
		"native_screen_bridge_state":_native_screen_bridge_state.duplicate(),
		"committed_catalog":_committed_catalog,"display_budget":display_budget,"display_bytes":int(_committed_cut.get("bytes",0)),
		"lod_grace_active":_display_grace,"lod_grace_frames":lod_grace_frames,"max_lod_grace_ms":max_lod_grace_ms,"max_lod_grace_ratio":max_lod_grace_ratio,
		"retained_cuts":retained_cuts,
		"zoom_rate":_zoom_rate,"zoom_prediction_reversals":zoom_prediction_reversals,
		"hlod_solver_builds":_selection_work.get("builds",0),"hlod_solver_reuses":_selection_work.get("reuses",0),
		"qualification_builds":_selection_work.get("qualification_builds",0),"qualification_reuses":_selection_work.get("qualification_reuses",0),
		"native_solver_builds":_native.solver_builds if _native!=null else 0,
		"native_partition_pages":_native._partition_pages.size() if _native!=null else 0,
		"native_ground_images":_committed_cut.get("ground_images",PackedStringArray()).size(),
		"ground_candidate":_ground_candidate_state,
		"native_solver_reuses":_native.solver_reuses if _native!=null else 0,
		"native_solver_peak":_native.solver_peak if _native!=null else {},
		"output_scale":output_scale,"selection_usec":selection_usec,"binding_usec":binding_usec,"native_cut":_committed_catalog==-2,
		"spatial_guard_px":_committed_cut.get("spatial_guard_px",0),"target_spatial_guard_px":_target.get("spatial_guard_px",0),
		"guard_rejection":_committed_cut.get("guard_rejection",{}),"target_guard_rejection":_target.get("guard_rejection",{}),
		"selection_current":_last_selected_canvas==_last_canvas and _last_selected_size==_last_size,
		"canvas":str(_last_canvas),"selected_catalog":_target_catalog,"screen_visible":is_instance_valid(_screen) and _screen.visible,
		"desired_cells":_target.get("keys",PackedStringArray()).size(),"ready_cells":ready,"active_cells":ready,
		"stream":_stream.summary() if is_instance_valid(_stream) else {},"hidden_legacy_sources":_hidden_sources,
		"output_size":_viewport.size if is_instance_valid(_viewport) else Vector2i.ZERO,
		"triangles":int(_committed_cut.get("triangles",0)) if ready>0 else 0,"redraws":redraws,"lod_switches":lod_switches}
