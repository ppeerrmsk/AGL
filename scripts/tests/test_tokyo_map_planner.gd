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


class ForecastCapture extends RefCounted:
	var request: Dictionary={}
	func plan(value: Dictionary) -> Dictionary:
		request=value
		return {"status":"captured"}


class NativeRetentionOverlay extends "res://scripts/rendering/tokyo_hlod_overlay.gd":
	var coverage_probe: RefCounted
	func _cut_covers_current_view(cut: Dictionary, catalog: int, margin_px: float = 0.0) -> bool:
		return coverage_probe._cut_covers_current_view(cut,catalog,margin_px)


class LodSuccessorOverlay extends "res://scripts/rendering/tokyo_hlod_overlay.gd":
	var fixture_ready := true
	var covered := true
	var requested := 0
	var combined := BUDGET
	func _cut_covers_current_view(_cut: Dictionary, _catalog: int, _margin_px: float = 0.0) -> bool: return covered
	func _resources_ready(_cut: Dictionary, _catalog: int) -> bool: return fixture_ready
	func _handoff_bytes(_next: Dictionary, _selected: int) -> int: return combined
	func _request_target(_keep_current: bool) -> void: requested+=1


static func lod_reverse_successor_checks() -> int:
	var failures := 0
	var overlay := LodSuccessorOverlay.new()
	var pool := GuardPool.new()
	overlay._stream=pool
	overlay._catalogs=[{"max_scale":1.25,"rows":{"coarse":{"max_scale":1.25}}}]
	overlay._committed_catalog=0
	overlay._committed_cut={"keys":PackedStringArray(["coarse"]),"within_budget":true,
		"lod_successor":{"catalog":-2,"cut":{"keys":PackedStringArray(["fine"]),"configuration":"lod5_full","within_budget":true},
		"direction":1,"scale":1.18,"reverse_scale":1.245}}
	overlay._zoom_rate=1.0
	overlay.fixture_ready=false
	failures+=int(overlay._stage_lod_successor(1.2) or not overlay._target.is_empty())
	overlay.fixture_ready=true;overlay.covered=false
	failures+=int(overlay._stage_lod_successor(1.2) or not overlay._target.is_empty())
	overlay.covered=true;overlay.combined=BUDGET+1
	failures+=int(overlay._stage_lod_successor(1.2) or not overlay._target.is_empty())
	overlay.combined=BUDGET
	for cycle in 20:
		var before := var_to_bytes(overlay._committed_cut)
		if not overlay._stage_lod_successor(1.2):
			failures+=1;break
		failures+=int(before!=var_to_bytes(overlay._committed_cut))
		var reverse: Dictionary=overlay._target.get("lod_successor",{})
		if reverse.is_empty():
			failures+=1;break
		failures+=int(int(reverse.catalog)!=overlay._committed_catalog or int(reverse.direction)*overlay._zoom_rate>=0.0)
		failures+=int(not is_equal_approx(float(reverse.scale),1.245 if overlay._zoom_rate>0.0 else 1.18))
		failures+=int(reverse.cut.has("lod_successor") or var_to_bytes(overlay._target).size()>2048)
		overlay._committed_catalog=overlay._target_catalog
		overlay._committed_cut=overlay._target.duplicate(true)
		overlay._target={};overlay._zoom_rate=-overlay._zoom_rate
	failures+=int(overlay.requested!=20)
	overlay.free();pool.free()
	print("[Tokyo LOD reverse successor] fail=",failures)
	return failures


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


static func compact_request_checks() -> int:
	var source := source_fixture()
	var request := request_fixture(Vector2.ZERO,0.06)
	request.stream._cache={"ready_mesh":true};request.stream._textures={"ready_image":true}
	request.stream.planned_meshes={"pending_mesh":true};request.stream.planned_images={"pending_image":true}
	var packed := request.duplicate(true)
	for field: String in ["_cache","_textures","planned_meshes","planned_images"]:
		packed.stream[field]=PackedStringArray(request.stream[field].keys())
		packed.stream[field].append(packed.stream[field][0])
	var before := var_to_bytes(packed)
	var plain_planner := Planner.new()
	var packed_planner := Planner.new()
	if not plain_planner.configure(source) or not packed_planner.configure(source): return 1
	var plain := plain_planner.plan(request)
	var result := packed_planner.plan(packed)
	var failures := int(comparable_cut(plain.cut)!=comparable_cut(result.cut) or plain.status!=result.status)
	failures+=int(packed_planner._stream!=request.stream or var_to_bytes(packed)!=before or not Worker.pure(packed))
	failures+=int(Worker.pure(PackedStringArray(["a","b"]),2) or not Worker.pure(PackedStringArray(["a","b"]),3))
	var cut := {"prefetch_extra":[{"mesh":"a","image":"x"},{"mesh":"b","image":"x"},{"mesh":"a","image":"x"},{"mesh":"a","image":"y"}]}
	var cut_before := var_to_bytes(cut)
	var compact := Planner.compact_cut(cut)
	failures+=int(compact.prefetch_extra!=[cut.prefetch_extra[0],cut.prefetch_extra[1],cut.prefetch_extra[3]])
	compact.prefetch_extra[0].mesh="changed"
	failures+=int(var_to_bytes(cut)!=cut_before)
	print("[Tokyo compact request] fail=",failures)
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


static func shared_texture_mesh_checks() -> int:
	var coarse := {"max_scale":0.25,"rows":{
		"same":{"bounds":[0,0,10,10],"native_geometry":{"path":"coarse"},"native_texture":{"path":"shared"}},
		"different":{"bounds":[10,0,20,10],"native_geometry":{"path":"other"},"native_texture":{"path":"other_image"}}}}
	var fine := {"max_scale":0.625,"rows":{
		"same":{"bounds":[0,0,10,10],"native_geometry":{"path":"fine"},"native_texture":{"path":"shared"}},
		"moved":{"bounds":[30,0,40,10],"native_geometry":{"path":"wrong_bounds"},"native_texture":{"path":"other_image"}}}}
	var catalogs: Array[Dictionary]=[coarse,fine]
	var original := var_to_bytes(catalogs)
	var aliases := Handoff.shared_texture_meshes(catalogs)
	var failures := int(aliases!={0:{"coarse":{"mesh":"fine","image":"shared"}}} or not Worker.pure(aliases) or var_to_bytes(catalogs)!=original)
	fine.rows.same.native_texture.path="different_image"
	failures+=int(not Handoff.shared_texture_meshes(catalogs).is_empty())
	print("[Tokyo shared texture meshes] fail=",failures)
	return failures


static func resident_reuse_checks() -> int:
	var data := preload("res://scripts/tests/test_tokyo_hlod_manifest.gd").fixture()
	data.max_scale=2.0
	var catalog := Contract.normalize(data)
	var source := source_fixture()
	source.catalogs=[catalog];source.geometry=catalog.geometry;source.textures=catalog.textures;source.prepared_catalogs={}
	source.flags={"return_cache":true}
	var planner := Planner.new()
	if not planner.configure(source): return 1
	var center := Vector2(-12000,-12000)
	var size := Vector2(6000,6000)
	var original := Contract.select(catalog,center,1.0,0,size)
	if original.is_empty() or not original.within_budget: return 1
	planner._stream=request_fixture(center,1.0).stream
	for path: String in catalog.geometry: planner._stream._cache[path]=true
	for path: String in catalog.textures: planner._stream._textures[path]=true
	for key: String in original.keys: planner._stream._cache.erase(catalog.rows[key].native_geometry.path)
	var before := var_to_bytes(original)
	var resident := planner._prefer_resident_hlod(catalog,original,center,1.0,0,size,false,BUDGET)
	var failures := int(not resident.get("cache_reuse",false) or resident.keys==original.keys or not planner._resources_ready(resident,0))
	failures+=int(not Handoff.covers_motion_view(catalog,resident,center,1.0,0,size) or not resident.within_budget)
	failures+=int(planner._prefer_resident_hlod(catalog,original,center,1.0,0,size,false,int(resident.bytes)-1)!=original)
	# 便宜父块在请求中时，不能反过来替换已经完整就绪的子块。
	planner._stream.planned_meshes={}
	for key: String in original.keys: planner._stream.planned_meshes[catalog.rows[key].native_geometry.path]=true
	failures+=int(planner._prefer_resident_hlod(catalog,original,center,1.0,0,size,false,BUDGET).keys!=resident.keys)
	planner._stream.planned_meshes=planner._stream._cache.duplicate()
	planner._stream.planned_images=planner._stream._textures.duplicate()
	planner._stream._cache.clear();planner._stream._textures.clear()
	var pending := planner._prefer_resident_hlod(catalog,original,center,1.0,0,size,false,BUDGET)
	failures+=int(not pending.get("request_reuse",false) or pending.get("cache_reuse",false) or pending.keys!=resident.keys)
	failures+=int(planner._resources_ready(pending,0))
	failures+=int(planner._prefer_resident_hlod(catalog,original,center,1.0,0,size,false,int(resident.bytes)-1)!=original)
	planner._stream.planned_images.clear()
	planner._stream._textures.clear()
	failures+=int(planner._prefer_resident_hlod(catalog,original,center,1.0,0,size,false,BUDGET)!=original or var_to_bytes(original)!=before)
	print("[Tokyo resident reuse] fail=",failures)
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


static func waiting_display_trim_checks() -> int:
	var source := guard_retry_source(200.0,55)
	source.native={}
	var catalog: Dictionary=source.catalogs[0]
	var subset := catalog.duplicate()
	subset.roots=catalog.roots.slice(0,2)
	var old := Contract.select(subset,Vector2(5000,0),1.0,0.0,Vector2(12000,70),false,BUDGET,source.context)
	var display := request_fixture(Vector2.ZERO,1.0,0.0,Vector2(100,70))
	var request := request_fixture(Vector2(80,0),1.0,0.0,Vector2(100,70))
	request.committed_catalog=0;request.committed=old
	request.target_catalog=0;request.target=old
	request["camera_demand"]=true
	request["display_canvas"]=display.canvas;request["display_size"]=display.size;request["display_scale"]=display.scale
	var planner := Planner.new()
	if not planner.configure(source): return 1
	var before := var_to_bytes(request)
	var result := planner.plan(request)
	# 旧页仍完整显示原机位，待移动机位缺页且联合费用超限；必须先只释放屏外55MiB旧页。
	var failures := int(result.status!="candidate" or result.cut.get("selection_stage")!="trim_displayed" \
		or result.cut.get("keys")!=PackedStringArray(["0:1"]) or not result.force_replan)
	failures+=int(var_to_bytes(request)!=before or not Worker.pure(result))
	# 屏内缺页、失格或没有守卫的请求均不得借此裁页。
	request.display_canvas=request.canvas
	failures+=int(not planner._trim_waiting_display(request).is_empty())
	request.display_canvas=display.canvas;request.display_scale=3.0
	failures+=int(not planner._trim_waiting_display(request).is_empty())
	request.display_scale=1.0;request.camera_demand=false
	failures+=int(not planner._trim_waiting_display(request).is_empty())
	print("[Tokyo planner] waiting_display_trim fail=",failures)
	return failures


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


static func enlarged_motion_pool_checks() -> int:
	var failures := 0
	# 快速缩远时旧切面50MiB，96px保护切面55MiB；96MiB池不可交接，192MiB可以。
	# 必须让新增缓存真正用于交接，不能先装20MiB裸视野再立刻装55MiB。
	for enabled: bool in [false,true]:
		for pool: int in [BUDGET,2*BUDGET,4*BUDGET]:
			for resident: int in [0,BUDGET]:
				if resident>=pool: continue
				var source := guard_retry_source(185.0,50)
				source.geometry["resident"]={"bytes":resident}
				source.flags={"display_compaction":true,"wide_motion_guard":enabled}
				var planner := Planner.new()
				if not planner.configure(source): return failures+1
				planner._stream=request_fixture(Vector2.ZERO,1.0).stream
				planner._stream.residency_limit=pool
				planner._stream.residency_bytes=resident
				if resident>0: planner._stream.residency_meshes=PackedStringArray(["resident"])
				planner._camera_demand_pending=true;planner._zoom_rate=-2.0
				var catalog: Dictionary=source.catalogs[0]
				var old := Contract.select(catalog,Vector2(10000,0),1.0,0.0,Vector2(100,70),false,BUDGET,source.context)
				planner._committed_catalog=0;planner._committed_cut=old;planner._committed=old.keys
				var cut := planner._select_hlod(catalog,Vector2.ZERO,1.0,0.0,Vector2(100,70),false,BUDGET/2,false)
				var enlarged := enabled and pool-resident>=2*BUDGET
				failures+=int(not cut.get("within_budget",false) or cut.get("spatial_guard_px",-1)!=(96.0 if enlarged else 0.0))
				failures+=int(cut.get("keys")!=(PackedStringArray(["0:1","0:2"]) if enlarged else PackedStringArray(["0:1"])))
				failures+=int(int(cut.get("bytes",BUDGET+1))>BUDGET or int(cut.get("active",17))>16 or int(cut.get("triangles",240001))>240000)
				# 常驻资源同样登记在物理账本；旧切面与新切面合计不可吃掉其预留。
				failures+=int(int(old.bytes)+int(cut.bytes)>pool-resident)
	print("[Tokyo planner] enlarged_motion_pool fail=",failures)
	return failures


static func motion_guard_source(side_mib: int, center_mib: int = 10) -> Dictionary:
	# 实际档(0.5,2]一页40MiB覆盖全图；提前细档(2,4]中心10MiB，左右各一页在裸视野外、48px保护带内。
	var bounds := Rect2(-1000,-1000,2000,2000)
	var geometry := {}
	var textures := {}
	var catalogs: Array[Dictionary]=[]
	for level in 2:
		var prefix: String=["coarse","finer"][level]
		var roots: Array[Dictionary]=[]
		var rows := {}
		var layout: Array=[[0.0,40,900.0]] if level==0 else [[0.0,center_mib,5.0],[60.0,side_mib,5.0],[-60.0,side_mib,5.0]]
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
			[50,Vector2(400,0),2.5,false,1,0.0],[50,Vector2(400,0),0.0,true,1,0.0],
			[50,Vector2.ZERO,0.0,false,0,192.0,80]]:
		# 最后一例为冷进入：零速度历史、细档裸视野80MiB，必须留下首次平移的交接空间。
		var source := motion_guard_source(int(scenario[0]),int(scenario[6]) if scenario.size()>6 else 10)
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
			okay=okay and is_equal_approx(float(result.cut.get("motion_guard_need_px",0)),Handoff.motion_guard_need(scenario[1],1.2,size)) \
				and Handoff.qualified(source.catalogs[0],result.cut,1.2)
			if scenario.size()==6:
				okay=okay and int(result.cut.get("prefetch_catalog",-1))==1 and not result.cut.get("prefetch_keys",PackedStringArray()).is_empty()
			else:
				# 80MiB细档与40MiB当前档不能同池共存；冷进入仍必须保留交接空间。
				okay=okay and int(result.cut.bytes)<=BUDGET/2
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


static func installed_display_compact_diagnostic() -> int:
	var loader := Overlay.new()
	loader._archive=loader._load_archive()
	if loader._archive==null or not loader._prepare_map_planner(): loader.free();return 1
	var planner: RefCounted=loader._map_worker._planner
	if planner._catalogs.size()<8:
		loader._map_worker.close();loader._map_worker=null;loader.free()
		return 1
	var catalog: Dictionary=planner._catalogs[6]
	var keys := PackedStringArray(["1:1","1:9","1:2","1:3","1:10","1:11"])
	var charges := Contract.charges(catalog,keys,planner._selection_work)
	var old := {"keys":keys,"charges":charges,"bytes":charges.total_bytes,"triangles":charges.faces,
		"active":keys.size(),"within_budget":charges.within_budget,"entries":[]}
	for key: String in keys:
		var parts := key.split(":")
		old.entries.append(Contract.tree(catalog.rows,int(parts[0]),int(parts[1])))
	var display := request_fixture(Vector2(-4549.134,-13805.84),0.249771565,0.0,Vector2(1920,1080))
	var request := request_fixture(Vector2(-4549.134,-14250.0),0.3536,0.0,Vector2(1920,1080))
	request.committed_catalog=6;request.committed=old;request.target_catalog=6;request.target=old
	request["camera_demand"]=true;request["display_canvas"]=display.canvas
	request["display_size"]=display.size;request["display_scale"]=display.scale
	var before := var_to_bytes(request)
	planner._flags["display_compaction"]=false
	var baseline: Dictionary=planner.plan(request)
	var old_union: int=planner._handoff_bytes(baseline.cut,int(baseline.catalog))
	planner._flags["display_compaction"]=true
	var result: Dictionary=planner.plan(request)
	var combined: int=planner._handoff_bytes(result.cut,int(result.catalog))
	var covered := Handoff.covers_motion_view(catalog,result.cut,Vector2(-4549.134,-13805.84),display.scale,0.0,display.size)
	var failures := int(old_union<=BUDGET or result.status!="candidate" or result.catalog!=6 \
		or result.cut.get("selection_stage")!="compact_displayed" or not result.force_replan \
		or not covered or not Handoff.qualified(catalog,result.cut,display.scale) \
		or combined<0 or combined>BUDGET or int(result.cut.bytes)>=int(old.bytes) \
		or before!=var_to_bytes(request) or not Worker.pure(result))
	print("[Tokyo displayed compaction] old=",old.bytes," baseline_union=",old_union," compact=",result.cut.get("bytes",0),
		" union=",combined," covered=",covered," stage=",result.cut.get("selection_stage","")," fail=",failures)
	request.display_scale=1.0
	failures+=int(not planner._trim_waiting_display(request).is_empty())
	request.display_scale=display.scale;request.camera_demand=false
	failures+=int(not planner._trim_waiting_display(request).is_empty())
	# 没有待处理镜头输入时，完整宽保护切面不能仅因大于半池而反复压缩、重载。
	failures+=int(not planner._compact_displayed_scale(request).is_empty())
	# 86 MiB 细档在缩远时卡住且没有在途 I/O；逐块替换必须在有限步内腾出半池。
	keys=PackedStringArray(["2:6","2:7","2:22","2:23","2:8","2:24"])
	catalog=planner._catalogs[4];charges=Contract.charges(catalog,keys,planner._selection_work)
	old={"keys":keys,"charges":charges,"bytes":charges.total_bytes,"triangles":charges.faces,
		"active":keys.size(),"within_budget":charges.within_budget,"entries":[]}
	for key: String in keys:
		var parts := key.split(":");old.entries.append(Contract.tree(catalog.rows,int(parts[0]),int(parts[1])))
	display=request_fixture(Vector2(-2003.303,-14683.86),0.420595467,0.0,Vector2(1920,1080))
	request=request_fixture(Vector2(-2003.303,-14683.86),0.38,0.0,Vector2(1920,1080))
	request.committed_catalog=4;request.committed=old;request.target_catalog=4;request.target=old
	request["camera_demand"]=true;request["display_canvas"]=display.canvas
	request["display_size"]=display.size;request["display_scale"]=display.scale
	request.zoom_rate=-2.0;request.zooming_out=true
	var progressed := false
	for step in 8:
		request.sequence+=1
		result=planner.plan(request)
		combined=planner._handoff_bytes(result.cut,int(result.catalog))
		var completes_motion: bool=result.catalog>=0 and Handoff.qualified(planner._catalogs[int(result.catalog)],result.cut,request.scale) \
			and Handoff.covers_motion_view(planner._catalogs[int(result.catalog)],result.cut,Vector2(-2003.303,-14683.86),request.scale,0.0,request.size)
		var step_good: bool=result.status=="candidate" and result.catalog>=0 and combined>=0 and combined<=BUDGET \
			and Handoff.qualified(planner._catalogs[int(result.catalog)],result.cut,display.scale) \
			and Handoff.covers_motion_view(planner._catalogs[int(result.catalog)],result.cut,Vector2(-2003.303,-14683.86),display.scale,0.0,display.size) \
			and (int(result.cut.bytes)<int(request.committed.bytes) or completes_motion)
		print("[Tokyo displayed scale compaction] step=",step," bytes=",result.cut.get("bytes",0)," union=",combined," good=",step_good)
		if not step_good: failures+=1;break
		request.committed_catalog=result.catalog;request.committed=result.cut
		request.target_catalog=result.catalog;request.target=result.cut
		if completes_motion or int(result.cut.bytes)<=BUDGET/2: progressed=true;break
	failures+=int(not progressed)
	# SPACE 远距返回的真实混合切面：完整目标和沿输入路径的中间机位分别核费用。
	keys=PackedStringArray(["9:49","8:57","9:50","9:51","9:58","9:59"])
	catalog=planner._catalogs[7];charges=Contract.charges(catalog,keys,planner._selection_work)
	old={"keys":keys,"charges":charges,"bytes":charges.total_bytes,"triangles":charges.faces,
		"active":keys.size(),"within_budget":charges.within_budget,"entries":[]}
	for key: String in keys:
		var parts := key.split(":");old.entries.append(Contract.tree(catalog.rows,int(parts[0]),int(parts[1])))
	var from := Vector2(-5166.319,11823.708)
	var toward := Vector2(-660.0,11950.0)
	for fraction: float in [1.0,0.5,0.25,0.125,0.0625]:
		request=request_fixture(from.lerp(toward,fraction),0.2,0.0,Vector2(1920,1080))
		request.committed_catalog=7;request.committed=old;request.target_catalog=7;request.target=old
		request["camera_demand"]=true
		display=request_fixture(from,0.200064823,0.0,request.size)
		request["display_canvas"]=display.canvas;request["display_size"]=display.size;request["display_scale"]=display.scale
		result=planner.plan(request)
		if fraction==1.0:
			# 可以先释放仍在显示的同档父页，但必须有限步内继续路径，不能只反复压缩停镜。
			var continued := false
			var progress_request := request.duplicate(true)
			var progress_result := result
			for step in 8:
				var progress_catalog: int=progress_result.catalog
				var progress_cut: Dictionary=progress_result.cut
				if progress_result.status!="candidate" or progress_catalog<0 \
					or planner._handoff_bytes(progress_cut,progress_catalog)>BUDGET: break
				if progress_cut.get("motion_checkpoint",false) or Handoff.covers_motion_view(planner._catalogs[progress_catalog],progress_cut,toward,0.2,0.0,request.size):
					continued=true;break
				if int(progress_cut.bytes)>=int(progress_request.committed.bytes) or not progress_result.force_replan \
					or not Handoff.qualified(planner._catalogs[progress_catalog],progress_cut,display.scale) \
					or not Handoff.covers_motion_view(planner._catalogs[progress_catalog],progress_cut,from,display.scale,0.0,display.size): break
				progress_request.committed_catalog=progress_catalog;progress_request.committed=progress_cut
				progress_request.target_catalog=progress_catalog;progress_request.target=progress_cut
				progress_request.sequence+=1
				progress_result=planner.plan(progress_request)
			failures+=int(not continued)
			planner.plan(request)
		var actual: Dictionary=planner._select_handoff_hlod(6,from.lerp(toward,fraction),0.2,0.0,request.size,BUDGET)
		print("[Tokyo return path] fraction=",fraction," status=",result.status," catalog=",result.catalog,
			" union=",planner._handoff_bytes(result.cut,int(result.catalog))," stage=",result.cut.get("selection_stage",""),
			" actual=",actual.get("bytes",0)," actual_union=",planner._handoff_bytes(actual,6))
	# 连续缩远的真实混合切面：细档父页仍相交，需同档空间细分而不是重求所有档。
	keys=PackedStringArray(["1:0","16:36","16:52","16:64","16:65","16:66","16:67","16:68"])
	catalog=planner._catalogs[7];charges=Contract.charges(catalog,keys,planner._selection_work)
	old={"keys":keys,"charges":charges,"bytes":charges.total_bytes,"triangles":charges.faces,
		"active":keys.size(),"within_budget":charges.within_budget,"entries":[]}
	for key: String in keys:
		old.entries.append(Contract.tree(catalog.rows,int(key.get_slice(":",0)),int(key.get_slice(":",1))))
	request=request_fixture(Vector2(-11171.36,-6140),0.20109254,0.0,Vector2(1920,1080))
	display=request_fixture(Vector2(-11171.36,-8372.352),0.20723979,0.0,request.size)
	request.committed_catalog=7;request.committed=old;request.target_catalog=7;request.target=old
	request["camera_demand"]=true;request["display_canvas"]=display.canvas
	request["display_size"]=display.size;request["display_scale"]=display.scale
	request.zoom_rate=-0.05748;request.zooming_out=true;request.pan_velocity=Vector2(0,20867)
	result=planner.plan(request)
	var compact: Dictionary=planner._trim_waiting_display(request)
	var spatial_good: bool=not compact.is_empty() and int(compact.bytes)<int(old.bytes) \
		and planner._handoff_bytes(compact,7)<=BUDGET \
		and Handoff.covers_motion_view(catalog,compact,Vector2(-11171.36,-8372.352),display.scale,0.0,display.size)
	failures+=int(not spatial_good)
	print("[Tokyo mixed spatial compact] old=",old.bytes," compact=",compact.get("bytes",0),
		" union=",planner._handoff_bytes(compact,7)," good=",spatial_good)
	if not spatial_good:
		var local := catalog.duplicate()
		var local_roots: Array[Dictionary]=[]
		for key: String in keys:
			local_roots.append(catalog.transition_spatial_trees[key])
			print("[Tokyo mixed source] ",key," bytes=",catalog.transition_leaves[key].bytes)
		local.roots=local_roots;local.erase("identity");local.erase("transition_intervals")
		for budget: int in [BUDGET/2,BUDGET]:
			var trial := Contract.select(local,Vector2(-11171.36,-8372.352),display.scale,0.0,display.size,false,budget,planner._selection_work)
			print("[Tokyo mixed local] ",JSON.stringify({"budget":budget,"within":trial.get("within_budget",false),
				"bytes":trial.get("bytes",0),"faces":trial.get("triangles",0),"pages":trial.get("active",0),
				"keys":trial.get("keys",[]),"union":planner._handoff_bytes(trial,7),
				"covered":Handoff.covers_motion_view(catalog,trial,Vector2(-11171.36,-8372.352),display.scale,0.0,display.size)}))
	# 快速反向放大的真实粗档大页：64 MB 旧页和整套紧凑页不能同池，须逐父页细分。
	keys=PackedStringArray(["0:0","1:2","1:10"])
	catalog=planner._catalogs[6];charges=Contract.charges(catalog,keys,planner._selection_work)
	old={"keys":keys,"charges":charges,"bytes":charges.total_bytes,"triangles":charges.faces,
		"active":keys.size(),"within_budget":charges.within_budget,"entries":[]}
	for key: String in keys:
		old.entries.append(Contract.tree(catalog.rows,int(key.get_slice(":",0)),int(key.get_slice(":",1))))
	display=request_fixture(Vector2(-11035.0605,-13272.2285),0.249601573,0.0,Vector2(1920,1080))
	request=request_fixture(Vector2(-11035.0605,-13700),0.285,0.0,display.size)
	request.committed_catalog=6;request.committed=old;request.target_catalog=6;request.target=old
	request["camera_demand"]=true;request["display_canvas"]=display.canvas
	request["display_size"]=display.size;request["display_scale"]=display.scale
	request.zoom_rate=2.0;request.pan_velocity=Vector2(0,-2400)
	progressed=false
	for step in 8:
		request.sequence+=1
		planner.plan(request)
		var split: Dictionary=planner._compact_displayed_scale(request)
		if split.is_empty(): failures+=1;break
		combined=planner._handoff_bytes(split.cut,int(split.catalog))
		var split_good: bool=combined>=0 and combined<=BUDGET and int(split.cut.bytes)<int(request.committed.bytes) \
			and Handoff.qualified(planner._catalogs[split.catalog],split.cut,display.scale) \
			and Handoff.covers_motion_view(planner._catalogs[split.catalog],split.cut,Vector2(-11035.0605,-13272.2285),display.scale,0.0,display.size)
		print("[Tokyo coarse reversal compact] step=",step," bytes=",split.cut.bytes," union=",combined," good=",split_good)
		if not split_good: failures+=1;break
		request.committed_catalog=split.catalog;request.committed=split.cut
		request.target_catalog=split.catalog;request.target=split.cut
		if int(split.cut.bytes)<=BUDGET/2: progressed=true;break
	failures+=int(not progressed)
	# 旋转巡检曾在此姿态沿用已不能覆盖的旧切面；新选页的保护带须与覆盖证明一致。
	keys=PackedStringArray(["1:3","2:39","1:4","2:40","2:41"])
	catalog=planner._catalogs[5];charges=Contract.charges(catalog,keys,planner._selection_work)
	old={"keys":keys,"charges":charges,"bytes":charges.total_bytes,"triangles":charges.faces,
		"active":keys.size(),"within_budget":charges.within_budget,"entries":[]}
	for key: String in keys:
		old.entries.append(Contract.tree(catalog.rows,int(key.get_slice(":",0)),int(key.get_slice(":",1))))
	var rotated_center := Vector2(362.6699,-13442.43)
	var rotated_angle := atan2(-0.006151,0.309253)
	request=request_fixture(rotated_center,0.257761379,rotated_angle,Vector2(1600,900))
	request.committed_catalog=5;request.committed=old;request.target_catalog=5;request.target=old
	request.zoom_rate=-0.2289518;request.zooming_out=true;request.pan_velocity=Vector2(-235.2464,534.6454)
	result=planner.plan(request)
	var fresh: Dictionary=planner._select_hlod(catalog,rotated_center,request.scale,rotated_angle,request.size,true,BUDGET/2)
	var fresh_covered := Handoff.covers_motion_view(catalog,fresh,rotated_center,request.scale,rotated_angle,request.size)
	var fresh_guarded := Handoff.covers_motion_view(catalog,fresh,rotated_center,request.scale,rotated_angle,request.size+Vector2.ONE*float(fresh.get("spatial_guard_px",0.0))*2.0)
	print("[Tokyo rotated guard] actual=",fresh_covered," guard=",fresh_guarded," px=",fresh.get("spatial_guard_px",0.0),
		" fresh=",fresh.get("keys",[])," planned=",result.cut.get("keys",[])," stage=",result.cut.get("selection_stage",""))
	failures+=int(not fresh_covered or not fresh_guarded)
	# C2 缩远时84MiB旧档阻塞带保护的新档，不能拖到只装得下裸视野才切换。
	keys=PackedStringArray(["2:37","2:53","1:11","1:12","1:13","2:69","2:85","1:19","2:101","2:102","2:103","1:20","1:21","1:28","2:106"])
	catalog=planner._catalogs[6];charges=Contract.charges(catalog,keys,planner._selection_work)
	old={"keys":keys,"charges":charges,"bytes":charges.total_bytes,"triangles":charges.faces,
		"active":keys.size(),"within_budget":charges.within_budget,"entries":[]}
	for key: String in keys:
		old.entries.append(Contract.tree(catalog.rows,int(key.get_slice(":",0)),int(key.get_slice(":",1))))
	rotated_center=Vector2(300.0005,-6690.441);rotated_angle=atan2(-0.006259,0.219008)
	request=request_fixture(rotated_center,0.182581394910812,rotated_angle,Vector2(1600,900))
	request.committed_catalog=6;request.committed=old;request.target_catalog=6;request.target=old
	request.zoom_rate=-0.193465568;request.zooming_out=true;request.pan_velocity=Vector2(0.002667,-3013.898)
	result=planner.plan(request)
	var motion := Handoff.native_motion_query(rotated_center,request.scale,rotated_angle,request.size,
		Handoff.pan_lead(request.pan_velocity,request.scale,0.25,request.size),0.25,request.zoom_rate)
	combined=planner._handoff_bytes(result.cut,int(result.catalog))
	var progressive: bool=result.status=="candidate" and result.catalog>=0 and int(result.cut.bytes)<int(old.bytes) \
		and combined>=0 and combined<=BUDGET and Handoff.qualified(planner._catalogs[result.catalog],result.cut,request.scale) \
		and Handoff.covers_motion_view(planner._catalogs[result.catalog],result.cut,motion.center,request.scale,rotated_angle,motion.size)
	print("[Tokyo moving coarse compaction] stage=",result.cut.get("selection_stage","")," old=",old.bytes,
		" next=",result.cut.get("bytes",0)," union=",combined," good=",progressive)
	if not progressive:
		var transition := preload("res://scripts/rendering/tokyo_hlod_transition.gd")
		var destination := Handoff.catalog_index(planner._catalogs,request.scale,false)
		var joined := transition.index_for(planner._catalogs,6,destination)
		print("[Tokyo moving coarse query] destination=",destination," joined=",joined," flags=",planner._flags)
		if joined>=0:
			for margin: float in [0.0,48.0,96.0]:
				var trial: Dictionary=transition.compact_display(planner._catalogs,6,old,destination,motion.center,request.scale,rotated_angle,
					motion.size+Vector2.ONE*margin*2.0,BUDGET-planner._handoff_bytes({"keys":PackedStringArray()},joined),
					planner._handoff_incremental_costs(joined),planner._selection_work)
				print("[Tokyo moving coarse trial] margin=",margin," bytes=",trial.get("cut",{}).get("bytes",0))
	failures+=int(not progressive)
	request.zooming_out=false
	failures+=int(not planner._compact_displayed_scale(request).is_empty())
	request.zooming_out=true;request.zoom_rate=0.0
	failures+=int(not planner._compact_displayed_scale(request).is_empty())
	request.zoom_rate=-0.193465568;planner._flags.display_compaction=false
	failures+=int(not planner._compact_displayed_scale(request).is_empty())
	loader._map_worker.close();loader._map_worker=null;loader.free()
	return failures


static func installed_f5_wait_diagnostic() -> int:
	var file := FileAccess.open(OS.get_environment("AGL_TOKYO_F5_WAIT_REPLAY"),FileAccess.READ)
	if file==null: return 1
	var snapshot: Variant=file.get_var(false)
	file.close()
	if not snapshot is Dictionary or not snapshot.get("request") is Dictionary: return 1
	var loader := Overlay.new()
	loader._archive=loader._load_archive()
	if loader._archive==null or loader._native==null:
		loader.free();return 1
	if not loader._prepare_map_planner(): loader.free();return 1
	var planner: RefCounted=loader._map_worker._planner
	var request: Dictionary=snapshot.request
	var result: Dictionary=planner.plan(request)
	var center: Vector2=request.canvas.affine_inverse()*(request.logical*0.5)
	print("[F5 wait replay] pose=",center," scale=",request.scale," size=",request.size,
		" status=",result.status," faces=",result.cut.get("triangles",0)," pages=",result.cut.get("active",0))
	var native: RefCounted=loader._native
	var failures := int(result.status!="candidate" or not result.cut.get("within_budget",false))
	if failures==0:
		failures+=int(not planner._cut_covers_current_view(result.cut,int(result.catalog)))
		failures+=int(not Handoff.native_qualified(result.cut,request.scale)) if int(result.catalog)==-2 else 0
		failures+=int(planner._handoff_bytes(result.cut,int(result.catalog))>BUDGET)
	var report := {"exact_request_status":result.status,"exact_request_faces":result.cut.get("triangles",0),
		"exact_request_pages":result.cut.get("active",0),"exact_request_bytes":result.cut.get("bytes",0),"poses":[]}
	# 可选空间审计只求纯值切面，不混入渲染或性能结论。
	if OS.has_environment("AGL_TOKYO_F5_POSES"):
		var poses: Variant=JSON.parse_string(FileAccess.get_file_as_string(OS.get_environment("AGL_TOKYO_F5_POSES")))
		if not poses is Dictionary or not poses.get("poses") is Array:
			failures+=1
		else:
			var sequence := 100000
			for pose: Dictionary in poses.poses:
				sequence+=1
				var cold := request_fixture(Vector2(pose.center[0],pose.center[1]),float(pose.scale),float(pose.get("rotation",0.0)),request.size,sequence)
				var selected: Dictionary=planner.plan(cold)
				var covered: bool=selected.status=="candidate" and planner._cut_covers_current_view(selected.cut,int(selected.catalog))
				var row := {"pose":pose,"status":selected.status,"covered":covered,"faces":selected.cut.get("triangles",0),"pages":selected.cut.get("active",0),"bytes":selected.cut.get("bytes",0)}
				if not covered and int(selected.catalog)==-2:
					row["entries"]=[]
					for entry: Dictionary in selected.cut.get("entries",[]):
						row.entries.append({"path":entry.path,"faces":entry.faces,"layers":entry.triangles,"mask":entry.mask,
							"refinable":preload("res://scripts/tests/build_tokyo_lossless_leaf_partitions.gd").refinable(entry,native,selected.cut.configuration)})
					if OS.get_environment("AGL_TOKYO_F5_SOURCE_TREE")=="1":
						row["source_branches"]=[]
						var stack: Array=[]
						for root: Dictionary in native.catalog.configurations[selected.cut.configuration]: stack.append({"entry":root,"parents":[]})
						while not stack.is_empty():
							var item: Dictionary=stack.pop_back()
							var entry: Dictionary=item.entry
							var descriptor := {"path":entry.path,"triangles":entry.triangles,"bytes":entry.bytes,"identity":native.pages[entry.path].canonical_identity,
								"no_game_sources":preload("res://scripts/tests/tokyo_partition_attach_probe.gd").no_game_sources(entry,native,selected.cut.configuration)}
							if entry.path in selected.cut.keys: row.source_branches.append(item.parents+[descriptor])
							for child: Dictionary in entry.children: stack.append({"entry":child,"parents":item.parents+[descriptor]})
				report.poses.append(row)
				if not covered: print("[F5 spatial failure] ",JSON.stringify(row));failures+=1
	for entry: Dictionary in result.cut.get("entries",[]) if OS.get_environment("AGL_TOKYO_F5_REFINE_PROBE")=="1" else []:
		print("[F5 wait leaf] ",String(entry.path).get_file()," faces=",entry.faces," refinable=",
			preload("res://scripts/tests/build_tokyo_lossless_leaf_partitions.gd").refinable(entry,native,result.cut.configuration))
	for depth: int in [1,2,3] if OS.get_environment("AGL_TOKYO_F5_REFINE_PROBE")=="1" else []:
		var probe := preload("res://scripts/tests/tokyo_native_refinement_probe.gd").new()
		probe.branching=2;probe.current_roots=true
		probe.eligible_leaf=preload("res://scripts/tests/build_tokyo_lossless_leaf_partitions.gd").refinable.bind(native,result.cut.configuration)
		var cut: Dictionary=probe.select(native,center,request.scale,request.canvas.get_rotation(),request.size,result.cut.configuration,depth)
		print("[F5 wait refinement] depth=",depth," failed=",probe.failed," faces=",cut.get("triangles",0),
			" pages=",cut.get("active",0)," bytes=",cut.get("bytes",0)," within=",cut.get("within_budget",false))
	loader._map_worker.close();loader._map_worker=null
	loader.free()
	report["fail"]=failures
	if OS.has_environment("AGL_TOKYO_F5_REPLAY_REPORT"):
		var output := FileAccess.open(OS.get_environment("AGL_TOKYO_F5_REPLAY_REPORT"),FileAccess.WRITE)
		if output==null: failures+=1
		else: output.store_string(JSON.stringify(report,"\t"));output.close()
	print("[F5 wait replay] checked=",report.poses.size()+1," fail=",failures)
	return failures


static func hlod_zoom_boundary_checks() -> int:
	var planner := Planner.new()
	var catalog := {"range":[0.24,0.625]}
	var size := Vector2(1920,1080)
	planner._zoom_rate=-2.0
	var failures := int(not planner._hlod_zoom_padding(catalog,0.28,size).is_equal_approx(Handoff.zoom_out_padding(-2.0,size)))
	planner._flags["display_compaction"]=true
	var padding := planner._hlod_zoom_padding(catalog,0.28,size)
	# 空间包络仍覆盖到换档边界，但不为 .24 以下视野继续加载细档。
	failures+=int(not (size+padding).is_equal_approx(size*0.28/0.24))
	failures+=int(not planner._hlod_zoom_padding(catalog,0.21,size).is_zero_approx())
	failures+=int(not planner._hlod_zoom_padding(catalog,0.6,size).is_equal_approx(Handoff.zoom_out_padding(-2.0,size)))
	planner._zoom_rate=2.0
	failures+=int(not planner._hlod_zoom_padding(catalog,0.28,size).is_zero_approx())
	# 最远滚轮档之外没有后续视野：保留到下限的完整包络，不能继续加载更远目录。
	planner._zoom_rate=-2.0;planner._prediction_floor=0.26
	padding=planner._hlod_zoom_padding(catalog,0.28,size)
	failures+=int(not (size+padding).is_equal_approx(size*0.28/0.26))
	failures+=int(not planner._hlod_zoom_padding(catalog,0.26,size).is_zero_approx())
	planner._flags.display_compaction=false
	failures+=int(not planner._hlod_zoom_padding(catalog,0.28,size).is_equal_approx(Handoff.zoom_out_padding(-2.0,size)))
	# 下限按每个请求取值；切到演出、关闭候选或失效元数据都必须撤销旧下限。
	var source := source_fixture()
	source.flags["display_compaction"]=true
	if not planner.configure(source): return failures+1
	var request := request_fixture(Vector2.ZERO,0.08)
	request["prediction_floor"]=0.075
	planner.plan(request)
	failures+=int(not is_equal_approx(planner._prediction_floor,0.075))
	for floor_value: float in [0.0,0.2,NAN,-1.0]:
		request.prediction_floor=floor_value;planner.plan(request)
		failures+=int(not is_zero_approx(planner._prediction_floor))
	request.prediction_floor=0.075;planner._flags.display_compaction=false;planner.plan(request)
	failures+=int(not is_zero_approx(planner._prediction_floor))
	print("[Tokyo HLOD zoom boundary] fail=",failures)
	return failures


static func approaching_coarse_budget_checks() -> int:
	var source := guard_retry_source(185.0,20)
	source.flags["display_compaction"]=true
	var catalog: Dictionary=source.catalogs[0]
	catalog["range"]=[0.8,2.0]
	var planner := Planner.new()
	if not planner.configure(source): return 1
	planner._stream=request_fixture(Vector2.ZERO,1.0).stream
	var size := Vector2(100,70)
	var old := Contract.select(catalog,Vector2(10000,0),1.0,0.0,size,false,BUDGET,source.context)
	planner._committed_catalog=0;planner._committed_cut=old;planner._committed=old.keys
	planner._zoom_rate=-2.0
	var compact: Dictionary=planner._select_hlod(catalog,Vector2.ZERO,1.0,0.0,size,false,BUDGET/2)
	var failures := int(not compact.get("within_budget",false) or int(compact.bytes)>BUDGET/2 \
		or compact.keys!=PackedStringArray(["0:1"]) or not Handoff.covers_motion_view(catalog,compact,Vector2.ZERO,1.0,0.0,size))
	# 快速缩放和等待中的平移都要留交接空间；慢速巡检仍需完整保护带。
	catalog.range=[0.1,2.0]
	for rate: float in [-2.0,2.0,0.0]:
		planner._zoom_rate=rate
		planner._camera_demand_pending=is_zero_approx(rate)
		planner._pan_velocity=Vector2(50,0) if is_zero_approx(rate) else Vector2.ZERO
		var moving: Dictionary=planner._select_hlod(catalog,Vector2.ZERO,1.0,0.0,size,false,BUDGET/2)
		failures+=int(not moving.get("within_budget",false) or int(moving.bytes)>BUDGET/2 \
			or not Handoff.covers_motion_view(catalog,moving,Vector2.ZERO,1.0,0.0,size))
	planner._camera_demand_pending=false
	planner._zoom_rate=-0.1;planner._pan_velocity=Vector2.ZERO
	var slow: Dictionary=planner._select_hlod(catalog,Vector2.ZERO,1.0,0.0,size,false,BUDGET/2)
	failures+=int(not slow.get("within_budget",false) or int(slow.bytes)<=BUDGET/2 or float(slow.get("spatial_guard_px",0.0))<=0.0)
	# 连续平移没有待处理守卫事务时，必须保留前方页面；不能因速度快就退成裸视野。
	var moving_size := Vector2(100,400)
	planner._zoom_rate=0.1;planner._pan_velocity=Vector2(500,0)
	var lead := Handoff.pan_lead(planner._pan_velocity,1.0,0.25,moving_size)
	var patrol: Dictionary=planner._select_hlod(catalog,Vector2.ZERO,1.0,0.0,moving_size,false,BUDGET/2)
	failures+=int(Handoff.motion_guard_need(planner._pan_velocity,1.0,moving_size)<=96.0 \
		or not patrol.get("within_budget",false) or int(patrol.bytes)<=BUDGET/2 \
		or not Handoff.covers_motion_view(catalog,patrol,Vector2.ZERO,1.0,0.0,moving_size,lead))
	planner._camera_demand_pending=true
	var waiting: Dictionary=planner._select_hlod(catalog,Vector2.ZERO,1.0,0.0,moving_size,false,BUDGET/2)
	failures+=int(not waiting.get("within_budget",false) or int(waiting.bytes)>BUDGET/2)
	planner._camera_demand_pending=false;planner._pan_velocity=Vector2.ZERO
	planner._zoom_rate=-2.0
	planner._flags.display_compaction=false
	var control: Dictionary=planner._select_hlod(catalog,Vector2.ZERO,1.0,0.0,size,false,BUDGET/2)
	failures+=int(not control.get("within_budget",false) or int(control.bytes)<=BUDGET/2)
	print("[Tokyo approaching coarse budget] fail=",failures)
	return failures


static func pending_hlod_motion_checks() -> int:
	var source := guard_retry_source(185.0,20)
	source.flags["display_compaction"]=true
	var planner := Planner.new()
	if not planner.configure(source): return 1
	var catalog: Dictionary=source.catalogs[0]
	var size := Vector2(100,400)
	var request := request_fixture(Vector2.ZERO,1.0,0.0,size)
	planner._last_canvas=request.canvas;planner._last_size=size;planner._logical=size
	planner._committed_catalog=0;planner._committed=PackedStringArray(["0:0"])
	planner._target_catalog=0;planner._zoom_rate=0.1;planner._pan_velocity=Vector2(500,0)
	var bare := Contract.select(catalog,Vector2.ZERO,1.0,0.0,size,false,BUDGET,source.context)
	planner._target=bare
	var lead := Handoff.pan_lead(planner._pan_velocity,1.0,0.25,size)
	# 当前视野完整，但0.25秒内会进入尚未准备的前方页；不能继续复用这份旧需求。
	var failures := int(not planner._target_covers_current_view() \
		or Handoff.covers_motion_view(catalog,bare,Vector2.ZERO,1.0,0.0,size,lead) \
		or planner._pending_hlod_covers(1.0,false))
	# 已受输入守卫约束的等待、停镜与关闭候选继续沿原保留策略。
	planner._camera_demand_pending=true
	failures+=int(not planner._pending_hlod_covers(1.0,false))
	planner._camera_demand_pending=false;planner._pan_velocity=Vector2.ZERO
	failures+=int(not planner._pending_hlod_covers(1.0,false))
	planner._pan_velocity=Vector2(500,0);planner._flags.display_compaction=false
	failures+=int(not planner._pending_hlod_covers(1.0,false))
	planner._flags.display_compaction=true
	var ahead := Contract.select(catalog,lead*0.5,1.0,0.0,size+lead.abs(),false,BUDGET,source.context)
	planner._target=ahead
	failures+=int(not ahead.within_budget or not planner._pending_hlod_covers(1.0,false))
	print("[Tokyo pending HLOD motion] fail=",failures)
	return failures


static func transition_leaf_index_checks() -> int:
	var source := Fixture.catalog()
	var catalogs: Array[Dictionary]=[source,source.duplicate(true)]
	var joined := preload("res://scripts/rendering/tokyo_hlod_transition.gd").build(catalogs,[0,1])
	var failures := int(joined.is_empty())
	if joined.is_empty(): return failures
	for key: String in joined.rows:
		var expected := Contract.tree(joined.rows,int(key.get_slice(":",0)),int(key.get_slice(":",1)))
		expected.erase("children")
		# 必须保存所有后代的完整覆盖包络，不能仅用当前低楼网格包围盒近似。
		failures+=int(joined.transition_leaves.get(key,{})!=expected)
	failures+=int(not Worker.pure(joined))
	print("[Tokyo transition leaf index] fail=",failures)
	return failures


static func pending_compaction_progress_checks() -> int:
	var source := guard_retry_source(200.0,55)
	source.native={};source.flags={"display_compaction":true}
	var catalog: Dictionary=source.catalogs[0]
	var old := Contract.select(catalog,Vector2.ZERO,1.0,0.0,Vector2(200,70),false,BUDGET,source.context)
	var compact := Contract.select(catalog,Vector2.ZERO,1.0,0.0,Vector2(100,70),false,BUDGET,source.context)
	compact["selection_stage"]="compact_displayed"
	var display := request_fixture(Vector2.ZERO,1.0)
	var planner := Planner.new()
	if not planner.configure(source): return 1
	var failures := 0
	for center: Vector2 in [Vector2(200,0),Vector2(230,0),Vector2(-200,0)]:
		var request := request_fixture(center,1.0)
		request.committed_catalog=0;request.committed=old;request.target_catalog=0;request.target=compact
		request["camera_demand"]=true;request["display_canvas"]=display.canvas
		request["display_size"]=display.size;request["display_scale"]=display.scale
		var result := planner.plan(request)
		failures+=int(result.status!="candidate" or result.catalog!=0 or result.cut.get("keys")!=compact.keys \
			or result.cut.get("selection_stage")!="compact_displayed" or not result.force_replan)
		# 失去实际覆盖、清晰度或联合预算后仍必须取消，不保留不安全事务。
		request.display_canvas=request_fixture(Vector2(200,0),1.0).canvas
		failures+=int(planner._pending_display_compaction(request))
		request.display_canvas=display.canvas;request.display_scale=3.0
		failures+=int(planner._pending_display_compaction(request))
		request.display_scale=display.scale;request.stream.residency_limit=1
		planner._stream=request.stream
		failures+=int(planner._pending_display_compaction(request))
		request.stream.residency_limit=BUDGET;request.camera_demand=false
		failures+=int(planner._pending_display_compaction(request))
	planner._flags.display_compaction=false
	print("[Tokyo pending compaction progress] fail=",failures)
	return failures


static func pending_motion_path_checks() -> int:
	var source := guard_retry_source(500.0,20)
	source.native={};source.flags={"display_compaction":true}
	var catalog: Dictionary=source.catalogs[0]
	var ranges := [Vector2(-100,100),Vector2(300,440),Vector2(440,600),Vector2(-600,-100),Vector2(100,300)]
	var middle: Dictionary=catalog.roots[1].duplicate(true)
	middle.key="0:4";middle.path="0:4";catalog.roots.append(middle)
	catalog.rows["0:4"]=catalog.rows["0:1"].duplicate(true)
	catalog.rows["0:4"].native_geometry.path="0:4"
	catalog.rows["0:4"].native_texture.path="0:4.image"
	source.geometry["0:4"]={"bytes":20*1024*1024};source.textures["0:4.image"]={"charge":0}
	for index in ranges.size():
		var box := AABB(Vector3(ranges[index].x,0,-60),Vector3(ranges[index].y-ranges[index].x,0,120))
		catalog.roots[index].boxes=[box,AABB(),AABB()];catalog.roots[index]["coverage_box"]=box
	catalog.bounds=Rect2(-600,-1000,1200,2000);source.bounds=catalog.bounds
	var old := Contract.select(catalog,Vector2.ZERO,1.0,0.0,Vector2(100,70),false,BUDGET,source.context)
	var next := Contract.select(catalog,Vector2(375,0),1.0,0.0,Vector2(100,70),false,BUDGET,source.context)
	next["selection_stage"]="handoff";next["handoff_bridge"]=true;next["motion_checkpoint"]=true
	var display := request_fixture(Vector2.ZERO,1.0)
	var request := request_fixture(Vector2(500,0),1.0)
	request.committed_catalog=0;request.committed=old;request.target_catalog=0;request.target=next
	request["camera_demand"]=true;request["display_canvas"]=display.canvas
	request["display_size"]=display.size;request["display_scale"]=display.scale
	var planner := Planner.new()
	if not planner.configure(source): return 1
	var before := var_to_bytes(request)
	var result := planner.plan(request)
	var failures := int(result.status!="candidate" or result.cut.get("keys")!=next.keys or not result.force_replan \
		or not planner._pending_motion_path(request) or before!=var_to_bytes(request))
	# 最新终点和半步都不覆盖，仅3/4步可交接；反向、未标记、超池仍拒绝。
	failures+=int(Handoff.covers_motion_view(catalog,next,Vector2(500,0),1.0,0.0,request.size) \
		or Handoff.covers_motion_view(catalog,next,Vector2(250,0),1.0,0.0,request.size))
	request.canvas=request_fixture(Vector2(-500,0),1.0).canvas
	failures+=int(planner._pending_motion_path(request))
	request.canvas=request_fixture(Vector2(500,0),1.0).canvas;next.motion_checkpoint=false
	failures+=int(planner._pending_motion_path(request))
	next.motion_checkpoint=true;request.stream.residency_limit=1;planner._stream=request.stream
	failures+=int(planner._pending_motion_path(request))
	request.stream.residency_limit=BUDGET;planner._flags.display_compaction=false
	failures+=int(planner._pending_motion_path(request))
	print("[Tokyo pending motion path] fail=",failures)
	return failures


static func camera_wait_metric_checks() -> int:
	var audit := preload("res://scripts/tests/tokyo_entry_burst_audit.gd")
	# 同一次等待跨过升级暂停：只扣明确关闭输入的时间，恢复后的最后放行帧仍计入。
	var samples: Array=[
		{"input_ms":0,"camera_wait_started":1000,"camera_wait_elapsed_ms":0},
		{"input_ms":100,"camera_wait_started":1000,"camera_wait_elapsed_ms":100},
		{"input_ms":100,"camera_wait_started":1000,"camera_wait_elapsed_ms":1400},
		{"input_ms":200,"camera_wait_started":-1,"camera_wait_elapsed_ms":0}]
	var failures := int(audit.camera_wait_metrics(samples).max_input_wait_ms!=200)
	# 真正的600ms操控等待必须报出；已经结束的两次等待不能拼接，也不能漏掉末帧。
	samples.append_array([
		{"input_ms":300,"camera_wait_started":2000,"camera_wait_elapsed_ms":20},
		{"input_ms":880,"camera_wait_started":-1,"camera_wait_elapsed_ms":0},
		{"input_ms":900,"camera_wait_started":3000,"camera_wait_elapsed_ms":10},
		{"input_ms":1000,"camera_wait_started":-1,"camera_wait_elapsed_ms":0}])
	failures+=int(audit.camera_wait_metrics(samples).max_input_wait_ms!=600)
	print("[Tokyo camera wait clock] fail=",failures)
	return failures


static func summary_foundation_checks() -> int:
	var data := preload("res://scripts/tests/test_tokyo_hlod_manifest.gd").fixture()
	data.max_scale=0.4
	data["far_summary_recipe"]={"path":"res://fixture/far.json","sha256":"a".repeat(64)}
	var coarse := Contract.normalize(data)
	coarse["range"]=[0.0972,0.4]
	var wider_data := data.duplicate(true)
	wider_data.max_scale=0.8
	var wider := Contract.normalize(wider_data)
	var wider_plan := preload("res://scripts/rendering/tokyo_hlod_foundation.gd").plan([wider])
	if wider_plan.is_empty() or preload("res://scripts/rendering/tokyo_hlod_foundation.gd").catalog_at(wider_plan,0.8)!=0 \
		or preload("res://scripts/rendering/tokyo_hlod_foundation.gd").catalog_at(wider_plan,0.800001)!=-1: return 1
	var motion_data := wider_data.duplicate(true)
	motion_data.max_scale=10.0
	motion_data["resident_motion_summary"]={"schema":1,"preferred_max_scale":0.8,"formal_unchanged":true}
	var motion_catalog := Contract.normalize(motion_data)
	var foundation_script := preload("res://scripts/rendering/tokyo_hlod_foundation.gd")
	var motion_plan := foundation_script.plan([motion_catalog])
	# 扩展的运动质量只作即时接管，常规规划仍在0.8以上请求细档。
	if motion_plan.is_empty() or foundation_script.catalog_at(motion_plan,8.0)!=-1 \
		or foundation_script.catalog_at(motion_plan,8.0,-1,true)!=0 \
		or foundation_script.catalog_at(motion_plan,10.01,-1,true)!=-1: return 1
	data.erase("far_summary_recipe");data.max_scale=0.625
	var fine := Contract.normalize(data)
	fine["range"]=[0.4,0.625]
	var catalogs: Array[Dictionary]=[coarse,fine]
	var source := source_fixture()
	source.catalogs=catalogs;source.prepared_catalogs={}
	source.geometry=coarse.geometry;source.textures=coarse.textures
	source.foundation=preload("res://scripts/rendering/tokyo_hlod_foundation.gd").plan(catalogs)
	var planner := Planner.new()
	if not planner.configure(source): return 1
	var failures := 0
	for scale: float in [0.2,0.3,0.4,0.400001]:
		var result := planner.plan(request_fixture(Vector2.ZERO,scale))
		failures+=int(result.status!="candidate" or result.catalog!=(0 if scale<=0.4 else 1))
		if scale<=0.4: failures+=int(not result.cut.get("foundation",false))
	# 未显式常驻时仍沿原提前档规则，普通地图选择不变。
	planner._pan_velocity=Vector2(100,0);planner._zoom_rate=0.0
	failures+=int(not planner._predict_prefetch(Vector2.ZERO,0.3,0,Vector2(100,70)).is_empty())
	# 接近粗档上限仍需准备真实细档，不能省略必经交接。
	planner._zoom_rate=1.0
	failures+=int(planner._predict_prefetch(Vector2.ZERO,0.39,0,Vector2(100,70)).is_empty())
	# 已常驻的概括根页在显示上限内可全图保持绑定，远距回中不应等待局部选页。
	source.flags["guard_prefetch"]=true
	if not planner.configure(source): return failures+1
	var whole := planner.plan(request_fixture(Vector2(-12000,-12000),0.2))
	var crossed := planner.plan(request_fixture(Vector2(12000,12000),0.2))
	failures+=int(whole.catalog!=0 or whole.cut.keys.size()!=16 or whole.cut.keys!=crossed.cut.keys \
		or not whole.cut.within_budget or whole.cut.bytes>BUDGET or whole.cut.triangles>240000)
	failures+=int(whole.cut.get("prefetch_catalog",-1)!=1 or whole.cut.get("prefetch_keys",PackedStringArray()).is_empty())
	# 实际出口为0.4004时，不能用20ms位置搭配347ms后的尺度。
	var capture := ForecastCapture.new()
	planner._prediction_planner=capture
	planner._prediction_request=request_fixture(Vector2.ZERO,0.2)
	planner._pan_velocity=Vector2(6000,0);planner._zoom_rate=2.0
	planner._predict_prefetch(Vector2.ZERO,0.2,0,Vector2(100,70),0.02)
	var exit_time := log(0.4004/0.2)/2.0
	var predicted_center: Vector2=capture.request.canvas.affine_inverse()*(Vector2(100,70)*0.5)
	failures+=int(not is_equal_approx(float(capture.request.scale),0.4004) or predicted_center.distance_to(Vector2(6000*exit_time,0))>0.01)
	# 持续WASD同时放大：0.2→0.4004时世界速度约减半，实际出口不能用匀速外推。
	planner._prediction_request["return_hint"]={"following":false,"screen_pan":true}
	planner._predict_prefetch(Vector2.ZERO,0.2,0,Vector2(100,70),0.02)
	predicted_center=capture.request.canvas.affine_inverse()*(Vector2(100,70)*0.5)
	failures+=int(predicted_center.distance_to(Vector2(6000*(1.0-0.2/0.4004)/2.0,0))>0.01 \
		or Vector2(capture.request.pan_velocity).distance_to(Vector2(6000*0.2/0.4004,0))>0.01)
	# 返回预测也沿相同出口时刻的原跟随曲线，不能重新变成线性超前。
	planner._prediction_request["return_hint"]={"position":Vector2(-1000,0),"rate":7.0,"following":true}
	planner._predict_prefetch(Vector2.ZERO,0.2,0,Vector2(100,70),0.02)
	predicted_center=capture.request.canvas.affine_inverse()*(Vector2(100,70)*0.5)
	failures+=int(predicted_center.distance_to(Vector2(-1000,0)*(1.0-exp(-7.0*exit_time)))>0.01)
	failures+=int(Vector2(capture.request.pan_velocity).distance_to((Vector2(-1000,0)-predicted_center)*7.0)>0.01)
	# 与正式逐帧lerp独立积分对照：运动目标、20个等长步骤，不得仍按静止点指数估计。
	var follow_start := Vector2(2000,-1000)
	var target_start := Vector2(-1000,500)
	var target_velocity := Vector2(120,80)
	var discrete := follow_start
	for index in 20:
		discrete=discrete.lerp(target_start+target_velocity*((index+1)*0.01),0.07)
	planner._zoom_rate=0.0
	planner._prediction_request["return_hint"]={"position":target_start,"rate":7.0,"following":true,
		"target_velocity":target_velocity,"step_seconds":0.01}
	planner._predict_prefetch(follow_start,1.0,0,Vector2(100,70),0.2)
	predicted_center=capture.request.canvas.affine_inverse()*(Vector2(100,70)*0.5)
	failures+=int(predicted_center.distance_to(discrete)>0.02)
	# 同一逻辑视野的2倍输出：已在8.0尺度的近景预取不得倒退为5.0。
	planner._predict_prefetch(follow_start,8.0,0,Vector2(200,140),0.2)
	failures+=int(not is_equal_approx(float(capture.request.scale),8.0))
	predicted_center=capture.request.canvas.affine_inverse()*(Vector2(100,70)*0.5)
	failures+=int(predicted_center.distance_to(discrete)>0.02)
	# 预测与正式 WASD 更新独立对照：输入保持 D，先加速同时放大，再松键缩远。
	planner._prediction_request["return_hint"]={"position":target_start,"rate":7.0,"following":true,
		"direct_destination":true,"target_velocity":target_velocity}
	planner._predict_prefetch(follow_start,5.0,0,Vector2(100,70),0.0)
	predicted_center=capture.request.canvas.affine_inverse()*(Vector2(100,70)*0.5)
	failures+=int(predicted_center.distance_to(target_start)>0.02)
	planner._predict_prefetch(follow_start,5.0,0,Vector2(100,70),0.25)
	predicted_center=capture.request.canvas.affine_inverse()*(Vector2(100,70)*0.5)
	failures+=int(predicted_center.distance_to(target_start+target_velocity*0.25)>0.02)
	planner._prediction_request.erase("return_hint")
	planner._prediction_request["return_hint"]={"direct_return":true}
	planner._zoom_rate=2.0
	planner._predict_prefetch(Vector2.ZERO,0.6,0,Vector2(100,70),0.5)
	failures+=int(not is_equal_approx(float(capture.request.scale),0.6*exp(1.0)))
	planner._zoom_rate=0.0
	planner._prediction_request.erase("return_hint")
	var controller := CameraController.new()
	var camera := Camera2D.new()
	controller.camera=camera
	controller._wasd_velocity=Vector2(300,0);controller._wasd_hold_time=0.1
	camera.zoom=Vector2.ONE*0.3
	for pressed: bool in [true,false]:
		var event := InputEventKey.new();event.physical_keycode=KEY_D;event.keycode=KEY_D;event.pressed=pressed
		Input.parse_input_event(event)
		Input.flush_buffered_events()
		failures+=int(Input.is_key_pressed(KEY_D)!=pressed)
		var old_zoom := camera.zoom.x
		var destination := old_zoom*(2.0 if pressed else 0.5)
		var pan_hint := {"pan_velocity":controller._wasd_velocity,"pan_direction":Vector2.RIGHT if pressed else Vector2.ZERO,
			"pan_hold":controller._wasd_hold_time,"pan_zoom":old_zoom,"step_seconds":0.01}
		var forecast := planner._predict_screen_pan(camera.position,old_zoom*2.0,destination*2.0,0.2,pan_hint)
		for index in 20:
			camera.zoom=Vector2.ONE*old_zoom*exp(log(destination/old_zoom)*(index+1)/20.0)
			controller._update_wasd(0.01)
		var incorrect := camera.position.distance_to(forecast.center)>0.02 \
			or (controller._wasd_velocity/camera.zoom.x).distance_to(forecast.velocity)>0.02
		if incorrect: print("[Tokyo WASD forecast] pressed=",pressed," actual=",camera.position," predicted=",forecast," velocity=",controller._wasd_velocity/camera.zoom.x)
		failures+=int(incorrect)
	camera.free()
	controller.free()
	# HLOD细档缩向常驻粗档也须经过边界；终点已就绪不能跳过最后一个细档视野。
	planner._zoom_rate=-2.0
	capture.request={}
	planner._predict_prefetch(Vector2.ZERO,0.5,0,Vector2(100,70),0.25)
	failures+=int(not is_equal_approx(float(capture.request.get("scale",-1.0)),0.4004))
	# 原生→普通HLOD同样要保留上侧视野，不能仅覆盖已常驻的终点目录。
	capture.request={}
	planner._predict_prefetch(Vector2.ZERO,0.7,0,Vector2(100,70),0.25)
	failures+=int(not is_equal_approx(float(capture.request.get("scale",-1.0)),0.625625))
	# 开关关闭后仍为局部选择；全图绑定不得溢出费用、页数和清晰度门。
	var foundation := preload("res://scripts/rendering/tokyo_hlod_foundation.gd")
	var entries: Array[Dictionary]=source.foundation.layers[0].entries
	failures+=int(not foundation.select(coarse,entries,Vector2.ZERO,0.2,0,Vector2(100,70),int(whole.cut.bytes)-1,planner._selection_work).is_empty())
	failures+=int(not foundation.select(coarse,entries,Vector2.ZERO,0.400001,0,Vector2(100,70),BUDGET,planner._selection_work).is_empty())
	source.flags.guard_prefetch=false
	source.foundation={}
	if not planner.configure(source): return failures+1
	failures+=int(planner.plan(request_fixture(Vector2.ZERO,0.3)).catalog!=1)
	print("[Tokyo summary foundation] fail=",failures)
	return failures


static func path_prefetch_checks() -> int:
	var source := native_motion_source(1.0,1000,1)
	for index in 4:
		var row: Dictionary=source.native.configurations.lod5_full[index]
		row.bytes=1024*1024;row.triangles=[1000,0,0]
		row.boxes[0]=AABB(Vector3([-230.0,0.0,68.0,260.0][index]-2,0,-5),Vector3(4,0,10))
		source.geometry[row.path].bytes=row.bytes
	var planner := Planner.new()
	if not planner.configure(source): return 1
	planner._stream=request_fixture(Vector2.ZERO,1.0).stream
	planner._pan_velocity=Vector2(100,0)
	var endpoint := planner._predict_prefetch(Vector2.ZERO,1.0,0,Vector2(100,70))
	var failures := int(endpoint.get("keys",PackedStringArray()).has("old"))
	# 远端切面不需要身后的页，但路径近端仍需它；缓存终点不能代表路径已准备。
	planner._flags["guard_prefetch"]=true
	var path := planner._predict_path_prefetch(Vector2.ZERO,1.0,0,Vector2(100,70))
	var requests := Handoff.prefetch_requests(planner._catalogs,{"prefetch_catalog":path.catalog,"prefetch_keys":path.keys,"prefetch_extra":path.extra},path.catalog)
	failures+=int(not path.keys.has("old") or {"mesh":"far","image":""} not in requests or not Worker.pure(path))
	planner._flags.guard_prefetch=false
	failures+=int(planner._predict_path_prefetch(Vector2.ZERO,1.0,0,Vector2(100,70))!=endpoint)
	# 高速回中：一屏截断会让四个未来机位重合，完全漏掉120/360/1500处。
	for index in 4:
		source.native.configurations.lod5_full[index].boxes[0].position.x=[0.0,120.0,360.0,1500.0][index]-2.0
	if not planner.configure(source): return failures+1
	planner._stream=request_fixture(Vector2.ZERO,4.0).stream
	planner._pan_velocity=Vector2(6000,0)
	var clipped := planner._predict_prefetch(Vector2.ZERO,4.0,0,Vector2(100,70))
	failures+=int(clipped.keys.has("far"))
	planner._flags["guard_prefetch"]=true
	var fast := planner._predict_path_prefetch(Vector2.ZERO,4.0,0,Vector2(100,70))
	var fast_requests := Handoff.prefetch_requests(planner._catalogs,{"prefetch_catalog":fast.catalog,"prefetch_keys":fast.keys,"prefetch_extra":fast.extra},fast.catalog)
	for key: String in ["inside","ahead","far"]:
		failures+=int({"mesh":key,"image":""} not in fast_requests)
	# WASD缩远时，近时刻经过的页可能不再与较远预测视野相交，不能只留下0.1秒以后的切面。
	planner._flags["return_cache"]=true;planner._zoom_rate=-0.1
	planner._prediction_request=request_fixture(Vector2.ZERO,4.0)
	planner._prediction_request["return_hint"]={"following":false,"screen_pan":true,"position":Vector2.ZERO}
	var expanding := planner._predict_path_prefetch(Vector2.ZERO,4.0,0,Vector2(100,70))
	var expanding_requests := Handoff.prefetch_requests(planner._catalogs,{"prefetch_catalog":expanding.catalog,"prefetch_keys":expanding.keys,"prefetch_extra":expanding.extra},expanding.catalog)
	failures+=int({"mesh":"inside","image":""} not in expanding_requests or not Worker.pure(expanding))
	planner._zoom_rate=0.0;planner._prediction_request={};planner._flags.erase("return_cache")
	# 尚在向右自由移动时，准备按空格突然向左的起步；不能等按键后才开始读。
	source.native.configurations.lod5_full[0].boxes[0].position.x=-140.0
	if not planner.configure(source): return failures+1
	planner._prediction_planner=null # 本夹具直接隔离纯值路径选页，完整算法一致性见下方guarded用例。
	planner._flags["guard_prefetch"]=true
	planner._stream=request_fixture(Vector2.ZERO,4.0).stream
	planner._pan_velocity=Vector2(6000,0)
	planner._prediction_request=request_fixture(Vector2.ZERO,4.0)
	planner._prediction_request["return_hint"]={"position":Vector2(-1000,0),"rate":7.0,"following":false}
	var saved_prediction := var_to_bytes(planner._prediction_request)
	var returning := planner._predict_path_prefetch(Vector2.ZERO,4.0,0,Vector2(100,70))
	var return_requests := Handoff.prefetch_requests(planner._catalogs,{"prefetch_catalog":returning.catalog,"prefetch_keys":returning.keys,"prefetch_extra":returning.extra},returning.catalog)
	failures+=int({"mesh":"old","image":""} not in return_requests or returning.prepared_cuts.size()>8 \
		or var_to_bytes(planner._prediction_request)!=saved_prediction or planner._pan_velocity!=Vector2(6000,0))
	# 四分之一秒路径不包含一秒后的目的地；候选必须额外准备目的地且保持输入纯值不变。
	source.native.configurations.lod5_full[3].boxes[0].position.x=-1002.0
	# 20ms时刻已经越过起步后缘；新增的5ms切面必须包含它，不能以终点已ready代替。
	var initial: Dictionary=source.native.configurations.lod5_full[0].duplicate(true)
	initial.path="initial";initial.boxes[0].position.x=-37.0
	source.native.configurations.lod5_full.append(initial)
	source.geometry["initial"]={"bytes":initial.bytes};source.native.pages["initial"]={"components":{"initial":true}}
	if not planner.configure(source): return failures+1
	planner._prediction_planner=null;planner._flags["guard_prefetch"]=true;planner._flags["return_cache"]=true
	planner._stream=request_fixture(Vector2.ZERO,4.0).stream;planner._pan_velocity=Vector2(6000,0)
	planner._prediction_request=request_fixture(Vector2.ZERO,4.0)
	planner._prediction_request["return_hint"]={"position":Vector2(-1000,0),"rate":7.0,"following":false}
	saved_prediction=var_to_bytes(planner._prediction_request)
	returning=planner._predict_path_prefetch(Vector2.ZERO,4.0,0,Vector2(100,70))
	return_requests=Handoff.prefetch_requests(planner._catalogs,{"prefetch_catalog":returning.catalog,"prefetch_keys":returning.keys,"prefetch_extra":returning.extra},returning.catalog)
	failures+=int({"mesh":"far","image":""} not in return_requests or {"mesh":"initial","image":""} not in return_requests or returning.prepared_cuts.size()>16 \
		or var_to_bytes(planner._prediction_request)!=saved_prediction or planner._pan_velocity!=Vector2(6000,0))
	# 按完整回程距离采样，代表性远距的相邻视野必须重叠；无效输入不得生成预测。
	var horizons := Handoff.return_horizons(9000.0,Vector2(1920,1080),7.0,1.0/120.0)
	failures+=int(horizons.size()>11 or not horizons.has(1.0) or not horizons.has(0.005))
	horizons.sort()
	var previous_distance := 0.0
	for horizon: float in horizons:
		var advanced := 9000.0*(1.0-pow(1.0-7.0/120.0,horizon*120.0))
		failures+=int(advanced-previous_distance>1080.0)
		previous_distance=advanced
	failures+=int(not Handoff.return_horizons(INF,Vector2(1920,1080),7.0,0.0).is_empty() \
		or not Handoff.return_horizons(9000.0,Vector2.ZERO,7.0,0.0).is_empty())
	# 提前细档只有裸视野时，正式规则会选择带保护的实际档；预测必须准备同一套资源。
	var guarded_source := motion_guard_source(50)
	guarded_source.flags["guard_prefetch"]=true
	var guarded_original := var_to_bytes(guarded_source)
	var guarded := Planner.new()
	if not guarded.configure(guarded_source): return failures+1
	var moving := request_fixture(Vector2.ZERO,1.2)
	moving.pan_velocity=Vector2(400,0)
	var moving_original := var_to_bytes(moving)
	var guarded_plan := guarded.plan(moving)
	var prepared: Array=guarded_plan.get("prepared_cuts",[])
	failures+=int(prepared.is_empty() or prepared.size()>4)
	for proposal: Dictionary in prepared:
		failures+=int(not proposal.cut.get("within_budget",false) or proposal.cut.get("keys",[]).is_empty())
	failures+=int(guarded_plan.catalog!=0 or guarded_plan.cut.get("prefetch_catalog",-1)!=0 \
		or guarded._prediction_planner==null or guarded._prediction_planner._prediction_planner!=null \
		or var_to_bytes(moving)!=moving_original or var_to_bytes(guarded_source)!=guarded_original)
	guarded_source=guarded_source.duplicate(true);guarded_source.flags["return_cache"]=true
	if not guarded.configure(guarded_source): return failures+1
	guarded_original=var_to_bytes(guarded_source)
	var coherent := guarded.plan(moving)
	failures+=int(coherent.catalog!=guarded_plan.catalog or not Worker.pure(coherent))
	for proposal: Dictionary in coherent.get("prepared_cuts",[]):
		failures+=int(not Handoff.qualified(guarded._catalogs[proposal.catalog],proposal.cut,moving.scale) or not proposal.cut.within_budget)
	failures+=int(var_to_bytes(moving)!=moving_original or var_to_bytes(guarded_source)!=guarded_original)
	print("[Tokyo path prefetch] fail=",failures)
	return failures


static func active_summary_checks() -> int:
	var foundation := preload("res://scripts/rendering/tokyo_hlod_foundation.gd")
	var data := preload("res://scripts/tests/test_tokyo_hlod_manifest.gd").fixture()
	data.max_scale=10.0
	data["far_summary_recipe"]={"path":"res://fixture/active.json","sha256":"a".repeat(64)}
	data["resident_motion_summary"]={"schema":1,"preferred_max_scale":0.8,"formal_unchanged":true}
	var coarse := Contract.normalize(data)
	coarse["range"]=[0.1666666,0.8]
	data.erase("far_summary_recipe");data.erase("resident_motion_summary")
	var fine := Contract.normalize(data)
	fine["range"]=[0.8,10.0]
	var source := source_fixture()
	source.catalogs=[coarse,fine];source.prepared_catalogs={}
	source.geometry=coarse.geometry;source.textures=coarse.textures
	source.foundation=foundation.plan([coarse,fine]);source.flags={"guard_prefetch":true}
	var failures := 0
	for scenario: String in ["fast","stopped","following","missing","budget","union","disabled","prediction"]:
		var input_source := source.duplicate(true)
		if scenario=="disabled": input_source.flags.guard_prefetch=false
		if scenario=="prediction": input_source.flags.prediction_only=true
		if scenario=="budget": input_source.context.display_limit=1
		var planner := Planner.new()
		if not planner.configure(input_source): return failures+1
		var request := request_fixture(Vector2.ZERO,8.0)
		request.pan_velocity=Vector2(1000,0) if scenario!="stopped" else Vector2.ZERO
		for path: String in source.geometry:
			for part: String in source.geometry[path].get("components",{path:{}}): request.stream._cache[part]=true
		for path: String in source.textures: request.stream._textures[path]=true
		if scenario=="following": request["return_hint"]={"following":true,"target_velocity":request.pan_velocity,"position":Vector2.ZERO,"rate":7.0}
		if scenario=="missing": request.stream._cache.clear()
		if scenario=="union": request.stream.residency_limit=1
		var original := var_to_bytes(request)
		var result := planner.plan(request)
		failures+=int(bool(result.cut.get("motion_summary",false))!=(scenario=="fast") or var_to_bytes(request)!=original or not Worker.pure(result))
		if scenario=="fast": failures+=int(result.catalog!=0 or result.cut.keys.size()!=16 or not result.cut.within_budget or not result.force_replan)
		if scenario in ["stopped","following"]: failures+=int(result.catalog!=1)
	failures+=int(foundation.motion_active(Vector2(100,0),0.0,8.0,Vector2(100,70),Vector2(200,140)))
	failures+=int(not foundation.motion_active(Vector2.ZERO,0.2,1.0,Vector2(100,70),Vector2(100,70)))
	print("[Tokyo active summary] fail=",failures)
	return failures


static func shared_selection_source_checks() -> int:
	var source := native_motion_source(1.0,1000,30)
	source.flags={"guard_prefetch":true,"return_cache":true,"share_selection_source":true}
	var before := var_to_bytes(source)
	var candidate := Planner.new()
	if not candidate.configure(source): return 1
	var control_source := source.duplicate(true)
	control_source.flags.share_selection_source=false
	var control := Planner.new()
	if not control.configure(control_source): return 1
	var failures := 0
	var shared: RefCounted=candidate._prediction_planner._native
	failures+=int(shared==candidate._native or not is_same(shared.pages,candidate._native.pages))
	failures+=int(is_same(shared.selection_context,candidate._native.selection_context))
	for center: Vector2 in [Vector2.ZERO,Vector2(50,0),Vector2(500,0)]:
		for angle: float in [0.0,0.4]:
			var request := request_fixture(center,1.0)
			request.canvas=Transform2D(angle,Vector2.ZERO).scaled(Vector2.ONE)
			request.canvas.origin=request.logical*0.5-request.canvas*center
			var actual := candidate.plan(request)
			var expected := control.plan(request)
			failures+=int(actual.get("status")!=expected.get("status") or actual.get("catalog")!=expected.get("catalog"))
			failures+=int(comparable_cut(actual.get("cut",{}))!=comparable_cut(expected.get("cut",{})))
			failures+=int(actual.get("extra_requests")!=expected.get("extra_requests") or not Worker.pure(actual))
	failures+=int(var_to_bytes(source)!=before)
	# 后续重新配置任一选择器不能清空另一个仍使用的共享表。
	var retained := var_to_bytes(candidate._native.selection_snapshot())
	failures+=int(not shared.configure_selection_snapshot(source.native,source.context))
	failures+=int(var_to_bytes(candidate._native.selection_snapshot())!=retained)
	print("[Tokyo shared selection source] fail=",failures)
	return failures


static func lod_display_checks() -> int:
	var catalogs: Array[Dictionary]=[{"range":[0.183,0.24]},{"range":[0.24,0.625]},{"range":[0.625,1.25]}]
	var failures := 0
	# 预取仍提前准备细档，但真实显示不能在静止0.20处被预取抬档、再被运动降回。
	for scale: float in [0.199,0.2,0.201,0.23,0.2399]:
		failures+=int(Handoff.catalog_index(catalogs,scale,true)!=1)
		failures+=int(Handoff.display_catalog_index(catalogs,scale,0)!=0)
	failures+=int(Handoff.display_catalog_index(catalogs,0.241,0)!=1)
	failures+=int(Handoff.display_catalog_index(catalogs,0.235,1)!=1)
	failures+=int(Handoff.display_catalog_index(catalogs,0.22,1)!=0)
	failures+=int(Handoff.display_catalog_index(catalogs,1.251,2)!=-1)
	failures+=int(Handoff.display_target_allowed(catalogs,0.2,0,1))
	failures+=int(not Handoff.display_target_allowed(catalogs,0.241,0,1))
	failures+=int(not Handoff.display_target_allowed(catalogs,0.235,1,1))
	failures+=int(Handoff.display_target_allowed(catalogs,0.22,1,1))
	failures+=int(not Handoff.display_target_allowed(catalogs,1.2,2,-2))
	failures+=int(Handoff.display_target_allowed(catalogs,0.2,0,-1))
	failures+=int(not is_equal_approx(Handoff.preload_entry_scale(catalogs,0.2,0.0),0.24024))
	failures+=int(not is_equal_approx(Handoff.preload_entry_scale(catalogs,0.5,1.0),0.625625))
	failures+=int(Handoff.preload_entry_scale(catalogs,0.2,-1.0)!=0.0)
	failures+=int(Handoff.preload_entry_scale(catalogs,0.3,0.0)!=0.0)
	failures+=int(Handoff.preload_entry_scale(catalogs,NAN,0.0)!=0.0)
	failures+=int(not is_equal_approx(Handoff.prediction_checkpoint(catalogs,0.5,1.4,2.0),0.625625))
	failures+=int(not is_equal_approx(Handoff.prediction_checkpoint(catalogs,2.0,0.2,-2.0),1.25125))
	failures+=int(not is_equal_approx(Handoff.prediction_checkpoint(catalogs,1.25125,0.2,-2.0,-2),1.24875))
	failures+=int(not is_equal_approx(Handoff.prediction_checkpoint(catalogs,1.2501,0.2,-2.0,-2),1.24875))
	failures+=int(not is_equal_approx(Handoff.prediction_checkpoint(catalogs,0.5,0.2,-2.0),0.2205792))
	failures+=int(not is_equal_approx(Handoff.prediction_checkpoint(catalogs,0.6,0.3,-2.0,2),0.574425))
	failures+=int(not is_equal_approx(Handoff.prediction_checkpoint(catalogs,0.5,0.55,2.0),0.55))
	var forecast_planner := Planner.new()
	var forecast_source := source_fixture()
	forecast_source.catalogs=catalogs
	forecast_source.flags={"lod_transition":true,"guard_prefetch":true,"prediction_only":true}
	failures+=int(not forecast_planner.configure(forecast_source))
	var capture := ForecastCapture.new()
	forecast_planner._prediction_planner=capture
	forecast_planner._prediction_request=request_fixture(Vector2.ZERO,0.5)
	forecast_planner._logical=Vector2(100,70)
	forecast_planner._pan_velocity=Vector2(100,0);forecast_planner._zoom_rate=2.0
	forecast_planner._predict_prefetch(Vector2.ZERO,0.5,0.0,Vector2(100,70),0.25,{},true)
	var forecast_center: Vector2=capture.request.canvas.affine_inverse()*(Vector2(100,70)*0.5)
	failures+=int(not is_equal_approx(float(capture.request.scale),0.625625) or forecast_center.length()>0.01)
	forecast_planner._zoom_rate=0.0
	forecast_planner._predict_prefetch(Vector2.ZERO,0.5,0.0,Vector2(100,70),0.25,{},true)
	forecast_center=capture.request.canvas.affine_inverse()*(Vector2(100,70)*0.5)
	failures+=int(not is_equal_approx(float(capture.request.scale),0.625625) or forecast_center.length()>0.01)
	forecast_planner._zoom_rate=2.0
	forecast_planner._predict_prefetch(Vector2.ZERO,0.5,0.0,Vector2(100,70),0.25)
	forecast_center=capture.request.canvas.affine_inverse()*(Vector2(100,70)*0.5)
	failures+=int(forecast_center.distance_to(Vector2(100*log(0.625625/0.5)/2.0,0))>0.01)
	forecast_planner._flags["display_compaction"]=true
	forecast_planner._prediction_floor=0.2;forecast_planner._zoom_rate=-2.0
	# 快速缩远的首点准备滞回入口，第二点继续到可达终点；不能全挤在入口前。
	forecast_planner._predict_prefetch(Vector2.ZERO,0.25,0.0,Vector2(100,70),0.25)
	failures+=int(not is_equal_approx(float(capture.request.scale),0.2205792))
	forecast_planner._predict_prefetch(Vector2.ZERO,0.25,0.0,Vector2(100,70),0.25,{"forecast_scale":0.2205792,"catalog":0})
	failures+=int(not is_equal_approx(float(capture.request.scale),0.2))
	forecast_planner._zoom_rate=2.0
	forecast_planner._predict_prefetch(Vector2.ZERO,0.5,0.0,Vector2(100,70),0.25,{"forecast_scale":0.625625,"catalog":2})
	failures+=int(not is_equal_approx(float(capture.request.scale),0.5*exp(0.5)))
	forecast_planner._zoom_rate=-2.0
	# 近景向外越界必须同时准备边界两侧；只备中景会在最后一段原生视野限制移动。
	forecast_planner._predict_prefetch(Vector2.ZERO,2.0,0.0,Vector2(100,70),0.25)
	failures+=int(not is_equal_approx(float(capture.request.scale),1.25125))
	forecast_planner._predict_prefetch(Vector2.ZERO,2.0,0.0,Vector2(100,70),0.25,{"forecast_scale":1.25125,"catalog":-2})
	failures+=int(not is_equal_approx(float(capture.request.scale),1.24875))
	forecast_planner._predict_prefetch(Vector2.ZERO,2.0,0.0,Vector2(100,70),0.25,{"forecast_scale":1.24875,"catalog":2})
	failures+=int(not is_equal_approx(float(capture.request.scale),2.0*exp(-0.5)))
	# 相邻原生预测继承尚在准备的完整切面；不能把它伪造成已提交或已加载。
	var native_source := native_motion_source(1.0,1000,1)
	var native_probe := Planner.new()
	failures+=int(not native_probe.configure(native_source))
	var native_cut: Dictionary=native_probe._native.select(Vector2.ZERO,2.0,0.0,Vector2(100,70),"lod5_full",BUDGET)
	var saved_request := var_to_bytes(forecast_planner._prediction_request)
	forecast_planner._flags["return_cache"]=true
	forecast_planner._zoom_rate=0.0
	forecast_planner._predict_prefetch(Vector2.ZERO,2.0,0.0,Vector2(100,70),0.25,{"catalog":-2,"prepared_cut":native_cut})
	failures+=int(capture.request.target_catalog!=-2 or capture.request.target!=native_cut)
	failures+=int(capture.request.committed!=forecast_planner._prediction_request.committed \
		or capture.request.stream!=forecast_planner._prediction_request.stream or var_to_bytes(forecast_planner._prediction_request)!=saved_request)
	forecast_planner._flags.erase("return_cache")
	forecast_planner._zoom_rate=-2.0
	var exit_growth := 0.25/(0.24*0.92)-1.0
	failures+=int(forecast_planner._hlod_zoom_padding(catalogs[1],0.25,Vector2(100,70)).distance_to(Vector2(100,70)*exit_growth)>0.001)
	failures+=int(forecast_planner._hlod_zoom_padding(catalogs[0],0.205,Vector2(100,70)).distance_to(Vector2(2.5,1.75))>0.001)
	# 同一后台规划器的显示与预测请求必须分开：稳定显示不能压住下一档预取。
	var source := source_fixture()
	source.catalogs[0].range=[0.05,0.075]
	var finer: Dictionary=source.catalogs[0].duplicate(true)
	finer.range=[0.075,0.1]
	finer.identity.path=String(finer.identity.path)+"_finer"
	source.catalogs.append(finer)
	source.prepared_catalogs={source.catalogs[0].identity.path:Prepared.build(source.catalogs[0]),finer.identity.path:Prepared.build(finer)}
	for predicting: bool in [false,true]:
		source.flags={"lod_transition":true,"prediction_only":predicting}
		var planner := Planner.new()
		failures+=int(not planner.configure(source))
		var request := request_fixture(Vector2.ZERO,0.06)
		request.committed_catalog=0
		var planned := planner.plan(request)
		failures+=int(planned.status!="candidate" or int(planned.catalog)!=(1 if predicting else 0))
		if predicting:
			request["actual_display_prediction"]=true
			planned=planner.plan(request)
			failures+=int(planned.status!="candidate" or planned.catalog!=0)
			request=request_fixture(Vector2.ZERO,0.0751)
			request["actual_display_prediction"]=true
			planned=planner.plan(request)
			failures+=int(planned.status!="candidate" or planned.catalog!=1)
	var old := {"within_budget":true,"keys":PackedStringArray(["a"]),"triangles":120000}
	var next := {"within_budget":true,"keys":PackedStringArray(["b"]),"triangles":120000}
	failures+=int(not Handoff.blend_allowed(old,next,BUDGET,BUDGET))
	failures+=int(Handoff.blend_allowed(old,next,BUDGET+1,BUDGET))
	next.triangles=120001;failures+=int(Handoff.blend_allowed(old,next,BUDGET,BUDGET))
	next.triangles=-1;failures+=int(Handoff.blend_allowed(old,next,BUDGET,BUDGET))
	next.triangles=10;next.keys.resize(16);failures+=int(Handoff.blend_allowed(old,next,BUDGET,BUDGET))
	# 固定相机按时间完成；快速缩放必须在共同质量区结束前完成，而非突然跳到终点。
	# 高速平移同一倍率：已交接中景不能被旧原生偏好抢回；真正放大仍恢复原生。
	var preference_source := native_motion_source(1.0,1000,1)
	var catalog := Fixture.catalog(false)
	catalog.range=[0.625,1.25];catalog.max_scale=1.25;catalog["prefer_native_above"]=0.9
	preference_source.catalogs=[catalog]
	preference_source.geometry.merge(catalog.geometry)
	preference_source.textures=catalog.textures
	preference_source.native.configurations["lod4_full"]=preference_source.native.configurations.lod5_full
	preference_source.prepared_catalogs={catalog.identity.path:Prepared.build(catalog)}
	preference_source.flags={"lod_transition":true}
	var preference_planner := Planner.new()
	failures+=int(not preference_planner.configure(preference_source))
	var preference_request := request_fixture(Vector2.ZERO,1.19)
	preference_request.committed_catalog=0
	preference_request.committed=Contract.select(catalog,Vector2.ZERO,1.19,0.0,Vector2(100,70),false,BUDGET)
	preference_request.pan_velocity=Vector2(1000,0)
	for rate: float in [0.0,-0.1,2.0]:
		preference_request.zoom_rate=rate;preference_request.zooming_out=rate<0.0
		var preferred := preference_planner.plan(preference_request)
		failures+=int(preferred.status!="candidate" or int(preferred.catalog)!=(-2 if rate>0.02 else 0))
	failures+=int(not is_zero_approx(Handoff.blend_progress(0.0,1.2,1.2,1.25)))
	failures+=int(not is_equal_approx(Handoff.blend_progress(0.045,1.2,1.2,1.25),0.5))
	failures+=int(Handoff.blend_progress(0.01,1.2,1.245,1.25)<0.95)
	failures+=int(Handoff.blend_progress(0.01,1.24,1.155,1.15)<0.95)
	failures+=int(not is_equal_approx(Handoff.blend_progress(0.09,1.2,1.2,0.0),1.0))
	print("[Tokyo LOD display] fail=",failures)
	return failures


static func zoom_target_forecast_checks() -> int:
	var failures := 0
	var planner := Planner.new()
	var controller := CameraController.new()
	var camera := Camera2D.new()
	controller.camera=camera
	# 用正式缩放与真实 WASD 输入逐步前进，验证减速段和 2 倍输出的世界位置。
	for pair: Vector2 in [Vector2(0.24,0.2),Vector2(0.209,0.2),Vector2(4.6,5.0),Vector2(0.625,5.0)]:
		for pressed: bool in [true,false]:
			var event := InputEventKey.new();event.physical_keycode=KEY_D;event.keycode=KEY_D;event.pressed=pressed
			Input.parse_input_event(event);Input.flush_buffered_events()
			camera.position=Vector2.ZERO;camera.zoom=Vector2.ONE*pair.x
			controller._base_zoom=pair.x;controller.target_zoom=pair.y
			controller._wasd_velocity=Vector2(2300,0);controller._wasd_hold_time=1.0
			var hint := {"pan_velocity":controller._wasd_velocity,"pan_direction":Vector2.RIGHT if pressed else Vector2.ZERO,
				"pan_hold":controller._wasd_hold_time,"pan_zoom":pair.x,"step_seconds":0.01,"zoom_target":pair.y}
			var zoom := planner._forecast_zoom(pair.x*2.0,0.5,2.0,hint)
			var forecast := planner._predict_screen_pan(Vector2.ZERO,pair.x*2.0,float(zoom.scale),0.5,hint)
			for index in 50:
				controller.update_zoom(0.01);controller._update_wasd(0.01)
			var wrong := absf(camera.zoom.x*2.0-float(zoom.scale))>0.00001 or camera.position.distance_to(forecast.center)>0.03
			if wrong: print("[Tokyo target forecast] actual=",camera.position," forecast=",forecast," scale=",camera.zoom.x*2.0," predicted=",zoom)
			failures+=int(wrong)
	camera.free();controller.free()
	print("[Tokyo target forecast] fail=",failures)
	return failures


static func run() -> int:
	var compact_failures := compact_request_checks()
	var failures := differential_checks() + native_bridge_checks() + shared_texture_mesh_checks() + resident_reuse_checks() + mixed_cached_hlod_checks() + directional_trim_checks() + waiting_display_trim_checks() + guard_budget_retry_checks() + motion_guard_actual_checks() + native_motion_guard_checks() + native_motion_retention_checks() + native_motion_query_checks() + native_motion_prefetch_checks() + hlod_zoom_boundary_checks() + transition_leaf_index_checks() + approaching_coarse_budget_checks()
	if OS.get_environment("AGL_TOKYO_NATIVE_MOTION_DIAGNOSTIC")=="1": failures+=installed_native_motion_diagnostic()
	failures+=enlarged_motion_pool_checks()
	failures+=pending_compaction_progress_checks()
	failures+=pending_motion_path_checks()
	failures+=camera_wait_metric_checks()
	failures+=summary_foundation_checks()
	failures+=zoom_target_forecast_checks()
	failures+=active_summary_checks()
	failures+=path_prefetch_checks()
	failures+=pending_hlod_motion_checks()
	if OS.get_environment("AGL_TOKYO_C1_COMPACT_DIAGNOSTIC")=="1": failures+=installed_c1_compact_diagnostic()
	if OS.get_environment("AGL_TOKYO_DISPLAY_COMPACT_DIAGNOSTIC")=="1": failures+=installed_display_compact_diagnostic()
	if OS.has_environment("AGL_TOKYO_F5_WAIT_REPLAY"): failures+=installed_f5_wait_diagnostic()
	failures+=compact_failures
	failures+=shared_selection_source_checks()
	failures+=lod_display_checks()
	failures+=lod_reverse_successor_checks()
	print("[Tokyo planner] fail=", failures)
	return failures
