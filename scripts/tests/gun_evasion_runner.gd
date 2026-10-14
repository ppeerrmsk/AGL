extends Node2D

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	var test: RefCounted = load("res://scripts/tests/gun_evasion_lifecycle_case.gd").new()
	var failures: int = await test.run(self, DisplayServer.get_name() != "headless")
	get_tree().quit(0 if failures == 0 else 1)
