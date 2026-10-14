extends RefCounted
## 片段还原诊断，Headless时间/采样内存不作实景验收。
static func digest(data: PackedByteArray) -> String:
	var h := HashingContext.new()
	h.start(HashingContext.HASH_SHA256)
	h.update(data)
	return h.finish().hex_encode()

static func load_bytes(binding: Dictionary) -> PackedByteArray:
	if FileAccess.get_sha256(binding.path)!=binding.sha256:return PackedByteArray()
	var data := FileAccess.get_file_as_bytes(binding.path).decompress(int(binding.decoded_bytes),FileAccess.COMPRESSION_GZIP)
	if data.size()!=int(binding.decoded_bytes):return PackedByteArray()
	return data

static func assemble(source: PackedByteArray, recipe: PackedByteArray, capacity: int) -> Dictionary:
	if recipe.size()%8!=0 or capacity<0 or capacity%4!=0:return {}
	var output := PackedByteArray()
	# 一次定长分配，避免append增长容量及slice临时副本；不把返回后采样当峰值。
	if output.resize(capacity)!=OK:return {}
	var cursor := 0
	var peak := OS.get_static_memory_usage()
	for i in range(0,recipe.size(),8):
		var begin := int(recipe.decode_u32(i))
		var count := int(recipe.decode_u32(i+4))
		if begin%12!=0 or count%12!=0 or count<=0 or begin+count>source.size() or cursor+count>capacity:return {}
		for j in range(0,count,4):output.encode_u32(cursor+j,source.decode_u32(begin+j))
		cursor+=count
		peak=maxi(peak,OS.get_static_memory_usage())
	peak=maxi(peak,OS.get_static_memory_usage())
	return {"bytes":output,"sampled_static_peak":peak}

static func run(input: Dictionary) -> int:
	if FileAccess.file_exists(input.output):return 1
	var binding: Dictionary=input.index_recipe_probe
	if FileAccess.get_sha256(binding.path)!=binding.sha256:return 1
	var contract: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(binding.path))
	if input.get("segmented_delta",false):return run_segmented(contract,input.output)
	if input.get("delta_indices",false):return run_delta(contract,input.output)
	var sources: Array[PackedByteArray]=[]
	var recipes: Array[PackedByteArray]=[]
	for item: Dictionary in contract.sources:
		var bytes := load_bytes(item)
		if bytes.is_empty():return 1
		sources.append(bytes)
	for item: Dictionary in contract.cases:
		var bytes := load_bytes(item.recipe)
		if bytes.is_empty():return 1
		recipes.append(bytes)
	var baseline := OS.get_static_memory_usage()
	var peak := baseline
	var rows: Array[Dictionary]=[]
	var current := PackedByteArray()
	for i in contract.cases.size():
		var item: Dictionary=contract.cases[i]
		var started := Time.get_ticks_usec()
		var next := assemble(sources[int(item.source)],recipes[i],int(item.capacity))
		var elapsed := Time.get_ticks_usec()-started
		if next.is_empty() or digest(next.bytes)!=item.padded_sha256:return 1
		peak=maxi(peak,int(next.sampled_static_peak))
		current=next.bytes
		rows.append({"case":i,"assembly_usec":elapsed,"bytes":current.size()})
	var bad := PackedByteArray()
	bad.resize(8)
	bad.encode_u32(0,sources[0].size()+12)
	bad.encode_u32(4,12)
	if not assemble(sources[0],bad,120).is_empty():return 1
	if not assemble(sources[0],PackedByteArray([1]),120).is_empty():return 1
	current.clear()
	sources.clear()
	recipes.clear()
	var file := FileAccess.open(input.output,FileAccess.WRITE)
	if file==null:return 1
	file.store_string(JSON.stringify({"cases":rows,"exact_cases":rows.size(),"invalid_cases":2,"baseline_static_bytes":baseline,"sampled_static_peak_bytes":peak,"sampled_delta_bytes":peak-baseline,"after_clear_static_bytes":OS.get_static_memory_usage(),"allocation_peak_certified":false,"visual_verified":false,"fps_verified":false},"\t"))
	file.close()
	return 0

static func decode_delta(data: PackedByteArray, count: int, vertices: int) -> PackedByteArray:
	# 有界诊断：分配前拒绝超限，单次定长输出；不进入帧热路径。
	if count<=0 or count>720000 or vertices<=0 or vertices>1048576:return PackedByteArray()
	if data.size()<count*2 or data.size()>count*6:return PackedByteArray()
	var output := PackedByteArray()
	if output.resize(count*4)!=OK:return PackedByteArray()
	var cursor := 0
	var previous := 0
	for i in count:
		if cursor+2>data.size():return PackedByteArray()
		var delta := data.decode_s16(cursor);cursor+=2
		if delta==-32768:
			if cursor+4>data.size():return PackedByteArray()
			previous=int(data.decode_u32(cursor));cursor+=4
		else:previous+=delta
		if previous<0 or previous>=vertices:return PackedByteArray()
		output.encode_u32(i*4,previous)
	if cursor!=data.size():return PackedByteArray()
	return output

static func run_segmented_frames(parent: Node, input: Dictionary) -> int:
	if FileAccess.file_exists(input.output):return 1
	var binding: Dictionary=input.index_recipe_probe
	if FileAccess.get_sha256(binding.path)!=binding.sha256:return 1
	var contract: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(binding.path))
	var worker := preload("res://scripts/tests/tokyo_delta_preparation.gd").new()
	var published := PackedByteArray([71,19,3,0])
	var steps := 0
	var commits := 0
	for row: Dictionary in contract.rows:
		if FileAccess.get_sha256(row.path)!=row.sha256:return 1
		var source := FileAccess.get_file_as_bytes(row.path)
		var previous_hash := digest(published)
		# 真实跨帧后取消，再跨帧检查旧发布值仍有效。
		if not worker.begin(source,int(row.indices),int(row.vertices)) or not worker.step(1):return 1
		await parent.get_tree().process_frame
		worker.cancel()
		await parent.get_tree().process_frame
		if worker.ready() or not worker.take().is_empty() or digest(published)!=previous_hash:return 1
		if not worker.begin(source,int(row.indices),int(row.vertices)):return 1
		while not worker.ready():
			if not worker.step():return 1
			steps+=1
			await parent.get_tree().process_frame
			if digest(published)!=previous_hash:return 1
			if not worker.ready() and not worker.take().is_empty():return 1
		var prepared := worker.take()
		if digest(prepared)!=row.decoded_sha256:return 1
		published=prepared;commits+=1
		await parent.get_tree().process_frame
		if digest(published)!=row.decoded_sha256 or worker.ready():return 1
	worker.cancel();published.clear()
	var file := FileAccess.open(input.output,FileAccess.WRITE)
	if file==null:return 1
	file.store_string(JSON.stringify({"streams":commits,"steps":steps,"cross_frame_cancellations":commits,"old_value_retained":true,"scope":"CPU publication only; no mesh or GPU handoff","fps_verified":false,"full_loading_budget_verified":false},"\t"))
	file.close()
	return 0

static func run_segmented(contract: Dictionary, output_path: String) -> int:
	var worker := preload("res://scripts/tests/tokyo_delta_preparation.gd").new()
	var maximum_usec := 0
	var steps := 0
	for row: Dictionary in contract.rows:
		if FileAccess.get_sha256(row.path)!=row.sha256:return 1
		var source := FileAccess.get_file_as_bytes(row.path)
		if not worker.begin(source,int(row.indices),int(row.vertices)):return 1
		if not worker.take().is_empty():return 1
		while not worker.ready():
			var started := Time.get_ticks_usec()
			if not worker.step():return 1
			maximum_usec=maxi(maximum_usec,Time.get_ticks_usec()-started);steps+=1
			if not worker.ready() and not worker.take().is_empty():return 1
		if digest(worker.take())!=row.decoded_sha256 or worker.ready():return 1
		if not worker.take().is_empty():return 1
	# 未完成取消、晚期非法值、截断逃逸、非法步长均不发布半成品。
	if not worker.begin(PackedByteArray([0,0,0,0]),2,1) or not worker.step(1):return 1
	worker.cancel()
	if worker.ready() or not worker.take().is_empty() or worker.step():return 1
	for bad: PackedByteArray in [PackedByteArray([0,0,1,0]),PackedByteArray([0,0,0,128])]:
		if not worker.begin(bad,2,1) or not worker.step(1):return 1
		if worker.step(1) or worker.ready() or not worker.take().is_empty():return 1
	if not worker.begin(PackedByteArray([0,0]),1,1) or worker.step(4097):return 1
	if not worker.take().is_empty():return 1
	var file := FileAccess.open(output_path,FileAccess.WRITE)
	if file==null:return 1
	file.store_string(JSON.stringify({"exact_streams":contract.rows.size(),"steps":steps,"maximum_step_usec":maximum_usec,"cancel_and_reject_cases":4,"partial_output_hidden":true,"real_frame_scheduling_verified":false,"allocation_peak_certified":false,"fps_verified":false},"\t"))
	file.close()
	return 0

static func run_delta(contract: Dictionary, output_path: String) -> int:
	var rows: Array[Dictionary]=[]
	for row: Dictionary in contract.rows:
		if FileAccess.get_sha256(row.path)!=row.sha256:return 1
		var source := FileAccess.get_file_as_bytes(row.path)
		if source.size()!=int(row.bytes):return 1
		var started := Time.get_ticks_usec()
		var restored := decode_delta(source,int(row.indices),int(row.vertices))
		var elapsed := Time.get_ticks_usec()-started
		if restored.is_empty() or digest(restored)!=row.decoded_sha256:return 1
		rows.append({"layer":row.layer,"state":row.state,"decode_usec":elapsed,"output_bytes":restored.size()})
	# 截断、逃逸截断、负/越界顶点、尾随数据、计数与容量上限。
	var invalid := [[PackedByteArray([0]),1,1],[PackedByteArray([0,128]),1,1],
		[PackedByteArray([255,255]),1,1],[PackedByteArray([1,0]),1,1],
		[PackedByteArray([0,0,0,0]),1,1],[PackedByteArray([0,0]),0,1],
		[PackedByteArray([0,0]),720001,1],[PackedByteArray([0,0]),1,1048577]]
	for test: Array in invalid:
		if not decode_delta(test[0],test[1],test[2]).is_empty():return 1
	var file := FileAccess.open(output_path,FileAccess.WRITE)
	if file==null:return 1
	file.store_string(JSON.stringify({"cases":rows,"exact_cases":rows.size(),"invalid_cases":invalid.size(),"allocation_bound_certified":false,"visual_verified":false,"fps_verified":false},"\t"))
	file.close()
	return 0
