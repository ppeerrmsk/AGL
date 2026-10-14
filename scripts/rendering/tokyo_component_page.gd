extends RefCounted
## 运行时与离线审计共用的纯组件装配；不读磁盘、不注册tick、不复制网格数组。
const Page := preload("res://scripts/rendering/tokyo_canonical_spatial_page.gd")
const Component := preload("res://scripts/rendering/tokyo_mesh_component.gd")
const Manifest := preload("res://scripts/rendering/tokyo_component_manifest.gd")


static func assemble(row: Dictionary, loaded: Dictionary) -> Resource:
	if not row.get("components") is Dictionary or not row.get("canonical_identity") is Dictionary:return null
	var identity: Dictionary=row.canonical_identity
	if identity.get("format")=="tokyo_ground_view":
		return preload("res://scripts/rendering/tokyo_ground_page.gd").assemble(row,loaded)
	if identity.get("format")=="tokyo_grid_view":
		return preload("res://scripts/rendering/tokyo_grid_page.gd").assemble(row,loaded)
	if identity.get("format")=="tokyo_partition_view":
		return preload("res://scripts/rendering/tokyo_partition_page.gd").assemble(row,loaded)
	if identity.size()!=11:return null
	for key: String in ["format","configuration","source","collision","owners","game_sources"]:
		if not identity.get(key) is String:return null
	for key: String in ["schema","level","parent","cell","ancestor"]:
		if not identity.get(key) is int:return null
	var expected: Dictionary={"canonical_identity":row.get("canonical_identity",{}),"bytes":row.get("bytes",-1)}
	if not Manifest.valid_row(row,expected,row.get("components",{})):return null
	for key: String in row.components:
		var value: Variant=loaded.get(key)
		if typeof(value)!=TYPE_OBJECT or not is_instance_valid(value) or not value is Component:return null
		var component:=value as Component
		if not component.valid() or component.stream_identity()!=row.components[key].canonical_identity or component.geometry_bytes!=row.components[key].bytes:return null
	var page:=Page.new()
	page.schema_version=identity.schema
	page.configuration=identity.configuration
	page.level=identity.level
	page.parent_id=identity.parent
	page.cell_id=identity.cell
	page.ancestor_id=identity.ancestor
	page.source_hash=identity.source
	page.collision_sha256=identity.collision
	page.owners_sha256=identity.owners
	page.game_sources=row.game_sources
	page.geometry_bytes=row.bytes
	page.triangles=row.triangles
	for slot: Array in row.mapping:
		page.meshes.append(loaded[slot[0]].meshes[slot[1]])
	if row.has("low_wall_slot"):
		var slot: Variant=row.low_wall_slot
		if not slot is Array or slot.size()!=2 or not slot[0] is String or not slot[1] is int \
				or not row.components.has(slot[0]) or slot[1]<0 or slot[1]>=loaded[slot[0]].meshes.size() \
				or not row.get("low_full_bounds") is AABB or not row.get("low_full_faces") is int:return null
		page.low_wall_mesh=loaded[slot[0]].meshes[slot[1]]
		page.low_full_bounds=row.low_full_bounds
		page.low_full_faces=row.low_full_faces
	return page if page.valid() and page.stream_identity()==identity else null
