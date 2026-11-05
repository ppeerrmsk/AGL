extends Node

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	var test := preload("res://scripts/tests/fear_cone_case.gd").new()
	var failures: int = await test.run(self, DisplayServer.get_name() != "headless")
	AudioManager.request_quit(0 if failures == 0 else 1)
