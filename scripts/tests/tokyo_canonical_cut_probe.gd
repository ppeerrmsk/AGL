extends RefCounted
## 只读目录预检；共享正式投影/切面求解，不把元数据估计冒称GPU提交或Visual。
const Catalog := preload("res://scripts/rendering/tokyo_canonical_catalog.gd")
const Cut := preload("res://scripts/experiments/tokyo_spatial_cut.gd")
const Pair := preload("res://scripts/experiments/tokyo_cluster_cut.gd")
const Volume := preload("res://scripts/rendering/tokyo_volume_overlay.gd")
const Cells := preload("res://scripts/rendering/tokyo_cells_overlay.gd")
const Archive := preload("res://scripts/rendering/tokyo_volume_archive.gd")


static func run(path: String, output_path: String = "") -> int:
	if OS.get_environment("AGL_TOKYO_CAPACITY_PROBE") == "1":
		return preload("res://scripts/tests/tokyo_capacity_probe.gd").run(path,output_path)
	if OS.get_environment("AGL_TOKYO_GUARD2_CATALOG_AUDIT")=="1":
		return preload("res://scripts/tests/tokyo_guard2_catalog_audit.gd").run(path,output_path)
	if OS.get_environment("AGL_TOKYO_DEPOT_UNION")=="1":
		return preload("res://scripts/tests/build_tokyo_depot_union.gd").build(path,output_path)
	if OS.get_environment("AGL_TOKYO_NORTH_PALETTE")=="1":
		return preload("res://scripts/tests/build_tokyo_north_palette.gd").build(path,output_path)
	if OS.get_environment("AGL_TOKYO_REBALANCE_COVERAGE")=="1":
		return preload("res://scripts/tests/build_tokyo_rebalanced_coverage.gd").new().build(path,output_path)
	if OS.get_environment("AGL_TOKYO_REBALANCE_BUILD")=="1":
		return preload("res://scripts/tests/build_tokyo_rebalanced_catalog.gd").new().build(path,output_path)
	if OS.get_environment("AGL_TOKYO_REBALANCE_LAYOUT")=="1":
		return preload("res://scripts/tests/tokyo_rebalanced_layout.gd").run(path,output_path)
	var catalog: Resource = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
	if not catalog is Catalog or not catalog.valid():
		return 1
	var descriptors: Dictionary = catalog.descriptors.duplicate()
	var component_path := OS.get_environment("AGL_TOKYO_CUT_COMPONENTS")
	if not component_path.is_empty():
		var components := preload("res://scripts/rendering/tokyo_component_manifest.gd").read(component_path,catalog,FileAccess.get_sha256(path))
		if components.is_empty():
			return 1
		descriptors.merge(components.pages,true)
	var budget := 96*1024*1024
	var requested_budget := OS.get_environment("AGL_TOKYO_CUT_BUDGET")
	if not requested_budget.is_empty():
		if not requested_budget.is_valid_int() or int(requested_budget)<0 or int(requested_budget)>budget:
			return 1
		budget = int(requested_budget)
	var rows: Array[Dictionary] = []
	var paired: Dictionary = {}
	for name_value: String in Catalog.CONFIGURATIONS:
		var level := int(name_value.substr(3, 1))
		if name_value.ends_with("guarded") or level == 5:
			continue
		var fallback := "lod%d_guarded" % level if level < 4 else "lod5_full"
		var roots: Array[Dictionary] = []
		for n in 16:
			roots.append(Pair.decorate(catalog.configurations[name_value][n], catalog.configurations[fallback][n], descriptors))
		paired[name_value] = roots
	if OS.get_environment("AGL_TOKYO_HANDOFF_INPUT")!="":
		return handoffs(catalog,descriptors,paired,path,OS.get_environment("AGL_TOKYO_HANDOFF_INPUT"),output_path)
	var logical := Vector2(1600, 900)
	var centers: Array[Vector2] = [Vector2(-5600,-2900),Vector2(-5300,-1700),Vector2(-5300,-700)]
	var left_probe := OS.get_environment("AGL_TOKYO_NORTH_LEFT_CUT_PROBE")=="1"
	if left_probe:
		if FileAccess.get_sha256(path) not in ["fbb2da6b32b5e3f75c6ad9c91dadcc07725a9805f1b0effb57ec343c590f81c9","c59753a8ac3779a30ed117cb817ef0861ef262b71db8114227a06bea01039b06"]:
			return 1
		centers=[Vector2(-8050,-3700),Vector2(-7800,-4200),Vector2(-7300,-3520)]
	var failures := 0
	var paired_failures := 0
	for center: Vector2 in centers:
		for scale_value: float in [0.06, 0.13, 0.26, 0.52, 0.96, 0.98, 2.2, 5.0]:
			for rotation_value: float in [0.0, deg_to_rad(14.0)]:
				var canvas := Transform2D(-rotation_value, Vector2.ZERO).scaled(Vector2.ONE * scale_value)
				canvas.origin = logical * 0.5 - canvas.basis_xform(center)
				var inverse := canvas.affine_inverse()
				var view := Rect2(inverse * Vector2.ZERO, Vector2.ZERO)
				for corner: Vector2 in [Vector2(logical.x, 0), logical, Vector2(0, logical.y)]:
					view = view.expand(inverse * corner)
				var ground := Volume.VolumeProjection.ground_basis(canvas, Volume.TILT).inverse()
				var camera := ground * Volume.VolumeProjection.camera_basis(canvas, Volume.TILT).z
				var sun := ground * Basis.from_euler(Vector3(deg_to_rad(-50), deg_to_rad(-35), 0)).z
				var roof := -Vector2(camera.x, camera.z) / camera.y
				var shadow := -Vector2(sun.x, sun.z) / sun.y
				var level := Archive.choose_level(-1, scale_value)
				var name_value := "lod%d_full" % level
				if level == 4 and Cells.relief_enabled(false, scale_value):
					name_value = "lod4_mid"
				var parents: Array[Dictionary] = []
				parents.assign(catalog.configurations[name_value])
				var query := Cut.choose(parents, view, canvas, logical, roof, shadow,16,budget)
				var layers := PackedInt32Array([0, 0, 0])
				var selected_details: Array[Dictionary] = []
				for entry: Dictionary in query.entries:
					if left_probe:
						selected_details.append({"path":entry.path,"parent":entry.parent_id,"cell":entry.cell_id,"ancestor":entry.ancestor_id,"faces":entry.faces,"triangles":entry.triangles,"mask":entry.mask,"boxes":entry.boxes,"has_children":entry.has("children")})
					for kind in 3:
						layers[kind] += int(entry.triangles[kind]) if entry.mask[kind] else 0
				var pair_query := query
				if paired.has(name_value):
					parents.assign(paired[name_value])
					pair_query = Cut.choose(parents, view, canvas, logical, roof, shadow,16,budget)
				var alternatives: Dictionary = {}
				if level == 4:
					for alternative: String in ["lod4_mid","lod4_full","lod5_full"]:
						parents.assign(paired.get(alternative,catalog.configurations[alternative]))
						var other := Cut.choose(parents,view,canvas,logical,roof,shadow,16,budget)
						alternatives[alternative] = {"faces":other.triangles,"bytes":other.bytes,"active":other.active,"within_budget":other.within_budget}
				failures += int(not query.within_budget)
				paired_failures += int(not pair_query.within_budget)
				rows.append({"center": [center.x, center.y], "scale": scale_value, "rotation": rotation_value,
					"configuration": name_value, "active": query.active, "faces_estimate": query.triangles,
					"bytes": query.bytes, "within_budget": query.within_budget, "layers_estimate": layers,
					"paired_active": pair_query.active, "paired_bytes": pair_query.bytes,
					"paired_proxy_faces": pair_query.triangles, "paired_within_budget": pair_query.within_budget,"alternatives":alternatives,"selected_details":selected_details})
	var output := path.get_basename() + "-cuts.json" if output_path.is_empty() else output_path
	var file := FileAccess.open(output, FileAccess.WRITE)
	if file == null:
		return 1
	file.store_string(JSON.stringify({"metadata_only": true, "visual_acceptance": false, "logical_size": [1600, 900],
		"lod4_fallback_is_conservative_lod5_cost_only": true,"geometry_budget":budget,"component_metadata":not component_path.is_empty(),"catalog_sha256":FileAccess.get_sha256(path), "rows": rows, "budget_failures": failures,
		"paired_budget_failures": paired_failures}, "\t"))
	file.close()
	print("[Tokyo canonical cut probe] poses=", rows.size(), " budget_failures=", failures,
		" paired_budget_failures=", paired_failures, " metadata_only=true output=", output)
	return 0


static func handoffs(catalog: Resource, descriptors: Dictionary, paired: Dictionary, path: String, input: String, output: String) -> int:
	var records: Variant = JSON.parse_string(FileAccess.get_file_as_string(input))
	if not records is Array or records.is_empty() or output.is_empty():
		return 1
	var rows: Array[Dictionary] = []
	var reuse := preload("res://scripts/experiments/tokyo_cut_reuse.gd")
	var hierarchy := preload("res://scripts/rendering/tokyo_hierarchical_overlay.gd")
	for record: Dictionary in records:
		if record.catalog_sha256!=FileAccess.get_sha256(path) or record.planned.is_empty():
			return 1
		var configuration: String = descriptors[record.planned[0]].canonical_identity.configuration
		var parents: Array[Dictionary] = []
		parents.assign(paired.get(configuration,catalog.configurations[configuration]))
		var spatial: Array[Dictionary] = []
		for old_path: String in record.current:
			var identity: Dictionary = descriptors[old_path].canonical_identity
			spatial.append({"parent_id":identity.parent,"cell_id":identity.cell,"ancestor_id":identity.ancestor})
		var pinned := PackedStringArray(record.pinned)
		var base := hierarchy.union_bytes(pinned,PackedStringArray(),descriptors)
		if base!=int(record.current_bytes) or base>int(record.budget):
			return 1
		var c: Array = record.canvas
		var canvas := Transform2D(Vector2(c[0],c[1]),Vector2(c[2],c[3]),Vector2(c[4],c[5]))
		var logical := Vector2(record.logical[0],record.logical[1])
		var inverse := canvas.affine_inverse()
		var view := Rect2(inverse*Vector2.ZERO,Vector2.ZERO)
		for corner: Vector2 in [Vector2(logical.x,0),logical,Vector2(0,logical.y)]:
			view = view.expand(inverse*corner)
		var roof := Vector2(record.roof[0],record.roof[1])
		var shadow := Vector2(record.shadow[0],record.shadow[1])
		var context := {"view":view,"canvas":canvas,"logical":logical,"roof":roof,"shadow":shadow}
		var same := reuse.corresponding_cut(spatial,parents)
		var incremental := reuse.incremental_parents(parents,pinned,descriptors)
		if incremental.is_empty():
			return 1
		var query := Cut.choose(incremental,view,canvas,logical,roof,shadow,16,int(record.budget)-base)
		var entries: Array[Dictionary] = []
		entries.assign(query.entries)
		var total := hierarchy.union_bytes(Pair.paths(entries),pinned,descriptors)
		var fallback_alternatives: Array[Dictionary] = []
		var target_level := int(configuration.substr(3,1))
		var current_level := int(str(record.configuration).substr(3,1))
		# 只读诊断：缩远时试算共用更细的近景备用，尚不证明跨档表现合同。
		if configuration.ends_with("full") and target_level < current_level and current_level < 4:
			var fallback_name := "lod%d_guarded" % current_level
			var alternate_parents: Array[Dictionary] = []
			for parent_index in 16:
				alternate_parents.append(Pair.decorate(catalog.configurations[configuration][parent_index],catalog.configurations[fallback_name][parent_index],descriptors))
			var alternate_cost := reuse.incremental_parents(alternate_parents,pinned,descriptors)
			var alternate_query := Cut.choose(alternate_cost,view,canvas,logical,roof,shadow,16,int(record.budget)-base)
			var alternate_entries: Array[Dictionary] = []
			alternate_entries.assign(alternate_query.entries)
			var alternate_union := hierarchy.union_bytes(Pair.paths(alternate_entries),pinned,descriptors)
			fallback_alternatives.append({"fallback":fallback_name,"union_bytes":alternate_union,"fits":alternate_union<=int(record.budget),
				"covers":reuse.covers(alternate_entries,alternate_parents,context),"faces_proxy":alternate_query.triangles,
				"active":alternate_query.active,"near_contract_proven":false,"paths":Pair.paths(alternate_entries)})
		rows.append({"frame":record.frame,"scale":record.scale,"configuration":record.configuration,"target":configuration,"budget":record.budget,
			"original_union":record.union_bytes,"same_partition_covers":reuse.covers(same,parents,context),"same_partition_union":hierarchy.union_bytes(Pair.paths(same),pinned,descriptors),
			"incremental_covers":reuse.covers(entries,parents,context),"incremental_union":total,"incremental_count":query.active,"incremental_faces_proxy":query.triangles,"fits":total<=int(record.budget),"fallback_alternatives":fallback_alternatives})
	var file := FileAccess.open(output,FileAccess.WRITE)
	if file==null:
		return 1
	file.store_string(JSON.stringify({"metadata_only":true,"runtime_mutation":false,"rows":rows},"\t"))
	print("[Tokyo handoff probe] rows=",rows.size()," offline_only=true output=",output)
	return 0
