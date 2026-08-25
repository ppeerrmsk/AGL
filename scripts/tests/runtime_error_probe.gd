extends Node

## 只用于验证外层 wrapper：Godot 故意以 0 退出，但 runtime-error gate 必须改判为 86。
func _ready() -> void:
	push_error("[BenchRuntimeErrorProbe] intentional runtime diagnostic")
	get_tree().quit(0)
