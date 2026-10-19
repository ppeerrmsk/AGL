extends RefCounted
## 离线：按现存XYZ连通体完整替换，不重建保留层，不在运行时计算。
const Selection := preload("res://scripts/tests/tokyo_residential_selection.gd")
const Read := preload("res://scripts/experiments/tokyo_packed_mesh_reindex.gd")
const Subset := preload("res://scripts/tests/build_tokyo_path_lod.gd")
const Diff := preload("res://scripts/experiments/tokyo_packed_mesh_difference.gd")
const Join := preload("res://scripts/experiments/tokyo_packed_mesh_join.gd")
const Preview := preload("res://scripts/tests/tokyo_residential_preview.gd")
const Count := preload("res://scripts/experiments/tokyo_indexed_mesh.gd")

static func checks() -> bool:
	var blocks: Array=[]
	for x: float in [-5590.0,-5580.0]:
		var ring: Array=[[x,-2890.0],[x+4,-2890.0],[x+4,-2886.0],[x,-2886.0]]
		blocks.append({"height":3.2,"rings":[ring],"roof":[[ring[0],ring[1],ring[2]],[ring[0],ring[2],ring[3]]]})
	var mesh := Count.pack(Preview.blocks_mesh(blocks))
	var outline: Array=[[-5590.,-2890.],[-5576.,-2890.],[-5576.,-2886.],[-5590.,-2886.]]
	var plan := {"height_m":6.4,"outer":outline,"triangles":[outline[0],outline[1],outline[2],outline[0],outline[2],outline[3]]}
	var before := Read.corner_digest(mesh)
	var result := merge_mesh(mesh,[plan])
	if result.is_empty() or result.groups!=1 or result.saved<=0 or Read.corner_digest(mesh)!=before: return false
	blocks[0].height=12.0
	var protected := Count.pack(Preview.blocks_mesh(blocks))
	result=merge_mesh(protected,[plan])
	return not result.is_empty() and result.groups==0 and Read.corner_digest(result.mesh)==Read.corner_digest(protected)

static func merge_mesh(mesh: ArrayMesh, plans: Array) -> Dictionary:
	if mesh.get_surface_count()==0: return {"mesh":mesh,"groups":0,"saved":0}
	if not Diff.supported(mesh): return {}
	var bounds := mesh.get_aabb()
	var area := Rect2(Vector2(bounds.position.x,bounds.position.z),Vector2(bounds.size.x,bounds.size.z))
	var shapes: Array[PackedVector2Array]=[]
	var blocks: Array=[]
	for plan: Dictionary in plans:
		if not is_equal_approx(float(plan.height_m),6.4): continue
		var shape := PackedVector2Array()
		for point: Array in plan.outer: shape.append(Vector2(point[0],point[1]))
		var box := Rect2(shape[0],Vector2.ZERO)
		for point: Vector2 in shape: box=box.expand(point)
		# 同一500world最细空间叶内，避免新体块跨页被重复画。
		if not area.grow(0.002).encloses(box) or Vector2i((box.position-Vector2(-16300,-15700))/500.0)!=Vector2i((box.end-Vector2(-16300,-15700))/500.0): continue
		shapes.append(shape)
		var roof: Array=[]
		for i in range(0,plan.triangles.size(),3): roof.append(plan.triangles.slice(i,i+3))
		blocks.append({"height":3.2,"roof":roof,"rings":[plan.outer]})
	if shapes.is_empty(): return {"mesh":mesh,"groups":0,"saved":0}
	var grid: Dictionary={}
	for i in shapes.size():
		var box := Rect2(shapes[i][0],Vector2.ZERO)
		for p: Vector2 in shapes[i]: box=box.expand(p)
		for y in range(floori(box.position.y/32),floori(box.end.y/32)+1):
			for x in range(floori(box.position.x/32),floori(box.end.x/32)+1):
				var key := Vector2i(x,y)
				if not grid.has(key): grid[key]=[]
				grid[key].append(i)
	var vertices: PackedVector3Array=mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var data := Read._read(mesh)
	var count: int=data.indices.size()/3
	var parents := PackedInt32Array();parents.resize(count)
	var owners: Dictionary={}
	for i in count:
		parents[i]=i
		for corner in 3:
			var p := vertices[data.indices[i*3+corner]]
			if owners.has(p):
				var a := Selection.root_of(parents,i)
				var b := Selection.root_of(parents,owners[p])
				parents[maxi(a,b)]=mini(a,b)
			else: owners[p]=i
	var connected: Dictionary={}
	for i in count:
		var id := Selection.root_of(parents,i)
		if not connected.has(id): connected[id]=PackedInt32Array()
		var indices: PackedInt32Array=connected[id]
		indices.append_array(data.indices.slice(i*3,i*3+3));connected[id]=indices
	var assignment: Dictionary={}
	var blocked: Dictionary={}
	var totals: Dictionary={}
	for id: int in connected:
		var indices: PackedInt32Array=connected[id]
		var first := vertices[indices[0]]
		var box := Rect2(Vector2(first.x,first.z),Vector2.ZERO)
		var label := -2
		var low := true
		var visited: Dictionary={}
		for index: int in indices:
			var p := vertices[index]
			if visited.has(p): continue
			visited[p]=true
			var q := Vector2(p.x,p.z);box=box.expand(q)
			low=low and p.y>=-0.01 and p.y<=3.21
			var found := -1
			for n: int in grid.get(Vector2i(floori(q.x/32),floori(q.y/32)),[]):
				if Selection.inside(q,[shapes[n]]): found=n;break
			if label==-2: label=found
			elif label!=found: label=-1
		if low and label>=0:
			assignment[id]=label
			var total: Dictionary=totals.get(label,{"count":0,"faces":0})
			total.count+=1;total.faces+=indices.size()/3;totals[label]=total
		else:
			# 保留体的包围矩形也不容新块侵入；宁可不合并，不能压住大楼/现有街坊。
			var nearby: Dictionary={}
			for y in range(floori(box.position.y/32),floori(box.end.y/32)+1):
				for x in range(floori(box.position.x/32),floori(box.end.x/32)+1):
					for n: int in grid.get(Vector2i(x,y),[]): nearby[n]=true
			var rectangle := PackedVector2Array([box.position,Vector2(box.end.x,box.position.y),box.end,Vector2(box.position.x,box.end.y)])
			for n: int in nearby:
				if not Geometry2D.intersect_polygons(rectangle,shapes[n]).is_empty(): blocked[n]=true
	var accepted: Dictionary={}
	var additions: Array=[]
	for n: int in totals:
		var faces: int=blocks[n].roof.size()+2*shapes[n].size()
		if not blocked.has(n) and totals[n].count>=2 and totals[n].faces>faces:
			accepted[n]=true;additions.append(blocks[n])
	if accepted.is_empty(): return {"mesh":mesh,"groups":0,"saved":0}
	var kept := PackedInt32Array();var removed := PackedInt32Array()
	for id: int in connected:
		if accepted.has(assignment.get(id,-1)): removed.append_array(connected[id])
		else: kept.append_array(connected[id])
	var kept_mesh := Subset.subset(mesh,kept)
	if not Diff.conserved(mesh,kept_mesh,Subset.subset(mesh,removed)): return {}
	var addition := Count.pack(Preview.blocks_mesh(additions))
	var joined := Join.join([kept_mesh,addition])
	if not Join.conserved(joined,[kept_mesh,addition]): return {}
	joined=Read.repack(joined)
	if Read.decoded_bytes(joined)>Read.decoded_bytes(mesh): return {"mesh":mesh,"groups":0,"saved":0,"rejected":"bytes"}
	return {"mesh":joined,"groups":accepted.size(),"saved":Count.triangles(mesh)-Count.triangles(joined),"retained_exact":true}
