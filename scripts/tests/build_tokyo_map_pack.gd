extends RefCounted
## 把已安装的东京地图包目录（默认 m20）直接打成独立 PCK（规格 systems/tokyo-map-distribution）。
## 用引擎自带 PCKPacker 逐文件写入，不经编辑器导出器：编辑器导出在单目录 10 万级文件时
## 收尾的 UID 过滤按路径线性查目录（Windows 上逐项 to_lower），总代价 O(N²)。
##
## 打包范围 = 安装器认定的"M20 运行时"：installed_package 所在版本目录的全部文件，加上三维启用门
## （TokyoVolumeArchive.PATH，缺它正常路径退回二维）。
## 用法（只经 bench 包装器，工具版无头运行；工程里不得有这些路径的散文件）：
##   set "AGL_TOKYO_PACK_SOURCE=<已安装地图的绝对路径>\resources\maps"
##   set "AGL_TOKYO_PACK_OUTPUT=<项目外绝对路径>\maps\tokyo_playable_m20.pck"
##   bench\run.cmd tokyo_map_pack 1 3600 Shadow Headless
## 每个文件读一次：算 SHA256（assets/<sha>.res 必须与文件名一致、package.json 里的包内绑定
## 必须一致）后写入；flush 后在本进程挂载回读，逐文件核 SHA256。收据写 bench/results/。
const Installed := preload("res://scripts/rendering/tokyo_installed_map.gd")
const VolumeArchive := preload("res://scripts/rendering/tokyo_volume_archive.gd")
const MAPS := "res://resources/maps/"
const ROOT := "res://resources/maps/tokyo_playable/"
const PROGRESS_EVERY := 5000

var _fail := 0
var _started := 0


func run() -> void:
	_started = Time.get_ticks_msec()
	var error := _build()
	if not error.is_empty():
		_fail += 1
		printerr("[tokyo_map_pack] ERROR %s" % error)


func _build() -> String:
	var source_root := OS.get_environment("AGL_TOKYO_PACK_SOURCE").replace("\\", "/").trim_suffix("/")
	var output := OS.get_environment("AGL_TOKYO_PACK_OUTPUT").replace("\\", "/")
	var package_path := String(ProjectSettings.get_setting(Installed.SETTING, ""))
	var project_dir := ProjectSettings.globalize_path("res://").replace("\\", "/")
	if not source_root.is_absolute_path() or not DirAccess.dir_exists_absolute(source_root):
		return "AGL_TOKYO_PACK_SOURCE must be an existing absolute directory: %s" % source_root
	if not output.is_absolute_path() or not output.ends_with(".pck") \
			or output.to_lower().begins_with(project_dir.to_lower()):
		return "AGL_TOKYO_PACK_OUTPUT must be an absolute .pck outside the project: %s" % output
	if FileAccess.file_exists(output):
		return "refusing to overwrite %s" % output
	if not package_path.begins_with(ROOT) or package_path.get_file() != "package.json" \
			or not VolumeArchive.PATH.begins_with(MAPS):
		return "unexpected %s=%s" % [Installed.SETTING, package_path]
	var target_dir := package_path.get_base_dir() + "/"
	# 回读核验必须读到包里的文件：项目里不能再有同路径散文件（散文件会抢先命中）。
	if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(target_dir)) \
			or FileAccess.file_exists(ProjectSettings.globalize_path(VolumeArchive.PATH)):
		return "loose %s or %s exists in the project; run in a copy without them" % [
			target_dir, VolumeArchive.PATH]
	var relative_dir := target_dir.trim_prefix(MAPS)
	var files := PackedStringArray()
	var error := _collect(source_root.path_join(relative_dir), relative_dir, files)
	if not error.is_empty():
		return error
	var gate := VolumeArchive.PATH.trim_prefix(MAPS)
	if not FileAccess.file_exists(source_root.path_join(gate)):
		return "missing 3D gate %s under %s" % [gate, source_root]
	files.append(gate)
	files.sort()
	print("[tokyo_map_pack] source=%s files=%d target=%s gate=%s" % [source_root, files.size(), target_dir, gate])

	DirAccess.make_dir_recursive_absolute(output.get_base_dir())
	var partial := output + ".partial"
	var packer := PCKPacker.new()
	if packer.pck_start(partial) != OK:
		return "pck_start failed: %s" % partial
	var digests: Dictionary = {}
	var total_bytes := 0
	for i in files.size():
		var relative := files[i]
		var bytes := FileAccess.get_file_as_bytes(source_root.path_join(relative))
		if bytes.is_empty() and FileAccess.get_open_error() != OK:
			return "read failed: %s" % relative
		var digest := _sha256(bytes)
		var stem := relative.get_file().get_basename()
		if relative.begins_with(relative_dir + "assets/") and stem.length() == 64 and stem != digest:
			return "asset digest mismatch: %s -> %s" % [relative, digest]
		if packer.add_file_from_buffer(MAPS + relative, bytes) != OK:
			return "add_file failed: %s" % relative
		digests[MAPS + relative] = digest
		total_bytes += bytes.size()
		if (i + 1) % PROGRESS_EVERY == 0:
			print("[tokyo_map_pack] packed %d/%d %.2f GB %.1fs" % [i + 1, files.size(),
				total_bytes / 1e9, _elapsed()])
	error = _check_bindings(source_root.path_join(relative_dir + "package.json"), target_dir, digests)
	if not error.is_empty():
		return error
	if packer.flush() != OK:
		return "flush failed"
	packer = null
	if DirAccess.rename_absolute(partial, output) != OK:
		return "rename failed: %s" % partial
	var pack_seconds := _elapsed()

	var mount_started := Time.get_ticks_usec()
	if not ProjectSettings.load_resource_pack(output, false):
		return "mount failed: %s" % output
	var mount_ms := (Time.get_ticks_usec() - mount_started) / 1000.0
	var checked := 0
	for path: String in digests:
		if FileAccess.get_sha256(path) != digests[path]:
			return "read-back digest mismatch: %s" % path
		checked += 1
		if checked % PROGRESS_EVERY == 0:
			print("[tokyo_map_pack] verified %d/%d %.1fs" % [checked, digests.size(), _elapsed()])
	var receipt := {
		"schema": 1,
		"pack": output.get_file(),
		"pack_bytes": FileAccess.open(output, FileAccess.READ).get_length(),
		"package": package_path,
		"package_sha256": digests[package_path],
		"gate": VolumeArchive.PATH,
		"gate_sha256": digests[VolumeArchive.PATH],
		"files": files.size(),
		"file_bytes": total_bytes,
		"listing_sha256": _sha256(_listing(digests).to_utf8_buffer()),
		"engine": Engine.get_version_info().string,
		"pack_seconds": pack_seconds,
		"mount_ms": mount_ms,
		"total_seconds": _elapsed(),
	}
	var receipt_path := "res://bench/results/tokyo_map_pack_%s.json" % \
		Time.get_datetime_string_from_system(true).replace(":", "").replace("-", "")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://bench/results"))
	FileAccess.open(receipt_path, FileAccess.WRITE).store_string(JSON.stringify(receipt, "  "))
	print("[tokyo_map_pack] OK %s" % JSON.stringify(receipt))
	return ""


func _collect(directory: String, prefix: String, out: PackedStringArray) -> String:
	var dir := DirAccess.open(directory)
	if dir == null:
		return "cannot open %s" % directory
	dir.include_hidden = true
	for name: String in dir.get_files():
		# 安装器在复制期间放 .gdignore 守卫；看到它说明安装未完成，拒绝打包。
		if name.begins_with(".") or name.ends_with(".import") or name.ends_with(".remap"):
			return "unexpected file %s%s (install incomplete?)" % [prefix, name]
		out.append(prefix + name)
	for name: String in dir.get_directories():
		var error := _collect(directory.path_join(name), prefix + name + "/", out)
		if not error.is_empty():
			return error
	return ""


## package.json 里指向本包目录的每个 {path, sha256} 绑定都必须在包内且摘要一致；
## 指向其它版本目录的绑定（增量包复用旧资产）只计数，由那个版本自己的包负责。
func _check_bindings(package_file: String, target_dir: String, digests: Dictionary) -> String:
	var stack: Array = [JSON.parse_string(FileAccess.get_file_as_string(package_file))]
	var bound := 0
	var external := 0
	while not stack.is_empty():
		var value: Variant = stack.pop_back()
		if value is Dictionary:
			if value.has("path") and value.has("sha256"):
				var path := String(value.path)
				if not path.begins_with(target_dir):
					external += 1
				elif digests.get(path, "") != String(value.sha256):
					return "package binding mismatch: %s" % path
				else:
					bound += 1
			stack.append_array(value.values())
		elif value is Array:
			stack.append_array(value)
	print("[tokyo_map_pack] package bindings verified=%d external=%d" % [bound, external])
	return "" if bound > 0 else "package.json has no bindings"


func _listing(digests: Dictionary) -> String:
	var paths: Array = digests.keys()
	paths.sort()
	var lines := PackedStringArray()
	for path: String in paths:
		lines.append("%s\t%s" % [path, digests[path]])
	return "\n".join(lines) + "\n"


func _elapsed() -> float:
	return (Time.get_ticks_msec() - _started) / 1000.0


static func _sha256(bytes: PackedByteArray) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	if not bytes.is_empty():
		context.update(bytes)
	return context.finish().hex_encode()
