extends RefCounted
## 显式阻塞诊断：只读真实树与物理组件，不改变运行时槽数、请求或显示。
const Cut := preload("res://scripts/experiments/tokyo_spatial_cut.gd")
const Pair := preload("res://scripts/experiments/tokyo_cluster_cut.gd")
const Hierarchy := preload("res://scripts/rendering/tokyo_hierarchical_overlay.gd")


static func run(map: Node, output: String) -> void:
	var before := _state(map)
	var inverse: Basis = map._city.basis.inverse()
	var camera_ray: Vector3 = inverse * map._camera.basis.z
	var light_ray: Vector3 = inverse * map._sun.basis.z
	var context := {"view":map._cull_view,"canvas":map._last_canvas,"logical":Vector2(map._viewport.size)*map._screen.scale,
		"roof":-Vector2(camera_ray.x,camera_ray.z)/camera_ray.y,"shadow":-Vector2(light_ray.x,light_ray.z)/light_ray.y}
	var desired := "lod%d_full" % int(map._level)
	if map._level==4 and map._relief_active:
		desired="lod4_mid"
	var fallback := "lod%d_guarded" % int(map._level) if map._level<4 else "lod5_full"
	var current: String = map._descriptors[map._current_cut[0].path].canonical_identity.configuration
	var trees := {"current":map._canonical.configurations[current],"desired":map._paired.get(desired,map._canonical.configurations[desired]),
		"fallback":map._canonical.configurations[fallback]}
	var snapshot := {"context":context,"trees":trees,"descriptors":map._descriptors,"before":before,
		"current_configuration":current,"desired_configuration":desired,"fallback_configuration":fallback,
		"current_cut":map._current_cut,"target_cut":map._target_cut,"planned_cut":map._planned_cut,
		"catalog_sha256":map._canonical_sha,"geometry_budget":map._stream.geometry_budget()}
	var file := FileAccess.open(output.path_join("r90-cut-snapshot.bin"),FileAccess.WRITE)
	assert(file!=null)
	file.store_var(snapshot)
	file.close()
	var rows: Array[Dictionary] = []
	var selections: Dictionary = {}
	var frontiers: Dictionary = {}
	var fail := 0
	for cap: int in [16,24,32]:
		for label: String in trees:
			var parents: Array[Dictionary] = []
			parents.assign(trees[label])
			var query := _query(parents,context,cap,int(snapshot.geometry_budget),map._current_paths,map._descriptors)
			var entries: Array[Dictionary] = []
			entries.assign(query.entries)
			var paths := Pair.paths(entries)
			selections["%s_%d" % [label,cap]]=paths
			frontiers["%s_%d" % [label,cap]]=query.frontier
			if cap==16:
				var production := Cut.choose(parents,context.view,context.canvas,context.logical,context.roof,context.shadow,16,int(snapshot.geometry_budget))
				fail+=int(production.entries!=entries)
			var row := {"kind":label,"cap":cap,"active":query.active,"node_upper_bound":int(query.active)*3,"faces":query.faces,
				"own_bytes":Hierarchy.union_bytes(paths,PackedStringArray(),map._descriptors),
				"union_current_bytes":Hierarchy.union_bytes(paths,map._current_paths,map._descriptors),
				"frontier_min_union_bytes":query.min_union,"frontier_states":query.states,"solver_usec":query.usec,"paths":paths}
			rows.append(row)
			print("[R90 capacity] kind=",label," cap=",cap," active=",row.active," faces=",row.faces," own=",row.own_bytes," union=",row.union_current_bytes," frontier_min_union=",row.frontier_min_union_bytes)
	var stages: Array[Dictionary] = []
	for cap: int in [16,24,32]:
		var stage_paths: PackedStringArray = selections["current_%d" % cap]
		var first := Hierarchy.union_bytes(stage_paths,map._current_paths,map._descriptors)
		for target_cap: int in [16,24,32]:
			for label: String in ["desired","fallback"]:
				var second := Hierarchy.union_bytes(stage_paths,selections["%s_%d" % [label,target_cap]],map._descriptors)
				stages.append({"stage_cap":cap,"target_cap":target_cap,"kind":label,"first_union":first,"second_union":second,
					"metadata_fits":first<=int(snapshot.geometry_budget) and second<=int(snapshot.geometry_budget)})
	var paired_frontiers := _pair_frontiers(frontiers,map._current_paths,map._descriptors,int(snapshot.geometry_budget))
	var unchanged := before==_state(map)
	fail+=int(not unchanged)
	file=FileAccess.open(output.path_join("r90-cut-capacity.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"fail":fail,"unchanged":unchanged,"geometry_budget":snapshot.geometry_budget,
		"rows":rows,"stages":stages,"paired_frontiers":paired_frontiers,"runtime_cap":16,"runtime_modified":false,"fps_evidence":false,
		"frontier_exhaustive_for_retained_cost":false,"context":context,"catalog_sha256":map._canonical_sha},"\t"))
	file.close()
	assert(fail==0,"capacity probe must agree with production at 16 and leave live state unchanged")


static func _state(map: Node) -> Dictionary:
	return {"current":map._current_paths.duplicate(),"target":map._target_paths.duplicate(),
		"planned":Pair.paths(map._planned_cut),"stream":map._stream.summary().duplicate(true),"blocked":map._transition_blocked}


static func _query(parents: Array[Dictionary], context: Dictionary, cap: int, budget: int,
		current: PackedStringArray, descriptors: Dictionary) -> Dictionary:
	assert(cap in [16,24,32])
	var start := Time.get_ticks_usec()
	var local := context.duplicate()
	local.cap=cap
	local.visited=0
	var frontier: Array[Dictionary] = [{"entries":[],"active":0,"faces":0,"bytes":0}]
	for parent: Dictionary in parents:
		frontier=Cut._combine(frontier,Cut._frontier(parent,local),cap)
	assert(not frontier.is_empty())
	var best: Dictionary = {}
	var min_union := 0x7fffffffffffffff
	for state: Dictionary in frontier:
		if best.is_empty() or Cut._better(state,best,budget):
			best=state
		var entries: Array[Dictionary] = []
		entries.assign(state.entries)
		min_union=mini(min_union,Hierarchy.union_bytes(Pair.paths(entries),current,descriptors))
	var result := best.duplicate()
	result.min_union=min_union
	result.states=frontier.size()
	result.frontier=frontier
	result.usec=Time.get_ticks_usec()-start
	return result


static func _pair_frontiers(frontiers: Dictionary, current: PackedStringArray, descriptors: Dictionary, budget: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for cap: int in [16,24,32]:
		for target_cap: int in [16,24,32]:
			for label: String in ["desired","fallback"]:
				var best: Dictionary = {}
				var tested := 0
				for stage: Dictionary in frontiers["current_%d" % cap]:
					var stage_entries: Array[Dictionary] = []
					stage_entries.assign(stage.entries)
					var stage_paths := Pair.paths(stage_entries)
					var first := Hierarchy.union_bytes(stage_paths,current,descriptors)
					for target: Dictionary in frontiers["%s_%d" % [label,target_cap]]:
						var target_entries: Array[Dictionary] = []
						target_entries.assign(target.entries)
						var target_paths := Pair.paths(target_entries)
						var second := Hierarchy.union_bytes(stage_paths,target_paths,descriptors)
						tested+=1
						if best.is_empty() or maxi(first,second)<int(best.peak_union):
							best={"stage_cap":cap,"target_cap":target_cap,"kind":label,"first_union":first,"second_union":second,
								"peak_union":maxi(first,second),"metadata_fits":first<=budget and second<=budget,"stage_paths":stage_paths,
								"target_paths":target_paths,"stage_active":stage.active,"target_active":target.active,
								"stage_faces":stage.faces,"target_faces":target.faces}
				best.tested=tested
				result.append(best)
				print("[R90 frontier pair] stage=",cap," target=",target_cap," kind=",label," peak=",best.peak_union," fits=",best.metadata_fits)
	return result
