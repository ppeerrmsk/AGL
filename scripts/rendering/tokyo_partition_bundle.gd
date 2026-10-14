extends Resource
## 同一逻辑页三层一次读取；不合并顶点、不改变显示分区或成本。
@export var source_hash := ""
@export var geometry_bytes := 0
@export var mesh_bytes := PackedInt32Array()
@export var meshes: Array[ArrayMesh]=[]


func valid() -> bool:
	if source_hash.length()!=64 or meshes.size()!=3 or mesh_bytes.size()!=3: return false
	var total := 0
	for n in 3:
		if meshes[n]==null or meshes[n].get_surface_count()>1 or mesh_bytes[n]<0: return false
		total+=mesh_bytes[n]
	return total==geometry_bytes


func stream_identity() -> Dictionary:
	return {"format":"tokyo_partition_bundle","schema":1,"source":source_hash,"slots":3}


static func descriptor(row: Dictionary, entry: Dictionary) -> Dictionary:
	var contract := preload("res://scripts/rendering/tokyo_hlod_manifest.gd")
	var binding: Variant=row.get("bundle")
	if not contract.binding(binding) or not binding.get("bytes") is int or binding.bytes!=entry.bytes: return {}
	var identity: Variant=binding.get("canonical_identity")
	if not identity is Dictionary or identity.size()!=4 or identity.get("format")!="tokyo_partition_bundle" \
		or identity.get("schema")!=1 or identity.get("slots")!=3 or not contract.sha(identity.get("source")): return {}
	var shapes := {"boxes":[],"faces":[],"mesh_bytes":[]}
	var total := 0
	for kind in 3:
		var layer: Variant=row.layers[kind]
		if not layer is Dictionary or not layer.get("bytes") is int or layer.bytes<0 \
			or not layer.get("faces") is int or layer.faces<0 or layer.faces!=entry.triangles[kind] \
			or not entry.boxes[kind] is AABB or layer.get("box")!=entry.boxes[kind]: return {}
		var box: AABB=entry.boxes[kind]
		if not box.position.is_finite() or not box.size.is_finite() or box.size.x<0 or box.size.y<0 or box.size.z<0: return {}
		shapes.boxes.append(box);shapes.faces.append(layer.faces);shapes.mesh_bytes.append(layer.bytes)
		total+=layer.bytes
	if total!=entry.bytes: return {}
	var result: Dictionary=binding.duplicate(true)
	result.merge(shapes,true)
	return result
