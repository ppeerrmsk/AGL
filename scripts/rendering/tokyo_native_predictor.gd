extends RefCounted
## 仅候选未来预取；旧结果绝不直接提交显示，不能替代主线程覆盖及资源交接门。
const Worker := preload("res://scripts/rendering/tokyo_cut_worker.gd")
const Native := preload("res://scripts/rendering/tokyo_hlod_native.gd")
const Cut := preload("res://scripts/experiments/tokyo_spatial_cut.gd")
const Handoff := preload("res://scripts/rendering/tokyo_hlod_handoff.gd")
var worker := Worker.new()
var limits: Dictionary={}
var latest: Dictionary={}
var submitted := 0
var applied := 0
var fallback := 0
var prepare_usec := 0
var rejections: Dictionary={}
var center_samples: Array[Dictionary]=[]
var _queued_queries: Array[Dictionary]=[]
var _queued_source := ""
var _last_request_usec := 0


static func smooth_pan(previous: Vector2, velocity: Vector2, delta: float) -> Vector2:
	return previous.lerp(velocity,1.0-exp(-maxf(delta,0.0)/0.10))


func prepare(native: RefCounted) -> bool:
	close()
	var started := Time.get_ticks_usec()
	var sources: Dictionary={}
	for configuration: String in native.catalog.configurations:
		if not configuration.ends_with("_full"): continue
		sources[configuration+"/raw"]=native._partition_roots.get(configuration,native.catalog.configurations[configuration])
		if native._ground_roots.has(configuration): sources[configuration+"/ground"]=native._ground_roots[configuration]
	limits=native.ground.get("limits",{}).duplicate(true)
	var valid := worker.configure_sources(sources,1)
	prepare_usec=Time.get_ticks_usec()-started
	return valid


func request(center: Vector2, scale_value: float, angle: float, size: Vector2, configuration: String, pan: Vector2, zoom_sign: int, display_budget: int, accept_full: Callable, zoom_rate: float = 0.0) -> Dictionary:
	var now := Time.get_ticks_usec()
	var interval := clampf(float(now-_last_request_usec)/1000000.0,0.016,0.10) if _last_request_usec>0 else 0.08
	_last_request_usec=now
	var hybrid: bool=limits.has(configuration) and scale_value<=float(limits[configuration])
	var source_key := configuration+("/ground" if hybrid else "/raw")
	if worker.ready(): latest=worker.take(1)
	if worker._task<0:
		# 求下一次预测查询，不是此刻已经能同步算出的过去视野；验收阈值不放宽。
		var job_scale := clampf(scale_value*exp(clampf(zoom_rate*interval,-0.7,0.7)),0.0973,5.0)
		var job_center := center+Handoff.pan_lead(pan,job_scale,interval,size)
		var job_hybrid: bool=limits.has(configuration) and job_scale<=float(limits[configuration])
		var lead := Handoff.pan_lead(pan,job_scale,0.35,size)
		var padding := (Transform2D(angle,Vector2.ZERO).basis_xform(lead)*job_scale).abs()+Vector2(384,384)
		var queries: Array[Dictionary]=[]
		for ratio: float in [1.0,0.5,0.25,0.0]:
			queries.append({"center":job_center+lead*0.5*ratio,"scale":job_scale,"angle":angle,"size":size+padding*ratio,
				"anchor":job_center,"base_size":size,"pan":pan,"zoom_sign":zoom_sign,"page_limit":Native.Contract.native_page_limit()})
		_queued_queries=queries
		_queued_source=configuration+("/ground" if job_hybrid else "/raw")
	var reason := rejection(latest,source_key,center,scale_value,angle,size,pan,zoom_sign,Time.get_ticks_usec())
	if not reason.is_empty():
		if reason=="center" and center_samples.size()<8 and OS.get_environment("AGL_TOKYO_WALL_TRACE")=="1":
			var previous: Dictionary=latest.queries[0]
			center_samples.append({"anchor":previous.anchor,"requested":center,"pan":pan,"previous_pan":previous.pan,"scale":scale_value,"age_usec":now-int(latest.submitted_usec),"interval":interval,"error_px":(center-Vector2(previous.anchor)).length()*scale_value})
		rejections[reason]=int(rejections.get(reason,0))+1
		fallback+=1
		return {}
	for budget in [48*1024*1024,display_budget]:
		var expanded := Native.decorate(Cut.pick(latest.solutions[0],budget),configuration,hybrid)
		if not expanded.within_budget and budget==48*1024*1024:
			var full := Native.decorate(Cut.pick(latest.solutions[0],display_budget),configuration,hybrid)
			if full.within_budget and bool(accept_full.call(full)): expanded=full
		if expanded.within_budget:
			expanded["spatial_guard_px"]=192
			applied+=1
			return expanded
		for index in [1,2,3]:
			var cut := Native.decorate(Cut.pick(latest.solutions[index],budget),configuration,hybrid)
			if cut.within_budget:
				cut["spatial_guard_px"]=[192.0,96.0,48.0,0.0][index]
				applied+=1
				return cut
	fallback+=1
	return {}


static func usable(response: Dictionary, source_key: String, center: Vector2, scale_value: float, angle: float, size: Vector2, pan: Vector2, zoom_sign: int, now: int) -> bool:
	return rejection(response,source_key,center,scale_value,angle,size,pan,zoom_sign,now).is_empty()


static func rejection(response: Dictionary, source_key: String, center: Vector2, scale_value: float, angle: float, size: Vector2, pan: Vector2, zoom_sign: int, now: int) -> String:
	if response.is_empty(): return "not_ready"
	if response.get("generation",-1)!=1 or response.get("source_key","")!=source_key: return "source"
	if response.get("solutions",[]).size()!=4 or response.get("queries",[]).size()!=4: return "shape"
	var age := now-int(response.submitted_usec)
	if age<0 or age>150000: return "age"
	var query: Dictionary=response.queries[0]
	if query.base_size!=size: return "size"
	if query.zoom_sign!=zoom_sign: return "zoom_direction"
	if query.pan.dot(pan)<0.0: return "pan_direction"
	if absf(wrapf(angle-float(query.angle),-PI,PI))>0.05: return "rotation"
	if absf(log(scale_value/float(query.scale)))>0.10: return "scale"
	if (center-Vector2(query.anchor)).length()*scale_value>48.0: return "center"
	return ""


func dispatch() -> void:
	# 调用方先完成本帧同步兜底，避免两边同时重复求树、争用分配器。
	if not _queued_queries.is_empty() and worker._task<0 and worker.submit(_queued_queries,_queued_source): submitted+=1
	_queued_queries=[]
	_queued_source=""


func close() -> void:
	worker.close()
	latest.clear()
	limits.clear()
	center_samples.clear()
	_queued_queries=[]
	_queued_source=""
	_last_request_usec=0
