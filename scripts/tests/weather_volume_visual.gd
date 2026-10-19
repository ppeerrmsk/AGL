extends Node
## 固定天气、真实 Survivor 地图/单位/HUD；多机位截图不冒充性能样本。
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run.call_deferred()

func _run() -> void:
	var tree := get_tree()
	tree.current_scene = null
	OS.set_environment("AGL_WEATHER_VOLUME","on")
	DisplayServer.window_set_size(Vector2i(1600,900))
	for map_name in ["desert_railway","ocean_islands"]:
		if OS.get_environment("AGL_WEATHER_DUST") == "1" and map_name != "desert_railway":
			continue
		tree.set_meta("ugc_map_path","res://resources/maps/%s_preview.aglmap" % map_name)
		tree.set_meta("map_preview_only",true)
		tree.set_meta("bench_scenario","map_raster_desert" if map_name == "desert_railway" else "map_raster_ocean")
		tree.set_meta("bench_duration",300.0)
		tree.change_scene_to_file("res://scenes/survivor_mode.tscn")
		await tree.scene_changed
		await tree.create_timer(3.0).timeout
		var mode: Node = tree.current_scene
		var source: WeatherSystem = mode._weather
		var weather_owner: Variant = source.get_meta(&"weather_volume_owner").get_ref()
		if weather_owner.warm_results.size() != 3:
			push_error("Weather material warmup did not finish")
			tree.quit(1)
			return
		for result: Dictionary in weather_owner.warm_results.values():
			if not result.get("rendered",false):
				push_error("Weather material warmup did not render: " + str(result))
				tree.quit(1)
				return
		print("Weather material warmup: ",weather_owner.warm_results)
		if OS.get_environment("AGL_WEATHER_DENSITY") == "1":
			await preload("res://scripts/tests/weather_density_preview.gd").run(self,mode,weather_owner,map_name)
			tree.current_scene = null
			mode.queue_free()
			await tree.process_frame
			await tree.process_frame
			continue
		if OS.get_environment("AGL_WEATHER_HOLO") == "1":
			await preload("res://scripts/tests/weather_holo_preview.gd").run(self,mode,weather_owner,map_name)
			tree.current_scene = null
			mode.queue_free()
			await tree.process_frame
			await tree.process_frame
			continue
		if OS.get_environment("AGL_WEATHER_COMPARE") == "1":
			await preload("res://scripts/tests/weather_cloud_shape_preview.gd").run(self,mode,weather_owner,map_name)
			tree.current_scene = null
			mode.queue_free()
			await tree.process_frame
			await tree.process_frame
			continue
		mode._camera_ctrl.follow_enabled = false
		mode._camera_ctrl.set_process(false)
		var best := Vector2.ZERO
		var density := 0.0
		for y in range(-10,11):
			for x in range(-10,11):
				var point := Vector2(x,y)*1000.0
				var value := source.sample_density(point)
				if value > density:
					density = value
					best = point
		var views := [["cloud",best,0.28],["cloud_far",best,0.12]]
		# 选择有明确疏密过渡的机位，避免只看云区最厚处。
		var edge := best
		var edge_score := -INF
		for y in range(-12,13):
			for x in range(-12,13):
				var point := Vector2(x,y)*1000.0
				var value := source.sample_density(point)
				var contrast := absf(source.sample_density(point+Vector2(1800,0))-source.sample_density(point-Vector2(1800,0)))
				var score := contrast-absf(value-0.15)
				if score > edge_score:
					edge_score = score
					edge = point
		views.append(["cloud_edge",edge,0.22])
		if map_name == "desert_railway":
			views.append(["storm_front",Vector2(2300,0),0.25])
		for view in views:
			mode.camera.position = view[1]
			mode.player_aircraft.global_position = view[1]
			mode.player_aircraft.clear_trail()
			mode._camera_ctrl.target_zoom = float(view[2])
			mode._camera_ctrl._base_zoom = float(view[2])
			mode.camera.zoom = Vector2.ONE * float(view[2])
			mode.camera.rotation = 0.15 if view[0] == "cloud_far" else 0.0
			mode.camera.force_update_scroll()
			await tree.create_timer(1.5).timeout
			await RenderingServer.frame_post_draw
			var path := "res://bench/results/weather_volume_%s_%s.png" % [map_name,view[0]]
			var result := get_viewport().get_texture().get_image().save_png(path)
			print("WeatherVolume capture ",path," result=",result," cloud_density=",density)
			if result != OK:
				tree.quit(1)
				return
		tree.paused = true
		await tree.process_frame
		var before := source._time
		await tree.create_timer(0.2,true,false,true).timeout
		if source._time != before:
			push_error("Weather clock moved while paused")
			tree.quit(1)
			return
		tree.paused = false
		tree.current_scene = null
		mode.queue_free()
		await tree.process_frame
		await tree.process_frame
	print("Weather density comparison: PASS" if OS.get_environment("AGL_WEATHER_DENSITY") == "1" else ("Weather hologram comparison: PASS" if OS.get_environment("AGL_WEATHER_HOLO") == "1" else ("Weather shape comparison: PASS" if OS.get_environment("AGL_WEATHER_COMPARE") == "1" else "WeatherVolume Visual and pause: PASS")))
	tree.quit(0)
