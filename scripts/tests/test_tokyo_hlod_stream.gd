extends RefCounted
const Stream := preload("res://scripts/rendering/tokyo_hlod_stream.gd")

class RefinementSource extends RefCounted:
	var catalog: Dictionary={}
	var _partition_roots: Dictionary={}
	var pages: Dictionary={}
	var coverage: Dictionary={}


static func refinement_source_checks() -> bool:
	var split := preload("res://scripts/tests/tokyo_native_refinement_probe.gd")
	var hint := {"axis":1,"threshold":-11700.0}
	if split.planned_cut({"source_root":hint},"source_root")!=hint \
		or not split.planned_cut({},"source_root").is_empty(): return false
	for invalid in [null,{}, {"axis":2,"threshold":0}, {"axis":true,"threshold":0},
		{"axis":0,"threshold":"0"},{"axis":0,"threshold":INF},{"axis":0,"threshold":NAN}]:
		if not split.planned_cut({"source_root":invalid},"source_root").is_empty(): return false
	var massing := preload("res://scripts/tests/build_tokyo_source_massing.gd")
	if massing.split_depth({})!=2: return false
	for depth in [1,2,3,4]:
		if massing.split_depth({"split_depth":depth})!=depth: return false
	for invalid in [0,5,-1,2.5,"2",true,null]:
		if massing.split_depth({"split_depth":invalid})!=-1: return false
	var exporter := preload("res://scripts/tests/export_tokyo_native_source.gd")
	var a := {"path":"a","children":[]}
	var b := {"path":"b","children":[]}
	var group := {"path":"group","children":[a,b]}
	var root := {"path":"root","children":[group,{"path":"other","children":[]}]}
	if exporter.common_source([root],["a","b"])!=group \
		or exporter.common_source([root],["a"])!=a \
		or exporter.common_source([root],["a","other"])!=root: return false
	for invalid in [[],["missing"],["a","missing"],["a","a"],[1],[""]]:
		if not exporter.common_source([root],invalid).is_empty(): return false
	if exporter.unchanged_sources(root,[root])!=[root]: return false
	var partial := root.duplicate(true)
	partial.children[0].children[0]={"path":"replacement","children":[]}
	if exporter.unchanged_sources(root,[partial])!=[b,root.children[1]] \
		or not exporter.unchanged_sources(root,[]).is_empty(): return false
	var builder := preload("res://scripts/tests/build_tokyo_lossless_leaf_partitions.gd")
	var source := RefinementSource.new()
	var entry := {"path":"original","children":[],"bytes":4096,"triangles":PackedInt32Array([10,0,0]),
		"boxes":[AABB(Vector3.ZERO,Vector3(10,1,10)),AABB(),AABB()]}
	var replaced := entry.duplicate(true)
	var leaf_plan := {"split_depth":1,"tree_sha256":var_to_bytes(entry).hex_encode().sha256_text(),"cuts":{"original":hint}}
	if not builder.valid_leaf_plan(leaf_plan,entry,1) or builder.valid_leaf_plan(leaf_plan,entry,2) \
		or builder.valid_leaf_plan(leaf_plan,{},1) or builder.valid_leaf_plan({},entry,1): return false
	var invalid_plan := leaf_plan.duplicate(true)
	invalid_plan.tree_sha256="0".repeat(64)
	if builder.valid_leaf_plan(invalid_plan,entry,1): return false
	invalid_plan=leaf_plan.duplicate(true);invalid_plan.cuts={"wrong":hint}
	if builder.valid_leaf_plan(invalid_plan,entry,1): return false
	invalid_plan=leaf_plan.duplicate(true);invalid_plan.cuts.original={"axis":3,"threshold":0.0}
	if builder.valid_leaf_plan(invalid_plan,entry,1): return false
	replaced.path="replacement";replaced.triangles=PackedInt32Array([2,0,0])
	source.catalog={"configurations":{"lod5_full":[entry]}}
	source._partition_roots={"lod5_full":[replaced]}
	source.pages={"original":{"game_sources":PackedStringArray()}}
	source.coverage={"lod5_full":{"pages":{"original":{"tokens":[[],[]]}}}}
	if not builder.refinable(entry,source,"lod5_full") or builder.refinable(replaced,source,"lod5_full"): return false
	source.coverage.lod5_full.pages.original.tokens[1]=["formal"]
	if builder.refinable(entry,source,"lod5_full"): return false
	source.coverage.lod5_full.pages.original.tokens[1]=[]
	source.pages.original.game_sources=PackedStringArray(["formal"])
	if builder.refinable(entry,source,"lod5_full"): return false
	# 拒绝细分的页仍参与成本，不能把未加工页当空白；当前树不可退回旧10面页。
	var probe := preload("res://scripts/tests/tokyo_native_refinement_probe.gd").new()
	probe.eligible_leaf=func(_entry: Dictionary) -> bool: return false
	var old := probe.select(source,Vector2(5,5),1.0,0.0,Vector2(1600,900),"lod5_full",1)
	probe.current_roots=true
	var current := probe.select(source,Vector2(5,5),1.0,0.0,Vector2(1600,900),"lod5_full",1)
	return not probe.failed and old.get("triangles",0)==10 and current.get("triangles",0)==2 \
		and probe._cache.is_empty() and int(entry.triangles[0])==10

## 只替换资源与GPU绑定；沿真实提交函数验证完整性、清晰度和可见性事务。
class CommitStream extends Node:
	var _cache: Dictionary={}
	var _textures: Dictionary={}
	var texture_ready := false
	var reserve_ok := true
	var reservations: Dictionary={}
	var payload := Resource.new()
	func resource(_path: String) -> Resource: return payload
	func texture(_path: String) -> Resource: return payload if texture_ready else null
	func reserve_auxiliary(key: int, amount: int) -> bool:
		if not reserve_ok or reservations.has(key): return false
		reservations[key]=amount
		return true
	func release_auxiliary(key: int) -> void: reservations.erase(key)
	func close() -> void: pass

class CommitOverlay extends "res://scripts/rendering/tokyo_hlod_overlay.gd":
	var binds := 0
	var current_view_covered := true
	var committed_view_covered := true
	var coverage_margin := INF
	func _cut_covers_current_view(_cut: Dictionary, _catalog: int, _margin_px: float = 0.0) -> bool: return committed_view_covered
	func _target_covers_current_view(margin_px: float = 0.0) -> bool: return current_view_covered and margin_px<=coverage_margin
	func _bind_target() -> void:
		binds+=1
		_committed=_target.keys.duplicate()
		_committed_cut=_target
		_committed_catalog=_target_catalog
	func _request_target(_keep_current: bool) -> void: pass

class NativeSelectionProbe extends RefCounted:
	var calls := 0
	var configurations: Array[String]=[]
	var budgets: Array[int]=[]
	var minimum_budget := 0
	var empty_below_budget := false
	var ground_choice := "lod5_full"
	var response: Dictionary={"within_budget":true,"keys":PackedStringArray(["replacement"]),"bytes":1}
	func ground_configuration(_scale: float) -> String: return ground_choice
	func select(_center: Vector2, _scale: float, _angle: float, _size: Vector2, _configuration: String, _budget: int, _resident: Dictionary = {}) -> Dictionary:
		calls+=1
		configurations.append(_configuration)
		budgets.append(_budget)
		if empty_below_budget and _budget<minimum_budget: return {}
		var result := response.duplicate(true)
		if _budget<minimum_budget: result["within_budget"]=false
		return result

class NativeBridgeOverlay extends CommitOverlay:
	var bridge_bytes := 100
	var bridge_ready := true
	func _handoff_bytes(_next: Dictionary, _selected: int) -> int: return bridge_bytes
	func _resources_ready(_cut: Dictionary, _catalog: int) -> bool: return bridge_ready

static func native_screen_bridge_checks() -> int:
	var overlay := NativeBridgeOverlay.new()
	var source := NativeSelectionProbe.new()
	overlay._native=source
	var stream := CommitStream.new()
	overlay._stream=stream
	source.response={"keys":PackedStringArray(["screen"]),"configuration":"lod5_full","within_budget":true,"bytes":100,"triangles":100}
	var pending := {"keys":PackedStringArray(["guard"]),"configuration":"lod5_full","ground_images":PackedStringArray(["ground","height"]),
		"prefetch_keys":PackedStringArray(["future"]),"prefetch_catalog":-2}
	var before := pending.duplicate(true)
	var cut := overlay._native_screen_bridge(pending,Vector2.ZERO,1.6,0,Vector2(1600,900),200)
	var failures := int(cut.is_empty() or cut.get("keys")!=PackedStringArray(["screen"]) or pending!=before)
	for request: Dictionary in [{"mesh":"guard","image":""},{"mesh":"guard","image":"ground"},{"mesh":"guard","image":"height"},{"mesh":"future","image":""}]:
		failures+=int(request not in cut.get("prefetch_extra",[]))
	for mode in 6:
		overlay.bridge_ready=mode!=0
		overlay.committed_view_covered=mode!=1
		overlay.bridge_bytes=201 if mode==2 else (-1 if mode==3 else 100)
		source.response.within_budget=mode!=4
		source.response["ground_max_scale"]=1.0 if mode==5 else 5.0
		failures+=int(not overlay._native_screen_bridge(pending,Vector2.ZERO,1.6,0,Vector2(1600,900),200).is_empty())
	overlay.free()
	stream.free()
	return failures+native_resident_tree_checks()

static func native_resident_tree_checks() -> int:
	var cached := preload("res://scripts/rendering/tokyo_hlod_cached_cut.gd")
	var multi := {"path":"multi","mask":[false,false,true],"ground_surfaces":[
		{"texture":"a","height_texture":"ha","max_scale":1.6},
		{"texture":"b","height_texture":"hb","max_scale":1.25}]}
	var decorated := preload("res://scripts/rendering/tokyo_hlod_native.gd").decorate({"entries":[multi]},"lod5_full",true)
	if decorated.ground_images!=PackedStringArray(["a","ha","b","hb"]) or decorated.ground_max_scale!=1.25 or decorated.charges.ground_bytes!=576: return 1
	multi.mask[2]=false
	decorated=preload("res://scripts/rendering/tokyo_hlod_native.gd").decorate({"entries":[multi]},"lod5_full",true)
	if not decorated.ground_images.is_empty() or decorated.charges.ground_bytes!=0: return 1
	var solver := preload("res://scripts/experiments/tokyo_spatial_cut.gd")
	var box := AABB(Vector3(10,0,10),Vector3(20,1,20))
	var child := {"path":"a","triangles":[2,0,2],"boxes":[box,AABB(),box],"bytes":100,"children":[],
		"ground_replacement":{"texture":"ground","height_texture":"height"}}
	var other := child.duplicate(true);other.path="b"
	var root := child.duplicate(true);root.path="root";root.triangles=[20,0,20];root.children=[child,other]
	var original := root.duplicate(true)
	var context := {"view":Rect2(0,0,100,100),"canvas":Transform2D.IDENTITY,"size":Vector2(100,100),"roof":Vector2.ZERO,
		"geometry":{"root":{"components":{"root":{}}},"a":{"components":{"a":{}}},"b":{"components":{"b":{}}}},
		"meshes":{"a":{},"b":{}},"textures":{"ground":{},"height":{}}}
	var failures := 0
	var multi_child := child.duplicate(true)
	multi_child.erase("ground_replacement")
	multi_child["ground_surfaces"]=[{"texture":"ground","height_texture":"height"},{"texture":"second"}]
	if cached.native_tree(multi_child,context).bytes<=192*1024*1024: return 1
	context.textures["second"]={}
	if cached.native_tree(multi_child,context).bytes!=child.bytes: return 1
	context.textures.erase("second")
	for mode in 5:
		context.meshes={"a":{},"b":{}} if mode==0 else ({"root":{},"a":{}} if mode==1 else {"a":{}})
		if mode==3: context.meshes={"a":{},"b":{}};context.textures.erase("height")
		if mode==4: context.textures["height"]={};context.geometry.erase("a");context.meshes={"a":{},"b":{}}
		var tree: Array[Dictionary]=[cached.native_tree(root,context)]
		var cut := solver.choose(tree,context.view,context.canvas,context.size,context.roof,Vector2.ZERO,16,192*1024*1024)
		failures+=int(cut.within_budget!=(mode<2))
		if mode==0: failures+=int(cut.active!=2 or cut.triangles!=8)
		if mode==1: failures+=int(cut.active!=1 or cut.entries[0].path!="root")
		failures+=int(root!=original)
	return failures

class LoadingOverlay extends CommitOverlay:
	func _select_native(_center: Vector2, _scale: float, _angle: float, _size: Vector2, _configuration: String = "", _budget: int = -1, _retain: bool = true) -> Dictionary:
		return {"within_budget":true,"keys":PackedStringArray(["warm_mesh"]),"ground_images":PackedStringArray(["warm_image"])}

static func foundation_checks() -> int:
	var static_script := preload("res://scripts/rendering/tokyo_static_hlod_overlay.gd")
	var readiness := preload("res://scripts/rendering/tokyo_volume_preload.gd")
	if static_script.STATIC_MIN_SCALE!=1.25: return 1
	var static_state := {"static_native_required":true,"static_native_ready":false,"level":0,"blend":1.0}
	if readiness.state_ready(static_state): return 1
	static_state.static_native_ready=true
	if not readiness.state_ready(static_state): return 1
	var foundation := preload("res://scripts/rendering/tokyo_hlod_foundation.gd")
	var entry := {"key":"0:0","path":"mesh","texture_path":"image","max_scale":0.1944,
		"bytes":488,"triangles":[2,0,0],"boxes":[AABB(Vector3(-10000,0,-10000),Vector3(20000,0,20000)),AABB(),AABB()]}
	var row := {"depth":0,"parent":-1,"bounds":[-10000,-10000,10000,10000],"faces":2,
		"native_geometry":{"path":"mesh","bytes":100},"native_texture":{"path":"image","three_copy_charge":100}}
	var catalog := {"max_scale":0.1944,"bounds":Rect2(-10000,-10000,20000,20000),"roots":[entry],"rows":{"0:0":row}}
	var catalogs: Array[Dictionary]=[catalog]
	var plan := foundation.plan(catalogs)
	var failures := int(plan.is_empty())
	if plan.is_empty(): return failures
	var entries: Array[Dictionary]=plan.layers[0].entries
	failures+=int(foundation.catalog_at(plan,0.18)!=0 or foundation.catalog_at(plan,0.25)!=-1 or foundation.catalog_at(plan,NAN)!=-1)
	failures+=int(foundation.catalog_at(plan,0.18,1)!=-1 or foundation.catalog_at(plan,0.18,0)!=0)
	var cut := foundation.select(catalog,entries,Vector2.ZERO,0.18,0.2,Vector2(1600,900),488)
	failures+=int(cut.is_empty() or cut.get("bytes",0)!=488)
	var many := catalog.duplicate(true)
	many.rows={}
	var many_entries: Array[Dictionary]=[]
	for index in 17:
		var added := entry.duplicate(true)
		added.key="0:%d"%index
		many.rows[added.key]=row.duplicate(true)
		many_entries.append(added)
		if index==15:
			failures+=int(foundation.select(many,many_entries,Vector2.ZERO,0.18,0,Vector2(1600,900),192*1024*1024).is_empty())
	failures+=int(not foundation.select(many,many_entries,Vector2.ZERO,0.18,0,Vector2(1600,900),192*1024*1024).is_empty())
	catalog["range"]=[0.16,0.1944]
	var overlay := CommitOverlay.new()
	overlay._catalogs=catalogs;overlay._foundation=plan;overlay._pan_velocity=Vector2(100,0)
	failures+=int(not overlay._predict_prefetch(Vector2.ZERO,0.18,0,Vector2(1600,900)).is_empty() or overlay.foundation_prefetch_skips!=1)
	overlay.free()
	for scale: float in [0.16,0.1944001,NAN]:
		failures+=int(not foundation.select(catalog,entries,Vector2.ZERO,scale,0,Vector2(1600,900),488).is_empty())
	failures+=int(not foundation.select(catalog,entries,Vector2.ZERO,0.18,0,Vector2(1600,900),487).is_empty())
	row.faces=240001
	failures+=int(not foundation.select(catalog,entries,Vector2.ZERO,0.18,0,Vector2(1600,900),488).is_empty())
	row.faces=2;row.bounds=[-10000,-10000,-5000,10000]
	failures+=int(not foundation.select(catalog,entries,Vector2.ZERO,0.18,0,Vector2(1600,900),488).is_empty())
	entry.max_scale=0.18
	failures+=int(not foundation.plan(catalogs).is_empty())
	var middle_entry: Dictionary=entry.duplicate(true)
	middle_entry.max_scale=0.625
	var middle := {"max_scale":0.625,"roots":[{"children":[middle_entry]}]}
	var middle_catalogs: Array[Dictionary]=[middle]
	failures+=int(not foundation.plan(middle_catalogs,192*1024*1024).is_empty())
	middle["middle_massing_recipe"]={"path":"res://fixture/recipe.json","sha256":"a".repeat(64)}
	var middle_plan := foundation.plan(middle_catalogs,192*1024*1024)
	failures+=int(middle_plan.is_empty() or foundation.catalog_at(middle_plan,0.3)!=0 or foundation.catalog_at(middle_plan,0.24)!=-1)
	failures+=int(not foundation.plan(middle_catalogs,96*1024*1024).is_empty())
	middle.middle_massing_recipe.sha256="invalid"
	failures+=int(not foundation.plan(middle_catalogs,192*1024*1024).is_empty())
	var fine_leaf: Dictionary=entry.duplicate(true)
	fine_leaf.max_scale=1.25
	var fine: Dictionary={"max_scale":1.25,"roots":[{"children":[{"children":[fine_leaf]}]}]}
	var fine_catalogs: Array[Dictionary]=[fine]
	failures+=int(not foundation.plan(fine_catalogs,192*1024*1024).is_empty())
	failures+=int(not foundation.plan(fine_catalogs,192*1024*1024,true).is_empty())
	entry.max_scale=0.1944
	middle.middle_massing_recipe.sha256="a".repeat(64)
	var quarter_leaf: Dictionary=entry.duplicate(true)
	quarter_leaf.max_scale=0.25
	var complete_catalogs: Array[Dictionary]=[catalog,{"max_scale":0.25,"roots":[{"children":[quarter_leaf]}]},middle,fine]
	var complete_plan := foundation.plan(complete_catalogs,192*1024*1024,true)
	failures+=int(complete_plan.is_empty() or complete_plan.get("layers",{}).size()!=4 or foundation.catalog_at(complete_plan,1.0)!=3 or foundation.catalog_at(complete_plan,1.25001)!=-1)
	failures+=int(not foundation.plan(complete_catalogs,96*1024*1024,true).is_empty())
	fine_leaf.max_scale=0.625
	failures+=int(not foundation.plan(complete_catalogs,192*1024*1024,true).is_empty())
	fine.roots[0].children[0].children=[]
	failures+=int(not foundation.plan(complete_catalogs,192*1024*1024,true).is_empty())
	failures+=int(not preload("res://scripts/tests/build_tokyo_middle_massing.gd").checks())
	failures+=int(not preload("res://scripts/rendering/tokyo_hlod_prefetch_cache.gd").checks())
	var route_probe := preload("res://scripts/tests/tokyo_wasd_audit.gd")
	var anchors: Array[Vector2]=[]
	for route: String in ["northeast_edge","southwest_edge","northwest_edge","southeast_edge",
		"north_edge","south_edge","west_edge","east_edge"]:
		var anchor := route_probe.anchor_for_route(route)
		failures+=int(not anchor.is_finite() or anchor in anchors or maxf(absf(anchor.x),absf(anchor.y))!=16000.0)
		anchors.append(anchor)
	failures+=int(route_probe.anchor_for_route("northwest_edge")!=Vector2(-16000,-16000)
		or route_probe.anchor_for_route("southeast_edge")!=Vector2(16000,16000)
		or route_probe.anchor_for_route("")!=Vector2(-5600,-2900)
		or route_probe.anchor_for_route("misspelled_edge").is_finite())
	return failures


static func commit_ready_checks() -> int:
	if native_screen_bridge_checks()!=0: return 1
	for needed in [false,true]:
		for visible in [false,true]:
			for ready in [false,true]:
				if Stream.defer_speculative_upload(needed,visible,ready)!=(needed and not visible and ready): return 1
	var handoff := preload("res://scripts/rendering/tokyo_hlod_handoff.gd")
	var ledger_failures := 0
	var ledger_geometry := {"a":{"components":{"shared":{"bytes":17},"a":{"bytes":31}}},"b":{"components":{"shared":{"bytes":17},"b":{"bytes":13}}},"conflict":{"components":{"shared":{"bytes":18}}},"negative":{"bytes":-1}}
	var ledger_textures := {"x":{"charge":29},"y":{"charge":11},"negative":{"charge":-1}}
	for limit in range(0,180):
		var ledger := {"bytes":7,"meshes":{},"images":{}}
		var accepted_meshes := PackedStringArray()
		var accepted_images := PackedStringArray()
		for pair: Array in [["a","x"],["b","y"],["a","x"],["conflict",""],["missing","x"],["negative",""],["b","negative"],["b","missing"],["a",""]]:
			var proposed_meshes := accepted_meshes+PackedStringArray([pair[0]])
			var bundle_images := PackedStringArray() if String(pair[1]).is_empty() else PackedStringArray([pair[1]])
			var proposed_images := accepted_images+bundle_images
			var expected := handoff.streaming_bytes(ledger_geometry,ledger_textures,proposed_meshes,proposed_images,7)
			var before := ledger.duplicate(true)
			var accepted := handoff.append_streaming_bundle(ledger,ledger_geometry,ledger_textures,PackedStringArray([pair[0]]),bundle_images,limit)
			ledger_failures+=int(accepted!=(expected>=0 and expected<=limit))
			if accepted:
				accepted_meshes=proposed_meshes;accepted_images=proposed_images
				ledger_failures+=int(ledger.bytes!=expected)
			else: ledger_failures+=int(ledger!=before)
	# 增量与完整联合账本逐值对照；只读固定集及失败原子性独立核验。
	var fixed := {"bytes":0,"meshes":{},"images":{}}
	ledger_failures+=int(not handoff.append_streaming_bundle(fixed,ledger_geometry,ledger_textures,PackedStringArray(["a"]),PackedStringArray(["x"]),1000))
	var fixed_before := fixed.duplicate(true)
	for limit in range(0,100):
		for pair: Array in [["a","x"],["b","y"],["b","x"],["conflict","x"],["missing","x"],["negative","x"],["a","negative"]]:
			var meshes := PackedStringArray([pair[0],pair[0]])
			var images := PackedStringArray([pair[1],pair[1]])
			var expected := handoff.streaming_bytes(ledger_geometry,ledger_textures,PackedStringArray(["a"])+meshes,PackedStringArray(["x"])+images,7)
			if expected>=0: expected-=int(fixed.bytes)
			var delta := {"bytes":7,"meshes":{},"images":{}}
			var accepted := handoff.append_streaming_bundle(delta,ledger_geometry,ledger_textures,meshes,images,limit,fixed)
			ledger_failures+=int(accepted!=(expected>=0 and expected<=limit) or fixed!=fixed_before)
			ledger_failures+=int(delta.bytes!=expected if accepted else delta!={"bytes":7,"meshes":{},"images":{}})
	var fallback_catalogs: Array[Dictionary]=[{"range":[0.1,0.2]},{"range":[0.2,0.4]}]
	var fallback_failures := int(handoff.actual_fallback(fallback_catalogs,1,0.15,false)!=0)
	fallback_failures+=int(handoff.actual_fallback(fallback_catalogs,1,0.15,true)!=-1)
	fallback_failures+=int(handoff.actual_fallback(fallback_catalogs,0,0.15,false)!=-1)
	fallback_failures+=int(handoff.actual_fallback(fallback_catalogs,-2,0.15,false)!=-1)
	fallback_failures+=int(handoff.actual_fallback(fallback_catalogs,1,NAN,false)!=-1)
	var ground_entry := {"path":"a","mask":[true,false,false],"boxes":[AABB(Vector3.ZERO,Vector3(100,1,100)),AABB(),AABB(Vector3.ZERO,Vector3(100,0,100))]}
	var ground_failures := int(handoff.native_covers_view({"entries":[ground_entry]},Rect2(0,0,100,100)))
	ground_entry.mask[2]=true
	ground_failures+=int(not handoff.native_covers_view({"entries":[ground_entry]},Rect2(0,0,100,100)))
	ground_failures+=int(handoff.native_covers_view({"entries":[ground_entry]},Rect2(0,0,101,100)))
	ground_failures+=int(not handoff.native_covers_view({"entries":[ground_entry]},Rect2(0,0,100.00006,100)))
	ground_failures+=int(handoff.native_covers_view({"entries":[ground_entry]},Rect2(0,0,100.01,100)))
	var native_gate_failures := ledger_failures+foundation_checks()+fallback_failures+projection_equivalence_checks()+cache_pruning_checks()+ground_lease_pressure_checks()+int(handoff.native_preference({"within_budget":true},Stream.BUDGET+1))
	var leaf_builder := preload("res://scripts/tests/build_tokyo_lossless_leaf_partitions.gd")
	for invalid_depth: Variant in [0,3,1.5,NAN,{},"2"]:
		native_gate_failures+=int(leaf_builder.run({"split_depth":invalid_depth},"")!=1)
	var expiring := {"keys":PackedStringArray(["page"]),"configuration":"lod4_full","ground_images":PackedStringArray(["image"]),"ground_max_scale":1.25}
	native_gate_failures+=int(handoff.native_preference_qualified(expiring,1.24,0.5))
	native_gate_failures+=int(not handoff.native_preference_qualified(expiring,1.05,0.5))
	native_gate_failures+=int(not handoff.native_preference_qualified(expiring,1.24,-0.5))
	native_gate_failures+=int(not handoff.native_preference_qualified(expiring,1.25,0.0))
	native_gate_failures+=int(handoff.native_preference_qualified(expiring,1.251,0.0) or handoff.native_preference_qualified(expiring,1.0,NAN))
	native_gate_failures+=int(not handoff.pan_lead(Vector2(2400,0),1.0,0.35,Vector2(1600,900)).is_equal_approx(Vector2(840,0)))
	native_gate_failures+=int(not handoff.pan_lead(Vector2(10000,0),2.0,0.35,Vector2(1600,900)).is_equal_approx(Vector2(450,0)))
	native_gate_failures+=int(handoff.pan_lead(Vector2(10000,10000),2.0,0.35,Vector2(1600,900)).length()*2.0>900.001)
	native_gate_failures+=int(handoff.pan_lead(Vector2(10000,0),NAN,0.35,Vector2(1600,900))!=Vector2.ZERO)
	var reuse := CommitOverlay.new()
	# 几何覆盖仍完整但地表清晰度已过期：不得等50ms常规选页周期。
	reuse._lod_clock=0.05
	reuse._committed_catalog=-2
	reuse._committed=PackedStringArray(["expiring_ground"])
	reuse._committed_cut={"keys":reuse._committed,"configuration":"lod5_full","ground_max_scale":1.6666666667}
	native_gate_failures+=int(reuse._selection_due(true,1.66,false,false))
	native_gate_failures+=int(not reuse._selection_due(true,1.6743,false,false))
	native_gate_failures+=int(not reuse._selection_due(false,1.66,false,false))
	native_gate_failures+=int(not reuse._selection_due(true,1.66,true,false))
	reuse._committed_cut.erase("ground_max_scale")
	native_gate_failures+=int(reuse._selection_due(true,1.6743,false,false))
	reuse._committed=PackedStringArray();reuse._committed_cut={};reuse._committed_catalog=-1
	var valid_display := {"keys":PackedStringArray(["display"]),"within_budget":true,"triangles":240000,"bytes":Stream.BUDGET}
	var page_contract := preload("res://scripts/rendering/tokyo_hlod_manifest.gd")
	for bench in [false,true]:
		for candidate: String in ["","16","24","32","33","garbage"]:
			native_gate_failures+=int(page_contract.resolve_native_page_limit(bench,candidate)!=(32 if bench and candidate=="32" else 16))
	var expanded := valid_display.duplicate(true)
	expanded.keys=PackedStringArray(Array(range(32)).map(func(value: int) -> String: return str(value)))
	native_gate_failures+=int(handoff.retain_display(expanded,true,true,Stream.BUDGET))
	native_gate_failures+=int(not handoff.retain_display(expanded,true,true,Stream.BUDGET,32))
	native_gate_failures+=int(handoff.retain_display(expanded,false,true,Stream.BUDGET,32) or handoff.retain_display(expanded,true,false,Stream.BUDGET,32))
	expanded.keys.append("overflow")
	native_gate_failures+=int(handoff.retain_display(expanded,true,true,Stream.BUDGET,32))
	native_gate_failures+=int(not handoff.retain_display(valid_display,true,true,Stream.BUDGET))
	native_gate_failures+=int(handoff.retain_display(valid_display,false,true,Stream.BUDGET) or handoff.retain_display(valid_display,true,false,Stream.BUDGET))
	for invalid: Dictionary in [{"keys":PackedStringArray()},{"keys":PackedStringArray(Array(range(17)).map(func(value: int) -> String: return str(value)))},{"within_budget":false},{"triangles":240001},{"bytes":Stream.BUDGET+1}]:
		var rejected := valid_display.duplicate(true)
		rejected.merge(invalid,true)
		native_gate_failures+=int(handoff.retain_display(rejected,true,true,Stream.BUDGET))
	var native_probe := NativeSelectionProbe.new()
	# 走真实预测入口：缩远地表LOD4不能被提前细档LOD5的另一组资源顶替。
	var prediction := CommitOverlay.new()
	var prediction_source := NativeSelectionProbe.new()
	prediction._native=prediction_source
	for sample: Array in [[-1.92019585044351,"lod4_full","lod4_full"],[1.0,"lod4_full","lod5_full"],[-1.92019585044351,"","lod5_full"]]:
		prediction._zoom_rate=sample[0]
		prediction_source.ground_choice=sample[1]
		prediction_source.configurations.clear()
		var predicted: Dictionary=prediction._predict_prefetch(Vector2.ZERO,1.36044561862946,0.0,Vector2(1600,900))
		native_gate_failures+=int(predicted.is_empty() or prediction_source.configurations!=[sample[2]])
	prediction_source.response={}
	native_gate_failures+=int(not prediction._predict_prefetch(Vector2.ZERO,1.36044561862946,0.0,Vector2(1600,900)).is_empty())
	prediction.free()
	reuse._native=native_probe
	reuse._target={"keys":PackedStringArray(["retained"]),"configuration":"lod4_full","bytes":1,"spatial_guard_px":96}
	reuse._target_catalog=-2;reuse._committed_catalog=-2;reuse._committed=reuse._target.keys;reuse._committed_cut=reuse._target
	reuse.coverage_margin=60.0
	var retained := reuse._select_native(Vector2.ZERO,1.0,0.0,Vector2(1600,900))
	native_gate_failures+=int(retained.keys!=PackedStringArray(["retained"]) or native_probe.calls!=0)
	reuse._pan_velocity=Vector2(2400,0)
	var refreshed := reuse._select_native(Vector2.ZERO,1.0,0.0,Vector2(1600,900))
	native_gate_failures+=int(refreshed.keys!=PackedStringArray(["replacement"]) or native_probe.calls!=1)
	# 已批准的显示档传到真实原生选择入口；显式窄预算不能被默认档覆盖。
	for display: int in [Stream.BUDGET,2*Stream.BUDGET]:
		reuse.display_budget=display
		native_probe.budgets.clear()
		reuse._select_native(Vector2.ZERO,1.0,0,Vector2(1600,900),"",-1,false)
		native_gate_failures+=int(native_probe.budgets!=[display])
		native_probe.budgets.clear()
		reuse._select_native(Vector2.ZERO,1.0,0,Vector2(1600,900),"",Stream.BUDGET/2,false)
		native_gate_failures+=int(native_probe.budgets!=[Stream.BUDGET/2])
	reuse._committed=PackedStringArray()
	native_probe.minimum_budget=Stream.BUDGET+1
	native_probe.budgets.clear()
	var full_retry := reuse._select_native(Vector2.ZERO,1.0,0,Vector2(1600,900),"",Stream.BUDGET/2,false)
	native_gate_failures+=int(not full_retry.within_budget or native_probe.budgets!=[Stream.BUDGET/2,2*Stream.BUDGET])
	native_probe.empty_below_budget=true
	native_probe.budgets.clear()
	full_retry=reuse._select_native(Vector2.ZERO,1.0,0,Vector2(1600,900),"",Stream.BUDGET/2,false)
	native_gate_failures+=int(full_retry.is_empty() or not full_retry.within_budget or native_probe.budgets!=[Stream.BUDGET/2,2*Stream.BUDGET])
	native_probe.empty_below_budget=false
	native_probe.minimum_budget=0
	native_probe.response={"keys":PackedStringArray(["page"]),"configuration":"lod5_full","within_budget":true,"ground_images":PackedStringArray(["ground"]),"ground_max_scale":1.6666666667}
	reuse._zoom_rate=3.0
	native_gate_failures+=int(reuse._select_current_ground(Vector2.ZERO,1.3,0,Vector2(1600,900),Stream.BUDGET).is_empty())
	for invalid: Dictionary in [{"within_budget":false},{"ground_images":PackedStringArray()},{"ground_max_scale":1.25}]:
		var valid := native_probe.response.duplicate(true)
		native_probe.response.merge(invalid,true)
		native_gate_failures+=int(not reuse._select_current_ground(Vector2.ZERO,1.3,0,Vector2(1600,900),Stream.BUDGET).is_empty())
		native_probe.response=valid
	native_probe.ground_choice=""
	var before_calls := native_probe.calls
	native_gate_failures+=int(not reuse._select_current_ground(Vector2.ZERO,1.3,0,Vector2(1600,900),Stream.BUDGET).is_empty() or native_probe.calls!=before_calls)
	reuse.free()
	# 延迟页列表拼接必须与原逐组合拼接完全等价，包括稳定顺序、同费用和cap拒绝。
	var cut_solver := preload("res://scripts/experiments/tokyo_spatial_cut.gd")
	var huge_costs: Array[Array]=[[500000000000000000,1,9,0],[500000000000000000,0,10,1],[0,0,0,2]]
	native_gate_failures+=int(cut_solver._ordered_costs(huge_costs,32)!=[[0,0,0,2],[500000000000000000,0,10,1],[500000000000000000,1,9,0]])
	var rng := RandomNumberGenerator.new()
	rng.seed=0xA61
	for trial in 512:
		var left: Array[Dictionary]=[]
		var right: Array[Dictionary]=[]
		var cap := rng.randi_range(1,32)
		var byte_unit := 1073741824 if trial%2==0 else 1
		for index in rng.randi_range(0,32):
			left.append({"entries":["l%d"%index],"active":rng.randi_range(0,16),"faces":rng.randi_range(0,20),"bytes":rng.randi_range(0,20)*byte_unit})
			right.append({"entries":["r%d"%index],"active":rng.randi_range(0,16),"faces":rng.randi_range(0,20),"bytes":rng.randi_range(0,20)*byte_unit})
		var before := [left.duplicate(true),right.duplicate(true)]
		var reference: Array[Dictionary]=[]
		for a: Dictionary in left:
			for b: Dictionary in right:
				if a.active+b.active<=cap: cut_solver._insert(reference,{"entries":a.entries+b.entries,"active":a.active+b.active,"faces":a.faces+b.faces,"bytes":a.bytes+b.bytes})
		native_gate_failures+=int(cut_solver._combine(left,right,cap)!=reference or [left,right]!=before)
		var parent_state := {"entries":["parent"],"active":rng.randi_range(0,32),"faces":rng.randi_range(0,40),"bytes":rng.randi_range(0,40)*byte_unit}
		var merged: Array[Dictionary]=[parent_state]
		for state: Dictionary in reference: cut_solver._insert(merged,state)
		native_gate_failures+=int(cut_solver._merge_parent(parent_state,reference)!=merged)
	# 跨过旧131072回退门，后半批支配前半批及同费用身份都与逐项参考一致。
	var batch_left: Array[Dictionary]=[]
	var batch_right: Array[Dictionary]=[]
	for index in 365:
		batch_left.append({"entries":["bl%d"%index],"active":1,"faces":index%17,"bytes":(364-index)%13})
		batch_right.append({"entries":["br%d"%index],"active":1,"faces":index%19,"bytes":(364-index)%11})
	var batch_reference: Array[Dictionary]=[]
	for a: Dictionary in batch_left:
		for b: Dictionary in batch_right:
			cut_solver._insert(batch_reference,{"entries":a.entries+b.entries,"active":2,"faces":a.faces+b.faces,"bytes":a.bytes+b.bytes})
	native_gate_failures+=int(cut_solver._combine(batch_left,batch_right,32)!=batch_reference)
	var ground_selector := preload("res://scripts/rendering/tokyo_hlod_native.gd").new()
	# 两个地面三角分区可有同一个外接矩形；仅加载其中一个时矩形覆盖是假阳性。
	var floor_a := {"path":"floor_a","triangles":[0,0,1],"boxes":[AABB(),AABB(),AABB(Vector3.ZERO,Vector3(100,0,100))],"children":[],"mask":[false,false,true]}
	var floor_b: Dictionary=floor_a.duplicate(true)
	floor_b.path="floor_b"
	var floor_parent: Dictionary=floor_a.duplicate(true)
	floor_parent.path="parent";floor_parent.triangles=[0,0,2];floor_parent.children=[floor_a,floor_b]
	ground_selector._partition_roots={"lod5_full":[floor_parent]}
	var floor_cut := {"configuration":"lod5_full","entries":[floor_a]}
	var floor_view := Rect2(0,0,100,100)
	native_gate_failures+=int(not handoff.native_covers_view(floor_cut,floor_view))
	native_gate_failures+=int(ground_selector.covers_ground(floor_cut,floor_view,Transform2D.IDENTITY,Vector2(100,100)))
	floor_cut.entries=[floor_a,floor_b]
	native_gate_failures+=int(not ground_selector.covers_ground(floor_cut,floor_view,Transform2D.IDENTITY,Vector2(100,100)))
	floor_cut.entries=[floor_parent]
	native_gate_failures+=int(not ground_selector.covers_ground(floor_cut,floor_view,Transform2D.IDENTITY,Vector2(100,100)))
	floor_cut.entries=[floor_a];floor_b.boxes[2]=AABB(Vector3(200,0,0),Vector3(100,0,100))
	native_gate_failures+=int(not ground_selector.covers_ground(floor_cut,floor_view,Transform2D.IDENTITY,Vector2(100,100)))
	ground_selector.ground={"limits":{"lod3_full":0.75,"lod4_full":1.25}}
	# 反例：地面仍完整不代表原先裁掉的建筑层在平移后仍不可见。
	# 此处记录现有接口的证明边界，不把地面覆盖通过冒充建筑覆盖通过。
	var masked_page := {"path":"masked","triangles":[0,1,2],"boxes":[AABB(),AABB(Vector3(120,0,10),Vector3(20,20,20)),AABB(Vector3.ZERO,Vector3(300,0,100))],"children":[],"mask":[false,false,true]}
	ground_selector._partition_roots={"lod5_full":[masked_page]}
	var masked_cut := {"configuration":"lod5_full","entries":[masked_page]}
	var shifted_canvas := Transform2D.IDENTITY
	shifted_canvas.origin=Vector2(-100,0)
	var projection := preload("res://scripts/rendering/tokyo_cells_overlay.gd")
	var building_bounds := projection.projected_layer_bounds(masked_page.boxes[1],Vector2.ZERO,Vector2.ZERO)
	var initially_visible := projection.intersects_view(building_bounds,floor_view,Transform2D.IDENTITY,Vector2(100,100))
	var moved_visible := projection.intersects_view(building_bounds,Rect2(100,0,100,100),shifted_canvas,Vector2(100,100))
	var ground_retained := ground_selector.covers_ground(masked_cut,Rect2(100,0,100,100),shifted_canvas,Vector2(100,100))
	native_gate_failures+=int(initially_visible or not moved_visible or not ground_retained or masked_page.mask[1])
	print("[HLOD layer coverage counterexample] initial_building_visible=%s moved_building_visible=%s ground_accepted=%s building_mask=%s"%[initially_visible,moved_visible,ground_retained,masked_page.mask[1]])
	native_gate_failures+=int(ground_selector.covers_visible_layers(masked_cut,Rect2(100,0,100,100),shifted_canvas,Vector2(100,100)))
	var gap_audit := preload("res://scripts/tests/tokyo_wasd_audit.gd")
	var detail := gap_audit.layer_gaps([masked_page],masked_cut,Rect2(100,0,100,100),shifted_canvas,Vector2(100,100))
	native_gate_failures+=int(detail.missing_leaves.size()!=1 or detail.missing_leaves[0].path!="masked" or detail.missing_leaves[0].layer!=1 or detail.entries[0].mask!=[false,false,true])
	masked_page.mask[1]=true
	native_gate_failures+=int(not ground_selector.covers_visible_layers(masked_cut,Rect2(100,0,100,100),shifted_canvas,Vector2(100,100)))
	native_gate_failures+=int(not gap_audit.layer_gaps([masked_page],masked_cut,Rect2(100,0,100,100),shifted_canvas,Vector2(100,100)).missing_leaves.is_empty())
	# 层级选择必须逐层完整；仅同AABB的一个子页不能替代另一个。
	var masked_child: Dictionary=masked_page.duplicate(true)
	masked_child.path="masked_child"
	var other_child: Dictionary=masked_child.duplicate(true)
	other_child.path="other_child"
	masked_page.children=[masked_child,other_child]
	masked_cut.entries=[masked_child]
	native_gate_failures+=int(ground_selector.covers_visible_layers(masked_cut,Rect2(100,0,100,100),shifted_canvas,Vector2(100,100)))
	masked_cut.entries=[masked_child,other_child]
	native_gate_failures+=int(not ground_selector.covers_visible_layers(masked_cut,Rect2(100,0,100,100),shifted_canvas,Vector2(100,100)))
	masked_cut.entries=[masked_page]
	native_gate_failures+=int(not ground_selector.covers_visible_layers(masked_cut,Rect2(100,0,100,100),shifted_canvas,Vector2(100,100)))
	masked_page.mask[1]=false
	native_gate_failures+=int(ground_selector.covers_visible_layers(masked_cut,Rect2(100,0,100,100),shifted_canvas,Vector2(100,100)))
	ground_selector._ground_roots={"lod3_full":[],"lod4_full":[]}
	for sample: Array in [[0.2,""],[0.4,""],[0.4001,"lod3_full"],[0.75,"lod3_full"],[0.7501,"lod4_full"],[1.25,"lod4_full"],[1.2501,""],[NAN,""]]:
		native_gate_failures+=int(ground_selector.ground_configuration(sample[0])!=sample[1])
	var policy := preload("res://scripts/rendering/tokyo_hlod_cache_policy.gd")
	for sample: Array in [[false,10240,1536,96],[true,0,1536,96],[true,8191,1536,96],[true,8192,1536,192],[true,10240,768,96],[true,10240,96,96],[true,10240,3072,192],[true,8191,3072,96]]:
		native_gate_failures+=int(policy.display_bytes(sample[0],sample[1],sample[2]*policy.MIB)!=sample[3]*policy.MIB)
	var display_solver := preload("res://scripts/experiments/tokyo_spatial_cut.gd")
	var display_frontier: Array[Dictionary]=[{"entries":[],"active":4,"faces":198770,"bytes":153*policy.MIB}]
	var display_state := {"frontier":display_frontier,"visited":4,"solver_usec":0}
	# 扩大的是内存，不是面数；失格/缺页哨兵必须仍被192MiB拒绝。
	native_gate_failures+=int(display_solver.pick(display_state,96*policy.MIB).within_budget)
	native_gate_failures+=int(not display_solver.pick(display_state,192*policy.MIB).within_budget)
	display_state.frontier[0].faces=240001
	native_gate_failures+=int(display_solver.pick(display_state,192*policy.MIB).within_budget)
	display_state.frontier[0].faces=1
	display_state.frontier[0].bytes=policy.MAX_DISPLAY+1
	native_gate_failures+=int(display_solver.pick(display_state,policy.MAX_DISPLAY).within_budget)
	for example: Array in [[0,16384,384],[-1,16384,384],[4095,16384,384],[4096,16384,768],[8191,16384,768],[8192,16384,1536],[10240,0,384],[10240,4095,384],[10240,4096,768],[10240,8192,1536]]:
		native_gate_failures+=int(policy.pool_bytes(example[0],example[1])!=example[2]*policy.MIB)
	for example: Array in [[false,10240,16384,0],[true,0,16384,0],[true,10239,16384,0],[true,10240,7167,0],[true,10240,7168,3072]]:
		native_gate_failures+=int(policy.static_pool_bytes(example[0],example[1],example[2])!=example[3]*policy.MIB)
	for example: Array in [[false,10240,16384,0],[true,0,16384,0],[true,10239,16384,0],[true,10240,7679,0],[true,10240,7680,4096]]:
		native_gate_failures+=int(policy.complete_pool_bytes(example[0],example[1],example[2])!=example[3]*policy.MIB)
	native_gate_failures+=int(policy.display_bytes(true,10240,policy.COMPLETE_POOL)!=192*policy.MIB)
	var warm_plan := {"meshes":PackedStringArray(),"images":PackedStringArray(),"bytes":0}
	var warm_geometry := {"a":{"bytes":40},"b":{"bytes":80}}
	var warm_images := {"t":{"charge":30}}
	native_gate_failures+=int(not policy.append_bundle(warm_plan,PackedStringArray(["a"]),PackedStringArray(["t"]),warm_geometry,warm_images,70))
	native_gate_failures+=int(not policy.append_bundle(warm_plan,PackedStringArray(["a","a"]),PackedStringArray(["t"]),warm_geometry,warm_images,70))
	native_gate_failures+=int(warm_plan.bytes!=70 or warm_plan.meshes.size()!=1)
	var preserved_plan := warm_plan.duplicate(true)
	native_gate_failures+=int(policy.append_bundle(warm_plan,PackedStringArray(["b"]),PackedStringArray(),warm_geometry,warm_images,149))
	native_gate_failures+=int(policy.append_bundle(warm_plan,PackedStringArray(["missing"]),PackedStringArray(),warm_geometry,warm_images,1000))
	native_gate_failures+=int(warm_plan!=preserved_plan)
	native_gate_failures+=int(not handoff.native_preference({"within_budget":true},1536*policy.MIB,1536*policy.MIB))
	native_gate_failures+=int(handoff.native_preference({"within_budget":true},0,1536*policy.MIB+1))
	native_gate_failures+=int(not handoff.native_preference({"within_budget":true},Stream.BUDGET+1,4*Stream.BUDGET))
	native_gate_failures+=int(handoff.native_preference({"within_budget":true},4*Stream.BUDGET+1,4*Stream.BUDGET))
	native_gate_failures+=int(handoff.native_preference({"within_budget":false},Stream.BUDGET,4*Stream.BUDGET))
	native_gate_failures+=ground_failures
	native_gate_failures+=int(handoff.prefetch_changed({}, {"prefetch_keys":PackedStringArray()},4))
	native_gate_failures+=int(not handoff.prefetch_changed({}, {"guard_prefetch_keys":["guard"]},4))
	native_gate_failures+=int(handoff.prefetch_changed({}, {"guard_prefetch_keys":PackedStringArray()},4))
	var guard_catalogs: Array[Dictionary]=[{"rows":{"same":{"native_geometry":{"path":"edge"},"native_texture":{"path":"edge_image"}}}},{"rows":{"same":{"native_geometry":{"path":"future"},"native_texture":{"path":"future_image"}}}}]
	var guarded_cut := {"guard_prefetch_keys":["same"],"prefetch_catalog":1,"prefetch_keys":["same"]}
	var guard_requests: Array[Dictionary]=handoff.prefetch_requests(guard_catalogs,guarded_cut,0)
	native_gate_failures+=int(guard_requests!=[{"mesh":"future","image":"future_image"},{"mesh":"edge","image":"edge_image"}])
	guarded_cut.prefetch_keys=[]
	native_gate_failures+=int(handoff.prefetch_requests(guard_catalogs,guarded_cut,0)!=[{"mesh":"edge","image":"edge_image"}])
	native_gate_failures+=int(handoff.prefetch_requests([], {"guard_prefetch_keys":["mesh"],"prefetch_keys":["next"]},-2)!=[{"mesh":"next","image":""},{"mesh":"mesh","image":""}])
	native_gate_failures+=int(not handoff.prefetch_changed({}, {"prefetch_keys":PackedStringArray(["a"])},4))
	native_gate_failures+=int(not handoff.prefetch_changed({"prefetch_keys":PackedStringArray(["a"])},{},4))
	native_gate_failures+=int(handoff.prefetch_changed({"prefetch_keys":["a"]},{"prefetch_keys":PackedStringArray(["a"])},4))
	native_gate_failures+=int(not handoff.prefetch_changed({"prefetch_catalog":4},{"prefetch_catalog":5},4))
	var texture_order := preload("res://scripts/rendering/tokyo_hlod_stream.gd").ordered_texture_jobs({"old":{},"prediction":{},"visible":{}},PackedStringArray(["visible","prediction","visible"]))
	native_gate_failures+=int(texture_order!=PackedStringArray(["visible","prediction","old"]))
	native_gate_failures+=int(handoff.prefetch_changed({}, {"prefetch_extra":[]},4))
	native_gate_failures+=int(not handoff.prefetch_changed({}, {"prefetch_extra":[{"mesh":"b","image":"t"}]},4))
	native_gate_failures+=int(handoff.prefetch_changed({"prefetch_extra":[{"mesh":"b","image":"t"}]},{"prefetch_extra":[{"mesh":"b","image":"t"}]},4))
	native_gate_failures+=int(handoff.zoom_direction(1.0,1.000001)!=0 or handoff.zoom_direction(1.0,0.999999)!=0)
	native_gate_failures+=int(handoff.zoom_direction(1.0,1.01)!=1 or handoff.zoom_direction(1.0,0.99)!=-1)
	native_gate_failures+=int(handoff.zoom_direction(0.0,1.0)!=0 or handoff.zoom_direction(1.0,NAN)!=0)
	# 原平滑在相机已反向时仍预测旧方向：先固定反例，再验证实际消费函数。
	native_gate_failures+=int(lerpf(-4.0,log(1.02)*60.0,0.4)>=0.0)
	native_gate_failures+=int(handoff.prediction_zoom_rate(-4.0,1.02,1.0/60.0)<=0.0)
	native_gate_failures+=int(handoff.prediction_zoom_rate(4.0,0.98,1.0/60.0)>=0.0)
	native_gate_failures+=int(not is_equal_approx(handoff.prediction_zoom_rate(4.0,1.02,1.0/60.0),lerpf(4.0,log(1.02)*60.0,0.4)))
	native_gate_failures+=int(handoff.prediction_zoom_rate(4.0,0.999999,1.0/60.0)<=0.0)
	native_gate_failures+=int(not is_equal_approx(handoff.prediction_zoom_rate(4.0,2.0,1.0/60.0),2.4))
	native_gate_failures+=int(handoff.prediction_zoom_rate(4.0,1.02,0.0)!=0.0 or handoff.prediction_zoom_rate(4.0,NAN,0.1)!=0.0)
	# 原生缩远预测越过1.25常驻边界时，先取边界近侧，防止提前停止图片预取。
	native_gate_failures+=int(not is_equal_approx(handoff.native_exit_checkpoint(1.77448,1.11,1.25),1.25125))
	native_gate_failures+=int(handoff.native_exit_checkpoint(1.2501,1.1,1.25)!=1.2501)
	native_gate_failures+=int(handoff.native_exit_checkpoint(1.7,1.4,1.25)!=1.4)
	native_gate_failures+=int(handoff.native_exit_checkpoint(1.2,1.1,1.25)!=1.1)
	native_gate_failures+=int(handoff.native_exit_checkpoint(1.2,1.8,1.25)!=1.8)
	native_gate_failures+=int(handoff.native_exit_checkpoint(NAN,1.1,1.25)!=1.1)
	native_gate_failures+=int(handoff.native_exit_checkpoint(1.7,1.1,0.0)!=1.1)
	# 可见节点不代表完整覆盖：单个透明像素也必须被边缘验收发现。
	var edge_audit := preload("res://scripts/tests/tokyo_hlod_edge_audit.gd")
	var coverage_image := Image.create(2,2,false,Image.FORMAT_RGBA8)
	coverage_image.fill(Color.WHITE)
	native_gate_failures+=int(edge_audit.alpha_coverage(coverage_image).uncovered_pixels!=0)
	coverage_image.set_pixel(0,0,Color.TRANSPARENT)
	var coverage: Dictionary=edge_audit.alpha_coverage(coverage_image)
	native_gate_failures+=int(coverage.uncovered_pixels!=1 or coverage.uncovered_fraction!=0.25)
	coverage_image.set_pixel(0,0,Color(1,1,1,250.0/255.0))
	native_gate_failures+=int(edge_audit.alpha_coverage(coverage_image).uncovered_pixels!=0)
	coverage_image.set_pixel(0,0,Color(1,1,1,249.0/255.0))
	native_gate_failures+=int(edge_audit.alpha_coverage(coverage_image).uncovered_pixels!=1)
	var audit_stream := Stream.new()
	audit_stream.visible_io_first=true
	audit_stream.visible_meshes=PackedStringArray(["required"])
	audit_stream.visible_images=PackedStringArray(["visible_image"])
	native_gate_failures+=int(audit_stream.can_start_image("prediction"))
	native_gate_failures+=int(not audit_stream.can_start_image("visible_image"))
	audit_stream._pending["required"]=0
	native_gate_failures+=int(not audit_stream.can_start_image("prediction"))
	audit_stream._pending.clear()
	audit_stream._cache["required"]={}
	native_gate_failures+=int(not audit_stream.can_start_image("prediction"))
	audit_stream._cache.clear()
	audit_stream._failures["required"]="test"
	native_gate_failures+=int(not audit_stream.can_start_image("prediction"))
	audit_stream._failures.clear()
	audit_stream.visible_io_first=false
	native_gate_failures+=int(not audit_stream.can_start_image("prediction"))
	audit_stream._texture_descriptors={"image":{"sha256":"a".repeat(64),"charge":100,"mip_bytes":32,"width":4,"height":4}}
	audit_stream.visible_images=PackedStringArray(["image"])
	audit_stream._request_limit=8
	audit_stream.fair_image_slot=false
	native_gate_failures+=int(audit_stream.image_slot_reserve()!=0)
	audit_stream.fair_image_slot=true
	native_gate_failures+=int(audit_stream.image_slot_reserve()!=1)
	audit_stream._textures["image"]={}
	native_gate_failures+=int(audit_stream.image_slot_reserve()!=0)
	audit_stream._textures.clear()
	audit_stream._texture_jobs["image"]={}
	native_gate_failures+=int(audit_stream.image_slot_reserve()!=0)
	audit_stream._texture_jobs.clear()
	audit_stream._request_limit=1
	native_gate_failures+=int(audit_stream.image_slot_reserve()!=0)
	audit_stream._request_limit=8
	audit_stream._audit_texture("image","upload",20)
	native_gate_failures+=int(not audit_stream._texture_audit.is_empty())
	audit_stream._audit_paths=true
	audit_stream._audit_texture("image","request")
	audit_stream._audit_texture("image","upload",20)
	audit_stream._audit_texture("image","budget_retire")
	audit_stream._audit_texture("image","retired")
	audit_stream._audit_texture("image","upload",10)
	native_gate_failures+=int(audit_stream._texture_audit.image.upload!=2 or audit_stream._texture_audit.image.max_upload_usec!=20)
	native_gate_failures+=int(audit_stream._texture_audit.image.retired!=1 or audit_stream._texture_audit.image.budget_retire!=1)
	audit_stream.free()
	var component := preload("res://scripts/rendering/tokyo_component_stream.gd").new()
	component._logical={"a":{"components":{"shared":{},"left":{}}},"b":{"components":{"right":{},"shared":{}}}}
	native_gate_failures+=int(component._paths(PackedStringArray(["a","b","a","plain"]))!=PackedStringArray(["shared","left","right","plain"]))
	native_gate_failures+=int(not component._paths(PackedStringArray()).is_empty())
	component.free()
	var contract := preload("res://scripts/rendering/tokyo_hlod_manifest.gd")
	var upload_catalog := {"rows":{"root":{"native_texture":{"mip_bytes":5*1024*1024}},"a":{"native_texture":{"mip_bytes":1024}},"b":{"native_texture":{"mip_bytes":1024}}}}
	var child_a := {"key":"a","triangles":[100,0,0],"boxes":[AABB(Vector3.ZERO,Vector3(40,0,40)),AABB(),AABB()],"bytes":110}
	var child_b := child_a.duplicate(true);child_b.key="b"
	var root := {"key":"root","faces":199,"bytes":200,"children":[child_a,child_b]}
	var original := {"entries":[root],"triangles":199,"bytes":200,"active":1,"solver_usec":0,"within_budget":true}
	var split: Dictionary = contract.split_large_uploads(original,upload_catalog,Rect2(0,0,100,100),Transform2D.IDENTITY,Vector2(100,100),Vector2.ZERO,220)
	native_gate_failures+=int(split.active!=2 or split.triangles!=200 or split.bytes!=220 or original.entries.size()!=1)
	var blocked: Dictionary = contract.split_large_uploads(original,upload_catalog,Rect2(0,0,100,100),Transform2D.IDENTITY,Vector2(100,100),Vector2.ZERO,219)
	native_gate_failures+=int(blocked.active!=1)
	child_a.bytes=Stream.BUDGET+1
	blocked=contract.split_large_uploads(original,upload_catalog,Rect2(0,0,100,100),Transform2D.IDENTITY,Vector2(100,100),Vector2.ZERO,Stream.BUDGET)
	native_gate_failures+=int(blocked.active!=1)
	child_a.bytes=110;child_a.triangles[0]=240001
	blocked=contract.split_large_uploads(original,upload_catalog,Rect2(0,0,100,100),Transform2D.IDENTITY,Vector2(100,100),Vector2.ZERO,Stream.BUDGET)
	native_gate_failures+=int(blocked.active!=1)
	var catalog := contract.normalize(preload("res://scripts/tests/test_tokyo_hlod_manifest.gd").fixture())
	# 失败选择必须保持空值；附加诊断键不能把无within_budget的空结果伪装成有效切面。
	var selection_overlay := CommitOverlay.new()
	var invalid_cut := selection_overlay._select_hlod(catalog,Vector2.ZERO,float(catalog.max_scale)+0.1,0.0,Vector2(160,90))
	native_gate_failures+=int(not invalid_cut.is_empty())
	selection_overlay.free()
	var cached_cut := preload("res://scripts/rendering/tokyo_hlod_cached_cut.gd")
	var ordered_catalogs: Array[Dictionary]=[{"max_scale":0.1},{"max_scale":0.5},{"max_scale":0.2},{"max_scale":1.0}]
	native_gate_failures+=int(cached_cut.candidate_catalogs(ordered_catalogs,3,1,0.15)!=PackedInt32Array([3,1,2]))
	native_gate_failures+=int(cached_cut.candidate_catalogs(ordered_catalogs,0,0,0.15)!=PackedInt32Array([2]))
	# 原生目标没有HLOD目录号，但仍必须尝试合格的已显示档与最近缓存档。
	native_gate_failures+=int(cached_cut.candidate_catalogs(ordered_catalogs,-2,1,0.15)!=PackedInt32Array([1,2]))
	native_gate_failures+=int(not cached_cut.candidate_catalogs(ordered_catalogs,1,0,NAN).is_empty())
	native_gate_failures+=int(not cached_cut.candidate_catalogs(ordered_catalogs,1,0,2.0).is_empty())
	var cached_meshes := {}
	var cached_images := {}
	for row: Dictionary in catalog.rows.values():
		cached_meshes[row.native_geometry.path]={}
		cached_images[row.native_texture.path]={}
	var resident_cut := cached_cut.select(catalog,Vector2.ZERO,0.08,0.0,Vector2(160,90),{},cached_meshes,cached_images)
	native_gate_failures+=int(resident_cut.is_empty() or not resident_cut.within_budget)
	native_gate_failures+=int(not cached_cut.select(catalog,Vector2.ZERO,float(catalog.max_scale)+0.01,0.0,Vector2(160,90),{},cached_meshes,cached_images).is_empty())
	native_gate_failures+=int(not cached_cut.select(catalog,Vector2.ZERO,NAN,0.0,Vector2(160,90),{},cached_meshes,cached_images).is_empty())
	native_gate_failures+=int(not cached_cut.select(catalog,Vector2(1000000,1000000),0.08,0.0,Vector2(160,90),{},cached_meshes,cached_images).is_empty())
	native_gate_failures+=int(not cached_cut.select(catalog,Vector2.ZERO,0.08,0.0,Vector2(160,90),{},cached_meshes,{}).is_empty())
	for entry: Dictionary in catalog.roots: cached_meshes.erase(entry.path)
	resident_cut=cached_cut.select(catalog,Vector2.ZERO,0.08,0.0,Vector2(160,90),{},cached_meshes,cached_images)
	native_gate_failures+=int(resident_cut.is_empty())
	for entry: Dictionary in resident_cut.get("entries",[]): native_gate_failures+=int(not cached_meshes.has(entry.path))
	var root_keys := PackedStringArray()
	for entry: Dictionary in catalog.roots: root_keys.append(entry.key)
	var root_cut := {"keys":root_keys,"entries":catalog.roots}
	var visible_old := contract.visible_subset(catalog,root_cut,Vector2.ZERO,0.08,0.2,Vector2(160,90))
	native_gate_failures+=int(visible_old.is_empty() or not visible_old.within_budget or visible_old.keys.is_empty() or visible_old.keys.size()>=root_keys.size())
	for key: String in visible_old.get("keys",PackedStringArray()): native_gate_failures+=int(not key in root_keys)
	for entry: Dictionary in visible_old.get("entries",[]): native_gate_failures+=int(entry.has("children"))
	native_gate_failures+=int(not catalog.roots[0].has("children"))
	# 原地面离屏但楼体投影仍可见时，必须保留该已载入页，不能只按地块矩形裁切。
	var raised_cut := root_cut.duplicate(true)
	raised_cut.entries[0].boxes[0]=raised_cut.entries[0].boxes[0].merge(AABB(Vector3(-100,0,-100),Vector3(200,8,200)))
	var raised_old := contract.visible_subset(catalog,raised_cut,Vector2.ZERO,0.08,0.0,Vector2(160,90))
	native_gate_failures+=int(not root_keys[0] in raised_old.get("keys",PackedStringArray()))
	native_gate_failures+=int(not contract.visible_subset(catalog,root_cut,Vector2.ZERO,0.2,0.0,Vector2(160,90)).is_empty())
	child_a.triangles[0]=100
	var full := original.duplicate(true)
	for n in 15:
		var leaf := child_b.duplicate(true)
		leaf.key="leaf%d" % n;leaf["faces"]=100
		upload_catalog.rows[leaf.key]={"native_texture":{"mip_bytes":1024}}
		full.entries.append(leaf)
	full.active=16;full.triangles=1699;full.bytes=1850
	blocked=contract.split_large_uploads(full,upload_catalog,Rect2(0,0,100,100),Transform2D.IDENTITY,Vector2(100,100),Vector2.ZERO,Stream.BUDGET)
	native_gate_failures+=int(blocked.active!=16 or blocked.entries[0].key!="root")
	upload_catalog.rows.root.native_texture.mip_bytes=4*1024*1024
	blocked=contract.split_large_uploads(original,upload_catalog,Rect2(0,0,100,100),Transform2D.IDENTITY,Vector2(100,100),Vector2.ZERO,Stream.BUDGET)
	native_gate_failures+=int(blocked.active!=1)
	catalog["identity"]={"sha256":"a".repeat(64)}
	var work: Dictionary = {}
	for budget: int in [0,48*1024*1024,96*1024*1024]:
		var expected := contract.select(catalog,Vector2.ZERO,0.08,0.2,Vector2(1600,900),true,budget)
		var actual := contract.select(catalog,Vector2.ZERO,0.08,0.2,Vector2(1600,900),true,budget,work)
		expected.erase("solver_usec");actual.erase("solver_usec")
		native_gate_failures+=int(actual!=expected)
	native_gate_failures+=int(work.get("builds")!=1 or work.get("reuses")!=2)
	contract.select(catalog,Vector2.ONE,0.08,0.2,Vector2(1600,900),true,Stream.BUDGET,work)
	native_gate_failures+=int(work.get("builds")!=2)
	work.frame=-1
	contract.select(catalog,Vector2.ONE,0.08,0.2,Vector2(1600,900),true,Stream.BUDGET,work)
	native_gate_failures+=int(work.get("builds")!=3)
	catalog.identity.sha256="b".repeat(64)
	contract.select(catalog,Vector2.ONE,0.08,0.2,Vector2(1600,900),true,Stream.BUDGET,work)
	native_gate_failures+=int(work.get("builds")!=4)
	contract.select(catalog,Vector2.ONE,0.08,0.2,Vector2(1600,900),false,Stream.BUDGET,work)
	native_gate_failures+=int(work.get("builds")!=5)
	# A→B→A：中间保护带不能顶掉同帧A；不同预算仍与无缓存结果逐项一致。
	var memo_builds: int=work.builds
	var memo_cut := contract.select(catalog,Vector2.ONE,0.08,0.2,Vector2(1600,900),true,0,work)
	var uncached_cut := contract.select(catalog,Vector2.ONE,0.08,0.2,Vector2(1600,900),true,0)
	memo_cut.erase("solver_usec");uncached_cut.erase("solver_usec")
	native_gate_failures+=int(work.builds!=memo_builds or memo_cut!=uncached_cut)
	for n in 32:
		contract.select(catalog,Vector2(n+10,0),0.08,0.2,Vector2(160,90),true,0,work)
	native_gate_failures+=int(work.solutions.size()!=contract.FRAME_SOLUTIONS)
	work.frame=-1
	contract.select(catalog,Vector2.ONE,0.08,0.2,Vector2(160,90),true,0,work)
	native_gate_failures+=int(work.solutions.size()!=1)
	var native := preload("res://scripts/rendering/tokyo_hlod_native.gd").new()
	native.catalog=preload("res://scripts/rendering/tokyo_canonical_catalog.gd").new()
	var box := AABB(Vector3(-50,0,-50),Vector3(100,10,100))
	var child := {"path":"child","key":"child","boxes":[box,AABB(),AABB()],"triangles":PackedInt32Array([100,0,0]),"bytes":200}
	var parent := {"path":"parent","key":"parent","boxes":[box,AABB(),AABB()],"triangles":PackedInt32Array([400,0,0]),"bytes":100,"children":[child]}
	native.catalog.configurations={"lod0_full":[parent],"lod1_full":[parent]}
	var first := native.select(Vector2.ZERO,1,0,Vector2(100,100),"lod0_full",150)
	var second := native.select(Vector2.ZERO,1,0,Vector2(100,100),"lod0_full",250)
	native_gate_failures+=int(first.keys!=PackedStringArray(["parent"]) or second.keys!=PackedStringArray(["child"]))
	native_gate_failures+=int(native.solver_builds!=1 or native.solver_reuses!=1)
	second.entries.clear()
	native_gate_failures+=int(native.select(Vector2.ZERO,1,0,Vector2(100,100),"lod0_full",250).keys!=PackedStringArray(["child"]))
	for args: Array in [[Vector2.ONE,1,0,Vector2(100,100),"lod0_full"],[Vector2.ONE,2,0,Vector2(100,100),"lod0_full"],[Vector2.ONE,2,0.1,Vector2(100,100),"lod0_full"],[Vector2.ONE,2,0.1,Vector2(120,100),"lod0_full"],[Vector2.ONE,2,0.1,Vector2(120,100),"lod1_full"]]:
		var builds := native.solver_builds
		native.select(args[0],args[1],args[2],args[3],args[4],250)
		native_gate_failures+=int(native.solver_builds!=builds+1)
	var builds := native.solver_builds
	native._selection_frame=-1
	native.select(Vector2.ONE,2,0.1,Vector2(120,100),"lod1_full",250)
	native_gate_failures+=int(native.solver_builds!=builds+1)
	native.select(Vector2.ZERO,1,0,Vector2(100,100),"lod0_full",150)
	var native_memo_builds: int=native.solver_builds
	var native_memo := native.select(Vector2.ONE,2,0.1,Vector2(120,100),"lod1_full",250)
	native_gate_failures+=int(native.solver_builds!=native_memo_builds or native_memo.configuration!="lod1_full")
	for n in 32: native.select(Vector2(n+10,0),1,0,Vector2(100,100),"lod0_full",150)
	native_gate_failures+=int(native._selection_solutions.size()!=contract.FRAME_SOLUTIONS)
	native.read(null)
	native_gate_failures+=int(not native._selection_solutions.is_empty())
	var session := preload("res://scripts/rendering/tokyo_volume_preload.gd")
	var state := {"stream":{"pending":0,"failures":{},"residency_ready":false},"desired_cells":1,"ready_cells":1,"cut_ready":true,"active_cells":1}
	native_gate_failures+=int(session.state_ready(state))
	state.stream.residency_ready=true
	native_gate_failures+=int(not session.state_ready(state))
	var candidate := Stream.new()
	var owner_node := Node.new()
	var neighborhood_geometry := {"warm_mesh":{"sha256":"a".repeat(64),"bytes":10}}
	var neighborhood_textures := {"image":{"sha256":"a".repeat(64),"width":4,"height":4,"format":Image.FORMAT_DXT5,"mip_bytes":48,"charge":4240}}
	neighborhood_textures["warm_image"]=neighborhood_textures.image.duplicate()
	candidate.configure_hlod(owner_node,neighborhood_geometry,neighborhood_textures)
	native_gate_failures+=int(candidate.geometry_budget()!=Stream.BUDGET)
	native_gate_failures+=int(candidate.configure_residency(PackedStringArray(),PackedStringArray(["missing"])))
	native_gate_failures+=int(not candidate.configure_residency(PackedStringArray(),PackedStringArray(["image"])))
	native_gate_failures+=int(candidate.residency_ready() or candidate.residency_bytes!=4240 or candidate.geometry_budget()!=384*1024*1024)
	native_gate_failures+=int(candidate.configure_residency(PackedStringArray(),PackedStringArray(["image"])))
	native_gate_failures+=int(candidate.configure_residency(PackedStringArray(),PackedStringArray(["warm_image"]),384*1024*1024,true))
	native_gate_failures+=int(candidate.configure_residency(PackedStringArray(),PackedStringArray(["image","warm_image"]),768*1024*1024,true))
	var warming := LoadingOverlay.new()
	warming._stream=candidate;warming._geometry=neighborhood_geometry;warming._textures=neighborhood_textures;warming.cache_pool_limit=384*1024*1024
	warming.prepare_loading_neighborhood(Vector2.ZERO,1.0,Vector2(1600,900))
	native_gate_failures+=int(not warming.loading_neighborhood or warming.loading_neighborhood_bytes!=4250 or candidate.residency_bytes!=8490)
	native_gate_failures+=int(candidate.residency_images!=PackedStringArray(["image","warm_image"]) or candidate.residency_meshes!=PackedStringArray(["warm_mesh"]))
	warming.release_loading_neighborhood()
	native_gate_failures+=int(warming.loading_neighborhood or candidate.residency_bytes!=4240 or candidate.residency_images!=PackedStringArray(["image"]) or not candidate.residency_meshes.is_empty())
	warming._stream=null;warming.free()
	candidate.close()
	native_gate_failures+=int(not candidate.residency_images.is_empty() or candidate.residency_bytes!=0)
	candidate.free();owner_node.free()
	var coverage_catalog := {"rows":{"left":{"bounds":[0,0,5,10]},"right":{"bounds":[5,0,10,10]},"island":{"bounds":[2,2,8,8]}}}
	var view := Rect2(0,0,10,10)
	native_gate_failures+=int(handoff.covers_view(coverage_catalog,{"keys":PackedStringArray(["island"])},view))
	native_gate_failures+=int(handoff.covers_view(coverage_catalog,{"keys":PackedStringArray(["left"])},view))
	native_gate_failures+=int(not handoff.covers_view(coverage_catalog,{"keys":PackedStringArray(["left","right"])},view))
	native_gate_failures+=int(handoff.covers_view(coverage_catalog,{"keys":PackedStringArray(["left","right"])},Rect2(-1,0,11,10)))
	coverage_catalog["max_scale"]=0.25
	var grace_cut := {"keys":PackedStringArray(["left","right"])}
	native_gate_failures+=int(not handoff.display_grace(coverage_catalog,grace_cut,0.26,100,view))
	native_gate_failures+=int(handoff.display_grace(coverage_catalog,grace_cut,0.26,101,view))
	native_gate_failures+=int(handoff.display_grace(coverage_catalog,grace_cut,0.276,0,view))
	native_gate_failures+=int(handoff.display_grace(coverage_catalog,grace_cut,0.25,0,view))
	native_gate_failures+=int(handoff.display_grace(coverage_catalog,grace_cut,0.26,-1,view))
	native_gate_failures+=int(handoff.display_grace(coverage_catalog,{"keys":PackedStringArray(["left"])},0.26,0,view))
	native_gate_failures+=int(handoff.anticipation_scale(coverage_catalog,{"keys":PackedStringArray(["left","right"])},view)!=0.25)
	native_gate_failures+=int(handoff.anticipation_scale(coverage_catalog,{"keys":PackedStringArray(["left"])},view)!=0.0)
	native_gate_failures+=int(handoff.anticipation_scale(coverage_catalog,{"keys":PackedStringArray(["left","right"])},Rect2(20,20,5,5))!=0.0)
	native_gate_failures+=int(handoff.native_preference({"within_budget":true},-1))
	native_gate_failures+=int(handoff.native_preference({"within_budget":false},0))
	native_gate_failures+=int(not handoff.native_preference({"within_budget":true},Stream.BUDGET))
	var overlay := CommitOverlay.new()
	var stream := CommitStream.new()
	overlay._stream=stream
	overlay._screen=Sprite2D.new()
	overlay.add_child(overlay._screen)
	overlay._active=true
	overlay._screen.show()
	overlay._catalogs=[{"max_scale":1.25,"rows":{"page":{"max_scale":1.25,"native_geometry":{"path":"mesh"},"native_texture":{"path":"image"}}}}]
	overlay._target_catalog=0
	overlay._target={"keys":PackedStringArray(["page"]),"charges":{"ground_bytes":288}}
	var failures := native_gate_failures+int(overlay._commit_ready_target(1.0) or not overlay._screen.visible)
	failures+=int(overlay._resources_ready(overlay._target,0) or overlay._resources_ready({},0) or overlay._resources_ready(overlay._target,99))
	stream.texture_ready=true
	failures+=int(not overlay._resources_ready(overlay._target,0))
	failures+=int(overlay._resources_ready({"keys":PackedStringArray(["missing"])},0))
	overlay.current_view_covered=false
	failures+=int(overlay._commit_ready_target(1.0) or overlay.binds!=0)
	overlay.current_view_covered=true
	failures+=int(overlay._commit_ready_target(1.26) or not overlay._screen.visible)
	overlay._target["anticipated_scale"]=1.1
	failures+=int(overlay._commit_ready_target(1.0) or overlay.binds!=0)
	failures+=int(overlay._commit_ready_target(1.2) or overlay.binds!=0) # 无真实视野证明不能交接。
	overlay._target.erase("anticipated_scale")
	# 缩远降档完成时已反向放大，不能把仍清晰的旧档换成即将过期的粗档。
	overlay._catalogs.append({"max_scale":2.5,"rows":{"fine":{"max_scale":2.5}}})
	overlay._committed_catalog=1
	overlay._committed=PackedStringArray(["fine"])
	overlay._committed_cut={"keys":PackedStringArray(["fine"])}
	overlay._zooming_in=true
	failures+=int(overlay._commit_ready_target(1.0) or overlay.binds!=0 or overlay._committed_catalog!=1)
	# 旧细档缺边时不能以更高上限阻止完整且当前清晰度合格的目标接替。
	overlay.committed_view_covered=false
	# GPU资源已齐但地表预约失败，必须保留旧显示与旧租约，不能先清屏。
	var old_ground := overlay._ground_token.get_instance_id()
	stream.reservations[old_ground]=144
	overlay._ground_charged=true
	stream.reserve_ok=false
	failures+=int(overlay._commit_ready_target(1.0) or overlay._committed_catalog!=1 \
		or overlay._committed!=PackedStringArray(["fine"]) or not overlay._screen.visible \
		or not stream.reservations.has(old_ground) or overlay.binds!=0)
	stream.reserve_ok=true
	failures+=int(not overlay._commit_ready_target(1.0) or not overlay._screen.visible or overlay.binds!=1)
	failures+=int(stream.reservations.size()!=1 or stream.reservations.has(old_ground) \
		or stream.reservations.get(overlay._ground_token.get_instance_id())!=288)
	# 同帧末尾再检查不得重复绑定；提前返回也必须已经恢复合成层。
	failures+=int(overlay._commit_ready_target(1.0) or overlay.binds!=1)
	# 混合原生也必须等纹理及新地表预约；不能只看原生网格ready。
	overlay._target_catalog=-2
	overlay._target={"keys":PackedStringArray(["native"]),"masks":[],"configuration":"lod4_full","ground_max_scale":1.25,"ground_images":PackedStringArray(["baked"]),"charges":{"ground_bytes":288}}
	stream.texture_ready=false
	failures+=int(overlay._commit_ready_target(1.0) or overlay.binds!=1 or not overlay._screen.visible)
	stream.texture_ready=true;stream.reserve_ok=false
	failures+=int(overlay._commit_ready_target(1.0) or overlay.binds!=1 or stream.reservations.size()!=1)
	stream.reserve_ok=true
	failures+=int(not overlay._commit_ready_target(1.0) or overlay.binds!=2 or not overlay._ground_charged or stream.reservations.size()!=1)
	overlay._clear_current()
	failures+=int(not stream.reservations.is_empty())
	overlay.free()
	stream.free()
	return failures

## 只替换I/O，真实父级请求/预约/取消/关闭流程照常；不作为GPU性能证据。
class PipelineFixture extends Stream:
	var payload_valid := true
	var simulate_heavy_upload := false
	var hold_texture_step := false
	var force_ready_visible := false
	func ready_visible_mesh() -> bool: return force_ready_visible or super.ready_visible_mesh()
	func _step_textures() -> void:
		if hold_texture_step: return
		if simulate_heavy_upload:
			_texture_upload_frame=Engine.get_process_frames()
			texture_completed+=1
			texture_upload_usec+=1200
		else: super._step_textures()
	func _request_load(_path: String) -> Error: return OK
	func _load_status(_path: String) -> int: return ResourceLoader.THREAD_LOAD_LOADED
	func _take_load(_path: String) -> Resource:
		var value := preload("res://scripts/rendering/tokyo_mesh_component.gd").new()
		value.geometry_bytes=int(_descriptors[_path].bytes)
		return value
	func _matches(_item: Resource, _path: String) -> bool: return payload_valid



static func projection_equivalence_checks() -> int:
	var overlay := preload("res://scripts/rendering/tokyo_cells_overlay.gd")
	var rng := RandomNumberGenerator.new()
	rng.seed=20261001
	var failures := 0
	for n in 1024:
		var box := AABB(Vector3(rng.randf_range(-20000,20000),rng.randf_range(-64,64),rng.randf_range(-20000,20000)),Vector3(rng.randf_range(0,8000),0 if n%3==0 else rng.randf_range(0,600),rng.randf_range(0,8000)))
		var roof := Vector2(rng.randf_range(-2,2),rng.randf_range(-2,2))
		var shadow := Vector2.ZERO if n%2==0 else Vector2(rng.randf_range(-3,3),rng.randf_range(-3,3))
		var footprint := Rect2(Vector2(box.position.x,box.position.z),Vector2(box.size.x,box.size.z))
		var expected := footprint
		for shift: Vector2 in [roof,shadow]:
			for height: float in [box.position.y,box.end.y]: expected=expected.merge(Rect2(footprint.position+shift*height,footprint.size))
		expected=expected.grow(8.0)
		var actual: Rect2=overlay.projected_layer_bounds(box,roof,shadow)
		failures+=int(actual!=expected)
		var canvas := Transform2D(rng.randf_range(-PI,PI),Vector2(800,450)-actual.get_center())
		canvas=canvas.scaled(Vector2.ONE*rng.randf_range(0.024,5.0))
		if n%17==0: canvas=Transform2D(Vector2.ZERO,Vector2.ZERO,Vector2.ZERO)
		var view := Rect2(-16000,-16000,32000,32000)
		var seen := expected.intersects(view,true)
		if seen and absf(canvas.determinant())>=0.00000001:
			var projected := Rect2(canvas*expected.position,Vector2.ZERO)
			for corner: Vector2 in [Vector2(expected.end.x,expected.position.y),expected.end,Vector2(expected.position.x,expected.end.y)]: projected=projected.expand(canvas*corner)
			seen=projected.intersects(Rect2(0,0,1600,900),true)
		failures+=int(overlay.intersects_view(actual,view,canvas,Vector2(1600,900))!=seen)
	return failures


static func cache_pruning_checks() -> int:
	var failures := partitioned_request_checks()
	for mode in ["grace","expired","pressure"]:
		var grace_stream := Stream.new()
		grace_stream.residency_limit=1024*1024*1024;grace_stream._retain_unused=true;grace_stream.recent_mesh_grace=true
		for path: String in ["returning","other"]:
			var part := preload("res://scripts/rendering/tokyo_mesh_component.gd").new()
			part.geometry_bytes=40;grace_stream._cache[path]=part
		grace_stream._bytes=80;grace_stream._auxiliary_bytes=grace_stream.residency_limit-80
		grace_stream._cache_access={"returning":0,"other":10}
		grace_stream._wanted=PackedStringArray(["returning"]);grace_stream._prune(0)
		grace_stream._wanted=PackedStringArray()
		if mode=="expired": grace_stream._recent_mesh_until["returning"]=0
		grace_stream._prune(80 if mode=="pressure" else 40)
		failures+=int(grace_stream._cache.has("returning")!=(mode=="grace"))
		failures+=int(grace_stream._cache.has("other")!=(mode=="expired"))
		failures+=int(grace_stream._bytes+(80 if mode=="pressure" else 40)>grace_stream.geometry_budget())
		grace_stream._auxiliary_bytes=0;grace_stream.close();grace_stream.free()
	var owner := Node.new()
	var resident := Stream.new()
	var p := {"bytes":10}
	var q := {"bytes":20}
	var geometry := {"a":{"components":{"p":p}},"b":{"components":{"p":p,"q":q}}}
	failures+=int(not resident.configure_hlod(owner,geometry,{}))
	failures+=int(not resident.configure_residency(PackedStringArray(["a"]),PackedStringArray()))
	var ledger := resident.residency_request_ledger(7)
	failures+=int(ledger.is_empty() or ledger.get("bytes",0)!=17)
	var overlay := preload("res://scripts/rendering/tokyo_hlod_overlay.gd").new()
	overlay._stream=resident;overlay._geometry=geometry
	overlay._committed_catalog=-2
	overlay._committed_cut={"keys":PackedStringArray(["a"]),"charges":{"ground_bytes":3}}
	var next := {"keys":PackedStringArray(["b"]),"charges":{"ground_bytes":4}}
	failures+=int(overlay._handoff_bytes(next,-2)!=27) # p已固定，只新增q和两份地表租约。
	resident._texture_descriptors={"image":{"charge":100}}
	resident.residency_images=PackedStringArray(["image"]);resident.residency_bytes=110
	overlay._textures=resident._texture_descriptors
	next.ground_images=PackedStringArray(["image","image"])
	failures+=int(overlay._handoff_bytes(next,-2)!=27)
	# 超预算必须返回真实增量而非负值，固定/逻辑组件描述冲突必须拒绝。
	geometry["b"].components["q"]={"bytes":resident.residency_limit}
	failures+=int(overlay._handoff_bytes(next,-2)!=resident.residency_limit+7)
	geometry["b"].components["q"]=q
	geometry["b"].components["p"]={"bytes":11}
	failures+=int(overlay._handoff_bytes(next,-2)!=-1)
	geometry["b"].components["p"]=p
	next.charges.ground_bytes=-10
	failures+=int(overlay._handoff_bytes(next,-2)!=-1)
	next.charges.ground_bytes=4
	resident.residency_images.clear();resident._texture_descriptors.clear();resident.residency_bytes=10
	next.erase("ground_images")
	resident.residency_bytes=0
	failures+=int(overlay._handoff_bytes(next,-2)!=37)
	resident.residency_bytes=10
	overlay._stream=null;overlay.free()
	var handoff := preload("res://scripts/rendering/tokyo_hlod_handoff.gd")
	failures+=int(not handoff.append_streaming_bundle(ledger,geometry,{},PackedStringArray(["b"]),PackedStringArray(),100))
	failures+=int(ledger.get("bytes",0)!=37)
	ledger.meshes.erase("p")
	ledger=resident.residency_request_ledger(7)
	failures+=int(ledger.get("bytes",0)!=17 or not ledger.meshes.has("p") or ledger.meshes.has("q"))
	# 模拟加载邻区解除：数组快照变化必须重建，调用者账本修改不能污染固定集。
	resident.residency_meshes=PackedStringArray(["b"])
	ledger=resident.residency_request_ledger(0)
	failures+=int(ledger.get("bytes",0)!=30 or resident._paths(PackedStringArray(["b","a"]))!=PackedStringArray(["p","q"]))
	var logical_wanted := PackedStringArray(["b","a"])
	var logical_pins := PackedStringArray(["a"])
	resident.request(logical_wanted,logical_pins)
	failures+=int(resident._wanted!=PackedStringArray(["p","q"]) or resident._pins!=PackedStringArray(["p"]))
	resident.request(logical_wanted,logical_pins)
	logical_wanted.clear();logical_wanted.append("a")
	logical_pins.clear();logical_pins.append("b")
	resident.request(logical_wanted,logical_pins)
	failures+=int(resident._wanted!=PackedStringArray(["p"]) or resident._pins!=PackedStringArray(["p","q"]))
	# 同路径、重配置成新物理组件必须使请求展开缓存失效。
	owner.tree_exiting.disconnect(resident.close)
	resident.configure(owner,{"a":{"components":{"q":q}},"b":{"components":{"p":p}}})
	resident.request(logical_wanted,logical_pins)
	failures+=int(resident._wanted!=PackedStringArray(["q"]) or resident._pins!=PackedStringArray(["p"]))
	resident.residency_meshes.clear()
	failures+=int(resident.residency_request_ledger(0).get("bytes",-1)!=0)
	resident.residency_meshes=PackedStringArray(["a"])
	resident.request_residency_only()
	failures+=int(resident._pins!=PackedStringArray(["q"]) or resident._wanted!=PackedStringArray(["q"]))
	var fixed_mesh := preload("res://scripts/rendering/tokyo_mesh_component.gd").new()
	fixed_mesh.geometry_bytes=20
	resident._cache["q"]=fixed_mesh;resident._bytes=20
	resident.request_residency_only()
	failures+=int(not resident._wanted.is_empty() or resident._pins!=PackedStringArray(["q"]) or not resident._cache.has("q"))
	resident.close()
	failures+=int(not resident._last_physical_wanted.is_empty() or not resident._last_physical_pins.is_empty())
	failures+=int(not resident.residency_request_ledger(0).is_empty() or not resident._expanded_paths.is_empty())
	resident.free();owner.free()
	# 旧判定逐值对拍大固定集，含重叠、独立pins和被移除项；计时仅是CPU微测，不作游戏FPS。
	var component := preload("res://scripts/rendering/tokyo_component_stream.gd").new()
	var wanted := PackedStringArray()
	var pins := PackedStringArray()
	var original: Dictionary={}
	var item := Resource.new()
	for n in 5000:
		var path := "fixture-%05d"%n
		original[path]=item
		if n%3==0: wanted.append(path)
		if n%5==0: pins.append(path)
	var expected := original.duplicate()
	var before := Time.get_ticks_usec()
	for path: String in expected.keys():
		if path not in wanted and path not in pins: expected.erase(path)
	var reference_usec := Time.get_ticks_usec()-before
	component._views=original.duplicate()
	before=Time.get_ticks_usec()
	component.request(wanted,pins)
	var optimized_usec := Time.get_ticks_usec()-before
	failures+=int(component._views!=expected)
	# 输入数组随后修改不能影响已保存请求/本次保留结果。
	wanted.clear();pins.clear()
	failures+=int(component._views!=expected or component._wanted.is_empty())
	component.request(wanted,pins)
	failures+=int(not component._views.is_empty())
	component.close();component.free()
	print("[HLOD membership microprobe] old_filter_us=",reference_usec," new_full_request_us=",optimized_usec," equivalent=",failures==0)
	for trial: Array in [[384,true],[1536,true],[1536,false]]:
		var pool: int=trial[0]
		var recent_mesh: bool=trial[1]
		var stream := Stream.new()
		stream.residency_limit=pool*1024*1024
		stream._retain_unused=true
		var mesh := preload("res://scripts/rendering/tokyo_mesh_component.gd").new()
		mesh.geometry_bytes=40
		stream._cache={"mesh":mesh};stream._bytes=40
		stream._auxiliary_bytes=stream.residency_limit-40
		stream._textures={"old":{},"pinned":{}}
		stream._texture_descriptors={"old":{"charge":80},"pinned":{"charge":80}}
		stream._texture_pins=PackedStringArray(["pinned"])
		stream._cache_access={"mesh":10 if recent_mesh else 0,"old":0 if recent_mesh else 10}
		var previous_charge: int=stream._auxiliary_bytes
		var required := 60 if recent_mesh else 30
		stream._prune(required)
		failures+=int(stream._cache.has("mesh")!=(pool==1536 and recent_mesh))
		failures+=int(stream._texture_retiring.has("old")!=recent_mesh or not stream._textures.has("pinned"))
		failures+=int(stream._auxiliary_bytes!=previous_charge) # 计划退役不提前释放计费。
		stream._prune(required)
		failures+=int(stream._cache.has("mesh")!=(pool==1536 and recent_mesh))
		stream._textures.clear();stream._texture_retiring.clear();stream._auxiliary_bytes=0
		stream.close()
		stream.free()
	return failures


static func ground_lease_pressure_checks() -> int:
	var failures := 0
	# 复现真实满池快照：仅余712字节，一张图片已计划退役但仍必须计费两帧。
	for mode in ["free","pinned","wanted","large"]:
		var stream := Stream.new()
		stream.residency_limit=1024*1024*1024;stream._retain_unused=true
		var spare := preload("res://scripts/rendering/tokyo_mesh_component.gd").new()
		var protected := preload("res://scripts/rendering/tokyo_mesh_component.gd").new()
		spare.geometry_bytes=4096;protected.geometry_bytes=1024
		stream._cache={"spare":spare,"protected":protected};stream._bytes=5120
		stream._pins=PackedStringArray(["protected"])
		if mode=="pinned": stream._pins.append("spare")
		if mode=="wanted": stream._wanted=PackedStringArray(["spare"])
		stream._auxiliary_bytes=stream.residency_limit-stream._bytes-712
		stream._texture_descriptors={"retiring":{"charge":8192}}
		stream._texture_retiring={"retiring":{"retire_frame":Engine.get_process_frames()+2}}
		var prior_charge: int=stream._auxiliary_bytes
		var token := RefCounted.new()
		var amount := 8192 if mode=="large" else 1152
		var accepted := stream.reserve_auxiliary(token.get_instance_id(),amount)
		failures+=int(accepted!=(mode=="free"))
		failures+=int(not stream._cache.has("protected") or not stream._texture_retiring.has("retiring"))
		failures+=int(stream._auxiliary_bytes!=prior_charge+(amount if accepted else 0))
		failures+=int(stream.summary().total_bytes>stream.residency_limit)
		failures+=int(stream._cache.has("spare")==(mode=="free"))
		if accepted: stream.release_auxiliary(token.get_instance_id())
		failures+=int(stream._auxiliary_bytes!=prior_charge)
		stream._texture_retiring.clear();stream._auxiliary_bytes=0
		stream.close();stream.free()
	print("[ground lease pressure] failures=",failures)
	return failures


static func partitioned_request_checks() -> int:
	var failures := 0
	var owner := Node.new()
	var reference := preload("res://scripts/rendering/tokyo_component_stream.gd").new()
	var grouped := preload("res://scripts/rendering/tokyo_component_stream.gd").new()
	var descriptors: Dictionary={}
	var views: Dictionary={}
	var payload := Resource.new()
	var fixed := PackedStringArray()
	for n in 128:
		var path := "logical-%03d"%n
		descriptors[path]={"components":{"physical-%03d"%n:{"bytes":1},"shared-%02d"%(n%7):{"bytes":1}}}
		views[path]=payload
		if n%3!=0: fixed.append(path)
	reference.configure(owner,descriptors);grouped.configure(owner,descriptors)
	for trial in 100:
		# 同一固定组重复使用、重排、原地修改及最终清空；前/后景与pins故意交叠。
		if trial==30: fixed.reverse()
		if trial==60: fixed.remove_at(0)
		if trial==99: fixed.clear()
		var front := PackedStringArray(["logical-%03d"%(trial%128),"logical-001"])
		var tail := PackedStringArray(["logical-%03d"%((trial+63)%128),"logical-001"])
		var pins := PackedStringArray(["logical-%03d"%((trial+23)%128)])
		var flat := front.duplicate();flat.append_array(fixed);flat.append_array(tail)
		var flat_pins := fixed.duplicate();flat_pins.append_array(pins)
		reference._views=views.duplicate();grouped._views=views.duplicate()
		reference.request(flat,flat_pins)
		grouped.request_partitioned(front,fixed,tail,pins)
		failures+=int(reference._wanted!=grouped._wanted or reference._pins!=grouped._pins or reference._views!=grouped._views)
	# 已校验固定资源只退出加载队列，不能退出保护或逻辑视图；丢失一项必须重入队。
	fixed=PackedStringArray(["logical-001","logical-002"])
	var fixed_paths := grouped._paths(fixed)
	var mesh := preload("res://scripts/rendering/tokyo_mesh_component.gd").new()
	mesh.geometry_bytes=1
	for path: String in fixed_paths: grouped._cache[path]=mesh
	grouped._bytes=fixed_paths.size()
	grouped._views=views.duplicate()
	grouped.request_partitioned(PackedStringArray(),fixed,PackedStringArray(),PackedStringArray())
	failures+=int(not grouped._wanted.is_empty() or grouped._pins!=fixed_paths or grouped._cache.size()!=fixed_paths.size() or grouped._views.size()!=2)
	grouped._cache.erase(fixed_paths[0]);grouped._bytes-=1
	grouped.request_partitioned(PackedStringArray(),fixed,PackedStringArray(),PackedStringArray())
	failures+=int(grouped._wanted!=fixed_paths or grouped._pins!=fixed_paths)
	grouped._cache.clear();grouped._bytes=0
	# 缓存过固定组后重配同名来源，必须按新的组件展开。
	fixed=PackedStringArray(["logical-001"])
	grouped.request_partitioned(PackedStringArray(),fixed,PackedStringArray(),PackedStringArray())
	owner.tree_exiting.disconnect(grouped.close)
	grouped.configure(owner,{"logical-001":{"components":{"replacement":{"bytes":1}}}})
	grouped.request_partitioned(PackedStringArray(),fixed,PackedStringArray(),PackedStringArray())
	failures+=int(grouped._wanted!=PackedStringArray(["replacement"]) or grouped._pins!=grouped._wanted)
	reference.close();grouped.close()
	failures+=int(not grouped._fixed_snapshot.is_empty() or not grouped._fixed_physical.is_empty() or not grouped._fixed_logical.is_empty())
	reference.free();grouped.free();owner.free()
	print("[HLOD partitioned request] exact_order_and_retention_fail=",failures)
	return failures


static func idle_completion_checks(parent: Node) -> int:
	var failures := 0
	var path := "res://scripts/rendering/tokyo_cell_stream.gd"
	# 真实父级调度/预算/关闭，I/O替身模拟GL已完成但目标已改变。
	for mode in 6:
		var owner := Node.new()
		parent.add_child(owner)
		var stream := PipelineFixture.new()
		parent.add_child(stream)
		stream.configure_hlod(owner,{path:{"bytes":40}}, {})
		stream.hold_texture_step=true
		stream._main_thread_meshes=mode==5
		stream._retain_unused=mode!=0
		stream.request(PackedStringArray([path]),PackedStringArray())
		stream._process_stream()
		stream.set_process(false)
		failures+=int(stream.started!=1 or stream._reserved!=40)
		stream.request(PackedStringArray(),PackedStringArray())
		if mode==2: stream.close()
		if mode==3: stream._auxiliary_bytes=stream.geometry_budget()-20
		if mode==4: stream.payload_valid=false
		stream._collect_completed()
		stream.set_process(false)
		var accepted := mode==1
		failures+=int(stream._cache.has(path)!=accepted or stream.retained_completions!=int(accepted))
		failures+=int(stream._reserved!=0 or not stream._pending.is_empty() or Stream._busy.has(path))
		if accepted:
			stream.request(PackedStringArray([path]),PackedStringArray())
			stream._process_stream()
			stream.set_process(false)
			failures+=int(stream.started!=1 or stream._bytes!=40)
		stream._auxiliary_bytes=0
		stream.close()
		var reference: WeakRef = weakref(stream)
		owner.queue_free()
		for frame in 3: await parent.get_tree().process_frame
		failures+=int(reference.get_ref()!=null)
	print("[HLOD idle completion] modes=6 failures=",failures)
	return failures


static func pipeline_checks(parent: Node) -> int:
	var paths := PackedStringArray(["res://scripts/rendering/tokyo_hlod_stream.gd","res://scripts/rendering/tokyo_cell_stream.gd"])
	var failures := 0
	# 用真实父级发起流程证明空出的共享槽不会被本轮网格立即抢回。
	var fair_owner := Node.new()
	parent.add_child(fair_owner)
	var fair_stream := PipelineFixture.new()
	parent.add_child(fair_stream)
	fair_stream.configure_hlod(fair_owner,{paths[0]:{"bytes":0},paths[1]:{"bytes":0}}, {})
	fair_stream.fair_image_slot=true
	fair_stream.hold_texture_step=true
	fair_stream._request_limit=2;fair_stream._pipeline_width=2
	fair_stream._texture_descriptors["waiting_image"]={}
	fair_stream.visible_images=PackedStringArray(["waiting_image"])
	fair_stream.request(paths,PackedStringArray())
	fair_stream._process_stream()
	fair_stream.set_process(false)
	failures+=int(fair_stream.started!=1 or fair_stream._pending.size()!=1 or fair_stream._request_limit!=2)
	fair_stream.close()
	fair_owner.queue_free()
	for frame in 4: await parent.get_tree().process_frame
	failures+=int(not Stream._busy.is_empty())
	for cancel in [false,true]:
		var owner := Node.new()
		parent.add_child(owner)
		var stream := PipelineFixture.new()
		parent.add_child(stream)
		stream.configure_hlod(owner,{paths[0]:{"bytes":0},paths[1]:{"bytes":0}}, {})
		stream._pipeline_width=2
		stream.request(paths,PackedStringArray())
		stream._process_stream()
		failures+=int(stream.summary().pending!=2 or stream.summary().peak_pending!=2)
		if cancel: stream.close()
		else:
			stream._process_stream()
			failures+=int(stream.completed!=2 or stream.max_completed_per_frame!=2)
			stream._main_thread_meshes=false # I/O替身：验证末次领取不会突破同帧两份上限。
			var extra := PackedStringArray(["res://scripts/rendering/tokyo_hlod_manifest.gd","res://scripts/rendering/tokyo_hlod_handoff.gd"])
			for path in extra: stream._descriptors[path]={"bytes":0}
			stream.request(extra,PackedStringArray())
			stream._process_stream()
			stream.collect_ready_meshes()
			failures+=int(stream.completed!=2 or stream._pending.size()!=2)
			stream.set_process(false)
			await parent.get_tree().process_frame
			stream._texture_upload_frame=Engine.get_process_frames()
			stream.collect_ready_meshes()
			failures+=int(stream.completed!=2)
			stream._texture_upload_frame=-1
			stream.collect_ready_meshes()
			failures+=int(stream.completed!=4 or stream.max_completed_per_frame!=2)
			stream.set_process(true)
		var reference: WeakRef = weakref(stream)
		owner.queue_free()
		for frame in 4: await parent.get_tree().process_frame
		failures+=int(reference.get_ref()!=null or not Stream._busy.is_empty())
	# 八槽候选沿同一个真实预算调度器；耗时门可以提前停止，不能要求单帧强取八份。
	var progress_owner := Node.new()
	parent.add_child(progress_owner)
	var progress_stream := PipelineFixture.new()
	parent.add_child(progress_stream)
	progress_stream.configure_hlod(progress_owner,{paths[0]:{"bytes":0},paths[1]:{"bytes":0}}, {})
	progress_stream._pipeline_width=8
	progress_stream.request(paths,PackedStringArray())
	progress_stream.simulate_heavy_upload=true
	progress_stream.minimum_mesh_progress=true
	progress_stream._process_stream()
	progress_stream.set_process(false)
	failures+=int(progress_stream.started!=1 or progress_stream._pipeline_width!=8)
	print("[HLOD heavy-upload progress] started=",progress_stream.started," width=",progress_stream._pipeline_width)
	await parent.get_tree().process_frame
	progress_stream._process_stream()
	progress_stream.set_process(false)
	failures+=int(progress_stream.completed!=1 or progress_stream.started!=2 or progress_stream._pipeline_width!=8)
	progress_stream.simulate_heavy_upload=false
	progress_stream.close()
	progress_owner.queue_free()
	for frame in 4: await parent.get_tree().process_frame
	var geometry: Dictionary={}
	paths=PackedStringArray()
	for name_value in ["tokyo_hlod_stream","tokyo_cell_stream","tokyo_component_stream","tokyo_hlod_manifest","tokyo_hlod_handoff","tokyo_hlod_native","tokyo_hlod_overlay","tokyo_volume_overlay"]:
		var path := "res://scripts/rendering/%s.gd" % name_value
		paths.append(path);geometry[path]={"bytes":0}
	var owner := Node.new()
	parent.add_child(owner)
	var stream := PipelineFixture.new()
	parent.add_child(stream)
	stream.configure_hlod(owner,geometry,{})
	stream._pipeline_width=8;stream._request_limit=8
	stream.request(paths,PackedStringArray())
	stream._process_stream()
	failures+=int(stream.summary().pending!=8 or stream.summary().peak_pending!=8)
	for frame in 8:
		stream._process_stream()
		if stream.completed == 8: break
		await parent.get_tree().process_frame
	failures+=int(stream.completed!=8 or stream.max_completed_per_frame>8)
	var reference: WeakRef=weakref(stream)
	owner.queue_free()
	for frame in 4: await parent.get_tree().process_frame
	failures+=int(reference.get_ref()!=null or not Stream._busy.is_empty())
	return failures

static func height_texture_checks(parent: Node) -> int:
	var height := preload("res://scripts/rendering/tokyo_ground_height.gd")
	var path := "res://tmp/tokyo_ground_height_fixture.res"
	var image := Image.create_from_data(1,2,false,Image.FORMAT_RGBA8,PackedByteArray([16,50,84,118,152,186,220,254]))
	if ResourceSaver.save(image,path,ResourceSaver.FLAG_COMPRESS)!=OK: return 1
	var row := {"path":path,"sha256":FileAccess.get_sha256(path),"kind":"ground_height_4bit","mipmaps":false,"width":1,"height":2,"format":Image.FORMAT_RGBA8,"mip_bytes":8,"charge":4120}
	var failures := int(height.descriptor(row,Vector2i(8,2)).is_empty())
	for change: Dictionary in [{"kind":"color"},{"mipmaps":true},{"width":2},{"format":Image.FORMAT_DXT5},{"charge":4119}]:
		var invalid := row.duplicate();invalid.merge(change,true)
		failures+=int(not height.descriptor(invalid,Vector2i(8,2)).is_empty())
	var loaded := Stream.load_image(path,row)
	failures+=int(not loaded.has("image") or loaded.image.get_data()!=image.get_data())
	var owner := Node.new();parent.add_child(owner)
	var stream := Stream.new();owner.add_child(stream)
	failures+=int(not stream.configure_hlod(owner,{}, {path:row}))
	stream.request_textures(PackedStringArray([path]),PackedStringArray([path]))
	for frame in 240:
		stream._process_stream()
		if stream.texture(path)!=null: break
		await parent.get_tree().process_frame
	failures+=int(stream.texture(path)==null or stream._auxiliary_bytes!=4120)
	stream.close()
	owner.queue_free()
	for frame in 4: await parent.get_tree().process_frame
	failures+=int(not Stream._busy.is_empty())
	print("[HLOD packed height] fail=",failures)
	return failures

static func shutdown_checks(parent: Node) -> int:
	var path := "res://resources/maps/tokyo_volume_preview/hlod_stream_fixture.tres"
	var owner := Node.new()
	parent.add_child(owner)
	var stream := Stream.new()
	parent.add_child(stream)
	var row := {"sha256":FileAccess.get_sha256(path),"width":4,"height":4,"format":Image.FORMAT_DXT5,"mip_bytes":48,"charge":4240}
	var valid := stream.configure_hlod(owner,{}, {path:row})
	stream.request_textures(PackedStringArray([path]),PackedStringArray())
	stream._process_stream()
	valid=valid and stream.texture_started==1
	var worker := Thread.new()
	var checksum_path := "res://scripts/rendering/tokyo_hlod_stream.gd"
	if worker.start(Stream.checksum_file.bind(checksum_path))==OK: stream._mesh_checks[checksum_path]=worker
	else: valid=false
	stream.free() # 无后续帧的退出必须join自有线程并归还静态请求槽。
	owner.queue_free()
	return int(not valid or not Stream._busy.is_empty())


static func checksum_reload_checks(parent: Node) -> int:
	var path := "res://resources/maps/tokyo_volume_preview/hlod_stream_fixture.tres"
	var expected := FileAccess.get_sha256(path)
	var owner := Node.new()
	parent.add_child(owner)
	var stream := Stream.new()
	parent.add_child(stream)
	stream.configure_hlod(owner,{path:{"bytes":0,"sha256":expected}}, {})
	stream._main_thread_meshes=false # Image资源可在线程载入；不触碰Dummy网格分配器。
	var failures := 0
	for repeat in 2:
		stream._mesh_hashes[path]="cancelled previous request"
		failures+=int(stream._request_load(path)!=OK or stream._mesh_hashes.has(path) or not stream._mesh_checks.has(path))
		var deadline := Time.get_ticks_msec()+5000
		while stream._load_status(path)!=ResourceLoader.THREAD_LOAD_LOADED and Time.get_ticks_msec()<deadline:
			await parent.get_tree().process_frame
		var item: Resource = stream._take_load(path)
		failures+=int(item==null or stream._mesh_hashes.get(path)!=expected or not stream._mesh_checks.is_empty())
		# 不调用_matches，模拟已完成资源因相机取消而丢弃，再重新请求同一路径。
	stream.free()
	owner.queue_free()
	return failures


static func installed_route_checks() -> bool:
	var installed := preload("res://scripts/rendering/tokyo_installed_map.gd")
	var session := preload("res://scripts/rendering/tokyo_volume_preload.gd")
	var saved: Dictionary={}
	for key: String in ["AGL_TOKYO_HLOD_PACKAGE","AGL_TOKYO_HLOD_PACKAGE_SHA","AGL_TOKYO_VOLUME","AGL_TOKYO_STATIC_NATIVE"]:
		saved[key]=[OS.has_environment(key),OS.get_environment(key)]
	OS.unset_environment("AGL_TOKYO_STATIC_NATIVE")
	OS.set_environment("AGL_TOKYO_HLOD_PACKAGE","res://explicit-candidate.json")
	OS.set_environment("AGL_TOKYO_HLOD_PACKAGE_SHA","a".repeat(64))
	OS.set_environment("AGL_TOKYO_VOLUME","cells")
	var good := installed.package_path()=="res://explicit-candidate.json" and installed.package_sha()=="a".repeat(64) \
		and session.script_path()=="res://scripts/rendering/tokyo_hlod_overlay.gd"
	OS.set_environment("AGL_TOKYO_STATIC_NATIVE","1")
	good=good and session.script_path()=="res://scripts/rendering/tokyo_static_hlod_overlay.gd"
	OS.unset_environment("AGL_TOKYO_HLOD_PACKAGE")
	OS.set_environment("AGL_TOKYO_VOLUME","off")
	good=good and installed.package_path().is_empty() and installed.package_sha().is_empty() \
		and session.script_path()=="res://scripts/rendering/tokyo_volume_overlay.gd"
	for key: String in saved:
		if saved[key][0]: OS.set_environment(key,saved[key][1])
		else: OS.unset_environment(key)
	return good


static func texture_pipeline_checks(parent: Node) -> int:
	if not Stream.can_upload_texture(0,0,0,8*1048576) or not Stream.can_upload_texture(1,999,1048576,1048576) \
		or Stream.can_upload_texture(1,1000,48,48) or Stream.can_upload_texture(2,0,48,48) \
		or Stream.can_upload_texture(1,0,1048577,48) or Stream.can_upload_texture(1,0,48,1048577): return 1
	var paths := PackedStringArray(["res://resources/maps/tokyo_volume_preview/hlod_stream_fixture.tres","res://resources/maps/tokyo_volume_preview/hlod_stream_fixture_pair.tres","res://resources/maps/tokyo_volume_preview/hlod_stream_fixture_third.tres","res://resources/maps/tokyo_volume_preview/hlod_stream_fixture_fourth.tres"])
	var descriptors: Dictionary={}
	for path: String in paths:
		descriptors[path]={"sha256":FileAccess.get_sha256(path),"width":4,"height":4,"format":Image.FORMAT_DXT5,"mip_bytes":48,"charge":4240}
	var owner := Node.new()
	parent.add_child(owner)
	var stream := Stream.new()
	parent.add_child(stream)
	stream.configure_hlod(owner,{},descriptors)
	stream._request_limit=8 # 与GL共享槽一致，图片后台读取不受Dummy网格构造限制。
	var blocker := RefCounted.new()
	stream.reserve_auxiliary(blocker.get_instance_id(),Stream.BUDGET)
	stream.request_textures(paths,PackedStringArray())
	stream.set_process(false)
	stream._step_textures()
	var failures := int(stream.texture_started!=0)
	stream.release_auxiliary(blocker.get_instance_id())
	stream._step_textures()
	failures+=int(stream.texture_started!=4 or stream._texture_jobs.size()!=4 or stream.summary().auxiliary_bytes!=16960 or Stream._busy.size()>8)
	var deadline := Time.get_ticks_msec()+5000
	while stream.texture_completed<4 and Time.get_ticks_msec()<deadline:
		await parent.get_tree().process_frame
		var previous := stream.texture_completed
		stream._step_textures()
		failures+=int(stream.texture_completed-previous>2)
	failures+=int(stream.texture_completed!=4 or not stream._texture_jobs.is_empty())
	# 满池交接须一次安排四份无用纹理退役，退役期间计费仍不能提前归还。
	stream.reserve_auxiliary(blocker.get_instance_id(),Stream.BUDGET-16960)
	stream._texture_descriptors["missing-a"]={"charge":8480}
	stream._texture_descriptors["missing-b"]={"charge":8480}
	stream.request_textures(PackedStringArray(["missing-a","missing-b"]),PackedStringArray())
	failures+=int(stream._texture_retiring.size()!=4 or stream.summary().auxiliary_bytes!=Stream.BUDGET)
	stream.request_textures(PackedStringArray(),PackedStringArray())
	stream.release_auxiliary(blocker.get_instance_id())
	var reference: WeakRef = weakref(stream)
	owner.queue_free()
	stream.set_process(true)
	deadline=Time.get_ticks_msec()+5000
	while reference.get_ref()!=null and Time.get_ticks_msec()<deadline: await parent.get_tree().process_frame
	failures+=int(reference.get_ref()!=null or not Stream._busy.is_empty())
	print("[HLOD texture pipeline] fail=",failures)
	return failures


static func decoded_slot_checks(parent: Node, enabled: bool, corrupted: bool = false) -> int:
	var old := "res://resources/maps/tokyo_volume_preview/hlod_stream_fixture.tres"
	var current := "res://resources/maps/tokyo_volume_preview/hlod_stream_fixture_pair.tres"
	var descriptors: Dictionary={}
	for path: String in [old,current]:
		descriptors[path]={"sha256":FileAccess.get_sha256(path),"width":4,"height":4,"format":Image.FORMAT_DXT5,"mip_bytes":48,"charge":4240}
	if corrupted: descriptors[old].sha256="0".repeat(64)
	var owner := Node.new()
	parent.add_child(owner)
	var stream := PipelineFixture.new()
	parent.add_child(stream)
	stream.configure_hlod(owner,{},descriptors)
	stream._request_limit=1
	stream.retain_decoded=true
	stream.detach_decoded=enabled
	stream.force_ready_visible=true
	stream.request_textures(PackedStringArray([old]),PackedStringArray())
	stream.set_process(false)
	stream._step_textures()
	var deadline := Time.get_ticks_msec()+5000
	while stream._texture_jobs.has(old) and stream._texture_jobs[old].worker.is_alive() and Time.get_ticks_msec()<deadline:
		await parent.get_tree().process_frame
	stream.visible_images=PackedStringArray([current])
	stream.request_textures(PackedStringArray([current,old]),PackedStringArray())
	stream.set_process(false)
	stream._step_textures()
	var failures := int(stream.texture_started!=(2 if enabled else 1) or stream.texture_completed!=0)
	var kept := enabled and not corrupted
	failures+=int(stream._texture_jobs.has(current)!=enabled or stream._decoded_images.has(old)!=kept)
	failures+=int(stream.decoded_detaches!=int(kept) or Stream._busy.size()!=1)
	failures+=int(stream.summary().auxiliary_bytes!=(8480 if kept else 4240))
	failures+=int(stream._texture_errors.has(old)!=(enabled and corrupted))
	var reference: WeakRef = weakref(stream)
	owner.queue_free()
	stream.set_process(true)
	deadline=Time.get_ticks_msec()+5000
	while reference.get_ref()!=null and Time.get_ticks_msec()<deadline: await parent.get_tree().process_frame
	failures+=int(reference.get_ref()!=null or not Stream._busy.is_empty())
	print("[HLOD decoded slot] enabled=",enabled," corrupted=",corrupted," fail=",failures)
	return failures


static func visible_dispatch_checks(parent: Node) -> int:
	var mesh := "res://scripts/rendering/tokyo_hlod_stream.gd"
	var picture := "res://resources/maps/tokyo_volume_preview/hlod_stream_fixture.tres"
	var owner := Node.new()
	parent.add_child(owner)
	var stream := PipelineFixture.new()
	parent.add_child(stream)
	stream.configure_hlod(owner,{mesh:{"bytes":1}}, {picture:{"sha256":FileAccess.get_sha256(picture),"width":4,"height":4,"format":Image.FORMAT_DXT5,"mip_bytes":48,"charge":4240}})
	stream._main_thread_meshes=false
	stream._request_limit=2
	stream.visible_finalize_first=false
	stream.visible_dispatch_yield=false
	stream.visible_meshes=PackedStringArray([mesh])
	stream.request(PackedStringArray([mesh]),PackedStringArray())
	stream.set_process(false)
	var failures := int(stream.visible_dispatch_ready())
	stream.visible_dispatch_yield=true
	failures+=int(not stream.visible_dispatch_ready())
	var token := RefCounted.new()
	failures+=int(not stream.reserve_auxiliary(token.get_instance_id(),Stream.BUDGET))
	failures+=int(stream.visible_dispatch_ready())
	stream.release_auxiliary(token.get_instance_id())
	stream._wanted.insert(0,"unavailable_first")
	failures+=int(stream.visible_dispatch_ready())
	stream._wanted.remove_at(0)
	stream._failures[mesh]="controlled"
	failures+=int(stream.visible_dispatch_ready())
	stream._failures.clear()
	stream.request_textures(PackedStringArray([picture]),PackedStringArray())
	stream.set_process(false)
	stream._step_textures()
	var deadline := Time.get_ticks_msec()+5000
	while stream._texture_jobs.has(picture) and stream._texture_jobs[picture].worker.is_alive() and Time.get_ticks_msec()<deadline:
		await parent.get_tree().process_frame
	stream._request_limit=1
	failures+=int(stream.visible_dispatch_ready())
	stream._request_limit=2
	stream._process_stream()
	stream.set_process(false)
	failures+=int(stream.started!=1 or not stream._pending.has(mesh) or stream.texture_completed!=0 or stream.visible_dispatch_deferrals!=1)
	# 已发起后不继续阻挡预测图；当前图永远不由该谓词挡住。
	stream.visible_images=PackedStringArray([picture])
	stream._process_stream()
	stream.set_process(false)
	failures+=int(stream.texture_completed!=1 or stream.visible_dispatch_deferrals!=1)
	var reference: WeakRef = weakref(stream)
	owner.queue_free()
	stream.set_process(true)
	deadline=Time.get_ticks_msec()+5000
	while reference.get_ref()!=null and Time.get_ticks_msec()<deadline: await parent.get_tree().process_frame
	failures+=int(reference.get_ref()!=null or not Stream._busy.is_empty())
	print("[HLOD visible dispatch yield] fail=",failures)
	return failures


static func cancelled_decode_checks(parent: Node, mode: int = 0) -> int:
	# 固定真实反例：后台读完前撤销预测，稍后同一图片重新成为当前需求。
	var path := "res://resources/maps/tokyo_volume_preview/hlod_stream_fixture.tres"
	var descriptor := {"sha256":FileAccess.get_sha256(path),"width":4,"height":4,"format":Image.FORMAT_DXT5,"mip_bytes":48,"charge":4240}
	var owner := Node.new()
	parent.add_child(owner)
	var stream := Stream.new()
	parent.add_child(stream)
	stream.configure_hlod(owner,{}, {path:descriptor})
	stream._retain_unused=true
	stream.retain_decoded=mode>0
	stream.request_textures(PackedStringArray([path]),PackedStringArray())
	stream.set_process(false)
	stream._step_textures()
	var failures := int(stream.texture_started!=1)
	var deadline := Time.get_ticks_msec()+5000
	while stream._texture_jobs.has(path) and stream._texture_jobs[path].worker.is_alive() and Time.get_ticks_msec()<deadline:
		await parent.get_tree().process_frame
	stream.request_textures(PackedStringArray(),PackedStringArray())
	stream.set_process(false)
	stream._step_textures()
	var kept := mode>0
	failures+=int(not stream._texture_jobs.is_empty() or stream.texture_completed!=0 or not Stream._busy.is_empty())
	failures+=int(stream.summary().auxiliary_bytes!=(4240 if kept else 0) or stream._decoded_images.has(path)!=kept or stream.texture(path)!=null)
	if mode==2:
		stream._decoded_images[path].expires=Time.get_ticks_msec()-1
		stream._step_textures()
	elif mode==3:
		stream._prune(Stream.BUDGET)
	elif mode==4:
		stream.retain_decoded=false
		stream._step_textures()
	elif mode==5:
		# 原预约仍在池内；真实已解码Image仅复制引用，不伪造GPU ready。
		for index in range(7):
			var extra := path+"_"+str(index)
			var row := descriptor.duplicate()
			row.charge=4*1024*1024
			stream._texture_descriptors[extra]=row
			var token := RefCounted.new()
			failures+=int(not stream.reserve_auxiliary(token.get_instance_id(),row.charge))
			failures+=int(not stream._keep_decoded(extra,stream._decoded_images[path].result.duplicate(),token))
		var rejected := RefCounted.new()
		stream._texture_descriptors["extra"]=descriptor.duplicate()
		failures+=int(stream._keep_decoded("extra",stream._decoded_images[path].result.duplicate(),rejected))
		stream._release_decoded(path+"_0")
		stream._texture_descriptors["extra"].charge=16*1024*1024
		failures+=int(stream._keep_decoded("extra",stream._decoded_images[path].result.duplicate(),rejected))
		stream._texture_descriptors["extra"].charge=33*1024*1024
		failures+=int(stream._keep_decoded("extra",stream._decoded_images[path].result.duplicate(),rejected))
		failures+=int(stream._keep_decoded("extra",{"error":"test"},rejected))
		stream.close()
	if mode>=2: failures+=int(not stream._decoded_images.is_empty() or stream.summary().auxiliary_bytes!=0)
	if mode==5:
		var closed_reference: WeakRef = weakref(stream)
		owner.queue_free()
		stream.set_process(true)
		deadline=Time.get_ticks_msec()+5000
		while closed_reference.get_ref()!=null and Time.get_ticks_msec()<deadline: await parent.get_tree().process_frame
		failures+=int(closed_reference.get_ref()!=null or not Stream._busy.is_empty())
		print("[HLOD cancelled decode] mode=5 close fail=",failures)
		return failures
	stream.request_textures(PackedStringArray([path]),PackedStringArray())
	stream.set_process(false)
	stream._step_textures()
	var expected_reads := 1 if mode==1 else 2
	failures+=int(stream.texture_started!=expected_reads)
	deadline=Time.get_ticks_msec()+5000
	while stream.texture_completed<1 and Time.get_ticks_msec()<deadline:
		await parent.get_tree().process_frame
		stream._step_textures()
	failures+=int(stream.texture_completed!=1 or not stream._texture_errors.is_empty() or not stream._decoded_images.is_empty())
	failures+=int(stream.decoded_reuses!=(1 if mode==1 else 0) or stream.summary().auxiliary_bytes!=4240)
	var reads := stream.texture_started
	var reference: WeakRef = weakref(stream)
	owner.queue_free()
	stream.set_process(true)
	deadline=Time.get_ticks_msec()+5000
	while reference.get_ref()!=null and Time.get_ticks_msec()<deadline: await parent.get_tree().process_frame
	failures+=int(reference.get_ref()!=null or not Stream._busy.is_empty())
	print("[HLOD cancelled decode] mode=",mode," reads=",reads," uploads=1 fail=",failures)
	return failures


static func handoff_budget_probe() -> int:
	# 复用冷进入捕获的旧切面，仅计算真实目录预算；不加载GPU资产，不作为Visual验收。
	var contract := preload("res://scripts/rendering/tokyo_hlod_manifest.gd")
	var handoff := preload("res://scripts/rendering/tokyo_hlod_handoff.gd")
	var package: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://resources/maps/tokyo_playable/package.json"))
	var old: Dictionary=contract.read(package.catalogs[5].path,package.catalogs[5].sha256)
	var next: Dictionary=contract.read(package.catalogs[4].path,package.catalogs[4].sha256)
	if old.is_empty() or next.is_empty(): return 1
	var previous := {"keys":PackedStringArray(["2:7","2:23","1:4"])}
	var anticipated: Dictionary=contract.select(next,Vector2(225,-13633),0.5625,0.0,Vector2(1600,900),true)
	print("[HLOD anticipated] valid=",anticipated.get("within_budget")," combined=",handoff.combined_bytes(old,previous,next,anticipated)," keys=",anticipated.get("keys"))
	if anticipated.is_empty() or not anticipated.within_budget or handoff.combined_bytes(old,previous,next,anticipated)>Stream.BUDGET: return 1
	for scale_value in [0.45,0.60]:
		var required: Dictionary=contract.select(next,Vector2(225,-13633),scale_value,0.0,Vector2(1600,900),true)
		print("[HLOD anticipated proof] scale=",scale_value," required=",required.get("keys")," covered=",contract.retained(next,anticipated,required,scale_value,true))
		if contract.retained(next,anticipated,required,scale_value,true)!=(scale_value==0.60): return 1
	for scale_value in [0.37,0.45,0.50,0.55,0.60,0.625]:
		for amount in [Stream.BUDGET/2,Stream.BUDGET]:
			var cut: Dictionary=contract.select(next,Vector2(225,-13633),scale_value,0.0,Vector2(1600,900),true,amount)
			if cut.is_empty(): return 1
			print("[HLOD budget probe] ",JSON.stringify({"scale":scale_value,"budget":amount,"keys":cut.keys,"bytes":cut.bytes,"faces":cut.triangles,"valid":cut.within_budget,"combined":handoff.combined_bytes(old,previous,next,cut)}))
	return 0


static func run(parent: Node) -> int:
	var worker_failures := await preload("res://scripts/tests/test_tokyo_cut_worker.gd").run(parent)
	if OS.get_environment("AGL_TOKYO_HANDOFF_BUDGET_PROBE")=="1": return handoff_budget_probe()
	if not refinement_source_checks(): return 1
	if await texture_pipeline_checks(parent)!=0: return 1
	for mode in range(6):
		if await cancelled_decode_checks(parent,mode)!=0: return 1
	if await visible_dispatch_checks(parent)!=0: return 1
	for enabled in [false,true]:
		if await decoded_slot_checks(parent,enabled)!=0: return 1
	if await decoded_slot_checks(parent,true,true)!=0: return 1
	if await height_texture_checks(parent)!=0: return 1
	if commit_ready_checks()!=0: return 1
	if await idle_completion_checks(parent)!=0: return 1
	if await pipeline_checks(parent)!=0: return 1
	if await checksum_reload_checks(parent)!=0: return 1
	if shutdown_checks(parent)!=0: return 1
	if not installed_route_checks(): return 1
	var handoff := preload("res://scripts/rendering/tokyo_hlod_handoff.gd")
	var loading := {"keys":PackedStringArray(["page"]),"configuration":"lod4_full","prefetched_native":true}
	var capped := loading.duplicate()
	capped["ground_max_scale"]=1.25
	if not handoff.native_qualified(capped,1.25) or handoff.native_qualified(capped,1.251): return 1
	var ground_entry := {"path":"ground","bytes":1000,"triangles":PackedInt32Array([10,20,30]),"boxes":[AABB(),AABB(),AABB(Vector3.ZERO,Vector3(20,1,30))]}
	var ground_row := {"source_faces":30,"footprint":Rect2(0,0,20,30),"charge":100,"plane_y":0.0}
	var adapted := preload("res://scripts/rendering/tokyo_native_ground.gd").tree(ground_entry,{"ground":ground_row})
	if adapted.is_empty() or adapted.triangles!=PackedInt32Array([10,20,2]) or adapted.bytes!=1388 or ground_entry.triangles[2]!=30 or ground_entry.has("ground_replacement"): return 1
	ground_row.plane_y=-0.35
	if not preload("res://scripts/rendering/tokyo_native_ground.gd").tree(ground_entry,{"ground":ground_row}).is_empty(): return 1
	ground_row.plane_y=0.0
	ground_row.source_faces=29
	if not preload("res://scripts/rendering/tokyo_native_ground.gd").tree(ground_entry,{"ground":ground_row}).is_empty(): return 1
	if handoff.loading_configuration(loading,1.25,"lod5_full")!="lod4_full" \
		or handoff.loading_configuration(loading,1.61,"lod5_full")!="lod5_full" \
		or handoff.loading_configuration({},1.0,"lod5_full")!="lod5_full": return 1
	loading.prefetched_native=false
	if handoff.loading_configuration(loading,1.25,"lod5_full")!="lod5_full": return 1
	var ranges: Array[Dictionary]=[{"range":[0.625,1.25]},{"range":[0.24,0.625]}]
	if handoff.catalog_index(ranges,0.60,false)!=1 or handoff.catalog_index(ranges,0.60,true)!=0: return 1
	if handoff.catalog_index(ranges,0.30)!=1 or handoff.catalog_index(ranges,0.32)!=0 \
		or handoff.catalog_index(ranges,0.625)!=0 or handoff.catalog_index(ranges,NAN)!=-1 \
		or handoff.catalog_index(ranges,0.20)!=-1: return 1
	var finer := {"min_scale":0.625,"max_scale":1.25,"rows":{"page":{"max_scale":1.25}}}
	if not handoff.qualified(finer,{"keys":PackedStringArray(["page"])},0.60) \
		or handoff.qualified(finer,{"keys":PackedStringArray(["page"])},1.26): return 1
	if not Stream.should_defer_mesh_finalize(false,2,3,1000) or Stream.should_defer_mesh_finalize(true,2,3,1000) \
		or Stream.should_defer_mesh_finalize(false,2,2,2000) or Stream.should_defer_mesh_finalize(false,2,3,999): return 1
	var surface := preload("res://scripts/rendering/tokyo_hlod_surface.gd").shader_code()
	if not surface.contains("uniform bool legacy_tint = false;") or surface.contains("DIFFUSE_LIGHT += ALBEDO * ATTENUATION *"): return 1
	var native_surface := preload("res://scripts/rendering/tokyo_hlod_surface.gd").native_code()
	var textured := preload("res://scripts/rendering/tokyo_hlod_surface.gd").textured_code()
	if not textured.contains("uniform bool wall_solid_color = false;") \
		or not textured.contains("wall_solid_color && ordinary_building") \
		or not textured.contains("uniform bool ordinary_building = false;") \
		or not textured.contains("if(sample_color.a<0.001){discard;}") \
		or not textured.contains("filter_linear_mipmap") or native_surface.contains("wall_solid_color"): return 1
	if native_surface.count("COLOR.a==1.0")!=11 or native_surface.find("COLOR.a==1.0")>native_surface.find("void fragment()"): return 1
	var bridge := preload("res://scripts/rendering/tokyo_hlod_native.gd").new()
	for invalid in [null,[],{}, {"catalog":{}}]:
		if bridge.read(invalid): return 1
	if not preload("res://scripts/tests/tokyo_hlod_gameplay_views.gd").checks(): return 1
	if not preload("res://scripts/tests/test_tokyo_hlod_manifest.gd").checks():
		print("[HLOD focused gates] manifest failed")
		return 1
	if not preload("res://scripts/tests/test_tokyo_hlod_coverage.gd").checks():
		print("[HLOD focused gates] coverage failed")
		return 1
	var overlay: Node = load("res://scripts/rendering/tokyo_hlod_overlay.gd").new()
	parent.add_child(overlay)
	overlay._committed=PackedStringArray(["2:1"])
	overlay._committed_catalog=0
	overlay._target_catalog=0
	overlay._target={"keys":PackedStringArray(["2:2"])}
	var pending_ok: bool = not overlay._target_committed()
	overlay._target.keys=PackedStringArray(["2:1"])
	pending_ok=pending_ok and overlay._target_committed()
	overlay.free()
	if not pending_ok: return 1
	var path := "res://resources/maps/tokyo_volume_preview/hlod_stream_fixture.tres"
	var definition := {"sha256":FileAccess.get_sha256(path),"width":4,"height":4,"format":Image.FORMAT_DXT5,"mip_bytes":48,"charge":4240}
	var geometry: Dictionary = {}
	var manifest_path := OS.get_environment("AGL_TOKYO_HLOD_STREAM_MANIFEST")
	if not manifest_path.is_empty():
		var catalog := Stream.Contract.read(manifest_path,OS.get_environment("AGL_TOKYO_HLOD_STREAM_MANIFEST_SHA"))
		if catalog.is_empty(): return 1
		var first: Dictionary = catalog.rows["0:5"]
		path=first.native_texture.path
		definition=catalog.textures[path]
		var covered := Stream.Coverage.read(OS.get_environment("AGL_TOKYO_HLOD_COVERAGE"),OS.get_environment("AGL_TOKYO_HLOD_COVERAGE_SHA"),catalog)
		if covered.size()!=336: return 1
		geometry[first.native_geometry.path]=covered[first.native_geometry.path]
	var failures := 0
	for mode in ["shared","cancel","digest","budget"]:
		var owner := Node.new()
		parent.add_child(owner)
		var stream := Stream.new()
		parent.add_child(stream)
		var row := definition.duplicate(true)
		if mode=="digest": row.sha256="0".repeat(64)
		if not stream.configure_hlod(owner,geometry, {path:row}):
			owner.queue_free();stream.queue_free()
			return 1
		failures+=int(stream._retain_unused!=(OS.get_environment("AGL_TOKYO_RETAIN_UNUSED")!="0"))
		# 此组检查立即退役；闲置复用及预算淘汰另由cache_checks覆盖。
		stream._retain_unused=false
		var stream_ref: WeakRef = weakref(stream)
		var held: WeakRef
		var blocker := RefCounted.new()
		if mode=="budget": failures+=int(not stream.reserve_auxiliary(blocker.get_instance_id(),Stream.BUDGET))
		stream.request_textures(PackedStringArray([path,path]),PackedStringArray([path]))
		if mode=="cancel":
			stream._process_stream()
			owner.queue_free()
		else:
			var deadline := Time.get_ticks_msec()+5000
			if mode=="budget":
				for frame in 4: await parent.get_tree().process_frame
				failures+=int(stream.texture_started!=0 or stream.texture(path)!=null)
				stream.release_auxiliary(blocker.get_instance_id())
			stream.request(PackedStringArray(geometry.keys()),PackedStringArray())
			while stream.texture(path)==null and stream.summary().texture_failures.is_empty() and Time.get_ticks_msec()<deadline:
				await parent.get_tree().process_frame
			if mode=="digest":
				failures+=int(stream.texture(path)!=null or stream.summary().texture_failures.is_empty() or stream.summary().auxiliary_bytes!=0)
			else:
				print("[HLOD stream ready] mode=",mode," ready=",stream.texture(path)!=null," started=",stream.texture_started," charged=",stream.summary().auxiliary_bytes)
				failures+=int(stream.texture(path)==null or stream.texture_started!=1 or stream.summary().auxiliary_bytes!=int(definition.charge))
				for mesh_path: String in geometry:
					while stream.resource(mesh_path)==null and Time.get_ticks_msec()<deadline:
						await parent.get_tree().process_frame
					failures+=int(stream.resource(mesh_path)==null)
				failures+=int(stream.summary().peak_total_bytes>Stream.BUDGET)
				if stream.texture(path)!=null: held=weakref(stream.texture(path))
				stream.request_textures(PackedStringArray(),PackedStringArray([path]))
				await parent.get_tree().process_frame
				failures+=int(stream.texture(path)==null)
				stream.request_textures(PackedStringArray(),PackedStringArray())
				failures+=int(stream.summary().auxiliary_bytes!=int(definition.charge) or stream.texture(path)!=null)
				stream.request_textures(PackedStringArray([path]),PackedStringArray())
				for frame in 3: await parent.get_tree().process_frame
				print("[HLOD stream revived] mode=",mode," ready=",stream.texture(path)!=null," started=",stream.texture_started," cumulative_fail=",failures)
				failures+=int(stream.texture_started!=1 or stream.texture(path)==null)
			owner.queue_free()
		var exit_deadline := Time.get_ticks_msec()+5000
		while stream_ref.get_ref()!=null and Time.get_ticks_msec()<exit_deadline:
			await parent.get_tree().process_frame
		failures+=int(stream_ref.get_ref()!=null or (held!=null and held.get_ref()!=null) or not Stream._busy.is_empty())
		print("[HLOD stream] mode=",mode," cumulative_fail=",failures)
	return worker_failures+failures+await cache_checks(parent)


static func cache_checks(parent: Node) -> int:
	var path := "res://resources/maps/tokyo_volume_preview/hlod_stream_fixture.tres"
	var row := {"sha256":FileAccess.get_sha256(path),"width":4,"height":4,"format":Image.FORMAT_DXT5,"mip_bytes":48,"charge":4240}
	var owner := Node.new()
	parent.add_child(owner)
	var stream := Stream.new()
	parent.add_child(stream)
	if not stream.configure_hlod(owner,{}, {path:row}):
		owner.queue_free();stream.queue_free();return 1
	stream._retain_unused=true
	stream.request_textures(PackedStringArray([path]),PackedStringArray())
	var deadline := Time.get_ticks_msec()+5000
	while stream.texture(path)==null and Time.get_ticks_msec()<deadline: await parent.get_tree().process_frame
	var failures := int(stream.texture(path)==null)
	var held: WeakRef = weakref(stream.texture(path)) if stream.texture(path)!=null else null
	stream.request_textures(PackedStringArray(),PackedStringArray([path]))
	var blocker := RefCounted.new()
	failures+=int(stream.reserve_auxiliary(blocker.get_instance_id(),Stream.BUDGET))
	for frame in 3: await parent.get_tree().process_frame
	failures+=int(stream.texture(path)==null)
	stream.request_textures(PackedStringArray(),PackedStringArray())
	for frame in 3: await parent.get_tree().process_frame
	failures+=int(stream.texture(path)==null)
	stream.request_textures(PackedStringArray([path]),PackedStringArray())
	for frame in 3: await parent.get_tree().process_frame
	failures+=int(stream.texture_started!=1)
	stream.request_textures(PackedStringArray(),PackedStringArray())
	failures+=int(stream.reserve_auxiliary(blocker.get_instance_id(),Stream.BUDGET))
	failures+=int(stream.summary().auxiliary_bytes!=4240 or stream.texture(path)!=null)
	for frame in 4: await parent.get_tree().process_frame
	failures+=int(held!=null and held.get_ref()!=null)
	failures+=int(not stream.reserve_auxiliary(blocker.get_instance_id(),Stream.BUDGET))
	stream.release_auxiliary(blocker.get_instance_id())
	stream.request_textures(PackedStringArray([path]),PackedStringArray())
	deadline=Time.get_ticks_msec()+5000
	while stream.texture(path)==null and Time.get_ticks_msec()<deadline: await parent.get_tree().process_frame
	failures+=int(stream.texture(path)==null or stream.texture_started!=2 or stream.summary().peak_total_bytes>Stream.BUDGET)
	held=weakref(stream.texture(path)) if stream.texture(path)!=null else null
	stream.request_textures(PackedStringArray(),PackedStringArray())
	var stream_ref: WeakRef = weakref(stream)
	owner.queue_free()
	deadline=Time.get_ticks_msec()+5000
	while stream_ref.get_ref()!=null and Time.get_ticks_msec()<deadline: await parent.get_tree().process_frame
	failures+=int(stream_ref.get_ref()!=null or (held!=null and held.get_ref()!=null) or not Stream._busy.is_empty())
	print("[HLOD stream] retained cache fail=",failures)
	return failures
