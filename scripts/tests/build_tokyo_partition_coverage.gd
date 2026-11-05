extends RefCounted
## 正式建筑无损分包：匹配原认证计划的朝向三角面和出现次数，再生成新叶依赖。
const Delta := preload("res://scripts/rendering/tokyo_partition_coverage.gd")
const Faces := preload("res://scripts/tests/build_tokyo_source_coverage.gd")
const Boundary := preload("res://scripts/tests/build_tokyo_boundary_tree.gd")
const Join := preload("res://scripts/experiments/tokyo_packed_mesh_join.gd")
var failed := false
var rows: Dictionary={}
var sources: Dictionary={}
var found: Array=[{},{}]


func visit(tree: Dictionary, normalized: Dictionary, needs: Array) -> Dictionary:
	var row := {"identity":normalized.pages[tree.path].canonical_identity,"leaves":PackedStringArray(),
		"tokens":[PackedStringArray(),PackedStringArray()]}
	if tree.children.is_empty():
		row.leaves.append(tree.path)
		var meshes := Boundary.meshes(normalized.pages[tree.path],normalized.pages[tree.path].components)
		if meshes.size()!=3: failed=true;print("[partition coverage rejected] check 19");return {}
		for kind in 2:
			for face: PackedByteArray in Faces._faces(meshes[kind]):
				if not needs[kind].has(face): continue
				found[kind][face]=int(found[kind].get(face,0))+1
				var token: String=tree.path+":"+str(kind)
				if row.tokens[kind].is_empty(): row.tokens[kind].append(token)
				for source: int in needs[kind][face].sources:
					if not sources.has(source): sources[source]=PackedStringArray()
					if not sources[source].has(token): sources[source].append(token)
	else:
		for child: Dictionary in tree.children:
			var sub := visit(child,normalized,needs)
			if failed: print("[partition coverage rejected] check 32");return {}
			row.leaves.append_array(sub.leaves)
			for kind in 2: row.tokens[kind].append_array(sub.tokens[kind])
	rows[tree.path]=row
	return row


func build(native: RefCounted, original: Dictionary, normalized: Dictionary, partition_sha: String,
		expected_binding: Dictionary, output: String) -> Dictionary:
	failed=false;rows={};sources={};found=[{},{}]
	var configuration: String=native.pages[original.path].canonical_identity.configuration
	var parent: int=native.pages[original.path].canonical_identity.parent
	var base: Dictionary=native.coverage[configuration]
	if expected_binding.get("plan",{}).get("sha256")!=base.plan_sha256 \
		or expected_binding.get("schedule",{}).get("sha256")!=base.schedule_sha256: print("[partition coverage rejected] check 46");return {}
	var expected := Delta.read(expected_binding)
	if not expected.has(parent) or not expected[parent] is Array or expected[parent].size()!=2: print("[partition coverage rejected] check 48");return {}
	var needs: Array=expected[parent]
	var before := Boundary.meshes(native.pages[original.path],native.pages[original.path].components)
	var after := Boundary.meshes(normalized.pages[normalized.tree.path],normalized.pages[normalized.tree.path].components)
	if before.size()!=3 or after.size()!=3: print("[partition coverage rejected] check 52");return {}
	for kind in 3:
		if not Join.conserved(before[kind],[after[kind]]): print("[partition coverage rejected] check 54");return {}
	var expected_counts: Array=[{},{}]
	var totals := PackedInt32Array([0,0])
	for kind in 2:
		for face: PackedByteArray in Faces._faces(before[kind]):
			if not needs[kind].has(face): continue
			expected_counts[kind][face]=int(expected_counts[kind].get(face,0))+1
			totals[kind]+=1
	# 区域来源标签可能覆盖没有正式三角面的邻页。只有旧逐面凭据也完全为空时，
	# 才允许生成空依赖迁移；全部三层属性仍已逐面守恒，不能凭标签补造来源。
	if totals[0]+totals[1]==0:
		var old: Dictionary=base.pages[original.path]
		if not old.tokens[0].is_empty() or not old.tokens[1].is_empty():
			print("[partition coverage rejected] zero matches but old dependencies exist: ",original.path);return {}
	visit(normalized.tree,normalized,needs)
	if failed or found!=expected_counts: print("[partition coverage rejected] check 64");return {}
	var delta := {"schema":1,"target":original.path,"partition_sha256":partition_sha,
		"tree_sha256":var_to_bytes(original).hex_encode().sha256_text(),"all_channels_conserved":true,
		"expected_faces":totals,"found_faces":totals,"pages":rows,"sources":sources,
		"expected_binding":expected_binding,"oriented_face_counts_sha256":var_to_bytes(expected_counts).hex_encode().sha256_text()}
	for field: String in ["configuration","catalog_sha256","collision_sha256","owners_sha256","plan_sha256"]:
		delta[field]=base[field]
	var adapted := Delta.apply(base,delta,original,normalized,partition_sha)
	if adapted.is_empty(): print("[partition coverage rejected] check 72");return {}
	# 全部新叶就绪才能替代这一来源的凭据；漏任一已声明层的依赖必须撤回。
	var committed: Dictionary={}
	for path: String in adapted.pages:
		var row: Dictionary=adapted.pages[path]
		if row.leaves.size()==1 and row.leaves[0]==path: committed[path]={"identity":row.identity,"layers":3}
	var coverage := preload("res://scripts/experiments/tokyo_source_coverage.gd")
	if coverage.covered_sources(adapted,committed,configuration,base.collision_sha256,base.catalog_sha256).size()!=base.sources.size(): print("[partition coverage rejected] check 79");return {}
	for source: int in sources:
		for token: String in sources[source]:
			var split := token.rfind(":")
			var path := token.left(split)
			var kind := int(token.substr(split+1))
			committed[path].layers=3 & ~(1<<kind)
			if coverage.covered_sources(adapted,committed,configuration,base.collision_sha256,base.catalog_sha256).has(source): print("[partition coverage rejected] check 86");return {}
			committed[path].layers=3
	if FileAccess.file_exists(output): print("[partition coverage rejected] check 88");return {}
	var file := FileAccess.open(output,FileAccess.WRITE)
	if file==null: print("[partition coverage rejected] check 90");return {}
	file.store_var(delta);file.close()
	var binding := {"path":output,"sha256":FileAccess.get_sha256(output)}
	if Delta.read(binding)!=delta: print("[partition coverage rejected] check 93");return {}
	return binding
