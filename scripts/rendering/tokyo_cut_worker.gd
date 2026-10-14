extends RefCounted
## 一次一个纯数据任务。尚未接入正式地图；持有者必须在退出/换源时close。
const Job := preload("res://scripts/rendering/tokyo_cut_job.gd")
var _roots: Array[Dictionary]=[]
var _sources: Dictionary={}
var _generation := -1
var _task := -1
var _job: Dictionary={}
var discarded := 0


func configure(roots: Array[Dictionary], generation: int) -> bool:
	close()
	if generation<0 or roots.is_empty() or not _pure(roots): return false
	# 仅换源时复制一次；运行期间不再随每次相机查询复制整图。
	_roots.assign(roots.duplicate(true))
	_generation=generation
	return true


func configure_sources(sources: Dictionary, generation: int) -> bool:
	close()
	if generation<0 or sources.is_empty() or not _pure(sources): return false
	for key: Variant in sources:
		if not key is String or not sources[key] is Array or sources[key].is_empty(): return false
	_sources=sources.duplicate(true)
	_generation=generation
	return true


func submit(queries: Array[Dictionary], source_key: String = "") -> bool:
	if _task>=0 or _generation<0 or queries.is_empty() or queries.size()>4: return false
	if (source_key.is_empty() and _roots.is_empty()) or (not source_key.is_empty() and not _sources.has(source_key)): return false
	for query: Dictionary in queries:
		if typeof(query.get("page_limit",16))!=TYPE_INT or query.get("page_limit",16) not in [16,32]: return false
		if not query.get("center") is Vector2 or not query.get("size") is Vector2: return false
		if typeof(query.get("scale")) not in [TYPE_FLOAT,TYPE_INT] or typeof(query.get("angle")) not in [TYPE_FLOAT,TYPE_INT]: return false
		if not query.center.is_finite() or not query.size.is_finite() or query.size.x<=0 or query.size.y<=0: return false
		if not is_finite(float(query.scale)) or float(query.scale)<=0 or not is_finite(float(query.angle)) or not _pure(query): return false
	var roots: Array[Dictionary]=[]
	roots.assign(_roots if source_key.is_empty() else _sources[source_key])
	_job={"roots":roots,"queries":queries.duplicate(true),"source_key":source_key,"generation":_generation,"submitted_usec":Time.get_ticks_usec(),"result":{}}
	_task=WorkerThreadPool.add_task(Job.run.bind(_job),false,"Tokyo future cut")
	return _task>=0


func ready() -> bool:
	return _task>=0 and WorkerThreadPool.is_task_completed(_task)


func take(expected_generation: int, max_age_usec: int = 150000) -> Dictionary:
	if not ready(): return {}
	# 先确认结束再回收句柄；不在帧循环等待仍在计算的任务。
	WorkerThreadPool.wait_for_task_completion(_task)
	_task=-1
	var result: Dictionary=_job.result
	_job={}
	if result.is_empty() or expected_generation!=_generation or max_age_usec<=0 or Time.get_ticks_usec()-int(result.submitted_usec)>max_age_usec:
		discarded+=1
		return {}
	return result


func close() -> void:
	if _task>=0:
		WorkerThreadPool.wait_for_task_completion(_task)
		_task=-1
	_job={}
	_roots.clear()
	_sources.clear()
	_generation=-1


static func _pure(value: Variant, depth: int = 0) -> bool:
	if depth>32 or typeof(value) in [TYPE_OBJECT,TYPE_CALLABLE,TYPE_SIGNAL,TYPE_RID]: return false
	if value is Dictionary:
		for key: Variant in value:
			if not _pure(key,depth+1) or not _pure(value[key],depth+1): return false
	elif value is Array:
		for item: Variant in value:
			if not _pure(item,depth+1): return false
	return true
