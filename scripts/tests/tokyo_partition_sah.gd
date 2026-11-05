extends RefCounted
## 离线分区按实际三角包络选择切线；不改动任何顶点或运行时预算。

static func choose(meshes: Array[ArrayMesh], view_size: Vector2 = Vector2(1200,675)) -> Dictionary:
	var all_centers := PackedVector2Array()
	for mesh: ArrayMesh in meshes: all_centers.append_array(preload("res://scripts/experiments/tokyo_spatial_split.gd").centers(mesh))
	if all_centers.is_empty(): return {}
	var bounds := Rect2(all_centers[0],Vector2.ZERO)
	for point: Vector2 in all_centers: bounds=bounds.expand(point)
	var projection := preload("res://scripts/experiments/volume_projection.gd")
	var ray := projection.ground_basis(Transform2D.IDENTITY,deg_to_rad(38)).inverse()*projection.camera_basis(Transform2D.IDENTITY,deg_to_rad(38)).z
	var roof := -Vector2(ray.x,ray.z)/ray.y
	var best := INF
	var result := {}
	for axis in 2:
		if bounds.size[axis]<=0.001: continue
		var bins: Array=[]
		for n in 16: bins.append({"counts":[0,0,0],"boxes":[AABB(),AABB(),AABB()]})
		for kind in meshes.size():
			var mesh: ArrayMesh=meshes[kind]
			if mesh.get_surface_count()==0: continue
			var arrays := mesh.surface_get_arrays(0)
			var positions: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
			var indices: PackedInt32Array=arrays[Mesh.ARRAY_INDEX]
			var count := indices.size() if not indices.is_empty() else positions.size()
			for offset in range(0,count,3):
				var first: Vector3=positions[indices[offset] if not indices.is_empty() else offset]
				var box := AABB(first,Vector3.ZERO)
				var center := Vector3.ZERO
				for corner in 3:
					var point: Vector3=positions[indices[offset+corner] if not indices.is_empty() else offset+corner]
					box=box.expand(point);center+=point/3.0
				var index := clampi(int((Vector2(center.x,center.z)[axis]-bounds.position[axis])/bounds.size[axis]*16.0),0,15)
				var bin: Dictionary=bins[index]
				bin.boxes[kind]=box if bin.counts[kind]==0 else bin.boxes[kind].merge(box)
				bin.counts[kind]+=1
		for boundary in range(1,16):
			var score := 0.0
			var valid := true
			for side in 2:
				var total := 0
				for kind in 3:
					var count := 0
					var box := AABB()
					for n in range(0 if side==0 else boundary,boundary if side==0 else 16):
						if bins[n].counts[kind]==0: continue
						box=bins[n].boxes[kind] if count==0 else box.merge(bins[n].boxes[kind])
						count+=int(bins[n].counts[kind])
					if count==0: continue
					total+=count
					var extent: Vector2=preload("res://scripts/rendering/tokyo_cells_overlay.gd").projected_layer_bounds(box,roof,Vector2.ZERO).size
					score+=count*(extent.x*extent.y+extent.x*view_size.y+extent.y*view_size.x)
				if total==0: valid=false
			if valid and score<best:
				best=score;result={"axis":axis,"threshold":bounds.position[axis]+bounds.size[axis]*boundary/16.0}
	return result
