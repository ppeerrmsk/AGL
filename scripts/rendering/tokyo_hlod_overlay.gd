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
var _metadata_retirement: Node
var _target: Dictionary = {}
var _target_catalog := -1
var _committed_catalog := -1
var _committed := PackedStringArray()
var _committed_cut: Dictionary = {}
var _nodes: Array[MeshInstance3D] = []
var _hlod_binding_nodes: Dictionary={}
var reused_hlod_pages := 0
var created_hlod_pages := 0
var _page_materials: Array[ShaderMaterial] = []
var _lod_old_nodes: Array[MeshInstance3D]=[]
var _lod_old_materials: Array[ShaderMaterial]=[]
var _lod_old_cut: Dictionary={}
var _lod_old_catalog := -1
var _lod_old_token: RefCounted
var _lod_blend_age := 0.0
var _lod_blend_started_usec := 0
var _lod_blend_start_scale := 0.0
var _lod_blend_amount := 0.0
var lod_blends := 0
var lod_blend_budget_skips := 0
var lod_blend_peak_pages := 0
var lod_blend_peak_bytes := 0
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
var display_qualified := false
var display_covered := false
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
var resident_foundation := preload("res://scripts/rendering/tokyo_installed_map.gd").runtime_option("AGL_TOKYO_RESIDENT_FOUNDATION")=="1"
var _foundation: Dictionary = {}
var foundation_prefetch_skips := 0
var _speculative_cache: Dictionary = {}
var speculative_plan_reuses := 0
var _future_predictor: RefCounted
var _ground_candidate_state: Dictionary={}
var _loading_residency_base: Dictionary={}
var loading_neighborhood_on_setup := false
var _selection_trace: Array[Dictionary]=[]
var _trace_selection := OS.get_environment("AGL_TOKYO_SELECTION_TRACE")=="1"
var _trace_counterfactual := OS.get_environment("AGL_TOKYO_HANDOFF_COUNTERFACTUAL")=="1"
var _camera_demand: Dictionary={}
var _camera_motion_hint: Dictionary={}
var _prepared_motion_cuts: Array=[]
var _geometry_aliases: Dictionary={}
var _cached_motion_frame := -1
var cached_motion_selects := 0
var cached_motion_select_peak_usec := 0
var summary_motion_commits := 0
var summary_motion_refinements := 0
var summary_motion_adoptions := 0
var _summary_refinement_ready_at := 0
var _guard_prefetch := preload("res://scripts/rendering/tokyo_installed_map.gd").motion_admission_enabled("AGL_TOKYO_GUARD_PREFETCH")
var _return_cache := preload("res://scripts/rendering/tokyo_installed_map.gd").motion_admission_enabled("AGL_TOKYO_RETURN_CACHE")
var camera_wait_frames := 0
var camera_wait_max_ms := 0
var _camera_wait_started := -1
var pending_selection_reuses := 0
var motion_actual_cuts := 0
var native_screen_rejections := 0
const MapPlanner := preload("res://scripts/rendering/tokyo_map_planner.gd")
const MapWorker := preload("res://scripts/rendering/tokyo_map_plan_worker.gd")
const PreparedCatalog := preload("res://scripts/rendering/tokyo_prepared_catalog.gd")
var _map_worker: RefCounted
var _plan_generation := 1
var _plan_sequence := 0
var _plan_revision := 0
var _plan_dirty := true
var _plan_stats: Dictionary={}
var _plan_applied := 0
var _plan_rejected := 0
var _plan_pending_frames := 0
var _plan_prepare_usec := 0
var _plan_prepare_stages: Dictionary={}
var _prepared_source_ready := false
var _prepared_stream_source: Dictionary={}
var _setup_stages: Dictionary={}
var _plan_submit_usec := 0
var _plan_admission_usec := 0
var _plan_mode := "unconfigured"
var _plan_readiness := false
## 主线程地图重活错峰：交接（清旧+绑定）、规划准入与规划提交同一帧只做一件，
## 并优先落到无物理步的帧。每类最多连续让出 MAP_HEAVY_MAX_DEFER 帧；当前画面不合格或
## 不覆盖视野时交接不让（不产生缺图/未覆盖帧）。正式地图由 MapFeatureRenderer 开启，
## 单测直接驱动 overlay 时保持即时语义。
const MAP_HEAVY_MAX_DEFER := 2
var map_frame_balance := false
var heavy_deferrals := 0
var heavy_deferrals_by_kind: Dictionary={}
var _heavy_frame := -1
var _heavy_runs: Dictionary={}

class Layout extends Resource:
	var bounds := Rect2(-16300,-15700,32000,32000)
	var catalogs: Array[Dictionary] = []
	func valid() -> bool:
		return not catalogs.is_empty()


func _load_archive() -> Resource:
	if _prepared_source_ready: return _archive
	var started := Time.get_ticks_usec()
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
	_plan_prepare_stages["hlod_read"]=Time.get_ticks_usec()-started
	if preload("res://scripts/rendering/tokyo_installed_map.gd").motion_admission_enabled("AGL_TOKYO_DISPLAY_COMPACTION"):
		preload("res://scripts/rendering/tokyo_hlod_transition.gd").append_catalogs(_catalogs)
	if package.has("native"):
		_native=preload("res://scripts/rendering/tokyo_grid_native.gd").new() if package.native.has("grid_candidate") else Native.new()
		if not _native.read(package.native): return null
		if _native is Native: _plan_prepare_stages["native_read"]=_native.read_stages_usec.duplicate()
		for texture_path: String in _native.ground.get("textures",{}):
			if _textures.has(texture_path): return null
			_textures[texture_path]=_native.ground.textures[texture_path]
		if _catalogs.is_empty() or _native.catalog.full_grid.bounds!=_catalogs[0].bounds: return null
		for physical: String in _native.pages:
			if _geometry.has(physical): return null
			_geometry[physical]=_native.pages[physical]
		preload_max_scale=5.0
		if OS.get_environment("AGL_TOKYO_ASYNC_PREFETCH")=="1" and OS.get_environment("AGL_TOKYO_SYNC_SELECTION")=="1" and not package.native.has("grid_candidate"):
			_future_predictor=preload("res://scripts/rendering/tokyo_native_predictor.gd").new()
			if not _future_predictor.prepare(_native):
				_future_predictor.close()
				return null
	var layout := Layout.new()
	if _catalogs.is_empty(): return null
	layout.bounds=_catalogs[0].bounds
	layout.catalogs=_catalogs
	return layout


func prepare_background_source() -> bool:
	# 仅在尚未入树的独占实例上运行；不创建视口、纹理、节点或显示资源。
	# 完成后由Loading主线程接管同一实例，不在战场重新读取或初始化。
	if is_inside_tree() or _prepared_source_ready: return false
	var archive_started := Time.get_ticks_usec()
	_archive=_load_archive()
	_plan_prepare_stages["archive"]=Time.get_ticks_usec()-archive_started
	if _archive==null or not _archive.valid(): return false
	if resident_foundation:
		_foundation=preload("res://scripts/rendering/tokyo_hlod_foundation.gd").plan(_catalogs,display_budget,OS.get_environment("AGL_TOKYO_COMPLETE_FOUNDATION")=="1")
		if _foundation.is_empty(): return false
	if not _prepare_map_planner(): return false
	var started := Time.get_ticks_usec()
	_prepared_stream_source=Stream.prepare_hlod_source(_geometry,_textures)
	_plan_prepare_stages["stream_source"]=Time.get_ticks_usec()-started
	if _prepared_stream_source.is_empty(): return false
	_prepared_source_ready=true
	return true


func _setup_geometry() -> void:
	_metadata_retirement=preload("res://scripts/rendering/tokyo_metadata_retirement.gd").attach(self)
	var phase_started := Time.get_ticks_usec()
	var motion_candidate := preload("res://scripts/rendering/tokyo_installed_map.gd").motion_admission_enabled("AGL_TOKYO_DISPLAY_COMPACTION")
	_exact_canvas_tracking=motion_candidate
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
	_setup_stages["shaders"]=Time.get_ticks_usec()-phase_started
	phase_started=Time.get_ticks_usec()
	_stream=Stream.new()
	# 当前交接页优先于预测页；只改变原共享槽/上传顺序，不增加并发、额度或缓存。
	if motion_candidate:
		_stream.visible_io_first=true
		_stream.visible_finalize_first=true
		# 连续大纹理上传不能把当前网格饿死；重帧最多领取/发起一件，仍守共享额度。
		_stream.minimum_mesh_progress=true
	# 正式地图流：完成件领取/纹理上传优先落到无物理步帧（有界延后，见 TokyoCellStream）。
	_stream.light_frame_balance=true
	if _native is GridNative:
		_native.subset_stream=weakref(_stream)
		_native.subset_geometry=_geometry
	# 退出后仍须领取在途资源，不能作为随overlay立即删除的子节点。
	get_tree().root.add_child(_stream)
	var stream_ready: bool=_stream.configure_hlod(self,_geometry,_textures) if _prepared_stream_source.is_empty() \
		else _stream.configure_prepared_hlod(self,_prepared_stream_source)
	_prepared_stream_source={}
	if not stream_ready:
		_fallback="invalid stream"
		_enabled=false
	elif resident_foundation:
		if _foundation.is_empty(): _foundation=preload("res://scripts/rendering/tokyo_hlod_foundation.gd").plan(_catalogs,display_budget,OS.get_environment("AGL_TOKYO_COMPLETE_FOUNDATION")=="1")
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
	_setup_stages["stream"]=Time.get_ticks_usec()-phase_started
	phase_started=Time.get_ticks_usec()
	# base.setup紧接着会同步_process(0)并发出首批I/O；邻区必须在那之前完成组合。
	if loading_neighborhood_on_setup and _enabled and cache_pool_limit>Stream.BUDGET:
		var source: Variant=_source_ref.get_ref()
		var camera: Variant=_camera_ref.get_ref()
		if typeof(source)==TYPE_OBJECT and is_instance_valid(source) and typeof(camera)==TYPE_OBJECT and is_instance_valid(camera):
			prepare_loading_neighborhood(camera.position,clampf(camera.zoom.x,0.0973,preload_max_scale),source.get_viewport().get_visible_rect().size)
	_setup_stages["neighborhood"]=Time.get_ticks_usec()-phase_started
	if _enabled and not _prepare_map_planner():
		_enabled=false
		_fallback="invalid prepared planning source"


func prepare_loading_neighborhood(center: Vector2, scale_value: float, output: Vector2) -> void:
	if cache_pool_limit<=2*Stream.BUDGET or loading_neighborhood: return
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


func _selection_phase(label: String, started: int) -> int:
	var now := Time.get_ticks_usec()
	PerfBuckets.tick("tokyo_select."+label,now-started)
	return now


func _step_geometry(view_bounds: Rect2, scale_value: float, _delta: float) -> bool:
	if not is_instance_valid(_stream): return false
	if _native!=null and _native.has_method("retire_subsets"):
		var protected := _committed.duplicate()
		protected.append_array(PackedStringArray(_target.get("keys",[])))
		protected.append_array(_stream.residency_meshes)
		protected.append_array(PackedStringArray(_lod_old_cut.get("keys",[])))
		_native.retire_subsets(protected)
	var handoff_budget: int=_stream.residency_limit-_stream.residency_bytes
	# 相机方向必须逐帧观察；后台请求可能仍在较早的倍率，不能用请求姿态判断反转。
	var observed_direction := Handoff.zoom_direction(output_scale,scale_value)
	var previous_zoom_rate := _zoom_rate
	if output_scale>0.0 and _delta>0.0:
		var ratio := scale_value/output_scale
		var next_rate := Handoff.prediction_zoom_rate(_zoom_rate,ratio,_delta)
		_zoom_rate=next_rate
	output_scale=scale_value
	var motion_source: Node = _source_ref.get_ref()
	var motion_center := _last_canvas.affine_inverse()*(motion_source.get_viewport().get_visible_rect().size*0.5)
	if _motion_center.is_finite() and _delta>0.0:
		var displacement := motion_center-_motion_center
		if displacement.length()*scale_value>=160.0:
			# 冷进入的位移与尺度差都不是连续运动；旧历史会膨胀首个切面并占满交接空间。
			_pan_velocity=Vector2.ZERO;_zoom_rate=0.0
			observed_direction=0;_last_zoom_direction=0
		else:
			# 候选预取按时间平滑：物理60Hz/呈现120Hz的零位移交替不能放大为预测摆动。
			_pan_velocity=preload("res://scripts/rendering/tokyo_native_predictor.gd").smooth_pan(_pan_velocity,displacement/_delta,_delta)
	zoom_prediction_reversals+=int(previous_zoom_rate*_zoom_rate<0.0)
	# 控制器已证明的连续输入不能因单帧超过160px被当作冷瞬切。
	# 只消费与实际显示姿态一致的新样本；外部cine_cut仍清空旧预测。
	if not _camera_motion_hint.is_empty() and _last_canvas.is_equal_approx(_camera_motion_hint.canvas) \
		and _last_size.is_equal_approx(_camera_motion_hint.size):
		_pan_velocity=_camera_motion_hint.velocity;_zoom_rate=_camera_motion_hint.rate
		observed_direction=1 if _zoom_rate>0.02 else (-1 if _zoom_rate< -0.02 else 0)
	_camera_motion_hint={}
	# 被地图连续性门暂缓的输入仍是当前需求；用它继续准备目标，而不是让相机超前后再清屏。
	if not _camera_demand.is_empty():
		_zoom_rate=float(_camera_demand.rate)
		_pan_velocity=_camera_demand.velocity
		observed_direction=1 if _zoom_rate>0.02 else (-1 if _zoom_rate< -0.02 else 0)
		_plan_dirty=true
	_motion_center=motion_center
	var previous_scale := _last_selected_canvas.x.length()
	var direction := observed_direction
	var zooming_out := direction<0
	var reversing_in := direction>0 and _last_zoom_direction<0
	if direction!=0: _last_zoom_direction=direction
	_zooming_in=direction>0
	# 反转撤销旧降档事务；下一呈现帧可能没有新物理位移，不能让旧目标借停镜提交。
	# 恢复当前保护并使在途结果过期，静止时仍会重采最新需求，不永久锁住方向。
	if reversing_in and not _target_committed() and _target_catalog>=0 and _committed_catalog>=0 \
		and _committed_qualified(scale_value) and _cut_covers_current_view(_committed_cut,_committed_catalog) \
		and Handoff.scale_limit(_catalogs[_target_catalog],_target)<Handoff.scale_limit(_catalogs[_committed_catalog],_committed_cut):
		_target=_committed_cut.duplicate(true);_target_catalog=_committed_catalog
		_plan_revision+=1;_plan_dirty=true;_last_selected_size=Vector2.ZERO
		_request_target(false)
	# 已就绪的合格中间档先交接；方向反转后不提交更快过期的降档事务。
	var changed := _step_lod_blend(scale_value,_delta)
	var staged_successor := _stage_lod_successor(scale_value)
	changed=staged_successor or changed
	# 进入相邻档合法区就接纳已准备的切面，不能等旧档过期后才发现它已被新预测覆盖。
	if not staged_successor and _lod_old_cut.is_empty() and _camera_demand.is_empty() \
		and preload("res://scripts/rendering/tokyo_installed_map.gd").motion_admission_enabled("AGL_TOKYO_LOD_BLEND"):
		for prepared: Dictionary in _prepared_motion_cuts:
			# 原生交接由成对后继负责；旧预测不能在缩远时再次把近景模型换回来。
			if int(prepared.catalog)<0 or int(prepared.catalog)==_committed_catalog: continue
			if _committed_catalog==-2 and _zoom_rate>= -0.02: continue
			if _stage_prepared_motion(scale_value,[prepared]):
				_target["lod_blend_target"]=true
				changed=true
				break
	changed=_commit_ready_target(scale_value) or changed
	_update_display_grace(view_bounds.intersection(_archive.bounds),scale_value)
	var rapid_zoom := previous_scale>0.0 and absf(_last_canvas.x.length()/previous_scale-1.0)>0.025
	var current_covered := _committed_catalog!=-1 and _cut_covers_current_view(_committed_cut,_committed_catalog)
	var display_revision := _plan_revision
	if _map_worker!=null:
		var plan_started := Time.get_ticks_usec() if PerfBuckets.frame_trace_enabled else 0
		changed=_step_prepared_selection(scale_value,zooming_out,reversing_in,rapid_zoom,current_covered,changed) or changed
		if PerfBuckets.frame_trace_enabled: PerfBuckets.tick("tokyo_map_plan_main",Time.get_ticks_usec()-plan_started)
	else:
		if _selection_due(current_covered,scale_value,reversing_in,rapid_zoom) and (_last_selected_canvas!=_last_canvas or _last_selected_size!=_last_size):
			_lod_clock=0.05
			_last_selected_canvas=_last_canvas
			_last_selected_size=_last_size
			var selected := Handoff.catalog_index(_catalogs,scale_value,not zooming_out)
			var foundation_catalog := preload("res://scripts/rendering/tokyo_hlod_foundation.gd").catalog_at(_foundation,scale_value,selected)
			# 新中景本身是完整合格显示表示；相邻细档另由预测I/O准备，不提前替换画面。
			if foundation_catalog<0:
				var actual_foundation := preload("res://scripts/rendering/tokyo_hlod_foundation.gd").catalog_at(_foundation,scale_value)
				if actual_foundation>=0 and (_catalogs[actual_foundation].has("middle_massing_recipe") or _catalogs[actual_foundation].has("far_summary_recipe")): foundation_catalog=actual_foundation
			if foundation_catalog>=0: selected=foundation_catalog
			var next: Dictionary = {}
			if selected<0 and _native!=null and scale_value>0.1944: selected=-2
			if selected>=0 or selected==-2:
				var selection_start := Time.get_ticks_usec()
				var phase_started := selection_start
				var source: Variant = _source_ref.get_ref()
				var logical: Vector2 = source.get_viewport().get_visible_rect().size
				var center := _last_canvas.affine_inverse()*(logical*0.5)
				# 双向缩放均先完成仍完整合格的在途桥接档，缩远还须保留96px余量。
				# 在求树前判断：原先先重算半池/全池再无条件覆盖结果，等待I/O时每帧白算。
				if _pending_hlod_covers(scale_value,zooming_out):
					selected=_target_catalog
					next=_target
					pending_selection_reuses+=1
				else:
					# 常驻页不必为重新加载同一资源预留半池；仍守原96MiB显示门。
					if foundation_catalog>=0:
						next=preload("res://scripts/rendering/tokyo_hlod_foundation.gd").select(_catalogs[selected],_foundation.layers[selected].entries,center,scale_value,_last_canvas.get_rotation(),_last_size,display_budget)
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
				if PerfBuckets.frame_trace_enabled: phase_started=_selection_phase("base",phase_started)
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
				if PerfBuckets.frame_trace_enabled: phase_started=_selection_phase("native",phase_started)
				if selected>=0 and selected==_target_catalog and not next.is_empty() and (not _target_committed() or int(_target.get("bytes",display_budget))<=maxi(Stream.BUDGET/2,int(next.bytes))) and Contract.retained(_catalogs[selected],_target,next,scale_value,true):
					next=_target
					retained_cuts+=1
				# 提前细档的联合费用过高时，先尝试当前清晰度的完整桥接。
				# 半池只是首选；同池重叠允许超过半池的切面，保护带也必须逐档验联合费用。
				if selected>=0 and not _committed.is_empty() and _committed_qualified(scale_value) \
					and (next.is_empty() or not next.within_budget or _handoff_bytes(next,selected)>handoff_budget):
					var actual_catalog := Handoff.catalog_index(_catalogs,scale_value,false)
					var bridge_catalogs: Array[int]=[]
					if zooming_out and actual_catalog>=0 and actual_catalog!=_committed_catalog: bridge_catalogs.append(actual_catalog)
					if _committed_catalog>=0: bridge_catalogs.append(_committed_catalog)
					if actual_catalog>=0 and actual_catalog not in bridge_catalogs: bridge_catalogs.append(actual_catalog)
					for bridge_catalog: int in bridge_catalogs:
						var handoff_cut := _select_handoff_hlod(bridge_catalog,center,scale_value,_last_canvas.get_rotation(),_last_size,handoff_budget,display_budget)
						if not handoff_cut.is_empty():
							next=handoff_cut;selected=bridge_catalog
							break
				if PerfBuckets.frame_trace_enabled: phase_started=_selection_phase("bridge",phase_started)
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
						_lod_clock=0.0
						_last_selected_size=Vector2.ZERO
				if PerfBuckets.frame_trace_enabled: phase_started=_selection_phase("trim",phase_started)
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
				if PerfBuckets.frame_trace_enabled: phase_started=_selection_phase("compact",phase_started)
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
				if PerfBuckets.frame_trace_enabled: phase_started=_selection_phase("actual",phase_started)
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
				if PerfBuckets.frame_trace_enabled: phase_started=_selection_phase("predict",phase_started)
				selection_usec+=Time.get_ticks_usec()-selection_start
			if _trace_selection and _selection_trace.size()<2048:
				var bridge_probe: Array[Dictionary]=[]
				var actual_index := Handoff.catalog_index(_catalogs,scale_value,false)
				if _trace_counterfactual and selected>=0 and actual_index>=0 and selected!=actual_index and not next.is_empty() and not _committed.is_empty() and _handoff_bytes(next,selected)>handoff_budget:
					var probe_size: Vector2=motion_source.get_viewport().get_visible_rect().size
					var probe_center := _last_canvas.affine_inverse()*(probe_size*0.5)
					for probe_budget: int in [Stream.BUDGET/2,display_budget]:
						var probe := _select_hlod(_catalogs[actual_index],probe_center,scale_value,_last_canvas.get_rotation(),_last_size,false,probe_budget)
						bridge_probe.append({"catalog":actual_index,"budget":probe_budget,"bytes":probe.get("bytes",0),"valid":probe.get("within_budget",false),
							"keys":probe.get("keys",[]).duplicate(),"guard":probe.get("spatial_guard_px",0),"union":_handoff_bytes(probe,actual_index) if not probe.is_empty() else -1,
							"ready":_resources_ready(probe,actual_index),"covered":_cut_covers_current_view(probe,actual_index) if not probe.is_empty() else false})
					var probe_lead := Handoff.pan_lead(_pan_velocity,scale_value,0.35,_last_size)
					var probe_padding := (Transform2D(_last_canvas.get_rotation(),Vector2.ZERO).basis_xform(probe_lead)*scale_value).abs()+Vector2(384,384)
					for probe_ratio: float in [1.0,0.5,0.25,0.0]:
						var candidate := Contract.select(_catalogs[actual_index],probe_center+probe_lead*0.5*probe_ratio,scale_value,_last_canvas.get_rotation(),_last_size+probe_padding*probe_ratio,false,display_budget,_selection_work,_small_uploads)
						bridge_probe.append({"catalog":actual_index,"budget":display_budget,"direct_ratio":probe_ratio,"bytes":candidate.get("bytes",0),"triangles":candidate.get("triangles",0),
							"valid":candidate.get("within_budget",false),"qualified":Handoff.qualified(_catalogs[actual_index],candidate,scale_value),"keys":candidate.get("keys",[]).duplicate(),
							"union":_handoff_bytes(candidate,actual_index) if not candidate.is_empty() else -1,"ready":_resources_ready(candidate,actual_index),
							"covered":_cut_covers_current_view(candidate,actual_index) if not candidate.is_empty() else false})
				_selection_trace.append({"frame":Engine.get_process_frames(),"ticks_msec":Time.get_ticks_msec(),"zoom_rate":_zoom_rate,"scale":scale_value,"center":motion_center,"canvas":_last_canvas,
					"current_qualified":_committed_qualified(scale_value),"current_limit":Handoff.scale_limit(_catalogs[_committed_catalog],_committed_cut) if _committed_catalog>=0 else 0.0,
					"current_catalog":_committed_catalog,"current":_committed.duplicate(),"current_bytes":_committed_cut.get("bytes",0),"covered":current_covered,
					"target_catalog":_target_catalog,"target":_target.get("keys",[]).duplicate(),"next_catalog":selected,"next":next.get("keys",[]).duplicate(),
					"next_bytes":next.get("bytes",0),"next_guard":next.get("spatial_guard_px",0),"next_budget":next.get("within_budget",false),
					"next_bridge":next.get("handoff_bridge",false),"next_incremental_bytes":next.get("handoff_incremental_bytes",-1),
					"next_stage":next.get("selection_stage",""),"next_trim_lead":next.get("trim_lead_world",Vector2.ZERO),"next_motion_need":next.get("motion_guard_need_px",0.0),
					"union":_handoff_bytes(next,selected) if not next.is_empty() and not _committed.is_empty() else -1,"ready":_resources_ready(next,selected),
					"next_covered":_cut_covers_current_view(next,selected) if selected!=-1 and not next.is_empty() else false,
					"native_builds":_native.solver_builds if _native!=null else 0,"pending_reuses":pending_selection_reuses,
					"reason":_handoff_reason,"fallback":_fallback,"stream":_stream.summary(),"actual_bridge_probe":bridge_probe})
			# 候选无解与当前显示失效是两件事；仍合格且覆盖完整时沿用已绑定切面。
			if (next.is_empty() or not next.within_budget) and Handoff.retain_display(_committed_cut,_committed_qualified(scale_value),current_covered,display_budget,Contract.native_page_limit() if _committed_catalog==-2 else 16):
				next=_committed_cut;selected=_committed_catalog
			if not next.is_empty() and next.within_budget: _refresh_native_guard_metadata(next,selected)
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
					if _committed_catalog>=0 and not current_covered:
						_handoff_reason="old_view"
						_clear_current()
					else:
						_handoff_reason="wait_union_budget"
						_fallback="waiting prefetch budget"
						return _finish_display_step(scale_value,changed,current_covered,display_revision)
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
	return _finish_display_step(scale_value,changed,current_covered,display_revision)


func _finish_display_step(scale_value: float, changed: bool, covered: bool, checked_revision: int) -> bool:
	# 先让已经就绪且满足此刻视野的目标接替，不能为清理旧显示制造一次空白。
	changed=_commit_ready_target(scale_value) or changed
	var has_display := not _committed.is_empty()
	if not has_display: covered=false
	elif checked_revision!=_plan_revision:
		covered=_cut_covers_current_view(_committed_cut,_committed_catalog)
	var qualified := has_display and _committed_qualified(scale_value)
	# pending不是继续显示缺边/过期切面的凭据；target恰好等于committed时也须执行。
	# 常驻资源只是可用输入，不等于已经绑定且覆盖此刻视野的显示基底。
	if has_display and (not covered or (not qualified and not _display_grace)):
		_trace_prepared_state("display_lost")
		_handoff_reason="old_view" if not covered else "old_scale"
		_clear_current()
		changed=true
		_plan_dirty=true
		if _map_worker==null: _last_selected_size=Vector2.ZERO
		if not _target.is_empty(): _request_target(false)
		else: _stream.request_residency_only()
		_fallback="loading cut"
		qualified=false;covered=false
	_record_display_grace(scale_value)
	_screen.visible=_active and not _committed.is_empty()
	display_qualified=_screen.visible and qualified
	display_covered=_screen.visible and covered
	_sync_legacy()
	return changed


func _pending_hlod_covers(scale_value: float, zooming_out: bool) -> bool:
	# 缩远退出当前档后停止同档扩装，但保留真正跨档的在途桥接；与后台规划同规则。
	if zooming_out and _target_catalog>=0 and _target_catalog==_committed_catalog \
		and scale_value<float(_catalogs[_target_catalog].get("range",[0.0,INF])[0]): return false
	# 普通保护带事务也可能即将到期；沿用桥接的0.25秒资格，不能占住下一细档的加载窗口。
	return _target_catalog>=0 and not _target_committed() and not _target.has("anticipated_scale") \
		and Handoff.qualified(_catalogs[_target_catalog],_target,scale_value) \
		and _handoff_bridge_qualified(_target_catalog,_target,scale_value) \
		and _target_covers_current_view(96.0 if zooming_out else 0.0)


func _selection_due(current_covered: bool, scale_value: float, reversing_in: bool, rapid_zoom: bool) -> bool:
	# 覆盖完整不代表清晰度仍合格；跨地表上限时必须当帧换目标，不能先清屏再等20Hz选页。
	# 方向包络没有全向保护；转弯时沿快速缩放的节拍重采，仍由调用方合并停镜和在途需求。
	var narrow_native: bool=_committed_catalog==-2 and not _committed.is_empty() \
		and _committed_cut.get("selection_stage","") in ["native_motion_guard","native_actual","native_retained"] \
		and float(_committed_cut.get("spatial_guard_px",-1))==0.0
	return _lod_clock<=0.0 or reversing_in or not current_covered or not _committed_qualified(scale_value) \
		or ((rapid_zoom or narrow_native) and _lod_clock<=0.05-1.0/60.0)


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


func _select_hlod(catalog: Dictionary, center: Vector2, scale: float, angle: float, size: Vector2, finer: bool = false, budget: int = -1, include_zoom_footprint: bool = true) -> Dictionary:
	if budget==-1:
		# 扩大硬上限不能把原48/96MiB首选一起抬高；原切面可用时保持原资源身份。
		if display_budget>Stream.BUDGET:
			var original := _select_hlod(catalog,center,scale,angle,size,finer,Stream.BUDGET,include_zoom_footprint)
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
	if include_zoom_footprint: padding+=Handoff.zoom_out_padding(_zoom_rate,size)
	var expanded := Contract.select(catalog,center+lead*0.5,scale,angle,size+padding,finer,budget,_selection_work,_small_uploads)
	var expanded_retry := false
	if (expanded.is_empty() or not expanded.within_budget) and budget<display_budget:
		var full := Contract.select(catalog,center+lead*0.5,scale,angle,size+padding,finer,display_budget,_selection_work,_small_uploads)
		var lookup_started := Time.get_ticks_usec() if PerfBuckets.frame_trace_enabled else 0
		var index := _catalogs.find(catalog)
		if PerfBuckets.frame_trace_enabled: PerfBuckets.tick("tokyo_map_hlod_catalog_lookup",Time.get_ticks_usec()-lookup_started)
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
			var lookup_started := Time.get_ticks_usec() if PerfBuckets.frame_trace_enabled else 0
			var index := _catalogs.find(catalog)
			if PerfBuckets.frame_trace_enabled: PerfBuckets.tick("tokyo_map_hlod_catalog_lookup",Time.get_ticks_usec()-lookup_started)
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
	# 同步兼容路径与 MapPlanner 同一规则：运动中细档裸切面改取实际档保护切面。
	var guard := float(next.get("spatial_guard_px",0.0))
	var need := Handoff.motion_guard_need(_pan_velocity,scale,size)
	# 冷进入无速度历史也须避免裸视野占满显示池，规则与后台规划一致。
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
	if include_zoom_footprint: padding+=Handoff.zoom_out_padding(_zoom_rate,size)
	var current_bytes := _handoff_bytes({"keys":PackedStringArray()},index)
	if current_bytes<0 or current_bytes>=budget: return {}
	var costs_started := Time.get_ticks_usec() if PerfBuckets.frame_trace_enabled else 0
	var costs := _handoff_incremental_costs(index)
	if PerfBuckets.frame_trace_enabled: PerfBuckets.tick("tokyo_bridge.costs",Time.get_ticks_usec()-costs_started)
	var roots_started := Time.get_ticks_usec() if PerfBuckets.frame_trace_enabled else 0
	var roots := Contract.handoff_roots(_catalogs[index],maxf(scale,future_scale),costs,_selection_work)
	if PerfBuckets.frame_trace_enabled: PerfBuckets.tick("tokyo_bridge.roots",Time.get_ticks_usec()-roots_started)
	for ratio: float in [1.0,0.5,0.25,0.0]:
		if 192.0*ratio<min_guard_px: continue
		var choose_started := Time.get_ticks_usec() if PerfBuckets.frame_trace_enabled else 0
		var candidate := Contract.select_handoff(_catalogs[index],center+lead*0.5*ratio,scale,angle,size+padding*ratio,budget-current_bytes,costs,_selection_work,index==_committed_catalog,future_scale,roots)
		if PerfBuckets.frame_trace_enabled: PerfBuckets.tick("tokyo_bridge.choose",Time.get_ticks_usec()-choose_started)
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
	if is_instance_valid(_stream):
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
	var query_started := Time.get_ticks_usec() if PerfBuckets.frame_trace_enabled else 0
	var expanded: Dictionary = _native.select(center+lead*0.5,scale,angle,size+padding,configuration,budget)
	if PerfBuckets.frame_trace_enabled: PerfBuckets.tick("tokyo_native_query.expanded",Time.get_ticks_usec()-query_started)
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
		query_started=Time.get_ticks_usec() if PerfBuckets.frame_trace_enabled else 0
		var reduced: Dictionary=_native.select(center+lead*0.5*ratio,scale,angle,size+padding*ratio,configuration,budget)
		if PerfBuckets.frame_trace_enabled: PerfBuckets.tick("tokyo_native_query.half" if ratio==0.5 else "tokyo_native_query.quarter",Time.get_ticks_usec()-query_started)
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
		query_started=Time.get_ticks_usec() if PerfBuckets.frame_trace_enabled else 0
		var motion: Dictionary=_native.select(motion_query.center,scale,angle,motion_query.size,configuration,budget)
		if PerfBuckets.frame_trace_enabled: PerfBuckets.tick("tokyo_native_query.motion",Time.get_ticks_usec()-query_started)
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
		and Handoff.retain_display(_target,Handoff.native_qualified(_target,scale),_target_covers_current_view(),budget,Contract.native_page_limit()):
		var retained: Dictionary=_target.duplicate()
		retained["selection_stage"]="native_retained";retained["spatial_guard_px"]=0
		return retained
	query_started=Time.get_ticks_usec() if PerfBuckets.frame_trace_enabled else 0
	var actual: Dictionary = _native.select(center,scale,angle,size,configuration,budget)
	if PerfBuckets.frame_trace_enabled: PerfBuckets.tick("tokyo_native_query.bare",Time.get_ticks_usec()-query_started)
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
	var future_foundation := preload("res://scripts/rendering/tokyo_hlod_foundation.gd").catalog_at(_foundation,future_scale)
	if future_foundation>=0 and _catalogs[future_foundation].has("far_summary_recipe"): index=future_foundation
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
			# future_scale已计入缩放，保护带只保留原纯平移包络，不再外推一次倍率。
			cut=_select_native(future_center,future_scale,angle,size,configuration,Stream.BUDGET/2,false,false)
			if cut.is_empty() or not cut.within_budget: cut=_select_native(future_center,future_scale,angle,size,configuration,display_budget,false,false)
		if _future_predictor!=null: _future_predictor.dispatch()
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


func camera_motion_checkpoint(scale_value: float) -> float:
	# 快速缩远逐段经过中间档；提交入口会独立核验当前镜头的覆盖与资源。
	if not _enabled or not _active or _committed.is_empty(): return 0.0
	var source: Variant=_source_ref.get_ref() if _source_ref!=null else null
	if typeof(source)!=TYPE_OBJECT or not is_instance_valid(source): return 0.0
	if not source.is_visible_in_tree() or source.get("vector_preview_enabled")==true: return 0.0
	if _target_catalog<0 or _target.is_empty() or _target_committed(): return 0.0
	# 已就绪的路径检查点同时约束位置和缩放。再单独截断缩放会改变整条
	# 插值路径，使后台已证明可交接的中间姿态永远无法被控制器尝试。
	# 保留原联合路径，由camera_motion_ready逐步核资格、覆盖与实际资源。
	if _target.get("motion_checkpoint",false) and _resources_ready(_target,_target_catalog): return 0.0
	var boundary := Handoff.scale_limit(_catalogs[_target_catalog],_target)*(1.0-0.000001)
	return boundary if scale_value<boundary and output_scale>boundary else 0.0


func camera_motion_pending(canvas: Transform2D, output: Vector2, rate: float, velocity: Vector2) -> void:
	# 显示已经推进的小步仍保留完整输入事务，供规划器准备尚未显示的镜头位置。
	var source: Variant=_source_ref.get_ref() if _source_ref!=null else null
	if typeof(source)!=TYPE_OBJECT or not is_instance_valid(source): return
	var logical: Vector2=source.get_viewport().get_visible_rect().size
	if minf(logical.x,logical.y)<=0.0 or minf(output.x,output.y)<=0.0: return
	var scale_value := canvas.x.length()*output.x/logical.x
	if absf(rate)<0.02 and not is_equal_approx(scale_value,_last_canvas.x.length()*output.x/logical.x):
		rate=clampf(log(scale_value/maxf(_last_canvas.x.length()*output.x/logical.x,0.001))/0.25,-2.0,2.0)
	_camera_demand={"rate":rate,"velocity":velocity,"canvas":canvas,"size":output,"scale":scale_value}
	if is_instance_valid(_stream): _stream.input_waiting=true
	_plan_dirty=true


func camera_motion_ready(canvas: Transform2D, output: Vector2, rate: float, velocity: Vector2, measure_wait: bool = true) -> bool:
	# 在镜头移动前复核目标；不以过期切面放行，也不延长旧切面的清晰度宽限。
	# 活动地图没有已提交切面时也必须等目标就绪；否则镜头会在清屏期间继续推进。
	if not _enabled or not _active: return true
	var source: Variant=_source_ref.get_ref() if _source_ref!=null else null
	if typeof(source)!=TYPE_OBJECT or not is_instance_valid(source): return true
	if not source.is_visible_in_tree() or source.get("vector_preview_enabled")==true: return true
	if minf(output.x,output.y)<=0.0: return false
	var logical: Vector2=source.get_viewport().get_visible_rect().size
	if minf(logical.x,logical.y)<=0.0: return false
	if _guard_prefetch and measure_wait and is_finite(rate) and velocity.is_finite():
		_camera_motion_hint={"canvas":canvas,"size":output,"rate":rate,"velocity":velocity}
	var scale_value := canvas.x.length()*output.x/logical.x
	var previous_canvas := _last_canvas
	var previous_size := _last_size
	var previous_direction := _zooming_in
	var previous_rate := _zoom_rate
	_last_canvas=canvas;_last_size=output;_zooming_in=rate>0.02;_zoom_rate=rate
	var ready := _committed_qualified(scale_value) and _cut_covers_current_view(_committed_cut,_committed_catalog)
	if not ready:
		# 后台已完成但尚未进入主线程缓存的网格，须在本帧决定镜头能否推进前领取。
		# 共用流送器原单帧领取配额；不发请求、不上传纹理、不在小步重试时重复调用。
		if _guard_prefetch and measure_wait and is_instance_valid(_stream): _stream.collect_ready_meshes()
		_commit_ready_target(scale_value)
		ready=not _committed.is_empty() and _committed_qualified(scale_value) and _cut_covers_current_view(_committed_cut,_committed_catalog)
		if not ready and _stage_prepared_motion(scale_value):
			_commit_ready_target(scale_value)
			ready=not _committed.is_empty() and _committed_qualified(scale_value) and _cut_covers_current_view(_committed_cut,_committed_catalog)
		if not ready and measure_wait and _stage_cached_motion(scale_value):
			_commit_ready_target(scale_value)
			ready=not _committed.is_empty() and _committed_qualified(scale_value) and _cut_covers_current_view(_committed_cut,_committed_catalog)
	_last_canvas=previous_canvas;_last_size=previous_size;_zooming_in=previous_direction;_zoom_rate=previous_rate
	if ready:
		if _camera_wait_started>=0: camera_wait_max_ms=maxi(camera_wait_max_ms,Time.get_ticks_msec()-_camera_wait_started)
		_camera_demand={};_camera_wait_started=-1
		if is_instance_valid(_stream): _stream.input_waiting=false
	else:
		if not measure_wait: return false
		camera_motion_pending(canvas,output,rate,velocity)
		camera_wait_frames+=1
		if _camera_wait_started<0: _camera_wait_started=Time.get_ticks_msec()
		camera_wait_max_ms=maxi(camera_wait_max_ms,Time.get_ticks_msec()-_camera_wait_started)
	return ready


func _stage_cached_motion(scale_value: float) -> bool:
	# SPACE可一帧经过数屏。只在首次准入失败时查一次已有空间索引，
	# 资源不齐即拒绝，不在这里加载/构建资源；避免完整驻留仍等后台往返。
	if not _guard_prefetch or not is_instance_valid(_stream) \
		or _cached_motion_frame==Engine.get_process_frames(): return false
	var fixed := preload("res://scripts/rendering/tokyo_hlod_foundation.gd").catalog_at(_foundation,scale_value,-1,true)
	if fixed<0 and _native==null and _catalogs.is_empty(): return false
	_cached_motion_frame=Engine.get_process_frames()
	var source: Variant=_source_ref.get_ref() if _source_ref!=null else null
	if typeof(source)!=TYPE_OBJECT or not is_instance_valid(source): return false
	var logical: Vector2=source.get_viewport().get_visible_rect().size
	var center := _last_canvas.affine_inverse()*(logical*0.5)
	var started := Time.get_ticks_usec()
	var next: Dictionary
	var staged := false
	_selection_work["stable_hlod_leaves"]=true
	_selection_work["stable_hlod_tiles"]=_return_cache
	if fixed>=0:
		# 返回全图常驻层也不等后台选择；原全图费用和资格检查仍生效。
		next=preload("res://scripts/rendering/tokyo_hlod_foundation.gd").select(_catalogs[fixed],_foundation.layers[fixed].entries,
			center,scale_value,_last_canvas.get_rotation(),_last_size,display_budget,{"persistent_summary":true})
		if not next.is_empty() and scale_value>float(_foundation.layers[fixed].upper): next["motion_summary"]=true
	else:
		# 普通HLOD同样可能已经驻留。只尝试有限的合格目录，避免仍等后台
		# 返回同一批资源的切面，或继续坚持已经失去边缘覆盖的原生视野。
		var cached := preload("res://scripts/rendering/tokyo_hlod_cached_cut.gd")
		for index: int in cached.candidate_catalogs(_catalogs,_target_catalog,_committed_catalog,scale_value,_return_cache):
			var catalog: Dictionary=_catalogs[index]
			if not catalog.has("geometry") or not catalog.has("textures") or not catalog.has("bounds"): continue
			next=cached.select(catalog,center,scale_value,_last_canvas.get_rotation(),_last_size,
				_geometry,_stream._cache,_stream._textures,_selection_work)
			if not next.is_empty() and _stage_prepared_motion(scale_value,[{"catalog":index,"cut":next}]):
				staged=true;break
		# HLOD也可能已经备好原生细档，只缺后台改切面的往返；复用最新目标档，
		# 没有原生目标时尝试同一已认证细档，任何缺资源/超预算仍立即拒绝。
		if not staged:
			next={}
			if _native!=null:
				var configuration: String=String(_target.get("configuration","lod5_full")) if _target_catalog==-2 \
					else String(_committed_cut.get("configuration","lod5_full")) if _committed_catalog==-2 else "lod5_full"
				next=_native.select(center,scale_value,_last_canvas.get_rotation(),_last_size,
					configuration,display_budget,{"meshes":_stream._cache,"textures":_stream._textures})
	var elapsed := Time.get_ticks_usec()-started
	cached_motion_selects+=1;cached_motion_select_peak_usec=maxi(cached_motion_select_peak_usec,elapsed)
	if PerfBuckets.frame_trace_enabled: PerfBuckets.tick("tokyo_map_cached_motion_select",elapsed)
	if staged: return true
	if next.is_empty(): return false
	return _stage_prepared_motion(scale_value,[{"catalog":fixed if fixed>=0 else -2,"cut":next}])


func _stage_prepared_motion(scale_value: float, proposals: Array = []) -> bool:
	# 后台已算过的预测切面随资源一起保留。跨边界时只核验，不再等一次规划往返。
	# 纯值候选没有显示权；仍必须通过最新机位、物理联合、清晰度和真实资源就绪门。
	if not _guard_prefetch or not is_instance_valid(_stream): return false
	for prepared: Dictionary in (_prepared_motion_cuts if proposals.is_empty() else proposals):
		var selected: int=prepared.catalog
		var next: Dictionary=prepared.cut
		if selected!=-2 and (selected<0 or selected>=_catalogs.size()): continue
		if preload("res://scripts/rendering/tokyo_installed_map.gd").motion_admission_enabled("AGL_TOKYO_LOD_BLEND") \
			and not Handoff.display_target_allowed(_catalogs,scale_value,_committed_catalog,selected): continue
		var qualified := Handoff.native_qualified(next,scale_value) if selected==-2 else Handoff.qualified(_catalogs[selected],next,scale_value)
		if not qualified or scale_value<float(next.get("anticipated_scale",0.0)): continue
		if not Handoff.retain_display(next,true,true,display_budget,Contract.native_page_limit() if selected==-2 else 16): continue
		if selected>=0 and not _resources_ready(next,selected) and _catalogs[selected].has("geometry"):
			var source: Variant=_source_ref.get_ref() if _source_ref!=null else null
			if typeof(source)!=TYPE_OBJECT or not is_instance_valid(source): continue
			var center: Vector2=_last_canvas.affine_inverse()*(source.get_viewport().get_visible_rect().size*0.5)
			var visible := Contract.visible_subset(_catalogs[selected],next,center,scale_value,
				_last_canvas.get_rotation(),_last_size,_selection_work)
			# 只裁掉屏外保护页；完整目录覆盖、逐页清晰度和真实资源门仍在下方重验。
			if visible.is_empty() or not Handoff.qualified(_catalogs[selected],visible,scale_value): continue
			visible["guard_prefetch_keys"]=next.keys
			next=visible
		if not _resources_ready(next,selected) or not _cut_covers_current_view(next,selected): continue
		var combined := _handoff_bytes(next,selected)
		if combined<0 or combined>_stream.residency_limit-_stream.residency_bytes: continue
		# 提交第一步仍要保留后续路径的预取意图，否则请求重建会回收刚读好的下一步。
		next=next.duplicate()
		next["prefetch_extra"]=Handoff.prefetch_requests(_catalogs,_target,_target_catalog)
		next["path_prefetch_first"]=_return_cache
		_target=next;_target_catalog=selected;_plan_revision+=1;_plan_dirty=true
		_request_target(true)
		_trace_prepared_state("prepared_motion",next,selected)
		return true
	return false


func _cut_covers_current_view(cut: Dictionary, catalog: int, margin_px: float = 0.0) -> bool:
	var coverage_started := Time.get_ticks_usec() if PerfBuckets.frame_trace_enabled else 0
	var source: Variant = _source_ref.get_ref() if _source_ref!=null else null
	if typeof(source)!=TYPE_OBJECT or not is_instance_valid(source): return false
	var logical: Vector2 = source.get_viewport().get_visible_rect().size
	var margin_logical := Vector2.ONE*margin_px*logical/_last_size
	var expanded_canvas := _last_canvas
	expanded_canvas.origin+=margin_logical
	var expanded_size := logical+2.0*margin_logical
	var inverse := expanded_canvas.affine_inverse()
	var view := Rect2(inverse*Vector2.ZERO,Vector2.ZERO)
	for point: Vector2 in [Vector2(expanded_size.x,0),expanded_size,Vector2(0,expanded_size.y)]: view=view.expand(inverse*point)
	view=view.intersection(_archive.bounds)
	if catalog>=0:
		var covered_hlod := Handoff.covers_projection(_catalogs[catalog],cut,view,expanded_canvas,expanded_size)
		if PerfBuckets.frame_trace_enabled: PerfBuckets.tick("tokyo_map_coverage",Time.get_ticks_usec()-coverage_started)
		return covered_hlod
	if _native==null: return false
	var covered_native: bool=_native.covers_visible_layers(cut,view,expanded_canvas,expanded_size)
	if PerfBuckets.frame_trace_enabled: PerfBuckets.tick("tokyo_map_coverage",Time.get_ticks_usec()-coverage_started)
	return covered_native


## 本帧该类重活是否处于争用（不改状态）：本帧已做过一件重活，或本帧含物理步（暂停不算），
## 且同类连续让出未达上限。
func _heavy_contested(kind: StringName) -> bool:
	if not map_frame_balance: return false
	# 旧画面完整不等于输入已有响应。显式候选的镜头正在等地图时，
	# 规划和提交不能再按“画面安全”让出；I/O/上传配额与物理预算仍照常。
	if not _camera_demand.is_empty() and preload("res://scripts/rendering/tokyo_installed_map.gd").motion_admission_enabled("AGL_TOKYO_DISPLAY_COMPACTION"): return false
	var stepped := PerfBuckets.frame_has_physics_step() and is_inside_tree() and not get_tree().paused
	return (_heavy_frame==Engine.get_process_frames() or stepped) and int(_heavy_runs.get(kind,0))<MAP_HEAVY_MAX_DEFER


## 本帧能否执行一件主线程重活；争用且可让时记一次让出，否则执行并占用本帧。
## 调用方声明不可让（画面安全依赖它）时照常执行。
func _heavy_slot(kind: StringName, deferrable: bool = true) -> bool:
	if deferrable and _heavy_contested(kind):
		_heavy_runs[kind]=int(_heavy_runs.get(kind,0))+1
		heavy_deferrals+=1
		heavy_deferrals_by_kind[kind]=int(heavy_deferrals_by_kind.get(kind,0))+1
		return false
	var frame := Engine.get_process_frames()
	_heavy_runs[kind]=0
	_heavy_frame=frame
	return true


func _summary_refinement_pending(scale_value: float) -> bool:
	# 只稳定普通细节质量；相机仍由完整常驻模型直接放行，不能等待这个计时器。
	if not _guard_prefetch or not _committed_cut.get("motion_summary",false) or _target.get("motion_summary",false) \
		or not _committed_qualified(scale_value) or not _cut_covers_current_view(_committed_cut,_committed_catalog): return false
	var logical := _last_size
	var hint: Dictionary={}
	var source: Variant=_source_ref.get_ref() if _source_ref!=null else null
	if typeof(source)==TYPE_OBJECT and is_instance_valid(source):
		var viewport: Viewport=source.get_viewport()
		logical=viewport.get_visible_rect().size
		var camera: Camera2D=viewport.get_camera_2d()
		if camera!=null: hint=camera.get_meta(&"map_return_hint",{})
	if preload("res://scripts/rendering/tokyo_hlod_foundation.gd").motion_active(_pan_velocity,_zoom_rate,scale_value,logical,_last_size,hint):
		_summary_refinement_ready_at=Time.get_ticks_msec()+150
	return Time.get_ticks_msec()<_summary_refinement_ready_at


func _commit_ready_target(scale_value: float) -> bool:
	if _target.is_empty() or _target_committed(): return false
	if preload("res://scripts/rendering/tokyo_installed_map.gd").motion_admission_enabled("AGL_TOKYO_LOD_BLEND") \
		and not Handoff.display_target_allowed(_catalogs,scale_value,_committed_catalog,_target_catalog): return false
	# 新输入已经需要接替时不得等待渐变计时；当前旧视野完整不代表下一视野可达。
	if not _lod_old_cut.is_empty():
		if _camera_demand.is_empty() and _committed_qualified(scale_value) and _cut_covers_current_view(_committed_cut,_committed_catalog): return false
		_end_lod_blend()
	# 所有目标都必须重新证明此刻覆盖；异步期间相机可能已离开请求时的视野。
	if not _target_covers_current_view(): return false
	if _zooming_in and not _committed_cut.get("motion_summary",false) and _target_catalog>=0 and _committed_catalog>=0 and _committed_qualified(scale_value) \
		and _cut_covers_current_view(_committed_cut,_committed_catalog) \
		and Handoff.scale_limit(_catalogs[_target_catalog],_target)<Handoff.scale_limit(_catalogs[_committed_catalog],_committed_cut):
		return false
	if _target.has("anticipated_scale"):
		if scale_value<float(_target.anticipated_scale): return false

	if _target_catalog==-2:
		if not Handoff.native_qualified(_target,scale_value): return false
	elif _target_catalog<0 or not Handoff.qualified(_catalogs[_target_catalog],_target,scale_value): return false
	if not _resources_ready(_target,_target_catalog): return false
	if _summary_refinement_pending(scale_value): return false
	# 错峰：旧切面仍合格且覆盖当前视野时，交接可有界让给后续帧，让出期间旧画面完整可见。
	# 覆盖核验有成本，只在本帧确实争用时才算；旧切面完整才让出。
	var display_safe := _heavy_contested(&"commit") and not _committed.is_empty() \
		and _committed_qualified(scale_value) and _cut_covers_current_view(_committed_cut,_committed_catalog)
	# 已准备的共同有效区很窄；再错峰会错过过渡窗口。资源准备仍受原额度约束。
	if _target.get("lod_blend_target",false): display_safe=false
	if not _heavy_slot(&"commit",display_safe): return false
	# 新地表租约先到手才释放旧画面；预约失败必须保持旧节点、可见性和旧租约。
	var next_ground: RefCounted
	if _target_catalog!=-2 or int(_target.get("charges",{}).get("ground_bytes",0))>0:
		next_ground=RefCounted.new()
		if not _stream.reserve_auxiliary(next_ground.get_instance_id(),int(_target.charges.ground_bytes)):
			_fallback="waiting ground budget"
			_handoff_reason="ground_budget"
			return false
	summary_motion_commits+=int(_target.get("motion_summary",false))
	if _target.get("motion_summary",false): _summary_refinement_ready_at=Time.get_ticks_msec()+150
	summary_motion_refinements+=int(_committed_cut.get("motion_summary",false) and _target_catalog!=_committed_catalog)
	var blend := false
	var blend_bytes := 0
	if preload("res://scripts/rendering/tokyo_installed_map.gd").motion_admission_enabled("AGL_TOKYO_LOD_BLEND") \
		and _camera_demand.is_empty() \
		and not _committed.is_empty() and (_committed_catalog!=_target_catalog or _committed_cut.get("configuration","")!=_target.get("configuration","")) \
		and _committed_qualified(scale_value) and _cut_covers_current_view(_committed_cut,_committed_catalog):
		blend_bytes=_handoff_bytes(_target,_target_catalog)
		blend=Handoff.blend_allowed(_committed_cut,_target,blend_bytes,display_budget)
		lod_blend_budget_skips+=int(not blend)
	var old_nodes: Array[MeshInstance3D]=[]
	var old_materials: Array[ShaderMaterial]=[]
	var old_cut := _committed_cut
	var old_catalog := _committed_catalog
	var old_token: RefCounted
	var retained_nodes := {}
	if blend:
		old_nodes=_nodes;_nodes=[]
		old_materials=_page_materials;_page_materials=[]
		if _ground_charged: old_token=_ground_token
		_ground_charged=false
	else: retained_nodes=_take_reusable_hlod_nodes()
	_clear_current()
	if next_ground!=null: _ground_token=next_ground
	_cached_cut_commits+=int(_target.get("cache_bridge",false))
	_native_screen_bridge_commits+=int(_target.get("native_screen_bridge",false))
	_ground_charged=next_ground!=null
	_bind_target(retained_nodes)
	if blend:
		_lod_old_nodes=old_nodes;_lod_old_materials=old_materials;_lod_old_cut=old_cut
		_lod_old_catalog=old_catalog;_lod_old_token=old_token;_lod_blend_age=0.0
		_lod_blend_start_scale=scale_value;_lod_blend_amount=0.0
		_lod_blend_started_usec=Time.get_ticks_usec()
		for material: ShaderMaterial in _lod_old_materials:
			material.set_shader_parameter("outgoing",true);material.set_shader_parameter("lod_mix",0.0)
		for material: ShaderMaterial in _page_materials: material.set_shader_parameter("lod_mix",0.0)
		lod_blends+=1
		max_transition_triangles=maxi(max_transition_triangles,int(old_cut.triangles)+int(_committed_cut.triangles))
		lod_blend_peak_pages=maxi(lod_blend_peak_pages,old_cut.keys.size()+_committed.size())
		lod_blend_peak_bytes=maxi(lod_blend_peak_bytes,blend_bytes)
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
		for key: String in cut.get("keys",PackedStringArray()):
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


func _visible_target_keys() -> PackedStringArray:
	var keys: PackedStringArray=_target.get("keys",PackedStringArray())
	var source: Variant=_source_ref.get_ref() if _source_ref!=null else null
	if _target_catalog<0 or typeof(source)!=TYPE_OBJECT or not is_instance_valid(source): return keys
	var logical: Vector2=source.get_viewport().get_visible_rect().size
	var canvas: Transform2D=_camera_demand.get("canvas",_last_canvas)
	var size: Vector2=_camera_demand.get("size",_last_size)
	if logical.x<=0.0 or size.x<=0.0: return keys
	var center := canvas.affine_inverse()*(logical*0.5)
	return Contract.visible_keys(_target,center,canvas.x.length()*size.x/logical.x,canvas.get_rotation(),size)


func _prioritized_target_keys(visible: PackedStringArray = PackedStringArray()) -> PackedStringArray:
	if visible.is_empty(): visible=_visible_target_keys()
	var keys: PackedStringArray=_target.get("keys",PackedStringArray())
	var ordered := PackedStringArray()
	for key: String in keys:
		if key in visible: ordered.append(key)
	for key: String in keys:
		if key not in visible: ordered.append(key)
	return ordered


func _request_target(keep_current: bool) -> void:
	var request_started := Time.get_ticks_usec()
	var meshes := PackedStringArray()
	var textures := PackedStringArray()
	var mesh_pins := PackedStringArray()
	var texture_pins := PackedStringArray()
	textures.append_array(PackedStringArray(_target.get("ground_images",[])))
	var visible := _visible_target_keys()
	var visible_meshes := PackedStringArray()
	var visible_images := PackedStringArray(_target.get("ground_images",[]))
	for key: String in _prioritized_target_keys(visible):
		if _target_catalog==-2:
			meshes.append(key)
			visible_meshes.append(key)
		else:
			var row: Dictionary = _catalogs[_target_catalog].rows[key]
			meshes.append(row.native_geometry.path)
			textures.append(row.native_texture.path)
			if key in visible:
				visible_meshes.append(row.native_geometry.path);visible_images.append(row.native_texture.path)
	# 在附加预测之前保存真实目标，跨网格/图片的共享槽不能只按各自列表排序。
	var charged_meshes := meshes.duplicate()
	var charged_images := textures.duplicate()
	var priority_meshes := meshes.duplicate()
	var prefetch_meshes := PackedStringArray()
	_stream.touch_display_resources(meshes,textures)
	if _stream.visible_io_first or _stream.fair_image_slot or _stream.visible_finalize_first or _stream.light_frame_balance:
		_stream.visible_meshes=_stream._paths(visible_meshes)
		_stream.visible_images=visible_images
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
	if not _lod_old_cut.is_empty():
		ground+=int(_lod_old_cut.get("charges",{}).get("ground_bytes",0))
		texture_pins.append_array(PackedStringArray(_lod_old_cut.get("ground_images",[])))
		charged_images.append_array(PackedStringArray(_lod_old_cut.get("ground_images",[])))
		for key: String in _lod_old_cut.keys:
			if _lod_old_catalog==-2:
				mesh_pins.append(key);charged_meshes.append(key)
			else:
				var row: Dictionary=_catalogs[_lod_old_catalog].rows[key]
				mesh_pins.append(row.native_geometry.path);charged_meshes.append(row.native_geometry.path)
				texture_pins.append(row.native_texture.path);charged_images.append(row.native_texture.path)
	var requests := Handoff.prefetch_requests(_catalogs,_target,_target_catalog)
	if _return_cache and _geometry_aliases.has(_target_catalog):
		var aliases: Array[Dictionary]=[]
		for path: String in priority_meshes:
			if _geometry_aliases[_target_catalog].has(path): aliases.append(_geometry_aliases[_target_catalog][path])
		# 高速平移时当前路线先于尚未需要的更细网格；开始放大或低速时提前预热换档。
		# 这里只排序同池预取，绝不延迟相机或降低已显示档的精度。
		if _zoom_rate>0.02 or _pan_velocity.length()*output_scale<600.0:
			aliases.append_array(requests);requests=aliases
		else: requests.append_array(aliases)
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
	# 同一个已接纳请求集合里，最近预测视野先于旧档屏外保护页。
	# 这里只更换队序，不改变目标切面、不废弃规划结果、也不增加槽或资源预算。
	var urgent_meshes := visible_meshes.duplicate()
	var urgent_images := visible_images.duplicate()
	for prepared: Dictionary in _prepared_motion_cuts:
		var index: int=prepared.catalog
		if index<0 or index>=_catalogs.size(): continue
		var outstanding := false
		var candidate_meshes := PackedStringArray()
		var candidate_images := PackedStringArray()
		for key: String in prepared.cut.get("keys",PackedStringArray()):
			var row: Dictionary=_catalogs[index].rows[key]
			if row.native_texture.path not in urgent_images and row.native_texture.path in textures:
				candidate_images.append(row.native_texture.path)
				if not _stream._textures.has(row.native_texture.path): outstanding=true
			if row.native_geometry.path not in urgent_meshes and (row.native_geometry.path in priority_meshes or row.native_geometry.path in prefetch_meshes):
				candidate_meshes.append(row.native_geometry.path)
				for path: String in _stream._paths(PackedStringArray([row.native_geometry.path])):
					if not _stream._cache.has(path): outstanding=true
		# 已完整驻留的近时刻不占用优先级，继续找到真正尚未就绪的最近路径。
		if outstanding:
			urgent_meshes.append_array(candidate_meshes);urgent_images.append_array(candidate_images)
			break
	var all_meshes := priority_meshes.duplicate();all_meshes.append_array(prefetch_meshes)
	priority_meshes=PackedStringArray();prefetch_meshes=PackedStringArray()
	for path: String in urgent_meshes:
		if path in all_meshes: priority_meshes.append(path)
	for path: String in all_meshes:
		if path not in priority_meshes: prefetch_meshes.append(path)
	var ordered_images := PackedStringArray()
	for path: String in urgent_images:
		if path in textures: ordered_images.append(path)
	for path: String in textures:
		if path not in ordered_images: ordered_images.append(path)
	textures=ordered_images
	if _stream.visible_io_first or _stream.fair_image_slot or _stream.visible_finalize_first or _stream.light_frame_balance:
		_stream.visible_meshes=_stream._paths(priority_meshes)
		_stream.visible_images=urgent_images
	if PerfBuckets.frame_trace_enabled: PerfBuckets.tick("tokyo_map_request_plan",Time.get_ticks_usec()-request_started)
	var dispatch_started := Time.get_ticks_usec()
	_stream.request_partitioned(priority_meshes,_stream.residency_meshes,prefetch_meshes,mesh_pins)
	var textures_started := Time.get_ticks_usec()
	_stream.request_textures(textures,texture_pins)
	if PerfBuckets.frame_trace_enabled: PerfBuckets.tick("tokyo_map_dispatch_textures",Time.get_ticks_usec()-textures_started)
	if PerfBuckets.frame_trace_enabled: PerfBuckets.tick("tokyo_map_request_dispatch",Time.get_ticks_usec()-dispatch_started)


func _take_reusable_hlod_nodes() -> Dictionary:
	# 所有显示门已通过后才转移所有权；中间没有await，旧页保持在原场景树位置。
	var retained := {}
	if not _return_cache or _target_catalog<0 or _target_catalog!=_committed_catalog: return retained
	var keep_ids := {}
	for key: String in _target.keys:
		var nodes: Array=_hlod_binding_nodes.get(key,[])
		var valid := not nodes.is_empty()
		for value: Variant in nodes:
			if typeof(value)!=TYPE_OBJECT or not is_instance_valid(value) or not value is MeshInstance3D:
				valid=false;break
			if value.get_parent()!=_city: valid=false;break
		if not valid: continue
		retained[key]=nodes.duplicate()
		for value: Variant in nodes: keep_ids[value.get_instance_id()]=true
	var disposable: Array[MeshInstance3D]=[]
	for value: Variant in _nodes:
		if typeof(value)!=TYPE_OBJECT or not is_instance_valid(value): continue
		if not keep_ids.has(value.get_instance_id()): disposable.append(value as MeshInstance3D)
	_nodes=disposable
	return retained


func _bind_target(retained_nodes: Dictionary = {}) -> void:
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
		if retained_nodes.has(key):
			# 来自本次同步交接的已验证节点；不重新创建地表网格、材质和实例RID。
			var nodes: Array=retained_nodes[key]
			for value: Variant in nodes:
				if typeof(value)==TYPE_OBJECT and is_instance_valid(value) and value is MeshInstance3D:
					_nodes.append(value as MeshInstance3D)
					var material: Material=value.material_override
					if material is ShaderMaterial and not _page_materials.has(material): _page_materials.append(material)
			_hlod_binding_nodes[key]=nodes
			reused_hlod_pages+=1
			continue
		var node_start := _nodes.size()
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
		_hlod_binding_nodes[key]=_nodes.slice(node_start)
		created_hlod_pages+=1
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


func _stage_lod_successor(scale_value: float) -> bool:
	if _pan_velocity.length()*scale_value>600.0: return false
	if not _lod_old_cut.is_empty() or not _committed_cut.has("lod_successor"): return false
	var successor: Dictionary=_committed_cut.lod_successor
	var direction: int=successor.direction
	if direction*_zoom_rate<=0.02 or direction*(scale_value-float(successor.scale))<0.0: return false
	var next: Dictionary=successor.cut
	var selected: int=successor.catalog
	var qualified := Handoff.native_qualified(next,scale_value) if selected==-2 else Handoff.qualified(_catalogs[selected],next,scale_value)
	if not qualified or not _cut_covers_current_view(next,selected) or not _resources_ready(next,selected): return false
	var combined := _handoff_bytes(next,selected)
	if combined<0 or combined>_stream.residency_limit-_stream.residency_bytes: return false
	_target=next.duplicate();_target["lod_blend_target"]=true
	# 成对切面交接后仍保留原反向入口；快速反转不必等待后台重建同一对已准备资源。
	# 剥掉旧后继，只保留一份反向切面，防止往返次数变成递归增长的历史链。
	if selected!=_committed_catalog and successor.has("reverse_scale"):
		var reverse_cut := _committed_cut.duplicate()
		reverse_cut.erase("lod_successor")
		_target["lod_successor"]={"catalog":_committed_catalog,"cut":reverse_cut,
			"direction":-direction,"scale":successor.reverse_scale,"reverse_scale":successor.scale}
	_target_catalog=selected;_plan_revision+=1;_plan_dirty=true
	_request_target(true)
	return true


func _step_lod_blend(scale_value: float, _delta: float) -> bool:
	if _lod_old_cut.is_empty(): return false
	# 这是显示过渡，不随战斗慢动作拉长，也不等待模拟恢复后才清理旧页。
	_lod_blend_age=maxf(0.0,float(Time.get_ticks_usec()-_lod_blend_started_usec)/1000000.0)
	var qualified := Handoff.native_qualified(_lod_old_cut,scale_value) if _lod_old_catalog==-2 \
		else Handoff.qualified(_catalogs[_lod_old_catalog],_lod_old_cut,scale_value)
	if _lod_blend_age>=0.09 or not _camera_demand.is_empty() or not qualified or not _cut_covers_current_view(_lod_old_cut,_lod_old_catalog):
		_end_lod_blend()
		if not _target.is_empty(): _request_target(not _target_committed())
		return true
	# 快速滚轮可能在90ms内穿过整个共同有效区；按剩余尺度同步完成，不能半途硬切。
	var boundary := float(_lod_old_cut.get("lod_blend_floor",0.0)) if _lod_old_catalog==-2 \
		else Handoff.scale_limit(_catalogs[_lod_old_catalog],_lod_old_cut)
	_lod_blend_amount=maxf(_lod_blend_amount,Handoff.blend_progress(_lod_blend_age,_lod_blend_start_scale,scale_value,boundary))
	var amount := _lod_blend_amount
	for material: ShaderMaterial in _lod_old_materials: material.set_shader_parameter("lod_mix",amount)
	for material: ShaderMaterial in _page_materials: material.set_shader_parameter("lod_mix",amount)
	return true


func _end_lod_blend() -> void:
	if _lod_old_cut.is_empty(): return
	for value: Variant in _lod_old_nodes:
		if typeof(value)==TYPE_OBJECT and is_instance_valid(value): value.free()
	_lod_old_nodes.clear();_lod_old_materials.clear();_lod_old_cut={};_lod_old_catalog=-1
	if _lod_old_token!=null and is_instance_valid(_stream): _stream.release_auxiliary(_lod_old_token.get_instance_id())
	_lod_old_token=null
	for material: ShaderMaterial in _page_materials:
		material.set_shader_parameter("outgoing",false);material.set_shader_parameter("lod_mix",1.0)


func _clear_current() -> void:
	_end_lod_blend()
	_plan_revision+=1
	display_qualified=false;display_covered=false
	var clear_started := Time.get_ticks_usec() if PerfBuckets.frame_trace_enabled else 0
	_display_grace=false;_grace_started=-1;_grace_age_ms=0
	for node in _nodes:
		if is_instance_valid(node): node.free()
	_nodes.clear();_hlod_binding_nodes.clear();_page_materials.clear();_committed.clear()
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
	_end_lod_blend()
	super._deactivate()
	display_qualified=false;display_covered=false
	_camera_demand={};_camera_wait_started=-1
	_camera_motion_hint={}
	_prepared_motion_cuts=[]
	if is_instance_valid(_stream): _stream.input_waiting=false
	_sync_legacy()


func _exit_tree() -> void:
	var retired: Array=[_catalogs,_geometry,_textures,_selection_work,_foundation,_prepared_stream_source]
	if _native!=null: retired.append_array(_native.retirement_data())
	if _map_worker!=null: _map_worker.close(retired)
	if is_instance_valid(_metadata_retirement): _metadata_retirement.hold(retired)
	if _future_predictor!=null: _future_predictor.close()
	_clear_current()
	if is_instance_valid(_stream): _stream.close()


func debug_state() -> Dictionary:
	var ready := _committed.size()
	return {"active":_active,"enabled":_enabled,"hlod":true,"fallback":_fallback,"cut_ready":_target_committed(),
		"lod_blends":lod_blends,"lod_blend_budget_skips":lod_blend_budget_skips,"lod_blend_peak_pages":lod_blend_peak_pages,"lod_blend_peak_bytes":lod_blend_peak_bytes,
		"reused_hlod_pages":reused_hlod_pages,"created_hlod_pages":created_hlod_pages,
		"staged_switches":staged_switches,"max_transition_triangles":max_transition_triangles,
		"handoff_reason":_handoff_reason,"native_page_limit":Contract.native_page_limit(),
		"prefetch_pages":_prefetch_pages,
		"map_frame_balance":map_frame_balance,"heavy_deferrals":heavy_deferrals,"heavy_deferrals_by_kind":heavy_deferrals_by_kind.duplicate(),
		"map_planning":{"mode":_plan_mode,"worker":_map_worker.summary() if _map_worker!=null else {},
			"setup_stages_usec":_setup_stages,
			"prepare_usec":_plan_prepare_usec,"prepare_stages_usec":_plan_prepare_stages,"submit_usec":_plan_submit_usec,"admission_usec":_plan_admission_usec,
			"applied":_plan_applied,"rejected":_plan_rejected,"pending_frames":_plan_pending_frames,"stats":_plan_stats},
		"loading_neighborhood_bytes":loading_neighborhood_bytes,"loading_neighborhood_pinned":loading_neighborhood,
		"resident_foundation":resident_foundation,"foundation_cut":_committed_cut.get("foundation",false),
		"foundation_prefetch_skips":foundation_prefetch_skips,
		"speculative_plan_reuses":speculative_plan_reuses,
		"async_prefetch":{} if _future_predictor==null else {"submitted":_future_predictor.submitted,"applied":_future_predictor.applied,"fallback":_future_predictor.fallback,"prepare_usec":_future_predictor.prepare_usec,"discarded":_future_predictor.worker.discarded,"rejections":_future_predictor.rejections,"center_samples":_future_predictor.center_samples},
		"cached_cut_attempts":_cached_cut_attempts,"cached_cut_commits":_cached_cut_commits,
		"cached_motion_selects":cached_motion_selects,"cached_motion_select_peak_usec":cached_motion_select_peak_usec,
		"summary_motion_commits":summary_motion_commits,"summary_motion_refinements":summary_motion_refinements,"summary_motion_adoptions":summary_motion_adoptions,
		"native_screen_bridge_commits":_native_screen_bridge_commits,
		"native_screen_bridge_state":_native_screen_bridge_state.duplicate(),
		"camera_wait_frames":camera_wait_frames,"camera_wait_max_ms":camera_wait_max_ms,
		"committed_catalog":_committed_catalog,"display_budget":display_budget,"display_bytes":int(_committed_cut.get("bytes",0)),
		"display_qualified":display_qualified,"display_covered":display_covered,
		"lod_grace_active":_display_grace,"lod_grace_frames":lod_grace_frames,"max_lod_grace_ms":max_lod_grace_ms,"max_lod_grace_ratio":max_lod_grace_ratio,
		"retained_cuts":retained_cuts,
		"pending_selection_reuses":pending_selection_reuses,"motion_actual_cuts":motion_actual_cuts,
		"native_screen_rejections":native_screen_rejections,
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


func _prepare_map_planner() -> bool:
	if _prepared_source_ready: return true
	_geometry_aliases=Handoff.shared_texture_meshes(_catalogs) if _return_cache else {}
	if _native is GridNative or OS.get_environment("AGL_TOKYO_SYNC_SELECTION")=="1":
		_plan_mode="legacy_grid" if _native is GridNative else "explicit_sync_control"
		return true
	var started := Time.get_ticks_usec()
	_plan_readiness=_return_cache or OS.get_environment("AGL_TOKYO_CACHED_CUT")=="1"
	var prepared := {}
	for catalog: Dictionary in _catalogs:
		if catalog.get("transition_only",false): continue
		var artifact := PreparedCatalog.load_or_build(catalog)
		if artifact.is_empty(): return false
		prepared[catalog.identity.path]=artifact
	_plan_prepare_stages["prepared_catalogs"]=Time.get_ticks_usec()-started
	var phase_started := Time.get_ticks_usec()
	# Physical identity was verified during package loading. Keep costs and dependency keys,
	# never duplicate vertex/UV/index arrays into the planner.
	var geometry := {}
	var physical_rows := {}
	for path: String in _geometry:
		var row: Dictionary=_geometry[path]
		var parts := {}
		for physical: String in row.get("components",{path:row}):
			var item: Dictionary=row.get("components",{path:row})[physical]
			if physical_rows.has(physical) and physical_rows[physical]!=item: return false
			physical_rows[physical]=item
			parts[physical]={"bytes":int(item.bytes),"physical_identity":physical}
		geometry[path]={"components":parts}
	var textures := {}
	for path: String in _textures: textures[path]={"charge":int(_textures[path].charge)}
	_plan_prepare_stages["descriptors"]=Time.get_ticks_usec()-phase_started
	phase_started=Time.get_ticks_usec()
	var native_snapshot: Dictionary=_native.selection_snapshot() if _native!=null else {}
	_plan_prepare_stages["native_snapshot"]=Time.get_ticks_usec()-phase_started
	var source := {"catalogs":_catalogs,"prepared_catalogs":prepared,"geometry":geometry,"textures":textures,
		"foundation":_foundation,"bounds":_archive.bounds,"native":native_snapshot,
		"context":{"background":true,"epoch":0,"display_limit":display_budget,"native_page_limit":Contract.native_page_limit()},
		"flags":{"small_uploads":_small_uploads,"actual_before_native":OS.get_environment("AGL_TOKYO_ACTUAL_BEFORE_NATIVE")=="1",
			"lod_transition":preload("res://scripts/rendering/tokyo_installed_map.gd").motion_admission_enabled("AGL_TOKYO_LOD_BLEND"),
			"share_selection_source":preload("res://scripts/rendering/tokyo_installed_map.gd").motion_admission_enabled("AGL_TOKYO_BACKGROUND_SOURCE"),
			"display_compaction":preload("res://scripts/rendering/tokyo_installed_map.gd").motion_admission_enabled("AGL_TOKYO_DISPLAY_COMPACTION"),
			"wide_motion_guard":preload("res://scripts/rendering/tokyo_installed_map.gd").runtime_option("AGL_TOKYO_WIDE_HANDOFF")=="1",
			"guard_prefetch":_guard_prefetch,
			"return_cache":_return_cache,
			"cached_cut":OS.get_environment("AGL_TOKYO_CACHED_CUT")=="1","native_screen_bridge":OS.get_environment("AGL_TOKYO_NATIVE_SCREEN_BRIDGE")=="1"}}
	_map_worker=MapWorker.new()
	phase_started=Time.get_ticks_usec()
	if not _map_worker.configure(source,_plan_generation):
		_map_worker=null
		return false
	_plan_prepare_stages["worker_configure"]=Time.get_ticks_usec()-phase_started
	_plan_prepare_usec=Time.get_ticks_usec()-started
	_plan_mode="prepared_background"
	return true


func _planning_request(scale_value: float, zooming_out: bool) -> Dictionary:
	var source: Variant=_source_ref.get_ref()
	var viewport: Viewport=source.get_viewport()
	var camera := viewport.get_camera_2d()
	var logical := viewport.get_visible_rect().size
	# 控制器声明的是逻辑 zoom，选页使用输出像素倍率；缩放视口不能直接套 0.2。
	var prediction_floor := float(camera.get_meta(&"map_prediction_zoom_floor",0.0))*_last_size.x/logical.x \
		if camera!=null and logical.x>0.0 else 0.0
	var ready_meshes: Variant={}
	var ready_images: Variant={}
	var planned_meshes: Variant={}
	var planned_images: Variant={}
	# Snapshot only key sets. Actual resources and their reference counts stay on the main thread.
	if _return_cache:
		# 字符串数组保持纯值快照；哈希集合在后台恢复，主线程不逐键递归复制 Dictionary。
		ready_meshes=PackedStringArray(_stream._cache.keys())
		ready_images=PackedStringArray(_stream._textures.keys())
		planned_meshes=_stream._wanted.duplicate()
		planned_meshes.append_array(PackedStringArray(_stream._pending.keys()))
		planned_images=_stream._texture_wanted.duplicate()
		planned_images.append_array(PackedStringArray(_stream._texture_jobs.keys()))
	elif _plan_readiness:
		for key: String in _stream._cache: ready_meshes[key]=true
		for key: String in _stream._textures: ready_images[key]=true
	elif _guard_prefetch:
		# 主动概括只需要常驻根的实际就绪键；不每次复制整个细节缓存。
		for path: String in _stream.residency_meshes:
			for part: String in _geometry.get(path,{}).get("components",{path:{}}):
				if _stream._cache.has(part): ready_meshes[part]=true
		for path: String in _stream.residency_images:
			if _stream._textures.has(path): ready_images[path]=true
	_plan_sequence+=1
	# 平移/放大被连续性门截住时，后台应准备待提交机位；缩远则逐步经过实际中间档。
	var pending_pose := not _camera_demand.is_empty() and (_committed_catalog==-2 or float(_camera_demand.get("scale",scale_value))>=scale_value or (preload("res://scripts/rendering/tokyo_installed_map.gd").motion_admission_enabled("AGL_TOKYO_DISPLAY_COMPACTION")))
	return {"sequence":_plan_sequence,"revision":_plan_revision,"canvas":_camera_demand.canvas if pending_pose else _last_canvas,
		"size":_camera_demand.size if pending_pose else _last_size,
		"display_canvas":_last_canvas,"display_size":_last_size,"display_scale":scale_value,
		"logical":logical,"scale":_camera_demand.scale if pending_pose else scale_value,"zooming_out":zooming_out,
		"prediction_floor":prediction_floor,
		"return_hint":camera.get_meta(&"map_return_hint",{}) if _guard_prefetch and camera!=null else {},
		"camera_demand":pending_pose,"pan_velocity":_camera_demand.get("velocity",_pan_velocity),
		"zoom_rate":_camera_demand.get("rate",_zoom_rate),"committed_catalog":_committed_catalog,
		"committed":MapPlanner.compact_cut(_committed_cut),"target_catalog":_target_catalog,"target":MapPlanner.compact_cut(_target),
		"stream":{"residency_limit":_stream.residency_limit,"residency_bytes":_stream.residency_bytes,
			"residency_meshes":_stream.residency_meshes.duplicate(),"residency_images":_stream.residency_images.duplicate(),
			"_cache":ready_meshes,"_textures":ready_images,"planned_meshes":planned_meshes,"planned_images":planned_images}}


func _step_prepared_selection(scale_value: float, zooming_out: bool, reversing_in: bool, rapid_zoom: bool, current_covered: bool, changed: bool) -> bool:
	var due := _selection_due(current_covered,scale_value,reversing_in,rapid_zoom)
	if due and (_last_selected_canvas!=_last_canvas or _last_selected_size!=_last_size): _plan_dirty=true
	# 只在当前画面完整（覆盖视野且合格）时允许让出；画面不安全时规划必须尽快推进。
	var display_safe := map_frame_balance and current_covered and _committed_qualified(scale_value)
	# 已完成的规划结果在 worker 中等待领取（占用唯一槽位），让出不会丢结果或重复提交。
	if _map_worker.ready() and _heavy_slot(&"plan_admit",display_safe):
		var started := Time.get_ticks_usec()
		var envelope: Dictionary=_map_worker.take(_plan_generation)
		if PerfBuckets.frame_trace_enabled: PerfBuckets.tick("tokyo_map_plan_take",Time.get_ticks_usec()-started)
		if not envelope.is_empty():
			var plan: Dictionary=envelope.plan
			_plan_stats=plan.stats
			_trace_prepared_state("prepared_result",plan.cut,int(plan.catalog),envelope.request)
			if int(envelope.request.revision)==_plan_revision:
				changed=_admit_prepared_plan(plan,envelope.request,scale_value,current_covered,changed) or changed
			else:
				_plan_rejected+=1;_plan_dirty=true
		_plan_admission_usec+=Time.get_ticks_usec()-started
		if PerfBuckets.frame_trace_enabled: PerfBuckets.tick("tokyo_map_plan_admit",Time.get_ticks_usec()-started)
	if _map_worker.busy():
		_plan_pending_frames+=1
	elif _plan_dirty and _heavy_slot(&"plan_submit",display_safe):
		var started := Time.get_ticks_usec()
		var request := _planning_request(scale_value,zooming_out)
		if PerfBuckets.frame_trace_enabled: PerfBuckets.tick("tokyo_map_plan_request",Time.get_ticks_usec()-started)
		if _map_worker.submit(request):
			_plan_dirty=false
			_lod_clock=0.05
			_last_selected_canvas=_last_canvas;_last_selected_size=_last_size
		else:
			_fallback="planning request rejected"
		_plan_submit_usec+=Time.get_ticks_usec()-started
		if PerfBuckets.frame_trace_enabled: PerfBuckets.tick("tokyo_map_plan_submit",Time.get_ticks_usec()-started)
	return changed


func _trace_prepared_state(kind: String, next: Dictionary = {}, selected: int = -1, request: Dictionary = {}) -> void:
	if not _trace_selection or _selection_trace.size()>=2048: return
	_selection_trace.append({"kind":kind,"frame":Engine.get_process_frames(),"ticks_msec":Time.get_ticks_msec(),
		"planning_worker":_map_worker.summary() if _map_worker!=null else {},"next_checkpoint":next.get("motion_checkpoint",false),
		"scale":output_scale,"center":_motion_center,"canvas":_last_canvas,"zoom_rate":_zoom_rate,"pan_velocity":_pan_velocity,
		"revision":_plan_revision,"request_revision":request.get("revision",-1),"request_canvas":request.get("canvas",Transform2D.IDENTITY),
		"request_pan_velocity":request.get("pan_velocity",Vector2.ZERO),"request_scale":request.get("scale",0.0),"request_zoom_rate":request.get("zoom_rate",0.0),
		"current_catalog":_committed_catalog,"current":_committed.duplicate(),"current_bytes":_committed_cut.get("bytes",0),
		"current_guard":_committed_cut.get("spatial_guard_px",0),"current_qualified":_committed_qualified(output_scale),
		"current_stage":_committed_cut.get("selection_stage",""),"current_trim_lead":_committed_cut.get("trim_lead_world",Vector2.ZERO),
		"current_motion_lead":_committed_cut.get("motion_lead_world",Vector2.ZERO),"current_motion_horizon":_committed_cut.get("motion_horizon",0.0),
		"current_configuration":_committed_cut.get("configuration",""),"current_triangles":_committed_cut.get("triangles",0),
		"current_guard_rejection":_committed_cut.get("guard_rejection",{}),"current_prefetched_native":_committed_cut.get("prefetched_native",false),
		"current_covered":_cut_covers_current_view(_committed_cut,_committed_catalog) if not _committed.is_empty() else false,
		"target_catalog":_target_catalog,"target":_target.get("keys",[]).duplicate(),"target_bytes":_target.get("bytes",0),
		"target_guard":_target.get("spatial_guard_px",0),"target_anticipated":_target.get("anticipated_scale",0),
		"target_stage":_target.get("selection_stage",""),"target_trim_lead":_target.get("trim_lead_world",Vector2.ZERO),
		"target_configuration":_target.get("configuration",""),"target_triangles":_target.get("triangles",0),
		"target_guard_rejection":_target.get("guard_rejection",{}),"target_prefetched_native":_target.get("prefetched_native",false),
		"target_covered":_target_covers_current_view() if not _target.is_empty() else false,
		"target_ready":_resources_ready(_target,_target_catalog) if not _target.is_empty() else false,
		"target_union":_handoff_bytes(_target,_target_catalog) if not _target.is_empty() else -1,
		"next_catalog":selected,"next":next.get("keys",[]).duplicate(),"next_bytes":next.get("bytes",0),
		"next_prefetch_catalog":next.get("prefetch_catalog",-1),"next_prefetch":next.get("prefetch_keys",[]).duplicate(),
		"next_prefetch_extra":next.get("prefetch_extra",[]).duplicate(),
		"next_guard":next.get("spatial_guard_px",0),"next_anticipated":next.get("anticipated_scale",0),
		"next_stage":next.get("selection_stage",""),"next_bridge":next.get("handoff_bridge",false),"next_trim_lead":next.get("trim_lead_world",Vector2.ZERO),
		"next_motion_need":next.get("motion_guard_need_px",0.0),
		"next_motion_lead":next.get("motion_lead_world",Vector2.ZERO),"next_motion_horizon":next.get("motion_horizon",0.0),
		"next_configuration":next.get("configuration",""),"next_triangles":next.get("triangles",0),
		"next_guard_rejection":next.get("guard_rejection",{}),"next_prefetched_native":next.get("prefetched_native",false),
		"next_covered":_cut_covers_current_view(next,selected) if not next.is_empty() else false,
		"next_ready":_resources_ready(next,selected) if not next.is_empty() else false,
		"next_union":_handoff_bytes(next,selected) if not next.is_empty() else -1,
		"reason":_handoff_reason,"fallback":_fallback,"stream":_stream.summary()})


func _admit_prepared_plan(plan: Dictionary, request: Dictionary, scale_value: float, current_covered: bool, changed: bool) -> bool:
	# 调用处已核验来源代数和显示修订；四份当前路径与两份突发回中纯值切面。
	if _guard_prefetch: _prepared_motion_cuts=plan.get("prepared_cuts",[]).slice(0,16 if _return_cache else 8)
	var next: Dictionary=plan.cut
	var selected: int=plan.catalog
	var handoff_budget: int=_stream.residency_limit-_stream.residency_bytes
	if plan.status=="no_solution":
		# An old failed query is not evidence about the current view. Pending is never failure.
		if request.canvas!=_last_canvas or request.size!=_last_size:
			_plan_rejected+=1;_plan_dirty=true
			return changed
		if Handoff.retain_display(_committed_cut,_committed_qualified(scale_value),current_covered,display_budget,Contract.native_page_limit() if _committed_catalog==-2 else 16): return changed
		_clear_current()
		_target={};_target_catalog=-1
		_stream.request_residency_only()
		_fallback="unsupported scale" if selected==-1 else "cut budget"
		return true
	var qualified := Handoff.native_qualified(next,scale_value) if selected==-2 else selected>=0 and Handoff.qualified(_catalogs[selected],next,scale_value)
	var covered := qualified and _cut_covers_current_view(next,selected)
	# 待提交机位不一定与当前画面相交；只有当前显示仍完整合格时才可在原预算内暂存它。
	var pending_motion := false
	var pending_bridge_scale := scale_value
	# 连续输入会每帧改变需求；不能要求后台请求与最新姿态逐位相等，否则永远接纳不了。
	# 过期请求只作为候选，按最新需求重新证明资格和覆盖后才暂存。
	if request.get("camera_demand",false) and not _camera_demand.is_empty() \
		and _committed_qualified(scale_value) and current_covered:
		var saved_canvas := _last_canvas
		var saved_size := _last_size
		var poses: Array[Transform2D]=[_camera_demand.canvas]
		var source: Variant=_source_ref.get_ref() if _source_ref!=null else null
		if next.get("motion_checkpoint",false) and typeof(source)==TYPE_OBJECT and is_instance_valid(source):
			var logical: Vector2=source.get_viewport().get_visible_rect().size
			var from_center := saved_canvas.affine_inverse()*(logical*0.5)
			var to_center: Vector2=_camera_demand.canvas.affine_inverse()*(logical*0.5)
			for fraction: float in CameraController.MAP_MOTION_FRACTIONS:
				var canvas := Transform2D(lerp_angle(saved_canvas.get_rotation(),_camera_demand.canvas.get_rotation(),fraction),Vector2.ZERO)
				canvas=canvas.scaled(Vector2.ONE*lerpf(saved_canvas.x.length(),_camera_demand.canvas.x.length(),fraction))
				canvas.origin=logical*0.5-canvas*from_center.lerp(to_center,fraction)
				poses.append(canvas)
		for canvas: Transform2D in poses:
			_last_canvas=canvas;_last_size=_camera_demand.size
			var pending_scale: float=float(_camera_demand.scale)*canvas.x.length()/_camera_demand.canvas.x.length()
			pending_motion=(Handoff.native_qualified(next,pending_scale) if selected==-2 \
				else selected>=0 and Handoff.qualified(_catalogs[selected],next,pending_scale)) \
				and _cut_covers_current_view(next,selected)
			# 每个中间机位同时核验放大前探。终点当前合格但即将过期时，
			# 继续尝试较小的一步，不能先选终点、再在循环外拒绝整个可行事务。
			if pending_motion and selected>=0 and next.get("handoff_bridge",false):
				pending_motion=Handoff.qualified(_catalogs[selected],next,
					pending_scale*exp(clampf(float(_camera_demand.get("rate",_zoom_rate))*0.25,0.0,0.7)))
			if pending_motion: pending_bridge_scale=pending_scale;break
		_last_canvas=saved_canvas;_last_size=saved_size
	var anticipated := next.has("anticipated_scale") and _committed_qualified(scale_value) and current_covered
	if not next.get("within_budget",false) or (not qualified and not pending_motion) \
		or (not covered and not anticipated and not pending_motion):
		_plan_rejected+=1;_plan_dirty=true
		return changed
	if selected>=0 and next.get("handoff_bridge",false):
		# 暂存目标属于待显示机位，不能拿仍停在近景的旧尺度否决缩远桥接。
		# 使用最新需求及其放大前探重新验资格；实际绑定仍由提交入口独立核验。
		var bridge_scale: float=pending_bridge_scale if pending_motion else scale_value
		var bridge_rate: float=_camera_demand.get("rate",_zoom_rate) if pending_motion else _zoom_rate
		if not Handoff.qualified(_catalogs[selected],next,bridge_scale*exp(clampf(bridge_rate*0.25,0.0,0.7))):
			_plan_rejected+=1;_plan_dirty=true
			return changed
	_ground_candidate_state=plan.ground_candidate
	_native_screen_bridge_state=plan.native_screen_bridge
	if plan.force_replan: _plan_dirty=true
	_plan_applied+=1
	if next.get("motion_summary",false) and selected==_committed_catalog and next.keys==_committed:
		# 已绑定的远景无需重新拆装；仍登记运动资格，停止后才能执行稳定恢复门。
		summary_motion_adoptions+=int(not _committed_cut.get("motion_summary",false))
		_committed_cut["motion_summary"]=true
		_summary_refinement_ready_at=Time.get_ticks_msec()+150
	_refresh_native_guard_metadata(next,selected)
	if next.has("lod_successor") and selected==_committed_catalog and next.keys==_committed \
		and next.get("configuration","")==_committed_cut.get("configuration","") \
		and next.get("masks",{})==_committed_cut.get("masks",{}):
		_committed_cut["lod_successor"]=next.lod_successor
		if _target_committed(): _target["lod_successor"]=next.lod_successor
	if selected==_target_catalog and _target.get("keys")==next.keys and _target.get("anticipated_scale",0.0)==next.get("anticipated_scale",0.0) \
		and (selected!=-2 or (_target.get("masks")==next.masks and _target.get("ground_images",PackedStringArray())==next.get("ground_images",PackedStringArray()))) \
		and not Handoff.prefetch_changed(_target,next,selected): return changed
	var staging := false
	_handoff_reason="native_or_initial"
	if not _committed.is_empty() and (_committed_qualified(scale_value) or _display_grace):
		var combined := _handoff_bytes(next,selected)
		staging=combined>=0 and combined<=handoff_budget
		_handoff_reason="retained" if staging else "union_budget"
	if not staging and not _committed.is_empty() and (_committed_qualified(scale_value) or _display_grace):
		if _committed_catalog>=0 and not current_covered:
			_handoff_reason="old_view";_clear_current()
		else:
			_handoff_reason="wait_union_budget";_fallback="waiting prefetch budget"
			return changed
	if not staging: _clear_current()
	else: staged_switches+=1
	_target=next;_target_catalog=selected;_plan_revision+=1
	_request_target(staging)
	_fallback="staging cut" if staging else "loading cut"
	return true


func _refresh_native_guard_metadata(next: Dictionary, selected: int) -> void:
	# 相同资源不需重新绑定，但新查询的保护范围必须及时替换旧标签，包括只改变预取的路径。
	if selected!=-2 or _target_catalog!=-2 or next.get("keys",PackedStringArray()).is_empty() \
		or _target.get("keys")!=next.get("keys") or _target.get("masks")!=next.get("masks") \
		or _target.get("configuration","")!=next.get("configuration","") \
		or _target.get("grid_pieces",{})!=next.get("grid_pieces",{}) \
		or _target.get("ground_images",PackedStringArray())!=next.get("ground_images",PackedStringArray()) \
		or _target.get("anticipated_scale",0.0)!=next.get("anticipated_scale",0.0): return
	var refresh: Array[Dictionary]=[_target]
	if _target_committed(): refresh.append(_committed_cut)
	for cut: Dictionary in refresh:
		cut["selection_stage"]=next.get("selection_stage","")
		cut["spatial_guard_px"]=next.get("spatial_guard_px",-1.0)
