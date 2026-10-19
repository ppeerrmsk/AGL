extends RefCounted
## 全图规范目录格式；只扩空间层级，不扩大活动块或几何预算。
const PAGES := 4432
const GRID_SHA := "9fddfbc1ef61728db3215b75bc0b4b01531ba50295de3f013a511208b0d2f741"
const REGIONAL_SHA := "60aa2c9902c771e51c7a282f44c51fa8e17b6a3a4a4c45b80cc6a7f50b88b851"
const LAYOUT_SHA := "37ce3793f6d3de3a1ac274f1ce7271b4a50151899087883b1c362ae4b68720a5"
const HIERARCHY_SHA := "d1e6ee51473588c6f6692336aad9c46f6489e526593f50fd23a279621658dd6b"
const GAME_SHA := "fa6b8b523f1212c3e2d53b46422611b7e2c65619524b11bde7ffb386393f4ec8"
const COLLISION_SHA := "4dba1b50bd6b8b43976286303c29578d4e246ed9a9730adcbf714880330be11c"
const BOUNDS := Rect2(-16300,-15700,32000,32000)
const Boundary := preload("res://scripts/rendering/tokyo_boundary_extent.gd")


static func digest(value: Variant) -> bool:
	if not value is String or value.length()!=64:
		return false
	for code: int in value.to_ascii_buffer():
		if not (code>=48 and code<=57) and not (code>=97 and code<=102):
			return false
	return true


static func metadata_valid(value: Dictionary, collision: String, owners: String) -> bool:
	# owners始终是游戏楼屋顶归属，不得借用OSM跨片登记充当该证明。
	var legacy: bool = value.get("layout_sha256")==LAYOUT_SHA and value.get("hierarchy_sha256")==HIERARCHY_SHA \
		and value.get("regional_registry_sha256")==REGIONAL_SHA and value.get("source_count")==2859809 and value.get("bounds")==BOUNDS
	return value.size()==11 and value.get("grid_sha256")==GRID_SHA and (legacy or Boundary.full_grid(value)) \
		and digest(owners) and owners!=value.get("regional_registry_sha256") and value.get("game_owners_sha256")==owners \
		and collision==COLLISION_SHA and digest(value.get("input_manifest_sha256")) \
		and value.get("tile_count")==256 \
		and value.get("game_source_count")==189 and value.get("game_source_sha256")==GAME_SHA


static func coordinates_valid(parent: int, cell: int, ancestor: int) -> bool:
	if parent<0 or parent>=16:
		return false
	if cell==-1:
		return ancestor==-1
	if cell>=0 and cell<64:
		return ancestor==-1 and cell/4==parent
	if cell<320 and cell>=64:
		return ancestor>=0 and ancestor<64 and ancestor/4==parent and (cell-64)/4==ancestor
	return cell>=320 and cell<4416 and ancestor>=64 and ancestor<320 and (ancestor-64)/16==parent and (cell-320)/16==ancestor-64


static func children(cell: int, parent: int) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	if cell==-1:
		for n in 4: result.append(Vector2i(parent*4+n,-1))
	elif cell<64:
		for n in 4: result.append(Vector2i(64+cell*4+n,cell))
	elif cell<320:
		for n in 16: result.append(Vector2i(320+(cell-64)*16+n,cell))
	return result


static func valid(catalog: Resource) -> bool:
	if catalog.schema_version!=2 or not catalog.regional_extension.is_empty() \
			or not metadata_valid(catalog.full_grid,catalog.collision_sha256,catalog.owners_sha256) \
			or catalog.configurations.size()!=catalog.CONFIGURATIONS.size() or catalog.descriptors.size()!=PAGES*catalog.CONFIGURATIONS.size():
		return false
	var seen: Dictionary = {}
	for configuration: String in catalog.CONFIGURATIONS:
		var roots: Variant = catalog.configurations.get(configuration)
		if not roots is Array or roots.size()!=16:
			return false
		for parent in 16:
			if not entry_valid(roots[parent],configuration,parent,-1,-1,catalog,seen):
				return false
	return seen.size()==catalog.descriptors.size()


static func entry_valid(entry: Variant, configuration: String, parent: int, cell: int, ancestor: int, catalog: Resource, seen: Dictionary) -> bool:
	if not entry is Dictionary or not coordinates_valid(parent,cell,ancestor):
		return false
	var path: Variant = entry.get("path")
	if not path is String or path.is_empty() or seen.has(path):
		return false
	var descriptor: Variant = catalog.descriptors.get(path)
	if not descriptor is Dictionary or not descriptor.get("canonical_identity") is Dictionary:
		return false
	var identity: Dictionary = descriptor.canonical_identity
	var level := int(configuration.substr(3,1))
	if identity.size()!=11 or identity.get("format")!="tokyo_canonical_spatial" or identity.get("schema")!=2 \
			or identity.get("configuration")!=configuration or identity.get("level")!=level \
			or identity.get("parent")!=parent or identity.get("cell")!=cell or identity.get("ancestor")!=ancestor \
			or identity.get("collision")!=catalog.collision_sha256 or identity.get("owners")!=catalog.owners_sha256 \
			or not digest(identity.get("source")) or not digest(identity.get("game_sources")):
		return false
	if entry.get("parent_id")!=parent or entry.get("cell_id")!=cell or entry.get("ancestor_id")!=ancestor or entry.get("level")!=level \
			or not entry.get("bytes") is int or entry.bytes<0 or entry.bytes!=descriptor.get("bytes") \
			or not entry.get("boxes") is Array or entry.boxes.size()!=3 \
			or not (entry.get("triangles") is Array or entry.get("triangles") is PackedInt32Array) or entry.triangles.size()!=3:
		return false
	for kind in 3:
		var box: Variant = entry.boxes[kind]
		if not box is AABB or not box.position.is_finite() or not box.size.is_finite() \
				or box.size.x<0 or box.size.y<0 or box.size.z<0 or not entry.triangles[kind] is int or entry.triangles[kind]<0:
			return false
	seen[path]=true
	var expected := children(cell,parent)
	var actual: Variant = entry.get("children",[])
	if not actual is Array or actual.size()!=expected.size():
		return false
	for n in expected.size():
		if not entry_valid(actual[n],configuration,parent,expected[n].x,expected[n].y,catalog,seen):
			return false
	return true
