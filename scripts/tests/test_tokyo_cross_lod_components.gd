extends RefCounted
const Builder := preload("res://scripts/tests/build_tokyo_cross_lod_components.gd")
const Manifest := preload("res://scripts/rendering/tokyo_component_manifest.gd")
const Component := preload("res://scripts/rendering/tokyo_mesh_component.gd")
const Page := preload("res://scripts/rendering/tokyo_canonical_spatial_page.gd")
const Stream := preload("res://scripts/rendering/tokyo_component_stream.gd")
var _pass := 0
var _fail := 0


func run() -> void:
	var descriptors: Dictionary = {}
	var pages: Dictionary = {}
	for n in 208:
		descriptors[str(n)] = {"canonical_identity":{"configuration":"lod1_full"}}
		pages[str(n)] = {}
	_check(Manifest.complete_coverage(pages,descriptors,PackedStringArray(["lod1_full"])),"full declared configuration covered")
	pages.erase("7")
	pages["outside"] = {}
	_check(not Manifest.complete_coverage(pages,descriptors,PackedStringArray(["lod1_full"])),"same count cannot mask missing source")
	pages.erase("outside")
	pages["7"] = {}
	for selected: PackedStringArray in [PackedStringArray(),PackedStringArray(["unknown"]),PackedStringArray(["lod1_full","lod1_full"]),PackedStringArray(["lod2_full"])]:
		_check(not Manifest.complete_coverage(pages,descriptors,selected),"invalid coverage declaration rejected")
	var mesh := ArrayMesh.new()
	_check(Builder.mesh_key(mesh,0)==Builder.mesh_key(mesh.duplicate(),0),"native content key repeatable")
	_check(Builder.mesh_key(mesh,0)!=Builder.mesh_key(mesh,1),"layer identity prevents intra-page cost alias")
	var copy: ArrayMesh = mesh.duplicate()
	copy.custom_aabb = AABB(Vector3.ONE,Vector3.ONE)
	_check(Builder.mesh_key(mesh,0)!=Builder.mesh_key(copy,0),"custom bounds participate in identity")
	var physical: Dictionary = {}
	for kind in 3:
		var part := Component.new()
		part.source_hash = str(kind).sha256_text()
		part.meshes.assign([ArrayMesh.new()])
		part.mesh_bytes = PackedInt32Array([0])
		physical[str(kind)] = {"path":str(kind),"bytes":0,"canonical_identity":part.stream_identity()}
	var page := Page.new()
	page.configuration = "lod1_full"
	page.level = 1
	page.parent_id = 0
	page.source_hash = "a".repeat(64)
	page.collision_sha256 = "b".repeat(64)
	page.owners_sha256 = "c".repeat(64)
	var row := {"bytes":0,"canonical_identity":page.stream_identity(),"components":physical,"mapping":[["0",0],["1",0],["2",0]],"game_sources":page.game_sources,"triangles":0}
	_check(Manifest.valid_row(row,row,physical),"three independent components on LOD1")
	var broken := row.duplicate(true)
	broken.mapping[2] = ["1",0]
	_check(not Manifest.valid_row(broken,row,physical),"unused charged component rejected")
	broken = row.duplicate(true)
	broken.mapping[2][1] = 1
	_check(not Manifest.valid_row(broken,row,physical),"single mesh component cannot address second slot")
	_check(load("res://scripts/tests/tokyo_component_review.gd").can_instantiate(),"original native comparison remains available")
	print("[R72 cross component test] pass=",_pass," fail=",_fail)


static func lifecycle(parent: Node, path: String, catalog_path: String) -> int:
	var catalog: Resource = load(catalog_path)
	var data := Manifest.read(path,catalog,FileAccess.get_sha256(catalog_path))
	if data.is_empty():
		return 1
	var first: String = catalog.configurations.lod1_full[8].path
	var second: String = catalog.configurations.lod2_full[8].path
	var owner := Node.new()
	parent.add_child(owner)
	var stream := Stream.new()
	parent.add_child(stream)
	stream.configure(owner,data.pages)
	stream.request(PackedStringArray([first,second]),PackedStringArray())
	var deadline := Time.get_ticks_msec()+15000
	while (stream.resource(first)==null or stream.resource(second)==null) and Time.get_ticks_msec()<deadline:
		await parent.get_tree().process_frame
	if stream.resource(first)==null or stream.resource(second)==null:
		owner.queue_free()
		return 1
	var fail := int(stream.resource(first).meshes[2]!=stream.resource(second).meshes[2])
	var fixed_ref: WeakRef = weakref(stream.resource(first).meshes[2])
	var old_ref: WeakRef = weakref(stream.resource(first))
	var stream_ref: WeakRef = weakref(stream)
	var before := stream.summary()
	stream.request(PackedStringArray([second]),PackedStringArray())
	await parent.get_tree().process_frame
	await parent.get_tree().process_frame
	var after := stream.summary()
	var expected_bytes: int = before.bytes if stream._retain_unused else data.pages[second].bytes
	fail += int(old_ref.get_ref()!=null or fixed_ref.get_ref()==null or before.completed!=after.completed or after.bytes!=expected_bytes)
	owner.queue_free()
	deadline = Time.get_ticks_msec()+15000
	while stream_ref.get_ref()!=null and Time.get_ticks_msec()<deadline:
		await parent.get_tree().process_frame
	fail += int(stream_ref.get_ref()!=null or fixed_ref.get_ref()!=null or not Stream._busy.is_empty())
	print("[R72 cross component lifecycle] before=",before," after=",after," fail=",fail)
	return fail


func _check(ok: bool, label: String) -> void:
	if ok:
		_pass += 1
	else:
		_fail += 1
		push_error("[Bench] R72 "+label)
