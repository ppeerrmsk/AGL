extends RefCounted
## 离线选择固定的无损空间布局；不在运行帧中搜索或改变预算。
const Override := preload("res://scripts/rendering/tokyo_partition_override.gd")
const Attach := preload("res://scripts/tests/tokyo_partition_attach_probe.gd")
var native: RefCounted
var poses: Array=[]
var source_options: Dictionary={}
var evaluations := {}

func trees(entries: Array, choices: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary]=[]
	for entry: Dictionary in entries:
		var copy := entry.duplicate()
		if choices.has(entry.path):
			var options: Array=[entry.children]
			options.append_array(entry.get("alternative_children",[]))
			copy.children=options[int(choices[entry.path])]
			copy.erase("alternative_children")
		else: copy.children=trees(entry.children,choices)
		result.append(copy)
	return result

func evaluate(choices: Dictionary) -> Dictionary:
	var key := var_to_bytes(choices).hex_encode().sha256_text()
	if evaluations.has(key): return evaluations[key]
	var rows := Attach.cuts(trees(native._partition_roots.lod5_full,choices),poses,"")
	var excess := 0
	var peak := 0
	var fail := 0
	for row: Dictionary in rows:
		if not row.within_budget: fail+=1
		peak=maxi(peak,int(row.faces))
		excess+=maxi(0,int(row.faces)-239000)
	var result := {"score":excess+maxi(0,peak-239000)*poses.size(),"fail":fail,"peak":peak,"rows":rows}
	evaluations[key]=result
	return result

func search(input: Dictionary) -> int:
	var package := Override.json_binding(input.get("layout_search"))
	var plan := Override.json_binding(input.get("variants_plan"))
	var pose_data := Override.json_binding(input.get("poses"))
	var output: String=input.get("output","")
	if package.is_empty() or plan.is_empty() or pose_data.is_empty() or FileAccess.file_exists(output): return 1
	native=preload("res://scripts/rendering/tokyo_hlod_native.gd").new()
	if not native.read(package.native): return 1
	poses=pose_data.poses
	var choices := {}
	for path: String in plan.sources:
		if native.pages[path].canonical_identity.configuration!="lod5_full": continue
		source_options[path]=plan.sources[path]
		choices[path]=int(input.get("initial",{}).get(path,0))
	var best := evaluate(choices)
	var best_choices := choices.duplicate()
	var rng := RandomNumberGenerator.new();rng.seed=4221
	for restart in 5:
		if restart>0:
			choices=best_choices.duplicate()
			for path: String in choices:
				if rng.randf()<0.4: choices[path]=rng.randi_range(0,source_options[path].size()-1)
		var current := evaluate(choices)
		for sweep in 5:
			var improved := false
			for path: String in choices:
				var selected := int(choices[path])
				for index in source_options[path].size():
					if index==selected: continue
					choices[path]=index
					var candidate := evaluate(choices)
					if candidate.score<current.score:
						selected=index;current=candidate;improved=true
				choices[path]=selected
				if current.score<best.score:
					best=current;best_choices=choices.duplicate()
					print("[fixed layout] evaluations=",evaluations.size()," fail=",best.fail," peak=",best.peak," score=",best.score)
				if best.score==0: break
			if not improved or best.score==0: break
		if best.score==0: break
	var selected_variants := {}
	for path: String in best_choices: selected_variants[path]=source_options[path][int(best_choices[path])]
	var result := {"fail":best.fail,"peak":best.peak,"choices":best_choices,"variants":selected_variants,"rows":best.rows,"evaluations":evaluations.size()}
	var file := FileAccess.open(output,FileAccess.WRITE)
	if file==null: return 1
	file.store_string(JSON.stringify(result,"\t"));file.close()
	return 0

static func run(input: Dictionary) -> int:
	return load("res://scripts/tests/tokyo_partition_layout_search.gd").new().search(input)
