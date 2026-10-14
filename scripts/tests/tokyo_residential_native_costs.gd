extends RefCounted
## 逐源住宅调用正式工厂，导出七档属性与来源范围；不改运行时包。
const Builder := preload("res://scripts/tests/build_tokyo_cells.gd")
const Factory := preload("res://scripts/experiments/tokyo_volume_preview_factory.gd")
const Geometry := preload("res://scripts/experiments/volume_mesh_factory.gd")
const Export := preload("res://scripts/tests/tokyo_residential_preview.gd")
const Levels := preload("res://scripts/rendering/tokyo_volume_archive.gd")
const Binding := preload("res://scripts/rendering/tokyo_partition_override.gd")


static func run(input: Dictionary) -> int:
	var output: String = input.get("output", "")
	if not output.is_absolute_path() or not "/tmp/" in output.replace("\\", "/") or DirAccess.dir_exists_absolute(output): return 1
	var jobs: Variant = input.get("residential_native_costs")
	if not jobs is Array or jobs.is_empty(): return 1
	if DirAccess.make_dir_recursive_absolute(output) != OK: return 1
	var reports: Array = []
	for job: Dictionary in jobs:
		var source := Binding.json_binding(job.get("source"))
		var plan := Binding.json_binding(job.get("plan"))
		if source.is_empty() or plan.is_empty() or plan.get("source_sha256") != job.source.sha256: return 1
		var height_error: float = plan.get("max_height_error_m", 0.0)
		if height_error not in [0.0, 1.0]: return 1
		var wanted: Dictionary = {}
		for group: Dictionary in plan.groups:
			for identity: String in group.ids:
				if wanted.has(identity): return 1
				wanted[identity] = float(group.height_m)
		var records: Array[Dictionary] = []
		for record: Dictionary in source.buildings:
			if not wanted.has(str(record.id)): continue
			if absf(float(record.height_m) - float(wanted[str(record.id)])) > height_error or record.get("height_source") not in ["height", "levels"] \
				or record.get("defer_render", false) or not record.get("render_outline", true): return 1
			records.append(record)
		if records.size() != wanted.size(): return 1
		for slot in 7:
			var level := slot if slot < 6 else 4
			var bytes := PackedByteArray()
			var ranges: Array = []
			for record: Dictionary in records:
				var detail := Builder.detail_level(record, float(Levels.SCALES[level]), true)
				var builder := Geometry.new()
				Factory._add_ring_building(builder, record, float(record.height_m) * 0.5, detail)
				var payload := Export.export_payload(builder.mesh())
				if payload.is_empty(): return 1
				var attributes: PackedByteArray = payload.attributes
				if attributes.size() % 120 != 0: return 1
				ranges.append({"id":str(record.id), "start":bytes.size()/120, "faces":attributes.size()/120, "detail":detail})
				bytes.append_array(attributes)
			var path := output.path_join("%s_%d.attributes" % [str(plan.tile), slot])
			var file := FileAccess.open(path, FileAccess.WRITE)
			if file == null: return 1
			file.store_buffer(bytes)
			file.close()
			if FileAccess.get_file_as_bytes(path) != bytes: return 1
			reports.append({"tile":plan.tile,"slot":slot,"path":path,"sha256":FileAccess.get_sha256(path),
				"source_sha256":job.source.sha256,"plan_sha256":job.plan.sha256,"ranges":ranges,"faces":bytes.size()/120})
			print("[Residential native] ", plan.tile, " slot=", slot, " faces=", bytes.size()/120)
	var result := FileAccess.open(output.path_join("manifest.json"), FileAccess.WRITE)
	if result == null: return 1
	result.store_string(JSON.stringify({"rows":reports,"installed_membership_verified":false,"runtime_integrated":false}))
	return 0
