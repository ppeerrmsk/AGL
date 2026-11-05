extends RefCounted
## 正常游戏的安装包入口；显式实验覆盖优先，回归默认不受本地大资产影响。
const SETTING := "rendering/tokyo_map/installed_package"
const MOTION_SETTING := "rendering/tokyo_map/streaming_optimization_enabled"
const MOTION_PACKAGE := "res://resources/maps/tokyo_playable/m20_f5_candidate_20261026/package.json"
const MOTION_OPTIONS := {
	"AGL_TOKYO_CACHE_MIB":"384", "AGL_TOKYO_RESIDENT_FOUNDATION":"0",
	"AGL_TOKYO_GUARD_PREFETCH":"1", "AGL_TOKYO_DISPLAY_COMPACTION":"1",
	"AGL_TOKYO_WIDE_HANDOFF":"1", "AGL_TOKYO_FAST_FILE_PROBE":"1",
	"AGL_TOKYO_CACHE_LRU":"1", "AGL_TOKYO_RETURN_CACHE":"1",
	"AGL_TOKYO_BACKGROUND_SOURCE":"1",
	"AGL_TOKYO_LOD_BLEND":"1", "AGL_TOKYO_DIRECT_RETURN":"1",
	"AGL_TOKYO_REUSE_TEXTURE":"1",
}


static func default_motion_profile() -> bool:
	# 普通启动保留缓存和预取，不启用运动概括；使用原 M20 清晰度分级。
	if ProjectSettings.get_setting(MOTION_SETTING,false)!=true \
		or String(ProjectSettings.get_setting(SETTING,""))!=MOTION_PACKAGE: return false
	if not OS.get_environment("AGL_TOKYO_HLOD_PACKAGE").is_empty() \
		or not OS.get_environment("AGL_TOKYO_VOLUME").is_empty(): return false
	if OS.get_environment("AGL_TOKYO_INSTALLED_TEST")!="1":
		for argument: String in OS.get_cmdline_user_args():
			if argument.begins_with("--bench="): return false
	return true


static func runtime_option(key: String) -> String:
	# 显式 0 仍可做对照；普通 F5 不需要设置测试环境变量。
	if OS.has_environment(key): return OS.get_environment(key)
	return String(MOTION_OPTIONS.get(key,"")) if default_motion_profile() else ""


static func motion_admission_enabled(key: String) -> bool:
	return runtime_option(key)=="1" and (default_motion_profile() \
		or OS.get_environment("AGL_TOKYO_INSTALLED_TEST")=="1")

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
