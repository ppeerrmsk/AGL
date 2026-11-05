extends RefCounted
## 从真实接管首帧观测，不等地图就绪；同帧多次真实滚轮输入，截图不作帧率证据。
static func camera_wait_metrics(samples: Array) -> Dictionary:
	var maximum := 0
	var waiting := 0
	var previous: Dictionary={}
	for row: Dictionary in samples:
		var elapsed := maxi(0,int(row.input_ms)-int(previous.get("input_ms",row.input_ms)))
		var before := int(previous.get("camera_wait_started",-1))
		var current := int(row.get("camera_wait_started",-1))
		# 包含拒绝之后到真实放行的最后一帧；模态停顿由输入时钟明确单列。
		if before>=0: waiting+=elapsed;maximum=maxi(maximum,waiting)
		if current!=before or current<0:
			waiting=mini(elapsed,int(row.get("camera_wait_elapsed_ms",0))) if current>=0 else 0
			maximum=maxi(maximum,waiting)
		previous=row
	return {"max_input_wait_ms":maximum}


static func run(battle: Node, map: Node, record: Dictionary, stream_ref: WeakRef, output: String, seconds: int) -> void:
	var tree := battle.get_tree()
	var continuity_only := OS.get_environment("AGL_TOKYO_ENTRY_CONTINUITY")=="1"
	record["sampling_mode"]="input_continuity_no_readback" if continuity_only else "pixel_integrity"
	record["map_preview_only"]=bool(tree.get_meta("map_preview_only",false))
	Engine.max_fps=OS.get_environment("AGL_TOKYO_ENTRY_FPS").to_int() if OS.has_environment("AGL_TOKYO_ENTRY_FPS") else 60
	record["diagnostic_fps_cap"]=Engine.max_fps
	var diagnostic_vsync := OS.get_environment("AGL_TOKYO_ENTRY_VSYNC")
	if diagnostic_vsync in ["0","1"]: DisplayServer.window_set_vsync_mode(int(diagnostic_vsync))
	record["diagnostic_vsync_override"]=diagnostic_vsync
	record["actual_vsync"]=DisplayServer.window_get_vsync_mode()
	record["window_mode"]=DisplayServer.window_get_mode()
	record["diagnostic_exclusive"]=OS.get_environment("AGL_TOKYO_ENTRY_EXCLUSIVE")=="1"
	record["window_size"]=str(DisplayServer.window_get_size())
	record["viewport_size"]=str(battle.get_viewport().get_visible_rect().size)
	record["screen_refresh_hz"]=DisplayServer.screen_get_refresh_rate()
	record["frame_boundary"]="RenderingServer.frame_post_draw"
	var combat: Variant=null
	var started := Time.get_ticks_msec()
	var previous_trace := PerfBuckets.frame_trace_enabled
	record["stream_before_input"]=map._stream.summary()
	# 载入阶段的首次分配不混入实际移动窗口；只复位测试统计，不改调度。
	map._stream.max_texture_upload_usec=0
	if OS.get_environment("AGL_TOKYO_STREAM_AUDIT")=="1" or OS.get_environment("AGL_TOKYO_CPU_TRACE")=="1":
		for row: Dictionary in map._stream._texture_audit.values(): row.max_upload_usec=0
		PerfBuckets.configure_frame_trace(true)
	var formal_menu := OS.get_environment("AGL_TOKYO_ENTRY_MENU")=="1"
	var stable_camera := OS.get_environment("AGL_TOKYO_ENTRY_STABLE_CAMERA")=="1"
	var no_camera_input := OS.get_environment("AGL_TOKYO_ENTRY_NO_CAMERA_INPUT")=="1"
	var camera_at_city := OS.get_environment("AGL_TOKYO_ENTRY_CAMERA_AT_CITY")=="1"
	if stable_camera:
		battle._camera_ctrl.follow_enabled=false
	if camera_at_city:
		battle.camera.global_position=Vector2(-4300.0,-3700.0)
		battle.camera.force_update_scroll()
	# 先定诊断镜头，再把完全相同的战斗负载生成在镜头周围，避免玩家相机接管重置测试视野。
	if OS.get_environment("AGL_TOKYO_ENTRY_COMBAT")=="1":
		combat=preload("res://scripts/survivor/battlefield_atmosphere_experiment.gd").new()
		battle.add_child(combat)
		combat.setup(battle,battle._spawner)
		var launched: bool=combat.launch_stress_battle(36,4000.0,battle.camera.global_position)
		record["combat_fixture"]={"launched":launched,"actors_start":combat._live_combat_actor_count(),"shell_peak":0,"impact_peak":0}
		record.fail+=int(not launched or record.combat_fixture.actors_start<36)
	var active_elapsed := 0
	var previous_tick := started
	var previous_input_open := true
	var modal_frames := 0
	var selections: Array[Dictionary]=[]
	var menu_driver: Node=null
	var sampled_modal_generation := 0
	if formal_menu:
		menu_driver=preload("res://scripts/tests/tokyo_formal_menu_driver.gd").new()
		menu_driver.setup(battle,started);menu_driver.selections=selections
		tree.root.add_child(menu_driver)
	var wasd_mode := OS.get_environment("AGL_TOKYO_ENTRY_WASD")
	if OS.get_environment("AGL_TOKYO_LOD_CAPACITY")=="1": preload("res://scripts/tests/tokyo_lod_transition_audit.gd").run(map)
	var return_audit: RefCounted=preload("res://scripts/tests/tokyo_camera_return_audit.gd").new() if wasd_mode=="return" else null
	if return_audit!=null:
		if continuity_only:
			# 回中停顿专项先持续移开5秒，避免仅覆盖短距离、刚加载过的回程。
			return_audit.departure_ms=5000;return_audit.cycle_ms=8000
		if OS.get_environment("AGL_TOKYO_ENTRY_RETURN_CLOSE")=="1":
			return_audit.close_range=true
			return_audit.departure_ms=6500;return_audit.cycle_ms=9000
		# 与36演员同样只增加样本生命值，伤害/命中/战斗/移动继续，避免阵亡提前结束回程测试。
		battle.player_aircraft.params=battle.player_aircraft.params.duplicate(true)
		battle.player_aircraft.params.max_hp=1.0e9; battle.player_aircraft.hp=1.0e9
		record["return_player_fixture_hp"]=1.0e9
	var held_keys: Array=[]
	var wasd_peak := 0.0
	var wasd_distance := 0.0
	var previous_position: Vector2=battle.camera.global_position
	var wasd_segments: Array=[]
	var burst_interval := clampi(OS.get_environment("AGL_TOKYO_ENTRY_INTERVAL_MS").to_int(),16,10000) if OS.has_environment("AGL_TOKYO_ENTRY_INTERVAL_MS") else 2000
	var burst_count := clampi(OS.get_environment("AGL_TOKYO_ENTRY_WHEEL_COUNT").to_int(),1,32) if OS.has_environment("AGL_TOKYO_ENTRY_WHEEL_COUNT") else 32
	var burst_delay := maxi(0,OS.get_environment("AGL_TOKYO_ENTRY_BURST_DELAY_MS").to_int()) if OS.has_environment("AGL_TOKYO_ENTRY_BURST_DELAY_MS") else 1000
	record["burst_interval_ms"]=burst_interval
	record["burst_count"]=burst_count
	record["burst_delay_ms"]=burst_delay
	var frames: Array[Dictionary]=[]
	var last_burst := -1
	var hidden := 0
	var missing := 0
	var unqualified := 0
	var uncovered := 0
	var budget := 0
	var lag := 0
	var composite_lag := 0
	var captured := 0
	var lod_audit := OS.get_environment("AGL_TOKYO_LOD_AUDIT")=="1"
	var previous_detail := ""
	var previous_map_image: Image
	var previous_blend_age := -1.0
	var motion_summary_frames := 0
	var progress_phase := "start"
	var progress_at_ms := started
	var raster_anomaly_captured := false
	var input_count := 0
	var raster_high_zoom_strategic_frames := 0
	var raster_fallback_active := false
	var raster_fallback_episodes: Array[Dictionary] = []
	var raster_visible_tile_missing_frames := 0
	var raster_same_lod_fade_frames := 0
	var raster_peak_missing_visible_tiles := 0
	var raster_peak_fading_visible_tiles := 0
	var raster_visible_under_hlod_frames := 0
	var legacy_basemap_sprite_attached_frames := 0
	var legacy_basemap_sprite_visible_frames := 0
	var previous_screen_visible := false
	var pending_wheel_capture := false
	var map_script: Variant=map.get_script()
	var map_script_path: String=map_script.resource_path if typeof(map_script)==TYPE_OBJECT and is_instance_valid(map_script) else "native"
	var map_features: Variant=battle._map_features
	var hlod_primary: bool=bool(map_features.get("_tokyo_hlod_primary"))
	var m20_required: bool=bool(map_features.get("_tokyo_m20_required"))
	record["tokyo_map_render_mode"]="3d_hlod" if hlod_primary else "2d_fallback"
	record["tokyo_m20_required_on_entry"]=m20_required
	var raster_source: Variant=map_features.get("_raster_basemap")
	var legacy_raster_attached := typeof(raster_source)==TYPE_OBJECT and is_instance_valid(raster_source)
	var basemap_sprite_source: Variant=map_features.get("_basemap_sprite")
	var legacy_basemap_sprite_attached := typeof(basemap_sprite_source)==TYPE_OBJECT and is_instance_valid(basemap_sprite_source)
	record["legacy_raster_attached_on_entry"]=legacy_raster_attached
	record["legacy_basemap_sprite_attached_on_entry"]=legacy_basemap_sprite_attached
	record.fail+=int(not m20_required or not hlod_primary or legacy_raster_attached or legacy_basemap_sprite_attached)
	if typeof(raster_source)==TYPE_OBJECT and is_instance_valid(raster_source) and raster_source is RasterBasemapRenderer:
		var raster_manifest: Dictionary=raster_source._manifest
		record["raster_basemap"]={"manifest_path":raster_source._map_root.path_join("manifest.json"),
			"source":String(raster_manifest.get("source","")),"source_sha256":String(raster_manifest.get("source_sha256","")),
			"style_profile_id":String(raster_manifest.get("style_profile_id",""))}
	var initial_catalog: Variant=map.get("_committed_catalog")
	var previous_committed_catalog: int=int(initial_catalog) if typeof(initial_catalog)==TYPE_INT else -1
	var first_visible := -1
	var drag_step := -1
	var drag_mode := OS.get_environment("AGL_TOKYO_ENTRY_DRAG").to_lower()
	var drag_held := false
	var drag_last_input_ms := -1
	var drag_position := battle.get_viewport().get_visible_rect().size * 0.5
	var drag_input_events := 0
	var drag_input_pixels := 0.0
	var drag_camera_distance := 0.0
	var capture_step := 0
	var waiting_snapshot := false
	var gap_audit := OS.get_environment("AGL_TOKYO_GAP_AUDIT")=="1"
	var gap_captures := 0
	var images: Array[Dictionary]=[]
	var progress_writes: Array[Dictionary]=[]
	record["entry_before_draw"]={"camera":str(battle.camera.global_position),"zoom":battle.camera.zoom.x}
	record["stable_camera_diagnostic"]=stable_camera
	record["camera_input_disabled"]=no_camera_input
	record["camera_at_city_diagnostic"]=camera_at_city
	while (active_elapsed if formal_menu else Time.get_ticks_msec()-started)<seconds*1000 and Time.get_ticks_msec()-started<(seconds+30)*1000:
		var progress_now := Time.get_ticks_msec()
		progress_phase="scene_timer"
		if progress_now-progress_at_ms>=1000 or frames.is_empty():
			progress_at_ms=progress_now
			var write_started := Time.get_ticks_usec()
			var progress_file := FileAccess.open(output.path_join("entry_progress.json"),FileAccess.WRITE)
			if progress_file!=null:
				progress_file.store_string(JSON.stringify({"phase":progress_phase,"elapsed_ms":progress_now-started,"tree_paused":tree.paused,
					"active_ms":active_elapsed,"frames":frames.size(),"input_count":input_count,
					"screen_visible":map._screen.visible,"zoom":battle.camera.zoom.x},"\t"))
				progress_file.close()
			progress_writes.append({"tick_us":write_started,"duration_us":Time.get_ticks_usec()-write_started,"phase":"before_sample"})
		# 每个真实渲染帧结束后采样，避免 60 Hz 定时器漏掉 120 Hz 输出中的单帧缺口。
		await RenderingServer.frame_post_draw
		progress_phase="pixel_readback"
		var tick_us := Time.get_ticks_usec()
		var now := int(tick_us/1000)
		var elapsed := now-started
		# 正式升级选择保留输入保护与退场动画，按可操控时间继续滚轮；像素审计始终不停。
		var input_open: bool=not tree.paused and not battle.is_paused_for_upgrade and is_equal_approx(battle._camera_ctrl.cine_zoom_mult,1.0)
		var sample_input_open := input_open
		if formal_menu:
			active_elapsed=menu_driver.active_ms
			# 若暂停期间没有绘制，恢复帧仍须标记跨过模态，不能把菜单等待当卡顿。
			sample_input_open=input_open and sampled_modal_generation==menu_driver.modal_generation
			sampled_modal_generation=menu_driver.modal_generation
		elif input_open and previous_input_open: active_elapsed+=now-previous_tick
		previous_tick=now;previous_input_open=input_open
		if formal_menu and not sample_input_open: modal_frames+=1
		var input_elapsed := active_elapsed if formal_menu else elapsed
		var burst := int((input_elapsed-burst_delay)/burst_interval) if not no_camera_input and input_elapsed>=burst_delay and input_elapsed<seconds*1000 and (not formal_menu or input_open) else -1
		var burst_due: bool = burst>=0 and burst!=last_burst
		var after_wheel_burst := pending_wheel_capture
		pending_wheel_capture=false
		wasd_peak=maxf(wasd_peak,battle._camera_ctrl._wasd_velocity.length())
		wasd_distance+=previous_position.distance_to(battle.camera.global_position)
		if drag_held: drag_camera_distance += previous_position.distance_to(battle.camera.global_position)
		previous_position=battle.camera.global_position
		if typeof(combat)==TYPE_OBJECT and is_instance_valid(combat):
			record.combat_fixture.shell_peak=maxi(record.combat_fixture.shell_peak,combat._ballistic_shells.size())
			record.combat_fixture.impact_peak=maxi(record.combat_fixture.impact_peak,combat._impact_flashes.size())
		var visible: bool=map._screen.visible
		var visibility_toggled: bool=visible!=previous_screen_visible
		var valid: bool=map.display_qualified or map._display_grace
		var covered: bool=map.display_covered
		var alpha_uncovered_pixels := 0
		var native: Image = null
		if frames.is_empty() or now-progress_at_ms>=1000:
			progress_at_ms=now
			var write_started := Time.get_ticks_usec()
			var readback_progress := FileAccess.open(output.path_join("entry_progress.json"),FileAccess.WRITE)
			if readback_progress!=null:
				readback_progress.store_string(JSON.stringify({"phase":"continuity_no_readback" if continuity_only else ("eligible_pixel_readback" if visible and valid and covered else "skip_hidden_or_uncovered_readback"),"elapsed_ms":now-started,
					"active_ms":active_elapsed,"frames":frames.size(),"input_count":input_count,
					"screen_visible":visible,"qualified":valid,"covered":covered,"zoom":battle.camera.zoom.x},"\t"))
				readback_progress.close()
			progress_writes.append({"tick_us":write_started,"duration_us":Time.get_ticks_usec()-write_started,"phase":"after_sample"})
		if not continuity_only and visible and valid and covered:
			native=map._viewport.get_texture().get_image()
			if native!=null:
				var small := native.duplicate() as Image
				small.resize(160,90,Image.INTERPOLATE_NEAREST)
				alpha_uncovered_pixels=preload("res://scripts/tests/tokyo_hlod_edge_audit.gd").alpha_coverage(small).uncovered_pixels
		var raster: Variant = map_features.get("_raster_basemap")
		var basemap_sprite: Variant = map_features.get("_basemap_sprite")
		var legacy_sprite_attached := typeof(basemap_sprite)==TYPE_OBJECT and is_instance_valid(basemap_sprite)
		var legacy_sprite_visible: bool = legacy_sprite_attached and basemap_sprite.is_visible_in_tree()
		legacy_basemap_sprite_attached_frames+=int(legacy_sprite_attached)
		legacy_basemap_sprite_visible_frames+=int(legacy_sprite_visible)
		var raster_state: Dictionary = {}
		var raster_is_visible := false
		if typeof(raster)==TYPE_OBJECT and is_instance_valid(raster) and raster is RasterBasemapRenderer:
			raster_state=raster.debug_state()
			raster_is_visible=raster.is_visible_in_tree()
		var raster_visible_under_hlod := hlod_primary and raster_is_visible
		raster_visible_under_hlod_frames+=int(raster_visible_under_hlod)
		var raster_visible_tile_count := 0
		var raster_missing_visible_keys := PackedStringArray()
		var raster_fading_visible_keys := PackedStringArray()
		var raster_current_layer_alpha := 1.0
		var raster_lod := StringName(String(raster_state.get("current_lod", "")))
		if typeof(raster)==TYPE_OBJECT and is_instance_valid(raster) and raster_lod != RasterBasemapRenderer.LOD_STRATEGIC and not bool(raster_state.get("transitioning", false)):
			var current_layer: Node2D = raster._layers.get(raster_lod) as Node2D
			var current_sprites: Dictionary = raster._sprites.get(raster_lod, {}) as Dictionary
			if current_layer != null:
				raster_current_layer_alpha = current_layer.modulate.a
			for tile_key: String in raster._visible_keys(raster_lod):
				raster_visible_tile_count += 1
				var sprite: Variant = current_sprites.get(tile_key)
				if typeof(sprite) != TYPE_OBJECT or not is_instance_valid(sprite) \
						or current_layer == null or not current_layer.is_visible_in_tree() \
						or not sprite.is_visible_in_tree():
					raster_missing_visible_keys.append(tile_key)
					continue
				if sprite.modulate.a * current_layer.modulate.a < 0.995:
					raster_fading_visible_keys.append(tile_key)
		var raster_missing_visible_count := raster_missing_visible_keys.size()
		var raster_fading_visible_count := raster_fading_visible_keys.size()
		raster_visible_tile_missing_frames += int(raster_missing_visible_count > 0)
		raster_same_lod_fade_frames += int(raster_fading_visible_count > 0)
		raster_peak_missing_visible_tiles = maxi(raster_peak_missing_visible_tiles, raster_missing_visible_count)
		raster_peak_fading_visible_tiles = maxi(raster_peak_fading_visible_tiles, raster_fading_visible_count)
		var catalog_value: Variant=map.get("_committed_catalog")
		var catalog_id: int=int(catalog_value) if typeof(catalog_value)==TYPE_INT else -1
		var catalog_changed: bool = catalog_id != previous_committed_catalog
		var detail_identity := str(catalog_id)+":"+String(map._committed_cut.get("configuration",""))
		var detail_changed := lod_audit and detail_identity!=previous_detail
		previous_detail=detail_identity
		var blend_age: float=map._lod_blend_age if not map._lod_old_cut.is_empty() else -1.0
		var blend_capture := lod_audit and (blend_age>=0.0 or (blend_age<0.0 and previous_blend_age>=0.0))
		previous_blend_age=blend_age
		if catalog_changed: previous_committed_catalog = catalog_id
		var high_zoom_strategic: bool = not raster_state.is_empty() and battle.camera.zoom.x > RasterBasemapRenderer.STRATEGIC_EXIT_ZOOM \
			and raster_state.get("current_lod", "") == String(RasterBasemapRenderer.LOD_STRATEGIC)
		raster_high_zoom_strategic_frames += int(high_zoom_strategic)
		if high_zoom_strategic and not raster_fallback_active:
			raster_fallback_episodes.append({"frame": frames.size(), "ms": elapsed,
				"zoom": battle.camera.zoom.x, "raster": raster_state.duplicate(true)})
		raster_fallback_active = high_zoom_strategic
		var camera_lag: bool=not map._last_canvas.is_equal_approx(battle.get_viewport().get_canvas_transform())
		var composite_rect: Rect2=map._screen.get_global_transform_with_canvas()*map._screen.get_rect()
		var screen_rect: Rect2=battle.get_viewport().get_visible_rect()
		var composite_misaligned: bool=composite_rect.position.distance_to(screen_rect.position)>0.5 or composite_rect.end.distance_to(screen_rect.end)>0.5
		composite_lag+=int(composite_misaligned)
		var over: bool=int(map._committed_cut.get("bytes",0))>map.display_budget or int(map._committed_cut.get("triangles",0))>240000 or map._committed.size()>16
		over=over or int(map._committed_cut.get("triangles",0))+int(map._lod_old_cut.get("triangles",0))>240000 \
			or map._committed.size()+map._lod_old_cut.get("keys",[]).size()>16 or map.lod_blend_peak_bytes>map.display_budget
		var wait_started: Variant=map.get("_camera_wait_started")
		var wait_epoch := int(wait_started) if typeof(wait_started)==TYPE_INT else -1
		hidden+=int(not visible);missing+=int(alpha_uncovered_pixels>0);unqualified+=int(visible and not valid)
		motion_summary_frames+=int(map._committed_cut.get("motion_summary",false))
		uncovered+=int(visible and not covered);budget+=int(over);lag+=int(camera_lag)
		if visible and first_visible<0: first_visible=frames.size()
		var row := {"frame":frames.size(),"ms":elapsed,"input_ms":input_elapsed,"input_open":sample_input_open,"visible":visible,"missing":alpha_uncovered_pixels,
			"detail_configuration":detail_identity,"display_triangles":map._committed_cut.get("triangles",0),"display_bytes":map._committed_cut.get("bytes",0),
			"lod_blend_age":blend_age,"lod_blends":map.lod_blends,"lod_blend_budget_skips":map.lod_blend_budget_skips,
			"selection_stage":map._committed_cut.get("selection_stage",""),"target_stage":map._target.get("selection_stage",""),
			"qualified":valid,"covered":covered,"over_budget":over,"camera_lag":camera_lag,
			"composite_misaligned":composite_misaligned,"composite_rect":str(composite_rect),"screen_rect":str(screen_rect),
			"zoom":battle.camera.zoom.x,"target_zoom":battle._camera_ctrl.target_zoom,"scale":map.output_scale,
			"motion_summary":bool(map._committed_cut.get("motion_summary",false)),
			"position":[previous_position.x,previous_position.y],"wasd_speed":battle._camera_ctrl._wasd_velocity.length(),
			"guard":battle.camera.has_meta(&"map_motion_guard"),"pending_pan":battle._camera_ctrl._map_pending_pan.length(),
			"camera_wait_started":wait_epoch,"camera_wait_elapsed_ms":maxi(0,now-wait_epoch) if wait_epoch>=0 else 0,
			"reason":map.get("_handoff_reason"),"old_catalog":catalog_id,"target_catalog":map.get("_target_catalog"),
			"raster_current_lod":raster_state.get("current_lod", ""),"raster_target_lod":raster_state.get("target_lod", ""),
			"raster_transitioning":raster_state.get("transitioning", false),"raster_resident_tiles":raster_state.get("resident_tiles", 0),
			"raster_visible_tile_count":raster_visible_tile_count,
			"raster_missing_visible_count":raster_missing_visible_count,
			"raster_fading_visible_count":raster_fading_visible_count,
			"raster_current_layer_alpha":raster_current_layer_alpha,
			"legacy_raster_attached":typeof(raster)==TYPE_OBJECT and is_instance_valid(raster),
			"legacy_basemap_sprite_attached":legacy_sprite_attached,
			"legacy_basemap_sprite_visible":legacy_sprite_visible,
			"legacy_raster_visible_under_hlod":raster_visible_under_hlod,
			"high_zoom_strategic_fallback":high_zoom_strategic,
			"keys":Array(map._committed),"pending":map._stream._pending.size(),"texture_pending":map._stream._texture_jobs.size()}
		if continuity_only:
			var player_position: Vector2=battle.player_aircraft.global_position
			row["window_focused"]=DisplayServer.window_is_focused()
			row["low_processor_mode"]=OS.low_processor_usage_mode
			row["fps_cap"]=Engine.max_fps
			row["tick_us"]=tick_us;row["physics_step"]=Engine.get_physics_frames()
			row["player_position"]=[player_position.x,player_position.y]
			row["return_case"]=return_audit.active if return_audit!=null else -1
			row["return_excess_px"]=maxf(0.0,preload("res://scripts/tests/tokyo_camera_return_audit.gd").error_px(battle) \
				-float(battle.player_aircraft.speed)*CombatUnit.PIXELS_PER_METER/CameraController.FOLLOW_LERP*battle.camera.zoom.x)
		var periodic := int(elapsed/5000)>capture_step
		if periodic: capture_step=int(elapsed/5000)
		var raster_anomaly := raster_missing_visible_count > 0 or raster_fading_visible_count > 0
		var first_raster_anomaly := raster_anomaly and not raster_anomaly_captured
		var capture_requested: bool = not visible or alpha_uncovered_pixels>0 or high_zoom_strategic or catalog_changed or burst_due or after_wheel_burst or raster_anomaly
		if not continuity_only and (frames.size()<2 or visibility_toggled or detail_changed or blend_capture or (capture_requested and captured<8) or periodic or first_raster_anomaly):
			var label := "frame_%04d"%frames.size()
			row["capture"]=label if native!=null else "state_only_"+label
			row["wheel_capture_phase"]="after" if after_wheel_burst else ("before" if burst_due else "")
			if visibility_toggled:
				row["capture_reason"]="display_visibility_toggle"
			elif raster_missing_visible_count>0:
				row["capture_reason"]="raster_tile_gap"
			elif raster_fading_visible_count>0:
				row["capture_reason"]="raster_tile_fade"
			elif catalog_changed:
				row["capture_reason"]="catalog_change"
			elif high_zoom_strategic:
				row["capture_reason"]="raster_fallback"
			elif after_wheel_burst:
				row["capture_reason"]="wheel_after"
			elif burst_due:
				row["capture_reason"]="wheel_before"
			else:
				row["capture_reason"]="periodic_or_gap"
			if visibility_toggled: row["visibility_debug"]=map.debug_state()
			if native!=null:
				if detail_changed and previous_map_image!=null:
					images.append({"label":label+"_before","map":previous_map_image})
				images.append({"label":label,"map":native,"screen":battle.get_viewport().get_texture().get_image()})
			elif visibility_toggled:
				images.append({"label":label,"screen":battle.get_viewport().get_texture().get_image()})
			if raster_missing_visible_count > 0:
				row["raster_missing_visible_keys"] = raster_missing_visible_keys
			if raster_fading_visible_count > 0:
				row["raster_fading_visible_keys"] = raster_fading_visible_keys
			if first_raster_anomaly: raster_anomaly_captured=true
			captured+=1
		if lod_audit and native!=null: previous_map_image=native
		frames.append(row)
		row["sample_usec"]=Time.get_ticks_usec()-tick_us
		var input_started := Time.get_ticks_usec()
		previous_screen_visible=visible
		var partial_motion: bool=gap_audit and battle._camera_ctrl._map_pending_pan.length()*battle.camera.zoom.x>0.5
		if (typeof(wait_started)!=TYPE_INT or int(wait_started)<0) and not partial_motion:
			waiting_snapshot=false
		elif not waiting_snapshot and ((int(wait_started)>=0 and Time.get_ticks_msec()-int(wait_started)>250) or (gap_audit and gap_captures<16)):
			row["waiting_state"]={"visible":visible,"qualified":valid,"covered":covered,
				"zoom":battle.camera.zoom.x,"position":str(battle.camera.global_position),"map":map.debug_state()}
			if gap_audit and gap_captures<16:
				var jobs := {}
				for path: String in map._stream._texture_jobs: jobs[path]=map._stream._texture_jobs[path].worker.is_alive()
				var checks: Array=[]
				if not map._camera_demand.is_empty():
					var demand: Dictionary=map._camera_demand
					var demand_canvas: Transform2D=demand.canvas
					var center: Vector2=demand_canvas.affine_inverse()*(battle.get_viewport().get_visible_rect().size*0.5)
					for prepared: Dictionary in map._prepared_motion_cuts:
						var catalog: int=prepared.catalog
						if catalog==-2:
							var saved_canvas: Transform2D=map._last_canvas
							var saved_size: Vector2=map._last_size
							map._last_canvas=demand_canvas;map._last_size=demand.size
							var native_covered: bool=map._cut_covers_current_view(prepared.cut,catalog)
							map._last_canvas=saved_canvas;map._last_size=saved_size
							var missing_meshes: Array=[]
							for key: String in prepared.cut.keys:
								if map._stream.resource(key)==null: missing_meshes.append(key)
							checks.append({"catalog":catalog,"qualified":preload("res://scripts/rendering/tokyo_hlod_handoff.gd").native_qualified(prepared.cut,demand.scale),
								"covered":native_covered,"ready":map._resources_ready(prepared.cut,catalog),"missing_meshes":missing_meshes,
								"union_bytes":map._handoff_bytes(prepared.cut,catalog),"triangles":prepared.cut.get("triangles",0),"charges":prepared.cut.get("charges",0)})
							continue
						if catalog<0: continue
						checks.append({"catalog":catalog,"keys":prepared.cut.keys,
							"qualified":preload("res://scripts/rendering/tokyo_hlod_handoff.gd").qualified(map._catalogs[catalog],prepared.cut,demand.scale),
							"covered":preload("res://scripts/rendering/tokyo_hlod_handoff.gd").covers_motion_view(map._catalogs[catalog],prepared.cut,center,demand.scale,demand_canvas.get_rotation(),demand.size),
							"ready":map._resources_ready(prepared.cut,catalog),"union_bytes":map._handoff_bytes(prepared.cut,catalog)})
				row["waiting_resources"]={"target":map._target.duplicate(true),"committed":map._committed_cut.duplicate(true),
					"demand":map._camera_demand.duplicate(true),"prepared":map._prepared_motion_cuts.duplicate(true),"prepared_checks":checks,
					"meshes":map._stream._cache.keys(),"images":map._stream._textures.keys(),
					"wanted_meshes":map._stream._wanted,"wanted_images":map._stream._texture_wanted,
					"pending_meshes":map._stream._pending.keys(),"image_workers_alive":jobs}
				gap_captures+=1
			waiting_snapshot=true
	# 正式入口允许在指定延迟后注入32格滚轮突发，覆盖刚接管阶段的交接。
		if wasd_mode=="steady" or no_camera_input or return_audit!=null: burst=-1
		if return_audit!=null: return_audit.step(battle,input_elapsed,input_open)
		if not wasd_mode.is_empty() and not no_camera_input and return_audit==null:
			var directions: Array=[[KEY_D],[KEY_A],[KEY_W],[KEY_S],[KEY_W,KEY_D],[KEY_S,KEY_A],[KEY_W,KEY_A],[KEY_S,KEY_D]]
			var keys: Array=directions[int((input_elapsed-1000)/3000)%directions.size()] if input_elapsed>=1000 and (not formal_menu or input_open) else []
			if keys!=held_keys:
				wasd_segments.append({"ms":elapsed,"keys":keys.duplicate(),"position":[previous_position.x,previous_position.y]})
				for code: int in [KEY_W,KEY_A,KEY_S,KEY_D]:
					if (code in keys)==(code in held_keys): continue
					var key_event := InputEventKey.new()
					key_event.keycode=code;key_event.physical_keycode=code;key_event.pressed=code in keys
					Input.parse_input_event(key_event)
				held_keys=keys.duplicate()
		if burst>=0 and burst!=last_burst:
			last_burst=burst
			pending_wheel_capture=true
			var wheel_direction := OS.get_environment("AGL_TOKYO_ENTRY_WHEEL_DIRECTION")
			for n in burst_count:
				var event := InputEventMouseButton.new()
				event.position=battle.get_viewport().get_visible_rect().size*0.5
				if wheel_direction=="up": event.button_index=MOUSE_BUTTON_WHEEL_UP
				elif wheel_direction=="down": event.button_index=MOUSE_BUTTON_WHEEL_DOWN
				else: event.button_index=MOUSE_BUTTON_WHEEL_UP if burst%2==0 else MOUSE_BUTTON_WHEEL_DOWN
				event.pressed=true
				Input.parse_input_event(event)
				event=event.duplicate();event.pressed=false;Input.parse_input_event(event)
				input_count+=1
		# 可选实际中键拖拽与突发滚轮叠加；前一秒仍只检查正式入场。
		var next_drag := int((input_elapsed-1000)/50) if input_elapsed>=1000 and (not formal_menu or input_open) else -1
		if OS.get_environment("AGL_TOKYO_ENTRY_DRAG")=="1" and next_drag>=0 and next_drag!=drag_step:
			drag_step=next_drag
			var press := InputEventMouseButton.new()
			press.position=battle.get_viewport().get_visible_rect().size*0.5
			press.button_index=MOUSE_BUTTON_MIDDLE;press.pressed=true;Input.parse_input_event(press)
			var motion := InputEventMouseMotion.new()
			motion.position=press.position;motion.button_mask=MOUSE_BUTTON_MASK_MIDDLE
			motion.relative=Vector2(sin(drag_step*0.12),cos(drag_step*0.12))*12.0
			Input.parse_input_event(motion)
			press=press.duplicate();press.pressed=false;Input.parse_input_event(press)
		elif drag_mode=="sweep":
			if next_drag<0:
				if drag_held:
					var release := InputEventMouseButton.new()
					release.position=drag_position;release.button_index=MOUSE_BUTTON_MIDDLE
					release.pressed=false;Input.parse_input_event(release)
					drag_held=false;drag_last_input_ms=-1
			else:
				if not drag_held:
					var press := InputEventMouseButton.new()
					press.position=drag_position;press.button_index=MOUSE_BUTTON_MIDDLE
					press.pressed=true;Input.parse_input_event(press)
					drag_held=true;drag_last_input_ms=input_elapsed
				var drag_directions: Array[Vector2]=[Vector2.RIGHT,Vector2.DOWN,Vector2.LEFT,Vector2.UP]
				var direction_index := int(maxi(0,input_elapsed-1000)/5000)%drag_directions.size()
				var drag_delta_ms := clampf(float(input_elapsed-drag_last_input_ms),1.0,100.0) if drag_last_input_ms>=0 else 16.0
				var relative := drag_directions[direction_index] * (240.0*drag_delta_ms/1000.0)
				var motion := InputEventMouseMotion.new()
				drag_position += relative;motion.position=drag_position
				motion.global_position=drag_position;motion.button_mask=MOUSE_BUTTON_MASK_MIDDLE
				motion.relative=relative;Input.parse_input_event(motion)
				drag_last_input_ms=input_elapsed;drag_step+=1
				drag_input_events+=1;drag_input_pixels+=relative.length()
		row["input_usec"]=Time.get_ticks_usec()-input_started
		row["audit_end_us"]=Time.get_ticks_usec()
	if drag_held:
		var final_release := InputEventMouseButton.new()
		final_release.position=drag_position;final_release.button_index=MOUSE_BUTTON_MIDDLE
		final_release.pressed=false;Input.parse_input_event(final_release)
		drag_held=false
	for code: int in held_keys:
		var release := InputEventKey.new()
		release.keycode=code;release.physical_keycode=code;release.pressed=false;Input.parse_input_event(release)
	if return_audit!=null:
		record["space_return"]=return_audit.finish()
		record.fail+=int(record.space_return.fail)
	if continuity_only:
		record["progress_writes"]=progress_writes
		record["input_continuity"]=preload("res://scripts/tests/tokyo_input_continuity.gd").summarize(frames)
		record.fail+=int(record.input_continuity.notice_detected)
		if OS.get_environment("AGL_TOKYO_ZERO_MAP_WAIT")=="1":
			record.fail+=int(record.input_continuity.map_limited_samples>0 or record.input_continuity.stationary_pan_frames>0 or record.input_continuity.stationary_zoom_frames>0)
			record.fail+=int(record.input_continuity.max_present_gap_ms>=1000.0/30.0)
	if not wasd_mode.is_empty() and return_audit==null:
		record["wasd"]={"mode":wasd_mode,"peak_speed":wasd_peak,"distance":wasd_distance,"segments":wasd_segments}
		record.fail+=int(wasd_peak<2300.0 or wasd_distance<1000.0 or wasd_segments.size()<8)
	if formal_menu:
		record["formal_ui"]={"selections":selections,"modal_frames":modal_frames,"active_ms":active_elapsed,"wall_ms":Time.get_ticks_msec()-started,"returned_to_gameplay":previous_input_open}
		record.formal_ui["present_independent_driver"]=true
		record.formal_ui["modal_generation"]=menu_driver.modal_generation
		record.formal_ui["display_changes"]=menu_driver.display_changes.duplicate(true)
		record.fail+=int(active_elapsed<seconds*1000 or not previous_input_open)
	record["entry_burst"]={"frames":frames.size(),"hidden_frames":hidden,"missing_frames":missing,
		"composite_lag_frames":composite_lag,
		"unqualified_frames":unqualified,"uncovered_frames":uncovered,"budget_frames":budget,"camera_lag_frames":lag,
		"input_events":input_count,"first_visible_frame":first_visible,"samples":frames,"performance_sample":false}
	record.entry_burst["raster_high_zoom_strategic_frames"] = raster_high_zoom_strategic_frames
	record.entry_burst["motion_summary_frames"] = motion_summary_frames
	# 默认入口禁止速度触发粗化；实验包的历史对照仍保留独立记录。
	if preload("res://scripts/rendering/tokyo_installed_map.gd").default_motion_profile():
		record.fail+=int(motion_summary_frames>0)
	record.entry_burst["raster_high_zoom_strategic_episodes"] = raster_fallback_episodes
	record.entry_burst["raster_visible_tile_missing_frames"] = raster_visible_tile_missing_frames
	record.entry_burst["raster_same_lod_fade_frames"] = raster_same_lod_fade_frames
	record.entry_burst["raster_peak_missing_visible_tiles"] = raster_peak_missing_visible_tiles
	record.entry_burst["raster_peak_fading_visible_tiles"] = raster_peak_fading_visible_tiles
	record.entry_burst["legacy_raster_visible_under_hlod_frames"] = raster_visible_under_hlod_frames
	record["selection_trace"]=map._selection_trace.duplicate(true)
	var final_map: Dictionary=map.debug_state()
	record["stream_after_input"]=final_map.get("stream",{})
	if OS.get_environment("AGL_TOKYO_STREAM_AUDIT")=="1" or OS.get_environment("AGL_TOKYO_CPU_TRACE")=="1":
		PerfBuckets.configure_frame_trace(previous_trace)
	var wait_metrics_available := final_map.has("camera_wait_frames") and final_map.has("camera_wait_max_ms")
	record["final_map_state"]={"screen_visible":map._screen.visible,
		"return_cache":map._return_cache,"resident_index_ready":bool(map._native.get("_resident_index_ready")) if map._native!=null else false,
		"display_qualified":map.display_qualified,"display_covered":map.display_covered,
		"committed_catalog":map.get("_committed_catalog"),"camera_wait_metrics_available":wait_metrics_available,
		"cached_motion_selects":final_map.get("cached_motion_selects",0),"cached_motion_select_peak_usec":final_map.get("cached_motion_select_peak_usec",0),
		"summary_motion_commits":final_map.get("summary_motion_commits",0),"summary_motion_refinements":final_map.get("summary_motion_refinements",0),
		"summary_motion_adoptions":final_map.get("summary_motion_adoptions",0),
		"camera_wait_frames":int(final_map.get("camera_wait_frames",-1)),"camera_wait_max_ms":int(final_map.get("camera_wait_max_ms",-1))}
	# 等待地图不能变成卡死镜头；普通全程突发须仍抵达两端，等待另行量化。
	var min_zoom := INF
	var max_zoom := 0.0
	for row: Dictionary in frames:
		min_zoom=minf(min_zoom,row.zoom);max_zoom=maxf(max_zoom,row.zoom)
	record["camera_response"]={"min_zoom":min_zoom,"max_zoom":max_zoom,
		"wait_metrics_available":bool(record.final_map_state.get("camera_wait_metrics_available",false)),
		"wait_frames":record.final_map_state.get("camera_wait_frames",-1),"max_wait_ms":camera_wait_metrics(frames).max_input_wait_ms,
		"wall_wait_max_ms":record.final_map_state.get("camera_wait_max_ms",-1),"wait_clock":"controllable_input_time",
		"wait_target_ms":250,"wait_limit_ms":500,"within_wait_target":false}
	# 原I/O/上传配额下纹理仍可能需要约0.3秒；250ms目标单列，500ms防止长时间卡住。
	# 显示完整性、严格资格、预算及真实缩放可达性继续独立硬门，不能用暂停绕过。
	if bool(record.camera_response.wait_metrics_available):
		record.camera_response.within_wait_target=int(record.camera_response.max_wait_ms)<=250
		record.fail+=int(int(record.camera_response.max_wait_ms)>500)
	else:
		record.fail+=1
	# WASD 与滚轮同时输入也必须抵达目标缩放；有移动距离不能抵消缩放卡住。
	if burst_interval>=2000 and wasd_mode!="steady" and not no_camera_input and return_audit==null:
		if burst_count==32:
			# 正式步长互逆后，5.0缩远32格的目标为约0.237；按实际完整目标验可达性，不能伪称已到0.2。
			var requested_min := INF
			var requested_max := 0.0
			for row: Dictionary in frames:
				requested_min=minf(requested_min,float(row.target_zoom));requested_max=maxf(requested_max,float(row.target_zoom))
			record.camera_response["requested_zoom_range"]=[requested_min,requested_max]
			record.fail+=int(min_zoom>requested_min*1.05 or max_zoom<requested_max*0.98)
		var phases: Array[Dictionary]=[]
		for endpoint: int in range(burst_delay+burst_interval,seconds*1000,burst_interval):
			var last: Dictionary={}
			for row: Dictionary in frames:
				if int(row.input_ms)>=endpoint: break
				if formal_menu and not row.input_open: continue
				last=row
			var reached: bool=not last.is_empty() and int(last.input_ms)>=endpoint-250 and absf(float(last.zoom)/maxf(float(last.target_zoom),0.001)-1.0)<=0.02
			phases.append({"end_ms":endpoint,"zoom":last.get("zoom",0.0),"target":last.get("target_zoom",0.0),"reached":reached})
			record.fail+=int(not reached)
		record["camera_response"]["completed_phases"]=phases
	if record.has("combat_fixture"):
		record["combat_verified"]=int(record.combat_fixture.actors_start)>=36 and int(record.combat_fixture.shell_peak)>0 and int(record.combat_fixture.impact_peak)>0
		record.fail+=int(not record.combat_verified)
	record["drag_events"]=drag_step+1 if drag_mode=="1" else drag_input_events
	record["drag"]={"mode":drag_mode,"events":drag_input_events,"input_pixels":drag_input_pixels,
		"camera_distance":drag_camera_distance,"mouse_end_position":[drag_position.x,drag_position.y]}
	if drag_mode=="sweep": record.fail+=int(drag_input_events<500 or drag_input_pixels<3000.0 or drag_camera_distance<500.0)
	record.entry_burst["raster_visible_tile_missing_frames"] = raster_visible_tile_missing_frames
	record.entry_burst["raster_same_lod_fade_frames"] = raster_same_lod_fade_frames
	record.entry_burst["raster_peak_missing_visible_tiles"] = raster_peak_missing_visible_tiles
	record.entry_burst["raster_peak_fading_visible_tiles"] = raster_peak_fading_visible_tiles
	record.fail+=int(raster_visible_tile_missing_frames>0 or raster_same_lod_fade_frames>0)
	record.fail+=int(raster_visible_under_hlod_frames>0)
	record["legacy_basemap_sprite"]={"attached_frames":legacy_basemap_sprite_attached_frames,
		"visible_frames":legacy_basemap_sprite_visible_frames}
	record.fail+=int(legacy_basemap_sprite_attached_frames>0 or legacy_basemap_sprite_visible_frames>0)
	var expected_inputs := burst_count*ceili(maxf(0.0,seconds*1000.0-burst_delay)/burst_interval)
	if wasd_mode=="steady" or no_camera_input or return_audit!=null: expected_inputs=0
	record.fail+=int(hidden>0 or missing>0 or unqualified>0 or uncovered>0 or budget>0 or lag>0 or composite_lag>0 or input_count!=expected_inputs)
	for item: Dictionary in images:
		if item.has("map"): record.fail+=int(item.map.save_png(output.path_join(item.label+"_map.png"))!=OK)
		if item.has("screen"): record.fail+=int(item.screen.save_png(output.path_join(item.label+"_screen.png"))!=OK)
	images.clear()
	record["menu_return"]=await preload("res://scripts/tests/tokyo_menu_return_audit.gd").run(battle,stream_ref)
	if is_instance_valid(menu_driver): menu_driver.queue_free()
	record["stream_released"]=record.menu_return.get("stream_released",false)
	record.fail+=int(record.menu_return.fail)
	var file := FileAccess.open(output.path_join("report.json"),FileAccess.WRITE)
	if file!=null: file.store_string(JSON.stringify(record,"\t"));file.close()
	else: record.fail+=1
	print("[TokyoEntryBurst] frames=%d hidden=%d pixels=%d quality=%d uncovered=%d budget=%d lag=%d"%[frames.size(),hidden,missing,unqualified,uncovered,budget,lag])
	AudioManager.request_quit(0 if record.fail==0 else 1)
