extends "res://scripts/rendering/tokyo_component_stream.gd"
## 新HLOD贴图与网格共用原预算/请求上限/更新循环。调用方先解绑退役材质，再撤销pins。
const Contract := preload("res://scripts/rendering/tokyo_hlod_manifest.gd")
const Coverage := preload("res://scripts/rendering/tokyo_hlod_coverage.gd")
const MAX_IMAGE_WORKERS := 4
const DECODED_LIMIT := 32*1024*1024
const DECODED_COUNT := 8
const DECODED_TTL_MS := 500
var retain_decoded := OS.get_environment("AGL_TOKYO_RETAIN_DECODED_IMAGE")=="1"
var _decoded_images: Dictionary = {}
var decoded_reuses := 0
var detach_decoded := OS.get_environment("AGL_TOKYO_DETACH_DECODED_IMAGE")=="1"
var decoded_detaches := 0
# 原16页切面的地表租约上限；只为小额交接回收可立即释放的非保护网格。
const IMMEDIATE_AUXILIARY_MAX := 16*288
var small_auxiliary_reclaims := 0
var _texture_descriptors: Dictionary = {}
var _texture_wanted := PackedStringArray()
var _texture_pins := PackedStringArray()
var _textures: Dictionary = {}
var _texture_jobs: Dictionary = {}
var _texture_retiring: Dictionary = {}
var _texture_reservations: Dictionary = {}
var _texture_errors: Dictionary = {}
var texture_started := 0
var texture_completed := 0
var max_texture_upload_usec := 0
var max_texture_uploads_per_frame := 0
var texture_upload_usec := 0
var _texture_upload_frame := -1
var reuse_textures := preload("res://scripts/rendering/tokyo_installed_map.gd").runtime_option("AGL_TOKYO_REUSE_TEXTURE") == "1"
var texture_reuses := 0
var texture_slot_handoffs := 0
var texture_reuse_usec := 0
var max_texture_reuse_usec := 0
var mesh_digest_usec := 0
var mesh_finalize_deferred_frames := 0
# 小页上传期间也让原一毫秒领取门最多推进一个网格，避免连续图片帧饿死回中几何。
# 复用已有受限路径；显式0仍可关闭，资源池、请求槽与单次领取预算不变。
var minimum_mesh_progress := preload("res://scripts/rendering/tokyo_installed_map.gd").runtime_option("AGL_TOKYO_MESH_PROGRESS")=="1" \
	or (not OS.has_environment("AGL_TOKYO_MESH_PROGRESS") and preload("res://scripts/rendering/tokyo_installed_map.gd").motion_admission_enabled("AGL_TOKYO_RETURN_CACHE"))
var minimum_mesh_progress_frames := 0
var visible_io_first := OS.get_environment("AGL_TOKYO_VISIBLE_IO_FIRST")=="1"
var visible_meshes := PackedStringArray()
var visible_images := PackedStringArray()
var speculative_image_deferrals := 0
var fair_image_slot := OS.get_environment("AGL_TOKYO_FAIR_IMAGE_SLOT")=="1"
var balanced_io := OS.get_environment("AGL_TOKYO_BALANCED_IO")=="1"
var input_waiting := false
var visible_finalize_first := OS.get_environment("AGL_TOKYO_VISIBLE_FINALIZE_FIRST")=="1"
var speculative_upload_deferrals := 0
var visible_dispatch_yield := OS.get_environment("AGL_TOKYO_VISIBLE_DISPATCH_YIELD")=="1"
var visible_dispatch_deferrals := 0
## 正式位置证明核验结果（path -> "文件SHA|位置SHA"），只存字符串，不持有资源。
var _formal_verified: Dictionary = {}
var formal_verify_reuses := 0
var _mesh_checks: Dictionary = {}
var _mesh_hashes: Dictionary = {}
var mesh_checks_started := 0
var mesh_checks_completed := 0
var async_mesh_dispatch := preload("res://scripts/rendering/tokyo_installed_map.gd").runtime_option("AGL_TOKYO_RETURN_CACHE")=="1"
var _mesh_dispatches: Dictionary = {}
var _mesh_dispatch_rejected: Dictionary = {}
var mesh_dispatches_started := 0
var mesh_dispatches_completed := 0
var residency_meshes := PackedStringArray()
var residency_images := PackedStringArray()
var residency_bytes := 0
var residency_limit := BUDGET
var _texture_audit: Dictionary = {}
var _cache_access: Dictionary = {}
var cache_lru := preload("res://scripts/rendering/tokyo_installed_map.gd").runtime_option("AGL_TOKYO_CACHE_LRU")=="1"
var recent_mesh_grace := OS.get_environment("AGL_TOKYO_RECENT_MESH_GRACE")=="1"
var _recent_mesh_until: Dictionary={}


func _audit_texture(path: String, event: String, elapsed: int = 0) -> void:
	# 仅显式STREAM_AUDIT诊断；按资源身份有界，不在正常局保留路径历史。
	if not _audit_paths: return
	var row: Dictionary = _texture_audit.get(path,{"sha256":_texture_descriptors[path].sha256,
		"charge":_texture_descriptors[path].charge,"mip_bytes":_texture_descriptors[path].mip_bytes,
		"width":_texture_descriptors[path].width,"height":_texture_descriptors[path].height,
		"max_upload_usec":0})
	row[event]=int(row.get(event,0))+1
	if event=="upload":
		row["last_upload_frame"]=PerfBuckets._trace_frame_index
		if elapsed>int(row.max_upload_usec):
			row["max_upload_usec"]=elapsed
			row["max_upload_frame"]=PerfBuckets._trace_frame_index
	_texture_audit[path]=row


func configure_residency(meshes: PackedStringArray, images: PackedStringArray, pool_limit: int = 384*1024*1024, extend_existing: bool = false) -> bool:
	if _closed or _owner_ref==null or (residency_bytes!=0 and not extend_existing) or not _cache.is_empty() or not _textures.is_empty() \
		or not _pending.is_empty() or not _texture_jobs.is_empty() or not _decoded_images.is_empty(): return false
	# 只允许首个加载tick之前追加完整邻区；原常驻保护与池档位不能被替换或丢弃。
	if extend_existing and residency_bytes>0:
		if pool_limit!=residency_limit: return false
		for path: String in residency_meshes:
			if path not in meshes: return false
		for path: String in residency_images:
			if path not in images: return false
	var amount := preload("res://scripts/rendering/tokyo_hlod_handoff.gd").streaming_bytes(_logical,_texture_descriptors,meshes,images,0)
	# 显式候选预算：常驻集外仍为原96MiB交接留空间，不伪装成原预算通过。
	if pool_limit not in [384*1024*1024,768*1024*1024,1536*1024*1024] \
		and not (pool_limit==3072*1024*1024 and OS.get_environment("AGL_TOKYO_STATIC_NATIVE")=="1") \
		and not (pool_limit==4096*1024*1024 and OS.get_environment("AGL_TOKYO_COMPLETE_FOUNDATION")=="1" and OS.get_environment("AGL_TOKYO_STATIC_NATIVE")!="1"): return false
	if amount<=0 or amount>pool_limit-BUDGET: return false
	residency_meshes=meshes.duplicate();residency_images=images.duplicate()
	residency_bytes=amount;residency_limit=pool_limit
	return true


var _residency_ledger: Dictionary={}
var _ledger_meshes := PackedStringArray()
var _ledger_images := PackedStringArray()


func residency_request_ledger(ground: int) -> Dictionary:
	# 目录在configure_hlod后不变；固定集追加/接管解除邻区时由值快照失效。
	# 缓存纯描述符，不持有Mesh/Image；每次返回独立的可写账本键表。
	if _closed or ground<0: return {}
	if _residency_ledger.is_empty() or _ledger_meshes!=residency_meshes or _ledger_images!=residency_images:
		var ledger := {"bytes":0,"meshes":{},"images":{}}
		if not preload("res://scripts/rendering/tokyo_hlod_handoff.gd").append_streaming_bundle(ledger,_logical,_texture_descriptors,residency_meshes,residency_images,residency_limit): return {}
		_residency_ledger=ledger
		_ledger_meshes=residency_meshes.duplicate();_ledger_images=residency_images.duplicate()
	if int(_residency_ledger.bytes)+ground>residency_limit: return {}
	return {"bytes":int(_residency_ledger.bytes)+ground,"meshes":_residency_ledger.meshes.duplicate(),"images":_residency_ledger.images.duplicate()}


func handoff_increment(geometry: Dictionary, textures: Dictionary, meshes: PackedStringArray, images: PackedStringArray, ground: int) -> int:
	if _closed or ground<0: return -1
	# 只在固定集合变化时沿原入口刷新；不把内部可写Dictionary暴露给调用者。
	if _residency_ledger.is_empty() or _ledger_meshes!=residency_meshes or _ledger_images!=residency_images:
		if residency_request_ledger(0).is_empty(): return -1
	if int(_residency_ledger.bytes)!=residency_bytes: return -1
	var delta := {"bytes":ground,"meshes":{},"images":{}}
	if not preload("res://scripts/rendering/tokyo_hlod_handoff.gd").append_streaming_bundle(delta,geometry,textures,meshes,images,9223372036854775807,_residency_ledger): return -1
	return int(delta.bytes)


func geometry_budget() -> int:
	return residency_limit-_auxiliary_bytes


func residency_ready() -> bool:
	for path: String in residency_meshes:
		if resource(path)==null: return false
	for path: String in residency_images:
		if texture(path)==null: return false
	return true


func _retirement_data() -> Array:
	var values: Array=super._retirement_data()
	values.append(_texture_descriptors)
	return values


func configure_hlod(owner_node: Node, geometry: Dictionary, textures: Dictionary) -> bool:
	if _owner_ref != null or _closed: return false
	return configure_prepared_hlod(owner_node,prepare_hlod_source(geometry,textures))


static func prepare_hlod_source(geometry: Dictionary, textures: Dictionary) -> Dictionary:
	for path: Variant in textures:
		var row: Variant = textures[path]
		if not path is String or geometry.has(path) or not row is Dictionary: return {}
		if row.has("mipmaps") and row.mipmaps!=true and not preload("res://scripts/rendering/tokyo_ground_height.gd").valid_texture(row): return {}
		if not Contract.sha(row.get("sha256")) or not Contract.integer(row.get("width"),1,16384) \
			or not Contract.integer(row.get("height"),1,16384) or not Contract.integer(row.get("mip_bytes"),1) \
			or (row.get("format")!=Image.FORMAT_DXT1 and row.get("format")!=Image.FORMAT_DXT5 and not preload("res://scripts/rendering/tokyo_ground_height.gd").valid_texture(row)) or row.get("charge")!=int(row.mip_bytes)*3+4096: return {}
	return {"textures":textures.duplicate(true),"layout":prepare_layout(geometry.duplicate(true))}


func configure_prepared_hlod(owner_node: Node, prepared: Dictionary) -> bool:
	# prepared 仅来自上面的验证函数，完成后台任务后由此唯一接管，不再次复制全图。
	if _owner_ref!=null or _closed or prepared.is_empty(): return false
	_texture_descriptors=prepared.textures
	_configure_layout(owner_node,prepared.layout)
	fast_file_probe=preload("res://scripts/rendering/tokyo_installed_map.gd").runtime_option("AGL_TOKYO_FAST_FILE_PROBE")=="1"
	# 同池复用不增加预算；明确0才关闭，供相同条件A/B使用。
	_retain_unused=OS.get_environment("AGL_TOKYO_RETAIN_UNUSED")!="0"
	# 低帧率下也允许细组件提前就绪；领取仍受父级1000us门、原字节预算约束。
	_request_limit=MAX_REQUESTS if _main_thread_meshes else 8
	_pipeline_width=1 if _main_thread_meshes else _request_limit
	return true


func request_residency_only() -> void:
	# 暂无合格显示切面不等于退出地图；固定基础层仍需保持同池保护及未完成加载。
	request_partitioned(PackedStringArray(),residency_meshes,PackedStringArray(),PackedStringArray())
	request_textures(residency_images,residency_images)


func request_textures(wanted: PackedStringArray, pins: PackedStringArray) -> void:
	if _closed: return
	_texture_wanted=wanted.duplicate()
	_texture_pins=pins.duplicate()
	_release_texture_reservations()
	for path: String in _textures.keys():
		if reuse_textures:
			if path in _texture_wanted or path in _texture_pins:
				_textures[path].erase("unused_frame")
			elif not _textures[path].has("unused_frame"):
				_textures[path]["unused_frame"]=Engine.get_process_frames()
		if not _retain_unused and path not in _texture_wanted and path not in _texture_pins:
			var row: Dictionary = _textures[path]
			row["retire_frame"]=Engine.get_process_frames()+2
			_texture_retiring[path]=row
			_textures.erase(path)
			_audit_texture(path,"unwanted_retire")
	prepare_target_space()
	set_process(true)


func prepare_target_space() -> void:
	# 只提前退役非目标缓存，不提前释放计费、不增加请求/上传额度。
	# 完整目标的缺口一次规划，避免每份资源各等待两帧退役。
	if _closed or not _retain_unused: return
	var missing := 0
	for path: String in _wanted:
		if not _cache.has(path) and not _pending.has(path):
			missing+=int(_descriptors.get(path,{}).get("bytes",BUDGET+1))
	for path: String in _texture_wanted:
		if not _textures.has(path) and not _texture_jobs.has(path) and not _texture_retiring.has(path) and not _decoded_images.has(path) and not _texture_reservations.has(path):
			missing+=int(_texture_descriptors.get(path,{}).get("charge",BUDGET+1))
	if missing>0: _prune(missing)


func _prune(required: int = 0) -> void:
	# 暂存CPU图不得挤占当前请求；归还原预约后再走既有网格/GPU退役。
	for path: String in _decoded_images.keys():
		if _bytes+_reserved+required<=geometry_budget(): break
		if path not in _texture_wanted and path not in _texture_pins: _release_decoded(path)
	if _retain_unused and (cache_lru or residency_limit>=768*1024*1024):
		_prune_lru(required)
		return
	super._prune(required)
	if not _retain_unused: return
	var retiring_bytes := 0
	for path: String in _texture_retiring:
		retiring_bytes+=int(_texture_descriptors[path].charge)
	for path: String in _textures.keys():
		if _bytes+_reserved+required<=geometry_budget()+retiring_bytes: break
		if path in _texture_wanted or path in _texture_pins: continue
		var row: Dictionary = _textures[path]
		row["retire_frame"]=Engine.get_process_frames()+2
		_texture_retiring[path]=row
		_textures.erase(path)
		_audit_texture(path,"budget_retire")
		retiring_bytes+=int(_texture_descriptors[path].charge)
	# 只计划释放；预算仍由既有两帧退役路径实际归还，申请方须等待。
	if not _texture_retiring.is_empty(): set_process(true)


func touch_display_resources(meshes: PackedStringArray, images: PackedStringArray) -> void:
	if not cache_lru and residency_limit<768*1024*1024: return
	var frame := Engine.get_process_frames()
	for path: String in _paths(meshes):
		if _cache.has(path): _cache_access[path]=frame
	for path: String in images:
		if _textures.has(path) or _texture_retiring.has(path): _cache_access[path]=frame


func _prune_lru(required: int, immediate_meshes: bool = false) -> void:
	# 软保护而非pin：短时需求摆动先淘汰其他闲置项，压力无解时仍严格回收。
	var now := Time.get_ticks_msec()
	if recent_mesh_grace:
		for path: String in _recent_mesh_until.keys():
			if int(_recent_mesh_until[path])<=now: _recent_mesh_until.erase(path)
		for path: String in _wanted: _recent_mesh_until[path]=now+500
	var shortage := _bytes+_reserved+required-geometry_budget()
	if not immediate_meshes:
		for path: String in _texture_retiring: shortage-=int(_texture_descriptors[path].charge)
	if shortage<=0: return
	var candidates: Array[Array]=[]
	# 数千常驻组件不能逐缓存项线性扫两份请求数组；集合只活在本次裁剪，不会跨请求过期。
	var kept_meshes: Dictionary={}
	var kept_images: Dictionary={}
	for path: String in _wanted: kept_meshes[path]=true
	for path: String in _pins: kept_meshes[path]=true
	for path: String in _texture_wanted: kept_images[path]=true
	for path: String in _texture_pins: kept_images[path]=true
	for path: String in _cache:
		if not kept_meshes.has(path):
			candidates.append([int(_cache_access.get(path,-1)),path,false,int(_cache[path].geometry_bytes),int(recent_mesh_grace and int(_recent_mesh_until.get(path,0))>now)])
	for path: String in _textures:
		if not immediate_meshes and not kept_images.has(path):
			candidates.append([int(_cache_access.get(path,-1)),path,true,int(_texture_descriptors[path].charge),0])
	# 统一实际使用时间；从未实际使用的预测页优先淘汰，避免两类资源相互挤死。
	candidates.sort_custom(func(a: Array,b: Array) -> bool: return a[4]<b[4] or (a[4]==b[4] and (a[0]<b[0] or (a[0]==b[0] and a[1]<b[1]))))
	for item: Array in candidates:
		if shortage<=0: break
		var path: String=item[1]
		if item[2]:
			var row: Dictionary=_textures[path]
			row["retire_frame"]=Engine.get_process_frames()+2
			_texture_retiring[path]=row;_textures.erase(path)
			_audit_texture(path,"budget_retire")
		else:
			if _audit_paths: _audit_evictions[path]=int(_audit_evictions.get(path,0))+1
			_bytes-=int(item[3]);_cache.erase(path);_cache_access.erase(path)
			_recent_mesh_until.erase(path)
		shortage-=int(item[3])
	# 不提前减图片计费；申请仍被真实预算挡住，直到两帧退役完成。
	if not _texture_retiring.is_empty(): set_process(true)


func reserve_auxiliary(key: int, amount: int) -> bool:
	if _retain_unused and not _closed and key!=0 and amount>0 and amount<=BUDGET and not _auxiliary.has(key):
		_prune(amount)
		# 退役图只代表未来容量；小地表已ready时不应因未来容量而放弃当前可回收网格。
		if amount<=IMMEDIATE_AUXILIARY_MAX and _bytes+_reserved+amount>geometry_budget():
			var before := _bytes
			_prune_lru(amount,true)
			if _bytes<before: small_auxiliary_reclaims+=1
	return super.reserve_auxiliary(key,amount)


func texture(path: String) -> Texture2D:
	return _textures.get(path,{}).get("texture") as Texture2D


func can_start_image(path: String) -> bool:
	# 只挡新增预测I/O，不挡目标纹理、在途领取及关闭清理；目标网格入队后即可并行。
	if not visible_io_first or path in visible_images: return true
	for mesh: String in visible_meshes:
		if not _cache.has(mesh) and not _pending.has(mesh) and not _failures.has(mesh): return false
	return true


func _matches(item: Resource, path: String) -> bool:
	if not super._matches(item,path): return false
	var descriptor: Dictionary = _descriptors[path]
	if descriptor.has("sha256"):
		var started_at := Time.get_ticks_usec()
		var actual: String = FileAccess.get_sha256(path) if _main_thread_meshes else String(_mesh_hashes.get(path,""))
		_mesh_hashes.erase(path)
		var matches: bool = actual==descriptor.sha256
		var digest_elapsed := Time.get_ticks_usec()-started_at
		mesh_digest_usec+=digest_elapsed
		if PerfBuckets.frame_trace_enabled: PerfBuckets.tick("tokyo_map_stream.digest",digest_elapsed)
		if not matches: return false
	if not descriptor.has("formal_positions_sha256"): return true
	# 本次领取已核对文件 SHA 时，同一路径+同一文件 SHA+同一位置证明本会话已核验过即复用：
	# 文件字节相同则载入网格位置相同；省去主线程回读、逐索引展开与哈希（每次 0.5–1ms）。
	var proof_key := "%s|%s" % [descriptor.sha256,descriptor.formal_positions_sha256] if descriptor.has("sha256") else ""
	if not proof_key.is_empty() and String(_formal_verified.get(path,""))==proof_key:
		formal_verify_reuses+=1
		return item.meshes.size()==2
	var verify_started := Time.get_ticks_usec() if PerfBuckets.frame_trace_enabled else 0
	var verified: bool = item.meshes.size()==2 and Coverage.matches(item.meshes[1],descriptor)
	if PerfBuckets.frame_trace_enabled: PerfBuckets.tick("tokyo_map_stream.coverage_verify",Time.get_ticks_usec()-verify_started)
	if verified and not proof_key.is_empty(): _formal_verified[path]=proof_key
	return verified


static func checksum_file(path: String) -> String:
	return FileAccess.get_sha256(path)


static func checksum_after_load(path: String) -> String:
	# 原共享请求槽内等待；后台只查询加载状态，主线程仍唯一领取资源。
	var status := ResourceLoader.load_threaded_get_status(path)
	while status==ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		OS.delay_msec(1)
		status=ResourceLoader.load_threaded_get_status(path)
	return checksum_file(path) if status==ResourceLoader.THREAD_LOAD_LOADED else ""


static func request_and_checksum(path: String, known: bool, direct_probe: bool) -> Dictionary:
	# 仅处理独立路径/纯值；场景、共享字典及资源领取仍只在主线程访问。
	var exists := known or (direct_probe and not path.begins_with("uid://") and FileAccess.file_exists(path))
	if not exists: exists=ResourceLoader.exists(path)
	if not exists: return {"requested":false,"error":"missing resource"}
	var error := ResourceLoader.load_threaded_request(path,"",false,ResourceLoader.CACHE_MODE_IGNORE)
	if error!=OK: return {"requested":false,"error":"request rejected: %d"%error}
	var digest := checksum_after_load(path)
	return {"requested":true,"sha256":digest}


func _defer_resource_probe(path: String) -> bool:
	return async_mesh_dispatch and not _main_thread_meshes and _descriptors.get(path,{}).has("sha256")


func _finish_mesh_dispatch(path: String) -> void:
	var worker: Thread = _mesh_dispatches[path]
	var result: Dictionary = worker.wait_to_finish()
	_mesh_dispatches.erase(path)
	mesh_dispatches_completed+=1
	if not result.requested:
		_mesh_dispatch_rejected[path]=true
		_failures[path]=String(result.error)
	else:
		_known_resources[path]=true
		_mesh_hashes[path]=String(result.sha256)


func _request_load(path: String) -> Error:
	# 上次加载可能已完成但被相机取消，未经过_matches；旧摘要不能使新请求提前ready。
	_mesh_hashes.erase(path)
	_mesh_dispatch_rejected.erase(path)
	if _defer_resource_probe(path):
		var worker := Thread.new()
		var error := worker.start(request_and_checksum.bind(path,_known_resources.has(path),fast_file_probe))
		if error!=OK: return error
		_mesh_dispatches[path]=worker
		mesh_dispatches_started+=1
		return OK
	var trace := PerfBuckets.frame_trace_enabled
	var phase_started := Time.get_ticks_usec() if trace else 0
	var result := super._request_load(path)
	if trace:
		PerfBuckets.tick("tokyo_map_stream.request_load",Time.get_ticks_usec()-phase_started)
		phase_started=Time.get_ticks_usec()
	if result==OK and not _main_thread_meshes and _descriptors[path].has("sha256"):
		var worker := Thread.new()
		if worker.start(checksum_after_load.bind(path))==OK:
			_mesh_checks[path]=worker
			mesh_checks_started+=1
		if trace: PerfBuckets.tick("tokyo_map_stream.checksum_start",Time.get_ticks_usec()-phase_started)
		# 启动失败时沿_load_status原路径重试，不跳过摘要验证。
	return result


func _load_status(path: String) -> int:
	if _mesh_dispatches.has(path):
		var dispatch: Thread = _mesh_dispatches[path]
		if dispatch.is_alive(): return ResourceLoader.THREAD_LOAD_IN_PROGRESS
		_finish_mesh_dispatch(path)
	# 尚未向ResourceLoader登记的失败不能调用load_threaded_get；父级仍归还预约和槽。
	if _mesh_dispatch_rejected.has(path): return ResourceLoader.THREAD_LOAD_INVALID_RESOURCE
	var status := super._load_status(path)
	if _closed or _main_thread_meshes or status!=ResourceLoader.THREAD_LOAD_LOADED or not _descriptors[path].has("sha256"):
		return status
	if _mesh_hashes.has(path): return status
	if not _mesh_checks.has(path):
		var worker := Thread.new()
		if worker.start(checksum_file.bind(path))!=OK:
			_failures[path]="checksum worker rejected"
			return ResourceLoader.THREAD_LOAD_FAILED
		_mesh_checks[path]=worker
		mesh_checks_started+=1
		return ResourceLoader.THREAD_LOAD_IN_PROGRESS
	var worker: Thread = _mesh_checks[path]
	if worker.is_alive(): return ResourceLoader.THREAD_LOAD_IN_PROGRESS
	_mesh_hashes[path]=worker.wait_to_finish()
	mesh_checks_completed+=1
	_mesh_checks.erase(path)
	return status


func _exit_tree() -> void:
	close()
	for path: String in _mesh_dispatches.keys(): _finish_mesh_dispatch(path)
	for path: String in _mesh_dispatch_rejected:
		_busy.erase(path)
		_reserved-=int(_pending.get(path,0))
		_pending.erase(path)
	_mesh_dispatch_rejected.clear()
	for worker: Thread in _mesh_checks.values(): worker.wait_to_finish()
	_mesh_checks.clear();_mesh_hashes.clear()
	for path: String in _texture_jobs:
		var job: Dictionary = _texture_jobs[path]
		job.worker.wait_to_finish()
		_busy.erase(path)
		release_auxiliary(job.token.get_instance_id())
	_texture_jobs.clear()
	super._exit_tree()


static func load_image(path: String, expected: Dictionary) -> Dictionary:
	# 工作线程只读取独立Image，不访问Node/GPU。先后摘要防止读取期间来源变化。
	if not FileAccess.file_exists(path) or FileAccess.get_sha256(path)!=expected.sha256:
		return {"error":"texture source digest mismatch"}
	var item: Resource = ResourceLoader.load(path,"Image",ResourceLoader.CACHE_MODE_IGNORE)
	if not item is Image or item.get_width()!=int(expected.width) or item.get_height()!=int(expected.height) \
		or item.get_format()!=int(expected.format) or item.has_mipmaps()!=bool(expected.get("mipmaps",true)) \
		or item.get_data_size()!=int(expected.mip_bytes) or FileAccess.get_sha256(path)!=expected.sha256:
		return {"error":"texture native payload mismatch"}
	return {"image":item}


static func can_upload_texture(count: int, elapsed_usec: int, previous_bytes: int, next_bytes: int) -> bool:
	return count==0 or (count==1 and elapsed_usec<1000 and previous_bytes<=1048576 and next_bytes<=1048576)


func _take_recycled_slot(path: String, allow_cached: bool = false) -> Dictionary:
	# 同规格旧 GPU + 新 Image 的加载/上传暂存仍由原完整三份费用覆盖，不再申请第二份额度。
	if not reuse_textures or _closed: return {}
	var expected: Dictionary=_texture_descriptors[path]
	var frame := Engine.get_process_frames()
	# 有容量就保留已加载地图；复用不能为了省一次创建而制造后续重读。
	var banks: Array[Dictionary]=[_texture_retiring]
	if allow_cached: banks.append(_textures)
	for bank: Dictionary in banks:
		for donor: String in bank:
			if donor==path or donor in _texture_wanted or donor in _texture_pins: continue
			var row: Dictionary=bank[donor]
			var ready_at := int(row.get("retire_frame",int(row.get("unused_frame",frame))+2))
			if frame<ready_at: continue
			var previous: Dictionary=_texture_descriptors[donor]
			if previous.width!=expected.width or previous.height!=expected.height \
				or previous.format!=expected.format or previous.get("mipmaps",true)!=expected.get("mipmaps",true) \
				or previous.charge!=expected.charge or previous.mip_bytes!=expected.mip_bytes: continue
			var texture := row.get("texture") as ImageTexture
			# 字典和本地变量各持有一份；额外引用说明材质/消费者仍在使用。
			if texture==null or texture.get_reference_count()!=2: continue
			if _auxiliary.get(row.token.get_instance_id(),-1)!=int(expected.charge): continue
			bank.erase(donor)
			_cache_access.erase(donor)
			_audit_texture(donor,"recycled")
			row.erase("retire_frame");row.erase("unused_frame")
			return row
	return {}


func _take_recycled_texture(path: String) -> ImageTexture:
	# 已经独立预约的新图也可接管闲置对象，此时归还旧额度，保留新预约。
	var row := _take_recycled_slot(path)
	if row.is_empty(): return null
	var texture := row.texture as ImageTexture
	row.erase("texture")
	release_auxiliary(row.token.get_instance_id())
	return texture


func _release_retired_textures() -> void:
	for path: String in _texture_retiring.keys():
		var row: Dictionary=_texture_retiring[path]
		if Engine.get_process_frames()<int(row.retire_frame): continue
		_audit_texture(path,"retired")
		row.erase("texture")
		release_auxiliary(row.token.get_instance_id())
		_texture_retiring.erase(path)
		_cache_access.erase(path)


func _release_texture_reservations(force: bool = false) -> void:
	for path: String in _texture_reservations.keys():
		if not force and reuse_textures and not _closed and path in _texture_wanted: continue
		var slot: Dictionary = _texture_reservations[path]
		slot.erase("texture")
		release_auxiliary(slot.token.get_instance_id())
		_texture_reservations.erase(path)


func _reserve_recycled_slots() -> void:
	# 旧GPU到期时即交给已明确的后继请求；共享I/O槽繁忙不能把这次交接丢掉。
	# 未启动的请求继承原完整预约，已启动请求则保留自己的预约并归还旧费用。
	if not reuse_textures or _closed: return
	for path: String in _texture_wanted:
		if _textures.has(path) or _texture_reservations.has(path) or _texture_errors.has(path) or not _texture_descriptors.has(path): continue
		var job: Dictionary = _texture_jobs.get(path,_decoded_images.get(path,{}))
		if job.has("texture"): continue
		var slot := _take_recycled_slot(path)
		if slot.is_empty(): continue
		if not job.is_empty():
			job["texture"]=slot.texture
			slot.erase("texture")
			release_auxiliary(slot.token.get_instance_id())
		else:
			_texture_reservations[path]=slot
		_audit_texture(path,"slot_reserved")


static func ordered_texture_jobs(jobs: Dictionary, wanted: PackedStringArray) -> PackedStringArray:
	# wanted由实际切面开始；旧预测任务不能凭启动更早抢占GPU上传额度。
	var result := PackedStringArray()
	for path: String in wanted:
		if jobs.has(path) and path not in result: result.append(path)
	for path: String in jobs:
		if path not in result: result.append(path)
	return result


func ready_visible_mesh() -> bool:
	if not visible_finalize_first or _closed or _main_thread_meshes: return false
	for path: String in visible_meshes:
		if not _pending.has(path) or super._load_status(path)!=ResourceLoader.THREAD_LOAD_LOADED: continue
		if not _descriptors[path].has("sha256") or _mesh_hashes.has(path): return true
		if _mesh_checks.has(path) and not _mesh_checks[path].is_alive(): return true
	return false


func visible_dispatch_ready() -> bool:
	if not visible_dispatch_yield or _closed or _main_thread_meshes: return false
	if _busy.size()>=_request_limit-image_slot_reserve(): return false
	# 按真实队列首个未发起项判断；不能越过一个预算不足的前项假称后项可启动。
	for path: String in _wanted:
		if _cache.has(path) or _pending.has(path) or _failures.has(path): continue
		if path not in visible_meshes or _busy.has(path): return false
		var amount := int(_descriptors.get(path,{}).get("bytes",BUDGET+1))
		return amount>=0 and amount<=BUDGET and _bytes+_reserved+amount<=geometry_budget()
	return false


## 当前可见切面网格不参与物理步帧负载均衡延后（visible_meshes 由 overlay 在开启时填充）。
func _light_defer_exempt(path: String) -> bool:
	return path in visible_meshes


static func defer_speculative_upload(needed: bool, visible: bool, mesh_ready: bool) -> bool:
	return needed and not visible and mesh_ready


func _release_decoded(path: String) -> void:
	var row: Dictionary = _decoded_images[path]
	row.result.clear()
	release_auxiliary(row.token.get_instance_id())
	_decoded_images.erase(path)
	_audit_texture(path,"decoded_release")


func _decoded_capacity(path: String) -> bool:
	if not retain_decoded or _closed or _decoded_images.has(path): return false
	var charge := int(_texture_descriptors[path].charge)
	if charge>DECODED_LIMIT or _decoded_images.size()>=DECODED_COUNT: return false
	var total := charge
	for other: String in _decoded_images: total+=int(_texture_descriptors[other].charge)
	return total<=DECODED_LIMIT


func _keep_decoded(path: String, result: Dictionary, token: RefCounted) -> bool:
	if result.has("error") or not result.has("image") or not _decoded_capacity(path): return false
	_decoded_images[path]={"result":result,"token":token,"expires":Time.get_ticks_msec()+DECODED_TTL_MS}
	_audit_texture(path,"decoded_keep")
	return true


func _detach_speculative(path: String) -> void:
	if not detach_decoded or not _texture_jobs.has(path) or not _decoded_capacity(path): return
	var job: Dictionary = _texture_jobs[path]
	if job.worker.is_alive(): return
	var result: Dictionary = job.worker.wait_to_finish()
	_texture_jobs.erase(path)
	_busy.erase(path)
	job.erase("texture") # 借用旧 GPU 不进入解码缓存，先释放再决定是否归还预约。
	if _keep_decoded(path,result,job.token):
		decoded_detaches+=1
		_audit_texture(path,"decoded_detach")
	else:
		_texture_errors[path]=result.get("error","invalid decoded payload")
		result.clear()
		release_auxiliary(job.token.get_instance_id())


func _step_textures() -> void:
	_release_texture_reservations()
	for path: String in _decoded_images.keys():
		if _closed or not retain_decoded or (Time.get_ticks_msec()>=int(_decoded_images[path].expires) and path not in _texture_wanted and path not in _texture_pins):
			_release_decoded(path)
	for path: String in _texture_retiring.keys():
		var row: Dictionary = _texture_retiring[path]
		if not _closed and (path in _texture_wanted or path in _texture_pins):
			row.erase("retire_frame")
			row.erase("unused_frame")
			_textures[path]=row
			_texture_retiring.erase(path)
		elif Engine.get_process_frames()>=int(row.retire_frame) and (not reuse_textures or _closed):
			_audit_texture(path,"retired")
			row.erase("texture")
			release_auxiliary(row.token.get_instance_id())
			_texture_retiring.erase(path)
			_cache_access.erase(path)
	_reserve_recycled_slots()
	var frame_uploads := 0
	var frame_upload_usec := 0
	var frame_upload_bytes := 0
	# 只暂停投机图片的GPU上传；当前图片与关闭回收照常，不叠加领取预算。
	var mesh_ready := ready_visible_mesh()
	var dispatch_ready := visible_dispatch_ready()
	var ready_jobs := _texture_jobs.duplicate()
	for path: String in _decoded_images:
		if path in _texture_wanted or path in _texture_pins: ready_jobs[path]=_decoded_images[path]
	for path: String in ordered_texture_jobs(ready_jobs,_texture_wanted):
		var job: Dictionary = ready_jobs[path]
		var from_decoded := _decoded_images.has(path)
		var worker: Thread = job.get("worker") as Thread
		if not from_decoded and worker.is_alive(): continue
		var needed := not _closed and (path in _texture_wanted or path in _texture_pins)
		if defer_speculative_upload(needed,path in visible_images,mesh_ready or dispatch_ready):
			speculative_upload_deferrals+=1
			if dispatch_ready and not mesh_ready: visible_dispatch_deferrals+=1
			if not from_decoded: _detach_speculative(path)
			continue
		# 负载均衡只延后非当前可见纹理；可见切面纹理照常按原单帧上传预算推进。
		if needed and ((path not in visible_images and defer_to_light_frame()) or not can_upload_texture(frame_uploads,frame_upload_usec,frame_upload_bytes,int(_texture_descriptors[path].mip_bytes))): continue
		var result: Dictionary
		if from_decoded:
			result=job.result
			_decoded_images.erase(path)
			decoded_reuses+=1
			_audit_texture(path,"decoded_reuse")
		else:
			result=worker.wait_to_finish()
		_busy.erase(path)
		_texture_jobs.erase(path)
		if not needed or result.has("error"):
			job.erase("texture") # ready_jobs 也持有此字典，不能让旧 GPU 留到预约释放之后。
		if not needed:
			if not _keep_decoded(path,result,job.token):
				result.clear()
				release_auxiliary(job.token.get_instance_id())
		elif result.has("error"):
			_texture_errors[path]=result.error
			release_auxiliary(job.token.get_instance_id())
		else:
			var started_at := Time.get_ticks_usec()
			_texture_upload_frame = Engine.get_process_frames()
			var uploaded := job.get("texture") as ImageTexture
			if uploaded==null: uploaded=_take_recycled_texture(path)
			var recycled := uploaded!=null
			if recycled: uploaded.update(result.image)
			else: uploaded=ImageTexture.create_from_image(result.image)
			var upload_elapsed := Time.get_ticks_usec()-started_at
			if recycled:
				texture_reuses+=1
				texture_reuse_usec+=upload_elapsed
				max_texture_reuse_usec=maxi(max_texture_reuse_usec,upload_elapsed)
			frame_uploads+=1
			frame_upload_usec+=upload_elapsed
			frame_upload_bytes+=int(_texture_descriptors[path].mip_bytes)
			max_texture_uploads_per_frame=maxi(max_texture_uploads_per_frame,frame_uploads)
			if PerfBuckets.frame_trace_enabled:
				PerfBuckets.tick("tokyo_map_stream.texture_upload",upload_elapsed)
				PerfBuckets.mark_frame_event("tokyo_texture_upload")
			texture_upload_usec+=upload_elapsed
			max_texture_upload_usec=maxi(max_texture_upload_usec,upload_elapsed)
			if uploaded==null:
				_texture_errors[path]="GPU texture creation failed"
				release_auxiliary(job.token.get_instance_id())
			else:
				_textures[path]={"texture":uploaded,"token":job.token}
				texture_completed+=1
				_audit_texture(path,"upload",upload_elapsed)
		# 仅首张不超过1MiB且耗时不足1ms时再传一张小图；最多两张，大图仍单份。
	if _closed:
		if reuse_textures: _release_retired_textures()
		return
	for path in _texture_wanted:
		if _textures.has(path) or _texture_jobs.has(path) or _decoded_images.has(path) or _texture_errors.has(path): continue
		if not can_start_image(path):
			speculative_image_deferrals+=1
			continue
		if not _texture_descriptors.has(path):
			_texture_errors[path]="missing texture descriptor"
			continue
		if _busy.size()>=_request_limit or _texture_jobs.size()>=MAX_IMAGE_WORKERS or _busy.has(path): break
		var charge := int(_texture_descriptors[path].charge)
		var slot: Dictionary=_texture_reservations.get(path,{})
		_texture_reservations.erase(path)
		if reuse_textures and slot.is_empty(): slot=_take_recycled_slot(path,_bytes+_reserved+charge>geometry_budget())
		var token: RefCounted
		if not slot.is_empty():
			token=slot.token
			texture_slot_handoffs+=1
		else:
			# 没有可接管项仍照常归还到期额度，不为缓存延长退役期。
			if reuse_textures: _release_retired_textures()
			token=RefCounted.new()
			if not reserve_auxiliary(token.get_instance_id(),charge): break
		var worker := Thread.new()
		var error := worker.start(load_image.bind(path,_texture_descriptors[path].duplicate(true)))
		if error!=OK:
			slot.erase("texture")
			release_auxiliary(token.get_instance_id())
			_texture_errors[path]="image worker rejected: %d" % error
			continue
		_texture_jobs[path]={"worker":worker,"token":token}
		if not slot.is_empty(): _texture_jobs[path]["texture"]=slot.texture
		_busy[path]=get_instance_id()
		texture_started+=1
		_audit_texture(path,"request")
		# 在原共享八槽和预留预算内使用最多四条图片I/O；GPU另守小图有界上传预算。
	if reuse_textures: _release_retired_textures()


func collect_ready_meshes() -> void:
	# 只收后台已完成项；不发新请求、不上传纹理，上传帧也不叠加末次领取。
	if _closed or _main_thread_meshes or _texture_upload_frame == Engine.get_process_frames(): return
	_collect_completed()


static func should_defer_mesh_finalize(closing: bool, previous: int, completed: int, uploaded_usec: int) -> bool:
	return not closing and completed>previous and uploaded_usec>=1000


func image_slot_reserve() -> int:
	# 原共享槽内为尚未发起的当前图片留位；图片四线程上限和至少一个网格槽均不变。
	# 不能等所有网格入队后再装地表，也不能让本轮刚完成的网格立即抢回全部名额。
	if balanced_io and input_waiting and not _closed and _request_limit>1:
		var missing := 0
		for path: String in visible_images:
			if _texture_descriptors.has(path) and not _textures.has(path) and not _texture_jobs.has(path) \
				and not _decoded_images.has(path) and not _texture_errors.has(path): missing+=1
		return mini(mini(missing,maxi(0,MAX_IMAGE_WORKERS-_texture_jobs.size())),_request_limit-1)
	# 已完成网格领取后不能立即抢回全部共享槽，至少让一张当前地表获得启动机会。
	if not fair_image_slot or _closed or _request_limit<=1 or not _texture_jobs.is_empty(): return 0
	for path: String in visible_images:
		if _texture_descriptors.has(path) and not _textures.has(path) and not _texture_errors.has(path): return 1
	return 0


func _process_stream() -> void:
	var owner_node: Variant = _owner_ref.get_ref() if _owner_ref!=null else null
	if typeof(owner_node)!=TYPE_OBJECT or not is_instance_valid(owner_node): close()
	var completed_before := texture_completed
	var uploaded_before := texture_upload_usec
	var textures_started := Time.get_ticks_usec() if PerfBuckets.frame_trace_enabled else 0
	_step_textures()
	if PerfBuckets.frame_trace_enabled: PerfBuckets.tick("tokyo_map_stream.textures",Time.get_ticks_usec()-textures_started)
	# 重上传帧不叠加原生网格领取/摘要验证；保留原预算/请求，下一帧继续，关闭时不延迟清理。
	if should_defer_mesh_finalize(_closed,completed_before,texture_completed,texture_upload_usec-uploaded_before):
		mesh_finalize_deferred_frames+=1
		# 显式对照：只保留一次网格领取/发起机会，其余延后，避免连续纹理帧完全饿死网格。
		if minimum_mesh_progress:
			minimum_mesh_progress_frames+=1
			var previous_width := _pipeline_width
			var previous_limit := _request_limit
			_pipeline_width=1
			_request_limit-=image_slot_reserve()
			super._process_stream()
			_pipeline_width=previous_width
			_request_limit=previous_limit
		set_process(true)
		return
	var original_request_limit := _request_limit
	_request_limit-=image_slot_reserve()
	super._process_stream()
	_request_limit=original_request_limit
	if is_queued_for_deletion(): return
	var waiting := not _texture_jobs.is_empty() or not _texture_retiring.is_empty() or not _decoded_images.is_empty()
	if not _closed:
		for path in _texture_wanted:
			if not _textures.has(path) and not _texture_errors.has(path): waiting=true
	if waiting: set_process(true)


func close() -> void:
	_release_texture_reservations(true)
	for path: String in _decoded_images.keys(): _release_decoded(path)
	if not _closed:
		_residency_ledger.clear();_ledger_meshes.clear();_ledger_images.clear()
		_cache_access.clear()
		_recent_mesh_until.clear()
		residency_meshes.clear();residency_images.clear()
		residency_bytes=0
		_retain_unused=false
		request_textures(PackedStringArray(),PackedStringArray())
	super.close()


func summary() -> Dictionary:
	var result := super.summary()
	result["decoded_cached"]=_decoded_images.size()
	result["decoded_reuses"]=decoded_reuses
	result["decoded_detaches"]=decoded_detaches
	result["detach_decoded"]=detach_decoded
	if _audit_paths: result["texture_audit"]=_texture_audit.duplicate(true)
	result["residency_bytes"]=residency_bytes
	result["pool_limit"]=residency_limit
	result["cache_lru"]=cache_lru
	result["small_auxiliary_reclaims"]=small_auxiliary_reclaims
	result["residency_ready"]=residency_ready()
	result["pipeline_width"]=_pipeline_width
	result["request_limit"]=_request_limit
	result["mesh_checks_pending"]=_mesh_checks.size()
	result["async_mesh_dispatch"]=async_mesh_dispatch
	result["mesh_dispatches_started"]=mesh_dispatches_started
	result["mesh_dispatches_completed"]=mesh_dispatches_completed
	result["mesh_dispatches_pending"]=_mesh_dispatches.size()
	result["minimum_mesh_progress"]=minimum_mesh_progress
	result["minimum_mesh_progress_frames"]=minimum_mesh_progress_frames
	result["visible_io_first"]=visible_io_first
	result["visible_finalize_first"]=visible_finalize_first
	result["speculative_upload_deferrals"]=speculative_upload_deferrals
	result["formal_verify_reuses"]=formal_verify_reuses
	result["visible_dispatch_yield"]=visible_dispatch_yield
	result["visible_dispatch_deferrals"]=visible_dispatch_deferrals
	result["speculative_image_deferrals"]=speculative_image_deferrals
	result["mesh_checks_started"]=mesh_checks_started
	result["mesh_checks_completed"]=mesh_checks_completed
	result["texture_pending"]=_texture_jobs.size()
	result["texture_cached"]=_textures.size()
	result["texture_retiring"]=_texture_retiring.size()
	result["texture_reservations"]=_texture_reservations.size()
	result["texture_failures"]=_texture_errors.duplicate()
	result["texture_started"]=texture_started
	result["texture_completed"]=texture_completed
	result["reuse_textures"]=reuse_textures
	result["balanced_io"]=balanced_io
	result["input_waiting"]=input_waiting
	result["texture_reuses"]=texture_reuses
	result["texture_slot_handoffs"]=texture_slot_handoffs
	result["texture_reuse_usec"]=texture_reuse_usec
	result["max_texture_reuse_usec"]=max_texture_reuse_usec
	result["max_texture_upload_usec"]=max_texture_upload_usec
	result["max_texture_uploads_per_frame"]=max_texture_uploads_per_frame
	result["texture_upload_usec"]=texture_upload_usec
	result["mesh_digest_usec"]=mesh_digest_usec
	result["mesh_finalize_deferred_frames"]=mesh_finalize_deferred_frames
	return result
