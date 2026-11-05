extends RefCounted
const Worker := preload("res://scripts/rendering/tokyo_map_plan_worker.gd")

class SourceFixture extends Node2D:
	var gate := Semaphore.new()
	var success := true
	func prepare_background_source() -> bool:
		gate.wait()
		return success

class BlendLease extends Node:
	var released: Array[int]=[]
	var closed := false
	var input_waiting := false
	func release_auxiliary(token: int) -> void: released.append(token)
	func close() -> void: closed=true

class BlendOverlay extends "res://scripts/rendering/tokyo_hlod_overlay.gd":
	func _cut_covers_current_view(_cut: Dictionary, _catalog: int, _margin_px: float = 0.0) -> bool:
		return true


static func lod_blend_lifecycle_checks(parent: Node) -> int:
	var failures := 0
	for ending: String in ["complete","deactivate","exit","input"]:
		var overlay := BlendOverlay.new()
		overlay.set_process(false)
		parent.add_child(overlay)
		var lease := BlendLease.new()
		parent.add_child(lease)
		overlay._stream=lease
		var old := MeshInstance3D.new()
		parent.add_child(old)
		var old_ref: WeakRef=weakref(old)
		overlay._lod_old_nodes.append(old)
		overlay._lod_old_cut={"keys":PackedStringArray(["old"]),"configuration":"lod5_full"}
		overlay._lod_old_catalog=-2
		overlay._lod_old_token=RefCounted.new()
		var token: int=overlay._lod_old_token.get_instance_id()
		if ending=="complete": overlay._end_lod_blend()
		elif ending=="deactivate": overlay._deactivate()
		elif ending=="input":
			overlay._lod_blend_started_usec=Time.get_ticks_usec()
			overlay._camera_demand={"rate":0.0}
			overlay._step_lod_blend(1.2,0.0)
		if ending!="exit":
			failures+=int(not overlay._lod_old_cut.is_empty() or not overlay._lod_old_nodes.is_empty() or overlay._lod_old_token!=null)
		overlay.queue_free()
		await parent.get_tree().process_frame
		await parent.get_tree().process_frame
		failures+=int(old_ref.get_ref()!=null or lease.released!=[token] or not lease.closed)
		lease.queue_free()
	print("[Tokyo LOD blend lifecycle] fail=",failures)
	return failures

class SourceSession extends "res://scripts/rendering/tokyo_volume_preload.gd":
	var accepted := false
	func _finish_begin(prepared: Node2D) -> void:
		accepted=true
		prepared.free()
		status="ready"
		set_process(false)


static func source_preparation_checks(parent: Node) -> int:
	var failures := 0
	for outcome: String in ["success","cancelled","failed"]:
		var cancelled := outcome=="cancelled"
		var session := SourceSession.new()
		parent.add_child(session)
		var fixture := SourceFixture.new()
		fixture.success=outcome!="failed"
		var fixture_ref: WeakRef=weakref(fixture)
		var session_ref: WeakRef=weakref(session)
		failures+=int(not session._start_source_preparation(fixture))
		await parent.get_tree().process_frame
		failures+=int(session.status!="preparing" or session.accepted)
		if cancelled:
			session.cancel()
			# 实际任务仍被门阻塞；cancel必须返回并继续下一SceneTree帧，不等待信号。
			await parent.get_tree().process_frame
			failures+=int(session.status!="cancelled" or session.accepted or session_ref.get_ref()==null)
		fixture.gate.post()
		var deadline := Time.get_ticks_msec()+5000
		while fixture_ref.get_ref()!=null and Time.get_ticks_msec()<deadline: await parent.get_tree().process_frame
		failures+=int(fixture_ref.get_ref()!=null)
		if outcome=="success":
			failures+=int(not session.accepted or session.status!="ready")
			session.queue_free()
		await parent.get_tree().process_frame
		failures+=int(session_ref.get_ref()!=null)
	print("[Tokyo background source lifecycle] fail=",failures)
	return failures


static func prepared_stream_checks(parent: Node) -> int:
	var stream_script := preload("res://scripts/rendering/tokyo_hlod_stream.gd")
	var geometry := {"one":{"components":{"shared":{"bytes":123}}},"two":{"components":{"shared":{"bytes":123}}}}
	var prepared := stream_script.prepare_hlod_source(geometry,{})
	var failures := int(prepared.is_empty() or prepared.layout.physical.size()!=1)
	geometry.one.components.shared.bytes=456
	failures+=int(prepared.layout.logical.one.components.shared.bytes!=123)
	failures+=int(not stream_script.prepare_hlod_source({}, {"invalid":{}}).is_empty())
	var owner_node := Node.new()
	var stream := stream_script.new()
	parent.add_child(owner_node);parent.add_child(stream)
	failures+=int(not stream.configure_prepared_hlod(owner_node,prepared))
	failures+=int(stream._descriptors.shared.bytes!=123 or stream._expanded_paths.one!=PackedStringArray(["shared"]))
	failures+=int(stream.is_processing() or not stream._pending.is_empty() or not stream._texture_jobs.is_empty())
	var stream_ref: WeakRef=weakref(stream)
	owner_node.queue_free()
	await parent.get_tree().process_frame
	await parent.get_tree().process_frame
	failures+=int(stream_ref.get_ref()!=null)
	print("[Tokyo prepared stream lifecycle] fail=",failures)
	return failures


class FixturePlanner extends RefCounted:
	var source: Dictionary={}
	var gate: Semaphore
	func configure(value: Dictionary) -> bool:
		source=value
		return bool(value.get("valid",true))
	func plan(request: Dictionary) -> Dictionary:
		if gate!=null: gate.wait()
		if request.get("unsafe_result",false): return {"unsafe":RefCounted.new()}
		return {"value":int(source.value)+int(request.value),"source_value":source.value,"request_value":request.value}


static func wait_ready(parent: Node, worker: RefCounted) -> bool:
	var deadline := Time.get_ticks_msec()+5000
	while not worker.ready() and Time.get_ticks_msec()<deadline: await parent.get_tree().process_frame
	return worker.ready()


static func run(parent: Node) -> int:
	var failures := await source_preparation_checks(parent)
	failures+=await lod_blend_lifecycle_checks(parent)
	failures+=await prepared_stream_checks(parent)
	var fixture := FixturePlanner.new()
	var worker := Worker.new(fixture)
	var source := {"value":3}
	var request := {"value":5}
	failures+=int(not worker.configure(source,7))
	source.value=30
	fixture.gate=Semaphore.new()
	failures+=int(not worker.submit(request))
	request.value=50
	failures+=int(not worker.busy() or worker.ready() or worker.submit(request))
	# 被门阻塞的真实任务未完成时take必须立即返回，且不能占用下一请求或丢弃旧句柄。
	failures+=int(not worker.take(7).is_empty() or not worker.busy() or worker.summary().completed!=0)
	fixture.gate.post()
	var done := await wait_ready(parent,worker)
	failures+=int(not done)
	var first := worker.take(7)
	if not done:
		worker.close()
		return failures+1
	fixture.gate=null
	failures+=int(first.is_empty())
	if not first.is_empty():
		failures+=int(first.generation!=7 or first.sequence!=1 or first.plan.value!=8 \
			or first.request.value!=5 or first.plan.source_value!=3 or first.background_elapsed_usec<0)
	failures+=int(worker.busy() or worker.ready() or not worker.take(7).is_empty())
	# 领取错代次只丢该结果，完成任务必须回收，随后仍可提交。
	failures+=int(not worker.submit({"value":2}))
	done=await wait_ready(parent,worker)
	failures+=int(not done)
	failures+=int(not worker.take(8).is_empty() or worker.busy() or worker.summary().discarded!=1)
	# 完成后故意延迟领取超过旧预测器150ms门；新worker不以年龄代替当前视野验收。
	failures+=int(not worker.submit({"value":4}))
	done=await wait_ready(parent,worker)
	failures+=int(not done)
	await parent.get_tree().create_timer(0.18).timeout
	var delayed := worker.take(7)
	failures+=int(delayed.is_empty() or delayed.get("plan",{}).get("value",-1)!=7)
	# 来源和请求均拒绝活动对象，不能依靠序列化把非法值悄悄删掉。
	var object_value := RefCounted.new()
	failures+=int(worker.submit({"value":1,"object":object_value}))
	failures+=int(worker.submit({"value":1,"large":"x".repeat(Worker.MAX_REQUEST_BYTES)}))
	var deep: Array=[]
	for index in Worker.MAX_DEPTH+2: deep=[deep]
	failures+=int(worker.submit({"value":1,"deep":deep}))
	failures+=int(not worker.submit({"value":1,"unsafe_result":true}))
	done=await wait_ready(parent,worker)
	failures+=int(not done)
	failures+=int(not worker.take(7).is_empty() or worker.summary().discarded!=2)
	# 退出可等待真实在途任务，但不把其未领取结果交给后继来源；重复close无副作用。
	failures+=int(not worker.submit({"value":9}))
	worker.close()
	var after_close := worker.summary()
	worker.close()
	failures+=int(worker.summary()!=after_close or worker.busy() or worker.ready() or worker.submit({"value":1}))
	failures+=int(after_close.submitted!=5 or after_close.completed!=5 or after_close.discarded!=3)
	failures+=int(worker.configure({"value":1,"object":object_value},8) or worker.configure({"value":1},-1))
	failures+=int(worker.configure({"value":1,"valid":false},8))
	failures+=int(not worker.configure({"value":10},9) or not worker.submit({"value":2}))
	done=await wait_ready(parent,worker)
	failures+=int(not done)
	var final := worker.take(9)
	failures+=int(final.is_empty() or final.get("plan",{}).get("value",-1)!=12 or final.get("sequence",-1)!=6)
	worker.close()
	var resource_worker := Worker.new(Resource.new())
	failures+=int(resource_worker.configure({"value":1},10))
	resource_worker.close()
	print("[Tokyo map plan worker] fail=",failures)
	return failures
