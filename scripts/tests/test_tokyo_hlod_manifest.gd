extends RefCounted
const Contract := preload("res://scripts/rendering/tokyo_hlod_manifest.gd")


static func fixture() -> Dictionary:
	var rows: Array = []
	for depth in 3:
		var count := 4<<depth
		var span := 32000.0/count
		for id_value in count*count:
			var x := id_value%count
			var y := id_value/count
			var low := Contract.ORIGIN+Vector2(x,y)*span
			var path := "res://fixture/d%d-%d" % [depth,id_value]
			var ids: Array = []
			var formal: Array = []
			var cells := 16/count
			for yy in cells:
				for xx in cells:
					var source_id := (y*cells+yy)*16+x*cells+xx
					if source_id<189:
						ids.append(source_id)
						formal.append({"source_id":source_id,"height":8.0,"first_face":2+formal.size()*2,"faces":2})
			var children: Array = []
			if depth<2:
				for dy in 2:
					for dx in 2: children.append((y*2+dy)*(count*2)+x*2+dx)
			rows.append({"depth":depth,"id":id_value,"bounds":[low.x,low.y,low.x+span,low.y+span],
				"parent":-1 if depth==0 else (y/2)*(count/2)+x/2,"children":children,
				"faces":4+formal.size()*2,"ordinary_faces":2,"top_faces":2,"formal":formal,"formal_source_ids":ids,
				"geometry_bounds":[low.x,0.0,low.y,low.x+span,8.0,low.y+span],
				"native_geometry":{"path":path+".res","sha256":"a".repeat(64),"bytes":(2+formal.size()*2)*144,
					"canonical_identity":{"format":"tokyo_mesh_component","schema":1,"slots":2,"source":path.sha256_text()}},
				"native_texture":{"path":path+".image.res","sha256":"b".repeat(64),"mip_bytes":48,"three_copy_charge":4240,"format":Image.FORMAT_DXT5,"roundtrip":true},
				"texture":{"file":{"path":path+".rgba8","sha256":"c".repeat(64)},"bounds":[low.x,low.y,low.x+span,low.y+span],"bytes":84,
					"levels":[{"width":4,"height":4,"offset":0,"bytes":64},{"width":2,"height":2,"offset":64,"bytes":16},{"width":1,"height":1,"offset":80,"bytes":4}]}})
	return {"schema":1,"roots":16,"nodes":336,"native_saved_roundtrip":true,"input_sha256":"d".repeat(64),"rows":rows,"min_scale":0.05,"max_scale":0.1}


static func checks() -> bool:
	if not preload("res://scripts/tests/build_tokyo_hlod_opaque.gd").checks():
		print("[Opaque] converter checks failed")
		return false
	if Contract.integer(NAN) or Contract.integer(1.5) or Contract.sha("z".repeat(64)) \
		or not Contract.normalize(null).is_empty() or not Contract.normalize({}).is_empty(): return false
	var source := fixture()
	var massing := source.duplicate(true)
	massing["middle_massing_recipe"]={"path":"res://fixture/recipe.json","sha256":"a".repeat(64)}
	if not Contract.normalize(massing).is_empty(): return false
	massing.max_scale=0.625
	if Contract.normalize(massing).get("middle_massing_recipe",{})!=massing.middle_massing_recipe: return false
	massing.middle_massing_recipe.sha256="broken"
	if not Contract.normalize(massing).is_empty(): return false
	var opaque := source.duplicate(true)
	for row: Dictionary in opaque.rows:
		row.native_texture.format=int(Image.FORMAT_DXT1)
		row.native_texture.mip_bytes=24
		row.native_texture.three_copy_charge=4168
	if Contract.normalize(opaque).is_empty():
		print("[Opaque] normalized fixture rejected texture=",Contract.texture_valid(opaque.rows[0]))
		return false
	opaque.rows[0].native_texture.mip_bytes=48
	if not Contract.normalize(opaque).is_empty(): return false
	var catalog := Contract.normalize(source)
	if Contract.normalize(JSON.parse_string(JSON.stringify(source))).is_empty(): return false
	if catalog.is_empty() or catalog.roots.size()!=16 or catalog.geometry.size()!=336 or catalog.textures.size()!=336: return false
	if catalog.formal_runtime_coverage_verified or catalog.runtime_integrated: return false
	var mixed := source.duplicate(true)
	for row: Dictionary in mixed.rows: row["max_scale"]=0.06 if int(row.depth)<2 else 0.1
	var fine_catalog := Contract.normalize(mixed)
	if fine_catalog.is_empty() or not fine_catalog.mixed_scales: return false
	# 静态资格树缓存：精确阈值、反向、身份变化，逐节点与旧算法相等。
	fine_catalog["identity"]={"path":"res://qualification-test","sha256":"a".repeat(64)}
	var qualification_work := {}
	var source_snapshot := var_to_bytes(fine_catalog)
	for scale_value: float in [0.055,0.059,0.06,0.060001,0.08,0.06,0.055,0.1]:
		var expected: Array[Dictionary]=[]
		for root: Dictionary in fine_catalog.roots: expected.append(Contract.qualified_tree(root,scale_value))
		if Contract.qualified_roots(fine_catalog,scale_value,qualification_work)!=expected: return false
	if qualification_work.qualification_builds!=2 or qualification_work.qualification_reuses!=6: return false
	if var_to_bytes(fine_catalog)!=source_snapshot: return false
	fine_catalog.identity.sha256="b".repeat(64)
	Contract.qualified_roots(fine_catalog,0.1,qualification_work)
	if qualification_work.qualification_builds!=3: return false
	# 多身份交错的缓存有界；失效后重建仍与无缓存资格树逐节点一致。
	for n in 20:
		fine_catalog.identity.path="res://qualification-test-%d"%n
		var fresh_roots: Array[Dictionary]=[]
		for root: Dictionary in fine_catalog.roots: fresh_roots.append(Contract.qualified_tree(root,0.08))
		if Contract.qualified_roots(fine_catalog,0.08,qualification_work)!=fresh_roots: return false
		if qualification_work.qualifications.size()>Contract.FRAME_SOLUTIONS: return false
	# 相机/预算变化仍逐次求切面，缓存不得改变选页内容和顺序。
	for center: Vector2 in [Vector2.ZERO,Vector2(7000,-4000),Vector2(-14000,8000)]:
		for scale_value: float in [0.055,0.06,0.08]:
			for budget: int in [0,48*1024*1024,96*1024*1024]:
				var fresh := Contract.select(fine_catalog,center,scale_value,0.2,Vector2(1600,900),true,budget)
				var reused := Contract.select(fine_catalog,center,scale_value,0.2,Vector2(1600,900),true,budget,qualification_work)
				fresh.erase("solver_usec");reused.erase("solver_usec")
				if fresh!=reused: return false
	var fine_cut := Contract.select(fine_catalog,Vector2.ZERO,0.08,0,Vector2(160,90))
	if fine_cut.is_empty() or not fine_cut.within_budget: return false
	for key: String in fine_cut.keys:
		if not key.begins_with("2:"): return false
	var early_cut := Contract.select(fine_catalog,Vector2.ZERO,0.055,0,Vector2(160,90),true)
	if early_cut.is_empty() or not early_cut.within_budget: return false
	for key: String in early_cut.keys:
		if not key.begins_with("2:"): return false
	var coarse := {"keys":PackedStringArray(["0:0"])}
	var required := {"keys":PackedStringArray(["1:0"])}
	if not Contract.retained(fine_catalog,coarse,required,0.055) \
		or Contract.retained(fine_catalog,coarse,required,0.055,true): return false
	if Contract.retained(fine_catalog,{"keys":PackedStringArray(["0:0"])},{"keys":PackedStringArray(["1:0"])},0.08): return false
	mixed.rows[0].max_scale=NAN
	if not Contract.normalize(mixed).is_empty(): return false
	if not Contract.select(catalog,Vector2.ZERO,0.2,0).is_empty() or not Contract.select(catalog,Vector2.ZERO,NAN,0).is_empty(): return false
	var visible := Contract.select(catalog,Vector2.ZERO,0.08,0.2)
	if visible.is_empty() or not visible.within_budget or visible.active<=0 or visible.active>16: return false
	var zero_budget := Contract.select(catalog,Vector2.ZERO,0.08,0.2,Vector2(1600,900),false,0)
	if zero_budget.is_empty() or zero_budget.within_budget or zero_budget.keys.is_empty(): return false
	if not Contract.select(catalog,Vector2.ZERO,0.08,0.2,Vector2(1600,900),false,-1).is_empty(): return false
	if not Contract.retained(catalog,visible,visible,0.08): return false
	# select允许较细目录提前进入，retained不能在同一提前窗口以min_scale否决它。
	var ahead := Contract.select(catalog,Vector2.ZERO,0.04,0.2,Vector2(1600,900),true)
	if ahead.is_empty() or not ahead.within_budget or not Contract.retained(catalog,ahead,ahead,0.04,true) \
		or Contract.retained(catalog,ahead,ahead,0.04):
		print("[HLOD prefetch regression] select/retained minimum-scale mismatch")
		return false
	var handoff := preload("res://scripts/rendering/tokyo_hlod_handoff.gd")
	var native := {"keys":PackedStringArray(["a"]),"configuration":"lod4_full"}
	if not handoff.native_qualified(native,1.5) or handoff.native_qualified(native,1.7) or handoff.native_qualified(native,NAN): return false
	# 接替max_scale=1.25的HLOD时，LOD4是完整桥接，LOD3只是临时档，不能同样锁定。
	if not handoff.native_qualified(native,1.25): return false
	var temporary := {"keys":PackedStringArray(["a"]),"configuration":"lod3_full"}
	if handoff.native_qualified(temporary,1.25): return false
	var parts := {"a":{"components":{"shared":{"bytes":10},"only_a":{"bytes":20}}},"b":{"components":{"shared":{"bytes":10},"only_b":{"bytes":30}}}}
	if handoff.streaming_bytes(parts,{"image":{"charge":12}},PackedStringArray(["a","b"]),PackedStringArray(["image","image"]),8)!=80: return false
	if handoff.streaming_bytes(parts,{},PackedStringArray(["missing"]),PackedStringArray(),0)!=-1: return false
	var broken_parts := parts.duplicate(true)
	broken_parts.b.components.shared.bytes=11
	if handoff.streaming_bytes(broken_parts,{},PackedStringArray(["a","b"]),PackedStringArray(),0)!=-1: return false
	var one := {"keys":PackedStringArray(["0:0"])}
	var charged := Contract.charges(catalog,one.keys)
	if handoff.combined_bytes(catalog,one,catalog,one)!=charged.total_bytes+charged.ground_bytes: return false
	if handoff.combined_bytes(catalog,{},catalog,one)!=-1: return false
	var conflict := catalog.duplicate(true)
	conflict.rows["0:0"].native_geometry.sha256="0".repeat(64)
	if handoff.combined_bytes(catalog,one,conflict,one)!=-1: return false
	if not handoff.qualified(catalog,one,0.08) or handoff.qualified(catalog,one,0.11) or handoff.qualified(catalog,one,NAN): return false
	if handoff.qualified(fine_catalog,one,0.08): return false
	if Contract.retained(catalog,visible,visible,0.2): return false
	var broken_cut := visible.duplicate(true)
	broken_cut.keys=PackedStringArray(["2:256"])
	if Contract.retained(catalog,broken_cut,visible,0.08): return false
	if not Contract.retained(catalog,{"keys":PackedStringArray(["0:0"])},{"keys":PackedStringArray(["1:0"])},0.08): return false
	if Contract.retained(catalog,{"keys":PackedStringArray(["1:0"])},{"keys":PackedStringArray(["0:0"])},0.08): return false
	var cut := Contract.charges(catalog,PackedStringArray(["0:0","0:1"]))
	if cut.is_empty() or cut.texture_charge!=8480 or cut.ground_bytes!=576 or cut.coverage_verified: return false
	if not Contract.charges(catalog,PackedStringArray(["0:0","0:0"])).is_empty() \
		or not Contract.charges(catalog,PackedStringArray(["0:0","1:0"])).is_empty() \
		or not Contract.charges(catalog,PackedStringArray(["2:256"])).is_empty(): return false
	for property in ["nodes","max_scale"]:
		var bad := source.duplicate(true)
		bad[property]=0
		if not Contract.normalize(bad).is_empty(): return false
	var missing := source.duplicate(true)
	missing.rows.pop_back()
	if not Contract.normalize(missing).is_empty(): return false
	for property in ["parent","faces","ordinary_faces"]:
		var bad := source.duplicate(true)
		bad.rows[0][property]=-2
		if not Contract.normalize(bad).is_empty(): return false
	var wrong := source.duplicate(true)
	wrong.rows[0].bounds[0]+=1
	if not Contract.normalize(wrong).is_empty(): return false
	wrong=source.duplicate(true);wrong.rows[0].children.reverse()
	if not Contract.normalize(wrong).is_empty(): return false
	wrong=source.duplicate(true);wrong.rows[0].formal[0].height+=1
	if not Contract.normalize(wrong).is_empty(): return false
	wrong=source.duplicate(true);wrong.rows[0].native_texture.three_copy_charge-=1
	if not Contract.normalize(wrong).is_empty(): return false
	wrong=source.duplicate(true);wrong.rows[0].texture.levels[1].offset+=4
	if not Contract.normalize(wrong).is_empty(): return false
	wrong=source.duplicate(true);wrong.rows[1].native_texture.path=wrong.rows[0].native_texture.path;wrong.rows[1].native_texture.sha256="e".repeat(64)
	if not Contract.normalize(wrong).is_empty(): return false
	# 同物理纹理身份可共享，计费一次，页面地面仍分别计费。
	var shared := source.duplicate(true)
	shared.rows[1].native_texture=shared.rows[0].native_texture.duplicate(true)
	var shared_catalog := Contract.normalize(shared)
	if shared_catalog.is_empty(): return false
	var shared_cut := Contract.charges(shared_catalog,PackedStringArray(["0:0","0:1"]))
	return shared_cut.texture_charge==4240 and shared_cut.ground_bytes==576 and source==fixture()
