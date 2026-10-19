extends RefCounted
## 单个后台规划任务；只有Loading/换源复制来源，游戏帧只提交紧凑请求并领取已完成结果。
## 不保存待办相机副本；所有者在空闲后重新采样最新视野，避免过期请求排队。
const Planner := preload("res://scripts/rendering/tokyo_map_planner.gd")
const MAX_REQUEST_BYTES := 2*1024*1024
const MAX_SOURCE_VALUES := 16*1024*1024
const MAX_REQUEST_VALUES := 256*1024
const MAX_DEPTH := 32
var _planner: RefCounted
var _test_planner: RefCounted
var _generation := -1
var _sequence := 0
var _task := -1
var _job: Dictionary={}
var _submitted := 0
var _completed := 0
var _discarded := 0
var _background_elapsed_usec := 0
var _peak_background_usec := 0


func _init(planner_override: RefCounted = null) -> void:
	# 生命周期夹具可注入纯规划器；该对象从不进入来源、请求或返回值。
	_test_planner=planner_override


func configure(source: Dictionary, generation: int) -> bool:
	close()
	if generation<0 or source.is_empty() or not pure(source,MAX_SOURCE_VALUES): return false
	var planner: RefCounted=Planner.new() if _test_planner==null else _test_planner
	if planner is Resource or not planner.has_method("configure") or not planner.has_method("plan"): return false
	# 规划器独占快照，后续调用者修改原容器不能影响在途工作。
	if not bool(planner.configure(source.duplicate(true))): return false
	_planner=planner
	_generation=generation
	return true


func busy() -> bool:
	# 已完成但尚未领取仍占用唯一槽位，不能覆盖旧结果。
	return _task>=0


func ready() -> bool:
	return _task>=0 and WorkerThreadPool.is_task_completed(_task)


func submit(request: Dictionary) -> bool:
	if busy() or _planner==null or _generation<0 or request.is_empty() or not pure(request,MAX_REQUEST_VALUES): return false
	if var_to_bytes(request).size()>MAX_REQUEST_BYTES: return false
	_sequence+=1
	_job={"request":request.duplicate(true),"generation":_generation,"sequence":_sequence,
		"submitted_usec":Time.get_ticks_usec(),"result":{},"background_elapsed_usec":0}
	_task=WorkerThreadPool.add_task(_run.bind(_planner,_job),false,"Tokyo map plan")
	if _task<0:
		_job={}
		return false
	_submitted+=1
	return true


func take(expected_generation: int) -> Dictionary:
	# 游戏帧不等待尚未结束的任务，也不以时间年龄否决仍可通过当前视野验收的计划。
	if not ready(): return {}
	WorkerThreadPool.wait_for_task_completion(_task)
	_task=-1
	_account_completion()
	var result: Dictionary=_job.result
	_job={}
	if result.is_empty() or expected_generation!=_generation or int(result.generation)!=expected_generation:
		_discarded+=1
		return {}
	return result


func close() -> void:
	# 只在退出/换源生命周期等待，保证规划器及其快照不在后台使用期间释放。
	if _task>=0:
		WorkerThreadPool.wait_for_task_completion(_task)
		_task=-1
		_account_completion()
		_discarded+=1
	_job={}
	_planner=null
	_generation=-1


func summary() -> Dictionary:
	return {"generation":_generation,"sequence":_sequence,"busy":busy(),"ready":ready(),
		"submitted":_submitted,"completed":_completed,"discarded":_discarded,
		"background_elapsed_usec":_background_elapsed_usec,"peak_background_usec":_peak_background_usec}


func _account_completion() -> void:
	_completed+=1
	_background_elapsed_usec=int(_job.get("background_elapsed_usec",0))
	_peak_background_usec=maxi(_peak_background_usec,_background_elapsed_usec)


static func _run(planner: RefCounted, job: Dictionary) -> void:
	# 仅访问独占规划器和任务容器。结果纯值检查也留在后台，不给领取帧增加全树扫描。
	var started := Time.get_ticks_usec()
	var plan: Variant=planner.plan(job.request)
	var valid: bool=plan is Dictionary and not plan.is_empty() and pure(plan,MAX_SOURCE_VALUES)
	var elapsed := Time.get_ticks_usec()-started
	job.background_elapsed_usec=elapsed
	if not valid: return
	job.result={"generation":job.generation,"sequence":job.sequence,"request":job.request,"plan":plan,
		"submitted_usec":job.submitted_usec,"background_elapsed_usec":elapsed}


static func pure(value: Variant, maximum_values: int = MAX_SOURCE_VALUES) -> bool:
	if maximum_values<=0: return false
	return _pure(value,0,{"remaining":maximum_values})


static func _pure(value: Variant, depth: int, budget: Dictionary) -> bool:
	budget.remaining=int(budget.remaining)-1
	if depth>MAX_DEPTH or int(budget.remaining)<0 or typeof(value) in [TYPE_OBJECT,TYPE_CALLABLE,TYPE_SIGNAL,TYPE_RID]: return false
	if value is Dictionary:
		if value.size()>int(budget.remaining)/2: return false
		for key: Variant in value:
			if not _pure(key,depth+1,budget) or not _pure(value[key],depth+1,budget): return false
	elif value is Array:
		if value.size()>int(budget.remaining): return false
		for item: Variant in value:
			if not _pure(item,depth+1,budget): return false
	return true
