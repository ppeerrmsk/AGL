extends "res://scripts/tests/build_tokyo_source_coverage.gd"
## 精确R237候选逐面重证；不改旧R62身份门，也不迁移旧leaf token。
const Candidate := preload("res://scripts/rendering/tokyo_canonical_catalog.gd")
const Builder := preload("res://scripts/tests/build_tokyo_cells.gd")
const SHA := "ce67b4a3b26be03be13397df7d28e34ff1e6cdefcd1c6bf09ba96884fda55daa"


func build(path: String, output: String) -> int:
	var near_only := OS.get_environment("AGL_TOKYO_NEAR_LAYOUT")=="1"
	var candidate_sha := "c59753a8ac3779a30ed117cb817ef0861ef262b71db8114227a06bea01039b06" if near_only else SHA
	var previous_sha := "fbb2da6b32b5e3f75c6ad9c91dadcc07725a9805f1b0effb57ec343c590f81c9" if near_only else "3e81e5f839591ac89d4d662163450b36902763f41b9c8539427d6bcdddb075ef"
	var previous_directory := "r261-eight-region-catalog-a" if near_only else "r232-six-region-catalog-a"
	if OS.get_environment("AGL_TOKYO_NINE_REGION_LAYOUT")=="1":
		if not near_only:
			return 1
		candidate_sha="90d2378a4f480b9c97609038ac7913fd6f3f6b5f816d9ebe36bd935f88000fab"
		previous_sha="fc2c255c53372e5f08643a70febfabeb277a8203d4ffe9f394c7bc86a709cb30"
		previous_directory="r275-nine-region-catalog-a"
	if OS.get_environment("AGL_TOKYO_SOUTH_LAYOUT")=="1":
		if not near_only or OS.get_environment("AGL_TOKYO_NINE_REGION_LAYOUT")!="1":
			return 1
		candidate_sha="167ef74c4d1a9b5c3dfdf3fe929473e6f67d6917c4d0bcf71accd0836ab71026"
		previous_sha="5ca41d3e671d5189288a49fdf71561d4c06b943636f465ee553c4f37859c5512"
		previous_directory="r298-south-catalog-a"
	if OS.get_environment("AGL_TOKYO_SOUTHWEST_LAYOUT")=="1":
		if not near_only or OS.get_environment("AGL_TOKYO_NINE_REGION_LAYOUT")!="1" or OS.get_environment("AGL_TOKYO_SOUTH_LAYOUT")!="1":
			return 1
		candidate_sha="22a0c03939f61d6f15fc800a7c676d411cbee72c30806dd4f6fe98c92ef5fd30"
		previous_sha="9c96d71f29c964b1174bff22b2d0518cadcf662bbce1b0ae33d7fcd34ddcd8d4"
		previous_directory="r312-southwest-catalog-a"
	if FileAccess.get_sha256(path)!=candidate_sha or not Builder.valid_sample_output(path.get_base_dir(),output):
		return 1
	var catalog: Resource = ResourceLoader.load(path,"",ResourceLoader.CACHE_MODE_IGNORE)
	if catalog==null or not catalog.valid():
		return 1
	var root := path.get_base_dir().get_base_dir()
	var schedule_path := root.path_join("r52-spatial-plan-a.json")
	var schedule: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(schedule_path))
	if not schedule.get("passed",false) or schedule.collision_sha256!=catalog.collision_sha256 or schedule.owners_sha256!=catalog.owners_sha256:
		return 1
	DirAccess.make_dir_recursive_absolute(output)
	var results: Array = []
	for configuration: String in Candidate.CONFIGURATIONS:
		var rows: Array = schedule.configurations.filter(func(row: Dictionary) -> bool: return row.name==configuration)
		if rows.size()!=1:
			return 1
		var row: Dictionary = rows[0]
		var plan_path := root.path_join("r51-canonical-plans-a").path_join(row.file)
		if FileAccess.get_sha256(plan_path)!=row.plan_sha256:
			return 1
		var plan: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(plan_path))
		if not plan.get("passed",false) or plan.collision_sha256!=catalog.collision_sha256 or plan.game_source_sha256!=schedule.game_source_sha256:
			return 1
		var file := FileAccess.open(root.path_join(previous_directory+"/coverage-"+configuration+".bin"),FileAccess.READ)
		if file==null:
			return 1
		var previous: Dictionary = file.get_var(false)
		file.close()
		if previous.catalog_sha256!=previous_sha or not previous.verified or previous.plan_sha256!=row.plan_sha256 or previous.schedule_sha256!=FileAccess.get_sha256(schedule_path):
			return 1
		var data := {"schema":1,"configuration":configuration,"catalog_sha256":candidate_sha,"collision_sha256":catalog.collision_sha256,"owners_sha256":catalog.owners_sha256,"plan_sha256":row.plan_sha256,"schedule_sha256":FileAccess.get_sha256(schedule_path),"game_source_sha256":plan.game_source_sha256,"pages":{},"sources":{},"verified":false}
		var expected := _expected(plan,row)
		var finest: Dictionary = {}
		_labels.clear()
		for parent: Dictionary in catalog.configurations[configuration]:
			_visit(parent,expected.get(int(parent.parent_id),[{},{}]),catalog,data,finest)
		for parent: int in expected:
			for kind in 2:
				for key: PackedByteArray in expected[parent][kind]:
					var token := str(parent)+":"+str(kind)+":"+key.hex_encode()
					_check(int(finest.get(token,0))==int(expected[parent][kind][key].count),"rebalanced finest source multiplicity")
		for source: Dictionary in plan.expected:
			_check(data.sources.has(int(source.source_id)),"rebalanced source has dependencies")
		_check(data.sources.size()==previous.sources.size(),"rebalanced source count preserved")
		for source: int in previous.sources:
			_check(data.sources.has(source),"rebalanced source IDs preserved")
		data.verified=_fail==0
		var checks := _audit_cuts(data,catalog)
		if _fail:
			return 1
		var destination := output.path_join("coverage-"+configuration+".bin")
		file=FileAccess.open(destination,FileAccess.WRITE)
		file.store_var(data)
		file.close()
		file=FileAccess.open(destination,FileAccess.READ)
		_check(file.get_var(false)==data,"rebalanced coverage saved roundtrip")
		file.close()
		results.append({"configuration":configuration,"sources":data.sources.size(),"checks":checks,"sha256":FileAccess.get_sha256(destination)})
		print("[Rebalanced coverage] ",configuration," sources=",data.sources.size()," fail=",_fail)
	var file := FileAccess.open(output.path_join("report.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"fail":_fail,"catalog_sha256":candidate_sha,"rows":results,"pages":_pages,"scanned":_scanned,"matches":_matched,"visual_verified":false}))
	file.close()
	return 0 if _fail==0 else 1
