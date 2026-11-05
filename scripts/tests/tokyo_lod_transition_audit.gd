extends RefCounted
## 只读几何交接容量探针；不把元数据可解当作连续显示通过。

static func run(map: Node) -> void:
	var center: Vector2=map._last_canvas.affine_inverse()*(map._last_size*0.5)
	for scale: float in [0.9,1.0,1.05,1.1,1.15,1.2,1.24]:
		var coarse := preload("res://scripts/rendering/tokyo_hlod_manifest.gd").select(map._catalogs[4],center,scale,0.0,map._last_size,false,map.display_budget)
		for config: String in ["lod4_full","lod5_full"]:
			var cut: Dictionary=map._native.select(center,scale,0.0,map._last_size,config,map.display_budget)
			var candidates: Array=[]
			for key: Array in map._native._selection_solutions:
				if key[0]!=config or key[1]!=center or key[2]!=scale or key[4]!=map._last_size: continue
				for state: Dictionary in map._native._selection_solutions[key].frontier:
					if state.active+coarse.keys.size()<=16 and state.faces+coarse.triangles<=240000 and state.bytes+coarse.bytes<=map.display_budget:
						candidates.append([state.active,state.faces,state.bytes])
			print("[LODPair] ",JSON.stringify({"scale":scale,"config":config,"native_pages":cut.get("active",0),"native_faces":cut.get("triangles",0),"coarse_pages":coarse.keys.size(),"coarse_faces":coarse.triangles,"paired_candidates":candidates}))
