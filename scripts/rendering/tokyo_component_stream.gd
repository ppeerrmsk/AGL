extends "res://scripts/rendering/tokyo_cell_stream.gd"
## 同一个Stream内部加载物理组件；原逻辑视图不持有额外几何副本。
const Page := preload("res://scripts/rendering/tokyo_canonical_spatial_page.gd")
const Assembly := preload("res://scripts/rendering/tokyo_component_page.gd")
var _logical: Dictionary = {}
var _views: Dictionary = {}
var _expanded_paths: Dictionary = {}
var _last_logical_wanted := PackedStringArray()
var _last_logical_pins := PackedStringArray()
var _last_physical_wanted := PackedStringArray()
var _last_physical_pins := PackedStringArray()
var _fixed_snapshot := PackedStringArray()
var _fixed_logical: Dictionary = {}
var _fixed_physical: Dictionary = {}
var _fixed_physical_paths: Array = []
const GRID_SUBSET_LIMIT := 128
var _grid_subsets: Dictionary={}
var _grid_subset_kept: Dictionary={}


func configure(owner_node: Node, descriptors: Dictionary) -> void:
	_logical = descriptors.duplicate()
	_grid_subsets.clear();_grid_subset_kept.clear()
	_expanded_paths.clear()
	_last_logical_wanted.clear();_last_logical_pins.clear()
	_last_physical_wanted.clear();_last_physical_pins.clear()
	_fixed_snapshot.clear();_fixed_logical.clear();_fixed_physical.clear()
	_fixed_physical_paths.clear()
	var physical: Dictionary = {}
	for path: String in descriptors:
		var parts: Dictionary = descriptors[path].get("components", {path: descriptors[path]})
		_expanded_paths[path]=PackedStringArray(parts.keys())
		for key: String in parts:
			assert(not physical.has(key) or physical[key] == parts[key], "component path identity conflict")
			physical[key] = parts[key]
	super.configure(owner_node, physical)


func request(wanted: PackedStringArray, pins: PackedStringArray) -> void:
	if _closed:
		return
	var trace := PerfBuckets.frame_trace_enabled
	var phase_started := Time.get_ticks_usec() if trace else 0
	var retained: Dictionary={}
	for path: String in wanted: retained[path]=true
	for path: String in pins: retained[path]=true
	_grid_subset_kept=retained
	for path: String in _views.keys():
		if not retained.has(path):
			_views.erase(path)
	if trace: PerfBuckets.tick("tokyo_map_dispatch_views",Time.get_ticks_usec()-phase_started)
	phase_started=Time.get_ticks_usec() if trace else 0
	# 固定保护集通常不变：仅复用路径字符串，不新增Resource持有者或另设预算池。
	# 值快照必须复制，否则调用方原地改Packed数组会让缓存错误命中。
	if wanted!=_last_logical_wanted:
		_last_physical_wanted=_paths(wanted)
		_last_logical_wanted=wanted.duplicate()
	if pins!=_last_logical_pins:
		_last_physical_pins=_paths(pins)
		_last_logical_pins=pins.duplicate()
	if trace: PerfBuckets.tick("tokyo_map_dispatch_paths",Time.get_ticks_usec()-phase_started)
	phase_started=Time.get_ticks_usec() if trace else 0
	super.request(_last_physical_wanted, _last_physical_pins)
	if trace: PerfBuckets.tick("tokyo_map_dispatch_queue",Time.get_ticks_usec()-phase_started)


func request_partitioned(front: PackedStringArray, fixed: PackedStringArray, tail: PackedStringArray, pins: PackedStringArray) -> void:
	if _closed: return
	var trace := PerfBuckets.frame_trace_enabled
	var phase_started := Time.get_ticks_usec() if trace else 0
	if fixed!=_fixed_snapshot:
		_fixed_logical=_path_set(fixed)
		_fixed_physical=_path_set(_paths(fixed))
		_fixed_physical_paths=_fixed_physical.keys()
		_fixed_snapshot=fixed.duplicate()
	# Dictionary保持插入顺序；不覆盖已有键，等价于逐路径首次出现去重。
	# 固定组只做原生merge，不在脚本中重新逐组件展开；前景仍排在固定组之前。
	var wanted_logical := _path_set(front)
	wanted_logical.merge(_fixed_logical,false)
	wanted_logical.merge(_path_set(tail),false)
	var retained := wanted_logical.duplicate()
	retained.merge(_path_set(pins),false)
	_grid_subset_kept=retained
	var wanted_physical := _path_set(_paths(front))
	# 全部固定组件已校验入池后，只需保留pins，不必再加入每帧扫描的加载队列。
	# 每次用真实cache核验；任何组件缺失都会恢复完整固定组请求，不依赖过期ready标记。
	if not _cache.has_all(_fixed_physical_paths): wanted_physical.merge(_fixed_physical,false)
	wanted_physical.merge(_path_set(_paths(tail)),false)
	var pinned_physical := _fixed_physical.duplicate()
	pinned_physical.merge(_path_set(_paths(pins)),false)
	var wanted_paths := PackedStringArray(wanted_physical.keys())
	var pinned_paths := PackedStringArray(pinned_physical.keys())
	if trace: PerfBuckets.tick("tokyo_map_dispatch_paths",Time.get_ticks_usec()-phase_started)
	phase_started=Time.get_ticks_usec() if trace else 0
	for path: String in _views.keys():
		if not retained.has(path): _views.erase(path)
	if trace: PerfBuckets.tick("tokyo_map_dispatch_views",Time.get_ticks_usec()-phase_started)
	phase_started=Time.get_ticks_usec() if trace else 0
	super.request(wanted_paths,pinned_paths)
	if trace: PerfBuckets.tick("tokyo_map_dispatch_queue",Time.get_ticks_usec()-phase_started)


func register_grid_subset(path: String, row: Dictionary) -> bool:
	# 新逻辑身份只能引用已认证物理目录，不能新增/覆写物理资源或改旧key含义。
	if _closed or not path.begins_with("grid-subset/"): return false
	if _logical.has(path): return _grid_subsets.has(path) and _logical[path]==row
	if _grid_subsets.size()>=GRID_SUBSET_LIMIT: return false
	var identity: Variant=row.get("canonical_identity")
	if not identity is Dictionary or identity.get("format")!="tokyo_grid_view" or identity.get("schema")!=3: return false
	if path!="grid-subset/"+JSON.stringify(identity).sha256_text(): return false
	if not row.get("views") is Array or row.views.size()!=2 or not row.get("components") is Dictionary: return false
	if not identity.get("layers") is Array or identity.layers.size()!=2: return false
	var parts: Dictionary={}
	var total := 0
	for kind in 2:
		if not row.views[kind] is Array: return false
		var identities: Array=[]
		for child: Variant in row.views[kind]:
			if not child is Dictionary or not child.get("canonical_identity") is Dictionary: return false
			var child_identity: Dictionary=child.canonical_identity
			if child_identity.get("schema")!=1 or child_identity.get("layer")!=kind: return false
			if child_identity.get("source")!=identity.get("source") or child_identity.get("configuration")!=identity.get("configuration"): return false
			if not child.get("components") is Dictionary or child.components.size()!=1: return false
			var physical: String=child.components.keys()[0]
			if parts.has(physical) or not _descriptors.has(physical) or _descriptors[physical]!=child.components[physical]: return false
			if child.get("bytes")!=_descriptors[physical].get("bytes"): return false
			parts[physical]=child.components[physical]
			identities.append(child_identity);total+=int(child.bytes)
		if identities!=identity.layers[kind]: return false
	if parts.is_empty() or parts!=row.components or total!=row.get("bytes"): return false
	_logical[path]=row.duplicate(true)
	_expanded_paths[path]=PackedStringArray(parts.keys())
	_grid_subsets[path]=true
	return true


func retire_grid_subsets(protected: PackedStringArray) -> PackedStringArray:
	# 未完成请求与pins也受保护；仅回收逻辑元数据，不触碰物理缓存/在途任务。
	var removed := PackedStringArray()
	var keep := _path_set(protected)
	keep.merge(_grid_subset_kept,false)
	for path: String in _grid_subsets.keys():
		if keep.has(path): continue
		_views.erase(path);_logical.erase(path);_expanded_paths.erase(path);_grid_subsets.erase(path)
		removed.append(path)
	return removed


static func _path_set(paths: PackedStringArray) -> Dictionary:
	var result: Dictionary={}
	for path: String in paths: result[path]=true
	return result


func _paths(logical: PackedStringArray) -> PackedStringArray:
	var result := PackedStringArray()
	var seen: Dictionary = {}
	for path: String in logical:
		# configure后的来源目录只读；物理路径串表只展开一次，不保留额外Resource引用。
		var parts: PackedStringArray=_expanded_paths[path] if _expanded_paths.has(path) else PackedStringArray(_logical.get(path,{}).get("components",{path:{}}).keys())
		for key: String in parts:
			# 按首次出现顺序展开；常驻数百页时不能逐项扫描已展开数组。
			if not seen.has(key):
				seen[key] = true
				result.append(key)
	return result


func resource(path: String) -> Resource:
	if not _logical.get(path, {}).has("components"):
		return super.resource(path)
	if _views.has(path):
		return _views[path]
	var row: Dictionary = _logical[path]
	var loaded: Dictionary = {}
	for key: String in row.components:
		loaded[key] = super.resource(key)
		if loaded[key] == null:
			return null
	var page := Assembly.assemble(row, loaded)
	if page == null:
		return null
	_views[path] = page
	return page


func close() -> void:
	_views.clear()
	_grid_subsets.clear();_grid_subset_kept.clear()
	_expanded_paths.clear()
	_last_logical_wanted.clear();_last_logical_pins.clear()
	_last_physical_wanted.clear();_last_physical_pins.clear()
	_fixed_snapshot.clear();_fixed_logical.clear();_fixed_physical.clear()
	_fixed_physical_paths.clear()
	super.close()


func summary() -> Dictionary:
	var result := super.summary()
	result["component_stream"] = true
	result["logical_cached"] = _views.size()
	return result
