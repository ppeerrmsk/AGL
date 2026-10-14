extends RefCounted
## 已验证源包的精确非owner差集；不重新生成其他楼、不改变既有规范目录。
const Builder := preload("res://scripts/tests/build_tokyo_cells.gd")
const Factory := preload("res://scripts/experiments/tokyo_volume_preview_factory.gd")
const Geometry := preload("res://scripts/experiments/volume_mesh_factory.gd")
const Gate := preload("res://scripts/experiments/tokyo_regional_ownership.gd")
const Duplicates := preload("res://scripts/experiments/tokyo_duplicate_outline.gd")
const Index := preload("res://scripts/rendering/tokyo_cell_index.gd")
const PackedDifference := preload("res://scripts/experiments/tokyo_packed_mesh_difference.gd")
const Same := preload("res://scripts/tests/build_tokyo_shared_pages.gd")


static func valid_routes(config: Variant, regions: Array, digest: String) -> bool:
	if not config is Dictionary or config.size()!=3 or config.get("schema")!=1 or config.get("registry_sha256")!=digest \
			or digest.length()!=64 or not config.get("routes") is Dictionary or regions.is_empty():
		return false
	var seen: Dictionary = {}
	for region: Variant in regions:
		if not region is String or region.is_empty() or seen.has(region) or not config.routes.get(region) is Dictionary:
			return false
		seen[region]=true
		var route: Dictionary = config.routes[region]
		if route.size()!=4 or not route.get("source") is String or not route.get("index") is String \
				or not route.get("dedup") is bool or not route.get("footprint_lod") is bool:
			return false
		if not route.source.is_absolute_path() or not route.index.is_absolute_path() or not route.index.ends_with("/index.res"):
			return false
	return seen.size()==config.routes.size()


static func read_routes(root: String, registry: Dictionary, digest: String) -> Dictionary:
	var config_path := OS.get_environment("AGL_TOKYO_REGIONAL_ROUTES")
	var config: Variant
	if not config_path.is_empty():
		config=JSON.parse_string(FileAccess.get_file_as_string(config_path))
	else:
		if registry.get("regions",[]) != ["north_coast","west_residential","yokohama"]:
			return {}
		var base := root.get_base_dir()
		config={"schema":1,"registry_sha256":digest,"routes":{
			"yokohama":{"source":base.path_join("r10c-roof-source"),"index":"res://resources/maps/tokyo_volume_preview/r19_cells/index.res","dedup":true,"footprint_lod":false},
			"north_coast":{"source":base.path_join("r22-kawasaki-footprints-c"),"index":"res://resources/maps/tokyo_volume_preview/r22_cells/index.res","dedup":true,"footprint_lod":true},
			"west_residential":{"source":base.path_join("r119-west-source-b"),"index":base.path_join("r120-west-native-a/index.res"),"dedup":false,"footprint_lod":false}}}
	return config.routes if valid_routes(config,registry.get("regions",[]),digest) else {}


static func batch_regions(config: Variant, regions: Array, digest: String) -> Array:
	if not config is Dictionary or config.size()!=3 or config.get("schema")!=1 or digest.length()!=64 \
			or config.get("registry_sha256")!=digest or not config.get("regions") is Array or config.regions.is_empty():
		return []
	var seen: Dictionary = {}
	for region: Variant in config.regions:
		if not region is String or not regions.has(region) or seen.has(region):
			return []
		seen[region]=true
	# 沿全图登记顺序构建，不按批次重新计算owner。
	return regions.filter(func(region: Variant) -> bool: return seen.has(region))


static func read_batch(registry: Dictionary, digest: String) -> Dictionary:
	var path := OS.get_environment("AGL_TOKYO_REGIONAL_BATCH")
	if path.is_empty():
		return {"regions":registry.regions,"partial":false}
	var expected := OS.get_environment("AGL_TOKYO_REGIONAL_BATCH_SHA")
	if expected.length()!=64 or FileAccess.get_sha256(path)!=expected:
		return {}
	var config: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	var selected := batch_regions(config,registry.regions,digest)
	return {} if selected.is_empty() else {"regions":selected,"partial":true,"sha256":expected,"config":config}


static func triangle_packets(mesh: ArrayMesh) -> Array[PackedByteArray]:
	var result: Array[PackedByteArray] = []
	if mesh.get_surface_count()==0:
		return result
	var data: Dictionary = mesh.get("_surfaces")[0]
	var count := int(data.vertex_count)
	var format := int(data.format)
	var ps := RenderingServer.mesh_surface_get_format_vertex_stride(format,count)
	var ns := RenderingServer.mesh_surface_get_format_normal_tangent_stride(format,count)
	var cs := RenderingServer.mesh_surface_get_format_attribute_stride(format,count)
	for first in range(0,count,3):
		var packet: PackedByteArray = data.vertex_data.slice(first*ps,(first+3)*ps)
		packet.append_array(data.vertex_data.slice(count*ps+first*ns,count*ps+(first+3)*ns))
		packet.append_array(data.attribute_data.slice(first*cs,(first+3)*cs))
		result.append(packet)
	return result


static func supported(mesh: ArrayMesh) -> bool:
	if mesh.get_surface_count()==0:
		return true
	if mesh.get_surface_count()!=1 or mesh.get_blend_shape_count()!=0:
		return false
	var data: Dictionary = mesh.get("_surfaces")[0]
	return int(data.get("index_count",0))==0 and int(data.vertex_count)%3==0 and data.primitive==Mesh.PRIMITIVE_TRIANGLES \
		and (int(data.format)&Mesh.ARRAY_FLAG_COMPRESS_ATTRIBUTES)==0 and data.get("skin_data",PackedByteArray()).is_empty() and data.get("lods",[]).is_empty()


static func subtract(original: ArrayMesh, removed: ArrayMesh) -> Dictionary:
	if not supported(original) or not supported(removed):
		# 新块面可带索引；旧非索引路径仍保持原生布局，供既有迁移器消费。
		return PackedDifference.subtract(original,removed)
	if removed.get_surface_count()==0:
		return {"mesh":original,"removed":0}
	if original.get_surface_count()==0:
		return {}
	var source: Dictionary = original.get("_surfaces")[0]
	var other: Dictionary = removed.get("_surfaces")[0]
	if source.format!=other.format:
		return {}
	var pending: Dictionary = {}
	for packet: PackedByteArray in triangle_packets(removed):
		var key := packet.hex_encode()
		pending[key]=int(pending.get(key,0))+1
	var kept: Array[int] = []
	var packets := triangle_packets(original)
	for i in packets.size():
		var key := packets[i].hex_encode()
		if int(pending.get(key,0))>0:
			pending[key]-=1
		else:
			kept.append(i)
	for count: int in pending.values():
		if count!=0:
			return {}
	var result := ArrayMesh.new()
	if not kept.is_empty():
		var count := int(source.vertex_count)
		var format := int(source.format)
		var ps := RenderingServer.mesh_surface_get_format_vertex_stride(format,count)
		var ns := RenderingServer.mesh_surface_get_format_normal_tangent_stride(format,count)
		var cs := RenderingServer.mesh_surface_get_format_attribute_stride(format,count)
		var positions := PackedByteArray()
		var normals := PackedByteArray()
		var colors := PackedByteArray()
		for face in kept:
			var first := face*3
			positions.append_array(source.vertex_data.slice(first*ps,(first+3)*ps))
			normals.append_array(source.vertex_data.slice(count*ps+first*ns,count*ps+(first+3)*ns))
			colors.append_array(source.attribute_data.slice(first*cs,(first+3)*cs))
		positions.append_array(normals)
		var changed := source.duplicate()
		changed.vertex_count=kept.size()*3
		changed.vertex_data=positions
		changed.attribute_data=colors
		result.set("_surfaces",[changed])
	return {"mesh":result,"removed":packets.size()-kept.size()}


func run() -> int:
	var root := OS.get_environment("AGL_TOKYO_REGIONAL_NATIVE_SOURCE")
	var output := OS.get_environment("AGL_TOKYO_REGIONAL_NATIVE_OUT")
	if not Builder.valid_sample_output(root,output):
		return 1
	var registry_path := root.path_join("ownership.json")
	var registry: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(registry_path))
	var digest := FileAccess.get_sha256(registry_path)
	var routes := read_routes(root,registry,digest)
	var batch := read_batch(registry,digest)
	if routes.is_empty() or batch.is_empty():
		return 1
	var combined := {"regions":[],"registry_sha256":digest,"owner_ids":{},"fail":0,"canonical_ready":false,"source_routes":routes}
	if batch.partial:
		combined["batch"]=batch
	DirAccess.make_dir_recursive_absolute(output)
	for region: String in batch.regions:
		var route: Dictionary = routes[region]
		var source_dir: String = route.source
		var original: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(source_dir.path_join("city.json")))
		var prepared: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(root.path_join(region).path_join("city.json")))
		for name_value: String in ["city.json","ground.json"]:
			if FileAccess.get_sha256(source_dir.path_join(name_value))!=registry.inputs[region][name_value]:
				return 1
		if FileAccess.get_sha256(root.path_join(region).path_join("ground.json"))!=registry.inputs[region]["ground.json"]:
			return 1
		var gate := Gate.validate(prepared,original,registry,region,digest)
		var previous: Resource = ResourceLoader.load(route.index,"",ResourceLoader.CACHE_MODE_IGNORE)
		if gate.is_empty() or previous==null or not previous.valid() or previous.source_hash!=registry.inputs[region]["city.json"]+":"+registry.inputs[region]["ground.json"]:
			push_error("[Regional native] baseline identity mismatch "+region)
			return 1
		var target: Resource = previous.duplicate(true)
		target.regional_id=region
		target.regional_registry_hash=digest
		target.regional_nonowner_ids=gate.nonowner_ids
		target.source_hash=FileAccess.get_sha256(root.path_join(region).path_join("city.json"))+":"+registry.inputs[region]["ground.json"]
		var records: Dictionary = {}
		for raw: Dictionary in prepared.buildings:
			records[raw.id]=raw
		var suppressed: Dictionary = Duplicates.suppressed(original.buildings) if route.dedup else {}
		var directory := output.path_join(region)
		DirAccess.make_dir_recursive_absolute(directory)
		var rows: Array = []
		for entry: Dictionary in target.cells:
			for slot in 7:
				var descriptor: Dictionary = entry.mid if slot==6 else entry.levels[slot]
				var path: String = descriptor.path
				var old: Resource = ResourceLoader.load(path,"",ResourceLoader.CACHE_MODE_IGNORE)
				var low := Geometry.new()
				var known := Geometry.new()
				var backup := Geometry.new()
				var counts: PackedInt32Array = old.detail_counts.duplicate()
				for identity: String in old.source_ids:
					var raw: Dictionary = records[identity]
					if slot==0 and String(raw.regional_draw_owner)==region:
						if combined.owner_ids.has(identity):
							return 1
						combined.owner_ids[identity]=region
					if identity not in gate.nonowner_ids or raw.get("defer_render",false) or not raw.get("render_outline",true) or suppressed.has(identity):
						continue
					# dedup旧路线可能另走Dome构建；全图普通路线与原生源使用同一个Factory，最终仍逐三角精确扣除。
					if route.dedup and raw.get("source_tags",{}).get("roof:shape","flat")!="flat":
						push_error("[Regional native] custom dome replay requires dedicated proof "+identity)
						return 1
					var scale_value: float = 1.0 if slot==6 and raw.height_source=="fallback" else Index.LEVELS.SCALES[4 if slot==6 else slot]
					var detail := Builder.detail_level(raw,scale_value,true)
					counts[detail]-=1
					counts[3]+=1
					if raw.height_source=="fallback":
						Factory._add_ring_building(backup,raw,float(raw.height_m)*0.5,detail)
					var record := raw
					if route.footprint_lod and slot<4 and detail==2 and raw.get("footprint_lod",{}).has(str(slot)):
						record=raw.duplicate()
						record.rings=raw.footprint_lod[str(slot)].rings
					Factory._add_ring_building(low if raw.height_source=="fallback" else known,record,float(raw.height_m)*0.5,detail)
				var removed: Array[ArrayMesh] = [low.mesh(),known.mesh()]
				var cell: Resource = old.duplicate(false)
				var meshes: Array[ArrayMesh] = []
				for kind in 2:
					var changed := subtract(old.meshes[kind],removed[kind])
					if changed.is_empty():
						push_error("[Regional native] triangle subtraction mismatch %s cell=%d slot=%d kind=%d" % [region,entry.id,slot,kind])
						return 1
					meshes.append(changed.mesh)
				cell.meshes=meshes
				cell.detail_counts=counts
				if old.precision_original!=null:
					var changed := subtract(old.precision_original,backup.mesh())
					if changed.is_empty():
						return 1
					cell.precision_original=changed.mesh
					cell.precision_triangles=Factory._triangles(changed.mesh)
					if cell.precision_triangles==0:
						cell.precision_original=null
						cell.precision_max_scale=0
				cell.geometry_bytes=0
				cell.triangles=0
				Builder.finish(cell)
				var destination := directory.path_join("cell_%02d_slot_%d.res" % [entry.id,slot])
				if not cell.valid() or ResourceSaver.save(cell,destination,ResourceSaver.FLAG_COMPRESS)!=OK:
					return 1
				var saved: Resource = ResourceLoader.load(destination,"",ResourceLoader.CACHE_MODE_IGNORE)
				if saved==null or not saved.valid() or saved.source_ids!=old.source_ids or saved.height_hash!=old.height_hash or saved.detail_counts!=counts:
					return 1
				for kind in 2:
					if not conserved(old.meshes[kind],saved.meshes[kind],removed[kind]):
						return 1
				if old.precision_original!=null and not conserved(old.precision_original,saved.precision_original if saved.precision_original!=null else ArrayMesh.new(),backup.mesh()):
					return 1
				descriptor.path=destination
				descriptor.bytes=saved.geometry_bytes
				descriptor.triangles=saved.triangles
				descriptor.counts=Array(saved.detail_counts)
				rows.append({"cell":entry.id,"slot":slot,"source":path,"source_sha256":FileAccess.get_sha256(path),"path":destination,"sha256":FileAccess.get_sha256(destination),"removed_faces":old.triangles-saved.triangles})
		if target.valid() or not target.valid(digest) or ResourceSaver.save(target,directory.path_join("index.res"),ResourceSaver.FLAG_COMPRESS)!=OK:
			return 1
		combined.regions.append({"region":region,"nonowners":Array(gate.nonowner_ids),"source_records":previous.source_count,"rows":rows,"index":directory.path_join("index.res")})
		print("[Regional native] ",region," archives=",rows.size()," nonowners=",gate.nonowner_ids.size())
	var expected_count := 0
	for identity: String in registry.assignments:
		if not batch.regions.has(registry.assignments[identity].owner):
			continue
		expected_count+=1
		if combined.owner_ids.get(identity,"")!=registry.assignments[identity].owner:
			return 1
	if combined.owner_ids.size()!=expected_count:
		return 1
	var manifest_name := "batch_manifest.json" if batch.partial else "manifest.json"
	if FileAccess.file_exists(output.path_join(manifest_name)):
		return 1
	var file := FileAccess.open(output.path_join(manifest_name),FileAccess.WRITE)
	file.store_string(JSON.stringify(combined))
	file.close()
	print("[Regional native] checked owners=",combined.owner_ids.size()," partial=",batch.partial," fail=0")
	return 0


static func conserved(original: ArrayMesh, current: ArrayMesh, removed: ArrayMesh) -> bool:
	# 无移除且保存前后packed完全相同，已足以证明守恒，不重复展开整层逐角哈希。
	if removed.get_surface_count()==0 and Same.same_mesh(original,current):
		return true
	if not supported(original) or not supported(current) or not supported(removed):
		return PackedDifference.conserved(original,current,removed)
	# 用解码后的逐角数组独立核对，不用裁取算法的原始字节key。
	var expected: Dictionary = {}
	var actual: Dictionary = {}
	for pair: Array in [[original,expected],[current,actual],[removed,actual]]:
		var mesh: ArrayMesh = pair[0]
		if mesh.get_surface_count()==0:
			continue
		var arrays := mesh.surface_get_arrays(0)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		for offset in range(0,vertices.size(),3):
			var keys: Array = []
			for channel: int in [Mesh.ARRAY_VERTEX,Mesh.ARRAY_NORMAL,Mesh.ARRAY_COLOR]:
				keys.append(arrays[channel].slice(offset,offset+3))
			var key := var_to_bytes(keys).hex_encode()
			pair[1][key]=int(pair[1].get(key,0))+1
	return expected==actual
