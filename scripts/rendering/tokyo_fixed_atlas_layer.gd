extends RefCounted
## 显式有限固定地表集合；共用原Stream，逐区完整覆盖门，近景立即恢复。
const Ground := preload("res://scripts/experiments/tokyo_tile_ground_candidate.gd")
const CATALOG_SHA := "3f3842acb66ddb133cc1738dbaf775fb09f4ddbb7d2df13f8f7b0677f2aaca92"
const FIXED_FACES := 28542
const CHARGE := 1668112
const FINE_MAX_SCALE := 0.55
const RESIDENTIAL_SHA := "c0311651371c29025b8db0a8618adb57a2faeb39ab59c4751ee743b3d9c346ca"
const RESIDENTIAL_MANIFESTS := {
	11:"2b686ae4a2c35bf7850c7254fe288e38172692c6b22491e6fdd65c2c42777f0a",
	0:"1919e02b6ec6693b8b16c517d5164a6b139a5e1e22c30d60e646b694a5eed2cf",
	1:"bb5d12456a2468337ede75fe44e3aff273a64b93c1787fcb91f907f0136389f0",
	3:"bfb41040fd5abf01db30ce86df78e24c3039b9d895fecbb9eb92cac01f62f747",
	12:"6e0c467472a4cd4ba2cb7bd29637fbc64df8cf875e89f27b4b1d3634e0675b5f",
	13:"6543df59bec80ea570fc73bc75c0a3c003d3cab1b1ed7747dce79a71b2c259cc"}
const REGIONS := {
	0:{"faces":4557,"bounds":[-6300.0,-600.0,-5940.0,-105.0],"width":184,"height":252,"bytes":62272},
	1:{"faces":6954,"bounds":[-5500.0,-600.0,-5020.0,-60.0],"width":244,"height":276,"bytes":90896},
	3:{"faces":8561,"bounds":[-6300.0,-1700.0,-5900.0,-985.0],"width":204,"height":364,"bytes":99968},
	11:{"faces":28542,"bounds":[-7300.0,-2700.0,-5660.0,-1700.0],"width":824,"height":504,"bytes":554672},
	12:{"faces":11867,"bounds":[-5660.0,-2700.0,-4700.0,-1700.0],"width":484,"height":504,"bytes":326512},
	13:{"faces":9566,"bounds":[-4700.0,-3700.0,-3740.0,-3100.0],"width":484,"height":304,"bytes":196944}}
var _node: MeshInstance3D
var _texture: ImageTexture
var _stream: WeakRef
var _warm: WeakRef
var _held: Array[Dictionary] = []
var _visible_last := false
var stats: Dictionary = {}
var _state: Dictionary = {}
var _regions: Array[RefCounted] = []
var _parent := 11
var _catalog_sha := CATALOG_SHA
var _fine := false


static func region_contract(parent: Variant, catalog_sha: String = CATALOG_SHA, fine: bool = false) -> Dictionary:
	if catalog_sha!=RESIDENTIAL_SHA and catalog_sha not in preload("res://scripts/rendering/tokyo_canonical_catalog.gd").UNCHANGED_FIXED_LOD12_CATALOGS:
		return {}
	if not typeof(parent) in [TYPE_INT,TYPE_FLOAT] or not is_finite(float(parent)) or parent!=int(parent):
		return {}
	if not REGIONS.has(int(parent)):
		return {}
	var region: Dictionary = REGIONS[int(parent)].duplicate(true)
	if catalog_sha==RESIDENTIAL_SHA and int(parent) in [11,12]:
		region.faces=28145 if int(parent)==11 else 9705
	if fine:
		if catalog_sha!=RESIDENTIAL_SHA or int(parent)!=11:
			return {}
		region.width=1644
		region.height=1004
		region.bytes=2205248
	return region


static func collection_entries(data: Variant, catalog_sha: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not data is Dictionary or data.get("schema")!=1 or data.get("catalog_sha256")!=catalog_sha or catalog_sha not in [RESIDENTIAL_SHA,preload("res://scripts/rendering/tokyo_canonical_catalog.gd").UNCHANGED_FIXED_LOD12_CATALOGS[1]]:
		return result
	var entries: Variant = data.get("regions")
	if not entries is Array or entries.size()!=6:
		return result
	# 已逐片原生对拍的清单身份；其它制作版本不得自动进入此集合。
	var hashes := ["9135df497cd1d699b88f7ae850712ddb321932bc2073cb6bedba5249ccde4c79",
		"24bd9b383cee8a18ac0c1e4115b97f4eef1fb971cd4a5357d5aa7953ce53743b",
		"f57dfced4940cbbf39b1f460bd76b99ff243a2fb0b3dcaccaee0a8ac99845904",
		"661803338bc24b2280064e2f2303bcc6b8e58e1419df5cdd42864087b3a2c089",
		"c6c9a30848aeb1b22c7d9aa624b106b049ade5c4e9ca142f733e6e1d4a2395cd",
		"66313a032c1922ab0c08df7bab4e7215a23a56c15ee1e3e27b200123748523cc"]
	if catalog_sha==RESIDENTIAL_SHA:
		hashes=[]
		for parent: int in [11,0,1,3,12,13]:
			hashes.append(RESIDENTIAL_MANIFESTS[parent])
	for index in entries.size():
		var entry: Variant = entries[index]
		if not entry is Dictionary or region_contract(entry.get("parent")).is_empty() or entry.parent!=[11,0,1,3,12,13][index] or entry.get("manifest_sha256")!=hashes[index]:
			return []
		if not entry.get("directory") is String or not entry.directory.is_absolute_path() or entry.directory.contains(".."):
			return []
		result.append(entry)
	return result


static func shader_code(source: String) -> String:
	if source.count("vec3 base = COLOR.rgb;")!=1 or source.contains("fixed_atlas"):
		return ""
	if source.contains("uniform sampler2D baked_ao"):
		var receiver := "float same_surface = 1.0 - smoothstep(0.04, 0.15, abs(ao_local.y - receiver));"
		if source.count(receiver)!=1:
			return ""
		# quad没有原道路微高度；使用同源高度场的地表范围，不能把屋顶AO投回地面。
		source=source.replace("shader_type spatial;","shader_type spatial;\nuniform vec2 fixed_ground_height_range;").replace(receiver,
			"float same_surface = step(fixed_ground_height_range.x - 0.004, receiver) * step(receiver, fixed_ground_height_range.y + 0.004);")
	return source.replace("shader_type spatial;","shader_type spatial;\nuniform sampler2D fixed_atlas : filter_linear_mipmap, repeat_disable;").replace("vec3 base = COLOR.rgb;","vec4 ground_sample = texture(fixed_atlas, UV);\n vec3 base = clamp(ground_sample.rgb / max(ground_sample.a,0.001),vec3(0.0),vec3(1.0));")


static func plane(rect: Rect2, uv: Rect2) -> ArrayMesh:
	var original := Ground.plane(rect,uv)
	var arrays := original.surface_get_arrays(0)
	arrays[Mesh.ARRAY_INDEX]=PackedInt32Array([0,1,2,0,2,3])
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	return mesh


static func eligible(scale: float, faces: int, compatible: bool, parent: int = 11, catalog_sha: String = CATALOG_SHA, fine: bool = false) -> bool:
	if fine and (catalog_sha!=RESIDENTIAL_SHA or parent!=11):
		return false
	if not compatible or not is_finite(scale) or scale<=0.0 or scale>(FINE_MAX_SCALE if fine else 0.3888) or not REGIONS.has(parent):
		return false
	if catalog_sha!=RESIDENTIAL_SHA and catalog_sha not in preload("res://scripts/rendering/tokyo_canonical_catalog.gd").UNCHANGED_FIXED_LOD12_CATALOGS:
		return false
	var expected: int = REGIONS[parent].faces
	if catalog_sha==RESIDENTIAL_SHA and parent in [11,12]:
		expected=28145 if parent==11 else 9705
	return faces==expected


static func borrowed_overlap(parent: int, tiles: Array[Rect2]) -> bool:
	if not REGIONS.has(parent):
		return true
	var bounds: Array = REGIONS[parent].bounds
	var rect := Rect2(bounds[0],bounds[1],bounds[2]-bounds[0],bounds[3]-bounds[1])
	for tile: Rect2 in tiles:
		if not Ground.valid_bounds(tile) or rect.intersection(tile).has_area():
			return true
	return false


static func fixed_configuration(configuration: Variant, catalog_sha: String) -> bool:
	# R170/R172完整XYZ/NXYZ/RGBA逐字节相等；不外推到LOD4/5或其他目录。
	if not configuration is String:
		return false
	return configuration=="lod2_full" or (catalog_sha==RESIDENTIAL_SHA and configuration in ["lod1_full","lod2_guarded","lod3_full","lod3_guarded"])


static func manifest_row(data: Variant, catalog_sha: String, fine: bool = false) -> Dictionary:
	if not data is Dictionary or (catalog_sha!=RESIDENTIAL_SHA and catalog_sha not in preload("res://scripts/rendering/tokyo_canonical_catalog.gd").UNCHANGED_FIXED_LOD12_CATALOGS) or data.get("catalog_sha256")!=catalog_sha or data.get("encoding")!="bc3_rgba_mips":
		return {}
	var region := region_contract(data.get("parent"),catalog_sha,fine)
	if region.is_empty():
		return {}
	if catalog_sha==RESIDENTIAL_SHA and data.get("original_fixed_faces")!=region.faces:
		return {}
	var rows: Variant = data.get("rows")
	var index := 1 if fine else 0
	var step := 1 if fine else 2
	if not rows is Array or rows.size()!=2 or not rows[index] is Dictionary:
		return {}
	var row: Dictionary = rows[index]
	if row.get("world_step")!=step or row.get("width")!=region.width or row.get("height")!=region.height or row.get("conservative_bytes")!=region.bytes*3+4096 or row.get("max_scale")!=0.3888:
		return {}
	if row.get("rectangular_coverage")!=true or row.get("premultiplied_alpha")!=true or row.get("native_bounds")!=region.bounds:
		return {}
	if not row.get("file") is String or String(row.file).get_file()!=row.file or not row.get("sha256") is String or String(row.sha256).length()!=64:
		return {}
	var bounds: Variant = row.get("bounds")
	var heights: Variant = row.get("height_range")
	if not bounds is Array or bounds.size()!=4 or not heights is Array or heights.size()!=2:
		return {}
	for value: Variant in bounds+heights:
		if not typeof(value) in [TYPE_INT,TYPE_FLOAT] or not is_finite(float(value)):
			return {}
	if heights[0]<-1 or heights[1]>1 or heights[0]>heights[1] or bounds[2]-bounds[0]!=region.width*step or bounds[3]-bounds[1]!=region.height*step or bounds[0]>region.bounds[0] or bounds[1]>region.bounds[1] or bounds[2]<region.bounds[2] or bounds[3]<region.bounds[3]:
		return {}
	return row


func bind(map: Node, directory: String) -> bool:
	if _stream!=null or not _regions.is_empty():
		return false
	var collection_path := directory.path_join("regions.json")
	if not FileAccess.file_exists(collection_path):
		var ok := _bind_region(map,directory,11)
		refresh_stats()
		return ok
	var entries := collection_entries(JSON.parse_string(FileAccess.get_file_as_string(collection_path)),map._canonical_sha)
	if entries.is_empty():
		return false
	# 先验整组身份，尚未领取任何资源；领取中失败仍按同一close整组回滚。
	for entry: Dictionary in entries:
		var manifest_path := String(entry.directory).path_join("manifest.json")
		if not FileAccess.file_exists(manifest_path) or FileAccess.get_sha256(manifest_path)!=entry.manifest_sha256:
			return false
	for index in entries.size():
		var layer: RefCounted = self if index==0 else get_script().new()
		if index>0:
			_regions.append(layer)
		if not layer._bind_region(map,entries[index].directory,int(entries[index].parent)):
			close()
			return false
	refresh_stats()
	return true


func _bind_region(map: Node, directory: String, parent: int) -> bool:
	if map._canonical_sha==RESIDENTIAL_SHA and FileAccess.get_sha256(directory.path_join("manifest.json"))!=RESIDENTIAL_MANIFESTS.get(parent,""):
		return false
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(directory.path_join("manifest.json")))
	_fine=map._canonical_sha==RESIDENTIAL_SHA and parent==11
	var row := manifest_row(data,map._canonical_sha,_fine)
	if row.is_empty() or data.parent!=parent:
		return false
	_parent=parent
	_catalog_sha=map._canonical_sha
	var region := region_contract(parent,_catalog_sha,_fine)
	var path := directory.path_join(row.file)
	var file := FileAccess.open(path,FileAccess.READ)
	if file==null or file.get_length()!=region.bytes or FileAccess.get_sha256(path)!=row.sha256:
		return false
	file.close()
	var code := shader_code(map._materials[4].shader.code)
	if code.is_empty() or not map._stream.reserve_auxiliary(get_instance_id(),int(row.conservative_bytes)):
		return false
	_stream=weakref(map._stream)
	var image := Image.create_from_data(int(region.width),int(region.height),true,Image.FORMAT_DXT5,FileAccess.get_file_as_bytes(path))
	if image==null:
		close()
		return false
	_texture=ImageTexture.create_from_image(image)
	var material: ShaderMaterial = map._materials[4].duplicate()
	var shader := Shader.new()
	shader.code=code
	material.shader=shader
	material.set_shader_parameter("fixed_atlas",_texture)
	material.set_shader_parameter("lod_mix",1.0)
	material.set_shader_parameter("outgoing",false)
	if code.contains("fixed_ground_height_range"):
		material.set_shader_parameter("fixed_ground_height_range",Vector2(row.height_range[0],row.height_range[1]))
	if map._preloaded_ao != null and not map._preloaded_ao.track_material(material):
		close()
		return false
	var native: Array = region.bounds
	var rect := Rect2(native[0],native[1],native[2]-native[0],native[3]-native[1])
	var bounds: Array = row.bounds
	var bake := Rect2(bounds[0],bounds[1],region.width*row.world_step,region.height*row.world_step)
	_node=map._add_mesh(plane(rect,Rect2((rect.position-bake.position)/bake.size,rect.size/bake.size)),material,false)
	_node.position.y=float(row.height_range[0])
	_node.hide()
	_state={"parent":parent,"ready":true,"faces":0,"visible_nodes":0,"pooled_nodes":1,"reserved_bytes":int(row.conservative_bytes),"texture_id":_texture.get_instance_id(),"applied":false,"applications":0}
	_state["texture_step"]=row.world_step
	_state["catalog_sha256"]=_catalog_sha
	var warm := preload("res://scripts/rendering/tokyo_shoreline_warmup.gd").new()
	if not warm.configure(map._stream,material,map._viewport.msaa_3d):
		warm.free()
		close()
		return false
	_state["warm"]=warm.result
	_warm=weakref(warm)
	map.add_child(warm)
	return true


func warm_ready() -> bool:
	for layer: RefCounted in members():
		var state: Dictionary = layer._state.get("warm",{})
		if state.get("reserved_bytes",-1)!=0 or not (state.get("state")=="ready" or (DisplayServer.get_name()=="headless" and state.get("state")=="headless_skipped")):
			return false
	return true


func members() -> Array[RefCounted]:
	var result: Array[RefCounted] = [self]
	result.append_array(_regions)
	return result


func refresh_stats() -> void:
	stats=_state.duplicate(false)
	for key: String in ["faces","visible_nodes","pooled_nodes","reserved_bytes","applications"]:
		stats[key]=0
	stats["regions"]={}
	stats["applied"]=false
	for layer: RefCounted in members():
		stats.regions[str(layer._parent)]=layer._state.duplicate(false)
		for key: String in ["faces","visible_nodes","pooled_nodes","reserved_bytes","applications"]:
			stats[key]+=int(layer._state.get(key,0))
		stats.applied=stats.applied or layer._state.get("applied",false)


func suspend() -> void:
	for layer: RefCounted in members():
		layer._suspend_region()
	refresh_stats()


func _suspend_region() -> void:
	if is_instance_valid(_node):
		_node.hide()
	for saved: Dictionary in _held:
		var node: Variant = saved.node.get_ref()
		if typeof(node)==TYPE_OBJECT and is_instance_valid(node):
			node.visible=saved.visible
	_held.clear()
	_state["faces"]=0
	_state["visible_nodes"]=0
	_state["applied"]=false


func update(map: Node, scale: float, active: bool) -> bool:
	var changed := false
	var layers := members()
	var grouped: Dictionary = {}
	var scanned := 0
	var maximum_scale := 0.3888
	for layer: RefCounted in layers:
		grouped[layer._parent]=[]
		if layer._fine:
			maximum_scale=FINE_MAX_SCALE
	# 仅本次事务分组，不保存跨帧Node；六区共享一次批次扫描。
	if active and is_finite(scale) and scale>0.0 and scale<=maximum_scale:
		for batch: Dictionary in map._batches.values():
			scanned+=1
			var identity: Dictionary = map._descriptors[batch.path].canonical_identity
			var parent := int(identity.get("parent",-1))
			if grouped.has(parent) and batch.nodes[2].visible:
				grouped[parent].append(batch)
	for layer: RefCounted in layers:
		changed=layer._update_region(map,scale,active,grouped[layer._parent]) or changed
	refresh_stats()
	stats["scan_batches"]=scanned
	return changed


func _update_region(map: Node, scale: float, active: bool, batches: Array) -> bool:
	var faces := 0
	var compatible := active and is_instance_valid(_node)
	# 图集失去逐像素微高度；不能代替借用瓦片的仅负高度裁切。
	if compatible and map._tile_ground!=null:
		compatible = not borrowed_overlap(_parent,map._tile_ground._tiles)
	var selected: Array[Dictionary] = []
	if compatible and is_finite(scale) and scale>0 and scale<=(FINE_MAX_SCALE if _fine else 0.3888):
		for batch: Dictionary in batches:
			var identity: Dictionary = map._descriptors[batch.path].canonical_identity
			if int(identity.get("parent",-1))!=_parent or not batch.nodes[2].visible:
				continue
			compatible = compatible and fixed_configuration(identity.get("configuration"),_catalog_sha)
			faces+=int(batch.layer_triangles[2])
			selected.append({"node":weakref(batch.nodes[2]),"visible":true})
	var apply := eligible(scale,faces,compatible,_parent,_catalog_sha,_fine)
	if apply:
		_held=selected
		for saved: Dictionary in _held:
			var node: Variant = saved.node.get_ref()
			if typeof(node)==TYPE_OBJECT and is_instance_valid(node):
				node.hide()
		_node.show()
	_state["faces"]=2 if apply else 0
	_state["visible_nodes"]=int(apply)
	_state["applied"]=apply
	_state["native_faces"]=faces
	var changed := apply!=_visible_last
	_state["applications"]=int(_state.get("applications",0))+int(apply and changed)
	_visible_last=apply
	return changed


func close() -> void:
	suspend()
	for layer: RefCounted in _regions:
		layer.close()
	_regions.clear()
	var warm: Variant = _warm.get_ref() if _warm!=null else null
	if typeof(warm)==TYPE_OBJECT and is_instance_valid(warm):
		warm.free()
	_warm=null
	if is_instance_valid(_node):
		_node.free()
	_node=null
	_texture=null
	var stream: Variant = _stream.get_ref() if _stream!=null else null
	if typeof(stream)==TYPE_OBJECT and is_instance_valid(stream):
		stream.release_auxiliary(get_instance_id())
	_stream=null
	_state["reserved_bytes"]=0
	_state["pooled_nodes"]=0
	_state["ready"]=false
	_visible_last=false
	refresh_stats()
