extends RefCounted
## 以真实包络入格；查询只筛候选，最终可见性仍沿用原投影判断。
const Select := preload("res://scripts/experiments/tokyo_spatial_select.gd")
const STEP := 512.0


static func build(entries: Array) -> Dictionary:
	var bins: Dictionary={}
	var low := 0.0
	var high := 0.0
	for n in entries.size():
		var entry: Dictionary=entries[n]
		for kind in 3:
			if int(entry.triangles[kind])==0: continue
			var box: AABB=entry.boxes[kind]
			low=minf(low,box.position.y);high=maxf(high,box.end.y)
			for x in range(floori(box.position.x/STEP),floori(box.end.x/STEP)+1):
				for z in range(floori(box.position.z/STEP),floori(box.end.z/STEP)+1):
					var key := Vector2i(x,z)
					if not bins.has(key): bins[key]={}
					bins[key][n]=true
	return {"entries":entries,"bins":bins,"low":low,"high":high}


static func query(index: Dictionary, view: Rect2, canvas: Transform2D, size: Vector2,
		roof: Vector2, shadow: Vector2) -> Dictionary:
	var region := view.grow(8.0)
	for shift in [roof,shadow]:
		for height: float in [index.low,index.high]:
			region=region.merge(Rect2(view.position-shift*height,view.size).grow(8.0))
	var candidates: Dictionary={}
	for x in range(floori(region.position.x/STEP),floori(region.end.x/STEP)+1):
		for z in range(floori(region.position.y/STEP),floori(region.end.y/STEP)+1):
			var bin: Dictionary=index.bins.get(Vector2i(x,z),{})
			for n: int in bin: candidates[n]=true
	var ordered: Array=candidates.keys()
	ordered.sort()
	var result: Array=[]
	for n: int in ordered:
		var entry := Select.visible(index.entries[n],view,canvas,size,roof,shadow)
		if entry.faces>0: result.append(entry)
	return {"entries":result,"candidates":ordered.size()}
