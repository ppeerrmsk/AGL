extends Node
## 仅持有已校验的纯值地图表；不接管 Node、Mesh、纹理或渲染资源。
## 旧所有者真正销毁后才在后台释放最后引用，不修改仍被读取的共享容器。
var _owner: WeakRef
var _values: Array=[]
var _task := -1

static func attach(owner_node: Node) -> Node:
	if not owner_node.is_inside_tree(): return null
	var sink: Node=load("res://scripts/rendering/tokyo_metadata_retirement.gd").new()
	sink._owner=weakref(owner_node)
	sink.process_mode=Node.PROCESS_MODE_ALWAYS
	owner_node.get_tree().root.add_child(sink)
	# Godot 入树会自动开启脚本的 _process；必须在入树后关闭空闲轮询。
	sink.set_process(false)
	sink.add_to_group("tokyo_metadata_retirement")
	owner_node.tree_exiting.connect(sink.set_process.bind(true),CONNECT_ONE_SHOT)
	return sink

func hold(values: Array) -> void:
	_values.append_array(values)

static func pending(tree: SceneTree) -> bool:
	for sink: Node in tree.get_nodes_in_group("tokyo_metadata_retirement"):
		if sink.is_processing(): return true
	return false

func _process(_delta: float) -> void:
	if _task>=0:
		if not WorkerThreadPool.is_task_completed(_task): return
		WorkerThreadPool.wait_for_task_completion(_task)
		_task=-1
		queue_free()
		set_process(false)
	elif _owner.get_ref()==null:
		if _values.is_empty():
			queue_free()
			set_process(false)
		else:
			_task=WorkerThreadPool.add_task(_release.bind(_values),false,"Tokyo metadata release")
			_values=[]

static func _release(values: Array) -> void:
	# 清空唯一交接数组，让最后引用的递归销毁发生在这个线程。
	values.clear()

func _exit_tree() -> void:
	# 应用退出没有下一帧；必须领取后台任务，不能遗留持有者。
	if _task>=0:
		WorkerThreadPool.wait_for_task_completion(_task)
		_task=-1
	_values.clear()
