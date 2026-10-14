extends RefCounted
const Planner := preload("res://scripts/rendering/tokyo_cut_worker.gd")
const Job := preload("res://scripts/rendering/tokyo_cut_job.gd")
const Predictor := preload("res://scripts/rendering/tokyo_native_predictor.gd")

class Owner extends Node:
	var planner := Planner.new()
	func _exit_tree() -> void:
		planner.close()


static func run(parent: Node) -> int:
	var failures := 0
	# 同时间平滑与呈现频率无关；60Hz位移在120Hz交替采样时不放大速度抖动。
	var at_60 := Vector2.ZERO
	var at_120 := Vector2.ZERO
	var alternating := Vector2.ZERO
	for frame in 120:
		at_120=Predictor.smooth_pan(at_120,Vector2(600,0),1.0/120.0)
		alternating=Predictor.smooth_pan(alternating,Vector2(1200 if frame%2==0 else 0,0),1.0/120.0)
		if frame<60: at_60=Predictor.smooth_pan(at_60,Vector2(600,0),1.0/60.0)
		if frame>60: failures+=int(absf(alternating.x-600)>30)
	failures+=int(at_60.distance_to(at_120)>0.01)
	failures+=int(Predictor.smooth_pan(at_60,Vector2.ZERO,0)!=at_60)
	var box := AABB(Vector3(-50,0,-50),Vector3(100,20,100))
	var leaf := {"path":"leaf","boxes":[box,box,box],"triangles":PackedInt32Array([40,20,10]),"bytes":1000,"children":[]}
	var root := leaf.duplicate(true)
	root.path="root";root.triangles=PackedInt32Array([80,40,20]);root.bytes=2000;root.children=[leaf]
	var roots: Array[Dictionary]=[root]
	var queries: Array[Dictionary]=[]
	for sample in 4:
		queries.append({"center":Vector2(sample*30,0),"size":Vector2(100+sample*20,90),"scale":1.0+sample*0.2,"angle":sample*0.1})
	var reference := {"roots":roots.duplicate(true),"queries":queries.duplicate(true),"generation":7,"submitted_usec":0,"result":{}}
	Job.run(reference)
	var worker := Planner.new()
	failures+=int(not worker.configure(roots,7))
	failures+=int(not worker.submit(queries) or worker.submit(queries))
	# 调用方修改原输入不得改变后台快照；主线程也不得读未完成结果。
	root.bytes=999999;queries[0].scale=9.0
	var deadline := Time.get_ticks_msec()+5000
	while not worker.ready() and Time.get_ticks_msec()<deadline: await parent.get_tree().process_frame
	var result := worker.take(7,5000000)
	failures+=int(result.is_empty())
	if not result.is_empty():
		failures+=int(result.queries!=reference.queries or result.solutions.size()!=4)
		for index in 4:
			failures+=int(result.solutions[index].frontier!=reference.result.solutions[index].frontier)
	failures+=int(not worker.take(7).is_empty() or worker._task!=-1)
	# 代次变化和过期结果必须丢弃且回收；不是冒充新的相机计划。
	for stale in [false,true]:
		failures+=int(not worker.submit(reference.queries))
		deadline=Time.get_ticks_msec()+5000
		while not worker.ready() and Time.get_ticks_msec()<deadline: await parent.get_tree().process_frame
		failures+=int(not worker.take(8 if stale else 7,5000000 if stale else 1).is_empty())
	failures+=int(worker.discarded!=2)
	worker.close();worker.close()
	failures+=int(worker.submit(reference.queries) or worker._task!=-1 or not worker._roots.is_empty())
	var owner := Owner.new()
	parent.add_child(owner)
	var retained := owner.planner
	failures+=int(not retained.configure(reference.roots,8) or not retained.submit(reference.queries))
	owner.queue_free()
	await parent.get_tree().process_frame
	await parent.get_tree().process_frame
	failures+=int(retained._task!=-1 or not retained._roots.is_empty())
	# 活动对象不可进入后台输入；无效查询不启动任务。
	var invalid: Array[Dictionary]=[{"unsafe":parent}]
	failures+=int(worker.configure(invalid,9))
	failures+=int(not worker.configure(reference.roots,9))
	var bad: Array[Dictionary]=[{"center":Vector2.ZERO,"size":Vector2.ONE,"scale":0,"angle":0}]
	failures+=int(worker.submit(bad))
	for invalid_limit: Variant in [0,17,24,33,32.0,"32"]:
		var invalid_query: Array[Dictionary]=[reference.queries[0].duplicate(true)]
		invalid_query[0]["page_limit"]=invalid_limit
		failures+=int(worker.submit(invalid_query))
	var expanded_queries: Array[Dictionary]=reference.queries.duplicate(true)
	for query: Dictionary in expanded_queries: query["page_limit"]=32
	failures+=int(not worker.submit(expanded_queries))
	deadline=Time.get_ticks_msec()+5000
	while not worker.ready() and Time.get_ticks_msec()<deadline: await parent.get_tree().process_frame
	var expanded_result := worker.take(9,5000000)
	failures+=int(expanded_result.is_empty() or expanded_result.get("queries",[])!=expanded_queries)
	worker.close()
	# 注册多个来源后按身份提交，未知来源不得启动；退出同时清空全部快照。
	failures+=int(not worker.configure_sources({"raw":reference.roots,"ground":reference.roots},10))
	failures+=int(worker.submit(reference.queries,"unknown") or not worker.submit(reference.queries,"ground"))
	deadline=Time.get_ticks_msec()+5000
	while not worker.ready() and Time.get_ticks_msec()<deadline: await parent.get_tree().process_frame
	var sourced := worker.take(10,5000000)
	failures+=int(sourced.is_empty() or sourced.get("source_key","")!="ground")
	worker.close()
	failures+=int(not worker._sources.is_empty())
	var sample_query := {"anchor":Vector2.ZERO,"center":Vector2.ZERO,"base_size":Vector2(100,100),"size":Vector2(100,100),"scale":1.0,"angle":0.0,"pan":Vector2.RIGHT,"zoom_sign":1}
	var response := {"generation":1,"source_key":"raw","submitted_usec":10,"queries":[sample_query,sample_query,sample_query,sample_query],"solutions":[{},{},{},{}]}
	failures+=int(not Predictor.usable(response,"raw",Vector2.ZERO,1,0,Vector2(100,100),Vector2.RIGHT,1,100))
	for args: Array in [["wrong",Vector2.ZERO,1.0,0.0,Vector2(100,100),Vector2.RIGHT,1,100],["raw",Vector2(49,0),1.0,0.0,Vector2(100,100),Vector2.RIGHT,1,100],["raw",Vector2.ZERO,1.2,0.0,Vector2(100,100),Vector2.RIGHT,1,100],["raw",Vector2.ZERO,1.0,0.06,Vector2(100,100),Vector2.RIGHT,1,100],["raw",Vector2.ZERO,1.0,0.0,Vector2(101,100),Vector2.RIGHT,1,100],["raw",Vector2.ZERO,1.0,0.0,Vector2(100,100),Vector2.LEFT,1,100],["raw",Vector2.ZERO,1.0,0.0,Vector2(100,100),Vector2.RIGHT,-1,100],["raw",Vector2.ZERO,1.0,0.0,Vector2(100,100),Vector2.RIGHT,1,150011]]:
		failures+=int(Predictor.usable(response,args[0],args[1],args[2],args[3],args[4],args[5],args[6],args[7]))
	var native := preload("res://scripts/rendering/tokyo_hlod_native.gd").new()
	native.catalog=preload("res://scripts/rendering/tokyo_canonical_catalog.gd").new()
	native.catalog.configurations={"lod5_full":reference.roots}
	var predictor := Predictor.new()
	failures+=int(not predictor.prepare(native))
	var accept := func(_cut: Dictionary) -> bool: return true
	predictor.request(Vector2.ZERO,1,0,Vector2(100,100),"lod5_full",Vector2.ZERO,0,192*1024*1024,accept)
	failures+=int(predictor.worker._task!=-1)
	predictor.dispatch()
	deadline=Time.get_ticks_msec()+1000
	while not predictor.worker.ready() and Time.get_ticks_msec()<deadline: await parent.get_tree().process_frame
	var predicted := predictor.request(Vector2.ZERO,1,0,Vector2(100,100),"lod5_full",Vector2.ZERO,0,192*1024*1024,accept)
	predictor.dispatch()
	failures+=int(predicted.is_empty() or predictor.applied!=1 or predictor.submitted!=2)
	predictor.close();predictor.close()
	failures+=int(predictor.worker._task!=-1 or not predictor.worker._sources.is_empty())
	print("[Tokyo cut worker] fail=",failures)
	return failures
