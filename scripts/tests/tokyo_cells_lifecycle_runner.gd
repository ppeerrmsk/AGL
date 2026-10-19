extends Node


func _ready() -> void:
	if not OS.get_environment("AGL_TOKYO_CUT_WORKER_REPLAY_OUT").is_empty():
		get_tree().quit(await preload("res://scripts/tests/tokyo_cut_worker_replay.gd").run(self,OS.get_environment("AGL_TOKYO_HLOD_PACKAGE"),OS.get_environment("AGL_TOKYO_HLOD_PACKAGE_SHA"),OS.get_environment("AGL_TOKYO_CUT_WORKER_REPLAY_OUT")))
		return
	if not OS.get_environment("AGL_TOKYO_PARTITION_STREAM").is_empty():
		get_tree().quit(await preload("res://scripts/tests/tokyo_partition_stream_probe.gd").run(self,OS.get_environment("AGL_TOKYO_PARTITION_STREAM"),OS.get_environment("AGL_TOKYO_PARTITION_STREAM_SHA")))
		return
	if not OS.get_environment("AGL_TOKYO_TAGGED_LOW_REVIEW").is_empty():
		get_tree().quit(await preload("res://scripts/tests/tokyo_tagged_low_cut_review.gd").run(self,OS.get_environment("AGL_TOKYO_TAGGED_LOW_REVIEW"),OS.get_environment("AGL_TOKYO_TAGGED_LOW_REVIEW_SHA")))
		return
	if not OS.get_environment("AGL_TOKYO_MIDDLE_MASSING_OUT").is_empty():
		get_tree().quit(preload("res://scripts/tests/build_tokyo_middle_massing.gd").run(OS.get_environment("AGL_TOKYO_MIDDLE_MASSING_OUT")))
		return
	if not OS.get_environment("AGL_TOKYO_FOUNDATION_AUDIT").is_empty():
		get_tree().quit(preload("res://scripts/tests/tokyo_foundation_audit.gd").run(OS.get_environment("AGL_TOKYO_FOUNDATION_AUDIT")))
		return
	if not OS.get_environment("AGL_TOKYO_BOUNDARY_COVERAGE").is_empty():
		get_tree().quit(preload("res://scripts/tests/audit_tokyo_boundary_coverage.gd").new().run(OS.get_environment("AGL_TOKYO_BOUNDARY_COVERAGE"),OS.get_environment("AGL_TOKYO_BOUNDARY_COVERAGE_SHA")))
		return
	if not OS.get_environment("AGL_TOKYO_BOUNDARY_CATALOG").is_empty():
		get_tree().quit(preload("res://scripts/tests/build_tokyo_boundary_catalog.gd").run(OS.get_environment("AGL_TOKYO_BOUNDARY_CATALOG"),OS.get_environment("AGL_TOKYO_BOUNDARY_CATALOG_SHA")))
		return
	if not OS.get_environment("AGL_TOKYO_BOUNDARY_TREE").is_empty():
		get_tree().quit(preload("res://scripts/tests/build_tokyo_boundary_tree.gd").run(OS.get_environment("AGL_TOKYO_BOUNDARY_TREE"),OS.get_environment("AGL_TOKYO_BOUNDARY_TREE_SHA")))
		return
	if not OS.get_environment("AGL_TOKYO_BOUNDARY_BLOCK_TILE").is_empty():
		get_tree().quit(preload("res://scripts/tests/build_tokyo_boundary_blocks.gd").run(OS.get_environment("AGL_TOKYO_BOUNDARY_SOURCES"),OS.get_environment("AGL_TOKYO_BOUNDARY_SOURCES_SHA"),OS.get_environment("AGL_TOKYO_BOUNDARY_BLOCK_AUDIT"),OS.get_environment("AGL_TOKYO_BOUNDARY_BLOCK_AUDIT_SHA"),OS.get_environment("AGL_TOKYO_BOUNDARY_BLOCK_TILE")))
		return
	if not OS.get_environment("AGL_TOKYO_BOUNDARY_EXPORT").is_empty():
		get_tree().quit(preload("res://scripts/tests/export_tokyo_boundary_layers.gd").run(OS.get_environment("AGL_TOKYO_BOUNDARY_EXPORT"),OS.get_environment("AGL_TOKYO_BOUNDARY_EXPORT_SHA")))
		return
	if not OS.get_environment("AGL_TOKYO_RESIDENCY_PROBE").is_empty():
		get_tree().quit(await preload("res://scripts/tests/tokyo_map_residency_probe.gd").run(self,OS.get_environment("AGL_TOKYO_RESIDENCY_PROBE")))
		return
	if not OS.get_environment("AGL_TOKYO_INSTALL_PACKAGE").is_empty():
		get_tree().quit(preload("res://scripts/tests/package_tokyo_installed.gd").run(OS.get_environment("AGL_TOKYO_INSTALL_PACKAGE"),OS.get_environment("AGL_TOKYO_INSTALL_STAGE")))
		return
	if not OS.get_environment("AGL_TOKYO_SOLID_INPUT").is_empty():
		get_tree().quit(preload("res://scripts/tests/build_tokyo_solid_native.gd").run(OS.get_environment("AGL_TOKYO_SOLID_INPUT"),OS.get_environment("AGL_TOKYO_SOLID_OUT")))
		return
	if not OS.get_environment("AGL_TOKYO_HLOD_OPAQUE_INPUT").is_empty():
		get_tree().quit(preload("res://scripts/tests/build_tokyo_hlod_opaque.gd").run(OS.get_environment("AGL_TOKYO_HLOD_OPAQUE_INPUT"),OS.get_environment("AGL_TOKYO_HLOD_OPAQUE_SHA"),OS.get_environment("AGL_TOKYO_HLOD_OPAQUE_OUT")))
		return
	if not OS.get_environment("AGL_TOKYO_MASSING_COLOR_SOURCE").is_empty():
		get_tree().quit(preload("res://scripts/tests/export_tokyo_massing_color.gd").run(OS.get_environment("AGL_TOKYO_MASSING_COLOR_SOURCE"),OS.get_environment("AGL_TOKYO_MASSING_COLOR_SHA"),OS.get_environment("AGL_TOKYO_MASSING_COLOR_OUT")))
		return
	if not OS.get_environment("AGL_TOKYO_NEAR_COMPONENT_AUDIT").is_empty():
		get_tree().quit(preload("res://scripts/tests/tokyo_near_component_audit.gd").run(OS.get_environment("AGL_TOKYO_NEAR_COMPONENT_AUDIT"),OS.get_environment("AGL_TOKYO_NEAR_COMPONENT_SHA"),OS.get_environment("AGL_TOKYO_NEAR_COMPONENT_OUT")))
		return
	if not OS.get_environment("AGL_TOKYO_HLOD_ROUTE_OUT").is_empty():
		var probe := preload("res://scripts/tests/tokyo_hlod_route_probe.gd").new()
		get_tree().root.add_child(probe)
		probe.call_deferred("run")
		return
	if OS.get_environment("AGL_TOKYO_HLOD_STREAM_TEST")=="1":
		get_tree().quit(await preload("res://scripts/tests/test_tokyo_hlod_stream.gd").run(self))
		return
	if not OS.get_environment("AGL_TOKYO_HLOD_MANIFEST_AUDIT").is_empty():
		get_tree().quit(preload("res://scripts/tests/tokyo_hlod_manifest_audit.gd").run(OS.get_environment("AGL_TOKYO_HLOD_MANIFEST_AUDIT"),OS.get_environment("AGL_TOKYO_HLOD_MANIFEST_AUDIT_SHA"),OS.get_environment("AGL_TOKYO_HLOD_MANIFEST_AUDIT_OUT")))
		return
	if not OS.get_environment("AGL_TOKYO_HLOD_PAGES_REVIEW").is_empty():
		get_tree().quit(await preload("res://scripts/tests/tokyo_hlod_pages_review.gd").run(get_tree(),OS.get_environment("AGL_TOKYO_HLOD_PAGES_REVIEW"),OS.get_environment("AGL_TOKYO_HLOD_PAGES_REVIEW_SHA"),OS.get_environment("AGL_TOKYO_HLOD_PAGES_REVIEW_OUT")))
		return
	if not OS.get_environment("AGL_TOKYO_HLOD_NATIVE_PAGES").is_empty():
		get_tree().quit(preload("res://scripts/tests/build_tokyo_hlod_native_pages.gd").run(OS.get_environment("AGL_TOKYO_HLOD_NATIVE_PAGES"),OS.get_environment("AGL_TOKYO_HLOD_NATIVE_SHA"),OS.get_environment("AGL_TOKYO_HLOD_NATIVE_OUT")))
		return
	if not OS.get_environment("AGL_TOKYO_OVERVIEW_HLOD_REVIEW").is_empty():
		get_tree().quit(await preload("res://scripts/tests/tokyo_overview_hlod_review.gd").run(get_tree(),OS.get_environment("AGL_TOKYO_OVERVIEW_HLOD_REVIEW"),OS.get_environment("AGL_TOKYO_OVERVIEW_HLOD_SHA"),OS.get_environment("AGL_TOKYO_OVERVIEW_HLOD_OUT")))
		return
	if not OS.get_environment("AGL_TOKYO_SEMANTIC_FIXED_TREE").is_empty():
		get_tree().quit(preload("res://scripts/tests/build_tokyo_semantic_fixed_tree.gd").run(OS.get_environment("AGL_TOKYO_SEMANTIC_FIXED_TREE"),OS.get_environment("AGL_TOKYO_SEMANTIC_FIXED_SHA"),OS.get_environment("AGL_TOKYO_SEMANTIC_FIXED_HIERARCHY"),OS.get_environment("AGL_TOKYO_SEMANTIC_FIXED_OUT")))
		return
	if not OS.get_environment("AGL_TOKYO_SEMANTIC_FIXED_REBIND").is_empty():
		get_tree().quit(preload("res://scripts/tests/rebind_tokyo_semantic_fixed_tree.gd").run(OS.get_environment("AGL_TOKYO_SEMANTIC_FIXED_REBIND"),OS.get_environment("AGL_TOKYO_SEMANTIC_FIXED_SHA"),OS.get_environment("AGL_TOKYO_SEMANTIC_FIXED_OUT")))
		return
	if not OS.get_environment("AGL_TOKYO_SEMANTIC_RAIL_ROOT").is_empty():
		get_tree().quit(preload("res://scripts/tests/bake_tokyo_semantic_rail_roots.gd").run(OS.get_environment("AGL_TOKYO_SEMANTIC_RAIL_ROOT"),OS.get_environment("AGL_TOKYO_SEMANTIC_RAIL_SHA"),OS.get_environment("AGL_TOKYO_SEMANTIC_RAIL_OUT")))
		return
	if not OS.get_environment("AGL_TOKYO_PORTABLE_INPUT").is_empty():
		get_tree().quit(preload("res://scripts/tests/build_tokyo_portable_package.gd").run(OS.get_environment("AGL_TOKYO_PORTABLE_INPUT"),OS.get_environment("AGL_TOKYO_PORTABLE_SHA"),OS.get_environment("AGL_TOKYO_PORTABLE_OUT")))
		return
	if not OS.get_environment("AGL_TOKYO_PORTABLE_VERIFY").is_empty():
		get_tree().quit(preload("res://scripts/tests/verify_tokyo_portable_package.gd").run(OS.get_environment("AGL_TOKYO_PORTABLE_VERIFY"),OS.get_environment("AGL_TOKYO_PORTABLE_SHA")))
		return
	if not OS.get_environment("AGL_TOKYO_FULL_CATALOG_INPUT").is_empty():
		get_tree().quit(preload("res://scripts/tests/build_tokyo_full_grid_catalog.gd").run(OS.get_environment("AGL_TOKYO_FULL_CATALOG_INPUT"),OS.get_environment("AGL_TOKYO_FULL_CATALOG_SHA"),OS.get_environment("AGL_TOKYO_FULL_CATALOG_OUT")))
		return
	if not OS.get_environment("AGL_TOKYO_FULL_COVERAGE_INPUT").is_empty():
		get_tree().quit(preload("res://scripts/tests/build_tokyo_full_source_coverage.gd").new().run())
		return
	if not OS.get_environment("AGL_TOKYO_FULL_CONFIG_ROOFS_INPUT").is_empty():
		get_tree().quit(preload("res://scripts/tests/bake_tokyo_full_grid_configuration.gd").run(OS.get_environment("AGL_TOKYO_FULL_CONFIG_ROOFS_INPUT"),OS.get_environment("AGL_TOKYO_FULL_CONFIG_ROOFS_SHA"),OS.get_environment("AGL_TOKYO_FULL_CONFIG_ROOFS_OUT"),OS.get_environment("AGL_TOKYO_FULL_CONFIG_ROOFS_AUDIT")))
		return
	if not OS.get_environment("AGL_TOKYO_INTERACTION_PROBE").is_empty():
		get_tree().quit(preload("res://scripts/tests/bake_tokyo_interaction_probe.gd").run(OS.get_environment("AGL_TOKYO_INTERACTION_PROBE"),OS.get_environment("AGL_TOKYO_INTERACTION_PROOF"),OS.get_environment("AGL_TOKYO_INTERACTION_PROOF_SHA"),OS.get_environment("AGL_TOKYO_INTERACTION_OUT"),OS.get_environment("AGL_TOKYO_INTERACTION_SAVED")))
		return
	if not OS.get_environment("AGL_TOKYO_FULL_ROOT_PAGES_INPUT").is_empty():
		get_tree().quit(preload("res://scripts/tests/build_tokyo_full_grid_root_pages.gd").run(OS.get_environment("AGL_TOKYO_FULL_ROOT_PAGES_INPUT"),OS.get_environment("AGL_TOKYO_FULL_ROOT_PAGES_SHA"),OS.get_environment("AGL_TOKYO_FULL_ROOT_PAGES_OUT"),OS.get_environment("AGL_TOKYO_FULL_ROOT_PAGES_FIXED")))
		return
	if not OS.get_environment("AGL_TOKYO_FULL_COMPONENT_TREE_TEST").is_empty():
		get_tree().quit(preload("res://scripts/tests/test_tokyo_full_component_tree.gd").run(OS.get_environment("AGL_TOKYO_FULL_COMPONENT_TREE_TEST"),OS.get_environment("AGL_TOKYO_FULL_COMPONENT_TREE_LAYOUT")))
		return
	if not OS.get_environment("AGL_TOKYO_FULL_NATIVE_LEAVES").is_empty():
		get_tree().quit(preload("res://scripts/tests/build_tokyo_full_native_leaves.gd").run(OS.get_environment("AGL_TOKYO_FULL_NATIVE_LEAVES"),OS.get_environment("AGL_TOKYO_FULL_NATIVE_LEAVES_SHA"),OS.get_environment("AGL_TOKYO_FULL_NATIVE_LEAVES_OUT")))
		return
	if not OS.get_environment("AGL_TOKYO_ROOT_ROOF_PRECISION").is_empty():
		get_tree().quit(preload("res://scripts/tests/audit_tokyo_full_root_roof_precision.gd").run(OS.get_environment("AGL_TOKYO_ROOT_ROOF_PRECISION"),OS.get_environment("AGL_TOKYO_ROOT_ROOF_PRECISION_SHA"),OS.get_environment("AGL_TOKYO_ROOT_ROOF_PRECISION_OUT"),OS.get_environment("AGL_TOKYO_ROOT_ROOF_PRECISION_AUDIT")=="1"))
		return
	if not OS.get_environment("AGL_TOKYO_FULL_ROOT_ROOFS").is_empty():
		get_tree().quit(preload("res://scripts/tests/export_tokyo_full_root_roofs.gd").run(OS.get_environment("AGL_TOKYO_FULL_ROOT_ROOFS"),OS.get_environment("AGL_TOKYO_FULL_ROOT_ROOFS_SHA"),OS.get_environment("AGL_TOKYO_FULL_ROOT_ROOFS_OUT")))
		return
	if not OS.get_environment("AGL_TOKYO_FULL_ROOT_INPUT").is_empty():
		get_tree().quit(preload("res://scripts/tests/build_tokyo_full_grid_root.gd").run(OS.get_environment("AGL_TOKYO_FULL_ROOT_INPUT"),OS.get_environment("AGL_TOKYO_FULL_ROOT_SHA"),OS.get_environment("AGL_TOKYO_FULL_ROOT_OUT"),OS.get_environment("AGL_TOKYO_FULL_ROOT_CONFIG")))
		return
	if not OS.get_environment("AGL_TOKYO_FULL_GRID_LAYOUT_OUT").is_empty():
		get_tree().quit(preload("res://scripts/tests/export_tokyo_full_grid_layout.gd").run(OS.get_environment("AGL_TOKYO_BLOCK_ROOT"),OS.get_environment("AGL_TOKYO_REGIONAL_ROUTES"),OS.get_environment("AGL_TOKYO_REGIONAL_ROUTES_SHA"),OS.get_environment("AGL_TOKYO_FULL_GRID_LAYOUT_OUT")))
		return
	if not OS.get_environment("AGL_TOKYO_OWNED_BLOCK_BATCH").is_empty():
		get_tree().quit(preload("res://scripts/tests/transfer_tokyo_full_tile_blocks.gd").run(OS.get_environment("AGL_TOKYO_OWNED_BLOCK_BATCH"),OS.get_environment("AGL_TOKYO_OWNED_BLOCK_BATCH_SHA")))
		return
	if OS.get_environment("AGL_TOKYO_BATCH_BLOCKS") == "1":
		if not OS.get_environment("AGL_TOKYO_BATCH_MANIFEST").is_empty():
			get_tree().quit(preload("res://scripts/tests/build_tokyo_full_tile_blocks.gd").run(OS.get_environment("AGL_TOKYO_BLOCK_ROOT"),OS.get_environment("AGL_TOKYO_BATCH_MANIFEST"),OS.get_environment("AGL_TOKYO_BATCH_MANIFEST_SHA"),OS.get_environment("AGL_TOKYO_BATCH_AUDIT"),OS.get_environment("AGL_TOKYO_BATCH_AUDIT_SHA")))
			return
		get_tree().quit(preload("res://scripts/tests/build_tokyo_batch_blocks.gd").run(OS.get_environment("AGL_TOKYO_BLOCK_ROOT")))
		return
	if OS.get_environment("AGL_TOKYO_BATCH_LAYERS") == "1":
		get_tree().quit(preload("res://scripts/tests/export_tokyo_batch_layers.gd").run(OS.get_environment("AGL_TOKYO_BLOCK_ROOT")))
		return
	if OS.get_environment("AGL_TOKYO_INDEXED_FIXED_REVIEW")!="":
		get_tree().quit(await preload("res://scripts/tests/tokyo_indexed_fixed_review.gd").run(get_tree(),OS.get_environment("AGL_TOKYO_BLOCK_ROOT"),OS.get_environment("AGL_TOKYO_INDEXED_FIXED_REVIEW")))
		return
	if OS.get_environment("AGL_TOKYO_LAYERED_DEPTH_REVIEW")!="":
		get_tree().quit(await preload("res://scripts/tests/tokyo_layered_depth_review.gd").run(get_tree(),OS.get_environment("AGL_TOKYO_BLOCK_ROOT"),OS.get_environment("AGL_TOKYO_LAYERED_DEPTH_REVIEW")))
		return
	if OS.get_environment("AGL_TOKYO_LAYERED_TEXTURE_REVIEW")!="":
		get_tree().quit(await preload("res://scripts/tests/tokyo_layered_texture_review.gd").run(get_tree(),OS.get_environment("AGL_TOKYO_BLOCK_ROOT"),OS.get_environment("AGL_TOKYO_LAYERED_TEXTURE_REVIEW")))
		return
	if OS.get_environment("AGL_TOKYO_NORTHWEST_WALLS") != "":
		get_tree().quit(preload("res://scripts/tests/build_tokyo_northwest_walls.gd").run(OS.get_environment("AGL_TOKYO_BLOCK_ROOT"),OS.get_environment("AGL_TOKYO_NORTHWEST_WALLS")))
		return
	if OS.get_environment("AGL_TOKYO_NORTHWEST_CATALOG") != "":
		var builder := preload("res://scripts/tests/build_tokyo_northwest_catalog.gd").new()
		var root := OS.get_environment("AGL_TOKYO_BLOCK_ROOT")
		var output := OS.get_environment("AGL_TOKYO_NORTHWEST_CATALOG")
		get_tree().quit(builder.audit_join(root,output) if OS.get_environment("AGL_TOKYO_NORTHWEST_CATALOG_AUDIT")=="1" else builder.build(root,output))
		return
	if OS.get_environment("AGL_TOKYO_NORTHWEST_BOUNDARY") != "":
		var boundary := preload("res://scripts/tests/tokyo_northwest_boundary.gd")
		var root := OS.get_environment("AGL_TOKYO_BLOCK_ROOT")
		var output := OS.get_environment("AGL_TOKYO_NORTHWEST_BOUNDARY")
		get_tree().quit(boundary.audit(root,output) if OS.get_environment("AGL_TOKYO_NORTHWEST_BOUNDARY_AUDIT")=="1" else boundary.run(root,output))
		return
	if OS.get_environment("AGL_TOKYO_NORTHWEST_BLOCKS_OUT") != "":
		get_tree().quit(preload("res://scripts/tests/build_tokyo_northwest_blocks.gd").run(OS.get_environment("AGL_TOKYO_BLOCK_ROOT"),OS.get_environment("AGL_TOKYO_NORTHWEST_BLOCKS_OUT")))
		return
	if OS.get_environment("AGL_TOKYO_RASTER_CAPACITY_UNIT") == "1":
		var failures := await preload("res://scripts/tests/raster_capacity_lifecycle_case.gd").run(self)
		await get_tree().process_frame
		get_tree().quit(1 if failures else 0)
		return
	if OS.get_environment("AGL_TOKYO_LOW_WALL_UNIT") == "1":
		var failures := 0
		for passed: bool in preload("res://scripts/tests/test_tokyo_low_walls.gd").checks():
			failures += int(not passed)
		failures += await preload("res://scripts/tests/test_tokyo_low_walls.gd").lifecycle(self)
		await get_tree().process_frame
		print("[R187 low wall focused] fail=",failures)
		get_tree().quit(1 if failures else 0)
		return
	if OS.get_environment("AGL_TOKYO_WALL_PAGES_AUDIT") != "":
		var directory := "r193-wall-pages-a" if OS.get_environment("AGL_TOKYO_WALL_PAGES_NORTH")=="1" else "r186-wall-pages-a"
		if OS.get_environment("AGL_TOKYO_WALL_PAGES_NORTHWEST")=="1":
			directory="r205-wall-pages-a"
			if OS.get_environment("AGL_TOKYO_NORTHWEST_COMBINED")=="1":
				directory="r213-wall-pages-a"
		get_tree().quit(preload("res://scripts/tests/build_tokyo_wall_pages.gd").audit(OS.get_environment("AGL_TOKYO_BLOCK_ROOT").path_join(directory+"/manifest.bin"),OS.get_environment("AGL_TOKYO_WALL_PAGES_AUDIT")))
		return
	if OS.get_environment("AGL_TOKYO_WALL_PAGES") != "":
		get_tree().quit(preload("res://scripts/tests/build_tokyo_wall_pages.gd").new().run(OS.get_environment("AGL_TOKYO_BLOCK_ROOT"),OS.get_environment("AGL_TOKYO_WALL_PAGES")))
		return
	if OS.get_environment("AGL_TOKYO_WALL_BUNDLE") != "":
		get_tree().quit(preload("res://scripts/tests/build_tokyo_wall_bundle.gd").run(OS.get_environment("AGL_TOKYO_BLOCK_ROOT"),OS.get_environment("AGL_TOKYO_WALL_BUNDLE")))
		return
	if OS.get_environment("AGL_TOKYO_ROOF_PROXY_REVIEW") != "":
		get_tree().quit(await preload("res://scripts/tests/tokyo_roof_proxy_review.gd").run(self,OS.get_environment("AGL_TOKYO_BLOCK_ROOT"),OS.get_environment("AGL_TOKYO_ROOF_PROXY_REVIEW")))
		return
	if OS.get_environment("AGL_TOKYO_RETAINED_LOD_PROBE") != "":
		get_tree().quit(preload("res://scripts/tests/tokyo_retained_lod_probe.gd").run(OS.get_environment("AGL_TOKYO_BLOCK_ROOT"),OS.get_environment("AGL_TOKYO_RETAINED_LOD_PROBE")))
		return
	if OS.get_environment("AGL_TOKYO_SUBMISSION_AUDIT") != "":
		get_tree().quit(preload("res://scripts/tests/tokyo_submission_duplicate_audit.gd").run(OS.get_environment("AGL_TOKYO_BLOCK_ROOT"),OS.get_environment("AGL_TOKYO_SUBMISSION_AUDIT")))
		return
	if OS.get_environment("AGL_TOKYO_RESIDENTIAL_CATALOG") != "":
		get_tree().quit(preload("res://scripts/tests/build_tokyo_residential_catalog.gd").new().run(OS.get_environment("AGL_TOKYO_BLOCK_ROOT"),OS.get_environment("AGL_TOKYO_RESIDENTIAL_CATALOG")))
		return
	if OS.get_environment("AGL_TOKYO_RESIDENTIAL_PATCH") != "":
		get_tree().quit(await preload("res://scripts/tests/tokyo_residential_patch.gd").run(self,OS.get_environment("AGL_TOKYO_BLOCK_ROOT"),OS.get_environment("AGL_TOKYO_RESIDENTIAL_PATCH")))
		return
	if OS.get_environment("AGL_TOKYO_RESIDENTIAL_PREVIEW") != "":
		get_tree().quit(await preload("res://scripts/tests/tokyo_residential_preview.gd").run(self,OS.get_environment("AGL_TOKYO_BLOCK_ROOT"),OS.get_environment("AGL_TOKYO_RESIDENTIAL_PREVIEW")))
		return
	if OS.get_environment("AGL_TOKYO_RAIL_AUDIT") != "":
		get_tree().quit(preload("res://scripts/tests/build_tokyo_rail_catalog.gd").audit(OS.get_environment("AGL_TOKYO_BLOCK_ROOT"),OS.get_environment("AGL_TOKYO_RAIL_AUDIT"),OS.get_environment("AGL_TOKYO_RAIL_NEIGHBOR")=="1"))
		return
	if OS.get_environment("AGL_TOKYO_RAIL_CATALOG") != "":
		if OS.get_environment("AGL_TOKYO_ROAD_MESHOPT") == "1":
			get_tree().quit(preload("res://scripts/tests/build_tokyo_road_meshopt_catalog.gd").new().run(OS.get_environment("AGL_TOKYO_BLOCK_ROOT"),OS.get_environment("AGL_TOKYO_RAIL_CATALOG")))
			return
		if OS.get_environment("AGL_TOKYO_RAIL_SOUTHWEST") == "1":
			get_tree().quit(preload("res://scripts/tests/build_tokyo_southwest_rail_catalog.gd").new().run(OS.get_environment("AGL_TOKYO_BLOCK_ROOT"),OS.get_environment("AGL_TOKYO_RAIL_CATALOG")))
			return
		get_tree().quit(preload("res://scripts/tests/build_tokyo_rail_catalog.gd").new().run(OS.get_environment("AGL_TOKYO_BLOCK_ROOT"),OS.get_environment("AGL_TOKYO_RAIL_CATALOG")))
		return
	if OS.get_environment("AGL_TOKYO_RAIL_OBSTACLE_EXPORT") != "":
		var exporter := preload("res://scripts/tests/export_tokyo_rail_obstacles.gd")
		var parent_text := OS.get_environment("AGL_TOKYO_RAIL_OBSTACLE_PARENT")
		if parent_text not in ["", "11", "12"]:
			get_tree().quit(1)
			return
		if not preload("res://scripts/tests/test_rail_obstacle_export.gd").checks(exporter):
			get_tree().quit(1)
			return
		get_tree().quit(exporter.run(OS.get_environment("AGL_TOKYO_CANONICAL_CATALOG"), OS.get_environment("AGL_TOKYO_RAIL_OBSTACLE_EXPORT"),12 if parent_text == "" else int(parent_text)))
		return
	if OS.get_environment("AGL_TOKYO_FIXED_ATLAS_BC3")!="":
		get_tree().quit(preload("res://scripts/tests/build_tokyo_fixed_atlas_bc3.gd").run(OS.get_environment("AGL_TOKYO_FIXED_ATLAS_SOURCE"),OS.get_environment("AGL_TOKYO_FIXED_ATLAS_BC3")))
		return
	if OS.get_environment("AGL_TOKYO_SHORELINE_MORPH_BAKE")!="":
		get_tree().quit(preload("res://scripts/tests/build_tokyo_shoreline_morph.gd").run(OS.get_environment("AGL_TOKYO_SHORELINE_DATA"),OS.get_environment("AGL_TOKYO_SHORELINE_MORPH_BAKE")))
		return
	if OS.get_environment("AGL_TOKYO_CUT_REUSE_UNIT") == "1":
		var test: RefCounted = load("res://scripts/tests/test_tokyo_cut_reuse.gd").new()
		test.run()
		get_tree().quit(1 if test._fail>0 else 0)
		return
	if OS.get_environment("AGL_TOKYO_HEIGHT_BITS_VISUAL")!="":
		get_tree().quit(await preload("res://scripts/tests/tokyo_height_bits_visual.gd").run(self,OS.get_environment("AGL_TOKYO_HEIGHT_BITS_SOURCE"),OS.get_environment("AGL_TOKYO_AO_PRELOAD"),OS.get_environment("AGL_TOKYO_HEIGHT_BITS_VISUAL")))
		return
	if OS.get_environment("AGL_TOKYO_SHORELINE_BAKE") != "":
		get_tree().quit(preload("res://scripts/tests/build_tokyo_shoreline_lod.gd").run(OS.get_environment("AGL_TOKYO_SHORELINE_DATA"),OS.get_environment("AGL_TOKYO_SHORELINE_BAKE")))
		return
	if OS.get_environment("AGL_TOKYO_AO_BC4_OUT") != "":
		get_tree().quit(preload("res://scripts/tests/build_tokyo_ao_bc4.gd").run(OS.get_environment("AGL_TOKYO_AO_BC4_SOURCE"),OS.get_environment("AGL_TOKYO_AO_BC4_OUT")))
		return
	if OS.get_environment("AGL_TOKYO_BLOCK_CATALOG_UNIT") == "1":
		var test: RefCounted = load("res://scripts/tests/test_tokyo_block_catalog.gd").new()
		test.run()
		get_tree().quit(1 if test._fail>0 else 0)
		return
	if OS.get_environment("AGL_TOKYO_REINDEX_NEAR") != "":
		var script: Script = load("res://scripts/tests/build_tokyo_reindexed_near.gd")
		get_tree().quit(script.run(OS.get_environment("AGL_TOKYO_CANONICAL_CATALOG"),OS.get_environment("AGL_TOKYO_REINDEX_NEAR")) if script != null and script.can_instantiate() else 1)
		return
	if OS.get_environment("AGL_TOKYO_REINDEX_UNIT") == "1":
		var test: RefCounted = load("res://scripts/tests/test_tokyo_packed_mesh_join.gd").new()
		get_tree().quit(1 if int(test.run().fail)>0 else 0)
		return
	if OS.get_environment("AGL_TOKYO_BLOCK_CATALOG") != "":
		var script: Script = load("res://scripts/tests/build_tokyo_street_catalog.gd" if OS.get_environment("AGL_TOKYO_STREET_CATALOG")=="1" else "res://scripts/tests/build_tokyo_block_catalog.gd")
		get_tree().quit(script.new().run(OS.get_environment("AGL_TOKYO_BLOCK_ROOT"),OS.get_environment("AGL_TOKYO_BLOCK_CATALOG")) if script != null and script.can_instantiate() else 1)
		return
	if OS.get_environment("AGL_TOKYO_FIXED_EXPORT") != "":
		var script: Script = load("res://scripts/tests/export_tokyo_fixed_mesh.gd")
		var configuration := "lod1_full" if OS.get_environment("AGL_TOKYO_FIXED_EXPORT_LOD1")=="1" else "lod2_full"
		if not OS.get_environment("AGL_TOKYO_FIXED_EXPORT_CONFIG").is_empty():
			configuration=OS.get_environment("AGL_TOKYO_FIXED_EXPORT_CONFIG")
		get_tree().quit(script.run(OS.get_environment("AGL_TOKYO_CANONICAL_CATALOG"),OS.get_environment("AGL_TOKYO_FIXED_EXPORT"),configuration) if script != null and script.can_instantiate() else 1)
		return
	if OS.get_environment("AGL_TOKYO_CROSS_COMPONENT_BUILD") != "":
		var script: Script = load("res://scripts/tests/build_tokyo_cross_lod_components.gd")
		get_tree().quit(script.run(OS.get_environment("AGL_TOKYO_CANONICAL_CATALOG"),OS.get_environment("AGL_TOKYO_CROSS_COMPONENT_BUILD")) if script != null and script.can_instantiate() else 1)
		return
	if OS.get_environment("AGL_TOKYO_CROSS_COMPONENT_UNIT") == "1":
		var test: RefCounted = load("res://scripts/tests/test_tokyo_cross_lod_components.gd").new()
		test.run()
		var failures: int = test._fail
		if OS.get_environment("AGL_TOKYO_COMPONENTS") != "":
			failures += await test.lifecycle(self,OS.get_environment("AGL_TOKYO_COMPONENTS"),OS.get_environment("AGL_TOKYO_CANONICAL_CATALOG"))
		get_tree().quit(1 if failures else 0)
		return
	if OS.get_environment("AGL_TOKYO_TILE_GROUND_UNIT") == "1":
		var test: RefCounted = load("res://scripts/tests/test_tokyo_tile_ground.gd").new()
		test.run()
		var failures: int = test._fail + await test.lifecycle(self)
		failures += await preload("res://scripts/tests/test_tokyo_shoreline_layer.gd").lifecycle(self)
		get_tree().quit(1 if failures else 0)
		return
	if OS.get_environment("AGL_TOKYO_COMPONENT_UNIT") == "1":
		var test: RefCounted = load("res://scripts/tests/test_tokyo_components.gd").new()
		test.run()
		var failures: int = test._fail + await test.lifecycle(self, OS.get_environment("AGL_TOKYO_COMPONENTS"), OS.get_environment("AGL_TOKYO_CANONICAL_CATALOG"))
		get_tree().quit(1 if failures else 0)
		return
	if OS.get_environment("AGL_TOKYO_COMPONENT_BUILD") != "":
		var script: Script = load("res://scripts/tests/build_tokyo_mesh_components.gd")
		get_tree().quit(script.run(OS.get_environment("AGL_TOKYO_COMPONENT_SOURCE"), OS.get_environment("AGL_TOKYO_CANONICAL_CATALOG"), OS.get_environment("AGL_TOKYO_COMPONENT_BUILD")) if script != null and script.can_instantiate() else 1)
		return
	if OS.get_environment("AGL_TOKYO_SHARED_UNIT") == "1":
		var test: RefCounted = load("res://scripts/tests/test_tokyo_shared_page.gd").new()
		test.run()
		get_tree().quit(1 if test._fail else 0)
		return
	if OS.get_environment("AGL_TOKYO_SHARED_STREAM") != "":
		var script: Script = load("res://scripts/tests/tokyo_shared_stream_case.gd")
		get_tree().quit(await script.run(self, OS.get_environment("AGL_TOKYO_SHARED_STREAM"), OS.get_environment("AGL_TOKYO_SHARED_RESULT")) if script != null and script.can_instantiate() else 1)
		return
	if OS.get_environment("AGL_TOKYO_SHARED_BUILD") != "":
		var script: Script = load("res://scripts/tests/build_tokyo_shared_pages.gd")
		get_tree().quit(script.run(OS.get_environment("AGL_TOKYO_CANONICAL_CATALOG"), OS.get_environment("AGL_TOKYO_SHARED_BUILD")) if script != null and script.can_instantiate() else 1)
		return
	if OS.get_environment("AGL_TOKYO_LOW_ROOF_MODE") != "":
		var script: Script = load("res://scripts/tests/tokyo_low_roof_candidate.gd")
		get_tree().quit(script.run() if script != null and script.can_instantiate() else 1)
		return
	if OS.get_environment("AGL_TOKYO_AO_UNIT") == "1":
		var test: RefCounted = load("res://scripts/tests/test_tokyo_ao.gd").new()
		test.run()
		var failures: int = test._fail + await test.lifecycle(self)
		get_tree().quit(1 if failures else 0)
		return
	if OS.get_environment("AGL_TOKYO_AO_EXPORT") != "":
		var script: Script = load("res://scripts/tests/export_tokyo_ao.gd")
		get_tree().quit(script.run(OS.get_environment("AGL_TOKYO_CANONICAL_CATALOG"), OS.get_environment("AGL_TOKYO_AO_EXPORT"), OS.get_environment("AGL_TOKYO_AO_REGION")))
		return
	if OS.get_environment("AGL_TOKYO_CANONICAL_RUNTIME") == "1":
		var script: Script = load("res://scripts/tests/tokyo_canonical_lifecycle_case.gd")
		if script == null or not script.can_instantiate():
			get_tree().quit(1)
			return
		get_tree().quit(await script.new().run(self))
		return
	if OS.get_environment("AGL_TOKYO_COVERAGE_CONFIG") != "":
		var script: Script = load("res://scripts/tests/build_tokyo_source_coverage.gd")
		if script == null or not script.can_instantiate():
			get_tree().quit(1)
			return
		get_tree().quit(script.new().run())
		return
	if OS.get_environment("AGL_TOKYO_CELLS_PRELOAD_TEST") == "1":
		var script: Script = load("res://scripts/tests/tokyo_cells_preload_case.gd")
		if script == null or not script.can_instantiate():
			get_tree().quit(1)
			return
		get_tree().quit(await script.new().run(self))
		return
	if OS.get_environment("AGL_TOKYO_STATIC_SHADOW_UNIT") == "1":
		var script: Script = load("res://scripts/tests/test_tokyo_static_shadow.gd")
		if script == null or not script.can_instantiate():
			get_tree().quit(1)
			return
		var test: RefCounted = script.new()
		test.run()
		get_tree().quit(1 if test._fail else 0)
		return
	if OS.get_environment("AGL_TOKYO_FAR_COST_OUT") != "":
		var script: Script = load("res://scripts/tests/export_tokyo_far_costs.gd")
		if script == null or not script.can_instantiate():
			get_tree().quit(1)
			return
		get_tree().quit(script.run(OS.get_environment("AGL_TOKYO_FAR_CLUSTER_BAKE"), OS.get_environment("AGL_TOKYO_FAR_COST_OUT")))
		return
	if OS.get_environment("AGL_TOKYO_FAR_CLUSTER_UNIT") == "1":
		var script: Script = load("res://scripts/tests/test_tokyo_far_clusters.gd")
		if script == null or not script.can_instantiate():
			get_tree().quit(1)
			return
		var test: RefCounted = script.new()
		test.run()
		get_tree().quit(1 if test._fail else 0)
		return
	if OS.get_environment("AGL_TOKYO_FAR_CLUSTER_BAKE") != "":
		var script: Script = load("res://scripts/tests/build_tokyo_far_clusters.gd")
		if script == null or not script.can_instantiate():
			get_tree().quit(1)
			return
		get_tree().quit(script.new().run(OS.get_environment("AGL_TOKYO_FAR_CLUSTER_BAKE"), OS.get_environment("AGL_TOKYO_FAR_CLUSTER_OUT")))
		return
	if OS.get_environment("AGL_TOKYO_GROUND_UNIT") == "1":
		var test: RefCounted = load("res://scripts/tests/test_tokyo_ground_merge.gd").new()
		test.run()
		get_tree().quit(1 if test._fail else 0)
		return
	if OS.get_environment("AGL_TOKYO_GROUND_BAKE") != "":
		var bake: Script = load("res://scripts/tests/bake_tokyo_ground_merge.gd")
		if not bake.can_instantiate():
			get_tree().quit(1)
			return
		get_tree().quit(bake.run(OS.get_environment("AGL_TOKYO_GROUND_BAKE"), OS.get_environment("AGL_TOKYO_GROUND_OUT")))
		return
	if OS.get_environment("AGL_TOKYO_GROUND_EXPORT") == "1":
		var export_script: Script = load("res://scripts/tests/export_tokyo_ground_planes.gd")
		var exporter: RefCounted = export_script.new()
		exporter.run()
		get_tree().quit(1 if exporter._fail else 0)
		return
	var canonical_mode := OS.get_environment("AGL_TOKYO_CANONICAL_MODE")
	if canonical_mode != "":
		var names := {"build": "build_tokyo_canonical_catalog", "stream": "tokyo_canonical_stream_case", "unit": "test_tokyo_canonical_stream", "cuts": "tokyo_canonical_cut_probe"}
		if not names.has(canonical_mode):
			get_tree().quit(1)
			return
		var script: Script = load("res://scripts/tests/" + names[canonical_mode] + ".gd")
		if script == null or not script.can_instantiate():
			get_tree().quit(1)
			return
		var failures := 0
		if canonical_mode == "unit":
			var test: RefCounted = script.new()
			test.run()
			failures = test._fail
		elif canonical_mode == "build":
			failures = script.run(OS.get_environment("AGL_TOKYO_CANONICAL_DIRECTORY"), OS.get_environment("AGL_TOKYO_CANONICAL_CATALOG"))
		elif canonical_mode == "cuts":
			failures = script.run(OS.get_environment("AGL_TOKYO_CANONICAL_CATALOG"), OS.get_environment("AGL_TOKYO_CUT_OUTPUT"))
		else:
			failures = await script.run(self, OS.get_environment("AGL_TOKYO_CANONICAL_CATALOG"))
		get_tree().quit(1 if failures else 0)
		return
	if OS.get_environment("AGL_TOKYO_RID_STREAM") == "1":
		var test: Script = load("res://scripts/tests/tokyo_rid_stream_case.gd")
		get_tree().quit(await test.run(self))
		return
	if OS.get_environment("AGL_TOKYO_RID_REPRO") == "1":
		var probe: Script = load("res://scripts/tests/tokyo_rid_repro.gd")
		get_tree().quit(await probe.run(self))
		return
	if OS.get_environment("AGL_TOKYO_SPATIAL_PLAN") != "":
		var builder: Script = load("res://scripts/tests/build_tokyo_canonical_spatial.gd")
		if builder == null or not builder.can_instantiate():
			get_tree().quit(1)
			return
		get_tree().quit(builder.run())
		return
	if OS.get_environment("AGL_TOKYO_CANONICAL_PLAN") != "":
		var builder: Script = load("res://scripts/tests/build_tokyo_canonical_roofs.gd")
		if builder == null or not builder.can_instantiate():
			get_tree().quit(1)
			return
		get_tree().quit(builder.run(OS.get_environment("AGL_TOKYO_CANONICAL_PLAN"), OS.get_environment("AGL_TOKYO_CANONICAL_OUT"), OS.get_environment("AGL_TOKYO_CANONICAL_AUDIT") == "1"))
		return
	if OS.get_environment("AGL_TOKYO_CANONICAL_EXPORT") != "":
		var exporter: Script = load("res://scripts/tests/export_tokyo_canonical_roofs.gd")
		if exporter == null or not exporter.can_instantiate():
			get_tree().quit(1)
			return
		get_tree().quit(exporter.run(OS.get_environment("AGL_TOKYO_CANONICAL_EXPORT")))
		return
	if OS.get_environment("AGL_TOKYO_SHARED_AUDIT") != "":
		var auditor: Script = load("res://scripts/tests/audit_tokyo_shared_roof_bundle.gd")
		if auditor == null or not auditor.can_instantiate():
			get_tree().quit(1)
			return
		var failures := 0
		for pose in 7:
			failures += auditor.run(OS.get_environment("AGL_TOKYO_SHARED_AUDIT") + "/tmp/tokyo-bay-volume/r50-shared-plan-%02d-c.json" % pose,
				OS.get_environment("AGL_TOKYO_SHARED_AUDIT") + "/bench/results/r50_shared_v2_pose_%02d.res" % pose)
		get_tree().quit(1 if failures else 0)
		return
	if OS.get_environment("AGL_TOKYO_SHARED_BAKE") != "":
		var baker: Script = load("res://scripts/tests/bake_tokyo_shared_roofs.gd")
		if baker == null or not baker.can_instantiate():
			get_tree().quit(1)
			return
		var result := 0
		for pose in 7:
			result += baker.run(OS.get_environment("AGL_TOKYO_SHARED_BAKE") + "/r50-shared-plan-%02d-c.json" % pose,
				"res://bench/results/r50_shared_v2_pose_%02d.res" % pose)
		get_tree().quit(1 if result else 0)
		return
	if OS.get_environment("AGL_TOKYO_GAMEPLAY_UNIT") == "1":
		var script: Script = load("res://scripts/tests/test_tokyo_gameplay_volume.gd")
		if script == null or not script.can_instantiate():
			get_tree().quit(1)
			return
		var test: RefCounted = script.new()
		test.run()
		get_tree().quit(1 if test._fail else 0)
		return
	if OS.get_environment("AGL_TOKYO_PRELOAD_ROUTE") == "1":
		var route_script: Script = load("res://scripts/tests/tokyo_preload_route_probe.gd")
		if route_script == null or not route_script.can_instantiate():
			get_tree().quit(1)
			return
		var probe: Node = route_script.new()
		get_tree().root.add_child.call_deferred(probe)
		probe.call_deferred("run")
		return
	if OS.get_environment("AGL_TOKYO_PRELOAD_LIFECYCLE") == "1":
		var preload_script: Script = load("res://scripts/tests/tokyo_preload_lifecycle_case.gd")
		if preload_script == null or not preload_script.can_instantiate():
			get_tree().quit(1)
			return
		var failures: int = await preload_script.new().run(self)
		get_tree().quit(1 if failures else 0)
		return
	if OS.get_environment("AGL_TOKYO_CLUSTER_LIFECYCLE") == "1":
		var cluster: Script = load("res://scripts/tests/tokyo_cluster_lifecycle_case.gd")
		if cluster == null or not cluster.can_instantiate():
			get_tree().quit(1)
			return
		var stable := OS.get_environment("AGL_TOKYO_CELLS_VARIANT") == "yokohama_cluster_stable"
		var result := 0
		if stable:
			var reuse: RefCounted = load("res://scripts/tests/test_tokyo_cut_reuse.gd").new()
			reuse.run()
			result += reuse._fail
		var overlay_path := "res://scripts/rendering/tokyo_stable_cluster_overlay.gd" if stable else "res://scripts/rendering/tokyo_cluster_overlay.gd"
		result += await cluster.new().run(self, load(overlay_path))
		get_tree().quit(1 if result else 0)
		return
	if OS.get_environment("AGL_TOKYO_HIERARCHY_LIFECYCLE") == "1":
		var candidate: Script = load("res://scripts/tests/tokyo_hierarchical_lifecycle_case.gd")
		if candidate == null or not candidate.can_instantiate():
			get_tree().quit(1)
			return
		var overlay_path := "res://scripts/rendering/tokyo_lod_hierarchical_overlay.gd" if OS.get_environment("AGL_TOKYO_CELLS_VARIANT") == "yokohama_joined_lod_hierarchy" else "res://scripts/rendering/tokyo_hierarchical_overlay.gd"
		var result: int = await candidate.new().run(self, load(overlay_path))
		get_tree().quit(1 if result else 0)
		return
	var test := preload("res://scripts/tests/tokyo_cells_lifecycle_case.gd").new()
	var failures: int = await test.run(self)
	get_tree().quit(1 if failures else 0)
