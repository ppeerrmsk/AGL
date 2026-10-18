extends RefCounted
const Worker := preload("res://scripts/rendering/tokyo_map_plan_worker.gd")


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
	var failures := 0
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
