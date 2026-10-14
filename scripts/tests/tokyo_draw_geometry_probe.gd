extends RefCounted
## 显式bench只读诊断：绘制边界节点状态，不能冒称GPU实际可见三角或更改原预算门。
var _owner: WeakRef
var _closed := true
var _samples := 0
var _skipped := 0
var _peak := 0
var _legacy_peak := 0
var _records: Array[Dictionary] = []
var _peak_record: Dictionary = {}
var _reported_peak := 0
var _underreported := 0
var _metric_samples := 0
var _pending_faces := -1
var _pending_runtime := false
var _runtime_peak := 0
var _reference_peak := 0
var _runtime_samples := 0
var _reference_samples := 0
var _runtime_underreported := 0
var _runtime_peak_record: Dictionary = {}


func setup(owner: Variant) -> bool:
	if not _closed or typeof(owner)!=TYPE_OBJECT or not is_instance_valid(owner) or not owner is Node:
		return false
	_owner = weakref(owner)
	_closed = false
	RenderingServer.frame_pre_draw.connect(capture)
	RenderingServer.frame_post_draw.connect(_verify_report)
	return true


func capture() -> void:
	_pending_faces=-1
	if _closed:
		return
	var owner: Variant = _owner.get_ref() if _owner!=null else null
	if typeof(owner)!=TYPE_OBJECT or not is_instance_valid(owner):
		close()
		return
	if not owner._active or not is_instance_valid(owner._viewport) or not owner._screen.is_visible_in_tree() \
			or owner._viewport.render_target_update_mode==SubViewport.UPDATE_DISABLED:
		_skipped += 1
		return
	var layers := PackedInt64Array([0,0,0])
	for batch: Dictionary in owner._batches.values():
		for kind in 3:
			if batch.nodes[kind].is_visible_in_tree():
				if kind == 0 and batch.has("low_wall_node"):
					layers[kind] += preload("res://scripts/experiments/tokyo_indexed_mesh.gd").triangles(batch.nodes[kind].mesh)
					layers[kind] += preload("res://scripts/rendering/tokyo_low_wall_binding.gd").faces(batch)
				elif batch.has("layer_triangles"):
					layers[kind] += int(batch.layer_triangles[kind])
				elif batch.nodes[kind].mesh!=null:
					# 旧cells没有分层缓存，直接查询实际ArrayMesh的索引数，不伪造新版字段。
					layers[kind] += preload("res://scripts/experiments/tokyo_indexed_mesh.gd").triangles(batch.nodes[kind].mesh)
	# 辅助层保守计数，即使个别网格已隐藏仍不扣减，避免低报。
	var auxiliary := 0
	var atlas: Variant = owner.get("_fixed_atlas")
	if typeof(atlas)==TYPE_OBJECT and is_instance_valid(atlas):
		for member: RefCounted in atlas.members():
			if is_instance_valid(member._node) and member._node.is_visible_in_tree():
				auxiliary+=2
	var ground: Variant = owner.get("_tile_ground")
	if typeof(ground)==TYPE_OBJECT and is_instance_valid(ground):
		auxiliary += int(ground.stats.get("extra_faces",0))
	var shore: Variant = owner.get("_shoreline")
	if typeof(shore)==TYPE_OBJECT and is_instance_valid(shore):
		auxiliary += int(shore.stats.get("faces",0))
	var faces := int(layers[0]+layers[1]+layers[2])+auxiliary
	var legacy := int(owner.peak_triangles)
	var runtime: bool = owner.is_processing()
	_pending_runtime=runtime
	_runtime_samples+=int(runtime)
	_reference_samples+=int(not runtime)
	if runtime and faces>_runtime_peak:
		_runtime_peak=faces
		var cells := {}
		for id: Variant in owner._batches:
			var batch: Dictionary = owner._batches[id]
			var counts := PackedInt64Array([0,0,0])
			for kind in 3:
				if batch.nodes[kind].is_visible_in_tree():
					if kind == 0 and batch.has("low_wall_node"):
						counts[kind] = preload("res://scripts/experiments/tokyo_indexed_mesh.gd").triangles(batch.nodes[kind].mesh)
						counts[kind] += preload("res://scripts/rendering/tokyo_low_wall_binding.gd").faces(batch)
					elif batch.has("layer_triangles"):
						counts[kind]=int(batch.layer_triangles[kind])
					elif batch.nodes[kind].mesh!=null:
						counts[kind]=preload("res://scripts/experiments/tokyo_indexed_mesh.gd").triangles(batch.nodes[kind].mesh)
			cells[str(id)]={"path":batch.path,"layers":counts}
		_runtime_peak_record={"frame":Engine.get_process_frames(),"faces":faces,"layers":layers,
			"auxiliary":auxiliary,"output_scale":float(owner._viewport.size.y)/owner._camera.size,"cells":cells}
	elif not runtime:
		_reference_peak=maxi(_reference_peak,faces)
	if owner.has_method("_record_submission_peak"):
		_pending_faces=faces
	_samples += 1
	if faces>_peak or legacy>_legacy_peak:
		var row := {"frame":Engine.get_process_frames(),"layers":layers,"auxiliary":auxiliary,"faces":faces,
			"legacy_peak":legacy,"legacy_peak_frame":int(owner._peak_snapshot.get("frame",-1)),
			"output_scale":float(owner._viewport.size.y)/owner._camera.size}
		if faces>_peak:
			_peak_record=row.duplicate(true)
		if legacy>_legacy_peak and _records.size()<32:
			_records.append(row)
	_peak=maxi(_peak,faces)
	_legacy_peak=maxi(_legacy_peak,legacy)


func close() -> void:
	if RenderingServer.frame_pre_draw.is_connected(capture):
		RenderingServer.frame_pre_draw.disconnect(capture)
	if RenderingServer.frame_post_draw.is_connected(_verify_report):
		RenderingServer.frame_post_draw.disconnect(_verify_report)
	_owner=null
	_closed=true
	_pending_faces=-1


func _verify_report() -> void:
	# 生产one-shot可能后于本探针注册；保留pre_draw独立计数，在post_draw核对已完成的计数。
	if _closed or _pending_faces<0:
		return
	var owner: Variant = _owner.get_ref() if _owner!=null else null
	if typeof(owner)!=TYPE_OBJECT or not is_instance_valid(owner):
		close()
		return
	_reported_peak=maxi(_reported_peak,int(owner._tile_peak_faces))
	_underreported+=int(_pending_faces>int(owner._tile_peak_faces))
	_runtime_underreported+=int(_pending_runtime and _pending_faces>int(owner._tile_peak_faces))
	_metric_samples+=1
	_pending_faces=-1


func summary() -> Dictionary:
	return {"diagnostic_only":true,"gpu_primitive_proof":false,"samples":_samples,"skipped":_skipped,
		"runtime_samples":_runtime_samples,"reference_samples":_reference_samples,"runtime_peak":_runtime_peak,
		"reference_peak":_reference_peak,"runtime_peak_record":_runtime_peak_record,"runtime_underreported":_runtime_underreported,
		"reported_peak":_reported_peak,"underreported_frames":_underreported,"metric_samples":_metric_samples,
		"boundary_peak":_peak,"legacy_peak":_legacy_peak,"peak_record":_peak_record,"legacy_peak_events":_records,"closed":_closed}
