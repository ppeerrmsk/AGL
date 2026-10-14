extends "res://scripts/tests/build_tokyo_regional_catalog.gd"
## R237仅重分父11；覆盖token需重新证明，不冒用旧verified覆盖。
const SOURCE_SHA := "3e81e5f839591ac89d4d662163450b36902763f41b9c8539427d6bcdddb075ef"
const LAYOUT_SHA := "be1bee0225893dcfb16e9a1dc5174afb43fc1cb0b733e4bd9914879de4818b91"
const Audit := preload("res://scripts/tests/build_tokyo_northwest_catalog.gd")


func build(source: String, output: String) -> int:
	var near_only := OS.get_environment("AGL_TOKYO_NEAR_LAYOUT")=="1"
	var source_sha := "fbb2da6b32b5e3f75c6ad9c91dadcc07725a9805f1b0effb57ec343c590f81c9" if near_only else SOURCE_SHA
	var layout_sha := "31feb7af2af976081df979faf84c091e16446b86d25abb28164901da77fb99ab" if near_only else LAYOUT_SHA
	var layout_path := source.get_base_dir().get_base_dir().path_join("r236-rebalanced-layout.json")
	if near_only:
		layout_path=source.get_base_dir().get_base_dir().path_join("r263-near-layout.json")
	if OS.get_environment("AGL_TOKYO_NINE_REGION_LAYOUT")=="1":
		if not near_only:
			return 1
		source_sha="fc2c255c53372e5f08643a70febfabeb277a8203d4ffe9f394c7bc86a709cb30"
		layout_sha="e44c48e7ed3bef3f20174181658b9a55841ac668ff6aa6ce4b0b82d80e3e0ac6"
		layout_path=source.get_base_dir().get_base_dir().path_join("r276-near-layout.json")
	if OS.get_environment("AGL_TOKYO_SOUTH_LAYOUT")=="1":
		if not near_only or OS.get_environment("AGL_TOKYO_NINE_REGION_LAYOUT")!="1":
			return 1
		source_sha="5ca41d3e671d5189288a49fdf71561d4c06b943636f465ee553c4f37859c5512"
		layout_sha="d9a9d4781e8359390d6a5bbd5495dfa243c1048c1765fa553f9afeb00426ca8f"
		layout_path=source.get_base_dir().get_base_dir().path_join("r299-near-layout.json")
	if OS.get_environment("AGL_TOKYO_SOUTHWEST_LAYOUT")=="1":
		if not near_only or OS.get_environment("AGL_TOKYO_NINE_REGION_LAYOUT")!="1" or OS.get_environment("AGL_TOKYO_SOUTH_LAYOUT")!="1":
			return 1
		source_sha="9c96d71f29c964b1174bff22b2d0518cadcf662bbce1b0ae33d7fcd34ddcd8d4"
		layout_sha="2c7491c6542d91300670a27bcee410cbe368493a13f07d4df533ca12a2a82f4e"
		layout_path=source.get_base_dir().get_base_dir().path_join("r313-near-layout.json")
	if FileAccess.get_sha256(source)!=source_sha or FileAccess.get_sha256(layout_path)!=layout_sha or not Components.Builder.valid_sample_output(source.get_base_dir(),output):
		return 1
	var original: Resource = ResourceLoader.load(source,"",ResourceLoader.CACHE_MODE_IGNORE)
	if original==null or not original.valid():
		return 1
	var layout: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(layout_path))
	if layout.get("fail",1)!=0 or layout.catalog_sha256!=source_sha or not layout.packed_conserved:
		return 1
	var targets: Array = ["lod4_full","lod4_mid","lod5_full"] if near_only else Array(Catalog.CONFIGURATIONS)
	if near_only and (layout.target_configurations!=targets or layout.shared_layout_all_lods_required):
		return 1
	_components=Manifest.read(source.get_base_dir().path_join("components/manifest.bin"),original,source_sha)
	if _components.is_empty():
		return 1
	var input := FileAccess.open(source.get_base_dir().path_join("components/manifest.bin"),FileAccess.READ)
	_components=input.get_var(false)
	input.close()
	_catalog=original.duplicate(true)
	_out=output
	DirAccess.make_dir_recursive_absolute(output.path_join("components"))
	var auditor := Audit.new()
	var stats := {"checked_pages":0,"component_mappings":0}
	for configuration: String in Catalog.CONFIGURATIONS:
		if configuration not in targets:
			continue
		var entry: Dictionary = original.configurations[configuration][11]
		var previous := _load(entry)
		if previous==null:
			return 1
		var planned := entry.duplicate(true)
		planned.cuts=PackedFloat32Array(layout.cuts)
		for n in 4:
			if planned.children[n].cell_id!=int(layout.children[n].cell_id):
				return 1
			planned.children[n].cuts=PackedFloat32Array(layout.children[n].cuts)
		var context := {"out":output.path_join(configuration),"configuration":configuration,"level":int(configuration.substr(3,1)),"parent_id":11,"collision_sha256":original.collision_sha256,"owners_sha256":original.owners_sha256,"game_sources":previous.game_sources,"audit":false,"source_hash":(previous.source_hash+layout_sha+configuration).sha256_text()}
		DirAccess.make_dir_recursive_absolute(context.out)
		var changed := _replace(planned,previous.meshes,context)
		if changed.is_empty() or changed.triangles!=entry.triangles:
			return 1
		_catalog.configurations[configuration][11]=changed
		# expected为原父全几何；planned仅替换已绑定切线，不伪造旧包几何一致。
		if not auditor.audit_entry(planned,changed,previous.meshes,_components,stats):
			return 1
		print("[Rebalanced catalog] ",configuration," conserved faces=",changed.triangles)
	for configuration: String in Catalog.CONFIGURATIONS:
		for parent in 16:
			if (parent!=11 or configuration not in targets) and _catalog.configurations[configuration][parent]!=original.configurations[configuration][parent]:
				return 1
	var destination := output.path_join("catalog.res")
	if not _catalog.valid() or ResourceSaver.save(_catalog,destination,ResourceSaver.FLAG_COMPRESS)!=OK:
		return 1
	var saved: Resource = ResourceLoader.load(destination,"",ResourceLoader.CACHE_MODE_IGNORE)
	if saved==null or not saved.valid() or saved.configurations!=_catalog.configurations:
		return 1
	var digest := FileAccess.get_sha256(destination)
	_components.catalog_sha256=digest
	var physical: Dictionary = {}
	for row: Dictionary in _components.pages.values():
		for path: String in row.components:
			physical[path]=_components.physical[path]
	_components.physical=physical
	var file := FileAccess.open(output.path_join("components/manifest.bin"),FileAccess.WRITE)
	file.store_var(_components)
	file.close()
	if Manifest.read(output.path_join("components/manifest.bin"),saved,digest).is_empty():
		return 1
	stats.merge({"fail":0,"catalog_sha256":digest,"source_sha256":source_sha,"layout_sha256":layout_sha,"changed_pages":_changes.size(),"unchanged_roots":176-targets.size(),"target_configurations":targets,"coverage_verified":false,"visual_verified":false,"production_enabled":false})
	file=FileAccess.open(output.path_join("report.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(stats))
	file.close()
	print("[Rebalanced catalog] ",stats)
	return 0
