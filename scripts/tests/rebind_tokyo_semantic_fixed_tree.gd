extends RefCounted
## 新固定组件替换逻辑页第三槽；建筑资源逐字节复用，组合身份和目录值重新绑定。
const Root := preload("res://scripts/tests/build_tokyo_full_grid_root.gd")
const Manifest := preload("res://scripts/rendering/tokyo_component_manifest.gd")


static func entry(before: Dictionary, old: Dictionary, fixed: Dictionary, output: String, result: Dictionary) -> Dictionary:
	var path: String=before.get("path","")
	if not old.pages.has(path) or not old.descriptors.has(path): return {}
	var original: Dictionary=old.pages[path]
	if not Manifest.valid_row(original,old.descriptors[path],old.physical): return {}
	if original.canonical_identity.source!=result.get("original_source"): return {}
	var key:=path.get_file().get_basename()
	if not fixed.nodes.has(key): return {}
	var node: Dictionary=fixed.nodes[key]
	if before.parent_id!=node.parent or before.cell_id!=node.cell or before.ancestor_id!=node.ancestor \
			or before.triangles.size()!=3 or before.boxes.size()!=3 or before.children.size()!=node.children.size(): return {}
	var old_fixed: String=original.mapping[2][0]
	if original.mapping[2][1]!=0 or original.mapping[0][0]==old_fixed or original.mapping[1][0]==old_fixed: return {}
	var item: Dictionary=node.component
	if not fixed.physical.has(item.path) or fixed.physical[item.path]!=item: return {}
	var row:=original.duplicate(true)
	row.components.erase(old_fixed)
	row.components[item.path]=item
	row.mapping[2]=[item.path,0]
	row.bytes=int(original.bytes)-int(original.components[old_fixed].bytes)+int(item.bytes)
	row.triangles=int(original.triangles)-int(before.triangles[2])+int(node.triangles)
	row.canonical_identity.source=result.source_hash
	var descriptor: Dictionary={"bytes":row.bytes,"canonical_identity":row.canonical_identity}
	for resource_path: String in row.components:
		var component: Dictionary=row.components[resource_path]
		if result.physical.has(resource_path) and result.physical[resource_path]!=component: return {}
		result.physical[resource_path]=component
	var logical:=output.path_join(key+".logical")
	if result.pages.has(logical) or not Manifest.valid_row(row,descriptor,result.physical): return {}
	result.pages[logical]=row
	result.descriptors[logical]=descriptor
	var after:=before.duplicate(true)
	after.path=logical
	after.bytes=row.bytes
	after.triangles[2]=int(node.triangles)
	after.boxes[2]=node.bounds
	after.children=[]
	for n in before.children.size():
		var child: Dictionary=before.children[n]
		if str(child.path).get_file().get_basename()!=node.children[n]: return {}
		var changed:=entry(child,old,fixed,output,result)
		if changed.is_empty(): return {}
		after.children.append(changed)
	return after


static func run(input: String, digest: String, output: String) -> int:
	if not Root.binding_valid({"path":input,"sha256":digest}) or not output.is_absolute_path() or DirAccess.dir_exists_absolute(output): return 1
	var config: Variant=JSON.parse_string(FileAccess.get_file_as_string(input))
	if not config is Dictionary: return 1
	for key: String in ["original_manifest","original_provenance","original_proof","fixed_manifest","fixed_provenance","fixed_proof"]:
		if not Root.binding_valid(config.get(key)): return 1
	var provenance: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(config.original_provenance.path))
	var fixed_provenance: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(config.fixed_provenance.path))
	for name: String in ["original_proof","fixed_proof"]:
		var proof: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(config[name].path))
		if proof.get("exit",-1)!=0: return 1
	if not provenance.get("saved_components",false) or not provenance.get("fixed_included",false) \
			or not provenance.get("gameplay_additions_included",false) or not fixed_provenance.get("saved_components",false) \
			or not fixed_provenance.get("actual_native_partition_verified",false) or provenance.get("parent")!=fixed_provenance.get("parent") \
			or provenance.get("parent")!=config.get("parent") or provenance.get("configuration")!=config.get("configuration") \
			or fixed_provenance.get("manifest_sha256")!=config.fixed_manifest.sha256: return 1
	var file:=FileAccess.open(config.original_manifest.path,FileAccess.READ)
	if file==null: return 1
	var old: Variant=file.get_var(false); file.close()
	file=FileAccess.open(config.fixed_manifest.path,FileAccess.READ)
	if file==null: return 1
	var fixed: Variant=file.get_var(false); file.close()
	if not old is Dictionary or not fixed is Dictionary or old.get("pages",{}).size()!=277 \
			or fixed.get("nodes",{}).size()!=277 or fixed.get("physical",{}).size()!=277 \
			or fixed.get("parent")!=config.parent or not fixed.get("saved_components",false): return 1
	var original_proof: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(config.original_proof.path))
	var bindings: Dictionary=original_proof.get("bindings",{})
	var origin_binding: Dictionary={"path":bindings.get("AGL_TOKYO_FULL_ROOT_PAGES_INPUT",""),"sha256":bindings.get("AGL_TOKYO_FULL_ROOT_PAGES_SHA","")}
	if not Root.binding_valid(origin_binding): return 1
	var origin: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(origin_binding.path))
	for key: String in ["plan","schedule","fixed_manifest"]:
		if not Root.binding_valid(origin.get(key)): return 1
	var schedule: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(origin.schedule.path))
	var original_fixed: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(origin.fixed_manifest.path))
	if not schedule.get("passed",false) or not Root.binding_valid(original_fixed.get("component")) \
			or origin.get("parent")!=config.parent or origin.get("configuration")!=config.configuration: return 1
	# 沿既有coverage的精确公式，不另造会令整图覆盖门失配的组合身份。
	var original_source: String=(str(origin.plan.sha256)+str(schedule.owners_sha256)+str(original_fixed.component.sha256)).sha256_text()
	var source_hash: String=(str(origin.plan.sha256)+str(schedule.owners_sha256)+str(fixed.fixed_source.sha256)).sha256_text()
	# 验证文件内容再复用，不能仅复制旧清单值冒充建筑未改变。
	for resource_path: String in old.physical:
		if not Root.binding_valid(old.physical[resource_path]): return 1
	for resource_path: String in fixed.physical:
		if not Root.binding_valid(fixed.physical[resource_path]): return 1
	var result: Dictionary={"pages":{},"descriptors":{},"physical":{},"root":{},"canonical_ready":false,"installed":false,
		"original_source":original_source,"source_hash":source_hash}
	result.root=entry(old.root,old,fixed,output,result)
	if result.root.is_empty() or result.pages.size()!=277 or result.descriptors.size()!=277: return 1
	if DirAccess.make_dir_recursive_absolute(output)!=OK: return 1
	var target:=output.path_join("manifest.bin")
	file=FileAccess.open(target,FileAccess.WRITE)
	if file==null: return 1
	file.store_var(result,false); file.close()
	file=FileAccess.open(target,FileAccess.READ)
	if file==null: return 1
	var saved: Variant=file.get_var(false); file.close()
	if saved!=result: return 1
	file=FileAccess.open(output.path_join("provenance.json"),FileAccess.WRITE)
	if file==null: return 1
	file.store_string(JSON.stringify({"input_sha256":digest,"parent":config.parent,"configuration":config.configuration,
		"nodes":277,"fixed_included":true,"gameplay_additions_included":true,"saved_components":true,
		"canonical_source_sha256":source_hash,"original_source_sha256":original_source,
		"building_geometry_rebuilt":false,"building_components_sha_checked":true,"source_coverage_proven":false,"installed":false},"",true,true)); file.close()
	print("[Semantic fixed rebind] ",config.configuration," parent=",config.parent," 277 logical pages; building files unchanged")
	return 0


static func checks() -> bool:
	if run("","","")!=1: return false
	var physical: Dictionary={}
	var mapping: Array=[]
	for kind in 3:
		var path: String="C:/fixture/layer%d.res" % kind
		physical[path]={"path":path,"bytes":(kind+1)*10,"sha256":"a".repeat(64),
			"canonical_identity":{"format":"tokyo_mesh_component","schema":1,"slots":1,"source":"b".repeat(64)}}
		mapping.append([path,0])
	var game:=PackedInt32Array([17,42])
	var identity: Dictionary={"configuration":"lod0_full","source":"c".repeat(64),"game_sources":var_to_bytes(game).hex_encode().sha256_text()}
	var row: Dictionary={"components":physical.duplicate(true),"mapping":mapping,"bytes":60,"triangles":9,"game_sources":game,"canonical_identity":identity}
	var before: Dictionary={"path":"C:/fixture/node.logical","parent_id":0,"cell_id":320,"ancestor_id":64,"level":0,
		"bytes":60,"triangles":PackedInt32Array([2,3,4]),"boxes":[AABB(),AABB(),AABB()],"children":[]}
	var old: Dictionary={"pages":{before.path:row},"descriptors":{before.path:{"bytes":60,"canonical_identity":identity}},"physical":physical}
	var replacement: Dictionary=physical[mapping[2][0]].duplicate(true)
	replacement.path="C:/fixture/new_fixed.res"
	replacement.bytes=12
	replacement.sha256="d".repeat(64)
	var fixed: Dictionary={"fixed_source":{"sha256":"e".repeat(64)},"physical":{replacement.path:replacement},
		"nodes":{"node":{"component":replacement,"parent":0,"cell":320,"ancestor":64,"children":[],"triangles":1,"bounds":AABB()}}}
	var snapshot:=var_to_bytes(old)
	var result: Dictionary={"pages":{},"descriptors":{},"physical":{},"original_source":identity.source,"source_hash":"f".repeat(64)}
	var after:=entry(before,old,fixed,"C:/new",result)
	if after.is_empty() or after.bytes!=42 or after.triangles!=PackedInt32Array([2,3,1]) or var_to_bytes(old)!=snapshot: return false
	var changed: Dictionary=result.pages[after.path]
	if changed.game_sources!=game or changed.mapping.slice(0,2)!=mapping.slice(0,2) or changed.triangles!=6 \
			or changed.canonical_identity.source==identity.source or changed.components.has(mapping[2][0]): return false
	for kind in 2:
		if changed.components[mapping[kind][0]]!=physical[mapping[kind][0]]: return false
	fixed.nodes.clear()
	return entry(before,old,fixed,"C:/new",{"pages":{},"descriptors":{},"physical":{},"original_source":identity.source,"source_hash":"f".repeat(64)}).is_empty()
