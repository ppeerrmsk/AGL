extends RefCounted
## F5 坐标轴既可能尚未入树，也可能是面板的世界兄弟；两种均须跟随所有者释放。

static func run(parent: Node) -> int:
	var failures := 0
	for mode in ["unopened", "opened", "panel_only"]:
		var world := Node2D.new()
		parent.add_child(world)
		var panel := SurvivorDebugSpawn.new()
		panel.game_scene = world
		world.add_child(panel)
		var axes_ref: WeakRef = weakref(panel._coord_axes)
		if mode != "unopened":
			panel.visible = true
			if panel._coord_axes.get_parent() != world:
				failures += 1
				push_error("Debug axes not attached by real visibility signal")
		if mode == "panel_only":
			panel.queue_free()
		else:
			world.queue_free()
		await parent.get_tree().process_frame
		await parent.get_tree().process_frame
		if axes_ref.get_ref() != null:
			failures += 1
			push_error("Debug axes survived owner: " + mode)
			# 失败时只回收本测试持有的节点，不掩盖其他 orphan。
			axes_ref.get_ref().free()
		if is_instance_valid(world):
			world.queue_free()
		await parent.get_tree().process_frame
	print("[DebugSpawnLifecycle] cases=3 fail=", failures)
	return failures
