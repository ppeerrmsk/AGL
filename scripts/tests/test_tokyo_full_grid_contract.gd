extends RefCounted
## 只验证全图目录格式/身份与旧格式隔离；不是地图几何或Visual通过证据。
const Contract := preload("res://scripts/rendering/tokyo_full_grid_contract.gd")
const Catalog := preload("res://scripts/rendering/tokyo_canonical_catalog.gd")
const Page := preload("res://scripts/rendering/tokyo_canonical_spatial_page.gd")
const GAME_OWNERS := "cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"


static func metadata() -> Dictionary:
	return {"grid_sha256":Contract.GRID_SHA,"layout_sha256":Contract.LAYOUT_SHA,"hierarchy_sha256":Contract.HIERARCHY_SHA,
		"regional_registry_sha256":Contract.REGIONAL_SHA,"game_owners_sha256":GAME_OWNERS,"input_manifest_sha256":"a".repeat(64),"tile_count":256,"source_count":2859809,
		"game_source_count":189,"game_source_sha256":Contract.GAME_SHA,"bounds":Contract.BOUNDS}


static func entry(catalog: Resource, configuration: String, parent: int, cell: int, ancestor: int) -> Dictionary:
	var path := "full/%s/%02d/%d" % [configuration,parent,cell]
	var level := int(configuration.substr(3,1))
	var identity := {"format":"tokyo_canonical_spatial","schema":2,"configuration":configuration,"level":level,
		"parent":parent,"cell":cell,"ancestor":ancestor,"source":"b".repeat(64),"collision":Contract.COLLISION_SHA,
		"owners":GAME_OWNERS,"game_sources":var_to_bytes(PackedInt32Array()).hex_encode().sha256_text()}
	catalog.descriptors[path]={"bytes":0,"canonical_identity":identity}
	var row := {"path":path,"parent_id":parent,"cell_id":cell,"ancestor_id":ancestor,"level":level,"bytes":0,
		"boxes":[AABB(),AABB(),AABB()],"triangles":[0,0,0],"children":[]}
	for child: Vector2i in Contract.children(cell,parent):
		row.children.append(entry(catalog,configuration,parent,child.x,child.y))
	return row


static func checks() -> bool:
	if not Contract.Boundary.checks(): return false
	var expanded := metadata()
	expanded.layout_sha256=Contract.Boundary.LAYOUT_SHA
	expanded.hierarchy_sha256=Contract.Boundary.HIERARCHY_SHA
	expanded.regional_registry_sha256=Contract.Boundary.REGISTRY_SHA
	expanded.source_count=3018595
	expanded.bounds=Contract.Boundary.EXPANDED
	if not Contract.metadata_valid(expanded,Contract.COLLISION_SHA,GAME_OWNERS): return false
	for field: String in ["layout_sha256","hierarchy_sha256","regional_registry_sha256"]:
		var changed:=expanded.duplicate(true)
		changed[field]="0".repeat(64)
		if Contract.metadata_valid(changed,Contract.COLLISION_SHA,GAME_OWNERS): return false
	expanded.bounds=Contract.BOUNDS
	if Contract.metadata_valid(expanded,Contract.COLLISION_SHA,GAME_OWNERS): return false
	if not Contract.coordinates_valid(0,-1,-1) or not Contract.coordinates_valid(15,63,-1) \
			or not Contract.coordinates_valid(15,319,63) or not Contract.coordinates_valid(15,4415,319):
		return false
	for bad: Vector3i in [Vector3i(16,-1,-1),Vector3i(0,4,-1),Vector3i(1,64,0),Vector3i(0,320,65),Vector3i(15,4416,319),Vector3i(0,-2,-1)]:
		if Contract.coordinates_valid(bad.x,bad.y,bad.z):
			return false
	var catalog := Catalog.new()
	catalog.schema_version=2
	catalog.collision_sha256=Contract.COLLISION_SHA
	catalog.owners_sha256=GAME_OWNERS
	catalog.full_grid=metadata()
	var confused := metadata()
	confused.game_owners_sha256=Contract.REGIONAL_SHA
	if Contract.metadata_valid(confused,Contract.COLLISION_SHA,Contract.REGIONAL_SHA):
		return false
	if Contract.metadata_valid(metadata(),Contract.COLLISION_SHA,"d".repeat(64)):
		return false
	if catalog.valid() or catalog.pages_per_configuration()!=4432 or catalog.gameplay_source_count()!=189:
		return false
	for configuration: String in Catalog.CONFIGURATIONS:
		var roots: Array = []
		for parent in 16: roots.append(entry(catalog,configuration,parent,-1,-1))
		catalog.configurations[configuration]=roots
	if catalog.descriptors.size()!=48752 or not catalog.valid():
		return false
	var leaf_parent: Dictionary = catalog.configurations.lod0_full[0].children[0].children[0]
	var leaf: Dictionary = leaf_parent.children.pop_back()
	if catalog.valid(): return false
	leaf_parent.children.append(leaf)
	var identity: Dictionary = catalog.descriptors[leaf.path].canonical_identity
	identity.schema=1
	if catalog.valid(): return false
	identity.schema=2
	leaf.bytes=0.5
	if catalog.valid(): return false
	leaf.bytes=0
	leaf.triangles="invalid"
	if catalog.valid(): return false
	leaf.triangles=PackedInt32Array([0,0,0])
	if Contract.digest("-"+"a".repeat(63)) or Contract.digest("G".repeat(64)): return false
	catalog.full_grid.layout_sha256="0".repeat(64)
	if catalog.valid(): return false
	catalog.full_grid=metadata()
	catalog.regional_extension={"region":"west_residential"}
	if catalog.valid(): return false
	catalog.regional_extension={}
	catalog.schema_version=1
	if catalog.valid(): return false
	catalog.schema_version=2
	var page := Page.new()
	page.schema_version=2
	page.parent_id=15
	page.cell_id=4415
	page.ancestor_id=319
	page.configuration="lod5_full"
	page.level=5
	page.source_hash="b".repeat(64)
	page.collision_sha256=Contract.COLLISION_SHA
	page.owners_sha256=GAME_OWNERS
	page.meshes.assign([ArrayMesh.new(),ArrayMesh.new(),ArrayMesh.new()])
	if not page.valid() or page.stream_identity().schema!=2: return false
	page.schema_version=1
	if page.valid(): return false
	var original := preload("res://scripts/rendering/tokyo_cell_index.gd").new()
	original.bounds=Rect2(0,0,10,10)
	original.source_hash="source"
	var presentation: Resource = catalog.presentation_archive(original)
	if presentation==null or presentation.bounds!=Contract.BOUNDS or presentation.coverage_rects!=[Contract.BOUNDS] or original.bounds!=Rect2(0,0,10,10):
		return false
	return true
