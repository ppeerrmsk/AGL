extends RefCounted
const Coverage := preload("res://scripts/rendering/tokyo_hlod_coverage.gd")


static func checks() -> bool:
	if not load("res://scripts/rendering/tokyo_hlod_overlay.gd").can_instantiate(): return false
	var catalog := Coverage.Contract.normalize(preload("res://scripts/tests/test_tokyo_hlod_manifest.gd").fixture())
	catalog["identity"]={"path":"res://fixture.json","sha256":"a".repeat(64)}
	var pages: Dictionary = {}
	for key: String in catalog.rows:
		var row: Dictionary = catalog.rows[key]
		pages[key]={"geometry":row.native_geometry.duplicate(true),"formal_sources":row.formal_source_ids.duplicate(),
			"formal_faces":int(row.faces)-int(row.ordinary_faces)-2,"formal_positions_sha256":"b".repeat(64)}
	var proof := {"schema":1,"sources":189,"source_geometry_verified":true,"game_source_sha256":Coverage.Full.GAME_SHA,
		"collision_sha256":Coverage.Full.COLLISION_SHA,"catalogs":[{"manifest":catalog.identity.duplicate(),"pages":pages}]}
	if Coverage.bind(proof,catalog).size()!=336: return false
	for field in ["collision_sha256","game_source_sha256"]:
		var wrong := proof.duplicate(true)
		wrong[field]="0".repeat(64)
		if not Coverage.bind(wrong,catalog).is_empty(): return false
	for field in ["formal_faces","formal_sources","formal_positions_sha256","geometry"]:
		var wrong := proof.duplicate(true)
		wrong.catalogs[0].pages["0:0"].erase(field)
		if not Coverage.bind(wrong,catalog).is_empty(): return false
	var points := PackedVector3Array([Vector3.ZERO,Vector3.RIGHT,Vector3.FORWARD])
	if not Coverage.matches(ArrayMesh.new(),{"formal_faces":0,"formal_positions_sha256":"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"}): return false
	var digest := HashingContext.new()
	digest.start(HashingContext.HASH_SHA256)
	digest.update(points.to_byte_array())
	var descriptor := {"formal_faces":1,"formal_positions_sha256":digest.finish().hex_encode()}
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=points
	arrays[Mesh.ARRAY_INDEX]=PackedInt32Array([0,1,2])
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	if not Coverage.matches(mesh,descriptor): return false
	descriptor.formal_faces=2
	if Coverage.matches(mesh,descriptor): return false
	descriptor.formal_faces=1;descriptor.formal_positions_sha256="0".repeat(64)
	if Coverage.matches(mesh,descriptor): return false
	var ready := {"stream":{"pending":0,"failures":{},"texture_pending":0,"texture_failures":{}},
		"desired_cells":1,"ready_cells":1,"cut_ready":true,"active_cells":1}
	var preload_session := preload("res://scripts/rendering/tokyo_volume_preload.gd")
	if not preload_session.state_ready(ready): return false
	ready.stream.texture_pending=1
	if preload_session.state_ready(ready): return false
	ready.stream.texture_pending=0;ready.stream.texture_failures={"bad":"digest"}
	return not preload_session.state_ready(ready)
