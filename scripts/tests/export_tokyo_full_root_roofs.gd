extends RefCounted
## 每次导出一个完整根的游戏楼共同屋面输入；最终十六根汇总后才可计算固定owner。
const Root := preload("res://scripts/tests/build_tokyo_full_grid_root.gd")
const Guard := preload("res://scripts/tests/tokyo_region_gameplay_guard.gd")
const Extract := preload("res://scripts/tests/export_tokyo_canonical_roofs.gd")
const Component := preload("res://scripts/rendering/tokyo_mesh_component.gd")


static func expected_sources(game: Dictionary) -> Array:
	if game.get("entries",[]).size()!=189 or game.get("source_sha256")!=Root.Contract.GAME_SHA \
			or game.get("collision_sha256")!=Root.Contract.COLLISION_SHA:
		return []
	var expected: Array = []
	for id in game.entries.size():
		var entry: Dictionary = game.entries[id]
		var points: Array = []
		for point: Vector2 in entry.footprint:
			points.append([point.x,point.y])
		expected.append({"source_id":id,"height":float(entry.max_real_h)*CombatUnit.PIXELS_PER_METER,"points":points})
	return expected


static func run(manifest_path: String, expected_sha: String, output: String) -> int:
	if not Root.binding_valid({"path":manifest_path,"sha256":expected_sha}) or not output.is_absolute_path() \
			or output.get_base_dir()!=manifest_path.get_base_dir() or FileAccess.file_exists(output):
		return 1
	var manifest: Variant = JSON.parse_string(FileAccess.get_file_as_string(manifest_path))
	if not manifest is Dictionary or manifest.get("schema")!=1 or manifest.get("fail",1)!=0 \
			or not manifest.get("packed_roundtrip",false) or manifest.get("sources",[]).size()!=256 \
			or not Root.binding_valid(manifest.get("component")):
		return 1
	var name := str(manifest.get("configuration",""))
	var choice := Root.selection(name)
	if choice.is_empty() or choice.kinds!=2 or manifest.get("parent_id",-1)<0 or manifest.parent_id>=16:
		return 1
	var game := Guard.read_source()
	var expected := expected_sources(game)
	if expected.size()!=189:
		return 1
	var source: Resource = ResourceLoader.load(manifest.component.path,"",ResourceLoader.CACHE_MODE_IGNORE)
	if not source is Component or not source.valid() or source.meshes.size()!=2 \
			or source.source_hash!=(str(manifest.input_sha256)+":"+name).sha256_text():
		return 1
	var heights: Dictionary = {}
	for row: Dictionary in expected:
		heights[roundi(float(row.height)*1000)]=true
	var meshes: Array = []
	var native: Array = []
	var parent := int(manifest.parent_id)
	for kind in 2:
		var mesh: ArrayMesh = source.meshes[kind]
		var descriptor := {"id":parent*2+kind,"parent_id":parent,"batch":"parent_%02d" % parent,
			"path":manifest.component.path,"kind":kind,"mesh_path":mesh.resource_path,"page":false,
			"precision_guarded":false,"source_sha256":manifest.component.sha256,"surfaces":[]}
		# 根构建器已选好guarded网格；不能再访问MeshComponent不存在的precision_original。
		Extract._extract(mesh,descriptor,heights,native)
		meshes.append(descriptor)
	var config := {"name":name,"level":4 if choice.slot==6 else choice.slot,"guarded":choice.guarded}
	if choice.slot in [4,6]:
		config["variant"]="mid" if choice.slot==6 else "full"
	var result := {"schema":1,"parent_id":parent,"configuration":config,
		"parents":[{"parent_id":parent,"path":manifest.component.path,"bounds":manifest.bounds}],
		"expected":expected,"meshes":meshes,"native":native,"camera_independent":true,
		"collision_sha256":game.collision_sha256,"game_source_sha256":game.source_sha256,
		"root_manifest_sha256":expected_sha,"partial":true,"canonical_ready":false,"installed":false}
	var file := FileAccess.open(output,FileAccess.WRITE)
	if file==null:
		return 1
	var encoded := JSON.stringify(result,"",true,true)
	file.store_string(encoded)
	file.close()
	if FileAccess.get_file_as_string(output)!=encoded:
		return 1
	print("[Full root roofs] parent=",parent," config=",name," meshes=2 native=",native.size()," game_sources=189 partial=true fail=0")
	return 0
