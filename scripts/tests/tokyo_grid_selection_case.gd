extends RefCounted
const Read := preload("res://scripts/tests/build_tokyo_grid_dependencies.gd")
const Select := preload("res://scripts/experiments/tokyo_spatial_select.gd")
const Cut := preload("res://scripts/experiments/tokyo_spatial_cut.gd")
const MapProjection := preload("res://scripts/experiments/volume_projection.gd")
const Query := preload("res://scripts/experiments/tokyo_grid_query.gd")


static func run(input: Dictionary) -> int:
	if input.has("cases"):
		for sample: Dictionary in input.cases:
			var request := input.duplicate()
			request.erase("cases");request.merge(sample,true)
			if run(request)!=0: return 1
		return 0
	var dependencies: Variant=Read.read(input.get("grid_selection"))
	var output: String=input.get("output","")
	if not dependencies is Dictionary or not output.is_absolute_path() or FileAccess.file_exists(output): return 1
	var snapshot: Variant=Read.read(dependencies.snapshot)
	if not snapshot is Dictionary: return 1
	var package: Variant=JSON.parse_string(FileAccess.get_file_as_string(snapshot.package.path))
	if FileAccess.get_sha256(snapshot.package.path)!=snapshot.package.sha256 or not package is Dictionary: return 1
	package.native["grid_candidate"]=input.grid_selection
	var native := preload("res://scripts/rendering/tokyo_grid_native.gd").new()
	if not native.read(package.native) or native.catalog_sha!=snapshot.catalog_sha256 or native.ground!=snapshot.ground: return 1
	var audit_binding: Dictionary=dependencies.joined_audit
	if FileAccess.get_sha256(audit_binding.path)!=audit_binding.sha256: return 1
	var audit: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(audit_binding.path))
	var cells: Dictionary={}
	var pieces: Array=[]
	var piece_costs: Dictionary={}
	for record: Dictionary in audit.rows:
		var joined: Variant=Read.read(record.joined)
		if not joined is Dictionary or joined.snapshot!=dependencies.snapshot: return 1
		for page: Dictionary in joined.pages:
			var words: PackedStringArray=String(page.key).split(":")
			var kind := int(words[0])
			piece_costs[page.key]={"faces":page.faces,"bytes":page.bytes,"fine_faces":0,"fine_bytes":0,"pieces":0,"visible":false}
			for origin: Dictionary in page.origins:
				var triangles := PackedInt32Array([0,0,0])
				triangles[kind]=int(origin.faces)
				var boxes: Array=[AABB(),AABB(),AABB()]
				boxes[kind]=origin.component.box
				pieces.append({"path":origin.component.path,"triangles":triangles,"boxes":boxes,"bytes":origin.component.bytes,"group":page.key,"layer":kind,"source":origin.source})
				piece_costs[page.key].fine_bytes+=int(origin.component.bytes)
			var key := words[1]+":"+words[2]
			if not cells.has(key): cells[key]={"path":"grid/"+key,"boxes":[AABB(),AABB(),AABB()],"triangles":PackedInt32Array([0,0,0]),"bytes":0,"components":{}}
			if cells[key].triangles[kind]!=0: return 1
			if not dependencies.pages.has(page.path) or dependencies.pages[page.path].sha256!=page.sha256: return 1
			cells[key].boxes[kind]=page.box
			cells[key].triangles[kind]=page.faces
			cells[key].bytes+=int(page.bytes)
			cells[key].components[page.path]={"bytes":page.bytes,"identity":page.canonical_identity,"layer":kind}
	var pose: Array=input.get("pose",[])
	if pose.size()!=3: return 1
	var center := Vector2(pose[0],pose[1])
	var scale_value := float(pose[2])
	var dimensions: Array=input.get("size",[1600,900])
	if dimensions.size()!=2: return 1
	var size := Vector2(dimensions[0],dimensions[1])
	var canvas := Transform2D(0.0,Vector2.ZERO).scaled(Vector2.ONE*scale_value)
	canvas.origin=size*0.5-canvas*center
	var inverse := canvas.affine_inverse()
	var view := Rect2(inverse*Vector2.ZERO,Vector2.ZERO)
	for corner in [Vector2(size.x,0),size,Vector2(0,size.y)]: view=view.expand(inverse*corner)
	var ray := MapProjection.ground_basis(canvas,deg_to_rad(38)).inverse()*MapProjection.camera_basis(canvas,deg_to_rad(38)).z
	var roof := -Vector2(ray.x,ray.z)/ray.y
	var started := Time.get_ticks_usec()
	var buildings: Array=[]
	var building_faces := 0
	var building_bytes := 0
	for entry: Dictionary in cells.values():
		var visible := Select.visible(entry,view,canvas,size,roof,Vector2.ZERO)
		if visible.faces==0: continue
		buildings.append(visible)
		building_faces+=int(visible.faces)
		building_bytes+=int(visible.bytes)
		for kind in 2:
			if visible.mask[kind]: piece_costs[str(kind)+":"+String(entry.path).trim_prefix("grid/")].visible=true
	var grid_usec := Time.get_ticks_usec()-started
	started=Time.get_ticks_usec()
	var index := Query.build(cells.values())
	var build_usec := Time.get_ticks_usec()-started
	started=Time.get_ticks_usec()
	var indexed := Query.query(index,view,canvas,size,roof,Vector2.ZERO)
	var query_usec := Time.get_ticks_usec()-started
	if indexed.entries!=buildings: return 1
	var differential: Dictionary=compare_queries(index) if input.get("differential",true) else {"checked":0,"failed":0}
	if differential.failed>0: return 1
	var roots: Array[Dictionary]=[]
	var configuration := "lod5_full"
	if not native._ground_roots.has(configuration): return 1
	var hybrid: bool=scale_value<=native.ground.limits[configuration]
	for root: Dictionary in (native._ground_roots[configuration] if hybrid else native._partition_roots[configuration]): roots.append(ground_tree(root))
	var root_visible := 0
	for root: Dictionary in roots: root_visible+=int(Select.visible(root,view,canvas,size,roof,Vector2.ZERO).faces>0)
	var available := 16-buildings.size()
	var result := {"building_cells":buildings.size(),"building_faces":building_faces,"building_bytes":building_bytes,
		"pose":pose,"size":dimensions,"hybrid_ground":hybrid,"ground_scale_limit":native.ground.limits[configuration],
		"grid_select_usec":grid_usec,"available_ground_pages":available,"visible_ground_roots":root_visible,
		"index_build_usec":build_usec,"index_query_usec":query_usec,"index_candidates":indexed.candidates,"differential":differential,
		"runtime_installed":false,"gpu_verified":false,"whole_map_accepted":false,"within_budget":false}
	if available>0 and root_visible<=available:
		var selection := Cut.choose(roots,view,canvas,size,roof,Vector2.ZERO,available,maxi(0,192*1024*1024-building_bytes))
		selection["configuration"]=configuration;selection["ground_tree"]=hybrid
		result["ground_cut"]=selection
		result["ground_coverage"]=native.covers_ground(selection,view,canvas,size)
		result["total_faces"]=building_faces+int(selection.triangles)
		result["total_bytes"]=building_bytes+int(selection.bytes)
		result["total_pages"]=buildings.size()+int(selection.active)
		result["within_budget"]=result.ground_coverage and result.total_faces<=240000 and result.total_bytes<=192*1024*1024 and result.total_pages<=16
	var actual := native.select(center,scale_value,0,size,configuration,192*1024*1024)
	result["actual_empty"]=actual.is_empty()
	result["actual_within_budget"]=actual.get("within_budget",false)
	result["building_over_faces"]=building_faces>240000
	result["building_over_bytes"]=building_bytes>192*1024*1024
	result["insufficient_ground_slots"]=available<=0 or root_visible>available
	var piece_faces := 0
	var piece_bytes := 0
	var piece_count := 0
	var visible_details: Array=[]
	var layer_faces := [0,0,0]
	for piece: Dictionary in pieces:
		var visible := Select.visible(piece,view,canvas,size,roof,Vector2.ZERO)
		if visible.faces==0: continue
		piece_faces+=int(visible.faces);piece_bytes+=int(visible.bytes);piece_count+=1
		piece_costs[piece.group].fine_faces+=int(visible.faces)
		piece_costs[piece.group].pieces+=1
		layer_faces[int(piece.layer)]+=int(visible.faces)
		visible_details.append({"path":piece.path,"source":piece.source,"group":piece.group,"layer":piece.layer,"faces":visible.faces,"bytes":piece.bytes})
	result["original_visible_pieces"]={"faces":piece_faces,"bytes":piece_bytes,"components":piece_count,"diagnostic_only":true}
	if input.get("geometry_breakdown",false):
		visible_details.sort_custom(func(a: Dictionary,b: Dictionary) -> bool: return a.faces>b.faces)
		result["visible_component_costs"]=visible_details
		result["visible_layer_faces"]=layer_faces
		# 显式对照既有LOD，不改变运行时选择；便宜不代表已通过视觉或覆盖验收。
		var alternatives: Dictionary={}
		for candidate: String in ["lod4_full","lod5_full"]:
			var original := preload("res://scripts/rendering/tokyo_hlod_native.gd").new()
			if not original.read(package.native): return 1
			var alternative := original.select(center,scale_value,0,size,candidate,192*1024*1024)
			alternatives[candidate]={"empty":alternative.is_empty(),"faces":alternative.get("triangles",-1),"bytes":alternative.get("bytes",-1),"within_budget":alternative.get("within_budget",false),"visual_verified":false}
		result["original_lod_comparison"]=alternatives
		if input.get("triangle_visibility",false):
			# 逐三角形保守屏幕包围盒，只定位分块浪费；不更改任何显示或覆盖凭据。
			var statistics := [{"total":0,"screen_box_overlap":0,"roof":0,"wall":0},{"total":0,"screen_box_overlap":0,"roof":0,"wall":0}]
			var split_cost := {"faces":0,"visible_components":0,"all_components":0,"conserved":true,"runtime_verified":false}
			for detail: Dictionary in visible_details:
				var component: Resource=load(detail.path)
				if component==null or component.meshes.size()!=1: return 1
				var mesh: ArrayMesh=component.meshes[0]
				if input.get("split_256",false):
					var splitter := preload("res://scripts/experiments/tokyo_spatial_split.gd")
					var ids: Dictionary={}
					var owners := PackedInt32Array()
					for midpoint: Vector2 in splitter.centers(mesh):
						var cell := Vector2i(floori(midpoint.x/256.0),floori(midpoint.y/256.0))
						if not ids.has(cell): ids[cell]=ids.size()
						owners.append(int(ids[cell]))
					var children := splitter.partition(mesh,owners,ids.size())
					if children.size()!=ids.size() or not preload("res://scripts/tests/build_tokyo_full_native_leaves.gd").conserved(mesh,children,owners): return 1
					split_cost.all_components+=children.size()
					for child: ArrayMesh in children:
						var box := preload("res://scripts/rendering/tokyo_cells_overlay.gd").projected_layer_bounds(child.get_aabb(),roof,Vector2.ZERO)
						if preload("res://scripts/rendering/tokyo_cells_overlay.gd").intersects_view(box,view,canvas,size):
							split_cost.visible_components+=1
							split_cost.faces+=preload("res://scripts/experiments/tokyo_indexed_mesh.gd").triangles(child)
				var stats: Dictionary=statistics[int(detail.layer)]
				for surface in mesh.get_surface_count():
					var arrays := mesh.surface_get_arrays(surface)
					var vertices: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
					var indices: PackedInt32Array=arrays[Mesh.ARRAY_INDEX]
					var count := indices.size() if not indices.is_empty() else vertices.size()
					for face in range(0,count,3):
						var a := vertices[indices[face] if not indices.is_empty() else face]
						var b := vertices[indices[face+1] if not indices.is_empty() else face+1]
						var c := vertices[indices[face+2] if not indices.is_empty() else face+2]
						var screen := Rect2(canvas*(Vector2(a.x,a.z)+roof*a.y),Vector2.ZERO)
						screen=screen.expand(canvas*(Vector2(b.x,b.z)+roof*b.y)).expand(canvas*(Vector2(c.x,c.z)+roof*c.y))
						stats.total+=1
						if screen.intersects(Rect2(Vector2.ZERO,size),true):
							stats.screen_box_overlap+=1
							stats["roof" if absf((b-a).cross(c-a).normalized().y)>0.5 else "wall"]+=1
			result["triangle_visibility_conservative"]=statistics
			if input.get("split_256",false): result["split_256"]=split_cost
	if available>0 and root_visible<=available:
		var frontier := Cut.solve(roots,view,canvas,size,roof,Vector2.ZERO,available)
		var minimum := 9223372036854775807
		for state: Dictionary in frontier.frontier:
			if int(state.bytes)+building_bytes<=192*1024*1024: minimum=mini(minimum,int(state.faces))
		result["minimum_ground_faces_with_current_slots"]=minimum
		result["piece_plus_ground_faces"]=piece_faces+minimum
		# 只估算少量边缘层细化；仍计全部原片加载字节，不虚扣不可见资源。
		var refinements: Array[Dictionary]=[]
		for key: String in piece_costs:
			var cost: Dictionary=piece_costs[key]
			var saved := int(cost.faces)-int(cost.fine_faces)
			if cost.visible and saved>0:
				refinements.append({"key":key,"saved_faces":saved,"draw_growth":int(cost.pieces)-1,
					"byte_growth":int(cost.fine_bytes)-int(cost.bytes),"score":float(saved)/maxi(1,int(cost.pieces)-1)})
		refinements.sort_custom(func(a: Dictionary,b: Dictionary) -> bool: return a.score>b.score)
		var refined_faces := building_faces+minimum
		var growth := 0
		var byte_growth := 0
		var chosen: Array=[]
		for refinement: Dictionary in refinements:
			if refined_faces<=240000: break
			refined_faces-=int(refinement.saved_faces)
			growth+=int(refinement.draw_growth);byte_growth+=int(refinement.byte_growth)
			chosen.append(refinement)
		result["selective_refinement_estimate"]={"faces":refined_faces,"additional_draws":growth,"additional_loaded_bytes":byte_growth,"choices":chosen,"runtime_verified":false}
	var file := FileAccess.open(output,FileAccess.WRITE)
	if file==null: return 1
	file.store_string(JSON.stringify(result,"\t"));file.close()
	result.erase("ground_cut")
	print("[Tokyo grid selection] ",result)
	return 0


static func ground_tree(entry: Dictionary) -> Dictionary:
	var result := entry.duplicate()
	result["triangles"]=PackedInt32Array([0,0,int(entry.triangles[2])])
	if entry.has("children"):
		var children: Array[Dictionary]=[]
		for child: Dictionary in entry.children: children.append(ground_tree(child))
		result["children"]=children
	return result


static func compare_queries(index: Dictionary) -> Dictionary:
	var checked := 0
	var failed := 0
	var size := Vector2(1600,900)
	# 固定种子覆盖全地图、旋转、缩放和非零阴影，不用帧率冒充内容一致性。
	var rng := RandomNumberGenerator.new()
	rng.seed=5122026
	for n in 64:
		var source: Dictionary=index.entries[(n*41)%index.entries.size()]
		var box: AABB=source.boxes[0] if source.triangles[0]>0 else source.boxes[1]
		var center := Vector2(box.position.x,box.position.z)+Vector2(rng.randf_range(-700,700),rng.randf_range(-700,700))
		var scale_value := rng.randf_range(0.2,2.5)
		var canvas := Transform2D(rng.randf_range(-PI,PI),Vector2.ZERO).scaled(Vector2.ONE*scale_value)
		canvas.origin=size*0.5-canvas*center
		var inverse := canvas.affine_inverse()
		var view := Rect2(inverse*Vector2.ZERO,Vector2.ZERO)
		for corner in [Vector2(size.x,0),size,Vector2(0,size.y)]: view=view.expand(inverse*corner)
		var roof := Vector2(rng.randf_range(-2,2),rng.randf_range(-2,2))
		var shadow := Vector2(rng.randf_range(-2,2),rng.randf_range(-2,2))
		var expected: Array=[]
		for entry: Dictionary in index.entries:
			var visible := Select.visible(entry,view,canvas,size,roof,shadow)
			if visible.faces>0: expected.append(visible)
		var actual := Query.query(index,view,canvas,size,roof,shadow)
		checked+=1
		failed+=int(actual.entries!=expected)
	return {"checked":checked,"failed":failed}
