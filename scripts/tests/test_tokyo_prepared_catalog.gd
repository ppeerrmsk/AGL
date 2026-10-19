extends RefCounted
const Prepared := preload("res://scripts/rendering/tokyo_prepared_catalog.gd")
const Contract := preload("res://scripts/rendering/tokyo_hlod_manifest.gd")
const Fixture := preload("res://scripts/tests/test_tokyo_hlod_manifest.gd")


static func catalog(mixed: bool = true) -> Dictionary:
	var data := Fixture.fixture()
	if mixed:
		for row: Dictionary in data.rows: row["max_scale"]=0.06 if int(row.depth)<2 else 0.1
	var result := Contract.normalize(data)
	result["identity"]={"path":"res://fixture/prepared.json","sha256":"a".repeat(64),"input_sha256":data.input_sha256}
	return result


static func checks() -> bool:
	var source := catalog()
	var unchanged := var_to_bytes(source)
	var artifact := Prepared.build(source)
	if artifact.is_empty() or not Prepared.validate(artifact,source) or artifact!=Prepared.build(source): return false
	if artifact.intervals.size()!=2 or artifact.intervals[0].lower!=0.0 or artifact.intervals[0].upper!=0.06 \
		or artifact.intervals[1].lower!=0.06 or artifact.intervals[1].upper!=0.1: return false
	# 旧算法对拍阈值等号、紧邻右侧、反向缩放与低于目录min_scale的提前查询。
	for scale: float in [0.0001,0.05,0.0599999999,0.06,0.0600000001,0.1,0.06]:
		var expected: Array[Dictionary]=[]
		for root: Dictionary in source.roots: expected.append(Contract.qualified_tree(root,scale))
		if Prepared.roots_at(artifact,scale)!=expected: return false
	for scale: float in [0.0,-1.0,NAN,INF,0.1000000001]:
		if not Prepared.roots_at(artifact,scale).is_empty(): return false
	if var_to_bytes(source)!=unchanged: return false
	# 非混合目录只保留一个快照，正文不带大资源表；Dictionary插入顺序不改变摘要。
	var single := catalog(false)
	var single_artifact := Prepared.build(single)
	if single_artifact.is_empty() or single_artifact.intervals.size()!=1 \
		or Prepared.roots_at(single_artifact,0.1)!=single.roots: return false
	var reordered := source.duplicate()
	reordered.identity={"input_sha256":source.input_sha256,"sha256":source.identity.sha256,"path":source.identity.path}
	reordered["unrelated_metadata"]={"not_serialized":Object.new()}
	var reordered_artifact := Prepared.build(reordered)
	reordered.unrelated_metadata.not_serialized.free()
	if reordered_artifact!=artifact or artifact.has("geometry") or artifact.has("textures"): return false
	for field: String in ["schema","algorithm","node_count"]:
		var invalid := artifact.duplicate(true)
		invalid[field]=int(invalid[field])+1
		invalid.payload_sha256=Prepared._payload_digest(invalid)
		if Prepared.validate(invalid,source): return false
	# 即使重写自报摘要，错误节点、区间或来源身份仍无法蒙混过关。
	var wrong_node := artifact.duplicate(true)
	wrong_node.intervals[1].roots[0].bytes-=1
	wrong_node.payload_sha256=Prepared._payload_digest(wrong_node)
	if Prepared.validate(wrong_node,source): return false
	var wrong_interval := artifact.duplicate(true)
	wrong_interval.intervals[0].upper+=0.0000001
	wrong_interval.payload_sha256=Prepared._payload_digest(wrong_interval)
	if Prepared.validate(wrong_interval,source): return false
	var wrong_identity := artifact.duplicate(true)
	wrong_identity.identity.sha256="b".repeat(64)
	wrong_identity.payload_sha256=Prepared._payload_digest(wrong_identity)
	if Prepared.validate(wrong_identity,source): return false
	var changed := source.duplicate(true)
	changed.roots[0].bytes+=1
	if Prepared.validate(artifact,changed) or Prepared.cache_path(source)==Prepared.cache_path(changed): return false
	changed=source.duplicate(true)
	changed.identity.input_sha256="e".repeat(64)
	if not Prepared.build(changed).is_empty(): return false
	changed=source.duplicate(true)
	changed.roots[0]["unexpected"]=true
	if not Prepared.build(changed).is_empty(): return false
	changed=source.duplicate(true)
	changed.roots[0].children.pop_back()
	if not Prepared.build(changed).is_empty(): return false
	changed=source.duplicate(true)
	changed.roots[0].max_scale=NAN
	if not Prepared.build(changed).is_empty(): return false
	if not Prepared.build({}).is_empty() or Prepared.validate({},source): return false
	return cache_checks(source,artifact)


static func cache_checks(source: Dictionary, artifact: Dictionary) -> bool:
	var path := "user://tokyo_prepared_catalog/test-%d-%d.bin"%[OS.get_process_id(),Time.get_ticks_usec()]
	var absolute := ProjectSettings.globalize_path(path)
	if not Prepared.load_or_build(source,path,false).is_empty(): return false
	if not Prepared.write(path,artifact,source): return false
	var loaded := Prepared.read(path,source)
	var valid := loaded==artifact and Prepared.load_or_build(source,path,false)==artifact
	var changed := source.duplicate(true)
	changed.identity.sha256="b".repeat(64)
	valid=valid and Prepared.read(path,changed).is_empty() and Prepared.load_or_build(changed,path,false).is_empty()
	# Loading内显式允许重建才替换旧身份缓存；回读与新来源精确匹配。
	var rebuilt := Prepared.load_or_build(changed,path,true)
	valid=valid and Prepared.validate(rebuilt,changed) and Prepared.read(path,changed)==rebuilt
	var corrupt := rebuilt.duplicate(true)
	corrupt.intervals[0].roots[0].path="res://wrong.res"
	corrupt.payload_sha256=Prepared._payload_digest(corrupt)
	valid=valid and write_payload(path,corrupt)
	valid=valid and Prepared.read(path,changed).is_empty() and Prepared.load_or_build(changed,path,false).is_empty()
	# 字节损坏、完整帧截断和随机旧文件均在Variant解析前拒绝，不依赖引擎错误日志。
	valid=valid and write_payload(path,rebuilt,"0".repeat(64)) and Prepared.read(path,changed).is_empty()
	var file := FileAccess.open(path,FileAccess.WRITE)
	if file!=null:
		file.store_buffer(Prepared.MAGIC.to_utf8_buffer())
		file.store_32(100)
		file.close()
		valid=valid and Prepared.read(path,changed).is_empty()
	else: valid=false
	file=FileAccess.open(path,FileAccess.WRITE)
	if file!=null:
		file.store_buffer(PackedByteArray([1,2,3]))
		file.close()
		valid=valid and Prepared.read(path,changed).is_empty()
	else: valid=false
	DirAccess.remove_absolute(absolute)
	return valid and not FileAccess.file_exists(path)


static func write_payload(path: String, artifact: Dictionary, checksum: String = "") -> bool:
	var file := FileAccess.open(path,FileAccess.WRITE)
	if file==null: return false
	var bytes := var_to_bytes(artifact)
	file.store_buffer(Prepared.MAGIC.to_utf8_buffer())
	file.store_32(bytes.size())
	file.store_buffer((Prepared._bytes_digest(bytes) if checksum.is_empty() else checksum).to_ascii_buffer())
	file.store_buffer(bytes)
	file.close()
	return true


static func run() -> int:
	var failures := int(not checks())
	print("[Tokyo prepared catalog] fail=",failures)
	return failures
