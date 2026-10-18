extends RefCounted
## 纯规划上下文与旧同步选择的差分；本文件由编排方接入聚焦入口。
const Contract := preload("res://scripts/rendering/tokyo_hlod_manifest.gd")
const Native := preload("res://scripts/rendering/tokyo_hlod_native.gd")
const Catalog := preload("res://scripts/rendering/tokyo_canonical_catalog.gd")
const MIB := 1024*1024


static func context(epoch: int = 1) -> Dictionary:
	return {"background":true,"epoch":epoch,"display_limit":96*MIB,"native_page_limit":16}


static func catalog_fixture() -> Dictionary:
	var rows := {}
	var descriptions := [[0,0,-1,[-100,-100,100,100],1000,6,1.0,[0,1]],
		[1,0,0,[-100,-100,0,100],800,2,2.0,[]],
		[1,1,0,[0,-100,100,100],800,2,2.0,[]],
		[0,1,-1,[400,-50,500,50],200,1,2.0,[]]]
	for item: Array in descriptions:
		var key := "%d:%d" % [int(item[0]),int(item[1])]
		rows[key]={"depth":item[0],"id":item[1],"parent":item[2],"bounds":item[3],"geometry_bounds":[],
			"faces":item[4],"max_scale":item[6],"children":item[7],
			"native_geometry":{"path":"mesh/"+key,"bytes":int(item[5])*MIB},
			"native_texture":{"path":"image/"+key,"three_copy_charge":0,"mip_bytes":0}}
	var roots: Array[Dictionary]=[Contract.tree(rows,0,0),Contract.tree(rows,0,1)]
	return {"rows":rows,"roots":roots,"min_scale":0.1,"max_scale":2.0,"mixed_scales":true,
		"bounds":Rect2(-100,-100,600,200),"identity":{"path":"fixture","sha256":"fixture"}}


static func native_fixture() -> RefCounted:
	var native := Native.new()
	native.catalog=Catalog.new()
	var box := AABB(Vector3(-100,0,-100),Vector3(200,10,200))
	var leaf := {"path":"leaf","boxes":[box,box,box],"triangles":[200,50,20],"bytes":MIB}
	var root := {"path":"root","boxes":[box,box,box],"triangles":[100,25,10],"bytes":2*MIB,"children":[leaf]}
	var partition := root.duplicate(true)
	partition.path="partition";partition.bytes=3*MIB
	native.catalog.configurations={"lod3_full":[root],"lod5_full":[root]}
	native._partition_roots={"lod5_full":[partition]}
	var hybrid := partition.duplicate(true)
	hybrid["ground_replacement"]={"texture":"ground","height_texture":"height","max_scale":2.0}
	hybrid.triangles[2]=2;hybrid.bytes+=2048
	native._ground_roots={"lod5_full":[hybrid]}
	native.ground={"limits":{"lod5_full":2.0}}
	native.pages={"root":{"components":{"root-part":{"bytes":2*MIB}}},
		"partition":{"components":{"partition-part":{"bytes":3*MIB}}},
		"leaf":{"components":{"leaf-part":{"bytes":MIB}}}}
	return native


static func semantic(cut: Dictionary) -> Dictionary:
	var result := cut.duplicate(true)
	result.erase("solver_usec")
	return result


static func manifest_checks() -> int:
	var failures := 0
	var catalog := catalog_fixture()
	var before := var_to_bytes(catalog)
	var work := context()
	# 只对齐旧入口实际的显示上限；后台之后只消费这个纯数值。
	work.display_limit=Contract.display_limit()
	for sample: Array in [[Vector2.ZERO,0.5,0.0],[Vector2.ZERO,1.0,0.3],[Vector2.ZERO,1.5,-0.4],[Vector2(440,0),1.0,0.0]]:
		for budget: int in [5*MIB,96*MIB]:
			var sync := Contract.select(catalog,sample[0],sample[1],sample[2],Vector2(180,120),false,budget)
			var pure := Contract.select(catalog,sample[0],sample[1],sample[2],Vector2(180,120),false,budget,work)
			failures+=int(semantic(sync)!=semantic(pure))
			if sync.is_empty(): continue
			failures+=int(Contract.charges(catalog,sync.keys)!=Contract.charges(catalog,sync.keys,work))
			failures+=int(Contract.retained(catalog,sync,sync,sample[1])!=Contract.retained(catalog,pure,pure,sample[1],false,work))
			var trimmed_sync := Contract.visible_subset(catalog,sync,sample[0],sample[1],sample[2],Vector2(80,80))
			var trimmed_pure := Contract.visible_subset(catalog,pure,sample[0],sample[1],sample[2],Vector2(80,80),work)
			failures+=int(semantic(trimmed_sync)!=semantic(trimmed_pure))
	var builds := int(work.get("builds",0))
	Contract.select(catalog,Vector2(440,0),1.0,0.0,Vector2(180,120),false,96*MIB,work)
	failures+=int(int(work.get("builds",0))!=builds)
	work.epoch+=1
	Contract.select(catalog,Vector2(440,0),1.0,0.0,Vector2(180,120),false,96*MIB,work)
	failures+=int(int(work.get("builds",0))!=builds+1)
	var costs := {"0:0":0,"1:0":288,"1:1":2*MIB+288,"0:1":MIB+288}
	for scale: float in [0.5,1.5]:
		var sync := Contract.select_handoff(catalog,Vector2.ZERO,scale,0.2,Vector2(180,120),3*MIB,costs)
		var pure := Contract.select_handoff(catalog,Vector2.ZERO,scale,0.2,Vector2(180,120),3*MIB,costs,work)
		failures+=int(semantic(sync)!=semantic(pure))
		if scale>1.0: failures+=int(pure.get("keys")!=PackedStringArray(["1:0","1:1"]))
	var limited := context()
	limited.display_limit=MIB
	failures+=int(Contract.charges(catalog,PackedStringArray(["0:0"]),limited).within_budget)
	failures+=int(not Contract.select(catalog,Vector2.ZERO,0.5,0.0,Vector2(180,120),false,2*MIB,limited).is_empty())
	failures+=int(var_to_bytes(catalog)!=before)
	return failures


static func native_checks() -> int:
	var failures := 0
	var native := native_fixture()
	var snapshot: Dictionary=native.selection_snapshot()
	var worker_native := Native.new()
	failures+=int(snapshot.is_empty() or not Native._selection_value_is_pure(snapshot))
	failures+=int(not worker_native.configure_selection_snapshot(snapshot,context()))
	failures+=int(worker_native.catalog!=null or not worker_native.coverage.is_empty())
	var saved := var_to_bytes(snapshot)
	for configuration: String in ["lod3_full","lod5_full"]:
		for scale: float in [1.0,2.5]:
			for resident: Dictionary in [{},{"meshes":{"root-part":true,"partition-part":true,"leaf-part":true},"textures":{"ground":true,"height":true}}]:
				var sync: Dictionary=native.select(Vector2.ZERO,scale,0.2,Vector2(180,120),configuration,96*MIB,resident)
				var pure: Dictionary=worker_native.select(Vector2.ZERO,scale,0.2,Vector2(180,120),configuration,96*MIB,resident)
				failures+=int(semantic(sync)!=semantic(pure))
				var canvas := Transform2D(0.2,Vector2(90,60)).scaled_local(Vector2.ONE*scale)
				var view := Rect2(-100,-100,200,200)
				failures+=int(native.covers_visible_layers(sync,view,canvas,Vector2(180,120))!=worker_native.covers_visible_layers(pure,view,canvas,Vector2(180,120)))
	var builds := worker_native.solver_builds
	worker_native.select(Vector2.ZERO,2.5,0.2,Vector2(180,120),"lod5_full")
	failures+=int(worker_native.solver_builds!=builds)
	worker_native.selection_context.epoch+=1
	worker_native.select(Vector2.ZERO,2.5,0.2,Vector2(180,120),"lod5_full")
	failures+=int(worker_native.solver_builds!=builds+1)
	failures+=int(var_to_bytes(snapshot)!=saved)
	# 配置后修改原快照与原目录均不得改变已冻结来源。
	var prior: Dictionary=worker_native.select(Vector2.ZERO,1.0,0.0,Vector2(180,120),"lod3_full")
	snapshot.configurations.lod3_full[0].bytes=90*MIB
	native.catalog.configurations.lod3_full[0].bytes=91*MIB
	worker_native.selection_context.epoch+=1
	failures+=int(semantic(prior)!=semantic(worker_native.select(Vector2.ZERO,1.0,0.0,Vector2(180,120),"lod3_full")))
	var invalid: Dictionary=native.selection_snapshot()
	invalid["unsafe"]=native
	failures+=int(worker_native.configure_selection_snapshot(invalid,context()))
	for bad: Dictionary in [{},{"background":true,"epoch":-1,"display_limit":96*MIB,"native_page_limit":16},
		{"background":true,"epoch":1,"display_limit":96*MIB,"native_page_limit":17}]:
		failures+=int(worker_native.configure_selection_snapshot(native.selection_snapshot(),bad))
	return failures


static func prepared_checks() -> int:
	var failures := 0
	var source := preload("res://scripts/tests/test_tokyo_prepared_catalog.gd").catalog()
	var artifact := preload("res://scripts/rendering/tokyo_prepared_catalog.gd").build(source)
	if artifact.is_empty(): return 1
	var unchanged := var_to_bytes(artifact)
	var work := context()
	work["prepared_catalogs"]={source.identity.path:artifact}
	var legacy := context()
	for scale: float in [0.0001,0.05,0.06,0.0600000001,0.08,0.1,0.06]:
		failures+=int(Contract.qualified_roots(source,scale,work)!=Contract.qualified_roots(source,scale,legacy))
	failures+=int(int(work.get("prepared_reuses",0))!=7 or int(work.get("qualification_builds",0))!=0)
	for scale: float in [0.05,0.06,0.08]:
		for budget: int in [0,48*MIB,96*MIB]:
			var fresh := Contract.select(source,Vector2.ZERO,scale,0.2,Vector2(160,90),true,budget,legacy)
			var prepared := Contract.select(source,Vector2.ZERO,scale,0.2,Vector2(160,90),true,budget,work)
			failures+=int(semantic(fresh)!=semantic(prepared))
	# 已登记但失效的来源不能退回旧资格树；完全没有预制表的fixture仍允许旧入口。
	work.prepared_catalogs[source.identity.path]={}
	failures+=int(not Contract.qualified_roots(source,0.08,work).is_empty())
	failures+=int(int(work.get("qualification_builds",0))!=0)
	work.prepared_catalogs.erase(source.identity.path)
	failures+=int(Contract.qualified_roots(source,0.08,work)!=Contract.qualified_roots(source,0.08,legacy))
	failures+=int(var_to_bytes(artifact)!=unchanged)
	return failures


static func _background_batch(job: Dictionary) -> void:
	var native := Native.new()
	var work: Dictionary=job.context.duplicate(true)
	if not native.configure_selection_snapshot(job.native,work):
		job.result={"invalid":true}
		return
	var cut := Contract.select(job.catalog,Vector2.ZERO,0.5,0.2,Vector2(180,120),false,96*MIB,work)
	var bridge := Contract.select_handoff(job.catalog,Vector2.ZERO,1.5,0.2,Vector2(180,120),3*MIB,
		{"0:0":0,"1:0":288,"1:1":2*MIB+288,"0:1":MIB+288},work)
	job.result={"cut":semantic(cut),"bridge":semantic(bridge),
		"trim":semantic(Contract.visible_subset(job.catalog,cut,Vector2.ZERO,0.5,0.2,Vector2(80,80),work)),
		"retained":Contract.retained(job.catalog,cut,cut,0.5,false,work),
		"native":semantic(native.select(Vector2.ZERO,1.0,0.2,Vector2(180,120),"lod5_full"))}


static func run(parent: Node) -> int:
	var failures := manifest_checks()+native_checks()+prepared_checks()
	var native := native_fixture()
	var job := {"catalog":catalog_fixture(),"native":native.selection_snapshot(),"context":context(),"result":{}}
	var reference := job.duplicate(true)
	_background_batch(reference)
	var task := WorkerThreadPool.add_task(_background_batch.bind(job),false,"Tokyo pure selection test")
	var deadline := Time.get_ticks_msec()+5000
	while not WorkerThreadPool.is_task_completed(task) and Time.get_ticks_msec()<deadline:
		await parent.get_tree().process_frame
	failures+=int(not WorkerThreadPool.is_task_completed(task))
	WorkerThreadPool.wait_for_task_completion(task)
	failures+=int(job.result!=reference.result)
	print("[Tokyo selection context] fail=",failures)
	return failures
