extends RefCounted
const Street := preload("res://scripts/tests/build_tokyo_street_catalog.gd")
const Geometry := preload("res://scripts/experiments/volume_mesh_factory.gd")
var _pass := 0
var _fail := 0


func run() -> void:
	var rows: Array = []
	for parent in range(8,16):
		rows.append({"block_profile":"street6","level":2,"max_scale":0.3888,"cell_id":parent})
	_check(Street.valid_rows(rows),"complete north LOD2 matrix")
	for mutation: Dictionary in [{"cell_id":9},{"cell_id":NAN},{"cell_id":8.5},{"level":1},{"max_scale":0.7776},{"block_profile":"street8"}]:
		var invalid := rows.duplicate(true)
		invalid[0].merge(mutation,true)
		_check(not Street.valid_rows(invalid),"source matrix refuses duplicate parent, wrong profile or scale")
	_check(not Street.valid_rows({}) and not Street.valid_rows([]),"malformed matrix rejected")
	var close_rows: Array = []
	for parent in range(8,16):
		close_rows.append({"block_profile":"district24street45","level":5,"max_scale":5.0,"cell_id":parent})
	_check(Street.valid_rows(close_rows,true) and not Street.valid_rows(close_rows) and not Street.valid_rows(rows,true),"near and far source matrices remain isolated")
	_check(Street.valid_rows(JSON.parse_string(JSON.stringify(close_rows)),true),"near matrix accepts exact JSON numeric values")
	for mutation: Dictionary in [{"cell_id":9},{"cell_id":NAN},{"cell_id":8.5},{"level":2},{"max_scale":0.3888},{"block_profile":"district24street"}]:
		var invalid := close_rows.duplicate(true)
		invalid[0].merge(mutation,true)
		_check(not Street.valid_rows(invalid,true),"near source matrix refuses wrong region, A profile or scale")
	var near_recipe := Street.recipe(true)
	_check(near_recipe.directory=="r139-native-b" and near_recipe.old=="r111-district24wide-a-native" and near_recipe.new=="r142-district24street45-native-b" and near_recipe.removed==743 and near_recipe.saved==139694,"near recipe locks current source chain and correct transferred LOD faces")
	near_recipe.level=2
	_check(Street.recipe(true).level==5 and Street.recipe().removed==115,"recipe mutation cannot change default or future source selection")
	for configuration: String in Street.Catalog.CONFIGURATIONS:
		for parent in 16:
			_check(Street.selected(configuration,parent)==(configuration=="lod2_full" and parent>=8),"only north LOD2 full can change")
			_check(Street.selected(configuration,parent,true)==(configuration=="lod5_full" and parent>=8),"near replacement leaves every guarded, middle and non-north configuration alone")
	_check(not Street.selected("lod2_full",16) and not Street.selected("lod2_full",-1),"parent range fails closed")
	var old := Geometry.new()
	old.quad(Vector3.ZERO,Vector3.RIGHT,Vector3(1,0,1),Vector3.BACK,Color("80877e"))
	var west := Geometry.new()
	west.quad(Vector3.UP,Vector3(1,1,0),Vector3(1,1,1),Vector3(0,1,1),Color("80877e"))
	var next := Geometry.new()
	next.triangle(Vector3.ZERO,Vector3.RIGHT,Vector3.BACK,Color("80877e"))
	var source := Street.Join.join([old.mesh(),west.mesh()])
	_check(Street.disjoint_transferred([{"ids":["a","b"]}],{"c":true}) and not Street.disjoint_transferred([{"ids":["a","b"]}],{"b":true}),"transferred source cannot be hidden in a merged group")
	var owned := Street.without_transferred(source,old.mesh())
	_check(not owned.is_empty() and Street.Join.conserved(owned.mesh,[west.mesh()]),"old boundary removed once from both versions")
	_check(Street.without_transferred(west.mesh(),old.mesh()).is_empty(),"wrong transfer rejected instead of arbitrary face deletion")
	var unchanged: Array = source.get("_surfaces").duplicate(true)
	var result := Street.replace_low(source,old.mesh(),next.mesh())
	_check(not result.is_empty() and Street.Join.conserved(result.remainder,[west.mesh()]) and Street.Join.conserved(result.mesh,[west.mesh(),next.mesh()]),"other region survives exact north replacement")
	_check(source.get("_surfaces")==unchanged,"input source remains immutable")
	_check(Street.replace_low(old.mesh(),west.mesh(),next.mesh()).is_empty(),"different height source cannot be removed")
	_check(Street.replace_low(old.mesh(),source,next.mesh()).is_empty(),"missing north multiplicity rejected")
	var only := Street.replace_low(old.mesh(),old.mesh(),next.mesh())
	_check(not only.is_empty() and only.remainder.get_surface_count()==0 and Street.Join.conserved(only.mesh,[next.mesh()]),"north-only parent permits empty remainder")
	var directory := OS.get_environment("AGL_TOKYO_STREET_AUDIT")
	if not directory.is_empty():
		_check(Street.audit(directory,OS.get_environment("AGL_TOKYO_STREET_NEAR_CATALOG")=="1")==0,"saved four-region low-only source conservation and coverage")
	print("[Street catalog test] pass=",_pass," fail=",_fail)


func _check(ok: bool, label: String) -> void:
	if ok:
		_pass+=1
	else:
		_fail+=1
		push_error("[Street catalog test] "+label)
