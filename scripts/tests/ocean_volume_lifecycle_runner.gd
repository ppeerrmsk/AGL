extends Node


func _ready() -> void:
	var failures: int = await preload("res://scripts/tests/ocean_volume_lifecycle_case.gd").new().run(self)
	get_tree().quit(1 if failures else 0)
