extends Node
## GL只领取后台已完成资源；Dummy网格分配器不支持并发，改用主线程延后领取。
const BUDGET := 96 * 1024 * 1024
const MAX_REQUESTS := 2
static var _busy: Dictionary = {}
var _owner_ref: WeakRef
var _descriptors: Dictionary = {}
var _wanted := PackedStringArray()
var _pins := PackedStringArray()
var _cache: Dictionary = {}
var _pending: Dictionary = {}
var _failures: Dictionary = {}
var _closed := false
var _main_thread_meshes := DisplayServer.get_name() == "headless"
var _main_queued: Dictionary = {}
var _bytes := 0
var _reserved := 0
var _auxiliary: Dictionary = {}
var _auxiliary_bytes := 0
var peak_total_bytes := 0
var peak_bytes := 0
var peak_pending := 0
var completed := 0
var discarded := 0
var retained_completions := 0
var started := 0
var max_take_usec := 0
var max_completed_per_frame := 0
## 显式诊断才保留逐物理路径计数；仅存字符串/整数，不延长资源生命期。
var _audit_paths := false
var _audit_requests: Dictionary = {}
var _audit_evictions: Dictionary = {}
var _retain_unused := false
var _pipeline_width := 1
var _request_limit := MAX_REQUESTS
var _completion_frame := -1
var _frame_collected := 0
var _collection_usec := 0
## 负载均衡：含物理步的帧主线程已付出整步脚本物理（~5ms），无步帧尚有余量。
## 完成件领取（网格校验）与 GPU 纹理上传优先落到无物理步帧；最多连续延后
## LIGHT_FRAME_MAX_DEFER 帧，满载（每帧都有物理步）时照常推进，关闭排空不延后。
## 默认关闭（单测逐帧断言领取结果）；正式 HLOD overlay 创建流时开启。
const LIGHT_FRAME_MAX_DEFER := 3
var light_frame_balance := false
var light_frame_deferrals := 0
var _light_defer_frame := -1
var _light_defer_result := false
var _light_defer_run := 0


func configure(owner_node: Node, descriptors: Dictionary) -> void:
	_audit_paths = OS.get_environment("AGL_TOKYO_STREAM_AUDIT") == "1"
	_retain_unused = OS.get_environment("AGL_TOKYO_RETAIN_UNUSED") == "1"
	_owner_ref = weakref(owner_node)
	owner_node.tree_exiting.connect(close, CONNECT_ONE_SHOT)
	_descriptors = descriptors
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_priority = 1000
	set_process(false)


func request(wanted: PackedStringArray, pins: PackedStringArray) -> void:
	if _closed:
		return
	if wanted == _wanted and pins == _pins:
		return
	# Packed数组按引用传递；调用方清空列表不能绕过下一次request的缓存清理。
	_wanted = wanted.duplicate()
	_pins = pins.duplicate()
	_prune()
	set_process(true)


func resource(path: String) -> Resource:
	return _cache.get(path) as Resource


func geometry_budget() -> int:
	return BUDGET - _auxiliary_bytes


func reserve_auxiliary(key: int, amount: int) -> bool:
	# 身份只存值；纹理由其唯一owner持有，不能让预算表强引用延长生命期。
	# RefCounted实例ID最高位可置位，在GDScript有符号int中为负；仅0是空身份。
	if _closed or key == 0 or amount <= 0 or _auxiliary.has(key):
		return false
	if _retain_unused and amount <= geometry_budget():
		_prune(amount)
	if amount > geometry_budget() - _bytes - _reserved:
		return false
	_auxiliary[key] = amount
	_auxiliary_bytes += amount
	peak_total_bytes = maxi(peak_total_bytes, _bytes + _reserved + _auxiliary_bytes)
	return true


func release_auxiliary(key: int) -> void:
	_auxiliary_bytes -= int(_auxiliary.get(key, 0))
	_auxiliary.erase(key)
	if _closed or not _wanted.is_empty():
		set_process(true)


func _prune(required: int = 0) -> void:
	for path: String in _cache.keys():
		# 候选只利用原预算剩余空间，按载入顺序淘汰非目标/非固定资源。
		if _retain_unused and _bytes + _reserved + required <= geometry_budget():
			break
		if path not in _wanted and path not in _pins:
			if _audit_paths:
				_audit_evictions[path] = int(_audit_evictions.get(path, 0)) + 1
			_bytes -= int(_cache[path].geometry_bytes)
			_cache.erase(path)


func _process(_delta: float) -> void:
	var trace := PerfBuckets.frame_trace_enabled
	var start := Time.get_ticks_usec() if trace else 0
	_process_stream()
	if trace:
		PerfBuckets.tick("tokyo_map_stream", Time.get_ticks_usec() - start)


## 本帧是否把主线程重活让给后续无物理步帧；同帧多次询问结果一致，只在真有待办时调用。
func defer_to_light_frame() -> bool:
	var frame := Engine.get_process_frames()
	if frame == _light_defer_frame:
		return _light_defer_result
	_light_defer_frame = frame
	_light_defer_result = light_frame_balance and not _closed \
		and is_inside_tree() and not get_tree().paused \
		and PerfBuckets.frame_has_physics_step() and _light_defer_run < LIGHT_FRAME_MAX_DEFER
	if _light_defer_result:
		_light_defer_run += 1
		light_frame_deferrals += 1
	else:
		_light_defer_run = 0
	return _light_defer_result


## 子类声明哪些路径属于当前可见切面、不参与负载均衡延后（基类无可见集合）。
func _light_defer_exempt(_path: String) -> bool:
	return false


func _collect_completed() -> void:
	# 正常更新与交接前末次领取共用帧预算，不能靠多次调用突破上限。
	var frame := Engine.get_process_frames()
	if frame != _completion_frame:
		_completion_frame = frame
		_frame_collected = 0
		_collection_usec = 0
	if _frame_collected >= _pipeline_width or _collection_usec >= 1000:
		return
	var completion_start := Time.get_ticks_usec()
	for path: String in _pending.keys():
		var status := _load_status(path)
		if status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			continue
		# 当前视野所需件照常领取，只把预取/驻留件让给无物理步帧，不拖慢可见切面交接。
		if not _light_defer_exempt(path) and defer_to_light_frame():
			continue
		PerfBuckets.mark_frame_event("tokyo_cell_take")
		var reserve: int = _pending[path]
		_pending.erase(path)
		_busy.erase(path)
		_reserved -= reserve
		if status == ResourceLoader.THREAD_LOAD_LOADED:
			var time := Time.get_ticks_usec()
			var item: Resource = _take_load(path)
			var take_elapsed := Time.get_ticks_usec() - time
			max_take_usec = maxi(max_take_usec, take_elapsed)
			if PerfBuckets.frame_trace_enabled: PerfBuckets.tick("tokyo_map_stream.mesh_take",take_elapsed)
			# GL请求已经完成；闲置缓存策略同样接管在途完成件，不重发I/O。
			# Dummy尚未实际加载，不为已取消请求补做同步加载；关闭后仍只排空。
			var idle_completion := _retain_unused and not _main_thread_meshes and path not in _wanted and path not in _pins
			if not _closed and (path in _wanted or path in _pins or idle_completion):
				if _matches(item, path) and _bytes + int(item.geometry_bytes) + _reserved <= geometry_budget():
					_cache[path] = item
					_bytes += int(item.geometry_bytes)
					completed += 1
					if idle_completion: retained_completions += 1
				else:
					_failures[path] = "invalid archive or geometry budget"
			else:
				discarded += 1
		else:
			if status == ResourceLoader.THREAD_LOAD_FAILED:
				# 已终结失败请求也要领取，以释放引擎内请求槽；绝不领取仍IN_PROGRESS的项。
				ResourceLoader.load_threaded_get(path)
			_failures[path] = "background load failed"
		_frame_collected += 1
		if _frame_collected>=_pipeline_width or _collection_usec+Time.get_ticks_usec()-completion_start>=1000: break
	_collection_usec += Time.get_ticks_usec()-completion_start
	max_completed_per_frame = maxi(max_completed_per_frame, _frame_collected)


func _process_stream() -> void:
	var owner_node: Variant = _owner_ref.get_ref() if _owner_ref != null else null
	if typeof(owner_node) != TYPE_OBJECT or not is_instance_valid(owner_node):
		close()
	_collect_completed()
	if _closed:
		if _pending.is_empty() and _auxiliary.is_empty():
			set_process(false)
			queue_free()
		return
	var waiting := false
	var requested := 0
	for path: String in _wanted:
		if _cache.has(path) or _pending.has(path) or _failures.has(path):
			continue
		waiting = true
		if _busy.size() >= _request_limit or _busy.has(path):
			break
		var amount := int(_descriptors.get(path, {}).get("bytes", BUDGET + 1))
		# 纯海面块合法拥有零建筑几何；仍须读取原生归档并通过身份/标高校验。
		if amount < 0 or amount > BUDGET:
			_failures[path] = "missing or invalid descriptor"
			continue
		if _retain_unused and _bytes + _reserved + amount > geometry_budget():
			_prune(amount)
		if _bytes + _reserved + amount > geometry_budget():
			break
		if not ResourceLoader.exists(path):
			_failures[path] = "missing resource"
			continue
		PerfBuckets.mark_frame_event("tokyo_cell_request")
		var error := _request_load(path)
		if error != OK:
			_failures[path] = "request rejected: %d" % error
			continue
		_busy[path] = get_instance_id()
		_pending[path] = amount
		_reserved += amount
		started += 1
		requested += 1
		if _audit_paths:
			_audit_requests[path] = int(_audit_requests.get(path, 0)) + 1
		if requested>=_pipeline_width: break
	peak_pending = maxi(peak_pending, _pending.size())
	peak_bytes = maxi(peak_bytes, _bytes + _reserved)
	peak_total_bytes = maxi(peak_total_bytes, _bytes + _reserved + _auxiliary_bytes)
	if not waiting and _pending.is_empty():
		set_process(false)


func _request_load(path: String) -> Error:
	if _main_thread_meshes:
		_main_queued[path] = Engine.get_process_frames()
		return OK
	return ResourceLoader.load_threaded_request(path, "", false, ResourceLoader.CACHE_MODE_IGNORE)


func _load_status(path: String) -> int:
	if _main_thread_meshes:
		return ResourceLoader.THREAD_LOAD_LOADED if Engine.get_process_frames() > int(_main_queued[path]) else ResourceLoader.THREAD_LOAD_IN_PROGRESS
	return ResourceLoader.load_threaded_get_status(path)


func _take_load(path: String) -> Resource:
	if _main_thread_meshes:
		_main_queued.erase(path)
		if _closed or (path not in _wanted and path not in _pins):
			return null
		return ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
	return ResourceLoader.load_threaded_get(path)


func _matches(item: Resource, path: String) -> bool:
	if item == null or not item.has_method("valid") or not item.valid():
		return false
	var expected: Dictionary = _descriptors[path]
	if expected.has("canonical_identity"):
		return item.has_method("stream_identity") and item.stream_identity() == expected.canonical_identity \
			and int(item.geometry_bytes) == int(expected.bytes)
	# 新格式不能误配旧描述符后继续访问不存在的height_hash。
	if item.has_method("stream_identity"):
		return false
	return int(item.cell_id) == int(expected.id) and int(item.level) == int(expected.level) \
		and int(item.geometry_bytes) == int(expected.bytes) \
		and (int(item.level) == -1 or String(item.height_hash) == String(expected.height_hash)) \
		and (not expected.has("source_hash") or String(item.get("source_hash")) == String(expected.source_hash)) \
		and (not expected.has("package_variant") or String(item.get("package_variant")) == String(expected.package_variant))


func close() -> void:
	if not _closed:
		_closed = true
		_wanted.clear()
		_pins.clear()
		_cache.clear()
		_bytes = 0
	set_process(true)


func _exit_tree() -> void:
	# 正常换场由close跨帧排空；应用退出没有下一帧，必须兜底领取并归还静态槽。
	close()
	for path: String in _pending:
		if not _main_thread_meshes: ResourceLoader.load_threaded_get(path)
		_busy.erase(path)
	_pending.clear();_main_queued.clear();_reserved=0


func summary() -> Dictionary:
	return {"loader_backend": "main_thread_deferred" if _main_thread_meshes else "resource_loader_threaded",
		"bytes": _bytes, "reserved_bytes": _reserved, "peak_bytes": peak_bytes,
		"auxiliary_bytes": _auxiliary_bytes, "geometry_budget": geometry_budget(),
		"total_bytes": _bytes + _reserved + _auxiliary_bytes, "peak_total_bytes": peak_total_bytes,
		"pending": _pending.size(), "peak_pending": peak_pending, "cached": _cache.size(),
		"started": started, "completed": completed, "discarded": discarded, "closed": _closed,
		"failures": _failures.duplicate(), "max_take_usec": max_take_usec,
		"light_frame_deferrals": light_frame_deferrals,
		"path_audit_enabled": _audit_paths, "path_requests": _audit_requests.duplicate(),
		"retain_unused": _retain_unused, "retained_completions": retained_completions,
		"path_evictions": _audit_evictions.duplicate(),
		"max_completed_per_frame": max_completed_per_frame}
