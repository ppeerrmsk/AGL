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
	_motion_profile_checks()
	_installed_clarity_checks(package)
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


func _motion_profile_checks() -> void:
	var policy := preload("res://scripts/rendering/tokyo_hlod_cache_policy.gd")
	var saved: Dictionary={}
	var keys: Array=Installed.MOTION_OPTIONS.keys()
	for extra: String in ["AGL_TOKYO_HLOD_PACKAGE","AGL_TOKYO_VOLUME","AGL_TOKYO_INSTALLED_TEST","AGL_TOKYO_DIRECT_RETURN"]:
		if extra not in keys: keys.append(extra)
	for key: String in keys:
		saved[key]=[OS.has_environment(key),OS.get_environment(key)]
		OS.unset_environment(key)
	var package: Variant=ProjectSettings.get_setting(Installed.SETTING)
	var enabled: Variant=ProjectSettings.get_setting(Installed.MOTION_SETTING)
	_check("普通回归不自动加载本地优化地图", not Installed.default_motion_profile() and Installed.package_path().is_empty(), "")
	ProjectSettings.set_setting(Installed.SETTING,Installed.MOTION_PACKAGE)
	ProjectSettings.set_setting(Installed.MOTION_SETTING,true)
	OS.set_environment("AGL_TOKYO_INSTALLED_TEST","1")
	var defaults_ok := Installed.default_motion_profile()
	for key: String in Installed.MOTION_OPTIONS:
		defaults_ok=defaults_ok and Installed.runtime_option(key)==Installed.MOTION_OPTIONS[key]
	_check("无候选参数时安装配置提供全部已验证选项", defaults_ok, "")
	_check("缓存384MiB且显示96MiB", policy.candidate_limit()==384*policy.MIB and policy.display_limit()==96*policy.MIB, "")
	var camera := CameraController.new()
	var overlay := preload("res://scripts/rendering/tokyo_hlod_overlay.gd").new()
	var stream := preload("res://scripts/rendering/tokyo_hlod_stream.gd").new()
	_check("默认保留预取缓存但关闭粗化常驻层", camera._return_prefetch and overlay._guard_prefetch and not overlay.resident_foundation and overlay.cache_pool_limit==384*policy.MIB, "")
	_check("默认接入已验证的回中缓存和后台网格请求", overlay._return_cache and stream.cache_lru and stream.async_mesh_dispatch and stream.minimum_mesh_progress, "")
	_check("默认分阶段加载与已验收的远距立即回中", Installed.motion_admission_enabled("AGL_TOKYO_BACKGROUND_SOURCE") and camera.distance_return_enabled, "")
	_check("默认稳定换档并复用同规格纹理", Installed.motion_admission_enabled("AGL_TOKYO_LOD_BLEND") and stream.reuse_textures, "")
	OS.set_environment("AGL_TOKYO_BACKGROUND_SOURCE","0")
	_check("分阶段加载允许显式回退对照", not Installed.motion_admission_enabled("AGL_TOKYO_BACKGROUND_SOURCE"), "")
	OS.unset_environment("AGL_TOKYO_BACKGROUND_SOURCE")
	camera.free();overlay.free();stream.free()
	for key: String in ["AGL_TOKYO_LOD_BLEND","AGL_TOKYO_DIRECT_RETURN","AGL_TOKYO_REUSE_TEXTURE"]: OS.set_environment(key,"0")
	camera=CameraController.new();stream=preload("res://scripts/rendering/tokyo_hlod_stream.gd").new()
	_check("显式0可分别关闭换档、立即回中及纹理复用", not Installed.motion_admission_enabled("AGL_TOKYO_LOD_BLEND") and not camera.distance_return_enabled and not stream.reuse_textures, "")
	camera.free();stream.free()
	for key: String in ["AGL_TOKYO_LOD_BLEND","AGL_TOKYO_DIRECT_RETURN","AGL_TOKYO_REUSE_TEXTURE"]: OS.unset_environment(key)
	OS.set_environment("AGL_TOKYO_CACHE_LRU","0")
	OS.set_environment("AGL_TOKYO_RETURN_CACHE","0")
	stream=preload("res://scripts/rendering/tokyo_hlod_stream.gd").new()
	overlay=preload("res://scripts/rendering/tokyo_hlod_overlay.gd").new()
	_check("显式0关闭新缓存与后台请求用于对照", not overlay._return_cache and not stream.cache_lru and not stream.async_mesh_dispatch and not stream.minimum_mesh_progress, "")
	overlay.free();stream.free()
	OS.unset_environment("AGL_TOKYO_CACHE_LRU")
	OS.unset_environment("AGL_TOKYO_RETURN_CACHE")
	OS.set_environment("AGL_TOKYO_GUARD_PREFETCH","0")
	_check("显式关闭仍可做同条件对照", not Installed.motion_admission_enabled("AGL_TOKYO_GUARD_PREFETCH"), "")
	OS.unset_environment("AGL_TOKYO_GUARD_PREFETCH")
	OS.set_environment("AGL_TOKYO_HLOD_PACKAGE","res://another-package.json")
	_check("显式其它地图不继承默认运动配置", not Installed.default_motion_profile() and Installed.runtime_option("AGL_TOKYO_CACHE_MIB").is_empty(), "")
	OS.unset_environment("AGL_TOKYO_HLOD_PACKAGE")
	OS.set_environment("AGL_TOKYO_VOLUME","off")
	_check("显式关闭三维地图不继承配置", not Installed.default_motion_profile(), "")
	OS.unset_environment("AGL_TOKYO_VOLUME")
	ProjectSettings.set_setting(Installed.MOTION_SETTING,false)
	_check("项目开关可回退", not Installed.default_motion_profile(), "")
	ProjectSettings.set_setting(Installed.MOTION_SETTING,true)
	ProjectSettings.set_setting(Installed.SETTING,"res://resources/maps/tokyo_playable/m20/package.json")
	_check("旧M20不误用新包质量合同", not Installed.default_motion_profile(), "")
	ProjectSettings.set_setting(Installed.SETTING,package)
	ProjectSettings.set_setting(Installed.MOTION_SETTING,enabled)
	for key: String in saved:
		if saved[key][0]: OS.set_environment(key,saved[key][1])
		else: OS.unset_environment(key)


func _installed_clarity_checks(package: String) -> void:
	# CI/主包不携带大型地图；有本地安装时逐项核对真实清晰度合同，不能只测配置常量。
	if not FileAccess.file_exists(package):
		print("  地图资产未安装，跳过本地目录清晰度核对")
		return
	var installed: Variant=JSON.parse_string(FileAccess.get_file_as_string(package))
	var baseline: Variant=JSON.parse_string(FileAccess.get_file_as_string("res://resources/maps/tokyo_playable/m20/package.json"))
	if not installed is Dictionary or not baseline is Dictionary:
		_check("已安装地图清晰度合同可读",false,package)
		return
	_check("恢复原 M20 全部档位、纹理绑定及尺度上限", installed.get("catalogs")==baseline.get("catalogs"),package)
	var no_summary: bool=not installed.has("far_summary_recipe")
	for binding: Dictionary in installed.get("catalogs",[]):
		var catalog: Variant=JSON.parse_string(FileAccess.get_file_as_string(binding.path))
		no_summary=no_summary and catalog is Dictionary and not catalog.has("resident_motion_summary") and not catalog.has("far_summary_recipe")
	_check("WASD及空格不可获得放大粗糙远景的资格",no_summary,package)


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
