extends RefCounted
## 东京地图发行打包的静态守卫（规格 systems/tokyo-map-distribution）。
## 运行：bench\run.cmd map_packs 1 120 Shadow Headless
## 1. MapPacks 必须是 project.godot 里第一个 AutoLoad（挂载时不能有别的脚本/线程在读 res://）
## 2. installed_packs 每项是相对可执行文件目录的 .pck，且包含当前 installed_package 版本的包
## 3. 主包导出预设排除地图包里的两个目录（版本包目录与三维启用门目录），且没有 include 把它们带回来
const MapPacks := preload("res://scripts/map_packs.gd")
const Installed := preload("res://scripts/rendering/tokyo_installed_map.gd")
const PACKED_DIRS: Array[String] = ["resources/maps/tokyo_playable/", "resources/maps/tokyo_volume_preview/"]

var _pass := 0
var _fail := 0


func run() -> void:
	print("\n════════ 地图包发行守卫 ════════")
	_check("MapPacks 是第一个 AutoLoad", _first_autoload() == "MapPacks", _first_autoload())
	var packs: PackedStringArray = ProjectSettings.get_setting(MapPacks.SETTING, PackedStringArray())
	var relative_ok := not packs.is_empty()
	for pack: String in packs:
		relative_ok = relative_ok and pack.ends_with(".pck") and not pack.is_absolute_path() \
			and not pack.begins_with("res://") and not pack.begins_with("user://") and not ".." in pack
	_check("installed_packs 均为相对可执行文件目录的 .pck", relative_ok, str(packs))
	var package := String(ProjectSettings.get_setting(Installed.SETTING, ""))
	var version := package.get_base_dir().get_file()
	_check("installed_packs 含当前版本 %s 的包" % version,
		packs.has("maps/tokyo_playable_%s.pck" % version), str(packs))
	var presets := ConfigFile.new()
	var loaded := presets.load("res://export_presets.cfg") == OK
	_check("export_presets.cfg 可读", loaded, "")
	if loaded:
		for section: String in presets.get_sections():
			if not section.begins_with("preset.") or section.ends_with(".options"):
				continue
			var include := String(presets.get_value(section, "include_filter", ""))
			var exclude := String(presets.get_value(section, "exclude_filter", ""))
			for packed: String in PACKED_DIRS:
				_check("%s 排除 %s*" % [section, packed], (packed + "*") in exclude.split(","), exclude)
				_check("%s 不 include %s" % [section, packed], not packed.get_base_dir().get_file() in include, include)
	print("[map_packs] pass=%d fail=%d" % [_pass, _fail])


func _first_autoload() -> String:
	var in_section := false
	for line: String in FileAccess.get_file_as_string("res://project.godot").split("\n"):
		line = line.strip_edges()
		if line.begins_with("["):
			in_section = line == "[autoload]"
		elif in_section and "=" in line:
			return line.get_slice("=", 0)
	return ""


func _check(label: String, ok: bool, detail: String) -> void:
	if ok:
		_pass += 1
		print("  ✓ %s" % label)
	else:
		_fail += 1
		printerr("  ✗ %s (%s)" % [label, detail])
