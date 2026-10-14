extends RefCounted
## R67只做隔离原生候选；不修改流送目录、默认地图或游戏碰撞。
const Export := preload("res://scripts/tests/export_tokyo_ground_planes.gd")
const Bake := preload("res://scripts/tests/bake_tokyo_ground_merge.gd")
const Shared := preload("res://scripts/tests/bake_tokyo_shared_roofs.gd")
const Spatial := preload("res://scripts/tests/build_tokyo_spatial_pages.gd")
const Indexed := preload("res://scripts/experiments/tokyo_indexed_mesh.gd")


static func run() -> int:
	var output := OS.get_environment("AGL_TOKYO_LOW_ROOF_OUT")
	var path := OS.get_environment("AGL_TOKYO_CANONICAL_CATALOG")
	if output.is_empty() or DirAccess.dir_exists_absolute(output):
		return 1
	var catalog: Resource = load(path)
	if catalog == null or not catalog.valid():
		return 1
	DirAccess.make_dir_recursive_absolute(output)
	return _export(catalog, path, output) if OS.get_environment("AGL_TOKYO_LOW_ROOF_MODE") == "export" else _bake(catalog, path, output)


static func _export(catalog: Resource, path: String, output: String) -> int:
	var manifest := {"schema": 1, "stride": 60, "index": path, "index_sha256": FileAccess.get_sha256(path), "cells": []}
	for entry: Dictionary in catalog.configurations.lod2_guarded:
		var source: Resource = ResourceLoader.load(entry.path, "", ResourceLoader.CACHE_MODE_IGNORE)
		if source == null or not source.valid() or FileAccess.get_sha256(entry.path) != entry.sha256:
			return 1
		var raw := Export.records(source.meshes[0])
		var name_value := "cell_%02d.bin" % source.parent_id
		var file := FileAccess.open(output.path_join(name_value), FileAccess.WRITE)
		if file == null:
			return 1
		file.store_buffer(raw)
		file.close()
		manifest.cells.append({"id": source.parent_id, "path": entry.path, "sha256": entry.sha256,
			"file": name_value, "buffer_sha256": FileAccess.get_sha256(output.path_join(name_value)),
			"triangles": Indexed.triangles(source.meshes[0]), "eligible": raw.size()/60, "bytes": source.geometry_bytes})
	var file := FileAccess.open(output.path_join("manifest.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(manifest, "\t"))
	file.close()
	print("[R67 low roof export] parents=", manifest.cells.size())
	return 0


static func _bake(catalog: Resource, path: String, output: String) -> int:
	var plans := OS.get_environment("AGL_TOKYO_LOW_ROOF_PLAN")
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(plans.path_join("manifest.json")))
	if manifest.get("source_index_sha256") != FileAccess.get_sha256(path) or manifest.get("max_scale", -1) != 0 or manifest.cells.size() != 16:
		return 1
	var rows: Array = []
	for entry: Dictionary in manifest.cells:
		var plan_path := plans.path_join(entry.file)
		if FileAccess.get_sha256(plan_path) != entry.sha256:
			return 1
		var plan: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(plan_path))
		var id := int(plan.cell_id)
		if id != rows.size() or catalog.configurations.lod2_guarded[id].path != plan.source or FileAccess.get_sha256(plan.source) != plan.source_sha256:
			return 1
		var source: Resource = ResourceLoader.load(plan.source, "", ResourceLoader.CACHE_MODE_IGNORE)
		if source == null or not source.valid() or source.cell_id != -1 or source.parent_id != id:
			return 1
		var original: ArrayMesh = source.meshes[0]
		var mesh := original
		if not plan.removed.is_empty():
			for component: Dictionary in plan.components:
				if not Bake._uniform(original, component.sources):
					return 1
			var removed: Dictionary = {}
			for face: float in plan.removed:
				removed[int(face)] = true
			var arrays := Shared._replace(original.surface_get_arrays(0), removed, plan.triangles)
			if arrays.is_empty():
				return 1
			var rewritten := ArrayMesh.new()
			rewritten.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
			Shared._retain_material(rewritten, original, 0)
			if not Shared._preserve_packed(rewritten, original, 0, plan.triangles):
				return 1
			mesh = Bake.compact(rewritten)
			if mesh == null or not Bake.Join.conserved(rewritten, [mesh]):
				return 1
		if Indexed.triangles(mesh) != int(plan.after):
			return 1
		var page: Resource = source.duplicate(false)
		var meshes: Array[ArrayMesh] = [mesh, source.meshes[1], source.meshes[2]]
		page.meshes = meshes
		var data := Spatial.descriptor(meshes)
		page.geometry_bytes = data.bytes
		page.triangles = source.triangles - int(plan.before) + int(plan.after)
		page.source_hash = (source.source_hash + entry.sha256).sha256_text()
		if not page.valid() or page.geometry_bytes > source.geometry_bytes:
			return 1
		var target := output.path_join("parent_%02d.res" % id)
		if ResourceSaver.save(page, target, ResourceSaver.FLAG_COMPRESS) != OK:
			return 1
		var saved: Resource = ResourceLoader.load(target, "", ResourceLoader.CACHE_MODE_IGNORE)
		if saved == null or not saved.valid() or saved.stream_identity() != page.stream_identity():
			return 1
		for kind in 3:
			if not Shared._same_arrays(saved.meshes[kind], page.meshes[kind]) or saved.meshes[kind].get_aabb() != page.meshes[kind].get_aabb():
				return 1
		for dependency: String in ResourceLoader.get_dependencies(target):
			if not dependency.ends_with(".gd"):
				return 1
		rows.append({"id": id, "source": plan.source, "source_sha256": plan.source_sha256, "path": target,
			"sha256": FileAccess.get_sha256(target), "before": plan.before, "after": plan.after,
			"old_bytes": source.geometry_bytes, "bytes": page.geometry_bytes, "collision_sha256": page.collision_sha256})
		print("[R67 low roof bake] parent=", id, " low_faces=", plan.before, "->", plan.after, " bytes=", source.geometry_bytes, "->", page.geometry_bytes)
	var file := FileAccess.open(output.path_join("manifest.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"rows": rows, "fail": 0, "production_enabled": false, "visual_verified": false}, "\t"))
	file.close()
	return 0
