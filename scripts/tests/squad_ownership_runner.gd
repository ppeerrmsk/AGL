extends Node

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	var failures: int = await preload("res://scripts/tests/squad_ownership_case.gd").run(self)
	AudioManager.request_quit(1 if failures else 0)
