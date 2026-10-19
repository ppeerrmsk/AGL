extends RefCounted
const Reuse := preload("res://scripts/experiments/tokyo_cut_reuse.gd")
var _pass := 0
var _fail := 0


func run() -> void:
	var guard := preload("res://scripts/experiments/tokyo_guarded_pair_reuse.gd")
	var pair := preload("res://scripts/experiments/tokyo_cluster_cut.gd")
	var p := _entry("p",Vector3.ZERO,Vector3(10,1,10),10)
	p.merge({"path":"p","parent_id":0,"cell_id":-1,"ancestor_id":-1})
	var c := p.duplicate(true)
	c.key="c"
	c.path="c"
	var b1 := p.duplicate(true)
	b1.key="b1"
	b1.path="b1"
	var b2 := p.duplicate(true)
	b2.key="b2"
	b2.path="b2"
	var pair_descriptors := {}
	for row: Array in [["p","lod1_full",15],["c","lod2_full",20],["b1","lod1_guarded",40],["b2","lod2_guarded",10]]:
		pair_descriptors[row[0]]={"bytes":row[2],"canonical_identity":{"configuration":row[1],"collision":"same","owners":"same","game_sources":"same","parent":0,"cell":-1,"ancestor":-1}}
	var planned: Array[Dictionary]=[pair.decorate(p,b1,pair_descriptors)]
	var current: Array[Dictionary]=[pair.decorate(c,b2,pair_descriptors)]
	var alternative_parents: Array[Dictionary]=[pair.decorate(p,b2,pair_descriptors)]
	var pair_context := {"view":Rect2(-1,-1,20,20),"canvas":Transform2D.IDENTITY,"logical":Vector2(20,20),"roof":Vector2.ZERO,"shadow":Vector2.ZERO}
	var pins := pair.paths(current)
	var frozen := var_to_bytes([planned,current,alternative_parents,pair_descriptors])
	var selected := guard.choose(planned,current,alternative_parents,pair_descriptors,pins,pair_context,50)
	_check(selected.size()==1 and selected[0].path=="p" and selected[0].fallback.path=="b2","guard reuse preserves target geometry and loaded finer fallback")
	_check(var_to_bytes([planned,current,alternative_parents,pair_descriptors])==frozen,"guard reuse leaves canonical data immutable")
	_check(guard.choose(planned,current,alternative_parents,pair_descriptors,pins,pair_context,100).is_empty(),"no reuse when original union fits")
	_check(guard.choose(planned,current,alternative_parents,pair_descriptors,pins,pair_context,44).is_empty(),"reuse cannot exceed remaining joint allowance")
	_check(guard.choose(planned,current,[],pair_descriptors,pins,pair_context,50).is_empty(),"missing alternate coverage refuses")
	for field: String in ["collision","owners","game_sources","parent","cell","ancestor"]:
		var broken := pair_descriptors.duplicate(true)
		broken.b2.canonical_identity[field]="wrong"
		_check(guard.choose(planned,current,alternative_parents,broken,pins,pair_context,50).is_empty(),"guard reuse rejects source or space drift")
	var mixed: Array[Dictionary]=[current[0],planned[0]]
	_check(guard.family(mixed,pair_descriptors,true).is_empty(),"mixed fallback families cannot enter legacy single-family consumer")
	var without_backup: Array[Dictionary]=[c]
	_check(guard.choose(planned,without_backup,alternative_parents,pair_descriptors,pins,pair_context,50).is_empty(),"missing loaded near fallback refuses reuse")
	var near_descriptors := pair_descriptors.duplicate(true)
	near_descriptors.p.canonical_identity.configuration="lod4_full"
	near_descriptors.b2.canonical_identity.configuration="lod5_full"
	var fine := b2.duplicate(true)
	fine.triangles=[5,0,0]
	for data: Dictionary in [p,fine]:
		near_descriptors[data.path].boxes=data.boxes
		near_descriptors[data.path].triangles=data.triangles
	var near_parents: Array[Dictionary]=[fine]
	var near_planned: Array[Dictionary]=[pair.decorate(p,fine,near_descriptors)]
	var near_native := guard.native_index([p,fine])
	var near_frozen := var_to_bytes([near_planned,near_parents,near_descriptors])
	_check(guard.near_choice(near_planned,near_parents,near_descriptors,pair_context,20,near_native).size()==1,"cheaper near geometry reuses complete existing fallback")
	_check(var_to_bytes([near_planned,near_parents,near_descriptors])==near_frozen,"near choice leaves native source and pair immutable")
	var stored_parents: Array = [fine]
	var typed_parents: Array[Dictionary]=[]
	typed_parents.assign(stored_parents)
	_check(guard.near_choice(near_planned,typed_parents,near_descriptors,pair_context,20,near_native).size()==1,"catalog untyped Array is normalized before typed near query")
	var actual_descriptors := near_descriptors.duplicate(true)
	for row: Dictionary in actual_descriptors.values():
		row.erase("boxes")
		row.erase("triangles")
	_check(guard.near_choice(near_planned,near_parents,actual_descriptors,pair_context,20,near_native).size()==1,"real descriptor has only identity and bytes; native configuration tree owns geometry")
	_check(guard.near_choice(near_planned,near_parents,near_descriptors,pair_context,9,near_native).is_empty(),"near selection respects remaining budget")
	_check(guard.near_choice(near_planned,[],near_descriptors,pair_context,20,near_native).is_empty(),"near selection rejects missing coverage tree")
	_check(guard.near_choice(near_planned,near_parents,near_descriptors,pair_context,20).is_empty(),"missing native cost must not silently use zero or proxy")
	for configuration: String in ["lod4_mid","lod3_full","lod5_full"]:
		var wrong := near_descriptors.duplicate(true)
		wrong.p.canonical_identity.configuration=configuration
		_check(guard.near_choice(near_planned,near_parents,wrong,pair_context,20,near_native).is_empty(),"near selection only applies to full4")
	for mutation: String in ["same_faces","more_faces","missing_native","wrong_owner","wrong_type"]:
		var wrong := near_descriptors.duplicate(true)
		var wrong_native := near_native.duplicate(true)
		if mutation=="same_faces": wrong_native.b2.triangles=[10,0,0]
		if mutation=="more_faces": wrong_native.b2.triangles=[11,0,0]
		if mutation=="missing_native": wrong_native.erase("b2")
		if mutation=="wrong_owner": wrong.b2.canonical_identity.owners="other"
		if mutation=="wrong_type": wrong.b2.canonical_identity.parent="0"
		_check(guard.near_choice(near_planned,near_parents,wrong,pair_context,20,wrong_native).is_empty(),"near dominance rejects cost/source drift")
	var descriptors := {"old":{"components":{"shared":{"bytes":20},"old_low":{"bytes":10}}},"new":{"components":{"shared":{"bytes":20},"new_low":{"bytes":15}}},"fine":{"bytes":25}}
	var parents_cost: Array[Dictionary] = [{"path":"new","bytes":60,"fallback":{"path":"fine"},"children":[{"path":"old","bytes":30}]}]
	var before := var_to_bytes(parents_cost)
	var incremental := Reuse.incremental_parents(parents_cost,PackedStringArray(["old","fine"]),descriptors)
	_check(incremental[0].bytes==15,"resident shared and fallback bytes not charged twice")
	_check(incremental[0].children[0].bytes==0,"already resident child has zero additional bytes")
	_check(var_to_bytes(parents_cost)==before,"incremental costs do not mutate catalog or child arrays")
	_check(Reuse.incremental_parents(parents_cost,PackedStringArray(["unknown"]),descriptors).is_empty(),"unknown pinned identity rejects incremental query")
	var unknown: Array[Dictionary] = [{"path":"unknown","bytes":0}]
	_check(Reuse.incremental_parents(unknown,PackedStringArray(["old"]),descriptors)[0].bytes>96*1024*1024,"unknown new identity cannot become affordable after subtraction")
	var target: Array[Dictionary] = [{"key":"mid/root","parent_id":8,"cell_id":-1,"children":[{"key":"mid/leaf","parent_id":8,"cell_id":32,"ancestor_id":-1}]}]
	var old: Array[Dictionary] = [{"key":"full/leaf","parent_id":8,"cell_id":32,"ancestor_id":-1}]
	_check(Reuse.corresponding_cut(old,target)==[target[0].children[0]],"cross configuration preserves spatial leaf")
	_check(Reuse.corresponding_cut([{"parent_id":8,"cell_id":-1}],target)==target,"parent stays parent, not finer children")
	_check(Reuse.corresponding_cut([{"parent_id":9,"cell_id":32}],target).is_empty(),"foreign parent rejected")
	_check(Reuse.corresponding_cut([{"parent_id":8,"cell_id":32,"ancestor_id":99}],target).is_empty(),"foreign ancestor rejected")
	_check(Reuse.corresponding_cut([old[0],old[0]],target).is_empty(),"duplicate target rejected")
	_check(Reuse.corresponding_cut([{"key":"fake"}],target).is_empty(),"missing spatial identity rejected")
	_check(load("res://scripts/rendering/tokyo_stable_cluster_overlay.gd").can_instantiate(), "stable paired controller compiles")
	var left := _entry("left", Vector3.ZERO, Vector3(4, 2, 4), 10)
	var right := _entry("right", Vector3(100, 0, 0), Vector3(4, 2, 4), 10)
	var root := _entry("root", Vector3.ZERO, Vector3(104, 2, 4), 20)
	root["children"] = [left, right]
	var parents: Array[Dictionary] = [root]
	var complete: Array[Dictionary] = [left, right]
	var partial: Array[Dictionary] = [left]
	var context := {"view": Rect2(-10, -10, 130, 40), "canvas": Transform2D(0, Vector2(10, 10)),
		"logical": Vector2(130, 40), "roof": Vector2.ZERO, "shadow": Vector2.ZERO}
	_check(Reuse.covers(complete, parents, context), "complete children cover all visible geometry")
	_check(not Reuse.covers(partial, parents, context), "one missing visible child rejects reuse")
	_check(Reuse.covers([root], parents, context), "canonical parent covers descendants")
	_check(not Reuse.covers([root, left], parents, context), "parent child overlap is not a valid cut")
	_check(not Reuse.covers([left, left, right], parents, context), "duplicate selected identity rejected")
	var foreign := left.duplicate()
	foreign.key = "foreign"
	_check(not Reuse.covers([foreign, right], parents, context), "foreign key cannot disguise missing source coverage")
	context.view = Rect2(-10, -10, 30, 30)
	context.logical = Vector2(30, 30)
	_check(Reuse.covers(partial, parents, context), "fully offscreen child is not required")
	right.boxes[0] = AABB(Vector3(100, 0, 0), Vector3(4, 100, 4))
	root.boxes[0] = AABB(Vector3.ZERO, Vector3(104, 100, 4))
	context.shadow = Vector2(-1, 0)
	_check(not Reuse.covers(partial, parents, context), "offscreen building casting an in-view shadow remains required")
	context.shadow = Vector2.ZERO
	context.roof = Vector2(-1, 0)
	_check(not Reuse.covers(partial, parents, context), "projected tall roof remains required")
	context.roof = Vector2.ZERO
	var native := {"left": left, "right": right, "root": root}
	_check(Reuse.faces(complete, context, native) == 10, "cost counts actual currently visible native geometry")
	var proxy := left.duplicate()
	proxy.triangles = [999, 0, 0]
	_check(Reuse.faces([proxy], context, native) == 10, "paired conservative proxy counts do not masquerade as submitted faces")
	_check(Reuse.faces([foreign], context, native) == 2147483647, "unknown cost fails closed")
	_check(not Reuse.covers([], parents, context), "empty retained cut is not a loaded replacement")
	var overflow: Array[Dictionary] = []
	for n in 17:
		overflow.append(_entry(str(n), Vector3.ZERO, Vector3.ONE, 1))
	_check(not Reuse.covers(overflow, parents, context), "reuse cannot bypass sixteen-slot cap")
	print("[Tokyo cut reuse test] pass=", _pass, " fail=", _fail)


func _entry(key: String, position: Vector3, size: Vector3, count: int) -> Dictionary:
	return {"key": key, "boxes": [AABB(position, size), AABB(), AABB()], "triangles": [count, 0, 0], "bytes": count * 12}


func _check(ok: bool, label: String) -> void:
	if ok:
		_pass += 1
	else:
		_fail += 1
		push_error("Tokyo cut reuse: " + label)
