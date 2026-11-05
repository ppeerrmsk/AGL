extends Node2D

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	var failures: int = await preload("res://scripts/tests/tactical_canvas_case.gd").run(self)
	AudioManager.request_quit(1 if failures else 0)
