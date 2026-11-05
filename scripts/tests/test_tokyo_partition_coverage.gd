extends RefCounted
const Delta := preload("res://scripts/rendering/tokyo_partition_coverage.gd")
const Coverage := preload("res://scripts/experiments/tokyo_source_coverage.gd")


static func row(path: String, leaves: Array, roof: Array, wall: Array) -> Dictionary:
	return {"identity":{"fixture":path},"leaves":PackedStringArray(leaves),
		"tokens":[PackedStringArray(roof),PackedStringArray(wall)]}


static func checks(share_unchanged: bool = false) -> bool:
	var box := AABB(Vector3.ZERO,Vector3(10,3,10))
	var original := {"path":"old","children":[{"path":"old-a","children":[]},{"path":"old-b","children":[]}],
		"triangles":PackedInt32Array([2,1,1]),"boxes":[box,box,box]}
	var left := {"path":"new-a","children":[]}
	var right := {"path":"new-b","children":[]}
	var tree := {"path":"new","children":[left,right],"triangles":[2,1,1],"boxes":[box,box,box]}
	var base := {"schema":1,"verified":true,"configuration":"lod5_full","catalog_sha256":"catalog",
		"collision_sha256":"collision","owners_sha256":"owners","plan_sha256":"plan","pages":{
		"above":row("above",["old-a","old-b","other"],["old-a:0","old-b:0"],["old-a:1","other:1"]),
		"old":row("old",["old-a","old-b"],["old-a:0","old-b:0"],["old-a:1"]),
		"old-a":row("old-a",["old-a"],["old-a:0"],["old-a:1"]),
		"old-b":row("old-b",["old-b"],["old-b:0"],[]),"other":row("other",["other"],[],["other:1"])},
		"sources":{0:PackedStringArray(["old-a:0","old-a:1"]),1:PackedStringArray(["old-b:0","other:1"])}}
	var before := base.duplicate(true)
	var rows := {"new":row("new",["new-a","new-b"],["new-a:0","new-b:0"],["new-a:1"]),
		"new-a":row("new-a",["new-a"],["new-a:0"],["new-a:1"]),"new-b":row("new-b",["new-b"],["new-b:0"],[])}
	var normalized := {"tree":tree,"pages":{}}
	for path: String in rows: normalized.pages[path]={"canonical_identity":rows[path].identity}
	var delta := {"schema":1,"partition_sha256":"partition","target":"old",
		"tree_sha256":var_to_bytes(original).hex_encode().sha256_text(),"all_channels_conserved":true,
		"configuration":"lod5_full","catalog_sha256":"catalog","collision_sha256":"collision",
		"owners_sha256":"owners","plan_sha256":"plan","expected_faces":PackedInt32Array([2,1]),
		"found_faces":PackedInt32Array([2,1]),"pages":rows,
		"sources":{0:PackedStringArray(["new-a:0","new-a:1","new-b:0"]),1:PackedStringArray(["new-b:0"])}}
	var result := Delta.apply(base,delta,original,normalized,"partition",share_unchanged)
	if result.is_empty() or base!=before or result.pages.has("old") or result.pages.has("old-a"): return false
	# 有保守来源标签但无正式三角面的邻页，只迁移空依赖，不得影响其他来源。
	var empty_base := base.duplicate(true)
	empty_base.sources={}
	for value: Dictionary in empty_base.pages.values(): value.tokens=[PackedStringArray(),PackedStringArray()]
	var empty_delta := delta.duplicate(true)
	empty_delta.expected_faces=PackedInt32Array([0,0]);empty_delta.found_faces=PackedInt32Array([0,0]);empty_delta.sources={}
	for value: Dictionary in empty_delta.pages.values(): value.tokens=[PackedStringArray(),PackedStringArray()]
	var empty_result := Delta.apply(empty_base,empty_delta,original,normalized,"partition",share_unchanged)
	if empty_result.is_empty() or not empty_result.sources.is_empty(): return false
	if not Delta.apply(base,empty_delta,original,normalized,"partition",share_unchanged).is_empty(): return false
	var false_claim := empty_delta.duplicate(true);false_claim.sources={0:PackedStringArray(["new-a:0"])}
	if not Delta.apply(empty_base,false_claim,original,normalized,"partition",share_unchanged).is_empty(): return false
	var committed: Dictionary={}
	for path: String in ["new-a","new-b","other"]: committed[path]={"identity":result.pages[path].identity,"layers":3}
	if Coverage.covered_sources(result,committed,"lod5_full","collision","catalog")!=PackedInt32Array([0,1]): return false
	committed.erase("new-b")
	if not Coverage.covered_sources(result,committed,"lod5_full","collision","catalog").is_empty(): return false
	committed["new-b"]={"identity":result.pages["new-b"].identity,"layers":3}
	committed["new-a"].layers=2
	if Coverage.covered_sources(result,committed,"lod5_full","collision","catalog")!=PackedInt32Array([1]): return false
	committed["new-a"].layers=3
	committed["new-a"].identity={"fixture":"wrong"}
	if not Coverage.covered_sources(result,committed,"lod5_full","collision","catalog").is_empty(): return false
	var ancestor := {"above":{"identity":result.pages.above.identity,"layers":3}}
	if Coverage.covered_sources(result,ancestor,"lod5_full","collision","catalog")!=PackedInt32Array([0,1]): return false
	ancestor["new-a"]={"identity":result.pages["new-a"].identity,"layers":3}
	if not Coverage.covered_sources(result,ancestor,"lod5_full","collision","catalog").is_empty(): return false
	for field: String in ["partition_sha256","target","tree_sha256","configuration","catalog_sha256","collision_sha256","owners_sha256","plan_sha256"]:
		var wrong := delta.duplicate(true);wrong[field]="wrong"
		if not Delta.apply(base,wrong,original,normalized,"partition",share_unchanged).is_empty(): return false
	var wrong := delta.duplicate(true);wrong.all_channels_conserved=false
	if not Delta.apply(base,wrong,original,normalized,"partition",share_unchanged).is_empty(): return false
	wrong=delta.duplicate(true);wrong.found_faces=PackedInt32Array([1,1])
	if not Delta.apply(base,wrong,original,normalized,"partition",share_unchanged).is_empty(): return false
	wrong=delta.duplicate(true);wrong.sources.erase(1)
	if not Delta.apply(base,wrong,original,normalized,"partition",share_unchanged).is_empty(): return false
	wrong=delta.duplicate(true);wrong.sources[0]=PackedStringArray(["not-a-leaf:0"])
	if not Delta.apply(base,wrong,original,normalized,"partition",share_unchanged).is_empty(): return false
	wrong=delta.duplicate(true);wrong.pages["new-a"].tokens[0]=PackedStringArray(["new-b:0"])
	if not Delta.apply(base,wrong,original,normalized,"partition",share_unchanged).is_empty(): return false
	wrong=delta.duplicate(true);wrong.pages["new"].leaves=PackedStringArray(["new-a"])
	if not Delta.apply(base,wrong,original,normalized,"partition",share_unchanged).is_empty(): return false
	wrong=delta.duplicate(true);wrong.pages["new-a"].identity={"fixture":"wrong"}
	if not Delta.apply(base,wrong,original,normalized,"partition",share_unchanged).is_empty(): return false
	var wrong_geometry := normalized.duplicate(true);wrong_geometry.tree.triangles[0]=1
	if not Delta.apply(base,delta,original,wrong_geometry,"partition",share_unchanged).is_empty(): return false
	return base==before


static func relocation_checks() -> bool:
	var old_sha := "a".repeat(64)
	var new_sha := "b".repeat(64)
	var old_path := old_sha+":leaf"
	var new_path := new_sha+":leaf"
	var identity := {"partition":old_sha}
	var data := {"schema":1,"verified":true,"configuration":"lod5_full","catalog_sha256":"catalog",
		"collision_sha256":"collision","partition_sha256":old_sha,"pages":{
		old_path:{"identity":identity,"leaves":PackedStringArray([old_path]),
			"tokens":[PackedStringArray([old_path+":0"]),PackedStringArray()]}},
		"sources":{0:PackedStringArray([old_path+":0"])}}
	var stage := preload("res://scripts/tests/stage_tokyo_incremental_package.gd")
	var moved := stage.relocated_coverage(data,old_sha,new_sha,{old_path:new_path})
	if moved.is_empty() or not stage.relocated_coverage(data,old_sha,new_sha,{}).is_empty(): return false
	var committed := {new_path:{"identity":{"partition":new_sha},"layers":1}}
	if Coverage.covered_sources(moved,committed,"lod5_full","collision","catalog")!=PackedInt32Array([0]): return false
	committed[new_path].identity=identity
	return Coverage.covered_sources(moved,committed,"lod5_full","collision","catalog").is_empty() \
		and data.partition_sha256==old_sha and data.pages.has(old_path)


static func run() -> int:
	var failures := int(not checks())+int(not checks(true))+int(not relocation_checks())
	print("[Tokyo partition formal coverage] fail=",failures)
	return failures
