extends RefCounted
const Index := preload("res://scripts/rendering/tokyo_cell_index.gd")
const Builder := preload("res://scripts/tests/build_tokyo_cells.gd")
const Factory := preload("res://scripts/experiments/tokyo_volume_preview_factory.gd")
const Geometry := preload("res://scripts/experiments/volume_mesh_factory.gd")
var _fail := 0
var _pass := 0


func run() -> void:
	var surface := Index.new()
	surface.bounds=Rect2(0,0,100,100)
	surface.source_hash="a".repeat(64)+":"+"b".repeat(64)
	for id in 16:
		var levels: Array = []
		for level in 6:
			levels.append({"bytes":0,"triangles":0,"counts":[0,0,0,0]})
		surface.cells.append({"id":id,"bounds":Builder.cell_rect(surface.bounds,id),"source_count":0,"levels":levels})
	_check(not surface.valid(),"empty ordinary building index remains invalid")
	surface.surface_only=true
	_check(surface.valid(),"explicit surface-only index carries no artificial buildings")
	surface.cells[0].levels[0].triangles=1
	_check(not surface.valid(),"surface-only index rejects hidden building triangles")
	surface.cells[0].levels[0].triangles=0
	surface.source_count=1
	_check(not surface.valid(),"surface-only index rejects positive building count")
	surface.source_count=0
	surface.source_hash="invalid"
	_check(not surface.valid(),"surface-only index requires both source digests")
	surface.source_hash="g".repeat(64)+":"+"b".repeat(64)
	_check(not surface.valid(),"surface-only source digests must be hexadecimal")
	surface.source_hash="a".repeat(64)+":"+"b".repeat(64)
	surface.cells[0].levels[0].counts=[0,0,0,1]
	_check(not surface.valid(),"surface-only index rejects hidden deferred sources")
	surface.cells[0].levels[0].counts=[0,0,0,0]
	var region_surface := preload("res://scripts/tests/build_tokyo_region_surface.gd")
	_check(region_surface.region_for("")==Rect2(-6750,-2400,400,400) and region_surface.region_for("west_extension")==Rect2(-7250,-2400,400,400),"independent AO retains old default and explicit second west region")
	_check(not region_surface.region_for("unknown").has_area() and not region_surface.region_for("WEST_EXTENSION").has_area(),"independent AO unknown region fails closed")
	_check(load("res://scripts/tests/build_tokyo_region_surface.gd").can_instantiate(), "regional palette and AO exporter compiles")
	_check(load("res://scripts/tests/tokyo_region_surface_review.gd").can_instantiate(), "regional AO material review compiles")
	_check(Builder.valid_sample_output("C:/fixture/tmp/tokyo-bay-volume/source", "C:/fixture/tmp/tokyo-bay-volume/r120-native"), "sample accepts isolated sibling output")
	_check(not Builder.valid_sample_output("C:/fixture/tmp/tokyo-bay-volume/source", "C:/fixture/resources/r120-native"), "sample rejects production output")
	_check(not Builder.valid_sample_output("C:/fixture/tmp/tokyo-bay-volume/source", "C:/fixture/tmp/tokyo-bay-volume/../r120-native"), "sample rejects traversal")
	_check(not Builder.valid_sample_output("C:/fixture/tmp/tokyo-bay-volume/r120-source", "C:/fixture/tmp/tokyo-bay-volume/r120-source"), "sample rejects source overwrite")
	_check(load("res://scripts/tests/audit_tokyo_region_sample.gd").can_instantiate(), "regional native auditor compiles")
	_check(load("res://scripts/tests/build_tokyo_region_blocks.gd").can_instantiate(), "regional street-block builder compiles")
	_check(load("res://scripts/tests/tokyo_cells_visual.gd").can_instantiate(), "regional sample visual compiles")
	var ao: RefCounted = load("res://scripts/tests/test_tokyo_ao.gd").new()
	ao.run()
	_pass += ao._pass
	_fail += ao._fail
	var shadow: RefCounted = load("res://scripts/tests/test_tokyo_static_shadow.gd").new()
	shadow.run()
	_pass += shadow._pass
	_fail += shadow._fail
	var far: RefCounted = load("res://scripts/tests/test_tokyo_far_clusters.gd").new()
	far.run()
	_pass += far._pass
	_fail += far._fail
	var ground: RefCounted = load("res://scripts/tests/test_tokyo_ground_merge.gd").new()
	ground.run()
	_pass += ground._pass
	_fail += ground._fail
	var canonical: RefCounted = load("res://scripts/tests/test_tokyo_canonical_stream.gd").new()
	canonical.run()
	_pass += canonical._pass
	_fail += canonical._fail
	var gameplay: RefCounted = load("res://scripts/tests/test_tokyo_gameplay_volume.gd").new()
	gameplay.run()
	_pass += gameplay._pass
	_fail += gameplay._fail
	var reuse: RefCounted = load("res://scripts/tests/test_tokyo_cut_reuse.gd").new()
	reuse.run()
	_pass += reuse._pass
	_fail += reuse._fail
	var cluster_stream: RefCounted = load("res://scripts/tests/test_tokyo_cluster_stream.gd").new()
	cluster_stream.run()
	_pass += cluster_stream._pass
	_fail += cluster_stream._fail
	var cluster_test: RefCounted = load("res://scripts/tests/test_tokyo_cluster_pages.gd").new()
	cluster_test.run()
	_pass += cluster_test._pass
	_fail += cluster_test._fail
	_check(load("res://scripts/tests/export_tokyo_roof_ownership.gd").can_instantiate(), "native roof source audit compiles")
	var lod_spatial: RefCounted = load("res://scripts/tests/test_tokyo_lod_spatial_pages.gd").new()
	lod_spatial.run()
	_pass += lod_spatial._pass
	_fail += lod_spatial._fail
	var stream_test: RefCounted = load("res://scripts/tests/test_tokyo_hierarchical_stream.gd").new()
	stream_test.run()
	_pass += stream_test._pass
	_fail += stream_test._fail
	var hierarchy: RefCounted = load("res://scripts/tests/test_tokyo_hierarchical_pages.gd").new()
	hierarchy.run()
	_pass += hierarchy._pass
	_fail += hierarchy._fail
	var spatial: RefCounted = load("res://scripts/tests/test_tokyo_spatial_pages.gd").new()
	spatial.run()
	_pass += spatial._pass
	_fail += spatial._fail
	_check(load("res://scripts/tests/tokyo_shell_review.gd").can_instantiate(), "isolated middle-near shell review compiles")
	var coastal := preload("res://scripts/tests/test_tokyo_coastal_cells.gd").new()
	coastal.run()
	_pass += coastal._pass
	_fail += coastal._fail
	var palette := preload("res://scripts/tests/test_tokyo_palette.gd").new()
	palette.run()
	_pass += palette._pass
	_fail += palette._fail
	var area := preload("res://scripts/tests/test_tokyo_area_cells.gd").new()
	area.run()
	_pass += area._pass
	_fail += area._fail
	var pairing := preload("res://scripts/tests/test_tokyo_cell_pairing.gd").new()
	pairing.run()
	_pass += pairing._pass
	_fail += pairing._fail
	var indexed_tests := preload("res://scripts/tests/test_tokyo_indexed_mesh.gd").new()
	indexed_tests.run()
	_fail += indexed_tests._fail
	_pass += indexed_tests._pass
	var regional_tests := preload("res://scripts/tests/test_tokyo_regional_ownership.gd").new()
	regional_tests.run()
	_fail += regional_tests._fail
	_pass += regional_tests._pass
	_test_regional_archive()
	_test_joined_union_archive()
	_test_precision_archive()
	_test_joined_paths()
	_test_joined_archive()
	var duplicate_tests := preload("res://scripts/tests/test_tokyo_duplicate_outline.gd").new()
	duplicate_tests.run()
	_fail += duplicate_tests._fail
	_pass += duplicate_tests._pass
	var depth_tests := preload("res://scripts/tests/test_tokyo_shadow_depth.gd").new()
	depth_tests.run()
	_fail += depth_tests._fail
	_pass += depth_tests._pass
	var dome_tests := preload("res://scripts/tests/test_tokyo_dome_roof.gd").new()
	dome_tests.run()
	_fail += dome_tests._fail
	_pass += dome_tests._pass
	_check(load("res://scripts/rendering/tokyo_cells_overlay.gd").can_instantiate(), "asynchronous overlay compiles")
	_check(load("res://scripts/tests/tokyo_cells_lifecycle_case.gd").can_instantiate(), "asynchronous lifecycle compiles")
	_check(load("res://scripts/tests/tokyo_cells_runtime_visual.gd").can_instantiate(), "asynchronous runtime Visual compiles")
	var visual: GDScript = load("res://scripts/tests/tokyo_cells_visual.gd")
	_check(visual != null and visual.can_instantiate(), "visual entry compiles before launching a window")
	_test_partition()
	_test_clip()
	_test_ring_levels()
	_test_relief()
	_test_yokohama()
	_test_tagged_roofs()
	_test_dome_archive()
	_test_duplicate_archive()
	_test_layer_bounds()
	_test_mid_relief()
	_test_density_partition()
	_test_density_partition(true)
	_test_density_partition(true, true)
	_test_density_partition(true, false, 20)
	_test_adaptive_archive()
	_test_adaptive_archive("r15_cells")
	_test_adaptive_archive("r15b_cells")
	_test_adaptive_archive("r15c_cells")
	_test_north_coast_archive()
	_test_rotated_view()
	var combat: GDScript = load("res://scripts/tests/tokyo_volume_combat_runner.gd")
	_check(combat.cell_peak_within_budget({"max_transition_triangles": 240000}), "submission budget includes exact 240k boundary")
	_check(not combat.cell_peak_within_budget({"max_transition_triangles": 240001, "triangles": 100000}), "low final count cannot conceal over-budget moving peak")
	_check(not combat.cell_peak_within_budget({}), "missing peak telemetry fails closed")
	var index: Resource = load(Index.PATH)
	_check(index != null and index.valid(), "lightweight cell index valid")
	if index == null or not index.valid():
		return
	_check(index.source_count == 17077, "R5B complete source population preserved")
	var counts := PackedInt32Array([0, 0, 0, 0, 0, 0])
	var totals := PackedInt64Array([0, 0, 0, 0, 0, 0])
	var bytes := PackedInt64Array([0, 0, 0, 0, 0, 0])
	var seen: Dictionary = {}
	for entry: Dictionary in index.cells:
		var physical_guard := float(entry.get("max_height_px", 0.0)) * (sin(deg_to_rad(38.0)) + 1.0 / tan(deg_to_rad(50.0)))
		_check(float(entry.get("visibility_margin", 0.0)) > physical_guard, "visibility includes tilted roof and longest shadow")
		var fixed: Resource = ResourceLoader.load(entry.fixed, "", ResourceLoader.CACHE_MODE_IGNORE)
		_check(fixed != null and fixed.valid() and fixed.level == -1, "fixed cell %d valid" % entry.id)
		if fixed == null:
			continue
		var contained := true
		var upward := true
		for mesh: ArrayMesh in fixed.meshes:
			if mesh.get_surface_count() == 0:
				continue
			for point: Vector3 in mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
				contained = contained and (entry.bounds as Rect2).grow(0.002).has_point(Vector2(point.x, point.z))
			for normal: Vector3 in mesh.surface_get_arrays(0)[Mesh.ARRAY_NORMAL]:
				upward = upward and normal.y > 0.99
		_check(contained, "fixed geometry stays in cell %d" % entry.id)
		_check(upward, "fixed ground/roads face upward in cell %d" % entry.id)
		var expected_ids := PackedStringArray()
		var expected_hash := ""
		var previous_triangles := -1
		for level in 6:
			var cell: Resource = ResourceLoader.load(entry.levels[level].path, "", ResourceLoader.CACHE_MODE_IGNORE)
			_check(cell != null and cell.valid() and cell.cell_id == entry.id and cell.level == level, "cell %d level %d valid" % [entry.id, level])
			if cell == null:
				continue
			if level == 0:
				expected_ids = cell.source_ids
				expected_hash = cell.height_hash
				for identity: String in cell.source_ids:
					_check(not seen.has(identity), "unique ownership " + identity, false)
					seen[identity] = int(entry.id)
			_check(cell.source_ids == expected_ids and cell.height_hash == expected_hash, "same identities/heights across LOD %d/%d" % [entry.id, level])
			_check(cell.triangles >= previous_triangles, "detail triangle monotonic %d/%d" % [entry.id, level])
			previous_triangles = cell.triangles
			var accounted := 0
			for number: int in cell.detail_counts:
				accounted += number
			_check(accounted == cell.source_ids.size(), "no source lost to LOD %d/%d" % [entry.id, level])
			counts[level] += accounted
			totals[level] += cell.triangles + fixed.triangles
			bytes[level] += cell.geometry_bytes + fixed.geometry_bytes
	_check(seen.size() == 17077, "all source ids owned once")
	_check(seen.get("r4856156", -1) == seen.get("r4856159", -2), "Tokyo Station dome part shares parent owner")
	for level in 6:
		_check(counts[level] == 17077, "all population at level %d" % level)
		_check(bytes[level] < 96 * 1024 * 1024, "one-level whole-region memory below 96 MiB")
	_check(index.visible_cells(Rect2(10000, 10000, 20, 20)).is_empty(), "offregion zero selected cells")
	_check(index.visible_cells(index.bounds).size() == 16, "overview retains all cells")
	var close_cells: PackedInt32Array = index.visible_cells(Rect2(-190, -12640, 320, 180))
	_check(close_cells.size() > 0 and close_cells.size() < 16, "close view omits only nonintersecting cell bounds")
	print("[Tokyo cells] full-region triangles=", totals, " geometry_bytes=", bytes, " close_cells=", close_cells)
	print("[Tokyo cells test] pass=", _pass, " fail=", _fail)


func _test_joined_union_archive() -> void:
	var merger: GDScript = load("res://scripts/tests/build_tokyo_joined_cells.gd")
	_check(merger.can_instantiate(), "R26 native merger compiles")
	var first := Geometry.new()
	var second := Geometry.new()
	first.triangle(Vector3.ZERO, Vector3(1, 2, 0), Vector3(0, 3, 1), Color.RED)
	second.triangle(Vector3(2, 4, 0), Vector3(3, 5, 0), Vector3(2, 6, 1), Color.BLUE)
	var merged: ArrayMesh = merger.merge_meshes([first.mesh(), ArrayMesh.new(), second.mesh()])
	_check(_meshes_sum(merged, [first.mesh(), second.mesh()]), "R26 merger preserves vertices normals colors and empty input")
	var entries := [{"id": 0, "bounds": Rect2(0, 0, 1, 1)}, {"id": 1, "bounds": Rect2(8, 0, 1, 1)},
		{"id": 2, "bounds": Rect2(1, 0, 1, 1)}, {"id": 3, "bounds": Rect2(9, 0, 1, 1)}]
	var pairs: Array = merger.pair_entries(entries)
	_check(pairs == merger.pair_entries(entries) and pairs.size() == 2 and pairs[0][0].id == 0 and pairs[0][1].id == 2,
		"R26 deterministic pairing prefers adjacent extent without dropping inputs")
	var path := "res://resources/maps/tokyo_volume_preview/r26b_cells/index.res"
	if not ResourceLoader.exists(path):
		return
	var current: Resource = load(path)
	_check(current.valid() and current.cells.size() == 16 and current.source_count == 69775, "R26 complete self-contained 16-cell union")
	_check(current.coverage_rects == [Rect2(-6300, -1700, 2000, 2000), Rect2(-6300, -3700, 4000, 2000)], "R26 preserves L-shaped coverage instead of filling bounding box")
	var seen: Dictionary = {}
	var consumed: Dictionary = {}
	for entry: Dictionary in current.cells:
		var previous: Resource = load(current.joined_sources[entry.region].index)
		var parts: Array = []
		for id: int in entry.part_ids:
			var key := "%s/%d" % [entry.region, id]
			_check(not consumed.has(key), "R26 input cell consumed once", false)
			consumed[key] = true
			parts.append(previous.cells[id])
		var fixed: Resource = load(entry.fixed)
		_check(_meshes_sum(fixed.meshes[0], [load(parts[0].fixed).meshes[0], load(parts[1].fixed).meshes[0]]), "R26 exact fixed triangle union without new ground")
		var inside := true
		if fixed.meshes[0].get_surface_count() > 0:
			for point: Vector3 in fixed.meshes[0].surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
				var p := Vector2(point.x, point.z)
				inside = inside and ((current.coverage_rects[0] as Rect2).grow(0.002).has_point(p) or (current.coverage_rects[1] as Rect2).grow(0.002).has_point(p))
		_check(inside, "R26 no ground vertices in unmade southeast corner")
		var identities := PackedStringArray()
		var heights := ""
		for slot in 7:
			var cell: Resource = ResourceLoader.load(entry.mid.path if slot == 6 else entry.levels[slot].path, "", ResourceLoader.CACHE_MODE_IGNORE)
			var originals: Array = []
			for part: Dictionary in parts:
				originals.append(ResourceLoader.load(part.mid.path if slot == 6 else part.levels[slot].path, "", ResourceLoader.CACHE_MODE_IGNORE))
			_check(cell.valid(), "R26 native package structural validity")
			if slot == 0:
				identities = cell.source_ids
				heights = cell.height_hash
				for identity: String in identities:
					_check(not seen.has(identity), "R26 unique global source identity", false)
					seen[identity] = true
			_check(cell.source_ids == identities and cell.height_hash == heights, "R26 identities and height hash unchanged across seven packages")
			var counts := 0
			for number: int in cell.detail_counts:
				counts += number
			_check(counts == identities.size(), "R26 detail accounting retains all owner records")
			for kind in 2:
				_check(_meshes_sum(cell.meshes[kind], [originals[0].meshes[kind], originals[1].meshes[kind]]), "R26 building triangles normals colors exactly conserved")
			var actual_bytes := Builder.mesh_bytes(cell.meshes[0]) + Builder.mesh_bytes(cell.meshes[1])
			if cell.precision_original != null:
				var guards: Array = []
				for original: Resource in originals:
					guards.append(original.precision_original if original.precision_original != null else original.meshes[0])
				_check(_meshes_sum(cell.precision_original, guards), "R26 merged precision original is complete")
				actual_bytes += Builder.mesh_bytes(cell.precision_original)
			_check(actual_bytes == cell.geometry_bytes, "R26 merged precision bytes counted in streaming budget")
	_check(consumed.size() == 32 and seen.size() == 69775, "R26 complete two-region source and fixed coverage")
	print("[R26 native union] sources=", seen.size(), " input_cells=", consumed.size())


func _meshes_sum(current: ArrayMesh, originals: Array) -> bool:
	var expected: Dictionary = {}
	var actual: Dictionary = {}
	for mesh: ArrayMesh in originals:
		_add_mesh_signature(expected, mesh)
	_add_mesh_signature(actual, current)
	if actual != expected and OS.get_environment("AGL_TOKYO_MERGE_AUDIT") == "1" and current.get_surface_count() > 0:
		var arrays := current.surface_get_arrays(0)
		var offset := 0
		var deltas := Vector3.ZERO
		for original: ArrayMesh in originals:
			if original.get_surface_count() == 0:
				continue
			var source_arrays := original.surface_get_arrays(0)
			for i in source_arrays[Mesh.ARRAY_VERTEX].size():
				deltas.x = maxf(deltas.x, (arrays[Mesh.ARRAY_VERTEX][offset + i] as Vector3).distance_to(source_arrays[Mesh.ARRAY_VERTEX][i]))
				deltas.y = maxf(deltas.y, (arrays[Mesh.ARRAY_NORMAL][offset + i] as Vector3).distance_to(source_arrays[Mesh.ARRAY_NORMAL][i]))
				deltas.z = maxf(deltas.z, (arrays[Mesh.ARRAY_COLOR][offset + i] as Color).r - (source_arrays[Mesh.ARRAY_COLOR][i] as Color).r)
			offset += source_arrays[Mesh.ARRAY_VERTEX].size()
		print("[R26 merge channel delta] ", deltas)
	return actual == expected


func _test_regional_archive() -> void:
	var fixture: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://scripts/tests/fixtures/tokyo_r25_nonowners.json"))
	for region: String in ["yokohama", "north_coast"]:
		var path := "res://resources/maps/tokyo_volume_preview/r25_%s_cells/index.res" % region
		if not ResourceLoader.exists(path):
			continue # 构建前只验证来源门；落盘后必须验证完整七档和原形兜底。
		var current: Resource = load(path)
		var previous: Resource = load("res://resources/maps/tokyo_volume_preview/%s/index.res" % ("r19_cells" if region == "yokohama" else "r22_cells"))
		_check(not current.valid() and current.valid(fixture.registry_sha256), "R25 joined-only archive fail-closed and digest-bound")
		_check(current.source_count == previous.source_count and current.bounds == previous.bounds, "R25 full source population and extent preserved")
		var records: Dictionary = {}
		for raw: Dictionary in fixture.regions[region]:
			records[raw.id] = raw
		var expected_ids := PackedStringArray(records.keys())
		expected_ids.sort()
		_check(current.regional_nonowner_ids == expected_ids, "R25 exact independent nonowner source set")
		var total_removed := PackedInt64Array([0, 0, 0, 0, 0, 0, 0])
		for id in 16:
			var entry: Dictionary = current.cells[id]
			var old: Dictionary = previous.cells[id]
			_check(entry.bounds == old.bounds and entry.content_bounds == old.content_bounds and entry.max_height_px == old.max_height_px,
				"R25 partition and conservative height bounds retained")
			_check(_same_mesh(load(entry.fixed).meshes[0], load(old.fixed).meshes[0]), "R25 fixed ground roads coast exactly unchanged")
			for slot in 7:
				var cell: Resource = ResourceLoader.load(entry.mid.path if slot == 6 else entry.levels[slot].path, "", ResourceLoader.CACHE_MODE_IGNORE)
				var reference: Resource = ResourceLoader.load(old.mid.path if slot == 6 else old.levels[slot].path, "", ResourceLoader.CACHE_MODE_IGNORE)
				_check(cell.valid() and cell.source_ids == reference.source_ids and cell.height_hash == reference.height_hash,
					"R25 every LOD retains source ids and heights")
				var removed_low := Geometry.new()
				var removed_known := Geometry.new()
				var removed_original := Geometry.new()
				var deferred := 0
				for identity: String in cell.source_ids:
					if not records.has(identity):
						continue
					deferred += 1
					var raw: Dictionary = records[identity]
					var scale_value: float = 1.0 if slot == 6 and raw.height_source == "fallback" else Index.LEVELS.SCALES[4 if slot == 6 else slot]
					var detail := Builder.detail_level(raw, scale_value, true)
					if raw.height_source == "fallback":
						Factory._add_ring_building(removed_original, raw, float(raw.height_m) * 0.5, detail)
					var record := raw
					if slot < 4 and detail == 2 and raw.get("footprint_lod", {}).has(str(slot)):
						record = raw.duplicate()
						record.rings = raw.footprint_lod[str(slot)].rings
					Factory._add_ring_building(removed_low if raw.height_source == "fallback" else removed_known, record, float(raw.height_m) * 0.5, detail)
				_check(cell.detail_counts[3] == reference.detail_counts[3] + deferred, "R25 nonowner records deferred rather than deleted")
				_check(_mesh_subtracts(reference.meshes[0], cell.meshes[0], removed_low.mesh()), "R25 low triangles remove only nonowner source volumes")
				_check(_mesh_subtracts(reference.meshes[1], cell.meshes[1], removed_known.mesh()), "R25 tagged triangles remove only nonowner source volumes")
				if slot < 4 and reference.precision_original != null:
					_check(_mesh_subtracts(reference.precision_original, cell.precision_original if cell.precision_original != null else cell.meshes[0], removed_original.mesh()),
						"R25 precision fallback cannot resurrect cross-region duplicate")
				total_removed[slot] += reference.triangles - cell.triangles
		for count: int in total_removed:
			_check(count > 0, "R25 every package actually omits duplicate geometry")
		print("[R25 native ownership] region=", region, " removed_triangles=", total_removed, " nonowners=", records.size())


func _mesh_subtracts(original: ArrayMesh, current: ArrayMesh, removed: ArrayMesh) -> bool:
	if removed.get_surface_count() == 0:
		return _same_mesh(original, current)
	var expected: Dictionary = {}
	var actual: Dictionary = {}
	_add_mesh_signature(expected, original)
	_add_mesh_signature(actual, current)
	_add_mesh_signature(actual, removed)
	return actual == expected


func _test_precision_archive() -> void:
	var path := "res://resources/maps/tokyo_volume_preview/r22_cells/index.res"
	if not ResourceLoader.exists(path):
		return
	var current: Resource = load(path)
	var previous: Resource = load("res://resources/maps/tokyo_volume_preview/r21_cells/index.res")
	_check(current.valid() and current.source_count == previous.source_count and current.bounds == previous.bounds,
		"R22 complete regional population and extent unchanged")
	var saved := PackedInt64Array([0, 0, 0, 0])
	for id in 16:
		var entry: Dictionary = current.cells[id]
		var old: Dictionary = previous.cells[id]
		_check(entry.bounds == old.bounds and entry.content_bounds == old.content_bounds and entry.max_height_px == old.max_height_px,
			"R22 source partition and original height bounds retained")
		_check(_same_mesh(load(entry.fixed).meshes[0], load(old.fixed).meshes[0]), "R22 roads ground water fixed mesh byte-identical")
		var previous_triangles := -1
		for slot in 7:
			var cell: Resource = ResourceLoader.load(entry.mid.path if slot == 6 else entry.levels[slot].path, "", ResourceLoader.CACHE_MODE_IGNORE)
			var old_cell: Resource = ResourceLoader.load(old.mid.path if slot == 6 else old.levels[slot].path, "", ResourceLoader.CACHE_MODE_IGNORE)
			_check(cell.valid() and cell.source_ids == old_cell.source_ids and cell.height_hash == old_cell.height_hash
				and cell.detail_counts == old_cell.detail_counts, "R22 every source height and detail classification retained")
			_check(_same_mesh(cell.meshes[1], old_cell.meshes[1]), "R22 tagged-height buildings never simplified")
			var actual_bytes := 0
			for mesh: ArrayMesh in cell.meshes:
				actual_bytes += Builder.mesh_bytes(mesh)
			if cell.precision_original != null:
				actual_bytes += Builder.mesh_bytes(cell.precision_original)
				_check(slot < 4 and _same_mesh(cell.precision_original, old_cell.meshes[0]), "R22 resident precision fallback equals original mesh exactly")
				_check(cell.precision_triangles == Factory._triangles(cell.precision_original), "R22 fallback telemetry matches actual mesh")
			_check(cell.geometry_bytes == actual_bytes, "R22 original fallback fully included in streaming memory accounting")
			if slot >= 4 or cell.precision_original == null:
				_check(_same_mesh(cell.meshes[0], old_cell.meshes[0]), "R22 near and unchanged low layers byte-identical")
			if slot < 4:
				saved[slot] += old_cell.triangles - cell.triangles
			if slot < 6:
				_check(cell.triangles >= previous_triangles, "R22 more distant package never has higher submission count")
				previous_triangles = cell.triangles
	for count: int in saved:
		_check(count > 0, "R22 real far package reduces roof triangles without losing sources")
	print("[R22 native savings] ", saved)


func _test_joined_paths() -> void:
	var points := PackedVector2Array([Vector2(0, 0), Vector2(10, 0), Vector2(10, 10)])
	var old := Geometry.new()
	var legacy := Geometry.new()
	Factory._ribbon(old, points, 2, 0.43, Factory.ROAD_MAJOR)
	Factory._path_ribbon(legacy, {}, "surface", points, 2, 0.43, Factory.ROAD_MAJOR)
	_check(_same_mesh(old.mesh(), legacy.mesh()), "R21 legacy path remains byte-identical without prepared data")
	var polygon := PackedVector2Array([Vector2(0,-1), Vector2(11,-1), Vector2(11,10), Vector2(9,10), Vector2(9,1), Vector2(0,1)])
	var values: Array = []
	for id: int in Geometry2D.triangulate_polygon(polygon):
		values.append([polygon[id].x, polygon[id].y])
	var prepared := {"joined_strokes": {"surface": {"width": 2, "triangles": values}}}
	var joined := Geometry.new()
	Factory._path_ribbon(joined, prepared, "surface", points, 2, 0.43, Factory.ROAD_MAJOR)
	var mesh: ArrayMesh = joined.mesh()
	var arrays := mesh.surface_get_arrays(0)
	var preserved := true
	var covers_corner := false
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	for id in vertices.size():
		preserved = preserved and is_equal_approx(vertices[id].y, 0.43) \
			and arrays[Mesh.ARRAY_NORMAL][id].y > 0.99 and arrays[Mesh.ARRAY_COLOR][id].is_equal_approx(Factory.ROAD_MAJOR)
	for id in range(0, vertices.size(), 3):
		var face := PackedVector2Array()
		for offset in 3:
			face.append(Vector2(vertices[id + offset].x, vertices[id + offset].z))
		covers_corner = covers_corner or Geometry2D.is_point_in_polygon(Vector2(10.8, -0.8), face)
	_check(preserved and covers_corner, "R21 prepared native road covers outer wedge with original elevation/color/upward normals")
	_check(absf(Builder.mesh_area(mesh) - 40.0) < 0.0001, "R21 native corner fixture has no extra overlapping area")


func _test_joined_archive() -> void:
	var path := "res://resources/maps/tokyo_volume_preview/r21_cells/index.res"
	if not ResourceLoader.exists(path):
		return
	var current: Resource = load(path)
	var previous: Resource = load("res://resources/maps/tokyo_volume_preview/r20_cells/index.res")
	_check(current.valid() and current.source_count == previous.source_count and current.bounds == previous.bounds,
		"R21 retains entire R20 population and area")
	var fixed_changed := false
	for id in 16:
		var entry: Dictionary = current.cells[id]
		var old: Dictionary = previous.cells[id]
		_check(entry.bounds == old.bounds and entry.content_bounds == old.content_bounds and entry.max_height_px == old.max_height_px,
			"R21 cell cuts and height protection unchanged")
		fixed_changed = fixed_changed or not _same_mesh(load(entry.fixed).meshes[0], load(old.fixed).meshes[0])
		for slot in 7:
			var cell: Resource = load(entry.mid.path if slot == 6 else entry.levels[slot].path)
			var old_cell: Resource = load(old.mid.path if slot == 6 else old.levels[slot].path)
			_check(cell.source_ids == old_cell.source_ids and cell.height_hash == old_cell.height_hash
				and cell.triangles == old_cell.triangles and cell.detail_counts == old_cell.detail_counts,
				"R21 every building identity height and detail count unchanged")
			for layer in cell.meshes.size():
				_check(_same_mesh(cell.meshes[layer], old_cell.meshes[layer]), "R21 every building vertex normal and color unchanged")
	_check(fixed_changed, "R21 actual fixed meshes include new continuous strokes")


func _test_north_coast_archive() -> void:
	var path := "res://resources/maps/tokyo_volume_preview/r20_cells/index.res"
	if not ResourceLoader.exists(path):
		return
	var index: Resource = load(path)
	_check(index.valid() and index.source_count == 53857 and index.bounds == Rect2(-6300, -3700, 4000, 2000),
		"R20 complete north-coast source and intended bounds")
	var seen: Dictionary = {}
	var area := 0.0
	var fixed_area := 0.0
	var disjoint := true
	for entry: Dictionary in index.cells:
		area += (entry.bounds as Rect2).get_area()
		for prior in range(int(entry.id)):
			disjoint = disjoint and not (entry.bounds as Rect2).intersects(index.cells[prior].bounds)
		var fixed: Resource = ResourceLoader.load(entry.fixed, "", ResourceLoader.CACHE_MODE_IGNORE)
		_check(fixed.valid() and fixed.level == -1 and fixed.triangles == entry.fixed_triangles,
			"R20 native fixed geometry metadata")
		fixed_area += Builder.mesh_area(fixed.meshes[0])
		var ids := PackedStringArray()
		var height_hash := ""
		for slot in 7:
			var descriptor: Dictionary = entry.mid if slot == 6 else entry.levels[slot]
			var cell: Resource = ResourceLoader.load(descriptor.path, "", ResourceLoader.CACHE_MODE_IGNORE)
			_check(cell.valid() and cell.cell_id == entry.id and cell.level == (4 if slot == 6 else slot)
				and cell.triangles == descriptor.triangles, "R20 six LOD and mid resources match index")
			if slot == 0:
				ids = cell.source_ids
				height_hash = cell.height_hash
				for identity: String in ids:
					_check(not seen.has(identity), "R20 unique regional source owner " + identity, false)
					seen[identity] = entry.id
			_check(cell.source_ids == ids and cell.height_hash == height_hash and cell.height_hash == descriptor.height_hash,
				"R20 all seven packages preserve identities and height hash")
			var accounted := 0
			for count: int in cell.detail_counts:
				accounted += count
			_check(accounted == ids.size(), "R20 LOD abstraction accounts for every source")
			for mesh: ArrayMesh in cell.meshes:
				_check(mesh.get_surface_count() == 0 or mesh.get_aabb().end.y <= float(entry.max_height_px) + 0.002,
					"R20 geometry stays below declared source-height protection")
	_check(seen.size() == 53857 and disjoint and absf(area - index.bounds.get_area()) < 0.01,
		"R20 source ownership and non-overlapping full regional partition")
	_check(absf(fixed_area - 16777247.1140538) < 2.0, "R20 clipped fixed geometry preserves measured source surface area")


func _test_rotated_view() -> void:
	var overlay: GDScript = load("res://scripts/rendering/tokyo_cells_overlay.gd")
	var logical := Vector2(1600, 900)
	for degrees in range(0, 360, 15):
		var canvas := Transform2D(deg_to_rad(degrees), logical * 0.5)
		var inverse := canvas.affine_inverse()
		var view := Rect2(inverse * Vector2.ZERO, Vector2.ZERO)
		for corner: Vector2 in [Vector2(logical.x, 0), logical, Vector2(0, logical.y)]:
			view = view.expand(inverse * corner)
		for pixel: Vector2 in [Vector2.ZERO, logical, Vector2(logical.x, 0), Vector2(0, logical.y), logical * 0.5]:
			var point := inverse * pixel
			_check(overlay.intersects_view(Rect2(point - Vector2.ONE, Vector2.ONE * 2), view, canvas, logical),
				"R14 edge and center coverage retained at actual rotated view")
		_check(not overlay.intersects_view(Rect2(Vector2(10000, 10000), Vector2.ONE), view, canvas, logical),
			"R14 distant rectangle rejected")
		if degrees % 90 == 45:
			var corner_box := Rect2(view.position + Vector2.ONE, Vector2.ONE * 2)
			_check(corner_box.intersects(view) and not overlay.intersects_view(corner_box, view, canvas, logical),
				"R14 rejects false-positive corner of broad world view")
	var crossing := Rect2(-1000, -1, 2000, 2)
	_check(overlay.intersects_view(crossing, Rect2(-800, -450, 1600, 900), Transform2D(0, logical * 0.5), logical),
		"R14 crossing slab retained without an interior endpoint")


func _test_density_partition(coverage: bool = false, batch_guard: bool = false, cut_steps: int = 10) -> void:
	var records: Array = []
	for id in 32:
		var x := float(id % 8) * 4.0
		var y := float(id / 8) * 4.0
		var outer := [[x, y], [x + 2, y], [x + 2, y + 2], [x, y + 2]]
		records.append({"id": str(id), "height_m": 6.4, "height_source": "fallback", "parents": [],
			"rings": [{"outer": outer, "holes": [], "triangles": [outer[0], outer[1], outer[2], outer[0], outer[2], outer[3]]}]})
	records[1].parents = [records[0].id]
	if coverage:
		records[31].height_m = 120.0
		records[31].height_source = "height"
		records[30].height_m = 32.0
		var atoms := Builder._partition_atoms(records)
		_check(Builder._coverage_cost(atoms, true) > Builder._coverage_cost(atoms), "R15B whole-layer tallest roof guard exceeds per-building union estimate")
	var bounds := Rect2(0, 0, 100, 100)
	var rectangles := Builder.coverage_rects(records, bounds, batch_guard, cut_steps) if coverage else Builder.adaptive_rects(records, bounds)
	records.reverse()
	var reversed := Builder.coverage_rects(records, bounds, batch_guard, cut_steps) if coverage else Builder.adaptive_rects(records, bounds)
	_check(rectangles == reversed, "density/coverage split deterministic independent of source order")
	_check(rectangles.size() == 16, "R13 retains 16 cells")
	var total := 0.0
	var disjoint := true
	for i in rectangles.size():
		total += rectangles[i].get_area()
		for j in range(i):
			disjoint = disjoint and not rectangles[i].intersects(rectangles[j])
	_check(disjoint and is_equal_approx(total, bounds.get_area()), "R13 density cells exactly partition land and empty sea")
	var owners := Builder.partition(records, bounds, rectangles)
	var together := false
	for group: Array in owners:
		var ids := PackedStringArray()
		for raw: Dictionary in group:
			ids.append(raw.id)
		together = together or ("0" in ids and "1" in ids)
	_check(together, "R13 parent/part connected group never split")
	if coverage:
		var empty := Builder.coverage_rects([], bounds, batch_guard, cut_steps)
		var empty_area := 0.0
		for rect: Rect2 in empty:
			empty_area += rect.get_area()
		_check(empty.size() == 16 and is_equal_approx(empty_area, bounds.get_area()), "R15 empty sea remains complete and finitely partitioned")
		var total_sources := 0
		for group: Array in owners:
			total_sources += group.size()
		_check(total_sources == records.size(), "R15 all source records assigned exactly once")


func _add_mesh_signature(result: Dictionary, mesh: ArrayMesh) -> void:
	if mesh.get_surface_count() == 0:
		return
	var arrays := mesh.surface_get_arrays(0)
	var vertices: PackedByteArray = arrays[Mesh.ARRAY_VERTEX].to_byte_array()
	var normals: PackedByteArray = arrays[Mesh.ARRAY_NORMAL].to_byte_array()
	var colors: PackedByteArray = arrays[Mesh.ARRAY_COLOR].to_byte_array()
	for start in range(0, mesh.surface_get_array_len(0), 3):
		var key := vertices.slice(start * 12, (start + 3) * 12)
		key.append_array(normals.slice(start * 12, (start + 3) * 12))
		key.append_array(colors.slice(start * 16, (start + 3) * 16))
		result[key] = int(result.get(key, 0)) + 1


func _test_adaptive_archive(folder: String = "r13_cells") -> void:
	var path := "res://resources/maps/tokyo_volume_preview/" + folder + "/index.res"
	if not ResourceLoader.exists(path):
		return # 离线首次构建前先允许编译/算法门。
	var current: Resource = load(path)
	var previous: Resource = load("res://resources/maps/tokyo_volume_preview/r11_cells/index.res")
	_check(current.valid() and current.source_hash == previous.source_hash and current.source_count == previous.source_count,
		"R13 reuses exact city/ground sources and population")
	var area := 0.0
	var disjoint := true
	var fixed_delta := 0.0
	for i in current.cells.size():
		var entry: Dictionary = current.cells[i]
		area += (entry.bounds as Rect2).get_area()
		for j in range(i):
			disjoint = disjoint and not (entry.bounds as Rect2).intersects(current.cells[j].bounds)
		fixed_delta += Builder.mesh_area(load(entry.fixed).meshes[0]) - Builder.mesh_area(load(previous.cells[i].fixed).meshes[0])
	_check(disjoint and absf(area - current.bounds.get_area()) < 0.01 and absf(fixed_delta) < 2,
		"R13 new cell cuts preserve full partition and fixed surface area")
	for slot in 7:
		var actual := [{}, {}]
		var expected := [{}, {}]
		var identities := PackedStringArray()
		var old_ids := PackedStringArray()
		for id in 16:
			var entry: Dictionary = current.cells[id]
			var old: Dictionary = previous.cells[id]
			var cell: Resource = load(entry.mid.path if slot == 6 else entry.levels[slot].path)
			var reference: Resource = load(old.mid.path if slot == 6 else old.levels[slot].path)
			identities.append_array(cell.source_ids)
			old_ids.append_array(reference.source_ids)
			_check(cell.valid() and cell.height_hash == entry.levels[0].height_hash, "R13 each cell keeps all LOD source heights")
			for kind in 2:
				_add_mesh_signature(actual[kind], cell.meshes[kind])
				_add_mesh_signature(expected[kind], reference.meshes[kind])
		identities.sort()
		old_ids.sort()
		_check(identities == old_ids, "R13 all source identities retained in level %d" % slot)
		_check(actual == expected, "R13 exact unordered triangle/normal/color multiset retained in level %d" % slot)


func _test_mid_relief() -> void:
	var overlay: GDScript = load("res://scripts/rendering/tokyo_cells_overlay.gd")
	_check(overlay.relief_enabled(false, 0.97) and not overlay.relief_enabled(false, 0.98), "mid relief enters at actual output 0.97")
	_check(overlay.relief_enabled(true, 1.0) and not overlay.relief_enabled(true, 1.001), "mid relief exits before source low walls exceed two pixels")
	var current: Resource = load("res://resources/maps/tokyo_volume_preview/r11_cells/index.res")
	var old: Resource = load("res://resources/maps/tokyo_volume_preview/r10_cells/index.res")
	_check(current.valid() and current.source_hash == old.source_hash, "R11 exact R10 source reused")
	var invalid: Resource = current.duplicate(true)
	invalid.cells[0].mid.bytes = -1
	_check(not invalid.valid(), "R11 invalid middle descriptor fails before resource requests")
	var total := 0
	for entry: Dictionary in current.cells:
		var fixed: Resource = load(entry.fixed)
		var old_fixed: Resource = load(old.cells[entry.id].fixed)
		_check(_same_mesh(fixed.meshes[0], old_fixed.meshes[0]), "R11 fixed ground remains identical")
		for level in 6:
			var cell: Resource = load(entry.levels[level].path)
			var old_cell: Resource = load(old.cells[entry.id].levels[level].path)
			_check(cell.source_ids == old_cell.source_ids and cell.height_hash == old_cell.height_hash \
				and _same_mesh(cell.meshes[0], old_cell.meshes[0]) and _same_mesh(cell.meshes[1], old_cell.meshes[1]), "R11 all original six levels unchanged")
		var mid: Resource = load(entry.mid.path)
		var full: Resource = load(entry.levels[4].path)
		_check(mid.valid() and mid.level == 4 and mid.source_ids == full.source_ids and mid.height_hash == full.height_hash, "R11 mid population and source heights retained")
		_check(_same_mesh(mid.meshes[1], full.meshes[1]), "R11 mid known-height geometry unchanged")
		_check(_roof_signature(mid.meshes[0]) == _roof_signature(full.meshes[0]), "R11 mid fallback roof positions and colors unchanged")
		total += mid.triangles + fixed.triangles
	_check(total <= 240000, "R11 mid full-region geometry remains below unchanged budget")
	print("[Tokyo R11 mid] full-region triangles=", total)


func _test_layer_bounds() -> void:
	var overlay: GDScript = load("res://scripts/rendering/tokyo_cells_overlay.gd")
	var projection: GDScript = load("res://scripts/experiments/volume_projection.gd")
	var box := AABB(Vector3(-200, 0, -200), Vector3(40, 150, 60))
	var bounds: Rect2 = overlay.layer_bounds(box)
	var light := Basis.from_euler(Vector3(deg_to_rad(-50), deg_to_rad(-35), 0))
	var safe := true
	var directional_safe := true
	var tighter := true
	for degrees in range(0, 360, 15):
		var canvas := Transform2D(deg_to_rad(degrees), Vector2.ZERO)
		var ground: Basis = projection.ground_basis(canvas, deg_to_rad(38))
		var camera: Basis = projection.camera_basis(canvas, deg_to_rad(38))
		var camera_ray := ground.inverse() * camera.z
		var light_ray := ground.inverse() * light.z
		var roof_shift := -Vector2(camera_ray.x, camera_ray.z) / camera_ray.y
		var shadow_shift := -Vector2(light_ray.x, light_ray.z) / light_ray.y
		var directed: Rect2 = overlay.projected_layer_bounds(box, roof_shift, shadow_shift)
		tighter = tighter and bounds.encloses(directed) and directed.get_area() < bounds.get_area()
		for corner in 8:
			var point := ground * box.get_endpoint(corner)
			for direction: Vector3 in [-camera.z, -light.z]:
				var hit := ground.inverse() * (point - direction * (point.y / direction.y))
				safe = safe and bounds.has_point(Vector2(hit.x, hit.z))
				directional_safe = directional_safe and directed.has_point(Vector2(hit.x, hit.z))
			# 遮挡物向中间高度屋面投影，再经相机投回地面；不能只验地面影子。
			for fraction: float in [0.0, 0.25, 0.5, 0.75, 1.0]:
				var receiver := point - light.z * (point.y * (1.0 - fraction) / light.z.y)
				var hit := ground.inverse() * (receiver - camera.z * (receiver.y / camera.z.y))
				directional_safe = directional_safe and directed.has_point(Vector2(hit.x, hit.z))
	_check(safe, "layer bounds retain roof projection and sunlight shadows at every rotation")
	_check(directional_safe, "R12 directional bounds retain corners and intermediate-height receiver shadows at 24 rotations")
	_check(tighter, "R12 directional bounds stay strictly tighter than broad guard at 24 rotations")
	var view := Rect2(-6100, -1160, 1600, 920)
	_check(not overlay.layer_bounds(AABB(Vector3(-6000, 0, -205), Vector3(300, 12, 300))).intersects(view), "offscreen low layer may retire without adjacent tall-layer guard")
	_check(overlay.layer_bounds(AABB(Vector3(-6000, 0, -205), Vector3(300, 150, 300))).intersects(view), "offscreen tall layer retains potentially visible shadow")


func _test_partition() -> void:
	var parent := {"id": "parent", "parents": [], "rings": [{"outer": [[2, 2], [25, 2], [25, 8], [2, 8]]}]}
	var part := {"id": "part", "parents": ["parent"], "rings": [{"outer": [[2, 2], [5, 2], [5, 8], [2, 8]]}]}
	var second := {"id": "second", "parents": [], "rings": [{"outer": [[31, 31], [32, 31], [32, 32], [31, 32]]}]}
	var a := Builder.partition([parent, part, second], Rect2(0, 0, 40, 40))
	var b := Builder.partition([second, part, parent], Rect2(0, 0, 40, 40))
	_check(a == b, "ownership independent of input order")
	_check(a[1].size() == 2 and a[15].size() == 1, "cross-cell connected building is not split")
	_check(Builder.cell_rect(Rect2(0, 0, 40, 40), 5) == Rect2(10, 10, 10, 10), "grid row/column integer coordinates")


func _test_tagged_roofs() -> void:
	var raw := {"height_source": "height", "kind": "urban", "min_height_m": 0,
		"rings": [{"outer": [[0, 0], [2, 0], [2, 2], [0, 2]], "holes": [],
			"triangles": [[0, 0], [2, 0], [2, 2], [0, 0], [2, 2], [0, 2]]}],
		"roof_volume": {"walls": [], "roof": [[0, 8, 0], [1, 10, 1], [2, 8, 0]]}}
	for detail in 3:
		var builder := Geometry.new()
		Factory._add_ring_building(builder, raw, 10.0, detail)
		var mesh: ArrayMesh = builder.mesh()
		_check(is_equal_approx(mesh.get_aabb().end.y, 10), "tagged roof never adds rise above source total height")
		var arrays := mesh.surface_get_arrays(0)
		var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
		if detail < 2:
			_check(mesh.get_aabb().position.y == 8 and colors[0].a == 0, "pitched roof geometry classified separately from facade bands")
		else:
			_check(mesh.get_aabb().position.y == 10 and colors[0].a == 1, "far roof retains original source-height coverage")
	var path := "res://resources/maps/tokyo_volume_preview/r10_cells/index.res"
	if not ResourceLoader.exists(path):
		return
	var current: Resource = load(path)
	var previous: Resource = load("res://resources/maps/tokyo_volume_preview/r9c_cells/index.res")
	_check(current.valid() and current.source_count == previous.source_count, "R10 complete regional source count retained")
	for entry: Dictionary in current.cells:
		var old: Dictionary = previous.cells[entry.id]
		var fixed: Resource = load(entry.fixed)
		var old_fixed: Resource = load(old.fixed)
		_check(_same_mesh(fixed.meshes[0], old_fixed.meshes[0]), "R10 ground/water/roads arrays unchanged")
		for level in 6:
			var cell: Resource = load(entry.levels[level].path)
			var old_cell: Resource = load(old.levels[level].path)
			_check(cell.source_ids == old_cell.source_ids and cell.height_hash == old_cell.height_hash, "R10 all identities/source heights unchanged across LOD")
			_check(_same_mesh(cell.meshes[0], old_cell.meshes[0]), "R10 untagged low-rise meshes unchanged")


func _test_duplicate_archive() -> void:
	var path := "res://resources/maps/tokyo_volume_preview/r19_cells/index.res"
	if not ResourceLoader.exists(path):
		return # 首次构建前运行算法门；原生归档落地后必验。
	var current: Resource = load(path)
	var previous: Resource = load("res://resources/maps/tokyo_volume_preview/r17b_cells/index.res")
	var duplicate: Dictionary = preload("res://scripts/tests/test_tokyo_duplicate_outline.gd").source_fixture()
	_check(current.valid() and current.source_hash == previous.source_hash and current.source_count == previous.source_count,
		"R19 original source records and hashes unchanged")
	var changed := 0
	for id in 16:
		var entry: Dictionary = current.cells[id]
		var old: Dictionary = previous.cells[id]
		_check(entry.bounds == old.bounds and entry.content_bounds == old.content_bounds, "R19 partition unchanged")
		_check(_same_mesh(load(entry.fixed).meshes[0], load(old.fixed).meshes[0]), "R19 fixed ground byte-identical")
		for slot in 7:
			var cell: Resource = load(entry.mid.path if slot == 6 else entry.levels[slot].path)
			var reference: Resource = load(old.mid.path if slot == 6 else old.levels[slot].path)
			_check(cell.valid() and cell.source_ids == reference.source_ids and cell.height_hash == reference.height_hash,
				"R19 source identities and all heights remain archived")
			_check(_same_mesh(cell.meshes[1], reference.meshes[1]), "R19 all explicitly tagged buildings including 90m tower byte-identical")
			if duplicate.id not in reference.source_ids:
				_check(_same_mesh(cell.meshes[0], reference.meshes[0]), "R19 unrelated low-rise cells byte-identical")
				continue
			var omitted := Geometry.new()
			var detail := Builder.detail_level(duplicate, 1.0 if slot == 6 else Index.LEVELS.SCALES[slot], true)
			Factory._add_ring_building(omitted, duplicate, 10.4, detail)
			var expected := {}
			var restored := {}
			_add_mesh_signature(expected, reference.meshes[0])
			_add_mesh_signature(restored, cell.meshes[0])
			_add_mesh_signature(restored, omitted.mesh())
			_check(expected == restored, "R19 only exact redundant shell triangles removed, including normals/colors")
			_check(reference.triangles - cell.triangles == (2 if detail == 2 else 10), "R19 no extra geometric deletion")
			changed += 1
	_check(changed == 7, "R19 duplicate suppression reaches every LOD and middle package")


func _test_dome_archive() -> void:
	var path := "res://resources/maps/tokyo_volume_preview/r17b_cells/index.res"
	if not ResourceLoader.exists(path):
		return # 首次离线构建前只跑算法门；归档存在后必验。
	var current: Resource = load(path)
	var previous: Resource = load("res://resources/maps/tokyo_volume_preview/r15c_cells/index.res")
	_check(current.valid() and current.source_hash == previous.source_hash and current.source_count == previous.source_count, "R17B uses exact original city and all source records")
	var changed := 0
	for id in 16:
		var entry: Dictionary = current.cells[id]
		var old: Dictionary = previous.cells[id]
		_check(entry.bounds == old.bounds and entry.content_bounds == old.content_bounds, "R17B cell partition and culling extents unchanged")
		_check(_same_mesh(load(entry.fixed).meshes[0], load(old.fixed).meshes[0]), "R17B exact ground/water/roads unchanged")
		for slot in 7:
			var cell: Resource = load(entry.mid.path if slot == 6 else entry.levels[slot].path)
			var reference: Resource = load(old.mid.path if slot == 6 else old.levels[slot].path)
			_check(cell.valid() and cell.source_ids == reference.source_ids and cell.height_hash == reference.height_hash, "R17B all LOD source identities and heights retained")
			_check(_same_mesh(cell.meshes[0], reference.meshes[0]), "R17B fallback buildings exactly unchanged")
			var actual := {}
			var expected := {}
			_add_mesh_signature(actual, cell.meshes[1])
			_add_mesh_signature(expected, reference.meshes[1])
			var local_changes := 0
			var confined := true
			for pair: Array in [[actual, expected], [expected, actual]]:
				for key: PackedByteArray in pair[0]:
					if int(pair[0][key]) != int(pair[1].get(key, 0)):
						local_changes += 1
						confined = confined and _inside_source_dome(key)
			_check(confined, "R17B every changed triangle belongs to the three source dome volumes")
			changed += local_changes
	_check(changed > 0, "R17B actually changes source domes rather than only metadata")


func _inside_source_dome(key: PackedByteArray) -> bool:
	# 独立来源边界：博物馆八角顶、Queen塔十九边顶、港区九边顶；不允许其他楼混入。
	var bounds: Array[AABB] = [AABB(Vector3(-5584.307, 0.12, -508.752), Vector3(6.574, 12.38, 6.949)),
		AABB(Vector3(-5317.137, 0.12, -510.372), Vector3(2.468, 25.38, 2.475)),
		AABB(Vector3(-5377.651, 0.12, -392.885), Vector3(4.01, 9.88, 4.074))]
	for box: AABB in bounds:
		var inside := true
		for corner in 3:
			var offset := corner * 12
			inside = inside and box.grow(0.002).has_point(Vector3(key.decode_float(offset), key.decode_float(offset + 4), key.decode_float(offset + 8)))
		if inside:
			return true
	return false


func _test_yokohama() -> void:
	var path := "res://resources/maps/tokyo_volume_preview/r9_cells/index.res"
	if not ResourceLoader.exists(path):
		return # 离线构建前允许先跑编译门；有归档后必须完整验证。
	var index: Resource = load(path)
	_check(index.valid() and index.bounds == Rect2(-6300, -1700, 2000, 2000), "Yokohama source bounds")
	var colored: Resource = load("res://resources/maps/tokyo_volume_preview/r9c_cells/index.res")
	_check(colored.valid() and colored.source_count == index.source_count \
		and colored.source_hash.split(":")[0] == index.source_hash.split(":")[0], "Yokohama water calibration keeps exact city source")
	var seen: Dictionary = {}
	for entry: Dictionary in index.cells:
		var fixed: Resource = load(entry.fixed)
		_check(fixed.valid() and fixed.level == -1, "Yokohama fixed coast cell valid")
		var colored_fixed: Resource = load(colored.cells[entry.id].fixed)
		_check(fixed.meshes[0].surface_get_arrays(0)[Mesh.ARRAY_VERTEX] == colored_fixed.meshes[0].surface_get_arrays(0)[Mesh.ARRAY_VERTEX],
			"water calibration preserves all fixed coastline/road vertices")
		var identities := PackedStringArray()
		var height_hash := ""
		for level in 6:
			var cell: Resource = load(entry.levels[level].path)
			var colored_cell: Resource = load(colored.cells[entry.id].levels[level].path)
			_check(_same_mesh(cell.meshes[0], colored_cell.meshes[0]) and _same_mesh(cell.meshes[1], colored_cell.meshes[1]),
				"water calibration preserves both building meshes exactly")
			_check(cell.valid() and cell.level == level and cell.cell_id == entry.id, "Yokohama LOD archive valid")
			if level == 0:
				identities = cell.source_ids
				height_hash = cell.height_hash
				for identity: String in identities:
					_check(not seen.has(identity), "Yokohama unique source", false)
					seen[identity] = true
			_check(cell.source_ids == identities and cell.height_hash == height_hash, "Yokohama heights/identities preserved across six LODs")
	_check(seen.size() == index.source_count and seen.size() > 0, "Yokohama complete population accounted")


func _test_clip() -> void:
	var source := Geometry.new()
	source.triangle(Vector3(-3, 0.4, -5), Vector3(42, 0.4, -5), Vector3(10, 0.4, 43), Color.WHITE)
	var builders: Array = []
	for id in 16:
		builders.append(Geometry.new())
	var expected := Builder.split_fixed(source.mesh(), Rect2(0, 0, 40, 40), builders)
	var actual := 0.0
	for item: RefCounted in builders:
		var mesh: ArrayMesh = item.mesh()
		actual += Builder.mesh_area(mesh)
		if mesh.get_surface_count() > 0:
			var expected_normal: Vector3 = source.mesh().surface_get_arrays(0)[Mesh.ARRAY_NORMAL][0]
			for normal: Vector3 in mesh.surface_get_arrays(0)[Mesh.ARRAY_NORMAL]:
				_check(normal.dot(expected_normal) > 0.999, "split preserves source face orientation", false)
	_check(absf(expected - actual) < 0.001, "cross-grid clipped area conserved")
	var clipped := Builder.clip_polygon(PackedVector3Array([Vector3(-1, 7, 0), Vector3(1, 7, 0), Vector3(1, 7, 2)]), 0, 0, true)
	_check(clipped.size() == 4, "crossing triangle gains exact seam vertices")
	for point: Vector3 in clipped:
		_check(point.x >= 0 and point.y == 7, "clipping preserves height")


func _test_ring_levels() -> void:
	var triangles: Array = []
	for quad: Array in [[[0, 0], [10, 0], [7, 3], [3, 3]], [[10, 0], [10, 10], [7, 7], [7, 3]], [[10, 10], [0, 10], [3, 7], [7, 7]], [[0, 10], [0, 0], [3, 3], [3, 7]]]:
		triangles.append_array([quad[0], quad[1], quad[2], quad[0], quad[2], quad[3]])
	var raw := {"kind": "urban", "height_source": "height", "min_height_m": 3.0, "height_m": 100.0,
		"rings": [{"outer": [[0, 0], [10, 0], [10, 10], [0, 10]], "holes": [[[3, 3], [7, 3], [7, 7], [3, 7]]], "triangles": triangles}]}
	for detail in 3:
		var geometry := Geometry.new()
		Factory._add_ring_building(geometry, raw, 50.0, detail)
		var mesh: ArrayMesh = geometry.mesh()
		_check(is_equal_approx(mesh.get_aabb().end.y, 50.0), "all LOD maxima preserve source height")
		_check(mesh.get_aabb().position.y >= 1.5, "no invented support below min_height")
		var arrays := mesh.surface_get_arrays(0)
		var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var roof_area := 0.0
		for start in range(0, points.size(), 3):
			if normals[start].y > 0.9:
				roof_area += (points[start + 1] - points[start]).cross(points[start + 2] - points[start]).length() * 0.5
		_check(is_equal_approx(roof_area, 84.0), "courtyard stays open at every LOD")
	_check(Builder.detail_level(raw, 0.2) == 1, "small-screen high-rise retains walls")
	_check(Builder.detail_level(raw, 1.6) == 0, "near high-rise retains detail")
	_check(Builder.detail_level(raw, 0.1) == 2, "far roof density preserved without tiny walls")


func _test_relief() -> void:
	var low := {"rings": [{"outer": [[0, 0], [40, 0], [40, 40], [0, 40]]}], "height_m": 6.4, "height_source": "fallback"}
	_check(Builder.detail_level(low, 0.8, true) == 2, "R8 sub-two-pixel fallback wall may simplify without removing roof")
	_check(Builder.detail_level(low, 1.6, true) == Builder.detail_level(low, 1.6), "R8 close fallback retains original details")
	low.height_source = "height"
	_check(Builder.detail_level(low, 0.8, true) == Builder.detail_level(low, 0.8), "R8 known-height buildings never use fallback relief rule")
	var original: Resource = load(Index.PATH)
	var candidate: Resource = load("res://resources/maps/tokyo_volume_preview/r8_cells/index.res")
	_check(candidate != null and candidate.valid(), "R8 independent native directory valid")
	if candidate == null:
		return
	_check(candidate.source_hash == original.source_hash and candidate.source_count == original.source_count, "R8 source hash and population unchanged")
	var totals := PackedInt64Array([0, 0, 0, 0, 0, 0])
	for id in original.cells.size():
		var old: Dictionary = original.cells[id]
		var next: Dictionary = candidate.cells[id]
		var old_fixed: Resource = load(old.fixed)
		var new_fixed: Resource = load(next.fixed)
		_check(_same_mesh(old_fixed.meshes[0], new_fixed.meshes[0]), "R8 fixed ground geometry identical %d" % id)
		for level in 6:
			var a: Resource = load(old.levels[level].path)
			var b: Resource = load(next.levels[level].path)
			_check(a.source_ids == b.source_ids and a.height_hash == b.height_hash, "R8 source identities and heights identical %d/%d" % [id, level])
			_check(_same_mesh(a.meshes[1], b.meshes[1]), "R8 known-height geometry identical %d/%d" % [id, level])
			_check(_roof_signature(a.meshes[0]) == _roof_signature(b.meshes[0]), "R8 fallback roofs preserve coordinates and colors %d/%d" % [id, level])
			if level >= 4:
				_check(_same_mesh(a.meshes[0], b.meshes[0]), "R8 near fallback geometry identical %d/%d" % [id, level])
			totals[level] += b.triangles + new_fixed.triangles
	for level in 4:
		_check(totals[level] <= 240000, "R8 far and middle whole-region submission within 240k at %d" % level)
	print("[Tokyo R8] full-region triangles=", totals)


func _roof_signature(mesh: ArrayMesh) -> PackedByteArray:
	var points := PackedVector3Array()
	var colors := PackedColorArray()
	if mesh.get_surface_count() == 0:
		return PackedByteArray()
	var arrays := mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var palette: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	for start in range(0, vertices.size(), 3):
		if normals[start].y > 0.99:
			for corner in 3:
				points.append(vertices[start + corner])
				colors.append(palette[start + corner])
	var result := points.to_byte_array()
	result.append_array(colors.to_byte_array())
	return result


func _same_mesh(a: ArrayMesh, b: ArrayMesh) -> bool:
	if a.get_surface_count() != b.get_surface_count():
		return false
	for surface in a.get_surface_count():
		var left := a.surface_get_arrays(surface)
		var right := b.surface_get_arrays(surface)
		for channel in left.size():
			if left[channel] != right[channel]:
				return false
	return true


func _check(ok: bool, label: String, verbose: bool = true) -> void:
	if ok:
		_pass += 1
	else:
		_fail += 1
	if verbose or not ok:
		print("  ", "PASS " if ok else "FAIL ", label)
