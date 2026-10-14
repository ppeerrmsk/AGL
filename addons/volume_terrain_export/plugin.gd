@tool
extends EditorPlugin
## 仅导出阶段附带缓存指纹输入与沙漠地图文档，不影响编译映射或运行时几何。
const Archive := preload("res://scripts/experiments/volume_terrain_archive.gd")

class TerrainSourcesExport extends EditorExportPlugin:


	func _get_name() -> String:
		return "AGLVolumeTerrainSources"


	func _export_begin(_features: PackedStringArray, _is_debug: bool, _path: String, _flags: int) -> void:
		# 非 remap 附件与 .gdc/.gd.remap 共存，FileAccess 仍可校验真实源码。
		for source: String in Archive.SOURCES:
			if source.ends_with(".gd"):
				add_file(source, FileAccess.get_file_as_bytes(source), false)
		# .aglmap 是 FileAccess 读取的自定义文档，all_resources 不会自动收录。
		var desert_map := "res://resources/maps/desert_railway_preview.aglmap"
		add_file(desert_map, FileAccess.get_file_as_bytes(desert_map), false)


var _exporter: EditorExportPlugin


func _enter_tree() -> void:
	_exporter = TerrainSourcesExport.new()
	add_export_plugin(_exporter)


func _exit_tree() -> void:
	remove_export_plugin(_exporter)
	_exporter = null
