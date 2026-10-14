extends RefCounted
## 正常游戏的安装包入口；显式实验覆盖优先，回归默认不受本地大资产影响。
const SETTING := "rendering/tokyo_map/installed_package"

static func package_path() -> String:
	var override := OS.get_environment("AGL_TOKYO_HLOD_PACKAGE")
	if not override.is_empty(): return override
	if not OS.get_environment("AGL_TOKYO_VOLUME").is_empty(): return ""
	if OS.get_environment("AGL_TOKYO_INSTALLED_TEST")!="1":
		for argument: String in OS.get_cmdline_user_args():
			if argument.begins_with("--bench="): return ""
	var path := String(ProjectSettings.get_setting(SETTING,""))
	return path if path.begins_with("res://resources/maps/tokyo_playable/") and FileAccess.file_exists(path) else ""

static func package_sha() -> String:
	if not OS.get_environment("AGL_TOKYO_HLOD_PACKAGE").is_empty(): return OS.get_environment("AGL_TOKYO_HLOD_PACKAGE_SHA")
	var path := package_path()
	return FileAccess.get_sha256(path) if not path.is_empty() else ""
