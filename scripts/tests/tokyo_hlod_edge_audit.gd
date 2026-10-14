extends RefCounted
## 显式验收：实际玩家边界、完整RGBA覆盖；不修改生产相机边界或资源。
const Session := preload("res://scripts/rendering/tokyo_volume_preload.gd")


static func alpha_coverage(image: Image) -> Dictionary:
	image.convert(Image.FORMAT_RGBA8)
	var bytes := image.get_data()
	var missing := 0
	for n in range(3,bytes.size(),4):
		if bytes[n]<250: missing+=1
	return {"pixels":image.get_width()*image.get_height(),"uncovered_pixels":missing,
		"uncovered_fraction":float(missing)/maxi(1,image.get_width()*image.get_height())}


static func run(battle: Node, map: Node, output: String) -> Dictionary:
	var tree := battle.get_tree()
	var window := tree.root
	var saved_size: Vector2i = window.size
	var result := {"cases":[],"fail":0,"performance_sample":false,"combat_verified":false}
	var locations := {"north":Vector2(0,-16000),"east":Vector2(16000,0),
		"south":Vector2(0,16000),"west":Vector2(-16000,0),
		"northwest":Vector2(-16000,-16000),"northeast":Vector2(16000,-16000),
		"southeast":Vector2(16000,16000),"southwest":Vector2(-16000,16000)}
	var cases: Array[Dictionary] = []
	for label: String in locations:
		for zoom: float in [0.2,0.35,1.0,5.0]:
			cases.append({"label":label,"position":locations[label],"zoom":zoom,"window":Vector2i(1600,900)})
	for size: Vector2i in [Vector2i(1200,900),Vector2i(2100,900)]:
		for label: String in ["northwest","northeast","southeast","southwest"]:
			cases.append({"label":label,"position":locations[label],"zoom":0.2,"window":size})
	battle._camera_ctrl.follow_enabled=false
	for n in cases.size():
		var item: Dictionary=cases[n]
		window.size=item.window
		for frame in 3: await tree.process_frame
		battle._camera_ctrl.cine_cut_to(item.position,item.zoom)
		battle.camera.force_update_scroll()
		map._lod_clock=0.0
		for frame in 4: await tree.process_frame
		var deadline := Time.get_ticks_msec()+5000
		while Time.get_ticks_msec()<deadline:
			var state: Dictionary=map.debug_state()
			if Session.state_ready(state) and state.selection_current: break
			await tree.process_frame
		for frame in 3: await tree.process_frame
		await RenderingServer.frame_post_draw
		var state: Dictionary=map.debug_state()
		var native: Image=map._viewport.get_texture().get_image()
		var coverage := alpha_coverage(native)
		var view: Viewport = battle.camera.get_viewport()
		var logical: Vector2=view.get_visible_rect().size
		var inverse: Transform2D=view.get_canvas_transform().affine_inverse()
		var rect := Rect2(inverse*Vector2.ZERO,Vector2.ZERO)
		for corner: Vector2 in [Vector2(logical.x,0),logical,Vector2(0,logical.y)]: rect=rect.expand(inverse*corner)
		var full_bounds: bool=map._archive.bounds.encloses(rect)
		var current: bool=Session.state_ready(state) and state.selection_current and state.screen_visible
		var name_value := "edge_%02d_%s" % [n,item.label]
		var saved := window.get_texture().get_image().save_png(output.path_join(name_value+".png"))==OK
		saved=native.save_png(output.path_join(name_value+"_native.png"))==OK and saved
		var good: bool=current and full_bounds and coverage.uncovered_pixels==0 and saved
		# 失败快照只记录值：区分资源等待、资格等待和已就绪但未提交，不污染帧时测试。
		var missing_meshes: Array[String]=[]
		var missing_textures: Array[String]=[]
		for path: String in map._stream._wanted:
			if not map._stream._cache.has(path): missing_meshes.append(path)
		for path: String in map._stream._texture_wanted:
			if not map._stream._textures.has(path): missing_textures.append(path)
		var target_debug := {"anticipated_scale":map._target.get("anticipated_scale",0),
			"charges":map._target.get("charges",{}),"keys":map._target.get("keys",[]),
			"missing_meshes":missing_meshes,"missing_textures":missing_textures}
		result.fail+=int(not good)
		result.cases.append({"label":item.label,"requested_zoom":item.zoom,"camera_zoom":battle.camera.zoom.x,
			"camera_center":battle.camera.global_position,"window_size":window.size,"logical_size":logical,
			"view_bounds":rect,"archive_covers_view":full_bounds,"ready":current,"coverage":coverage,
			"state":state,"target_debug":target_debug,"file":name_value+".png","native_file":name_value+"_native.png","passed":good})
		print("[Tokyo edge audit] ",n," ",item.label," zoom=",item.zoom," passed=",good," missing=",coverage.uncovered_pixels)
	window.size=saved_size
	return result
