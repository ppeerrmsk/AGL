extends Node

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("_run")

func _run() -> void:
	var failures: int = await preload("res://scripts/tests/dock_decision_case.gd").new().run(self)
	AudioManager.request_quit(1 if failures else 0)
