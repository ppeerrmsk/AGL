extends RefCounted
const Assembly := preload("res://scripts/rendering/tokyo_component_page.gd")
const FullCoverage := preload("res://scripts/tests/build_tokyo_full_source_coverage.gd")
const GridFixture := preload("res://scripts/tests/test_tokyo_full_grid_contract.gd")


static func checks() -> bool:
	if not export_filter_checks(): return false
	if not partition_checks(): return false
	if preload("res://scripts/tests/build_tokyo_full_grid_catalog.gd").run("","","")!=1 or FullCoverage.new().run()!=1:return false
	if Assembly.assemble({"components":9},{})!=null:return false
	var loaded: Dictionary={}
	var row: Dictionary={"components":{},"mapping":[],"game_sources":PackedInt32Array(),"triangles":0,"bytes":0}
	var page:=Assembly.Page.new()
	page.schema_version=2
	page.configuration="lod5_full"
	page.level=5
	page.parent_id=0
	page.source_hash="a".repeat(64)
	page.owners_sha256="b".repeat(64)
	page.collision_sha256="c".repeat(64)
	for kind in 3:
		var component:=Assembly.Component.new()
		component.source_hash=str(kind).repeat(64)
		component.meshes.append(ArrayMesh.new())
		component.mesh_bytes.append(0)
		var key: String="component_"+str(kind)
		loaded[key]=component
		row.components[key]={"path":key,"bytes":0,"canonical_identity":component.stream_identity()}
		row.mapping.append([key,0])
		page.meshes.append(component.meshes[0])
	row.canonical_identity=page.stream_identity()
	var malformed:=row.duplicate(true)
	malformed.canonical_identity.schema="invalid"
	if Assembly.assemble(malformed,loaded)!=null:return false
	var assembled:=Assembly.assemble(row,loaded)
	if assembled==null or assembled.stream_identity()!=page.stream_identity():return false
	for kind in 3:
		if assembled.meshes[kind]!=loaded[row.mapping[kind][0]].meshes[0]:return false
	var missing:=loaded.duplicate()
	missing.erase("component_1")
	if Assembly.assemble(row,missing)!=null:return false
	missing=loaded.duplicate()
	var invalid:=Node.new()
	missing.component_1=invalid
	invalid.free()
	if Assembly.assemble(row,missing)!=null:return false
	var drift:=row.duplicate(true)
	drift.components.component_0.canonical_identity.source="f".repeat(64)
	if Assembly.assemble(drift,loaded)!=null:return false
	drift=row.duplicate(true)
	drift.mapping[0][1]=1
	if Assembly.assemble(drift,loaded)!=null:return false
	drift=row.duplicate(true)
	drift.low_wall_slot=["component_0",9]
	if Assembly.assemble(drift,loaded)!=null:return false
	# 真实16/64/256/4096层级的纯值切面反例；不冒充几何coverage成品。
	var catalog:=GridFixture.Catalog.new()
	var roots: Array=[]
	for parent in 16:roots.append(GridFixture.entry(catalog,"lod5_full",parent,-1,-1))
	catalog.configurations["lod5_full"]=roots
	var first: String=roots[1].children[0].children[0].children[0].path
	var last: String=roots[1].children[3].children[3].children[15].path
	var data: Dictionary={"schema":1,"configuration":"lod5_full","collision_sha256":GridFixture.Contract.COLLISION_SHA,
		"catalog_sha256":"a".repeat(64),"verified":true,"pages":{},"sources":{82:PackedStringArray([first+":1",last+":0"])}}
	for root: Dictionary in roots:_coverage_page(root,catalog,data,first,last)
	var auditor:=FullCoverage.new()
	var result:=auditor._audit_cuts(data,catalog)
	return auditor._fail==0 and result.full_tile_cut==256 and result.mixed_four_depth_cut and result.missing_fragment_cases==2


static func partition_checks() -> bool:
	var override := preload("res://scripts/rendering/tokyo_partition_override.gd")
	if not override.identity_matches({"schema":2,"node":"root"},{"schema":2.0,"node":"root"}): return false
	if override.identity_matches({"schema":2},{"schema":2.5}) or override.identity_matches({"schema":2},{"schema":"2"}): return false
	if not preload("res://scripts/rendering/tokyo_partition_override.gd").read({},null,"",{},{}).is_empty(): return false
	var row := {"canonical_identity":{"format":"tokyo_partition_view","schema":1,"partition":"a".repeat(64),
		"source":"b".repeat(64),"node":"root/0","configuration":"lod5_full"},"components":{},"mapping":[],"bytes":0}
	var loaded: Dictionary={}
	for kind in 3:
		var key := "res://component_%d.res"%kind
		var component := Assembly.Component.new()
		component.source_hash=str(kind).repeat(64)
		component.meshes.append(ArrayMesh.new())
		component.mesh_bytes.append(0)
		loaded[key]=component
		row.components[key]={"path":key,"sha256":"c".repeat(64),"bytes":0,"canonical_identity":component.stream_identity(),"box":AABB(),"faces":0}
		row.mapping.append([key,0])
	var data := {"schema":2,"input_sha256":"d".repeat(64),"pages":{"root":{"bytes":0,"layers":[]}},
		"tree":{"path":"root","bytes":0,"children":[],"triangles":[0,0,0],"boxes":[AABB(),AABB(),AABB()]}}
	for key: String in row.components:
		var layer: Dictionary=row.components[key].duplicate(true)
		layer["faces"]=0
		layer["box"]=AABB()
		data.pages.root.layers.append(layer)
	var binding := {"path":"res://partition.bin","sha256":"a".repeat(64),"configuration":"lod5_full"}
	var catalog := preload("res://scripts/rendering/tokyo_partition_catalog.gd")
	var normalized := catalog.normalize(data,binding)
	if normalized.is_empty() or normalized.coverage_verified or normalized.tree.path!="a".repeat(64)+":root": return false
	var bundle := preload("res://scripts/rendering/tokyo_partition_bundle.gd").new()
	bundle.source_hash="e".repeat(64)
	bundle.meshes=[ArrayMesh.new(),ArrayMesh.new(),ArrayMesh.new()]
	bundle.mesh_bytes=PackedInt32Array([0,0,0])
	var packed := data.duplicate(true)
	packed.schema=3
	packed.pages.root.bundle={"path":"res://bundle.res","sha256":"f".repeat(64),"bytes":0,"canonical_identity":bundle.stream_identity()}
	var packed_catalog := catalog.normalize(packed,binding)
	if packed_catalog.is_empty(): return false
	var packed_row: Dictionary=packed_catalog.pages[packed_catalog.tree.path]
	var packed_loaded := {"res://bundle.res":bundle}
	var packed_view := Assembly.assemble(packed_row,packed_loaded)
	if packed_view==null or packed_row.components.size()!=1: return false
	for kind in 3:
		if packed_view.meshes[kind]!=bundle.meshes[kind]: return false
	var bad_packed := packed.duplicate(true)
	bad_packed.pages.root.layers[1].bytes=1
	if not catalog.normalize(bad_packed,binding).is_empty(): return false
	bad_packed=packed.duplicate(true)
	bad_packed.schema=2
	if not catalog.normalize(bad_packed,binding).is_empty(): return false
	var bad_row := packed_row.duplicate(true)
	bad_row.mapping[2][1]=1
	if Assembly.assemble(bad_row,packed_loaded)!=null: return false
	bad_row=packed_row.duplicate(true)
	bad_row.components["res://bundle.res"].faces[0]=1
	if Assembly.assemble(bad_row,packed_loaded)!=null: return false
	bundle.mesh_bytes[1]=1
	if Assembly.assemble(packed_row,packed_loaded)!=null: return false
	bundle.mesh_bytes[1]=0
	if Assembly.assemble(packed_row,{})!=null: return false
	var damaged := data.duplicate(true)
	damaged.tree.triangles[0]=1
	if not catalog.normalize(damaged,binding).is_empty(): return false
	damaged=data.duplicate(true)
	damaged.pages.extra=damaged.pages.root
	if not catalog.normalize(damaged,binding).is_empty(): return false
	damaged=data.duplicate(true)
	damaged.tree.children=[damaged.tree.duplicate(true)]
	if not catalog.normalize(damaged,binding).is_empty(): return false
	var page := Assembly.assemble(row,loaded)
	if page==null or page.stream_identity()!=row.canonical_identity: return false
	for kind in 3:
		if page.meshes[kind]!=loaded[row.mapping[kind][0]].meshes[0]: return false
	var broken := row.duplicate(true)
	broken.mapping[1]=broken.mapping[0]
	if Assembly.assemble(broken,loaded)!=null: return false
	broken=row.duplicate(true)
	broken.canonical_identity.partition=7
	if Assembly.assemble(broken,loaded)!=null: return false
	broken=row.duplicate(true)
	broken.bytes=1
	if Assembly.assemble(broken,loaded)!=null: return false
	broken=row.duplicate(true)
	broken.components[row.mapping[0][0]].faces=1
	if Assembly.assemble(broken,loaded)!=null: return false
	broken=row.duplicate(true)
	broken.components[row.mapping[0][0]].box=AABB(Vector3.ZERO,Vector3.ONE)
	if Assembly.assemble(broken,loaded)!=null: return false
	var absent := loaded.duplicate()
	absent.erase(row.mapping[0][0])
	if Assembly.assemble(row,absent)!=null: return false
	var dead := Node.new()
	absent[row.mapping[0][0]]=dead
	dead.free()
	return Assembly.assemble(row,absent)==null


## 地图二进制随独立地图包分发（规格 systems/tokyo-map-distribution）：主包导出必须排除它们，
## 由 tokyo_map_pack 按版本目录整包打入 PCK，不再依赖主包 include_filter。
static func export_filter_checks() -> bool:
	var config := ConfigFile.new()
	if config.load("res://export_presets.cfg")!=OK: return false
	var filters := String(config.get_value("preset.0","exclude_filter","")).split(",")
	for path: String in ["resources/maps/tokyo_playable/native/components.bin",
		"resources/maps/tokyo_playable/m20/native/components.bin",
		"resources/maps/tokyo_playable/resident_candidate_01/partition_00.bin"]:
		var found := false
		for filter_value: String in filters:
			var pattern := filter_value.strip_edges()
			found=found or path.matchn(pattern) or ("res://"+path).matchn(pattern)
		if not found: return false
	return true


static func _coverage_page(entry: Dictionary, catalog: Resource, data: Dictionary, first: String, last: String) -> Dictionary:
	var row: Dictionary={"identity":catalog.descriptors[entry.path].canonical_identity,"leaves":PackedStringArray(),"tokens":[PackedStringArray(),PackedStringArray()]}
	if entry.children.is_empty():
		row.leaves.append(entry.path)
		if entry.path==first:row.tokens[1].append(first+":1")
		if entry.path==last:row.tokens[0].append(last+":0")
	else:
		for child: Dictionary in entry.children:
			var sub:=_coverage_page(child,catalog,data,first,last)
			row.leaves.append_array(sub.leaves)
			for kind in 2:row.tokens[kind].append_array(sub.tokens[kind])
	data.pages[entry.path]=row
	return row
