extends Node2D

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	var failures: int = await preload("res://scripts/tests/orion_lifecycle_case.gd").new().run(self)
	get_tree().quit(0 if failures == 0 else 1)
