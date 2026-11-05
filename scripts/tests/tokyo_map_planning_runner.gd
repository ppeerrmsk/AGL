extends Node

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	var failures := await preload("res://scripts/tests/tokyo_map_planning_case.gd").run(self)
	AudioManager.request_quit(0 if failures==0 else 1)
