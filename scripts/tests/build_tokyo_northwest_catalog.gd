extends "res://scripts/tests/build_tokyo_regional_catalog.gd"
## 原切线/组件流程的五区接合，不替换其他父区或正式默认。
const BASE_SHA := "bccdd77db85e42d9ac258b9ca6497557fcb34b1e5ac3703fb805fd541099b827"
const REGISTRY_SHA := "b2071a17cbb4222ddd7532b495f1ed2425212e9dac237d388aedbe4ce8c068fe"
const NATIVE_SHA := "68c3981291b9e2c04783471f9e4d34a366b55f1b9797b7cb8849388e3bbb71a3"
const BOUNDARY_SHA := "a140ace529731e8e210de0b695f3503e024b64b8ac76c4ca08682f6cf6f5edb9"
const COMBINED_SHA := "e4418975c4c5da7818043376e3b14c33c22994c87c2a0b8b318b709f1a9f3d33"
const EAST_COMBINED_SHA := "a8176d4a777584200a239f5cf13fe7ff2a4b5327aedfd75c8615f4bbe1e46084"
const OUTER_REGISTRY_SHA := "e57da4c3ca3e0cddbfb692ec78e6df2a273caf7b0fede082b6f22c8a8624603d"


static func native_binding(combined: bool, east: bool = false, outer: bool = false, north: bool = false, left: bool = false, right: bool = false, south: bool = false, southwest: bool = false) -> Dictionary:
	# 仅切换已认证输入配对，旧构建/审计的默认身份保持。
	if southwest:
		if not combined or not east or not outer or not north or not left or not right or not south:
			return {}
		return {"directory":"r310-owned-native-a","sha256":"de82a0722298df2f816e7f546353726578c73c9d183015ae017019fe84862a1f","audit_sha256":"ae3f8bc261479ada1dcb61a8dfa98755f1c967a8094efc41360a75ca1c5c2f4a"}
	if south:
		if not combined or not east or not outer or not north or not left or not right:
			return {}
		return {"directory":"r297-owned-native-a","sha256":"48652d4fe45243908d947c2d793273ba4e7e2fd25abeb86a6930c98527e55c31","audit_sha256":"6e0696e5e2cfcd3d2774a3a7e85033f9a68236ed887c28d6324b6340c80a1988"}
	if right:
		if not combined or not east or not outer or not north or not left:
			return {}
		return {"directory":"r274-owned-native-a","sha256":"f4457072407b815990fc2a9cd57fc2762fd080023708bc3f6653b547fbbdd807","audit_sha256":"fa5fe3dd251b11edb488e713a0775225a38561d51de9af1bb8f554cc40554f62"}
	if left:
		if not combined or not east or not outer or not north:
			return {}
		return {"directory":"r260-owned-native-a","sha256":"3fd5c30f2977993ba99f68133815bf40795cfd2f97470fe6669a3f4fe069bda7","audit_sha256":"9b770aa0b004a8b63adf1d436daa14501fbe934d30a6dfac8e41047438298c74"}
	if north:
		if not combined or not east or not outer:
			return {}
		return {"directory":"r247-owned-native-b","sha256":"d7f76a7c97f58fa4f566324f33fde079230a8761e34833758970e106bba168e6","audit_sha256":"2eb42c5671850060e051bbd1bce4c8df52a5a10f6d6be2db54f01bf4428bebb9"}
	if outer:
		if not combined or not east:
			return {}
		return {"directory":"r230-owned-native-a","sha256":"2c939a288876ce091bcfbdf2972652e72111d89bdc22589644c866f1b44f7567","audit_sha256":"5cf817332ea5d853a0246a91357e13ed09d1aa86526c09566b879bdd160e8c0d"}
	if east:
		if not combined:
			return {}
		return {"directory":"r217-owned-native-a","sha256":EAST_COMBINED_SHA,"audit_sha256":"243a1cba844221e7b8a3552795b9fd5c7f0c038eb6569ff378fc2bebca11b407"}
	if combined:
		return {"directory":"r211-owned-native-a","sha256":COMBINED_SHA,"audit_sha256":"0c737ffa26f0f9bf070dbf9641fb3bf6dcdc2b8502dbcd82fdc8c36b8990403f"}
	return {"directory":"r201-owned-native-c","sha256":NATIVE_SHA,"audit_sha256":"d59f9db57886b130e17c6210a19579e64c1e5173f242c294caa547389d9641de"}


func build(root: String, output: String) -> int:
	var southwest := OS.get_environment("AGL_TOKYO_SOUTHWEST_COMBINED")=="1"
	var right := OS.get_environment("AGL_TOKYO_NORTH_RIGHT_COMBINED")=="1"
	var left := OS.get_environment("AGL_TOKYO_NORTH_LEFT_COMBINED")=="1"
	var outer := OS.get_environment("AGL_TOKYO_NORTHWEST_OUTER_COMBINED")=="1"
	var north := OS.get_environment("AGL_TOKYO_NORTH_SEAM_COMBINED")=="1"
	var registry_sha := OUTER_REGISTRY_SHA if outer else REGISTRY_SHA
	if north:
		registry_sha="6ca1fb5664dd0ce41ff58650d2c50bd7391eb2e23913ec0d4425208c74060204"
	if left:
		registry_sha="07d7bf28673e6472a05211a58a95a1325d9dc9b0c2abf613ea49d12f05dfde09"
	var baseline := root.path_join("r193-native-full-a")
	if right:
		registry_sha="45098e3d30e11470986c93200e8d81be56ff68e6616929baffc3d12e7cfb54b9"
	if southwest:
		registry_sha="67f3e204ecda7a49d6d51f00f2b49a0c8ecfc2b9b4c04a24ba559df8b03b1229"
	if root.is_empty() or output.is_empty() or not Components.Builder.valid_sample_output(baseline,output):
		return 1
	var path := baseline.path_join("catalog.res")
	var binding := native_binding(OS.get_environment("AGL_TOKYO_NORTHWEST_COMBINED")=="1",OS.get_environment("AGL_TOKYO_NORTHWEST_EAST_COMBINED")=="1",outer,north,left,right,OS.get_environment("AGL_TOKYO_SOUTH_COMBINED")=="1",southwest)
	if binding.is_empty():
		return 1
	var native_path := root.path_join(binding.directory).path_join("manifest.json")
	var boundary_path := root.path_join("r203-boundary-c/report.json")
	if FileAccess.get_sha256(path)!=BASE_SHA or FileAccess.get_sha256(native_path)!=binding.sha256 or FileAccess.get_sha256(boundary_path)!=BOUNDARY_SHA \
		or FileAccess.get_sha256(root.path_join("r203-boundary-c/saved_audit.json"))!="77ad7213a33508d281d61f6a573d4973f9bcaa52fb09dac7346d789bd2ff3228" \
		or FileAccess.get_sha256(root.path_join(binding.directory).path_join("saved_audit.json"))!=binding.audit_sha256:
		return 1
	var original: Resource = ResourceLoader.load(path,"",ResourceLoader.CACHE_MODE_IGNORE)
	if original==null or not original.valid() or Manifest.read(baseline.path_join("components/manifest.bin"),original,BASE_SHA).is_empty():
		return 1
	var proof: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(boundary_path))
	var native: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(native_path))
	if proof.failures.size()!=0 or proof.rows.size()!=66 or native.fail!=0 or native.registry_sha256!=registry_sha:
		return 1
	var matching: Array = native.regions.filter(func(row: Dictionary) -> bool: return row.region=="northwest")
	if matching.size()!=1:
		return 1
	_west=ResourceLoader.load(matching[0].index,"",ResourceLoader.CACHE_MODE_IGNORE)
	if _west==null or not _west.valid(registry_sha) or _west.bounds!=Rect2(-7300,-3700,1000,1000) or _west.source_count!=8216 or _west.regional_nonowner_ids.size()!=(124 if right else (110 if north else (104 if outer else 83))):
		return 1
	if outer:
		var extra: Array = native.regions.filter(func(row: Dictionary) -> bool: return row.region=="outer_west")
		if extra.size()!=1:
			return 1
		var extra_index: Resource = ResourceLoader.load(extra[0].index,"",ResourceLoader.CACHE_MODE_IGNORE)
		if extra_index==null or not extra_index.valid(registry_sha) or extra_index.bounds!=Rect2(-8300,-3700,1000,1000) or extra_index.source_count!=5525 or extra_index.regional_nonowner_ids.size()!=(58 if southwest else (49 if left else (31 if north else 21))):
			return 1
		# 仅本地聚合视图供原三层工厂遍历，不保存伪造的跨区CellIndex。
		_west=_west.duplicate(true)
		_west.cells.append_array(extra_index.cells)
		_west.bounds=_west.bounds.merge(extra_index.bounds)
		matching[0].rows.append_array(extra[0].rows)
	_raw_west=_west
	if north:
		var extra: Array = native.regions.filter(func(row: Dictionary) -> bool: return row.region=="north_seam")
		if extra.size()!=1:
			return 1
		var extra_index: Resource = ResourceLoader.load(extra[0].index,"",ResourceLoader.CACHE_MODE_IGNORE)
		if extra_index==null or not extra_index.valid(registry_sha) or extra_index.bounds!=Rect2(-7800,-4700,1000,1000) or extra_index.source_count!=3339 or extra_index.regional_nonowner_ids.size()!=(38 if right else (27 if left else 13)):
			return 1
		_west.cells.append_array(extra_index.cells)
		_west.bounds=_west.bounds.merge(extra_index.bounds)
		matching[0].rows.append_array(extra[0].rows)
	if left:
		var extra: Array = native.regions.filter(func(row: Dictionary) -> bool: return row.region=="north_left")
		if extra.size()!=1:
			return 1
		var extra_index: Resource = ResourceLoader.load(extra[0].index,"",ResourceLoader.CACHE_MODE_IGNORE)
		if extra_index==null or not extra_index.valid(registry_sha) or extra_index.bounds!=Rect2(-8300,-4700,500,1000) or extra_index.source_count!=2697 or extra_index.regional_nonowner_ids.size()!=33:
			return 1
		_west.cells.append_array(extra_index.cells)
		_west.bounds=_west.bounds.merge(extra_index.bounds)
		matching[0].rows.append_array(extra[0].rows)
	if right:
		var extra: Array = native.regions.filter(func(row: Dictionary) -> bool: return row.region=="north_right")
		if extra.size()!=1:
			return 1
		var extra_index: Resource = ResourceLoader.load(extra[0].index,"",ResourceLoader.CACHE_MODE_IGNORE)
		if extra_index==null or not extra_index.valid(registry_sha) or extra_index.bounds!=Rect2(-6800,-4700,500,1000) or extra_index.source_count!=1276 or extra_index.regional_nonowner_ids.size()!=16:
			return 1
		_west.cells.append_array(extra_index.cells)
		_west.bounds=_west.bounds.merge(extra_index.bounds)
		matching[0].rows.append_array(extra[0].rows)
	if southwest:
		var extra: Array = native.regions.filter(func(row: Dictionary) -> bool: return row.region=="southwest")
		if extra.size()!=1:
			return 1
		var extra_index: Resource = ResourceLoader.load(extra[0].index,"",ResourceLoader.CACHE_MODE_IGNORE)
		if extra_index==null or not extra_index.valid(registry_sha) or extra_index.bounds!=Rect2(-8300,-2700,1000,1000) or extra_index.source_count!=5774 or extra_index.regional_nonowner_ids.size()!=28:
			return 1
		_west.cells.append_array(extra_index.cells)
		_west.bounds=_west.bounds.merge(extra_index.bounds)
		matching[0].rows.append_array(extra[0].rows)
	for row: Dictionary in matching[0].rows:
		_source_hashes[row.path]=row.sha256
		var page: Resource = ResourceLoader.load(row.path,"",ResourceLoader.CACHE_MODE_IGNORE)
		if page==null or page.precision_original!=null:
			return 1
	var game := Gameplay.read_source()
	var guard := Gameplay.inspect_bounds(_west.bounds,game.get("entries",[]))
	if game.is_empty() or game.collision_sha256!=original.collision_sha256 or guard.is_empty() or not guard.standalone_merge_allowed:
		return 1
	var fixed: Array[ArrayMesh] = []
	for entry: Dictionary in _west.cells:
		var page: Resource = ResourceLoader.load(entry.fixed,"",ResourceLoader.CACHE_MODE_IGNORE)
		if page==null or not page.valid() or page.triangles!=entry.fixed_triangles or page.geometry_bytes!=entry.fixed_bytes:
			return 1
		fixed.append(Palette.recolor(page.meshes[0]))
	_fixed=Repack.repack(Spatial.Join.join(fixed))
	_catalog=original.duplicate(true)
	_out=output
	var file := FileAccess.open(baseline.path_join("components/manifest.bin"),FileAccess.READ)
	_components=file.get_var(false)
	file.close()
	DirAccess.make_dir_recursive_absolute(output.path_join("components"))
	var rows: Array = []
	for configuration: String in Catalog.CONFIGURATIONS:
		var additions := _west_meshes(configuration)
		if additions.size()!=3:
			return 1
		for parent in [8,9,11]:
			var entry: Dictionary = original.configurations[configuration][parent]
			var previous := _load(entry)
			if previous==null:
				return 1
			var meshes: Array[ArrayMesh] = []
			for kind in 3:
				var remaining: ArrayMesh = previous.meshes[kind]
				if kind<2:
					var selected: Array = proof.rows.filter(func(row: Dictionary) -> bool: return row.configuration==configuration and int(row.parent)==parent and int(row.layer)==kind)
					if selected.size()!=1 or selected[0].original!=entry.path or FileAccess.get_sha256(selected[0].kept)!=selected[0].kept_sha256 or FileAccess.get_sha256(selected[0].removed)!=selected[0].removed_sha256:
						return 1
					remaining=ResourceLoader.load(selected[0].kept,"",ResourceLoader.CACHE_MODE_IGNORE)
					var removed: ArrayMesh = ResourceLoader.load(selected[0].removed,"",ResourceLoader.CACHE_MODE_IGNORE)
					if not Boundary.Diff.conserved(previous.meshes[kind],remaining,removed):
						return 1
					if southwest and parent==11:
						remaining=southwest_kept(root,configuration,kind,remaining)
						if remaining==null:
							return 1
				var parts: Array[ArrayMesh] = [remaining]
				if parent==11:
					parts.append(additions[kind])
				var joined := Repack.repack(Spatial.Join.join(parts))
				if not Spatial.Join.conserved(joined,parts):
					return 1
				meshes.append(joined)
			var context := {"out":output.path_join(configuration),"configuration":configuration,"level":int(configuration.substr(3,1)),"parent_id":parent,"collision_sha256":original.collision_sha256,"owners_sha256":original.owners_sha256,"game_sources":previous.game_sources,"audit":false,"source_hash":(previous.source_hash+String(binding.sha256)+BOUNDARY_SHA+configuration).sha256_text()}
			DirAccess.make_dir_recursive_absolute(context.out)
			var changed := _replace(entry,meshes,context)
			if changed.is_empty():
				return 1
			_catalog.configurations[configuration][parent]=changed
			rows.append({"configuration":configuration,"parent":parent,"before":Array(entry.triangles),"after":Array(changed.triangles)})
			print("[Northwest catalog] ",configuration," parent=",parent," ",entry.triangles," -> ",changed.triangles)
	_catalog.regional_extension={"region":"west_northwest","bounds":Rect2(-7300,-3700,1000,2000),"source_count":88575,"registry_sha256":REGISTRY_SHA,"source_manifest_sha256":binding.sha256,"boundary_manifest_sha256":BOUNDARY_SHA}
	if outer:
		_catalog.regional_extension={"region":"west_outer","bounds":Rect2(-8300,-3700,2000,2000),"source_count":94058,"registry_sha256":registry_sha,"source_manifest_sha256":binding.sha256,"boundary_manifest_sha256":BOUNDARY_SHA}
	if north:
		_catalog.regional_extension={"region":"west_north_seam","bounds":Rect2(-8300,-4700,2000,3000),"source_count":97368,"registry_sha256":registry_sha,"source_manifest_sha256":binding.sha256,"boundary_manifest_sha256":BOUNDARY_SHA}
	if left:
		_catalog.regional_extension={"region":"west_north_left","bounds":Rect2(-8300,-4700,2000,3000),"source_count":100000,"registry_sha256":registry_sha,"source_manifest_sha256":binding.sha256,"boundary_manifest_sha256":BOUNDARY_SHA}
	if right:
		_catalog.regional_extension={"region":"west_north_right","bounds":Rect2(-8300,-4700,2000,3000),"source_count":101235,"registry_sha256":registry_sha,"source_manifest_sha256":binding.sha256,"boundary_manifest_sha256":BOUNDARY_SHA}
	if southwest:
		_catalog.regional_extension={"region":"west_southwest","bounds":Rect2(-8300,-4700,2000,3000),"source_count":106951,"registry_sha256":registry_sha,"source_manifest_sha256":binding.sha256,"boundary_manifest_sha256":"a6500e439ac54be0538727b8620e6b030f8489deb73a5b441240fabbf0d6f808"}
	return finish(root,original,rows)


func finish(root: String, original: Resource, rows: Array) -> int:
	for name: String in Catalog.CONFIGURATIONS:
		for parent in 16:
			if parent not in [8,9,11] and _catalog.configurations[name][parent]!=original.configurations[name][parent]:
				return 1
	var destination := _out.path_join("catalog.res")
	if not _catalog.valid() or ResourceSaver.save(_catalog,destination,ResourceSaver.FLAG_COMPRESS)!=OK:
		return 1
	var saved: Resource = ResourceLoader.load(destination,"",ResourceLoader.CACHE_MODE_IGNORE)
	if saved==null or not saved.valid() or saved.configurations!=_catalog.configurations:
		return 1
	var digest := FileAccess.get_sha256(destination)
	for name: String in Catalog.CONFIGURATIONS:
		var file := FileAccess.open(root.path_join("r193-native-full-a/coverage-"+name+".bin"),FileAccess.READ)
		var old: Dictionary=file.get_var(false)
		file.close()
		if old.catalog_sha256!=BASE_SHA or not old.verified or old.sources.size()!=48:
			return 1
		var coverage := Blocks.rewrite_coverage(old,_changes,digest)
		if coverage.is_empty():
			return 1
		file=FileAccess.open(_out.path_join("coverage-"+name+".bin"),FileAccess.WRITE)
		file.store_var(coverage)
		file.close()
	_components.catalog_sha256=digest
	var physical: Dictionary = {}
	for row: Dictionary in _components.pages.values():
		for path: String in row.components:
			physical[path]=_components.physical[path]
	_components.physical=physical
	var file := FileAccess.open(_out.path_join("components/manifest.bin"),FileAccess.WRITE)
	file.store_var(_components)
	file.close()
	if Manifest.read(_out.path_join("components/manifest.bin"),_catalog,digest).is_empty():
		return 1
	file=FileAccess.open(_out.path_join("report.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"fail":0,"catalog_sha256":digest,"source_catalog_sha256":BASE_SHA,"changed_pages":_changes.size(),"rows":rows,"physical":physical.size(),"logical":_catalog.descriptors.size(),"production_enabled":false,"visual_verified":false,"wall_pairing_verified":false}))
	file.close()
	print("[Northwest catalog] changed=",_changes.size()," physical=",physical.size()," fail=0")
	return 0


func audit_join(root: String, directory: String) -> int:
	var southwest := OS.get_environment("AGL_TOKYO_SOUTHWEST_COMBINED")=="1"
	var right := OS.get_environment("AGL_TOKYO_NORTH_RIGHT_COMBINED")=="1"
	var left := OS.get_environment("AGL_TOKYO_NORTH_LEFT_COMBINED")=="1"
	var outer := OS.get_environment("AGL_TOKYO_NORTHWEST_OUTER_COMBINED")=="1"
	var north := OS.get_environment("AGL_TOKYO_NORTH_SEAM_COMBINED")=="1"
	var registry_sha := OUTER_REGISTRY_SHA if outer else REGISTRY_SHA
	if north:
		registry_sha="6ca1fb5664dd0ce41ff58650d2c50bd7391eb2e23913ec0d4425208c74060204"
	if left:
		registry_sha="07d7bf28673e6472a05211a58a95a1325d9dc9b0c2abf613ea49d12f05dfde09"
	if right:
		registry_sha="45098e3d30e11470986c93200e8d81be56ff68e6616929baffc3d12e7cfb54b9"
	if southwest:
		registry_sha="67f3e204ecda7a49d6d51f00f2b49a0c8ecfc2b9b4c04a24ba559df8b03b1229"
	if root.is_empty() or directory.is_empty() or not FileAccess.file_exists(directory.path_join("report.json")) or FileAccess.file_exists(directory.path_join("saved_audit.json")):
		return 1
	var binding := native_binding(OS.get_environment("AGL_TOKYO_NORTHWEST_COMBINED")=="1",OS.get_environment("AGL_TOKYO_NORTHWEST_EAST_COMBINED")=="1",outer,north,left,right,OS.get_environment("AGL_TOKYO_SOUTH_COMBINED")=="1",southwest)
	if binding.is_empty():
		return 1
	var native_path := root.path_join(binding.directory).path_join("manifest.json")
	var baseline := root.path_join("r193-native-full-a")
	if FileAccess.get_sha256(baseline.path_join("catalog.res"))!=BASE_SHA or FileAccess.get_sha256(root.path_join("r203-boundary-c/report.json"))!=BOUNDARY_SHA or FileAccess.get_sha256(native_path)!=binding.sha256 or FileAccess.get_sha256(root.path_join(binding.directory).path_join("saved_audit.json"))!=binding.audit_sha256:
		return 1
	var report: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(directory.path_join("report.json")))
	var digest := FileAccess.get_sha256(directory.path_join("catalog.res"))
	var current: Resource = ResourceLoader.load(directory.path_join("catalog.res"),"",ResourceLoader.CACHE_MODE_IGNORE)
	var original: Resource = ResourceLoader.load(baseline.path_join("catalog.res"),"",ResourceLoader.CACHE_MODE_IGNORE)
	if current==null or original==null or not current.valid() or not original.valid() or report.get("fail",1)!=0 or report.catalog_sha256!=digest or report.rows.size()!=33:
		return 1
	var components := Manifest.read(directory.path_join("components/manifest.bin"),current,digest)
	if components.is_empty():
		return 1
	var native: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(native_path))
	var northwest: Array = native.regions.filter(func(row: Dictionary) -> bool: return row.region=="northwest")
	if northwest.size()!=1:
		return 1
	var index: Resource = ResourceLoader.load(northwest[0].index,"",ResourceLoader.CACHE_MODE_IGNORE)
	if index==null or not index.valid(registry_sha):
		return 1
	var audit_cells: Array = index.cells.duplicate(true)
	if outer:
		var extra: Array = native.regions.filter(func(row: Dictionary) -> bool: return row.region=="outer_west")
		if extra.size()!=1:
			return 1
		var extra_index: Resource = ResourceLoader.load(extra[0].index,"",ResourceLoader.CACHE_MODE_IGNORE)
		if extra_index==null or not extra_index.valid(registry_sha):
			return 1
		audit_cells.append_array(extra_index.cells)
		northwest[0].rows.append_array(extra[0].rows)
	if north:
		var extra: Array = native.regions.filter(func(row: Dictionary) -> bool: return row.region=="north_seam")
		if extra.size()!=1:
			return 1
		var extra_index: Resource = ResourceLoader.load(extra[0].index,"",ResourceLoader.CACHE_MODE_IGNORE)
		if extra_index==null or not extra_index.valid(registry_sha):
			return 1
		audit_cells.append_array(extra_index.cells)
		northwest[0].rows.append_array(extra[0].rows)
	if left:
		var extra: Array = native.regions.filter(func(row: Dictionary) -> bool: return row.region=="north_left")
		if extra.size()!=1:
			return 1
		var extra_index: Resource = ResourceLoader.load(extra[0].index,"",ResourceLoader.CACHE_MODE_IGNORE)
		if extra_index==null or not extra_index.valid(registry_sha):
			return 1
		audit_cells.append_array(extra_index.cells)
		northwest[0].rows.append_array(extra[0].rows)
	if right:
		var extra: Array = native.regions.filter(func(row: Dictionary) -> bool: return row.region=="north_right")
		if extra.size()!=1:
			return 1
		var extra_index: Resource = ResourceLoader.load(extra[0].index,"",ResourceLoader.CACHE_MODE_IGNORE)
		if extra_index==null or not extra_index.valid(registry_sha):
			return 1
		audit_cells.append_array(extra_index.cells)
		northwest[0].rows.append_array(extra[0].rows)
	if southwest:
		var extra: Array = native.regions.filter(func(row: Dictionary) -> bool: return row.region=="southwest")
		if extra.size()!=1:
			return 1
		var extra_index: Resource = ResourceLoader.load(extra[0].index,"",ResourceLoader.CACHE_MODE_IGNORE)
		if extra_index==null or not extra_index.valid(registry_sha):
			return 1
		audit_cells.append_array(extra_index.cells)
		northwest[0].rows.append_array(extra[0].rows)
	var proof: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(root.path_join("r203-boundary-c/report.json")))
	var stats := {"checked_pages":0,"component_mappings":0,"unchanged_parents":0}
	for name: String in Catalog.CONFIGURATIONS:
		var additions: Array[ArrayMesh] = []
		for kind in 3:
			var parts: Array[ArrayMesh] = []
			for entry: Dictionary in audit_cells:
				var descriptor: Dictionary = entry.mid if name=="lod4_mid" else entry.levels[int(name.substr(3,1))]
				var path: String = entry.fixed if kind==2 else descriptor.path
				var page: Resource = ResourceLoader.load(path,"",ResourceLoader.CACHE_MODE_IGNORE)
				if page==null or not page.valid():
					return 1
				if kind<2:
					var rows: Array = northwest[0].rows.filter(func(row: Dictionary) -> bool: return row.path==path)
					if rows.size()!=1 or FileAccess.get_sha256(path)!=rows[0].sha256:
						return 1
				parts.append(Palette.recolor(page.meshes[0 if kind==2 else kind]))
			additions.append(Spatial.Join.join(parts))
		for parent in 16:
			var before: Dictionary = original.configurations[name][parent]
			var after: Dictionary = current.configurations[name][parent]
			if parent not in [8,9,11]:
				if before!=after:
					return 1
				stats.unchanged_parents+=1
				continue
			var old: Resource = ResourceLoader.load(before.path,"",ResourceLoader.CACHE_MODE_IGNORE)
			var expected: Array[ArrayMesh] = []
			for kind in 3:
				var kept: ArrayMesh = old.meshes[kind]
				if kind<2:
					var matches: Array = proof.rows.filter(func(row: Dictionary) -> bool: return row.configuration==name and int(row.parent)==parent and int(row.layer)==kind)
					if matches.size()!=1 or FileAccess.get_sha256(matches[0].kept)!=matches[0].kept_sha256:
						return 1
					kept=ResourceLoader.load(matches[0].kept,"",ResourceLoader.CACHE_MODE_IGNORE)
					if southwest and parent==11:
						kept=southwest_kept(root,name,kind,kept)
						if kept==null:
							return 1
				var parts: Array[ArrayMesh] = [kept]
				if parent==11:
					parts.append(additions[kind])
				expected.append(Spatial.Join.join(parts))
			if not audit_entry(before,after,expected,components,stats):
				return 1
		var file := FileAccess.open(directory.path_join("coverage-"+name+".bin"),FileAccess.READ)
		var coverage: Dictionary=file.get_var(false)
		file.close()
		if coverage.catalog_sha256!=digest or not coverage.verified or coverage.sources.size()!=48 or coverage.pages.size()!=208 or coverage.collision_sha256!=original.collision_sha256 or coverage.owners_sha256!=original.owners_sha256:
			return 1
		for path: String in coverage.pages:
			if not current.descriptors.has(path) or coverage.pages[path].identity!=current.descriptors[path].canonical_identity or FileAccess.get_sha256(path)!=coverage.pages[path].sha256:
				return 1
	stats.fail=0
	stats.catalog_sha256=digest
	stats.production_enabled=false
	stats.visual_verified=false
	var file := FileAccess.open(directory.path_join("saved_audit.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(stats))
	file.close()
	print("[Northwest catalog saved audit] ",stats)
	return 0


static func southwest_kept(root: String, configuration: String, layer: int, original: ArrayMesh) -> ArrayMesh:
	var directory := root.path_join("r311-southwest-boundary-a")
	var digest := "a6500e439ac54be0538727b8620e6b030f8489deb73a5b441240fabbf0d6f808"
	if original==null or FileAccess.get_sha256(directory.path_join("report.json"))!=digest or FileAccess.get_sha256(directory.path_join("saved_audit.json"))!=digest:
		return null
	var report: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(directory.path_join("report.json")))
	var rows: Array = report.rows.filter(func(row: Dictionary) -> bool: return row.configuration==configuration and int(row.layer)==layer and int(row.parent)==11)
	if rows.size()!=1:
		return null
	var row: Dictionary = rows[0]
	for key: String in ["original","kept","removed"]:
		if FileAccess.get_sha256(row[key])!=row[key+"_sha256"]:
			return null
	var source: ArrayMesh = ResourceLoader.load(row.original,"",ResourceLoader.CACHE_MODE_IGNORE)
	var kept: ArrayMesh = ResourceLoader.load(row.kept,"",ResourceLoader.CACHE_MODE_IGNORE)
	var removed: ArrayMesh = ResourceLoader.load(row.removed,"",ResourceLoader.CACHE_MODE_IGNORE)
	if source==null or kept==null or removed==null or not Boundary.Diff.conserved(source,original,ArrayMesh.new()) or not Boundary.Diff.conserved(original,kept,removed):
		return null
	return kept


func audit_entry(before: Dictionary, after: Dictionary, expected: Array[ArrayMesh], components: Dictionary, stats: Dictionary) -> bool:
	if FileAccess.get_sha256(before.path)!=before.sha256 or FileAccess.get_sha256(after.path)!=after.sha256 or before.get("cuts",[])!=after.get("cuts",[]) or before.get("children",[]).size()!=after.get("children",[]).size():
		return false
	var old: Resource = ResourceLoader.load(before.path,"",ResourceLoader.CACHE_MODE_IGNORE)
	var page: Resource = ResourceLoader.load(after.path,"",ResourceLoader.CACHE_MODE_IGNORE)
	if old==null or page==null or not page.valid() or old.game_sources!=page.game_sources or not components.pages.has(after.path):
		return false
	var row: Dictionary = components.pages[after.path]
	if row.canonical_identity!=page.stream_identity() or row.bytes!=page.geometry_bytes or row.triangles!=page.triangles:
		return false
	for kind in 3:
		if not Spatial.Join.conserved(expected[kind],[page.meshes[kind]]):
			return false
		var path: String = row.mapping[kind][0]
		var component: Resource = ResourceLoader.load(path,"",ResourceLoader.CACHE_MODE_IGNORE)
		if component==null or not component.valid() or component.stream_identity()!=row.components[path].canonical_identity or not Spatial.Join.conserved(page.meshes[kind],[component.meshes[row.mapping[kind][1]]]):
			return false
		stats.component_mappings+=1
	stats.checked_pages+=1
	if not after.get("children",[]).is_empty():
		var pieces := Spatial._split(expected,after.cuts)
		if pieces.is_empty():
			return false
		for child in 4:
			var batch: Array[ArrayMesh] = [pieces[0][child],pieces[1][child],pieces[2][child]]
			if not audit_entry(before.children[child],after.children[child],batch,components,stats):
				return false
	return true
