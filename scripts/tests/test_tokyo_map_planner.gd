extends RefCounted
const Planner := preload("res://scripts/rendering/tokyo_map_planner.gd")
const Overlay := preload("res://scripts/rendering/tokyo_hlod_overlay.gd")
const Prepared := preload("res://scripts/rendering/tokyo_prepared_catalog.gd")
const Fixture := preload("res://scripts/tests/test_tokyo_prepared_catalog.gd")
const Contract := preload("res://scripts/rendering/tokyo_hlod_manifest.gd")
const Handoff := preload("res://scripts/rendering/tokyo_hlod_handoff.gd")
const Worker := preload("res://scripts/rendering/tokyo_map_plan_worker.gd")
const BUDGET := 96 * 1024 * 1024


class GuardPool extends Node:
	var residency_limit := BUDGET
	var residency_bytes := 0
	var residency_meshes := PackedStringArray()
	var residency_images := PackedStringArray()


class NativeRetentionOverlay extends "res://scripts/rendering/tokyo_hlod_overlay.gd":
	var coverage_probe: RefCounted
	func _cut_covers_current_view(cut: Dictionary, catalog: int, margin_px: float = 0.0) -> bool:
		return coverage_probe._cut_covers_current_view(cut,catalog,margin_px)


static func source_fixture() -> Dictionary:
	var catalog := Fixture.catalog()
	catalog["range"] = [0.05, 0.1]
	var prepared := Prepared.build(catalog)
	return {"catalogs": [catalog], "prepared_catalogs": {catalog.identity.path: prepared},
		"geometry": catalog.geometry.duplicate(true), "textures": catalog.textures.duplicate(true),
		"foundation": {}, "bounds": catalog.bounds, "native": {}, "flags": {},
		"context": {"background": true, "epoch": 0, "display_limit": BUDGET, "native_page_limit": 16}}


static func request_fixture(center: Vector2, scale: float, angle: float = 0.0,
		size: Vector2 = Vector2(100, 70), sequence: int = 1) -> Dictionary:
	var canvas := Transform2D(angle, Vector2.ZERO).scaled(Vector2.ONE * scale)
	canvas.origin = size * 0.5 - canvas * center
	return {"sequence": sequence, "canvas": canvas, "size": size, "logical": size,
		"scale": scale, "zooming_out": false, "pan_velocity": Vector2.ZERO, "zoom_rate": 0.0,
		"committed_catalog": -1, "committed": {}, "target_catalog": -1, "target": {},
		"stream": {"residency_limit": BUDGET, "residency_bytes": 0,
			"residency_meshes": PackedStringArray(), "residency_images": PackedStringArray(),
			"_cache": {}, "_textures": {}}}


static func comparable_cut(cut: Dictionary) -> Dictionary:
	var result := Planner.compact_cut(cut)
	result.erase("solver_usec")
	return result


static func differential_checks() -> int:
	var source := source_fixture()
	var before := var_to_bytes(source)
	var planner := Planner.new()
	if not planner.configure(source): return 1
	# 旧同步helper作为独立参照：不接SceneTree、不加载网格或贴图，仍走旧即时资格树。
	var legacy := Overlay.new()
	legacy._catalogs.assign(source.catalogs)
	legacy._geometry = source.geometry
	legacy._textures = source.textures
	legacy._small_uploads = false
	legacy.display_budget = BUDGET
	legacy._selection_work = {}
	var failures := 0
	var sequence := 0
	for center: Vector2 in [Vector2.ZERO, Vector2(7000, -4000), Vector2(-14000, 8000)]:
		for scale: float in [0.055, 0.06, 0.0600000001, 0.08, 0.1, 0.06]:
			for angle: float in [0.0, 0.2]:
				sequence += 1
				var request := request_fixture(center, scale, angle, Vector2(100, 70), sequence)
				var request_before := var_to_bytes(request)
				var expected := legacy._select_hlod(source.catalogs[0], center, scale, angle, request.size, true, BUDGET / 2)
				if not expected.is_empty() and not expected.within_budget:
					expected = legacy._select_hlod(source.catalogs[0], center, scale, angle, request.size, true)
				var result := planner.plan(request)
				var okay: bool=not expected.is_empty() and expected.within_budget \
					and result.status == "candidate" and result.catalog == 0 \
					and comparable_cut(result.cut) == comparable_cut(expected)
				if not okay:
					print("[Tokyo planner] differential mismatch center=", center, " scale=", scale,
						" angle=", angle, " status=", result.status,
						" expected=", expected.get("keys", []), " actual=", result.cut.get("keys", []))
				failures += int(not okay or not Worker.pure(result))
				failures += int(var_to_bytes(source) != before or var_to_bytes(request) != request_before)
				failures += int(int(result.stats.qualification_builds) != 0 or int(result.stats.prepared_reuses) <= 0)
	# 没有目录资格时必须明确报告无解，不能复用上次候选冒充当前视野。
	var unsupported := planner.plan(request_fixture(Vector2.ZERO, 0.11, 0.0, Vector2(100, 70), sequence + 1))
	failures += int(unsupported.status != "no_solution" or not unsupported.cut.is_empty())
	legacy.free()
	print("[Tokyo planner] differential cases=", sequence, " fail=", failures)
	return failures


static func native_bridge_checks() -> int:
	var source := source_fixture()
	var box := AABB(Vector3(-25, 0, -25), Vector3(50, 1, 50))
	var inside := {"path": "inside", "bytes": 10, "triangles": [10, 0, 0],
		"boxes": [box, AABB(), AABB()], "children": []}
	var outside := inside.duplicate(true)
	outside.path = "outside"
	outside.boxes[0] = AABB(Vector3(50, 0, -10), Vector3(20, 1, 20))
	var root := {"path": "root", "bytes": 100, "triangles": [100, 0, 0],
		"boxes": [AABB(Vector3(-100, 0, -100), Vector3(200, 1, 200)), AABB(), AABB()],
		"children": [inside, outside]}
	var pages := {}
	for entry: Dictionary in [root, inside, outside]:
		pages[entry.path] = {"components": {entry.path: true}}
		source.geometry[entry.path] = {"components": {entry.path: {"bytes": int(entry.bytes)}}}
	source.native = {"schema": 1, "catalog_sha": "fixture", "configurations": {"lod5_full": [root]},
		"partition_roots": {}, "ground_roots": {}, "ground_limits": {}, "pages": pages}
	source.flags = {"cached_cut": true, "native_screen_bridge": true}
	var request := request_fixture(Vector2.ZERO, 1.7)
	request.committed_catalog = 0
	request.committed = {"keys": PackedStringArray(["0:0"]), "charges": {"ground_bytes": 288}}
	request.stream._cache = {"inside": true}
	var original := var_to_bytes(source)
	var request_original := var_to_bytes(request)
	var planner := Planner.new()
	if not planner.configure(source): return 1
	var result := planner.plan(request)
	# 扩区切面需要inside+outside，而实际屏内只需已驻留inside。必须完整接住屏幕，
	# 不能因非空stream被误判为无效，也不能把尚未就绪outside从后续预取丢掉。
	var failures := int(result.status != "candidate" or result.catalog != -2)
	failures += int(result.cut.get("keys") != PackedStringArray(["inside"]))
	failures += int(not result.cut.get("native_screen_bridge", false) or not result.cut.get("cache_bridge", false))
	failures += int(result.native_screen_bridge.get("reason") != "ready")
	failures += int({"mesh": "outside", "image": ""} not in result.cut.get("prefetch_extra", []))
	failures += int(var_to_bytes(source) != original or var_to_bytes(request) != request_original or not Worker.pure(result))
	# 关闭这一明确对照开关时，保持原完整guard候选，不能偷偷把缓存偏好变成常态政策。
	source.flags.native_screen_bridge = false
	var control := Planner.new()
	if not control.configure(source): return failures + 1
	var plain := control.plan(request)
	failures += int(plain.status != "candidate" or plain.cut.get("native_screen_bridge", false))
	failures += int(plain.cut.get("keys") != PackedStringArray(["inside", "outside"]))
	print("[Tokyo planner] native_bridge fail=", failures)
	return failures


static func mixed_cached_hlod_checks() -> int:
	var cached := preload("res://scripts/rendering/tokyo_hlod_cached_cut.gd")
	var source := source_fixture()
	var catalog: Dictionary=source.catalogs[0]
	var original := var_to_bytes(source)
	var meshes := {}
	var images := {}
	for path: String in catalog.geometry: meshes[path]=true
	for path: String in catalog.textures: images[path]=true
	var work: Dictionary=source.context.duplicate(true)
	work["prepared_catalogs"]=source.prepared_catalogs.duplicate()
	# 无身份来源的拒绝哨兵：旧实现擦除identity后再次资格查询会得到空根，
	# 因而下面非空且等值的断言必失败；正常入口先以真实身份认证一次即可。
	work.prepared_catalogs[""]={}
	var reference: Dictionary=source.context.duplicate(true)
	reference["prepared_catalogs"]=source.prepared_catalogs
	var failures := 0
	var samples: Array[float]=[0.06,0.0600000001,0.08,0.1,0.06]
	for scale: float in samples:
		var expected := Contract.select(catalog,Vector2.ZERO,scale,0.2,Vector2(160,90),false,BUDGET,reference)
		var actual: Dictionary=cached.select(catalog,Vector2.ZERO,scale,0.2,Vector2(160,90),
			catalog.geometry,meshes,images,work)
		failures+=int(expected.is_empty() or not expected.get("within_budget",false) or actual.is_empty() \
			or comparable_cut(actual)!=comparable_cut(expected))
		if scale>0.06:
			for key: String in actual.get("keys",PackedStringArray()): failures+=int(not key.begins_with("2:"))
	# 每次缓存查询仅消费一次已认证区间，不能悄悄回到无身份的整树资格构建。
	failures+=int(int(work.get("prepared_reuses",0))!=samples.size() or int(work.get("qualification_builds",0))!=0)
	var baseline := Contract.select(catalog,Vector2.ZERO,0.08,0.2,Vector2(160,90),false,BUDGET,reference)
	if baseline.get("keys",PackedStringArray()).is_empty(): return failures+1
	var missing_key: String=baseline.keys[0]
	var incomplete_meshes := meshes.duplicate()
	incomplete_meshes.erase(catalog.rows[missing_key].native_geometry.path)
	var incomplete_images := images.duplicate()
	incomplete_images.erase(catalog.rows[missing_key].native_texture.path)
	# 所有父页仍已驻留，但尺度超过0.06；缺一可见叶块不能退回失格父页，
	# 也不能借前一次同相机结果绕过此次真实驻留集合。
	failures+=int(not cached.select(catalog,Vector2.ZERO,0.08,0.2,Vector2(160,90),
		catalog.geometry,incomplete_meshes,images,work).is_empty())
	failures+=int(not cached.select(catalog,Vector2.ZERO,0.08,0.2,Vector2(160,90),
		catalog.geometry,meshes,incomplete_images,work).is_empty())
	var restored: Dictionary=cached.select(catalog,Vector2.ZERO,0.08,0.2,Vector2(160,90),
		catalog.geometry,meshes,images,work)
	failures+=int(restored.is_empty() or comparable_cut(restored)!=comparable_cut(baseline))
	failures+=int(var_to_bytes(source)!=original)
	print("[Tokyo planner] mixed_cached_hlod fail=",failures)
	return failures


static func trim_covers_pose(catalog: Dictionary, cut: Dictionary, center: Vector2, angle: float, size: Vector2) -> bool:
	var request := request_fixture(center,1.0,angle,size)
	var inverse: Transform2D=request.canvas.affine_inverse()
	var view := Rect2(inverse*Vector2.ZERO,Vector2.ZERO)
	for point: Vector2 in [Vector2(size.x,0),size,Vector2(0,size.y)]: view=view.expand(inverse*point)
	return Handoff.covers_projection(catalog,cut,view,request.canvas,size)


static func directional_trim_checks() -> int:
	var work := {"background":true,"epoch":0,"display_limit":BUDGET,"native_page_limit":16}
	var failures := 0
	# 每页20MiB：原切面三页可共存，方向性裁页必须真实释放后方页，不能抬预算。
	for direction: float in [1.0,-1.0]:
		var roots: Array[Dictionary]=[]
		var rows := {}
		for index in 3:
			var key := "0:%d"%index
			# 投影自带8世界单位余量；ahead当前仍离屏，60ms后进入此真实包络。
			var x: float=[0.0,68.0,-85.0][index]*direction
			var box := AABB(Vector3(x-5.0,0.0,-10.0),Vector3(10.0,0.0,20.0))
			roots.append({"key":key,"bytes":20*1024*1024+1024+288,"triangles":[12,0,0],
				"boxes":[box,AABB(),AABB()],"children":[]})
			rows[key]={"depth":0,"parent":-1,"faces":12,"children":[],"max_scale":2.0,
				"native_geometry":{"path":key+".mesh","bytes":20*1024*1024},
				"native_texture":{"path":key+".image","three_copy_charge":1024}}
		var catalog := {"roots":roots,"rows":rows,"min_scale":0.1,"max_scale":2.0}
		var original := var_to_bytes(catalog)
		for angle: float in [0.0,PI*0.5]:
			var size := Vector2(100,70) if angle==0.0 else Vector2(70,100)
			var old_size := Vector2(300,70) if angle==0.0 else Vector2(70,300)
			var old := Contract.select(catalog,Vector2.ZERO,1.0,angle,old_size,false,BUDGET,work)
			var old_original := var_to_bytes(old)
			var lead := Vector2(50.0*direction,0.0)
			var bare := Contract.visible_subset(catalog,old,Vector2.ZERO,1.0,angle,size,work)
			var zero := Contract.visible_subset(catalog,old,Vector2.ZERO,1.0,angle,size,work,Vector2.ZERO)
			var guarded := Contract.visible_subset(catalog,old,Vector2.ZERO,1.0,angle,size,work,lead)
			var future_center := Vector2(200.0*direction,0.0)*0.06
			failures+=int(old.get("keys")!=PackedStringArray(["0:0","0:1","0:2"]))
			failures+=int(bare.get("keys")!=PackedStringArray(["0:0"]) or comparable_cut(bare)!=comparable_cut(zero))
			failures+=int(guarded.get("keys")!=PackedStringArray(["0:0","0:1"]) \
				or guarded.get("trim_lead_world")!=lead or not guarded.get("within_budget",false))
			failures+=int(int(guarded.get("bytes",BUDGET+1))>=int(old.get("bytes",0)) \
				or int(guarded.get("bytes",BUDGET+1))>BUDGET)
			# 裸裁当前完整，但60ms后需要ahead；方向性裁页同时保留两姿态且删去behind。
			failures+=int(not trim_covers_pose(catalog,bare,Vector2.ZERO,angle,size) \
				or trim_covers_pose(catalog,bare,future_center,angle,size))
			failures+=int(not trim_covers_pose(catalog,guarded,Vector2.ZERO,angle,size) \
				or not trim_covers_pose(catalog,guarded,future_center,angle,size))
			var query_size := size+(Transform2D(angle,Vector2.ZERO).basis_xform(lead)).abs()
			failures+=int(not trim_covers_pose(catalog,guarded,lead*0.5,angle,query_size))
			# 原切面缺ahead时，子集仍可能费用合格；必须由完整目录的覆盖核验拒绝。
			var incomplete := old.duplicate(true)
			incomplete.entries.remove_at(1)
			var incomplete_trim := Contract.visible_subset(catalog,incomplete,Vector2.ZERO,1.0,angle,size,work,lead)
			failures+=int(not incomplete_trim.get("within_budget",false) \
				or trim_covers_pose(catalog,incomplete_trim,lead*0.5,angle,query_size))
			failures+=int(var_to_bytes(old)!=old_original or var_to_bytes(catalog)!=original \
				or not Worker.pure(guarded))
	print("[Tokyo planner] directional_trim fail=",failures)
	return failures


static func guard_retry_source(far_x: float, old_mib: int) -> Dictionary:
	var roots: Array[Dictionary]=[]
	var rows := {}
	var geometry := {}
	var textures := {}
	var pages := {}
	for index in 4:
		var key := "0:%d"%index
		var x: float=[10000.0,0.0,80.0,far_x][index]
		var cost: int=[old_mib,20,35,45][index]*1024*1024
		roots.append({"key":key,"path":key,"bytes":cost+288,"triangles":[12,0,0],
			"boxes":[AABB(Vector3(x-5.0,0.0,-10.0),Vector3(10.0,0.0,20.0)),AABB(),AABB()],"children":[]})
		rows[key]={"depth":0,"parent":-1,"faces":12,"children":[],"max_scale":2.0,
			"native_geometry":{"path":key,"bytes":cost},
			"native_texture":{"path":key+".image","three_copy_charge":0}}
		geometry[key]={"bytes":cost}
		textures[key+".image"]={"charge":0}
		pages[key]={"components":{key:true}}
	var bounds := Rect2(-1000,-1000,12000,2000)
	var catalog := {"roots":roots,"rows":rows,"min_scale":0.0,"max_scale":2.0,"range":[0.0,2.0],"bounds":bounds}
	return {"catalogs":[catalog],"prepared_catalogs":{},"geometry":geometry,"textures":textures,
		"foundation":{},"bounds":bounds,"flags":{},
		"native":{"schema":1,"catalog_sha":"guard-fixture","configurations":{"lod5_full":roots},
			"partition_roots":{},"ground_roots":{},"ground_limits":{},"pages":pages},
		"context":{"background":true,"epoch":0,"display_limit":BUDGET,"native_page_limit":16}}


static func guard_budget_retry_checks() -> int:
	var failures := 0
	var size := Vector2(100,70)
	for wanted_guard: float in [96.0,48.0]:
		for old_mib: int in [20,50]:
			var source := guard_retry_source(185.0 if wanted_guard==96.0 else 130.0,old_mib)
			var original := var_to_bytes(source)
			var catalog: Dictionary=source.catalogs[0]
			var planner := Planner.new()
			if not planner.configure(source):
				failures+=1
				continue
			var legacy := Overlay.new()
			legacy._catalogs.assign(source.catalogs)
			legacy._geometry=source.geometry;legacy._textures=source.textures
			legacy._selection_work=source.context.duplicate(true);legacy.display_budget=BUDGET
			legacy._stream=GuardPool.new()
			legacy._native=preload("res://scripts/rendering/tokyo_hlod_native.gd").new()
			if not legacy._native.configure_selection_snapshot(source.native,source.context): failures+=1
			planner._stream=request_fixture(Vector2.ZERO,1.0).stream
			# 192px需100MiB；两档中间保护都超过48MiB，而裸视野仅20MiB。
			# 旧代码只重试192px，所以在所有可行正例中必退到guard0。
			var wide := Contract.select(catalog,Vector2.ZERO,1.0,0.0,size+Vector2.ONE*384.0,false,BUDGET,source.context)
			var required := Contract.select(catalog,Vector2.ZERO,1.0,0.0,size+Vector2.ONE*wanted_guard*2.0,false,BUDGET,source.context)
			failures+=int(wide.get("within_budget",true) or not required.get("within_budget",false) \
				or int(required.get("bytes",0))<=BUDGET/2)
			for guard: float in [96.0,48.0]:
				var half := Contract.select(catalog,Vector2.ZERO,1.0,0.0,size+Vector2.ONE*guard*2.0,false,BUDGET/2,source.context)
				failures+=int(half.get("within_budget",true))
			for native: bool in [false,true]:
				var old: Dictionary=planner._native.select(Vector2(10000,0),1.0,0.0,size,"lod5_full",BUDGET) if native \
					else Contract.select(catalog,Vector2(10000,0),1.0,0.0,size,false,BUDGET,source.context)
				planner._committed_catalog=-2 if native else 0
				planner._committed_cut=old;planner._committed=old.keys
				legacy._committed_catalog=planner._committed_catalog
				legacy._committed_cut=old;legacy._committed=old.keys
				var actual: Dictionary=planner._select_native(Vector2.ZERO,1.0,0.0,size,"lod5_full",BUDGET/2,false) if native \
					else planner._select_hlod(catalog,Vector2.ZERO,1.0,0.0,size,false,BUDGET/2)
				var synchronous: Dictionary=legacy._select_native(Vector2.ZERO,1.0,0.0,size,"lod5_full",BUDGET/2,false) if native \
					else legacy._select_hlod(catalog,Vector2.ZERO,1.0,0.0,size,false,BUDGET/2)
				var accepted := old_mib==20
				var expected_keys := PackedStringArray(["0:1","0:2"]) if accepted else PackedStringArray(["0:1"])
				var expected_guard := wanted_guard if accepted else 0.0
				var combined := planner._handoff_bytes(actual,planner._committed_catalog)
				failures+=int(actual.get("keys")!=expected_keys or actual.get("spatial_guard_px")!=expected_guard \
					or not actual.get("within_budget",false) or int(actual.get("active",17))>16 \
					or int(actual.get("triangles",240001))>240000 or combined<0 or combined>BUDGET)
				failures+=int(comparable_cut(actual)!=comparable_cut(synchronous))
				# 50MiB旧页+55MiB保护切面虽然分别合格，联合超96MiB仍必须退回裸视野。
				var required_union := planner._handoff_bytes(required,0)
				failures+=int((required_union<=BUDGET)!=accepted or required_union<0)
				failures+=int(var_to_bytes(source)!=original or not Worker.pure(actual))
			legacy._stream.free()
			legacy.free()
	print("[Tokyo planner] guard_budget_retry fail=",failures)
	return failures


static func motion_guard_source(side_mib: int) -> Dictionary:
	# 实际档(0.5,2]一页40MiB覆盖全图；提前细档(2,4]中心10MiB，左右各一页在裸视野外、48px保护带内。
	var bounds := Rect2(-1000,-1000,2000,2000)
	var geometry := {}
	var textures := {}
	var catalogs: Array[Dictionary]=[]
	for level in 2:
		var prefix: String=["coarse","finer"][level]
		var roots: Array[Dictionary]=[]
		var rows := {}
		var layout: Array=[[0.0,40,900.0]] if level==0 else [[0.0,10,5.0],[60.0,side_mib,5.0],[-60.0,side_mib,5.0]]
		for index in layout.size():
			var key := "0:%d"%index
			var path := "%s/%s"%[prefix,key]
			var x: float=layout[index][0]
			var half: float=layout[index][2]
			var cost: int=int(layout[index][1])*1024*1024
			roots.append({"key":key,"path":path,"bytes":cost+288,"triangles":[12,0,0],
				"boxes":[AABB(Vector3(x-half,0.0,-half if level==0 else -10.0),Vector3(half*2.0,0.0,half*2.0 if level==0 else 20.0)),AABB(),AABB()],"children":[]})
			rows[key]={"depth":0,"parent":-1,"faces":12,"children":[],"max_scale":[2.0,4.0][level],
				"native_geometry":{"path":path,"bytes":cost},"native_texture":{"path":path+".image","three_copy_charge":0}}
			geometry[path]={"bytes":cost}
			textures[path+".image"]={"charge":0}
		catalogs.append({"roots":roots,"rows":rows,"min_scale":[0.5,2.0][level],"max_scale":[2.0,4.0][level],
			"range":[[0.5,2.0],[2.0,4.0]][level],"bounds":bounds})
	return {"catalogs":catalogs,"prepared_catalogs":{},"geometry":geometry,"textures":textures,
		"foundation":{},"bounds":bounds,"native":{},"flags":{},
		"context":{"background":true,"epoch":0,"display_limit":BUDGET,"native_page_limit":16}}


static func motion_guard_actual_checks() -> int:
	var failures := 0
	var size := Vector2(100,70)
	# 场景：[侧页MiB, 平移速度, 缩放率, 已提交细档切面, 期望目录, 期望保护带]
	for scenario: Array in [[50,Vector2.ZERO,0.0,false,1,0.0],[50,Vector2(400,0),0.0,false,0,192.0],
			[50,Vector2(-400,0),0.0,false,0,192.0],[10,Vector2(400,0),0.0,false,1,192.0],
			[50,Vector2(400,0),2.5,false,1,0.0],[50,Vector2(400,0),0.0,true,1,0.0]]:
		var source := motion_guard_source(int(scenario[0]))
		var original := var_to_bytes(source)
		var planner := Planner.new()
		if not planner.configure(source):
			failures+=1
			continue
		var request := request_fixture(Vector2.ZERO,1.2,0.0,size)
		request.pan_velocity=scenario[1];request.zoom_rate=scenario[2]
		if scenario[3]:
			# 旧细档中心+右页60MiB；实际档40MiB保护切面与其联合100MiB超池，必须保持原裸切面。
			var old := Contract.select(source.catalogs[1],Vector2(20,0),1.2,0.0,size,true,BUDGET,source.context)
			request.committed_catalog=1;request.committed=Planner.compact_cut(old)
			failures+=int(old.get("keys")!=PackedStringArray(["0:0","0:1"]))
		var request_original := var_to_bytes(request)
		var result := planner.plan(request)
		var expected_catalog: int=scenario[4]
		var moving: bool=scenario[1]!=Vector2.ZERO
		var okay: bool=result.status=="candidate" and result.catalog==expected_catalog \
			and is_equal_approx(float(result.cut.get("spatial_guard_px",-1)),float(scenario[5])) \
			and int(result.stats.motion_actual_cuts)==int(expected_catalog==0)
		if expected_catalog==0:
			# 实际档只替换显示；细档资源仍由预测预取准备，需求按0.25秒平移计算。
			okay=okay and int(result.cut.get("prefetch_catalog",-1))==1 and not result.cut.get("prefetch_keys",PackedStringArray()).is_empty() \
				and is_equal_approx(float(result.cut.get("motion_guard_need_px",0)),Handoff.motion_guard_need(scenario[1],1.2,size)) \
				and Handoff.qualified(source.catalogs[0],result.cut,1.2)
		elif not moving or int(scenario[0])==10:
			okay=okay and not result.cut.has("motion_guard_need_px")
		if not okay: print("[Tokyo planner] motion_guard mismatch scenario=",scenario," catalog=",result.catalog," guard=",result.cut.get("spatial_guard_px")," stats=",result.stats.motion_actual_cuts)
		failures+=int(not okay or not Worker.pure(result) or var_to_bytes(source)!=original or var_to_bytes(request)!=request_original)
		# 同步兼容路径同一规则、同一结果。
		var legacy := Overlay.new()
		legacy._catalogs.assign(source.catalogs)
		legacy._geometry=source.geometry;legacy._textures=source.textures
		legacy._selection_work=source.context.duplicate(true);legacy.display_budget=BUDGET
		legacy._stream=GuardPool.new()
		legacy._pan_velocity=scenario[1];legacy._zoom_rate=scenario[2]
		planner._pan_velocity=scenario[1];planner._zoom_rate=scenario[2]
		if scenario[3]:
			legacy._committed_catalog=1;legacy._committed_cut=request.committed;legacy._committed=PackedStringArray(request.committed.keys)
		var bare: Dictionary=planner._select_hlod(source.catalogs[1],Vector2.ZERO,1.2,0.0,size,true,BUDGET/2)
		if not bare.is_empty() and not bare.within_budget: bare=planner._select_hlod(source.catalogs[1],Vector2.ZERO,1.2,0.0,size,true)
		var planned: Dictionary=planner._motion_guarded_actual(1,bare,Vector2.ZERO,1.2,0.0,size,BUDGET)
		var synchronous: Dictionary=legacy._motion_guarded_actual(1,bare,Vector2.ZERO,1.2,0.0,size,BUDGET)
		failures+=int(comparable_cut(planned)!=comparable_cut(synchronous) or planned.is_empty()!=(expected_catalog==1))
		legacy._stream.free();legacy.free()
	print("[Tokyo planner] motion_guard_actual fail=",failures)
	return failures


static func native_motion_source(direction: float, ahead_faces: int, old_mib: int) -> Dictionary:
	var source := source_fixture()
	var roots: Array[Dictionary]=[]
	var geometry := {}
	var pages := {}
	for index in 4:
		var path: String=["old","inside","ahead","far"][index]
		var x: float=[10000.0,0.0,68.0,95.0][index]*direction
		var cost: int=[old_mib,20,35,5][index]*1024*1024
		var faces: int=[12,180000,ahead_faces,30000][index]
		roots.append({"path":path,"bytes":cost,"triangles":[faces,0,0],
			"boxes":[AABB(Vector3(x-5.0,0.0,-10.0),Vector3(10.0,0.0,20.0)),AABB(),AABB()],"children":[]})
		geometry[path]={"bytes":cost}
		pages[path]={"components":{path:true}}
	source.geometry=geometry;source.textures={}
	source.bounds=Rect2(-12000,-1000,24000,2000)
	source.native={"schema":1,"catalog_sha":"motion-fixture","configurations":{"lod5_full":roots},
		"partition_roots":{},"ground_roots":{},"ground_limits":{},"pages":pages}
	return source


static func native_motion_guard_checks() -> int:
	var failures := 0
	for direction: float in [1.0,-1.0]:
		for angle: float in [0.0,PI*0.5]:
			var size := Vector2(100,70) if angle==0.0 else Vector2(70,100)
			for scenario: String in ["accept","union_rejected","faces_rejected"]:
				var source := native_motion_source(direction,70000 if scenario=="faces_rejected" else 40000,
					50 if scenario=="union_rejected" else 20)
				var original := var_to_bytes(source)
				var planner := Planner.new()
				if not planner.configure(source):
					failures+=1
					continue
				planner._stream=request_fixture(Vector2.ZERO,1.0).stream
				planner._pan_velocity=Vector2(200.0*direction,0.0)
				var legacy := Overlay.new()
				legacy._geometry=source.geometry;legacy._textures=source.textures
				legacy._selection_work=source.context.duplicate(true);legacy.display_budget=BUDGET
				legacy._stream=GuardPool.new();legacy._pan_velocity=planner._pan_velocity
				legacy._native=preload("res://scripts/rendering/tokyo_hlod_native.gd").new()
				if not legacy._native.configure_selection_snapshot(source.native,source.context): failures+=1
				var old: Dictionary=planner._native.select(Vector2(10000.0*direction,0.0),1.0,angle,size,"lod5_full",BUDGET)
				planner._committed_catalog=-2;planner._committed_cut=old;planner._committed=old.keys
				legacy._committed_catalog=-2;legacy._committed_cut=old;legacy._committed=old.keys
				var lead := Handoff.pan_lead(planner._pan_velocity,1.0,0.35,size)
				var rotation := Transform2D(angle,Vector2.ZERO)
				var padding := rotation.basis_xform(lead).abs()+Vector2(384,384)
				# 所有对称带及0.35/0.175s前探都包含far，至少25万面；不能因放宽字节预算放行。
				for ratio: float in [1.0,0.5,0.25]:
					var symmetric: Dictionary=planner._native.select(lead*ratio*0.5,1.0,angle,size+padding*ratio,"lod5_full",BUDGET)
					failures+=int(symmetric.get("within_budget",true) or int(symmetric.get("triangles",0))<=240000)
				for ratio: float in [1.0,0.5]:
					var longer: Dictionary=planner._native.select(lead*ratio*0.5,1.0,angle,size+rotation.basis_xform(lead*ratio).abs(),"lod5_full",BUDGET)
					failures+=int(longer.get("within_budget",true) or int(longer.get("triangles",0))<=240000)
				var short_cut: Dictionary=planner._native.select(lead*0.125,1.0,angle,size+rotation.basis_xform(lead*0.25).abs(),"lod5_full",BUDGET)
				var short_union := planner._handoff_bytes(short_cut,-2)
				var bare: Dictionary=planner._native.select(Vector2.ZERO,1.0,angle,size,"lod5_full",BUDGET)
				var actual := planner._select_native(Vector2.ZERO,1.0,angle,size,"lod5_full",BUDGET/2,false)
				var synchronous := legacy._select_native(Vector2.ZERO,1.0,angle,size,"lod5_full",BUDGET/2,false)
				var accepted := scenario=="accept"
				var current := request_fixture(Vector2.ZERO,1.0,angle,size)
				# 后续姿态既平移12世界单位又转0.01弧度，直接以真实投影核验，而非只比较页名。
				var future := request_fixture(Vector2(12.0*direction,0.0),1.0,angle+0.01,size)
				failures+=int(not native_trace_covered(planner._native,bare,current.canvas,size,source.bounds) \
					or native_trace_covered(planner._native,bare,future.canvas,size,source.bounds))
				failures+=int(actual.get("keys")!=(PackedStringArray(["inside","ahead"]) if accepted else PackedStringArray(["inside"])) \
					or actual.get("selection_stage")!=("native_motion_guard" if accepted else "native_actual") \
					or actual.get("spatial_guard_px",-1)!=0 or actual.get("configuration")!="lod5_full" \
					or not actual.get("within_budget",false) or not Handoff.native_qualified(actual,1.0))
				failures+=int(not native_trace_covered(planner._native,actual,current.canvas,size,source.bounds) \
					or native_trace_covered(planner._native,actual,future.canvas,size,source.bounds)!=accepted)
				if accepted:
					failures+=int(actual.get("motion_lead_world")!=lead*0.25 \
						or not is_equal_approx(float(actual.get("motion_horizon",0)),0.0875) \
						or int(actual.get("triangles",0))!=220000 or int(actual.get("bytes",0))<=BUDGET/2)
				elif scenario=="union_rejected":
					# 候选本身55MiB/22万面合格，但与50MiB旧页联合105MiB必须拒绝。
					failures+=int(not short_cut.get("within_budget",false) or short_union<=BUDGET)
				else:
					failures+=int(short_cut.get("within_budget",true) or int(short_cut.get("triangles",0))<=240000)
				var actual_union := planner._handoff_bytes(actual,-2)
				failures+=int(actual_union<0 or actual_union>BUDGET or int(actual.get("active",17))>16 \
					or int(actual.get("triangles",240001))>240000 or int(actual.get("bytes",BUDGET+1))>BUDGET)
				failures+=int(comparable_cut(actual)!=comparable_cut(synchronous) \
					or not Worker.pure(actual) or var_to_bytes(source)!=original)
				if accepted:
					# 放大后未来视野缩小，同一数据允许0.175s前探；资格仍以当前scale核验。
					planner._zoom_rate=1.0;legacy._zoom_rate=1.0
					var zoom_cut := planner._select_native(Vector2.ZERO,1.0,angle,size,"lod5_full",BUDGET/2,false)
					var zoom_sync := legacy._select_native(Vector2.ZERO,1.0,angle,size,"lod5_full",BUDGET/2,false)
					var forecast := planner._select_native(Vector2.ZERO,1.0,angle,size,"lod5_full",BUDGET/2,false,false)
					failures+=int(zoom_cut.get("keys")!=actual.get("keys") or not zoom_cut.get("within_budget",false) \
						or not is_equal_approx(float(zoom_cut.get("motion_horizon",0)),0.175) \
						or comparable_cut(zoom_cut)!=comparable_cut(zoom_sync) or comparable_cut(forecast)!=comparable_cut(actual))
					planner._zoom_rate=0.0;legacy._zoom_rate=0.0
				# 亚像素前探不重复裸查询，也不能冒记方向保护。
				planner._pan_velocity=Vector2(0.1,0)
				var tiny := planner._select_native(Vector2.ZERO,1.0,angle,size,"lod5_full",BUDGET/2,false)
				failures+=int(tiny.get("selection_stage")!="native_actual" or tiny.has("motion_lead_world"))
				legacy._stream.free();legacy.free()
	print("[Tokyo planner] native_motion_guard fail=",failures)
	return failures


static func native_motion_retention_checks() -> int:
	var failures := 0
	for direction: float in [1.0,-1.0]:
		for angle: float in [0.0,PI*0.5]:
			var size := Vector2(100,70) if angle==0.0 else Vector2(70,100)
			var source := native_motion_source(direction,40000,20)
			var roots: Array=source.native.configurations.lod5_full
			# 旧查询可带上ahead而不含far；当前所有保护查询都额外包含far并超过24万面。
			roots[2].bytes=10*1024*1024;source.geometry.ahead.bytes=roots[2].bytes
			roots[3].boxes[0]=AABB(Vector3(80.0*direction-5.0,0,-10),Vector3(10,0,20))
			var original := var_to_bytes(source)
			var planner := Planner.new()
			if not planner.configure(source): failures+=1;continue
			var request := request_fixture(Vector2.ZERO,1.0,angle,size)
			request.pan_velocity=Vector2(600.0*direction,0)
			planner._stream=request.stream;planner._last_canvas=request.canvas
			planner._last_size=size;planner._logical=size;planner._pan_velocity=request.pan_velocity
			var padding := Transform2D(angle,Vector2.ZERO).basis_xform(Vector2(10,0)).abs()
			var old: Dictionary=planner._native.select(Vector2(4.0*direction,0),1.0,angle,size+padding,"lod5_full",BUDGET/2)
			old["selection_stage"]="native_motion_guard";old["spatial_guard_px"]=0
			old["motion_horizon"]=0.0875;old["motion_lead_world"]=Vector2(8.0*direction,0)
			if direction>0.0 and angle==0.0:
				old["selection_stage"]="native_guard";old["spatial_guard_px"]=48
			var old_before := var_to_bytes(old)
			var expected_retained: Dictionary=old.duplicate(true)
			expected_retained["selection_stage"]="native_retained";expected_retained["spatial_guard_px"]=0
			var legacy := NativeRetentionOverlay.new()
			legacy.coverage_probe=planner;legacy._native=planner._native;legacy._stream=GuardPool.new()
			legacy._geometry=source.geometry;legacy._textures=source.textures
			legacy.display_budget=BUDGET;legacy._pan_velocity=request.pan_velocity
			for selector: Variant in [planner,legacy]:
				selector._target_catalog=-2;selector._target=old
				selector._committed_catalog=-2;selector._committed_cut=old;selector._committed=old.keys
			var future := request_fixture(Vector2(12.0*direction,0),1.0,angle+0.01,size)
			var bare := planner._select_native(Vector2.ZERO,1.0,angle,size,"lod5_full",BUDGET/2,false)
			var retained := planner._select_native(Vector2.ZERO,1.0,angle,size,"lod5_full",BUDGET/2)
			var synchronous := legacy._select_native(Vector2.ZERO,1.0,angle,size,"lod5_full",BUDGET/2)
			failures+=int(old.get("keys")!=PackedStringArray(["inside","ahead"]) or int(old.get("triangles",0))!=220000 \
				or not old.get("within_budget",false) or planner._target_covers_current_view(150.0))
			failures+=int(bare.get("selection_stage")!="native_actual" or bare.get("keys")!=PackedStringArray(["inside"]) \
				or comparable_cut(retained)!=comparable_cut(expected_retained) or comparable_cut(retained)!=comparable_cut(synchronous) \
				or var_to_bytes(old)!=old_before)
			# 零余量保留不能携旧48px标记越过原生偏好门、压掉另一个完整HLOD候选。
			failures+=int(Handoff.native_preference(retained,planner._handoff_bytes(retained,-2),BUDGET) \
				and float(retained.get("spatial_guard_px",0))>0.0)
			failures+=int(not native_trace_covered(planner._native,retained,request.canvas,size,source.bounds) \
				or not native_trace_covered(planner._native,retained,future.canvas,size,source.bounds) \
				or native_trace_covered(planner._native,bare,future.canvas,size,source.bounds))
			# 同一旧切面不能越过清晰度、配置、显示预算、页数、面数或真实当前覆盖门。
			for rejected: String in ["expired","configuration","bytes","pages","faces","invalid_budget","coverage"]:
				var invalid := old.duplicate(true)
				match rejected:
					"expired": invalid["ground_max_scale"]=0.99
					"configuration": invalid.configuration="lod4_full"
					"bytes": invalid.bytes=BUDGET/2+1
					"pages":
						var too_many := PackedStringArray()
						for index in 17: too_many.append("inside")
						invalid.keys=too_many
					"faces": invalid.triangles=240001
					"invalid_budget": invalid.within_budget=false
					"coverage": invalid.entries=[]
				for selector: Variant in [planner,legacy]:
					selector._target=invalid;selector._committed_cut=invalid;selector._committed=invalid.keys
				var result := planner._select_native(Vector2.ZERO,1.0,angle,size,"lod5_full",BUDGET/2)
				var sync_result := legacy._select_native(Vector2.ZERO,1.0,angle,size,"lod5_full",BUDGET/2)
				failures+=int(result.get("selection_stage")!="native_actual" or result.get("keys")!=bare.keys \
					or comparable_cut(result)!=comparable_cut(sync_result))
			request.target_catalog=-2;request.target=old;request.committed_catalog=-2;request.committed=old
			var planned: Dictionary=planner.plan(request)
			# 保留仅结束本次显示查询，整个plan仍为未来真实视野求新预取身份。
			failures+=int(planned.get("status")!="candidate" or planned.cut.get("keys")!=old.keys \
				or not planned.cut.get("prefetch_keys",PackedStringArray()).has("far") \
				or planned.cut.get("prefetch_keys")==old.keys or old.has("prefetch_catalog") \
				or not Worker.pure(planned) or var_to_bytes(source)!=original)
			legacy._stream.free();legacy.free()
	print("[Tokyo planner] native_motion_retention fail=",failures)
	return failures


static func native_motion_query_checks() -> int:
	var failures := 0
	var center := Vector2(20,-10)
	var size := Vector2(1600,900)
	var lead := Vector2(100,-40)
	var scale := 1.3
	var horizon := 0.0875
	for angle: float in [0.0,0.7,PI*0.5]:
		var rotation := Transform2D(angle,Vector2.ZERO)
		for zoom: float in [-2.0,0.0,2.0]:
			var query := Handoff.native_motion_query(center,scale,angle,size,lead,horizon,zoom)
			if query.is_empty():
				failures+=1
				continue
			var query_offset: Vector2=rotation.basis_xform(query.center-center)*scale
			var query_rect := Rect2(query_offset-query.size*0.5,query.size).grow(0.001)
			var future_scale := clampf(scale*exp(zoom*horizon),0.0973,5.0)
			var future_size := size*(scale/future_scale)
			var future_offset := rotation.basis_xform(lead)*scale
			failures+=int(not query_rect.encloses(Rect2(-size*0.5,size)) \
				or not query_rect.encloses(Rect2(future_offset-future_size*0.5,future_size)))
			if zoom==0.0:
				failures+=int(query.center!=center+lead*0.5 or query.size!=size+future_offset.abs())
			failures+=int(not Worker.pure(query))
	failures+=int(not Handoff.native_motion_query(center,0.0,0.0,size,lead,horizon,1.0).is_empty() \
		or not Handoff.native_motion_query(center,scale,0.0,size,lead,horizon,NAN).is_empty())
	print("[Tokyo planner] native_motion_query fail=",failures)
	return failures


static func native_motion_prefetch_checks() -> int:
	var source := native_motion_source(1.0,40000,20)
	# 额外页只进入二次放大后的0.175s包络，原未来scale上的纯平移0.0875s不需它。
	var extra := {"path":"extra","bytes":1024*1024,"triangles":[5000,0,0],
		"boxes":[AABB(Vector3(80,0,-10),Vector3(10,0,20)),AABB(),AABB()],"children":[]}
	source.native.configurations.lod5_full.append(extra)
	source.native.pages.extra={"components":{"extra":true}}
	source.geometry.extra={"bytes":1024*1024}
	var planner := Planner.new()
	if not planner.configure(source): return 1
	planner._stream=request_fixture(Vector2.ZERO,1.0).stream
	planner._pan_velocity=Vector2(200,0);planner._zoom_rate=1.0
	var size := Vector2(100,70)
	var old: Dictionary=planner._native.select(Vector2(10000,0),1.0,0.0,size,"lod5_full",BUDGET)
	planner._committed_catalog=-2;planner._committed_cut=old;planner._committed=old.keys
	var expected := planner._select_native(Vector2.ZERO,1.0,0.0,size,"lod5_full",BUDGET/2,false,false)
	var double_zoom := planner._select_native(Vector2.ZERO,1.0,0.0,size,"lod5_full",BUDGET/2,false,true)
	var predicted := planner._predict_prefetch(Vector2(-50,0),exp(-0.25),0.0,size)
	var failures := int(expected.get("keys")!=PackedStringArray(["inside","ahead"]) \
		or double_zoom.get("keys")!=PackedStringArray(["inside","ahead","extra"]) \
		or predicted.get("catalog")!=-2 or predicted.get("keys")!=expected.get("keys"))
	var legacy := Overlay.new()
	legacy._catalogs.assign(source.catalogs);legacy._geometry=source.geometry;legacy._textures=source.textures
	legacy._selection_work=source.context.duplicate(true);legacy.display_budget=BUDGET;legacy._stream=GuardPool.new()
	legacy._pan_velocity=planner._pan_velocity;legacy._zoom_rate=planner._zoom_rate
	legacy._committed_catalog=-2;legacy._committed_cut=old;legacy._committed=old.keys
	legacy._native=preload("res://scripts/rendering/tokyo_hlod_native.gd").new()
	if not legacy._native.configure_selection_snapshot(source.native,source.context): failures+=1
	var synchronous := legacy._predict_prefetch(Vector2(-50,0),exp(-0.25),0.0,size)
	failures+=int(predicted!=synchronous or not Worker.pure(predicted))
	legacy._stream.free();legacy.free()
	print("[Tokyo planner] native_motion_prefetch fail=",failures)
	return failures


static func native_motion_trace_poses() -> Array[Dictionary]:
	# Near deep 20261015-091946：canvas是1920x1080逻辑视口，查询输出为1600x900。
	# trace仅存领取结果时的pan_velocity；这里明确重放该观测值，不冒称原请求速度。
	return [
		{"name":"near_f884_to889","scale":1.48834387461344,"future_scale":1.4983332157135,
			"canvas":Transform2D(Vector2(1.781972,0.12007),Vector2(-0.12007,1.781972),Vector2(-1264.985,26499.63)),
			"future_canvas":Transform2D(Vector2(1.795331,0.09793),Vector2(-0.09793,1.795331),Vector2(-999.1147,26714.04)),
			"observed_velocity":Vector2(452.7947,-143.8938),"bare_triangles":195611},
		{"name":"near_f892_to893","scale":1.50166670481364,"future_scale":1.50499910116196,
			"canvas":Transform2D(Vector2(1.799728,0.090471),Vector2(-0.090471,1.799728),Vector2(-909.285,26782.44)),
			"future_canvas":Transform2D(Vector2(1.804092,0.082977),Vector2(-0.082977,1.804092),Vector2(-818.3177,26835.59)),
			"observed_velocity":Vector2(455.2172,-101.1309),"bare_triangles":184872}
	]


static func native_trace_covered(adapter: RefCounted, cut: Dictionary, canvas: Transform2D, logical: Vector2, bounds: Rect2) -> bool:
	var inverse := canvas.affine_inverse()
	var view := Rect2(inverse*Vector2.ZERO,Vector2.ZERO)
	for point: Vector2 in [Vector2(logical.x,0),logical,Vector2(0,logical.y)]: view=view.expand(inverse*point)
	return adapter.covers_visible_layers(cut,view.intersection(bounds),canvas,logical)


static func native_gap_trace_poses() -> Array[Dictionary]:
	# motion-v7 Near deep：精确使用request字段，未来为同一次巡检的真实丢失姿态。
	return [
		{"name":"v7_f1004","scale":1.48170719544093,"velocity":Vector2(606.7864,-198.8538),"zoom_rate":0.20116164742078,
			"canvas":Transform2D(Vector2(1.772947,0.134599),Vector2(-0.134599,1.772947),Vector2(-1439.156,26355.77)),"bare_faces":216604},
		{"name":"v7_f1012","scale":1.49167040983836,"velocity":Vector2(578.9178,-187.2455),"zoom_rate":0.176716092806363,
			"canvas":Transform2D(Vector2(1.786451,0.112733),Vector2(-0.112733,1.786451),Vector2(-1176.939,26571.31)),"bare_faces":195611},
		{"name":"v7_f3502","scale":1.47840032974879,"velocity":Vector2(589.8608,-194.1387),"zoom_rate":0.18502535217274,
			"canvas":Transform2D(Vector2(1.768406,0.141785),Vector2(-0.141785,1.768406),Vector2(-1525.208,26283.67)),"bare_faces":216604},
		{"name":"v7_f3509","scale":1.48834387461344,"velocity":Vector2(587.4489,-190.8638),"zoom_rate":0.165750765788015,
			"canvas":Transform2D(Vector2(1.781972,0.12007),Vector2(-0.12007,1.781972),Vector2(-1264.985,26499.63)),"bare_faces":195611}
	]


static func native_gap_view(canvas: Transform2D, logical: Vector2) -> Dictionary:
	var projection := preload("res://scripts/experiments/volume_projection.gd")
	var inverse := canvas.affine_inverse()
	var view := Rect2(inverse*Vector2.ZERO,Vector2.ZERO)
	for point: Vector2 in [Vector2(logical.x,0),logical,Vector2(0,logical.y)]: view=view.expand(inverse*point)
	var ray: Vector3=projection.ground_basis(canvas,deg_to_rad(38)).inverse()*projection.camera_basis(canvas,deg_to_rad(38)).z
	return {"view":view,"canvas":canvas,"logical":logical,"roof":-Vector2(ray.x,ray.z)/ray.y}


static func native_joint_tree(entry: Dictionary, poses: Array[Dictionary], marker: AABB, originals: Dictionary) -> Dictionary:
	# 仅诊断：在原树的副本上把每层费用设为两真实视野的可见性并集，再由正式DP求完整切面。
	# marker只让已证明可见的层参与DP；输出恢复原始包络，并对两真实视野重新核验覆盖。
	originals[entry.path]=entry
	var triangles: Array[int]=[0,0,0]
	for pose: Dictionary in poses:
		var visible: Dictionary=preload("res://scripts/experiments/tokyo_spatial_select.gd").visible(entry,
			pose.view,pose.canvas,pose.logical,pose.roof,Vector2.ZERO)
		for kind in 3:
			if visible.mask[kind]: triangles[kind]=int(entry.triangles[kind])
	var result := entry.duplicate()
	result.triangles=triangles;result.boxes=[marker,marker,marker]
	var children: Array[Dictionary]=[]
	for child: Dictionary in entry.get("children",[]): children.append(native_joint_tree(child,poses,marker,originals))
	result.children=children
	return result


static func native_joint_cut(adapter: RefCounted, reference: Dictionary, canvases: Array[Transform2D], logical: Vector2) -> Dictionary:
	var configuration: String=reference.configuration
	var roots: Array=[]
	if reference.get("ground_tree",false): roots=adapter._ground_roots[configuration]
	elif adapter._partition_roots.has(configuration): roots=adapter._partition_roots[configuration]
	else: roots=adapter._configurations()[configuration]
	var poses: Array[Dictionary]=[]
	for canvas: Transform2D in canvases: poses.append(native_gap_view(canvas,logical))
	var center: Vector2=canvases[0].affine_inverse()*(logical*0.5)
	var marker := AABB(Vector3(center.x-1,0,center.y-1),Vector3(2,0,2))
	var originals := {}
	var adapted: Array[Dictionary]=[]
	for entry: Dictionary in roots: adapted.append(native_joint_tree(entry,poses,marker,originals))
	var first: Dictionary=poses[0]
	var solution: Dictionary=preload("res://scripts/experiments/tokyo_spatial_cut.gd").solve(adapted,
		first.view,first.canvas,first.logical,first.roof,Vector2.ZERO,16,false)
	var cut: Dictionary=preload("res://scripts/experiments/tokyo_spatial_cut.gd").pick(solution,BUDGET)
	for entry: Dictionary in cut.entries:
		entry.triangles=originals[entry.path].triangles;entry.boxes=originals[entry.path].boxes
		entry.erase("children")
	return preload("res://scripts/rendering/tokyo_hlod_native.gd").decorate(cut,configuration,reference.get("ground_tree",false))


static func native_gap_candidate(loader: Node, cut: Dictionary, bare: Dictionary, pose: Dictionary,
		future: Transform2D, bounds: Rect2, kind: String, extra: Dictionary = {}) -> Dictionary:
	var adapter: RefCounted=loader._native
	var meshes := PackedStringArray(bare.get("keys",[]));meshes.append_array(PackedStringArray(cut.get("keys",[])))
	var images := PackedStringArray(bare.get("ground_images",[]));images.append_array(PackedStringArray(cut.get("ground_images",[])))
	var ground := int(bare.get("charges",{}).get("ground_bytes",0))+int(cut.get("charges",{}).get("ground_bytes",0))
	var union_bytes := Handoff.streaming_bytes(loader._geometry,loader._textures,meshes,images,ground)
	var current_covered := native_trace_covered(adapter,cut,pose.canvas,Vector2(1920,1080),bounds)
	var future_covered := native_trace_covered(adapter,cut,future,Vector2(1920,1080),bounds)
	var qualified := Handoff.native_qualified(cut,float(pose.scale)) and Handoff.native_qualified(cut,1.4983332157135)
	var row := {"pose":pose.name,"kind":kind,"stage":cut.get("selection_stage",""),"faces":cut.get("triangles",0),
		"pages":cut.get("active",0),"bytes":cut.get("bytes",0),"union_bytes":union_bytes,
		"current_covered":current_covered,"future_covered":future_covered,"qualified":qualified,
		"within_budget":cut.get("within_budget",false),"future_admissible":cut.get("within_budget",false) \
			and int(cut.get("active",17))<=16 and int(cut.get("bytes",BUDGET+1))<=BUDGET \
			and union_bytes>=0 and union_bytes<=BUDGET and qualified and current_covered and future_covered}
	row.merge(extra)
	var entries: Array[Dictionary]=[]
	for entry: Dictionary in cut.get("entries",[]):
		entries.append({"path":String(entry.path).get_file().left(8),"mask":entry.mask,"faces":entry.faces})
	row["entries"]=entries
	print("[Tokyo native gap diagnostic] ",JSON.stringify(row))
	return row


static func installed_native_gap_diagnostic(loader: Node, archive: Resource, planner: RefCounted) -> int:
	var adapter: RefCounted=loader._native
	var logical := Vector2(1920,1080)
	var size := Vector2(1600,900)
	var future := Transform2D(Vector2(1.795331,0.09793),Vector2(-0.09793,1.795331),Vector2(-999.1147,26714.04))
	var future_center := future.affine_inverse()*(logical*0.5)
	var future_cut: Dictionary=adapter.select(future_center,1.4983332157135,future.get_rotation(),size,"lod5_full",BUDGET)
	var failures := 0
	var prior_motion: Dictionary={}
	for pose: Dictionary in native_gap_trace_poses():
		var center: Vector2=pose.canvas.affine_inverse()*(logical*0.5)
		var scale: float=pose.scale
		var angle: float=pose.canvas.get_rotation()
		var rotation := Transform2D(angle,Vector2.ZERO)
		var bare: Dictionary=adapter.select(center,scale,angle,size,"lod5_full",BUDGET)
		failures+=int(int(bare.get("triangles",0))!=int(pose.bare_faces))
		native_gap_candidate(loader,bare,bare,pose,future,archive.bounds,"bare")
		native_gap_candidate(loader,future_cut,bare,pose,future,archive.bounds,"future_bare_at_current")
		var joint := native_joint_cut(adapter,bare,[pose.canvas,future],logical)
		var joint_row := native_gap_candidate(loader,joint,bare,pose,future,archive.bounds,"exact_two_pose_dp")
		failures+=int(not joint_row.current_covered or not joint_row.future_covered)
		planner._pan_velocity=pose.velocity;planner._zoom_rate=pose.zoom_rate
		planner._committed_catalog=-2;planner._committed_cut=bare;planner._committed=bare.keys
		var production: Dictionary=planner._select_native(center,scale,angle,size,"lod5_full",BUDGET/2,false)
		var production_row := native_gap_candidate(loader,production,bare,pose,future,archive.bounds,"production",{"horizon":production.get("motion_horizon",0)})
		loader._pan_velocity=pose.velocity;loader._zoom_rate=pose.zoom_rate
		loader._committed_catalog=-2;loader._committed_cut=bare;loader._committed=bare.keys
		var synchronous: Dictionary=loader._select_native(center,scale,angle,size,"lod5_full",BUDGET/2,false)
		failures+=int(not production_row.future_admissible or production.get("selection_stage")!="native_motion_guard" \
			or comparable_cut(production)!=comparable_cut(synchronous))
		if pose.name=="v7_f3502": prior_motion=production
		elif pose.name=="v7_f3509" and not prior_motion.is_empty():
			native_gap_candidate(loader,prior_motion,bare,pose,future,archive.bounds,"prior_f3502_motion")
		for horizon: float in [0.0875,0.05,0.04375,0.025,0.021875]:
			var lead := Handoff.pan_lead(pose.velocity,scale,horizon,size)
			var offset := rotation.basis_xform(lead)*scale
			var motion: Dictionary=adapter.select(center+lead*0.5,scale,angle,size+offset.abs(),"lod5_full",BUDGET)
			native_gap_candidate(loader,motion,bare,pose,future,archive.bounds,"short_motion",{"horizon":horizon})
			# 两矩形并集仍在当前scale/同configuration求解；未来缩小只改变所需空间包络。
			var future_size := size*exp(-clampf(float(pose.zoom_rate)*horizon,-0.7,0.7))
			var swept := Rect2(-size*0.5,size).merge(Rect2(offset-future_size*0.5,future_size))
			var swept_center := center+rotation.basis_xform_inv(swept.get_center()/scale)
			var zoom_aware: Dictionary=adapter.select(swept_center,scale,angle,swept.size,"lod5_full",BUDGET)
			native_gap_candidate(loader,zoom_aware,bare,pose,future,archive.bounds,"pan_zoom_envelope",{"horizon":horizon})
		# 用真实未来姿态做包络上界对照；不能把这个oracle当作可预测的生产输入。
		var oracle := Rect2(-size*0.5,size)
		for corner: Vector2 in [Vector2.ZERO,Vector2(logical.x,0),logical,Vector2(0,logical.y)]:
			oracle=oracle.expand(rotation.basis_xform(future.affine_inverse()*corner-center)*scale)
		var oracle_center := center+rotation.basis_xform_inv(oracle.get_center()/scale)
		var oracle_cut: Dictionary=adapter.select(oracle_center,scale,angle,oracle.size,"lod5_full",BUDGET)
		native_gap_candidate(loader,oracle_cut,bare,pose,future,archive.bounds,"oracle_actual_pose_envelope")
	print("[Tokyo native gap diagnostic] replay_fail=",failures)
	return failures


static func installed_native_retention_diagnostic(loader: Node, archive: Resource, planner: RefCounted) -> int:
	# guard-v8 Near：按f800原请求重建旧保护切面，随后精确重放f807与f808丢失姿态。
	var logical := Vector2(1920,1080)
	var size := Vector2(1600,900)
	var old_canvas := Transform2D(Vector2(1.772947,0.134599),Vector2(-0.134599,1.772947),Vector2(-1439.156,26355.77))
	var old_center := old_canvas.affine_inverse()*(logical*0.5)
	planner._committed=PackedStringArray();planner._committed_catalog=-1;planner._committed_cut={}
	planner._target_catalog=-1;planner._target={}
	planner._pan_velocity=Vector2(536.7131,-175.8284);planner._zoom_rate=0.100978041262396
	var old: Dictionary=planner._select_native(old_center,1.48170719544093,old_canvas.get_rotation(),size,"lod5_full",BUDGET/2,false)
	var pose := {"name":"v8_f807","scale":1.49500081936518,
		"canvas":Transform2D(Vector2(1.790905,0.105352),Vector2(-0.105352,1.790905),Vector2(-1088.303,26642.8))}
	var future := Transform2D(Vector2(1.795331,0.09793),Vector2(-0.09793,1.795331),Vector2(-999.1147,26714.04))
	var canvas: Transform2D=pose.canvas
	var center := canvas.affine_inverse()*(logical*0.5)
	planner._bounds=archive.bounds;planner._last_canvas=canvas;planner._last_size=size;planner._logical=logical
	planner._pan_velocity=Vector2(600.2318,-193.2652);planner._zoom_rate=0.178063161425192
	planner._target_catalog=-2;planner._target=old
	planner._committed_catalog=-2;planner._committed_cut=old;planner._committed=old.get("keys",PackedStringArray())
	var legacy := NativeRetentionOverlay.new()
	legacy.coverage_probe=planner;legacy._native=loader._native;legacy._stream=loader._stream
	legacy._geometry=loader._geometry;legacy._textures=loader._textures;legacy.display_budget=BUDGET
	legacy._pan_velocity=planner._pan_velocity;legacy._zoom_rate=planner._zoom_rate
	legacy._target_catalog=-2;legacy._target=old
	legacy._committed_catalog=-2;legacy._committed_cut=old;legacy._committed=planner._committed
	var bare: Dictionary=planner._select_native(center,float(pose.scale),canvas.get_rotation(),size,"lod5_full",BUDGET/2,false)
	var retained: Dictionary=planner._select_native(center,float(pose.scale),canvas.get_rotation(),size,"lod5_full",BUDGET/2)
	var synchronous := legacy._select_native(center,float(pose.scale),canvas.get_rotation(),size,"lod5_full",BUDGET/2)
	var before := native_gap_candidate(loader,bare,bare,pose,future,archive.bounds,"retention_disabled")
	var after := native_gap_candidate(loader,retained,bare,pose,future,archive.bounds,"retention_enabled")
	var expected_retained: Dictionary=old.duplicate(true)
	expected_retained["selection_stage"]="native_retained";expected_retained["spatial_guard_px"]=0
	var failures := int(old.get("selection_stage")!="native_motion_guard" or int(old.get("triangles",0))!=227314 \
		or int(old.get("active",0))!=7 or int(old.get("bytes",0))!=28317756 \
		or bare.get("selection_stage")!="native_actual" or int(bare.get("triangles",0))!=187915 \
		or not before.current_covered or before.future_covered or not after.future_admissible \
		or comparable_cut(retained)!=comparable_cut(expected_retained) or comparable_cut(retained)!=comparable_cut(synchronous))
	legacy.free()
	print("[Tokyo native retention diagnostic] replay_fail=",failures)
	return failures


static func installed_native_motion_diagnostic() -> int:
	var installed := preload("res://scripts/rendering/tokyo_installed_map.gd")
	var path: String=installed.package_path()
	if not path.ends_with("/m20/package.json"):
		print("[Tokyo native motion diagnostic] requires installed M20; resolved=",path)
		return 1
	# 复用正式package/coverage/native身份认证；不绕过清晰度、物理费用或完整覆盖门。
	var loader := Overlay.new()
	var archive: Resource=loader._load_archive()
	if archive==null or loader._native==null:
		loader.free()
		print("[Tokyo native motion diagnostic] authenticated source unavailable")
		return 1
	var adapter: RefCounted=loader._native
	adapter.selection_context={"background":true,"epoch":0,"display_limit":BUDGET,"native_page_limit":16}
	loader.display_budget=BUDGET;loader._stream=GuardPool.new()
	var planner := Planner.new()
	planner.display_budget=BUDGET;planner._geometry=loader._geometry;planner._textures=loader._textures
	planner._stream=request_fixture(Vector2.ZERO,1.0).stream
	planner._native=preload("res://scripts/rendering/tokyo_hlod_native.gd").new()
	if not planner._native.configure_selection_snapshot(adapter.selection_snapshot(),adapter.selection_context):
		if loader._future_predictor!=null: loader._future_predictor.close()
		loader._stream.free();loader.free()
		print("[Tokyo native motion diagnostic] pure selection snapshot unavailable")
		return 1
	var logical := Vector2(1920,1080)
	var size := Vector2(1600,900)
	var failures := 0
	for pose: Dictionary in native_motion_trace_poses():
		var canvas: Transform2D=pose.canvas
		var center := canvas.affine_inverse()*(logical*0.5)
		var scale: float=pose.scale
		var angle := canvas.get_rotation()
		var velocity: Vector2=pose.observed_velocity
		var lead35 := Handoff.pan_lead(velocity,scale,0.35,size)
		var lead25 := Handoff.pan_lead(velocity,scale,0.25,size)
		var lead175 := Handoff.pan_lead(velocity,scale,0.175,size)
		var lead0875 := Handoff.pan_lead(velocity,scale,0.0875,size)
		var rotate := Transform2D(angle,Vector2.ZERO)
		var padding35 := (rotate.basis_xform(lead35)*scale).abs()+Vector2(384,384)
		var bare: Dictionary=adapter.select(center,scale,angle,size,"lod5_full",BUDGET)
		var matches_trace: bool=bare.get("triangles",-1)==pose.bare_triangles \
			and native_trace_covered(adapter,bare,canvas,logical,archive.bounds) \
			and not native_trace_covered(adapter,bare,pose.future_canvas,logical,archive.bounds)
		failures+=int(not matches_trace)
		var queries := [
			{"kind":"bare","center":center,"size":size},
			{"kind":"existing_guard48","center":center+lead35*0.125,"size":size+padding35*0.25},
			{"kind":"motion025","center":center+lead25*0.5,"size":size+(rotate.basis_xform(lead25)*scale).abs()},
			{"kind":"motion0175","center":center+lead175*0.5,"size":size+(rotate.basis_xform(lead175)*scale).abs()},
			{"kind":"motion00875","center":center+lead0875*0.5,"size":size+(rotate.basis_xform(lead0875)*scale).abs()},
			{"kind":"lod4_motion025","configuration":"lod4_full","center":center+lead25*0.5,"size":size+(rotate.basis_xform(lead25)*scale).abs()},
			{"kind":"lod4_existing_guard48","configuration":"lod4_full","center":center+lead35*0.125,"size":size+padding35*0.25}
		]
		for query: Dictionary in queries:
			var configuration: String=query.get("configuration","lod5_full")
			var cut: Dictionary=adapter.select(query.center,scale,angle,query.size,configuration,BUDGET)
			var meshes := PackedStringArray(bare.get("keys",[]))
			meshes.append_array(PackedStringArray(cut.get("keys",[])))
			var images := PackedStringArray(bare.get("ground_images",[]))
			images.append_array(PackedStringArray(cut.get("ground_images",[])))
			var ground := int(bare.get("charges",{}).get("ground_bytes",0))+int(cut.get("charges",{}).get("ground_bytes",0))
			var union_bytes := Handoff.streaming_bytes(loader._geometry,loader._textures,meshes,images,ground)
			var current_covered := native_trace_covered(adapter,cut,canvas,logical,archive.bounds)
			var future_covered := native_trace_covered(adapter,cut,pose.future_canvas,logical,archive.bounds)
			var qualified := Handoff.native_qualified(cut,scale) and Handoff.native_qualified(cut,float(pose.future_scale))
			var admissible: bool=cut.get("within_budget",false) and int(cut.get("active",17))<=16 \
				and int(cut.get("triangles",240001))<=240000 and int(cut.get("bytes",BUDGET+1))<=BUDGET \
				and union_bytes>=0 and union_bytes<=BUDGET and qualified and current_covered
			print("[Tokyo native motion diagnostic] ",JSON.stringify({"pose":pose.name,"kind":query.kind,"configuration":configuration,
				"trace_match":matches_trace,"faces":cut.get("triangles",0),"pages":cut.get("active",0),
				"bytes":cut.get("bytes",0),"union_bytes":union_bytes,"qualified":qualified,
				"current_covered":current_covered,"future_covered":future_covered,"admissible":admissible,
				"future_admissible":admissible and future_covered,"observed_velocity":velocity}))
		# 反事实查询以外，再走最终生产helper和原半池入口，证明真实顺序确实选中合法前探。
		planner._pan_velocity=velocity;planner._committed_catalog=-2
		planner._committed_cut=bare;planner._committed=bare.keys
		loader._pan_velocity=velocity;loader._committed_catalog=-2
		loader._committed_cut=bare;loader._committed=bare.keys
		var production := planner._select_native(center,scale,angle,size,"lod5_full",BUDGET/2,false)
		var synchronous := loader._select_native(center,scale,angle,size,"lod5_full",BUDGET/2,false)
		var production_union := planner._handoff_bytes(production,-2)
		var production_current := native_trace_covered(adapter,production,canvas,logical,archive.bounds)
		var production_future := native_trace_covered(adapter,production,pose.future_canvas,logical,archive.bounds)
		var production_qualified := Handoff.native_qualified(production,scale) \
			and Handoff.native_qualified(production,float(pose.future_scale))
		var production_admissible: bool=production.get("within_budget",false) \
			and production.get("selection_stage")=="native_motion_guard" and production.get("configuration")=="lod5_full" \
			and production.get("spatial_guard_px",-1)==0 and int(production.get("active",17))<=16 \
			and int(production.get("triangles",240001))<=240000 and int(production.get("bytes",BUDGET+1))<=BUDGET \
			and production_union>=0 and production_union<=BUDGET and production_qualified and production_current and production_future
		var helpers_match := comparable_cut(production)==comparable_cut(synchronous)
		failures+=int(not production_admissible or not helpers_match or not Worker.pure(production))
		print("[Tokyo native motion diagnostic] ",JSON.stringify({"pose":pose.name,"kind":"production",
			"stage":production.get("selection_stage"),"configuration":production.get("configuration"),
			"faces":production.get("triangles",0),"pages":production.get("active",0),"bytes":production.get("bytes",0),
			"union_bytes":production_union,"motion_horizon":production.get("motion_horizon",0),
			"qualified":production_qualified,"current_covered":production_current,"future_covered":production_future,
			"future_admissible":production_admissible,"helpers_match":helpers_match}))
	failures+=installed_native_gap_diagnostic(loader,archive,planner)
	failures+=installed_native_retention_diagnostic(loader,archive,planner)
	if loader._future_predictor!=null:
		loader._future_predictor.close()
		loader._future_predictor=null
	loader._stream.free()
	loader.free()
	print("[Tokyo native motion diagnostic] replay_fail=",failures)
	return failures


static func c1_compact_trace_poses() -> Array[Dictionary]:
	# release-profile-C1-deep 20261015-104826：使用请求姿态，不能拿领取结果的姿态代替。
	return [
		{"name":"initial_f1","initial":true,"scale":0.291666686534882,"velocity":Vector2.ZERO,"zoom_rate":0.0,
			"canvas":Transform2D(Vector2(0.35,0),Vector2(0,0.35),Vector2(960.0001,-4325.0))},
		{"name":"initial_f2","initial":true,"scale":0.218749990065893,"velocity":Vector2.ZERO,"zoom_rate":-2.30145748787562,
			"canvas":Transform2D(Vector2(0.2625,0),Vector2(0,0.2625),Vector2(881.25,4031.25))},
		{"name":"f568","scale":0.231520161032677,"velocity":Vector2(-207.2168,-753.5121),"zoom_rate":0.192011576022475,
			"canvas":Transform2D(Vector2(0.277593,0.01132),Vector2(-0.01132,0.277593),Vector2(743.5215,4303.51))},
		{"name":"f580","scale":0.237847616275152,"velocity":Vector2(-234.7286,-853.5492),"zoom_rate":0.199492884604667,
			"canvas":Transform2D(Vector2(0.284887,0.017385),Vector2(-0.017385,0.284887),Vector2(667.6394,4439.391))},
		{"name":"f584","scale":0.240128189325333,"velocity":Vector2(-237.4831,-863.5593),"zoom_rate":0.177396445944605,
			"canvas":Transform2D(Vector2(0.287483,0.019645),Vector2(-0.019645,0.287483),Vector2(639.0225,4488.485))},
		{"name":"initial_f2_reset","initial":true,"scale":0.218749990065893,"velocity":Vector2.ZERO,"zoom_rate":0.0,
			"canvas":Transform2D(Vector2(0.2625,0),Vector2(0,0.2625),Vector2(881.25,4031.25))}
	]


static func c1_compact_pair_bytes(planner: RefCounted, left: Dictionary, left_index: int,
		right: Dictionary, right_index: int) -> int:
	var meshes := PackedStringArray()
	var images := PackedStringArray()
	var ground := 0
	for pair: Array in [[left,left_index],[right,right_index]]:
		var cut: Dictionary=pair[0]
		ground+=int(cut.get("charges",{}).get("ground_bytes",0))
		for key: String in cut.get("keys",[]):
			var row: Dictionary=planner._catalogs[pair[1]].rows[key]
			meshes.append(row.native_geometry.path);images.append(row.native_texture.path)
	return Handoff.streaming_bytes(planner._geometry,planner._textures,meshes,images,ground)


static func c1_compact_metrics(planner: RefCounted, cut: Dictionary, pose: Dictionary,
		old: Dictionary, successor: Dictionary) -> Dictionary:
	var catalog: Dictionary=planner._catalogs[6]
	var logical := Vector2(1920,1080)
	var current := native_gap_view(pose.canvas,logical)
	var late_canvas := Transform2D(Vector2(0.298332,0.029697),Vector2(-0.029697,0.298332),Vector2(509.5327,4698.032))
	var late := native_gap_view(late_canvas,logical)
	var future_canvas := Transform2D(Vector2(0.304769,0.036162),Vector2(-0.036162,0.304769),Vector2(424.466,4825.954))
	var future := native_gap_view(future_canvas,logical)
	var old_union := c1_compact_pair_bytes(planner,old,6,cut,6) if not cut.is_empty() else -1
	var next_union := c1_compact_pair_bytes(planner,cut,6,successor,5) if not cut.is_empty() else -1
	var forecast: float=pose.scale*exp(clampf(pose.zoom_rate*0.25,0.0,0.7))
	return {"pose":pose.name,"keys":cut.get("keys",[]),"bytes":cut.get("bytes",0),"faces":cut.get("triangles",0),
		"pages":cut.get("active",0),"within_budget":cut.get("within_budget",false),
		"stage":cut.get("selection_stage",""),"guard":cut.get("spatial_guard_px",-1),
		"current_qualified":Handoff.qualified(catalog,cut,pose.scale),
		"forecast_scale":forecast,"forecast_qualified":Handoff.qualified(catalog,cut,forecast),
		"current_covered":Handoff.covers_projection(catalog,cut,current.view.intersection(catalog.bounds),pose.canvas,logical),
		"preexpiry_f597_qualified":Handoff.qualified(catalog,cut,0.249838555852572),
		"preexpiry_f597_covered":Handoff.covers_projection(catalog,cut,late.view.intersection(catalog.bounds),late_canvas,logical),
		"old_to_candidate_union":old_union,"old_to_candidate_fits":old_union>=0 and old_union<=BUDGET,
		"candidate_to_successor_union":next_union,"candidate_to_successor_fits":next_union>=0 and next_union<=BUDGET,
		"successor_f605_qualified":Handoff.qualified(planner._catalogs[5],successor,0.255755409598351),
		"successor_f605_covered":Handoff.covers_projection(planner._catalogs[5],successor,
			future.view.intersection(catalog.bounds),future_canvas,logical)}


static func installed_c1_compact_diagnostic() -> int:
	var path: String=preload("res://scripts/rendering/tokyo_installed_map.gd").package_path()
	if OS.get_environment("AGL_TOKYO_INSTALLED_TEST")!="1" or not path.ends_with("/m20/package.json"):
		print("[Tokyo C1 compact diagnostic] requires installed M20; resolved=",path)
		return 1
	var loader := NativeRetentionOverlay.new()
	var archive: Resource=loader._load_archive()
	if archive==null or loader._catalogs.size()<=6:
		loader.free()
		return 1
	var prepared := {}
	for catalog: Dictionary in loader._catalogs:
		if catalog.get("mixed_scales",false): prepared[catalog.identity.path]=Prepared.build(catalog)
	var source := {"catalogs":loader._catalogs,"prepared_catalogs":prepared,
		"geometry":loader._geometry,"textures":loader._textures,"foundation":{},"bounds":archive.bounds,"native":{},"flags":{},
		"context":{"background":true,"epoch":0,"display_limit":BUDGET,"native_page_limit":16}}
	var planner := Planner.new()
	if not planner.configure(source):
		if loader._future_predictor!=null: loader._future_predictor.close()
		loader.free()
		return 1
	loader.coverage_probe=planner;loader.display_budget=BUDGET;loader._stream=GuardPool.new()
	loader._selection_work=planner._selection_work.duplicate(true)
	planner._stream=request_fixture(Vector2.ZERO,1.0).stream
	var keys := PackedStringArray(["0:1","0:2"])
	var charged := Contract.charges(planner._catalogs[6],keys,planner._selection_work)
	var old := {"keys":keys,"charges":charged,"bytes":charged.total_bytes,"triangles":charged.faces,
		"active":charged.pages,"within_budget":charged.within_budget,"spatial_guard_px":192,"selection_stage":"hlod_guard_retry"}
	var failures := int(old.bytes!=87494936 or old.triangles!=135298)
	var logical := Vector2(1920,1080)
	var size := Vector2(1600,900)
	var successor_pose: Dictionary=c1_compact_trace_poses()[3]
	var successor_canvas: Transform2D=successor_pose.canvas
	var successor := Contract.select(planner._catalogs[5],successor_canvas.affine_inverse()*(logical*0.5),
		successor_pose.scale,successor_canvas.get_rotation(),size,true,BUDGET/2,planner._selection_work)
	failures+=int(successor.get("keys")!=PackedStringArray(["1:3","2:38","2:39","1:4"]) or successor.get("bytes",0)!=47242856)
	for pose: Dictionary in c1_compact_trace_poses():
		var canvas: Transform2D=pose.canvas
		var center := canvas.affine_inverse()*(logical*0.5)
		var angle := canvas.get_rotation()
		var committed: Dictionary={} if pose.get("initial",false) else old
		planner._last_canvas=canvas;planner._last_size=size;planner._logical=logical
		planner._pan_velocity=pose.velocity;planner._zoom_rate=pose.zoom_rate
		planner._committed=PackedStringArray(committed.get("keys",[]));planner._committed_cut=committed
		planner._committed_catalog=-1 if committed.is_empty() else 6
		loader._last_canvas=canvas;loader._last_size=size
		loader._pan_velocity=pose.velocity;loader._zoom_rate=pose.zoom_rate
		loader._committed=planner._committed;loader._committed_cut=committed;loader._committed_catalog=planner._committed_catalog
		var production: Dictionary=planner._select_hlod(planner._catalogs[6],center,pose.scale,angle,size,true,BUDGET/2)
		var synchronous: Dictionary=loader._select_hlod(loader._catalogs[6],center,pose.scale,angle,size,true,BUDGET/2)
		var row := c1_compact_metrics(planner,production,pose,committed,successor)
		row["kind"]="production";row["helpers_match"]=comparable_cut(production)==comparable_cut(synchronous)
		failures+=int(not row.helpers_match or not Worker.pure(production))
		if pose.name=="initial_f2":
			failures+=int(production.get("keys")!=keys or production.get("bytes",0)!=87494936 \
				or production.get("spatial_guard_px",0)!=192 or production.get("selection_stage","")!="hlod_guard_retry")
		if pose.name=="initial_f2_reset":
			# 同一冷启动姿态仅清除跳转前缩放历史：最大保护带已有可用半池切面。
			# 两切面共享两张各2058496字节的纹理；物理联合费用扣除4116992，不能直接相加。
			var contrast: bool=production.get("bytes",0)==44378176 and production.get("triangles",0)==79878 \
				and production.get("active",0)==9 and production.get("spatial_guard_px",0)==192 \
				and production.get("selection_stage","")=="hlod_guard" and row.current_qualified and row.current_covered \
				and row.candidate_to_successor_union==87504040 and row.candidate_to_successor_fits \
				and row.successor_f605_qualified and row.successor_f605_covered
			row["cold_history_contrast"]=contrast
			failures+=int(not contrast)
		print("[Tokyo C1 compact diagnostic] ",JSON.stringify(row))
		var lead := Handoff.pan_lead(pose.velocity,pose.scale,0.35,size)
		var padding: Vector2=(Transform2D(angle,Vector2.ZERO).basis_xform(lead)*pose.scale).abs()+Vector2(384,384)+Handoff.zoom_out_padding(pose.zoom_rate,size)
		for ratio: float in [1.0,0.5,0.25,0.0]:
			for budget: int in [BUDGET/2,BUDGET]:
				var direct := Contract.select(planner._catalogs[6],center+lead*0.5*ratio,pose.scale,angle,
					size+padding*ratio,true,budget,planner._selection_work)
				row=c1_compact_metrics(planner,direct,pose,committed,successor)
				row["kind"]="direct";row["query_guard"]=192*ratio;row["query_budget"]=budget
				print("[Tokyo C1 compact diagnostic] ",JSON.stringify(row))
	if loader._future_predictor!=null: loader._future_predictor.close();loader._future_predictor=null
	loader._stream.free();loader.free()
	print("[Tokyo C1 compact diagnostic] replay_fail=",failures)
	return failures


static func run() -> int:
	var failures := differential_checks() + native_bridge_checks() + mixed_cached_hlod_checks() + directional_trim_checks() + guard_budget_retry_checks() + motion_guard_actual_checks() + native_motion_guard_checks() + native_motion_retention_checks() + native_motion_query_checks() + native_motion_prefetch_checks()
	if OS.get_environment("AGL_TOKYO_NATIVE_MOTION_DIAGNOSTIC")=="1": failures+=installed_native_motion_diagnostic()
	if OS.get_environment("AGL_TOKYO_C1_COMPACT_DIAGNOSTIC")=="1": failures+=installed_c1_compact_diagnostic()
	print("[Tokyo planner] fail=", failures)
	return failures
