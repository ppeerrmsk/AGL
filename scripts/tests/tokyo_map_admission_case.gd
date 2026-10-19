extends RefCounted
## 真实SceneTree中的异步接纳/退出门；只替代磁盘/GPU资源提交，不替代覆盖或接纳算法。
const Overlay := preload("res://scripts/rendering/tokyo_hlod_overlay.gd")
const Worker := preload("res://scripts/rendering/tokyo_map_plan_worker.gd")
const SIZE := Vector2(160,100)


class Probe extends "res://scripts/rendering/tokyo_hlod_overlay.gd":
	var clears := 0
	var requests := 0
	var requested_staging := false
	var commit_zoom_directions: Array[bool]=[]
	var ready_to_commit := false
	var bound_targets := 0
	func _process(_delta: float) -> void:
		# 夹具直接驱动接纳入口，不创建真实地图相机和GPU流送器。
		pass
	func _clear_current() -> void:
		clears+=1
		super._clear_current()
	func _request_target(keep_current: bool) -> void:
		requests+=1
		requested_staging=keep_current
	func _commit_ready_target(scale_value: float) -> bool:
		commit_zoom_directions.append(_zooming_in)
		return super._commit_ready_target(scale_value)
	func _resources_ready(_cut: Dictionary, _catalog: int) -> bool:
		return ready_to_commit
	func _bind_target() -> void:
		# 只替代GPU节点装配；真实提交入口仍负责资格、覆盖、租约与先后顺序。
		bound_targets+=1
		_committed=_target.keys.duplicate()
		_committed_catalog=_target_catalog
		_committed_cut=_target.duplicate(true)


class StreamProbe extends Node:
	var residency_limit := 96*1024*1024
	var residency_bytes := 0
	var residency_meshes := PackedStringArray()
	var residency_images := PackedStringArray()
	var _cache: Dictionary={}
	var _textures: Dictionary={}
	var residency_requests := 0
	var mesh_collections := 0
	var ready_after_collect: WeakRef
	var closed := false
	func request_residency_only() -> void:
		residency_requests+=1
	func collect_ready_meshes() -> void:
		mesh_collections+=1
		var owner: Variant=ready_after_collect.get_ref() if ready_after_collect!=null else null
		if typeof(owner)==TYPE_OBJECT and is_instance_valid(owner): owner.ready_to_commit=true
	func reserve_auxiliary(_token: int, _bytes: int) -> bool:
		return true
	func release_auxiliary(_token: int) -> void:
		pass
	func close() -> void:
		closed=true
	func summary() -> Dictionary:
		return {}


class ReplyPlanner extends RefCounted:
	var response: Dictionary={}
	var gate: Semaphore
	func configure(source: Dictionary) -> bool:
		response=source.response
		return true
	func plan(_request: Dictionary) -> Dictionary:
		if gate!=null: gate.wait()
		return response.duplicate(true)


static func pose(center: Vector2 = Vector2.ZERO, angle: float = 0.0) -> Transform2D:
	var canvas := Transform2D(angle,Vector2.ZERO)
	canvas.origin=SIZE*0.5-canvas*center
	return canvas


static func catalog_fixture() -> Dictionary:
	var rows := {}
	var roots: Array[Dictionary]=[]
	var regions := [Rect2(-1000,-60,2000,120),Rect2(-1000,60,2000,940),Rect2(-1000,-1000,2000,940)]
	for index in regions.size():
		var region: Rect2=regions[index]
		var key := "0:%d"%index
		var box := AABB(Vector3(region.position.x,0,region.position.y),Vector3(region.size.x,0,region.size.y))
		rows[key]={"max_scale":5.0,"bounds":[region.position.x,region.position.y,region.end.x,region.end.y],
			"native_geometry":{"path":"mesh/"+key},"native_texture":{"path":"image/"+key}}
		roots.append({"key":key,"boxes":[box,AABB(),AABB()],"coverage_box":box,"triangles":[2,0,0],"bytes":200})
	return {"rows":rows,"roots":roots,"max_scale":5.0,"min_scale":0.1}


static func cut(keys: PackedStringArray, catalog: Dictionary) -> Dictionary:
	var entries: Array[Dictionary]=[]
	for root: Dictionary in catalog.roots:
		if root.key in keys: entries.append(root.duplicate(true))
	return {"keys":keys,"entries":entries,"within_budget":true,"triangles":keys.size()*2,"bytes":keys.size()*200,
		"charges":{"ground_bytes":0}}


static func candidate(value: Dictionary) -> Dictionary:
	return {"status":"candidate","catalog":0,"cut":value,"force_replan":false,"ground_candidate":{},"native_screen_bridge":{},"stats":{}}


static func make_fixture(parent: Node) -> Dictionary:
	var viewport := SubViewport.new()
	viewport.size=Vector2i(SIZE)
	viewport.render_target_update_mode=SubViewport.UPDATE_DISABLED
	parent.add_child(viewport)
	var source := Node2D.new()
	viewport.add_child(source)
	var stream := StreamProbe.new()
	parent.add_child(stream)
	var overlay := Probe.new()
	overlay._source_ref=weakref(source)
	overlay._archive=Overlay.Layout.new()
	overlay._archive.bounds=Rect2(-1000,-1000,2000,2000)
	overlay._stream=stream
	overlay._screen=Sprite2D.new()
	overlay.add_child(overlay._screen)
	source.add_child(overlay)
	var catalog := catalog_fixture()
	overlay._catalogs=[catalog]
	for key: String in catalog.rows:
		overlay._geometry[catalog.rows[key].native_geometry.path]={"bytes":100}
		overlay._textures[catalog.rows[key].native_texture.path]={"charge":100}
	var full := cut(PackedStringArray(["0:0","0:1","0:2"]),catalog)
	var partial := cut(PackedStringArray(["0:0"]),catalog)
	overlay._committed_cut=full.duplicate(true)
	overlay._committed=full.keys.duplicate()
	overlay._committed_catalog=0
	overlay._target=full.duplicate(true)
	overlay._target_catalog=0
	overlay._last_canvas=pose()
	overlay._last_size=SIZE
	overlay._last_selected_canvas=overlay._last_canvas
	overlay._last_selected_size=SIZE
	overlay._lod_clock=1.0
	overlay._plan_dirty=false
	overlay._plan_generation=7
	overlay._active=true
	var planner := ReplyPlanner.new()
	var worker := Worker.new(planner)
	if not worker.configure({"response":candidate(partial)},7):
		viewport.queue_free();stream.queue_free()
		return {}
	overlay._map_worker=worker
	return {"viewport":viewport,"source":source,"overlay":overlay,"stream":stream,"planner":planner,"worker":worker,
		"full":full,"partial":partial}


static func wait_ready(parent: Node, worker: RefCounted) -> bool:
	var deadline := Time.get_ticks_msec()+5000
	while not worker.ready() and Time.get_ticks_msec()<deadline: await parent.get_tree().process_frame
	return worker.ready()


static func dispose(parent: Node, state: Dictionary) -> void:
	var planner: RefCounted=state.planner
	if planner.gate!=null: planner.gate.post()
	state.viewport.queue_free()
	await parent.get_tree().process_frame
	await parent.get_tree().process_frame
	state.stream.queue_free()
	await parent.get_tree().process_frame
	state.clear()


static func empty_display_trace_checks(parent: Node) -> int:
	var state := make_fixture(parent)
	if state.is_empty(): return 1
	var overlay: Probe=state.overlay
	var full_bytes := overlay._handoff_bytes(state.full,0)
	var failures := int(full_bytes<=0)
	overlay._clear_current()
	failures+=int(overlay._handoff_bytes(state.full,0)!=full_bytes)
	overlay._trace_selection=true
	overlay._trace_prepared_state("empty_current",state.full,0)
	overlay._trace_prepared_state("no_solution",{},-1)
	failures+=int(overlay._selection_trace.size()!=2)
	if overlay._selection_trace.size()==2:
		failures+=int(overlay._selection_trace[0].next_union!=full_bytes or overlay._selection_trace[1].next_union!=-1)
	await dispose(parent,state)
	return failures


static func direct_checks(parent: Node) -> int:
	var state := make_fixture(parent)
	if state.is_empty(): return 1
	var failures := 0
	var overlay: Probe=state.overlay
	var request := overlay._planning_request(1.0,false)
	var failed_plan := {"status":"no_solution","catalog":0,"cut":{}}
	# 当前视野确有完整合格显示时，真正的无解结果也不能清空它。
	failures+=int(not overlay._cut_covers_current_view(state.full,0) or not overlay._cut_covers_current_view(state.partial,0))
	failures+=int(overlay._admit_prepared_plan(failed_plan,request,1.0,true,false))
	failures+=int(overlay.clears!=0 or overlay._committed_cut!=state.full or not overlay._screen.visible)
	# 移动后的旧无解报告不代表新视野无解；旧候选必须重验现在的真实投影。
	overlay._last_canvas=pose(Vector2(0,200))
	failures+=int(not overlay._cut_covers_current_view(state.full,0) or overlay._cut_covers_current_view(state.partial,0))
	failures+=int(overlay._admit_prepared_plan(failed_plan,request,1.0,true,false))
	failures+=int(overlay._plan_rejected!=1 or overlay.clears!=0 or overlay._committed_cut!=state.full)
	failures+=int(overlay._admit_prepared_plan(candidate(state.partial),request,1.0,true,false))
	failures+=int(overlay._plan_rejected!=2 or overlay.requests!=0 or overlay.clears!=0)
	# 不改变中心的90度转动也会露出上下条带；不能只比较中心偏移。
	overlay._last_canvas=pose(Vector2.ZERO,PI*0.5)
	failures+=int(not overlay._cut_covers_current_view(state.full,0) or overlay._cut_covers_current_view(state.partial,0))
	failures+=int(overlay._admit_prepared_plan(candidate(state.partial),request,1.0,true,false))
	failures+=int(overlay._plan_rejected!=3 or overlay.clears!=0 or overlay._target!=state.full)
	# 负对照：同视野确实无合格显示时，生产清理路径仍能执行，并触发仅常驻资源请求。
	overlay._committed_cut=state.partial.duplicate(true)
	overlay._committed=state.partial.keys.duplicate()
	failures+=int(overlay._cut_covers_current_view(overlay._committed_cut,0))
	var current_request := overlay._planning_request(1.0,false)
	failures+=int(not overlay._admit_prepared_plan(failed_plan,current_request,1.0,false,false))
	failures+=int(overlay.clears!=1 or not overlay._committed.is_empty() or state.stream.residency_requests!=1)
	await dispose(parent,state)
	return failures


static func stopped_camera_checks(parent: Node) -> int:
	var state := make_fixture(parent)
	if state.is_empty(): return 1
	var failures := 0
	var overlay: Probe=state.overlay
	var worker: RefCounted=state.worker
	state.planner.gate=Semaphore.new()
	failures+=int(not worker.submit(overlay._planning_request(1.0,false)))
	for frame in 2:
		failures+=int(overlay._step_prepared_selection(1.0,false,false,false,true,false))
		failures+=int(overlay.clears!=0 or overlay._committed_cut!=state.full or overlay._target!=state.full or not overlay._screen.visible)
		await parent.get_tree().process_frame
	failures+=int(overlay._plan_pending_frames!=2 or worker.summary().submitted!=1)
	state.planner.gate.post()
	var ready := await wait_ready(parent,worker)
	failures+=int(not ready)
	# 镜头及LOD时钟均未触发新查询，已完成结果仍必须领取并形成真实暂存事务。
	failures+=int(not overlay._step_prepared_selection(1.0,false,false,false,true,false))
	failures+=int(worker.busy() or overlay._plan_applied!=1 or overlay._target.keys!=state.partial.keys \
		or overlay.requests!=1 or not overlay.requested_staging or overlay.clears!=0 or overlay._committed_cut!=state.full)
	await dispose(parent,state)
	return failures


static func native_guard_metadata_checks(parent: Node) -> int:
	var failures: int=0
	var box: AABB=AABB(Vector3(-1000,0,-1000),Vector3(2000,0,2000))
	var child: Dictionary={"path":"native/child","boxes":[box,AABB(),AABB()],"triangles":[2,0,0],"bytes":120}
	var root: Dictionary={"path":"native/root","boxes":[box,AABB(),AABB()],"triangles":[2,0,0],"bytes":100,"children":[child]}
	var entry: Dictionary=root.duplicate(true)
	entry.erase("children");entry["mask"]=[true,false,false]
	var original: Dictionary={"keys":PackedStringArray(["native/root"]),"entries":[entry],"masks":[[true,false,false]],
		"configuration":"lod5_full","within_budget":true,"triangles":2,"bytes":100,
		"charges":{"ground_bytes":0},"ground_images":PackedStringArray(),
		"selection_stage":"native_guard","spatial_guard_px":48}
	var snapshot: Dictionary={"schema":1,"configurations":{"lod5_full":[root]},"partition_roots":{},"ground_roots":{},
		"ground_limits":{},"pages":{"native/root":{"components":{"native/root":true}},"native/child":{"components":{"native/child":true}}}}
	for variant: String in ["unchanged","prefetch","identity","masks"]:
		var state: Dictionary=make_fixture(parent)
		if state.is_empty(): failures+=1;continue
		var overlay: Probe=state.overlay
		overlay._native=preload("res://scripts/rendering/tokyo_hlod_native.gd").new()
		if not overlay._native.configure_selection_snapshot(snapshot,{"background":true,"epoch":0,"display_limit":96*1024*1024,"native_page_limit":16}):
			failures+=1
			await dispose(parent,state)
			continue
		overlay._geometry["native/root"]={"bytes":100}
		overlay._geometry["native/child"]={"bytes":120}
		# 两个独立字典：不能依靠生产绑定时可能存在的别名来掩盖committed未刷新。
		overlay._target_catalog=-2;overlay._committed_catalog=-2
		overlay._target=original.duplicate(true);overlay._committed_cut=original.duplicate(true)
		overlay._committed=original.keys.duplicate()
		var next: Dictionary=original.duplicate(true)
		next.selection_stage="native_retained";next.spatial_guard_px=0
		if variant=="prefetch":
			next["prefetch_catalog"]=-2;next["prefetch_keys"]=PackedStringArray(["native/child"])
		elif variant=="identity":
			var child_entry: Dictionary=child.duplicate(true)
			child_entry["mask"]=[true,false,false]
			next.keys=PackedStringArray(["native/child"]);next.entries=[child_entry];next.bytes=120
		elif variant=="masks":
			# 增加零面数的高楼层仍是真实完整覆盖，但资源绑定身份必须不同。
			next.masks=[[true,true,false]];next.entries[0].mask=[true,true,false]
		var revision: int=overlay._plan_revision
		var request: Dictionary=overlay._planning_request(1.0,false)
		var plan: Dictionary=candidate(next)
		plan.catalog=-2
		var same_identity: bool=variant in ["unchanged","prefetch"]
		var needs_request: bool=variant!="unchanged"
		var case_failures: int=int(not overlay._cut_covers_current_view(original,-2) or not overlay._cut_covers_current_view(next,-2))
		var changed: bool=overlay._admit_prepared_plan(plan,request,1.0,true,false)
		var expected_committed: Dictionary=original.duplicate(true)
		if same_identity:
			expected_committed.selection_stage="native_retained";expected_committed.spatial_guard_px=0
		case_failures+=int(changed!=needs_request or overlay._target!=next or overlay._committed_cut!=expected_committed)
		case_failures+=int(overlay._plan_revision!=revision+int(needs_request) or overlay.requests!=int(needs_request) \
			or overlay.clears!=0 or overlay.bound_targets!=0 or overlay._target_committed()!=same_identity \
			or overlay._plan_applied!=1 or overlay._plan_rejected!=0 or overlay._plan_dirty)
		case_failures+=int(needs_request and not overlay.requested_staging)
		if case_failures:
			print("[Tokyo map admission] native metadata variant=",variant," fail=",case_failures,
				" target=",overlay._target.get("selection_stage")," committed=",overlay._committed_cut.get("selection_stage"),
				" requests=",overlay.requests," revision=",overlay._plan_revision-revision)
		failures+=case_failures
		await dispose(parent,state)
	print("[Tokyo map admission] native_guard_metadata fail=",failures)
	return failures


static func native_guard_cadence_checks(parent: Node) -> int:
	var failures := 0
	var cases := [
		{"stage":"native_motion_guard","guard":0,"catalog":-2,"accelerated":true},
		{"stage":"native_actual","guard":0,"catalog":-2,"accelerated":true},
		{"stage":"native_retained","guard":0,"catalog":-2,"accelerated":true},
		{"stage":"native_motion_guard","guard":48,"catalog":-2,"accelerated":false},
		{"stage":"native_motion_guard","guard":0,"catalog":0,"accelerated":false},
		{"stage":"unknown","guard":0,"catalog":-2,"accelerated":false},
		{"stage":"native_motion_guard","catalog":-2,"accelerated":false}
	]
	for item: Dictionary in cases:
		var state := make_fixture(parent)
		if state.is_empty(): failures+=1;continue
		var overlay: Probe=state.overlay
		var worker: RefCounted=state.worker
		state.planner.gate=Semaphore.new()
		overlay._committed_catalog=int(item.catalog)
		overlay._committed_cut["configuration"]="lod5_full"
		overlay._committed_cut["selection_stage"]=item.stage
		if item.has("guard"): overlay._committed_cut["spatial_guard_px"]=item.guard
		overlay._target_catalog=overlay._committed_catalog
		overlay._target=overlay._committed_cut.duplicate(true)
		# 即使短周期已到，静止镜头也不能产生新请求。
		overlay._lod_clock=0.05-0.020
		overlay._step_prepared_selection(1.0,false,false,false,true,false)
		failures+=int(worker.summary().submitted!=0 or overlay._plan_dirty)
		overlay._last_canvas=pose(Vector2(1,0));overlay._lod_clock=0.05-0.010
		overlay._step_prepared_selection(1.0,false,false,false,true,false)
		failures+=int(worker.summary().submitted!=0)
		overlay._last_canvas=pose(Vector2(2,0));overlay._lod_clock=0.05-0.020
		overlay._step_prepared_selection(1.0,false,false,false,true,false)
		failures+=int(worker.summary().submitted!=(1 if item.accelerated else 0))
		# 普通保护带仍在原50ms门提交；负对照也继续走真实单槽阻塞检查。
		if worker.summary().submitted==0:
			overlay._lod_clock=0.0
			overlay._step_prepared_selection(1.0,false,false,false,true,false)
		failures+=int(worker.summary().submitted!=1 or not worker.busy() or worker.ready())
		overlay._lod_clock=0.0
		overlay._step_prepared_selection(1.0,false,false,false,true,false)
		failures+=int(worker.summary().submitted!=1 or overlay._plan_dirty)
		for x: float in [3.0,4.0]:
			overlay._last_canvas=pose(Vector2(x,0))
			overlay._step_prepared_selection(1.0,false,false,false,true,false)
			failures+=int(worker.summary().submitted!=1 or not worker.busy() or worker.ready() or not overlay._plan_dirty)
		await dispose(parent,state)
	print("[Tokyo map admission] native_guard_cadence fail=",failures)
	return failures


static func release_later(gate: Semaphore) -> void:
	OS.delay_msec(20)
	gate.post()


static func step_pose(overlay: Probe, scale_value: float, center: Vector2 = Vector2.ZERO, delta: float = 1.0/60.0) -> bool:
	var canvas := Transform2D(0.0,Vector2.ZERO).scaled(Vector2.ONE*scale_value)
	canvas.origin=SIZE*0.5-canvas*center
	overlay._last_canvas=canvas
	var half := SIZE*0.5/scale_value
	return overlay._step_geometry(Rect2(center-half,half*2.0),scale_value,delta)


static func pending_motion_sampling_checks(parent: Node) -> int:
	var failures := 0
	var final_positions: Array[Vector2]=[]
	for presentation_hz: int in [20,60,120]:
		var state := make_fixture(parent)
		if state.is_empty(): failures+=1;continue
		var overlay: Probe=state.overlay
		var worker: RefCounted=state.worker
		var source: Node2D=state.source
		state.planner.gate=Semaphore.new()
		var case_failures := int(not worker.submit(overlay._planning_request(1.0,false)))
		# 默认prepared路径没有旧的future predictor；真实worker阻塞也必须持续采样运动。
		case_failures+=int(overlay._future_predictor!=null)
		step_pose(overlay,1.0,source.position,0.0)
		var delta := 1.0/float(presentation_hz)
		var physics_steps := 0
		var sampled := 0
		var outside_tolerance := 0
		var min_speed := INF
		var max_speed := -INF
		# 1.5秒内始终执行90个60Hz权威位置步，每步10world单位；呈现仅观察该位置。
		# 20Hz一帧见三个物理步，120Hz则交替见一个步和零步，不改场景时间或位移。
		for frame in int(float(presentation_hz)*1.5):
			var physics_goal := mini(90,floori(float(frame+1)*60.0/float(presentation_hz)+0.000001))
			while physics_steps<physics_goal:
				source.position+=Vector2(10.0,0.0)
				physics_steps+=1
			var authoritative_position := source.position
			step_pose(overlay,1.0,authoritative_position,delta)
			case_failures+=int(source.position!=authoritative_position or not overlay._motion_center.is_equal_approx(authoritative_position))
			if float(frame+1)*delta<0.5: continue
			sampled+=1
			var velocity: Vector2=overlay._pan_velocity
			min_speed=minf(min_speed,velocity.x)
			max_speed=maxf(max_speed,velocity.x)
			outside_tolerance+=int(not velocity.is_finite() or absf(velocity.x-600.0)>600.0*0.06 or absf(velocity.y)>0.001)
		final_positions.append(source.position)
		case_failures+=int(sampled==0 or outside_tolerance>0 or physics_steps!=90 or source.position!=Vector2(900.0,0.0))
		case_failures+=int(worker.summary().submitted!=1 or not worker.busy() or worker.ready() \
			or overlay._plan_pending_frames<sampled or overlay._plan_applied!=0 or overlay.clears!=0)
		if case_failures>0:
			print("[Tokyo map admission] pending motion hz=",presentation_hz," fail=",case_failures,
				" speed_range=",Vector2(min_speed,max_speed)," outside=",outside_tolerance,
				" physics_steps=",physics_steps," final_position=",source.position)
		failures+=case_failures
		await dispose(parent,state)
	for position: Vector2 in final_positions: failures+=int(position!=Vector2(900.0,0.0))
	return failures


static func cold_jump_prediction_checks(parent: Node) -> int:
	var failures := 0
	for cold_jump: bool in [true,false]:
		var state := make_fixture(parent)
		if state.is_empty(): failures+=1;continue
		var overlay: Probe=state.overlay
		var worker: RefCounted=state.worker
		state.planner.response=candidate(state.full)
		state.planner.gate=Semaphore.new()
		overlay.output_scale=1.0
		step_pose(overlay,1.0,Vector2.ZERO,0.0)
		var case_failures := int(not worker.submit(overlay._planning_request(1.0,false)))
		overlay._lod_clock=0.05
		var delta := 1.0/60.0
		var center := Vector2.ZERO
		var scale_value := 1.0
		# 真实逐帧采样先建立非零平移、缩放和方向历史；不能只测初始零值。
		for frame in 6:
			center+=Vector2(4.0,0.0)
			scale_value=exp(0.5*float(frame+1)*delta)
			# 直接驱动_step_geometry时同步推进外层_process负责的LOD倒计时。
			overlay._lod_clock=maxf(0.0,overlay._lod_clock-delta)
			step_pose(overlay,scale_value,center,delta)
		case_failures+=int(overlay._pan_velocity.x<=0.0 or overlay._zoom_rate<=0.0 or overlay._last_zoom_direction!=1)
		var prior_velocity: Vector2=overlay._pan_velocity
		var prior_rate: float=overlay._zoom_rate
		var prior_reversals: int=overlay.zoom_prediction_reversals
		var next_scale: float=0.8 if cold_jump else scale_value*exp(0.5*delta)
		center+=Vector2(200.0/next_scale,0.0) if cold_jump else Vector2(4.0,0.0)
		step_pose(overlay,next_scale,center,delta)
		if cold_jump:
			case_failures+=int(not overlay._pan_velocity.is_zero_approx() or not is_zero_approx(overlay._zoom_rate))
			case_failures+=int(overlay._last_zoom_direction!=0 or overlay._zooming_in or overlay.zoom_prediction_reversals!=prior_reversals)
		else:
			# 普通小步继续沿时间平滑；瞬切修复不能屏蔽正常运动预测。
			var expected_velocity: Vector2=preload("res://scripts/rendering/tokyo_native_predictor.gd").smooth_pan(prior_velocity,Vector2(4.0/delta,0.0),delta)
			var expected_rate: float=Overlay.Handoff.prediction_zoom_rate(prior_rate,next_scale/scale_value,delta)
			case_failures+=int(not overlay._pan_velocity.is_equal_approx(expected_velocity) or not is_equal_approx(overlay._zoom_rate,expected_rate))
			case_failures+=int(overlay._last_zoom_direction!=1 or not overlay._zooming_in or overlay.zoom_prediction_reversals!=prior_reversals)
		case_failures+=int(worker.summary().submitted!=1 or not worker.busy() or worker.ready() or not overlay._plan_dirty)
		state.planner.gate.post()
		var ready := await wait_ready(parent,worker)
		case_failures+=int(not ready)
		if ready:
			state.planner.gate=Semaphore.new()
			# 领取旧结果后由真实_step_geometry提交最新姿态，不直接构造测试请求。
			step_pose(overlay,next_scale,center,0.0)
			var request: Dictionary=worker._job.get("request",{})
			case_failures+=int(worker.summary().submitted!=2 or not worker.busy() or worker.ready() or request.is_empty())
			if not request.is_empty():
				case_failures+=int(not is_equal_approx(float(request.scale),next_scale) or request.canvas!=overlay._last_canvas)
				if cold_jump:
					case_failures+=int(not Vector2(request.pan_velocity).is_zero_approx() or not is_zero_approx(float(request.zoom_rate)) or request.zooming_out)
				else:
					case_failures+=int(Vector2(request.pan_velocity).x<=0.0 or float(request.zoom_rate)<=0.0)
		if case_failures:
			print("[Tokyo map admission] cold_jump=",cold_jump," fail=",case_failures,
				" pan=",overlay._pan_velocity," zoom=",overlay._zoom_rate," direction=",overlay._last_zoom_direction,
				" submitted=",worker.summary().submitted)
		failures+=case_failures
		await dispose(parent,state)
	print("[Tokyo map admission] cold_jump_prediction fail=",failures)
	return failures


static func pending_display_checks(parent: Node) -> int:
	var state := make_fixture(parent)
	if state.is_empty(): return 1
	var overlay: Probe=state.overlay
	var worker: RefCounted=state.worker
	# 只有已显示的外围两页先到期；中间页仍是当前视野的完整合格接替。
	for key: String in ["0:1","0:2"]: overlay._catalogs[0].rows[key].max_scale=1.0
	state.planner.gate=Semaphore.new()
	var failures := int(not worker.submit(overlay._planning_request(1.0,false)))
	var initial_revision := overlay._plan_revision
	failures+=int(step_pose(overlay,1.0))
	failures+=int(overlay.clears!=0 or not overlay._screen.visible or not overlay.display_qualified \
		or not overlay.display_covered or overlay._plan_revision!=initial_revision)
	# target==committed也须受原grace上界约束。首帧从0ms开始，避免测试靠真实等待。
	failures+=int(step_pose(overlay,1.05))
	failures+=int(overlay.clears!=0 or not overlay._display_grace or not overlay._screen.visible \
		or overlay.display_qualified or not overlay.display_covered)
	while Time.get_ticks_msec()<102: await parent.get_tree().process_frame
	overlay._grace_started=Time.get_ticks_msec()-101
	failures+=int(not step_pose(overlay,1.05))
	var cleared_revision := overlay._plan_revision
	failures+=int(overlay.clears!=1 or cleared_revision!=initial_revision+1 or not overlay._committed.is_empty() \
		or overlay._screen.visible or overlay.display_qualified or overlay.display_covered or not overlay._plan_dirty)
	# worker仍阻塞时不能每帧再次clear；否则会让任何返回结果永远错revision。
	failures+=int(step_pose(overlay,1.05))
	failures+=int(overlay.clears!=1 or overlay._plan_revision!=cleared_revision or worker.summary().submitted!=1)
	state.planner.gate.post()
	failures+=int(not await wait_ready(parent,worker))
	state.planner.gate=null
	step_pose(overlay,1.05)
	failures+=int(overlay._plan_rejected!=1 or worker.summary().submitted!=2 or not worker.busy() \
		or int(worker._job.get("request",{}).get("revision",-1))!=cleared_revision)
	failures+=int(not await wait_ready(parent,worker))
	step_pose(overlay,1.05)
	var accepted_revision := overlay._plan_revision
	failures+=int(overlay._plan_rejected!=1 or overlay._plan_applied!=1 or overlay._target.keys!=state.partial.keys \
		or worker.busy() or overlay._plan_dirty)
	step_pose(overlay,1.05)
	failures+=int(overlay._plan_revision!=accepted_revision or worker.summary().submitted!=2 or overlay._plan_rejected!=1)
	await dispose(parent,state)
	return failures


static func pending_coverage_checks(parent: Node) -> int:
	var state := make_fixture(parent)
	if state.is_empty(): return 1
	var overlay: Probe=state.overlay
	var worker: RefCounted=state.worker
	overlay._committed_cut=state.partial.duplicate(true)
	overlay._committed=state.partial.keys.duplicate()
	overlay._target=state.partial.duplicate(true)
	# 常驻资源只是可用输入，不是另一个已经绑定的全图显示层。
	state.stream.residency_meshes=PackedStringArray(["mesh/0:0"])
	state.stream.residency_images=PackedStringArray(["image/0:0"])
	state.stream.residency_bytes=200
	state.planner.gate=Semaphore.new()
	var failures := int(not worker.submit(overlay._planning_request(1.0,false)))
	failures+=int(step_pose(overlay,1.0))
	failures+=int(not overlay.display_qualified or not overlay.display_covered or not overlay._screen.visible)
	failures+=int(not step_pose(overlay,1.0,Vector2(0,200)))
	var cleared_revision := overlay._plan_revision
	failures+=int(overlay.clears!=1 or overlay._handoff_reason!="old_view" or overlay._screen.visible \
		or overlay.display_qualified or overlay.display_covered or not overlay._plan_dirty)
	step_pose(overlay,1.0,Vector2(0,200))
	failures+=int(overlay.clears!=1 or overlay._plan_revision!=cleared_revision or worker.summary().submitted!=1)
	await dispose(parent,state)
	return failures


static func ready_before_clear_checks(parent: Node) -> int:
	var state := make_fixture(parent)
	if state.is_empty(): return 1
	var overlay: Probe=state.overlay
	var worker: RefCounted=state.worker
	for key: String in ["0:1","0:2"]: overlay._catalogs[0].rows[key].max_scale=1.0
	overlay._target=state.partial.duplicate(true)
	state.stream.ready_after_collect=weakref(overlay)
	state.planner.gate=Semaphore.new()
	var failures := int(not worker.submit(overlay._planning_request(1.0,false)))
	# 帧首尚未就绪，领取资源后在收尾变为就绪；超过10%宽限也先提交合格目标。
	failures+=int(not step_pose(overlay,1.2))
	failures+=int(overlay.clears!=1 or overlay.bound_targets!=1 or not overlay._target_committed() \
		or not overlay._screen.visible or not overlay.display_qualified or not overlay.display_covered \
		or overlay._display_grace or overlay._committed!=state.partial.keys or state.stream.mesh_collections!=1)
	var committed_revision := overlay._plan_revision
	step_pose(overlay,1.2)
	failures+=int(overlay.clears!=1 or overlay.bound_targets!=1 or overlay._plan_revision!=committed_revision)
	await dispose(parent,state)
	return failures


static func in_flight_zoom_reversal_checks(parent: Node) -> int:
	var state := make_fixture(parent)
	if state.is_empty(): return 1
	var overlay: Probe=state.overlay
	var worker: RefCounted=state.worker
	state.planner.gate=Semaphore.new()
	overlay.output_scale=1.0
	var failures := int(not worker.submit(overlay._planning_request(1.0,false)))
	# 保持真实worker在倍率1.0的请求内，镜头先缩远到0.8，再逐帧反向到0.85。
	# 生产_step_geometry必须在两次真实_commit_ready_target入口前识别当前方向；
	# 不能等镜头重新超过旧请求倍率，才阻止已在途降档覆盖更清晰的显示。
	for scale_value: float in [0.8,0.85]:
		var canvas := Transform2D(0.0,Vector2.ZERO).scaled(Vector2.ONE*scale_value)
		canvas.origin=SIZE*0.5
		overlay._last_canvas=canvas
		var half := SIZE*0.5/scale_value
		overlay._step_geometry(Rect2(-half,half*2.0),scale_value,1.0/60.0)
	var expected: Array[bool]=[false,false,true,true]
	failures+=int(overlay.commit_zoom_directions!=expected or not overlay._zooming_in)
	failures+=int(worker.summary().submitted!=1 or not worker.busy() \
		or not is_equal_approx(overlay._last_selected_canvas.x.length(),1.0))
	if failures>0:
		print("[Tokyo map admission] in-flight zoom reversal expected=",expected,
			" observed=",overlay.commit_zoom_directions," submitted_scale=",overlay._last_selected_canvas.x.length())
	await dispose(parent,state)
	return failures


static func ready_downgrade_reversal_checks(parent: Node) -> int:
	var state := make_fixture(parent)
	if state.is_empty(): return 1
	var overlay: Probe=state.overlay
	var worker: RefCounted=state.worker
	# 两档投影范围相同，只有清晰度上限不同；当前细档和在途粗档均真实覆盖视口。
	var fine: Dictionary=overlay._catalogs[0]
	var coarse: Dictionary=fine.duplicate(true)
	coarse.max_scale=1.0
	for row: Dictionary in coarse.rows.values(): row.max_scale=1.0
	overlay._catalogs=[coarse,fine]
	overlay._committed_catalog=1
	overlay._target_catalog=0
	overlay._target=cut(state.full.keys,coarse)
	state.planner.response=candidate(overlay._target)
	state.planner.gate=Semaphore.new()
	overlay.output_scale=1.0
	var original_revision := overlay._plan_revision
	var failures := int(overlay._target_committed())
	failures+=int(not overlay._cut_covers_current_view(overlay._committed_cut,1) \
		or not overlay._target_covers_current_view())
	failures+=int(not worker.submit(overlay._planning_request(1.0,true)))
	# 缩远时资源尚未就绪；反转帧已就绪，也不能用旧粗档替换完整合格的细档。
	failures+=int(step_pose(overlay,0.8))
	failures+=int(overlay.bound_targets!=0 or overlay.clears!=0 or overlay._target_catalog!=0)
	overlay.ready_to_commit=true
	step_pose(overlay,0.85)
	var reversed_revision := overlay._plan_revision
	failures+=int(overlay.bound_targets!=0 or overlay.clears!=0 or overlay._committed_catalog!=1 \
		or overlay._target_catalog!=1 or not overlay._target_committed() \
		or reversed_revision!=original_revision+1 or not overlay._plan_dirty \
		or overlay._last_selected_size!=Vector2.ZERO or overlay.requests!=1 or overlay.requested_staging)
	# 120Hz呈现可夹着没有新物理步的帧；停镜也不能让同一旧粗档在下一帧偷渡提交。
	for idle_frame in 3:
		step_pose(overlay,0.85)
		failures+=int(overlay.bound_targets!=0 or overlay.clears!=0 or overlay._committed_catalog!=1 \
			or overlay._target_catalog!=1 or not overlay._target_committed() \
			or overlay._plan_revision!=reversed_revision or overlay.requests!=1 \
			or not overlay._screen.visible or not overlay.display_qualified or not overlay.display_covered)
	failures+=int(worker.summary().submitted!=1 or not worker.busy())
	# 随后明确缩远，再停镜。旧任务只能按revision丢弃；最新请求仍可决定并提交粗档。
	step_pose(overlay,0.8)
	state.planner.gate.post()
	var first_ready := await wait_ready(parent,worker)
	failures+=int(not first_ready)
	if not first_ready:
		await dispose(parent,state)
		return failures+1
	state.planner.gate=null
	step_pose(overlay,0.8)
	failures+=int(overlay._plan_rejected!=1 or overlay._plan_applied!=0 or overlay.bound_targets!=0 \
		or overlay._committed_catalog!=1 or worker.summary().submitted!=2 or not worker.busy() \
		or int(worker._job.get("request",{}).get("revision",-1))!=reversed_revision \
		or not is_equal_approx(float(worker._job.get("request",{}).get("scale",0.0)),0.8))
	var second_ready := await wait_ready(parent,worker)
	failures+=int(not second_ready)
	if second_ready: step_pose(overlay,0.8)
	failures+=int(overlay._plan_rejected!=1 or overlay._plan_applied!=1 or overlay.bound_targets!=1 \
		or overlay.clears!=1 or overlay._committed_catalog!=0 or not overlay._target_committed() \
		or worker.busy() or overlay._plan_dirty or not overlay._screen.visible \
		or not overlay.display_qualified or not overlay.display_covered)
	if failures>0:
		print("[Tokyo map admission] ready downgrade reversal fail=",failures,
			" binds=",overlay.bound_targets," clears=",overlay.clears," current=",overlay._committed_catalog,
			" rejected=",overlay._plan_rejected," applied=",overlay._plan_applied)
	await dispose(parent,state)
	return failures


static func revision_and_exit_checks(parent: Node) -> int:
	var state := make_fixture(parent)
	if state.is_empty(): return 1
	var failures := 0
	var overlay: Probe=state.overlay
	var worker: RefCounted=state.worker
	state.planner.gate=Semaphore.new()
	failures+=int(not worker.submit(overlay._planning_request(1.0,false)))
	overlay._plan_revision+=1
	state.planner.gate.post()
	var ready := await wait_ready(parent,worker)
	failures+=int(not ready)
	failures+=int(overlay._step_prepared_selection(1.0,false,false,false,true,false))
	failures+=int(overlay._plan_rejected!=1 or overlay._plan_applied!=0 or overlay.clears!=0 or overlay.requests!=0 \
		or overlay._target!=state.full or worker.summary().submitted!=2 or not worker.busy())
	# 错修订结果领取后立即以最新状态重采样；不重用排队的旧请求容器。
	failures+=int(int(worker._job.get("request",{}).get("revision",-1))!=overlay._plan_revision)
	var weak_overlay: WeakRef=weakref(overlay)
	# 第二个真实任务仍阻塞时退出，生产_exit_tree必须等待其完成并回收句柄。
	var releaser := WorkerThreadPool.add_task(release_later.bind(state.planner.gate),false,"Tokyo admission exit release")
	state.viewport.queue_free()
	await parent.get_tree().process_frame
	await parent.get_tree().process_frame
	WorkerThreadPool.wait_for_task_completion(releaser)
	failures+=int(weak_overlay.get_ref()!=null or worker.busy() or worker.ready() or not state.stream.closed \
		or worker.summary().submitted!=2 or worker.summary().completed!=2 or worker.summary().discarded!=1)
	state.stream.queue_free()
	await parent.get_tree().process_frame
	state.clear()
	return failures


static func run(parent: Node) -> int:
	var failures := await empty_display_trace_checks(parent)
	failures+=await direct_checks(parent)
	failures+=await stopped_camera_checks(parent)
	failures+=await native_guard_metadata_checks(parent)
	failures+=await native_guard_cadence_checks(parent)
	failures+=await pending_motion_sampling_checks(parent)
	failures+=await cold_jump_prediction_checks(parent)
	failures+=await pending_display_checks(parent)
	failures+=await pending_coverage_checks(parent)
	failures+=await ready_before_clear_checks(parent)
	failures+=await in_flight_zoom_reversal_checks(parent)
	failures+=await ready_downgrade_reversal_checks(parent)
	failures+=await revision_and_exit_checks(parent)
	print("[Tokyo map admission] fail=",failures)
	return failures
