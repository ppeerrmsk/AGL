extends Node


func _ready() -> void:
	var test: RefCounted = load("res://scripts/tests/tokyo_volume_lifecycle_case.gd").new()
	var failures: int = await test.run(self)
	get_tree().quit(1 if failures else 0)
