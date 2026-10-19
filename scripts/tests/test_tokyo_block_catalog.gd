extends RefCounted
const Builder := preload("res://scripts/tests/build_tokyo_block_catalog.gd")
var _pass := 0
var _fail := 0


func run() -> void:
	var old_inputs := Builder.input_paths("C:/root",false)
	var wide := Builder.input_paths("C:/root",false,false,false,false,false,false,true)
	_check(wide.catalog=="C:/root/r109-native-b/catalog.res" and wide.components=="C:/root/r109-native-b/components/manifest.bin" and wide.coverage_prefix=="C:/root/r109-native-b/coverage-" and wide.plan=="C:/root/r111-district24wide-a-native/manifest.json" and wide.baseline=="C:/root/r106-district16-a-native/manifest.json" and wide.levels==[5] and wide.profile=="district24wide","wide inherits mid6 catalog and identifies current finest independently")
	for flag in range(6):
		var flags := [false,false,false,false,false,false]
		flags[flag]=true
		_check(Builder.input_paths("C:/root",flags[0],flags[1],flags[2],flags[3],flags[4],flags[5],true).is_empty(),"wide refuses each combined route")
	var wide_rows: Array = []
	var previous_wide: Array = []
	for parent in range(8,16):
		var row := {"level":5,"cell_id":parent,"block_profile":"district24wide","source":"source_5_%d"%parent,"source_sha256":"sha_5_%d"%parent,"max_scale":5.0}
		wide_rows.append(row)
		var previous := row.duplicate()
		previous.block_profile="district16"
		previous_wide.append(previous)
	_check(Builder.matched_baseline_rows(wide_rows,previous_wide,"district24wide").size()==8,"wide complete three-way provenance accepted")
	for mutation: Dictionary in [{"source":"wrong"},{"source_sha256":"wrong"},{"max_scale":1.5552},{"level":4},{"cell_id":9},{"block_profile":"district8"}]:
		var wrong := previous_wide.duplicate(true)
		wrong[0].merge(mutation,true)
		_check(Builder.matched_baseline_rows(wide_rows,wrong,"district24wide").is_empty(),"wide previous identity or matrix drift rejected")
	for mutation: Dictionary in [{"level":4},{"cell_id":8.5},{"block_profile":"district20wide"},{"source_sha256":"wrong"}]:
		var wrong := wide_rows.duplicate(true)
		wrong[0].merge(mutation,true)
		_check(Builder.matched_baseline_rows(wrong,previous_wide,"district24wide").is_empty(),"wide new identity and unselected alternative rejected")
	_check(not Builder.valid_plan_rows(wide_rows,[4],"district24wide") and not Builder.valid_plan_rows(wide_rows,[5],"district20wide"),"wide cannot expand middle or promote other profile")
	var middle := Builder.input_paths("C:/root",false,false,false,false,false,true)
	_check(middle.catalog=="C:/root/r107-native-a/catalog.res" and middle.components=="C:/root/r107-native-a/components/manifest.bin" and middle.coverage_prefix=="C:/root/r107-native-a/coverage-" and middle.plan=="C:/root/r108-mid6-a-native/manifest.json" and middle.levels==[4] and middle.profile=="mid6","middle route inherits current full catalog and selected native source")
	for flags: Array in [[true,false,false,false,false],[false,true,false,false,false],[false,false,true,false,false],[false,false,false,true,false],[false,false,false,false,true]]:
		_check(Builder.input_paths("C:/root",flags[0],flags[1],flags[2],flags[3],flags[4],true).is_empty(),"middle route refuses ambiguous replacement flags")
	var middle_rows: Array = []
	for parent in range(8,16):
		middle_rows.append({"level":4,"cell_id":parent,"block_profile":"mid6"})
	_check(Builder.valid_plan_rows(middle_rows,[4],"mid6"),"complete selected middle matrix accepted")
	for mutation: Dictionary in [{"level":5},{"level":3},{"cell_id":9},{"cell_id":8.5},{"block_profile":"mid4"}]:
		var wrong := middle_rows.duplicate(true)
		wrong[0].merge(mutation,true)
		_check(not Builder.valid_plan_rows(wrong,[4],"mid6"),"middle level parent or profile drift rejected")
	_check(not Builder.valid_plan_rows(middle_rows,[5],"mid6") and not Builder.valid_plan_rows(middle_rows,[4],"mid4"),"middle cannot extend finest or promote unselected alternative")
	var legacy_middle := middle_rows.duplicate(true)
	for row: Dictionary in legacy_middle:
		row.block_profile="blocks"
	_check(not Builder.valid_plan_rows(legacy_middle,[4]),"old blocks integration cannot expand into middle level")
	var middle_source := preload("res://scripts/rendering/tokyo_cell_archive.gd").new()
	middle_source.level=4
	middle_source.cell_id=8
	middle_source.source_ids=PackedStringArray(["source"])
	middle_source.height_hash="height"
	middle_source.meshes=[ArrayMesh.new(),ArrayMesh.new()]
	_check(Builder.middle_source_chain(middle_source,middle_source,middle_source),"middle original source and unchanged marked layer chain accepted")
	for mutation: Dictionary in [{"level":5},{"cell_id":9},{"source_ids":PackedStringArray(["wrong"])},{"height_hash":"wrong"}]:
		var wrong: Resource = middle_source.duplicate(true)
		for key: String in mutation:
			wrong.set(key,mutation[key])
		_check(not Builder.middle_source_chain(wrong,middle_source,middle_source) and not Builder.middle_source_chain(middle_source,wrong,middle_source),"middle original and previous source identity both fail closed")
	var triangle := ArrayMesh.new()
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=PackedVector3Array([Vector3.ZERO,Vector3.RIGHT,Vector3.FORWARD])
	triangle.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	var geometry_wrong: Resource = middle_source.duplicate(true)
	geometry_wrong.meshes.assign([triangle,ArrayMesh.new()])
	_check(not Builder.middle_source_chain(geometry_wrong,middle_source,middle_source),"middle original low geometry cannot differ from candidate origin")
	geometry_wrong.meshes.assign([ArrayMesh.new(),triangle])
	_check(not Builder.middle_source_chain(middle_source,geometry_wrong,middle_source),"previous marked geometry cannot differ from original")
	_check(not Builder.middle_source_chain(null,middle_source,middle_source),"missing middle source refuses")
	var strong := Builder.input_paths("C:/root",false,false,false,false,true)
	_check(strong.catalog=="C:/root/r103-native-a/catalog.res" and strong.components=="C:/root/r103-native-a/components/manifest.bin" and strong.coverage_prefix=="C:/root/r103-native-a/coverage-" and strong.plan=="C:/root/r106-district16-a-native/manifest.json" and strong.baseline=="C:/root/r92-district8-a-native/manifest.json" and strong.levels==[5],"strong finest inherits full catalog and independently identifies old low layer")
	for flags: Array in [[true,false,false,false],[false,true,false,false],[false,false,true,false],[false,false,false,true]]:
		_check(Builder.input_paths("C:/root",flags[0],flags[1],flags[2],flags[3],true).is_empty(),"strong route refuses combined replacement modes")
	var strong_rows: Array = []
	var old_strong_rows: Array = []
	for parent in range(8,16):
		var row := {"level":5,"cell_id":parent,"block_profile":"district16","source":"source_5_%d"%parent,"source_sha256":"sha_5_%d"%parent,"max_scale":5.0}
		strong_rows.append(row)
		var previous := row.duplicate()
		previous.block_profile="district8"
		old_strong_rows.append(previous)
	_check(Builder.matched_baseline_rows(strong_rows,old_strong_rows,"district16").size()==8,"strong finest three-way full matrix matches")
	for mutation: Dictionary in [{"source":"wrong"},{"source_sha256":"wrong"},{"max_scale":0.7776},{"level":3},{"cell_id":9},{"block_profile":"blocks"}]:
		var wrong := old_strong_rows.duplicate(true)
		wrong[0].merge(mutation,true)
		_check(Builder.matched_baseline_rows(strong_rows,wrong,"district16").is_empty(),"strong baseline provenance or matrix drift rejected")
	_check(not Builder.valid_plan_rows(strong_rows,[1,2],"district16") and not Builder.valid_plan_rows(strong_rows,[5],"district12") and Builder.matched_baseline_rows(strong_rows,old_strong_rows,"district12").is_empty(),"only selected strongest finest profile can integrate")
	var far_inputs := Builder.input_paths("C:/root",false,false,false,true)
	_check(far_inputs.catalog=="C:/root/r93-native-a/catalog.res" and far_inputs.plan=="C:/root/r102-far6-a-native/manifest.json" and far_inputs.baseline=="C:/root/r78-blocks-native-a/manifest.json" and far_inputs.levels==[1,2] and far_inputs.ao_region=="north_density","far6 inherits complete near catalog and independently identifies current blocks")
	_check(Builder.input_paths("C:/root",true,false,false,true).is_empty() and Builder.input_paths("C:/root",false,true,false,true).is_empty() and Builder.input_paths("C:/root",false,false,true,true).is_empty(),"far cannot combine with other replacement modes")
	var far_rows: Array = []
	var previous_rows: Array = []
	for level in [1,2]:
		for parent in range(8,16):
			var row := {"level":level,"cell_id":parent,"block_profile":"far6","source":"source_%d_%d"%[level,parent],"source_sha256":"hash_%d_%d"%[level,parent],"max_scale":0.1944 if level==1 else 0.3888}
			far_rows.append(row)
			var previous := row.duplicate()
			previous.block_profile="blocks"
			previous_rows.append(previous)
	_check(Builder.matched_baseline_rows(far_rows,previous_rows).size()==16,"three-way matching uses full exact source matrix")
	for mutation: Dictionary in [{"source":"wrong"},{"source_sha256":"wrong"},{"max_scale":5.0},{"level":3},{"cell_id":9}]:
		var wrong := previous_rows.duplicate(true)
		wrong[0].merge(mutation,true)
		_check(Builder.matched_baseline_rows(far_rows,wrong).is_empty(),"baseline source or matrix drift rejects integration")
	_check(not Builder.valid_plan_rows(far_rows,[1,2],"far4") and not Builder.valid_plan_rows(far_rows,[5],"far6"),"only selected far6 at declared levels can integrate")
	var near_inputs := Builder.input_paths("C:/root",true)
	var finest_inputs := Builder.input_paths("C:/root",false,true)
	_check(finest_inputs.catalog=="C:/root/r85-native-a/catalog.res" and finest_inputs.components=="C:/root/r85-native-a/components/manifest.bin" and finest_inputs.coverage_prefix=="C:/root/r85-native-a/coverage-" and finest_inputs.plan=="C:/root/r88-blocks-a-native/manifest.json" and finest_inputs.levels==[5] and finest_inputs.ao_region=="north_density","finest inherits R85 and reexports actual north AO")
	_check(Builder.input_paths("C:/root",true,true).is_empty(),"ambiguous near and finest flags refuse")
	var district_inputs := Builder.input_paths("C:/root",false,true,true)
	_check(district_inputs.plan=="C:/root/r92-district8-a-native/manifest.json" and district_inputs.profile=="district8" and district_inputs.catalog==finest_inputs.catalog and district_inputs.levels==[5],"district explicitly inherits original finest geometry and selected reviewed plan")
	_check(Builder.input_paths("C:/root",false,false,true).is_empty() and Builder.input_paths("C:/root",true,true,true).is_empty(),"district requires only finest mode")
	_check(old_inputs.catalog=="C:/root/r54-catalog-a.res" and old_inputs.levels==[1,2],"old factory routes preserved")
	_check(near_inputs.catalog=="C:/root/r79-native-a/catalog.res" and near_inputs.components=="C:/root/r79-native-a/components/manifest.bin" and near_inputs.coverage_prefix=="C:/root/r79-native-a/coverage-" and near_inputs.plan=="C:/root/r84-blocks-a-native/manifest.json" and near_inputs.levels==[3],"near factory inherits catalog components and coverage together")
	var rows: Array = []
	for parent in range(8,16):
		rows.append({"level":3.0,"cell_id":float(parent),"block_profile":"blocks"})
	_check(Builder.valid_plan_rows(rows,[3]),"complete JSON numeric near matrix accepted")
	var district_rows: Array = rows.duplicate(true)
	for row: Dictionary in district_rows:
		row.level=5
		row.block_profile="district8"
	_check(Builder.valid_plan_rows(district_rows,[5],"district8"),"complete district finest matrix accepted")
	_check(not Builder.valid_plan_rows(district_rows,[5]),"district never silently enters old blocks route")
	_check(not Builder.valid_plan_rows(rows,[3],"district8"),"district cannot repurpose middle geometry")
	_check(not Builder.valid_plan_rows(district_rows,[5],"district6"),"unselected profile fails closed")
	district_rows[0].block_profile="blocks"
	_check(not Builder.valid_plan_rows(district_rows,[5],"district8"),"mixed profile matrix rejected")
	var bad := rows.duplicate(true)
	bad[0].cell_id=9
	_check(not Builder.valid_plan_rows(bad,[3]),"duplicate and missing parent rejected")
	bad=rows.duplicate(true)
	bad.pop_back()
	_check(not Builder.valid_plan_rows(bad,[3]),"incomplete matrix rejected")
	bad=rows.duplicate(true)
	bad[0].level=2
	_check(not Builder.valid_plan_rows(bad,[3]),"undeclared level rejected")
	bad=rows.duplicate(true)
	bad[0].cell_id=8.5
	_check(not Builder.valid_plan_rows(bad,[3]),"fractional parent rejected before truncation")
	bad=rows.duplicate(true)
	bad[0].block_profile="gentle"
	_check(not Builder.valid_plan_rows(bad,[3]),"wrong profile rejected")
	bad=rows.duplicate(true)
	bad[0].level="3"
	_check(not Builder.valid_plan_rows(bad,[3]),"string level rejected")
	var changes := {"C:/old":{"path":"C:/new","old_identity":{"source":"old"},"identity":{"source":"new"},"sha256":"new-sha"}}
	var input := {"catalog_sha256":"old","pages":{"C:/old":{"identity":{"source":"old"},"sha256":"old-sha","leaves":PackedStringArray(["C:/old"]),"tokens":[PackedStringArray(),PackedStringArray(["C:/old:1"])]}},"sources":{7:PackedStringArray(["C:/old:1"])}}
	var original := input.duplicate(true)
	var result := Builder.rewrite_coverage(input,changes,"new")
	_check(not result.is_empty() and result.catalog_sha256=="new" and result.pages.has("C:/new") and result.sources[7]==PackedStringArray(["C:/new:1"]),"verified high-layer dependency remapped")
	_check(input==original,"old coverage stays immutable")
	_check(result.pages["C:/new"].leaves==PackedStringArray(["C:/new"]) and result.pages["C:/new"].identity==changes["C:/old"].identity,"leaf and identity remapped together")
	input.pages["C:/old"].tokens[0]=PackedStringArray(["C:/old:0"])
	_check(Builder.rewrite_coverage(input,changes,"new").is_empty(),"game roof on modified low layer rejects wholesale replacement")
	input=original.duplicate(true)
	input.pages["C:/old"].identity={"source":"wrong"}
	_check(Builder.rewrite_coverage(input,changes,"new").is_empty(),"old identity mismatch rejects migration")
	_check(Builder.remap_tokens(PackedStringArray(["C:/old:2"]),changes).is_empty(),"invalid layer token rejected")
	_check(Builder.remap_tokens(PackedStringArray(["C:/other:1"]),changes)==PackedStringArray(["C:/other:1"]),"unchanged source token retained")
	print("[R79 block catalog test] pass=",_pass," fail=",_fail)


func _check(ok: bool, label: String) -> void:
	if ok:
		_pass+=1
	else:
		_fail+=1
		push_error("R79 "+label)
