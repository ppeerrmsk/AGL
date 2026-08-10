extends RefCounted

## 本地化源表目录与审计入口。
## 运行时翻译仍由 project.godot 注册的 .translation 资源提供；本文件只服务构建与测试。

const CSV_DIR := "res://i18n"
const SOURCE_FILES := [
	"interface.csv",
	"gameplay.csv",
	"skills.csv",
	"meta.csv",
	"radio.csv",
]
const EXPECTED_HEADER := ["keys", "zh", "en", "ja"]


static func csv_paths() -> Array[String]:
	var paths: Array[String] = []
	for file_name in SOURCE_FILES:
		paths.append("%s/%s" % [CSV_DIR, file_name])
	return paths


static func read_source(path: String) -> Dictionary:
	var errors: Array[String] = []
	var rows: Array[PackedStringArray] = []
	var header := PackedStringArray()
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		errors.append("无法读取 %s" % path)
		return {"header": header, "rows": rows, "errors": errors}

	header = file.get_csv_line()
	if Array(header) != EXPECTED_HEADER:
		errors.append("%s 表头应为 %s，实际 %s" % [path, str(EXPECTED_HEADER), str(header)])
	var line_no := 1
	while file.get_position() < file.get_length():
		line_no += 1
		var row := file.get_csv_line()
		if row.is_empty() or (row.size() == 1 and String(row[0]).strip_edges().is_empty()):
			continue
		if row.size() != header.size():
			errors.append("%s:%d 列数=%d，预期=%d" % [path, line_no, row.size(), header.size()])
			continue
		if String(row[0]).is_empty():
			errors.append("%s:%d key 为空" % [path, line_no])
			continue
		rows.append(row)
	file.close()
	return {"header": header, "rows": rows, "errors": errors}


static func audit() -> Dictionary:
	var errors: Array[String] = []
	var rows: Dictionary = {}
	var owners: Dictionary = {}
	var expected_names: Array[String] = []
	for file_name in SOURCE_FILES:
		expected_names.append(file_name)
	var actual_names: Array[String] = []
	for file_name in DirAccess.get_files_at(CSV_DIR):
		if file_name.get_extension().to_lower() == "csv":
			actual_names.append(file_name)
	expected_names.sort()
	actual_names.sort()
	if actual_names != expected_names:
		errors.append("CSV 分表集合漂移：预期=%s 实际=%s" % [str(expected_names), str(actual_names)])

	var paths := csv_paths()
	for path in paths:
		var source: Dictionary = read_source(path)
		errors.append_array(source.get("errors", []))
		for row: PackedStringArray in source.get("rows", []):
			var key := String(row[0])
			if rows.has(key):
				errors.append("重复 key %s：%s / %s" % [key, owners[key], path])
				continue
			rows[key] = [row[1], row[2], row[3]]
			owners[key] = path
	return {"paths": paths, "rows": rows, "owners": owners, "errors": errors}


static func expected_translation_paths() -> Array[String]:
	var paths: Array[String] = []
	for file_name in SOURCE_FILES:
		var stem: String = String(file_name).get_basename()
		for locale in EXPECTED_HEADER.slice(1):
			paths.append("res://i18n/%s.%s.translation" % [stem, locale])
	return paths
