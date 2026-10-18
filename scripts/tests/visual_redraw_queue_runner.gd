extends Node2D

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	var failures := await preload("res://scripts/tests/visual_redraw_queue_case.gd").run(self)
	get_tree().quit(0 if failures==0 else 1)
