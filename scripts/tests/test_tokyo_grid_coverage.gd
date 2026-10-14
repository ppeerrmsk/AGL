extends RefCounted
const Grid := preload("res://scripts/experiments/tokyo_grid_coverage.gd")


static func checks(real: Dictionary={}) -> int:
	var old := {"schema":1,"verified":true,"configuration":"lod5_full","collision_sha256":"c","catalog_sha256":"a",
		"sources":{17:PackedStringArray(["leaf:0","leaf:1"])},"pages":{
		"leaf":{"identity":{"id":"old"},"leaves":PackedStringArray(["leaf"]),"tokens":[PackedStringArray(["leaf:0"]),PackedStringArray(["leaf:1"])]}}}
	var data := {"schema":1,"configuration":"lod5_full","source_layers_complete":true,"original_coverage":old,
		"pages":{"a":{"identity":{"id":"a"}},"b":{"identity":{"id":"b"}}},
		"dependencies":{"leaf":{0:[{"path":"a","identity":{"id":"a"}},{"path":"b","identity":{"id":"b"}}],
		1:[{"path":"b","identity":{"id":"b"}}]}}}
	var full := {"a":{"identity":{"id":"a"},"layers":1},"b":{"identity":{"id":"b"},"layers":3}}
	var fail := 0
	fail+=refinement_checks()
	fail+=index_checks()
	fail+=mask_checks()
	var compiled := preload("res://scripts/experiments/tokyo_grid_coverage_index.gd").new()
	if not compiled.configure(data) or not compiled.compile_sources(): return fail+1
	for a in 4:
		for b in 4:
			var cut := full.duplicate(true);cut.a.layers=a;cut.b.layers=b
			fail+=int(compiled.covered_sources(cut,{},"lod5_full","c","a")!=Grid.covered_sources(data,cut,"lod5_full","c","a"))
	fail+=int(not compiled.covered_sources(full,{},"lod4_full","c","a").is_empty())
	fail+=int(not compiled.covered_sources(full,{},"lod5_full","wrong","a").is_empty())
	fail+=int(not compiled.covered_sources(full,{},"lod5_full","c","wrong").is_empty())
	if not compiled.configure(data): return fail+1
	fail+=int(not compiled.covered_sources(full,{},"lod5_full","c","a").is_empty()) # 重配后未编译不可沿用旧认证。
	var spatial := data.duplicate(true)
	spatial.pages.a["box"]=AABB(Vector3(0,0,0),Vector3(5,10,5))
	spatial.pages.b["box"]=AABB(Vector3(1000,0,1000),Vector3(5,10,5))
	var projection := {"view":Rect2(-10,-10,100,100),"canvas":Transform2D.IDENTITY,"size":Vector2(100,100),"roof":Vector2.ZERO}
	if Grid.covered_sources(spatial,{"a":full.a},"lod5_full","c","a",projection)!=PackedInt32Array([17]): fail+=1
	if not Grid.covered_sources(spatial,{},"lod5_full","c","a",projection).is_empty(): fail+=1
	# 平移到原屏外页后不能继续沿用旧的豁免；投影进入屏幕亦必须有实际提交。
	projection.view=Rect2(990,990,100,100);projection.canvas=Transform2D(0,Vector2(-990,-990))
	if not Grid.covered_sources(spatial,{"a":full.a},"lod5_full","c","a",projection).is_empty(): fail+=1
	projection.view=Rect2(-10,-10,100,100);projection.canvas=Transform2D.IDENTITY
	projection.roof=Vector2(-100,-100)
	if not Grid.covered_sources(spatial,{"a":full.a},"lod5_full","c","a",projection).is_empty(): fail+=1
	if Grid.covered_sources(data,full,"lod5_full","c","a")!=PackedInt32Array([17]): fail+=1
	if not Grid.covered_sources(data,{},"lod5_full","c","a").is_empty(): fail+=1
	for missing: String in full:
		var partial := full.duplicate(true)
		partial.erase(missing)
		if not Grid.covered_sources(data,partial,"lod5_full","c","a").is_empty(): fail+=1
	for field: String in ["identity","layers"]:
		var altered := full.duplicate(true)
		altered.b[field]={"id":"foreign"} if field=="identity" else 1
		if not Grid.covered_sources(data,altered,"lod5_full","c","a").is_empty(): fail+=1
	var foreign := full.duplicate(true)
	foreign["unknown"]=full.a
	if not Grid.covered_sources(data,foreign,"lod5_full","c","a").is_empty(): fail+=1
	if not Grid.covered_sources(data,full,"lod4_full","c","a").is_empty(): fail+=1
	if not Grid.covered_sources(data,full,"lod5_full","wrong","a").is_empty(): fail+=1
	var empty := data.duplicate(true)
	empty.dependencies.leaf[0]=[]
	if not Grid.covered_sources(empty,full,"lod5_full","c","a").is_empty(): fail+=1
	if not real.is_empty():
		var joined_pages: Array=[]
		var audit: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(real.joined_audit.path))
		if FileAccess.get_sha256(real.joined_audit.path)!=real.joined_audit.sha256: return fail+1
		for row: Dictionary in audit.rows:
			var joined: Variant=preload("res://scripts/tests/build_tokyo_grid_dependencies.gd").read(row.joined)
			if not joined is Dictionary: return fail+1
			joined_pages.append_array(joined.pages)
		var refined := Grid.refinement_data(real,joined_pages)
		if refined.is_empty(): return fail+1
		var committed: Dictionary={}
		var expected: Dictionary={}
		for source: String in real.dependencies:
			var layers := 0
			for kind: int in real.dependencies[source]:
				layers|=1<<kind
				for dependency: Dictionary in real.dependencies[source][kind]:
					if not committed.has(dependency.path): committed[dependency.path]={"identity":dependency.identity,"layers":0}
					committed[dependency.path].layers|=1<<kind
			if real.original_coverage.pages.has(source): expected[source]={"identity":real.original_coverage.pages[source].identity,"layers":layers}
		if Grid.source_layers(real,committed)!=expected: fail+=1
		if Grid.refined_layers(refined,committed)!=expected: fail+=1
		var fine_committed: Dictionary={}
		for group: Dictionary in refined.coarse_to_fine.values():
			for child: Dictionary in group.children: fine_committed[child.path]={"identity":child.identity,"layers":1<<int(child.layer)}
		if Grid.refined_layers(refined,fine_committed)!=expected: fail+=1
		var indexed := preload("res://scripts/experiments/tokyo_grid_coverage_index.gd").new()
		if not indexed.configure(refined): return fail+1
		if not indexed.compile_sources(): return fail+1
		if indexed.refined_layers(committed)!=Grid.refined_layers(refined,committed): fail+=1
		var sparse := fine_committed.duplicate()
		var ordinal := 0
		for path: String in fine_committed:
			ordinal+=1
			if ordinal%3!=0: sparse.erase(path)
		for n in 12:
			var center := Vector2(-14000+n*2400,-15000+(n%4)*8000)
			var pose := {"view":Rect2(center-Vector2(1600,900),Vector2(3200,1800)),"canvas":Transform2D(float(n%3)*0.2,-center+Vector2(1600,900)),"size":Vector2(3200,1800),"roof":Vector2(-0.8+n*0.1,0.5)}
			if indexed.refined_layers(sparse,pose)!=Grid.refined_layers(refined,sparse,pose): fail+=1
			var oracle := preload("res://scripts/experiments/tokyo_source_coverage.gd").covered_sources(refined.original_coverage,Grid.refined_layers(refined,sparse,pose),real.configuration,real.original_coverage.collision_sha256,real.original_coverage.catalog_sha256)
			if indexed.covered_sources(sparse,pose,real.configuration,real.original_coverage.collision_sha256,real.original_coverage.catalog_sha256)!=oracle: fail+=1
		var original: Dictionary=real.original_coverage
		var baseline := preload("res://scripts/experiments/tokyo_source_coverage.gd").covered_sources(original,expected,real.configuration,original.collision_sha256,original.catalog_sha256)
		if baseline.is_empty(): fail+=1
		if indexed.covered_sources(committed,{},real.configuration,original.collision_sha256,original.catalog_sha256)!=baseline: fail+=1
		if Grid.covered_sources(real,committed,real.configuration,original.collision_sha256,original.catalog_sha256)!=baseline: fail+=1
		print("[Tokyo grid coverage actual] committed=",committed.size()," original_sources=",expected.size()," covered_buildings=",baseline.size())
	print("[Tokyo grid coverage] fail=",fail)
	return fail


static func mask_checks() -> int:
	var data := {"schema":1,"verified":true,"configuration":"lod5_full","collision_sha256":"c","catalog_sha256":"a","pages":{},"sources":{1:PackedStringArray(["t","u"]),2:PackedStringArray(["t"]),3:PackedStringArray(),4:PackedStringArray(["absent"])}}
	for path: String in ["a","b","c"]:
		data.pages[path]={"identity":{"id":path},"leaves":PackedStringArray(["shared" if path!="c" else "c"]),"tokens":[PackedStringArray(["t"]),PackedStringArray(["u","t"])]}
	var compiled := preload("res://scripts/experiments/tokyo_source_mask_index.gd").new()
	if not compiled.configure(data,{"a":3,"b":3,"c":3}): return 1
	var fail := 0
	for a in 4:
		for b in 4:
			for c in 4:
				var masks := {"a":a,"b":b,"c":c}
				var committed: Dictionary={}
				for path: String in masks:
					if masks[path]: committed[path]={"identity":data.pages[path].identity,"layers":masks[path]}
				var expected := preload("res://scripts/experiments/tokyo_source_coverage.gd").covered_sources(data,committed,"lod5_full","c","a")
				fail+=int(compiled.covered(masks,"lod5_full","c","a")!=expected)
	return fail


static func index_checks() -> int:
	var data := {"schema":1,"source_layers_complete":true,"coarse_to_fine":{},"pages":{},"dependencies":{},"original_coverage":{"pages":{}}}
	var committed: Dictionary={}
	for n in 32:
		var path := str(n)
		var identity := {"id":n}
		data.pages[path]={"identity":identity,"box":AABB(Vector3(n*20,0,(n%5)*40),Vector3(8,n+1,12))}
		data.dependencies[path]={0:[{"path":path,"identity":identity}]}
		data.original_coverage.pages[path]={"identity":identity}
		if n%2==0: committed[path]={"identity":identity,"layers":1}
	var indexed := preload("res://scripts/experiments/tokyo_grid_coverage_index.gd").new()
	if not indexed.configure(data): return 1
	var fail := int(indexed.refined_layers(committed)!=Grid.refined_layers(data,committed))
	for n in 24:
		var center := Vector2(n*30-100,(n%4)*50)
		var pose := {"view":Rect2(center,Vector2(120,100)),"canvas":Transform2D(float(n%4)*0.3,-center),"size":Vector2(120,100),"roof":Vector2(-2+n*0.2,1)}
		fail+=int(indexed.refined_layers(committed,pose)!=Grid.refined_layers(data,committed,pose))
	for actual: Dictionary in [{"identity":{"id":999},"layers":1},{"identity":{"id":0},"layers":4}]:
		var wrong := committed.duplicate(true);wrong["0"]=actual
		fail+=int(not indexed.refined_layers(wrong).is_empty())
	var frozen := indexed.refined_layers(committed)
	data.dependencies.clear() # 配置后的外部修改不得换义已编译快照。
	fail+=int(indexed.refined_layers(committed)!=frozen)
	return fail


static func refinement_checks() -> int:
	var box := AABB(Vector3.ZERO,Vector3(5,10,5))
	var far := AABB(Vector3(1000,0,1000),Vector3(5,10,5))
	var data := {"schema":1,"source_layers_complete":true,"original_coverage":{"pages":{"leaf":{"identity":{"id":"old"}}}},
		"pages":{"coarse":{"identity":{"id":"coarse"},"faces":2,"box":box.merge(far)}},
		"dependencies":{"leaf":{0:[{"path":"coarse","identity":{"id":"coarse"},"first_face":0,"faces":1},{"path":"coarse","identity":{"id":"coarse"},"first_face":1,"faces":1}]}}}
	var joined: Array=[{"path":"coarse","canonical_identity":{"id":"coarse"},"faces":2,"box":box.merge(far),"origins":[]}]
	for n in 2:
		joined[0].origins.append({"first_face":n,"faces":1,"source":"leaf","layer":0,"component":{"path":str(n),"canonical_identity":{"id":n},"box":box if n==0 else far}})
	var refined := Grid.refinement_data(data,joined)
	if refined.is_empty(): return 1
	var full := {"0":{"identity":{"id":0},"layers":1},"1":{"identity":{"id":1},"layers":1}}
	var expected := {"leaf":{"identity":{"id":"old"},"layers":1}}
	var fail := int(Grid.refined_layers(refined,full)!=expected)
	for key: String in full:
		var partial := full.duplicate(true);partial.erase(key)
		fail+=int(not Grid.refined_layers(refined,partial).is_empty())
	var wrong := full.duplicate(true);wrong["0"].identity={"id":"wrong"}
	fail+=int(not Grid.refined_layers(refined,wrong).is_empty())
	var duplicate := full.duplicate(true);duplicate["coarse"]={"identity":{"id":"coarse"},"layers":1}
	fail+=int(not Grid.refined_layers(refined,duplicate).is_empty())
	var overlap := joined.duplicate(true);overlap[0].origins[1].first_face=0
	fail+=int(not Grid.refinement_data(data,overlap).is_empty())
	var projection := {"view":Rect2(-10,-10,100,100),"canvas":Transform2D.IDENTITY,"size":Vector2(100,100),"roof":Vector2.ZERO}
	fail+=int(Grid.refined_layers(refined,{"0":full["0"]},projection)!=expected)
	projection.view=Rect2(990,990,100,100);projection.canvas=Transform2D(0,Vector2(-990,-990))
	fail+=int(not Grid.refined_layers(refined,{"0":full["0"]},projection).is_empty())
	var indexed := preload("res://scripts/experiments/tokyo_grid_coverage_index.gd").new()
	if not indexed.configure(refined): return fail+1
	for actual: Dictionary in [full,wrong,duplicate,{}, {"0":full["0"]},{"coarse":{"identity":{"id":"coarse"},"layers":1}}]:
		for pose: Dictionary in [{},projection,{"view":Rect2(-10,-10,100,100),"canvas":Transform2D.IDENTITY,"size":Vector2(100,100),"roof":Vector2.ZERO}]:
			fail+=int(indexed.refined_layers(actual,pose)!=Grid.refined_layers(refined,actual,pose))
	return fail
