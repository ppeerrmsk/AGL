extends RefCounted
## 离线逐面校验，不用父块来源标签推断子页完整性。
const Baker := preload("res://scripts/tests/bake_tokyo_shared_roofs.gd")
const Coverage := preload("res://scripts/experiments/tokyo_source_coverage.gd")
var _fail := 0
var _pages := 0
var _matched := 0
var _scanned := 0
var _labels: Dictionary = {}


func run() -> int:
	var catalog_path := OS.get_environment("AGL_TOKYO_CANONICAL_CATALOG")
	var catalog: Resource = load(catalog_path)
	var schedule_path := OS.get_environment("AGL_TOKYO_COVERAGE_SCHEDULE")
	var schedule: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(schedule_path))
	var configuration := OS.get_environment("AGL_TOKYO_COVERAGE_CONFIG")
	var output := OS.get_environment("AGL_TOKYO_COVERAGE_OUT")
	if catalog == null or not catalog.valid() or not schedule.get("passed", false) or FileAccess.file_exists(output):
		return 1
	var row: Dictionary = {}
	for item: Dictionary in schedule.configurations:
		if item.name == configuration:
			row = item
	if row.is_empty() or not catalog.configurations.has(configuration):
		return 1
	var plan_path := OS.get_environment("AGL_TOKYO_COVERAGE_PLANS").path_join(row.file)
	var plan: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(plan_path))
	if FileAccess.get_sha256(plan_path) != row.plan_sha256 or not plan.get("passed", false) \
			or plan.collision_sha256 != catalog.collision_sha256 or schedule.collision_sha256 != catalog.collision_sha256 \
			or schedule.owners_sha256 != catalog.owners_sha256 or plan.game_source_sha256 != schedule.game_source_sha256:
		return 1
	var data := {"schema": 1, "configuration": configuration, "catalog_sha256": FileAccess.get_sha256(catalog_path),
		"collision_sha256": catalog.collision_sha256, "owners_sha256": catalog.owners_sha256,
		"plan_sha256": row.plan_sha256, "schedule_sha256": FileAccess.get_sha256(schedule_path),
		"game_source_sha256": plan.game_source_sha256, "pages": {}, "sources": {}, "verified": false}
	var expected := _expected(plan, row)
	var finest: Dictionary = {}
	for parent: Dictionary in catalog.configurations[configuration]:
		var fixed_sha := _fixed_sha(int(parent.parent_id))
		_check(catalog.descriptors[parent.path].canonical_identity.source == (str(row.plan_sha256) + str(schedule.owners_sha256) + fixed_sha).sha256_text(), "catalog binds this exact source plan")
		var needs: Array = expected.get(int(parent.parent_id), [{}, {}])
		_visit(parent, needs, catalog, data, finest)
	for parent: int in expected:
		for kind in 2:
			for key: PackedByteArray in expected[parent][kind]:
				var face: Dictionary = expected[parent][kind][key]
				var token_key := str(parent) + ":" + str(kind) + ":" + key.hex_encode()
				_check(int(finest.get(token_key, 0)) == int(face.count), "finest face multiplicity: " + token_key)
	for source: Dictionary in plan.expected:
		_check(data.sources.has(int(source.source_id)), "source has nonempty dependencies")
	data.verified = _fail == 0
	var committed: Dictionary = {}
	for parent: Dictionary in catalog.configurations[configuration]:
		committed[parent.path] = {"identity": data.pages[parent.path].identity, "layers": 3}
	_check(Coverage.covered_sources(data, committed, configuration, catalog.collision_sha256, data.catalog_sha256).size() == plan.expected.size(), "all root pages cover every source")
	var stats := _audit_cuts(data, catalog)
	if _fail:
		return 1
	var file := FileAccess.open(output, FileAccess.WRITE)
	if file == null:
		return 1
	file.store_var(data)
	file.close()
	file = FileAccess.open(output, FileAccess.READ)
	_check(file.get_var(false) == data, "saved pure-value sidecar roundtrip")
	file.close()
	print("[Tokyo source coverage] configuration=", configuration, " sources=", data.sources.size(), " metadata_pages=", _pages, " scanned_pages=", _scanned, " face_matches=", _matched, " bytes=", FileAccess.get_file_as_bytes(output).size(), " cuts=", stats, " fail=", _fail)
	return 1 if _fail else 0


func _expected(plan: Dictionary, row: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	var walls: Dictionary = {}
	var candidates: Dictionary = {}
	var roles: Dictionary = {}
	for part: Dictionary in row.parts:
		for source: float in part.expected:
			walls[int(source)] = int(part.parent_id)
		for index: float in part.triangles:
			candidates[int(index)] = int(part.parent_id)
	for index in plan.triangles.size():
		var triangle: Dictionary = plan.triangles[index]
		if triangle.game_sources.is_empty():
			continue
		var parent := -1
		var kind := 1
		if triangle.layer == "native":
			var native: Dictionary = plan.native_sources[int(triangle.owner)]
			for mesh: Dictionary in plan.meshes:
				if int(mesh.id) == int(native.mesh):
					parent = int(mesh.parent_id)
					kind = int(mesh.kind)
		else:
			parent = int(candidates.get(index, -1))
		_check(parent >= 0, "roof has a known actual parent")
		_add(result, parent, kind, Baker._points(triangle).to_byte_array(), PackedInt32Array(triangle.game_sources))
		for source: float in triangle.game_sources:
			roles[int(source)] = true
	for entry: Dictionary in plan.expected:
		var source := int(entry.source_id)
		_check(roles.has(source) and walls.has(source), "source needs both roof and walls")
		var mesh: ArrayMesh = Baker._addition({"expected": [entry], "triangles": []})
		var faces := _faces(mesh)
		_check(not faces.is_empty(), "nonempty wall faces")
		for face: PackedByteArray in faces:
			_add(result, int(walls[source]), 1, face, PackedInt32Array([source]))
	return result


static func _add(result: Dictionary, parent: int, kind: int, key: PackedByteArray, sources: PackedInt32Array) -> void:
	if not result.has(parent):
		result[parent] = [{}, {}]
	if not result[parent][kind].has(key):
		result[parent][kind][key] = {"count": 0, "sources": PackedInt32Array()}
	var face: Dictionary = result[parent][kind][key]
	face.count += 1
	for source: int in sources:
		if not face.sources.has(source):
			face.sources.append(source)


static func _faces(mesh: ArrayMesh) -> Array[PackedByteArray]:
	var result: Array[PackedByteArray] = []
	if mesh.get_surface_count() == 0:
		return result
	var arrays := mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var raw := vertices.to_byte_array()
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
	for start in range(0, indices.size() if not indices.is_empty() else vertices.size(), 3):
		var key := PackedByteArray()
		for n in 3:
			var index := indices[start+n] if not indices.is_empty() else start+n
			key.append_array(raw.slice(index * 12, (index+1) * 12))
		result.append(key)
	return result


func _fixed_sha(parent: int) -> String:
	var original: Resource = load("res://resources/maps/tokyo_volume_preview/r34_cells/index.res")
	return FileAccess.get_sha256(original.cells[parent].fixed)


func _page_sha(entry: Dictionary) -> String:
	return str(entry.sha256)


func _read_page(entry: Dictionary, _catalog: Resource) -> Resource:
	_check(FileAccess.get_sha256(entry.path) == entry.sha256, "page SHA: " + str(entry.path))
	return ResourceLoader.load(entry.path, "", ResourceLoader.CACHE_MODE_IGNORE)


func _visit(entry: Dictionary, needs: Array, catalog: Resource, data: Dictionary, finest: Dictionary) -> Dictionary:
	var path: String = entry.path
	var row := {"identity": catalog.descriptors[path].canonical_identity, "sha256": _page_sha(entry),
		"leaves": PackedStringArray(), "tokens": [PackedStringArray(), PackedStringArray()]}
	var counts: Array[Dictionary] = [{}, {}]
	if not needs[0].is_empty() or not needs[1].is_empty():
		var page: Resource = _read_page(entry, catalog)
		if page == null or not page.valid() or page.stream_identity() != row.identity:
			_check(false, "actual page identity: " + path)
			return row
		_scanned += 1
		_labels[path] = page.game_sources
		for kind in 2:
			if needs[kind].is_empty():
				continue
			for key: PackedByteArray in _faces(page.meshes[kind]):
				if needs[kind].has(key):
					counts[kind][key] = int(counts[kind].get(key, 0)) + 1
					_matched += 1
	var children: Array = entry.get("children", [])
	if children.is_empty():
		row.leaves.append(path)
		for kind in 2:
			for key: PackedByteArray in counts[kind]:
				var token := path + ":" + str(kind)
				if not row.tokens[kind].has(token):
					row.tokens[kind].append(token)
				var total_key := str(entry.parent_id) + ":" + str(kind) + ":" + key.hex_encode()
				finest[total_key] = int(finest.get(total_key, 0)) + int(counts[kind][key])
				for source: int in needs[kind][key].sources:
					if not data.sources.has(source):
						data.sources[source] = PackedStringArray()
					if not data.sources[source].has(token):
						data.sources[source].append(token)
	else:
		var summed: Array[Dictionary] = [{}, {}]
		for child: Dictionary in children:
			var sub := _visit(child, needs, catalog, data, finest)
			row.leaves.append_array(sub.leaves)
			for kind in 2:
				row.tokens[kind].append_array(sub.tokens[kind])
				for key: PackedByteArray in sub.get("counts", [{}, {}])[kind]:
					summed[kind][key] = int(summed[kind].get(key, 0)) + int(sub.counts[kind][key])
		for kind in 2:
			_check(summed[kind] == counts[kind], "each subtree conserves required oriented faces: " + path)
	if int(entry.cell_id) == -1:
		for kind in 2:
			for key: PackedByteArray in needs[kind]:
				_check(int(counts[kind].get(key, 0)) == int(needs[kind][key].count), "root face multiplicity: " + path)
	data.pages[path] = row.duplicate(true)
	_pages += 1
	row["counts"] = counts
	return row


func _audit_cuts(data: Dictionary, catalog: Resource) -> Dictionary:
	var cut: Dictionary = {}
	var paths: Dictionary = {}
	var result := {"missing_fragment_cases": 0, "multi_page_sources": 0, "multi_parent_sources": 0, "insufficient_page_labels": 0}
	for path: String in data.pages:
		var row: Dictionary = data.pages[path]
		if row.leaves.size() == 1 and row.leaves[0] == path:
			cut[path] = {"identity": row.identity, "layers": 3}
			for kind in 2:
				for token: String in row.tokens[kind]:
					paths[token] = {"path": path, "kind": kind, "parent": row.identity.parent}
	_check(Coverage.covered_sources(data, cut, data.configuration, data.collision_sha256, data.catalog_sha256).size() == data.sources.size(), "all finest pages cover every source")
	for source: int in data.sources:
		var source_pages: Dictionary = {}
		var parents: Dictionary = {}
		for token: String in data.sources[source]:
			var item: Dictionary = paths[token]
			source_pages[item.path] = true
			parents[item.parent] = true
			cut[item.path].layers = 3 & ~(1 << int(item.kind))
			_check(not Coverage.covered_sources(data, cut, data.configuration, data.collision_sha256, data.catalog_sha256).has(source), "actual source retains old visual when any dependency is absent")
			cut[item.path].layers = 3
			result.missing_fragment_cases += 1
		result.multi_page_sources += int(source_pages.size() > 1)
		result.multi_parent_sources += int(parents.size() > 1)
	for path: String in _labels:
		var single := {path: {"identity": data.pages[path].identity, "layers": 3}}
		var covered := Coverage.covered_sources(data, single, data.configuration, data.collision_sha256, data.catalog_sha256)
		for source: int in _labels[path]:
			result.insufficient_page_labels += int(not covered.has(source))
	cut.clear()
	for parent: Dictionary in catalog.configurations[data.configuration]:
		for child: Dictionary in parent.children:
			cut[child.path] = {"identity": data.pages[child.path].identity, "layers": 3}
	_check(Coverage.covered_sources(data, cut, data.configuration, data.collision_sha256, data.catalog_sha256).size() == data.sources.size(), "all intermediate pages cover every source")
	return result


func _check(ok: bool, label: String) -> void:
	if not ok:
		_fail += 1
		if _fail <= 12:
			push_error("[Bench] Tokyo source coverage: " + label)
