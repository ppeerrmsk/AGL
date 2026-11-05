extends RefCounted
## 显式编辑器 F5 验收入口：只覆盖本次进程，不修改正式地图设置。
const PREFIX := "--tokyo-f5-review="
const Contract := preload("res://scripts/rendering/tokyo_hlod_manifest.gd")


static func request_path(arguments: PackedStringArray, editor_build: bool) -> Dictionary:
	var paths := PackedStringArray()
	for argument: String in arguments:
		if argument.begins_with(PREFIX): paths.append(argument.substr(PREFIX.length()))
	if paths.is_empty(): return {}
	if not editor_build or paths.size()!=1 or not paths[0].begins_with("res://tmp/") \
		or paths[0].simplify_path()!=paths[0] or not paths[0].ends_with(".json"):
		return {"error":"invalid editor F5 review request"}
	return {"path":paths[0]}


static func valid_request(value: Variant) -> bool:
	if not value is Dictionary or value.get("schema")!=1 or not Contract.binding(value.get("package")) \
		or not String(value.package.path).begins_with("res://resources/maps/tokyo_playable/") \
		or String(value.package.path).simplify_path()!=value.package.path \
		or not value.get("run") is String or not String(value.run).is_valid_identifier() or String(value.run).length()>40 \
		or value.get("mode","automatic") not in ["automatic","manual"] \
		or not value.get("stream_optimizations",false) is bool \
		or not value.get("wide_handoff",false) is bool \
		or not value.get("fast_file_probe",false) is bool \
		or not value.get("resident_foundation",false) is bool \
		or not value.get("guard_prefetch",false) is bool \
		or not Contract.integer(value.get("cache_budget_mib",96)) or int(value.get("cache_budget_mib",96)) not in [96,192,384] \
		or not Contract.integer(value.get("seconds")) or int(value.seconds)<30 or int(value.seconds)>120 \
		or not Contract.numbers(value.get("pose"),3): return false
	return float(value.pose[2])>=CameraController.ZOOM_MIN and float(value.pose[2])<=CameraController.ZOOM_MAX


static func stream_options(config: Dictionary) -> Dictionary:
	# 必须在显式验收文件中填写 true；原验收文件与普通 F5 都不会默认开启新优化。
	var enabled := "1" if config.get("stream_optimizations",false)==true else "0"
	return {"AGL_TOKYO_REUSE_TEXTURE":enabled,"AGL_TOKYO_BALANCED_IO":enabled,
		"AGL_TOKYO_CACHE_MIB":str(int(config.get("cache_budget_mib",96))),
		"AGL_TOKYO_WIDE_HANDOFF":"1" if config.get("wide_handoff",false)==true else "0",
		"AGL_TOKYO_FAST_FILE_PROBE":"1" if config.get("fast_file_probe",false)==true else "0",
		"AGL_TOKYO_GUARD_PREFETCH":"1" if config.get("guard_prefetch",false)==true else "0",
		"AGL_TOKYO_RESIDENT_FOUNDATION":"1" if config.get("resident_foundation",false)==true else "0"}


static func start(parent: Node) -> bool:
	var request := request_path(OS.get_cmdline_user_args(),OS.has_feature("editor") and OS.is_debug_build())
	if request.is_empty(): return false
	var config: Variant=null
	if request.has("path") and FileAccess.file_exists(request.path):
		config=JSON.parse_string(FileAccess.get_file_as_string(request.path))
	if not valid_request(config) or FileAccess.get_sha256(config.package.path)!=config.package.sha256:
		push_error("Tokyo F5 review rejected: missing or invalid bound candidate")
		AudioManager.request_quit(1)
		return true
	var options := stream_options(config)
	for key: String in options: OS.set_environment(key,options[key])
	if config.get("mode","automatic")=="manual":
		# 人工 F5 只绑定候选；菜单、输入、镜头、音频和退出全部由玩家正常控制。
		OS.set_environment("AGL_TOKYO_INSTALLED_TEST","1")
		OS.set_environment("AGL_TOKYO_HLOD_PACKAGE",config.package.path)
		OS.set_environment("AGL_TOKYO_HLOD_PACKAGE_SHA",config.package.sha256)
		OS.set_environment("AGL_TOKYO_DISPLAY_COMPACTION","1")
		print("[Tokyo manual F5 review] run=",config.run," stream_optimizations=",config.get("stream_optimizations",false),
			" cache_budget_mib=",int(config.get("cache_budget_mib",96))," wide_handoff=",config.get("wide_handoff",false),
			" guard_prefetch=",config.get("guard_prefetch",false),
			" candidate=",config.package.path," sha256=",config.package.sha256,
			" default=",ProjectSettings.get_setting("rendering/tokyo_map/installed_package",""))
		return false
	var output := ProjectSettings.globalize_path("res://tmp/map_f5_review/"+String(config.run))
	if DirAccess.dir_exists_absolute(output):
		push_error("Tokyo F5 review rejected: output already exists")
		AudioManager.request_quit(1)
		return true
	var environment := {"AGL_TOKYO_INSTALLED_TEST":"1","AGL_TOKYO_HLOD_PACKAGE":config.package.path,
		"AGL_TOKYO_HLOD_PACKAGE_SHA":config.package.sha256,"AGL_TOKYO_ENTRY_BURST":"1","AGL_TOKYO_DISPLAY_COMPACTION":"1",
		"AGL_TOKYO_ENTRY_MENU":"1","AGL_TOKYO_ENTRY_COMBAT":"1","AGL_TOKYO_ENTRY_WASD":"sweep",
		"AGL_TOKYO_ENTRY_SIZE":"1920x1080","AGL_TOKYO_ENTRY_FPS":"0","AGL_TOKYO_ENTRY_INTERVAL_MS":"2000",
		"AGL_TOKYO_ENTRY_WHEEL_COUNT":"32","AGL_TOKYO_ENTRY_STABLE_CAMERA":"1","AGL_TOKYO_SELECTION_TRACE":"1",
		"AGL_TOKYO_ENTRY_POSE":"%s,%s,%s"%[config.pose[0],config.pose[1],config.pose[2]],
		"AGL_TOKYO_HLOD_PLAY_SECONDS":str(int(config.seconds)),"AGL_TOKYO_HLOD_ROUTE_OUT":output}
	for key: String in environment: OS.set_environment(key,environment[key])
	# 只静音本次验收进程，声音播放与战斗逻辑继续执行。
	AudioServer.set_bus_mute(AudioServer.get_bus_index("Master"),true)
	parent.get_tree().set_meta("tokyo_f5_review",{"request":request.path,
		"request_sha256":FileAccess.get_sha256(request.path),"package":config.package,
		"launch_arguments":OS.get_cmdline_args(),"run":config.run,"inputs":"InputEvent WASD and wheel",
		"default_package":ProjectSettings.get_setting("rendering/tokyo_map/installed_package","")})
	var route := preload("res://scripts/tests/tokyo_hlod_route_probe.gd").new()
	parent.add_child(route)
	route.call_deferred("run")
	return true
