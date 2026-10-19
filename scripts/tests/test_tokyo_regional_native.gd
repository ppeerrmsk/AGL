extends RefCounted
const Build := preload("res://scripts/tests/build_tokyo_regional_native.gd")
const Geometry := preload("res://scripts/experiments/volume_mesh_factory.gd")
const Indexed := preload("res://scripts/experiments/tokyo_indexed_mesh.gd")
const Gameplay := preload("res://scripts/tests/tokyo_region_gameplay_guard.gd")
const OwnedBlocks := preload("res://scripts/tests/build_tokyo_owned_region_blocks.gd")
const Difference := preload("res://scripts/experiments/tokyo_packed_mesh_difference.gd")
var _pass := 0
var _fail := 0


func run() -> void:
	_check(preload("res://scripts/tests/test_tokyo_hlod_coverage.gd").checks(),"HLOD coverage binds source/collision, native formal faces and Loading texture readiness")
	_check(preload("res://scripts/tests/build_tokyo_hlod_native_pages.gd").checks(),"native HLOD page packing rejects missing/incomplete sources and keeps empty mesh valid")
	_check(preload("res://scripts/tests/test_tokyo_hlod_manifest.gd").checks(),"runtime HLOD manifest keeps full hierarchy and source ownership, separate texture charges, and rejects identity or mip drift")
	_check(not preload("res://scripts/tests/tokyo_hlod_pages_review.gd").valid_pose(null) and not preload("res://scripts/tests/tokyo_hlod_pages_review.gd").valid_pose({"center":[0,0],"scale":0,"rotation":0,"cut":[]}),"native HLOD review rejects absent and empty zero-scale views")
	_check(preload("res://scripts/tests/tokyo_overview_hlod_review.gd").checks(),"overview native review rejects absent bindings and preserves saved positions, upward roofs and whole-map UV")
	_check(preload("res://scripts/tests/build_tokyo_semantic_fixed_tree.gd").checks(),"semantic fixed tree validates retained original-leaf order and rejects malformed deletion routes")
	_check(preload("res://scripts/tests/rebind_tokyo_semantic_fixed_tree.gd").checks(),"fixed component rebinding preserves building references and gameplay sources without mutating original metadata")
	_check(preload("res://scripts/tests/bake_tokyo_semantic_rail_roots.gd").checks(),"semantic rail filtering matches full attributes and duplicate counts, preserving other packed channels")
	_check(preload("res://scripts/tests/tokyo_interaction_certificate.gd").checks(),"certified interaction inputs preserve exact candidate values and reject unbound proof")
	_check(preload("res://scripts/tests/bake_tokyo_interaction_probe.gd").run("","","","")==1,"interaction native probe rejects unbound selection evidence")
	_check(preload("res://scripts/tests/tokyo_full_grid_review.gd").checks(),"full-map visual route covers all sixteen roots and twenty-four root seams")
	_check(preload("res://scripts/tests/tokyo_portable_paths.gd").checks() and preload("res://scripts/tests/tokyo_portable_paths.gd").full_grid_checks(),"portable paths preserve typed values and full four-depth graph through reversible relocation")
	_check(preload("res://scripts/tests/build_tokyo_portable_package.gd").run("","","")==1 and preload("res://scripts/tests/verify_tokyo_portable_package.gd").run("","")==1,"portable package cannot install or certify unbound input")
	_check(preload("res://scripts/tests/test_tokyo_component_page.gd").checks(),"shared component assembly rejects stale/missing state and full four-depth coverage cuts stay exact")
	_check(preload("res://scripts/tests/test_tokyo_full_root_page_join.gd").checks(),"whole canonical input gates and native/fixed/game additions preserve exact original leaf routes")
	_check(preload("res://scripts/tests/test_tokyo_full_component_tree.gd").run("","")==1,"full component tree fixture rejects unbound output and layout")
	_check(preload("res://scripts/tests/test_tokyo_full_native_leaves.gd").checks(),"post-roof native partition preserves original leaves and packed faces")
	_check(preload("res://scripts/tests/audit_tokyo_full_root_roof_precision.gd").run("","","",false)==1,"full-grid roof precision probe rejects unbound input")
	_check(preload("res://scripts/tests/test_tokyo_full_root_roofs.gd").checks(),"full-grid roof export preserves all 189 formal gameplay identities and heights")
	_check(preload("res://scripts/tests/test_tokyo_full_grid_root.gd").checks(),"full-root packed join, stable cell ranges and configuration selection")
	_check(preload("res://scripts/tests/test_tokyo_full_grid_contract.gd").checks(),"full-grid catalog format, missing leaves and legacy isolation")
	_check(preload("res://scripts/tests/transfer_tokyo_full_tile_blocks.gd").run("","")==1,"owned full-grid blocks reject missing binding")
	var batch_digest := "a".repeat(64)
	var batch_config := {"schema":1,"registry_sha256":batch_digest,"regions":["b","a"]}
	_check(Build.batch_regions(batch_config,["a","b","c"],batch_digest)==["a","b"],"regional batch retains global order")
	_check(Build.batch_regions(batch_config,["a","b"],"b".repeat(64)).is_empty(),"regional batch rejects changed registry")
	batch_config.regions=["a","a"]
	_check(Build.batch_regions(batch_config,["a","b"],batch_digest).is_empty(),"regional batch rejects duplicate region")
	batch_config.regions=["unknown"]
	_check(Build.batch_regions(batch_config,["a","b"],batch_digest).is_empty(),"regional batch rejects unknown region")
	batch_config.regions=[]
	_check(Build.batch_regions(batch_config,["a","b"],batch_digest).is_empty(),"regional batch rejects empty work")
	batch_config.regions=[1]
	_check(Build.batch_regions(batch_config,["a","b"],batch_digest).is_empty(),"regional batch rejects nonstring region")
	var southwest_boundary := preload("res://scripts/tests/tokyo_northwest_boundary.gd")
	_check(southwest_boundary.southwest("","",false)==1,"southwest historical build rejects empty input")
	_check(southwest_boundary.southwest("","",true)==1,"southwest historical audit rejects empty input")
	var prior_southwest := OS.get_environment("AGL_TOKYO_SOUTHWEST_BOUNDARY")
	OS.set_environment("AGL_TOKYO_SOUTHWEST_BOUNDARY","1")
	_check(southwest_boundary.run("","")==1,"southwest build dispatch rejects empty input")
	_check(southwest_boundary.audit("","")==1,"southwest audit dispatch rejects empty input")
	OS.set_environment("AGL_TOKYO_SOUTHWEST_BOUNDARY",prior_southwest)
	_check(preload("res://scripts/tests/build_tokyo_depot_union.gd").build("", "") == 1,"depot union rejects missing exact source")
	var shadow_renderer := BuildingRenderer.new()
	_check(shadow_renderer.consume_view_change(Vector2.ZERO,Vector2.ONE,Vector2(1600,900)),"initial view redraw")
	_check(not shadow_renderer.consume_view_change(Vector2.ZERO,Vector2.ONE,Vector2(1600,900)),"static view no redraw")
	_check(shadow_renderer.consume_view_change(Vector2.ZERO,Vector2(2,2),Vector2(1600,900)),"stationary zoom redraw")
	_check(shadow_renderer.consume_view_change(Vector2.ZERO,Vector2.ONE,Vector2(1600,900)),"zoom restore redraw")
	_check(shadow_renderer.consume_view_change(Vector2.ZERO,Vector2.ONE,Vector2(1920,1080)),"resize redraw")
	_check(not shadow_renderer.consume_view_change(Vector2(3,0),Vector2.ONE,Vector2(1920,1080)),"small movement retains threshold")
	_check(shadow_renderer.consume_view_change(Vector2(4,0),Vector2.ONE,Vector2(1920,1080)),"accumulated movement redraw")
	var shadow_rows: Array = [{"d":{"shadow_poly":PackedVector2Array([Vector2.ZERO,Vector2.RIGHT,Vector2.DOWN]),"shadow_tri":PackedInt32Array([0,1,2])}}]
	var shadow_ids := PackedInt32Array([2])
	var shadow_reference := var_to_bytes(shadow_renderer.shadow_packet(shadow_rows,shadow_ids))
	shadow_renderer.cache_shadow_geometry=true
	_check(var_to_bytes(shadow_renderer.shadow_packet(shadow_rows,shadow_ids))==shadow_reference,"cached shadow equals original arrays")
	var shadow_builds := shadow_renderer.shadow_cache_builds
	shadow_renderer.shadow_packet(shadow_rows,shadow_ids)
	_check(shadow_renderer.shadow_cache_builds==shadow_builds,"unchanged shadow reused")
	shadow_renderer.shadow_color=Color.RED
	_check(shadow_renderer.shadow_packet(shadow_rows,shadow_ids).colors[0]==Color.RED,"shadow tint invalidates")
	shadow_renderer.shadow_offset_px+=2
	_check(var_to_bytes(shadow_renderer.shadow_packet(shadow_rows,shadow_ids))!=shadow_reference,"shadow offset invalidates")
	_check(shadow_renderer.shadow_packet([],PackedInt32Array()).indices.is_empty(),"empty selection removes shadow")
	shadow_renderer.shadow_packet(shadow_rows,shadow_ids)
	shadow_renderer.setup(null)
	_check(shadow_renderer._shadow_packet.is_empty(),"setup clears prior shadow packet")
	shadow_renderer.cache_shadow_geometry=false
	shadow_renderer.shadow_packet(shadow_rows,shadow_ids)
	_check(shadow_renderer._shadow_packet.is_empty(),"disabled cache retains no geometry")
	shadow_renderer.free()
	_check(BuildingRenderer.bounded_roof_offset(Vector2(9000,0),0,0.1)==Vector2.ZERO,"zero height has no projected wall")
	_check(BuildingRenderer.bounded_roof_offset(Vector2.ZERO,40,0.1)==Vector2(0,-10),"center retains vertical relief")
	var roof_far := BuildingRenderer.bounded_roof_offset(Vector2(100000,0),40,0.1)
	_check(roof_far.x<20.0 and roof_far.x>19.9 and roof_far.y==-10,"far radial offset bounded by height")
	_check(BuildingRenderer.bounded_roof_offset(Vector2(199,0),40,0.1).distance_to(BuildingRenderer.bounded_roof_offset(Vector2(201,0),40,0.1))<0.2,"projection continuous across saturation scale")
	_check(BuildingRenderer.bounded_roof_offset(Vector2(-100000,0),40,0.1).x<0,"projection preserves radial direction")
	var original_east := OS.get_environment("AGL_TOKYO_RESIDENTIAL_NORTHWEST_EAST")
	OS.set_environment("AGL_TOKYO_RESIDENTIAL_NORTHWEST_EAST","1")
	_check(preload("res://scripts/tests/tokyo_residential_preview.gd").northwest_matrix("","")==1,"east matrix rejects empty input")
	_check(preload("res://scripts/tests/build_tokyo_northwest_blocks.gd").run("","")==1,"east combined archive rejects empty input")
	OS.set_environment("AGL_TOKYO_RESIDENTIAL_NORTHWEST_EAST",original_east)
	var previous_west := OS.get_environment("AGL_TOKYO_RESIDENTIAL_NORTHWEST_WEST")
	for west_value: String in ["0","1"]:
		OS.set_environment("AGL_TOKYO_RESIDENTIAL_NORTHWEST_WEST",west_value)
		_check(preload("res://scripts/tests/tokyo_residential_preview.gd").northwest_matrix("","")==1,"northwest matrix modes reject empty source/output")
		_check(preload("res://scripts/tests/build_tokyo_northwest_blocks.gd").run("","")==1,"northwest archive modes reject empty source/output")
	OS.set_environment("AGL_TOKYO_RESIDENTIAL_NORTHWEST_WEST",previous_west)
	var submission_audit := preload("res://scripts/tests/tokyo_submission_duplicate_audit.gd")
	_check(submission_audit.run("","")==1,"submission audit rejects empty destination")
	var digest_tree: Array = [{"path":"root","sha256":"root_digest","children":[{"path":"leaf","sha256":"leaf_digest"}]}]
	_check(submission_audit.entry_digest(digest_tree,"leaf")=="leaf_digest","submission audit resolves leaf hash from tree not logical descriptor")
	_check(submission_audit.entry_digest(digest_tree,"root")=="root_digest" and submission_audit.entry_digest(digest_tree,"missing")=="","submission audit root hash and absent path")
	var wall_builder := preload("res://scripts/tests/build_tokyo_northwest_walls.gd")
	_check(wall_builder.run("","")==1,"northwest wall build rejects empty source/output")
	var previous_combined := OS.get_environment("AGL_TOKYO_NORTHWEST_COMBINED")
	for combined_value: String in ["0","1"]:
		OS.set_environment("AGL_TOKYO_NORTHWEST_COMBINED",combined_value)
		_check(wall_builder.run("","")==1,"both certified wall recipes reject empty source/output")
	OS.set_environment("AGL_TOKYO_NORTHWEST_COMBINED",previous_combined)
	_check(wall_builder.partition(null).is_empty(),"northwest wall partition rejects null")
	_check(wall_builder.partition(ArrayMesh.new()).is_empty(),"northwest wall partition rejects empty mesh")
	var wall_fixture := Geometry.new()
	wall_fixture.triangle(Vector3(0,3.2,0),Vector3(0,3.2,1),Vector3(1,3.2,0),Color("a1aaa0"))
	wall_fixture.quad(Vector3.ZERO,Vector3.RIGHT,Vector3(1,3.2,0),Vector3(0,3.2,0),Color("69766f"))
	var wall_source := wall_fixture.mesh()
	var wall_split := wall_builder.partition(wall_source)
	_check(not wall_split.is_empty() and Indexed.triangles(wall_split.roofs)==1 and Indexed.triangles(wall_split.walls)==2 and Difference.conserved(wall_source,wall_split.roofs,wall_split.walls),"northwest block roof/wall exact conserved split")
	var wrong_wall := Geometry.new()
	wrong_wall.triangle(Vector3.ZERO,Vector3.RIGHT,Vector3.UP,Color.WHITE)
	_check(wall_builder.partition(wrong_wall.mesh()).is_empty(),"northwest partition rejects non-plan colors")
	_routes_contract()
	var extension_audit := OS.get_environment("AGL_TOKYO_EXTENSION_CATALOG_AUDIT")
	if not extension_audit.is_empty():
		_check(load("res://scripts/tests/build_tokyo_extension_catalog.gd").new().audit(extension_audit)==0,"four-region saved catalog boundary conservation and coverage")
	var stable_output := OS.get_environment("AGL_TOKYO_REGIONAL_STABLE_OUTPUT")
	if not stable_output.is_empty():
		_check(load("res://scripts/tests/audit_tokyo_regional_native.gd").compare_previous(OS.get_environment("AGL_TOKYO_REGIONAL_STABLE_CURRENT"),OS.get_environment("AGL_TOKYO_REGIONAL_STABLE_PREVIOUS"),stable_output)==0,"prior unaffected regions retain packed surfaces and decoded geometry")
	_path_lod_contract()
	var path_lod_audit := OS.get_environment("AGL_TOKYO_PATH_LOD_AUDIT")
	if not path_lod_audit.is_empty():
		_check(load("res://scripts/tests/build_tokyo_path_lod.gd").audit(path_lod_audit)==0,"saved path LOD exact selected fixed layer and all building components unchanged")
	_guarded_blocks_contract()
	var guarded_audit := OS.get_environment("AGL_TOKYO_GUARDED_BLOCK_AUDIT")
	if not guarded_audit.is_empty():
		_check(load("res://scripts/tests/build_tokyo_guarded_blocks.gd").audit(guarded_audit)==0,"saved guarded catalog low-only change and all components/coverage")
	_extension_contract()
	var catalog_audit := OS.get_environment("AGL_TOKYO_REGIONAL_CATALOG_AUDIT")
	if not catalog_audit.is_empty():
		_check(load("res://scripts/tests/build_tokyo_regional_catalog.gd").new().audit(catalog_audit)==0,"independent saved catalog and all physical layer arrays")
	var records := {"a":{},"b":{},"c":{},"d":{}}
	_check(OwnedBlocks.disjoint_groups([{"ids":["a","b"]}],PackedStringArray(["c"]),records),"owner-only group can transfer unchanged")
	_check(not OwnedBlocks.disjoint_groups([{"ids":["a","c"]}],PackedStringArray(["c"]),records),"mixed-owner group rejected rather than split")
	_check(not OwnedBlocks.disjoint_groups([{"ids":["a","b"]},{"ids":["a","d"]}],PackedStringArray(),records),"duplicate group membership rejected")
	_check(not OwnedBlocks.disjoint_groups([{"ids":["a","missing"]}],PackedStringArray(),records),"unknown source rejected")
	_check(not OwnedBlocks.disjoint_groups([{"ids":["a"]}],PackedStringArray(),records),"single-source pseudo merge rejected")
	_check(not OwnedBlocks.disjoint_groups([{}],PackedStringArray(),records),"malformed merge rejected")
	_check(not OwnedBlocks.disjoint_groups({},PackedStringArray(),records),"malformed plan rejected")
	_transfer_contract()
	_difference_contract()
	var first := Geometry.new()
	first.quad(Vector3.ZERO,Vector3.RIGHT,Vector3(1,0,1),Vector3.BACK,Color("80877e"))
	var one := first.mesh()
	var source := Geometry.new()
	for i in 2:
		source.quad(Vector3.ZERO,Vector3.RIGHT,Vector3(1,0,1),Vector3.BACK,Color("80877e"))
	var two := source.mesh()
	# R201真实归属入口使用同一索引差集，不仅测试旧非索引辅助函数。
	var indexed_two := preload("res://scripts/experiments/tokyo_packed_mesh_join.gd").join([two])
	var indexed_before: Array = indexed_two.get("_surfaces").duplicate(true)
	var indexed_delta := Build.subtract(indexed_two,one)
	_check(not indexed_delta.is_empty() and indexed_delta.removed==2 and Build.conserved(indexed_two,indexed_delta.mesh,one),"regional indexed candidate removes exact multiplicity with decoded conservation")
	_check(indexed_two.get("_surfaces")==indexed_before,"regional indexed source bytes unchanged")
	_check(Build.subtract(one,indexed_two).is_empty(),"regional indexed excess removal rejected")
	var before: Array = two.get("_surfaces").duplicate(true)
	var result := Build.subtract(two,one)
	_check(Build.supported(result.mesh),"legacy regional subtraction retains unindexed layout")
	_check(not result.is_empty() and result.removed==2 and Build.conserved(two,result.mesh,one),"remove one duplicate multiplicity not all equal faces")
	_check(two.get("_surfaces")==before,"original packed geometry not mutated")
	_check(Build.subtract(one,two).is_empty(),"missing multiplicity rejected")
	_check(Build.subtract(ArrayMesh.new(),one).is_empty(),"absent source rejected")
	_check(Build.subtract(one,one).mesh.get_surface_count()==0,"complete removal gives empty mesh")
	_check(Build.subtract(two,ArrayMesh.new()).mesh==two,"empty removal retains original mesh")
	_check(Build.conserved(two,two,ArrayMesh.new()),"unchanged packed mesh proves empty subtraction without decoded rebuilding")
	_check(not Build.conserved(two,one,ArrayMesh.new()) and not Build.conserved(two,two,one),"unchanged fast path cannot hide lost or added triangles")
	for prepared_roof in [false,true]:
		for detail in 3:
			var roof_record := {"source_tags":{"roof:shape":"gabled"},"height_source":"levels","min_height_m":0.0,"rings":[{"outer":[[0,0],[2,0],[0,2]],"holes":[],"triangles":[[0,0],[2,0],[0,2]]}]}
			if prepared_roof:
				roof_record["roof_volume"]={"walls":[[0,0,0],[0,4,0],[2,4,0]],"roof":[[0,4,0],[2,5,0],[0,4,2]]}
			var roof_original := Geometry.new()
			Build.Factory._add_ring_building(roof_original,roof_record,5.0,detail)
			var replay := Geometry.new()
			var owned_record := roof_record.duplicate(true)
			owned_record["regional_draw_owner"]="neighbor"
			Build.Factory._add_ring_building(replay,owned_record,5.0,detail)
			var roof_delta := Build.subtract(roof_original.mesh(),replay.mesh())
			_check(not roof_delta.is_empty() and roof_delta.mesh.get_surface_count()==0,"nonflat native factory replay removes exact prepared or fallback roof at every detail")
	var bad := Geometry.new()
	bad.quad(Vector3.UP,Vector3(1,1,0),Vector3(1,1,1),Vector3(0,1,1),Color("80877e"))
	_check(Build.subtract(two,bad.mesh()).is_empty(),"height mismatch rejected")
	var color := Geometry.new()
	color.quad(Vector3.ZERO,Vector3.RIGHT,Vector3(1,0,1),Vector3.BACK,Color("ffffff"))
	_check(Build.subtract(two,color.mesh()).is_empty(),"color mismatch rejected")
	var northwest := preload("res://scripts/tests/tokyo_northwest_boundary.gd")
	_check(northwest.run("","")==1,"northwest boundary missing inputs rejected")
	var same_positions: Dictionary = northwest.compare_positions(two,one)
	_check(same_positions.missing_position_faces==0 and same_positions.attribute_mismatch_faces==0,"position diagnostic handles source multiplicity")
	_check(northwest.compare_positions(one,two).missing_position_faces==2,"position diagnostic detects excess duplicate")
	_check(northwest.compare_positions(two,bad.mesh()).missing_position_faces==2,"position diagnostic detects height mismatch")
	_check(northwest.compare_positions(two,color.mesh()).attribute_mismatch_faces==2,"position-only match cannot hide changed colors")
	_check(northwest.decoded_roundtrip(ArrayMesh.new()).get_surface_count()==0,"empty encoding roundtrip remains empty")
	_check(northwest.audit("","")==1,"northwest boundary audit missing evidence rejected")
	_check(northwest.historical_target("","unknown",one)==null,"unknown historical configuration rejected")
	var historical_mesh: ArrayMesh = northwest.select_historical(one,one)
	_check(historical_mesh!=null and Build.conserved(one,historical_mesh,ArrayMesh.new()),"historical selection preserves exact source attributes")
	_check(northwest.select_historical(two,one)==null,"ambiguous historical source face rejected")
	_check(northwest.select_historical(one,two)==null,"repeated historical target face rejected")
	_check(northwest.select_historical(one,color.mesh())==null,"historical source color identity enforced")
	_check(not Build.conserved(two,one,ArrayMesh.new()),"independent audit detects missing face")
	var packed := Indexed.pack(two)
	var packed_delta := Build.subtract(packed,one)
	_check(packed.surface_get_array_index_len(0)>0 and not packed_delta.is_empty() and Build.conserved(packed,packed_delta.mesh,one),"indexed archive accepted only with exact decoded conservation")
	var boxes: Array = [{"bbox": Rect2(0,0,10,10)}]
	_check(Gameplay.inspect_bounds(Rect2(20,20,5,5),boxes).standalone_merge_allowed,"separate low-rise region allowed")
	_check(not Gameplay.inspect_bounds(Rect2(2,2,2,2),boxes).standalone_merge_allowed,"building contains region: protect even with center outside")
	_check(not Gameplay.inspect_bounds(Rect2(9,9,5,5),boxes).standalone_merge_allowed,"partial crossing protected")
	_check(not Gameplay.inspect_bounds(Rect2(10,0,5,5),boxes).standalone_merge_allowed,"shared boundary protected")
	_check(Gameplay.inspect_bounds(Rect2(-1,-1,12,12),boxes).contained==[0],"enclosed building source identity retained")
	_check(Gameplay.inspect_bounds(Rect2(0,0,0,5),boxes).is_empty(),"empty region rejected")
	_check(Gameplay.inspect_bounds(Rect2(Vector2(INF,0),Vector2.ONE),boxes).is_empty(),"nonfinite region rejected")
	_check(Gameplay.inspect_bounds(Rect2(20,20,5,5),[{}]).is_empty(),"malformed authority rejected")
	var expanded := Gameplay.include_points(Rect2(20,20,5,5),[[0,0],[1,0],[0,1]])
	_check(not expanded.is_empty() and not Gameplay.inspect_bounds(expanded.bounds,boxes).standalone_merge_allowed,"actual cross-boundary vertices expand nominal region")
	_check(Gameplay.include_points(Rect2(20,20,5,5),[[0,0],[1,0],[NAN,1]]).is_empty(),"nonfinite source vertex rejected")
	_check(Gameplay.include_points(Rect2(20,20,5,5),[[0,0],[1,0]]).is_empty(),"incomplete polygon rejected")
	var game_source := Gameplay.read_source()
	_check(Gameplay.protection_data({}).is_empty(),"gameplay protection rejects absent authority")
	_check(Gameplay.export_protection("","")==1,"gameplay protection rejects absent output")
	var protection := Gameplay.protection_data(game_source)
	var preservation := {"source_sha256":game_source.source_sha256,"collision_sha256":game_source.collision_sha256,"mask_sha256":JSON.stringify(protection).sha256_text(),"selected_intersects":false,"blocks_intersects":false}
	var protected_bounds: Rect2 = game_source.entries[0].bbox
	_check(not Gameplay.preserved_merge_allowed(protected_bounds,game_source),"intersecting tile still rejects absent preservation proof")
	_check(Gameplay.preserved_merge_allowed(protected_bounds,game_source,preservation),"complete disjoint-geometry proof may preserve gameplay in intersecting tile")
	for field: String in ["source_sha256","collision_sha256","mask_sha256"]:
		var wrong: Dictionary = preservation.duplicate()
		wrong[field]="f".repeat(64)
		_check(not Gameplay.preserved_merge_allowed(protected_bounds,game_source,wrong),"preservation rejects stale authority or modified mask")
	for field: String in ["selected_intersects","blocks_intersects"]:
		var touching: Dictionary = preservation.duplicate()
		touching[field]=true
		_check(not Gameplay.preserved_merge_allowed(protected_bounds,game_source,touching),"preservation rejects any touched gameplay geometry")
		var mistyped: Dictionary = preservation.duplicate()
		mistyped[field]=0
		_check(not Gameplay.preserved_merge_allowed(protected_bounds,game_source,mistyped),"preservation requires explicit boolean geometry results")
	_check(protection.entries.size()==game_source.entries.size() and protection.collision_sha256==game_source.collision_sha256 and protection.source_sha256==game_source.source_sha256,"gameplay protection retains complete authority and digests")
	for id in protection.entries.size():
		_check(protection.entries[id].source_id==id and protection.entries[id].raw_id==game_source.raw_ids[id] and protection.entries[id].height_m==game_source.entries[id].max_real_h and protection.entries[id].tri_indices==Array(game_source.entries[id].tri_indices),"gameplay protection preserves source order height and triangles")
		var authored: Dictionary = game_source.entries[id]
		var outline_ok: bool = protection.entries[id].footprint.size()==authored.footprint.size()
		for corner in mini(protection.entries[id].footprint.size(),authored.footprint.size()):
			outline_ok=outline_ok and protection.entries[id].footprint[corner]==[authored.footprint[corner].x,authored.footprint[corner].y]
		_check(outline_ok and protection.entries[id].bbox==[authored.bbox.position.x,authored.bbox.position.y,authored.bbox.size.x,authored.bbox.size.y],"gameplay protection preserves every point and bounds")
	var protection_output := OS.get_environment("AGL_TOKYO_GAMEPLAY_PROTECTION_OUT")
	if not protection_output.is_empty():
		_check(Gameplay.export_protection(protection_output,OS.get_environment("AGL_TOKYO_REGION_GAMEPLAY_ROOT"))==0,"gameplay protection saved and independently parsed")
	_check(not game_source.is_empty() and game_source.entries.size()==189 and game_source.raw_ids.size()==189 and game_source.rejected_raw_ids.size()==4,"real gameplay acceptance authority: 193 raw / 189 accepted")
	_check(not game_source.is_empty() and Gameplay.inspect_bounds(Rect2(-6800,-2700,500,1000),game_source.entries).standalone_merge_allowed,"west sample does not intersect real gameplay buildings")
	var game_output := OS.get_environment("AGL_TOKYO_REGION_GAMEPLAY_AUDIT")
	if not game_output.is_empty():
		_check(Gameplay.write_audit(game_output,game_source,OS.get_environment("AGL_TOKYO_REGION_GAMEPLAY_ROOT"))==0,"native regional collision identity and canonical coverage audit")
	var candidate := OS.get_environment("AGL_TOKYO_REGION_GAMEPLAY_CANDIDATE")
	if not candidate.is_empty():
		_check(_compare_candidate(OS.get_environment("AGL_TOKYO_REGION_GAMEPLAY_BASELINE"),candidate),"saved five-LOD geometry and fixed/marked layers unchanged")
	var audit_path := OS.get_environment("AGL_TOKYO_REGIONAL_NATIVE_AUDIT")
	if not audit_path.is_empty():
		_check(load("res://scripts/tests/audit_tokyo_regional_native.gd").run(audit_path,OS.get_environment("AGL_TOKYO_REGIONAL_NATIVE_SOURCE"))==0,"separate-process saved complete regional audit")
	var boundary_path := OS.get_environment("AGL_TOKYO_BOUNDARY_TRANSFER_AUDIT")
	if not boundary_path.is_empty():
		_check(load("res://scripts/tests/build_tokyo_boundary_transfer.gd").audit(boundary_path,OS.get_environment("AGL_TOKYO_REGIONAL_NATIVE_SOURCE"))==0,"independent saved boundary conservation and game-building protection")
	print("[Regional native tests] pass=",_pass," fail=",_fail)


func _routes_contract() -> void:
	var digest := "a".repeat(64)
	var route := {"source":"res://tmp/source","index":"res://tmp/native/index.res","dedup":false,"footprint_lod":false}
	var config := {"schema":1,"registry_sha256":digest,"routes":{"west":route}}
	_check(Build.valid_routes(config,["west"],digest),"explicit one-region native route accepted")
	_check(Build.valid_routes(JSON.parse_string(JSON.stringify(config)),["west"],digest),"route schema survives JSON numeric conversion")
	_check(not Build.valid_routes(config,["west","east"],digest),"missing native region rejected")
	_check(not Build.valid_routes(config,[],digest),"empty route set rejected")
	_check(not Build.valid_routes(config,["west","west"],digest),"duplicate native region rejected")
	_check(not Build.valid_routes(config,["west"],"b".repeat(64)),"stale registry route rejected")
	for pair: Array in [["source","relative/path"],["index","res://wrong.res"],["dedup",1],["footprint_lod","false"]]:
		var bad := config.duplicate(true)
		bad.routes.west[pair[0]]=pair[1]
		_check(not Build.valid_routes(bad,["west"],digest),"malformed native route rejected: "+str(pair[0]))
	var extra := config.duplicate(true)
	extra.routes.east=route
	_check(not Build.valid_routes(extra,["west"],digest),"unregistered extra route rejected")
	var blocks := {"schema":1,"registry_sha256":digest,"region":"west","source":"res://source","joined":"res://joined",
		"candidate":"res://candidate","full":"res://full","plans":"res://plans","audit":"res://joined/saved_audit.json"}
	_check(OwnedBlocks.valid_config(blocks,["west"],digest),"explicit block transfer configuration accepted")
	_check(OwnedBlocks.valid_config(JSON.parse_string(JSON.stringify(blocks)),["west"],digest),"block config accepts JSON schema number")
	_check(not OwnedBlocks.valid_config(blocks,["east"],digest),"unknown block region rejected")
	_check(not OwnedBlocks.valid_config(blocks,["west"],"b".repeat(64)),"stale block registry rejected")
	blocks.plans="relative/plans"
	_check(not OwnedBlocks.valid_config(blocks,["west"],digest),"relative block plan directory rejected")


func _path_lod_contract() -> void:
	var path_lod := preload("res://scripts/tests/build_tokyo_path_lod.gd")
	var geometry := Geometry.new()
	for pair: Array in [[0.22,Color("9c9d8d")],[0.38,Color("9c9d8d")],[0.22,Color.RED]]:
		var y: float = pair[0]
		geometry.quad(Vector3(0,y,0),Vector3(1,y,0),Vector3(1,y,1),Vector3(0,y,1),pair[1])
	var source := geometry.mesh()
	var before: Array = source.get("_surfaces").duplicate(true)
	var result := path_lod.partition(source)
	_check(not result.is_empty() and Indexed.triangles(result.kept)==4 and Indexed.triangles(result.removed)==2,"far paths select only exact semantic height and palette")
	_check(not result.is_empty() and Difference.conserved(source,result.kept,result.removed),"far paths preserve all other packed triangles")
	_check(source.get("_surfaces")==before,"far path partition does not mutate original")
	var indexed := Indexed.pack(source)
	var packed := path_lod.partition(indexed)
	_check(not packed.is_empty() and Difference.conserved(indexed,packed.kept,packed.removed),"far paths also preserve indexed source")
	_check(path_lod.partition(ArrayMesh.new()).kept.get_surface_count()==0,"empty fixed source retained")
	var writer := path_lod.new()
	_check(writer._replace_layer({},ArrayMesh.new(),{},1).is_empty(),"layer writer refuses marked-building mutation")
	source.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,source.surface_get_arrays(0))
	_check(path_lod.partition(source).is_empty(),"unsupported fixed surface layout rejected")


func _guarded_blocks_contract() -> void:
	var guarded := preload("res://scripts/tests/build_tokyo_guarded_blocks.gd")
	_check(guarded.Far.Factory._points([[0,-3560.346923828125]])==guarded.Far.Factory._points([[0,-3560.34692382813]]),"report decimal rounding preserves exact native float32 outline")
	_check(guarded.Far.Factory._points([[0,-3560.346923828125]])!=guarded.Far.Factory._points([[0,-3560.3475]]),"native outline shift is not hidden by broad epsilon")
	var ring := {"outer":[[0,0],[2,0],[2,2],[0,2]],"holes":[],"triangles":[[0,0],[2,0],[2,2],[0,0],[2,2],[0,2]]}
	var raw := {"height_m":6.4,"height_source":"fallback","rings":[ring]}
	var records := {"a":raw,"b":raw.duplicate(true)}
	var group := {"ids":["a","b"],"height_m":6.4,"outer":ring.outer,"triangles":ring.triangles}
	var result := guarded.group_meshes(records,[group],1)
	_check(not result.is_empty() and result.groups==1 and Indexed.triangles(result.removed)==4 and Indexed.triangles(result.added)==2,"guarded uses near block and really saves roof faces")
	_check(not result.is_empty() and is_equal_approx(result.added.get_aabb().position.y,3.2),"guarded retains actual source roof height")
	_check(guarded.group_meshes(records,[group,group],1).is_empty(),"guarded duplicate membership rejected")
	_check(guarded.group_meshes(records,[group],5).is_empty(),"guarded cannot overwrite full near slot")
	records.b.height_m=9.6
	_check(guarded.group_meshes(records,[group],1).is_empty(),"guarded cannot average different source heights")
	records.b.height_m=6.4
	records.b.height_source="levels"
	_check(guarded.group_meshes(records,[group],1).is_empty(),"guarded cannot merge marked buildings")
	records.b.height_source="fallback"
	records.b.kind="industrial"
	_check(guarded.group_meshes(records,[group],1).is_empty(),"guarded cannot merge different palettes")
	records.erase("b")
	_check(guarded.group_meshes(records,[group],1).is_empty(),"guarded unknown source rejected")


func _extension_contract() -> void:
	var catalog: Resource = load("res://scripts/rendering/tokyo_canonical_catalog.gd").new()
	var original: Resource = load("res://resources/maps/tokyo_volume_preview/r34_cells/index.res")
	var bounds: Rect2 = original.bounds
	var rects: Array = original.coverage_rects.duplicate()
	_check(catalog.extension_valid() and catalog.presentation_archive(original)==original,"legacy archive unchanged without extension")
	_check(catalog.presentation_archive(null)==null,"missing presentation archive rejected")
	catalog.regional_extension={"region":"west_residential","bounds":Rect2(-6800,-2700,500,1000),"source_count":76473,
		"registry_sha256":"a".repeat(64),"source_manifest_sha256":"b".repeat(64),"boundary_manifest_sha256":"c".repeat(64)}
	var extended: Resource = catalog.presentation_archive(original)
	_check(catalog.extension_valid() and extended!=original and extended.bounds==bounds.merge(Rect2(-6800,-2700,500,1000)) and extended.source_count==76473,"regional presentation bounds and owner count extended")
	_check(original.bounds==bounds and original.coverage_rects==rects and extended.coverage_rects.size()==rects.size()+1,"shared original archive never mutated")
	_check(extended.source_hash!=original.source_hash,"extension provenance changes presentation identity")
	var old_extension: Dictionary = catalog.regional_extension.duplicate(true)
	catalog.regional_extension.region="west_corridor"
	catalog.regional_extension.bounds=Rect2(-7300,-2700,1000,1000)
	catalog.regional_extension.source_count=80511
	var corridor: Resource = catalog.presentation_archive(original)
	_check(catalog.extension_valid() and corridor!=null and corridor.source_count==80511 and corridor.bounds==bounds.merge(Rect2(-7300,-2700,1000,1000)),"four-region corridor presentation bounds and sources")
	_check(original.bounds==bounds and original.coverage_rects==rects,"corridor does not mutate shared original")
	catalog.regional_extension.source_count=76473
	_check(not catalog.extension_valid(),"corridor cannot reuse old three-region source count")
	catalog.regional_extension.source_count=80511
	catalog.regional_extension.bounds=Rect2(-7300,-2700,500,1000)
	_check(not catalog.extension_valid(),"corridor must include both western strips")
	var northwest_builder := preload("res://scripts/tests/build_tokyo_northwest_catalog.gd")
	_check(northwest_builder.new().build("","")==1,"northwest catalog missing inputs rejected")
	_check(northwest_builder.new().audit_join("","")==1,"northwest catalog audit missing evidence rejected")
	catalog.regional_extension={"region":"west_northwest","bounds":Rect2(-7300,-3700,1000,2000),"source_count":88575,
		"registry_sha256":northwest_builder.REGISTRY_SHA,"source_manifest_sha256":northwest_builder.NATIVE_SHA,"boundary_manifest_sha256":northwest_builder.BOUNDARY_SHA}
	_check(catalog.extension_valid() and catalog.presentation_archive(original).source_count==88575,"exact five-region candidate provenance accepted")
	var old_binding: Dictionary = northwest_builder.native_binding(false)
	var new_binding: Dictionary = northwest_builder.native_binding(true)
	_check(old_binding.directory=="r201-owned-native-c" and old_binding.sha256==northwest_builder.NATIVE_SHA,"old northwest source binding retained")
	_check(new_binding.directory=="r211-owned-native-a" and new_binding.sha256==northwest_builder.COMBINED_SHA and new_binding.audit_sha256!=old_binding.audit_sha256,"combined northwest binds its own certified audit")
	var east_binding: Dictionary = northwest_builder.native_binding(true,true)
	_check(east_binding.directory=="r217-owned-native-a" and east_binding.sha256==northwest_builder.EAST_COMBINED_SHA and east_binding.audit_sha256!=new_binding.audit_sha256,"three-piece native binds independent audit")
	_check(northwest_builder.native_binding(false,true).is_empty(),"east combined requires combined mode")
	var outer_binding: Dictionary = northwest_builder.native_binding(true,true,true)
	var north_binding: Dictionary = northwest_builder.native_binding(true,true,true,true)
	var left_binding: Dictionary = northwest_builder.native_binding(true,true,true,true,true)
	var right_binding: Dictionary = northwest_builder.native_binding(true,true,true,true,true,true)
	var south_binding: Dictionary = northwest_builder.native_binding(true,true,true,true,true,true,true)
	var southwest_binding: Dictionary = northwest_builder.native_binding(true,true,true,true,true,true,true,true)
	_check(southwest_binding.get("directory","")=="r310-owned-native-a","ten-region exact native binding")
	_check(northwest_builder.native_binding(true,true,true,true,true,true,false,true).is_empty(),"ten-region requires southern composition")
	_check(northwest_builder.southwest_kept("","lod0_full",0,null)==null,"historical transfer rejects missing source")
	_check(south_binding.get("directory","")=="r297-owned-native-a" and south_binding.get("sha256","")=="48652d4fe45243908d947c2d793273ba4e7e2fd25abeb86a6930c98527e55c31","south exact native binding")
	_check(northwest_builder.native_binding(true,true,true,true,true,false,true).is_empty() and northwest_builder.native_binding(false,true,true,true,true,true,true).is_empty(),"south requires full nine-region chain")
	_check(right_binding.get("directory","")=="r274-owned-native-a" and right_binding.get("sha256","")=="f4457072407b815990fc2a9cd57fc2762fd080023708bc3f6653b547fbbdd807","nine-region exact native binding")
	_check(northwest_builder.native_binding(true,true,true,true,false,true).is_empty() and northwest_builder.native_binding(false,true,true,true,true,true).is_empty(),"nine-region requires full composition chain")
	_check(left_binding.get("directory")=="r260-owned-native-a" and left_binding.get("sha256")=="3fd5c30f2977993ba99f68133815bf40795cfd2f97470fe6669a3f4fe069bda7","eight-region exact native binding")
	_check(northwest_builder.native_binding(false,true,true,true,true).is_empty() and northwest_builder.native_binding(true,false,true,true,true).is_empty() and northwest_builder.native_binding(true,true,false,true,true).is_empty() and northwest_builder.native_binding(true,true,true,false,true).is_empty(),"eight-region requires full composition chain")
	_check(north_binding.directory=="r247-owned-native-b" and north_binding.audit_sha256=="2eb42c5671850060e051bbd1bce4c8df52a5a10f6d6be2db54f01bf4428bebb9","seven-region binds independent saved audit")
	_check(northwest_builder.native_binding(true,true,false,true).is_empty() and northwest_builder.native_binding(true,false,true,true).is_empty() and northwest_builder.native_binding(false,true,true,true).is_empty(),"seven-region requires full composition chain")
	_check(outer_binding.directory=="r230-owned-native-a" and outer_binding.sha256=="2c939a288876ce091bcfbdf2972652e72111d89bdc22589644c866f1b44f7567" and outer_binding.audit_sha256=="5cf817332ea5d853a0246a91357e13ed09d1aa86526c09566b879bdd160e8c0d","six-region native binds exact saved audit")
	_check(northwest_builder.native_binding(true,false,true).is_empty() and northwest_builder.native_binding(false,true,true).is_empty(),"six-region requires both previous composition flags")
	catalog.regional_extension.source_manifest_sha256=northwest_builder.EAST_COMBINED_SHA
	_check(catalog.extension_valid(),"three-piece exact extension accepted")
	catalog.regional_extension.boundary_manifest_sha256="a".repeat(64)
	_check(not catalog.extension_valid(),"three-piece wrong boundary rejected")
	catalog.regional_extension.boundary_manifest_sha256=northwest_builder.BOUNDARY_SHA
	catalog.regional_extension.source_manifest_sha256=northwest_builder.COMBINED_SHA
	_check(catalog.extension_valid() and catalog.presentation_archive(original).source_count==88575,"combined northwest exact identity accepted")
	catalog.regional_extension.registry_sha256="a".repeat(64)
	_check(not catalog.extension_valid(),"combined northwest wrong registry rejected")
	catalog.regional_extension.registry_sha256=northwest_builder.REGISTRY_SHA
	catalog.regional_extension.source_manifest_sha256="a".repeat(64)
	_check(not catalog.extension_valid(),"unknown northwest native identity rejected")
	catalog.regional_extension.source_manifest_sha256=northwest_builder.COMBINED_SHA
	catalog.regional_extension.boundary_manifest_sha256="a".repeat(64)
	_check(not catalog.extension_valid(),"five-region boundary proof mismatch rejected")
	catalog.regional_extension.boundary_manifest_sha256=northwest_builder.BOUNDARY_SHA
	catalog.regional_extension.bounds=Rect2(-7300,-3700,2000,2000)
	_check(not catalog.extension_valid(),"five-region cannot claim unproduced extra coverage")
	catalog.regional_extension=old_extension
	var six: Dictionary = {"region":"west_outer","bounds":Rect2(-8300,-3700,2000,2000),"source_count":94058,
		"registry_sha256":"e57da4c3ca3e0cddbfb692ec78e6df2a273caf7b0fede082b6f22c8a8624603d",
		"source_manifest_sha256":"2c939a288876ce091bcfbdf2972652e72111d89bdc22589644c866f1b44f7567","boundary_manifest_sha256":northwest_builder.BOUNDARY_SHA}
	catalog.regional_extension=six.duplicate(true)
	var outer: Resource = catalog.presentation_archive(original)
	_check(catalog.extension_valid() and outer!=null and outer.source_count==94058,"six-region exact identity accepted")
	_check(outer.coverage_rects.size()==rects.size()+2 and outer.bounds==bounds.merge(six.bounds),"six-region envelope differs from two actual coverage rectangles")
	var addition_rects: Array = outer.coverage_rects.slice(rects.size())
	_check(addition_rects==[Rect2(-7300,-3700,1000,2000),Rect2(-8300,-3700,1000,1000)],"six-region exact L coverage")
	_check(not addition_rects.any(func(rect: Rect2) -> bool: return rect.has_point(Vector2(-7800,-2200))),"unproduced southwest remains uncovered")
	_check(original.bounds==bounds and original.coverage_rects==rects,"six-region shared original remains unchanged")
	for field: String in ["registry_sha256","source_manifest_sha256","boundary_manifest_sha256"]:
		catalog.regional_extension=six.duplicate(true)
		catalog.regional_extension[field]="a".repeat(64)
		_check(not catalog.extension_valid() and catalog.presentation_archive(original)==null,"six-region rejects mismatched "+field)
	catalog.regional_extension=six.duplicate(true)
	catalog.regional_extension.source_count=88575
	_check(not catalog.extension_valid(),"six-region rejects stale five-region count")
	var seven: Dictionary = {"region":"west_north_seam","bounds":Rect2(-8300,-4700,2000,3000),"source_count":97368,
		"registry_sha256":"6ca1fb5664dd0ce41ff58650d2c50bd7391eb2e23913ec0d4425208c74060204",
		"source_manifest_sha256":"d7f76a7c97f58fa4f566324f33fde079230a8761e34833758970e106bba168e6","boundary_manifest_sha256":northwest_builder.BOUNDARY_SHA}
	catalog.regional_extension=seven.duplicate(true)
	var northern: Resource = catalog.presentation_archive(original)
	_check(catalog.extension_valid() and northern!=null and northern.source_count==97368,"seven-region exact identity accepted")
	var north_rects: Array = northern.coverage_rects.slice(rects.size())
	_check(north_rects==[Rect2(-7300,-3700,1000,2000),Rect2(-8300,-3700,1000,1000),Rect2(-7800,-4700,1000,1000)],"seven-region exact three-part coverage")
	for empty_point: Vector2 in [Vector2(-8100,-4400),Vector2(-6500,-4400),Vector2(-7800,-2200)]:
		_check(not north_rects.any(func(rect: Rect2) -> bool: return rect.has_point(empty_point)),"seven-region envelope gaps remain uncovered")
	_check(northern.bounds==bounds.merge(seven.bounds) and original.bounds==bounds and original.coverage_rects==rects,"seven-region envelope and shared original preserved")
	for field: String in ["registry_sha256","source_manifest_sha256","boundary_manifest_sha256"]:
		catalog.regional_extension=seven.duplicate(true)
		catalog.regional_extension[field]="a".repeat(64)
		_check(not catalog.extension_valid() and catalog.presentation_archive(original)==null,"seven-region rejects mismatched "+field)
	catalog.regional_extension=seven.duplicate(true)
	catalog.regional_extension.source_count=94058
	_check(not catalog.extension_valid(),"seven-region rejects stale six-region count")
	var eight := seven.duplicate(true)
	eight.region="west_north_left"
	eight.source_count=100000
	eight.registry_sha256="07d7bf28673e6472a05211a58a95a1325d9dc9b0c2abf613ea49d12f05dfde09"
	eight.source_manifest_sha256="3fd5c30f2977993ba99f68133815bf40795cfd2f97470fe6669a3f4fe069bda7"
	catalog.regional_extension=eight.duplicate(true)
	var left_archive: Resource = catalog.presentation_archive(original)
	_check(catalog.extension_valid() and left_archive!=null and left_archive.source_count==100000,"eight-region exact identity accepted")
	var left_rects: Array = left_archive.coverage_rects.slice(rects.size())
	_check(left_rects==north_rects+[Rect2(-8300,-4700,500,1000)],"eight-region adds only left coverage")
	_check(left_rects.any(func(rect: Rect2) -> bool: return rect.has_point(Vector2(-8100,-4400))),"left coverage enabled")
	for point: Vector2 in [Vector2(-6500,-4400),Vector2(-7800,-2200)]:
		_check(not left_rects.any(func(rect: Rect2) -> bool: return rect.has_point(point)),"eight-region unbuilt gaps preserved")
	_check(original.bounds==bounds and original.coverage_rects==rects,"eight-region original untouched")
	for field: String in ["registry_sha256","source_manifest_sha256","boundary_manifest_sha256"]:
		catalog.regional_extension=eight.duplicate(true)
		catalog.regional_extension[field]="a".repeat(64)
		_check(not catalog.extension_valid() and catalog.presentation_archive(original)==null,"eight-region rejects mismatched "+field)
	catalog.regional_extension=eight.duplicate(true)
	catalog.regional_extension.source_count=97368
	_check(not catalog.extension_valid(),"eight-region rejects stale source count")
	var nine := eight.duplicate(true)
	nine.region="west_north_right"
	nine.source_count=101235
	nine.registry_sha256="45098e3d30e11470986c93200e8d81be56ff68e6616929baffc3d12e7cfb54b9"
	nine.source_manifest_sha256="f4457072407b815990fc2a9cd57fc2762fd080023708bc3f6653b547fbbdd807"
	catalog.regional_extension=nine.duplicate(true)
	var right_archive: Resource = catalog.presentation_archive(original)
	_check(catalog.extension_valid() and right_archive!=null and right_archive.source_count==101235,"nine-region exact identity accepted")
	var right_rects: Array = right_archive.coverage_rects.slice(rects.size())
	_check(right_rects==left_rects+[Rect2(-6800,-4700,500,1000)],"nine-region adds only right coverage")
	_check(right_rects.any(func(rect: Rect2) -> bool: return rect.has_point(Vector2(-6500,-4400))),"right coverage enabled")
	_check(not right_rects.any(func(rect: Rect2) -> bool: return rect.has_point(Vector2(-7800,-2200))),"nine-region southwest gap preserved")
	_check(original.bounds==bounds and original.coverage_rects==rects,"nine-region original untouched")
	catalog.regional_extension=nine.duplicate(true)
	catalog.regional_extension.source_manifest_sha256="48652d4fe45243908d947c2d793273ba4e7e2fd25abeb86a6930c98527e55c31"
	var south_archive: Resource = catalog.presentation_archive(original)
	_check(catalog.extension_valid() and south_archive!=null and south_archive.coverage_rects==right_archive.coverage_rects,"south blocks preserve nine-region coverage")
	catalog.regional_extension.source_count=101236
	_check(not catalog.extension_valid(),"south rejects source count drift")
	var ten := nine.duplicate(true)
	ten.region="west_southwest"
	ten.source_count=106951
	ten.registry_sha256="67f3e204ecda7a49d6d51f00f2b49a0c8ecfc2b9b4c04a24ba559df8b03b1229"
	ten.source_manifest_sha256="de82a0722298df2f816e7f546353726578c73c9d183015ae017019fe84862a1f"
	ten.boundary_manifest_sha256="a6500e439ac54be0538727b8620e6b030f8489deb73a5b441240fabbf0d6f808"
	catalog.regional_extension=ten.duplicate(true)
	var ten_archive: Resource = catalog.presentation_archive(original)
	_check(catalog.extension_valid() and ten_archive!=null and ten_archive.source_count==106951,"ten-region exact identity accepted")
	_check(ten_archive.coverage_rects==right_archive.coverage_rects+[Rect2(-8300,-2700,1000,1000)],"ten-region adds only produced southwest rectangle")
	_check(original.bounds==bounds and original.coverage_rects==rects,"ten-region original archive untouched")
	for field: String in ["registry_sha256","source_manifest_sha256","boundary_manifest_sha256"]:
		catalog.regional_extension=ten.duplicate(true)
		catalog.regional_extension[field]="a".repeat(64)
		_check(not catalog.extension_valid(),"ten-region rejects mismatched "+field)
	catalog.regional_extension=ten.duplicate(true)
	catalog.regional_extension.source_count=101235
	_check(not catalog.extension_valid(),"ten-region rejects stale owner count")
	for field: String in ["registry_sha256","source_manifest_sha256","boundary_manifest_sha256"]:
		catalog.regional_extension=nine.duplicate(true)
		catalog.regional_extension[field]="a".repeat(64)
		_check(not catalog.extension_valid() and catalog.presentation_archive(original)==null,"nine-region rejects mismatched "+field)
	catalog.regional_extension=nine.duplicate(true)
	catalog.regional_extension.source_count=100000
	_check(not catalog.extension_valid(),"nine-region rejects stale source count")
	catalog.regional_extension=old_extension
	catalog.regional_extension.registry_sha256="g".repeat(64)
	_check(not catalog.extension_valid() and catalog.presentation_archive(original)==null,"nonhex extension identity rejected")
	catalog.regional_extension.erase("registry_sha256")
	_check(not catalog.extension_valid(),"partial extension rejected")
	_check(load("res://scripts/tests/build_tokyo_regional_catalog.gd").can_instantiate(),"regional catalog builder compiles")
	_check(load("res://scripts/tests/build_tokyo_extension_catalog.gd").can_instantiate(),"four-region extension builder compiles")
	_check(load("res://scripts/tests/tokyo_canonical_review.gd").can_instantiate(),"regional actual-route review compiles")
	var review := preload("res://scripts/tests/tokyo_canonical_review.gd")
	var raster := {"current_lod":"detail","target_lod":"detail","transitioning":false,"pending_count":0,"missing_keys":[]}
	_check(review.source_state_ready(raster),"source stable metadata accepted")
	raster.pending_count=1
	_check(not review.source_state_ready(raster),"source still-loading tiles cannot release comparison")
	raster.pending_count=0
	raster.missing_keys=["tile"]
	_check(not review.source_state_ready(raster),"source missing tile cannot release comparison")
	raster.missing_keys=[]
	raster.target_lod="strategic"
	_check(not review.source_state_ready(raster),"source requested LOD not yet current")
	var ready := {"stream":{"pending":0,"failures":{}},"desired_cells":1,"ready_cells":1,"cut_ready":true,"active_cells":1}
	_check(review.ready_at_canvas(Transform2D.IDENTITY,Transform2D.IDENTITY,ready),"ready cut belongs to current camera")
	_check(not review.ready_at_canvas(Transform2D(0,Vector2.ONE),Transform2D.IDENTITY,ready),"previous-camera readiness must not release new-camera capture")
	ready.stream.pending=1
	_check(not review.ready_at_canvas(Transform2D.IDENTITY,Transform2D.IDENTITY,ready),"same-camera pending request still rejects capture")


func _difference_contract() -> void:
	var full := _toy_cell([0,0,1])
	var one := _toy_cell([0])
	var indexed := Indexed.pack(full.meshes[0])
	var before := Difference.Read.corner_digest(indexed)
	var result := Difference.subtract(indexed,one.meshes[0])
	_check(not result.is_empty() and result.removed==2 and Difference.conserved(indexed,result.mesh,one.meshes[0]),"indexed source exact multiplicity subtraction")
	_check(Difference.Read.corner_digest(indexed)==before,"indexed source packed input unchanged")
	var indexed_removed := Indexed.pack(one.meshes[0])
	var other := Difference.subtract(full.meshes[0],indexed_removed)
	_check(not other.is_empty() and Difference.conserved(full.meshes[0],other.mesh,indexed_removed),"unindexed source accepts indexed removal")
	_check(Difference.subtract(indexed,_toy_cell([2]).meshes[0]).is_empty(),"indexed missing face rejected")
	_check(Difference.subtract(indexed,indexed).mesh.get_surface_count()==0,"indexed complete removal empty")
	_check(Difference.subtract(indexed,ArrayMesh.new()).mesh==indexed,"indexed empty removal returns original")
	_check(not Difference.conserved(indexed,one.meshes[0],one.meshes[0]),"decoded independent audit catches missing third face pair")
	var isolated := Geometry.new()
	var first_triangle := Geometry.new()
	for i in 20:
		isolated.triangle(Vector3(i*3,0,0),Vector3(i*3+1,0,0),Vector3(i*3,0,1),Color("80877e"))
	first_triangle.triangle(Vector3.ZERO,Vector3.RIGHT,Vector3.BACK,Color("80877e"))
	var flat := isolated.mesh()
	var delta := first_triangle.mesh()
	var economical := Difference.subtract(flat,delta)
	_check(not economical.is_empty() and economical.mesh.surface_get_array_index_len(0)==0 and Difference.Read.decoded_bytes(economical.mesh)<Difference.Read.decoded_bytes(flat),"isolated far triangles must not grow memory by adding useless indices")
	_check(not economical.is_empty() and Difference.conserved(flat,economical.mesh,delta),"unindexed economical path preserves decoded corners")
	var large := Geometry.new()
	for i in 11000:
		large.quad(Vector3(i,0,0),Vector3(i+1,0,0),Vector3(i+1,0,1),Vector3(i,0,1),Color("80877e"))
	var joined: Array[ArrayMesh] = [large.mesh()]
	var wide := Difference.Join.join(joined)
	var surface: Dictionary = wide.get("_surfaces")[0]
	_check(RenderingServer.mesh_surface_get_format_index_stride(surface.format,surface.vertex_count)==4,"large fixture actually has 32-bit indices")
	var trimmed := Difference.subtract(wide,one.meshes[0])
	_check(not trimmed.is_empty() and Difference.conserved(wide,trimmed.mesh,one.meshes[0]) and Difference.Read.decoded_bytes(trimmed.mesh)<=Difference.Read.decoded_bytes(wide),"32-bit source compacted with corner conservation and bounded bytes")
	_check(load("res://scripts/tests/build_tokyo_boundary_transfer.gd").can_instantiate(),"boundary transfer builder compiles")


func _transfer_contract() -> void:
	var full := _toy_cell([0,0,1])
	var owned := _toy_cell([0,0])
	var candidate := _toy_cell([0,1])
	var backup := _toy_cell([0])
	owned.precision_original = backup.meshes[0]
	owned.precision_max_scale = 0.18*1.08
	owned.precision_triangles = 2
	owned.geometry_bytes = 0
	owned.triangles = 0
	Build.Builder.finish(owned)
	var result := OwnedBlocks.transfer(full,owned,candidate)
	_check(result != null and result.triangles==2 and result.source_ids==owned.source_ids,"transfer preserves merge savings while removing only nonowner faces")
	_check(result != null and result.precision_original==owned.precision_original and result.precision_triangles==2,"transfer retains already-owned precision backup")
	_check(full.triangles==6 and owned.triangles==4 and candidate.triangles==4,"transfer does not mutate input archives")
	candidate.height_hash="changed"
	_check(OwnedBlocks.transfer(full,owned,candidate)==null,"transfer height identity mismatch rejected")
	candidate.height_hash=full.height_hash
	candidate.source_ids=PackedStringArray(["different"])
	_check(OwnedBlocks.transfer(full,owned,candidate)==null,"transfer source identity mismatch rejected")
	candidate.source_ids=full.source_ids
	candidate.meshes[1]=backup.meshes[0]
	_check(OwnedBlocks.transfer(full,owned,candidate)==null,"transfer altered marked buildings rejected")
	_check(OwnedBlocks.transfer(full,owned,_toy_cell([0]))==null,"transfer cannot remove absent nonowner face")
	_check(OwnedBlocks.transfer(full,owned,_toy_cell([0]),true)==null,"cell redistribution still rejects missing nonowner face")
	var larger := _toy_cell([0,0,0,1])
	_check(OwnedBlocks.transfer(full,owned,larger)==null,"legacy transfer still rejects per-cell growth")
	var redistributed := OwnedBlocks.transfer(full,owned,larger,true)
	_check(redistributed!=null and redistributed.triangles==6 and full.triangles-larger.triangles==owned.triangles-redistributed.triangles,"explicit redistribution conserves the exact owner delta")
	_check(OwnedBlocks.transfer(full,_toy_cell([2]),_toy_cell([0,1]))==null,"owned baseline cannot contain unknown faces")


static func _toy_cell(heights: Array) -> Resource:
	var geometry := Geometry.new()
	for height: float in heights:
		geometry.quad(Vector3(0,height,0),Vector3(1,height,0),Vector3(1,height,1),Vector3(0,height,1),Color("80877e"))
	var cell := preload("res://scripts/rendering/tokyo_cell_archive.gd").new()
	cell.cell_id=0
	cell.level=1
	cell.bounds=Rect2(0,0,2,2)
	cell.source_ids=PackedStringArray(["a","b","c"])
	cell.height_hash="test_height_identity"
	var meshes: Array[ArrayMesh] = [geometry.mesh(),ArrayMesh.new()]
	cell.meshes=meshes
	Build.Builder.finish(cell)
	return cell


static func _compare_candidate(baseline: String, candidate: String) -> bool:
	var before: Resource = load(baseline.path_join("index.res"))
	var after: Resource = load(candidate.path_join("index.res"))
	if before == null or after == null or not before.valid() or not after.valid() or before.source_hash != after.source_hash or before.cells.size() != after.cells.size():
		return false
	var count := 0
	for id in before.cells.size():
		var original: Dictionary = before.cells[id]
		var current: Dictionary = after.cells[id]
		# 固定层/最远档/mid不应重新导出；五档只允许输出路径改变。
		var restored: Dictionary = current.duplicate(true)
		for level in range(1,6):
			var a: Resource = ResourceLoader.load(original.levels[level].path,"",ResourceLoader.CACHE_MODE_IGNORE)
			var b: Resource = ResourceLoader.load(current.levels[level].path,"",ResourceLoader.CACHE_MODE_IGNORE)
			if a == null or b == null or not a.valid() or not b.valid() or a.source_ids != b.source_ids or a.height_hash != b.height_hash \
					or a.detail_counts != b.detail_counts or a.triangles != b.triangles or a.geometry_bytes != b.geometry_bytes:
				return false
			for kind in 2:
				if not preload("res://scripts/tests/audit_tokyo_region_sample.gd").same_mesh(a.meshes[kind],b.meshes[kind]):
					return false
			if (a.precision_original == null) != (b.precision_original == null):
				return false
			if a.precision_original != null and not preload("res://scripts/tests/audit_tokyo_region_sample.gd").same_mesh(a.precision_original,b.precision_original):
				return false
			restored.levels[level].path = original.levels[level].path
			count += 1
		if restored != original:
			return false
	print("[Tokyo regional unchanged geometry] packages=",count," fail=0")
	return count == 80


func _check(ok: bool, message: String) -> void:
	if ok:
		_pass+=1
	else:
		_fail+=1
		print("FAIL regional native: ",message)
