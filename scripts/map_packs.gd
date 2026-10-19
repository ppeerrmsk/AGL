extends Node
## MapPacks — 导出包挂载随包分发的地图资源包（独立 PCK，规格 systems/tokyo-map-distribution）。
##
## 必须是 project.godot 里的第一个 AutoLoad：在 _init 里挂载，此时还没有任何脚本或后台线程
## 读 res://，挂载改 PackedData 不会与并发读文件竞争。包路径相对"可执行文件所在目录"解析，
## 与工作目录无关（快捷方式 / 启动器 / 任意 cwd 启动都一样）。
## 编辑器与工具版（feature "editor"）直接读项目里的散文件，不挂载。
const SETTING := "rendering/tokyo_map/installed_packs"

## 本次进程实际挂上的包（绝对路径），供诊断与测试读取。
static var mounted: PackedStringArray = PackedStringArray()


func _init() -> void:
	if OS.has_feature("editor"):
		return
	var base := OS.get_executable_path().get_base_dir()
	for relative: String in ProjectSettings.get_setting(SETTING, PackedStringArray()):
		var path := base.path_join(relative)
		if not FileAccess.file_exists(path):
			print("[MapPacks] missing %s" % path)
			continue
		var started := Time.get_ticks_usec()
		# replace_files=false：地图包只能新增路径，不能覆盖主包里的脚本或资源。
		if ProjectSettings.load_resource_pack(path, false):
			mounted.append(path)
			print("[MapPacks] mounted %s in %.1f ms" % [path, (Time.get_ticks_usec() - started) / 1000.0])
		else:
			push_error("[MapPacks] failed to mount %s" % path)
