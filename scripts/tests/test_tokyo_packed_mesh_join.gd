extends RefCounted
const Join := preload("res://scripts/experiments/tokyo_packed_mesh_join.gd")
const Geometry := preload("res://scripts/experiments/volume_mesh_factory.gd")
const Split := preload("res://scripts/experiments/tokyo_spatial_split.gd")
const Page := preload("res://scripts/rendering/tokyo_canonical_spatial_page.gd")
var _pass := 0
var _fail := 0


func run() -> Dictionary:
	_check(load("res://scripts/tests/build_tokyo_canonical_spatial.gd").can_instantiate(), "spatial builder compiles")
	var builder := Geometry.new()
	builder.triangle(Vector3(-1,2,0), Vector3(3,2,0), Vector3(0,2,4), Color(0.31,0.53,0.77))
	var source := builder.mesh()
	var before := var_to_bytes(source.get("_surfaces"))
	var indexed := Join.join([source])
	var joined := Join.join([indexed, source, ArrayMesh.new()])
	_check(Join.conserved(joined, [source, source]), "mixed indexed/unindexed packed corners conserved")
	_check(joined.get_surface_count() == 1, "one surface avoids extra draw/material batch")
	_check(before == var_to_bytes(source.get("_surfaces")), "source packed data immutable")
	_check(Join.join([ArrayMesh.new()]).get_surface_count() == 0, "empty layers remain empty")
	_check(not Join.conserved(joined, [source]), "missing duplicate multiplicity rejected")
	_check(not Join.conserved(source, [joined]), "extra faces rejected")
	var pieces := Split.split(joined, PackedFloat32Array([0,0,0]))
	_check(Join.conserved(joined, pieces), "split preserves positions normals tangents colors and winding")
	for mesh: ArrayMesh in pieces:
		if mesh.get_surface_count() > 0:
			_check(mesh.get_aabb().position.x == -1 and mesh.get_aabb().end.x == 3, "cross-boundary face retains full bounds")
	var large := Geometry.new()
	for n in 21845:
		large._vertices.append_array(builder._vertices)
		large._normals.append_array(builder._normals)
		large._colors.append_array(builder._colors)
	var old := large.mesh()
	var wide := Join.join([old, source])
	var surface: Dictionary = wide.get("_surfaces")[0]
	_check(int(surface.vertex_count) == 65538 and surface.index_data.size() == 65538 * 4, "index width expands at 65536 vertices")
	_check(Join.conserved(wide, [old, source]), "32-bit remap preserves every old corner")
	var reindex := preload("res://scripts/experiments/tokyo_packed_mesh_reindex.gd")
	var compact := reindex.repack(wide)
	_check(compact.surface_get_array_len(0)==3 and reindex.corner_digest(compact)==reindex.corner_digest(wide),"reindex shares exact corners and retains order and multiplicity")
	_check(compact.get("_surfaces")[0].index_data.size()==65538*2,"reindex shrinks index width after exact vertex reuse")
	_check(reindex.decoded_bytes(compact)<reindex.decoded_bytes(wide),"decoded memory actually decreases")
	_check(reindex.repack(source)==source and reindex.repack(ArrayMesh.new()).get_surface_count()==0,"no saving and empty keep original")
	var seam := Geometry.new()
	seam.triangle(Vector3(-1,2,0),Vector3(3,2,0),Vector3(0,2,4),Color.RED)
	var seam_mesh := Join.join([source,seam.mesh()])
	_check(reindex.repack(seam_mesh).surface_get_array_len(0)==6,"same position with distinct color cannot weld")
	_check(before==var_to_bytes(source.get("_surfaces")),"reindex never mutates source")
	var reverse := Geometry.new()
	reverse._vertices=builder._vertices.duplicate()
	reverse._colors=builder._colors.duplicate()
	for normal: Vector3 in builder._normals:
		reverse._normals.append(-normal)
	_check(reindex.repack(Join.join([source,reverse.mesh()])).surface_get_array_len(0)==6,"normal seam cannot weld at equal position and color")
	var unused := Join.join([source,source])
	var unused_surface: Dictionary = unused.get("_surfaces")[0].duplicate()
	unused_surface.index_count=3
	unused_surface.index_data=unused_surface.index_data.slice(0,6)
	unused.set("_surfaces",[unused_surface])
	unused.custom_aabb=AABB(Vector3(-5,-5,-5),Vector3(20,20,20))
	var material := StandardMaterial3D.new()
	unused.surface_set_material(0,material)
	var pruned := reindex.repack(unused)
	_check(pruned.surface_get_array_len(0)==3 and reindex.corner_digest(pruned)==reindex.corner_digest(unused),"unused corners removed without changing drawn sequence")
	_check(pruned.custom_aabb==unused.custom_aabb and pruned.surface_get_material(0)==material,"custom bounds and material retained")
	var page := Page.new()
	page.level = 5
	page.configuration = "lod5_full"
	page.parent_id = 0
	page.meshes = [source, indexed, ArrayMesh.new()]
	page.source_hash = "a".repeat(64)
	page.collision_sha256 = "b".repeat(64)
	page.owners_sha256 = "c".repeat(64)
	_check(page.valid(), "canonical parent page identity accepted")
	page.cell_id = 4
	_check(not page.valid(), "child cannot claim another parent")
	page.cell_id = 0
	_check(page.valid(), "own child identity accepted")
	page.configuration = "lod4_full"
	_check(not page.valid(), "wrong LOD configuration rejected")
	print("[Tokyo packed join] pass=", _pass, " fail=", _fail)
	return {"pass": _pass, "fail": _fail}


func _check(value: bool, message: String) -> void:
	if value:
		_pass += 1
	else:
		_fail += 1
		push_error("Tokyo packed join: " + message)
