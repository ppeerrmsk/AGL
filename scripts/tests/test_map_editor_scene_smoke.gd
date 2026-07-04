extends SceneTree

## 地图编辑器场景冒烟（无头）：
##   godot --headless --path . --script res://scripts/tests/test_map_editor_scene_smoke.gd
## 验证：① map_editor.tscn 可实例化、_ready UI 构建链不炸（跑 5 帧）
##       ② 程序化涂一笔 → 烘焙出多边形 → 保存/读回
## 交互手感（鼠标涂格/缩放/对话框）无法无头覆盖 —— 归 F5 手测清单。

var _frames := 0
var _editor: Node = null

func _initialize() -> void:
	var scene := load("res://scenes/map_editor.tscn") as PackedScene
	if scene == null:
		print("FAIL: map_editor.tscn 加载失败")
		quit(1)
		return
	_editor = scene.instantiate()
	root.add_child(_editor)

func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < 5:
		return false
	var fails: Array[String] = []
	var doc = _editor.get("doc")
	if doc == null:
		fails.append("场景 doc 未初始化")
	else:
		# 程序化涂一块 → 烘焙 → 校验
		doc.push_undo("land")
		for cy in range(70, 80):
			for cx in range(70, 80):
				doc.editor_cells["land"][cy * MapDocument.GRID_W + cx] = 1
		doc.mark_dirty_and_rebake("land")
		if (doc.layer_polygons["land"] as Array).is_empty():
			fails.append("涂格后未烘焙出多边形")
		if not doc.layer_dirty["land"]:
			fails.append("layer_dirty 未置位")
		var path := "user://test_editor_smoke.json"
		if not doc.save_to(path):
			fails.append("保存失败")
		elif MapDocument.load_from(path) == null:
			fails.append("读回失败")
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	if fails.is_empty():
		print("PASS: 编辑器场景冒烟通过（实例化5帧/涂格烘焙/存读）")
		quit(0)
	else:
		for m in fails:
			print("FAIL: " + m)
		quit(1)
	return true
