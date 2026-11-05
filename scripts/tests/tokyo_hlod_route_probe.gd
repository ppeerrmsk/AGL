extends Node
## M1正式Loading→Survivor地图预览；不伪称实战或最终视觉通过。
const Session := preload("res://scripts/rendering/tokyo_volume_preload.gd")
const Views := preload("res://scripts/tests/tokyo_hlod_gameplay_views.gd")


func run() -> void:
	var output := OS.get_environment("AGL_TOKYO_HLOD_ROUTE_OUT")
	if not output.is_absolute_path() or DirAccess.dir_exists_absolute(output) \
		or DirAccess.make_dir_recursive_absolute(output)!=OK:
		AudioManager.request_quit(1);return
	process_mode=Node.PROCESS_MODE_ALWAYS
	var tree := get_tree()
	if OS.get_environment("AGL_TOKYO_ENTRY_BURST")=="1":
		seed(20261024)
		var audit_size := OS.get_environment("AGL_TOKYO_ENTRY_SIZE").split("x")
		tree.root.size=Vector2i(audit_size[0].to_int(),audit_size[1].to_int()) if audit_size.size()==2 else Vector2i(1920,1080)
		# 仅诊断窗口呈现阻塞；默认和正式 F5 不改变窗口模式。
		if OS.get_environment("AGL_TOKYO_ENTRY_EXCLUSIVE")=="1":
			tree.root.mode=Window.MODE_EXCLUSIVE_FULLSCREEN
		await tree.process_frame
	var play_seconds := clampi(OS.get_environment("AGL_TOKYO_HLOD_PLAY_SECONDS").to_int(),0,1200)
	tree.set_meta("bench_mode",false)
	tree.set_meta("map_preview_only",play_seconds==0 or OS.get_environment("AGL_TOKYO_HLOD_INPUT_REPLAY")=="1" or (OS.get_environment("AGL_TOKYO_ENTRY_BURST")=="1" and OS.get_environment("AGL_TOKYO_ENTRY_MENU")!="1"))
	tree.set_meta("bench_scenario","")
	tree.set_meta("bench_duration",120.0)
	var record := {"formal_route":true,"map_preview_only":true,"combat_verified":false,"views":[],"fail":0,
		"normal_camera_range":[CameraController.ZOOM_MIN,CameraController.ZOOM_MAX],"spawn_zoom":CameraController.START_ZOOM}
	var write_progress := func() -> void:
		var progress := FileAccess.open(output.path_join("loading_progress.json"),FileAccess.WRITE)
		if progress!=null: progress.store_string(JSON.stringify(record,"\t"));progress.close()
	if tree.has_meta("tokyo_f5_review"): record["editor_f5_review"]=tree.get_meta("tokyo_f5_review")
	record["package_path"]=preload("res://scripts/rendering/tokyo_installed_map.gd").package_path()
	record["explicit_package_override"]=not OS.get_environment("AGL_TOKYO_HLOD_PACKAGE").is_empty()
	record["installed_motion_profile"]=preload("res://scripts/rendering/tokyo_installed_map.gd").default_motion_profile()
	if OS.get_environment("AGL_TOKYO_ENTRY_BURST")=="1" and String(record.get("package_path","")).is_empty():
		record["fail"]=1
		record["rejection"]="current-map entry audit requires the installed Tokyo HLOD package"
		var package_failure_file := FileAccess.open(output.path_join("report.json"),FileAccess.WRITE)
		if package_failure_file!=null:
			package_failure_file.store_string(JSON.stringify(record,"\t"));package_failure_file.close()
		AudioManager.request_quit(1);return
	if OS.get_environment("AGL_TOKYO_STATIC_NATIVE")=="1" or OS.get_environment("AGL_TOKYO_COMPLETE_FOUNDATION")=="1":
		var policy := preload("res://scripts/rendering/tokyo_hlod_cache_policy.gd")
		record["candidate_pool"]=policy.candidate_limit()
		record["available_ram_at_route"]=OS.get_memory_info().get("free",0)
		var required_pool: int=policy.COMPLETE_POOL if OS.get_environment("AGL_TOKYO_COMPLETE_FOUNDATION")=="1" else policy.STATIC_POOL
		if int(record.candidate_pool)!=required_pool:
			record["fail"]=1;record["rejection"]="resident candidate capacity guard"
			var rejection := FileAccess.open(output.path_join("report.json"),FileAccess.WRITE)
			if rejection!=null: rejection.store_string(JSON.stringify(record,"\t"));rejection.close()
			AudioManager.request_quit(1);return
	var automatic_menu := OS.get_environment("AGL_TOKYO_ENTRY_MENU")=="1"
	var through_menu := OS.get_environment("AGL_TOKYO_HLOD_START_MENU")=="1" or automatic_menu
	record["started_at_main_menu"]=through_menu
	record["menu_steps"]=[]
	var city_entry := OS.get_environment("AGL_TOKYO_ENTRY_CAMERA_AT_CITY")=="1"
	var entry_position := Vector2(-4300,-3700) if city_entry else _replay_input_anchor()
	var entry_zoom := CameraController.START_ZOOM
	var custom_entry := OS.has_environment("AGL_TOKYO_ENTRY_POSE")
	if custom_entry:
		var pose := OS.get_environment("AGL_TOKYO_ENTRY_POSE").split(",")
		if pose.size()!=3 or not pose[0].is_valid_float() or not pose[1].is_valid_float() or not pose[2].is_valid_float():
			AudioManager.request_quit(1);return
		entry_position=Vector2(pose[0].to_float(),pose[1].to_float())
		entry_zoom=pose[2].to_float()
		if not is_finite(entry_zoom) or entry_zoom<CameraController.ZOOM_MIN or entry_zoom>CameraController.ZOOM_MAX:
			AudioManager.request_quit(1);return
		record["requested_entry_pose"]={"center":[entry_position.x,entry_position.y],"zoom":entry_zoom}
	var replay_entry := custom_entry or city_entry or (play_seconds>0 and OS.get_environment("AGL_TOKYO_HLOD_INPUT_REPLAY")=="1" and OS.get_environment("AGL_TOKYO_WASD_AUDIT")!="1")
	# 城区冷进入也预热实际起点，不能先预热海面、再绕过正式镜头入口瞬移到城区。
	var entry_hook := _prepare_replay_entry.bind(_replay_entry_position(entry_position,entry_zoom),entry_zoom)
	# 诊断镜头从正式Loading就预热实际起点，Survivor接管前保持同一位置。
	if replay_entry: tree.node_added.connect(entry_hook)
	if tree.change_scene_to_file("res://scenes/main_menu.tscn" if through_menu else "res://scenes/building_preloader.tscn")!=OK:
		if replay_entry: tree.node_added.disconnect(entry_hook)
		AudioManager.request_quit(1);return
	var prepared_id := 0
	var loading_started_at := Time.get_ticks_msec()
	var loading_draws: Array[Dictionary]=[]
	var loading_draw := func() -> void:
		if tree.current_scene!=null and tree.current_scene.scene_file_path=="res://scenes/building_preloader.tscn":
			loading_draws.append({"usec":Time.get_ticks_usec(),"phase":tree.current_scene.get("_loading_phase_key")})
	RenderingServer.frame_post_draw.connect(loading_draw)
	var viewport_id := 0
	var stream_ref: WeakRef
	var battle: Node
	var deadline := Time.get_ticks_msec()+(300000 if through_menu or OS.get_environment("AGL_TOKYO_STATIC_NATIVE")=="1" or OS.get_environment("AGL_TOKYO_COMPLETE_FOUNDATION")=="1" else 60000)
	var next_progress := Time.get_ticks_msec()+5000
	while Time.get_ticks_msec()<deadline:
		# 自动验收消费正式菜单入口，保留选图写入的真实战局配置。
		if automatic_menu and tree.current_scene!=null:
			var current: Node=tree.current_scene
			var scene_path: String=current.scene_file_path
			if scene_path not in record.menu_steps:
				match scene_path:
					"res://scenes/main_menu.tscn":
						record.menu_steps.append(scene_path);record["route_handoff"]={"scene":scene_path,"state":"calling","ticks_msec":Time.get_ticks_msec()};write_progress.call();current._on_survivor_pressed();record["route_handoff"]["state"]="returned";write_progress.call()
					"res://scenes/survivor_map_select.tscn":
						record.menu_steps.append(scene_path);record["route_handoff"]={"scene":scene_path,"state":"calling","ticks_msec":Time.get_ticks_msec()};write_progress.call();current._on_map_selected(0);record["route_handoff"]["state"]="returned";write_progress.call()
					"res://scenes/survivor_select.tscn":
						# 生涯存档可能锁住首卡；自动化沿用正式卡片顺序选择首架可出击机。
						var candidate_list: Variant = current.get("_list")
						var selected_index := -1
						if typeof(candidate_list) == TYPE_ARRAY:
							for index in range(candidate_list.size()):
								var candidate: Variant = candidate_list[index]
								if typeof(candidate) != TYPE_DICTIONARY:
									continue
								var aircraft: Dictionary = candidate
								if bool(aircraft.get("locked", false)) or bool(aircraft.get("dev_locked", false)):
									continue
								selected_index = index
								break
						if selected_index < 0:
							record["menu_selection_error"] = "no_unlocked_aircraft"
							record.fail += 1
							var failure_file := FileAccess.open(output.path_join("report.json"), FileAccess.WRITE)
							if failure_file != null:
								failure_file.store_string(JSON.stringify(record, "\t")); failure_file.close()
							AudioManager.request_quit(1)
							return
						record.menu_steps.append(scene_path);record["selected_aircraft_id"]=String(current._list[selected_index].get("id",""));record["route_handoff"]={"scene":scene_path,"state":"calling","ticks_msec":Time.get_ticks_msec()};write_progress.call();current._on_aircraft_selected(selected_index);record["route_handoff"]["state"]="returned";write_progress.call()
		for session: Node in tree.get_nodes_in_group(Session.GROUP):
			if is_instance_valid(session.overlay) and session.overlay.debug_state().get("hlod",false):
				prepared_id=session.overlay.get_instance_id()
				viewport_id=session.overlay._viewport.get_instance_id()
				stream_ref=weakref(session.overlay._stream)
				record["loading_state"]=session.overlay.debug_state()
				record["warm_draws"]=session.rendered_frames
				if not session.warm_pixel_probe.is_empty():
					record["preload_warm_pixel_probe"]=session.warm_pixel_probe.duplicate(true)
				record["preload_status"]=session.status
				if replay_entry:
					record["replay_preload_position"]=str(session.entry_position)
					record["replay_preload_zoom"]=session.entry_zoom
		if Time.get_ticks_msec()>=next_progress:
			next_progress=Time.get_ticks_msec()+5000
			write_progress.call()
		if tree.current_scene!=null and tree.current_scene.scene_file_path=="res://scenes/survivor_mode.tscn":
			battle=tree.current_scene;break
		await tree.process_frame
	if replay_entry: tree.node_added.disconnect(entry_hook)
	RenderingServer.frame_post_draw.disconnect(loading_draw)
	var load_draw_peak := 0.0
	var load_draw_previous := 0
	var load_phase_counts := {}
	for draw: Dictionary in loading_draws:
		if load_draw_previous>0: load_draw_peak=maxf(load_draw_peak,(int(draw.usec)-load_draw_previous)/1000.0)
		load_draw_previous=int(draw.usec)
		load_phase_counts[draw.phase]=int(load_phase_counts.get(draw.phase,0))+1
	record["loading_draws"]={"frames":loading_draws.size(),"max_gap_ms":load_draw_peak,"phases":load_phase_counts}
	record["loading_route_ms"]=Time.get_ticks_msec()-loading_started_at
	record["resident_middle_candidate"]=OS.get_environment("AGL_TOKYO_RESIDENT_MIDDLE")=="1"
	record["resident_pool_only"]=OS.get_environment("AGL_TOKYO_RESIDENCY_POOL_ONLY")=="1"
	if battle==null or not is_instance_valid(battle._map_features._tokyo_volume):
		record.fail+=1
	else:
		var map: Node = battle._map_features._tokyo_volume
		record["same_overlay"]=map.get_instance_id()==prepared_id
		record["same_viewport"]=map._viewport.get_instance_id()==viewport_id
		record["same_stream"]=stream_ref!=null and stream_ref.get_ref()==map._stream
		record.fail+=int(not record.same_stream)
		record.fail+=int(not record.same_overlay or not record.same_viewport or record.get("warm_draws",0)<2)
		if OS.get_environment("AGL_TOKYO_EDGE_AUDIT")=="1":
			record["edge_audit"]=await preload("res://scripts/tests/tokyo_hlod_edge_audit.gd").run(battle,map,output)
			record.fail+=int(record.edge_audit.fail)
			tree.change_scene_to_file("res://scenes/main_menu.tscn")
			deadline=Time.get_ticks_msec()+10000
			while stream_ref!=null and stream_ref.get_ref()!=null and Time.get_ticks_msec()<deadline: await tree.process_frame
			record["stream_released"]=stream_ref!=null and stream_ref.get_ref()==null
			record.fail+=int(not record.stream_released)
			var report_file := FileAccess.open(output.path_join("report.json"),FileAccess.WRITE)
			if report_file!=null: report_file.store_string(JSON.stringify(record,"\t"));report_file.close()
			else: record.fail+=1
			AudioManager.request_quit(0 if record.fail==0 else 1)
			return
		if play_seconds>0:
			if OS.get_environment("AGL_TOKYO_ENTRY_BURST")=="1":
				await preload("res://scripts/tests/tokyo_entry_burst_audit.gd").run(battle,map,record,stream_ref,output,play_seconds)
				return
			if OS.get_environment("AGL_TOKYO_WASD_AUDIT")=="1":
				await preload("res://scripts/tests/tokyo_wasd_audit.gd").run(battle,map,record,stream_ref,output,play_seconds)
				return
			await play_session(battle,map,record,stream_ref,output,play_seconds)
			return
		battle._camera_ctrl.follow_enabled=false
		var poses := Views.poses()
		var native_scale_views: Dictionary={}
		if OS.get_environment("AGL_TOKYO_HLOD_NORTH_FIXED_REVIEW")=="1":
			for pose: Array in [[302.274,-15568.74,1.34357124567032],[304,-15585,1.34357124567032]]:
				native_scale_views[poses.size()]=float(pose[2])
				poses.append(pose)
			poses.append([302.274,-15568.74,CameraController.ZOOM_MAX])
			record["requested_native_scales"]=native_scale_views.duplicate()
		if OS.get_environment("AGL_TOKYO_HLOD_WEST_REVIEW")=="1":
			poses.append_array([[-5442.712,-11350.26,1.28798832496007],
				[-5513.884,-12004.75,2.6671435435613],[-5513.884,-12004.75,5.0]])
			record["west_partition_review"]=true
		# 新北西低楼候选走同一个正式Loading/Survivor/overlay；追加而不替代原8幅检查。
		if OS.get_environment("AGL_TOKYO_HLOD_NORTHWEST_REVIEW")=="1":
			poses.append_array([[-7466.66666666667,-16000,1.3],[-7466.66666666667,-16000,1.6666666667],
				[-7466.66666666667,-16000,2.5],[-7466.66666666667,-16000,5.0]])
			record["northwest_massing_review"]=true
		if OS.get_environment("AGL_TOKYO_SOLID_REVIEW")=="1": poses.append_array([[-5600,-2900,1.5],[-5600,-2900,3.0],[-5600,-2900,5.0]])
		# 附加已批准R3高楼区和正常过渡尺度；不替换原八幅玩家视图。
		if OS.get_environment("AGL_TOKYO_HLOD_ART_REVIEW")=="1":
			poses.append_array([[-4300,-3700,0.8],[-4300,-3700,0.9],[-4300,-3700,1.0],
				[330,-13420,1.5],[330,-13420,3.0]])
			if OS.get_environment("AGL_TOKYO_HLOD_MASSING_REVIEW")=="1": poses.append_array([[-4300,-3700,0.5],[-4300,-3700,0.6]])
			record["highrise_and_transition_review"]=true
		var color_only := OS.get_environment("AGL_TOKYO_HLOD_COLOR_REVIEW")=="1"
		var wall_only := OS.get_environment("AGL_TOKYO_HLOD_WALL_REVIEW")=="1"
		record["wall_diagnostic_only"]=wall_only
		record["color_diagnostic_only"]=color_only
		if color_only: poses=[[-4300,-3700,CameraController.ZOOM_MIN],[9000,8000,CameraController.ZOOM_MIN]]
		# 仅核已有四个制作档的配色；不可替代正常玩家范围验收。
		if color_only and OS.get_environment("AGL_TOKYO_HLOD_PALETTE_SWEEP")=="1":
			poses=[[-4300,-3700,0.04],[-4300,-3700,0.07],[-4300,-3700,0.10],[-4300,-3700,0.20]]
			record["production_scales_not_gameplay_acceptance"]=true
		if wall_only: poses=[[330,-13420,1.0],[330,-13420,1.5],[330,-13420,2.0],[330,-13420,3.0],[-4300,-3700,0.5],[-4300,-3700,0.9]]
		for n in poses.size():
			var pose: Array = poses[n]
			var camera_scale := float(pose[2])
			# 坏点来自实际输出像素尺度；不能把窗口缩放后的camera.zoom当同一尺度。
			if native_scale_views.has(n): camera_scale*=battle.get_viewport().get_visible_rect().size.x/map._last_size.x
			battle._camera_ctrl.cine_cut_to(Vector2(pose[0],pose[1]),camera_scale)
			battle.camera.force_update_scroll()
			map._lod_clock=0.0
			for frame in 4: await tree.process_frame
			var capture_wait_started := Time.get_ticks_msec()
			deadline=Time.get_ticks_msec()+15000
			while (not Session.state_ready(map.debug_state()) or not map.debug_state().selection_current or (wall_only and not map.debug_state().cut_ready)) and Time.get_ticks_msec()<deadline:
				if map.debug_state().selection_current and map.debug_state().fallback=="unsupported scale": break
				await tree.process_frame
			for frame in 3: await tree.process_frame
			await RenderingServer.frame_post_draw
			# 就绪检查后后台可能又开始细档交接；必须在实际截图帧重新核验，不能拍过期状态。
			while Time.get_ticks_msec()<deadline:
				var capture_state: Dictionary=map.debug_state()
				if Session.state_ready(capture_state) and capture_state.selection_current and capture_state.screen_visible \
					and capture_state.display_qualified and capture_state.display_covered and (not wall_only or capture_state.cut_ready): break
				if capture_state.selection_current and capture_state.fallback=="unsupported scale": break
				await tree.process_frame
				await RenderingServer.frame_post_draw
			var name_value := "view_%02d.png" % n
			var state: Dictionary = map.debug_state()
			var error := get_viewport().get_texture().get_image().save_png(output.path_join(name_value))
			var native_name := ""
			var native_error: int = ERR_UNAVAILABLE
			var current_visible: bool = Session.state_ready(state) and state.selection_current and state.screen_visible and state.display_qualified and state.display_covered and (not wall_only or state.cut_ready)
			if current_visible:
				if wall_only:
					# 固定同一已提交几何，避免 A/B 之间流送换档；结束后逐项恢复材质。
					var previous_mode: int = battle.process_mode
					battle.process_mode=Node.PROCESS_MODE_DISABLED
					var saved_materials: Dictionary = {}
					for material: ShaderMaterial in map._page_materials:
						if material.shader==map._surface: saved_materials[material]=material.get_shader_parameter("wall_solid_color")
					var committed_keys: PackedStringArray = map._committed.duplicate()
					for enabled in [false,true]:
						for material: ShaderMaterial in saved_materials: material.set_shader_parameter("wall_solid_color",enabled)
						map._viewport.render_target_update_mode=SubViewport.UPDATE_ONCE
						await RenderingServer.frame_post_draw
						var suffix := "after" if enabled else "before"
						record.fail+=int(map._viewport.get_texture().get_image().save_png(output.path_join("wall_%02d_%s.png" % [n,suffix]))!=OK)
						await tree.process_frame
					var unchanged: bool = committed_keys==map._committed and state.committed_catalog==map.debug_state().committed_catalog and state.lod_switches==map.debug_state().lod_switches
					record.fail+=int(not unchanged)
					if not record.has("wall_pairs"): record["wall_pairs"]=[]
					record.wall_pairs.append({"pose":pose,"geometry_unchanged":unchanged,"ordinary_materials":saved_materials.size(),"state_after":map.debug_state()})
					for material: ShaderMaterial in saved_materials: material.set_shader_parameter("wall_solid_color",saved_materials[material])
					map._viewport.render_target_update_mode=SubViewport.UPDATE_ONCE
					await RenderingServer.frame_post_draw
					battle.process_mode=previous_mode
				if color_only:
					for legacy in [true,false]:
						for material: ShaderMaterial in map._page_materials: material.set_shader_parameter("legacy_tint",legacy)
						map._viewport.render_target_update_mode=SubViewport.UPDATE_ONCE
						await RenderingServer.frame_post_draw
						var suffix := "before" if legacy else "after"
						record.fail+=int(map._viewport.get_texture().get_image().save_png(output.path_join("color_%02d_%s.png" % [n,suffix]))!=OK)
						await tree.process_frame
				native_name="native_%02d.png" % n
				native_error=map._viewport.get_texture().get_image().save_png(output.path_join(native_name))
			var good: bool = current_visible and error==OK and native_error==OK
			record.fail+=int(not good)
			record.views.append({"file":name_value,"native_file":native_name,"pose":pose,"state":state,"passed":good,
				"capture_wait_ms":Time.get_ticks_msec()-capture_wait_started,"target_resources_ready":map._resources_ready(map._target,map._target_catalog),
				"target_anticipated_scale":map._target.get("anticipated_scale",0.0)})
			print("[M1 formal view] ",n," ready=",good," fallback=",state.get("fallback")," faces=",state.get("triangles"))
		# 连续实际相机运动；截图读取会干扰帧时，明确不作为性能采样。
		if not color_only and not wall_only:
			record["patrol"]=await patrol(battle,map,output)
			record["near_patrol"]=await patrol(battle,map,output,true)
			for key: String in ["patrol","near_patrol"]:
				record.fail+=int(not record[key].passed)
		var manual_seconds := clampi(OS.get_environment("AGL_TOKYO_HLOD_MANUAL_SECONDS").to_int(),0,180)
		if manual_seconds>0:
			battle._camera_ctrl.cine_cut_to(Vector2(-4300,-3700),CameraController.START_ZOOM)
			battle.camera.rotation=0.0
			await tree.create_timer(float(manual_seconds)).timeout
		tree.change_scene_to_file("res://scenes/main_menu.tscn")
		deadline=Time.get_ticks_msec()+10000
		while stream_ref!=null and stream_ref.get_ref()!=null and Time.get_ticks_msec()<deadline:
			await tree.process_frame
		record["stream_released"]=stream_ref!=null and stream_ref.get_ref()==null
		record.fail+=int(not record.stream_released)
	var file := FileAccess.open(output.path_join("report.json"),FileAccess.WRITE)
	if file!=null: file.store_string(JSON.stringify(record,"\t"));file.close()
	else: record.fail+=1
	print("[M1 formal route] fail=",record.fail," output=",output)
	AudioManager.request_quit(0 if record.fail==0 else 1)


func _replay_input_anchor() -> Vector2:
	match OS.get_environment("AGL_TOKYO_HLOD_INPUT_REGION"):
		"north", "highrise": return Vector2(330,-13420)
		"west": return Vector2(-7000,-2200)
		"north_edge": return Vector2(0,-16000)
		"east_edge": return Vector2(16000,0)
		"northeast_edge": return Vector2(16000,-16000)
	return Vector2(-5600,-2900)


func _replay_entry_position(anchor: Vector2, zoom_value: float = CameraController.START_ZOOM) -> Vector2:
	# 与CameraController的真实起始视口钳制一致，边界测试也不能预热图外镜头。
	var half_view := get_viewport().get_visible_rect().size/(2.0*zoom_value)
	var extent := Vector2.ONE*(MapBoundary.WORLD_HALF_PX-MapBoundary.CAMERA_CONTENT_INSET_PX)
	var limit := (extent-half_view).max(Vector2.ZERO)
	return anchor.clamp(-limit,limit)


func _prepare_replay_entry(node: Node, position: Vector2, zoom_value: float = CameraController.START_ZOOM) -> void:
	if node.get_script()==Session:
		# start()先加入根节点、下一帧才_begin；此时尚未构造预热相机或求图。
		node.entry_position=position
		node.entry_zoom=zoom_value
	elif node is MapBoundary:
		var battle := node.get_parent()
		if battle==null or battle.scene_file_path!="res://scenes/survivor_mode.tscn": return
		# Survivor在边界节点入树之后才claim预热地图，之前镜头已完成创建。
		battle._camera_ctrl.follow_enabled=false
		battle._camera_ctrl.set_world_bounds(node.get_camera_bounds())
		battle._camera_ctrl.cine_cut_to(position,zoom_value)
		battle.camera.force_update_scroll()


func play_session(battle: Node, map: Node, record: Dictionary, stream_ref: WeakRef, output: String, seconds: int) -> void:
	var tree := get_tree()
	# 只用于输入诊断：高帧率会掩盖按帧限额的流送吞吐，不能代替正常性能样本。
	var replay_fps := clampi(OS.get_environment("AGL_TOKYO_HLOD_REPLAY_FPS").to_int(),0,240)
	if OS.get_environment("AGL_TOKYO_HLOD_INPUT_REPLAY")=="1" and replay_fps>0:
		Engine.max_fps=replay_fps
	record["diagnostic_fps_cap"]=Engine.max_fps
	record["map_preview_only"]=OS.get_environment("AGL_TOKYO_HLOD_INPUT_REPLAY")=="1"
	record["manual_input_verified"]=false
	record["full_run_verified"]=false
	record["requested_seconds"]=seconds
	var input_anchor := _replay_input_anchor()
	record["input_region"]=OS.get_environment("AGL_TOKYO_HLOD_INPUT_REGION")
	record["input_anchor"]=str(input_anchor)
	var replay := OS.get_environment("AGL_TOKYO_HLOD_INPUT_REPLAY")=="1"
	if replay:
		var startup_at := Time.get_ticks_msec()
		var startup_deadline := startup_at+15000
		while (not Session.state_ready(map.debug_state()) or not map.display_qualified or not map.display_covered) and Time.get_ticks_msec()<startup_deadline:
			await tree.process_frame
		record["replay_startup_wait_ms"]=Time.get_ticks_msec()-startup_at
		record["replay_start_position"]=str(battle.camera.global_position)
		record["replay_start_zoom"]=battle.camera.zoom.x
		record.fail+=int(not Session.state_ready(map.debug_state()) or not map.display_qualified or not map.display_covered \
			or battle.camera.global_position.distance_to(_replay_entry_position(input_anchor))>0.1 \
			or not is_equal_approx(battle.camera.zoom.x,CameraController.START_ZOOM))
	var combat_fixture: Variant = null
	var shell_peak := 0
	var impact_peak := 0
	if OS.get_environment("AGL_TOKYO_HLOD_INPUT_REPLAY")=="1" and OS.get_environment("AGL_TOKYO_HLOD_REPLAY_COMBAT")=="1":
		combat_fixture=preload("res://scripts/survivor/battlefield_atmosphere_experiment.gd").new()
		battle.add_child(combat_fixture)
		combat_fixture.setup(battle,battle._spawner)
		var launched: bool=combat_fixture.launch_stress_battle(36,4000.0,input_anchor)
		record["combat_fixture"]={"launched":launched,"actors_start":combat_fixture._live_combat_actor_count(),"span_world":4000}
		record.fail+=int(not launched or record.combat_fixture.actors_start<36)
	var initial: Variant = battle.player_aircraft
	var start_position := Vector2.ZERO
	var player_valid := typeof(initial)==TYPE_OBJECT and is_instance_valid(initial) and initial is Aircraft
	record["player_present"]=player_valid
	if player_valid: start_position=initial.global_position
	else: record.fail+=1
	initial=null
	await RenderingServer.frame_post_draw
	record.fail+=int(get_viewport().get_texture().get_image().save_png(output.path_join("play_start.png"))!=OK)
	var started := Time.get_ticks_msec()
	if OS.get_environment("AGL_TOKYO_SELECTION_TRACE")=="1": record["selection_trace_started_msec"]=started
	var next_log := 0
	var previous := started
	var active_msec := 0
	var display_samples := 0
	var hidden_frames := 0
	var budget_frames := 0
	var unqualified_frames := 0
	var expired_frames := 0
	var uncovered_frames := 0
	var quality_failures: Array[Dictionary]=[]
	var gaps: Array[Dictionary]=[]
	var gap_active := false
	var gap_index := -1
	var input_step := -1
	var input_count := 0
	var min_input_scale := INF
	var max_input_scale := 0.0
	var input_interval := 50 if OS.get_environment("AGL_TOKYO_HLOD_FAST_INPUT")=="1" else 100
	var handoff_trace: Array[Dictionary]=[]
	var trace_at := maxi(0,OS.get_environment("AGL_TOKYO_HLOD_TRACE_START_MS").to_int())
	var selection_trace_at := trace_at
	var pixel_audit := OS.get_environment("AGL_TOKYO_HLOD_PIXEL_AUDIT")=="1"
	var pixels := {"frames":0,"hidden_frames":0,"missing_frames":0,"peak_missing_pixels":0,"captures":[],"performance_sample":false}
	var pixel_images: Array[Dictionary]=[]
	record["scripted_camera_input"]=replay
	# 真实Loading接管之后计时；截屏在测量前后，循环内不读回GPU。
	var clock := preload("res://scripts/tests/tokyo_render_clock.gd")
	var wall_previous := 0
	var wall_total := 0
	var wall_max := 0
	var wall_samples := 0
	var wall_intervals := PackedInt64Array()
	var wall_slow := 0
	var wall_spikes: Array[Dictionary]=[]
	var render_trace: RefCounted
	var previous_trace := PerfBuckets.frame_trace_enabled
	if OS.get_environment("AGL_TOKYO_LOADED_PHASE_TRACE")=="1":
		PerfBuckets.configure_frame_trace(true)
		render_trace=preload("res://scripts/tests/tokyo_render_trace.gd").new()
		render_trace.setup(get_viewport(),map._viewport,false)
	record["preloaded_residency_ready"]=map._stream.residency_ready()
	record["textures_at_play_start"]=map._stream.texture_completed
	record.fail+=int(not record.preloaded_residency_ready)
	while Time.get_ticks_msec()-started<seconds*1000 and is_instance_valid(battle) and tree.current_scene==battle:
		var wall_now := Time.get_ticks_usec()
		# process_frame信号恢复先于Survivor._process清算上一帧，复用原同帧采样时序。
		if render_trace!=null: render_trace.begin_frame((wall_now-wall_previous)/1000000.0 if wall_previous>0 else 0.0,wall_now)
		if wall_previous>0:
			var interval := wall_now-wall_previous
			wall_total+=interval;wall_max=maxi(wall_max,interval);wall_samples+=1
			if wall_intervals.size()<12000: wall_intervals.append(interval)
			wall_slow+=int(not clock.frame_within_budget(interval))
			if not clock.frame_within_budget(interval):
				clock.retain_slowest(wall_spikes,{"wall_us":interval,"elapsed_ms":Time.get_ticks_msec()-started,
					"textures_completed":map._stream.texture_completed,"texture_upload_usec":map._stream.texture_upload_usec,
					"mesh_pending":map._stream._pending.size(),"texture_pending":map._stream._texture_jobs.size()})
		wall_previous=wall_now
		var now := Time.get_ticks_msec()
		# 长回放的显式诊断只保留指定窗口，避免2048条上限吞掉后半程失效证据。
		if replay and selection_trace_at>0 and now-started<selection_trace_at: map._selection_trace.clear()
		elif map._selection_trace.size()>1024: map._selection_trace=map._selection_trace.slice(512)
		if typeof(combat_fixture)==TYPE_OBJECT and is_instance_valid(combat_fixture):
			shell_peak=maxi(shell_peak,combat_fixture._ballistic_shells.size())
			impact_peak=maxi(impact_peak,combat_fixture._impact_flashes.size())
		var step := int((now-started)/input_interval)
		if replay and not tree.paused and step!=input_step:
			input_step=step
			input_count+=1
			battle._camera_ctrl.handle_zoom_input(1.1 if step%80<40 else 1.0/1.1)
			battle._camera_ctrl.handle_drag(Vector2(sin(step*0.12),cos(step*0.12))*12.0)
		if is_instance_valid(map) and map._active:
			if replay and OS.get_environment("AGL_TOKYO_HLOD_HANDOFF_TRACE")=="1" and now-started>=trace_at and handoff_trace.size()<80:
				trace_at=now-started+50
				handoff_trace.append({"ms":now-started,"scale":map.output_scale,"reason":map._handoff_reason,
					"old_catalog":map._committed_catalog,"target_catalog":map._target_catalog,
					"old_keys":map._committed.duplicate(),"target_keys":map._target.get("keys",PackedStringArray()).duplicate(),
					"old_bytes":map._committed_cut.get("bytes",0),"target_bytes":map._target.get("bytes",0),
					"anticipated_scale":map._target.get("anticipated_scale",0.0),
					"reverse_handoff":map._reverse_handoff.duplicate(true),
					"target_prefetch":preload("res://scripts/rendering/tokyo_hlod_handoff.gd").prefetch_requests(map._catalogs,map._target,map._target_catalog),
					"handoff_bytes":map._handoff_bytes(map._target,map._target_catalog) if not map._target.is_empty() else 0,
					"old_configuration":map._committed_cut.get("configuration","hlod"),
					"target_configuration":map._target.get("configuration","hlod"),
					"mesh_wanted":map._stream._wanted.duplicate(),"mesh_cached":map._stream._cache.keys(),
					"mesh_pending":map._stream._pending.keys(),
					"texture_wanted":map._stream._texture_wanted.duplicate(),
					"texture_cached":map._stream._textures.keys(),"texture_jobs":map._stream._texture_jobs.keys(),
					"texture_retiring":map._stream._texture_retiring.keys(),
					"stream":map._stream.summary()})
			min_input_scale=minf(min_input_scale,map.output_scale)
			max_input_scale=maxf(max_input_scale,map.output_scale)
			display_samples+=1
			hidden_frames+=int(not map._screen.visible)
			unqualified_frames+=int(map._screen.visible and not map.display_qualified)
			expired_frames+=int(map._screen.visible and not map.display_qualified and not map._display_grace)
			uncovered_frames+=int(map._screen.visible and not map.display_covered)
			if map._screen.visible and (not map.display_covered or (not map.display_qualified and not map._display_grace)) and quality_failures.size()<32:
				quality_failures.append({"elapsed_ms":now-started,"scale":map.output_scale,"catalog":map._committed_catalog,
					"qualified":map.display_qualified,"covered":map.display_covered,"grace":map._display_grace,"reason":map._handoff_reason})
			budget_frames+=int(map._fallback=="cut budget" or map._stream._bytes+map._stream._reserved>map._stream.geometry_budget())
			if not map._screen.visible:
				if not record.has("first_gap_selection"):
					record["first_gap_selection"]=map._selection_trace.slice(-80).duplicate(true)
					var missing_images: Array[Dictionary]=[]
					for path: String in map._stream.visible_images:
						if map._stream._textures.has(path): continue
						var job: Dictionary=map._stream._texture_jobs.get(path,{})
						missing_images.append({"path":path,"pending":not job.is_empty(),"reading":not job.is_empty() and job.worker.is_alive(),"retiring":map._stream._texture_retiring.has(path)})
					record["first_gap_images"]=missing_images
				if not gap_active:
					gap_index=-1
					if gaps.size()<32:
						gap_index=gaps.size()
						if not record.has("gap_selections"): record["gap_selections"]=[]
						record.gap_selections.append({"start_ms":now-started,"trace":map._selection_trace.slice(-40).duplicate(true)})
						gaps.append({"start_ms":now-started,"end_ms":now-started,"frames":0,
						"position":str(battle.camera.global_position),"scale":map.output_scale,
						"target_zoom":battle._camera_ctrl.target_zoom,"reason":map._handoff_reason,
						"fallback":map._fallback,"catalog":map._target_catalog})
				gap_active=true
				if gap_index>=0:
					gaps[gap_index].end_ms=now-started
					gaps[gap_index].frames+=1
			else: gap_active=false
		if not tree.paused: active_msec+=now-previous
		previous=now
		var elapsed := now-started
		if elapsed>=next_log:
			print("[Tokyo play] seconds=",elapsed/1000," paused=",tree.paused," units=",CombatUnit.all_units.size())
			next_log=elapsed+10000
		if pixel_audit:
			# 独立正确性检查：保留同一战斗与画质，读回实际绘制帧，不作帧率证据。
			await RenderingServer.frame_post_draw
			var native: Image=map._viewport.get_texture().get_image()
			var thumbnail := native.duplicate() as Image
			thumbnail.resize(160,90,Image.INTERPOLATE_NEAREST)
			var coverage := preload("res://scripts/tests/tokyo_hlod_edge_audit.gd").alpha_coverage(thumbnail)
			pixels.frames+=1
			pixels.hidden_frames+=int(not map._screen.is_visible_in_tree())
			pixels.missing_frames+=int(coverage.uncovered_pixels>0)
			pixels.peak_missing_pixels=maxi(pixels.peak_missing_pixels,coverage.uncovered_pixels)
			if (coverage.uncovered_pixels>0 or not map._screen.is_visible_in_tree()) and pixels.captures.size()<8:
				var name_value := "pixel_gap_%02d"%pixels.captures.size()
				# 保存到回放结束后，避免PNG编码自身的数百毫秒停顿改变后续输入与缺口。
				pixel_images.append({"name":name_value,"native":native,"screen":get_viewport().get_texture().get_image()})
				pixels.captures.append({"file":name_value+".png","ms":Time.get_ticks_msec()-started,"state":map.debug_state()})
		await tree.process_frame
	record["elapsed_seconds"]=(Time.get_ticks_msec()-started)/1000.0
	if pixel_audit:
		record["pixel_audit"]=pixels
		record.fail+=int(pixels.frames==0 or pixels.hidden_frames>0 or pixels.missing_frames>0)
		for capture: Dictionary in pixel_images:
			record.fail+=int(capture.native.save_png(output.path_join(capture.name+"_native.png"))!=OK)
			record.fail+=int(capture.screen.save_png(output.path_join(capture.name+".png"))!=OK)
		pixel_images.clear()
	if render_trace!=null:
		render_trace.close()
		record["loaded_render_trace"]=render_trace.summary()
		PerfBuckets.configure_frame_trace(previous_trace)
	record["play_wall_clock"]={"samples":wall_samples,"below60":wall_slow,"max_ms":wall_max/1000.0,
		"avg_fps":wall_samples*1000000.0/maxi(1,wall_total),"vsync":DisplayServer.window_get_vsync_mode(),
		"scope":"post-loading scripted/normal play; not full-run or all-edge proof"}
	record["play_wall_spikes"]=wall_spikes
	record["play_wall_percentiles"]=clock.percentiles_usec(wall_intervals)
	record.play_wall_percentiles["complete"]=wall_intervals.size()==wall_samples
	record.fail+=int(wall_samples==0 or wall_slow>0)
	if record.has("combat_fixture"):
		record.combat_fixture["shell_peak"]=shell_peak
		record.combat_fixture["impact_peak"]=impact_peak
		record.fail+=int(shell_peak==0 or impact_peak==0)
	record["active_seconds"]=active_msec/1000.0
	record["input_coverage"]={"interval_ms":input_interval,"events":input_count,"min_scale":min_input_scale,"max_scale":max_input_scale}
	record["handoff_trace"]=handoff_trace
	if replay: record.fail+=int(input_count<int(seconds*1000/input_interval)*0.95 or max_input_scale<3.5 or min_input_scale>0.2)
	record["live_display"]={"samples":display_samples,"hidden_frames":hidden_frames,"budget_frames":budget_frames,"gaps":gaps,
		"unqualified_frames":unqualified_frames,"expired_frames":expired_frames,"uncovered_frames":uncovered_frames,"quality_failures":quality_failures}
	var display_state: Dictionary=map.debug_state()
	record.live_display["lod_grace_frames"]=display_state.get("lod_grace_frames",0)
	record.live_display["max_lod_grace_ms"]=display_state.get("max_lod_grace_ms",0)
	record.live_display["max_lod_grace_ratio"]=display_state.get("max_lod_grace_ratio",1.0)
	record.fail+=int(record.live_display.max_lod_grace_ms>100 or record.live_display.max_lod_grace_ratio>1.10)
	record.fail+=int(display_samples==0 or hidden_frames>0 or budget_frames>0 or expired_frames>0 or uncovered_frames>0)
	if is_instance_valid(battle):
		var player: Variant = battle.player_aircraft
		if typeof(player)==TYPE_OBJECT and is_instance_valid(player) and player is Aircraft:
			record["player_displacement"]=player.global_position.distance_to(start_position)
			record.fail+=int(float(record.player_displacement)<1.0)
	if is_instance_valid(map):
		record["final_map"]=map.debug_state()
		if OS.get_environment("AGL_TOKYO_SELECTION_TRACE")=="1": record["selection_trace"]=map._selection_trace.duplicate(true)
	await RenderingServer.frame_post_draw
	record.fail+=int(get_viewport().get_texture().get_image().save_png(output.path_join("play_end.png"))!=OK)
	if OS.get_environment("AGL_TOKYO_HLOD_SETTLED_CAPTURE")=="1":
		# 仅测量结束后的静止对照，不删除或改写上面的连续输入缺失样本。
		battle._camera_ctrl.cine_cut_to(battle.camera.global_position,battle.camera.zoom.x)
		var settle_deadline := Time.get_ticks_msec()+15000
		for frame in 4: await tree.process_frame
		while (not Session.state_ready(map.debug_state()) or not map.debug_state().selection_current) and Time.get_ticks_msec()<settle_deadline:
			await tree.process_frame
		record["settled_map"]=map.debug_state()
		record.fail+=int(not Session.state_ready(record.settled_map) or not record.settled_map.selection_current)
		record["settled_cut"]={"catalog":map._committed_catalog,"keys":map._committed.duplicate(),"pages":[]}
		if map._committed_catalog>=0:
			for key in map._committed:
				var row: Dictionary=map._catalogs[map._committed_catalog].rows[key]
				record.settled_cut.pages.append({"key":key,"bounds":row.bounds,"geometry_bounds":row.geometry_bounds})
		await RenderingServer.frame_post_draw
		record.fail+=int(get_viewport().get_texture().get_image().save_png(output.path_join("settled.png"))!=OK)
		record.fail+=int(map._viewport.get_texture().get_image().save_png(output.path_join("settled_native.png"))!=OK)
	tree.change_scene_to_file("res://scenes/main_menu.tscn")
	var deadline := Time.get_ticks_msec()+10000
	while stream_ref!=null and stream_ref.get_ref()!=null and Time.get_ticks_msec()<deadline: await tree.process_frame
	record["stream_released"]=stream_ref!=null and stream_ref.get_ref()==null
	record.fail+=int(not record.stream_released)
	var file := FileAccess.open(output.path_join("report.json"),FileAccess.WRITE)
	if file==null: record.fail+=1
	else: file.store_string(JSON.stringify(record,"\t"));file.close()
	print("[Tokyo play] fail=",record.fail," output=",output)
	AudioManager.request_quit(0 if record.fail==0 else 1)


func patrol(battle: Node, map: Node, output: String, near: bool = false) -> Dictionary:
	var duration := 18.0 if near else 12.0
	var center := Vector2(-5600,-2900) if near else Vector2(-4300,-3700)
	var span := Vector2(440,1600) if near else Vector2(3500,1800)
	var min_zoom := 0.7 if near else CameraController.ZOOM_MIN
	var max_zoom := CameraController.ZOOM_MAX if near else CameraController.START_ZOOM*2.0
	var result := {"performance_evidence":false,"seconds":duration,"samples":[],"frames":[],"fallback_samples":0,
		"hidden_frames":0,"budget_frames":0,"passed":false,"near":near}
	var capture := OS.get_environment("AGL_TOKYO_HLOD_NO_PATROL_CAPTURE")!="1"
	result["screenshot_readback"]=capture
	# 先到路线起点；之后不等待资源、不跳过跨档帧，连续交互必须独立过门。
	battle._camera_ctrl.cine_cut_to(center+Vector2(0,span.y),min_zoom)
	battle.camera.ignore_rotation=false
	battle.camera.rotation=0.0
	battle.camera.force_update_scroll()
	map._lod_clock=0.0
	for frame in 4: await get_tree().process_frame
	var deadline := Time.get_ticks_msec()+15000
	while (not Session.state_ready(map.debug_state()) or not map.debug_state().selection_current) and Time.get_ticks_msec()<deadline:
		await get_tree().process_frame
	for frame in 3: await get_tree().process_frame
	await RenderingServer.frame_post_draw
	while Time.get_ticks_msec()<deadline:
		var ready_state: Dictionary=map.debug_state()
		if Session.state_ready(ready_state) and ready_state.selection_current and ready_state.screen_visible and ready_state.display_qualified and ready_state.display_covered: break
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
	result["initial_state"]=map.debug_state()
	if not Session.state_ready(result.initial_state) or not result.initial_state.screen_visible or not result.initial_state.display_qualified or not result.initial_state.display_covered: return result
	var profile := OS.get_environment("AGL_TOKYO_HLOD_ROUTE_TRACE")=="1"
	var previous_trace := PerfBuckets.frame_trace_enabled
	if profile: PerfBuckets.configure_frame_trace(true)
	var start := Time.get_ticks_msec()
	var previous_frame := Time.get_ticks_usec()
	var next_capture := 0.0
	var next_trace := 1.5
	var handoff_trace: Array[Dictionary]=[]
	battle.camera.ignore_rotation=false
	while Time.get_ticks_msec()-start<int(duration*1000):
		var elapsed := (Time.get_ticks_msec()-start)/1000.0
		var phase := elapsed/duration*TAU
		var position := center+Vector2(sin(phase)*span.x,cos(phase)*span.y)
		var zoom := lerpf(min_zoom,max_zoom,(1.0-cos(phase))*0.5)
		battle._camera_ctrl.cine_cut_to(position,zoom)
		battle.camera.rotation=sin(phase)*0.2
		battle.camera.force_update_scroll()
		await get_tree().process_frame
		var state: Dictionary = map.debug_state()
		if near and OS.get_environment("AGL_TOKYO_HLOD_HANDOFF_TRACE")=="1" and elapsed>=next_trace and handoff_trace.size()<60:
			next_trace=elapsed+0.05
			handoff_trace.append({"seconds":elapsed,"scale":state.output_scale,"reason":state.handoff_reason,
				"old_catalog":map._committed_catalog,"target_catalog":map._target_catalog,
				"old_configuration":map._committed_cut.get("configuration","hlod"),"target_configuration":map._target.get("configuration","hlod"),
				"old_keys":map._committed.duplicate(),"target_keys":map._target.get("keys",PackedStringArray()).duplicate(),
				"union_bytes":map._handoff_bytes(map._target,map._target_catalog) if not map._target.is_empty() else -1,
				"stream":map._stream.summary(),"missing":map._stream._pending.keys()})
		var now := Time.get_ticks_usec()
		result.samples.append({"seconds":elapsed,"position":[position.x,position.y],"zoom":zoom,"rotation":battle.camera.rotation,
			"frame_usec":now-previous_frame,"output_scale":state.output_scale,
			"selection_usec":state.selection_usec,"binding_usec":state.binding_usec,"upload_usec":state.stream.texture_upload_usec,
			"ready":Session.state_ready(state),"fallback":state.fallback,"bytes":state.stream.total_bytes,
			"screen_visible":state.screen_visible,"handoff_reason":state.handoff_reason})
		previous_frame=now
		result.fallback_samples+=int(not state.fallback.is_empty())
		result.hidden_frames+=int(not state.screen_visible)
		result.budget_frames+=int(state.fallback=="cut budget" or state.stream.total_bytes>map._stream.residency_limit \
			or state.display_bytes>state.display_budget or state.triangles>240000 or state.active_cells>16)
		if capture and elapsed>=next_capture:
			await RenderingServer.frame_post_draw
			var name_value := ("near_patrol_%02d.png" if near else "patrol_%02d.png") % result.frames.size()
			var saved := get_viewport().get_texture().get_image().save_png(output.path_join(name_value))
			result.frames.append({"file":name_value,"seconds":elapsed,"saved":saved==OK})
			next_capture=elapsed+0.5
	result["final_state"]=map.debug_state()
	result["handoff_trace"]=handoff_trace
	if profile:
		var trace_name := "near_patrol_cpu.txt" if near else "patrol_cpu.txt"
		var trace_file := FileAccess.open(output.path_join(trace_name),FileAccess.WRITE)
		if trace_file!=null: trace_file.store_string(PerfBuckets.format_frame_trace_dump());trace_file.close()
		result["diagnostic_cpu_trace"]=trace_name
		PerfBuckets.configure_frame_trace(previous_trace)
	result.passed=not result.samples.is_empty() and result.hidden_frames==0 and result.budget_frames==0
	for frame: Dictionary in result.frames: result.passed=result.passed and frame.saved
	return result
