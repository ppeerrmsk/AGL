extends Node2D


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var failures: int = await preload("res://scripts/tests/unit_status_case.gd").new().run(self)
	AudioManager.request_quit(1 if failures else 0)
