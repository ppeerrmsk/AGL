extends RefCounted
## 屋顶/完整墙面凭据只授权精确原生槽，不沿用旧canonical来源标签。
const Contract := preload("res://scripts/rendering/tokyo_hlod_manifest.gd")
const Full := preload("res://scripts/rendering/tokyo_full_grid_contract.gd")


static func bind(data: Variant, catalog: Dictionary) -> Dictionary:
	if not data is Dictionary or data.get("schema")!=1 or data.get("sources")!=189 \
		or data.get("source_geometry_verified")!=true or data.get("game_source_sha256")!=Full.GAME_SHA \
		or data.get("collision_sha256")!=Full.COLLISION_SHA or not data.get("catalogs") is Array \
		or not catalog.get("identity") is Dictionary: return {}
	var found: Dictionary = {}
	for row: Variant in data.catalogs:
		if not row is Dictionary or not Contract.binding(row.get("manifest")): return {}
		if row.manifest.path==catalog.identity.path and row.manifest.sha256==catalog.identity.sha256:
			if not found.is_empty(): return {}
			found=row
	if not found.get("pages") is Dictionary or found.pages.size()!=336: return {}
	var geometry: Dictionary = catalog.geometry.duplicate(true)
	for key: String in catalog.rows:
		var page: Dictionary = catalog.rows[key]
		var proof: Variant = found.pages.get(key)
		if not proof is Dictionary or not Contract.binding(proof.get("geometry")) \
			or not Contract.sha(proof.get("formal_positions_sha256")) or not proof.get("formal_sources") is Array \
			or proof.get("formal_faces")!=int(page.faces)-int(page.ordinary_faces)-2 \
			or not Contract.same_numbers(proof.formal_sources,page.formal_source_ids): return {}
		var physical: String = page.native_geometry.path
		if proof.geometry.path!=physical or proof.geometry.sha256!=page.native_geometry.sha256 \
			or proof.geometry.get("bytes")!=page.native_geometry.bytes \
			or proof.geometry.get("canonical_identity")!=page.native_geometry.canonical_identity: return {}
		var descriptor: Dictionary = geometry[physical]
		if descriptor.has("formal_positions_sha256") and (descriptor.formal_positions_sha256!=proof.formal_positions_sha256 \
			or descriptor.formal_faces!=proof.formal_faces): return {}
		descriptor["formal_positions_sha256"]=proof.formal_positions_sha256
		descriptor["formal_faces"]=int(proof.formal_faces)
	return geometry


static func read(path: String, sha: String, catalog: Dictionary) -> Dictionary:
	if not Contract.sha(sha) or not FileAccess.file_exists(path) or FileAccess.get_sha256(path)!=sha: return {}
	return bind(JSON.parse_string(FileAccess.get_file_as_string(path)),catalog)


static func matches(mesh: ArrayMesh, descriptor: Dictionary) -> bool:
	if mesh==null or not Contract.sha(descriptor.get("formal_positions_sha256")) \
		or not Contract.integer(descriptor.get("formal_faces")): return false
	var points := PackedVector3Array()
	if mesh.get_surface_count()>1: return false
	var trace := PerfBuckets.frame_trace_enabled
	var phase_started := Time.get_ticks_usec() if trace else 0
	if mesh.get_surface_count()==1:
		if mesh.surface_get_primitive_type(0)!=Mesh.PRIMITIVE_TRIANGLES: return false
		var arrays := mesh.surface_get_arrays(0)
		if trace:
			PerfBuckets.tick("tokyo_map_stream.coverage_arrays",Time.get_ticks_usec()-phase_started)
			phase_started=Time.get_ticks_usec()
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		if indices.is_empty():
			points=vertices
		else:
			points.resize(indices.size())
			for n in indices.size():
				if indices[n]<0 or indices[n]>=vertices.size(): return false
				points[n]=vertices[indices[n]]
		if trace:
			PerfBuckets.tick("tokyo_map_stream.coverage_expand",Time.get_ticks_usec()-phase_started)
			phase_started=Time.get_ticks_usec()
	if points.size()!=int(descriptor.formal_faces)*3: return false
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	if not points.is_empty(): context.update(points.to_byte_array())
	var verified: bool = context.finish().hex_encode()==descriptor.formal_positions_sha256
	if trace: PerfBuckets.tick("tokyo_map_stream.coverage_hash",Time.get_ticks_usec()-phase_started)
	return verified
