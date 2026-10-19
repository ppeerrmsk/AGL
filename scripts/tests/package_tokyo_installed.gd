extends RefCounted
## 复用原迁址器；只在tmp准备完整原生metadata与拷贝清单，不改生产文件。
const Native := preload("res://scripts/rendering/tokyo_hlod_native.gd")
const Paths := preload("res://scripts/tests/tokyo_portable_paths.gd")
const Values := preload("res://scripts/tests/build_tokyo_portable_package.gd")
const TARGET := "res://resources/maps/tokyo_playable/"

static func binding(path: String, logical: String) -> Dictionary:
	return {"path":logical,"sha256":FileAccess.get_sha256(path)}

static func run(package_path: String, output: String) -> int:
	var version := OS.get_environment("AGL_TOKYO_INSTALL_VERSION")
	if not version.is_empty() and (not version.is_valid_identifier() or version.begins_with("_")): return 1
	var target := TARGET if version.is_empty() else TARGET+version+"/"
	if DirAccess.dir_exists_absolute(output): return 1
	FileAccess.open(output+".progress",FileAccess.WRITE).store_string("reading native catalog")
	var package: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(package_path))
	# 原迁址器不会迁移二分覆盖；拒绝静默丢弃，改走显式增量制作入口。
	if package.get("native",{}).has("partition_override"): return 1
	for item: Dictionary in [package.native.catalog,package.native.components]:
		if FileAccess.get_sha256(item.path)!=item.sha256: return 1
	var native := Native.new()
	if not native.read(package.native): return 1
	FileAccess.open(output+".progress",FileAccess.WRITE).store_string("reading component values")
	var data := Values.read_values(package.native.components.path)
	var catalog: Resource=native.catalog.duplicate(true)
	var paths: Dictionary={}
	var copies: Array=[]
	for path: String in catalog.descriptors:
		paths[path]=target+"logical/"+path.sha256_text()+".logical"
	for path: String in data.physical:
		var descriptor: Dictionary=data.physical[path]
		if FileAccess.get_sha256(path)!=descriptor.sha256: return 1
		var relative := "assets/"+String(descriptor.sha256)+".res"
		paths[path]=target+relative
		copies.append({"source":path,"relative":relative,"sha256":descriptor.sha256})
		if copies.size()%500==0:
			FileAccess.open(output+".progress",FileAccess.WRITE).store_string("hashed %d/%d" % [copies.size(),data.physical.size()])
	FileAccess.open(output+".progress",FileAccess.WRITE).store_string("verifying reversible metadata")
	for value: Dictionary in [catalog.configurations,catalog.descriptors,data]:
		if not Paths.reversible(value,paths): return 1
	catalog.configurations=Paths.rewrite(catalog.configurations,paths)
	catalog.descriptors=Paths.rewrite(catalog.descriptors,paths)
	if not catalog.valid() or DirAccess.make_dir_recursive_absolute(output)!=OK: return 1
	var path := output.path_join("catalog.res")
	if ResourceSaver.save(catalog,path,ResourceSaver.FLAG_COMPRESS)!=OK: return 1
	var native_binding := {"catalog":binding(path,target+"native/catalog.res"),"coverage":{}}
	copies.append({"source":path,"relative":"native/catalog.res","sha256":FileAccess.get_sha256(path)})
	data=Paths.rewrite(data,paths);data.catalog_sha256=native_binding.catalog.sha256
	path=output.path_join("components.bin")
	if not Values.save_values(path,data): return 1
	native_binding["components"]=binding(path,target+"native/components.bin")
	copies.append({"source":path,"relative":"native/components.bin","sha256":FileAccess.get_sha256(path)})
	for name: String in package.native.coverage:
		FileAccess.open(output+".progress",FileAccess.WRITE).store_string("coverage "+name)
		if FileAccess.get_sha256(package.native.coverage[name].path)!=package.native.coverage[name].sha256: return 1
		var original := Values.read_values(package.native.coverage[name].path)
		if not Paths.reversible(original,paths): return 1
		var coverage: Dictionary=Paths.rewrite(original,paths)
		coverage.catalog_sha256=native_binding.catalog.sha256
		for logical: String in coverage.pages:
			coverage.pages[logical].sha256=var_to_bytes(data.pages[logical]).hex_encode().sha256_text()
		path=output.path_join("coverage_"+name+".bin")
		if not Values.save_values(path,coverage): return 1
		var relative := "native/coverage_"+name+".bin"
		native_binding.coverage[name]=binding(path,target+relative)
		copies.append({"source":path,"relative":relative,"sha256":FileAccess.get_sha256(path)})
	var file := FileAccess.open(output.path_join("inventory.json"),FileAccess.WRITE)
	if file==null: return 1
	file.store_string(JSON.stringify({"target":target,"native":native_binding,"copies":copies,"reversible":true},"\t"));file.close()
	FileAccess.open(output+".progress",FileAccess.WRITE).store_string("complete")
	print("[Installed stage] copies=",copies.size()," source unchanged=true")
	return 0
