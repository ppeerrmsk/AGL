extends RefCounted

## 从 CSV 重建项目跟踪的三份 Translation 资源。
## 输出到 bench/results，由隔离 wrapper 带回原工作区，避免无头测试写源树。
var _fail := 0


func run() -> void:
	var csv := FileAccess.open("res://i18n/translations.csv", FileAccess.READ)
	if csv == null:
		_fail = 1
		printerr("[i18n_build] cannot open translations.csv")
		return
	var header := csv.get_csv_line()
	if header.size() < 2 or header[0] != "keys":
		_fail = 1
		printerr("[i18n_build] invalid header")
		return
	var translations: Array[Translation] = []
	for i in range(1, header.size()):
		var translation := Translation.new()
		translation.locale = header[i]
		translations.append(translation)
	while csv.get_position() < csv.get_length():
		var row := csv.get_csv_line()
		if row.is_empty() or row[0] == "":
			continue
		for i in range(translations.size()):
			if i + 1 < row.size():
				translations[i].add_message(row[0], row[i + 1])
	csv.close()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://bench/results"))
	for i in range(translations.size()):
		var locale := String(header[i + 1])
		var path := "res://bench/results/translations.%s.translation" % locale
		var err := ResourceSaver.save(translations[i], path)
		if err != OK:
			_fail += 1
			printerr("[i18n_build] save failed locale=%s err=%d" % [locale, err])
		else:
			print("[i18n_build] wrote %s (%d messages)" % [path,
				translations[i].get_message_count()])
