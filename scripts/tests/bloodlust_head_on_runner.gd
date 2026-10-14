extends Node2D

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	var test: RefCounted = load("res://scripts/tests/bloodlust_head_on_case.gd").new()
	var failures: int = await test.run(self)
	get_tree().quit(0 if failures == 0 else 1)
