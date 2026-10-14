extends RefCounted
## 直接读取已完成原生组件树，先核正常玩家视野成本，不重烘或生成第二份目录。
const Cut := preload("res://scripts/experiments/tokyo_spatial_cut.gd")
const MapProjection := preload("res://scripts/experiments/volume_projection.gd")
const Archive := preload("res://scripts/rendering/tokyo_volume_archive.gd")
const Views := preload("res://scripts/tests/tokyo_hlod_gameplay_views.gd")
const Root := preload("res://scripts/tests/build_tokyo_full_grid_root.gd")


static func run(input: String, digest: String, output: String) -> int:
	var solver_test := preload("res://scripts/tests/test_tokyo_hierarchical_pages.gd").new()
	solver_test._test_solver()
	if solver_test._fail!=0: return 1
	if not Root.binding_valid({"path":input,"sha256":digest}) or not output.is_absolute_path() or FileAccess.file_exists(output): return 1
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(input))
	if not data is Dictionary or not data.get("component_trees_complete",false): return 1
	var loaded: Dictionary = {}
	var rows: Array = []
	var poses := Views.poses()
	if OS.get_environment("AGL_TOKYO_NEAR_TRANSITION_AUDIT")=="1":
		poses=[[-4300,-3700,0.8],[-4300,-3700,0.9],[-4300,-3700,1.0],[-4300,-3700,1.2],[-4300,-3700,1.4]]
	for pose: Array in poses:
		var scale_value := float(pose[2])*1600.0/1920.0
		var level := Archive.choose_level(-1,scale_value)
		var names := ["lod%d_full" % level]
		if level<4: names.append("lod%d_guarded" % level)
		# 跨档只读成本对比，不能据此授予运行时显示资格。
		if OS.get_environment("AGL_TOKYO_NEAR_COMPARE_LEVELS")=="1":
			if pose[0]!=-4300 or pose[2] not in [0.35,0.7]: continue
			names=["lod0_full","lod1_full","lod2_full","lod3_full","lod4_full","lod4_mid","lod5_full"]
		for name_value: String in names:
			if not loaded.has(name_value):
				var parents: Array[Dictionary] = []
				for group: Dictionary in data.configurations:
					if group.configuration!=name_value: continue
					for binding: Dictionary in group.roots:
						if not Root.binding_valid(binding.manifest): return 1
						var file := FileAccess.open(binding.manifest.path,FileAccess.READ)
						if file==null: return 1
						var tree: Variant = file.get_var(false)
						file.close()
						if not tree is Dictionary or tree.get("pages",{}).size()!=277: return 1
						parents.append(tree.root)
				if parents.size()!=16: return 1
				loaded[name_value]=parents
			var size := Vector2(1600,900)
			var canvas := Transform2D(0,Vector2.ZERO).scaled(Vector2.ONE*scale_value)
			canvas.origin=size*0.5-canvas.basis_xform(Vector2(pose[0],pose[1]))
			var inverse := canvas.affine_inverse()
			var view := Rect2(inverse*Vector2.ZERO,inverse.basis_xform(size))
			var ground := MapProjection.ground_basis(canvas,deg_to_rad(38))
			var ray := ground.inverse()*MapProjection.camera_basis(canvas,deg_to_rad(38)).z
			var parents: Array[Dictionary] = []
			parents.assign(loaded[name_value])
			var cut := Cut.choose(parents,view,canvas,size,-Vector2(ray.x,ray.z)/ray.y,Vector2.ZERO)
			var layer_faces := PackedInt64Array([0,0,0])
			for entry: Dictionary in cut.entries:
				for kind in 3:
					if entry.mask[kind]: layer_faces[kind]+=int(entry.triangles[kind])
			rows.append({"pose":pose,"scale":scale_value,"configuration":name_value,"pages":cut.active,"faces":cut.triangles,"layer_faces":Array(layer_faces),"bytes":cut.bytes,"within_budget":cut.within_budget,"solver_usec":cut.solver_usec})
			print("[Near source cut] ",name_value," zoom=",pose[2]," faces=",cut.triangles," bytes=",cut.bytes," budget=",cut.within_budget)
	var file := FileAccess.open(output,FileAccess.WRITE)
	if file==null: return 1
	file.store_string(JSON.stringify({"input_sha256":digest,"metadata_only":true,"runtime_integrated":false,"rows":rows},"\t"))
	file.close()
	return 0
