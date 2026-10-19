extends Node


func _ready() -> void:
	var test: RefCounted = preload("res://scripts/tests/desert_preload_lifecycle_case.gd").new()
	var failures: int = await test.run(self)
	get_tree().quit(1 if failures > 0 else 0)
