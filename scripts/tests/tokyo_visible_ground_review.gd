extends RefCounted
## 同一真实地图、相机和借用纹理，切换可见覆盖证明；不重造地表。
const Session := preload("res://scripts/rendering/tokyo_volume_preload.gd")
const Capture := preload("res://scripts/tests/tokyo_ao_review.gd")
const Pixels := preload("res://scripts/tests/tokyo_shell_review.gd")


static func run(battle: Node, map: Node, output: String) -> int:
	var tree := battle.get_tree()
	var paused := tree.paused
	var source: RasterBasemapRenderer = battle._map_features._raster_basemap
	var source_mode := source.process_mode
	var ignore: bool = battle.camera.ignore_rotation
	var signature := var_to_bytes(BuildingRenderer._cache_entries)
	tree.paused=true
	source.process_mode=Node.PROCESS_MODE_ALWAYS
	battle.camera.ignore_rotation=false
	var fail := 0
	var reductions := 0
	var rows: Array = []
	var poses := [Vector3(.13,0,0),Vector3(.26,0,0),Vector3(.52,0,0),Vector3(.98,0,0),Vector3(2.2,0,0),Vector3(5,0,0),
		Vector3(.26,14,1),Vector3(.98,-14,1),Vector3(.52,0,2)]
	for index in poses.size():
		var pose: Vector3 = poses[index]
		battle.camera.position=[Vector2(-6550,-2200),Vector2(-6300,-2200),Vector2(-6300,-1700)][int(pose.z)]
		battle.camera.zoom=Vector2.ONE*pose.x
		battle.camera.rotation=deg_to_rad(pose.y)
		battle.camera.force_update_scroll()
		var deadline := Time.get_ticks_msec()+15000
		var stable := 0
		var ready := false
		while Time.get_ticks_msec()<deadline:
			await RenderingServer.frame_post_draw
			var current: bool = preload("res://scripts/tests/tokyo_canonical_review.gd").ready_at_canvas(map._last_canvas,battle.get_viewport().get_canvas_transform(),map.debug_state())
			if current and not source._transitioning:
				if stable==0:
					stable=Time.get_ticks_msec()
				if Time.get_ticks_msec()-stable>=200:
					ready=true
					break
			else:
				stable=0
		if not ready:
			rows.append({"pose":str(pose),"ready":false,"state":map.debug_state()})
			fail+=1
			continue
		var ground: RefCounted = map._tile_ground
		map.set_process(false)
		source.set_process(false)
		var flags := [false,true,false]
		var images: Array[Image] = []
		var states: Array = []
		var original_flag: bool = ground.visible_retirement if ground!=null else false
		for version in 3:
			if ground!=null:
				ground.suspend_fixed()
				ground.visible_retirement=flags[version]
				fail+=int(not ground.resume_fixed(map))
			images.append(await Capture._capture(battle,map,output.path_join("r128_%02d_%d"%[index,version])))
			states.append(map.debug_state())
		var error := Pixels._pixel_error(images[0],images[1])
		var restored := Pixels._pixel_error(images[0],images[2])
		var saved: int = int(states[0].triangles)-int(states[1].triangles)
		fail+=int(error>1 or restored>1 or saved<0 or var_to_bytes(BuildingRenderer._cache_entries)!=signature)
		reductions+=int(saved>0)
		rows.append({"pose":str(pose),"center":str(battle.camera.position),"ready":true,"borrowed":ground!=null,"pixels":error,"restored":restored,"faces_saved":saved,"states":states})
		if ground!=null:
			ground.suspend_fixed()
			ground.visible_retirement=original_flag
			fail+=int(not ground.resume_fixed(map))
		map._viewport.render_target_update_mode=SubViewport.UPDATE_ONCE
		map.set_process(true)
		source.set_process(true)
		print("[R128 ground review] pose=",pose," saved=",saved," pixels=",error," restored=",restored)
	fail+=int(reductions==0)
	source.process_mode=source_mode
	battle.camera.ignore_rotation=ignore
	tree.paused=paused
	var file := FileAccess.open(output.path_join("r128_visible_ground.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"fail":fail,"reductions":reductions,"rows":rows,"fps_evidence":false},"\t"))
	file.close()
	return fail
