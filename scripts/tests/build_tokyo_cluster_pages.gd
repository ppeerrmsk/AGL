extends "res://scripts/tests/build_tokyo_lod_spatial_pages.gd"
## R44离线：同父包低层合并，先原形重建守恒再替换；标高和固定面不动。
const Factory := preload("res://scripts/experiments/tokyo_volume_preview_factory.gd")
const Geometry := preload("res://scripts/experiments/volume_mesh_factory.gd")
const Builder := preload("res://scripts/tests/build_tokyo_cells.gd")
const Palette := preload("res://scripts/experiments/tokyo_palette.gd")
const Signature := preload("res://scripts/tests/tokyo_mesh_signature.gd")
const Duplicates := preload("res://scripts/experiments/tokyo_duplicate_outline.gd")
const CLUSTER_OUT := "res://bench/results/tokyo_r44_lod_pages"
const CLUSTER_DEST := "res://resources/maps/tokyo_volume_preview/r44_lod_pages"
const PLAN_HASH := "b938fb328a5b8102eb117535f9a56ed4a5f34685b448b15b8c0dcbad76615213"
const CITY_HASH := "ccdb340925d2646d98eaa873055951d46e095198dec20b057774354a5633a170"
var _records: Dictionary = {}
var _suppressed: Dictionary = {}
var _plan: Dictionary = {}


func run() -> void:
	assert(not DirAccess.dir_exists_absolute(CLUSTER_OUT), "cluster output cannot overwrite a prior candidate")
	var city_path := OS.get_environment("AGL_TOKYO_CLUSTER_SOURCE")
	var plan_path := OS.get_environment("AGL_TOKYO_CLUSTER_PLAN")
	assert(FileAccess.get_sha256(city_path) == CITY_HASH and FileAccess.get_sha256(plan_path) == PLAN_HASH)
	var city: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(city_path))
	_plan = JSON.parse_string(FileAccess.get_file_as_string(plan_path))
	assert(_plan.source_sha256 == CITY_HASH and _plan.max_group == 4 and is_equal_approx(_plan.max_scale, 1.5552))
	_suppressed = Duplicates.suppressed(city.buildings)
	for raw: Dictionary in city.buildings:
		_records[String(raw.id)] = raw
	DirAccess.make_dir_recursive_absolute(CLUSTER_OUT)
	var report := {"plan_sha256": PLAN_HASH, "city_sha256": CITY_HASH, "parents": [], "fail": 0}
	for variant: String in ["full", "mid"]:
		var out := CLUSTER_OUT.path_join(variant)
		var destination := CLUSTER_DEST.path_join(variant)
		DirAccess.make_dir_recursive_absolute(out)
		var catalog: Resource = load("res://resources/maps/tokyo_volume_preview/r42_lod_pages/" + variant + "/index.res").duplicate(true)
		assert(catalog.valid())
		var claimed: Dictionary = {}
		for id in range(8, 16):
			var old: Dictionary = catalog.parents[id].duplicate(true)
			var source: Resource = ResourceLoader.load(old.building, "", ResourceLoader.CACHE_MODE_IGNORE)
			assert(source.valid() and source.level == 4 and old.removed_faces.is_empty())
			var converted := rebuild(source, variant == "mid")
			for identity: String in converted.source_ids:
				assert(not claimed.has(identity), "one source cannot enter two cluster roots")
				claimed[identity] = true
			var row := {"parent_id": id, "variant": variant, "groups": converted.groups.size(),
				"sources": converted.source_ids.size(), "faces_saved": converted.faces_saved}
			report.parents.append(row)
			if converted.groups.is_empty():
				continue
			var fixed: Resource = ResourceLoader.load(old.fixed, "", ResourceLoader.CACHE_MODE_IGNORE)
			var meshes: Array[ArrayMesh] = [converted.mesh, source.meshes[1], fixed.meshes[0]]
			var descriptor := Spatial.descriptor(meshes)
			var canonical: Resource = source.duplicate(false)
			var building_meshes: Array[ArrayMesh] = [meshes[0], meshes[1]]
			canonical.meshes = building_meshes
			canonical.triangles = source.triangles - int(converted.faces_saved)
			canonical.geometry_bytes = int(descriptor.bytes) - int(fixed.geometry_bytes)
			assert(canonical.valid() and canonical.height_hash == source.height_hash and canonical.source_ids == source.source_ids)
			var name_value := "parent_%02d_lod_4.res" % id
			_fail += int(ResourceSaver.save(canonical, out.path_join(name_value), ResourceSaver.FLAG_COMPRESS) != OK)
			var context := {"out": out, "destination": destination, "variant": variant, "parent_id": id,
				"height_hash": source.height_hash, "source_hash": (FileAccess.get_sha256(old.fixed) + ":" + FileAccess.get_sha256(out.path_join(name_value))).sha256_text()}
			var parent := old.duplicate(true)
			parent.merge(descriptor, true)
			parent.building = destination.path_join(name_value)
			parent["cluster_original"] = old.building
			parent["cluster_plan_sha256"] = PLAN_HASH
			parent["cluster_groups"] = converted.groups
			parent["cluster_sources"] = converted.source_ids
			parent["cluster_faces_saved"] = converted.faces_saved
			parent.children = []
			var pieces := _split_layers(meshes, old.cuts)
			for n in 4:
				var child_meshes: Array[ArrayMesh] = [pieces[0][n], pieces[1][n], pieces[2][n]]
				var child := _save_page(child_meshes, id * 4 + n, -1, context)
				child["cuts"] = old.children[n].cuts
				child["children"] = []
				var leaves := _split_layers(child_meshes, child.cuts)
				for slot in 4:
					var leaf_meshes: Array[ArrayMesh] = [leaves[0][slot], leaves[1][slot], leaves[2][slot]]
					child.children.append(_save_page(leaf_meshes, 64 + int(child.cell_id) * 4 + slot, child.cell_id, context))
				parent.children.append(child)
			catalog.parents[id] = parent
			print("[Tokyo cluster build] variant=", variant, " parent=", id, " groups=", row.groups, " saved=", row.faces_saved)
		assert(catalog.valid())
		_fail += int(ResourceSaver.save(catalog, out.path_join("index.res"), ResourceSaver.FLAG_COMPRESS) != OK)
	report.fail = _fail
	var file := FileAccess.open(CLUSTER_OUT.path_join("build_report.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print("[Tokyo cluster build] fail=", _fail)


func rebuild(source: Resource, middle: bool) -> Dictionary:
	var local_ids: Dictionary = {}
	for identity: String in source.source_ids:
		local_ids[identity] = true
	var replacement: Dictionary = {}
	var groups: Array[Dictionary] = []
	var changed_ids := PackedStringArray()
	for group: Dictionary in _plan.groups:
		var valid := true
		var detail := 2
		var old_faces := 0
		for identity: String in group.ids:
			if not local_ids.has(identity) or not _records.has(identity) or _suppressed.has(identity):
				valid = false
				break
			var raw: Dictionary = _records[identity]
			if raw.regional_draw_owner != "north_coast" or raw.height_source != "fallback" or raw.height_m != group.height_m or raw.get("defer_render", false) or not raw.get("render_outline", true):
				valid = false
				break
			var source_detail := Builder.detail_level(raw, 1.0 if middle else 1.6, true)
			detail = mini(detail, source_detail)
			old_faces += face_count(raw.rings[0], source_detail)
		if not valid:
			continue
		var ring := {"outer": group.outer, "holes": [], "triangles": group.triangles}
		if face_count(ring, detail) >= old_faces:
			continue
		var first: String = group.ids[0]
		var record: Dictionary = _records[first].duplicate()
		record.rings = [ring]
		var accepted := {"ids": group.ids, "height_m": group.height_m, "outer": group.outer, "detail": detail}
		groups.append(accepted)
		for identity: String in group.ids:
			assert(not replacement.has(identity))
			replacement[identity] = {"emit": identity == first, "record": record, "detail": detail}
			changed_ids.append(identity)
	var before := Geometry.new()
	var after := Geometry.new()
	for identity: String in source.source_ids:
		var raw: Dictionary = _records[identity]
		assert(raw.regional_draw_owner == "north_coast")
		if raw.height_source != "fallback" or raw.get("defer_render", false) or not raw.get("render_outline", true) or _suppressed.has(identity):
			continue
		var detail := Builder.detail_level(raw, 1.0 if middle else 1.6, true)
		Factory._add_ring_building(before, raw, float(raw.height_m) * 0.5, detail)
		if replacement.has(identity):
			var entry: Dictionary = replacement[identity]
			if entry.emit:
				Factory._add_ring_building(after, entry.record, float(raw.height_m) * 0.5, entry.detail)
		else:
			Factory._add_ring_building(after, raw, float(raw.height_m) * 0.5, detail)
	var reconstructed := Palette.recolor(Indexed.pack(before.mesh()))
	assert(Signature.of_mesh(reconstructed) == Signature.of_mesh(source.meshes[0]), "unmodified source rebuild must equal the native R42 low layer")
	var mesh := Palette.recolor(Indexed.pack(after.mesh()))
	var saved := Indexed.triangles(source.meshes[0]) - Indexed.triangles(mesh)
	assert(saved >= 0)
	return {"mesh": mesh, "groups": groups, "source_ids": changed_ids, "faces_saved": saved}


static func face_count(ring: Dictionary, detail: int) -> int:
	var count := int((ring.triangles as Array).size() / 3)
	if detail < 2:
		count += (ring.outer as Array).size() * 2
		for hole: Array in ring.get("holes", []):
			count += hole.size() * 2
	if detail == 0:
		count += int((ring.get("inset_triangles", []) as Array).size() / 3) + int((ring.get("panel_triangles", []) as Array).size() / 3)
	return count
