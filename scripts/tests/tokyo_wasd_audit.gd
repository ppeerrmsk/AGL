extends RefCounted
const StaticOverlay := preload("res://scripts/rendering/tokyo_static_hlod_overlay.gd")
const MapProjection := preload("res://scripts/experiments/volume_projection.gd")
## 真实键盘状态/滚轮、每个绘制帧透明缺口检查；GPU读回有观测成本，不作性能证据。
static func anchor_for_route(route: String) -> Vector2:
	# 未知拼写必须拒绝，不能默默在城区跑完却声称验过边缘。
	return {"":Vector2(-5600,-2900),
		"northeast_edge":Vector2(16000,-16000),"southwest_edge":Vector2(-16000,16000),
		"northwest_edge":Vector2(-16000,-16000),"southeast_edge":Vector2(16000,16000),
		"north_edge":Vector2(0,-16000),"south_edge":Vector2(0,16000),
		"west_edge":Vector2(-16000,0),"east_edge":Vector2(16000,0)}.get(route,Vector2(INF,INF))


static func layer_gaps(roots: Array, cut: Dictionary, view: Rect2, canvas: Transform2D, logical: Vector2) -> Dictionary:
	# 仅失败截图时调用；复用正式完整性原语，不另设较宽松的覆盖标准。
	var selected: Dictionary={}
	var entries: Array=[]
	for entry: Dictionary in cut.get("entries",[]):
		var bits := 0
		for kind in 3:
			if entry.mask[kind]: bits|=1<<kind
		selected[entry.path]=int(selected.get(entry.path,0))|bits
		entries.append({"path":entry.path,"mask":Array(entry.mask)})
	var ray := MapProjection.ground_basis(canvas,deg_to_rad(38)).inverse()*MapProjection.camera_basis(canvas,deg_to_rad(38)).z
	var roof := -Vector2(ray.x,ray.z)/ray.y
	var gaps: Array[Dictionary]=[]
	for root: Dictionary in roots:
		for kind in 3: _collect_layer_gaps(root,selected,view,canvas,logical,roof,kind,gaps)
	return {"configuration":cut.get("configuration",""),"ground_tree":cut.get("ground_tree",false),
		"canvas":[canvas.x.x,canvas.x.y,canvas.y.x,canvas.y.y,canvas.origin.x,canvas.origin.y],
		"logical":[logical.x,logical.y],"view":[view.position.x,view.position.y,view.size.x,view.size.y],
		"entries":entries,"missing_leaves":gaps,"limit_reached":gaps.size()>=8,"root_count":roots.size()}


static func _collect_layer_gaps(entry: Dictionary, selected: Dictionary, view: Rect2, canvas: Transform2D, logical: Vector2, roof: Vector2, kind: int, gaps: Array[Dictionary]) -> void:
	if gaps.size()>=8 or preload("res://scripts/rendering/tokyo_hlod_native.gd")._layer_complete(entry,selected,view,canvas,logical,roof,kind): return
	if not entry.get("children",[]).is_empty():
		for child: Dictionary in entry.children: _collect_layer_gaps(child,selected,view,canvas,logical,roof,kind,gaps)
		return
	var box: AABB=entry.boxes[kind]
	var projected := preload("res://scripts/rendering/tokyo_cells_overlay.gd").projected_layer_bounds(box,roof,Vector2.ZERO)
	gaps.append({"path":entry.path,"layer":kind,"triangles":entry.triangles[kind],
		"box":[box.position.x,box.position.y,box.position.z,box.size.x,box.size.y,box.size.z],
		"projected":[projected.position.x,projected.position.y,projected.size.x,projected.size.y],
		"selected_mask":selected.get(entry.path,0)})


static func layer_gap_snapshot(map: Node, view: Rect2, canvas: Transform2D, logical: Vector2) -> Dictionary:
	if map._committed_catalog!=-2: return {"native":false}
	var cut: Dictionary=map._committed_cut
	var configuration: String=cut.get("configuration","")
	var roots: Array=[]
	if cut.get("ground_tree",false) and map._native._ground_roots.has(configuration): roots=map._native._ground_roots[configuration]
	elif map._native._partition_roots.has(configuration): roots=map._native._partition_roots[configuration]
	elif map._native.catalog!=null and map._native.catalog.configurations.has(configuration): roots=map._native.catalog.configurations[configuration]
	var result := layer_gaps(roots,cut,view,canvas,logical)
	var previous_canvas: Transform2D=map._last_canvas
	result["overlay_canvas"]=[previous_canvas.x.x,previous_canvas.x.y,previous_canvas.y.x,previous_canvas.y.y,previous_canvas.origin.x,previous_canvas.origin.y]
	result["recorded_canvas_covered"]=map._native.covers_visible_layers(cut,view,canvas,logical)
	result["native"]=true
	result["bound_nodes"]=map._nodes.size()
	return result


static func run(battle: Node, map: Node, record: Dictionary, stream_ref: WeakRef, output: String, seconds: int) -> void:
	var tree := battle.get_tree()
	Engine.max_fps=60
	var ground_costs := {}
	for level in 6:
		var components := {}
		var faces := 0
		for root: Dictionary in map._native.catalog.configurations["lod%d_full"%level]:
			var row: Dictionary=map._native.pages[root.path]
			var path: String=row.mapping[2][0]
			components[path]=int(row.components[path].bytes)
			faces+=int(root.triangles[2])
		var bytes := 0
		for value: int in components.values(): bytes+=value
		ground_costs[level]={"bytes":bytes,"triangles":faces,"components":components.size()}
	record["ground_costs"]=ground_costs
	var route := OS.get_environment("AGL_TOKYO_WASD_ROUTE")
	var anchor := anchor_for_route(route)
	if not anchor.is_finite():
		push_error("Tokyo WASD route rejected: " + route)
		tree.quit(1)
		return
	var start_scale := 0.65
	if OS.get_environment("AGL_TOKYO_WASD_SCALE").is_valid_float():
		start_scale=clampf(float(OS.get_environment("AGL_TOKYO_WASD_SCALE")),0.0973,5.0)
	record["wasd_route"]={"anchor":str(anchor),"scale":start_scale,"route":route,"seconds":seconds}
	battle._camera_ctrl.cine_cut_to(anchor,start_scale)
	battle._camera_ctrl.follow_enabled=false
	await tree.create_timer(2.0).timeout
	# 复用已有加载后诊断开关；峰值携带真实配置/保护带，不能用最后姿态代替慢查询。
	var previous_trace := PerfBuckets.frame_trace_enabled
	if OS.get_environment("AGL_TOKYO_LOADED_PHASE_TRACE")=="1": PerfBuckets.configure_frame_trace(true)
	var started := Time.get_ticks_msec()
	var held := 0
	var wheel_step := -1
	var frames := 0
	var native_ground_frames := 0
	var missing := 0
	var hidden := 0
	var peak_fraction := 0.0
	var peak_speed := 0.0
	var distance := 0.0
	var minimum_zoom := INF
	var maximum_zoom := 0.0
	var uncovered_cut_frames := 0
	var covered_cut_gap_frames := 0
	var camera_lag_frames := 0
	var transitions: Array[Dictionary]=[]
	var geometry_gaps: Array[Dictionary]=[]
	var previous_keys := PackedStringArray()
	var previous_wanted := PackedStringArray()
	var handoff_trace := OS.get_environment("AGL_TOKYO_HANDOFF_TRACE")=="1"
	var plans: Array=[]
	var watched_paths := PackedStringArray([
		"res://resources/maps/tokyo_playable/resident_foundation_c1/assets/837810f0a5415470e2497aab22d0b35774e17de0c9cea8445ee8b514459a92f8.res",
		"C:/Users/noelu/Documents/AGL/tmp/tokyo-joined-grid-1280-0256-01/grid_01281.res"])
	var watched_states: Dictionary={}
	var watched_events: Array=[]
	var plan_identities: Dictionary={}
	var plan_components: Dictionary={}
	var previous: Vector2=battle.camera.global_position
	var snapshots: Array[Dictionary]=[]
	var static_map := map as StaticOverlay
	var static_cut: Dictionary={"configuration":"lod5_full","entries":[],"keys":PackedStringArray()}
	var static_catalog: Dictionary={"rows":{}}
	if static_map!=null:
		for entry: Dictionary in static_map._static_leaves:
			var selected := entry.duplicate()
			selected.mask=[true,true,true]
			static_cut.entries.append(selected)
			if int(entry.triangles[2])==0: continue
			var box: AABB=entry.boxes[2]
			static_catalog.rows[entry.path]={"bounds":[box.position.x,box.position.z,box.end.x,box.end.z]}
		static_cut.keys=PackedStringArray(static_catalog.rows.keys())
	var static_frames := 0
	var budget_frames := 0
	var budget_samples: Array[Dictionary]=[]
	var peak_display_faces := 0
	var peak_display_cells := 0
	while Time.get_ticks_msec()-started<seconds*1000:
		var elapsed := Time.get_ticks_msec()-started
		var key: int=[KEY_D,KEY_S,KEY_A,KEY_W][(elapsed/3000)%4]
		if held!=key:
			for code: int in [held,key]:
				if code==0: continue
				var event := InputEventKey.new()
				event.keycode=code;event.physical_keycode=code;event.pressed=code==key
				Input.parse_input_event(event)
			held=key
		if elapsed>=12000 and elapsed/100!=wheel_step:
			wheel_step=elapsed/100
			var event := InputEventMouseButton.new()
			event.position=battle.get_viewport().get_visible_rect().size*0.5
			event.button_index=MOUSE_BUTTON_WHEEL_UP if (elapsed/2000)%2==0 else MOUSE_BUTTON_WHEEL_DOWN
			event.pressed=true
			Input.parse_input_event(event)
			event=event.duplicate();event.pressed=false
			Input.parse_input_event(event)
		await RenderingServer.frame_post_draw
		frames+=1
		native_ground_frames+=int(not map._committed_cut.get("ground_images",PackedStringArray()).is_empty())
		minimum_zoom=minf(minimum_zoom,battle.camera.zoom.x)
		maximum_zoom=maxf(maximum_zoom,battle.camera.zoom.x)
		distance+=previous.distance_to(battle.camera.global_position)
		previous=battle.camera.global_position
		peak_speed=maxf(peak_speed,battle._camera_ctrl._wasd_velocity.length())
		hidden+=int(not map._screen.visible)
		var native: Image=map._viewport.get_texture().get_image()
		var small := native.duplicate() as Image
		small.resize(160,90,Image.INTERPOLATE_NEAREST)
		var coverage := preload("res://scripts/tests/tokyo_hlod_edge_audit.gd").alpha_coverage(small)
		var gap: bool=coverage.uncovered_pixels>0 or not map._screen.visible
		var canvas: Transform2D=battle.get_viewport().get_canvas_transform()
		var inverse := canvas.affine_inverse()
		var logical: Vector2=battle.get_viewport().get_visible_rect().size
		var view := Rect2(inverse*Vector2.ZERO,Vector2.ZERO)
		for point: Vector2 in [Vector2(logical.x,0),logical,Vector2(0,logical.y)]: view=view.expand(inverse*point)
		view=view.intersection(map._archive.bounds)
		var catalog: Dictionary={"rows":{}}
		var cut: Dictionary=map._committed_cut
		var static_active := static_map!=null and static_map._static_visible
		static_frames+=int(static_active)
		if static_active:
			cut=static_cut;catalog=static_catalog
		elif map._committed_catalog>=0:
			catalog=map._catalogs[map._committed_catalog]
		else:
			for entry: Dictionary in cut.get("entries",[]):
				if not entry.mask[2]: continue
				var box: AABB=entry.boxes[2]
				catalog.rows[entry.path]={"bounds":[box.position.x,box.position.z,box.end.x,box.end.z]}
			cut={"keys":PackedStringArray(catalog.rows.keys())}
		var uncovered: Array[Rect2]=preload("res://scripts/rendering/tokyo_hlod_handoff.gd").uncovered_view(catalog,cut,view)
		var cut_covered := uncovered.is_empty()
		# 固定层不能借用上次远景动态cut作证明；同时核实际树与绘制层，alpha检查不变。
		var display_tree_covered := false
		if static_active: display_tree_covered=map._native.covers_ground(cut,view,canvas,logical)
		else: display_tree_covered=map._cut_covers_current_view(map._committed_cut,map._committed_catalog)
		if static_active: cut_covered=cut_covered and display_tree_covered and static_map._static_ready and static_map._camera.cull_mask==2
		else: cut_covered=cut_covered and display_tree_covered
		# 与debug_state同源计费字段；不得为每帧预算检查触发全常驻集residency_ready扫描。
		var faces := int(static_map._static_cost.get("triangles",0)) if static_active else (int(map._committed_cut.get("triangles",0)) if not map._committed.is_empty() else 0)
		var cells: int=int(static_map._static_cost.get("active",0)) if static_active else map._committed.size()
		var display_bytes := int(static_map._static_cost.get("bytes",0)) if static_active else int(map._committed_cut.get("bytes",0))
		peak_display_faces=maxi(peak_display_faces,faces);peak_display_cells=maxi(peak_display_cells,cells)
		var over_budget: bool=faces>240000 or cells>16 or display_bytes>map.display_budget
		budget_frames+=int(over_budget)
		if over_budget and budget_samples.size()<16:
			budget_samples.append({"ms":elapsed,"position":str(previous),"zoom":battle.camera.zoom.x,"static":static_active,"faces":faces,"cells":cells,"bytes":display_bytes})
		if not cut_covered and geometry_gaps.size()<256:
			var regions: Array=[]
			for region: Rect2 in uncovered:
				regions.append({"position":[region.position.x,region.position.y],"size":[region.size.x,region.size.y],"pixel_size":[region.size.x*map.output_scale,region.size.y*map.output_scale]})
			geometry_gaps.append({"ms":elapsed,"regions":regions})
		var camera_lag: bool=not canvas.is_equal_approx(map._last_canvas)
		uncovered_cut_frames+=int(not cut_covered)
		covered_cut_gap_frames+=int(cut_covered and gap)
		camera_lag_frames+=int(camera_lag)
		var target_keys: PackedStringArray=map._target.get("keys",PackedStringArray())
		# 显式短回放诊断，只记录既有选择结果，不额外调用求解器或改变请求顺序。
		if handoff_trace and watched_events.size()<512:
			for watched: String in watched_paths:
				var observed := {"wanted":watched in map._stream._wanted,"pending":map._stream._pending.has(watched),"cached":map._stream._cache.has(watched),"failure":map._stream._failures.get(watched,"")}
				if watched_states.get(watched,{})!=observed:
					watched_states[watched]=observed
					watched_events.append({"ms":elapsed,"path":watched,"state":observed,"reason":map._handoff_reason,"pending_count":map._stream._pending.size(),"reserved":map._stream._reserved,"bytes":map._stream._bytes})
		if handoff_trace and plans.size()<1024:
			var predicted_keys: PackedStringArray=map._target.get("prefetch_keys",PackedStringArray())
			var images: PackedStringArray=map._target.get("ground_images",PackedStringArray())
			if plans.is_empty() or plans.back().keys!=target_keys or plans.back().predicted!=predicted_keys \
				or plans.back().images!=images:
				for page_key: String in Array(target_keys)+Array(predicted_keys):
					if not plan_identities.has(page_key) and map._native.pages.has(page_key):
						plan_identities[page_key]=map._native.pages[page_key].get("canonical_identity",{}).duplicate(true)
						plan_components[page_key]=map._native.pages[page_key].components.keys()
				plans.append({"ms":elapsed,"center":str(previous),"scale":map.output_scale,
					"pan":str(map._pan_velocity),"zoom_rate":map._zoom_rate,"catalog":map._target_catalog,
					"configuration":map._target.get("configuration",""),"bytes":map._target.get("bytes",0),
					"guard":map._target.get("spatial_guard_px",0),"keys":target_keys.duplicate(),"images":images.duplicate(),
					"predicted_catalog":map._target.get("prefetch_catalog",-1),"predicted":predicted_keys.duplicate(),
					"predicted_extra":map._target.get("prefetch_extra",[]).duplicate(true),
					"wanted_meshes":map._stream._wanted.duplicate(),"wanted_images":map._stream._texture_wanted.duplicate(),
					"pending_meshes":map._stream._pending.keys(),"pending_images":map._stream._texture_jobs.keys()})
		if target_keys!=previous_keys:
			var parts := {}
			for key_path: String in target_keys:
				var logical_path: String=key_path if map._target_catalog==-2 else map._catalogs[map._target_catalog].rows[key_path].native_geometry.path
				for part: String in map._geometry[logical_path].get("components",{logical_path:{}}): parts[part]=true
			var not_prefetched := 0
			var not_cached := 0
			for part: String in parts:
				not_prefetched+=int(part not in previous_wanted)
				not_cached+=int(not map._stream._cache.has(part))
			transitions.append({"ms":elapsed,"catalog":map._target_catalog,"parts":parts.size(),"not_prefetched":not_prefetched,"not_cached":not_cached,"keys":target_keys.duplicate()})
			previous_keys=target_keys.duplicate()
		previous_wanted=map._stream._wanted.duplicate()
		missing+=int(gap)
		peak_fraction=maxf(peak_fraction,coverage.uncovered_fraction)
		if (gap or not cut_covered) and snapshots.size()<8 and (snapshots.is_empty() or elapsed-int(snapshots.back().ms)>=1000):
			var layer_detail := layer_gap_snapshot(map,view,canvas,logical)
			var target_status := {"covers_view":map._target_covers_current_view(),"missing_meshes":[],"missing_images":[]}
			# 只在有界失败快照保存身份，不复制Resource，不在游戏帧里额外求切面。
			var exact_center: Vector2=inverse*(logical*0.5)
			target_status["resident_snapshot"]={"center":[exact_center.x,exact_center.y],"scale":map.output_scale,
				"size":[map._last_size.x,map._last_size.y],"angle":canvas.get_rotation(),
				"components":map._stream._cache.keys(),"textures":map._stream._textures.keys()}
			var target_parts: Dictionary={}
			for key_path: String in target_keys:
				var logical_path: String=key_path if map._target_catalog==-2 else map._catalogs[map._target_catalog].rows[key_path].native_geometry.path
				for part: String in map._geometry[logical_path].get("components",{logical_path:{}}): target_parts[part]=true
			var pending_parts: Array=[]
			for part: String in map._stream._pending:
				var worker: Thread=map._stream._mesh_checks.get(part)
				pending_parts.append({"path":part,"current_target":target_parts.has(part),"wanted_rank":map._stream._wanted.find(part),
					"pinned":part in map._stream._pins,"load_status":ResourceLoader.load_threaded_get_status(part),
					"digest_pending":worker!=null,"digest_alive":worker!=null and worker.is_alive(),"bytes":map._stream._pending[part]})
			target_status["pending_meshes"]=pending_parts
			target_status["configuration"]=map._target.get("configuration","")
			target_status["ground_max_scale"]=str(map._target.get("ground_max_scale",INF))
			target_status["ground_images"]=map._target.get("ground_images",PackedStringArray())
			# 原生混合地面的纹理也必须记录，不能把HLOD纹理列表为空误读成不欠图片。
			for path: String in map._target.get("ground_images",PackedStringArray()):
				if map._stream._textures.has(path): continue
				var stage := "not_requested"
				if map._stream._texture_jobs.has(path): stage="background_read" if map._stream._texture_jobs[path].worker.is_alive() else "waiting_upload"
				elif map._stream._texture_retiring.has(path): stage="retiring"
				target_status.missing_images.append({"path":path,"stage":stage,"native_ground":true,"wanted":path in map._stream._texture_wanted})
			# 仅首个失败后的诊断，不改显示/请求；检查有界三档是否遗漏可用完整切面。
			if snapshots.is_empty() and OS.get_environment("AGL_TOKYO_GAP_CATALOG_AUDIT")=="1":
				var alternatives: Array=[]
				for candidate in map._catalogs.size():
					var ready_cut := preload("res://scripts/rendering/tokyo_hlod_cached_cut.gd").select(map._catalogs[candidate],inverse*(logical*0.5),map.output_scale,canvas.get_rotation(),Vector2(map._last_size),map._geometry,map._stream._cache,map._stream._textures)
					alternatives.append({"catalog":candidate,"ready":not ready_cut.is_empty(),"keys":ready_cut.get("keys",[]),"bytes":ready_cut.get("bytes",0),
						"union":map._handoff_bytes(ready_cut,candidate) if not ready_cut.is_empty() else -1})
				record["first_gap_catalog_audit"]={"ms":elapsed,"diagnostic_only":true,"candidates":alternatives}
			for key_path: String in target_keys:
				var logical_path: String=key_path if map._target_catalog==-2 else map._catalogs[map._target_catalog].rows[key_path].native_geometry.path
				for part: String in map._geometry[logical_path].get("components",{logical_path:{}}):
					if not map._stream._cache.has(part):
						target_status.missing_meshes.append({"path":part,"wanted":part in map._stream._wanted,"pending":map._stream._pending.has(part),"digest_pending":map._stream._mesh_checks.has(part)})
				if map._target_catalog>=0:
					var path: String=map._catalogs[map._target_catalog].rows[key_path].native_texture.path
					if not map._stream._textures.has(path):
						var stage := "not_requested"
						if map._stream._texture_jobs.has(path):
							stage="background_read" if map._stream._texture_jobs[path].worker.is_alive() else "waiting_upload"
						elif map._stream._texture_retiring.has(path): stage="retiring"
						target_status.missing_images.append({"path":path,"wanted":path in map._stream._texture_wanted,"pending":map._stream._texture_jobs.has(path),"retiring":map._stream._texture_retiring.has(path),"bytes":map._textures[path].charge,"stage":stage})
			var index := snapshots.size()
			native.save_png(output.path_join("gap_%02d_native.png"%index))
			battle.get_viewport().get_texture().get_image().save_png(output.path_join("gap_%02d.png"%index))
			snapshots.append({"ms":elapsed,"position":str(previous),"fraction":coverage.uncovered_fraction,"state":map.debug_state(),"display_tree_covered":display_tree_covered,"static_display":static_active,
				"cut_covered":cut_covered,"camera_lag":camera_lag,"view":str(view),"committed_keys":map._committed.duplicate(),"target_keys":target_keys.duplicate(),"target_status":target_status,"layer_detail":layer_detail})
	if handoff_trace: record["handoff_trace"]={"diagnostic_only":true,"limit":1024,"plans":plans,"identities":plan_identities,"components":plan_components,"watched_events":watched_events,"watched_limit":512}
	var release := InputEventKey.new()
	release.keycode=held;release.physical_keycode=held;release.pressed=false
	Input.parse_input_event(release)
	record["wasd"]={"frames":frames,"missing_frames":missing,"hidden_frames":hidden,"peak_uncovered_fraction":peak_fraction,
		"peak_screen_speed":peak_speed,"world_distance":distance,"snapshots":snapshots,"performance_sample":false,
		"uncovered_cut_frames":uncovered_cut_frames,"covered_cut_gap_frames":covered_cut_gap_frames,"camera_lag_frames":camera_lag_frames}
	record.wasd["transitions"]=transitions
	record.wasd["native_ground_frames"]=native_ground_frames
	record.wasd["static_frames"]=static_frames
	record.wasd["budget_frames"]=budget_frames
	record.wasd["continuous_layer_coverage"]=true
	record.wasd["budget_samples"]=budget_samples
	record.wasd["peak_display_faces"]=peak_display_faces
	record.wasd["peak_display_cells"]=peak_display_cells
	record.wasd["geometry_gaps"]=geometry_gaps
	record.wasd["final_stream"]=map._stream.summary()
	record.wasd["camera_zoom_range"]=[minimum_zoom,maximum_zoom]
	record.wasd["final_map"]=map.debug_state()
	# 有界诊断只在路线结束导出，不能把累计绑定耗时冒充慢帧归因。
	if OS.get_environment("AGL_TOKYO_LOADED_PHASE_TRACE")=="1":
		var trace_file := FileAccess.open(output.path_join("wasd_cpu_trace.txt"),FileAccess.WRITE)
		if trace_file!=null:
			trace_file.store_string(PerfBuckets.format_frame_trace_dump());trace_file.close()
			record.wasd["diagnostic_cpu_trace"]="wasd_cpu_trace.txt"
	PerfBuckets.frame_trace_enabled=previous_trace
	record.wasd["overlay_sha256"]=FileAccess.get_sha256("res://scripts/rendering/tokyo_hlod_overlay.gd")
	# 测量结束后绑定各消费者版本，不能只用overlay摘要证明整个调度代码一致。
	record.wasd["runtime_sha256"]={}
	for name_value: String in ["tokyo_hlod_overlay","tokyo_static_hlod_overlay","tokyo_hlod_native","tokyo_hlod_stream","tokyo_component_stream","tokyo_cell_stream","tokyo_hlod_handoff","tokyo_hlod_manifest","tokyo_hlod_cached_cut","tokyo_hlod_cache_policy","tokyo_volume_preload"]:
		record.wasd.runtime_sha256[name_value]=FileAccess.get_sha256("res://scripts/rendering/%s.gd"%name_value)
	record.fail+=int(missing>0 or uncovered_cut_frames>0 or budget_frames>0 or frames<seconds*15 or peak_speed<2300 or distance<1000)
	tree.change_scene_to_file("res://scenes/main_menu.tscn")
	var deadline := Time.get_ticks_msec()+10000
	while stream_ref.get_ref()!=null and Time.get_ticks_msec()<deadline: await tree.process_frame
	record["stream_released"]=stream_ref.get_ref()==null
	record.fail+=int(not record.stream_released)
	var file := FileAccess.open(output.path_join("report.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(record,"\t"));file.close()
	print("[Tokyo WASD] frames=",frames," missing=",missing," hidden=",hidden," speed=",peak_speed," fail=",record.fail)
	tree.quit(1 if record.fail else 0)
