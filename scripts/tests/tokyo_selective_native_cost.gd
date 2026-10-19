extends RefCounted
## 选择性烘焙的原生余量实物；不赋予纹理或运行时覆盖资格。
const Packed := preload("res://scripts/experiments/tokyo_packed_mesh_reindex.gd")

static func run(input: Dictionary) -> int:
	for binding: Dictionary in [input.selective_native_cost,input.source_export]:
		if FileAccess.get_sha256(binding.path)!=binding.sha256: return 1
	var plan: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(input.selective_native_cost.path))
	var report: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(input.source_export.path))
	if plan.source_sha256!=input.source_export.sha256: return 1
	var exports: Array=report.samples[0].triangle_cost.exports
	var edits: Dictionary={}
	for option: Dictionary in plan.selected:
		var entry: Dictionary=exports[int(option.export_index)]
		if option.source_sha256!=entry.sha256: return 1
		var path: String=entry.source.path
		if not edits.has(path): edits[path]={"binding":entry.source,"slots":{}}
		var slots: Dictionary=edits[path].slots
		var slot := int(entry.slot)
		if not slots.has(slot): slots[slot]={}
		for face: float in option.source_face_indices:
			if slots[slot].has(int(face)): return 1
			slots[slot][int(face)]=true
	var directory: String=input.output
	if not directory.is_absolute_path() or DirAccess.dir_exists_absolute(directory): return 1
	if DirAccess.make_dir_recursive_absolute(directory)!=OK: return 1
	var rows: Array=[]
	var old_bytes := 0
	var new_bytes := 0
	for path: String in edits:
		var edit: Dictionary=edits[path]
		if FileAccess.get_sha256(path)!=edit.binding.sha256: print("[selective] source SHA mismatch ",path);return 1
		var original: Resource=load(path)
		if original==null or not original.valid(): print("[selective] invalid source ",path);return 1
		var identity: Dictionary=edit.binding.canonical_identity.duplicate()
		identity.schema=int(identity.schema);identity.slots=int(identity.slots)
		if original.stream_identity()!=identity: print("[selective] identity mismatch ",path);return 1
		var candidate: Resource=original.duplicate(false)
		candidate.meshes=original.meshes.duplicate()
		candidate.mesh_bytes=original.mesh_bytes.duplicate()
		for slot: int in edit.slots:
			var mesh: ArrayMesh=original.meshes[slot]
			var data := Packed._read(mesh)
			var kept := PackedInt32Array()
			var removed: Dictionary=edit.slots[slot]
			for face: int in removed:
				if face<0 or face>=data.indices.size()/3: return 1
			var hash := HashingContext.new();hash.start(HashingContext.HASH_SHA256)
			for face in range(data.indices.size()/3):
				if removed.has(face): continue
				for corner in 3:
					var index: int=data.indices[face*3+corner]
					kept.append(index);hash.update(Packed._corner(data,index))
			var output_mesh := ArrayMesh.new()
			if not kept.is_empty():
				var surface: Dictionary=data.surface.duplicate()
				surface.format=int(surface.format)|Mesh.ARRAY_FORMAT_INDEX
				surface.index_count=kept.size()
				var stride := RenderingServer.mesh_surface_get_format_index_stride(surface.format,data.count)
				var indices := PackedByteArray();indices.resize(kept.size()*stride)
				for n in kept.size():
					if stride==2: indices.encode_u16(n*2,kept[n])
					elif stride==4: indices.encode_u32(n*4,kept[n])
					else: return 1
				surface.index_data=indices
				output_mesh.set("_surfaces",[surface]);output_mesh.custom_aabb=mesh.custom_aabb
				output_mesh=Packed.repack(output_mesh)
			if Packed.corner_digest(output_mesh)!=hash.finish().hex_encode(): print("[selective] retained corner mismatch ",path," slot ",slot);return 1
			candidate.meshes[slot]=output_mesh
			candidate.mesh_bytes[slot]=Packed.decoded_bytes(output_mesh)
		candidate.geometry_bytes=0
		for amount: int in candidate.mesh_bytes: candidate.geometry_bytes+=amount
		candidate.source_hash=var_to_bytes([edit.binding.sha256,edit.slots]).hex_encode().sha256_text()
		var destination := directory.path_join("%04d.res"%rows.size())
		if not candidate.valid() or ResourceSaver.save(candidate,destination,ResourceSaver.FLAG_COMPRESS)!=OK: print("[selective] candidate save rejected ",destination);return 1
		var restored: Resource=ResourceLoader.load(destination,"",ResourceLoader.CACHE_MODE_IGNORE)
		if restored==null or not restored.valid() or restored.geometry_bytes!=candidate.geometry_bytes: print("[selective] restored resource rejected ",destination);return 1
		for slot in candidate.meshes.size():
			if Packed.corner_digest(restored.meshes[slot])!=Packed.corner_digest(candidate.meshes[slot]): return 1
		old_bytes+=int(original.geometry_bytes);new_bytes+=candidate.geometry_bytes
		rows.append({"source":edit.binding,"path":destination,"sha256":FileAccess.get_sha256(destination),"bytes":candidate.geometry_bytes})
	var result := {"changed_old_bytes":old_bytes,"changed_new_bytes":new_bytes,"saved_bytes":old_bytes-new_bytes,
		"rows":rows,"roundtrip_exact":true,"runtime_integrated":false,"texture_coverage_verified":false}
	var file := FileAccess.open(directory.path_join("report.json"),FileAccess.WRITE)
	if file==null: return 1
	file.store_string(JSON.stringify(result,"\t"));file.close()
	return 0
