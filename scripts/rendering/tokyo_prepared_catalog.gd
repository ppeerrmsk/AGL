extends RefCounted
## 仅在离线制作或Loading生成/验证。游戏帧只调用roots_at，不能从缺失缓存同步重建。
## 快照只保存336节点的选择元数据，不复制geometry、textures或原生组件大表。
const FORMAT := "tokyo_prepared_catalog"
const SCHEMA := 1
const ALGORITHM := 1
const ROOT_COUNT := 16
const NODE_COUNT := 336
const MAX_FILE_BYTES := 64*1024*1024
const MAGIC := "AGLTCAT1"
const HEADER_BYTES := 8+4+64
const DISQUALIFIED_BYTES := 192*1024*1024+1
const CACHE_ROOT := "user://tokyo_prepared_catalog/"
const NODE_FIELDS := ["key","path","texture_path","max_scale","triangles","boxes","bytes","coverage_box"]


static func build(catalog: Dictionary) -> Dictionary:
	var source := _source(catalog)
	if source.is_empty(): return {}
	var intervals: Array[Dictionary]=[]
	var lower := 0.0
	for upper: float in source.limits:
		var roots: Array[Dictionary]=[]
		for root: Dictionary in source.roots: roots.append(_qualified(root,upper))
		intervals.append({"lower":lower,"upper":upper,"roots":roots})
		lower=upper
	var artifact := {"format":FORMAT,"schema":SCHEMA,"algorithm":ALGORITHM,"identity":source.identity,
		"source_sha256":_digest(source),"min_scale":source.min_scale,"max_scale":source.max_scale,
		"node_count":NODE_COUNT,"intervals":intervals}
	artifact["payload_sha256"]=_payload_digest(artifact)
	return artifact


static func validate(artifact: Variant, catalog: Dictionary) -> bool:
	# 不能只信文件自报摘要；每个节点仍与已认证来源逐字段核对，工作上限固定。
	var source := _source(catalog)
	return not source.is_empty() and _validate_source(artifact,source)


static func roots_at(artifact: Dictionary, scale: float) -> Array[Dictionary]:
	# 调用方在Loading验证一次并保持只读；这里只查精确(lower,upper]，不解析、不求树。
	var empty: Array[Dictionary]=[]
	if not is_finite(scale) or scale<=0.0 or scale>float(artifact.get("max_scale",0.0)): return empty
	if artifact.get("format")!=FORMAT or artifact.get("schema")!=SCHEMA or artifact.get("algorithm")!=ALGORITHM \
		or not artifact.get("intervals") is Array: return empty
	var intervals: Array=artifact.intervals
	var low := 0
	var high := intervals.size()-1
	while low<=high:
		var middle := (low+high)/2
		var interval: Dictionary=intervals[middle]
		if scale>float(interval.upper): low=middle+1
		elif scale<=float(interval.lower): high=middle-1
		else:
			var roots: Array[Dictionary]=[]
			roots.assign(interval.roots)
			return roots
	return empty


static func cache_path(catalog: Dictionary) -> String:
	var source := _source(catalog)
	return "" if source.is_empty() else CACHE_ROOT+"v%d-a%d-%s.bin"%[SCHEMA,ALGORITHM,_digest(source)]


static func load_or_build(catalog: Dictionary, path: String = "", allow_build: bool = true) -> Dictionary:
	# 只能由Loading/离线入口调用。只读模式失效返回空，绝不暗中走同步制作。
	if path.is_empty(): path=cache_path(catalog)
	if path.is_empty(): return {}
	var artifact := read(path,catalog)
	if not artifact.is_empty() or not allow_build: return artifact
	artifact=build(catalog)
	if artifact.is_empty(): return {}
	# 磁盘缓存不可写不改变游戏内容；Loading内已完成的合格快照仍可使用。
	write(path,artifact,catalog)
	return artifact


static func read(path: String, catalog: Dictionary) -> Dictionary:
	if not _cache_location(path) or not FileAccess.file_exists(path): return {}
	var artifact: Variant=_read_payload(path)
	return artifact if validate(artifact,catalog) else {}


static func _read_payload(path: String) -> Variant:
	# 先核完整帧和字节摘要；普通截断/位损坏不能进入Variant解析器制造运行时错误。
	var file := FileAccess.open(path,FileAccess.READ)
	if file==null: return null
	if file.get_length()<=HEADER_BYTES or file.get_length()>MAX_FILE_BYTES:
		file.close()
		return null
	if file.get_buffer(8)!=MAGIC.to_utf8_buffer():
		file.close()
		return null
	var length := file.get_32()
	if length<=0 or length+HEADER_BYTES!=file.get_length():
		file.close()
		return null
	var expected := file.get_buffer(64).get_string_from_ascii()
	var bytes := file.get_buffer(length)
	file.close()
	if bytes.size()!=length or not _sha(expected) or _bytes_digest(bytes)!=expected: return null
	return bytes_to_var(bytes)


static func write(path: String, artifact: Dictionary, catalog: Dictionary) -> bool:
	if not _cache_location(path) or not validate(artifact,catalog): return false
	var bytes := var_to_bytes(artifact)
	if bytes.size()+HEADER_BYTES>MAX_FILE_BYTES: return false
	var absolute := ProjectSettings.globalize_path(path)
	if DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())!=OK: return false
	var temporary := absolute+".pending-%d-%d"%[OS.get_process_id(),Time.get_ticks_usec()]
	var file := FileAccess.open(temporary,FileAccess.WRITE)
	if file==null: return false
	file.store_buffer(MAGIC.to_utf8_buffer())
	file.store_32(bytes.size())
	file.store_buffer(_bytes_digest(bytes).to_ascii_buffer())
	file.store_buffer(bytes)
	var stored := file.get_error()==OK
	file.close()
	# 临时文件不经公开read的扩展名门；先回读完全等值，再原子替换旧缓存。
	var saved: Variant=_read_payload(temporary)
	stored=stored and saved==artifact
	if not stored or DirAccess.rename_absolute(temporary,absolute)!=OK:
		DirAccess.remove_absolute(temporary)
		return false
	return true


static func _cache_location(path: String) -> bool:
	# 不接受正式res资源作为可写缓存；显式离线输出允许绝对路径和隔离tmp目录。
	return path.ends_with(".bin") and ".." not in path \
		and (path.begins_with("user://") or path.begins_with("res://tmp/") or path.is_absolute_path() and not path.begins_with("res://"))


static func _source(catalog: Dictionary) -> Dictionary:
	var identity: Variant=catalog.get("identity")
	if not identity is Dictionary or not identity.get("path") is String or String(identity.path).is_empty() \
		or not _sha(identity.get("sha256")) or not _sha(catalog.get("input_sha256")) \
		or identity.get("input_sha256",catalog.input_sha256)!=catalog.input_sha256: return {}
	if typeof(catalog.get("min_scale")) not in [TYPE_INT,TYPE_FLOAT] or typeof(catalog.get("max_scale")) not in [TYPE_INT,TYPE_FLOAT] \
		or not is_finite(float(catalog.min_scale)) or not is_finite(float(catalog.max_scale)) \
		or float(catalog.min_scale)<0.0 or float(catalog.max_scale)<=float(catalog.min_scale) \
		or not catalog.get("roots") is Array or catalog.roots.size()!=ROOT_COUNT: return {}
	var context := {"seen":{},"limits":{},"max_scale":float(catalog.max_scale),"valid":true}
	var roots: Array[Dictionary]=[]
	for root: Variant in catalog.roots:
		var copied := _copy_node(root,0,context)
		if not context.valid: return {}
		roots.append(copied)
	if context.seen.size()!=NODE_COUNT: return {}
	var limits: Array[float]=[]
	for limit: float in context.limits: limits.append(limit)
	limits.sort()
	limits.append(float(catalog.max_scale))
	return {"identity":{"path":String(identity.path),"sha256":String(identity.sha256),"input_sha256":String(catalog.input_sha256)},
		"min_scale":float(catalog.min_scale),"max_scale":float(catalog.max_scale),"roots":roots,"limits":limits}


static func _copy_node(value: Variant, depth: int, context: Dictionary) -> Dictionary:
	if depth>2 or not value is Dictionary or value.size()!=NODE_FIELDS.size()+int(depth<2):
		context.valid=false
		return {}
	for name: String in NODE_FIELDS:
		if not value.has(name):
			context.valid=false
			return {}
	if not value.key is String or String(value.key).is_empty() or context.seen.has(value.key) \
		or not value.path is String or String(value.path).is_empty() or not value.texture_path is String or String(value.texture_path).is_empty() \
		or typeof(value.bytes)!=TYPE_INT or value.bytes<0 or value.bytes>1099511627776 \
		or typeof(value.max_scale) not in [TYPE_INT,TYPE_FLOAT] or is_nan(float(value.max_scale)) or float(value.max_scale)<=0.0 \
		or not value.triangles is Array or value.triangles.size()!=3 or not value.boxes is Array or value.boxes.size()!=3 \
		or not _box(value.coverage_box):
		context.valid=false
		return {}
	for index in 3:
		if typeof(value.triangles[index])!=TYPE_INT or value.triangles[index]<0 or not _box(value.boxes[index]):
			context.valid=false
			return {}
	context.seen[value.key]=true
	if float(value.max_scale)<float(context.max_scale): context.limits[float(value.max_scale)]=true
	# 固定字段次序使内容摘要不受Dictionary插入顺序影响。
	var result := {"key":value.key,"path":value.path,"texture_path":value.texture_path,"max_scale":float(value.max_scale),
		"triangles":value.triangles.duplicate(),"boxes":value.boxes.duplicate(),"bytes":value.bytes,"coverage_box":value.coverage_box}
	if depth<2:
		if not value.get("children") is Array or value.children.size()!=4:
			context.valid=false
			return {}
		var children: Array[Dictionary]=[]
		for child: Variant in value.children:
			children.append(_copy_node(child,depth+1,context))
			if not context.valid: return {}
		result["children"]=children
	return result


static func _qualified(source: Dictionary, scale: float) -> Dictionary:
	var result := source.duplicate()
	if scale>float(source.max_scale): result.bytes=DISQUALIFIED_BYTES+int(source.bytes)
	if source.has("children"):
		var children: Array[Dictionary]=[]
		for child: Dictionary in source.children: children.append(_qualified(child,scale))
		result.children=children
	return result


static func _validate_source(artifact: Variant, source: Dictionary) -> bool:
	if not artifact is Dictionary or artifact.size()!=10 or artifact.get("format")!=FORMAT \
		or artifact.get("schema")!=SCHEMA or artifact.get("algorithm")!=ALGORITHM or artifact.get("node_count")!=NODE_COUNT \
		or artifact.get("identity")!=source.identity or artifact.get("source_sha256")!=_digest(source) \
		or artifact.get("min_scale")!=source.min_scale or artifact.get("max_scale")!=source.max_scale \
		or not artifact.get("intervals") is Array or artifact.intervals.size()!=source.limits.size(): return false
	var lower := 0.0
	for index in source.limits.size():
		var interval: Variant=artifact.intervals[index]
		var upper: float=source.limits[index]
		if not interval is Dictionary or interval.size()!=3 or interval.get("lower")!=lower or interval.get("upper")!=upper \
			or not interval.get("roots") is Array or interval.roots.size()!=ROOT_COUNT: return false
		for root_index in ROOT_COUNT:
			if not _matches(interval.roots[root_index],source.roots[root_index],upper,0): return false
		lower=upper
	return _sha(artifact.get("payload_sha256")) and artifact.payload_sha256==_payload_digest(artifact)


static func _matches(value: Variant, source: Dictionary, scale: float, depth: int) -> bool:
	if depth>2 or not value is Dictionary or value.size()!=source.size(): return false
	for name: String in NODE_FIELDS:
		var expected: Variant=DISQUALIFIED_BYTES+int(source.bytes) if name=="bytes" and scale>float(source.max_scale) else source[name]
		if not value.has(name) or typeof(value[name])!=typeof(expected) or value[name]!=expected: return false
	if source.has("children"):
		if not value.get("children") is Array or value.children.size()!=4: return false
		for index in 4:
			if not _matches(value.children[index],source.children[index],scale,depth+1): return false
	return true


static func _box(value: Variant) -> bool:
	return value is AABB and value.position.is_finite() and value.size.is_finite() \
		and value.size.x>=0.0 and value.size.y>=0.0 and value.size.z>=0.0


static func _sha(value: Variant) -> bool:
	if not value is String or value.length()!=64: return false
	for character in value:
		if character not in "0123456789abcdef": return false
	return true


static func _digest(value: Variant) -> String:
	return _bytes_digest(var_to_bytes(value))


static func _bytes_digest(bytes: PackedByteArray) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(bytes)
	return context.finish().hex_encode()


static func _payload_digest(artifact: Dictionary) -> String:
	# 不对自报摘要再做摘要；字段顺序与来源路径独立固定。
	return _digest([artifact.get("format"),artifact.get("schema"),artifact.get("algorithm"),artifact.get("identity"),
		artifact.get("source_sha256"),artifact.get("min_scale"),artifact.get("max_scale"),artifact.get("node_count"),artifact.get("intervals")])
