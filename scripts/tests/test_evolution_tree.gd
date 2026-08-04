extends SceneTree

## 进化树数据完整性冒烟测试（旧 SceneTree 独立脚本，尚未接入 BenchRunner）。
## Agent 不得绕过 bench wrapper 直接启动 Godot；日常回归改跑 evo_detail + attr_gates。
## 验证：① 树 JSON 可解析 ② 所有节点 profile 在 AircraftDB 可加载（base_params 非空）
##       ③ exits 无悬空引用 ④ 非终点节点出口 ≥3（ACE 手动三选铁律）⑤ name_key 有翻译行

func _initialize() -> void:
	var fails: Array[String] = []
	var nodes: Dictionary = {}
	# ① 解析
	var f := FileAccess.open("res://resources/evolution/evolution_tree.json", FileAccess.READ)
	if f == null:
		print("FAIL: 树文件缺失"); quit(1); return
	var data = JSON.parse_string(f.get_as_text())
	if not (data is Dictionary):
		print("FAIL: JSON 解析失败"); quit(1); return
	for nd in data.get("nodes", []):
		nodes[StringName(nd["id"])] = nd
	print("节点数: %d" % nodes.size())
	# ②③④
	for nid in nodes:
		var nd: Dictionary = nodes[nid]
		var prof := AircraftDB.get_profile(StringName(nd.get("profile", "")))
		if prof == null:
			fails.append("%s: profile '%s' 加载失败" % [nid, nd.get("profile")])
		elif prof.base_params == null:
			fails.append("%s: base_params 为空" % nid)
		var exits: Array = nd.get("exits", [])
		for eid in exits:
			if not nodes.has(StringName(eid)):
				fails.append("%s: 悬空出口 '%s'" % [nid, eid])
		# T5 终端档豁免 ≥3（x02→ax00 / x44→x90 单出口特殊边，tree spec §4 v2）
		if not exits.is_empty() and exits.size() < 3 and int(nd.get("tier", 1)) < 5:
			fails.append("%s: 出口仅 %d 个（ACE 三选铁律要求 ≥3）" % [nid, exits.size()])
	# ⑤ name_key 粗验（翻译 CSV 里有这一行）
	var csv := FileAccess.open("res://i18n/translations.csv", FileAccess.READ)
	var csv_text := csv.get_as_text() if csv else ""
	for nid in nodes:
		var key: String = nodes[nid].get("name_key", "")
		if key != "" and not csv_text.contains(key + ","):
			fails.append("%s: name_key '%s' 不在 translations.csv" % [nid, key])
	# 汇总
	if fails.is_empty():
		print("PASS: 树完整性 %d 节点全通过（profile 加载/出口引用/≥3 选/i18n）" % nodes.size())
		quit(0)
	else:
		for m in fails:
			print("FAIL: " + m)
		quit(1)
