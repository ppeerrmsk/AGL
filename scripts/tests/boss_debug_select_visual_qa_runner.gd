extends Node

## 仅供 bench Visual：加载真实 Boss Debug 选择场景，固定采集四卡与 Hyper-A 场景下拉框。

const BOSS_DEBUG_SCENE := preload("res://scenes/boss_debug_select.tscn")


func _ready() -> void:
	DisplayServer.window_set_size(Vector2i(1920, 1080))
	TranslationServer.set_locale("en")
	var screen := BOSS_DEBUG_SCENE.instantiate()
	add_child(screen)
	for _frame in range(4):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var path := "res://bench/results/boss_debug_select_black_star.png"
	var err := get_viewport().get_texture().get_image().save_png(path)
	print("[boss_debug_select_visual] path=%s err=%d" % [path, err])
	get_tree().quit(0 if err == OK else 1)
