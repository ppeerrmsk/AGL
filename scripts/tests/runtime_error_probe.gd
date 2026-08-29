extends Node

## 只用于验证外层 wrapper：Godot 故意以 0 退出，但 runtime-error gate 必须改判为 86。
func _ready() -> void:
	push_error("[BenchRuntimeErrorProbe] intentional runtime diagnostic")
	# 带类型边界会中断当前方法；先延迟退出，证明 Godot 仍可正常返回 0。
	get_tree().quit.call_deferred(0)
	var probe_node := Node.new()
	var stale_value: Variant = probe_node
	probe_node.free()
	_accept_typed_node(stale_value)


func _accept_typed_node(_value: Node) -> void:
	pass
