extends RefCounted
## 真实候选目录的纯数据回放；无渲染、无资源上传，不授予Visual性能通过。
const Native := preload("res://scripts/rendering/tokyo_hlod_native.gd")
const Planner := preload("res://scripts/rendering/tokyo_cut_worker.gd")
const Cut := preload("res://scripts/experiments/tokyo_spatial_cut.gd")


static func run(parent: Node, path: String, sha: String, output: String) -> int:
	if output.is_empty() or FileAccess.file_exists(output) or sha.length()!=64 or FileAccess.get_sha256(path)!=sha: return 1
	var data: Variant=JSON.parse_string(FileAccess.get_file_as_string(path))
	var native := Native.new()
	if not data is Dictionary or not native.read(data.get("native")): return 1
	var rows: Array[Dictionary]=[]
	var failures := 0
	# LOD5跨地表替换资格边界，必须拆成不同来源快照，不能混在同一个任务中。
	for batch in 3:
		var level := 4 if batch==0 else 5
		var configuration := "lod%d_full"%level
		var scales: Array=[1.0,1.1,1.2,1.25] if batch==0 else ([1.3,1.5] if batch==1 else [1.8,2.0])
		var hybrid: bool=native._ground_roots.has(configuration) and float(scales[-1])<=float(native.ground.limits[configuration])
		var roots: Array[Dictionary]=[]
		roots.assign(native._ground_roots[configuration] if hybrid else native._partition_roots.get(configuration,native.catalog.configurations[configuration]))
		var queries: Array[Dictionary]=[]
		var references: Array[Dictionary]=[]
		for index in scales.size():
			var query := {"center":Vector2(300+index*60,-13300+index*80),"scale":scales[index],"angle":0.05*index,"size":Vector2(1600,900)}
			queries.append(query)
			references.append(native.select(query.center,query.scale,query.angle,query.size,configuration,192*1024*1024))
		var worker := Planner.new()
		var started := Time.get_ticks_usec()
		var configured := worker.configure(roots,level)
		var setup_us := Time.get_ticks_usec()-started
		if not configured:
			failures+=1
			continue
		started=Time.get_ticks_usec()
		var submitted := worker.submit(queries)
		var submit_us := Time.get_ticks_usec()-started
		var deadline := Time.get_ticks_msec()+10000
		while submitted and not worker.ready() and Time.get_ticks_msec()<deadline: await parent.get_tree().process_frame
		var elapsed_us := Time.get_ticks_usec()-started
		started=Time.get_ticks_usec()
		var response := worker.take(level,10000000)
		var take_us := Time.get_ticks_usec()-started
		if response.is_empty(): failures+=1
		else:
			for index in scales.size():
				var selected := Cut.pick(response.solutions[index],192*1024*1024)
				var equal: bool=selected.entries==references[index].entries and selected.within_budget==references[index].within_budget and selected.bytes==references[index].bytes
				failures+=int(not equal)
				rows.append({"configuration":configuration,"hybrid":hybrid,"query":index,"equal":equal,"faces":selected.triangles,"pages":selected.active,"within_budget":selected.within_budget,"worker_solve_us":response.solutions[index].solver_usec,"setup_us":setup_us,"submit_us":submit_us,"take_us":take_us,"batch_elapsed_us":elapsed_us})
		worker.close()
		failures+=int(worker._task!=-1 or not worker._roots.is_empty())
	var layer_audit := _layer_audit(native,parent)
	failures+=int(layer_audit.failures)
	var file := FileAccess.open(output,FileAccess.WRITE)
	if file==null: return 1
	file.store_string(JSON.stringify({"failures":failures,"package_sha":sha,"rows":rows,"layer_audit":layer_audit,"performance_sample":false,"runtime_integrated":false},"\t"))
	file.close()
	print("[Tokyo cut worker replay] failures=",failures," queries=",rows.size())
	return int(failures>0)


static func _layer_audit(native: RefCounted, parent: Node) -> Dictionary:
	# 真实目录的保留切面反例；只核纯元数据，不假称执行了GPU显示交接。
	var result := {"failures":0,"fresh_cuts":0,"budget_qualified":0,"probes":0,"ground_only_accepts":0,"examples":[],"max_check_usec":0,"overlay_rejections":0,"commit_rejections":0,"reselected":0}
	var size := Vector2(1600,900)
	var viewport := SubViewport.new()
	viewport.size=Vector2i(size)
	viewport.render_target_update_mode=SubViewport.UPDATE_DISABLED
	parent.add_child(viewport)
	var source := Node2D.new()
	viewport.add_child(source)
	var overlay := preload("res://scripts/rendering/tokyo_hlod_overlay.gd").new()
	overlay._source_ref=weakref(source)
	overlay._native=native
	overlay._archive=preload("res://scripts/rendering/tokyo_volume_archive.gd").new()
	overlay._archive.bounds=Rect2(-18000,-18000,36000,36000)
	overlay._last_size=size
	overlay.display_budget=192*1024*1024
	var anchors: Array[Vector2]=[Vector2(300,-13300),Vector2(-5600,-2900),Vector2(0,-16000),Vector2(16000,-16000),Vector2(16000,0),Vector2(16000,16000),Vector2(0,16000),Vector2(-16000,16000),Vector2(-16000,0),Vector2(-16000,-16000)]
	for center: Vector2 in anchors:
		for scale_value: float in [1.0,1.5,2.0,5.0]:
			var cut: Dictionary=native.select(center,scale_value,0.0,size,"",192*1024*1024)
			if cut.is_empty():
				result.failures+=1
				continue
			result.fresh_cuts+=1
			result.budget_qualified+=int(cut.within_budget)
			for offset: Vector2 in [Vector2.ZERO,Vector2(64,0),Vector2(-64,0),Vector2(0,64),Vector2(0,-64),Vector2(256,0),Vector2(-256,0),Vector2(0,256),Vector2(0,-256)]:
				var moved := center+offset/scale_value
				var canvas := Transform2D.IDENTITY.scaled(Vector2.ONE*scale_value)
				canvas.origin=size*0.5-canvas*moved
				var view := Rect2(moved-size/(2.0*scale_value),size/scale_value)
				var ground_ok: bool=native.covers_ground(cut,view,canvas,size)
				var started := Time.get_ticks_usec()
				var all_ok: bool=native.covers_visible_layers(cut,view,canvas,size)
				result.max_check_usec=maxi(result.max_check_usec,Time.get_ticks_usec()-started)
				result.probes+=1
				result.failures+=int(all_ok and not ground_ok)
				if offset==Vector2.ZERO: result.failures+=int(not all_ok)
				if ground_ok and not all_ok and cut.within_budget:
					result.ground_only_accepts+=1
					# 调用真实overlay覆盖、提交及复用入口，不覆写其覆盖判定。
					overlay._last_canvas=canvas
					overlay.output_scale=scale_value
					overlay._target=cut
					overlay._target_catalog=-2
					var rejected: bool=not overlay._cut_covers_current_view(cut,-2)
					result.overlay_rejections+=int(rejected)
					result.failures+=int(not rejected)
					if rejected:
						var refused: bool=not overlay._commit_ready_target(scale_value)
						result.commit_rejections+=int(refused)
						result.failures+=int(not refused)
						var refreshed: Dictionary=overlay._select_native(moved,scale_value,0.0,size,"",192*1024*1024,true)
						var changed: bool=refreshed!=cut
						result.reselected+=int(changed)
						result.failures+=int(not changed)
					if result.examples.size()<8: result.examples.append({"center":[center.x,center.y],"scale":scale_value,"screen_offset":[offset.x,offset.y],"configuration":cut.configuration,"faces":cut.triangles,"bytes":cut.bytes})
	overlay.free()
	viewport.free()
	print("[Tokyo actual layer audit] ",result)
	return result
