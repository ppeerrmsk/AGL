extends RefCounted
const Palette := preload("res://scripts/experiments/tokyo_palette.gd")
const OUT := "res://bench/results/tokyo_r32_cells"
var _fail := 0


func run() -> void:
	var source: Resource = load("res://resources/maps/tokyo_volume_preview/r30_cells/index.res")
	assert(source.valid())
	var target: Resource = source.duplicate(true)
	DirAccess.make_dir_recursive_absolute(OUT)
	var report := {"source_count": source.source_count, "palette": Palette.PAIRS, "cells": [], "fail": 0}
	for entry: Dictionary in target.cells:
		for slot in range(-1, 7):
			var descriptor: Dictionary = {} if slot == -1 else (entry.mid if slot == 6 else entry.levels[slot])
			var path: String = entry.fixed if slot == -1 else descriptor.path
			var original: Resource = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
			assert(original.valid())
			var cell: Resource = original.duplicate(false)
			var meshes: Array[ArrayMesh] = []
			for mesh: ArrayMesh in original.meshes:
				meshes.append(Palette.recolor(mesh))
			cell.meshes = meshes
			if original.precision_original != null:
				cell.precision_original = Palette.recolor(original.precision_original)
			assert(cell.valid())
			var destination := path.replace("r30_cells", "r32_cells")
			if slot == -1:
				entry.fixed = destination
			else:
				descriptor.path = destination
			_save(cell, destination)
		report.cells.append(entry)
		print("[Tokyo palette build] cell=", entry.id, " fail=", _fail)
	_save(target, "index.res")
	report.fail = _fail
	var file := FileAccess.open(OUT.path_join("build_report.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	print("[Tokyo palette build] sources=", source.source_count, " fail=", _fail)


func _save(resource: Resource, path: String) -> void:
	_fail += int(ResourceSaver.save(resource, OUT.path_join(path.get_file()), ResourceSaver.FLAG_COMPRESS) != OK)
