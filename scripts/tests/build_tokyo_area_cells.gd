extends RefCounted
const Builder := preload("res://scripts/tests/build_tokyo_cells.gd")
const Factory := preload("res://scripts/experiments/tokyo_volume_preview_factory.gd")
const Geometry := preload("res://scripts/experiments/volume_mesh_factory.gd")
const Indexed := preload("res://scripts/experiments/tokyo_indexed_mesh.gd")
const Signature := preload("res://scripts/tests/tokyo_mesh_signature.gd")
const Duplicates := preload("res://scripts/experiments/tokyo_duplicate_outline.gd")
const Levels := preload("res://scripts/rendering/tokyo_volume_archive.gd")
const OUT := "res://bench/results/tokyo_r30_cells"
var _fail := 0
var _records: Dictionary = {}
var _suppressed: Dictionary = {}
var _changes := 0


func run() -> void:
	var root := OS.get_environment("AGL_TOKYO_AREA_ROOT")
	if root.is_empty() or not FileAccess.file_exists(root.path_join("audit.json")):
		_fail = 1
		print("[Tokyo area] missing verified source fail=1")
		return
	var audit: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(root.path_join("audit.json")))
	var source: Resource = load("res://resources/maps/tokyo_volume_preview/r29_cells/index.res")
	assert(source.valid())
	for region: String in ["yokohama", "north_coast"]:
		var path := root.path_join(region).path_join("city.json")
		assert(audit.regions[region].source_hash == source.joined_sources[region].source_hash)
		assert(FileAccess.get_sha256(path) == audit.regions[region].prepared_sha256)
		var city: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
		_records[region] = {}
		_suppressed[region] = Duplicates.suppressed(city.buildings)
		for raw: Dictionary in city.buildings:
			_records[region][String(raw.id)] = raw
	var target: Resource = source.duplicate(true)
	DirAccess.make_dir_recursive_absolute(OUT)
	var report := {"source_count": source.source_count, "cells": [], "audit_sha256": FileAccess.get_sha256(root.path_join("audit.json")), "fail": 0}
	for id in source.cells.size():
		var old: Dictionary = source.cells[id]
		var entry: Dictionary = target.cells[id]
		entry.fixed = String(old.fixed).replace("r29_cells", "r30_cells")
		_save(load(old.fixed), entry.fixed)
		for slot in 7:
			var descriptor: Dictionary = entry.mid if slot == 6 else entry.levels[slot]
			var original: Resource = ResourceLoader.load(descriptor.path, "", ResourceLoader.CACHE_MODE_IGNORE)
			var cell := _convert(original, old.region) if slot < 4 else original
			descriptor.path = String(descriptor.path).replace("r29_cells", "r30_cells")
			descriptor.bytes = cell.geometry_bytes
			descriptor.triangles = cell.triangles
			_save(cell, descriptor.path)
		report.cells.append(entry)
		print("[Tokyo area] cell=", id, " changes=", _changes, " fail=", _fail)
	_save(target, "index.res")
	report.fail = _fail
	report.changed_building_levels = _changes
	var file := FileAccess.open(OUT.path_join("build_report.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	print("[Tokyo area] sources=", source.source_count, " changes=", _changes, " fail=", _fail)


func _convert(source: Resource, region: String) -> Resource:
	var before := Geometry.new()
	var after := Geometry.new()
	var changed := 0
	for identity: String in source.source_ids:
		var raw: Dictionary = _records[region][identity]
		assert(raw.regional_draw_owner == region)
		if raw.height_source != "fallback" or raw.get("defer_render", false) or not raw.get("render_outline", true) or _suppressed[region].has(identity):
			continue
		var detail := Builder.detail_level(raw, Levels.SCALES[source.level], true)
		var record: Dictionary = raw.duplicate()
		if detail == 2 and region == "north_coast" and raw.get("footprint_lod", {}).has(str(source.level)):
			record.rings = raw.footprint_lod[str(source.level)].rings
		Factory._add_ring_building(before, record, float(raw.height_m) * 0.5, detail)
		if detail == 2 and raw.get("area_lod", {}).has(str(source.level)):
			assert(is_equal_approx(raw.area_lod[str(source.level)].max_scale, Levels.CUTS[source.level] * 1.08))
			record.rings = raw.area_lod[str(source.level)].rings
			changed += 1
		Factory._add_ring_building(after, record, float(raw.height_m) * 0.5, detail)
	if changed == 0:
		return source
	var before_mesh := before.mesh()
	assert(Signature.of_mesh(before_mesh) == Signature.of_mesh(source.meshes[0]), "source reconstruction must exactly match prior ordered triangles independent of batch order")
	var result: Resource = source.duplicate(false)
	result.meshes = source.meshes.duplicate()
	result.meshes[0] = Indexed.pack(after.mesh())
	result.precision_original = source.precision_original if source.precision_original != null else source.meshes[0]
	result.precision_triangles = Indexed.triangles(result.precision_original)
	result.precision_max_scale = Levels.CUTS[source.level] * 1.08
	result.triangles = 0
	result.geometry_bytes = 0
	Builder.finish(result)
	assert(result.valid() and result.triangles < source.triangles)
	_changes += changed
	return result


func _save(resource: Resource, path: String) -> void:
	if ResourceSaver.save(resource, OUT.path_join(path.get_file()), ResourceSaver.FLAG_COMPRESS) != OK:
		_fail += 1
