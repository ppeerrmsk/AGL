extends RefCounted
## R47只读导出：原生地表的同高、同法线、同色三角，保留float32和资源摘要。
const OUT := "res://bench/results/tokyo_r47_ground_input"
const Indexed := preload("res://scripts/experiments/tokyo_indexed_mesh.gd")
var _fail := 0


func run() -> void:
	assert(not DirAccess.dir_exists_absolute(OUT), "ground input must not overwrite earlier evidence")
	DirAccess.make_dir_recursive_absolute(OUT)
	var catalog: Resource = load("res://resources/maps/tokyo_volume_preview/r34_cells/index.res")
	assert(catalog.valid())
	var manifest := {"schema": 1, "stride": 60, "index": catalog.resource_path,
		"index_sha256": FileAccess.get_sha256(catalog.resource_path), "cells": []}
	for entry: Dictionary in catalog.cells:
		var source: Resource = ResourceLoader.load(entry.fixed, "", ResourceLoader.CACHE_MODE_IGNORE)
		assert(source.valid() and source.meshes.size() == 1)
		var data := records(source.meshes[0])
		var name_value := "cell_%02d.bin" % entry.id
		var file := FileAccess.open(OUT.path_join(name_value), FileAccess.WRITE)
		assert(file != null)
		file.store_buffer(data)
		file.close()
		manifest.cells.append({"id": entry.id, "path": entry.fixed, "sha256": FileAccess.get_sha256(entry.fixed),
			"file": name_value, "buffer_sha256": FileAccess.get_sha256(OUT.path_join(name_value)),
			"triangles": Indexed.triangles(source.meshes[0]), "eligible": data.size() / 60,
			"bytes": source.geometry_bytes})
	var file := FileAccess.open(OUT.path_join("manifest.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(manifest, "\t"))
	file.close()
	print("[Tokyo ground export] cells=", manifest.cells.size(), " fail=", _fail)


static func records(mesh: ArrayMesh) -> PackedByteArray:
	var result := PackedByteArray()
	if mesh.get_surface_count() == 0:
		return result
	assert(mesh.get_surface_count() == 1)
	var arrays := mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	var indices := PackedInt32Array()
	if arrays[Mesh.ARRAY_INDEX] != null:
		indices = arrays[Mesh.ARRAY_INDEX]
	var count := indices.size() if not indices.is_empty() else vertices.size()
	for offset in range(0, count, 3):
		var ids := PackedInt32Array()
		for n in 3:
			ids.append(indices[offset + n] if not indices.is_empty() else offset + n)
		var p: Vector3 = vertices[ids[0]]
		var normal: Vector3 = normals[ids[0]]
		var color: Color = colors[ids[0]]
		var eligible := p.is_finite() and normal.is_finite() and normal.y > 0.99
		for n in 3:
			eligible = eligible and vertices[ids[n]].is_finite() and vertices[ids[n]].y == p.y \
				and normals[ids[n]] == normal and colors[ids[n]] == color
		if not eligible:
			continue
		var record := PackedByteArray()
		record.resize(60)
		record.encode_u32(0, offset / 3)
		var attributes := [p.y, normal.x, normal.y, normal.z, color.r, color.g, color.b, color.a]
		for n in attributes.size():
			record.encode_float(4 + n * 4, attributes[n])
		for n in 3:
			record.encode_float(36 + n * 8, vertices[ids[n]].x)
			record.encode_float(40 + n * 8, vertices[ids[n]].z)
		result.append_array(record)
	return result
