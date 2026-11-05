extends RefCounted
## 离线重放已保存的无损分区树；比较固定布局，不在运行时搜索或增加页数。
const Override := preload("res://scripts/rendering/tokyo_partition_override.gd")
const Attach := preload("res://scripts/tests/tokyo_partition_attach_probe.gd")


static func replace_sources(entries: Array, selected: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary]=[]
	for entry: Dictionary in entries:
		if selected.has(entry.path): result.append(selected[entry.path]);continue
		var copy := entry.duplicate()
		copy.children=replace_sources(entry.children,selected)
		result.append(copy)
	return result


static func run(input: Dictionary) -> int:
	var package := Override.json_binding(input.get("refined_tree_cost"))
	var poses := Override.json_binding(input.get("poses"))
	var variants: Variant=input.get("variants")
	var output: String=input.get("output","")
	if package.is_empty() or not poses.get("poses") is Array or poses.poses.is_empty() \
		or not variants is Array or variants.is_empty() or variants.size()>4 \
		or not output.is_absolute_path() or DirAccess.dir_exists_absolute(output): return 1
	var native := preload("res://scripts/rendering/tokyo_hlod_native.gd").new()
	if not native.read(package.native): return 1
	if DirAccess.make_dir_recursive_absolute(output)!=OK: return 1
	var report := {"diagnostic_only":true,"runtime_verified":false,"fail":0,"configurations":{}}
	var selected_plans: Dictionary={}
	for configuration: String in ["lod4_full","lod5_full"]:
		var options: Dictionary={}
		for variant: Dictionary in variants:
			var binding: Dictionary=variant[configuration].trees
			if FileAccess.get_sha256(binding.path)!=binding.sha256: return 1
			var file := FileAccess.open(binding.path,FileAccess.READ)
			if file==null: return 1
			var saved: Variant=file.get_var(false);file.close()
			var plans := Override.json_binding(variant[configuration].plans)
			if not saved is Dictionary or saved.get("source_catalog_sha256")!=native.catalog_sha or plans.get("schema")!=1: return 1
			for tree: Dictionary in saved.trees.values():
				var original := Attach.find_entry(native.catalog.configurations[configuration],tree.path)
				if original.is_empty() or Array(original.triangles)!=Array(tree.triangles) or not Attach.no_game_sources(original,native,configuration): return 1
				if not plans.plans.has(tree.path): return 1
				if not options.has(tree.path): options[tree.path]=[]
				options[tree.path].append({"name":variant.name,"tree":tree,"plan":plans.plans[tree.path]})
		var keys: Array=options.keys();keys.sort()
		var combinations := 1
		for key: String in keys: combinations*=options[key].size()
		if combinations>256: return 1
		var best: Dictionary={}
		for code in combinations:
			var cursor := code
			var selected := {}
			var choices := {}
			for key: String in keys:
				var choice: int=cursor%options[key].size();cursor/=int(options[key].size())
				selected[key]=options[key][choice].tree;choices[key]=choice
			var rows := Attach.cuts(replace_sources(native.catalog.configurations[configuration],selected),poses.poses,"")
			var failures := 0
			var excess := 0
			var peak := 0
			for row: Dictionary in rows:
				failures+=int(not row.within_budget)
				excess+=maxi(0,int(row.faces)-240000)+maxi(0,int(row.bytes)-96*1024*1024)
				peak=maxi(peak,int(row.faces))
			var score: int=failures*1000000000000+excess*1000000+peak
			if best.is_empty() or score<int(best.score):
				best={"score":score,"fail":failures,"peak":peak,"rows":rows,"choices":choices}
				print("[refined tree cost] configuration=",configuration," tested=",code+1,"/",combinations," fail=",failures," peak=",peak)
		for key: String in keys: selected_plans[key]=options[key][int(best.choices[key])].plan
		best["combinations"]=combinations
		report.configurations[configuration]=best
		report.fail+=int(best.fail)
	var save := preload("res://scripts/tests/build_tokyo_lossless_leaf_partitions.gd")
	if save.save_json(output.path_join("plans.json"),{"schema":1,"plans":selected_plans}).is_empty(): return 1
	if save.save_json(output.path_join("report.json"),report).is_empty(): return 1
	return int(report.fail>0)
