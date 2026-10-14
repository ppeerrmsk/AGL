extends RefCounted
const Indexed := preload("res://scripts/experiments/tokyo_indexed_mesh.gd")
const Builder := preload("res://scripts/tests/build_tokyo_cells.gd")
const OUT := "res://bench/results/tokyo_r28_cells"
var _fail := 0


func run() -> void:
	var source: Resource = load("res://resources/maps/tokyo_volume_preview/r26b_cells/index.res")
	assert(source.valid())
	var target: Resource = source.duplicate(true)
	DirAccess.make_dir_recursive_absolute(OUT)
	var report := {"source_count": source.source_count, "cells": [], "fail": 0}
	for id in source.cells.size():
		var old: Dictionary = source.cells[id]
		var entry: Dictionary = target.cells[id]
		var fixed := _convert(old.fixed)
		entry.fixed = String(old.fixed).replace("r26b_cells", "r28_cells")
		entry.fixed_bytes = fixed.geometry_bytes
		_save(fixed, entry.fixed)
		for slot in 7:
			var descriptor: Dictionary = entry.mid if slot == 6 else entry.levels[slot]
			var cell := _convert(descriptor.path)
			descriptor.path = String(descriptor.path).replace("r26b_cells", "r28_cells")
			descriptor.bytes = cell.geometry_bytes
			assert(cell.triangles == descriptor.triangles)
			_save(cell, descriptor.path)
		report.cells.append(entry)
		print("[Tokyo indexed] cell=", id, " fail=", _fail)
	_save(target, "index.res")
	report.fail = _fail
	var file := FileAccess.open(OUT.path_join("build_report.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	print("[Tokyo indexed] sources=", source.source_count, " fail=", _fail)


func _convert(path: String) -> Resource:
	var source: Resource = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
	assert(source.valid())
	var result: Resource = source.duplicate(false)
	var meshes: Array[ArrayMesh] = []
	for mesh: ArrayMesh in source.meshes:
		meshes.append(Indexed.pack(mesh))
	result.meshes = meshes
	if source.precision_original != null:
		result.precision_original = Indexed.pack(source.precision_original)
		assert(Indexed.triangles(result.precision_original) == source.precision_triangles)
	result.triangles = 0
	result.geometry_bytes = 0
	Builder.finish(result)
	assert(result.triangles == source.triangles and result.valid())
	return result


func _save(resource: Resource, path: String) -> void:
	if ResourceSaver.save(resource, OUT.path_join(path.get_file()), ResourceSaver.FLAG_COMPRESS) != OK:
		_fail += 1
