extends RefCounted
## 固定世界网格组合原型；只重组引用，不生成或简化几何，不授予运行时覆盖资格。
const Overlay := preload("res://scripts/rendering/tokyo_cells_overlay.gd")
const MapProjection := preload("res://scripts/experiments/volume_projection.gd")


static func run(native: RefCounted, input: Dictionary) -> int:
	var candidate_cells: Array=[]
	if input.has("shared_low_cells"):
		var binding: Dictionary=input.shared_low_cells
		if FileAccess.get_sha256(binding.path)!=binding.sha256: return 1
		var report: Variant=JSON.parse_string(FileAccess.get_file_as_string(binding.path))
		if not report is Dictionary or not report.get("complete_source_root",false): return 1
		for row: Dictionary in report.cells:
			if not row.get("exact",false) or FileAccess.get_sha256(row.path)!=row.sha256: return 1
			candidate_cells.append(row)
	var leaves: Array=[]
	var stack: Array=native._grid_native_ground.duplicate()
	while not stack.is_empty():
		var node: Dictionary=stack.pop_back()
		if not node.get("children",[]).is_empty(): stack.append_array(node.children)
		else: leaves.append(node)
	var samples: Array=[]
	for pose: Array in input.audit_poses:
		var scale_value := float(pose[2])
		var size := Vector2(1600,900)
		var canvas := Transform2D(0.0,Vector2.ZERO).scaled(Vector2.ONE*scale_value)
		canvas.origin=size*0.5-canvas*Vector2(pose[0],pose[1])
		var view := Rect2(canvas.affine_inverse()*Vector2.ZERO,size/scale_value)
		var ray: Vector3=MapProjection.ground_basis(canvas,deg_to_rad(38)).inverse()*MapProjection.camera_basis(canvas,deg_to_rad(38)).z
		var roof := -Vector2(ray.x,ray.z)/ray.y
		var pieces: Array=[]
		var building_choices: Array=[]
		for entry: Dictionary in native.Query.query(native._grid_index,view,canvas,size,roof,Vector2.ZERO).entries:
			for kind in 2:
				if not entry.mask[kind]: continue
				var fine_faces := 0
				for child: Dictionary in native._grid_fine[entry.path][kind]:
					if Overlay.intersects_view(Overlay.projected_layer_bounds(child.box,roof,Vector2.ZERO),view,canvas,size):
						pieces.append({"box":child.box,"faces":int(child.faces),"components":child.components,"kind":kind,"source":entry.path})
						fine_faces+=int(child.faces)
				building_choices.append({"source":entry.path,"kind":kind,"fine_faces":fine_faces,"coarse_faces":int(entry.triangles[kind])})
		for entry: Dictionary in leaves:
			var visible: Dictionary=native.Select.visible(entry,view,canvas,size,roof,Vector2.ZERO)
			if visible.faces>0:
				pieces.append({"box":entry.boxes[2],"faces":int(visible.faces),"components":native.pages[entry.path].components,"kind":2,"source":entry.path})
		var physical: Dictionary={}
		var triangle_cost: Dictionary={}
		if input.get("triangle_visibility",false):
			if input.has("triangle_export") and input.audit_poses.size()!=1: return 1
			triangle_cost=preload("res://scripts/tests/tokyo_triangle_visibility_audit.gd").count(native,pieces,view,canvas,size,roof,input.get("triangle_export",""))
			if triangle_cost.is_empty(): return 1
		var faces := 0
		for piece: Dictionary in pieces:
			faces+=int(piece.faces)
			for path: String in piece.components:
				var binding: Dictionary=piece.components[path]
				# 相同物理身份只收费一次；同路径冲突必须拒绝。
				if physical.has(path) and physical[path]!=binding: return 1
				physical[path]=binding
		var bytes := 0
		for binding: Dictionary in physical.values(): bytes+=int(binding.bytes)
		var options: Array=[]
		for cell_size: int in [512,1024,2048]:
			var groups: Dictionary={}
			for n in pieces.size():
				var box: AABB=pieces[n].box
				var center := box.get_center()
				var key := Vector2i(floori(center.x/cell_size),floori(center.z/cell_size))
				if not groups.has(key): groups[key]=[]
				groups[key].append(n)
			var seen: Dictionary={}
			var grouped_faces := 0
			for indices: Array in groups.values():
				for n: int in indices:
					if seen.has(n): return 1
					seen[n]=true;grouped_faces+=int(pieces[n].faces)
			options.append({"cell_size":cell_size,"logical_pages":groups.size(),"reference_conservation":seen.size()==pieces.size() and grouped_faces==faces,
				"budget_pass":groups.size()<=16 and faces<=240000 and bytes<=192*1024*1024})
		var layer_faces := [0,0,0]
		var largest: Array=[]
		for piece: Dictionary in pieces:
			layer_faces[piece.kind]+=int(piece.faces)
			var box: AABB=piece.box
			largest.append({"kind":piece.kind,"faces":piece.faces,"source":piece.source,"components":piece.components,
				"box":[box.position.x,box.position.y,box.position.z,box.size.x,box.size.y,box.size.z]})
		largest.sort_custom(func(a: Dictionary,b: Dictionary) -> bool: return a.faces>b.faces)
		largest.resize(mini(10,largest.size()))
		var candidate_faces := 0
		var candidate_visible := 0
		for row: Dictionary in candidate_cells:
			var b: Array=row.aabb
			var box := AABB(Vector3(b[0],b[1],b[2]),Vector3(b[3],b[4],b[5]))
			if Overlay.intersects_view(Overlay.projected_layer_bounds(box,roof,Vector2.ZERO),view,canvas,size):
				candidate_faces+=int(row.middle_faces);candidate_visible+=1
		# 未加入其他根低楼，因此仅可用超门结果排除此组合；低于门不授予完整覆盖。
		var lower_bound: int=candidate_faces+layer_faces[1]+layer_faces[2]
		samples.append({"pose":pose,"faces":faces,"layer_faces":layer_faces,"building_choices":building_choices,"largest":largest,"physical_bytes":bytes,"physical_components":physical.size(),"unmerged_mesh_slots":pieces.size(),"options":options,
			"triangle_cost":triangle_cost,"shared_low_tested":not candidate_cells.is_empty(),"shared_low_faces":candidate_faces,"shared_low_visible_cells":candidate_visible,
			"shared_low_joint_lower_bound":lower_bound,"shared_low_joint_rejected":not candidate_cells.is_empty() and lower_bound>240000})
	var file := FileAccess.open(input.output,FileAccess.WRITE)
	if file==null: return 1
	file.store_string(JSON.stringify({"samples":samples,"metadata_only":true,"actual_surfaces_verified":false,"draw_reduction":false,"runtime_coverage_verified":false},"\t"))
	file.close()
	return 0
