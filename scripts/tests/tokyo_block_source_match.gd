extends RefCounted
## 精确原三角匹配门：候选源不在当前网格中时禁止再次扣除或重复合并。
const Export := preload("res://scripts/tests/tokyo_residential_preview.gd")

static func keys(mesh: ArrayMesh, positions_only: bool = false) -> Dictionary:
	var raw: PackedByteArray=Export.export_payload(mesh).attributes
	var result: Dictionary={}
	var width := 12 if positions_only else 40
	for offset in range(0,raw.size(),120):
		var a := raw.slice(offset,offset+width).hex_encode()
		var b := raw.slice(offset+40,offset+40+width).hex_encode()
		var c := raw.slice(offset+80,offset+80+width).hex_encode()
		var rotations := [a+b+c,b+c+a,c+a+b]
		rotations.sort()
		var key: String=rotations[0]
		result[key]=int(result.get(key,0))+1
	return result

static func run(native: RefCounted, input: Dictionary) -> int:
	var binding: Dictionary=input.block_source_match
	if FileAccess.get_sha256(binding.path)!=binding.sha256: return 1
	var source: ArrayMesh=ResourceLoader.load(binding.path,"",ResourceLoader.CACHE_MODE_IGNORE)
	if source==null: return 1
	var positions_only := bool(input.get("positions_only",false))
	var wanted := keys(source,positions_only)
	var expected := 0
	for amount: int in wanted.values(): expected+=amount
	var box := source.get_aabb().grow(0.001)
	var visited: Dictionary={}
	var matched := 0
	var exported := PackedByteArray()
	for layers: Array in native._grid_fine.values():
		for piece: Dictionary in layers[0]:
			if not box.intersects(piece.box): continue
			for path: String in piece.components:
				if visited.has(path): continue
				visited[path]=true
				var part: Dictionary=piece.components[path]
				if FileAccess.get_sha256(path)!=part.sha256: return 1
				var resource: Resource=ResourceLoader.load(path,"",ResourceLoader.CACHE_MODE_IGNORE)
				if resource==null or not resource.valid() or resource.stream_identity()!=part.canonical_identity or resource.meshes.size()!=1: return 1
				if input.get("export_current",false): exported.append_array(Export.export_payload(resource.meshes[0]).attributes)
				var available := keys(resource.meshes[0],positions_only)
				for key: String in available:
					var take := mini(int(wanted.get(key,0)),int(available[key]))
					matched+=take
					if take>0: wanted[key]-=take
	var report := {"source":binding,"positions_only":positions_only,"expected_faces":expected,"matched_faces":matched,"missing_faces":expected-matched,"components_checked":visited.size(),"exact_replacement_eligible":matched==expected and not positions_only,"runtime_integrated":false}
	if input.get("export_current",false):
		var path: String=input.output+".attributes"
		var payload := FileAccess.open(path,FileAccess.WRITE)
		if payload==null: return 1
		payload.store_buffer(exported);payload.close()
		report["current_attributes"]={"path":path,"sha256":FileAccess.get_sha256(path),"faces":exported.size()/120}
	var file := FileAccess.open(input.output,FileAccess.WRITE)
	if file==null: return 1
	file.store_string(JSON.stringify(report,"\t"));file.close()
	print("[Block source match] ",JSON.stringify(report))
	return 0
