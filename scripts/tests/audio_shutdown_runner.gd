extends Node

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	var failures: int = await preload("res://scripts/tests/audio_shutdown_case.gd").run(self)
	if failures:
		AudioManager.request_quit(1)
		return
	if String(get_tree().get_meta("bench_scenario", "")) == "audio_shutdown_failure":
		AudioManager.request_quit(7)
		AudioManager.request_quit(0)
	# 正式窗口关闭信号与程序退出共用同一条清理路径。
	get_tree().root.close_requested.emit()
	if not AudioManager._quit_requested:
		AudioManager.request_quit(1)
