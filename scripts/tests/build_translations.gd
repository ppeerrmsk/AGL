extends RefCounted

## 从五份 CSV 重建项目跟踪的十五份 Translation 资源。
## 输出到 bench/results，由隔离 wrapper 带回原工作区，避免无头测试写源树。
const _I18N_CATALOG := preload("res://scripts/i18n_catalog.gd")

var _fail := 0


func run() -> void:
	var audit: Dictionary = _I18N_CATALOG.audit()
	var errors: Array = audit.get("errors", [])
	if not errors.is_empty():
		_fail = errors.size()
		for message in errors:
			printerr("[i18n_build] %s" % message)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://bench/results"))
	for path: String in audit.get("paths", []):
		_build_source(path)


func _build_source(path: String) -> void:
	var source: Dictionary = _I18N_CATALOG.read_source(path)
	var header: PackedStringArray = source.get("header", PackedStringArray())
	var rows: Array = source.get("rows", [])
	var translations: Array[Translation] = []
	for i in range(1, header.size()):
		var translation := Translation.new()
		translation.locale = header[i]
		translations.append(translation)
	for row: PackedStringArray in rows:
		for i in range(translations.size()):
			translations[i].add_message(row[0], row[i + 1])
	var stem := path.get_file().get_basename()
	for i in range(translations.size()):
		var locale := String(header[i + 1])
		var output_path := "res://bench/results/%s.%s.translation" % [stem, locale]
		var err := ResourceSaver.save(translations[i], output_path)
		if err != OK:
			_fail += 1
			printerr("[i18n_build] save failed path=%s err=%d" % [output_path, err])
		else:
			print("[i18n_build] wrote %s (%d messages)" % [output_path,
				translations[i].get_message_count()])
