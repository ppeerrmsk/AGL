extends Node

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	var failures: int = await preload("res://scripts/tests/weather_volume_lifecycle_case.gd").new().run(self)
	get_tree().quit(1 if failures > 0 else 0)
