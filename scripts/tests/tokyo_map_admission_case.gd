extends RefCounted
## 真实SceneTree中的异步接纳/退出门；只替代磁盘/GPU资源提交，不替代覆盖或接纳算法。
const Overlay := preload("res://scripts/rendering/tokyo_hlod_overlay.gd")
const Worker := preload("res://scripts/rendering/tokyo_map_plan_worker.gd")
const SIZE := Vector2(160,100)


class CompositeProbe extends "res://scripts/rendering/tokyo_volume_overlay.gd":
	func _presentation_bounds() -> Rect2:
		return Rect2(-100000,-100000,200000,200000)
	func _step_geometry(_bounds: Rect2, _scale: float, _delta: float) -> bool:
		return false
	func _configure_camera_depth(_basis: Basis) -> void:
		pass


class CheckpointGuard extends RefCounted:
	var ready := false
	var pending: Dictionary={}
	func camera_motion_checkpoint(scale_value: float) -> float:
		return 0.25 if scale_value<0.25 else 0.0
	func camera_motion_ready(_canvas: Transform2D, _output: Vector2, _rate: float, _velocity: Vector2, _measure: bool = true) -> bool:
		return ready
	func camera_motion_pending(canvas: Transform2D, _output: Vector2, _rate: float, _velocity: Vector2) -> void:
		pending={"canvas":canvas}


class Probe extends "res://scripts/rendering/tokyo_hlod_overlay.gd":
	var real_binding := false
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
	func _bind_target(_retained_nodes: Dictionary = {}) -> void:
		if real_binding:
			super._bind_target(_retained_nodes)
			return
		# 只替代GPU节点装配；真实提交入口仍负责资格、覆盖、租约与先后顺序。
		bound_targets+=1
		_committed=_target.keys.duplicate()
		_committed_catalog=_target_catalog
		_committed_cut=_target.duplicate(true)


class RequestProbe extends "res://scripts/rendering/tokyo_hlod_overlay.gd":
	func _process(_delta: float) -> void: pass


class SubsetProbe extends Probe:
	var unavailable := ""
	func _resources_ready(value: Dictionary, _catalog: int) -> bool:
		return unavailable not in value.get("keys",PackedStringArray())


class BindingPage extends Resource:
	var meshes: Array[ArrayMesh]=[]


class StreamProbe extends Node:
	var page: Resource
	var image: Texture2D
	func resource(_path: String) -> Resource: return page
	func texture(_path: String) -> Texture2D: return image
	var input_waiting := false
	var residency_limit := 96*1024*1024
	var residency_bytes := 0
	var residency_meshes := PackedStringArray()
	var residency_images := PackedStringArray()
	var _cache: Dictionary={}
	var _textures: Dictionary={}
	var _wanted := PackedStringArray()
	var _pending: Dictionary={}
	var _texture_wanted := PackedStringArray()
	var _texture_jobs: Dictionary={}
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


static func make_fixture(parent: Node, injected: Probe = null) -> Dictionary:
	var viewport := SubViewport.new()
	viewport.size=Vector2i(SIZE)
	viewport.render_target_update_mode=SubViewport.UPDATE_DISABLED
	parent.add_child(viewport)
	var source := Node2D.new()
	viewport.add_child(source)
	var stream := StreamProbe.new()
	parent.add_child(stream)
	var overlay: Probe=Probe.new() if injected==null else injected
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


static func incremental_binding_checks(parent: Node) -> int:
	var state := make_fixture(parent)
	if state.is_empty(): return 1
	var overlay: Probe=state.overlay
	var stream: StreamProbe=state.stream
	overlay.real_binding=true;overlay._return_cache=true;overlay.ready_to_commit=true
	overlay._city=Node3D.new();overlay.add_child(overlay._city)
	var shader := Shader.new()
	shader.code="shader_type spatial; uniform sampler2D overview; uniform bool facade_detail=false; void fragment(){ ALBEDO=vec3(1.0); }"
	overlay._surface=shader;overlay._formal_surface=shader
	for row: Dictionary in overlay._catalogs[0].rows.values(): row["texture"]={"bounds":row.bounds}
	var page := BindingPage.new()
	page.meshes=[Overlay.Ground.plane(Rect2(0,0,10,10),Rect2(0,0,1,1)),Overlay.Ground.plane(Rect2(10,0,10,10),Rect2(0,0,1,1))]
	stream.page=page
	stream.image=ImageTexture.create_from_image(Image.create(4,4,false,Image.FORMAT_RGBA8))
	overlay._clear_current()
	var failures := int(not overlay._commit_ready_target(1.0) or overlay._nodes.size()!=9)
	var first: Array=overlay._hlod_binding_nodes.get("0:0",[]).duplicate()
	var removed: Array=overlay._hlod_binding_nodes.get("0:2",[]).duplicate()
	overlay._return_cache=false
	failures+=int(not overlay._take_reusable_hlod_nodes().is_empty() or overlay._nodes.size()!=9)
	overlay._return_cache=true;overlay._target_catalog=-2
	failures+=int(not overlay._take_reusable_hlod_nodes().is_empty() or overlay._nodes.size()!=9)
	overlay._target_catalog=1
	failures+=int(not overlay._take_reusable_hlod_nodes().is_empty() or overlay._nodes.size()!=9)
	overlay._target_catalog=0
	overlay._target=cut(PackedStringArray(["0:0","0:1"]),overlay._catalogs[0])
	failures+=int(not overlay._commit_ready_target(1.0) or overlay._nodes.size()!=6 or overlay.reused_hlod_pages!=2)
	failures+=int(overlay._hlod_binding_nodes.get("0:0",[])!=first or overlay.created_hlod_pages!=3)
	for value: Variant in removed: failures+=int(is_instance_valid(value))
	# 缺资源不能先动旧节点；已释放缓存项也不能穿过类型守卫。
	overlay.ready_to_commit=false;overlay._target=state.full
	failures+=int(overlay._commit_ready_target(1.0) or overlay._nodes.size()!=6 or overlay._hlod_binding_nodes.get("0:0",[])!=first)
	overlay.ready_to_commit=true
	(first[0] as MeshInstance3D).free()
	failures+=int(not overlay._commit_ready_target(1.0) or overlay._nodes.size()!=9 or overlay.created_hlod_pages!=5)
	var held: Array=[]
	for value: Variant in overlay._nodes: held.append(weakref(value))
	await dispose(parent,state)
	for value: WeakRef in held: failures+=int(value.get_ref()!=null)
	print("[Tokyo incremental binding] fail=",failures)
	return failures


static func compact_stream_snapshot_checks(parent: Node) -> int:
	var state := make_fixture(parent)
	if state.is_empty(): return 1
	var overlay: Probe=state.overlay
	var stream: StreamProbe=state.stream
	overlay._return_cache=true
	stream._cache={"ready_mesh":null};stream._textures={"ready_image":null}
	stream._wanted=PackedStringArray(["wanted_mesh"]);stream._pending={"pending_mesh":null}
	stream._texture_wanted=PackedStringArray(["wanted_image"]);stream._texture_jobs={"pending_image":null}
	var request := overlay._planning_request(1.0,false)
	var failures := int(request.stream._cache!=PackedStringArray(["ready_mesh"]) or request.stream._textures!=PackedStringArray(["ready_image"]))
	failures+=int(request.stream.planned_meshes!=PackedStringArray(["wanted_mesh","pending_mesh"]))
	failures+=int(request.stream.planned_images!=PackedStringArray(["wanted_image","pending_image"]) or not Worker.pure(request))
	failures+=int(stream._wanted!=PackedStringArray(["wanted_mesh"]) or stream._texture_wanted!=PackedStringArray(["wanted_image"]))
	stream._wanted.append("later");stream._cache["later"]=null
	failures+=int("later" in request.stream._cache or "later" in request.stream.planned_meshes)
	await dispose(parent,state)
	print("[Tokyo compact stream snapshot] fail=",failures)
	return failures


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


static func prepared_motion_checks(parent: Node) -> int:
	var failures := 0
	for scenario: String in ["ready","completed","disabled","missing","coverage","quality","faces","bytes","union"]:
		var state := make_fixture(parent)
		if state.is_empty(): return failures+1
		var overlay: Probe=state.overlay
		overlay._guard_prefetch=scenario!="disabled"
		overlay.ready_to_commit=scenario not in ["missing","completed"]
		if scenario=="completed": state.stream.ready_after_collect=weakref(overlay)
		overlay._enabled=true
		var next: Dictionary=state.full.duplicate(true)
		if scenario=="coverage": next=state.partial.duplicate(true)
		if scenario=="quality": overlay._catalogs[0].max_scale=0.5
		if scenario=="faces": next.triangles=240001
		if scenario=="bytes": next.bytes=overlay.display_budget+1
		if scenario=="union": state.stream.residency_limit=1
		overlay._prepared_motion_cuts=[{"catalog":0,"cut":next}]
		overlay._committed_cut=state.partial.duplicate(true)
		overlay._committed=state.partial.keys.duplicate()
		overlay._target=state.partial.duplicate(true)
		overlay._target["prefetch_extra"]=[{"mesh":"next_step","image":"next_image"}]
		var accepted := overlay.camera_motion_ready(pose(Vector2(0,300)),SIZE,0.0,Vector2(0,1000))
		var expected := scenario in ["ready","completed"]
		failures+=int(accepted!=expected)
		failures+=int(overlay.bound_targets!=int(expected))
		if expected: failures+=int(overlay._target.get("prefetch_extra",[])!=[{"mesh":"next_step","image":"next_image"}])
		if not expected: failures+=int(overlay.clears!=0 or overlay._committed!=state.partial.keys)
		if scenario=="completed": failures+=int(state.stream.mesh_collections!=1)
		overlay._deactivate()
		failures+=int(not overlay._prepared_motion_cuts.is_empty())
		await dispose(parent,state)
	print("[Tokyo prepared motion] fail=",failures)
	return failures


static func resource_priority_checks(parent: Node) -> int:
	var viewport := SubViewport.new();viewport.size=Vector2i(SIZE);parent.add_child(viewport)
	var source := Node2D.new();viewport.add_child(source)
	var overlay := RequestProbe.new()
	var contract := preload("res://scripts/rendering/tokyo_hlod_manifest.gd")
	var data := preload("res://scripts/tests/test_tokyo_hlod_manifest.gd").fixture()
	data.max_scale=2.0
	var catalog := contract.normalize(data);catalog["range"]=[0.05,2.0]
	overlay._catalogs=[catalog];overlay._geometry=catalog.geometry;overlay._textures=catalog.textures
	overlay._source_ref=weakref(source);overlay._last_size=SIZE
	var center := Vector2(-12000,-12000);overlay._last_canvas=pose(center)
	var full := contract.select(catalog,center,1.0,0.0,Vector2(6000,6000),false,overlay.display_budget,{"stable_hlod_leaves":true})
	overlay._target=full;overlay._target_catalog=0
	var visible := overlay._visible_target_keys()
	var upcoming := ""
	var outside := ""
	for key: String in full.keys:
		if key not in visible: upcoming=key
	for key: String in catalog.rows:
		if key not in full.keys: outside=key;break
	var failures := int(upcoming.is_empty() or outside.is_empty())
	if failures==0:
		overlay._prepared_motion_cuts=[{"catalog":0,"cut":{"keys":PackedStringArray([outside,upcoming])}}]
		var stream := preload("res://scripts/rendering/tokyo_hlod_stream.gd").new()
		failures+=int(not stream.configure_hlod(source,catalog.geometry,catalog.textures))
		stream.visible_io_first=true;overlay._stream=stream
		var before := var_to_bytes(full)
		overlay._request_target(false)
		failures+=int(before!=var_to_bytes(overlay._target) or stream.started!=0 or stream.texture_started!=0)
		var expected_meshes := PackedStringArray();var expected_images := PackedStringArray()
		for key: String in full.keys:
			expected_meshes.append(catalog.rows[key].native_geometry.path)
			expected_images.append(catalog.rows[key].native_texture.path)
		var actual_meshes: PackedStringArray=stream._wanted.duplicate();var actual_images: PackedStringArray=stream._texture_wanted.duplicate()
		expected_meshes=stream._paths(expected_meshes)
		actual_meshes.sort();actual_images.sort();expected_meshes.sort();expected_images.sort()
		failures+=int(actual_meshes!=expected_meshes or actual_images!=expected_images)
		failures+=int(catalog.rows[outside].native_texture.path in stream._texture_wanted)
		var next_image: String=catalog.rows[upcoming].native_texture.path
		for key: String in visible:
			failures+=int(stream._texture_wanted.find(catalog.rows[key].native_texture.path)>stream._texture_wanted.find(next_image))
		for key: String in full.keys:
			if key!=upcoming and key not in visible:
				failures+=int(stream._texture_wanted.find(next_image)>stream._texture_wanted.find(catalog.rows[key].native_texture.path))

		# 第一段路径已驻留时，必须继续把第二段缺失资源提前，不能被空优先级截断。
		var later := ""
		for key: String in full.keys:
			if key not in visible and key!=upcoming: later=key;break
		failures+=int(later.is_empty())
		if not later.is_empty():
			var loaded_paths := stream._paths(PackedStringArray([catalog.rows[upcoming].native_geometry.path]))
			for path: String in loaded_paths: stream._cache[path]={}
			stream._textures[next_image]={}
			overlay._prepared_motion_cuts=[{"catalog":0,"cut":{"keys":PackedStringArray([upcoming])}},
				{"catalog":0,"cut":{"keys":PackedStringArray([later])}}]
			overlay._request_target(false)
			var later_image: String=catalog.rows[later].native_texture.path
			failures+=int(later_image not in stream.visible_images or next_image in stream.visible_images)
			failures+=int(stream._texture_wanted.find(later_image)>stream._texture_wanted.find(next_image))
			var still_meshes: PackedStringArray=stream._wanted.duplicate()
			var still_images: PackedStringArray=stream._texture_wanted.duplicate()
			still_meshes.sort();still_images.sort()
			failures+=int(still_meshes!=expected_meshes or still_images!=expected_images)
			for path: String in loaded_paths: stream._cache.erase(path)
			stream._textures.erase(next_image)
		stream.close();stream.free();overlay._stream=null
	overlay.free();viewport.queue_free();await parent.get_tree().process_frame
	print("[Tokyo resource priority] fail=",failures)
	return failures


static func visible_prepared_checks(parent: Node) -> int:
	var failures := 0
	var contract := preload("res://scripts/rendering/tokyo_hlod_manifest.gd")
	for missing_visible: bool in [false,true]:
		var overlay := SubsetProbe.new()
		var state := make_fixture(parent,overlay)
		var data := preload("res://scripts/tests/test_tokyo_hlod_manifest.gd").fixture()
		data.max_scale=2.0
		var catalog := contract.normalize(data)
		catalog["range"]=[0.05,2.0]
		overlay._catalogs=[catalog];overlay._geometry=catalog.geometry;overlay._textures=catalog.textures
		overlay._archive.bounds=catalog.bounds
		overlay._guard_prefetch=true
		overlay._selection_work["stable_hlod_leaves"]=true
		var center := Vector2(-12000,-12000)
		overlay._last_canvas=pose(center)
		var full := contract.select(catalog,center,1.0,0.0,Vector2(6000,6000),false,overlay.display_budget,overlay._selection_work)
		var visible := contract.visible_keys(full,center,1.0,0.0,SIZE)
		failures+=int(visible.is_empty() or visible.size()>=full.keys.size())
		for key: String in full.keys:
			if (key in visible)==missing_visible:
				overlay.unavailable=key
				break
		overlay._target=full;overlay._target_catalog=0
		failures+=int(overlay._visible_target_keys()!=visible)
		var ordered := overlay._prioritized_target_keys()
		failures+=int(ordered.size()!=full.keys.size() or ordered[0] not in visible)
		for key: String in full.keys: failures+=int(key not in ordered)
		overlay._prepared_motion_cuts=[{"catalog":0,"cut":full}]
		var accepted := overlay._stage_prepared_motion(1.0)
		failures+=int(accepted==missing_visible)
		if accepted:
			failures+=int(overlay.unavailable in overlay._target.keys or overlay._target.guard_prefetch_keys!=full.keys)
			failures+=int(not overlay._cut_covers_current_view(overlay._target,0))
		await dispose(parent,state)
	print("[Tokyo visible prepared handoff] fail=",failures)
	return failures


static func resident_motion_checks(parent: Node) -> int:
	var failures := 0
	for scenario: String in ["ready","disabled","missing","quality","budget","union"]:
		var state := make_fixture(parent)
		if state.is_empty(): return failures+1
		var overlay: Probe=state.overlay
		var data := preload("res://scripts/tests/test_tokyo_hlod_manifest.gd").fixture()
		data.max_scale=0.4
		data["far_summary_recipe"]={"path":"res://fixture/far.json","sha256":"a".repeat(64)}
		var catalog := preload("res://scripts/rendering/tokyo_hlod_manifest.gd").normalize(data)
		overlay._catalogs=[catalog];overlay._geometry=catalog.geometry;overlay._textures=catalog.textures
		overlay._archive.bounds=catalog.bounds
		overlay._foundation=preload("res://scripts/rendering/tokyo_hlod_foundation.gd").plan(overlay._catalogs)
		overlay._guard_prefetch=scenario!="disabled";overlay.ready_to_commit=scenario!="missing"
		overlay._committed=PackedStringArray();overlay._committed_cut={};overlay._committed_catalog=-1
		overlay._target={};overlay._target_catalog=-1
		overlay._last_canvas=Transform2D.IDENTITY.scaled(Vector2.ONE*0.2);overlay._last_canvas.origin=SIZE*0.5
		if scenario=="budget": overlay.display_budget=1
		if scenario=="union": state.stream.residency_limit=1
		var accepted := overlay._stage_cached_motion(0.41 if scenario=="quality" else 0.2)
		failures+=int(accepted!=(scenario=="ready") or overlay.requests!=int(scenario=="ready"))
		# 同一帧不因小步准入反复执行空间选择；缺资源不能转为同步加载。
		if scenario!="quality": failures+=int(overlay._stage_cached_motion(0.2))
		if scenario=="ready":
			failures+=int(overlay.cached_motion_selects!=1 or not overlay._commit_ready_target(0.2) or overlay._committed.size()!=16)
		await dispose(parent,state)
	print("[Tokyo resident motion] fail=",failures)
	return failures


static func cached_hlod_motion_checks(parent: Node) -> int:
	var failures := 0
	for scenario: String in ["ready","missing","budget","disabled"]:
		var state := make_fixture(parent)
		if state.is_empty(): return failures+1
		var overlay: Probe=state.overlay
		var data := preload("res://scripts/tests/test_tokyo_hlod_manifest.gd").fixture()
		data.max_scale=2.0
		var catalog := preload("res://scripts/rendering/tokyo_hlod_manifest.gd").normalize(data)
		catalog["range"]=[0.8,2.0]
		overlay._catalogs=[catalog];overlay._geometry=catalog.geometry;overlay._textures=catalog.textures
		overlay._archive.bounds=catalog.bounds
		overlay._foundation={};overlay._guard_prefetch=scenario!="disabled";overlay.ready_to_commit=true
		overlay._target={};overlay._target_catalog=-1
		overlay._committed_cut={};overlay._committed=PackedStringArray();overlay._committed_catalog=-1
		for path: String in catalog.geometry: state.stream._cache[path]=true
		if scenario!="missing":
			for path: String in catalog.textures: state.stream._textures[path]=true
		if scenario=="budget": overlay.display_budget=1
		var accepted := overlay.camera_motion_ready(pose(),SIZE,0.0,Vector2.ZERO)
		failures+=int(accepted!=(scenario=="ready"))
		if accepted: failures+=int(overlay._committed_catalog!=0 or overlay._committed.is_empty() or overlay.bound_targets!=1)
		else: failures+=int(overlay.requests!=0 or overlay.clears!=0)
		await dispose(parent,state)
	print("[Tokyo cached HLOD motion] fail=",failures)
	return failures


static func summary_motion_checks(parent: Node) -> int:
	var failures := 0
	var contract := preload("res://scripts/rendering/tokyo_hlod_manifest.gd")
	var foundation := preload("res://scripts/rendering/tokyo_hlod_foundation.gd")
	for scenario: String in ["ready","missing","budget","union","disabled"]:
		var state := make_fixture(parent)
		if state.is_empty(): return failures+1
		var overlay: Probe=state.overlay
		var data := preload("res://scripts/tests/test_tokyo_hlod_manifest.gd").fixture()
		data.max_scale=10.0
		data["far_summary_recipe"]={"path":"res://fixture/motion.json","sha256":"a".repeat(64)}
		data["resident_motion_summary"]={"schema":1,"preferred_max_scale":0.8,"formal_unchanged":true}
		var catalog := contract.normalize(data)
		overlay._catalogs=[catalog];overlay._geometry=catalog.geometry;overlay._textures=catalog.textures
		overlay._archive.bounds=catalog.bounds;overlay._foundation=foundation.plan(overlay._catalogs)
		overlay._guard_prefetch=scenario!="disabled";overlay.ready_to_commit=scenario!="missing"
		overlay._committed=PackedStringArray();overlay._committed_cut={};overlay._committed_catalog=-1
		overlay._target={};overlay._target_catalog=-1
		var canvas := Transform2D.IDENTITY.scaled(Vector2.ONE*8.0)
		canvas.origin=SIZE*0.5
		if scenario=="budget": overlay.display_budget=1
		if scenario=="union": state.stream.residency_limit=1
		var accepted := overlay.camera_motion_ready(canvas,SIZE,2.0,Vector2(10000,0))
		failures+=int(accepted!=(scenario=="ready"))
		if accepted:
			failures+=int(overlay._committed.size()!=16 or overlay.summary_motion_commits!=1 or overlay.camera_wait_frames!=0)
			# 后台真实请求也必须看见已驻留根；只传就绪键，不复制细缓存和资源对象。
			overlay._last_canvas=canvas;overlay._last_size=SIZE;overlay._plan_readiness=false
			state.stream.residency_meshes=overlay._foundation.meshes
			state.stream.residency_images=overlay._foundation.images
			for path: String in state.stream.residency_meshes:
				for part: String in overlay._geometry[path].get("components",{path:{}}): state.stream._cache[part]=true
			for path: String in state.stream.residency_images: state.stream._textures[path]=true
			state.stream._cache["nonresident_fixture"]=true
			var request := overlay._planning_request(8.0,false)
			failures+=int(request.stream._cache.is_empty() or request.stream._textures.is_empty() or request.stream._cache.has("nonresident_fixture") or not Worker.pure(request))
			state.stream.residency_meshes=PackedStringArray();state.stream.residency_images=PackedStringArray()
			state.stream._cache.clear();state.stream._textures.clear()
			# 已显示根块激活运动模式不能重绑GPU；同样必须获得150ms细节稳定期。
			overlay._committed_cut.erase("motion_summary");overlay._target.erase("motion_summary")
			var active := overlay._committed_cut.duplicate(true)
			active["motion_summary"]=true
			var unchanged_clears := overlay.clears
			overlay._admit_prepared_plan({"status":"candidate","catalog":0,"cut":active,"force_replan":true,"ground_candidate":{},"native_screen_bridge":{}},request,8.0,true,false)
			failures+=int(overlay.summary_motion_adoptions!=1 or not overlay._committed_cut.get("motion_summary",false) or overlay.clears!=unchanged_clears)
			# 运动概括的宽资格不是细节质量排名；放大时仍允许恢复清晰细档。
			var fine := catalog.duplicate()
			fine.erase("far_summary_recipe");fine.erase("resident_motion_summary")
			fine.max_scale=9.0
			overlay._catalogs.append(fine)
			overlay._target=contract.select(fine,Vector2.ZERO,8.0,0,SIZE)
			overlay._target_catalog=1;overlay._zooming_in=true
			overlay._last_canvas=canvas;overlay._last_size=SIZE
			failures+=int(overlay._commit_ready_target(8.0))
			overlay._pan_velocity=Vector2(2000,0)
			await parent.get_tree().create_timer(0.16).timeout
			failures+=int(overlay._commit_ready_target(8.0))
			# 高速阶段只有细节延后，镜头继续由完整常驻模型放行。
			var moved := canvas
			moved.origin-=Vector2(8000,0)
			failures+=int(not overlay.camera_motion_ready(moved,SIZE,0.0,Vector2(2000,0)) or overlay.camera_wait_frames!=0)
			overlay._pan_velocity=Vector2.ZERO;overlay._zoom_rate=0.0
			await parent.get_tree().create_timer(0.16).timeout
			# 正常跟随飞行不是操作者高速移镜；扣除目标平移后应恢复细档。
			var tracking_camera := Camera2D.new()
			state.source.add_child(tracking_camera)
			tracking_camera.make_current()
			tracking_camera.set_meta(&"map_return_hint",{"following":true,"target_velocity":Vector2(2000,0)})
			overlay._pan_velocity=Vector2(2000,0)
			failures+=int(not overlay._commit_ready_target(8.0) or overlay._committed_catalog!=1 or overlay.summary_motion_refinements!=1)
		else: failures+=int(overlay.clears!=0 or overlay.requests!=0)
		await dispose(parent,state)
	print("[Tokyo summary motion] fail=",failures)
	return failures


static func cached_native_motion_checks(parent: Node) -> int:
	# 更便宜的父页尚未加载，等价子页已驻留：即时接管应选完整子树，不能再读父页。
	var failures := 0
	var box := AABB(Vector3(-1000,0,-1000),Vector3(2000,0,2000))
	var child := {"path":"native/child","boxes":[box,AABB(),AABB()],"triangles":[2,0,0],"bytes":120}
	var root := {"path":"native/root","boxes":[box,AABB(),AABB()],"triangles":[2,0,0],"bytes":100,"children":[child]}
	var snapshot := {"schema":1,"configurations":{"lod5_full":[root]},"partition_roots":{},"ground_roots":{},
		"ground_limits":{},"pages":{"native/root":{"components":{"native/root":true}},"native/child":{"components":{"native/child":true}}}}
	for resident: bool in [true,false]:
		var state := make_fixture(parent)
		if state.is_empty(): return failures+1
		var overlay: Probe=state.overlay
		overlay._native=preload("res://scripts/rendering/tokyo_hlod_native.gd").new()
		if not overlay._native.configure_selection_snapshot(snapshot,{"background":true,"epoch":0,"display_limit":96*1024*1024,"native_page_limit":16}):
			failures+=1;await dispose(parent,state);continue
		overlay._geometry["native/root"]={"bytes":100};overlay._geometry["native/child"]={"bytes":120}
		overlay._guard_prefetch=true;overlay.ready_to_commit=true;overlay._foundation={}
		overlay._target_catalog=-1;overlay._committed_catalog=-1
		overlay._target={};overlay._committed_cut={};overlay._committed=PackedStringArray()
		state.stream._cache={"native/child":true} if resident else {}
		var plain: Dictionary=overlay._native.select(Vector2.ZERO,1.0,0,SIZE,"lod5_full",overlay.display_budget)
		failures+=int(plain.keys!=PackedStringArray(["native/root"]))
		var accepted := overlay._stage_cached_motion(1.0)
		failures+=int(accepted!=resident)
		if accepted: failures+=int(overlay._target.keys!=PackedStringArray(["native/child"]) or not overlay._commit_ready_target(1.0))
		else: failures+=int(overlay.requests!=0 or overlay.clears!=0)
		await dispose(parent,state)
	print("[Tokyo cached native motion] fail=",failures)
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


static func evolving_camera_demand_checks(parent: Node) -> int:
	var state := make_fixture(parent)
	if state.is_empty(): return 1
	var overlay: Probe=state.overlay
	var southern := cut(PackedStringArray(["0:1"]),overlay._catalogs[0])
	overlay.camera_motion_pending(pose(Vector2(0,200)),SIZE,0.0,Vector2(0,100))
	var request := overlay._planning_request(1.0,false)
	# 后台期间继续按键；候选虽不是最后一次请求，但仍完整覆盖最新需求，应允许暂存。
	overlay.camera_motion_pending(pose(Vector2(0,220)),SIZE,0.0,Vector2(0,100))
	var failures := int(not overlay._admit_prepared_plan(candidate(southern),request,1.0,true,false))
	failures+=int(overlay.requests!=1 or not overlay.requested_staging or overlay.clears!=0 \
		or overlay._target.keys!=southern.keys or overlay._committed!=state.full.keys)
	await parent.get_tree().process_frame
	# 反向离开候选覆盖后，旧请求必须拒绝，不能拿旧姿态的证明放行。
	overlay.camera_motion_pending(pose(Vector2(0,-220)),SIZE,0.0,Vector2(0,-100))
	failures+=int(overlay._admit_prepared_plan(candidate(southern),request,1.0,true,false))
	failures+=int(overlay.requests!=1 or overlay.clears!=0 or overlay._committed!=state.full.keys)
	await dispose(parent,state)
	print("[Tokyo map admission] evolving_camera_demand fail=",failures)
	return failures


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


static func pending_zoom_bridge_checks(parent: Node) -> int:
	var failures := 0
	for mode: String in ["zoom_out","reversed","stale_position","unsafe_display"]:
		var state := make_fixture(parent)
		if state.is_empty(): failures+=1;continue
		var overlay: Probe=state.overlay
		var coarse: Dictionary=overlay._catalogs[0].duplicate(true)
		coarse.max_scale=0.5
		for row: Dictionary in coarse.rows.values(): row.max_scale=0.5
		overlay._catalogs.append(coarse)
		var next: Dictionary=state.full.duplicate(true)
		if mode=="stale_position": next=cut(PackedStringArray(["0:1"]),coarse)
		next["handoff_bridge"]=true
		var plan := candidate(next)
		plan.catalog=1
		var canvas := Transform2D.IDENTITY.scaled(Vector2.ONE*0.3)
		canvas.origin=SIZE*0.5
		if mode=="stale_position": canvas.origin-=Vector2(0,400)*0.3
		overlay.camera_motion_pending(canvas,SIZE,-2.0,Vector2.ZERO)
		var request := {"camera_demand":true,"canvas":canvas,"size":SIZE}
		if mode=="reversed": overlay._camera_demand.rate=2.8
		if mode=="stale_position": overlay._camera_demand.canvas.origin+=Vector2(0,800)*0.3
		var accepted := overlay._admit_prepared_plan(plan,request,1.0,mode!="unsafe_display",false)
		var expected := mode=="zoom_out"
		var case_failures := int(accepted!=expected or overlay.requests!=int(expected) or overlay.clears!=0 \
			or overlay._committed_catalog!=0 or overlay._committed!=state.full.keys)
		if expected:
			overlay.ready_to_commit=true
			# 允许先加载，不代表允许在原近景显示低档；只有镜头事务到达目标才绑定。
			case_failures+=int(overlay._commit_ready_target(1.0) or overlay.bound_targets!=0)
			await parent.get_tree().process_frame
			overlay._last_canvas=canvas
			case_failures+=int(not overlay._commit_ready_target(0.3) or overlay.bound_targets!=1 \
				or overlay._committed_catalog!=1 or overlay.clears!=1)
		if case_failures: print("[Tokyo map admission] zoom_bridge mode=",mode," fail=",case_failures)
		failures+=case_failures
		await dispose(parent,state)
	print("[Tokyo map admission] pending_zoom_bridge fail=",failures)
	return failures


static func pending_path_checkpoint_checks(parent: Node) -> int:
	var failures := 0
	for mode: String in ["forward","reverse","untagged"]:
		var state := make_fixture(parent)
		if state.is_empty(): failures+=1;continue
		var overlay: Probe=state.overlay
		var catalog: Dictionary=overlay._catalogs[0].duplicate(true)
		catalog.rows["0:1"].bounds=[-1000,60,1000,300]
		var box := AABB(Vector3(-1000,0,60),Vector3(2000,0,240))
		catalog.roots[1].boxes=[box,AABB(),AABB()];catalog.roots[1].coverage_box=box
		# 保留未选择的南侧区域，不能把夹具中的空白当成覆盖完成。
		var south := AABB(Vector3(-1000,0,300),Vector3(2000,0,700))
		catalog.roots.append({"key":"0:3","boxes":[south,AABB(),AABB()],"coverage_box":south,"triangles":[2,0,0],"bytes":200})
		overlay._catalogs.append(catalog)
		var next := cut(PackedStringArray(["0:1"]),catalog)
		next["motion_checkpoint"]=mode!="untagged"
		var plan := candidate(next);plan.catalog=1
		overlay.camera_motion_pending(pose(Vector2(0,440)),SIZE,0.0,Vector2(0,1000))
		var request := {"camera_demand":true,"canvas":pose(Vector2(0,440)),"size":SIZE}
		if mode=="reverse": overlay.camera_motion_pending(pose(Vector2(0,-440)),SIZE,0.0,Vector2(0,-1000))
		var accepted := overlay._admit_prepared_plan(plan,request,1.0,true,false)
		var expected := mode=="forward"
		var case_failures := int(accepted!=expected or overlay.requests!=int(expected) or overlay.clears!=0)
		if expected:
			overlay.ready_to_commit=true
			case_failures+=int(overlay._commit_ready_target(1.0) or overlay.bound_targets!=0)
			await parent.get_tree().process_frame
			overlay._last_canvas=pose(Vector2(0,220))
			case_failures+=int(not overlay._commit_ready_target(1.0) or overlay.bound_targets!=1 or overlay.clears!=1)
		if case_failures: print("[Tokyo map admission] path mode=",mode," fail=",case_failures)
		failures+=case_failures
		await dispose(parent,state)
	print("[Tokyo map admission] pending_path_checkpoint fail=",failures)
	return failures


static func cold_jump_prediction_checks(parent: Node) -> int:
	var failures := 0
	for scenario in 4:
		var cold_jump := scenario!=1
		var continuous_hint := scenario==2
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
		if continuous_hint or scenario==3:
			var canvas := Transform2D(0.0,Vector2.ZERO).scaled(Vector2.ONE*next_scale)
			canvas.origin=SIZE*0.5-canvas*center
			if scenario==3: canvas.origin+=Vector2(1,0)
			overlay._camera_motion_hint={"canvas":canvas,"size":SIZE,"rate":-0.5,"velocity":Vector2(9000,0)}
		step_pose(overlay,next_scale,center,delta)
		if continuous_hint:
			case_failures+=int(overlay._pan_velocity!=Vector2(9000,0) or overlay._zoom_rate!=-0.5 or overlay._last_zoom_direction!=-1 or not overlay._camera_motion_hint.is_empty())
		elif cold_jump:
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
				if continuous_hint:
					case_failures+=int(request.pan_velocity!=Vector2(9000,0) or request.zoom_rate!=-0.5)
				elif cold_jump:
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
	# 活动地图清屏后不能继续推进镜头；新切面完整就绪并提交后才放行。
	overlay._enabled=true
	overlay._committed=PackedStringArray()
	overlay._committed_cut={}
	overlay._committed_catalog=-1
	overlay._screen.visible=false
	overlay._target=state.full.duplicate(true)
	overlay._target_catalog=0
	state.stream.ready_after_collect=null # 此子案例尚未完成，不能沿用上一案例的完成件。
	overlay.ready_to_commit=false
	var motion_canvas := pose()
	var motion_ready := overlay.camera_motion_ready(motion_canvas,SIZE,0.1,Vector2.ZERO)
	failures+=int(motion_ready or overlay.camera_wait_frames!=1 or overlay._camera_demand.is_empty() or not state.stream.input_waiting)
	overlay.ready_to_commit=true
	motion_ready=overlay.camera_motion_ready(motion_canvas,SIZE,0.1,Vector2.ZERO)
	failures+=int(not motion_ready or overlay._committed!=state.full.keys or not overlay._screen.visible \
		or not overlay._camera_demand.is_empty() or state.stream.input_waiting)
	overlay.camera_motion_pending(pose(Vector2(0,400)),SIZE,0.0,Vector2(0,1000))
	failures+=int(not state.stream.input_waiting)
	overlay._deactivate()
	failures+=int(state.stream.input_waiting)
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


static func subpixel_composite_checks(parent: Node) -> int:
	var owner_view := SubViewport.new()
	owner_view.size=Vector2i(1920,1080)
	owner_view.render_target_update_mode=SubViewport.UPDATE_DISABLED
	parent.add_child(owner_view)
	var source := Node2D.new()
	owner_view.add_child(source)
	var camera := Camera2D.new()
	camera.enabled=false
	source.add_child(camera)
	var overlay := CompositeProbe.new()
	source.add_child(overlay)
	overlay.set_process(false)
	overlay._exact_canvas_tracking=true
	overlay._source_ref=weakref(source);overlay._camera_ref=weakref(camera)
	overlay._viewport=SubViewport.new()
	overlay._viewport.render_target_update_mode=SubViewport.UPDATE_DISABLED
	overlay.add_child(overlay._viewport)
	overlay._city=Node3D.new();overlay._viewport.add_child(overlay._city)
	overlay._camera=Camera3D.new();overlay._viewport.add_child(overlay._camera)
	overlay._camera.projection=Camera3D.PROJECTION_ORTHOGONAL
	overlay._screen=Sprite2D.new();overlay._screen.centered=false
	overlay._screen.texture=overlay._viewport.get_texture()
	overlay.add_child(overlay._screen)
	overlay._composite.shader=overlay.COMPOSITE_SHADER
	owner_view.canvas_transform=Transform2D(0.0,Vector2(3400,-62000)).scaled_local(Vector2.ONE*4.22)
	overlay._process_map(1.0/120.0)
	var failures := 0
	var count := overlay.redraws
	# 实测返回末段的 .6 像素平移在大坐标 relative epsilon 内，合成层却已错开一行。
	var shifted := owner_view.canvas_transform
	shifted.origin+=Vector2(0.025,-0.6)
	owner_view.canvas_transform=shifted
	overlay._process_map(1.0/120.0)
	var rect: Rect2=overlay._screen.get_global_transform_with_canvas()*overlay._screen.get_rect()
	failures+=int(rect.position.length()>0.05 or rect.end.distance_to(Vector2(owner_view.size))>0.05 \
		or overlay.redraws!=count+1 or overlay._last_canvas!=shifted)
	count=overlay.redraws
	overlay._process_map(1.0/120.0)
	failures+=int(overlay.redraws!=count)
	owner_view.queue_free()
	await parent.get_tree().process_frame
	print("[Tokyo subpixel composite] fail=",failures)
	return failures


static func pending_display_progress_checks() -> int:
	var planner := preload("res://scripts/rendering/tokyo_map_planner.gd").new()
	var catalog := catalog_fixture()
	catalog["range"]=[0.1,5.0]
	planner._catalogs=[catalog]
	planner._target_catalog=0;planner._committed_catalog=0
	planner._target=cut(PackedStringArray(["0:0"]),catalog)
	planner._committed=PackedStringArray(["0:0","0:1","0:2"])
	planner._committed_cut=cut(planner._committed,catalog)
	planner._logical=SIZE;planner._last_size=SIZE;planner._last_canvas=pose()
	planner._bounds=Rect2(-1000,-1000,2000,2000);planner._zoom_rate=-2.0
	var failures := int(planner._pending_hlod_covers(1.0,true))
	planner._flags["display_compaction"]=true
	# 实际视野已完整、仅额外96px不足：完成此在途页。真正移出或失格仍拒绝。
	failures+=int(not planner._pending_hlod_covers(1.0,true))
	planner._last_canvas=pose(Vector2(0,20))
	failures+=int(planner._pending_hlod_covers(1.0,true))
	planner._last_canvas=pose()
	catalog.rows["0:0"].max_scale=0.5
	failures+=int(planner._pending_hlod_covers(1.0,true))
	print("[Tokyo pending display progress] fail=",failures)
	return failures


static func pending_zoom_checkpoint_checks(parent: Node) -> int:
	var failures := 0
	for tagged: bool in [true,false]:
		var state := make_fixture(parent)
		if state.is_empty(): failures+=1;continue
		var overlay: Probe=state.overlay
		var catalog: Dictionary=overlay._catalogs[0].duplicate(true)
		catalog.max_scale=0.7
		var regions: Array[Vector2]=[Vector2(-170,170),Vector2(170,1000),Vector2(-1000,-170)]
		for index in 3:
			var key := "0:%d"%index
			var box := AABB(Vector3(-1000,0,regions[index].x),Vector3(2000,0,regions[index].y-regions[index].x))
			catalog.rows[key].max_scale=0.7
			catalog.rows[key].bounds=[-1000,regions[index].x,1000,regions[index].y]
			catalog.roots[index].boxes=[box,AABB(),AABB()];catalog.roots[index].coverage_box=box
		overlay._catalogs.append(catalog)
		var displayed := Transform2D.IDENTITY.scaled(Vector2.ONE*0.25)
		displayed.origin=SIZE*0.5
		overlay._last_canvas=displayed
		var desired := Transform2D.IDENTITY.scaled(Vector2.ONE*0.45)
		desired.origin=SIZE*0.5
		overlay.camera_motion_pending(desired,SIZE,2.0,Vector2.ZERO)
		var next := cut(PackedStringArray(["0:0"]),catalog)
		next["motion_checkpoint"]=tagged;next["handoff_bridge"]=true
		var plan := candidate(next);plan.catalog=1
		# 终点此刻合格、但放大前探失格；半步的覆盖和同样的前探都合格。
		var accepted := overlay._admit_prepared_plan(plan,{"camera_demand":true,"canvas":desired,"size":SIZE},0.25,true,false)
		failures+=int(accepted!=tagged or overlay.requests!=int(tagged) or overlay.clears!=0)
		if accepted:
			overlay.ready_to_commit=true
			failures+=int(overlay._commit_ready_target(0.25))
			await parent.get_tree().process_frame
			var midway := Transform2D.IDENTITY.scaled(Vector2.ONE*0.35)
			midway.origin=SIZE*0.5;overlay._last_canvas=midway
			failures+=int(not overlay._commit_ready_target(0.35) or overlay.bound_targets!=1)
		await dispose(parent,state)
	print("[Tokyo zoom checkpoint admission] fail=",failures)
	return failures


static func waiting_motion_priority_checks(parent: Node) -> int:
	var state := make_fixture(parent)
	if state.is_empty(): return 1
	var overlay: Probe=state.overlay
	overlay.map_frame_balance=true;overlay._heavy_frame=Engine.get_process_frames()
	var installed := OS.get_environment("AGL_TOKYO_INSTALLED_TEST")
	var compact := OS.get_environment("AGL_TOKYO_DISPLAY_COMPACTION")
	OS.set_environment("AGL_TOKYO_DISPLAY_COMPACTION","1")
	OS.set_environment("AGL_TOKYO_INSTALLED_TEST","0")
	overlay.camera_motion_pending(pose(Vector2(0,400)),SIZE,0.0,Vector2(0,1000))
	var failures := int(not overlay._heavy_contested(&"plan_admit"))
	OS.set_environment("AGL_TOKYO_INSTALLED_TEST","1")
	for kind: StringName in [&"plan_submit",&"plan_admit",&"commit"]:
		failures+=int(overlay._heavy_contested(kind))
	overlay._camera_demand={}
	failures+=int(not overlay._heavy_contested(&"plan_admit"))
	OS.set_environment("AGL_TOKYO_INSTALLED_TEST",installed)
	OS.set_environment("AGL_TOKYO_DISPLAY_COMPACTION",compact)
	await dispose(parent,state)
	print("[Tokyo waiting motion priority] fail=",failures)
	return failures


static func return_hint_checks(parent: Node) -> int:
	var state := make_fixture(parent)
	if state.is_empty(): return 1
	var camera := Camera2D.new();state.source.add_child(camera)
	var controller := CameraController.new();state.source.add_child(controller)
	controller.setup(camera);controller._return_prefetch=true;controller.follow_enabled=false
	var target := Node2D.new();state.source.add_child(target);target.position=Vector2(500,20)
	controller.set_follow_target(target)
	var before := camera.position
	controller._update_follow(0.016)
	var hint: Dictionary=camera.get_meta(&"map_return_hint",{})
	var failures := int(hint.is_empty() or hint.get("position")!=target.position or camera.position!=before or not Worker.pure(hint))
	controller._wasd_velocity=Vector2(1200,0);controller._update_follow(0.016)
	failures+=int(not camera.get_meta(&"map_return_hint",{}).get("screen_pan",false))
	target.position+=Vector2(1.6,0.8);controller._update_follow(0.016)
	hint=camera.get_meta(&"map_return_hint",{})
	failures+=int(Vector2(hint.target_velocity).distance_to(Vector2(100,50))>0.002 or hint.step_seconds!=0.016)
	controller.follow_enabled=true;controller._update_follow(0.016)
	failures+=int(not camera.get_meta(&"map_return_hint",{}).get("following",false) or camera.get_meta(&"map_return_hint",{}).get("screen_pan",true))
	# 真正释放后跨帧再次读取；纯值提示必须撤销，不能持有旧玩家对象或旧返回点。
	target.queue_free();await parent.get_tree().process_frame
	controller._update_follow(0.016)
	failures+=int(not camera.get_meta(&"map_return_hint",{}).is_empty())
	var replacement := Node2D.new();state.source.add_child(replacement);replacement.position=Vector2(2000,20)
	controller.set_follow_target(replacement);controller.follow_enabled=false;controller._update_follow(0.016)
	failures+=int(camera.get_meta(&"map_return_hint",{}).target_velocity!=Vector2.ZERO)
	await dispose(parent,state)
	print("[Tokyo return hint] fail=",failures)
	return failures


static func checkpoint_input_intent_checks(parent: Node) -> int:
	var failures := 0
	for ready: bool in [false,true]:
		var viewport := SubViewport.new()
		viewport.size=Vector2i(SIZE);viewport.render_target_update_mode=SubViewport.UPDATE_DISABLED
		parent.add_child(viewport)
		var camera := Camera2D.new();viewport.add_child(camera)
		var controller := CameraController.new();viewport.add_child(controller)
		controller.setup(camera);controller.follow_enabled=false
		controller._base_zoom=0.2577;camera.zoom=Vector2.ONE*0.2577
		controller.target_zoom=0.2;controller._map_pending_zoom=0.21
		controller._map_pending_pan=Vector2(200,0)
		var guard := CheckpointGuard.new();guard.ready=ready
		camera.set_meta(&"map_motion_guard",weakref(guard))
		controller.update(1.0/60.0)
		# 显示可停在中间档，加载需求必须继续指向未显示的完整输入终点。
		failures+=int(guard.pending.is_empty())
		if not guard.pending.is_empty():
			var demand: Transform2D=guard.pending.canvas
			failures+=int(demand.x.length()>=0.25 or (demand.affine_inverse()*(SIZE*0.5)).distance_to(Vector2(200,0))>0.01)
		failures+=int(not is_equal_approx(camera.zoom.x,0.25 if ready else 0.2577))
		# 下一次反向滚轮立即替换旧需求，不粘住原缩远终点。
		controller.target_zoom=0.4;guard.ready=false
		controller.update(1.0/60.0)
		failures+=int(guard.pending.is_empty() or guard.pending.canvas.x.length()<=camera.zoom.x)
		viewport.queue_free();await parent.get_tree().process_frame
	print("[Tokyo checkpoint input intent] fail=",failures)
	return failures


static func large_path_checkpoint_checks(parent: Node) -> int:
	var failures := 0
	for tagged: bool in [true,false]:
		var state := make_fixture(parent)
		if state.is_empty(): failures+=1;continue
		var overlay: Probe=state.overlay
		var catalog: Dictionary=overlay._catalogs[0].duplicate(true)
		var regions := [Vector2(-60,60),Vector2(300,440),Vector2(-1000,-60),Vector2(60,300),Vector2(440,1000)]
		for index in regions.size():
			var key := "0:%d"%index
			if index>=3:
				catalog.rows[key]=catalog.rows["0:1"].duplicate(true)
				var root: Dictionary=catalog.roots[1].duplicate(true);root.key=key;catalog.roots.append(root)
			var box := AABB(Vector3(-1000,0,regions[index].x),Vector3(2000,0,regions[index].y-regions[index].x))
			catalog.roots[index].boxes=[box,AABB(),AABB()];catalog.roots[index].coverage_box=box
			catalog.rows[key].bounds=[-1000,regions[index].x,1000,regions[index].y]
		overlay._catalogs.append(catalog)
		var next := cut(PackedStringArray(["0:1"]),catalog);next["motion_checkpoint"]=tagged
		var plan := candidate(next);plan.catalog=1
		overlay.camera_motion_pending(pose(Vector2(0,500)),SIZE,0.0,Vector2(0,1000))
		var accepted := overlay._admit_prepared_plan(plan,{"camera_demand":true,"canvas":pose(Vector2(0,500)),"size":SIZE},1.0,true,false)
		failures+=int(accepted!=tagged or overlay.requests!=int(tagged) or overlay.clears!=0)
		if accepted:
			overlay.ready_to_commit=true
			failures+=int(overlay._commit_ready_target(1.0))
			await parent.get_tree().process_frame
			overlay._last_canvas=pose(Vector2(0,375))
			failures+=int(not overlay._commit_ready_target(1.0) or overlay.bound_targets!=1)
		await dispose(parent,state)
	print("[Tokyo large path checkpoint] fail=",failures)
	return failures


static func coupled_checkpoint_checks(parent: Node) -> int:
	var failures := 0
	for options: Array in [[true,true],[true,false],[false,true]]:
		var state := make_fixture(parent)
		if state.is_empty(): failures+=1;continue
		var overlay: Probe=state.overlay
		var old_catalog: Dictionary=overlay._catalogs[0]
		var next_catalog: Dictionary=old_catalog.duplicate(true)
		for pair: Array in [[old_catalog,[Vector2(-200,200),Vector2(200,1000),Vector2(-1000,-200)]],
			[next_catalog,[Vector2(280,900),Vector2(900,1000),Vector2(-1000,280)]]]:
			var catalog: Dictionary=pair[0]
			for index in 3:
				var limits: Vector2=pair[1][index]
				var key := "0:%d"%index
				var box := AABB(Vector3(-1000,0,limits.x),Vector3(2000,0,limits.y-limits.x))
				catalog.rows[key].bounds=[-1000,limits.x,1000,limits.y]
				catalog.roots[index].boxes=[box,AABB(),AABB()];catalog.roots[index].coverage_box=box
		next_catalog.max_scale=0.24
		for row: Dictionary in next_catalog.rows.values(): row.max_scale=0.24
		overlay._catalogs.append(next_catalog)
		overlay._committed_cut=cut(PackedStringArray(["0:0"]),old_catalog)
		overlay._committed=overlay._committed_cut.keys
		overlay._target=cut(PackedStringArray(["0:0"]),next_catalog)
		overlay._target["motion_checkpoint"]=options[0];overlay._target_catalog=1
		overlay.ready_to_commit=options[1];overlay.output_scale=0.28
		var camera := Camera2D.new();state.source.add_child(camera)
		var controller := CameraController.new();state.source.add_child(controller)
		controller.setup(camera);controller.follow_enabled=false
		controller._base_zoom=0.28;camera.zoom=Vector2.ONE*0.28
		controller.target_zoom=0.2;controller._map_pending_zoom=0.2
		controller._map_pending_pan=Vector2(0,1000)
		camera.force_update_scroll();overlay._last_canvas=state.viewport.canvas_transform
		camera.set_meta(&"map_motion_guard",weakref(overlay))
		controller.update(1.0/60.0)
		# 标量0.24断点下没有可行小步；原联合路径的5/8位置+0.23缩放已完整就绪。
		var moved: bool=camera.global_position.y>500.0 and camera.zoom.x<0.24 \
			and overlay._committed_catalog==1 and overlay.bound_targets==1
		failures+=int(moved!=bool(options[0] and options[1]))
		if not moved: failures+=int(camera.global_position.length()>0.01 or absf(camera.zoom.x-0.28)>0.0001)
		# 实际 Camera2D 的下限经过输出缩放送到纯值后台；演出接管后不沿用普通滚轮下限。
		overlay._last_size=SIZE*0.8
		var bounded_request := overlay._planning_request(camera.zoom.x*0.8,true)
		failures+=int(not is_equal_approx(float(bounded_request.prediction_floor),0.16))
		controller.cine_cut_to(camera.global_position,0.12)
		failures+=int(not is_zero_approx(float(overlay._planning_request(0.096,true).prediction_floor)))
		await dispose(parent,state)
	print("[Tokyo coupled checkpoint] fail=",failures)
	return failures


class MenuBoundaryFixture extends Node:
	var _menu_visible := false
	var _menu_root := Control.new()
	var cancelled := 0
	func _ready() -> void: add_child(_menu_root)
	func _on_cancel_pressed() -> void:
		cancelled+=1;_menu_visible=false;get_tree().paused=false


class MenuUpgradeFixture extends Node:
	var visible := true
	var _input_locked := false
	var _selection_locked := false
	var _choices: Array[Dictionary]=[{"id":"fixture_upgrade"}]
	var selected := 0
	func _on_choice_pressed(_index: int) -> void:
		selected+=1;visible=false;_selection_locked=true;get_tree().paused=false


class MenuBattleFixture extends Node:
	var is_paused_for_upgrade := false
	var _camera_ctrl := {"cine_zoom_mult":1.0}
	var upgrade_ui := MenuUpgradeFixture.new()
	var _boundary_ui := MenuBoundaryFixture.new()
	func _ready() -> void:
		add_child(_boundary_ui);add_child(upgrade_ui)


static func formal_menu_driver_checks(parent: Node) -> int:
	var tree := parent.get_tree()
	var battle := MenuBattleFixture.new()
	parent.add_child(battle)
	var driver := preload("res://scripts/tests/tokyo_formal_menu_driver.gd").new()
	driver.setup(battle,Time.get_ticks_msec());parent.add_child(driver)
	tree.paused=true
	# Headless没有frame_post_draw也必须经正式回调解除菜单，并跨帧恢复可操控时钟。
	await tree.process_frame
	await tree.process_frame
	await tree.process_frame
	var failures := int(tree.paused or battle.upgrade_ui.selected!=1 or driver.selections.size()!=1 or driver.modal_generation<2)
	tree.paused=false
	battle.queue_free()
	await tree.process_frame
	await tree.process_frame
	failures+=int(not driver.source_released)
	driver.queue_free()
	await tree.process_frame
	print("[Tokyo formal menu driver] fail=",failures)
	return failures


static func run(parent: Node) -> int:
	var menu_failures := await formal_menu_driver_checks(parent)
	var failures := await empty_display_trace_checks(parent)
	failures+=await compact_stream_snapshot_checks(parent)
	failures+=await incremental_binding_checks(parent)
	failures+=menu_failures
	failures+=pending_display_progress_checks()
	failures+=await subpixel_composite_checks(parent)
	failures+=await direct_checks(parent)
	failures+=await prepared_motion_checks(parent)
	failures+=await visible_prepared_checks(parent)
	failures+=await resource_priority_checks(parent)
	failures+=await resident_motion_checks(parent)
	failures+=await cached_native_motion_checks(parent)
	failures+=await cached_hlod_motion_checks(parent)
	failures+=await summary_motion_checks(parent)
	failures+=await stopped_camera_checks(parent)
	failures+=await native_guard_metadata_checks(parent)
	failures+=await native_guard_cadence_checks(parent)
	failures+=await pending_motion_sampling_checks(parent)
	failures+=await evolving_camera_demand_checks(parent)
	failures+=await pending_zoom_bridge_checks(parent)
	failures+=await pending_path_checkpoint_checks(parent)
	failures+=await large_path_checkpoint_checks(parent)
	failures+=await pending_zoom_checkpoint_checks(parent)
	failures+=await waiting_motion_priority_checks(parent)
	failures+=await checkpoint_input_intent_checks(parent)
	failures+=await return_hint_checks(parent)
	failures+=await coupled_checkpoint_checks(parent)
	failures+=await cold_jump_prediction_checks(parent)
	failures+=await pending_display_checks(parent)
	failures+=await pending_coverage_checks(parent)
	failures+=await ready_before_clear_checks(parent)
	failures+=await in_flight_zoom_reversal_checks(parent)
	failures+=await ready_downgrade_reversal_checks(parent)
	failures+=await revision_and_exit_checks(parent)
	print("[Tokyo map admission] fail=",failures)
	return failures
