extends RefCounted
## 完整树切面动态规划；不能因中间层零收益而错过下一层，也不能丢可见几何。
const Select := preload("res://scripts/experiments/tokyo_spatial_select.gd")


static func choose(parents: Array[Dictionary], view: Rect2, canvas: Transform2D, logical: Vector2,
		roof: Vector2, shadow: Vector2, cap: int = 16, byte_budget: int = 96*1024*1024) -> Dictionary:
	return pick(solve(parents,view,canvas,logical,roof,shadow,cap),byte_budget)


static func solve(parents: Array[Dictionary], view: Rect2, canvas: Transform2D, logical: Vector2,
		roof: Vector2, shadow: Vector2, cap: int = 16, trace_enabled: bool = true) -> Dictionary:
	assert(cap > 0 and cap <= 32)
	var started := Time.get_ticks_usec()
	var context := {"view": view, "canvas": canvas, "logical": logical, "roof": roof, "shadow": shadow, "cap": cap, "visited": 0,
		"trace":trace_enabled and PerfBuckets.frame_trace_enabled,"visible_usec":0,"combine_usec":0}
	var frontier: Array[Dictionary] = [{"entries": [], "active": 0, "faces": 0, "bytes": 0}]
	for parent: Dictionary in parents:
		var branch := _frontier(parent, context)
		# 可见性已证明整个分支为空；与零切面组合不会改变任何候选或稳定顺序。
		if branch.size()==1 and int(branch[0].active)==0: continue
		if frontier.size()==1 and int(frontier[0].active)==0:
			frontier=branch
			continue
		var combine_started := Time.get_ticks_usec() if context.trace else 0
		frontier = _combine(frontier, branch, cap)
		if context.trace: context.combine_usec+=Time.get_ticks_usec()-combine_started
	assert(not frontier.is_empty(), "a complete root cut must fit the active count")
	if context.trace:
		PerfBuckets.tick("tokyo_solver.visible",int(context.visible_usec))
		PerfBuckets.tick("tokyo_solver.combine",int(context.combine_usec))
	return {"frontier":frontier,"visited":context.visited,"solver_usec":Time.get_ticks_usec()-started}


static func pick(solved: Dictionary, byte_budget: int = 96*1024*1024) -> Dictionary:
	assert(byte_budget>=0 and byte_budget<=192*1024*1024)
	var frontier: Array[Dictionary] = solved.frontier
	var best: Dictionary = {}
	for state: Dictionary in frontier:
		if best.is_empty() or _better(state, best, byte_budget):
			best = state
	return {"entries": best.entries.duplicate(), "active": best.active, "triangles": best.faces, "bytes": best.bytes,
		"within_budget": best.bytes <= byte_budget and best.faces <= 240000,
		"solver_usec": solved.solver_usec, "visited": solved.visited, "frontier_states": frontier.size()}


static func _frontier(entry: Dictionary, context: Dictionary) -> Array[Dictionary]:
	context.visited += 1
	# 离线容量探针也直接调用此入口，旧上下文不要求诊断字段。
	var trace := bool(context.get("trace",false))
	var visible_started := Time.get_ticks_usec() if trace else 0
	var visible := Select.visible(entry, context.view, context.canvas, context.logical, context.roof, context.shadow)
	if trace: context.visible_usec+=Time.get_ticks_usec()-visible_started
	var result: Array[Dictionary] = []
	if visible.faces == 0:
		result.append({"entries": [], "active": 0, "faces": 0, "bytes": 0})
		return result
	result.append({"entries": [visible], "active": 1, "faces": visible.faces, "bytes": visible.bytes})
	if entry.has("children") and not entry.children.is_empty():
		var split: Array[Dictionary] = [{"entries": [], "active": 0, "faces": 0, "bytes": 0}]
		for child: Dictionary in entry.children:
			var branch := _frontier(child, context)
			if branch.size()==1 and int(branch[0].active)==0: continue
			if split.size()==1 and int(split[0].active)==0:
				split=branch
				continue
			var combine_started := Time.get_ticks_usec() if trace else 0
			split = _combine(split, branch, int(context.cap))
			if trace: context.combine_usec+=Time.get_ticks_usec()-combine_started
		var insert_started := Time.get_ticks_usec() if trace else 0
		result=_merge_parent(result[0],split)
		if trace: context.combine_usec+=Time.get_ticks_usec()-insert_started
	return result




static func _combine(left: Array[Dictionary], right: Array[Dictionary], cap: int) -> Array[Dictionary]:
	var pairs := left.size()*right.size()
	# 大组合分批筛选，不能超过临时批量后退回二次支配扫描。
	if pairs>64: return _combine_sweep(left,right,cap)
	var result: Array[Dictionary] = []
	for a: Dictionary in left:
		for b: Dictionary in right:
			if int(a.active) + int(b.active) > cap:
				continue
			# 大多数候选立即被支配；连临时Dictionary也只为留下的候选创建。
			var active := int(a.active)+int(b.active)
			var faces := int(a.faces)+int(b.faces)
			var bytes := int(a.bytes)+int(b.bytes)
			var dominated := false
			for state: Dictionary in result:
				if state.active<=active and state.faces<=faces and state.bytes<=bytes:
					dominated=true
					break
			if dominated: continue
			for n in range(result.size()-1,-1,-1):
				var state: Dictionary=result[n]
				if active<=state.active and faces<=state.faces and bytes<=state.bytes: result.remove_at(n)
			result.append({"entries":a.entries+b.entries,"active":active,"faces":faces,"bytes":bytes})
	return result


static func _combine_sweep(left: Array[Dictionary], right: Array[Dictionary], cap: int) -> Array[Dictionary]:
	var costs: Array[Array]=[]
	var pending := 0
	for x in left.size():
		var a: Dictionary=left[x]
		for y in right.size():
			var b: Dictionary=right[y]
			var active := int(a.active)+int(b.active)
			if active<=cap:
				costs.append([int(a.faces)+int(b.faces),active,int(a.bytes)+int(b.bytes),x*right.size()+y])
				pending+=1
				if pending>=131072:
					costs=_pareto_costs(costs,cap)
					pending=0
	var kept := _pareto_costs(costs,cap)
	# 恢复全局原组合序号；分批不能改变同费用的首个资源身份。
	kept.sort_custom(func(a: Array,b: Array) -> bool: return a[3]<b[3])
	var result: Array[Dictionary]=[]
	for cost: Array in kept:
		var pair := int(cost[3])
		var a: Dictionary=left[pair/right.size()]
		var b: Dictionary=right[pair%right.size()]
		result.append({"entries":a.entries+b.entries,"active":cost[1],"faces":cost[0],"bytes":cost[2]})
	return result


static func _pareto_costs(costs: Array[Array], cap: int) -> Array[Array]:
	# 旧前沿与下一批的并集可再次精确筛选；新临时项每批最多131072，前沿不截断。
	costs=_ordered_costs(costs,cap)
	# faces已非递减；Fenwick前缀给出active<=当前的最小bytes，精确证明支配。
	var minima := PackedInt64Array()
	minima.resize(cap+2);minima.fill(9223372036854775807)
	var kept: Array[Array]=[]
	for cost: Array in costs:
		var index := int(cost[1])+1
		var best: int=9223372036854775807
		while index>0:
			best=mini(best,minima[index]);index-=index & -index
		if best<=int(cost[2]): continue
		kept.append(cost)
		index=int(cost[1])+1
		while index<minima.size():
			minima[index]=mini(minima[index],int(cost[2]));index+=index & -index
	return kept


static func _ordered_costs(costs: Array[Array], cap: int) -> Array[Array]:
	if costs.is_empty(): return costs
	var count := costs.size()
	var face_limit: int=9223372036854775807/(cap+1)/count-1
	for cost: Array in costs:
		if int(cost[0])<0 or int(cost[0])>face_limit:
			# 极端输入不允许整数编码溢出；精确比较路径保留。
			costs.sort_custom(func(a: Array,b: Array) -> bool:
				for index in 4:
					if a[index]!=b[index]: return a[index]<b[index]
				return false)
			return costs
	var order := PackedInt64Array()
	order.resize(count)
	for index in count:
		var cost: Array=costs[index]
		order[index]=(int(cost[0])*(cap+1)+int(cost[1]))*count+index
	order.sort()
	var result: Array[Array]=[]
	var group := -1
	var best: Array=[]
	for encoded: int in order:
		var current_group: int=encoded/count
		var cost: Array=costs[encoded%count]
		if current_group!=group:
			if not best.is_empty(): result.append(best)
			group=current_group;best=cost
		elif int(cost[2])<int(best[2]): best=cost
	if not best.is_empty(): result.append(best)
	return result


static func _merge_parent(parent: Dictionary, split: Array[Dictionary]) -> Array[Dictionary]:
	# split已经是完整非支配前沿；成员间再次逐对比较没有信息增益。
	var keep_parent := true
	var children: Array[Dictionary]=[]
	for state: Dictionary in split:
		if parent.active<=state.active and parent.faces<=state.faces and parent.bytes<=state.bytes: continue
		if state.active<=parent.active and state.faces<=parent.faces and state.bytes<=parent.bytes: keep_parent=false
		children.append(state)
	var result: Array[Dictionary]=[]
	if keep_parent: result.append(parent)
	result.append_array(children)
	return result


static func _insert(frontier: Array[Dictionary], candidate: Dictionary) -> bool:
	for state: Dictionary in frontier:
		if state.active <= candidate.active and state.faces <= candidate.faces and state.bytes <= candidate.bytes:
			return false
	for n in range(frontier.size() - 1, -1, -1):
		var state: Dictionary = frontier[n]
		if candidate.active <= state.active and candidate.faces <= state.faces and candidate.bytes <= state.bytes:
			frontier.remove_at(n)
	frontier.append(candidate)
	return true


static func _better(a: Dictionary, b: Dictionary, byte_budget: int = 96*1024*1024) -> bool:
	var a_fits := int(a.bytes) <= byte_budget
	var b_fits := int(b.bytes) <= byte_budget
	if a_fits != b_fits:
		return a_fits
	if a.faces != b.faces:
		return a.faces < b.faces
	if a.bytes != b.bytes:
		return a.bytes < b.bytes
	return a.active < b.active
